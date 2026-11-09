class_name Crosshair
extends Control
## Прицел в центре экрана: четыре чёрточки и точка. При попадании на мгновение краснеет.

var _flash: float = 0.0
var _flash_kill: bool = false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func flash(killed: bool) -> void:
	_flash = 0.15
	_flash_kill = killed
	queue_redraw()


func _process(delta: float) -> void:
	if _flash > 0.0:
		_flash = maxf(_flash - delta, 0.0)
		queue_redraw()


func _draw() -> void:
	var c := size * 0.5
	var color := Color(1, 1, 1, 0.9)
	if _flash > 0.0:
		color = Color(1.0, 0.2, 0.15, 1.0) if _flash_kill else Color(1.0, 0.85, 0.2, 1.0)
	var gap := 6.0
	var length := 9.0
	for dir: Vector2 in [Vector2.LEFT, Vector2.RIGHT, Vector2.UP, Vector2.DOWN]:
		var a := c + dir * gap
		var b := c + dir * (gap + length)
		draw_line(a, b, Color(0, 0, 0, 0.7), 4.0)
		draw_line(a, b, color, 2.0)
	draw_circle(c, 2.0, Color(0, 0, 0, 0.7))
	draw_circle(c, 1.2, color)
