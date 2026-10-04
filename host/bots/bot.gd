class_name Bot
extends RefCounted
## Jugador virtual: vive en la TV y "aprieta botones" como un celular.
##
## Concepto (ADR 0010): un bot NO es un jugador especial para el juego. En
## cada paso de física mira el estado público del juego (`MiniGame.bot_view()`,
## lo mismo que se ve en la TV), decide qué haría una persona y devuelve una
## entrada con la misma forma que manda un celular: {axis: Vector2, btn: int}.
## BotDriver la valida con `Protocol.parse_input` y se la pasa al juego por
## `on_input`, igual que HostServer con la red. Nunca decide resultados: la
## TV sigue siendo autoritativa.
##
## Ejemplo: en Arena, el bot "Normal" elige la estrella más cercana, apunta
## con un error de ~35 px que corrige al acercarse y su mano llega 0,22 s
## tarde (tiempo de reacción). En ningún momento suma estrellas él mismo:
## solo mueve el joystick.
##
## La dificultad son unos pocos números (PROFILES), así se ajusta con
## tools/simulate.gd sin tocar la lógica de cada juego.
##
## Cada juego tiene su bot en host/bots/<id>_bot.gd (extiende esta clase y
## sobrescribe `decide`). Un juego sin bot usa esta clase tal cual: entradas
## suaves y al azar según su control (nunca rompe un juego nuevo).

enum Difficulty { EASY, NORMAL, HARD }

const DIFFICULTY_NAMES: Array[String] = ["Fácil", "Normal", "Difícil"]

## Perfiles de dificultad:
##   reaction  segundos entre decidir y que la entrada llegue al juego.
##   aim       error de puntería en px (se corrige al acercarse al objetivo).
##   noise     temblor de la mano (0..1 del eje).
##   speed     cuánto empuja el joystick (1 = a fondo).
##   think     cada cuántos segundos vuelve a pensar su plan.
##   skill     0..1: qué tan buenas son sus decisiones (lo usa cada juego).
const PROFILES: Array[Dictionary] = [
	{"reaction": 0.34, "aim": 70.0, "noise": 0.22, "speed": 0.78, "think": 0.30, "skill": 0.30},
	{"reaction": 0.22, "aim": 34.0, "noise": 0.12, "speed": 0.92, "think": 0.16, "skill": 0.62},
	{"reaction": 0.13, "aim": 12.0, "noise": 0.05, "speed": 1.00, "think": 0.07, "skill": 0.92},
]
## Cada cuánto cambia el error de puntería (segundos, al azar en este rango).
const AIM_CHANGE_SEC := Vector2(0.6, 1.4)

var player_id := 0
var slot := 0
var difficulty: int = Difficulty.NORMAL
## Metadatos del juego (MiniGameRegistry.info): la base usa el layout.
var info: Dictionary = {}
var reaction := 0.22
var aim_error := 34.0
var noise := 0.12
var speed := 0.92
var think_every := 0.16
var skill := 0.62
## Segundos de juego que lleva el bot (solo avanza mientras el juego corre).
var time := 0.0
var rng := RandomNumberGenerator.new()

var _queue: Array = []          # [[t, axis, btn]] decisiones esperando el tiempo de reacción
var _out_axis := Vector2.ZERO   # lo último que "llegó" al juego
var _out_btn := 0
var _aim_offset := Vector2.ZERO
var _aim_timer := 0.0
var _wobble := Vector2.ZERO
var _think_timer := 0.0
var _seq := 0
var _press_timer := 0.0         # fallback: botón apretado
var _help_timer := 0.0          # ayuda: pulso del joystick o del botón
var _help_wait := -1.0          # ayuda: segundos "pensando" antes de ayudar (-1 = sin empezar)


## seed_value: 0 = al azar (partidas reales); otro = reproducible (tests).
func setup(p_player_id: int, p_slot: int, p_difficulty: int, p_info: Dictionary, seed_value: int = 0) -> void:
	player_id = p_player_id
	slot = p_slot
	difficulty = clampi(p_difficulty, 0, PROFILES.size() - 1)
	info = p_info
	var prof: Dictionary = PROFILES[difficulty]
	reaction = prof.reaction
	aim_error = prof.aim
	noise = prof.noise
	speed = prof.speed
	think_every = prof.think
	skill = prof.skill
	if seed_value != 0:
		rng.seed = seed_value
	else:
		rng.randomize()
	_think_timer = rng.randf() * think_every  # Que no piensen todos en el mismo frame.
	_aim_timer = 0.0
	_ready_bot()


## Nombre para mostrar de una dificultad ("Normal").
static func difficulty_name(d: int) -> String:
	return DIFFICULTY_NAMES[clampi(d, 0, DIFFICULTY_NAMES.size() - 1)]


## ¿La entrada tiene la forma y el rango que acepta la TV de un celular?
## (eje finito de largo ≤ 1 y solo los botones conocidos). Lo verifican los tests.
static func is_valid_output(out: Dictionary) -> bool:
	var axis: Variant = out.get("axis")
	var btn: Variant = out.get("btn")
	if not axis is Vector2 or typeof(btn) != TYPE_INT:
		return false
	var a := axis as Vector2
	return is_finite(a.x) and is_finite(a.y) and a.length() <= 1.0001 and (int(btn) & ~Protocol.BTN_MASK) == 0


## Un paso: decide, agrega el temblor de la mano y aplica el tiempo de
## reacción. Devuelve la entrada cruda {axis, btn} (BotDriver la valida).
func tick(view: Dictionary, delta: float) -> Dictionary:
	time += delta
	_aim_timer -= delta
	if _aim_timer <= 0.0:
		_aim_timer = rng.randf_range(AIM_CHANGE_SEC.x, AIM_CHANGE_SEC.y)
		_aim_offset = Vector2.from_angle(rng.randf() * TAU) * aim_error * sqrt(rng.randf())
	# Eliminado y con ayudas (HelpSession): elige y ayuda en vez de jugar.
	var wanted := decide_help(view.help, delta) if view.has("help") else decide(view, delta)
	var axis: Vector2 = wanted.get("axis", Vector2.ZERO)
	var btn: int = int(wanted.get("btn", 0)) & Protocol.BTN_MASK
	if axis.length() > 0.05 and noise > 0.0:
		_wobble = _wobble.lerp(Vector2(rng.randf_range(-1, 1), rng.randf_range(-1, 1)) * noise, minf(1.0, delta * 8.0))
		axis += _wobble
	axis = axis.limit_length(1.0)
	if not (is_finite(axis.x) and is_finite(axis.y)):
		axis = Vector2.ZERO
	# Tiempo de reacción: lo decidido ahora llega al juego `reaction` segundos después.
	_queue.append([time, axis, btn])
	while _queue.size() > 1 and time - float(_queue[1][0]) >= reaction:
		_queue.pop_front()
	if time - float(_queue[0][0]) >= reaction:
		_out_axis = _queue[0][1]
		_out_btn = _queue[0][2]
	return {"axis": _out_axis, "btn": _out_btn}


func next_seq() -> int:
	_seq += 1
	return _seq


# --- Para sobrescribir en cada juego ----------------------------------------------

## Preparación propia del bot de un juego (después de setup).
func _ready_bot() -> void:
	pass


## Qué haría una persona ahora: {axis: Vector2, btn: int}. `view` es
## MiniGame.bot_view() (solo lectura). La base: entradas suaves al azar
## según el control del juego, para juegos que todavía no tienen bot.
func decide(_view: Dictionary, delta: float) -> Dictionary:
	var k := float(slot) * 1.7 + float(player_id)
	match str(info.get("layout", "")):
		Protocol.LAYOUT_JOYSTICK:
			return {"axis": Vector2.from_angle(time * 0.7 + k) * 0.45, "btn": 0}
		Protocol.LAYOUT_SLIDER_H:
			return {"axis": Vector2(sin(time * 0.8 + k) * 0.6, 0.0), "btn": 0}
		Protocol.LAYOUT_ONE_BUTTON:
			_press_timer -= delta
			if _press_timer < -rng.randf_range(0.5, 1.2):
				_press_timer = 0.12
			return {"axis": Vector2.ZERO, "btn": Protocol.BTN_A if _press_timer > 0.0 else 0}
	return {"axis": Vector2.ZERO, "btn": 0}


## Ayuda de los eliminados (MODOS.md §11, ADR 0020): el bot eliminado ayuda
## UNA vez por juego al que va último en la competencia, si le alcanzan los
## puntos. Como una persona: piensa un momento, empuja el joystick hacia la
## mascota de ese jugador hasta que la TV lo marca y aprieta A. Nunca decide
## nada: la TV valida, cobra y aplica. `view`: HelpSession.bot_view().
func decide_help(view: Dictionary, delta: float) -> Dictionary:
	var last := int(view.get("last", -1))
	if last == -1 or int(view.get("used", 0)) >= 1 or not bool(view.get("can_afford", false)) \
			or bool(view.get("busy", false)) or float(view.get("wait", 0.0)) > 0.0:
		return idle()
	if _help_wait < 0.0:
		_help_wait = lerpf(1.6, 0.6, skill) + rng.randf() * 0.8
	_help_wait -= delta
	if _help_wait > 0.0:
		return idle()
	# Pulsos: 0,15 s apretado y 0,15 s suelto (la TV cuenta cada empujón una vez).
	_help_timer += delta
	var on := fmod(_help_timer, 0.3) < 0.15
	if int(view.get("selected", -1)) != last:
		var anchors: Dictionary = view.get("candidates", {})
		var to: Vector2 = anchors.get(last, Vector2.ZERO) - (view.get("from", Vector2.ZERO) as Vector2)
		if not on or to.length() < 1.0:
			return idle()
		return {"axis": to.normalized(), "btn": 0}
	return {"axis": Vector2.ZERO, "btn": Protocol.BTN_A if on else 0}


# --- Utilidades para los bots de cada juego -----------------------------------------

## true cada `think_every` segundos (volver a elegir objetivo, plan…).
func think_due(delta: float) -> bool:
	_think_timer -= delta
	if _think_timer <= 0.0:
		_think_timer += think_every * rng.randf_range(0.8, 1.2)
		return true
	return false


## Objetivo con error de puntería: lejos se apunta "más o menos", cerca se
## corrige (como una persona). `near` = distancia a la que el error ya es chico.
func aim_at(target: Vector2, from: Vector2, near: float = 260.0) -> Vector2:
	var k := clampf(from.distance_to(target) / near, 0.15, 1.0)
	return target + _aim_offset * k


## Dónde va a estar (más o menos) cuando le llegue al juego lo que decide
## ahora: suma lo que ya "mandó" y todavía no llegó (el tiempo de reacción).
## Una persona hace lo mismo: frena antes de llegar. Sin esto, con reacción
## lenta, el bot da vueltas alrededor del objetivo. Los menos hábiles
## predicen peor. `px_per_sec`: velocidad del jugador con el joystick a fondo.
func predict(me: Vector2, px_per_sec: float) -> Vector2:
	if _queue.is_empty():
		return me
	var sum := Vector2.ZERO
	for e: Array in _queue:
		sum += e[1] as Vector2
	var ahead := minf(reaction, time) * lerpf(0.7, 1.0, skill)
	return me + sum / _queue.size() * px_per_sec * ahead


## Joystick para ir de `from` a `to`: a fondo (según `speed`) y frenando al
## llegar, para no pasarse.
func steer(from: Vector2, to: Vector2, arrive: float = 40.0) -> Vector2:
	var d := to - from
	var dist := d.length()
	if dist < 2.0:
		return Vector2.ZERO
	return d / dist * speed * clampf(dist / arrive, 0.0, 1.0)


## Número al azar con distribución normal (media 0, desvío `sd`).
func gauss(sd: float) -> float:
	return rng.randfn(0.0, sd)


## Entrada neutra (no toca nada).
static func idle() -> Dictionary:
	return {"axis": Vector2.ZERO, "btn": 0}
