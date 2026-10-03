extends MiniGame
## Memoria de colores: la TV muestra una secuencia en un tablero de Simón
## (cuatro botones que se iluminan con su sonido) y todos la repiten A LA VEZ
## con el joystick. Cada ronda la secuencia crece en uno y se muestra más
## rápido. Quien se equivoca (o no termina a tiempo) queda afuera: su mascota
## queda mareada y sigue mirando. Gana el último en pie.
##
## Control: el joystick de siempre (sin cambios de protocolo). Las cuatro
## direcciones son los cuatro botones del tablero, cada uno con color, forma
## e ícono propios (no depende solo del color):
##   arriba = estrella · derecha = corazón · abajo = rombo · izquierda = círculo
##
## Concepto: *flanco*. El celular manda la posición del joystick unas 30
## veces por segundo, no "toques". Una pulsación es el paso de "centro" a
## "dirección": se cuenta una sola vez y para la siguiente hay que volver al
## centro (aunque se repita el mismo símbolo). Zona muerta y umbral:
##   largo < DEAD_ZONE        centro: rearma la pulsación.
##   largo >= PRESS_AT        cuenta, si viene del centro y apunta claro a una
##                            dirección (a menos de ~35° de un eje; en las
##                            diagonales no cuenta y sigue armado).
##   entre los dos            no hace nada (histéresis: el temblor del dedo
##                            no genera pulsaciones dobles).
##
## Puntaje: rondas completadas (largo de la secuencia más larga que repitió).
## Se suma apenas termina de repetirla. Termina cuando queda uno solo en pie
## (con 1 jugador, cuando se equivoca) o al llegar al tope de TOTAL_TIME: ahí
## gana quien completó más rondas (desempate por rondas; si empatan, ganan
## todos los empatados).
##
## La TV es autoritativa: el celular solo manda `axis`; la secuencia, los
## aciertos y los errores se deciden acá. Las fichas de cada jugador se
## llenan con su color, no con el símbolo: así nadie copia al de al lado.

enum Phase { COUNTDOWN, SHOW, INPUT, ROUND_END, END }

## Símbolos (= direcciones del joystick), en el orden de UiTheme.MEMORY_PADS.
const UP := 0
const RIGHT := 1
const DOWN := 2
const LEFT := 3
const DIRS: Array[Vector2] = [Vector2.UP, Vector2.RIGHT, Vector2.DOWN, Vector2.LEFT]
const SYMBOL_NAMES: Array[String] = ["estrella", "corazón", "rombo", "círculo"]
const SOUNDS: Array[String] = ["memo_star", "memo_heart", "memo_diamond", "memo_circle"]
## Resultado de direction_of() cuando no apunta a ningún botón.
const CENTER := -1       ## Dentro de la zona muerta: rearma.
const NO_DIRECTION := -2 ## Entre la zona muerta y el umbral, o en diagonal.

# Joystick.
const DEAD_ZONE := 0.35
const PRESS_AT := 0.7
const AXIS_COS := 0.82   ## cos(35°): qué tan cerca de un eje tiene que apuntar.

# Ritmo (segundos).
const COUNTDOWN := 3.0
const TOTAL_TIME := 90.0         ## Tope de la partida (sin la cuenta regresiva).
const WATCH_LEAD := 0.8          ## "¡Mirá!" antes de mostrar la secuencia.
const STEP_SLOW := 0.62          ## Cada símbolo en la ronda 1…
const STEP_FAST := 0.3           ## …y desde la ronda RAMP_ROUNDS + 1.
const RAMP_ROUNDS := 10.0
const LIT_FRACTION := 0.7        ## Parte de cada paso con el botón encendido.
const INPUT_BASE := 2.2          ## Tiempo para repetir: base…
const INPUT_PER_SYMBOL := 0.75   ## …más esto por símbolo.
const ROUND_END_TIME := 0.9
const END_TIME := 1.8            ## Festejo antes de terminar.
const PRESS_ANIM := 0.3
const MAX_SEQUENCE := 64         ## Tope de seguridad (en 90 s no se llega).

# Tablero (resolución lógica 1920×1080).
const BOARD_C := Vector2(960, 566)
const R_HUB := 112.0             ## Centro con el número de ronda.
const R_PAD_IN := 128.0
const R_PAD_OUT := 290.0
const R_RIM := 334.0             ## Aro de plástico con flechas y lucecitas.
const PAD_GAP := 16.0            ## Separación entre botones (px).
const PAD_LIP := 9.0             ## Canto de los botones (relieve).
const BOARD_DEPTH := 22.0
const ICON_R := 50.0
const ARC_SEGS := 18             ## Segmentos por cuarto de círculo.

# Jugadores: una tarjeta por jugador a los costados del tablero (1P y 2P a la
# izquierda, 3P y 4P a la derecha, como en el marcador).
const SLOT_X: Array[float] = [318.0, 1602.0]
const SLOT_FEET_Y: Array[float] = [452.0, 906.0]
const MASCOT_SCALE := 1.5
const CARD_SIZE := Vector2(440, 384)
const TRAY_SIZE := Vector2(380, 58)
const TRAY_ABOVE_FEET := 266.0   ## Centro de la fila de fichas, arriba de los pies.
const CHIP_MAX := 40.0

var _phase := Phase.COUNTDOWN
var _t := 0.0                    # Segundos desde el arranque (con la cuenta).
var _play_t := 0.0               # Segundos de juego (sin cuenta ni festejo final).
var _phase_t := 0.0              # Segundos en la fase actual.
var _sequence: Array[int] = []
var _rng := RandomNumberGenerator.new()
var _lit := -1                   # Botón encendido (o -1).
var _lit_since := 0.0
var _shown := -1                 # Último índice de la secuencia que sonó.
var _progress: Dictionary = {}   # player_id -> aciertos en la ronda actual
var _rounds: Dictionary = {}     # player_id -> rondas completadas (puntaje)
var _out: Dictionary = {}        # player_id -> [largo de su última ronda, ficha donde falló o se quedó]
var _armed: Dictionary = {}      # player_id -> el joystick volvió al centro
var _press: Dictionary = {}      # player_id -> [dirección, anim_time de la pulsación]
var _by_time := false            # Terminó por el tope de tiempo.
var _result: Dictionary = {}

var _meshes: Dictionary = {}     # [botón, encendido] -> [puntos, colores]


static func get_info() -> Dictionary:
	return {
		"id": "memory",
		"title": "Memoria de colores",
		"description": "Mirá la secuencia del tablero y repetila con el joystick: arriba estrella, derecha corazón, abajo rombo, izquierda círculo. Volvé al centro entre uno y otro. ¡Si te equivocás, quedás afuera!",
		"min_players": 1,
		"max_players": 4,
		"layout": Protocol.LAYOUT_JOYSTICK,
		"layout_data": {},
		"accent": UiTheme.ACCENT_MEMORY,
		"score_label": "rondas",
	}


# --- Reglas (puras, para los tests) ----------------------------------------------

## Qué botón marca el joystick: UP, RIGHT, DOWN, LEFT, CENTER (zona muerta) o
## NO_DIRECTION (entre la zona muerta y el umbral, o en diagonal).
static func direction_of(axis: Vector2) -> int:
	var mag := axis.length()
	if not is_finite(mag) or mag < DEAD_ZONE:
		return CENTER
	if mag < PRESS_AT:
		return NO_DIRECTION
	var d := axis / mag
	for i in DIRS.size():
		if d.dot(DIRS[i]) >= AXIS_COS:
			return i
	return NO_DIRECTION


## Siguiente símbolo al azar; nunca tres iguales seguidos (se lee mal).
static func next_symbol(rng: RandomNumberGenerator, seq: Array[int]) -> int:
	var s := rng.randi_range(0, DIRS.size() - 1)
	var n := seq.size()
	if n >= 2 and seq[n - 1] == s and seq[n - 2] == s:
		s = (s + 1 + rng.randi_range(0, DIRS.size() - 2)) % DIRS.size()
	return s


## Secuencia de `length` símbolos para una semilla (la misma que arma el
## juego ronda a ronda con esa semilla en `_rng`).
static func sequence_for_seed(seed_value: int, length: int) -> Array[int]:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var seq: Array[int] = []
	for i in length:
		seq.append(next_symbol(rng, seq))
	return seq


## Segundos por símbolo al mostrar la ronda `round_no` (1, 2…): cada vez más rápido.
static func step_time(round_no: int) -> float:
	return lerpf(STEP_SLOW, STEP_FAST, clampf((round_no - 1) / RAMP_ROUNDS, 0.0, 1.0))


## Segundos para repetir una secuencia de `length` símbolos.
static func input_time(length: int) -> float:
	return INPUT_BASE + INPUT_PER_SYMBOL * length


# --- Ciclo del juego ---------------------------------------------------------------

func setup(p_players: Array[Dictionary]) -> void:
	super.setup(p_players)
	_rng.randomize()
	for p in players:
		_progress[p.id] = 0
		_rounds[p.id] = 0
		_armed[p.id] = false  # Hay que pasar por el centro antes de la primera.


func on_input(player_id: int, input: Dictionary) -> void:
	if not _armed.has(player_id) or is_finished():
		return
	var raw: Variant = input.get("axis", Vector2.ZERO)
	var axis: Vector2 = raw if raw is Vector2 else Vector2.ZERO
	var dir := direction_of(axis.limit_length(1.0))
	if dir == CENTER:
		_armed[player_id] = true
		return
	if dir == NO_DIRECTION or not _armed[player_id]:
		return
	# Flanco: centro -> dirección. Cuenta una vez; la próxima, al volver al centro.
	_armed[player_id] = false
	if _phase == Phase.INPUT and is_alive(player_id) and not has_completed(player_id):
		_on_press(player_id, dir)


func on_player_disconnected(player_id: int) -> void:
	super.on_player_disconnected(player_id)  # Joystick al centro; si no vuelve, se le acaba el tiempo.


func _physics_process(delta: float) -> void:
	step(delta)
	queue_redraw()


## Avanza el juego `delta` segundos (lo usan _physics_process y los tests).
func step(delta: float) -> void:
	if is_finished():
		return
	_t += delta
	_phase_t += delta
	match _phase:
		Phase.COUNTDOWN:
			tick_countdown(COUNTDOWN - (_t - delta), COUNTDOWN - _t)
			if _t >= COUNTDOWN:
				_start_round()
			return
		Phase.END:
			if _phase_t >= END_TIME:
				finish(_result)
			return
	_play_t += delta
	if _play_t >= TOTAL_TIME:
		_end_game(true)
		return
	match _phase:
		Phase.SHOW:
			_update_show()
		Phase.INPUT:
			if _phase_t >= input_time(_sequence.size()):
				_time_out()
		Phase.ROUND_END:
			if _phase_t >= ROUND_END_TIME:
				if _should_end():
					_end_game(false)
				else:
					_start_round()


func _start_round() -> void:
	if _sequence.size() < MAX_SEQUENCE:
		_sequence.append(next_symbol(_rng, _sequence))
	for pid: int in _progress:
		_progress[pid] = 0
	_set_phase(Phase.SHOW)
	_shown = -1
	_lit = -1


func _update_show() -> void:
	var step_len := step_time(_sequence.size())
	var t := _phase_t - WATCH_LEAD
	if t < 0.0:
		return
	var i := floori(t / step_len)
	if i >= _sequence.size():
		_lit = -1
		_set_phase(Phase.INPUT)
		play_sfx("select")
		notify_all("count")
		return
	var on := t - i * step_len < step_len * LIT_FRACTION
	if on and i != _shown:
		_shown = i
		_lit = _sequence[i]
		_lit_since = anim_time
		play_sfx(SOUNDS[_lit])
	elif not on:
		_lit = -1


func _on_press(pid: int, dir: int) -> void:
	_press[pid] = [dir, anim_time]
	var at: int = _progress[pid]
	if dir != _sequence[at]:
		_eliminate(pid, at)
	else:
		_progress[pid] = at + 1
		if at + 1 >= _sequence.size():
			_rounds[pid] = _sequence.size()
			play_sfx("point")
			notify_player(pid, "point")
		else:
			notify_player(pid, "tap")
	if _everyone_done():
		_set_phase(Phase.ROUND_END)


func _eliminate(pid: int, fail_index: int) -> void:
	_out[pid] = [_sequence.size(), fail_index]
	play_sfx("hit")
	notify_player(pid, "hit")


## Se acabó el tiempo para repetir: quedan afuera los que no terminaron.
func _time_out() -> void:
	for pid: int in _progress:
		if is_alive(pid) and not has_completed(pid):
			_eliminate(pid, int(_progress[pid]))
	_set_phase(Phase.ROUND_END)


func _everyone_done() -> bool:
	for pid: int in _progress:
		if is_alive(pid) and not has_completed(pid):
			return false
	return true


func _should_end() -> bool:
	var alive := alive_count()
	return alive == 0 or (players.size() > 1 and alive <= 1)


func _end_game(by_time: bool) -> void:
	_by_time = by_time
	_lit = -1
	var summary := "Se acabó el tiempo: más rondas gana" if by_time else "Último en pie gana"
	_result = result_from_scores(_rounds, summary)
	_set_phase(Phase.END)
	play_sfx("win")
	for pid: int in _rounds:
		notify_player(pid, "win" if pid in _result.winners else "lose")


func _set_phase(p: Phase) -> void:
	_phase = p
	_phase_t = 0.0


# --- Consultas ------------------------------------------------------------------

func phase() -> Phase:
	return _phase


## Es el turno de repetir la secuencia.
func accepting_input() -> bool:
	return _phase == Phase.INPUT


func sequence() -> Array[int]:
	return _sequence


func is_alive(pid: int) -> bool:
	return _progress.has(pid) and not _out.has(pid)


## Ya repitió toda la secuencia de esta ronda.
func has_completed(pid: int) -> bool:
	return int(_progress.get(pid, 0)) >= _sequence.size() and not _sequence.is_empty()


func alive_count() -> int:
	var n := 0
	for pid: int in _progress:
		if is_alive(pid):
			n += 1
	return n


func scores() -> Dictionary:
	return _rounds.duplicate()


func time_left() -> float:
	return TOTAL_TIME - _play_t


# --- Dibujo -------------------------------------------------------------------------

func _draw() -> void:
	draw_sky()
	draw_static(_draw_fixed)
	var b := GameArt.TriBatch.new()
	_add_lit_pad(b)
	_add_hub_timer(b)
	_add_chips(b)
	b.flush(self)
	_draw_hub_text()
	_draw_players()
	draw_hud(_rounds, clock_text(time_left()), "clock")


## Pies de la mascota del jugador `i` (de `n`): 1P y 2P a la izquierda, el
## resto a la derecha. Un jugador solo en su lado va abajo (arriba queda la
## ayuda de los controles, ver _draw_fixed).
func _feet_of(i: int) -> Vector2:
	var n := players.size()
	var left := ceili(n / 2.0)
	var side := 0 if i < left else 1
	var on_side := left if side == 0 else n - left
	var row := (i if side == 0 else i - left) + (1 if on_side == 1 else 0)
	return Vector2(SLOT_X[side], SLOT_FEET_Y[row])


func _card_of(feet: Vector2) -> Rect2:
	return Rect2(feet.x - CARD_SIZE.x / 2.0, feet.y - TRAY_ABOVE_FEET - 50.0, CARD_SIZE.x, CARD_SIZE.y)


func _tray_of(feet: Vector2) -> Rect2:
	return Rect2(feet - Vector2(TRAY_SIZE.x / 2.0, TRAY_ABOVE_FEET + TRAY_SIZE.y / 2.0), TRAY_SIZE)


func _pad_center(dir: int) -> Vector2:
	return BOARD_C + DIRS[dir] * (R_PAD_IN + R_PAD_OUT) / 2.0


## Lo fijo (se dibuja una vez, ver MiniGame.draw_static): el tablero con sus
## botones apagados, las tarjetas de los jugadores y la ayuda de los controles.
func _draw_fixed(ci: CanvasItem) -> void:
	var b := GameArt.TriBatch.new()
	_add_board(b)
	for d in DIRS.size():
		var m := _pad_mesh(d, false)
		b.template(m[0], m[1], Transform2D(0.0, BOARD_C))
		_add_symbol(b, d, _pad_center(d), ICON_R, UiTheme.PAPER)
	# Centro: aro con bisel y pantalla oscura.
	b.circle(BOARD_C, R_HUB + 8.0, UiTheme.INK, 48)
	b.circle(BOARD_C, R_HUB, UiTheme.MEMORY_RIM, 48)
	b.circle(BOARD_C + Vector2(0, -3), R_HUB - 6.0, UiTheme.MEMORY_RIM_LIGHT, 48)
	b.circle(BOARD_C + Vector2(0, 2), R_HUB - 14.0, UiTheme.CHIP_DARK, 48)
	var taken: Array[Vector2] = []
	for i in players.size():
		taken.append(_feet_of(i))
		_add_player_card(b, players[i], taken[i])
	# Ayuda de los controles en el primer lugar libre de arriba (con 4 no hay).
	var help := Rect2()
	for x in SLOT_X:
		var spot := Vector2(x, SLOT_FEET_Y[0])
		if not spot in taken:
			help = _card_of(spot)
			_add_help_card(b, help)
			break
	b.flush(ci)
	if help.has_area():
		UiTheme.draw_text(ci, "Mové el joystick", Vector2(help.get_center().x, help.position.y + 34), 28, UiTheme.INK)
		UiTheme.draw_text(ci, "y volvé al centro", Vector2(help.get_center().x, help.end.y - 26), 26, UiTheme.INK_SOFT)


## Tablero: sombra, canto, aro con flechas y lucecitas, y el hueco oscuro
## donde van los botones. Solo anillos: cada píxel se pinta pocas veces.
func _add_board(b: GameArt.TriBatch) -> void:
	var shadow_c := BOARD_C + Vector2(0, 38)
	b.feather_circle(shadow_c, R_RIM + 8.0, UiTheme.BOARD_SHADOW, 64, 34.0)
	b.shape(_ring(R_RIM - 40.0, R_RIM + 8.0), Transform2D(0.0, shadow_c), UiTheme.BOARD_SHADOW)
	var depth_c := BOARD_C + Vector2(0, BOARD_DEPTH)
	b.feather_circle(depth_c, R_RIM + 7.0, UiTheme.INK, 64)
	b.shape(_ring(R_RIM - 30.0, R_RIM + 7.0), Transform2D(0.0, depth_c), UiTheme.INK)
	b.shape(_ring(R_RIM - 30.0, R_RIM), Transform2D(0.0, depth_c + Vector2(0, -2)), UiTheme.MEMORY_RIM.darkened(0.35))
	b.feather_circle(BOARD_C, R_RIM + 7.0, UiTheme.INK, 64)
	b.shape(_ring(R_RIM, R_RIM + 7.0), Transform2D(0.0, BOARD_C), UiTheme.INK)
	b.shape(_ring(R_PAD_OUT, R_RIM), Transform2D(0.0, BOARD_C), UiTheme.MEMORY_RIM)
	# Luz arriba del aro (media luna más clara).
	b.shape(_ring(R_RIM - 12.0, R_RIM - 4.0, PI * 1.12, PI * 1.88), Transform2D(0.0, BOARD_C), UiTheme.MEMORY_RIM_LIGHT)
	b.shape(_ring(R_HUB, R_PAD_OUT + 6.0), Transform2D(0.0, BOARD_C), UiTheme.INK)
	# Flechas: hacia dónde mover el joystick para cada botón.
	var r_mid := (R_PAD_OUT + R_RIM) / 2.0 + 3.0
	for d in DIRS.size():
		var dir := DIRS[d]
		var side := dir.orthogonal()
		var tip := BOARD_C + dir * (r_mid + 13.0)
		var base := BOARD_C + dir * (r_mid - 11.0)
		b.tri(tip + dir * 5.0, base - dir * 3.0 + side * 21.0, base - dir * 3.0 - side * 21.0, UiTheme.INK)
		b.tri(tip, base + side * 15.0, base - side * 15.0, UiTheme.PAPER)
		# Lucecitas entre las flechas.
		for k in 3:
			var a := dir.angle() + deg_to_rad(30.0 + k * 15.0)
			var c := BOARD_C + Vector2.from_angle(a) * r_mid
			b.circle(c, 7.5, UiTheme.INK, 12)
			b.circle(c, 5.5, UiTheme.MEMORY_STUD if k != 1 else UiTheme.MEMORY_PADS[(d + 1) % 4].lightened(0.3), 12)


## Botón `dir` (apagado o encendido): canto oscuro abajo y cara con degradé
## de luz (arriba) a sombra (abajo), en coordenadas locales del tablero. Se
## arma una vez por botón y estado.
func _pad_mesh(dir: int, lit: bool) -> Array:
	var key := [dir, lit]
	if _meshes.has(key):
		return _meshes[key]
	var base: Color = UiTheme.MEMORY_PADS[dir]
	if lit:
		base = base.lerp(Color.WHITE, UiTheme.MEMORY_LIT_MIX)
	var pts := PackedVector2Array()
	var cols := PackedColorArray()
	var lip := _sector(dir, R_PAD_IN, R_PAD_OUT)
	pts.append_array(Transform2D(0.0, Vector2(0, PAD_LIP * 0.5)) * lip)
	var lip_col := base.darkened(0.42)
	for i in lip.size():
		cols.append(lip_col)
	var face := _sector(dir, R_PAD_IN + 2.0, R_PAD_OUT - 2.0)
	face = Transform2D(0.0, Vector2(0, -PAD_LIP * 0.5)) * face
	pts.append_array(face)
	var light := 0.45 if lit else 0.3
	for p in face:
		var k := clampf((p.y + R_PAD_OUT) / (2.0 * R_PAD_OUT), 0.0, 1.0)
		cols.append(base.lightened(light * (1.0 - k)).darkened(0.16 * k))
	# Reflejo: franja clara cerca del borde de afuera.
	var shine := Transform2D(0.0, Vector2(0, -PAD_LIP * 0.5)) * _sector(dir, R_PAD_OUT - 24.0, R_PAD_OUT - 13.0, 0.62)
	pts.append_array(shine)
	var shine_col := Color(1, 1, 1, 0.5 if lit else 0.32)
	for i in shine.size():
		cols.append(shine_col)
	_meshes[key] = [pts, cols]
	return _meshes[key]


## Cuarto de anillo del botón `dir` entre r0 y r1, con una separación de
## PAD_GAP px con los vecinos. `span`: fracción del ángulo (1 = entero).
static func _sector(dir: int, r0: float, r1: float, span: float = 1.0, gap: float = PAD_GAP) -> PackedVector2Array:
	var mid := DIRS[dir].angle()
	var h0 := (PI / 4.0 - asin(gap / 2.0 / r0)) * span
	var h1 := (PI / 4.0 - asin(gap / 2.0 / r1)) * span
	var tris := PackedVector2Array()
	for i in ARC_SEGS:
		var t0 := float(i) / ARC_SEGS
		var t1 := float(i + 1) / ARC_SEGS
		var a0 := Vector2.from_angle(mid - h0 + 2.0 * h0 * t0) * r0
		var a1 := Vector2.from_angle(mid - h0 + 2.0 * h0 * t1) * r0
		var b0 := Vector2.from_angle(mid - h1 + 2.0 * h1 * t0) * r1
		var b1 := Vector2.from_angle(mid - h1 + 2.0 * h1 * t1) * r1
		tris.append_array([a0, b0, b1, a0, b1, a1])
	return tris


## Anillo entre r0 y r1 (o un arco, de a0 a a1 radianes) centrado en (0, 0).
static func _ring(r0: float, r1: float, a0: float = 0.0, a1: float = TAU, segs: int = 72) -> PackedVector2Array:
	var inner := PackedVector2Array()
	var outer := PackedVector2Array()
	var full := is_equal_approx(a1 - a0, TAU)
	var n := segs if full else segs + 1
	for i in n:
		var d := Vector2.from_angle(a0 + (a1 - a0) * i / segs)
		inner.append(d * r0)
		outer.append(d * r1)
	var tris := GameArt.ring_tris(inner, outer)
	if not full:
		tris.resize(tris.size() - 6)  # Sin el tramo que cierra el anillo.
	return tris


## Ícono del botón `sym` con contorno de tinta: estrella, corazón, rombo o círculo.
static func _add_symbol(b: GameArt.TriBatch, sym: int, c: Vector2, r: float, fill: Color, outline: float = 6.0) -> void:
	match sym:
		UP:
			b.star(c + Vector2(0, 2), r, fill, 0.0, outline)
		RIGHT:
			_add_heart(b, c, r + outline, UiTheme.INK)
			_add_heart(b, c, r, fill)
		DOWN:
			var k := outline * 1.4
			b.polygon(PackedVector2Array([c + Vector2(0, -r - k), c + Vector2(r * 0.78 + k, 0), c + Vector2(0, r + k),
				c + Vector2(-r * 0.78 - k, 0)]), UiTheme.INK)
			b.polygon(PackedVector2Array([c + Vector2(0, -r), c + Vector2(r * 0.78, 0), c + Vector2(0, r),
				c + Vector2(-r * 0.78, 0)]), fill)
		_:
			b.circle(c, r * 0.82 + outline, UiTheme.INK, 28)
			b.circle(c, r * 0.82, fill, 28)
	# Brillo chico arriba a la izquierda (plástico).
	if sym != UP:
		b.circle(c + Vector2(-r * 0.3, -r * 0.34), r * 0.14, Color(1, 1, 1, 0.55), 10)


## Corazón de radio ~r: dos círculos arriba y una punta abajo.
static func _add_heart(b: GameArt.TriBatch, c: Vector2, r: float, col: Color) -> void:
	var lobe := r * 0.5
	b.circle(c + Vector2(-r * 0.46, -r * 0.3), lobe, col, 20)
	b.circle(c + Vector2(r * 0.46, -r * 0.3), lobe, col, 20)
	b.polygon(PackedVector2Array([c + Vector2(-r * 0.93, -r * 0.14), c + Vector2(0, -r * 0.42), c + Vector2(r * 0.93, -r * 0.14),
		c + Vector2(0, r * 0.9)]), col)


## Tarjeta del jugador (fija): fondo claro, bandeja oscura de las fichas y
## el pedestal de su color donde se para la mascota.
func _add_player_card(b: GameArt.TriBatch, p: Dictionary, feet: Vector2) -> void:
	var card := _card_of(feet)
	_add_card(b, card)
	var tray := _tray_of(feet)
	b.feather_capsule(tray.grow(4.0), UiTheme.INK)
	b.capsule(tray.grow(4.0), UiTheme.INK)
	b.capsule(tray, UiTheme.CHIP_DARK)
	var col: Color = p.color
	var plate := Rect2(feet.x - 130.0, feet.y - 14.0, 260.0, 46.0)
	b.capsule(plate.grow(4.0).grow_side(SIDE_BOTTOM, 4.0), UiTheme.INK)
	b.capsule(plate.grow_side(SIDE_BOTTOM, 4.0), col.darkened(0.35))
	b.capsule(plate, col)
	b.capsule(Rect2(plate.position + Vector2(24, 5), Vector2(plate.size.x - 48, 9)), Color(1, 1, 1, 0.32))


func _add_help_card(b: GameArt.TriBatch, card: Rect2) -> void:
	_add_card(b, card)
	var c := card.get_center() + Vector2(0, 8)
	# Joystick en el medio y los cuatro botones alrededor, con su flecha.
	b.circle(c, 38.0, UiTheme.INK, 28)
	b.circle(c, 32.0, UiTheme.MUTED, 28)
	b.circle(c + Vector2(0, -3), 22.0, UiTheme.INK_SOFT, 24)
	for d in DIRS.size():
		var dir := DIRS[d]
		var at := c + dir * Vector2(136, 102)
		var col: Color = UiTheme.MEMORY_PADS[d]
		b.circle(at, 40.0, UiTheme.INK, 28)
		b.circle(at, 34.0, col, 28)
		_add_symbol(b, d, at, 20.0, UiTheme.PAPER, 4.0)
		var tip := c + dir * (52.0 if dir.x == 0.0 else 74.0)
		var side := dir.orthogonal()
		b.tri(tip + dir * 8.0, tip - dir * 6.0 + side * 11.0, tip - dir * 6.0 - side * 11.0, UiTheme.INK)


static func _add_card(b: GameArt.TriBatch, card: Rect2) -> void:
	GameArt.add_soft_shadow(b, card, 30.0, 14.0, 18.0)
	b.feather_round_rect(card.grow(5.0), 35.0, UiTheme.INK)
	b.round_rect(card.grow(5.0), 35.0, UiTheme.INK)
	b.round_rect(card, 30.0, UiTheme.MEMORY_CARD)


## Mientras la TV muestra la secuencia, los botones apagados se oscurecen y
## el encendido brilla con halo y borde blanco (cambia en cada frame).
func _add_lit_pad(b: GameArt.TriBatch) -> void:
	if _phase != Phase.SHOW:
		return
	for d in DIRS.size():
		if d != _lit:
			b.template(_dim_mesh(d), _dim_colors(d), Transform2D(0.0, BOARD_C))
	if _lit < 0:
		return
	var k := clampf((anim_time - _lit_since) / 0.12, 0.0, 1.0)  # Se prende rápido.
	var col: Color = UiTheme.MEMORY_PADS[_lit].lerp(Color.WHITE, 0.3)
	var c := _pad_center(_lit)
	var glow_c := BOARD_C + DIRS[_lit] * R_PAD_OUT * 0.72
	b.radial(glow_c, 300.0 * (0.85 + 0.15 * k), Color(col, 0.9 * k), Color(col, 0.0), 40)
	var rim := _dim_mesh(_lit, true)
	b.shape(rim, Transform2D(0.0, BOARD_C + Vector2(0, -PAD_LIP * 0.5)), Color(UiTheme.PAPER, 0.95 * k))
	var m := _pad_mesh(_lit, true)
	b.template(m[0], m[1], Transform2D(0.0, BOARD_C))
	# Foco de luz en el medio del botón, como una lamparita detrás del plástico.
	b.radial(c, 120.0, Color(1, 1, 1, 0.55 * k), Color(1, 1, 1, 0.0), 32)
	_add_symbol(b, _lit, c + Vector2(0, -PAD_LIP * 0.5), ICON_R * (1.0 + 0.16 * k), UiTheme.PAPER)


## Sombra que apaga el botón `dir` mientras se muestra la secuencia (o, con
## `rim`, el borde blanco un poco más grande del botón encendido). Se arma una vez.
func _dim_mesh(dir: int, rim: bool = false) -> PackedVector2Array:
	var key := [dir, "rim" if rim else "dim"]
	if not _meshes.has(key):
		if rim:
			_meshes[key] = _sector(dir, R_PAD_IN - 5.0, R_PAD_OUT + 5.0, 1.0, PAD_GAP - 8.0)
		else:
			_meshes[key] = Transform2D(0.0, Vector2(0, -PAD_LIP * 0.5)) * _sector(dir, R_PAD_IN + 2.0, R_PAD_OUT - 2.0)
	return _meshes[key]


func _dim_colors(dir: int) -> PackedColorArray:
	return GameArt.pattern_colors(PackedColorArray([UiTheme.MEMORY_DIM]), _dim_mesh(dir).size())


## Tiempo para repetir: arco que se achica alrededor del centro.
func _add_hub_timer(b: GameArt.TriBatch) -> void:
	if _phase != Phase.INPUT:
		return
	var left := clampf(1.0 - _phase_t / input_time(_sequence.size()), 0.0, 1.0)
	if left <= 0.0:
		return
	var col := UiTheme.ACCENT if left > 0.3 else UiTheme.DANGER
	var segs := maxi(2, ceili(64 * left))
	b.shape(_ring(R_HUB - 12.0, R_HUB - 2.0, -PI / 2.0, -PI / 2.0 + TAU * left, segs), Transform2D(0.0, BOARD_C), col)


## Fichas de cada jugador: una por símbolo de la ronda, llenas con su color a
## medida que acierta (sin mostrar el símbolo: nadie copia al de al lado).
func _add_chips(b: GameArt.TriBatch) -> void:
	for i in players.size():
		var p: Dictionary = players[i]
		var pid: int = p.id
		var tray := _tray_of(_feet_of(i))
		var out: Array = _out.get(pid, [])
		var n := _sequence.size() if out.is_empty() else int(out[0])
		if _phase == Phase.COUNTDOWN or n <= 0:
			continue
		var filled: int = _progress.get(pid, 0) if out.is_empty() else int(out[1])
		var gap := 6.0
		var d := minf(CHIP_MAX, (tray.size.x - 24.0 - gap * (n - 1)) / n)
		var x := tray.get_center().x - (d * n + gap * (n - 1)) / 2.0 + d / 2.0
		var pressed: Array = _press.get(pid, [])
		var pop := 0.0
		if not pressed.is_empty():
			pop = maxf(0.0, 1.0 - (anim_time - float(pressed[1])) / PRESS_ANIM)
		for k in n:
			var c := Vector2(x + k * (d + gap), tray.get_center().y)
			var r := d / 2.0
			if not out.is_empty() and k == int(out[1]):
				b.circle(c, r, UiTheme.DANGER, 20)
				var s := r * 0.42
				b.line(c + Vector2(-s, -s), c + Vector2(s, s), UiTheme.PAPER, maxf(3.0, r * 0.28))
				b.line(c + Vector2(-s, s), c + Vector2(s, -s), UiTheme.PAPER, maxf(3.0, r * 0.28))
			elif k < filled:
				var grow := 1.0 + (0.3 * pop if k == filled - 1 else 0.0)
				var col: Color = p.color if out.is_empty() else p.color.lerp(UiTheme.MEMORY_SOCKET, 0.5)
				b.circle(c, r * grow + 2.0, UiTheme.PAPER, 20)
				b.circle(c, r * grow, col, 20)
				b.circle(c + Vector2(-r * 0.28, -r * 0.3), r * 0.26, Color(1, 1, 1, 0.55), 10)
			else:
				b.circle(c, r, UiTheme.MEMORY_SOCKET, 20)
				b.circle(c + Vector2(0, r * 0.18), r * 0.7, UiTheme.CHIP_DARK, 16)


## Número de ronda y qué hacer, en la pantalla del centro.
func _draw_hub_text() -> void:
	var c := BOARD_C
	match _phase:
		Phase.COUNTDOWN:
			var n := ceili(COUNTDOWN - _t)
			draw_text_centered("%d" % maxi(n, 1), c + Vector2(0, -8), 110, UiTheme.ACCENT)
			draw_text_centered("¡Preparados!", c + Vector2(0, 60), 24, UiTheme.PAPER)
		Phase.END:
			draw_text_centered("¡Fin!", c + Vector2(0, -6), 64, UiTheme.ACCENT)
			draw_text_centered("¡Tiempo!" if _by_time else "Ronda %d" % _sequence.size(), c + Vector2(0, 52), 24, UiTheme.PAPER)
		_:
			var status := "¡Mirá!"
			if _phase == Phase.INPUT:
				status = "¡Repetí!"
			elif _phase == Phase.ROUND_END:
				status = "¡Bien!" if alive_count() > 0 else "¡Uy!"
			draw_text_centered("RONDA", c + Vector2(0, -60), 24, UiTheme.MUTED)
			draw_text_centered("%d" % _sequence.size(), c + Vector2(0, 0), 96, UiTheme.ACCENT)
			draw_text_centered(status, c + Vector2(0, 60), 28, UiTheme.PAPER)


func _draw_players() -> void:
	var dizzy := GameArt.TriBatch.new()
	var tags: Array = []
	var ended := _phase == Phase.END
	for i in players.size():
		var p: Dictionary = players[i]
		var pid: int = p.id
		var feet := _feet_of(i)
		var mood: int = PlayerAvatar.Mood.NORMAL
		var look := (BOARD_C - feet).normalized() * 0.6
		var hop := 0.0
		var xform := Transform2D.IDENTITY
		if _lit >= 0:
			look = (_pad_center(_lit) - (feet + Vector2(0, -80))).normalized()
		var pressed: Array = _press.get(pid, [])
		if not pressed.is_empty() and anim_time - float(pressed[1]) < PRESS_ANIM:
			var k := (anim_time - float(pressed[1])) / PRESS_ANIM
			look = DIRS[int(pressed[0])]
			hop = sin(k * PI) * 14.0
		if _out.has(pid):
			mood = PlayerAvatar.Mood.SAD
			look = Vector2.ZERO
			# Mareada: se bambolea y le giran estrellitas sobre la cabeza.
			var wobble := sin(anim_time * 3.2 + i) * 0.07
			xform = Transform2D(0.0, feet) * Transform2D(wobble, Vector2.ZERO) * Transform2D(0.0, -feet)
			var head := feet + Vector2(0, -92.0 * MASCOT_SCALE)
			for s in 3:
				var a := anim_time * 3.0 + s * TAU / 3.0
				dizzy.star(head + Vector2(cos(a) * 62.0, sin(a) * 14.0), 12.0, UiTheme.GOLD, a, 3.0)
		elif ended and pid in _result.get("winners", []):
			mood = PlayerAvatar.Mood.HAPPY
			hop = absf(sin(_phase_t * 7.0)) * 16.0
		elif has_completed(pid) and _phase != Phase.SHOW:
			mood = PlayerAvatar.Mood.HAPPY
		var anim := {"t": anim_time + p.slot, "look": look, "wave": mood == PlayerAvatar.Mood.HAPPY, "xform": xform}
		PlayerAvatar.draw_mascot(self, feet, MASCOT_SCALE, p.color, PlayerAvatar.style_of(p), mood, 0.0, hop, false, anim)
		draw_set_transform_matrix(Transform2D.IDENTITY)
		tags.append([p, feet, MASCOT_SCALE, 22.0])
	dizzy.flush(self)
	draw_player_tags(tags)
	# "¡Afuera!" sobre la bandeja de los eliminados (sigue viendo el juego).
	for i in players.size():
		if _out.has(players[i].id):
			var tray := _tray_of(_feet_of(i))
			var pill := Rect2(tray.get_center() - Vector2(84, 22), Vector2(168, 44))
			UiTheme.draw_round_rect(self, pill.grow(4.0), UiTheme.INK, 26)
			UiTheme.draw_round_rect(self, pill, UiTheme.DANGER, 22)
			draw_text_centered("¡Afuera!", pill.get_center(), 28, UiTheme.PAPER)
