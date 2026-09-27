class_name BigButton
extends Control
## Un solo botón gigante que ocupa toda el área. Soporta multitouch:
## sigue "apretado" mientras quede al menos un dedo encima.
##
## Se ve como un botón de arcade con el color del jugador: aro de tinta,
## bisel, brillo y sombra. Al tocarlo la tapa baja y se aplasta (squash) y
## sale una onda; al soltar rebota. `pressed` cambia en el mismo evento
## táctil: la animación es solo visual y no agrega latencia.

@export var color := Color.WHITE
@export var label := "A"

var pressed := false
var _touches: Dictionary = {}
## 0..1: cuánto está hundida la tapa (animado).
var _press := 0.0:
	set(v):
		_press = v
		queue_redraw()
## 0..1: onda que se expande al apretar (1 = terminada).
var _ripple := 1.0:
	set(v):
		_ripple = v
		queue_redraw()
var _tween: Tween


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
			Haptics.buzz("tap")
			Sfx.play("tap")
		_animate()


func _animate() -> void:
	if not is_inside_tree():
		_press = 1.0 if pressed else 0.0
		return
	if _tween:
		_tween.kill()
	_tween = create_tween()
	if pressed:
		_tween.tween_property(self, "_press", 1.0, 0.04)
		_ripple = 0.0
		_tween.parallel().tween_property(self, "_ripple", 1.0, 0.35).set_ease(Tween.EASE_OUT)
	else:
		_tween.tween_property(self, "_press", 0.0, 0.24).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _draw() -> void:
	var r := minf(size.x, size.y) * 0.36
	var c := size / 2.0 - Vector2(0, r * 0.06)
	var line := maxf(6.0, r * 0.04)
	# Carcasa: aro oscuro hundido alrededor del botón (como en un arcade).
	var housing := UiTheme.ShapeBatch.new()
	housing.circle(c + Vector2(0, r * 0.2), r * 1.24, UiTheme.SHADOW)
	housing.circle(c + Vector2(0, r * 0.12), r * 1.2 + line, UiTheme.INK)
	housing.circle(c + Vector2(0, r * 0.12), r * 1.2, UiTheme.PHONE_DISH)
	housing.circle(c + Vector2(0, r * 0.12), r * 1.12, UiTheme.PHONE_DISH_RIM)
	housing.circle(c + Vector2(0, r * 0.16), r * 1.07, UiTheme.PHONE_DISH)
	housing.flush(self)
	if _ripple < 1.0:
		draw_arc(c + Vector2(0, r * 0.12), r * (1.2 + 0.35 * _ripple), 0, TAU, 64,
			Color(color.lerp(UiTheme.PAPER, 0.4), 0.8 * (1.0 - _ripple)), line * 2.0 * (1.0 - _ripple) + 2.0, true)
	var face := UiTheme.draw_toy_disc(self, c, r, color, _press, r * 0.14)
	# Texto de la tapa: blanco con contorno, legible sobre cualquier color.
	var fs := int(r * (0.4 if label.length() <= 2 else 0.3))
	UiTheme.draw_text(self, label, face + Vector2(0, maxf(3.0, fs / 16.0)), fs, UiTheme.SHADOW, maxi(6, int(r * 0.05)), UiTheme.SHADOW)
	UiTheme.draw_text(self, label, face, fs, UiTheme.PAPER, maxi(6, int(r * 0.05)), UiTheme.INK)
