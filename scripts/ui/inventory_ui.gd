extends CanvasLayer
## Экран инвентаря (клавиша Tab).
## Стиль вдохновлён S.T.A.L.K.E.R. 2: тёмные приглушённые панели, тонкие рамки, янтарный акцент,
## общий рюкзак-сетка, слева снаряжение (броня по центру, оружие по бокам), шкала веса.
## Управление: клик выбирает предмет, перетаскивание перемещает его по ячейкам и в слоты
## снаряжения (оружие в слоте сразу берётся в руки), за пределы окна или клавиша G выбрасывают,
## Shift+клик быстро отправляет предмет в подходящий слот (или обратно в рюкзак).
## Интерфейс собирается из Control-узлов в коде. Пока открыт, игра стоит на паузе.

const PICKUP_SCENE: PackedScene = preload("res://scenes/items/item_pickup.tscn")

const COL_DIM := Color(0.02, 0.025, 0.025, 0.86)
const COL_PANEL := Color(0.085, 0.092, 0.092, 0.97)
const COL_PANEL_INNER := Color(0.065, 0.07, 0.07, 1.0)
const COL_CELL := Color(0.125, 0.135, 0.135, 1.0)
const COL_CELL_HOVER := Color(0.19, 0.2, 0.19, 1.0)
const COL_LINE := Color(0.36, 0.37, 0.35, 1.0)
const COL_LINE_SOFT := Color(0.2, 0.21, 0.2, 1.0)
const COL_TEXT := Color(0.82, 0.82, 0.78, 1.0)
const COL_MUTED := Color(0.52, 0.53, 0.5, 1.0)
const COL_ACCENT := Color(0.88, 0.63, 0.18, 1.0)
const COL_OK := Color(0.45, 0.7, 0.3, 1.0)
const COL_WARN := Color(0.88, 0.63, 0.18, 1.0)
const COL_BAD := Color(0.78, 0.22, 0.16, 1.0)

const COLUMNS := 7
const CELL_SIZE := 68
const DRAG_TYPE := "inventory_slot"

## Названия слотов снаряжения: клавиша быстрого выбора оружия в скобках
const EQUIP_TITLES := {
	&"primary": "ОСНОВНОЕ\nОРУЖИЕ\n[2]",
	&"pistol": "ПИСТОЛЕТ\n[1]",
}
const EQUIP_KEYS := {&"primary": "[2]", &"pistol": "[1]"}

## Слоты оружия и брони одного размера
const EQUIP_SLOT_SIZE := Vector2(88, 196)

const ITEMS_DIR := "res://resources/items"

var _inventory: Inventory
var _player: Node
var _open: bool = false
var _selected: int = -1                  # выбранная ячейка рюкзака
var _selected_eq: StringName = &""       # или выбранный слот снаряжения
var _equip_row: HBoxContainer

var _console_on: bool = false            # консоль разработчика (клавиша ё)
var _title_label: Label
var _details_panel: Control
var _console_panel: Control

var _root: Control
var _grid: GridContainer
var _weight_bar: ProgressBar
var _weight_fill: StyleBoxFlat
var _weight_label: Label
var _detail_icon: TextureRect
var _detail_name: Label
var _detail_meta: Label
var _detail_desc: Label
var _use_button: Button
var _drop_button: Button


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS  # работает, пока игра на паузе
	layer = 10
	_build_ui()
	visible = false
	call_deferred("_connect_player")


func _connect_player() -> void:
	_player = get_tree().get_first_node_in_group("player")
	if _player == null:
		push_warning("InventoryUI: игрок не найден (группа 'player')")
		return
	_inventory = _player.get_node_or_null("Inventory") as Inventory
	if _inventory == null:
		push_warning("InventoryUI: у игрока нет узла Inventory")
		return
	_inventory.changed.connect(_on_inventory_changed)
	_refresh()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("inventory"):
		_set_open(not _open)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("dev_console"):
		_toggle_console()
		get_viewport().set_input_as_handled()
	elif _open and event.is_action_pressed("ui_cancel"):
		_set_open(false)
		get_viewport().set_input_as_handled()
	elif _open and event.is_action_pressed("drop_item"):
		_drop_under_cursor()
		get_viewport().set_input_as_handled()


func _set_open(value: bool) -> void:
	if value == _open:
		return
	if value and _inventory == null:
		return
	_open = value
	visible = value
	get_tree().paused = value
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if value else Input.MOUSE_MODE_CAPTURED
	if not value:
		_console_on = false
		_apply_console()
	if value:
		_refresh()


## Клавиша «ё»: открывает инвентарь с консолью разработчика (список всех предметов).
## Если инвентарь уже открыт, консоль включается и выключается.
func _toggle_console() -> void:
	if _inventory == null:
		return
	_console_on = not _console_on if _open else true
	_apply_console()
	_set_open(true)


func _apply_console() -> void:
	_details_panel.visible = not _console_on
	_console_panel.visible = _console_on
	_title_label.text = "ИНВЕНТАРЬ · КОНСОЛЬ РАЗРАБОТЧИКА" if _console_on else "ИНВЕНТАРЬ"


func _on_inventory_changed() -> void:
	# Откладываем перерисовку: изменение может прийти прямо посреди перетаскивания,
	# и нельзя удалять ячейки, пока Godot ещё обрабатывает отпускание мыши.
	if _open:
		_refresh.call_deferred()


# --- Построение интерфейса -----------------------------------------------

func _build_ui() -> void:
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	# Всё, что отпущено мимо окна инвентаря, выбрасывается на землю
	_root.set_drag_forwarding(Callable(), _outside_can_drop, _outside_drop)
	add_child(_root)

	var dim := ColorRect.new()
	dim.color = COL_DIM
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(center)

	var main := PanelContainer.new()
	main.custom_minimum_size = Vector2(1200, 640)
	# STOP нужен, чтобы отпускание предмета над окном (мимо ячеек) не считалось «за окном»
	main.mouse_filter = Control.MOUSE_FILTER_STOP
	main.add_theme_stylebox_override("panel", _box(COL_PANEL, COL_LINE, 1))
	center.add_child(main)

	var margin := MarginContainer.new()
	for side in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 16)
	main.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	margin.add_child(vbox)

	vbox.add_child(_build_header())
	vbox.add_child(_line())

	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 14)
	vbox.add_child(body)
	body.add_child(_build_equipment_panel())
	body.add_child(_build_backpack_panel())
	_details_panel = _build_details_panel()
	body.add_child(_details_panel)
	_console_panel = _build_console_panel()
	_console_panel.visible = false
	body.add_child(_console_panel)

	vbox.add_child(_line())
	vbox.add_child(_build_footer())


func _build_header() -> Control:
	var row := HBoxContainer.new()
	_title_label = _label("ИНВЕНТАРЬ", 28, COL_ACCENT)
	row.add_child(_title_label)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)
	var hint := _label("TAB / ESC — закрыть", 14, COL_MUTED)
	hint.size_flags_vertical = Control.SIZE_SHRINK_END
	row.add_child(hint)
	return row


func _build_equipment_panel() -> Control:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(300, 0)
	panel.add_theme_stylebox_override("panel", _box(COL_PANEL_INNER, COL_LINE_SOFT, 1, 10))

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	panel.add_child(v)
	v.add_child(_label("СНАРЯЖЕНИЕ", 14, COL_MUTED))

	# Броня стоит вертикально по центру, слоты оружия по бокам от неё.
	# Содержимое слотов перестраивается в _refresh_equipment().
	_equip_row = HBoxContainer.new()
	_equip_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_equip_row.add_theme_constant_override("separation", 6)
	v.add_child(_equip_row)

	v.add_child(_label("АРТЕФАКТЫ", 14, COL_MUTED))
	var arts := HBoxContainer.new()
	arts.alignment = BoxContainer.ALIGNMENT_CENTER
	arts.add_theme_constant_override("separation", 6)
	for _i in range(3):
		arts.add_child(_slot_frame("", Vector2(84, 64)))
	v.add_child(arts)
	return panel


func _build_backpack_panel() -> Control:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel", _box(COL_PANEL_INNER, COL_LINE_SOFT, 1, 10))

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	panel.add_child(v)
	v.add_child(_label("РЮКЗАК", 14, COL_MUTED))

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(scroll)

	_grid = GridContainer.new()
	_grid.columns = COLUMNS
	_grid.add_theme_constant_override("h_separation", 6)
	_grid.add_theme_constant_override("v_separation", 6)
	scroll.add_child(_grid)
	return panel


func _build_details_panel() -> Control:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(270, 0)
	panel.add_theme_stylebox_override("panel", _box(COL_PANEL_INNER, COL_LINE_SOFT, 1, 10))

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	panel.add_child(v)
	v.add_child(_label("ПРЕДМЕТ", 14, COL_MUTED))

	var icon_frame := PanelContainer.new()
	icon_frame.custom_minimum_size = Vector2(0, 140)
	icon_frame.add_theme_stylebox_override("panel", _box(COL_CELL, COL_LINE_SOFT, 1, 8))
	v.add_child(icon_frame)
	_detail_icon = TextureRect.new()
	_detail_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_detail_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon_frame.add_child(_detail_icon)

	_detail_name = _label("Выберите предмет", 20, COL_ACCENT)
	_detail_name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(_detail_name)

	_detail_meta = _label("", 14, COL_TEXT)
	_detail_meta.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(_detail_meta)

	_detail_desc = _label("", 14, COL_MUTED)
	_detail_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_detail_desc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(_detail_desc)

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 8)
	v.add_child(buttons)
	_use_button = _make_button("Использовать")
	_use_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_use_button.pressed.connect(_on_use_pressed)
	buttons.add_child(_use_button)
	_drop_button = _make_button("Выбросить [G]")
	_drop_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_drop_button.pressed.connect(_on_drop_pressed)
	buttons.add_child(_drop_button)
	return panel


## Консоль разработчика: все предметы игры. Их можно перетащить в рюкзак или слот
## снаряжения (каждый раз выдаётся полная стопка), двойной клик кладёт стопку в рюкзак.
func _build_console_panel() -> Control:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(270, 0)
	panel.add_theme_stylebox_override("panel", _box(COL_PANEL_INNER, COL_ACCENT, 1, 10))

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	panel.add_child(v)
	v.add_child(_label("КОНСОЛЬ · ВСЕ ПРЕДМЕТЫ", 14, COL_ACCENT))
	var hint := _label("Перетащите предмет в рюкзак или слот. Двойной клик: стопка в рюкзак.", 12, COL_MUTED)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(hint)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(scroll)

	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 4)
	scroll.add_child(list)

	for item in _load_catalog():
		list.add_child(_make_catalog_row(item))
	return panel


## Все предметы из папки ресурсов, по категории и названию.
func _load_catalog() -> Array[Item]:
	var items: Array[Item] = []
	for file_name in DirAccess.get_files_at(ITEMS_DIR):
		var clean := file_name.trim_suffix(".remap")   # в собранной игре ресурсы переименованы
		if not clean.ends_with(".tres"):
			continue
		var res := load(ITEMS_DIR + "/" + clean) as Item
		if res != null:
			items.append(res)
	items.sort_custom(func(a: Item, b: Item) -> bool:
		if a.category != b.category:
			return a.category < b.category
		return a.display_name < b.display_name
	)
	return items


func _make_catalog_row(item: Item) -> Control:
	var btn := Button.new()
	btn.custom_minimum_size = Vector2(0, 54)
	btn.focus_mode = Control.FOCUS_NONE
	btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	btn.icon = item.icon
	btn.expand_icon = true
	btn.add_theme_constant_override("icon_max_width", 44)
	btn.add_theme_font_size_override("font_size", 14)
	btn.add_theme_color_override("font_color", COL_TEXT)
	btn.text = " " + item.display_name
	btn.clip_text = true
	btn.tooltip_text = "%s\n%s\n%.2f кг" % [item.display_name, item.category_name(), item.weight]
	btn.add_theme_stylebox_override("normal", _box(COL_CELL, COL_LINE_SOFT, 1, 5))
	btn.add_theme_stylebox_override("hover", _box(COL_CELL_HOVER, COL_ACCENT, 1, 5))
	btn.add_theme_stylebox_override("pressed", _box(COL_CELL_HOVER, COL_ACCENT, 2, 5))
	btn.set_drag_forwarding(_catalog_drag.bind(item, btn), Callable(), Callable())
	btn.gui_input.connect(_on_catalog_gui_input.bind(item))
	return btn


func _on_catalog_gui_input(event: InputEvent, item: Item) -> void:
	var click := event as InputEventMouseButton
	if click != null and click.pressed and click.double_click and click.button_index == MOUSE_BUTTON_LEFT:
		_inventory.dev_give(item, item.max_stack)


func _catalog_drag(_at: Vector2, item: Item, source: Control) -> Variant:
	_start_drag_preview(item, source)
	return {"type": DRAG_TYPE, "from": "catalog", "item": item}


func _build_footer() -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	row.add_child(_label("ВЕС", 14, COL_MUTED))

	_weight_bar = ProgressBar.new()
	_weight_bar.custom_minimum_size = Vector2(380, 16)
	_weight_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_weight_bar.show_percentage = false
	_weight_bar.add_theme_stylebox_override("background", _box(COL_CELL, COL_LINE_SOFT, 1))
	_weight_fill = _box(COL_OK, COL_OK, 0)
	_weight_bar.add_theme_stylebox_override("fill", _weight_fill)
	row.add_child(_weight_bar)

	_weight_label = _label("0.0 / 50.0 кг", 16, COL_TEXT)
	row.add_child(_weight_label)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)
	var hint := _label("Перетащить: переместить · G: выбросить · Shift+клик: в слот и обратно", 13, COL_MUTED)
	row.add_child(hint)
	return row


# --- Обновление содержимого -----------------------------------------------

func _refresh() -> void:
	if _inventory == null:
		return
	if _selected >= _inventory.slots.size() or _inventory.is_slot_empty(_selected):
		_selected = -1
	if _selected_eq != &"" and _inventory.get_equipped(_selected_eq) == null:
		_selected_eq = &""

	for child in _grid.get_children():
		_grid.remove_child(child)
		child.queue_free()
	for i in range(_inventory.slots.size()):
		_grid.add_child(_make_cell(i))

	_refresh_equipment()
	_refresh_details()
	_refresh_weight()


## Перестраивает слоты снаряжения: слева основное оружие, по центру броня, справа пистолет.
func _refresh_equipment() -> void:
	for child in _equip_row.get_children():
		_equip_row.remove_child(child)
		child.queue_free()

	var primary := _make_equip_slot(Inventory.SLOT_PRIMARY, EQUIP_SLOT_SIZE)
	var armor := _slot_frame("БРОНЯ", EQUIP_SLOT_SIZE)
	var pistol := _make_equip_slot(Inventory.SLOT_PISTOL, EQUIP_SLOT_SIZE)
	for control: Control in [primary, armor, pistol]:
		control.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		_equip_row.add_child(control)


## Слот снаряжения: пустая рамка (принимает подходящий предмет) или кнопка с предметом.
func _make_equip_slot(slot_name: StringName, min_size: Vector2) -> Control:
	var item := _inventory.get_equipped(slot_name)
	var can_drop := _equip_can_drop.bind(slot_name)
	var drop := _equip_drop.bind(slot_name)

	if item == null:
		var frame := PanelContainer.new()
		frame.custom_minimum_size = min_size
		frame.add_theme_stylebox_override("panel", _box(COL_CELL, COL_LINE_SOFT, 1))
		var title := _label(EQUIP_TITLES[slot_name], 11, COL_MUTED)
		title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		frame.add_child(title)
		frame.set_meta("equip_slot", slot_name)
		frame.set_drag_forwarding(Callable(), can_drop, drop)
		return frame

	var selected := slot_name == _selected_eq
	var btn := Button.new()
	btn.custom_minimum_size = min_size
	btn.focus_mode = Control.FOCUS_NONE
	btn.icon = item.icon
	btn.expand_icon = true
	btn.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	btn.tooltip_text = "%s\n%.2f кг" % [item.display_name, item.weight]
	btn.add_theme_stylebox_override("normal", _box(COL_CELL, COL_ACCENT if selected else COL_LINE, 2 if selected else 1, 5))
	btn.add_theme_stylebox_override("hover", _box(COL_CELL_HOVER, COL_ACCENT, 1, 5))
	btn.add_theme_stylebox_override("pressed", _box(COL_CELL_HOVER, COL_ACCENT, 2, 5))
	btn.pressed.connect(_on_equip_pressed.bind(slot_name))
	btn.set_meta("equip_slot", slot_name)
	btn.set_drag_forwarding(_equip_drag.bind(slot_name, btn), can_drop, drop)

	var key_label := _label(EQUIP_KEYS[slot_name], 12, COL_ACCENT)
	key_label.position = Vector2(6, 2)
	key_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn.add_child(key_label)
	return btn


func _make_cell(index: int) -> Control:
	if _inventory.is_slot_empty(index):
		var empty := Panel.new()
		empty.custom_minimum_size = Vector2(CELL_SIZE, CELL_SIZE)
		empty.add_theme_stylebox_override("panel", _box(COL_PANEL_INNER, COL_LINE_SOFT, 1))
		# В пустую ячейку можно положить перетаскиваемый предмет
		empty.set_drag_forwarding(Callable(), _cell_can_drop.bind(index), _cell_drop.bind(index))
		empty.set_meta("bag_index", index)
		return empty

	var slot: Dictionary = _inventory.slots[index]
	var item: Item = slot["item"]
	var count: int = slot["count"]
	var selected := index == _selected

	var btn := Button.new()
	btn.custom_minimum_size = Vector2(CELL_SIZE, CELL_SIZE)
	btn.focus_mode = Control.FOCUS_NONE
	btn.icon = item.icon
	btn.expand_icon = true
	btn.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	btn.tooltip_text = "%s\n%.2f кг" % [item.display_name, item.weight * count]
	btn.add_theme_stylebox_override("normal", _box(COL_CELL, COL_ACCENT if selected else COL_LINE, 2 if selected else 1, 5))
	btn.add_theme_stylebox_override("hover", _box(COL_CELL_HOVER, COL_ACCENT, 1, 5))
	btn.add_theme_stylebox_override("pressed", _box(COL_CELL_HOVER, COL_ACCENT, 2, 5))
	btn.pressed.connect(_on_cell_pressed.bind(index))
	# Ячейку с предметом можно тащить, а на неё можно бросить другой предмет (слияние или обмен)
	btn.set_drag_forwarding(_cell_drag.bind(index, btn), _cell_can_drop.bind(index), _cell_drop.bind(index))
	btn.set_meta("bag_index", index)

	if count > 1:
		var count_label := _label("%d" % count, 14, COL_TEXT)
		count_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		count_label.offset_right = -5
		count_label.offset_bottom = -2
		count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		count_label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
		count_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		count_label.add_theme_color_override("font_outline_color", Color.BLACK)
		count_label.add_theme_constant_override("outline_size", 4)
		btn.add_child(count_label)
	return btn


func _refresh_details() -> void:
	var item: Item = null
	var count := 1
	var equipped := _selected_eq != &""
	if equipped:
		item = _inventory.get_equipped(_selected_eq)
	elif not _inventory.is_slot_empty(_selected):
		var slot: Dictionary = _inventory.slots[_selected]
		item = slot["item"]
		count = slot["count"]
	if item == null:
		_detail_icon.texture = null
		_detail_name.text = "Выберите предмет"
		_detail_meta.text = ""
		_detail_desc.text = ""
		_use_button.text = "Использовать"
		_use_button.disabled = true
		_drop_button.disabled = true
		return
	_detail_icon.texture = item.icon
	_detail_name.text = item.display_name
	var meta := "%s  ·  %.2f кг" % [item.category_name(), item.weight]
	if count > 1:
		meta += "  ×  %d  =  %.2f кг" % [count, item.weight * count]
	_detail_meta.text = meta
	_detail_desc.text = item.description
	if equipped:
		_use_button.text = "Снять"
	elif item is Weapon:
		_use_button.text = "В слот"
	else:
		_use_button.text = "Использовать"
	_use_button.disabled = not (equipped or item.is_usable())
	_drop_button.disabled = false


func _refresh_weight() -> void:
	var total := _inventory.get_total_weight()
	var maximum := _inventory.max_weight
	_weight_bar.max_value = maximum
	_weight_bar.value = total
	_weight_label.text = "%.1f / %.1f кг" % [total, maximum]
	var ratio := total / maximum if maximum > 0.0 else 0.0
	var color := COL_OK
	if ratio >= 0.85:
		color = COL_BAD
	elif ratio >= 0.6:
		color = COL_WARN
	_weight_fill.bg_color = color
	_weight_fill.border_color = color


# --- Действия -------------------------------------------------------------

func _on_cell_pressed(index: int) -> void:
	# Быстрый перенос: Shift+клик отправляет предмет в подходящий слот снаряжения
	if Input.is_key_pressed(KEY_SHIFT):
		_inventory.equip_from_backpack(index)   # для неподходящих предметов ничего не делает
		return
	_selected = index
	_selected_eq = &""
	_refresh()


func _on_equip_pressed(slot_name: StringName) -> void:
	# Shift+клик по надетому предмету возвращает его в рюкзак
	if Input.is_key_pressed(KEY_SHIFT):
		_inventory.unequip_to_backpack(slot_name)
		return
	_selected_eq = slot_name
	_selected = -1
	_refresh()


func _on_use_pressed() -> void:
	if _selected_eq != &"":
		_inventory.unequip_to_backpack(_selected_eq)
		return
	if _inventory.use_slot(_selected, _player):
		_refresh()


func _on_drop_pressed() -> void:
	if _selected_eq != &"":
		_drop_equipped(_selected_eq)
	else:
		_drop_slot(_selected)


## Клавиша G: выбрасывает предмет под курсором, а если курсор не над ячейкой, выбранный.
func _drop_under_cursor() -> void:
	var hovered := get_viewport().gui_get_hovered_control()
	if hovered != null:
		if hovered.has_meta("slot_frame"):
			return   # курсор над слотом брони или артефакта: выбрасывать нечего
		if hovered.has_meta("bag_index"):
			_drop_slot(int(hovered.get_meta("bag_index")))
			return
		if hovered.has_meta("equip_slot"):
			_drop_equipped(hovered.get_meta("equip_slot") as StringName)
			return
	_on_drop_pressed()


## Выбрасывает всю стопку из ячейки на землю перед игроком.
func _drop_slot(index: int) -> void:
	if _inventory.is_slot_empty(index):
		return
	var slot: Dictionary = _inventory.slots[index]
	var item: Item = slot["item"]
	var count: int = slot["count"]
	_inventory.remove_from_slot(index, count)
	_spawn_drop(item, count)


## Выбрасывает предмет из слота снаряжения.
func _drop_equipped(slot_name: StringName) -> void:
	var item := _inventory.take_equipped(slot_name)
	if item != null:
		_spawn_drop(item, 1)


func _spawn_drop(item: Item, count: int) -> void:
	_inventory.item_dropped.emit(item, count)
	var drop := PICKUP_SCENE.instantiate() as Node3D
	drop.set("item", item)
	drop.set("amount", count)
	get_tree().current_scene.add_child(drop)
	drop.global_position = _drop_position()


func _drop_position() -> Vector3:
	var origin: Vector3 = _player.global_position
	var mesh := _player.get_node_or_null("Mesh") as Node3D
	var forward := -mesh.global_transform.basis.z if mesh != null else Vector3.FORWARD
	# Небольшой разброс, чтобы несколько выброшенных предметов не лежали точно друг в друге
	var jitter := Vector3(randf_range(-0.3, 0.3), 0.0, randf_range(-0.3, 0.3))
	var pos := origin + forward * 1.2 + jitter
	# Опускаем предмет на землю лучом вниз: на склоне он иначе завис бы или ушёл в землю
	var player_body := _player as CharacterBody3D
	if player_body != null:
		var query := PhysicsRayQueryParameters3D.create(pos + Vector3.UP * 1.5, pos + Vector3.DOWN * 3.0, 1)
		query.exclude = [player_body.get_rid()]
		var hit := player_body.get_world_3d().direct_space_state.intersect_ray(query)
		if not hit.is_empty():
			pos.y = hit["position"].y
	return pos


# --- Перетаскивание ---------------------------------------------------------

## Что перетаскивают: {"type", "from": "bag" + "index"} или {"type", "from": "equip" + "slot"}.
func _is_slot_drag(data: Variant) -> bool:
	return data is Dictionary and data.get("type", "") == DRAG_TYPE and _drag_item(data) != null


func _drag_item(data: Dictionary) -> Item:
	if data.get("from", "bag") == "catalog":
		return data["item"] as Item
	if data.get("from", "bag") == "equip":
		return _inventory.get_equipped(data["slot"] as StringName)
	var index := int(data["index"])
	if _inventory.is_slot_empty(index):
		return null
	return _inventory.slots[index]["item"]


## Иконка под курсором во время перетаскивания.
func _start_drag_preview(item: Item, source: Control) -> void:
	var preview := TextureRect.new()
	preview.texture = item.icon
	preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	preview.size = Vector2(CELL_SIZE - 8, CELL_SIZE - 8)
	preview.position = -preview.size * 0.5   # иконка центрируется на курсоре
	preview.modulate = Color(1, 1, 1, 0.85)
	preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var holder := Control.new()
	holder.add_child(preview)
	source.set_drag_preview(holder)


func _cell_drag(_at: Vector2, index: int, source: Control) -> Variant:
	if _inventory.is_slot_empty(index):
		return null
	_start_drag_preview(_inventory.slots[index]["item"], source)
	return {"type": DRAG_TYPE, "from": "bag", "index": index}


func _equip_drag(_at: Vector2, slot_name: StringName, source: Control) -> Variant:
	var item := _inventory.get_equipped(slot_name)
	if item == null:
		return null
	_start_drag_preview(item, source)
	return {"type": DRAG_TYPE, "from": "equip", "slot": slot_name}


func _cell_can_drop(_at: Vector2, data: Variant, index: int) -> bool:
	if not _is_slot_drag(data):
		return false
	if data["from"] == "catalog":
		return true
	if data["from"] == "bag":
		return int(data["index"]) != index
	# Из слота снаряжения: в пустую ячейку, либо в ячейку с предметом того же типа (обмен)
	if _inventory.is_slot_empty(index):
		return true
	var target: Item = _inventory.slots[index]["item"]
	return Inventory.equipment_slot_for(target) == data["slot"]


func _cell_drop(_at: Vector2, data: Variant, index: int) -> void:
	_selected = index   # выделение переходит вместе с предметом
	_selected_eq = &""
	if data["from"] == "catalog":
		_inventory.dev_spawn_into_slot(index, data["item"] as Item)
	elif data["from"] == "bag":
		_inventory.move_slot(int(data["index"]), index)
	elif _inventory.is_slot_empty(index):
		_inventory.unequip_to_backpack(data["slot"] as StringName, index)
	else:
		_inventory.equip_from_backpack(index, data["slot"] as StringName)


## В слот снаряжения принимается только подходящий предмет из рюкзака.
func _equip_can_drop(_at: Vector2, data: Variant, slot_name: StringName) -> bool:
	if not _is_slot_drag(data) or data["from"] == "equip":
		return false
	return Inventory.equipment_slot_for(_drag_item(data)) == slot_name


func _equip_drop(_at: Vector2, data: Variant, slot_name: StringName) -> void:
	_selected = -1
	_selected_eq = slot_name
	if data["from"] == "catalog":
		_inventory.dev_equip(slot_name, data["item"] as Item)
	else:
		_inventory.equip_from_backpack(int(data["index"]), slot_name)


## Выбросить на землю можно только то, что реально лежит у игрока (не из каталога).
func _outside_can_drop(_at: Vector2, data: Variant) -> bool:
	return _is_slot_drag(data) and data["from"] != "catalog"


func _outside_drop(_at: Vector2, data: Variant) -> void:
	if data["from"] == "equip":
		_drop_equipped(data["slot"] as StringName)
	else:
		_drop_slot(int(data["index"]))


# --- Помощники оформления ---------------------------------------------------

func _box(bg: Color, border: Color, border_width: int = 0, margin: float = 0.0) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(border_width)
	if margin > 0.0:
		sb.set_content_margin_all(margin)
	return sb


func _label(text: String, font_size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	return l


func _line() -> Control:
	var r := ColorRect.new()
	r.color = COL_LINE_SOFT
	r.custom_minimum_size = Vector2(0, 1)
	return r


func _slot_frame(text: String, min_size: Vector2) -> Control:
	# Пустая рамка: слоты снаряжения заработают на этапах оружия и артефактов
	var frame := PanelContainer.new()
	frame.custom_minimum_size = min_size
	frame.add_theme_stylebox_override("panel", _box(COL_CELL, COL_LINE_SOFT, 1))
	frame.set_meta("slot_frame", true)
	if text != "":
		var l := _label(text, 12, COL_MUTED)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		frame.add_child(l)
	return frame


func _make_button(text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(0, 36)
	b.add_theme_font_size_override("font_size", 15)
	b.add_theme_color_override("font_color", COL_TEXT)
	b.add_theme_color_override("font_hover_color", COL_ACCENT)
	b.add_theme_color_override("font_disabled_color", Color(0.35, 0.36, 0.34, 1.0))
	b.add_theme_stylebox_override("normal", _box(COL_CELL, COL_LINE, 1, 6))
	b.add_theme_stylebox_override("hover", _box(COL_CELL_HOVER, COL_ACCENT, 1, 6))
	b.add_theme_stylebox_override("pressed", _box(COL_CELL_HOVER, COL_ACCENT, 2, 6))
	b.add_theme_stylebox_override("disabled", _box(COL_PANEL_INNER, COL_LINE_SOFT, 1, 6))
	return b
