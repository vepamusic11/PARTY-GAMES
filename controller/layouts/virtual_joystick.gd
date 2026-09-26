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
	if _touch_index == -1:
		var c := size / 2.0
		draw_arc(c, radius, 0, TAU, 64, Color(color, 0.35), 4.0)
		draw_circle(c, radius * 0.4, Color(color, 0.35))
		return
	draw_circle(_origin, radius, Color(color, 0.15))
	draw_arc(_origin, radius, 0, TAU, 64, Color(color, 0.6), 4.0)
	draw_circle(_knob, radius * 0.4, color)
