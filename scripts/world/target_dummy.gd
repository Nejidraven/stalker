extends StaticBody3D
## Мишень для проверки оружия. Принимает попадания (apply_hit), показывает урон,
## падает, когда здоровье кончилось, и через несколько секунд встаёт снова.
## Попадание в «яблочко» (центр) наносит двойной урон.

const MODEL_PATH := "res://assets/target.glb"
const HIT_SOUND := "res://assets/audio/bullet_hit.wav"

@export var max_health: float = 100.0
@export var respawn_time: float = 3.0
## Высота центра мишени над землёй, м
@export var board_height: float = 1.25
@export var bullseye_radius: float = 0.09

var health: float
var _fallen: bool = false
var _hits: int = 0
var _label: Label3D
var _hit_sound: AudioStreamPlayer3D
var _tilt_tween: Tween

@onready var _pivot: Node3D = $Pivot
@onready var _shape: CollisionShape3D = $CollisionShape3D


func _ready() -> void:
	health = max_health
	_build_model()
	_build_label()
	_hit_sound = AudioStreamPlayer3D.new()
	_hit_sound.stream = Fx.load_stream(HIT_SOUND, false)
	_hit_sound.volume_db = -10.0
	_hit_sound.unit_size = 8.0
	add_child(_hit_sound)
	_snap_to_ground()


## Опускает мишень на землю: рельеф за пределами ровной площадки неровный.
func _snap_to_ground() -> void:
	await get_tree().physics_frame
	await get_tree().physics_frame   # к этому моменту у ландшафта уже есть коллизия
	var query := PhysicsRayQueryParameters3D.create(
		global_position + Vector3.UP * 40.0, global_position + Vector3.DOWN * 40.0, 1
	)
	query.exclude = [get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if not hit.is_empty():
		global_position.y = (hit["position"] as Vector3).y


## Вызывается оружием. Возвращает true, если мишень сбита этим выстрелом.
func apply_hit(damage: float, point: Vector3, _normal: Vector3) -> bool:
	if _fallen:
		return false
	var local := to_local(point)
	var radius := Vector2(local.x, local.y - board_height).length()
	var bullseye := radius <= bullseye_radius
	var dealt := damage * (2.0 if bullseye else 1.0)

	health = maxf(health - dealt, 0.0)
	_hits += 1
	_update_label()
	_show_damage(point, dealt, bullseye)
	if _hit_sound.stream != null:
		_hit_sound.play()

	if health <= 0.0:
		_fall()
		return true
	_wobble()
	return false


func _fall() -> void:
	_fallen = true
	_shape.set_deferred("disabled", true)   # лежащая мишень пули не ловит
	_kill_tween()
	_tilt_tween = create_tween()
	_tilt_tween.tween_property(_pivot, "rotation:x", deg_to_rad(-85.0), 0.35).set_trans(Tween.TRANS_QUAD)
	_tilt_tween.tween_interval(respawn_time)
	_tilt_tween.tween_callback(_stand_up)


func _stand_up() -> void:
	_tilt_tween = create_tween()
	_tilt_tween.tween_property(_pivot, "rotation:x", 0.0, 0.4).set_trans(Tween.TRANS_BACK)
	_tilt_tween.tween_callback(_reset)


func _reset() -> void:
	health = max_health
	_hits = 0
	_fallen = false
	_shape.set_deferred("disabled", false)
	_update_label()


func _wobble() -> void:
	_kill_tween()
	_tilt_tween = create_tween()
	_tilt_tween.tween_property(_pivot, "rotation:x", deg_to_rad(-6.0), 0.05)
	_tilt_tween.tween_property(_pivot, "rotation:x", 0.0, 0.2).set_trans(Tween.TRANS_ELASTIC)


func _kill_tween() -> void:
	if _tilt_tween != null and _tilt_tween.is_valid():
		_tilt_tween.kill()


func _show_damage(point: Vector3, amount: float, bullseye: bool) -> void:
	var label := Label3D.new()
	label.text = ("ЯБЛОЧКО! -%d" if bullseye else "-%d") % roundi(amount)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.font_size = 48 if bullseye else 36
	label.pixel_size = 0.004
	label.modulate = Color(1.0, 0.85, 0.2) if bullseye else Color(1.0, 1.0, 1.0)
	label.outline_size = 10
	get_tree().current_scene.add_child(label)
	label.global_position = point + Vector3(0.0, 0.15, 0.0)
	var tween := label.create_tween()
	tween.set_parallel(true)
	tween.tween_property(label, "global_position:y", point.y + 0.9, 0.8)
	tween.tween_property(label, "modulate:a", 0.0, 0.8).set_delay(0.3)
	tween.chain().tween_callback(label.queue_free)


func _build_model() -> void:
	var model: Node3D = null
	if ResourceLoader.exists(MODEL_PATH):
		var scene := load(MODEL_PATH) as PackedScene
		if scene != null:
			model = scene.instantiate() as Node3D
	if model == null:
		# Запасной вариант без модели: красный диск
		var disc := MeshInstance3D.new()
		var mesh := CylinderMesh.new()
		mesh.top_radius = 0.5
		mesh.bottom_radius = 0.5
		mesh.height = 0.05
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.75, 0.12, 0.1)
		mesh.material = mat
		disc.mesh = mesh
		disc.rotation.x = deg_to_rad(90.0)
		disc.position = Vector3(0.0, board_height, 0.0)
		model = disc
	_pivot.add_child(model)


func _build_label() -> void:
	_label = Label3D.new()
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.font_size = 28
	_label.pixel_size = 0.004
	_label.outline_size = 8
	_label.position = Vector3(0.0, board_height + 0.75, 0.0)
	add_child(_label)
	_update_label()


func _update_label() -> void:
	_label.text = "МИШЕНЬ  %d / %d" % [roundi(health), roundi(max_health)]
	if _hits > 0 and not _fallen:
		_label.text += "\nпопаданий: %d" % _hits
