class_name Fx
extends RefCounted
## Общие помощники для эффектов этапа 3.1: частицы, материалы, звук и знаки по периметру.


## Мягкая круглая точка для частиц (белая в центре, прозрачная по краю).
static func soft_dot() -> Texture2D:
	var grad := Gradient.new()
	grad.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0)])
	grad.offsets = PackedFloat32Array([0.0, 1.0])
	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	tex.width = 64
	tex.height = 64
	return tex


## Светящийся материал для частиц: без освещения, сложение цветов, всегда лицом к камере.
static func particle_material(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.vertex_color_use_as_albedo = true
	m.albedo_texture = soft_dot()
	m.albedo_color = Color(color.r, color.g, color.b, 1.0)
	return m


## Прозрачность частицы за время жизни: появляется, достигает peak и гаснет.
static func fade_ramp(color: Color, peak: float = 1.0) -> GradientTexture1D:
	var g := Gradient.new()
	g.colors = PackedColorArray([
		Color(color.r, color.g, color.b, 0.0),
		Color(color.r, color.g, color.b, peak),
		Color(color.r, color.g, color.b, 0.0),
	])
	g.offsets = PackedFloat32Array([0.0, 0.25, 1.0])
	var t := GradientTexture1D.new()
	t.gradient = g
	return t


## Загружает звук. Если файла нет, возвращает null (игра работает и без звука).
## looped: включить зацикливание (ожидается WAV 16 бит, моно).
static func load_stream(path: String, looped: bool) -> AudioStream:
	if not ResourceLoader.exists(path):
		return null
	var stream := load(path) as AudioStream
	if looped and stream is AudioStreamWAV:
		var wav := (stream as AudioStreamWAV).duplicate() as AudioStreamWAV
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
		wav.loop_begin = 0
		wav.loop_end = wav.data.size() >> 1   # 2 байта на отсчёт
		return wav
	return stream


## Расставляет знаки по кольцу вокруг host и опускает каждый на землю лучом вниз.
## Если модели знака нет, ничего не делает.
static func spawn_ring_signs(host: Node3D, path: String, count: int, ring_radius: float, angle_offset: float = 0.0) -> void:
	if count <= 0 or not ResourceLoader.exists(path):
		return
	var scene := load(path) as PackedScene
	if scene == null:
		return
	# Ждём два физических кадра: к этому моменту у ландшафта уже есть коллизия
	await host.get_tree().physics_frame
	await host.get_tree().physics_frame
	if not is_instance_valid(host):
		return
	var space := host.get_world_3d().direct_space_state
	for i in range(count):
		var angle := angle_offset + TAU * i / count
		var dir := Vector3(cos(angle), 0.0, sin(angle))
		var world_pos := host.global_position + dir * ring_radius
		var query := PhysicsRayQueryParameters3D.create(
			world_pos + Vector3.UP * 30.0, world_pos + Vector3.DOWN * 30.0, 1
		)
		var hit := space.intersect_ray(query)
		if not hit.is_empty():
			world_pos = hit["position"]
		var sign_node := scene.instantiate() as Node3D
		host.add_child(sign_node)
		sign_node.global_position = world_pos
		sign_node.rotation.y = atan2(dir.x, dir.z)   # лицом наружу
