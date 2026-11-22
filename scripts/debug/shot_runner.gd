extends SceneTree
## Отладочный прогон: запускает уровень, берёт нож в первом лице и сохраняет кадры.
## Запуск: Godot.exe --path <проект> --script res://scripts/debug/shot_runner.gd -- <папка_для_png> [tp]
## Кадры: idle, затем серия во время комбо и после него, затем бег.

var _t: float = 0.0
var _out: String = "."
var _level: Node
var _player: Node
var _wc: Node
var _third: bool = false
var _shots: Array = []   # [время, имя]
var _events: Array = []  # [время, имя события]
var _done: Array = []
var _freeze: int = -1


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_out = args[0]
	_third = args.size() > 1 and args[1] == "tp"
	DirAccess.make_dir_recursive_absolute(_out)
	_level = (load("res://scenes/levels/level.tscn") as PackedScene).instantiate()
	root.add_child(_level)
	_player = _level.get_node("Player")
	# расписание
	_events = [[0.5, "equip"], [1.5, "attack1"], [1.5 + 0.37, "attack2"], [1.5 + 0.74, "attack3"], [4.0, "run_on"], [5.5, "run_off"]]
	if args.size() > 2 and args[2] == "series":
		_shots = []
		for i in range(24):
			_shots.append([2.5 + 0.05 * i, "t_%02d" % i])
	else:
		_shots = [[1.2, "01_idle"], [1.65, "02_a1_mid"], [1.95, "03_a1_end"], [2.25, "04_a2_mid"], [2.5, "05_a2_end"],
			[2.75, "06_a3_wind"], [3.0, "07_a3_hit"], [3.2, "08_after_0.1"], [3.35, "09_after_0.25"], [3.6, "10_after_0.5"], [3.9, "11_idle2"], [5.2, "12_run"]]


func _process(delta: float) -> bool:
	_t += delta
	if _freeze >= 0:
		_freeze += 1
		var arms := _player.get_node("FpArms")
		var meshes: Array = arms.find_children("*", "MeshInstance3D", true, false)
		match _freeze:
			3: root.get_texture().get_image().save_png("%s/f_normal.png" % _out)
			5:
				for m in meshes:
					if m.name == "Arms_Mesh": m.visible = false
			8: root.get_texture().get_image().save_png("%s/f_no_arms.png" % _out)
			10:
				for m in meshes:
					m.visible = true
					if m.name.begins_with("Knife"): m.visible = false
			13: root.get_texture().get_image().save_png("%s/f_no_knife.png" % _out)
			15: quit()
		return false
	for e: Array in _events:
		if _t >= float(e[0]) and not _done.has(e[1]):
			_done.append(e[1])
			_run_event(String(e[1]))
	for s: Array in _shots:
		if _t >= float(s[0]) and not _done.has(s[1]):
			_done.append(s[1])
			var img := root.get_texture().get_image()
			img.save_png("%s/%s.png" % [_out, s[1]])
	if _t > 6.2:
		quit()
	return false


func _run_event(name: String) -> void:
	_wc = _player.get_node("WeaponController")
	match name:
		"equip":
			_player.call("_set_view", not _third, true)
			var knife := load("res://resources/items/knife.tres") as Resource
			var inv: Object = _wc.get("_inventory")
			inv.call("dev_equip", &"melee", knife)
			_wc.call("equip", knife)
		"freeze":
			Engine.time_scale = 0.0
			_freeze = 0
		"debug2", "debug2b":
			var arms2 := _player.get_node("FpArms")
			var sk2: Skeleton3D = arms2.get("_skeleton")
			print("T=", _t, " step=", _wc.get("_atk_step"), " left_hide=", arms2.get("_left_hide"),
				" sc5=", sk2.get_bone_pose_scale(5), " sc6=", sk2.get_bone_pose_scale(6),
				" UA.L global origin=", sk2.get_bone_global_pose(6).origin, " Hand.L=", sk2.get_bone_global_pose(8).origin,
				" Hand.R=", sk2.get_bone_global_pose(sk2.find_bone("Hand.R")).origin)
		"debug":
			var arms := _player.get_node("FpArms")
			print("FPARMS ready=", arms.call("is_ready_ok"), " left_bones=", arms.get("_left_bones"), " attach=", arms.get("_hand_attach"))
			var att = arms.get("_hand_attach")
			if att != null:
				print("ATTACH children=", att.get_children(), " bone=", att.bone_name)
			var holder: Node3D = _wc.call("get_holder")
			print("HOLDER children=", holder.get_children())
			var sk: Skeleton3D = arms.get("_skeleton")
			if sk != null:
				var names := []
				for i in sk.get_bone_count():
					names.append(sk.get_bone_name(i))
				print("BONES ", names.slice(0, 20))
			print("MESHES ", arms.find_children("*", "MeshInstance3D", true, false))
		"attack1", "attack2", "attack3":
			_wc.set("_cooldown", 0.0)
			_wc.call("_melee_attack")
		"run_on":
			Input.action_press("move_forward")
			Input.action_press("sprint")
		"run_off":
			Input.action_release("move_forward")
			Input.action_release("sprint")
