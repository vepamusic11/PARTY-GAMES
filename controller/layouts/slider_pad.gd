class_name SliderPad
extends Control
## Slider horizontal de control absoluto: la posición del dedo en el ancho
## de la pantalla es la posición de la paleta. value.x va de -1 a 1.
## Al soltar, el valor se queda donde estaba (la paleta no vuelve al centro).

@export var color := Color.WHITE

var value := Vector2.ZERO
var _touch_index := -1


func _gui_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		var t := event as InputEventScreenTouch
		if t.pressed and _touch_index == -1:
			_touch_index = t.index
			_set_from(t.position)
			accept_event()
		elif not t.pressed and t.index == _touch_index:
			_touch_index = -1
			accept_event()
	elif event is InputEventScreenDrag:
		var d := event as InputEventScreenDrag
		if d.index == _touch_index:
			_set_from(d.position)
			accept_event()


func _set_from(pos: Vector2) -> void:
	var margin := size.x * 0.08
	var t := clampf((pos.x - margin) / maxf(size.x - margin * 2.0, 1.0), 0.0, 1.0)
	value = Vector2(t * 2.0 - 1.0, 0.0)
	queue_redraw()


func _draw() -> void:
	var margin := size.x * 0.08
	var y := size.y / 2.0
	draw_line(Vector2(margin, y), Vector2(size.x - margin, y), Color(color, 0.4), 10.0)
	var x := lerpf(margin, size.x - margin, (value.x + 1.0) / 2.0)
	draw_rect(Rect2(x - 90, y - 40, 180, 80), color)
