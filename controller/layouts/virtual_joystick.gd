class_name VirtualJoystick
extends Control
## Joystick táctil. El dedo puede apoyarse en cualquier parte del área:
## ahí aparece la base (joystick "flotante"), más cómodo que uno fijo
## porque no hace falta mirar el celular para encontrarlo.
##
## Se ve como el stick de una consola: base hundida con flechas y una
## perilla con bisel del color del jugador. Al tocarla se aplasta (squash)
## y la flecha hacia donde va se ilumina. value cambia en el mismo evento
## táctil: la animación es solo visual y no agrega latencia.

const DEAD_ZONE := 0.12

@export var radius := 140.0
@export var color := Color.WHITE

## Dirección actual, -1..1 en cada eje. Vector2.ZERO si no hay dedo.
var value := Vector2.ZERO

var _touch_index := -1
var _origin := Vector2.ZERO
var _knob := Vector2.ZERO
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
			_origin = t.position
			_knob = t.position
			_animate(true)
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
	var was_active := _touch_index != -1
	_touch_index = -1
	value = Vector2.ZERO
	if was_active:
		_animate(false)
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
	var active := _touch_index != -1
	var c := _origin if active else size / 2.0
	var knob := _knob if active else c
	var knob_r := radius * 0.56
	var dish := radius + knob_r * 0.45
	var line := maxf(6.0, radius * 0.045)
	# Base hundida: sombra, aro de tinta, hueco oscuro y aro interno.
	var base := UiTheme.ShapeBatch.new()
	base.circle(c + Vector2(0, 14), dish + line + 6.0, UiTheme.SHADOW)
	base.circle(c, dish + line, UiTheme.INK)
	base.circle(c, dish, UiTheme.PHONE_DISH)
	base.circle(c, dish - line * 1.6, UiTheme.PHONE_DISH_RIM)
	base.circle(c + Vector2(0, line * 0.8), dish - line * 2.4, UiTheme.PHONE_DISH)
	# Flechas de dirección alrededor de la base; se ilumina la del dedo.
	for dir: Vector2 in [Vector2.UP, Vector2.RIGHT, Vector2.DOWN, Vector2.LEFT]:
		var lit := active and value.length() > 0.0 and value.normalized().dot(dir) > 0.7
		var tip := c + dir * (dish + line + radius * 0.22)
		base.polygon(_arrow_points(tip, radius * 0.3, dir), UiTheme.INK)
		base.polygon(_arrow_points(tip, radius * 0.22, dir), UiTheme.ACCENT if lit else UiTheme.PAPER)
	# Sombra de la perilla corrida hacia donde se inclina: da sensación de altura.
	var lean := (knob - c) / maxf(radius, 1.0)
	base.ellipse(knob + Vector2(lean.x * 10.0, knob_r * 0.35 + 8.0), knob_r * 1.05, knob_r * 0.7, UiTheme.SHADOW)
	base.flush(self)
	UiTheme.draw_toy_disc(self, knob - Vector2(0, knob_r * 0.12), knob_r, color if active else color.lerp(UiTheme.PAPER, 0.15),
		_press, knob_r * 0.24)
	if not active:
		var hint := "Arrastrá en cualquier lugar"
		var hint_w := UiTheme.FONT_BOLD.get_string_size(hint, HORIZONTAL_ALIGNMENT_LEFT, -1, 34).x
		var pill := Rect2(size.x / 2.0 - hint_w / 2.0 - 36.0, size.y - 100.0, hint_w + 72.0, 72.0)
		UiTheme.draw_round_rect(self, pill, UiTheme.PHONE_GLASS, 36.0)
		UiTheme.draw_text(self, hint, pill.get_center(), 34, UiTheme.INK)


## Mismo triángulo que UiTheme.draw_arrow, para meterlo en el lote.
static func _arrow_points(center: Vector2, s: float, dir: Vector2) -> PackedVector2Array:
	var n := Vector2(-dir.y, dir.x)
	return PackedVector2Array([
		center + dir * s * 0.6, center - dir * s * 0.4 + n * s * 0.55, center - dir * s * 0.4 - n * s * 0.55,
	])
