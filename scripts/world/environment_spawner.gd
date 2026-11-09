extends Node3D
## Расставляет руины и деревья по ландшафту (этап 2.1).
## Берёт модели из Blender (res://assets/*.glb). Если какого-то файла нет,
## вместо него строятся временные примитивы, так что сцена работает в любом случае.

@export var terrain_path: NodePath
@export var rng_seed: int = 42
@export var building_count: int = 8
@export var tree_count: int = 140
@export var min_radius: float = 30.0
@export var max_radius: float = 85.0
@export var spawn_clear_radius: float = 8.0

const FLOOR_HEIGHT := 3.2
const WALL_THICKNESS := 0.4

## footprint: размеры основной коробки здания без обломков (нужны для посадки на склон)
const RUIN_MODELS: Array[Dictionary] = [
	{"path": "res://assets/ruin_a.glb", "footprint": Vector2(12.0, 9.0)},
	{"path": "res://assets/ruin_b.glb", "footprint": Vector2(9.0, 7.0)},
]
const RUBBLE_PATH := "res://assets/rubble_pile.glb"
const TREE_PATHS: Array[String] = [
	"res://assets/pine.glb",
	"res://assets/dead_tree.glb",
]

var _rng := RandomNumberGenerator.new()
var _terrain
var _ruin_scenes: Array[Dictionary] = []
var _tree_scenes: Array[PackedScene] = []
var _rubble_scene: PackedScene
var _building_centers: Array[Vector2] = []

# материалы для запасных примитивов
var _concrete: StandardMaterial3D
var _rubble: StandardMaterial3D
var _bark: StandardMaterial3D
var _leaves: StandardMaterial3D


func _ready() -> void:
	_terrain = get_node(terrain_path)
	_rng.seed = rng_seed
	_concrete = _make_material(Color(0.45, 0.45, 0.43))
	_rubble = _make_material(Color(0.36, 0.34, 0.32))
	_bark = _make_material(Color(0.22, 0.17, 0.12))
	_leaves = _make_material(Color(0.20, 0.27, 0.15))
	_load_models()
	_spawn_buildings()
	_spawn_trees()


func _load_models() -> void:
	for m in RUIN_MODELS:
		var scene := _load_scene(m["path"])
		if scene != null:
			_ruin_scenes.append({"scene": scene, "footprint": m["footprint"]})
	for p in TREE_PATHS:
		var tree_scene := _load_scene(p)
		if tree_scene != null:
			_tree_scenes.append(tree_scene)
	_rubble_scene = _load_scene(RUBBLE_PATH)


func _load_scene(path: String) -> PackedScene:
	if ResourceLoader.exists(path):
		return load(path) as PackedScene
	return null


func _make_material(color: Color, rough: float = 0.95) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = rough
	return m


func _random_point(r_min: float, r_max: float) -> Vector2:
	var angle := _rng.randf() * TAU
	var r := _rng.randf_range(r_min, r_max)
	return Vector2(cos(angle), sin(angle)) * r


func _is_far_enough(pos: Vector2, min_dist: float) -> bool:
	for c in _building_centers:
		if pos.distance_to(c) < min_dist:
			return false
	return true


## Низшая точка земли под прямоугольником w x d, повёрнутым по xf.
func _min_ground_height(xf: Transform3D, w: float, d: float) -> float:
	var base_y := INF
	for sx in [-0.5, 0.5]:
		for sz in [-0.5, 0.5]:
			var corner: Vector3 = xf * Vector3(sx * w, 0.0, sz * d)
			base_y = minf(base_y, _terrain.get_height(corner.x, corner.z))
	return base_y


# --- Руины ---------------------------------------------------------------

func _spawn_buildings() -> void:
	var attempts := 0
	while _building_centers.size() < building_count and attempts < 300:
		attempts += 1
		var pos := _random_point(min_radius, max_radius)
		if not _is_far_enough(pos, 24.0):
			continue
		_building_centers.append(pos)
		_build_ruin(pos)


func _build_ruin(pos: Vector2) -> void:
	if _ruin_scenes.is_empty():
		_build_primitive_ruin(pos)
		return

	var entry: Dictionary = _ruin_scenes[_rng.randi() % _ruin_scenes.size()]
	var footprint: Vector2 = entry["footprint"]
	var yaw := _rng.randf() * TAU
	var xf := Transform3D(Basis(Vector3.UP, yaw), Vector3(pos.x, 0.0, pos.y))
	var base_y := _min_ground_height(xf, footprint.x, footprint.y)

	var ruin: Node3D = (entry["scene"] as PackedScene).instantiate()
	add_child(ruin)
	ruin.position = Vector3(pos.x, base_y, pos.y)
	ruin.rotation.y = yaw
	_scatter_rubble(pos, maxf(footprint.x, footprint.y))


func _scatter_rubble(center: Vector2, building_size: float) -> void:
	if _rubble_scene == null:
		return
	for _i in range(_rng.randi_range(2, 3)):
		var angle := _rng.randf() * TAU
		var r := building_size * 0.5 + _rng.randf_range(4.0, 9.0)
		var p := center + Vector2(cos(angle), sin(angle)) * r
		var pile: Node3D = _rubble_scene.instantiate()
		add_child(pile)
		pile.position = Vector3(p.x, _terrain.get_height(p.x, p.y) - 0.1, p.y)
		pile.rotation.y = _rng.randf() * TAU


# Запасной вариант, если модели руин не найдены
func _build_primitive_ruin(pos: Vector2) -> void:
	var w := _rng.randf_range(8.0, 14.0)
	var d := _rng.randf_range(8.0, 12.0)
	var floors := _rng.randi_range(1, 4)
	var full_h := floors * FLOOR_HEIGHT
	var yaw := _rng.randf() * TAU
	var xf := Transform3D(Basis(Vector3.UP, yaw), Vector3(pos.x, 0.0, pos.y))
	var base_y := _min_ground_height(xf, w, d)

	var root := Node3D.new()
	root.name = "Ruin"
	add_child(root)
	root.position = Vector3(pos.x, base_y, pos.y)
	root.rotation.y = yaw

	var hw := w * 0.5
	var hd := d * 0.5

	_add_box(root, Vector3(w, 0.4, d), Vector3(0.0, 0.0, 0.0), _concrete)
	_add_wall_run(root, Vector3(-hw, 0.0, hd), true, w, full_h, true)
	_add_wall_run(root, Vector3(-hw, 0.0, -hd), true, w, full_h, false)
	_add_wall_run(root, Vector3(-hw, 0.0, -hd), false, d, full_h, false)
	_add_wall_run(root, Vector3(hw, 0.0, -hd), false, d, full_h, false)

	for _i in range(_rng.randi_range(5, 9)):
		var size := Vector3(
			_rng.randf_range(0.4, 1.4),
			_rng.randf_range(0.3, 0.9),
			_rng.randf_range(0.4, 1.4)
		)
		var rx := _rng.randf_range(-hw - 3.0, hw + 3.0)
		var rz := _rng.randf_range(-hd - 3.0, hd + 3.0)
		var wp: Vector3 = xf * Vector3(rx, 0.0, rz)
		var gy: float = _terrain.get_height(wp.x, wp.z) - base_y
		_add_box(root, size, Vector3(rx, gy + size.y * 0.3, rz), _rubble, _rng.randf() * TAU)


func _add_wall_run(parent: Node3D, start: Vector3, along_x: bool, length: float, full_h: float, with_door: bool) -> void:
	var count := maxi(1, ceili(length / 2.5))
	var seg := length / count
	for i in range(count):
		var offset := seg * (i + 0.5)
		if with_door and absf(offset - length * 0.5) < 1.2:
			continue
		var top := full_h * _rng.randf_range(0.35, 1.0)
		var height := top + 1.0  # стена уходит на 1 м под пол, чтобы не висеть над склоном
		var center := start
		var size: Vector3
		if along_x:
			center.x += offset
			size = Vector3(seg, height, WALL_THICKNESS)
		else:
			center.z += offset
			size = Vector3(WALL_THICKNESS, height, seg)
		_add_box(parent, size, Vector3(center.x, -1.0 + height * 0.5, center.z), _concrete)


func _add_box(parent: Node3D, size: Vector3, pos: Vector3, mat: Material, yaw: float = 0.0) -> void:
	var body := StaticBody3D.new()
	parent.add_child(body)
	body.position = pos
	body.rotation.y = yaw

	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)

	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	body.add_child(mi)


# --- Деревья -------------------------------------------------------------

func _spawn_trees() -> void:
	var placed := 0
	var attempts := 0
	while placed < tree_count and attempts < tree_count * 10:
		attempts += 1
		var pos := _random_point(spawn_clear_radius, 95.0)
		if not _is_far_enough(pos, 9.0):
			continue
		_build_tree(pos)
		placed += 1


func _build_tree(pos: Vector2) -> void:
	if _tree_scenes.is_empty():
		_build_primitive_tree(pos)
		return
	var tree: Node3D = _tree_scenes[_rng.randi() % _tree_scenes.size()].instantiate()
	add_child(tree)
	tree.position = Vector3(pos.x, _terrain.get_height(pos.x, pos.y), pos.y)
	tree.rotation.y = _rng.randf() * TAU


# Запасной вариант, если модели деревьев не найдены
func _build_primitive_tree(pos: Vector2) -> void:
	var h := _rng.randf_range(4.0, 7.5)
	var dead := _rng.randf() < 0.45

	var tree := Node3D.new()
	tree.name = "Tree"
	add_child(tree)
	tree.position = Vector3(pos.x, _terrain.get_height(pos.x, pos.y), pos.y)

	var body := StaticBody3D.new()
	tree.add_child(body)
	body.position = Vector3(0.0, h * 0.5 - 0.3, 0.0)

	var col := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = 0.22
	cyl.height = h
	col.shape = cyl
	body.add_child(col)

	var trunk := MeshInstance3D.new()
	var tm := CylinderMesh.new()
	tm.bottom_radius = 0.22
	tm.top_radius = 0.12
	tm.height = h
	trunk.mesh = tm
	trunk.material_override = _bark
	body.add_child(trunk)

	if dead:
		for i in range(3):
			var branch := MeshInstance3D.new()
			var bm := CylinderMesh.new()
			bm.top_radius = 0.03
			bm.bottom_radius = 0.07
			bm.height = 1.8
			branch.mesh = bm
			branch.material_override = _bark
			tree.add_child(branch)
			branch.position = Vector3(0.0, h * (0.6 + 0.12 * i), 0.0)
			branch.rotation = Vector3(0.0, i * 2.1, deg_to_rad(55.0))
			var dir: Vector3 = branch.basis * Vector3.UP
			branch.position += dir * 0.8
	else:
		var crown := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.0
		cm.bottom_radius = _rng.randf_range(1.2, 1.8)
		cm.height = h * 0.8
		crown.mesh = cm
		crown.material_override = _leaves
		tree.add_child(crown)
		crown.position = Vector3(0.0, h * 0.85, 0.0)
