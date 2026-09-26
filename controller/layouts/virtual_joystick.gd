class_name VirtualJoystick
extends Control
## Joystick táctil. El dedo puede apoyarse en cualquier parte del área:
## ahí aparece la base (joystick "flotante"), más cómodo que uno fijo
## porque no hace falta mirar el celular para encontrarlo.

const DEAD_ZONE := 0.12

@export var radius := 140.0
@export var color := Color.WHITE

## Dirección actual, -1..1 en cada eje. Vector2.ZERO si no hay dedo.
var value := Vector2.ZERO

var _touch_index := -1
var _origin := Vector2.ZERO
var _knob := Vector2.ZERO


func _gui_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		var t := event as InputEventScreenTouch
		if t.pressed and _touch_index == -1:
			_touch_index = t.index
			_origin = t.position
			_knob = t.position
			accept_event()
		elif not t.pressed and t.index == _touch_index:
			_release()
			accept_event()
	elif event is InputEventScreenDrag:
		var d := event as InputEventScreenDrag
		if d.index == _touch_index:
			_knob = _origin + (d.position - _origin).limit_length(radius)
			var raw := (_knob - _origin) / radius
			value = raw if raw.length() > DEAD_ZONE else Vector2.ZERO
			queue_redraw()
			accept_event()


func _notification(what: int) -> void:
	# La app pasó a segundo plano: soltar para no dejar al personaje caminando solo.
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_VISIBILITY_CHANGED:
		_release()


func _release() -> void:
	_touch_index = -1
	value = Vector2.ZERO
	queue_redraw()


func _draw() -> void:
	var active := _touch_index != -1
	var c := _origin if active else size / 2.0
	var knob := _knob if active else c
	draw_circle(c, radius + 5.0, Color(UiTheme.INK, 0.8 if active else 0.35))
	draw_circle(c, radius, Color(1, 1, 1, 0.55 if active else 0.3))
	draw_circle(knob, radius * 0.42 + 5.0, UiTheme.INK)
	draw_circle(knob, radius * 0.42, color if active else Color(color, 0.7))
	draw_circle(knob + Vector2(-radius * 0.12, -radius * 0.12), radius * 0.14, Color(1, 1, 1, 0.45))
	if not active:
		UiTheme.draw_text(self, "Arrastrá en cualquier lugar", Vector2(size.x / 2.0, size.y - 40), 34, UiTheme.INK, 8, UiTheme.PAPER)
