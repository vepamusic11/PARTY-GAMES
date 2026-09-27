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
const METAL := UiTheme.MASCOT_METAL   ## Piezas de metal del robot.
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
##   (-1..1) · squash: >0 aplastada, <0 estirada · wave: saluda con los brazos
##   · xform: transformación que ya tenía el lienzo.
##
## Concepto: *juguete 3D dibujado en 2D*. Cada pieza (cabeza, cuerpo, brazos,
## pies, orejas) es una figura con degradé de luz a sombra y contorno grueso
## de tinta (MascotShading). Encima van los brillos: una mancha de luz suave
## y un reflejo chico y blanco, como el plástico de los juguetes.
## Proporciones de la referencia (docs/design/referencia_mascotas.webp):
## cabeza grande y un poco más ancha que alta, cara blanca grande con ojos
## ovalados, cuerpo chico, brazos y piernas cortos, zapatos oscuros.
##
## Concepto: *nivel de detalle* (LOD). Una mascota chica (juegos, u < LOD_U)
## usa mallas con menos puntos y saltea brillos que a ese tamaño no se ven:
## se ve igual y cuesta bastante menos.
##
## Rendimiento: todo va en un UiTheme.ShapeBatch (un draw call para la
## sombra y uno para el resto); las mallas y los colores por vértice están
## precalculados, así que por frame solo se transforman y copian arreglos.
static func draw_mascot(ci: CanvasItem, feet: Vector2, u: float, col: Color, p_style: int,
		p_mood: int = Mood.NORMAL, bob: float = 0.0, lift: float = 0.0, is_empty: bool = false,
		anim: Dictionary = {}) -> void:
	var detail := u >= LOD_U
	var sh := _shapes(detail)
	var ink := UiTheme.INK
	var mat := MascotShading.PLASTIC
	if is_empty:
		col = Color(1, 1, 1, 0.3)
		ink = Color(1, 1, 1, 0.75)
		mat = MascotShading.FLAT
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
	var w := INK_WIDTH * u        # Contorno de las piezas grandes.
	var ws := INK_WIDTH_SMALL * u # Contorno de las piezas chicas.
	var batch := MascotShading.Batch.new()

	# Sombra en el piso, difusa; se achica cuando la mascota está en el aire.
	var shadow_k := clampf(1.0 - lift / (80.0 * u), 0.3, 1.0)
	batch.add(sh.glow, MascotShading.GLOW, SHADOW, feet + Vector2(0, 0.5 * u),
		Vector2(30.0, 7.0) * u * shadow_k)
	batch.flush(ci)  # La sombra va sin el transform de squash.

	# Al caminar, rebota un poco con cada paso.
	var step_bob := absf(sin(walk * TAU)) * 3.0 * u if walking else 0.0
	# Squash & stretch alrededor de los pies: ancho × alto ≈ constante.
	ci.draw_set_transform_matrix(outer * Transform2D(0.0, Vector2(1.0 + sq * 0.6, 1.0 - sq * 0.6), 0.0,
		feet - Vector2(0, lift + step_bob)))
	var head := Vector2(0, -57.0 * u + bob)
	var hr := Vector2(HEAD_RX, HEAD_RY) * u
	var body := Vector2(0, -20.0 * u + bob * 0.4)
	var sway := sin(walk * TAU) * 0.08 if walking else sin(t * 1.6 + p_style) * 0.03

	# Piernas cortas y zapatos oscuros brillantes, que se alternan al caminar.
	if not is_empty:
		for side in [-1.0, 1.0]:
			var phase: float = sin(walk * TAU) * side if walking else 0.0
			var lift_k := maxf(0.0, phase)
			if detail:
				batch.add(sh.ball_s, mat, col, Vector2((side * 7.0 + phase * 1.5) * u, (-9.5 - lift_k * 2.0) * u),
					Vector2(5.2, 6.5) * u, 0.0, ws, ink)
			var foot := Vector2((side * 8.5 + phase * 3.0) * u, (-4.2 - lift_k * 4.0) * u)
			batch.add(sh.ball_s, MascotShading.EYE, UiTheme.MASCOT_SHOE, foot, Vector2(7.4, 4.6) * u, 0.0, ws, ink)
			if detail:
				batch.add(sh.dot, MascotShading.FLAT, SHINE_SOFT, foot + Vector2(-2.6, -2.0) * u,
					Vector2(2.2, 1.0) * u, -0.2)

	# Cuerpo: un poco más ancho abajo, con la gema en la panza.
	batch.add(sh.body, mat, col, body, Vector2(17.5, 12.5) * u, 0.0, w, ink)
	if not is_empty:
		if detail:
			batch.add(sh.glow, MascotShading.GLOW, SHINE_SOFT, body + Vector2(-8.0, -3.0) * u,
				Vector2(6.0, 4.0) * u, -0.4)
			# Sombra que deja la cabeza sobre el cuerpo (cuello).
			batch.add(sh.glow, MascotShading.GLOW, NECK_SHADOW, body + Vector2(0, -9.0 * u), Vector2(17.0, 6.0) * u)
		var robot := style == STYLE_ROBOT
		var gem_col := UiTheme.MASCOT_METAL if robot else _gem_color(col)
		var gem := body + Vector2(0, 1.5 * u)
		if detail:
			batch.add(sh.glow, MascotShading.GLOW, Color(gem_col, 0.55), gem, Vector2(7.5, 7.5) * u)
		batch.add(sh.ball_s, MascotShading.METAL if robot else mat, gem_col, gem, Vector2(3.4, 3.4) * u,
			0.0, 1.1 * u, ink)
		batch.add(sh.dot, MascotShading.FLAT, SHINE, gem + Vector2(-1.1, -1.1) * u, Vector2(1.1, 1.1) * u)

	# Brazos (delante del cuerpo). Al saludar van delante de la cabeza: si
	# no, la cabeza grande los taparía.
	if not is_empty and not wave:
		_arms(batch, sh, mat, col, ink, body, u, ws, false, walk, t)

	# Accesorios que van detrás de la cabeza (se mueven un poco con el paso).
	match style:
		1:  # Oso: orejas redondas con el interior más claro.
			for sx in [-1.0, 1.0]:
				var ear: Vector2 = head + Vector2(sx * 27.0 * u, -28.0 * u).rotated(sway)
				batch.add(sh.ball, mat, col, ear, Vector2(12.0, 12.0) * u, 0.0, w, ink)
				if not is_empty:
					batch.add(sh.ball_s, mat, col.lerp(UiTheme.PAPER, 0.35), ear + Vector2(sx * 0.5, 0.0) * u,
						Vector2(5.6, 5.6) * u, 0.0, 0.8 * u, col.darkened(0.3))
		2:  # Gato: orejas puntiagudas con el interior naranja.
			for sx in [-1.0, 1.0]:
				var base: Vector2 = head + Vector2(sx * 22.0 * u, -24.0 * u).rotated(sway)
				var sc := Vector2(sx * u, u)
				var rot: float = sx * 0.3 + sway
				batch.add(sh.cat_ink, MascotShading.FLAT, ink, base, sc, rot)
				batch.add(sh.cat, mat, col, base, sc, rot)
				if not is_empty:
					batch.add(sh.cat_inner, mat, UiTheme.MASCOT_EAR_INNER.lerp(col, 0.1), base, sc, rot)
		STYLE_ROBOT:  # Robot: auriculares de metal a los costados.
			for sx in [-1.0, 1.0]:
				var bolt: Vector2 = head + Vector2(sx * (hr.x + 1.0 * u), -1.0 * u)
				batch.add(sh.ball_s, mat if is_empty else MascotShading.METAL,
					col if is_empty else UiTheme.MASCOT_METAL, bolt, Vector2(6.5, 11.0) * u, 0.0, ws, ink)
				if not is_empty:
					batch.add(sh.disc_s, MascotShading.FLAT, Color(ink, 0.45), bolt + Vector2(sx * 1.2 * u, 0),
						Vector2(2.2, 6.0) * u)
		STYLE_HORNS:  # Diablito: cuernos curvos.
			var horn_col := col.darkened(0.4) if col.get_luminance() > 0.25 else col.lightened(0.45)
			for sx in [-1.0, 1.0]:
				var base: Vector2 = head + Vector2(sx * 16.0 * u, -27.0 * u).rotated(sway)
				var sc := Vector2(sx * u, u)
				var rot: float = sx * 0.3 + sway
				batch.add(sh.horn_ink, MascotShading.FLAT, ink, base, sc, rot)
				batch.add(sh.horn, mat, col if is_empty else horn_col, base, sc, rot)
		STYLE_BUNNY:  # Conejo: orejas largas con el interior rosa.
			for sx in [-1.0, 1.0]:
				var ear: Vector2 = head + Vector2(sx * 14.0 * u, -40.0 * u)
				var rot: float = sx * 0.18 + sway
				batch.add(sh.ball, mat, col, ear, Vector2(8.5, 21.0) * u, rot, w, ink)
				if not is_empty:
					batch.add(sh.ball_s, mat, UiTheme.MASCOT_BUNNY_INNER, ear + Vector2(0, 3.0 * u).rotated(rot),
						Vector2(3.8, 13.5) * u, rot, 0.8 * u, UiTheme.MASCOT_FACE_SHADE)

	# Cabeza: esfera de juguete, un poco más ancha que alta.
	batch.add(sh.head, mat, col, head, hr, 0.0, w, ink)
	if is_empty:
		batch.flush(ci)
		ci.draw_set_transform_matrix(outer)
		return
	# Luz suave y reflejo chico del plástico (arriba a la izquierda).
	batch.add(sh.glow, MascotShading.GLOW, SHINE_GLOW,
		head + Vector2(-0.3 * hr.x, -0.5 * hr.y), Vector2(0.46 * hr.x, 0.3 * hr.y), -0.3)
	batch.add(sh.dot, MascotShading.FLAT, SHINE,
		head + Vector2(-0.5 * hr.x, -0.55 * hr.y), Vector2(0.2 * hr.x, 0.085 * hr.y), -0.7)
	if detail:
		batch.add(sh.dot, MascotShading.FLAT, SHINE,
			head + Vector2(-0.78 * hr.x, -0.18 * hr.y), Vector2(0.045 * hr.x, 0.07 * hr.y), -0.3)
	# Cara: blanco con volumen, metida bajo la "capucha" (sombra arriba).
	var face := head + Vector2(0, 8.5 * u)
	batch.add(sh.glow, MascotShading.GLOW, Color(col.darkened(0.55), 0.5),
		face + Vector2(0, -2.5 * u), Vector2(31.5, 26.5) * u)
	batch.add(sh.ball, MascotShading.FACE, col, face, Vector2(27.5, 23.0) * u)
	if wave:
		_arms(batch, sh, mat, col, ink, body, u, ws, true, walk, t)
	var gaze := look.limit_length(1.0) * Vector2(3.0, 2.0) * u
	# Parpadeo cada ~3,3 s, desfasado por estilo para que no parpadeen a la vez.
	var blinking := p_mood == Mood.NORMAL and t > 0.0 and fposmod(t + p_style * 1.37, 3.3) < 0.12
	var eye_ink := UiTheme.MASCOT_EYE
	for sx in [-1.0, 1.0]:
		var eye: Vector2 = face + Vector2(sx * 11.0 * u, -2.0 * u) + gaze
		match p_mood:
			Mood.HAPPY:
				batch.add(sh.arc, MascotShading.GLOW, eye_ink, eye + Vector2(0, 3.0 * u), Vector2(5.2, 5.2) * u)
				batch.add(sh.glow, MascotShading.GLOW, BLUSH, eye + Vector2(sx * 7.5 * u, 9.0 * u) - gaze,
					Vector2(5.0, 3.4) * u)
			Mood.SAD:
				batch.add(sh.ball_s, MascotShading.EYE, eye_ink, eye + Vector2(0, 2.0 * u), Vector2(3.6, 5.4) * u)
				batch.add(sh.dot, MascotShading.FLAT, Color.WHITE, eye + Vector2(-1.0 * u, 0.0), Vector2(1.3, 1.5) * u)
				_stick(batch, sh, eye + Vector2(-sx * 5.5 * u, -9.0 * u), eye + Vector2(sx * 4.5 * u, -6.0 * u), 1.2 * u, eye_ink)
			Mood.SURPRISED:
				batch.add(sh.dot, MascotShading.FLAT, Color.WHITE, eye, Vector2(4.0, 4.0) * u, 0.0, 1.9 * u, eye_ink)
				batch.add(sh.ball_s, MascotShading.EYE, eye_ink, eye, Vector2(2.3, 2.3) * u)
			_:
				if blinking:
					_stick(batch, sh, eye + Vector2(-4.2 * u, 0), eye + Vector2(4.2 * u, 0), 1.3 * u, eye_ink)
				else:
					# Ojos brillantes: óvalo negro con dos reflejos.
					batch.add(sh.ball_s, MascotShading.EYE, eye_ink, eye, Vector2(5.4, 8.4) * u)
					batch.add(sh.dot, MascotShading.FLAT, Color.WHITE, eye + Vector2(-1.5 * u, -3.6 * u),
						Vector2(2.1, 2.6) * u)
					if detail:
						batch.add(sh.dot, MascotShading.FLAT, SHINE, eye + Vector2(1.8 * u, 3.6 * u),
							Vector2(1.0, 1.0) * u)

	# Boca según el ánimo (el robot tiene rejilla cuando está tranquilo).
	var mouth := face + Vector2(0, 11.0 * u) + gaze * 0.5
	match p_mood:
		Mood.HAPPY:
			batch.add(sh.smile, MascotShading.FLAT, eye_ink, mouth + Vector2(0, -1.0 * u), Vector2(6.0, 5.0) * u)
			batch.add(sh.dot, MascotShading.FLAT, TONGUE, mouth + Vector2(0, 2.2 * u), Vector2(2.2, 2.2) * u)
		Mood.SAD:
			batch.add(sh.arc, MascotShading.GLOW, eye_ink, mouth + Vector2(0, 4.0 * u), Vector2(4.5, 4.5) * u)
			# Lágrima que cae y vuelve a empezar.
			var drop := fposmod(t * 0.9, 1.0)
			var tear := face + Vector2(-10.5 * u, 6.0 * u + drop * 12.0 * u) + gaze
			batch.add(sh.disc_s, MascotShading.FLAT, Color(TEAR, TEAR.a * (1.0 - drop)), tear,
				Vector2(2.4, 2.8) * u * (1.0 - drop * 0.4))
		Mood.SURPRISED:
			batch.add(sh.disc_s, MascotShading.FLAT, eye_ink, mouth, Vector2(3.6, 4.0) * u)
			batch.add(sh.disc_s, MascotShading.FLAT, TONGUE, mouth + Vector2(0, 1.0 * u), Vector2(2.2, 1.8) * u)
		_:
			if style == STYLE_ROBOT:
				batch.add(sh.plate, MascotShading.FLAT, eye_ink, mouth, Vector2(7.0, 2.8) * u)
				for k in 3:
					batch.add(sh.plate, MascotShading.FLAT, UiTheme.MASCOT_METAL,
						mouth + Vector2((k - 1) * 3.6 * u, 0), Vector2(0.6, 1.4) * u)

	# Accesorios que van delante / arriba.
	match style:
		0:  # Antena con bola brillante.
			var tip := head + Vector2(6.0 * u, -hr.y - 17.0 * u).rotated(sway * 2.0)
			var root := head + Vector2(0, -hr.y + 1.0 * u)
			_stick(batch, sh, root, tip, 1.6 * u, ink)
			batch.add(sh.disc_s, MascotShading.FLAT, ink, root + Vector2(0, -1.0 * u), Vector2(4.6, 2.8) * u)
			batch.add(sh.ball_s, mat, col, tip, Vector2(7.5, 7.5) * u, 0.0, ws, ink)
			batch.add(sh.dot, MascotShading.FLAT, SHINE, tip + Vector2(-2.2, -2.2) * u,
				Vector2(1.9, 1.4) * u, -0.7)
		3:  # Brote: tallito y dos hojas.
			var stem := head + Vector2(0, -hr.y - 7.0 * u).rotated(sway)
			var root := head + Vector2(0, -hr.y + 2.0 * u)
			_stick(batch, sh, root, stem, 2.0 * u, ink)
			_stick(batch, sh, root + Vector2(0, -2.0 * u), stem, 0.8 * u, UiTheme.LEAF.darkened(0.3))
			for sx in [-1.0, 1.0]:
				var rot: float = sx * -0.42 + sway
				var leaf: Vector2 = stem + Vector2(sx * 9.5 * u, 0).rotated(rot)
				batch.add(sh.ball_s, MascotShading.PLASTIC, UiTheme.LEAF, leaf, Vector2(10.5, 6.2) * u, rot, ws, ink)
				if detail:
					_stick(batch, sh, leaf - Vector2(sx * 7.0 * u, 0).rotated(rot), leaf + Vector2(sx * 5.0 * u, 0).rotated(rot),
						0.55 * u, LEAF_VEIN)
		STYLE_ROBOT:  # Antena de metal con foco que titila y tornillos en la frente.
			var top := head + Vector2(0, -hr.y - 14.0 * u).rotated(sway)
			var plate := head + Vector2(0, -hr.y - 0.5 * u)
			_stick(batch, sh, plate, top, 2.0 * u, ink)
			_stick(batch, sh, plate, top, 0.9 * u, UiTheme.MASCOT_METAL)
			batch.add(sh.plate, MascotShading.METAL, UiTheme.MASCOT_METAL, plate, Vector2(6.5, 3.5) * u, 0.0, ws, ink)
			var glow := 0.55 + 0.45 * absf(sin(t * 3.0 + p_style))
			var bulb := UiTheme.DANGER.lerp(UiTheme.ACCENT, 0.3)
			batch.add(sh.glow, MascotShading.GLOW, Color(bulb, 0.6 * glow), top, Vector2(12.0, 12.0) * u)
			batch.add(sh.ball_s, mat, bulb.lerp(UiTheme.PAPER, 0.3 * glow), top, Vector2(5.2, 5.2) * u, 0.0, ws, ink)
			batch.add(sh.dot, MascotShading.FLAT, SHINE, top + Vector2(-1.6, -1.6) * u,
				Vector2(1.5, 1.2) * u, -0.7)
			for sx in [-1.0, 1.0]:
				batch.add(sh.ball_s, MascotShading.METAL, UiTheme.MASCOT_METAL, head + Vector2(sx * 20.0 * u, -21.0 * u),
					Vector2(2.2, 2.2) * u, 0.0, 1.0 * u, ink)
	batch.flush(ci)
	ci.draw_set_transform_matrix(outer)


## Brazos tipo cápsula con la mano redonda: colgando, balanceándose al
## caminar (walk ≥ 0) o saludando (wave).
static func _arms(batch: MascotShading.Batch, sh: Dictionary, mat: int, col: Color, ink: Color, body: Vector2,
		u: float, ws: float, wave: bool, walk: float, t: float) -> void:
	for side in [-1.0, 1.0]:
		var angle := 0.55
		var arm_len := 12.0 * u
		if wave:
			angle = 2.2 + sin(t * 12.0 + side) * 0.3  # Hacia arriba y afuera.
			arm_len = 14.0 * u
		elif walk >= 0.0:
			angle = 0.55 + sin(walk * TAU) * side * 0.55
		var shoulder: Vector2 = body + Vector2(side * 14.5 * u, -7.5 * u)
		var dir := Vector2(side * sin(angle), cos(angle))
		var hand: Vector2 = shoulder + dir * arm_len
		batch.add(sh.ball_s, mat, col, (shoulder + hand) / 2.0, Vector2(arm_len / 2.0 + 4.6 * u, 4.8 * u),
			dir.angle(), ws, ink)
		batch.add(sh.ball_s, mat, col, hand, Vector2(5.8, 5.8) * u, 0.0, ws, ink)


## Palito (antena, tallo, nervadura) de a hasta b y medio ancho r: una
## superelipse angosta, sin la cuenta de una línea con antialiasing.
static func _stick(batch: MascotShading.Batch, sh: Dictionary, a: Vector2, b: Vector2, r: float, col: Color) -> void:
	batch.add(sh.plate, MascotShading.FLAT, col, (a + b) / 2.0, Vector2(a.distance_to(b) / 2.0 + r * 0.5, r),
		(b - a).angle())


## Gema de la panza: una versión clara y brillante del color (dorada en los
## colores sin tono, como blanco y negro).
static func _gem_color(col: Color) -> Color:
	if col.s < 0.25:
		return UiTheme.ACCENT
	return Color.from_hsv(fposmod(col.h + 0.06, 1.0), col.s * 0.55, 1.0)


const HEAD_RX := 39.0
const HEAD_RY := 34.0
const INK_WIDTH := 3.0        ## Contorno de cabeza y cuerpo (en u).
const INK_WIDTH_SMALL := 2.5  ## Contorno de manos, pies y accesorios chicos.
const LOD_U := 1.7            ## Desde este tamaño, mallas y brillos completos.
const SHADOW := Color(0.07, 0.1, 0.3, 0.4)  ## Sombra difusa en el piso (UiTheme.SHADOW, más cargada).
const SHINE := Color(1, 1, 1, 0.9)          ## Reflejos chicos del plástico.
const SHINE_SOFT := Color(1, 1, 1, 0.4)
const SHINE_GLOW := Color(1, 1, 1, 0.5)     ## Mancha de luz grande de la cabeza.
const NECK_SHADOW := Color(0.15, 0.19, 0.48, 0.35)
const LEAF_VEIN := Color(0.33, 0.55, 0.25, 0.6)

## Mallas de las piezas por nivel de detalle (se arman la primera vez).
static var _shape_sets: Array[Dictionary] = [{}, {}]


static func _shapes(detail: bool) -> Dictionary:
	var cached := _shape_sets[1 if detail else 0]
	if not cached.is_empty():
		return cached
	var fine := PackedFloat32Array([0.35, 0.64, 0.85, 1.0]) if detail else PackedFloat32Array([0.45, 0.8, 1.0])
	var small := PackedFloat32Array([0.5, 1.0])
	var flat := PackedFloat32Array([1.0])
	var seg := 1.0 if detail else 0.8   # Puntos del contorno, relativo al detalle completo.
	var s := cached
	s.ball = MascotShading.make_shape(MascotShading.blob_outline(int(32 * seg)), fine)
	s.ball_s = MascotShading.make_shape(MascotShading.blob_outline(int(18 * seg)), small)
	s.disc_s = MascotShading.make_shape(MascotShading.blob_outline(int(18 * seg)), flat)
	s.dot = MascotShading.make_shape(MascotShading.blob_outline(10), flat)
	s.glow = MascotShading.make_shape(MascotShading.blob_outline(int(16 * seg)), PackedFloat32Array([0.5, 1.0]), false)
	s.head = MascotShading.make_shape(MascotShading.blob_outline(int(36 * seg), 2.15, -0.05), fine)
	s.body = MascotShading.make_shape(MascotShading.blob_outline(int(28 * seg), 3.0, 0.14),
		PackedFloat32Array([0.4, 0.75, 1.0]) if detail else small)
	# Ojos felices y boca triste (arco), sonrisa (media elipse).
	s.arc = MascotShading.make_arc(PI * 1.12, PI * 1.88, 8 if detail else 6, 0.56, 0.07 if detail else 0.15)
	var smile := PackedVector2Array()
	for i in 9:
		smile.append(Vector2(cos(PI * i / 8.0), sin(PI * i / 8.0)))
	s.smile = MascotShading.make_shape(smile, flat)
	s.plate = MascotShading.make_shape(MascotShading.blob_outline(int(16 * seg), 4.0), PackedFloat32Array([0.5, 1.0]))
	# Orejas de gato y cuernos: polígonos con esquinas redondeadas, en u, con
	# la base en el origen y la punta hacia arriba (la de la derecha; la otra
	# se espeja). La tinta es el mismo polígono con más radio.
	var step := 0.4 / seg
	var cat := PackedVector2Array([Vector2(-11, 5), Vector2(10, 5), Vector2(4, -21)])
	s.cat = MascotShading.make_shape(MascotShading.rounded_outline(cat, 3.5, step), small)
	s.cat_ink = MascotShading.make_shape(MascotShading.rounded_outline(cat, 3.5 + INK_WIDTH, step), flat)
	var cat_in := PackedVector2Array([Vector2(-5.5, 0), Vector2(5.5, 0), Vector2(3, -14)])
	s.cat_inner = MascotShading.make_shape(MascotShading.rounded_outline(cat_in, 2.0, step), small)
	var horn := PackedVector2Array([Vector2(-6, 5), Vector2(6, 5), Vector2(8, -6), Vector2(6, -16)])
	s.horn = MascotShading.make_shape(MascotShading.rounded_outline(horn, 2.5, step), small)
	s.horn_ink = MascotShading.make_shape(MascotShading.rounded_outline(horn, 2.5 + INK_WIDTH_SMALL, step), flat)
	return s
