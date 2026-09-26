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
	var track := Rect2(margin - 20, y - 16, size.x - margin * 2.0 + 40, 32)
	UiTheme.draw_round_rect(self, track.grow(5), UiTheme.INK, 21)
	UiTheme.draw_round_rect(self, track, Color(1, 1, 1, 0.8), 16)
	var x := lerpf(margin, size.x - margin, (value.x + 1.0) / 2.0)
	var knob := Rect2(x - 90, y - 44, 180, 88)
	UiTheme.draw_round_rect(self, knob.grow(5), UiTheme.INK, 30)
	UiTheme.draw_round_rect(self, knob, color, 26)
	UiTheme.draw_text(self, "Deslizá el dedo de lado a lado", Vector2(size.x / 2.0, size.y - 60), 34, UiTheme.INK, 8, UiTheme.PAPER)
