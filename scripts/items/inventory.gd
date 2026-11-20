class_name Inventory
extends Node
## Рюкзак игрока: сетка фиксированного числа ячеек и лимит по весу.
## Ячейка: {"item": Item, "count": int}, пустая ячейка: {} (пустой словарь).
## Всё локально (одиночная игра), сервера нет.

signal changed
signal item_added(item: Item, amount: int)
signal rejected(item: Item, reason: String)
## Сигнал вызывается из inventory_ui.gd, поэтому анализатор считает его неиспользуемым
@warning_ignore("unused_signal")
signal item_dropped(item: Item, amount: int)

## Максимальный переносимый вес, кг
@export var max_weight: float = 50.0
## Число ячеек рюкзака
@export var capacity: int = 42

## Слоты снаряжения: слот -> Item (по одному предмету в слоте)
const SLOT_PRIMARY := &"primary"
const SLOT_PISTOL := &"pistol"
const SLOT_MELEE := &"melee"

## Экипировали или сняли предмет в слоте снаряжения
signal equipment_changed(slot_name: StringName)

var slots: Array[Dictionary] = []
var equipment: Dictionary = {}


func _ready() -> void:
	slots.clear()
	for _i in range(capacity):
		slots.append({})


func is_slot_empty(index: int) -> bool:
	return index < 0 or index >= slots.size() or slots[index].is_empty()


func get_total_weight() -> float:
	var total := 0.0
	for slot in slots:
		if slot.is_empty():
			continue
		var item: Item = slot["item"]
		total += item.weight * int(slot["count"])
	for equipped: Item in equipment.values():
		total += equipped.weight
	return total


# --- Снаряжение ---------------------------------------------------------------

## В какой слот снаряжения подходит предмет (пустое имя, если ни в какой).
static func equipment_slot_for(item: Item) -> StringName:
	if item is Weapon:
		var wslot := (item as Weapon).slot
		if wslot == 1:
			return SLOT_PISTOL
		return SLOT_MELEE if wslot == 3 else SLOT_PRIMARY
	return &""


func get_equipped(slot_name: StringName) -> Item:
	return equipment.get(slot_name) as Item


func is_equipped(item: Item) -> bool:
	for equipped: Item in equipment.values():
		if equipped.id == item.id:
			return true
	return false


## Надевает предмет из ячейки рюкзака в подходящий слот. Если слот занят,
## прежний предмет возвращается в ту же ячейку (обмен). slot_name можно не указывать.
func equip_from_backpack(index: int, slot_name: StringName = &"") -> bool:
	if is_slot_empty(index):
		return false
	var item: Item = slots[index]["item"]
	var target := equipment_slot_for(item)
	if target == &"" or (slot_name != &"" and slot_name != target):
		return false
	var old := get_equipped(target)
	var left := int(slots[index]["count"]) - 1
	if old != null and left > 0 and _free_cells() == 0:
		rejected.emit(item, "Нет места")
		return false

	if left <= 0:
		slots[index] = {}
	else:
		slots[index]["count"] = left
	equipment[target] = item
	if old != null:
		if slots[index].is_empty():
			slots[index] = {"item": old, "count": 1}
		else:
			for i in range(slots.size()):
				if slots[i].is_empty():
					slots[i] = {"item": old, "count": 1}
					break
	equipment_changed.emit(target)
	changed.emit()
	return true


## Снимает предмет из слота в рюкзак: в ячейку to_index (она должна быть пустой)
## или в первую свободную.
func unequip_to_backpack(slot_name: StringName, to_index: int = -1) -> bool:
	var item := get_equipped(slot_name)
	if item == null:
		return false
	var cell := to_index
	if cell >= 0:
		if cell >= slots.size() or not is_slot_empty(cell):
			return false
	else:
		for i in range(slots.size()):
			if slots[i].is_empty():
				cell = i
				break
		if cell < 0:
			rejected.emit(item, "Нет места")
			return false
	slots[cell] = {"item": item, "count": 1}
	equipment.erase(slot_name)
	equipment_changed.emit(slot_name)
	changed.emit()
	return true


## Забирает предмет из слота снаряжения совсем (для выбрасывания на землю).
func take_equipped(slot_name: StringName) -> Item:
	var item := get_equipped(slot_name)
	if item == null:
		return null
	equipment.erase(slot_name)
	equipment_changed.emit(slot_name)
	changed.emit()
	return item


func get_count(item_id: StringName) -> int:
	var total := 0
	for slot in slots:
		if slot.is_empty():
			continue
		var item: Item = slot["item"]
		if item.id == item_id:
			total += int(slot["count"])
	return total


## Убирает из рюкзака до amount штук предмета с таким id (из любых ячеек).
## Возвращает, сколько реально убрано.
func remove_item(item_id: StringName, amount: int) -> int:
	var left := amount
	for i in range(slots.size() - 1, -1, -1):   # с конца: сначала неполные стопки
		if left <= 0:
			break
		if slots[i].is_empty():
			continue
		var slot_item: Item = slots[i]["item"]
		if slot_item.id != item_id:
			continue
		var take := mini(left, int(slots[i]["count"]))
		slots[i]["count"] = int(slots[i]["count"]) - take
		if int(slots[i]["count"]) <= 0:
			slots[i] = {}
		left -= take
	if left < amount:
		changed.emit()
	return amount - left


func _free_cells() -> int:
	var free := 0
	for slot in slots:
		if slot.is_empty():
			free += 1
	return free


## Кладёт предмет в рюкзак. Всё или ничего: если не влезает по весу или по месту, ничего не добавляется.
func add_item(item: Item, amount: int = 1) -> bool:
	if item == null or amount <= 0:
		return false
	if get_total_weight() + item.weight * amount > max_weight:
		rejected.emit(item, "Слишком тяжело")
		return false

	# Проверяем место заранее, чтобы не добавить предмет наполовину
	var stack_space := 0
	for slot in slots:
		if slot.is_empty():
			continue
		var slot_item: Item = slot["item"]
		if slot_item.id == item.id:
			stack_space += maxi(item.max_stack - int(slot["count"]), 0)
	var rest := maxi(amount - stack_space, 0)
	var cells_needed := ceili(rest / float(maxi(item.max_stack, 1)))
	if cells_needed > _free_cells():
		rejected.emit(item, "Нет места")
		return false

	var remaining := amount
	# Сначала докладываем в неполные стопки
	for slot in slots:
		if remaining == 0:
			break
		if slot.is_empty():
			continue
		var slot_item: Item = slot["item"]
		if slot_item.id == item.id and int(slot["count"]) < item.max_stack:
			var to_add := mini(item.max_stack - int(slot["count"]), remaining)
			slot["count"] = int(slot["count"]) + to_add
			remaining -= to_add
	# Остаток раскладываем по первым свободным ячейкам
	for i in range(slots.size()):
		if remaining <= 0:
			break
		if slots[i].is_empty():
			var chunk := mini(item.max_stack, remaining)
			slots[i] = {"item": item, "count": chunk}
			remaining -= chunk

	item_added.emit(item, amount)
	changed.emit()
	return true


## Убирает из ячейки до amount штук. Возвращает, сколько реально убрано.
func remove_from_slot(index: int, amount: int = 1) -> int:
	if is_slot_empty(index) or amount <= 0:
		return 0
	var slot := slots[index]
	var removed := mini(amount, int(slot["count"]))
	slot["count"] = int(slot["count"]) - removed
	if int(slot["count"]) <= 0:
		slots[index] = {}
	changed.emit()
	return removed


## Переносит содержимое ячейки from в ячейку to:
## пустая ячейка принимает предмет, такая же стопка сливается, иначе ячейки меняются местами.
func move_slot(from: int, to: int) -> void:
	if from == to or is_slot_empty(from) or to < 0 or to >= slots.size():
		return
	if slots[to].is_empty():
		slots[to] = slots[from]
		slots[from] = {}
	else:
		var from_item: Item = slots[from]["item"]
		var to_item: Item = slots[to]["item"]
		if from_item.id == to_item.id and int(slots[to]["count"]) < to_item.max_stack:
			var space := to_item.max_stack - int(slots[to]["count"])
			var moved := mini(space, int(slots[from]["count"]))
			slots[to]["count"] = int(slots[to]["count"]) + moved
			slots[from]["count"] = int(slots[from]["count"]) - moved
			if int(slots[from]["count"]) <= 0:
				slots[from] = {}
		else:
			var tmp := slots[from]
			slots[from] = slots[to]
			slots[to] = tmp
	changed.emit()


# --- Консоль разработчика (клавиша «ё») -----------------------------------------
# Выдают предметы из воздуха, лимит по весу не проверяют. Нужно только свободное место.

## Кладёт предмет в рюкзак, не глядя на вес. Сначала докладывает в неполные стопки.
func dev_give(item: Item, amount: int) -> bool:
	if item == null or amount <= 0:
		return false
	var stack_space := 0
	for slot in slots:
		if not slot.is_empty() and (slot["item"] as Item).id == item.id:
			stack_space += maxi(item.max_stack - int(slot["count"]), 0)
	var rest := maxi(amount - stack_space, 0)
	if ceili(rest / float(maxi(item.max_stack, 1))) > _free_cells():
		rejected.emit(item, "Нет места")
		return false

	var remaining := amount
	for slot in slots:
		if remaining <= 0:
			break
		if slot.is_empty() or (slot["item"] as Item).id != item.id:
			continue
		var to_add := mini(item.max_stack - int(slot["count"]), remaining)
		if to_add > 0:
			slot["count"] = int(slot["count"]) + to_add
			remaining -= to_add
	for i in range(slots.size()):
		if remaining <= 0:
			break
		if slots[i].is_empty():
			var chunk := mini(item.max_stack, remaining)
			slots[i] = {"item": item, "count": chunk}
			remaining -= chunk
	item_added.emit(item, amount)
	changed.emit()
	return true


## Кладёт полную стопку предмета в конкретную ячейку. Если ячейка занята,
## предмет уходит в первую подходящую свободную.
func dev_spawn_into_slot(index: int, item: Item) -> bool:
	if item == null:
		return false
	if index >= 0 and index < slots.size() and slots[index].is_empty():
		slots[index] = {"item": item, "count": item.max_stack}
		item_added.emit(item, item.max_stack)
		changed.emit()
		return true
	return dev_give(item, item.max_stack)


## Ставит предмет прямо в слот снаряжения. Прежний предмет возвращается в рюкзак
## (если места нет, он просто исчезает: это отладочная функция).
func dev_equip(slot_name: StringName, item: Item) -> bool:
	if item == null or equipment_slot_for(item) != slot_name:
		return false
	var old := get_equipped(slot_name)
	equipment[slot_name] = item
	if old != null and old.id != item.id:
		dev_give(old, 1)
	equipment_changed.emit(slot_name)
	changed.emit()
	return true


## Использует одну штуку из ячейки на пользователе (сейчас: лечение).
func use_slot(index: int, user: Node) -> bool:
	if is_slot_empty(index):
		return false
	var item: Item = slots[index]["item"]
	if not item.is_usable():
		return false
	if item is Weapon:
		# Оружие не расходуется: «использовать» = надеть в слот снаряжения
		return equip_from_backpack(index)
	if item.heal_amount > 0.0:
		var health: float = user.get("health")
		var max_health: float = user.get("max_health")
		if health >= max_health:
			rejected.emit(item, "Здоровье полное")
			return false
		user.call("heal", item.heal_amount)
	if item.radiation_reduce > 0.0:
		var radiation: float = user.get("radiation")
		if radiation <= 0.0 and item.heal_amount <= 0.0:
			rejected.emit(item, "Радиации нет")
			return false
		user.call("reduce_radiation", item.radiation_reduce)
	remove_from_slot(index, 1)
	return true
