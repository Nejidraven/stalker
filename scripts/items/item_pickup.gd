extends Area3D
## Предмет на земле. Игрок подбирает его клавишей E (через interactor.gd).
## Пока вместо модели цветная коробка, позже заменим на модели из Blender.

@export var item: Item
@export var amount: int = 1

@onready var _mesh: MeshInstance3D = $Mesh
@onready var _label: Label3D = $Label


func _ready() -> void:
	collision_layer = 2   # слой 2 = «интерактивное», его видит Interactor
	collision_mask = 0
	monitoring = false
	add_to_group("interactable")
	_mesh.rotation.y = randf() * TAU   # каждый предмет лежит под своим углом
	_label.visible = false
	_refresh_visuals()


func _refresh_visuals() -> void:
	if item == null:
		_label.text = "?"
		return
	var mat := StandardMaterial3D.new()
	mat.albedo_color = item.world_color
	mat.roughness = 0.7
	mat.emission_enabled = true
	mat.emission = item.world_color
	mat.emission_energy_multiplier = 0.25
	_mesh.material_override = mat
	_label.text = item.display_name if amount <= 1 else "%s ×%d" % [item.display_name, amount]


func set_focused(focused: bool) -> void:
	_label.visible = focused


func get_prompt() -> String:
	if item == null:
		return "Подобрать"
	return "Подобрать: %s" % _label.text


func interact(player: Node) -> void:
	if item == null:
		return
	var inventory := player.get_node_or_null("Inventory") as Inventory
	if inventory == null:
		return
	if inventory.add_item(item, amount):
		queue_free()
