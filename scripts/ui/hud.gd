extends CanvasLayer
## HUD: полоски здоровья, выносливости и радиации, подсказка [E] и уведомления о предметах.
## Подключается к узлу из группы "player" и слушает его сигналы.

@onready var hp_bar: ProgressBar = $Root/Bars/HpBar
@onready var hp_label: Label = $Root/Bars/HpBar/Label
@onready var stamina_bar: ProgressBar = $Root/Bars/StaminaBar
@onready var stamina_label: Label = $Root/Bars/StaminaBar/Label
@onready var rad_bar: ProgressBar = $Root/Bars/RadBar
@onready var rad_label: Label = $Root/Bars/RadBar/Label
@onready var prompt_label: Label = $Root/Prompt
@onready var notifications: VBoxContainer = $Root/Notifications

var _crosshair: Crosshair
var _weapon_box: VBoxContainer
var _weapon_name: Label
var _ammo_label: Label
var _mode_label: Label

var _player_ref: Node
var _armed: bool = false
var _aiming: bool = false


func _ready() -> void:
	_build_weapon_ui()
	# Откладываем на конец кадра: игрок к этому моменту точно в дереве и в группе
	call_deferred("_connect_player")


func _connect_player() -> void:
	var player := get_tree().get_first_node_in_group("player")
	if player == null:
		push_warning("HUD: игрок не найден (группа 'player')")
		return
	_player_ref = player
	player.connect("health_changed", _on_health_changed)
	player.connect("stamina_changed", _on_stamina_changed)
	_on_health_changed(player.get("health"), player.get("max_health"))
	_on_stamina_changed(player.get("stamina"), player.get("max_stamina"))
	player.connect("radiation_changed", _on_radiation_changed)
	_on_radiation_changed(player.get("radiation"), player.get("max_radiation"), 0.0)

	var weapons := player.get_node_or_null("WeaponController")
	if weapons != null:
		weapons.connect("weapon_changed", _on_weapon_changed)
		weapons.connect("aim_changed", _on_aim_changed)
		weapons.connect("ammo_changed", _on_ammo_changed)
		weapons.connect("reload_started", _on_reload_started)
		weapons.connect("hit_confirmed", _on_hit_confirmed)
		weapons.connect("notice", _on_weapon_notice)

	var interactor := player.get_node_or_null("InteractionArea")
	if interactor != null:
		interactor.connect("focus_changed", _on_focus_changed)
	var inventory := player.get_node_or_null("Inventory")
	if inventory != null:
		inventory.connect("item_added", _on_item_added)
		inventory.connect("rejected", _on_item_rejected)
		inventory.connect("item_dropped", _on_item_dropped)


func _on_health_changed(current: float, maximum: float) -> void:
	hp_bar.max_value = maximum
	hp_bar.value = current
	hp_label.text = "HP  %d / %d" % [roundi(current), roundi(maximum)]


func _on_stamina_changed(current: float, maximum: float) -> void:
	stamina_bar.max_value = maximum
	stamina_bar.value = current
	stamina_label.text = "ВЫНОСЛИВОСТЬ  %d / %d" % [roundi(current), roundi(maximum)]


func _on_radiation_changed(current: float, maximum: float, exposure: float) -> void:
	rad_bar.max_value = maximum
	rad_bar.value = current
	rad_bar.visible = current > 0.01 or exposure > 0.0
	var text := "ЛУЧЕВАЯ БОЛЕЗНЬ  %d / %d" % [roundi(current), roundi(maximum)]
	if exposure > 0.0:
		text += "   (+%.1f/с)" % exposure
	rad_label.text = text


## Прицел и панель патронов справа внизу. Строятся кодом и скрыты, пока оружия нет в руках.
func _build_weapon_ui() -> void:
	var root := $Root as Control

	_crosshair = Crosshair.new()
	_crosshair.visible = false
	root.add_child(_crosshair)

	_weapon_box = VBoxContainer.new()
	_weapon_box.visible = false
	_weapon_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_weapon_box.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_weapon_box.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_weapon_box.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_weapon_box.offset_right = -24.0
	_weapon_box.offset_bottom = -24.0
	_weapon_box.add_theme_constant_override("separation", 0)
	root.add_child(_weapon_box)

	_weapon_name = _make_weapon_label(16, Color(0.82, 0.82, 0.76))
	_ammo_label = _make_weapon_label(34, Color(0.95, 0.8, 0.3))
	_mode_label = _make_weapon_label(14, Color(0.7, 0.72, 0.68))


func _make_weapon_label(font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 6)
	_weapon_box.add_child(label)
	return label


func _on_weapon_changed(weapon: Weapon) -> void:
	_armed = weapon != null
	if _armed:
		_weapon_name.text = weapon.display_name
	_apply_weapon_ui()


func _on_aim_changed(aiming: bool) -> void:
	_aiming = aiming
	_apply_weapon_ui()


## Что показывать из оружейного интерфейса. От первого лица при прицеливании
## прицел убирается (целишься по мушке).
func _apply_weapon_ui() -> void:
	var first_person := _player_ref != null and bool(_player_ref.call("is_first_person"))
	_crosshair.visible = _armed and not (_aiming and first_person)
	_weapon_box.visible = _armed


func _on_ammo_changed(in_magazine: int, reserve: int, mode_text: String) -> void:
	if mode_text == "БЛИЖНИЙ БОЙ":
		_ammo_label.text = " "
		_mode_label.text = mode_text
		return
	_ammo_label.text = "%d / %d" % [in_magazine, reserve]
	_ammo_label.add_theme_color_override(
		"font_color", Color(0.95, 0.8, 0.3) if in_magazine > 0 else Color(0.9, 0.3, 0.22)
	)
	_mode_label.text = mode_text


func _on_reload_started(_duration: float) -> void:
	_ammo_label.text = "ПЕРЕЗАРЯДКА"
	_ammo_label.add_theme_color_override("font_color", Color(0.75, 0.75, 0.7))


func _on_hit_confirmed(killed: bool) -> void:
	_crosshair.flash(killed)


func _on_weapon_notice(text: String) -> void:
	_notify(text, Color(0.85, 0.3, 0.22, 1.0))


func _on_focus_changed(target: Node3D) -> void:
	if target == null or not is_instance_valid(target) or not target.has_method("get_prompt"):
		prompt_label.visible = false
		return
	prompt_label.text = "[E]  %s" % target.call("get_prompt")
	prompt_label.visible = true


func _on_item_added(item: Item, amount: int) -> void:
	var text := "Подобрано: %s" % item.display_name
	if amount > 1:
		text += " ×%d" % amount
	_notify(text, Color(0.88, 0.63, 0.18, 1.0))


func _on_item_dropped(item: Item, amount: int) -> void:
	var text := "Выброшено: %s" % item.display_name
	if amount > 1:
		text += " ×%d" % amount
	_notify(text, Color(0.72, 0.72, 0.68, 1.0))


func _on_item_rejected(item: Item, reason: String) -> void:
	_notify("%s: %s" % [item.display_name, reason], Color(0.85, 0.3, 0.22, 1.0))


func _notify(text: String, color: Color) -> void:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	label.add_theme_font_size_override("font_size", 16)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 5)
	notifications.add_child(label)

	var tween := create_tween()
	tween.tween_interval(2.5)
	tween.tween_property(label, "modulate:a", 0.0, 0.6)
	tween.tween_callback(label.queue_free)
