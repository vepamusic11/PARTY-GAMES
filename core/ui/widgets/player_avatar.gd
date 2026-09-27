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
## Concepto: *acción secundaria* (inercia). Lo que cuelga o sobresale
## (orejas, antena, brote) no se mueve junto con el cuerpo: llega tarde y se
## pasa un poco. Ejemplo: al caer de un salto, las orejas del conejo siguen
## bajando un instante (se doblan hacia afuera) y después rebotan. El nodo lo
## calcula con un resorte (ver _process); draw_mascot sola lo aproxima con la
## caminata, el baile y el squash.
##
## Animaciones del nodo (para pantallas): celebrate() baila, lose() se
## desanima, say_hello() saluda con una mano y sleep_after lo duerme si nadie
## lo "despierta" (wake()). Ver docs/adr/0004-sistema-visual.md.
##
## `draw_mascot` es estática para que los minijuegos (Node2D) dibujen al
## mismo personaje sin instanciar este Control.

## Expresiones. Las nuevas van siempre al final (los juegos guardan el número).
##   ANGRY: enojada / concentrada · DIZZY: mareada (ojos en espiral) ·
##   SLEEPY: dormida (Z y globito) · WINNER: ganadora (ojos de estrella) ·
##   LAUGHING: llorando de risa (ojos ">" "<" y lágrimas).
enum Mood { NORMAL, HAPPY, SAD, SURPRISED, ANGRY, DIZZY, SLEEPY, WINNER, LAUGHING }

## Bailes (clave "dance_kind" de anim / propiedad dance_kind). -1: el del estilo.
const DANCE_HOPS := 0   ## Saltitos con los brazos en V.
const DANCE_SPIN := 1   ## Giro sobre sí misma con los brazos abiertos.
const DANCE_ARMS := 2   ## Brazos arriba, balanceándose de lado a lado.
const DANCE_KINDS := 3

@export var color := Color.WHITE
@export var slot := 0
## Estilo elegido desde el celular (índice de STYLE_NAMES). -1 = el clásico
## del lugar (slot). Ver style_of().
@export var style := -1:
	set(v):
		style = v
		queue_redraw()
var mood := Mood.NORMAL:
	set(v):
		mood = v
		queue_redraw()
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
## 0..1: cuánto baila (lo anima celebrate()). El paso sale del reloj interno.
var dance := 0.0:
	set(v):
		dance = v
		queue_redraw()
## Qué baile (DANCE_*); -1 = el de su estilo (cada estilo tiene uno propio).
var dance_kind := -1:
	set(v):
		dance_kind = v
		queue_redraw()
## 0..1: derrota (hombros caídos, cabeza gacha, orejas caídas). Ver lose().
var defeat := 0.0:
	set(v):
		defeat = v
		queue_redraw()
## 0..1: saluda con una mano (lo anima say_hello()).
var greet := 0.0:
	set(v):
		greet = v
		queue_redraw()
## Segundos sin wake() (ni hop, baile o saludo) para quedarse dormida con
## ánimo NORMAL. 0 = nunca. Ejemplo: el lobby lo pone en 40 y llama a wake()
## cuando ese jugador toca algo.
var sleep_after := 0.0
## Cuadros por segundo del idle (respirar, mirar, parpadear, saludar).
## 0 = en cada frame (TV). El celular lo baja mientras espera (ver
## PartyBackground.anim_fps).
var anim_fps := 0.0

var _t := 0.0
var _anim_slot := -1
var _idle := 0.0
var _flop := 0.0       ## Resorte de la acción secundaria (orejas, antena).
var _flop_v := 0.0
var _dance_tween: Tween
var _defeat_tween: Tween
var _greet_tween: Tween


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
	_idle += delta
	# Resorte: las orejas "siguen" al aplastado/estirado del salto con
	# retraso y rebote (ver *acción secundaria* arriba).
	var dt := minf(delta, 0.05)
	_flop_v += ((absf(squash) * 2.4 - _flop) * FLOP_STIFFNESS - _flop_v * FLOP_DAMPING) * dt
	_flop += _flop_v * dt
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
	wake()
	var tw := create_tween()
	for i in times:
		tw.tween_property(self, "squash", 0.25, 0.08)                     # Anticipación: se agacha.
		tw.tween_property(self, "squash", -0.22, 0.06)                    # Despega estirado.
		tw.parallel().tween_property(self, "hop_height", 1.0, 0.2).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tw.tween_property(self, "hop_height", 0.0, 0.24).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		tw.tween_property(self, "squash", 0.3, 0.05)                      # Aterriza aplastado.
		tw.tween_property(self, "squash", 0.0, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## Baile de victoria. kind: DANCE_* (-1 = el de su estilo). seconds > 0:
## baila ese tiempo y para sola; 0 = hasta stop_celebrating().
func celebrate(kind: int = -1, seconds: float = 0.0) -> void:
	wake()
	dance_kind = kind
	if _dance_tween:
		_dance_tween.kill()
	_dance_tween = create_tween()
	_dance_tween.tween_property(self, "dance", 1.0, 0.25).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	if seconds > 0.0:
		_dance_tween.tween_property(self, "dance", 0.0, 0.3).set_delay(seconds)


func stop_celebrating() -> void:
	if _dance_tween:
		_dance_tween.kill()
	_dance_tween = create_tween()
	_dance_tween.tween_property(self, "dance", 0.0, 0.3)


## Derrota: se desanima (on = true) o se recompone (false). Combina bien con
## mood = SAD.
func lose(on: bool = true) -> void:
	if _defeat_tween:
		_defeat_tween.kill()
	_defeat_tween = create_tween()
	_defeat_tween.tween_property(self, "defeat", 1.0 if on else 0.0, 0.5 if on else 0.3) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)


## Saludo al entrar (lobby): un saltito, levanta una mano y la agita ~1,5 s.
## Con ánimo NORMAL pone cara feliz mientras saluda.
func say_hello() -> void:
	hop(1)
	if _greet_tween:
		_greet_tween.kill()
	_greet_tween = create_tween()
	_greet_tween.tween_property(self, "greet", 1.0, 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_greet_tween.tween_property(self, "greet", 0.0, 0.35).set_delay(1.3)


## Reinicia la cuenta para dormirse (ver sleep_after) y la despierta.
func wake() -> void:
	if is_asleep():
		queue_redraw()
	_idle = 0.0


func is_asleep() -> bool:
	return sleep_after > 0.0 and _idle >= sleep_after and animate and not empty


## Ánimo que se ve: NORMAL + saludo = feliz; NORMAL + mucho tiempo quieta = dormida.
func shown_mood() -> int:
	if mood != Mood.NORMAL or dance > 0.0:
		return mood
	if greet > 0.35:
		return Mood.HAPPY
	if is_asleep():
		return Mood.SLEEPY
	return mood


func _draw() -> void:
	var u := minf(size.x / 80.0, size.y / 112.0)
	var feet := Vector2(size.x / 2.0, size.y - 6.0 * u)
	var st := slot if style < 0 else style
	# Respira: la cabeza sube y baja un poco después que el pecho (ver breath()).
	var bob := breath(_t - 0.18, st) * 1.3 * u if animate else 0.0
	# Mirada: de vez en cuando mira a un costado (idle), para que no parezca congelado.
	var look := Vector2(sin(_t * 0.7 + slot) * 0.8, 0.0) if animate else Vector2.ZERO
	var m := shown_mood()
	var anim := {
		"t": _t, "look": look, "squash": squash,
		"wave": m == Mood.HAPPY and animate and greet <= 0.0,
		"dance": dance, "dance_kind": dance_kind, "defeat": defeat, "greet": greet,
	}
	if animate:
		anim["flop"] = _flop
	draw_mascot(self, feet, u, color, st, m, bob, hop_height * 20.0 * u, empty, anim)


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


## Respiración "orgánica" (-1..1): inspira más rápido de lo que exhala
## (una senoide deformada), cada estilo con su ritmo. El pecho se infla con
## esto y la cabeza lo sigue un poco después.
static func breath(t: float, p_style: int) -> float:
	var b := t * (1.9 + 0.07 * posmod(p_style, 4)) + p_style
	return sin(b + 0.45 * sin(b))


## Mascotas dibujadas desde que arrancó el programa (lo usan los tests para
## saber que draw_mascot llegó al final sin errores).
static var drawn := 0


## Dibuja la mascota. feet: punto donde apoya. u: unidad de escala (mide ~105u).
## p_style: estilo (índice de STYLE_NAMES; si se pasa el lugar 0–3, da el
## accesorio clásico de 1P–4P).
## anim (todo opcional):
##   t: segundos (parpadeo, brazos, lágrima, baile) · walk: fase de caminata
##   en vueltas (≥ 0 camina; negativo, quieta) · look: dirección de la mirada
##   (-1..1) · squash: >0 aplastada, <0 estirada · wave: saluda con los brazos
##   · xform: transformación que ya tenía el lienzo.
##   Nuevas: dance: 0..1 baila (el paso sale de t) · dance_kind: DANCE_*
##   (-1 o sin clave = el del estilo) · defeat: 0..1 derrota · greet: 0..1
##   saluda con una mano · flop: acción secundaria de orejas/antena (>0 se
##   doblan hacia afuera; sin clave, se aproxima con squash).
##
## Concepto: *juguete 3D dibujado en 2D*. Cada pieza (cabeza, cuerpo, brazos,
## pies, orejas) es una figura con degradé de luz a sombra y contorno grueso
## de tinta (MascotShading). Encima van los brillos: una mancha de luz suave
## y un reflejo chico y blanco, como el plástico de los juguetes.
## Proporciones de la referencia (docs/design/referencia_mascotas.webp):
## cabeza grande y un poco más ancha que alta, cara blanca grande con ojos
## ovalados, cuerpo chico, brazos y piernas cortos, zapatos oscuros.
##
## Concepto: *pose por capas*. Cada animación (respirar, caminar, bailar,
## derrota, saludo, ánimo) suma su parte a unos pocos números de la pose:
## inclinación del cuerpo y de la cabeza, ángulo de cada brazo, altura del
## salto, aplastado, giro de la cara. Después se dibuja una sola vez con esa
## pose: por eso las capas se combinan (bailar caminando, mareada y
## derrotada) y agregar una no suma figuras.
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
	var sq := float(anim.get("squash", 0.0))
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

	# --- Pose (ver *pose por capas*) ---
	var dance := clampf(float(anim.get("dance", 0.0)), 0.0, 1.0)
	var defeat := clampf(float(anim.get("defeat", 0.0)), 0.0, 1.0)
	var greet := clampf(float(anim.get("greet", 0.0)), 0.0, 1.0)
	var flop := float(anim.get("flop", absf(sq) * 1.6))
	var lean := 0.0        # Inclinación de todo el cuerpo (sobre los pies).
	var tilt := 0.0        # Inclinación de la cabeza.
	var head_dy := 0.0     # La cabeza baja (derrota, dormida).
	var face_k := 1.0      # Ancho de la cara al girar (1 de frente, 0 de perfil).
	var face_dx := 0.0     # Corrimiento de la cara al girar (-1..1).
	var body_kx := 1.0     # Ancho del cuerpo al girar.
	var swing := 0.0       # Retraso lateral de orejas/antena (inercia).
	var tuck := 0.0        # Pies recogidos en el aire (0..1).
	var shoulder_dy := 0.0
	var arm_l := 0.55      # Ángulo de cada brazo: 0 colgando, PI/2 de costado, PI arriba.
	var arm_r := 0.55
	var sway := 0.0
	var breathing := 0.0
	if walking:
		var s := sin(walk * TAU)
		arm_l = 0.55 - s * 0.55
		arm_r = 0.55 + s * 0.55
		sway = s * 0.08
		swing = sin(walk * TAU - 1.1) * 0.1
		flop += absf(sin(walk * TAU - 0.9)) * 0.35
	else:
		sway = sin(t * 1.6 + p_style) * 0.03
		if t > 0.0:
			breathing = breath(t, style)
			shoulder_dy = -0.5 * u * breathing
			arm_l += 0.04 * breathing
			arm_r += 0.04 * breathing
	if wave:
		arm_l = 2.2 + sin(t * 12.0 - 1.0) * 0.3
		arm_r = 2.2 + sin(t * 12.0 + 1.0) * 0.3
	if not is_empty:
		match p_mood:
			Mood.DIZZY:
				tilt += sin(t * 2.8) * 0.13
				lean += sin(t * 2.8 - 0.6) * 0.045
				swing += sin(t * 2.8 - 1.4) * 0.25
			Mood.SLEEPY:
				tilt += 0.1 + sin(t * 0.9) * 0.03
				head_dy += 2.0 * u
				arm_l = 0.3
				arm_r = 0.3
			Mood.LAUGHING:  # Se sacude de risa, agarrándose la panza.
				var shake := sin(t * 17.0)
				lift += absf(sin(t * 8.5)) * 2.2 * u
				tilt += shake * 0.035
				swing += shake * 0.12
				arm_l = -0.3 + shake * 0.08
				arm_r = -0.3 - shake * 0.08
			Mood.ANGRY:  # Puños apretados, tiembla un poquito.
				arm_l = 0.3
				arm_r = 0.3
				tilt += sin(t * 31.0) * 0.012
		if dance > 0.0:
			var kind := int(anim.get("dance_kind", -1))
			if kind < 0 or kind >= DANCE_KINDS:
				kind = posmod(style, DANCE_KINDS)
			var beat := t * 2.0  # 2 pasos por segundo (120 bpm).
			var da_l := arm_l
			var da_r := arm_r
			match kind:
				DANCE_HOPS:  # Un saltito por paso, brazos en V que se alternan.
					var h := absf(sin(beat * PI))
					var land := pow(1.0 - h, 6.0)
					lift += dance * h * 12.0 * u
					sq += dance * (0.24 * land - 0.1 * h)
					tuck = dance * smoothstep(0.4, 1.0, h)
					flop += dance * (1.0 - absf(sin(beat * PI - 0.6))) * 1.1
					tilt += dance * sin(beat * PI) * 0.05
					da_l = 0.35 + h * 0.85  # Brazos que se abren en el aire.
					da_r = da_l
				DANCE_SPIN:  # Cada 2 pasos, una vuelta con los brazos abiertos.
					var p := fposmod(beat / 2.0, 1.0)
					if p < 0.5:
						var k := p / 0.5
						var a := smoothstep(0.0, 1.0, k) * TAU
						var open := sin(k * PI)
						face_k = cos(a)
						face_dx = sin(a)
						body_kx = 0.84 + 0.16 * absf(cos(a))
						lift += dance * open * 9.0 * u
						flop += dance * open * 1.3
						swing -= dance * open * 0.2
						da_l = lerpf(0.4, 1.55, open)
						da_r = da_l
					else:
						var k := (p - 0.5) / 0.5
						lean += dance * sin(k * TAU) * 0.09
						swing -= dance * sin(k * TAU - 0.8) * 0.2
						da_l = 0.5 + sin(k * TAU) * 0.3
						da_r = 0.5 - sin(k * TAU) * 0.3
				_:  # DANCE_ARMS: brazos arriba, balanceándose de lado a lado.
					var h := absf(sin(beat * PI))
					lean += dance * sin(beat * PI) * 0.12
					tilt += dance * sin(beat * PI - 0.3) * 0.08
					swing -= dance * sin(beat * PI - 0.9) * 0.3
					lift += dance * h * 3.5 * u
					sq += dance * 0.12 * pow(1.0 - h, 4.0)
					da_l = 2.1 + sin(beat * TAU) * 0.4
					da_r = 2.1 - sin(beat * TAU) * 0.4
			arm_l = lerpf(arm_l, da_l, dance)
			arm_r = lerpf(arm_r, da_r, dance)
			face_k = lerpf(1.0, face_k, dance)
			face_dx *= dance
			body_kx = lerpf(1.0, body_kx, dance)
		if defeat > 0.0:  # Hombros caídos, cabeza gacha, orejas caídas.
			head_dy += 4.0 * u * defeat
			shoulder_dy += 2.2 * u * defeat
			sq += 0.05 * defeat
			flop += 1.3 * defeat
			tilt += 0.05 * defeat
			look = look.lerp(Vector2(0.0, 0.8), defeat)
			arm_l = lerpf(arm_l, 0.1, defeat)
			arm_r = lerpf(arm_r, 0.1, defeat)
		if greet > 0.0:  # Una mano arriba, agitándose; la cabeza se ladea.
			arm_r = lerpf(arm_r, 2.0 + sin(t * 11.0) * 0.35, greet)
			tilt -= 0.08 * greet
			swing += sin(t * 11.0 - 1.0) * 0.06 * greet
	sq = clampf(sq, -0.5, 0.5)
	flop = clampf(flop, -0.8, 2.0)

	# Sombra en el piso, difusa; se achica cuando la mascota está en el aire.
	var shadow_k := clampf(1.0 - lift / (80.0 * u), 0.3, 1.0)
	batch.add(sh.glow, MascotShading.GLOW, SHADOW, feet + Vector2(0, 0.5 * u),
		Vector2(30.0, 7.0) * u * shadow_k)
	batch.flush(ci)  # La sombra va sin el transform de squash.

	# Al caminar, rebota un poco con cada paso.
	var step_bob := absf(sin(walk * TAU)) * 3.0 * u if walking else 0.0
	# Squash & stretch alrededor de los pies: ancho × alto ≈ constante.
	ci.draw_set_transform_matrix(outer * Transform2D(lean, Vector2((1.0 + sq * 0.6) * body_kx, 1.0 - sq * 0.6), 0.0,
		feet - Vector2(0, lift + step_bob)))
	var head := Vector2(0, -58.5 * u + bob + head_dy)
	var hr := Vector2(HEAD_RX, HEAD_RY) * u
	var body := Vector2(0, -23.0 * u + bob * 0.4)
	var acc := sway + swing + tilt   # Giro de los accesorios de la cabeza.

	# Piernas cortas y zapatos oscuros brillantes, que se alternan al caminar.
	if not is_empty:
		for side in [-1.0, 1.0]:
			var phase: float = sin(walk * TAU) * side if walking else 0.0
			var lift_k := maxf(0.0, phase) + tuck
			batch.add(sh.ball_s, mat, col, Vector2((side * 6.8 + phase * 1.5) * u, (-8.8 - lift_k * 2.0) * u),
				Vector2(5.0, 6.2) * u, 0.0, ws, ink)
			var foot := Vector2((side * 8.5 + phase * 3.0) * u, (-3.5 - lift_k * 4.0) * u)
			batch.add(sh.ball_s, MascotShading.EYE, UiTheme.MASCOT_SHOE, foot, Vector2(7.4, 3.8) * u, 0.0, ws, ink)
			if detail:
				batch.add(sh.dot, MascotShading.FLAT, SHINE_SOFT, foot + Vector2(-2.6, -2.0) * u,
					Vector2(2.2, 1.0) * u, -0.2)

	# Cuerpo: un poco más ancho abajo, con la gema en la panza. Al respirar
	# el pecho se infla apenas.
	batch.add(sh.body, mat, col, body, Vector2(17.5 * (1.0 - 0.012 * breathing), 11.0 * (1.0 + 0.03 * breathing)) * u,
		0.0, w, ink)
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
		if detail:
			batch.add(sh.dot, MascotShading.FLAT, SHINE, gem + Vector2(-1.1, -1.1) * u, Vector2(1.1, 1.1) * u)

	# Brazos (delante del cuerpo). Levantados van delante de la cabeza: si
	# no, la cabeza grande los taparía.
	var arms_up := maxf(arm_l, arm_r) > ARMS_FRONT
	if not is_empty and not arms_up:
		_arms(batch, sh, mat, col, ink, body, u, ws, arm_l, arm_r, shoulder_dy)

	# Accesorios que van detrás de la cabeza (se mueven un poco con el paso y
	# se doblan hacia afuera con `flop`).
	match style:
		1:  # Oso: orejas redondas con el interior más claro.
			for sx in [-1.0, 1.0]:
				var ear: Vector2 = head + Vector2(sx * face_k * 27.0 * u, -28.0 * u).rotated(acc + sx * flop * 0.1)
				batch.add(sh.ball, mat, col, ear, Vector2(12.0, 12.0) * u, 0.0, w, ink)
				if not is_empty:
					batch.add(sh.ball_s, mat, col.lerp(UiTheme.PAPER, 0.35), ear + Vector2(sx * 0.5, 0.0) * u,
						Vector2(5.6, 5.6) * u, 0.0, 0.8 * u, col.darkened(0.3))
		2:  # Gato: orejas puntiagudas con el interior naranja.
			for sx in [-1.0, 1.0]:
				var base: Vector2 = head + Vector2(sx * face_k * 22.0 * u, -24.0 * u).rotated(acc)
				var sc := Vector2(sx * u, u)
				var rot: float = sx * 0.3 + acc + sx * flop * 0.28
				batch.add(sh.cat_ink, MascotShading.FLAT, ink, base, sc, rot)
				batch.add(sh.cat, mat, col, base, sc, rot)
				if not is_empty:
					batch.add(sh.cat_inner, mat, UiTheme.MASCOT_EAR_INNER.lerp(col, 0.1), base, sc, rot)
		STYLE_ROBOT:  # Robot: auriculares de metal a los costados.
			for sx in [-1.0, 1.0]:
				var bolt: Vector2 = head + Vector2(sx * face_k * (hr.x + 1.0 * u), -1.0 * u).rotated(tilt)
				batch.add(sh.ball_s, mat if is_empty else MascotShading.METAL,
					col if is_empty else UiTheme.MASCOT_METAL, bolt, Vector2(6.5, 11.0) * u, tilt, ws, ink)
				if not is_empty and detail:
					batch.add(sh.disc_s, MascotShading.FLAT, Color(ink, 0.45), bolt + Vector2(sx * 1.2 * u, 0),
						Vector2(2.2, 6.0) * u, tilt)
		STYLE_HORNS:  # Diablito: cuernos curvos (rígidos: no se doblan).
			var horn_col := col.darkened(0.4) if col.get_luminance() > 0.25 else col.lightened(0.45)
			for sx in [-1.0, 1.0]:
				var base: Vector2 = head + Vector2(sx * face_k * 16.0 * u, -27.0 * u).rotated(sway + tilt)
				var sc := Vector2(sx * u, u)
				var rot: float = sx * 0.3 + sway + tilt
				batch.add(sh.horn_ink, MascotShading.FLAT, ink, base, sc, rot)
				batch.add(sh.horn, mat, col if is_empty else horn_col, base, sc, rot)
		STYLE_BUNNY:  # Conejo: orejas largas con el interior rosa; giran desde la base.
			for sx in [-1.0, 1.0]:
				var rot: float = sx * 0.18 + acc + sx * flop * 0.5
				var ear: Vector2 = head + Vector2(sx * face_k * 12.5 * u, -24.0 * u).rotated(acc) + Vector2(0, -16.0 * u).rotated(rot)
				batch.add(sh.ball, mat, col, ear, Vector2(8.5, 21.0) * u, rot, w, ink)
				if not is_empty:
					batch.add(sh.ball_s, mat, UiTheme.MASCOT_BUNNY_INNER, ear + Vector2(0, 3.0 * u).rotated(rot),
						Vector2(3.8, 13.5) * u, rot, 0.8 * u, UiTheme.MASCOT_FACE_SHADE)

	# Cabeza: esfera de juguete, un poco más ancha que alta.
	batch.add(sh.head, mat, col, head, hr, tilt, w, ink)
	if is_empty:
		batch.flush(ci)
		ci.draw_set_transform_matrix(outer)
		drawn += 1
		return
	# Luz suave y reflejo chico del plástico (arriba a la izquierda: la luz no gira con la cabeza).
	batch.add(sh.glow, MascotShading.GLOW, SHINE_GLOW,
		head + Vector2(-0.3 * hr.x, -0.5 * hr.y), Vector2(0.46 * hr.x, 0.3 * hr.y), -0.3)
	batch.add(sh.dot, MascotShading.FLAT, SHINE,
		head + Vector2(-0.5 * hr.x, -0.55 * hr.y), Vector2(0.2 * hr.x, 0.085 * hr.y), -0.7)
	if detail:
		batch.add(sh.dot, MascotShading.FLAT, SHINE,
			head + Vector2(-0.78 * hr.x, -0.18 * hr.y), Vector2(0.045 * hr.x, 0.07 * hr.y), -0.3)
	# Cara: blanco con volumen, metida bajo la "capucha" (sombra arriba). Todo
	# lo de la cara se ubica en su propio sistema (fr): gira con la cabeza y
	# se angosta y corre cuando la mascota da una vuelta (baile).
	var fr := Transform2D(tilt, Vector2(face_k, 1.0), 0.0, head + Vector2(face_dx * 17.0 * u, 8.5 * u).rotated(tilt))
	var ax := fr.x   # Derecha de la cara (ya multiplicada por face_k).
	var ay := fr.y   # Abajo de la cara.
	var face := fr.origin
	var face_on := face_k > 0.12  # De espaldas no se ve la cara.
	if face_on:
		batch.add(sh.glow, MascotShading.GLOW, Color(col.darkened(0.55), 0.5),
			face - ay * 2.5 * u, Vector2(31.5 * face_k, 26.5) * u, tilt)
		batch.add(sh.ball, MascotShading.FACE, col, face, Vector2(27.5 * face_k, 23.0) * u, tilt)
	if arms_up:
		_arms(batch, sh, mat, col, ink, body, u, ws, arm_l, arm_r, shoulder_dy)
	if face_on:
		_face(batch, sh, p_mood, style, face, ax, ay, face_k, tilt, look, u, t, detail)

	# Accesorios que van delante / arriba.
	match style:
		0:  # Antena con bola brillante: resorte que se inclina y se acorta.
			var tip := head + Vector2(6.0 * face_k * u, -hr.y - 17.0 * u * (1.0 - 0.15 * flop)).rotated(sway * 2.0 + swing * 1.6 + tilt + flop * 0.25)
			var root := head + Vector2(0, -hr.y + 1.0 * u).rotated(tilt)
			_stick(batch, sh, root, tip, 1.6 * u, ink)
			batch.add(sh.disc_s, MascotShading.FLAT, ink, root + Vector2(0, -1.0 * u), Vector2(4.6, 2.8) * u, tilt)
			batch.add(sh.ball_s, mat, col, tip, Vector2(7.5, 7.5) * u, 0.0, ws, ink)
			batch.add(sh.dot, MascotShading.FLAT, SHINE, tip + Vector2(-2.2, -2.2) * u,
				Vector2(1.9, 1.4) * u, -0.7)
		3:  # Brote: tallito y dos hojas que se doblan con la inercia.
			var stem := head + Vector2(0, -hr.y - 7.0 * u).rotated(acc)
			var root := head + Vector2(0, -hr.y + 2.0 * u).rotated(tilt)
			_stick(batch, sh, root, stem, 2.0 * u, ink)
			if detail:
				_stick(batch, sh, root + Vector2(0, -2.0 * u), stem, 0.8 * u, UiTheme.LEAF.darkened(0.3))
			for sx in [-1.0, 1.0]:
				var rot: float = sx * -0.42 + acc + sx * flop * 0.4
				var leaf: Vector2 = stem + Vector2(sx * 9.5 * u, 0).rotated(rot)
				batch.add(sh.ball_s, MascotShading.PLASTIC, UiTheme.LEAF, leaf, Vector2(10.5, 6.2) * u, rot, ws, ink)
				if detail:
					_stick(batch, sh, leaf - Vector2(sx * 7.0 * u, 0).rotated(rot), leaf + Vector2(sx * 5.0 * u, 0).rotated(rot),
						0.55 * u, LEAF_VEIN)
		STYLE_ROBOT:  # Antena de metal en un zócalo oscuro, foco que titila y tornillos.
			var top := head + Vector2(0, -hr.y - 14.0 * u * (1.0 - 0.12 * flop)).rotated(sway + swing * 1.3 + tilt + flop * 0.15)
			var socket := head + Vector2(0, -hr.y + 0.5 * u).rotated(tilt)
			_stick(batch, sh, socket, top, 2.0 * u, ink)
			_stick(batch, sh, socket, top, 0.9 * u, UiTheme.MASCOT_METAL)
			# Zócalo: cúpula de goma oscura y brillante (antes, una placa de
			# metal que de lejos se leía como un cuadradito blanco).
			batch.add(sh.ball_s, MascotShading.EYE, UiTheme.MASCOT_SOCKET, socket, Vector2(7.0, 4.6) * u, tilt, ws, ink)
			if detail:
				batch.add(sh.dot, MascotShading.FLAT, SHINE_SOFT, socket + Vector2(-2.6, -1.8) * u,
					Vector2(2.2, 0.9) * u, -0.2)
			var glow := 0.55 + 0.45 * absf(sin(t * 3.0 + p_style))
			var bulb := UiTheme.DANGER.lerp(UiTheme.ACCENT, 0.3)
			batch.add(sh.glow, MascotShading.GLOW, Color(bulb, 0.6 * glow), top, Vector2(12.0, 12.0) * u)
			batch.add(sh.ball_s, mat, bulb.lerp(UiTheme.PAPER, 0.3 * glow), top, Vector2(5.2, 5.2) * u, 0.0, ws, ink)
			batch.add(sh.dot, MascotShading.FLAT, SHINE, top + Vector2(-1.6, -1.6) * u,
				Vector2(1.5, 1.2) * u, -0.7)
			for sx in ([-1.0, 1.0] if face_on else []):  # Tornillos de la frente.
				batch.add(sh.ball_s, MascotShading.METAL, UiTheme.MASCOT_BOLT,
					head + Vector2(sx * face_k * 20.0 * u, -21.0 * u).rotated(tilt), Vector2(2.2, 2.2) * u, 0.0, 1.0 * u, ink)

	# Efectos del ánimo alrededor de la cabeza.
	match p_mood:
		Mood.DIZZY:  # Estrellitas que dan vueltas sobre la cabeza.
			for k in 3:
				var a := t * 3.2 + k * TAU / 3.0
				var p := head + Vector2(cos(a) * hr.x * 0.8, -hr.y * 0.95 + sin(a) * 5.0 * u).rotated(tilt)
				batch.add(sh.star, MascotShading.PLASTIC, UiTheme.ACCENT, p, Vector2(4.2, 4.2) * u * (0.85 + 0.15 * sin(a)),
					a * 0.5, 1.0 * u, ink)
		Mood.SLEEPY:  # Z que suben y se desvanecen (y globito en la nariz, de cerca).
			for k in 2:
				var ph := fposmod(t * 0.45 + k * 0.5, 1.0)
				var z := head + Vector2(hr.x * 0.6 + ph * 16.0 * u, -hr.y * 0.55 - ph * 26.0 * u)
				batch.add(sh.zee, MascotShading.GLOW, Color(ink, sin(ph * PI)), z, Vector2(4.0, 4.0) * u * (0.6 + ph * 0.7), -0.15)
			if detail:
				var r := (2.0 + 2.6 * (0.5 + 0.5 * sin(t * 1.9))) * u
				var bub := face + ax * 7.5 * u + ay * 5.0 * u + Vector2(r * 0.7, 0)
				batch.add(sh.ball_s, MascotShading.FLAT, BUBBLE, bub, Vector2(r, r), 0.0, 0.9 * u, ink)
				batch.add(sh.dot, MascotShading.FLAT, SHINE, bub + Vector2(-0.4, -0.45) * r, Vector2(0.28, 0.2) * r, -0.6)
		Mood.WINNER:  # Destellos que titilan a los costados.
			for k in 2:
				var sx := -1.0 if k == 0 else 1.0
				var pulse := 0.5 + 0.5 * sin(t * 5.0 + k * 2.0)
				batch.add(sh.spark, MascotShading.FLAT, UiTheme.PAPER,
					head + Vector2(sx * (hr.x + 6.0 * u), -hr.y * 0.35 + k * 10.0 * u), Vector2(5.0, 5.0) * u * (0.5 + 0.6 * pulse))
		Mood.ANGRY:  # Venita de enojo en la frente (solo de cerca).
			if detail:
				var v := head + Vector2(hr.x * 0.55, -hr.y * 0.62).rotated(tilt)
				for k in 4:
					var d := Vector2.from_angle(PI * 0.25 + k * PI * 0.5)
					batch.add(sh.arc, MascotShading.GLOW, UiTheme.DANGER, v + d * 4.6 * u, Vector2(3.0, 3.0) * u,
						d.angle() + PI * 0.5)
	batch.flush(ci)
	ci.draw_set_transform_matrix(outer)
	drawn += 1


## Ojos, cejas, cachetes y boca según el ánimo. face: centro de la cara; ax,
## ay: ejes de la cara (derecha y abajo, ya girados y angostados).
static func _face(batch: MascotShading.Batch, sh: Dictionary, p_mood: int, style: int, face: Vector2,
		ax: Vector2, ay: Vector2, fk: float, tilt: float, look: Vector2, u: float, t: float, detail: bool) -> void:
	var gaze := look.limit_length(1.0) * Vector2(3.0, 2.0) * u
	# Parpadeo cada ~3,3 s, desfasado por estilo para que no parpadeen a la
	# vez; una de cada tres veces, doble (como la gente).
	var blinking := false
	if (p_mood == Mood.NORMAL or p_mood == Mood.ANGRY) and t > 0.0:
		var bt := t + style * 1.37
		var cycle := floorf(bt / 3.3)
		var ph := bt - cycle * 3.3
		blinking = ph < 0.12 or (posmod(int(cycle), 3) == 1 and ph > 0.24 and ph < 0.36)
	var eye_ink := UiTheme.MASCOT_EYE
	for sx in [-1.0, 1.0]:
		var eye: Vector2 = face + ax * (sx * 11.0 * u) - ay * 2.0 * u + gaze
		match p_mood:
			Mood.HAPPY, Mood.WINNER, Mood.LAUGHING:
				if p_mood == Mood.WINNER:  # Ojos de estrella dorada.
					batch.add(sh.star, MascotShading.PLASTIC, UiTheme.ACCENT, eye,
						Vector2(7.0 * fk, 7.0) * u, tilt + sin(t * 3.0 + sx) * 0.12, 1.2 * u, eye_ink)
					batch.add(sh.dot, MascotShading.FLAT, SHINE, eye + (ax * -1.8 - ay * 2.2) * u, Vector2(1.5 * fk, 1.3) * u, tilt)
				elif p_mood == Mood.LAUGHING:  # Ojos apretados ">" "<".
					batch.add(sh.chevron, MascotShading.GLOW, eye_ink, eye, Vector2(-sx * 4.0 * fk, 4.6) * u, tilt)
				else:
					batch.add(sh.arc, MascotShading.GLOW, eye_ink, eye + ay * 3.0 * u, Vector2(5.2 * fk, 5.2) * u, tilt)
				batch.add(sh.glow, MascotShading.GLOW, BLUSH, eye + (ax * (sx * 7.5) + ay * 9.0) * u - gaze,
					Vector2(5.0 * fk, 3.4) * u, tilt)
			Mood.SAD:
				batch.add(sh.ball_s, MascotShading.EYE, eye_ink, eye + ay * 2.0 * u, Vector2(3.6 * fk, 5.4) * u, tilt)
				batch.add(sh.dot, MascotShading.FLAT, Color.WHITE, eye - ax * 1.0 * u, Vector2(1.3 * fk, 1.5) * u, tilt)
				_stick(batch, sh, eye + (ax * (-sx * 5.5) - ay * 9.0) * u, eye + (ax * (sx * 4.5) - ay * 6.0) * u,
					1.2 * u, eye_ink)
			Mood.SURPRISED:
				batch.add(sh.dot, MascotShading.FLAT, Color.WHITE, eye, Vector2(4.0 * fk, 4.0) * u, tilt, 1.9 * u, eye_ink)
				batch.add(sh.ball_s, MascotShading.EYE, eye_ink, eye, Vector2(2.3 * fk, 2.3) * u, tilt)
				# Cejas bien arriba.
				batch.add(sh.arc, MascotShading.GLOW, eye_ink, eye - ay * 6.5 * u, Vector2(4.4 * fk, 3.6) * u, tilt)
			Mood.ANGRY:
				if blinking:
					_stick(batch, sh, eye + ax * (-4.0 * u) + ay * 1.5 * u, eye + ax * (4.0 * u) + ay * 1.5 * u, 1.3 * u, eye_ink)
				else:
					batch.add(sh.ball_s, MascotShading.EYE, eye_ink, eye + ay * 1.2 * u, Vector2(5.0 * fk, 6.6) * u, tilt)
					batch.add(sh.dot, MascotShading.FLAT, Color.WHITE, eye + (ax * -1.4 - ay * 1.6) * u,
						Vector2(1.8 * fk, 2.0) * u, tilt)
				# Cejas fruncidas: bajas hacia el centro, tapan el borde del ojo.
				_stick(batch, sh, eye + (ax * (-sx * 6.5) - ay * 6.0) * u, eye + (ax * (sx * 5.5) - ay * 10.5) * u,
					1.8 * u, eye_ink)
			Mood.DIZZY:  # Espirales que giran en sentidos opuestos.
				batch.add(sh.spiral, MascotShading.GLOW, eye_ink, eye - gaze, Vector2(7.0 * fk, 7.0) * u, t * 5.0 * sx + tilt)
			Mood.SLEEPY:  # Ojos cerrados, relajados (arco hacia abajo).
				batch.add(sh.arc, MascotShading.GLOW, eye_ink, eye - gaze - ay * 2.4 * u, Vector2(5.0 * fk, 4.4) * u, tilt + PI)
			_:
				if blinking:
					_stick(batch, sh, eye - ax * 4.2 * u, eye + ax * 4.2 * u, 1.3 * u, eye_ink)
				else:
					# Ojos brillantes: óvalo negro con dos reflejos.
					batch.add(sh.ball_s, MascotShading.EYE, eye_ink, eye, Vector2(5.4 * fk, 8.4) * u, tilt)
					batch.add(sh.dot, MascotShading.FLAT, Color.WHITE, eye + (ax * -1.5 - ay * 3.6) * u,
						Vector2(2.1 * fk, 2.6) * u, tilt)
					if detail:
						batch.add(sh.dot, MascotShading.FLAT, SHINE, eye + (ax * 1.8 + ay * 3.6) * u,
							Vector2(1.0, 1.0) * u)

	# Boca según el ánimo (el robot tiene rejilla cuando está tranquilo).
	var mouth := face + ay * 11.0 * u + gaze * 0.5
	match p_mood:
		Mood.HAPPY:
			batch.add(sh.smile, MascotShading.FLAT, eye_ink, mouth - ay * 1.0 * u, Vector2(6.0 * fk, 5.0) * u, tilt)
			batch.add(sh.dot, MascotShading.FLAT, TONGUE, mouth + ay * 2.2 * u, Vector2(2.2 * fk, 2.2) * u, tilt)
		Mood.WINNER, Mood.LAUGHING:  # Boca grande bien abierta.
			var big := 1.0 if p_mood == Mood.WINNER else 1.12
			batch.add(sh.smile, MascotShading.FLAT, eye_ink, mouth - ay * 2.0 * u, Vector2(7.2 * fk, 7.0) * u * big, tilt)
			batch.add(sh.disc_s, MascotShading.FLAT, TONGUE, mouth + ay * 2.8 * u * big, Vector2(3.4 * fk, 2.2) * u * big, tilt)
			if p_mood == Mood.LAUGHING:  # Lágrimas de risa que saltan hacia afuera.
				for sx in [-1.0, 1.0]:
					var ph := fposmod(t * 1.7 + (0.5 if sx > 0.0 else 0.0), 1.0)
					var drop: Vector2 = face + ax * (sx * (17.0 + ph * 9.0) * u) + ay * ((-3.0 - ph * 5.0 + ph * ph * 14.0) * u)
					batch.add(sh.disc_s, MascotShading.FLAT, Color(TEAR, TEAR.a * (1.0 - ph * ph)), drop,
						Vector2(2.2, 2.7) * u * (1.0 - ph * 0.3))
		Mood.SAD:
			batch.add(sh.arc, MascotShading.GLOW, eye_ink, mouth + ay * 4.0 * u, Vector2(4.5 * fk, 4.5) * u, tilt)
			# Lágrima que cae y vuelve a empezar.
			var drop := fposmod(t * 0.9, 1.0)
			var tear := face + ax * (-10.5 * u) + ay * (6.0 * u + drop * 12.0 * u) + gaze
			batch.add(sh.disc_s, MascotShading.FLAT, Color(TEAR, TEAR.a * (1.0 - drop)), tear,
				Vector2(2.4, 2.8) * u * (1.0 - drop * 0.4))
		Mood.SURPRISED:
			batch.add(sh.disc_s, MascotShading.FLAT, eye_ink, mouth, Vector2(3.6 * fk, 4.0) * u, tilt)
			batch.add(sh.disc_s, MascotShading.FLAT, TONGUE, mouth + ay * 1.0 * u, Vector2(2.2 * fk, 1.8) * u, tilt)
		Mood.ANGRY:  # Dientes apretados.
			batch.add(sh.plate, MascotShading.FLAT, UiTheme.PAPER, mouth + ay * 1.5 * u, Vector2(5.2 * fk, 2.2) * u, tilt,
				1.3 * u, eye_ink)
			_stick(batch, sh, mouth + (ay * 1.5 - ax * 4.4) * u, mouth + (ay * 1.5 + ax * 4.4) * u, 0.5 * u, eye_ink)
		Mood.DIZZY:
			batch.add(sh.wave, MascotShading.GLOW, eye_ink, mouth + ay * 1.0 * u, Vector2(6.5 * fk, 2.0) * u, tilt)
		Mood.SLEEPY:  # Boquita abierta que respira.
			var o := 0.8 + 0.2 * sin(t * 1.9)
			batch.add(sh.disc_s, MascotShading.FLAT, eye_ink, mouth + ay * 1.0 * u, Vector2(1.9 * fk, 2.3 * o) * u, tilt)
		_:
			if style == STYLE_ROBOT:
				batch.add(sh.plate, MascotShading.FLAT, eye_ink, mouth, Vector2(7.0 * fk, 2.8) * u, tilt)
				for k in 3:
					batch.add(sh.plate, MascotShading.FLAT, UiTheme.MASCOT_METAL,
						mouth + ax * ((k - 1) * 3.6 * u), Vector2(0.6 * fk, 1.4) * u, tilt)


## Brazos con la mano redonda (una sola pieza: sin línea de tinta en la
## muñeca). a_l / a_r: ángulo de cada brazo (0 colgando, PI arriba).
static func _arms(batch: MascotShading.Batch, sh: Dictionary, mat: int, col: Color, ink: Color, body: Vector2,
		u: float, ws: float, a_l: float, a_r: float, shoulder_dy: float) -> void:
	for side in [-1.0, 1.0]:
		var angle: float = a_l if side < 0.0 else a_r
		var shoulder: Vector2 = body + Vector2(side * 14.5 * u, -7.5 * u + shoulder_dy)
		var dir := Vector2(side * sin(angle), cos(angle))
		batch.add(sh.arm, mat, col, shoulder + dir * (-ARM_SHOULDER.x * u), Vector2(u, u), dir.angle(), ws, ink)


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
const ARMS_FRONT := 1.3       ## Brazo más levantado que esto: se dibuja delante de la cabeza.
const FLOP_STIFFNESS := 170.0 ## Resorte de orejas/antena (ver _process).
const FLOP_DAMPING := 7.0
## Brazo con mano (en u, a lo largo de +x): hombro, mano y sus radios.
const ARM_SHOULDER := Vector2(-6.6, 0.0)
const ARM_HAND := Vector2(5.4, 0.0)
const ARM_RADIUS := 4.5
const HAND_RADIUS := 5.8
const SHADOW := Color(0.07, 0.1, 0.3, 0.4)  ## Sombra difusa en el piso (UiTheme.SHADOW, más cargada).
const SHINE := Color(1, 1, 1, 0.9)          ## Reflejos chicos del plástico.
const SHINE_SOFT := Color(1, 1, 1, 0.4)
const SHINE_GLOW := Color(1, 1, 1, 0.5)     ## Mancha de luz grande de la cabeza.
const NECK_SHADOW := Color(0.15, 0.19, 0.48, 0.35)
const LEAF_VEIN := Color(0.33, 0.55, 0.25, 0.6)
const BUBBLE := Color(0.8, 0.92, 1.0, 0.45)  ## Globito de la nariz al dormir.

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
	s.arm = _arm_shape(int(28 * seg), PackedFloat32Array([0.4, 0.75, 1.0]) if detail else small)
	# Ojos felices y boca triste (arco), sonrisa (media elipse).
	s.arc = MascotShading.make_arc(PI * 1.12, PI * 1.88, 8 if detail else 6, 0.56, 0.07 if detail else 0.15)
	var smile := PackedVector2Array()
	for i in 9:
		smile.append(Vector2(cos(PI * i / 8.0), sin(PI * i / 8.0)))
	s.smile = MascotShading.make_shape(smile, flat)
	s.plate = MascotShading.make_shape(MascotShading.blob_outline(int(16 * seg), 4.0), PackedFloat32Array([0.5, 1.0]))
	# Trazos de las expresiones nuevas (en unidades de la figura, radio ~1).
	var fe := 0.08 if detail else 0.16   # Borde suavizado: relativamente más ancho de chico.
	var spiral := PackedVector2Array()
	var turns := 1.75
	var n_sp := 22 if detail else 14
	for i in n_sp + 1:
		var k := float(i) / n_sp
		spiral.append(Vector2.from_angle(k * turns * TAU) * (0.12 + 0.88 * k))
	s.spiral = MascotShading.make_strip(spiral, 0.3, fe)
	s.chevron = MascotShading.make_strip(PackedVector2Array([Vector2(-0.8, -0.9), Vector2(0.7, 0.0), Vector2(-0.8, 0.9)]),
		0.42, fe)
	s.zee = MascotShading.make_strip(PackedVector2Array([Vector2(-0.8, -0.8), Vector2(0.8, -0.8), Vector2(-0.8, 0.8),
		Vector2(0.8, 0.8)]), 0.36, fe)
	var wave := PackedVector2Array()
	for i in 13:
		var x := -1.0 + 2.0 * i / 12.0
		wave.append(Vector2(x, sin(x * TAU * 1.0) * 0.55))
	s.wave = MascotShading.make_strip(wave, 0.55, fe * 0.6)
	s.star = MascotShading.make_shape(MascotShading.star_outline(5, 0.5), small)
	s.spark = MascotShading.make_shape(MascotShading.star_outline(4, 0.28), flat)
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


## Brazo y mano en una sola figura (unión de una cápsula y un círculo),
## a lo largo de +x y centrada en el origen. La luz de cada vértice es la de
## un cilindro en el brazo y la de una esfera en la mano: se ven redondos
## los dos, sin la línea de tinta que quedaba entre dos piezas.
static func _arm_shape(segments: int, rings: PackedFloat32Array) -> MascotShading.Shape:
	# Punto adentro de las dos piezas: desde ahí se "ve" todo el contorno.
	var c := Vector2(ARM_HAND.x - 3.0, 0.0)
	var outline := PackedVector2Array()
	for i in segments:
		var d := Vector2.from_angle(TAU * i / segments)
		var lo := 0.0
		var hi := 20.0
		for k in 16:  # Bisección del borde a lo largo del rayo.
			var mid := (lo + hi) / 2.0
			if _in_arm(c + d * mid):
				lo = mid
			else:
				hi = mid
		outline.append(c + d * lo)
	var s := MascotShading.make_shape(outline, rings, true, c)
	for i in s.core.size():
		var p := s.core[i]
		var q: Vector2
		if p.x > ARM_HAND.x - 2.5:
			q = (p - ARM_HAND) / HAND_RADIUS
		elif p.x < ARM_SHOULDER.x:
			q = (p - ARM_SHOULDER) / ARM_RADIUS
		else:
			q = Vector2(0.0, p.y / ARM_RADIUS)
		s.sphere[i] = q.limit_length(1.0)
	return s


static func _in_arm(p: Vector2) -> bool:
	if p.distance_to(ARM_HAND) <= HAND_RADIUS:
		return true
	var x := clampf(p.x, ARM_SHOULDER.x, ARM_HAND.x)
	return p.distance_to(Vector2(x, 0.0)) <= ARM_RADIUS
