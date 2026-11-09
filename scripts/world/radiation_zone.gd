extends Area3D
## Зона радиации. Пока игрок внутри, он накапливает лучевую болезнь;
## к центру зоны излучение сильнее. Сама болезнь и её действие на здоровье живут в player.gd.

const SIGN_PATH := "res://assets/radiation_sign.glb"

@export var radius: float = 14.0
## Скорость накопления лучевой болезни в центре, ед/сек
@export var max_rate: float = 2.0
## То же на краю зоны
@export var min_rate: float = 0.4
## Сколько знаков радиации поставить по периметру
@export var sign_count: int = 8

var _player: Node3D = null


func _ready() -> void:
	collision_layer = 0
	collision_mask = 1
	monitoring = true
	monitorable = false
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	_build_collision()
	_build_mist()
	Fx.spawn_ring_signs(self, SIGN_PATH, sign_count, radius)


func _physics_process(_delta: float) -> void:
	if not is_instance_valid(_player):
		return
	var offset := _player.global_position - global_position
	var t := clampf(Vector2(offset.x, offset.z).length() / radius, 0.0, 1.0)
	_player.call("set_radiation_exposure", get_instance_id(), lerpf(max_rate, min_rate, t))


func _on_body_entered(body: Node3D) -> void:
	if body.is_in_group("player"):
		_player = body


func _on_body_exited(body: Node3D) -> void:
	if body == _player:
		_player.call("set_radiation_exposure", get_instance_id(), 0.0)
		_player = null


## Форма лежит в сцене (чтобы редактор не ругался), здесь только подгоняем радиус.
func _build_collision() -> void:
	var shape := get_node_or_null("CollisionShape3D") as CollisionShape3D
	if shape == null:
		shape = CollisionShape3D.new()
		add_child(shape)
	var sphere := SphereShape3D.new()
	sphere.radius = radius
	shape.shape = sphere


## Лёгкая зеленоватая дымка над зоной, чтобы её было видно издалека.
func _build_mist() -> void:
	var color := Color(0.45, 0.9, 0.35)
	var particles := GPUParticles3D.new()
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(radius * 0.9, 0.6, radius * 0.9)
	pm.direction = Vector3.UP
	pm.spread = 90.0
	pm.initial_velocity_min = 0.1
	pm.initial_velocity_max = 0.4
	pm.gravity = Vector3.ZERO
	pm.scale_min = 0.8
	pm.scale_max = 1.6
	pm.color_ramp = Fx.fade_ramp(color, 0.12)

	var quad := QuadMesh.new()
	quad.size = Vector2(6.0, 6.0)
	quad.material = Fx.particle_material(color)

	particles.amount = 60
	particles.lifetime = 8.0
	particles.preprocess = 8.0   # дымка есть сразу, не нарастает после старта
	particles.process_material = pm
	particles.draw_pass_1 = quad
	particles.visibility_aabb = AABB(
		Vector3(-radius - 4.0, -2.0, -radius - 4.0),
		Vector3(radius * 2.0 + 8.0, 8.0, radius * 2.0 + 8.0)
	)
	add_child(particles)
	particles.emitting = true
