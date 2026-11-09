extends Area3D
## Зона взаимодействия игрока. Находит ближайший интерактивный объект рядом
## и по клавише E вызывает у него interact(игрок).

signal focus_changed(target: Node3D)

var _candidates: Array[Node3D] = []
var _focus: Node3D = null
## id объекта в фокусе (0 = ничего). Сравниваем именно id: после удаления предмета
## в Godot «удалённый объект == null» даёт true, и по обычному сравнению исчезновение не заметить.
var _focus_id: int = 0


func _ready() -> void:
	collision_layer = 0
	collision_mask = 2   # видим только слой 2 (предметы)
	monitoring = true
	monitorable = false
	area_entered.connect(_on_area_entered)
	area_exited.connect(_on_area_exited)


func _on_area_entered(area: Area3D) -> void:
	if area.is_in_group("interactable") and not _candidates.has(area):
		_candidates.append(area)


func _on_area_exited(area: Area3D) -> void:
	_candidates.erase(area)


func _physics_process(_delta: float) -> void:
	var best: Node3D = null
	var best_dist := INF
	for candidate in _candidates.duplicate():
		if not is_instance_valid(candidate):
			_candidates.erase(candidate)
			continue
		var dist := global_position.distance_squared_to(candidate.global_position)
		if dist < best_dist:
			best_dist = dist
			best = candidate

	var best_id := best.get_instance_id() if best != null else 0
	if best_id == _focus_id:
		return

	# Фокус сменился (или предмет подобрали и он исчез)
	if is_instance_valid(_focus) and _focus.has_method("set_focused"):
		_focus.call("set_focused", false)
	_focus = best
	_focus_id = best_id
	if best != null and best.has_method("set_focused"):
		best.call("set_focused", true)
	focus_changed.emit(best)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("interact") and is_instance_valid(_focus) and _focus.has_method("interact"):
		_focus.call("interact", get_parent())
		get_viewport().set_input_as_handled()
