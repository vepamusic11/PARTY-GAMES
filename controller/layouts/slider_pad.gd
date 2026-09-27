class_name SliderPad
extends Control
## Slider horizontal de control absoluto: la posición del dedo en el ancho
## de la pantalla es la posición de la paleta. value.x va de -1 a 1.
## Al soltar, el valor se queda donde estaba (la paleta no vuelve al centro).
##
## Se ve como el fader de una consola: canal hundido con marcas, flechas en
## las puntas y una perilla con bisel del color del jugador que se aplasta
## al tocarla (solo visual: value cambia en el mismo evento táctil).

@export var color := Color.WHITE
## Tamaño elegido en Ajustes: agranda o achica la perilla (el recorrido
## sigue siendo todo el ancho). Zurdo no cambia nada: es simétrico.
@export var control_scale := 1.0:
	set(v):
		control_scale = v
		queue_redraw()

var value := Vector2.ZERO
var _touch_index := -1
## 0..1: perilla apretada (animado).
var _press := 0.0:
	set(v):
		_press = v
		queue_redraw()
var _tween: Tween


func _gui_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		var t := event as InputEventScreenTouch
		if t.pressed and _touch_index == -1:
			_touch_index = t.index
			_set_from(t.position)
			_animate(true)
			accept_event()
		elif not t.pressed and t.index == _touch_index:
			_touch_index = -1
			_animate(false)
			accept_event()
	elif event is InputEventScreenDrag:
		var d := event as InputEventScreenDrag
		if d.index == _touch_index:
			_set_from(d.position)
			accept_event()


func _notification(what: int) -> void:
	if (what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_VISIBILITY_CHANGED) and _touch_index != -1:
		_touch_index = -1
		_animate(false)


func _set_from(pos: Vector2) -> void:
	var margin := size.x * 0.08
	var t := clampf((pos.x - margin) / maxf(size.x - margin * 2.0, 1.0), 0.0, 1.0)
	value = Vector2(t * 2.0 - 1.0, 0.0)
	queue_redraw()


func _animate(down: bool) -> void:
	if not is_inside_tree():
		_press = 1.0 if down else 0.0
		return
	if _tween:
		_tween.kill()
	_tween = create_tween()
	if down:
		_tween.tween_property(self, "_press", 1.0, 0.05)
	else:
		_tween.tween_property(self, "_press", 0.0, 0.24).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _draw() -> void:
	var margin := size.x * 0.08
	var y := size.y * 0.46
	var x := lerpf(margin, size.x - margin, (value.x + 1.0) / 2.0)
	# Canal hundido: tinta, hueco oscuro y aro interno.
	var track := Rect2(margin - 40.0, y - 34.0, size.x - margin * 2.0 + 80.0, 68.0)
	UiTheme.draw_round_rect(self, track.grow(8), UiTheme.INK, 42.0, 0.0, UiTheme.INK, true)
	UiTheme.draw_round_rect(self, track, UiTheme.PHONE_DISH, 34.0)
	UiTheme.draw_round_rect(self, Rect2(track.position + Vector2(10, 8), Vector2(track.size.x - 20, 10)), UiTheme.PHONE_DISH_RIM, 5.0)
	# Recorrido hecho, en el color del jugador (dónde está la paleta de un vistazo).
	var fill := Rect2(track.position + Vector2(14, 22), Vector2(maxf(x - track.position.x - 14.0, 0.0), track.size.y - 36.0))
	UiTheme.draw_round_rect(self, fill, Color(color, 0.55), 16.0)
	# Marcas cada cuarto, más largas en el centro.
	for i in 5:
		var mx := lerpf(margin, size.x - margin, i / 4.0)
		var h := 64.0 if i == 2 else 40.0
		draw_line(Vector2(mx, y + 60.0), Vector2(mx, y + 60.0 + h), Color(UiTheme.INK, 0.45), 8.0, true)
	for dir: Vector2 in [Vector2.LEFT, Vector2.RIGHT]:
		var tip := Vector2(size.x / 2.0 + dir.x * (size.x / 2.0 - margin + 80.0), y)
		UiTheme.draw_arrow(self, tip + Vector2(0, 5), 64.0, dir, UiTheme.INK)
		UiTheme.draw_arrow(self, tip, 56.0, dir, UiTheme.PAPER)
	# Perilla: tecla de juguete con estrías para "agarrarla"; se ensancha al tocarla.
	var w := 230.0 * control_scale * (1.0 + UiTheme.PHONE_PRESS_SQUASH * _press)
	var h := 170.0 * control_scale * (1.0 - UiTheme.PHONE_PRESS_SQUASH * _press)
	var knob := Rect2(x - w / 2.0, y + 80.0 - h, w, h)  # Apoyada abajo: se aplasta hacia el canal.
	var face := UiTheme.draw_toy_key(self, knob, color, _press, 34.0, 18.0, 6.0)
	for k: int in [-1, 0, 1]:
		var gx := face.get_center().x + k * 30.0
		draw_line(Vector2(gx, face.position.y + face.size.y * 0.28), Vector2(gx, face.end.y - face.size.y * 0.24),
			Color(UiTheme.INK, 0.35), 9.0, true)
	var hint := "Deslizá el dedo de lado a lado"
	var hint_w := UiTheme.FONT_BOLD.get_string_size(hint, HORIZONTAL_ALIGNMENT_LEFT, -1, 34).x
	var pill := Rect2(size.x / 2.0 - hint_w / 2.0 - 36.0, size.y - 110.0, hint_w + 72.0, 72.0)
	UiTheme.draw_round_rect(self, pill, UiTheme.PHONE_GLASS, 36.0)
	UiTheme.draw_text(self, hint, pill.get_center(), 34, UiTheme.INK)
