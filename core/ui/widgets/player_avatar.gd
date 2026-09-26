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
## `draw_mascot` es estática para que los minijuegos (Node2D) dibujen al
## mismo personaje sin instanciar este Control.

enum Mood { NORMAL, HAPPY, SAD }

@export var color := Color.WHITE
@export var slot := 0
var mood := Mood.NORMAL
var empty := false     ## Lugar libre: silueta sin cara.
var animate := true    ## "Respira" suavemente (idle).
var hop_height := 0.0  ## 0..1, lo anima hop().

var _t := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_t = slot * 0.8


func _process(delta: float) -> void:
	if animate:
		_t += delta
		queue_redraw()


## Salto de festejo.
func hop(times: int = 2) -> void:
	var tw := create_tween()
	for i in times:
		tw.tween_property(self, "hop_height", 1.0, 0.2).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tw.tween_property(self, "hop_height", 0.0, 0.24).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)


func _draw() -> void:
	var u := minf(size.x / 80.0, size.y / 112.0)
	var feet := Vector2(size.x / 2.0, size.y - 6.0 * u)
	var bob := sin(_t * 2.4) * 1.3 * u if animate else 0.0
	draw_mascot(self, feet, u, color, slot, mood, bob, hop_height * 20.0 * u, empty)


## feet: punto donde apoya. u: unidad de escala (la mascota mide ~105u).
static func draw_mascot(ci: CanvasItem, feet: Vector2, u: float, col: Color, p_slot: int,
		p_mood: int = Mood.NORMAL, bob: float = 0.0, lift: float = 0.0, is_empty: bool = false) -> void:
	var ink := UiTheme.INK
	if is_empty:
		col = Color(1, 1, 1, 0.3)
		ink = Color(1, 1, 1, 0.75)
	UiTheme.draw_ellipse(ci, feet, 26.0 * u * (1.0 - lift / (80.0 * u)), 5.0 * u, UiTheme.SHADOW)
	var base := feet - Vector2(0, lift)
	var head := base + Vector2(0, -52.0 * u + bob)
	var r := 34.0 * u

	# Cuerpo
	var body := Rect2(base.x - 20.0 * u, base.y - 28.0 * u + bob * 0.4, 40.0 * u, 27.0 * u)
	UiTheme.draw_round_rect(ci, body.grow(2.5 * u), ink, 13.0 * u)
	UiTheme.draw_round_rect(ci, body, col.darkened(0.1), 12.0 * u)

	var accessory := p_slot % 4
	# Accesorios que van detrás de la cabeza
	if accessory == 1:
		for sx in [-1.0, 1.0]:
			var ear: Vector2 = head + Vector2(sx * 24.0 * u, -24.0 * u)
			ci.draw_circle(ear, 12.5 * u, ink)
			ci.draw_circle(ear, 10.0 * u, col)
			if not is_empty:
				ci.draw_circle(ear, 5.5 * u, col.lightened(0.45))
	elif accessory == 2:
		for sx in [-1.0, 1.0]:
			var tri := PackedVector2Array([
				head + Vector2(sx * 31.0 * u, -8.0 * u), head + Vector2(sx * 25.0 * u, -46.0 * u), head + Vector2(sx * 6.0 * u, -30.0 * u)])
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
		return
	UiTheme.draw_ellipse(ci, head + Vector2(0, 5.0 * u), 25.0 * u, 21.0 * u, Color.WHITE)
	UiTheme.draw_ellipse(ci, head + Vector2(-12.0 * u, -16.0 * u), 7.0 * u, 4.0 * u, Color(1, 1, 1, 0.35), -0.5)
	for sx in [-1.0, 1.0]:
		var eye: Vector2 = head + Vector2(sx * 9.0 * u, 4.0 * u)
		match p_mood:
			Mood.HAPPY:
				ci.draw_arc(eye + Vector2(0, 2.5 * u), 5.0 * u, PI * 1.15, PI * 1.85, 10, ink, 2.8 * u, true)
				ci.draw_circle(eye + Vector2(sx * 7.0 * u, 8.0 * u), 3.5 * u, Color(1.0, 0.45, 0.55, 0.45))
			Mood.SAD:
				UiTheme.draw_ellipse(ci, eye + Vector2(0, 2.0 * u), 3.0 * u, 4.5 * u, ink)
				ci.draw_line(eye + Vector2(-sx * 5.0 * u, -8.0 * u), eye + Vector2(sx * 4.0 * u, -5.5 * u), ink, 2.2 * u, true)
			_:
				UiTheme.draw_ellipse(ci, eye, 3.8 * u, 6.5 * u, ink)
				ci.draw_circle(eye + Vector2(-1.1 * u, -2.6 * u), 1.4 * u, Color.WHITE)

	# Accesorios que van delante / arriba
	if accessory == 0:
		var tip := head + Vector2(7.0 * u, -r - 16.0 * u)
		ci.draw_line(head + Vector2(0, -r + 2.0 * u), tip, ink, 2.8 * u, true)
		ci.draw_circle(tip, 7.0 * u, ink)
		ci.draw_circle(tip, 5.0 * u, col.lightened(0.4))
	elif accessory == 3:
		var stem := head + Vector2(0, -r - 8.0 * u)
		ci.draw_line(head + Vector2(0, -r + 1.0 * u), stem, ink, 2.8 * u, true)
		for sx in [-1.0, 1.0]:
			var leaf: Vector2 = stem + Vector2(sx * 8.0 * u, -3.0 * u)
			UiTheme.draw_ellipse(ci, leaf, 10.5 * u, 6.0 * u, ink, sx * -0.5)
			UiTheme.draw_ellipse(ci, leaf, 8.5 * u, 4.2 * u, Color("#8BE36B"), sx * -0.5)
