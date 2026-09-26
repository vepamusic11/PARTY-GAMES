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
	# Botón de arcade: base oscura fija y tapa de color que "baja" al apretar.
	var r := minf(size.x, size.y) * 0.38
	var c := size / 2.0
	var depth := r * (0.04 if pressed else 0.14)
	draw_circle(c + Vector2(0, r * 0.14), r + 8.0, UiTheme.INK)
	draw_circle(c + Vector2(0, r * 0.14), r, color.darkened(0.35))
	draw_circle(c + Vector2(0, r * 0.14 - depth), r + 8.0, UiTheme.INK)
	draw_circle(c + Vector2(0, r * 0.14 - depth), r, color)
	draw_circle(c + Vector2(-r * 0.3, r * 0.14 - depth - r * 0.3), r * 0.22, Color(1, 1, 1, 0.3))
	UiTheme.draw_text(self, label, c + Vector2(0, r * 0.14 - depth), int(r * 0.34), UiTheme.PAPER, maxi(6, int(r * 0.05)), UiTheme.INK)
