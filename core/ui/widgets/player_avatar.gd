class_name PlayerAvatar
extends Control
## Mascota del jugador, dibujada por código. Cada lugar (1P–4P) tiene un
## accesorio propio además del color:
##   1P antena · 2P orejas redondas · 3P orejas puntiagudas · 4P brote
##
## Concepto: *no depender solo del color*. Cerca de 1 de cada 12 hombres
## tiene alguna forma de daltonismo; si 1P (rojo) y 4P (verde) se
## distinguieran solo por el color, para esas personas serían iguales.
## Con el accesorio + la etiqueta "1P" se distinguen igual.
##
## Concepto: *squash & stretch* (aplastar y estirar), el principio de
## animación más usado en dibujos animados. Al saltar, el cuerpo se estira
## hacia arriba; al caer, se aplasta y se ensancha, conservando el volumen.
## Ejemplo: en el podio el ganador salta; sin esto parece un recorte que
## sube y baja, con esto parece un personaje con peso.
##
## `draw_mascot` es estática para que los minijuegos (Node2D) dibujen al
## mismo personaje sin instanciar este Control.

enum Mood { NORMAL, HAPPY, SAD, SURPRISED }

@export var color := Color.WHITE
@export var slot := 0
var mood := Mood.NORMAL
var empty := false     ## Lugar libre: silueta sin cara.
var animate := true    ## "Respira", parpadea y mira alrededor (idle).
var hop_height := 0.0  ## 0..1, lo anima hop().
var squash := 0.0      ## >0 aplastado, <0 estirado; lo anima hop().

var _t := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_t = slot * 0.8


func _process(delta: float) -> void:
	if animate and is_visible_in_tree():
		_t += delta
		queue_redraw()


## Salto de festejo con anticipación, estiramiento en el aire y aplastamiento
## al caer.
func hop(times: int = 2) -> void:
	var tw := create_tween()
	for i in times:
		tw.tween_property(self, "squash", 0.25, 0.08)                     # Anticipación: se agacha.
		tw.tween_property(self, "squash", -0.22, 0.06)                    # Despega estirado.
		tw.parallel().tween_property(self, "hop_height", 1.0, 0.2).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tw.tween_property(self, "hop_height", 0.0, 0.24).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		tw.tween_property(self, "squash", 0.3, 0.05)                      # Aterriza aplastado.
		tw.tween_property(self, "squash", 0.0, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _draw() -> void:
	var u := minf(size.x / 80.0, size.y / 112.0)
	var feet := Vector2(size.x / 2.0, size.y - 6.0 * u)
	var bob := sin(_t * 2.4) * 1.3 * u if animate else 0.0
	# Mirada: de vez en cuando mira a un costado (idle), para que no parezca congelado.
	var look := Vector2(sin(_t * 0.7 + slot) * 0.8, 0.0) if animate else Vector2.ZERO
	draw_mascot(self, feet, u, color, slot, mood, bob, hop_height * 20.0 * u, empty, {
		"t": _t, "look": look, "squash": squash,
		"wave": mood == Mood.HAPPY and animate,
	})


## Dibuja la mascota. feet: punto donde apoya. u: unidad de escala (mide ~105u).
## anim (todo opcional):
##   t: segundos (parpadeo, brazos, lágrima) · walk: fase de caminata en
##   vueltas (≥ 0 camina; negativo, quieta) · look: dirección de la mirada
##   (-1..1) · squash: >0 aplastada, <0 estirada · wave: saluda con los brazos.
static func draw_mascot(ci: CanvasItem, feet: Vector2, u: float, col: Color, p_slot: int,
		p_mood: int = Mood.NORMAL, bob: float = 0.0, lift: float = 0.0, is_empty: bool = false,
		anim: Dictionary = {}) -> void:
	var ink := UiTheme.INK
	if is_empty:
		col = Color(1, 1, 1, 0.3)
		ink = Color(1, 1, 1, 0.75)
	var t := float(anim.get("t", 0.0))
	var walk := float(anim.get("walk", -1.0))
	var look: Vector2 = anim.get("look", Vector2.ZERO)
	var sq := clampf(float(anim.get("squash", 0.0)), -0.5, 0.5)
	var wave := bool(anim.get("wave", false))
	var walking := walk >= 0.0

	# La sombra se achica cuando la mascota está en el aire (queda fija en el piso).
	UiTheme.draw_ellipse(ci, feet, 26.0 * u * (1.0 - lift / (80.0 * u)), 5.0 * u, UiTheme.SHADOW)

	# Al caminar, rebota un poco con cada paso.
	var step_bob := absf(sin(walk * TAU)) * 3.0 * u if walking else 0.0
	# Squash & stretch alrededor de los pies: ancho × alto ≈ constante.
	ci.draw_set_transform(feet - Vector2(0, lift + step_bob), 0.0, Vector2(1.0 + sq * 0.6, 1.0 - sq * 0.6))
	var base := Vector2.ZERO
	var head := base + Vector2(0, -52.0 * u + bob)
	var r := 34.0 * u
	var body := Rect2(base.x - 20.0 * u, base.y - 28.0 * u + bob * 0.4, 40.0 * u, 27.0 * u)

	# Pies: se alternan al caminar.
	if not is_empty:
		for side in [-1.0, 1.0]:
			var phase: float = sin(walk * TAU) * side if walking else 0.0
			var foot: Vector2 = base + Vector2(side * 10.0 * u + phase * 3.0 * u, -2.5 * u - maxf(0.0, phase) * 4.0 * u)
			UiTheme.draw_ellipse(ci, foot, 8.5 * u, 5.0 * u, ink)
			UiTheme.draw_ellipse(ci, foot, 6.5 * u, 3.4 * u, col.darkened(0.3))

	# Cuerpo
	UiTheme.draw_round_rect(ci, body.grow(2.5 * u), ink, 13.0 * u)
	UiTheme.draw_round_rect(ci, body, col.darkened(0.1), 12.0 * u)

	# Brazos (delante del cuerpo): colgando, balanceándose al caminar o saludando.
	if not is_empty:
		for side in [-1.0, 1.0]:
			var angle := 0.5
			if wave:
				angle = 2.0 + sin(t * 12.0 + side) * 0.3  # Hacia arriba y afuera: que no lo tape la cabeza.
			elif walking:
				angle = 0.5 + sin(walk * TAU) * side * 0.55
			var shoulder: Vector2 = body.position + Vector2(body.size.x / 2.0 + side * 16.0 * u, 8.0 * u)
			var hand: Vector2 = shoulder + Vector2(side * sin(angle), cos(angle)) * 15.0 * u
			ci.draw_line(shoulder, hand, ink, 8.5 * u, true)
			ci.draw_line(shoulder, hand, col.darkened(0.1), 5.5 * u, true)
			ci.draw_circle(hand, 4.6 * u, ink)
			ci.draw_circle(hand, 3.1 * u, col.lightened(0.15))

	var accessory := p_slot % 4
	# Accesorios que van detrás de la cabeza (se mueven un poco con el paso).
	var sway := sin(walk * TAU) * 0.08 if walking else sin(t * 1.6 + p_slot) * 0.03
	if accessory == 1:
		for sx in [-1.0, 1.0]:
			var ear: Vector2 = head + Vector2(sx * 24.0 * u, -24.0 * u).rotated(sway)
			ci.draw_circle(ear, 12.5 * u, ink)
			ci.draw_circle(ear, 10.0 * u, col)
			if not is_empty:
				ci.draw_circle(ear, 5.5 * u, col.lightened(0.45))
	elif accessory == 2:
		for sx in [-1.0, 1.0]:
			var tri := PackedVector2Array([
				head + Vector2(sx * 31.0 * u, -8.0 * u), head + Vector2(sx * 25.0 * u, -46.0 * u).rotated(sway),
				head + Vector2(sx * 6.0 * u, -30.0 * u)])
			var big := PackedVector2Array()
			var c := (tri[0] + tri[1] + tri[2]) / 3.0
			for p in tri:
				big.append(c + (p - c) * 1.18)
			ci.draw_colored_polygon(big, ink)
			ci.draw_colored_polygon(tri, col)

	# Cabeza y cara
	ci.draw_circle(head, r + 2.5 * u, ink)
	ci.draw_circle(head, r, col)
	if is_empty:
		ci.draw_set_transform(Vector2.ZERO)
		return
	var face := head + Vector2(0, 5.0 * u)
	UiTheme.draw_ellipse(ci, face, 25.0 * u, 21.0 * u, Color.WHITE)
	UiTheme.draw_ellipse(ci, head + Vector2(-12.0 * u, -16.0 * u), 7.0 * u, 4.0 * u, Color(1, 1, 1, 0.35), -0.5)
	var gaze := look.limit_length(1.0) * Vector2(3.0, 2.0) * u
	# Parpadeo cada ~3,3 s, desfasado por jugador para que no parpadeen a la vez.
	var blinking := p_mood == Mood.NORMAL and t > 0.0 and fposmod(t + p_slot * 1.37, 3.3) < 0.12
	for sx in [-1.0, 1.0]:
		var eye: Vector2 = head + Vector2(sx * 9.0 * u, 4.0 * u) + gaze
		match p_mood:
			Mood.HAPPY:
				ci.draw_arc(eye + Vector2(0, 2.5 * u), 5.0 * u, PI * 1.15, PI * 1.85, 10, ink, 2.8 * u, true)
				ci.draw_circle(eye + Vector2(sx * 7.0 * u, 8.0 * u) - gaze, 3.5 * u, Color(1.0, 0.45, 0.55, 0.45))
			Mood.SAD:
				UiTheme.draw_ellipse(ci, eye + Vector2(0, 2.0 * u), 3.0 * u, 4.5 * u, ink)
				ci.draw_line(eye + Vector2(-sx * 5.0 * u, -8.0 * u), eye + Vector2(sx * 4.0 * u, -5.5 * u), ink, 2.2 * u, true)
			Mood.SURPRISED:
				ci.draw_circle(eye, 5.2 * u, ink)
				ci.draw_circle(eye, 3.4 * u, Color.WHITE)
				ci.draw_circle(eye, 2.0 * u, ink)
			_:
				if blinking:
					ci.draw_line(eye + Vector2(-3.8 * u, 0), eye + Vector2(3.8 * u, 0), ink, 2.4 * u, true)
				else:
					UiTheme.draw_ellipse(ci, eye, 3.8 * u, 6.5 * u, ink)
					ci.draw_circle(eye + Vector2(-1.1 * u, -2.6 * u), 1.4 * u, Color.WHITE)

	# Boca según el ánimo
	var mouth := face + Vector2(0, 11.0 * u) + gaze * 0.5
	match p_mood:
		Mood.HAPPY:
			var smile := PackedVector2Array()
			for i in 9:
				var a := PI * i / 8.0
				smile.append(mouth + Vector2(cos(a) * 6.0 * u, sin(a) * 5.0 * u - 1.0 * u))
			ci.draw_colored_polygon(smile, ink)
			ci.draw_circle(mouth + Vector2(0, 2.2 * u), 2.2 * u, Color(1.0, 0.5, 0.55))
		Mood.SAD:
			ci.draw_arc(mouth + Vector2(0, 4.0 * u), 4.5 * u, PI * 1.2, PI * 1.8, 8, ink, 2.2 * u, true)
			# Lágrima que cae y vuelve a empezar.
			var drop := fposmod(t * 0.9, 1.0)
			var tear := head + Vector2(-9.0 * u, 11.0 * u + drop * 12.0 * u) + gaze
			ci.draw_circle(tear, 2.4 * u * (1.0 - drop * 0.4), Color(0.45, 0.75, 1.0, 0.9 * (1.0 - drop)))
		Mood.SURPRISED:
			ci.draw_circle(mouth, 3.6 * u, ink)
			ci.draw_circle(mouth, 2.0 * u, Color(1.0, 0.5, 0.55))

	# Accesorios que van delante / arriba
	if accessory == 0:
		var tip := head + Vector2(7.0 * u, -r - 16.0 * u).rotated(sway * 2.0)
		ci.draw_line(head + Vector2(0, -r + 2.0 * u), tip, ink, 2.8 * u, true)
		ci.draw_circle(tip, 7.0 * u, ink)
		ci.draw_circle(tip, 5.0 * u, col.lightened(0.4))
	elif accessory == 3:
		var stem := head + Vector2(0, -r - 8.0 * u).rotated(sway)
		ci.draw_line(head + Vector2(0, -r + 1.0 * u), stem, ink, 2.8 * u, true)
		for sx in [-1.0, 1.0]:
			var leaf: Vector2 = stem + Vector2(sx * 8.0 * u, -3.0 * u)
			UiTheme.draw_ellipse(ci, leaf, 10.5 * u, 6.0 * u, ink, sx * -0.5 + sway)
			UiTheme.draw_ellipse(ci, leaf, 8.5 * u, 4.2 * u, Color("#8BE36B"), sx * -0.5 + sway)
	ci.draw_set_transform(Vector2.ZERO)
