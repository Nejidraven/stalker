@tool
extends MeshInstance3D
## Процедурный ландшафт из шума с ровной площадкой в центре (там появляется игрок).
## Временное решение этапа 2.1: позже можно заменить на heightmap или Terrain3D.
## @tool: ландшафт строится и в редакторе, чтобы его было видно без запуска игры.

@export var size: float = 200.0
@export var cells: int = 100
@export var height_scale: float = 7.0
@export var flat_radius: float = 12.0
@export var flat_falloff: float = 28.0
@export var noise_seed: int = 1337
@export var grass_color: Color = Color(0.30, 0.33, 0.22)
@export var dirt_color: Color = Color(0.25, 0.22, 0.17)

var _noise: FastNoiseLite


func _ready() -> void:
	_ensure_noise()
	_build_mesh()


func _notification(what: int) -> void:
	# Чтобы огромный меш не записывался внутрь level.tscn: на время сохранения
	# убираем его, после сохранения строим заново. В игре это не вызывается.
	if not Engine.is_editor_hint():
		return
	if what == NOTIFICATION_EDITOR_PRE_SAVE:
		mesh = null
		material_override = null
	elif what == NOTIFICATION_EDITOR_POST_SAVE:
		_build_mesh()


## Высота ландшафта в точке (x, z). Используется и для расстановки объектов.
func get_height(x: float, z: float) -> float:
	_ensure_noise()
	var dist := Vector2(x, z).length()
	var flat_factor := smoothstep(flat_radius, flat_radius + flat_falloff, dist)
	return _noise.get_noise_2d(x, z) * height_scale * flat_factor


func _ensure_noise() -> void:
	if _noise != null:
		return
	_noise = FastNoiseLite.new()
	_noise.seed = noise_seed
	_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_noise.frequency = 0.012
	_noise.fractal_octaves = 3


func _normal_at(x: float, z: float, e: float) -> Vector3:
	var h_left := get_height(x - e, z)
	var h_right := get_height(x + e, z)
	var h_back := get_height(x, z - e)
	var h_front := get_height(x, z + e)
	return Vector3(h_left - h_right, 2.0 * e, h_back - h_front).normalized()


func _build_mesh() -> void:
	_ensure_noise()
	var step := size / cells
	var half := size * 0.5

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	for iz in range(cells + 1):
		for ix in range(cells + 1):
			var x := -half + ix * step
			var z := -half + iz * step
			var tint := clampf(absf(_noise.get_noise_2d(x * 3.0, z * 3.0)) * 2.0, 0.0, 1.0)
			st.set_color(grass_color.lerp(dirt_color, tint))
			st.set_normal(_normal_at(x, z, step))
			st.add_vertex(Vector3(x, get_height(x, z), z))

	var row := cells + 1
	for iz in range(cells):
		for ix in range(cells):
			var a := iz * row + ix
			var b := a + 1
			var c := a + row
			var d := c + 1
			# Порядок обхода по часовой стрелке, если смотреть сверху (передняя грань в Godot)
			st.add_index(a)
			st.add_index(b)
			st.add_index(c)
			st.add_index(b)
			st.add_index(d)
			st.add_index(c)

	mesh = st.commit()

	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 1.0
	material_override = mat

	# Коллизия по форме меша нужна только в игре. В редакторе её не создаём:
	# иначе она записалась бы в сцену вместе с гигантской формой.
	if not Engine.is_editor_hint():
		create_trimesh_collision()
