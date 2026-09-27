class_name PlayerAvatar
extends Control
## Mascota del jugador, dibujada por código. Cada jugador elige desde el
## celular su color y su estilo (accesorio: antena, oso, gato, brote, robot,
## diablito, conejo; ver STYLE_NAMES y docs/adr/0007). Si no elige, su lugar
## da el clásico:
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
## Estilo elegido desde el celular (índice de STYLE_NAMES). -1 = el clásico
## del lugar (slot). Ver style_of().
@export var style := -1:
	set(v):
		style = v
		queue_redraw()
var mood := Mood.NORMAL
var empty := false     ## Lugar libre: silueta sin cara.
var animate := true:   ## "Respira", parpadea y mira alrededor (idle).
	set(v):
		animate = v
		_update_processing()
		queue_redraw()
## 0..1, lo anima hop(). hop_height y squash redibujan al cambiar: el salto
## se ve fluido aunque el idle vaya a menos cuadros por segundo (anim_fps).
var hop_height := 0.0:
	set(v):
		hop_height = v
		queue_redraw()
var squash := 0.0:     ## >0 aplastado, <0 estirado; lo anima hop().
	set(v):
		squash = v
		queue_redraw()
## Cuadros por segundo del idle (respirar, mirar, parpadear, saludar).
## 0 = en cada frame (TV). El celular lo baja mientras espera (ver
## PartyBackground.anim_fps).
var anim_fps := 0.0

var _t := 0.0
var _anim_slot := -1


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_t = slot * 0.8
	_update_processing()


func _notification(what: int) -> void:
	# Oculta (pantalla que no se ve) no anima: ni siquiera corre _process.
	if what == NOTIFICATION_VISIBILITY_CHANGED:
		_update_processing()


func _update_processing() -> void:
	if is_inside_tree():
		set_process(animate and is_visible_in_tree())


func _process(delta: float) -> void:
	_t += delta
	if anim_fps <= 0.0:
		queue_redraw()
		return
	# Reloj común: varios nodos con el mismo anim_fps se redibujan en el mismo frame.
	var anim_slot := int(Time.get_ticks_msec() * anim_fps / 1000.0)
	if anim_slot != _anim_slot:
		_anim_slot = anim_slot
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
	draw_mascot(self, feet, u, color, slot if style < 0 else style, mood, bob, hop_height * 20.0 * u, empty, {
		"t": _t, "look": look, "squash": squash,
		"wave": mood == Mood.HAPPY and animate,
	})


## Estilos de mascota (accesorio). Los 4 primeros son los de siempre por
## lugar (1P–4P); el resto se elige desde el celular.
const STYLE_NAMES: Array[String] = ["Antena", "Oso", "Gato", "Brote", "Robot", "Diablito", "Conejo"]
const STYLE_ROBOT := 4
const STYLE_HORNS := 5
const STYLE_BUNNY := 6
const METAL := Color("#C3CADB")   ## Piezas de metal del robot.
const BLUSH := Color(1.0, 0.45, 0.55, 0.45)
const TONGUE := Color(1.0, 0.5, 0.55)
const TEAR := Color(0.45, 0.75, 1.0, 0.9)


## Estilo de mascota de un jugador (dict de HostServer.get_players() o de
## las tablas del torneo). Si no trae "style" (datos viejos, pruebas), usa el
## clásico de su lugar: 1P antena, 2P oso… Siempre devuelve un índice válido.
static func style_of(p: Dictionary) -> int:
	var raw: Variant = p.get("style", p.get("slot", 0))
	var s := int(raw) if typeof(raw) == TYPE_INT or typeof(raw) == TYPE_FLOAT else 0
	return posmod(s, STYLE_NAMES.size())


## Dibuja la mascota. feet: punto donde apoya. u: unidad de escala (mide ~105u).
## p_style: estilo (índice de STYLE_NAMES; si se pasa el lugar 0–3, da el
## accesorio clásico de 1P–4P).
## anim (todo opcional):
##   t: segundos (parpadeo, brazos, lágrima) · walk: fase de caminata en
##   vueltas (≥ 0 camina; negativo, quieta) · look: dirección de la mirada
##   (-1..1) · squash: >0 aplastada, <0 estirada · wave: saluda con los brazos.
##
## Concepto: *volumen con luz*. Para que un círculo plano parezca una esfera
## de juguete se apilan 4 capas: sombra (color oscurecido), volumen (el color,
## corrido hacia la luz), luz suave y un brillo especular chico y blanco. Es
## el mismo truco de los personajes "de plástico" de los party games.
##
## Rendimiento: círculos, elipses y polígonos consecutivos van en un
## UiTheme.ShapeBatch (un draw call por tramo). Antes de cada figura que no va
## en lote (rectángulos redondeados, líneas, arcos) se hace flush, así el
## orden de dibujo se respeta.
static func draw_mascot(ci: CanvasItem, feet: Vector2, u: float, col: Color, p_style: int,
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
	# Transformación que ya tenía el lienzo (ej. la mascota que cae girando en
	# Empujones): el squash se compone encima y al final se restaura, en vez
	# de volver a la identidad y dibujar el resto en la esquina.
	var outer: Transform2D = anim.get("xform", Transform2D.IDENTITY)
	var walking := walk >= 0.0
	var style := posmod(p_style, STYLE_NAMES.size())
	# Colores oscuros (negro, azul noche) necesitan más luz para leerse.
	var dark := col.get_luminance() < 0.2
	var shade := col.darkened(0.12 if dark else 0.24)
	var light := col.lightened(0.5 if dark else 0.35)
	var batch := UiTheme.ShapeBatch.new()

	# La sombra se achica cuando la mascota está en el aire (queda fija en el piso).
	batch.ellipse(feet, 26.0 * u * (1.0 - lift / (80.0 * u)), 5.0 * u, UiTheme.SHADOW)
	batch.flush(ci)  # La sombra va sin el transform de squash.

	# Al caminar, rebota un poco con cada paso.
	var step_bob := absf(sin(walk * TAU)) * 3.0 * u if walking else 0.0
	# Squash & stretch alrededor de los pies: ancho × alto ≈ constante.
	ci.draw_set_transform_matrix(outer * Transform2D(0.0, Vector2(1.0 + sq * 0.6, 1.0 - sq * 0.6), 0.0,
		feet - Vector2(0, lift + step_bob)))
	var base := Vector2.ZERO
	var head := base + Vector2(0, -52.0 * u + bob)
	var r := 34.0 * u
	var body := Rect2(base.x - 20.0 * u, base.y - 28.0 * u + bob * 0.4, 40.0 * u, 27.0 * u)

	# Pies: óvalos brillantes que se alternan al caminar.
	if not is_empty:
		for side in [-1.0, 1.0]:
			var phase: float = sin(walk * TAU) * side if walking else 0.0
			var foot: Vector2 = base + Vector2(side * 10.0 * u + phase * 3.0 * u, -2.5 * u - maxf(0.0, phase) * 4.0 * u)
			batch.ellipse(foot, 9.0 * u, 5.4 * u, ink)
			batch.ellipse(foot, 7.0 * u, 3.8 * u, shade.darkened(0.15))
			batch.ellipse(foot + Vector2(-2.0 * u, -1.4 * u), 2.6 * u, 1.2 * u, Color(1, 1, 1, 0.35))
		batch.flush(ci)

	# Cuerpo con volumen y botón en la panza.
	UiTheme.draw_round_rect(ci, body.grow(2.5 * u), ink, 13.0 * u)
	UiTheme.draw_round_rect(ci, body, shade, 12.0 * u)
	if not is_empty:
		UiTheme.draw_round_rect(ci, Rect2(body.position + Vector2(1.5 * u, 1.0 * u), body.size - Vector2(5.0 * u, 5.0 * u)), col, 11.0 * u)
		var gem := body.get_center() + Vector2(0, 1.5 * u)
		batch.circle(gem, 3.9 * u, ink)
		batch.circle(gem, 2.9 * u, METAL if style == STYLE_ROBOT else light)
		batch.circle(gem + Vector2(-0.9 * u, -0.9 * u), 1.0 * u, Color.WHITE)

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
			batch.flush(ci)
			ci.draw_line(shoulder, hand, ink, 8.5 * u, true)
			ci.draw_line(shoulder, hand, shade, 5.5 * u, true)
			batch.circle(hand, 5.2 * u, ink)
			batch.circle(hand, 3.9 * u, col)
			batch.circle(hand + Vector2(-1.2 * u, -1.3 * u), 1.3 * u, Color(1, 1, 1, 0.5))

	# Accesorios que van detrás de la cabeza (se mueven un poco con el paso).
	var sway := sin(walk * TAU) * 0.08 if walking else sin(t * 1.6 + p_style) * 0.03
	match style:
		1:  # Oso: orejas redondas.
			for sx in [-1.0, 1.0]:
				var ear: Vector2 = head + Vector2(sx * 24.0 * u, -24.0 * u).rotated(sway)
				batch.circle(ear, 12.5 * u, ink)
				batch.circle(ear, 10.0 * u, shade)
				batch.circle(ear + Vector2(-0.8 * u, -0.8 * u), 9.0 * u, col)
				if not is_empty:
					batch.circle(ear, 5.5 * u, light)
		2:  # Gato: orejas puntiagudas.
			for sx in [-1.0, 1.0]:
				var tri := PackedVector2Array([
					head + Vector2(sx * 31.0 * u, -8.0 * u), head + Vector2(sx * 25.0 * u, -46.0 * u).rotated(sway),
					head + Vector2(sx * 6.0 * u, -30.0 * u)])
				batch.polygon(_grow_poly(tri, 1.18), ink)
				batch.polygon(tri, col)
				if not is_empty:
					batch.polygon(_grow_poly(tri, 0.5), light)
		STYLE_ROBOT:  # Robot: tornillos laterales tipo auricular.
			for sx in [-1.0, 1.0]:
				var bolt: Vector2 = head + Vector2(sx * (r + 1.0 * u), -2.0 * u)
				batch.ellipse(bolt, 7.5 * u, 11.0 * u, ink)
				batch.ellipse(bolt, 5.5 * u, 9.0 * u, METAL)
				batch.ellipse(bolt + Vector2(-1.5 * u, -3.0 * u), 1.8 * u, 3.0 * u, Color(1, 1, 1, 0.7))
		STYLE_HORNS:  # Diablito: cuernos curvos.
			for sx in [-1.0, 1.0]:
				var horn := PackedVector2Array([
					head + Vector2(sx * 12.0 * u, -28.0 * u), head + Vector2(sx * 28.0 * u, -38.0 * u).rotated(sway),
					head + Vector2(sx * 33.0 * u, -52.0 * u).rotated(sway), head + Vector2(sx * 26.0 * u, -24.0 * u)])
				batch.polygon(_grow_poly(horn, 1.22), ink)
				batch.polygon(horn, col.darkened(0.35))
		STYLE_BUNNY:  # Conejo: orejas largas.
			for sx in [-1.0, 1.0]:
				var ear: Vector2 = head + Vector2(sx * 13.0 * u, -40.0 * u)
				var rot: float = sx * 0.2 + sway
				batch.ellipse(ear, 9.0 * u, 22.0 * u, ink, rot)
				batch.ellipse(ear, 7.0 * u, 20.0 * u, col, rot)
				if not is_empty:
					batch.ellipse(ear + Vector2(0, 2.0 * u), 3.5 * u, 14.0 * u, Color("#FFB3C7"), rot)

	# Cabeza: esfera de juguete (sombra, volumen, luz suave).
	batch.circle(head, r + 2.5 * u, ink)
	batch.circle(head, r, shade if not is_empty else col)
	if is_empty:
		batch.flush(ci)
		ci.draw_set_transform_matrix(outer)
		return
	batch.circle(head + Vector2(-0.05 * r, -0.07 * r), r * 0.92, col)
	batch.ellipse(head + Vector2(-0.22 * r, -0.36 * r), 0.5 * r, 0.32 * r, Color(light, 0.55), -0.35)
	# Cara con volumen: una base gris clara y el blanco corrido hacia arriba.
	var face := head + Vector2(0, 5.0 * u)
	batch.ellipse(face + Vector2(0, 1.2 * u), 25.0 * u, 21.0 * u, Color("#DDE3EF"))
	batch.ellipse(face + Vector2(0, -0.6 * u), 24.0 * u, 19.6 * u, Color.WHITE)
	# Brillo especular del plástico.
	batch.ellipse(head + Vector2(-0.42 * r, -0.55 * r), 0.16 * r, 0.09 * r, Color(1, 1, 1, 0.9), -0.6)
	var gaze := look.limit_length(1.0) * Vector2(3.0, 2.0) * u
	# Parpadeo cada ~3,3 s, desfasado por estilo para que no parpadeen a la vez.
	var blinking := p_mood == Mood.NORMAL and t > 0.0 and fposmod(t + p_style * 1.37, 3.3) < 0.12
	for sx in [-1.0, 1.0]:
		var eye: Vector2 = head + Vector2(sx * 9.0 * u, 4.0 * u) + gaze
		match p_mood:
			Mood.HAPPY:
				batch.flush(ci)
				ci.draw_arc(eye + Vector2(0, 2.5 * u), 5.0 * u, PI * 1.15, PI * 1.85, 10, ink, 2.8 * u, true)
				batch.circle(eye + Vector2(sx * 7.0 * u, 8.0 * u) - gaze, 3.5 * u, BLUSH)
			Mood.SAD:
				batch.ellipse(eye + Vector2(0, 2.0 * u), 3.2 * u, 4.8 * u, ink)
				batch.circle(eye + Vector2(-0.9 * u, 0.2 * u), 1.1 * u, Color.WHITE)
				batch.flush(ci)
				ci.draw_line(eye + Vector2(-sx * 5.0 * u, -8.0 * u), eye + Vector2(sx * 4.0 * u, -5.5 * u), ink, 2.2 * u, true)
			Mood.SURPRISED:
				batch.circle(eye, 5.4 * u, ink)
				batch.circle(eye, 3.6 * u, Color.WHITE)
				batch.circle(eye, 2.1 * u, ink)
			_:
				if blinking:
					batch.flush(ci)
					ci.draw_line(eye + Vector2(-3.8 * u, 0), eye + Vector2(3.8 * u, 0), ink, 2.4 * u, true)
				else:
					# Ojos brillantes: dos reflejos, como en los personajes de juguete.
					batch.ellipse(eye, 4.4 * u, 7.2 * u, ink)
					batch.circle(eye + Vector2(-1.3 * u, -2.9 * u), 1.7 * u, Color.WHITE)
					batch.circle(eye + Vector2(1.4 * u, 2.4 * u), 0.8 * u, Color(1, 1, 1, 0.8))

	# Boca según el ánimo (el robot tiene rejilla cuando está tranquilo).
	var mouth := face + Vector2(0, 11.0 * u) + gaze * 0.5
	match p_mood:
		Mood.HAPPY:
			var smile := PackedVector2Array()
			for i in 9:
				var a := PI * i / 8.0
				smile.append(mouth + Vector2(cos(a) * 6.0 * u, sin(a) * 5.0 * u - 1.0 * u))
			batch.polygon(smile, ink)
			batch.circle(mouth + Vector2(0, 2.2 * u), 2.2 * u, TONGUE)
		Mood.SAD:
			batch.flush(ci)
			ci.draw_arc(mouth + Vector2(0, 4.0 * u), 4.5 * u, PI * 1.2, PI * 1.8, 8, ink, 2.2 * u, true)
			# Lágrima que cae y vuelve a empezar.
			var drop := fposmod(t * 0.9, 1.0)
			var tear := head + Vector2(-9.0 * u, 11.0 * u + drop * 12.0 * u) + gaze
			batch.circle(tear, 2.4 * u * (1.0 - drop * 0.4), Color(TEAR, TEAR.a * (1.0 - drop)))
		Mood.SURPRISED:
			batch.circle(mouth, 3.6 * u, ink)
			batch.circle(mouth, 2.0 * u, TONGUE)
		_:
			if style == STYLE_ROBOT:
				batch.flush(ci)
				UiTheme.draw_round_rect(ci, Rect2(mouth - Vector2(6.0 * u, 2.2 * u), Vector2(12.0 * u, 4.4 * u)), ink, 2.0 * u)
				for k in 3:
					var gx := mouth.x + (k - 1) * 3.6 * u
					ci.draw_line(Vector2(gx, mouth.y - 1.2 * u), Vector2(gx, mouth.y + 1.2 * u), METAL, 1.2 * u)

	# Accesorios que van delante / arriba
	match style:
		0:  # Antena con bolita.
			var tip := head + Vector2(7.0 * u, -r - 16.0 * u).rotated(sway * 2.0)
			batch.flush(ci)
			ci.draw_line(head + Vector2(0, -r + 2.0 * u), tip, ink, 2.8 * u, true)
			batch.circle(tip, 7.0 * u, ink)
			batch.circle(tip, 5.0 * u, light)
			batch.circle(tip + Vector2(-1.5 * u, -1.5 * u), 1.4 * u, Color.WHITE)
		3:  # Brote.
			var stem := head + Vector2(0, -r - 8.0 * u).rotated(sway)
			batch.flush(ci)
			ci.draw_line(head + Vector2(0, -r + 1.0 * u), stem, ink, 2.8 * u, true)
			for sx in [-1.0, 1.0]:
				var leaf: Vector2 = stem + Vector2(sx * 8.0 * u, -3.0 * u)
				batch.ellipse(leaf, 10.5 * u, 6.0 * u, ink, sx * -0.5 + sway)
				batch.ellipse(leaf, 8.5 * u, 4.2 * u, UiTheme.LEAF, sx * -0.5 + sway)
		STYLE_ROBOT:  # Antena gruesa con foco que titila y tornillos en la frente.
			var top := head + Vector2(0, -r - 14.0 * u).rotated(sway)
			batch.flush(ci)
			UiTheme.draw_round_rect(ci, Rect2(head + Vector2(-5.0 * u, -r - 3.0 * u), Vector2(10.0 * u, 6.0 * u)), ink, 2.0 * u)
			ci.draw_line(head + Vector2(0, -r - 1.0 * u), top, ink, 3.6 * u, true)
			ci.draw_line(head + Vector2(0, -r - 1.0 * u), top, METAL, 1.8 * u, true)
			var glow := 0.55 + 0.45 * absf(sin(t * 3.0 + p_style))
			batch.circle(top, 6.5 * u, ink)
			batch.circle(top, 5.0 * u, Color(UiTheme.DANGER.lerp(UiTheme.ACCENT, 0.3), glow + 0.2))
			batch.circle(top + Vector2(-1.4 * u, -1.4 * u), 1.4 * u, Color.WHITE)
			for sx in [-1.0, 1.0]:
				var screw: Vector2 = head + Vector2(sx * 17.0 * u, -22.0 * u)
				batch.circle(screw, 2.6 * u, ink)
				batch.circle(screw, 1.7 * u, METAL)
	batch.flush(ci)
	ci.draw_set_transform_matrix(outer)


## Agranda (o achica) un polígono desde su centro: contornos y rellenos internos.
static func _grow_poly(pts: PackedVector2Array, k: float) -> PackedVector2Array:
	var c := Vector2.ZERO
	for p in pts:
		c += p
	c /= pts.size()
	var out := PackedVector2Array()
	for p in pts:
		out.append(c + (p - c) * k)
	return out
