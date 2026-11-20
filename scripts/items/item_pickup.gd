extends Area3D
## Предмет на земле. Игрок подбирает его клавишей E (через interactor.gd).
## Если у предмета задана world_model, на земле лежит настоящая модель (.glb),
## иначе — цветная коробка-заглушка.

@export var item: Item
@export var amount: int = 1

@onready var _mesh: MeshInstance3D = $Mesh
@onready var _label: Label3D = $Label


func _ready() -> void:
	collision_layer = 2   # слой 2 = «интерактивное», его видит Interactor
	collision_mask = 0
	monitoring = false
	add_to_group("interactable")
	var spin := randf() * TAU   # каждый предмет лежит под своим углом
	_mesh.rotation.y = spin
	_label.visible = false
	_spawn_model(spin)
	_refresh_visuals()


## Ставит модель предмета на землю. origin модели должен быть в центре
## нижней грани, поэтому экземпляр встаёт точно на уровень пола.
func _spawn_model(spin: float) -> void:
	if item == null or item.world_model.is_empty():
		return
	var packed := load(item.world_model) as PackedScene
	if packed == null:
		push_warning("ItemPickup: не удалось загрузить модель '%s'" % item.world_model)
		return
	var inst := packed.instantiate()
	inst.rotation.y = spin
	add_child(inst)
	_mesh.visible = false   # заглушка больше не нужна


func _refresh_visuals() -> void:
	if item == null:
		_label.text = "?"
		return
	if _mesh.visible:
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
