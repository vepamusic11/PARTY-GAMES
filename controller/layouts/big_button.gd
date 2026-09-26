class_name BigButton
extends Control
## Un solo botón gigante que ocupa toda el área. Soporta multitouch:
## sigue "apretado" mientras quede al menos un dedo encima.

@export var color := Color.WHITE
@export var label := "A"

var pressed := false
var _touches: Dictionary = {}


func _gui_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		var t := event as InputEventScreenTouch
		if t.pressed:
			_touches[t.index] = true
		else:
			_touches.erase(t.index)
		_update()
		accept_event()


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_VISIBILITY_CHANGED:
		_touches.clear()
		_update()


func _update() -> void:
	var now_pressed := not _touches.is_empty()
	if now_pressed != pressed:
		pressed = now_pressed
		if pressed:
			Input.vibrate_handheld(15)
		queue_redraw()


func _draw() -> void:
	var r := minf(size.x, size.y) * (0.36 if pressed else 0.4)
	draw_circle(size / 2.0, r, color if pressed else Color(color, 0.75))
	var font := ThemeDB.fallback_font
	var fs := int(r * 0.35)
	var w := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	draw_string(font, size / 2.0 + Vector2(-w / 2.0, fs / 3.0), label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color.BLACK)
