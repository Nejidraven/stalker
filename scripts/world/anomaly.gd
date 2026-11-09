extends Area3D
## Аномалия: зона, которая периодически бьёт игрока, пока он внутри.
## Свет, частицы, звук и знаки строятся кодом, поэтому вид, радиус и урон
## настраиваются прямо в инспекторе у каждого экземпляра.

enum Kind { ELECTRA, FIRE }

const SIGN_PATH := "res://assets/anomaly_sign.glb"
const ZAP_PATH := "res://assets/audio/anomaly_zap.wav"
const ELECTRA_LOOP := "res://assets/audio/anomaly_electra_loop.wav"
const FIRE_LOOP := "res://assets/audio/anomaly_fire_loop.wav"

@export var kind: Kind = Kind.ELECTRA
@export var radius: float = 2.5
## Урон за один удар
@export var damage: float = 8.0
## Пауза между ударами, сек
@export var tick_interval: float = 0.4
## Сколько предупреждающих знаков поставить вокруг
@export var sign_count: int = 2

var _victims: Array[Node3D] = []
var _tick_timer: float = 0.0
var _flash: float = 0.0
var _color: Color = Color.WHITE
var _base_energy: float = 1.5
var _light: OmniLight3D
var _zap_player: AudioStreamPlayer3D


func _ready() -> void:
	collision_layer = 0
	collision_mask = 1   # реагируем на игрока (слой 1)
	monitoring = true
	monitorable = false
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)

	if kind == Kind.ELECTRA:
		_color = Color(0.45, 0.8, 1.0)
		_base_energy = 2.0
	else:
		_color = Color(1.0, 0.5, 0.15)
		_base_energy = 2.5

	_build_collision()
	_build_ground_disc()
	_build_particles()
	_build_light()
	_build_audio()
	Fx.spawn_ring_signs(self, SIGN_PATH, sign_count, radius + 1.3, 0.6)


func _process(delta: float) -> void:
	# Мерцание света, при ударе вспышка
	_flash = move_toward(_flash, 0.0, delta * 4.0)
	_light.light_energy = _base_energy * randf_range(0.6, 1.4) + _flash * 4.0


func _physics_process(delta: float) -> void:
	if _victims.is_empty():
		return
	_tick_timer -= delta
	if _tick_timer > 0.0:
		return
	_tick_timer = tick_interval
	for body in _victims.duplicate():
		if not is_instance_valid(body):
			_victims.erase(body)
			continue
		body.call("take_damage", damage)
	_flash = 1.0
	if _zap_player != null:
		_zap_player.play()


func _on_body_entered(body: Node3D) -> void:
	if body.is_in_group("player") and not _victims.has(body):
		_victims.append(body)
		_tick_timer = 0.0   # первый удар сразу при входе


func _on_body_exited(body: Node3D) -> void:
	_victims.erase(body)


# --- Построение ------------------------------------------------------------

## Форма лежит в сцене (чтобы редактор не ругался), здесь только подгоняем радиус
## под значение из инспектора. Форма создаётся заново, поэтому экземпляры не делят её.
func _build_collision() -> void:
	var shape := get_node_or_null("CollisionShape3D") as CollisionShape3D
	if shape == null:
		shape = CollisionShape3D.new()
		shape.position = Vector3(0.0, 1.2, 0.0)
		add_child(shape)
	var cyl := CylinderShape3D.new()
	cyl.radius = radius
	cyl.height = 3.0
	shape.shape = cyl


## Едва заметный светящийся круг на земле: видно границу аномалии.
func _build_ground_disc() -> void:
	var disc := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = 0.02
	mesh.radial_segments = 32
	mesh.rings = 1
	disc.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(_color.r, _color.g, _color.b, 0.14)
	disc.material_override = mat
	disc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	disc.position = Vector3(0.0, 0.04, 0.0)
	add_child(disc)


func _build_particles() -> void:
	var particles := GPUParticles3D.new()
	var pm := ParticleProcessMaterial.new()
	var quad := QuadMesh.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.color_ramp = Fx.fade_ramp(_color)

	if kind == Kind.ELECTRA:
		# Электра: яркие искры, разлетающиеся во все стороны
		particles.amount = 50
		particles.lifetime = 0.5
		pm.emission_sphere_radius = 0.25
		pm.direction = Vector3.UP
		pm.spread = 180.0
		pm.initial_velocity_min = 2.0
		pm.initial_velocity_max = 5.0
		pm.gravity = Vector3.ZERO
		pm.damping_min = 2.0
		pm.damping_max = 4.0
		pm.scale_min = 0.6
		pm.scale_max = 1.3
		quad.size = Vector2(0.3, 0.3)
		particles.position = Vector3(0.0, 0.7, 0.0)
	else:
		# Жарка: столб огня, поднимающийся вверх
		particles.amount = 70
		particles.lifetime = 1.3
		pm.emission_sphere_radius = radius * 0.5
		pm.direction = Vector3.UP
		pm.spread = 12.0
		pm.initial_velocity_min = 0.8
		pm.initial_velocity_max = 2.0
		pm.gravity = Vector3(0.0, 1.5, 0.0)
		pm.scale_min = 0.6
		pm.scale_max = 1.4
		quad.size = Vector2(0.7, 0.7)
		particles.position = Vector3(0.0, 0.3, 0.0)

	quad.material = Fx.particle_material(_color)
	particles.process_material = pm
	particles.draw_pass_1 = quad
	# Рамка видимости побольше, иначе частицы пропадают, когда центр аномалии вне кадра
	particles.visibility_aabb = AABB(
		Vector3(-radius - 2.0, -1.0, -radius - 2.0),
		Vector3(radius * 2.0 + 4.0, 7.0, radius * 2.0 + 4.0)
	)
	add_child(particles)
	particles.emitting = true


func _build_light() -> void:
	_light = OmniLight3D.new()
	_light.light_color = _color
	_light.omni_range = radius * 3.0 + 2.0
	_light.light_energy = _base_energy
	_light.shadow_enabled = false
	_light.position = Vector3(0.0, 1.0, 0.0)
	add_child(_light)


func _build_audio() -> void:
	var loop_stream := Fx.load_stream(ELECTRA_LOOP if kind == Kind.ELECTRA else FIRE_LOOP, true)
	if loop_stream != null:
		var hum := AudioStreamPlayer3D.new()
		hum.stream = loop_stream
		hum.unit_size = 5.0
		hum.max_distance = 45.0
		hum.volume_db = -20.0
		add_child(hum)
		hum.play()

	var zap_stream := Fx.load_stream(ZAP_PATH, false)
	if zap_stream != null:
		_zap_player = AudioStreamPlayer3D.new()
		_zap_player.stream = zap_stream
		_zap_player.volume_db = -12.0
		_zap_player.unit_size = 8.0
		_zap_player.max_distance = 50.0
		_zap_player.pitch_scale = 1.0 if kind == Kind.ELECTRA else 0.6
		add_child(_zap_player)
