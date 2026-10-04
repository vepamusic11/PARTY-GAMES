extends MiniGame
## Desenfunde: duelo del Oeste a un botón. Las mascotas, con sombrero de
## vaquero, esperan en la calle de un pueblo al atardecer. El cartel de madera
## dice "Preparados…" y, en un momento al azar, "¡YA!": el primero en tocar
## gana la ronda. Tocar antes es "¡Muy temprano!" y esa ronda se pierde.
## Desde la 2ª ronda la TV a veces engaña con un cartel trampa ("¡YA…mate!",
## "¡YAcaré!" o un cartel dorado igual al de verdad que dice "¡YO!"): tocar
## durante un cartel trampa también es "¡Muy temprano!".
##
## 5 rondas. Puntos por ronda: WIN_POINTS al ganador (a igual tiempo, a
## todos los empatados) y a cada uno que disparó a tiempo un bonus por
## velocidad (speed_bonus). Al final gana el de más puntos; a igualdad, el
## de mejor tiempo de reacción (rank_winners).
##
## Cada jugador dispara una sola vez por ronda (flanco de subida del botón,
## como en tap_race: mantener apretado no cuenta).
##
## Justicia de red (el tiempo lo mide la TV, nunca el celular):
##   - La TV marca el "¡YA!" en el paso de física en que aparece y cada toque
##     cuando llega el mensaje `btn`. El tiempo de reacción es el reloj del
##     juego entre los dos (se frena con la pausa) más lo que pasó desde el
##     último paso de física (reloj real, `wall_clock_usec`).
##   - HostServer lee la red una vez por frame: dos toques que llegan en la
##     misma lectura empatan (sello compartido, ver _stamp_usec). La precisión
##     real es de un frame (≈ 17 ms a 60 fps), igual para todos.
##   - Limitación: el tiempo incluye la latencia de la red de cada celular
##     (Wi-Fi local: típicamente 5–30 ms, con picos) y la demora de la TV en
##     mostrar la imagen (igual para todos). Un celular con peor Wi-Fi queda
##     en desventaja por su diferencia de latencia.
##   - Compensación: si el jugador trae "latency_ms" (latencia de ida medida
##     por HostServer), se descuenta (recortada a MAX_LATENCY_COMP_MS). HOY
##     HostServer no la mide (el `ping` lo inicia el celular y la TV solo
##     responde), así que vale 0. Mejora pendiente: que la TV mande pings
##     propios y guarde la mediana de la latencia de cada jugador.
##   - El "¡YA!" no vibra en los celulares: la señal es la TV, y la vibración
##     llegaría antes a quien tenga mejor Wi-Fi.
##
## Azar: `_rng` (semilla fija en tests y miniaturas). La ronda se sortea al
## empezar (en el primer paso de física), así una semilla puesta después de
## setup() ya vale para la ronda 1.

enum Phase { READY, GO, RESULT }

const ROUNDS := 5
const ROUND_INTRO := 1.0        ## "Ronda N": todavía no cuenta como temprano.
const READY_MIN := 1.4          ## "Preparados…" dura al azar entre esto…
const READY_MAX := 3.8          ## …y esto (sin cartel trampa).
const TRICK_CHANCE := 0.5       ## Probabilidad de cartel trampa (desde la ronda 2).
const TRICK_TIME := 0.9         ## Segundos que se ve el cartel trampa.
const TRICK_TEASE := 0.4        ## "¡YA…" solo, antes de completar "¡YA…mate!".
const TRICK_LEAD_MIN := 0.7     ## Entre el fin del cartel trampa y el ¡YA! real…
const TRICK_LEAD_MAX := 2.0     ## …pasa al menos/a lo sumo esto.
const GO_WINDOW := 1.5          ## Segundos para disparar después del ¡YA!.
const RESULT_TIME := 2.6        ## Segundos mostrando los tiempos de la ronda.
const WIN_POINTS := 100
const SPEED_BONUS_MAX := 50
const SPEED_BONUS_ZERO_MS := 1000.0   ## Desde acá el disparo no da bonus.
const SPEED_BONUS_MS_PER_POINT := 15.0
const MAX_SUBFRAME_USEC := 34000      ## Tope de lo medido con el reloj real (2 frames).
const MAX_LATENCY_COMP_MS := 150.0
const TICK_PERIOD := 0.5              ## Tic-tac de la tensión (ritmo fijo: no delata el ¡YA!).
const NO_TIME := -1

## Carteles trampa. tease: lo que se ve primero; gold: cartel falso con el
## mismo dorado que el ¡YA! de verdad.
const TRICKS: Array[Dictionary] = [
	{"text": "¡YA…mate!", "tease": "¡YA…", "gold": false},
	{"text": "¡YAcaré!", "tease": "", "gold": false},
	{"text": "¡YO!", "tease": "", "gold": true},
]

# Medidas del dibujo (resolución lógica 1920×1080).
const HORIZON_Y := 600.0
const SIGN_PIVOT := Vector2(960, 132)          ## De dónde cuelga el cartel.
const SIGN_SIZE := Vector2(820, 250)
const SIGN_TEXT_MAX := 740.0
const SIGN_TEXT_SIZE := 104
const SIGN_GO_SIZE := 180
const ROPE_TOP_Y := 96.0
const FEET_Y := 846.0
const MASCOT_SCALE := 1.65   ## Por debajo de PlayerAvatar.LOD_U: mallas livianas (4 mascotas por frame).
const PLAQUE_SIZE := Vector2(236, 64)
const PLAQUE_DY := 96.0                        ## Centro de la placa debajo de los pies.
const PLAQUE_TEXT_SIZE := 36
const PLAQUE_SMALL_SIZE := 28
const POPUP_SIZE := 44
const TUMBLE_Y := 772.0
const TUMBLE_R := 36.0
const TUMBLE_TIME := 3.4

var _rng := RandomNumberGenerator.new()
## Reloj real en microsegundos (se reemplaza en los tests).
var wall_clock_usec: Callable = Time.get_ticks_usec

var _round := 0                 # 0: todavía no empezó.
var _phase := Phase.READY
var _phase_t := 0.0             # Segundos en la fase actual.
var _t := 0.0                   # Reloj del juego (se frena con la pausa).
var _ticks := 0
var _tick_wall := 0             # Reloj real en el último paso de física.
var _go_at := 0.0               # Tiempo de fase (READY) en que sale el ¡YA!.
var _trick := -1                # Índice en TRICKS o -1.
var _trick_at := 0.0            # Tiempo de fase (READY) del cartel trampa.
var _go_t := 0.0                # Reloj del juego en el ¡YA!.
var _stamp_key: Array = []      # [frame, paso] de la última lectura de la red.
var _stamp_usec := 0

var _was_down: Dictionary = {}  # player_id -> bool
var _early: Dictionary = {}     # player_id -> true (esta ronda)
var _react: Dictionary = {}     # player_id -> µs de reacción (esta ronda)
var _shot_t: Dictionary = {}    # player_id -> reloj del juego al disparar (animación)
var _round_winners: Array[int] = []
var _round_gain: Dictionary = {}  # player_id -> puntos de esta ronda
var _points: Dictionary = {}    # player_id -> total
var _wins: Dictionary = {}      # player_id -> rondas ganadas
var _best: Dictionary = {}      # player_id -> mejor reacción en µs
var history: Array[Dictionary] = []  ## Una entrada por ronda: {go_at, trick, winners, react, early}.

# Arte precalculado (ver _draw).
var _sign_wood: GameArt.TriBatch
var _sign_gold: GameArt.TriBatch
static var _fit_cache: Dictionary = {}  # "tamaño|texto" -> tamaño que entra en el cartel
var _hats: Dictionary = {}      # color de la cinta -> [puntos, colores] (unidad u = 1)


static func get_info() -> Dictionary:
	return {
		"id": "quickdraw",
		"title": "Desenfunde",
		"description": "Cuando el cartel diga ¡YA!, tocá lo más rápido que puedas. Si tocás antes, perdés la ronda. ¡Ojo con los carteles tramposos!",
		"min_players": 1,
		"max_players": 4,
		"layout": Protocol.LAYOUT_ONE_BUTTON,
		"layout_data": {"label": "¡PUM!", "hint": "Tocá solo cuando la TV diga ¡YA!"},
		"accent": UiTheme.ACCENT_QUICKDRAW,
		"score_label": "puntos",
	}


## Bonus por velocidad de un disparo a tiempo (0..SPEED_BONUS_MAX).
static func speed_bonus(ms: float) -> int:
	return clampi(roundi((SPEED_BONUS_ZERO_MS - ms) / SPEED_BONUS_MS_PER_POINT), 0, SPEED_BONUS_MAX)


## Ganadores del juego: más puntos; a igualdad, mejor reacción (menos µs;
## quien nunca disparó a tiempo va último); si sigue el empate, todos.
static func rank_winners(points: Dictionary, best: Dictionary) -> Array[int]:
	var top := -INF
	for pid: int in points:
		top = maxf(top, float(points[pid]))
	var tied: Array[int] = []
	for pid: int in points:
		if float(points[pid]) == top:
			tied.append(pid)
	var fastest := INF
	for pid in tied:
		fastest = minf(fastest, float(best.get(pid, INF)))
	var out: Array[int] = []
	for pid in tied:
		if float(best.get(pid, INF)) == fastest:
			out.append(pid)
	return out


func setup(p_players: Array[Dictionary]) -> void:
	super.setup(p_players)
	_rng.randomize()
	for p in players:
		_was_down[p.id] = false
		_points[p.id] = 0
		_wins[p.id] = 0


# --- Reglas ---------------------------------------------------------------------

func on_input(player_id: int, input: Dictionary) -> void:
	if not _was_down.has(player_id) or is_finished():
		return
	var down := (int(input.get("btn", 0)) & Protocol.BTN_A) != 0
	var pressed: bool = down and not _was_down[player_id]
	_was_down[player_id] = down
	if not pressed or _round == 0 or _early.has(player_id) or _react.has(player_id):
		return
	if _phase == Phase.READY and _phase_t >= ROUND_INTRO:
		_early[player_id] = true
		_shot_t[player_id] = _t
		play_sfx("lose")
		notify_player(player_id, "lose")
	elif _phase == Phase.GO:
		_react[player_id] = _reaction_usec(player_id)
		_shot_t[player_id] = _t
		play_sfx("pop", 1.0 + 0.1 * _react.size())
		notify_player(player_id, "tap")


## Microsegundos desde el ¡YA! hasta que llegó el toque (ver "Justicia de red").
func _reaction_usec(player_id: int) -> int:
	var key := [Engine.get_process_frames(), _ticks]
	if key != _stamp_key:  # Primera lectura de la red en este frame: se sella una vez.
		_stamp_key = key
		_stamp_usec = int(wall_clock_usec.call())
	var sub := clampi(_stamp_usec - _tick_wall, 0, MAX_SUBFRAME_USEC)
	var usec := roundi((_t - _go_t) * 1000000.0) + sub
	return maxi(0, usec - roundi(latency_ms(player_id) * 1000.0))


## Latencia de ida del jugador que se descuenta (0 si HostServer no la midió).
func latency_ms(player_id: int) -> float:
	var raw: Variant = player_by_id(player_id).get("latency_ms", 0.0)
	if typeof(raw) != TYPE_INT and typeof(raw) != TYPE_FLOAT:
		return 0.0
	var ms := float(raw)
	return clampf(ms, 0.0, MAX_LATENCY_COMP_MS) if is_finite(ms) else 0.0


func _physics_process(delta: float) -> void:
	if is_finished():
		return
	if _round == 0:
		_start_round(1)
	_ticks += 1
	_t += delta
	_tick_wall = int(wall_clock_usec.call())
	var before := _phase_t
	_phase_t += delta
	match _phase:
		Phase.READY:
			_ready_sounds(before, _phase_t)
			if _early.size() == players.size() and not players.is_empty():
				_end_round()  # Todos se adelantaron: no hace falta esperar el ¡YA!.
			elif _phase_t >= _go_at:
				_start_go()
		Phase.GO:
			if _phase_t >= GO_WINDOW or _early.size() + _react.size() >= players.size():
				_end_round()
		Phase.RESULT:
			if _phase_t >= RESULT_TIME:
				if _round >= ROUNDS:
					finish({"winners": rank_winners(_points, _best), "scores": _points.duplicate(),
						"summary": "Más rápido en desenfundar"})
				else:
					_start_round(_round + 1)
	request_redraw()


func _start_round(n: int) -> void:
	_round = n
	_phase = Phase.READY
	_phase_t = 0.0
	_early.clear()
	_react.clear()
	_shot_t.clear()
	_round_winners = []
	_round_gain.clear()
	_trick = -1
	if n >= 2 and _rng.randf() < TRICK_CHANCE:
		_trick = _rng.randi_range(0, TRICKS.size() - 1)
		_trick_at = ROUND_INTRO + _rng.randf_range(0.6, 2.0)
		_go_at = _trick_at + TRICK_TIME + _rng.randf_range(TRICK_LEAD_MIN, TRICK_LEAD_MAX)
	else:
		_go_at = ROUND_INTRO + _rng.randf_range(READY_MIN, READY_MAX)


func _start_go() -> void:
	_phase = Phase.GO
	_phase_t = 0.0
	_go_t = _t
	play_sfx("go")


func _end_round() -> void:
	_phase = Phase.RESULT
	_phase_t = 0.0
	var fastest := INF
	for pid: int in _react:
		fastest = minf(fastest, float(_react[pid]))
	_round_winners = []
	for pid: int in _react:
		var gain := speed_bonus(_react[pid] / 1000.0)
		if float(_react[pid]) == fastest:
			_round_winners.append(pid)
			gain += WIN_POINTS
		_round_gain[pid] = gain
		_points[pid] = int(_points[pid]) + gain
		_best[pid] = mini(int(_best.get(pid, _react[pid])), int(_react[pid]))
	for pid in _round_winners:
		_wins[pid] = int(_wins[pid]) + 1
		notify_player(pid, "win")
	for pid: int in _react:
		if not pid in _round_winners:
			notify_player(pid, "point")
	play_sfx("win" if not _round_winners.is_empty() else "lose")
	history.append({"go_at": _go_at, "trick": _trick, "winners": _round_winners.duplicate(),
		"react": _react.duplicate(), "early": _early.keys()})


## Tensión: tic-tac a ritmo fijo y un "bum" grave por segundo (no delatan
## cuándo sale el ¡YA!); el cartel trampa suena distinto que el de verdad.
func _ready_sounds(before: float, after: float) -> void:
	if after < ROUND_INTRO:
		return
	var a := floori((before - ROUND_INTRO) / TICK_PERIOD)
	var b := floori((after - ROUND_INTRO) / TICK_PERIOD)
	if b > a and before >= ROUND_INTRO:
		play_sfx("tick", 1.0 if b % 2 == 0 else 0.75)
		if b % 2 == 0:
			play_sfx("pong", 0.5)
	if _trick >= 0 and before < _trick_at and after >= _trick_at:
		play_sfx("select", 0.7)
	var tumble_at := ROUND_INTRO + 0.2
	if before < tumble_at and after >= tumble_at:
		play_sfx("whoosh")


# --- Consultas (tests y dibujo) -------------------------------------------------

func round_number() -> int:
	return _round


func is_go() -> bool:
	return _phase == Phase.GO


func is_result() -> bool:
	return _phase == Phase.RESULT


func is_early(player_id: int) -> bool:
	return _early.has(player_id)


## Milisegundos de reacción de esta ronda, o NO_TIME.
func reaction_ms(player_id: int) -> int:
	return roundi(_react[player_id] / 1000.0) if _react.has(player_id) else NO_TIME


func round_winners() -> Array[int]:
	return _round_winners


func points() -> Dictionary:
	return _points


## Cartel trampa que se ve ahora (índice en TRICKS) o -1.
func trick_showing() -> int:
	if _phase != Phase.READY or _trick < 0:
		return -1
	return _trick if _phase_t >= _trick_at and _phase_t < _trick_at + TRICK_TIME else -1


## Lo que dice el cartel y si es dorado (el ¡YA! y el cartel falso).
func sign_text() -> Array:
	match _phase:
		Phase.GO:
			return ["¡YA!", true]
		Phase.RESULT:
			return [_result_text(), false]
	if _phase_t < ROUND_INTRO:
		return ["¡Última ronda!" if _round == ROUNDS else "Ronda %d de %d" % [maxi(_round, 1), ROUNDS], false]
	var k := trick_showing()
	if k >= 0:
		var trick: Dictionary = TRICKS[k]
		var tease: String = trick.tease
		return [tease if tease != "" and _phase_t < _trick_at + TRICK_TEASE else trick.text, trick.gold]
	return ["Preparados…", false]


func _result_text() -> String:
	if _round_winners.size() > 1:
		return "¡Empate!"
	if _round_winners.size() == 1:
		return "¡Ganó %s!" % str(player_by_id(_round_winners[0]).get("name", ""))
	return "¡Muy temprano!" if not _early.is_empty() else "¡Nadie disparó!"


# --- Dibujo -------------------------------------------------------------------

func _draw() -> void:
	draw_static(_draw_town)
	_draw_sign_and_street()
	for i in players.size():
		_draw_cowboy(players[i], _feet_of(i))
	_draw_props()
	var tags: Array = []
	for i in players.size():
		tags.append([players[i], _feet_of(i) + Vector2(0, _sit_drop(players[i].id)), MASCOT_SCALE])
	draw_player_tags(tags)
	draw_start_markers(tags)
	_draw_plaque_texts()
	draw_hud(_points, "Ronda %d/%d" % [maxi(_round, 1), ROUNDS], "flag")


## Dónde apoya la mascota del jugador `i` (en fila, mirando al frente).
func _feet_of(i: int) -> Vector2:
	var slot_w := (SCREEN.x - 2.0 * UiTheme.SAFE_MARGIN) / 4.0
	var left := (SCREEN.x - slot_w * players.size()) / 2.0
	return Vector2(left + slot_w * (i + 0.5), FEET_Y)


func _plaque_of(feet: Vector2) -> Rect2:
	return Rect2(feet + Vector2(-PLAQUE_SIZE.x / 2.0, PLAQUE_DY - PLAQUE_SIZE.y / 2.0), PLAQUE_SIZE)


## Cuánto se hunde la mascota que se adelantó (se cae sentada).
func _sit_drop(pid: int) -> float:
	if not _early.has(pid):
		return 0.0
	return 10.0 * clampf((_t - float(_shot_t[pid])) / 0.25, 0.0, 1.0)


# Pueblo al atardecer: lo fijo, dibujado una vez (ver MiniGame.draw_static).
func _draw_town(ci: CanvasItem) -> void:
	var b := GameArt.TriBatch.new()
	var w := SCREEN.x
	# Cielo en tres tramos (violeta arriba, naranja, amarillo en el horizonte).
	var stops: Array = [[0.0, UiTheme.QD_SKY_TOP], [300.0, UiTheme.QD_SKY_MID], [500.0, UiTheme.QD_SKY_LOW],
		[HORIZON_Y, UiTheme.QD_HORIZON]]
	for k in stops.size() - 1:
		var y0: float = stops[k][0]
		var y1: float = stops[k + 1][0]
		b.quad_colors(Vector2(0, y0), Vector2(w, y0), Vector2(w, y1), Vector2(0, y1),
			stops[k][1], stops[k][1], stops[k + 1][1], stops[k + 1][1])
	# Sol que se pone al final de la calle, con halo y franjas retro.
	var sun := Vector2(960, HORIZON_Y - 20)
	b.radial(sun, 360, UiTheme.QD_SUN_GLOW, Color(UiTheme.QD_SUN_GLOW, 0.0))
	b.circle(sun, 170, UiTheme.QD_SUN, 48)
	for k in 3:
		var y := sun.y - 70 + k * 26
		b.rect(Rect2(sun.x - 180, y, 360, 6 + k * 3), UiTheme.QD_SKY_LOW)
	# Mesetas lejanas (siluetas) y más cercanas.
	for m: Array in [[520, 820, 470, 90], [1180, 1440, 455, 80], [1560, 1760, 520, 60], [300, 440, 530, 50]]:
		b.polygon(PackedVector2Array([Vector2(m[0], HORIZON_Y), Vector2(m[0] + m[3], m[2]),
			Vector2(m[1] - m[3], m[2]), Vector2(m[1], HORIZON_Y)]), UiTheme.QD_MESA_FAR)
	for m: Array in [[640, 760, 540, 30], [1250, 1330, 548, 22]]:
		b.polygon(PackedVector2Array([Vector2(m[0], HORIZON_Y), Vector2(m[0] + m[3], m[2]),
			Vector2(m[1] - m[3], m[2]), Vector2(m[1], HORIZON_Y)]), UiTheme.QD_MESA_NEAR)
	# Arena y calle en perspectiva con huellas de carreta.
	b.quad_colors(Vector2(0, HORIZON_Y), Vector2(w, HORIZON_Y), Vector2(w, SCREEN.y), Vector2(0, SCREEN.y),
		UiTheme.QD_SAND_FAR, UiTheme.QD_SAND_FAR, UiTheme.QD_SAND_NEAR, UiTheme.QD_SAND_NEAR)
	b.quad(Vector2(915, HORIZON_Y), Vector2(1005, HORIZON_Y), Vector2(2300, SCREEN.y), Vector2(-380, SCREEN.y),
		UiTheme.QD_STREET)
	for side in [-1.0, 1.0]:
		for off in [0.3, 0.62]:
			var top := Vector2(960 + side * 45.0 * off, HORIZON_Y)
			var bottom := Vector2(960 + side * 1340.0 * off, SCREEN.y)
			b.quad(top - Vector2(1, 0), top + Vector2(1, 0), bottom + Vector2(9, 0), bottom - Vector2(9, 0), UiTheme.QD_RUT)
	# Edificios con fachada falsa, como bloques de juguete.
	_add_building(b, Rect2(28, 336, 500, 330), Rect2(96, 262, 364, 84), UiTheme.QD_SALOON, true)
	_add_building(b, Rect2(1392, 356, 500, 310), Rect2(1460, 284, 364, 82), UiTheme.QD_SHERIFF, false)
	# Barriles, cactus y bebedero.
	for c: Vector3 in [Vector3(560, 712, 1.0), Vector3(612, 722, 0.85), Vector3(1356, 716, 0.9)]:
		_add_barrel(b, Vector2(c.x, c.y), c.z)
	_add_cactus(b, Vector2(96, 1000), 1.15)
	_add_cactus(b, Vector2(1838, 980), 1.0)
	_add_cactus(b, Vector2(820, 640), 0.45)
	_add_cactus(b, Vector2(1110, 636), 0.38)
	# Placas de cada jugador (debajo del nombre): tiempos y rondas ganadas.
	for i in players.size():
		_add_plaque(b, _plaque_of(_feet_of(i)))
	b.flush(ci)
	UiTheme.draw_text(ci, "SALOON", Vector2(278, 304), 46, UiTheme.QD_WOOD_INK)
	UiTheme.draw_text(ci, "SHERIFF", Vector2(1642, 325), 44, UiTheme.QD_WOOD_INK)


## Edificio: cuerpo con tablas, fachada falsa con cartel, alero con postes,
## ventanas con luz, puerta y vereda de madera.
func _add_building(b: GameArt.TriBatch, body: Rect2, front: Rect2, col: Color, saloon: bool) -> void:
	var ink := UiTheme.INK
	b.chamfer_rect(front.grow(5), 8, ink)
	b.chamfer_rect(body.grow(5), 8, ink)
	b.chamfer_rect(front, 6, col)
	b.rect(Rect2(body.position.x, body.position.y, body.size.x, body.size.y), col)
	b.rect(Rect2(body.position.x, front.end.y - 2, body.size.x, 4), col)
	# Tablas horizontales.
	var y := body.position.y + 30
	while y < body.end.y - 10:
		b.rect(Rect2(body.position.x + 4, y, body.size.x - 8, 3), col.darkened(0.14))
		y += 34
	b.rect(Rect2(body.position.x, body.position.y, body.size.x, 8), col.lightened(0.18))
	# Cartel de la fachada.
	var board := Rect2(front.position.x + 26, front.position.y + 14, front.size.x - 52, front.size.y - 22)
	b.chamfer_rect(board.grow(4), 6, ink)
	b.chamfer_rect(board, 5, UiTheme.QD_TRIM)
	# Ventanas altas con luz cálida y marco.
	var win_y := body.position.y + 34
	for x in [body.position.x + 50, body.end.x - 150]:
		var r := Rect2(x, win_y, 100, 76)
		b.chamfer_rect(r.grow(7), 6, UiTheme.QD_TRIM)
		b.rect(r, UiTheme.QD_WINDOW_LIT)
		b.rect(Rect2(r.position.x, r.position.y + r.size.y * 0.55, r.size.x, r.size.y * 0.45), UiTheme.QD_WINDOW_LIT.darkened(0.12))
		b.rect(Rect2(r.get_center().x - 3, r.position.y, 6, r.size.y), UiTheme.QD_TRIM)
		b.rect(Rect2(r.position.x, r.get_center().y - 3, r.size.x, 6), UiTheme.QD_TRIM)
	# Alero con postes y vereda.
	var roof_y := body.position.y + 150
	b.quad(Vector2(body.position.x - 18, roof_y), Vector2(body.end.x + 18, roof_y),
		Vector2(body.end.x + 30, roof_y + 30), Vector2(body.position.x - 30, roof_y + 30), ink)
	b.quad(Vector2(body.position.x - 14, roof_y + 3), Vector2(body.end.x + 14, roof_y + 3),
		Vector2(body.end.x + 22, roof_y + 24), Vector2(body.position.x - 22, roof_y + 24), UiTheme.QD_WOOD_DARK)
	for x in [body.position.x + 6, body.end.x - 20]:
		b.rect(Rect2(x - 3, roof_y + 24, 20, body.end.y - roof_y - 24), ink)
		b.rect(Rect2(x, roof_y + 24, 14, body.end.y - roof_y - 24), UiTheme.QD_WOOD)
	# Puerta: vaivén en el saloon, puerta con estrella en la oficina.
	var door := Rect2(body.get_center().x - 58, body.end.y - 132, 116, 132)
	b.rect(door.grow(6), ink)
	b.rect(door, UiTheme.QD_WINDOW)
	if saloon:
		for k in 2:
			var leaf := Rect2(door.position.x + 4 + k * 56, door.position.y + 34, 52, 60)
			b.chamfer_rect(leaf.grow(3), 5, ink)
			b.chamfer_rect(leaf, 4, UiTheme.QD_WOOD_LIGHT)
			b.rect(Rect2(leaf.position.x + 6, leaf.position.y + 10, leaf.size.x - 12, 4), UiTheme.QD_WOOD_DARK)
			b.rect(Rect2(leaf.position.x + 6, leaf.position.y + 30, leaf.size.x - 12, 4), UiTheme.QD_WOOD_DARK)
	else:
		b.rect(door.grow(-8), UiTheme.QD_WOOD)
		b.star(door.get_center() + Vector2(0, -20), 26, UiTheme.GOLD, 0.0, 4.0)
		b.rect(Rect2(door.end.x - 30, door.get_center().y + 20, 10, 10), UiTheme.GOLD)
	var walk := Rect2(body.position.x - 34, body.end.y, body.size.x + 68, 26)
	b.rect(walk.grow(4), ink)
	b.rect(walk, UiTheme.QD_WOOD_LIGHT)
	b.rect(Rect2(walk.position.x, walk.end.y - 8, walk.size.x, 8), UiTheme.QD_WOOD_DARK)
	var px := walk.position.x + 60
	while px < walk.end.x:
		b.rect(Rect2(px, walk.position.y, 3, walk.size.y - 8), UiTheme.QD_WOOD_DARK)
		px += 70


func _add_barrel(b: GameArt.TriBatch, base: Vector2, s: float) -> void:
	var r := Rect2(base + Vector2(-24, -64) * s, Vector2(48, 64) * s)
	b.chamfer_rect(r.grow(4), 10 * s, UiTheme.INK)
	b.chamfer_rect(r, 9 * s, UiTheme.QD_WOOD)
	b.rect(Rect2(r.position.x + r.size.x * 0.55, r.position.y + 4, r.size.x * 0.3, r.size.y - 8), UiTheme.QD_WOOD_DARK)
	for k in 2:
		b.rect(Rect2(r.position.x, r.position.y + r.size.y * (0.22 + k * 0.5), r.size.x, 6 * s), UiTheme.INK_SOFT)


func _add_cactus(b: GameArt.TriBatch, base: Vector2, s: float) -> void:
	var col := UiTheme.QD_CACTUS
	var ink := UiTheme.INK
	var trunk := Rect2(base + Vector2(-22, -170) * s, Vector2(44, 170) * s)
	var arms: Array[Rect2] = [
		Rect2(base + Vector2(-66, -120) * s, Vector2(30, 70) * s), Rect2(base + Vector2(-66, -64) * s, Vector2(56, 26) * s),
		Rect2(base + Vector2(36, -140) * s, Vector2(30, 64) * s), Rect2(base + Vector2(10, -90) * s, Vector2(56, 26) * s),
	]
	for r in arms:
		b.capsule(r.grow(4), ink)
	b.capsule(trunk.grow(4), ink)
	for r in arms:
		b.capsule(r, col)
	b.capsule(trunk, col)
	b.capsule(Rect2(trunk.position + Vector2(8, 12) * s, Vector2(8, trunk.size.y - 40 * s)), col.lightened(0.25))


func _add_plaque(b: GameArt.TriBatch, r: Rect2) -> void:
	b.chamfer_rect(r.grow(5), 12, UiTheme.INK)
	b.chamfer_rect(r, 10, UiTheme.QD_WOOD_DARK)
	b.chamfer_rect(Rect2(r.position, r.size - Vector2(0, 7)), 10, UiTheme.QD_WOOD)
	b.rect(Rect2(r.position.x + 14, r.position.y + 5, r.size.x - 28, 4), Color(UiTheme.QD_WOOD_LIGHT, 0.8))
	for x in [r.position.x + 12, r.end.x - 12]:
		b.circle(Vector2(x, r.get_center().y - 3), 4, UiTheme.QD_WOOD_INK, 8)


# Cartel colgante, sogas, brillo del ¡YA! y la planta rodadora.
func _draw_sign_and_street() -> void:
	if _sign_wood == null:
		_sign_wood = _build_sign(false)
		_sign_gold = _build_sign(true)
	var st := sign_text()
	var gold: bool = st[1]
	var angle := sin(anim_time * 1.3) * 0.02
	if is_go():
		angle = sin(_phase_t * 60.0) * 0.03 * maxf(0.0, 1.0 - _phase_t * 3.0)
	var b := GameArt.TriBatch.new()
	if gold:
		GameArt.add_glow(b, SIGN_PIVOT + Vector2(0, SIGN_SIZE.y / 2.0), 470, UiTheme.GLOW, anim_time, 14)
	var xf := Transform2D(angle, SIGN_PIVOT)
	for x in [-SIGN_SIZE.x / 2.0 + 110, SIGN_SIZE.x / 2.0 - 110]:
		var top := Vector2(SIGN_PIVOT.x + x * 0.9, ROPE_TOP_Y)
		var end: Vector2 = xf * Vector2(x, 10)
		b.line(top, end, UiTheme.INK, 11)
		b.line(top, end, UiTheme.QD_ROPE, 5)
	_add_tumbleweed(b)
	b.flush(self)
	draw_set_transform(SIGN_PIVOT, angle)
	(_sign_gold if gold else _sign_wood).draw(self)
	var text: String = st[0]
	var center := Vector2(0, SIGN_SIZE.y / 2.0 + 14)
	if gold:
		var size := _fit(text, SIGN_TEXT_MAX, SIGN_GO_SIZE)
		UiTheme.draw_text(self, text, center + Vector2(0, 6), size, UiTheme.DANGER, 14, UiTheme.INK)
	else:
		var size := _fit(text, SIGN_TEXT_MAX, SIGN_TEXT_SIZE)
		UiTheme.draw_text(self, text, center, size, UiTheme.QD_TRIM, 12, UiTheme.QD_WOOD_INK)
	draw_set_transform_matrix(Transform2D.IDENTITY)


## Tamaño de letra para que `text` entre en `max_w`.
## Se guarda por texto: el cartel se dibuja en cada frame.
static func _fit(text: String, max_w: float, size: int) -> int:
	var key := "%d|%s" % [size, text]
	if _fit_cache.has(key):
		return _fit_cache[key]
	var w := UiTheme.FONT_BOLD.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	var out := size if w <= max_w else maxi(32, floori(size * max_w / w))
	if _fit_cache.size() > 64:
		_fit_cache.clear()
	_fit_cache[key] = out
	return out


## Cartel de tres tablas con contorno, clavos y vetas, en coordenadas locales
## (0, 0 = de donde cuelga). Se arma una vez (madera y dorado) y en cada frame
## solo se vuelve a mandar con la rotación del vaivén.
static func _build_sign(gold: bool) -> GameArt.TriBatch:
	var b := GameArt.TriBatch.new()
	var r := Rect2(Vector2(-SIGN_SIZE.x / 2.0, 14), SIGN_SIZE)
	var face := UiTheme.GOLD if gold else UiTheme.QD_WOOD
	var light := UiTheme.GOLD.lightened(0.3) if gold else UiTheme.QD_WOOD_LIGHT
	var dark := UiTheme.GOLD.darkened(0.3) if gold else UiTheme.QD_WOOD_DARK
	b.chamfer_rect(r.grow(8).grow_side(SIDE_BOTTOM, 6), 22, UiTheme.INK)
	b.chamfer_rect(r, 18, dark)
	var plank_h := (r.size.y - 12) / 3.0
	for k in 3:
		var p := Rect2(r.position.x + 6, r.position.y + 4 + k * plank_h, r.size.x - 12, plank_h - 5)
		b.chamfer_rect(p, 12, face if k != 1 else face.lerp(light, 0.35))
		b.rect(Rect2(p.position.x + 20, p.position.y + 5, p.size.x - 40, 4), Color(light, 0.9))
		# Vetas.
		for g in 2:
			var gy := p.position.y + p.size.y * (0.45 + g * 0.25)
			var gx := p.position.x + 60 + ((k * 3 + g * 5) % 7) * 70
			b.capsule(Rect2(gx, gy, 150 + g * 60, 4), Color(dark, 0.45))
	for c in [Vector2(r.position.x + 30, r.position.y + 26), Vector2(r.end.x - 30, r.position.y + 26),
			Vector2(r.position.x + 30, r.end.y - 26), Vector2(r.end.x - 30, r.end.y - 26)]:
		b.circle(c, 9, UiTheme.INK, 12)
		b.circle(c, 5, UiTheme.MASCOT_METAL, 10)
	return b


## Planta rodadora que cruza la calle mientras todos esperan (va detrás de
## las mascotas). Una ronda de izquierda a derecha y la siguiente al revés.
func _add_tumbleweed(b: GameArt.TriBatch) -> void:
	var s := _phase_t - ROUND_INTRO - 0.2
	if _phase != Phase.READY or s < 0.0 or s > TUMBLE_TIME:
		return
	var dir := 1.0 if _round % 2 == 1 else -1.0
	var k := s / TUMBLE_TIME
	var x := lerpf(-80.0, SCREEN.x + 80.0, k if dir > 0.0 else 1.0 - k)
	var hop := absf(sin(s * 4.2)) * 46.0
	var c := Vector2(x, TUMBLE_Y - TUMBLE_R - hop)
	b.ellipse(Vector2(x, TUMBLE_Y), TUMBLE_R * (1.0 - hop / 140.0), 8, UiTheme.QD_SHADE)
	b.circle(c, TUMBLE_R + 4, UiTheme.INK, 20)
	b.circle(c, TUMBLE_R, UiTheme.QD_TUMBLE_DARK, 20)
	var rot := s * 7.0 * dir
	for i in 5:
		b.ellipse(c, TUMBLE_R - 4, 7, UiTheme.QD_TUMBLE, rot + i * PI / 5.0)
	b.circle(c + Vector2(-10, -12), 7, Color(UiTheme.QD_TUMBLE, 0.8), 10)


func _draw_cowboy(p: Dictionary, feet: Vector2) -> void:
	var pid: int = p.id
	var mood: int = PlayerAvatar.Mood.NORMAL
	var squash := 0.0
	var hop := 0.0
	var wave := false
	if _early.has(pid):
		mood = PlayerAvatar.Mood.SAD
		squash = 0.28 * clampf((_t - float(_shot_t[pid])) / 0.25, 0.0, 1.0)
	elif _phase == Phase.RESULT and pid in _round_winners:
		mood = PlayerAvatar.Mood.HAPPY
		hop = absf(sin(_phase_t * 7.0)) * 22.0
	elif (_phase == Phase.GO and not _react.has(pid)) or trick_showing() >= 0:
		mood = PlayerAvatar.Mood.SURPRISED
	var at := feet + Vector2(0, _sit_drop(pid))
	PlayerAvatar.draw_mascot(self, at, MASCOT_SCALE, p.color, PlayerAvatar.style_of(p), mood, 0.0, hop, false,
		{"t": anim_time + p.slot, "squash": squash, "wave": wave})


## Sombreros, cebitas de corcho, humo y confeti, placas: todo en un lote.
func _draw_props() -> void:
	var b := GameArt.TriBatch.new()
	var u := MASCOT_SCALE
	for i in players.size():
		var p: Dictionary = players[i]
		var pid: int = p.id
		var feet := _feet_of(i) + Vector2(0, _sit_drop(pid))
		var early := _early.has(pid)
		var winner := _phase == Phase.RESULT and pid in _round_winners
		var hop := absf(sin(_phase_t * 7.0)) * 22.0 if winner else 0.0
		var sq := 0.28 * clampf((_t - float(_shot_t.get(pid, _t))) / 0.25, 0.0, 1.0) if early else 0.0
		var scale := Vector2(1.0 + sq * 0.6, 1.0 - sq * 0.6)
		var base := feet - Vector2(0, hop)
		# El sombrero sigue a la cabeza (mismo squash que draw_mascot).
		var head := base + Vector2(0, -57.0 * u * scale.y)
		var hat_rot := -0.12 if winner else (0.28 if early else 0.0)
		var hat_pos := head + (Vector2(4, 9) * u if early else Vector2.ZERO)
		if winner:
			hat_pos += Vector2(0, -10.0 * u * absf(sin(_phase_t * 7.0)))
		var tpl := _hat(p.color)
		b.template(tpl[0], tpl[1], Transform2D(hat_rot, scale * u, 0.0, hat_pos))
		if winner:
			b.star(base + Vector2(0, -19.0 * u * scale.y), 10.0 * u, UiTheme.GOLD, 0.0, 3.0)
		if _shot_t.has(pid):
			_add_popgun(b, pid, base + Vector2(30.0 * u * scale.x, -18.0 * u * scale.y), _t - float(_shot_t[pid]), early)
		# Placa: roja si se adelantó, dorada si ganó la ronda.
		var plaque := _plaque_of(_feet_of(i))
		if early:
			b.chamfer_rect(Rect2(plaque.position, plaque.size - Vector2(0, 7)), 10, UiTheme.DANGER)
		elif winner:
			b.chamfer_rect(Rect2(plaque.position, plaque.size - Vector2(0, 7)), 10, UiTheme.GOLD)
		elif not _showing_time(pid):
			_add_win_stars(b, plaque, int(_wins.get(pid, 0)))
	b.flush(self)


## Estrellitas de rondas ganadas en la placa (mientras no muestra un tiempo).
func _add_win_stars(b: GameArt.TriBatch, plaque: Rect2, wins: int) -> void:
	var c := plaque.get_center() + Vector2(0, -3)
	for k in ROUNDS:
		var at := c + Vector2((k - (ROUNDS - 1) / 2.0) * 34.0, 0)
		b.star(at, 12, UiTheme.GOLD if k < wins else UiTheme.QD_WOOD_DARK, 0.0, 3.0 if k < wins else 0.0)


func _showing_time(pid: int) -> bool:
	return _react.has(pid) or (_phase == Phase.RESULT and not _early.has(pid))


## Cebita de corcho de juguete: apunta al cielo, el corcho sale atado a un
## hilo con destello, humo y confeti. Si se adelantó, el corcho sale flojito
## y queda colgando para abajo.
func _add_popgun(b: GameArt.TriBatch, pid: int, hand: Vector2, s: float, early: bool) -> void:
	var u := MASCOT_SCALE
	var aim := -PI / 2.0 + 0.5
	if early:
		aim = lerpf(-0.3, 0.9, clampf((s - 0.15) / 0.4, 0.0, 1.0))
	var dir := Vector2.from_angle(aim)
	var side := dir.orthogonal()
	var muzzle := hand + dir * 30.0 * u
	# Mango y caño con contorno.
	var grip_a := hand - dir * 2.0 * u
	var grip_b := grip_a + dir.rotated(2.3) * 12.0 * u
	b.line(grip_a, grip_b, UiTheme.INK, 11.0 * u)
	b.line(hand - dir * 6.0 * u, muzzle + dir * 2.0 * u, UiTheme.INK, 12.0 * u)
	b.line(grip_a, grip_b, UiTheme.QD_WOOD, 6.0 * u)
	b.line(hand - dir * 4.0 * u, muzzle, UiTheme.QD_POPGUN, 7.0 * u)
	b.line(hand + side * 1.8 * u, muzzle + side * 1.8 * u, UiTheme.QD_POPGUN.lightened(0.35), 1.6 * u)
	# Corcho con hilo.
	var reach := (58.0 if not early else 20.0) * u
	var out := clampf(s / 0.12, 0.0, 1.0)
	var swing := clampf((s - 0.25) / 0.6, 0.0, 1.0)
	var cork_dir := dir.slerp(Vector2.DOWN, swing * swing * (3.0 - 2.0 * swing)) if not early else Vector2.DOWN.slerp(dir, 0.3)
	var cork := muzzle + cork_dir * reach * out
	b.line(muzzle, cork, UiTheme.QD_TRIM, 2.2 * u)
	b.ellipse(cork, 7.5 * u, 6.0 * u, UiTheme.INK, cork_dir.angle())
	b.ellipse(cork, 5.8 * u, 4.4 * u, UiTheme.QD_CORK, cork_dir.angle())
	# Destello.
	if s < 0.16 and not early:
		var k := 1.0 - s / 0.16
		b.star(muzzle + dir * 6.0 * u, (10.0 + 20.0 * k) * u, UiTheme.GLOW, aim, 0.0)
		b.circle(muzzle + dir * 6.0 * u, 7.0 * u * k, UiTheme.PAPER, 12)
	# Humo: tres bocanadas que suben y se desvanecen.
	for n in 3:
		var age := s - n * 0.06
		if age <= 0.0 or age >= 0.9:
			continue
		var puff := muzzle + dir * (6.0 + age * 26.0) * u + side * (n - 1) * 7.0 * u + Vector2(0, -age * 30.0 * u)
		var r := (5.0 + age * 14.0) * u * (0.6 if early else 1.0)
		b.circle(puff, r, Color(UiTheme.QD_SMOKE, UiTheme.QD_SMOKE.a * (1.0 - age / 0.9)), 14)
	# Confeti (solo en un disparo a tiempo), con caída.
	if not early and s < 1.3:
		for n in 14:
			var h1 := fposmod(sin(n * 12.9898 + pid * 78.233) * 43758.5453, 1.0)
			var h2 := fposmod(sin(n * 39.3468 + pid * 11.135) * 24634.6345, 1.0)
			var v := dir.rotated((h1 - 0.5) * 1.6) * (260.0 + h2 * 320.0)
			var at := muzzle + v * s + Vector2(0, 700.0) * s * s
			var alpha := clampf((1.3 - s) / 0.4, 0.0, 1.0)
			var spin := s * (6.0 + h2 * 8.0) + n
			var half := Vector2(7, 4).rotated(spin)
			var perp := half.orthogonal() * 0.6
			b.quad(at - half - perp, at + half - perp, at + half + perp, at - half + perp,
				Color(UiTheme.BRICKS[n % UiTheme.BRICKS.size()], alpha))


## Textos de las placas y el "+puntos" de la ronda (después de los globitos).
func _draw_plaque_texts() -> void:
	for i in players.size():
		var p: Dictionary = players[i]
		var pid: int = p.id
		var feet := _feet_of(i)
		var c := _plaque_of(feet).get_center() + Vector2(0, -3)
		var winner := _phase == Phase.RESULT and pid in _round_winners
		if _early.has(pid):
			UiTheme.draw_text(self, "¡Muy temprano!", c, PLAQUE_SMALL_SIZE, UiTheme.PAPER)
		elif _react.has(pid):
			UiTheme.draw_text(self, "%d ms" % reaction_ms(pid), c, PLAQUE_TEXT_SIZE,
				UiTheme.INK if winner else UiTheme.QD_TRIM, 0 if winner else 6, UiTheme.QD_WOOD_INK)
		elif _phase == Phase.RESULT:
			UiTheme.draw_text(self, "Sin disparo", c, PLAQUE_SMALL_SIZE, UiTheme.QD_TRIM, 6, UiTheme.QD_WOOD_INK)
		if _phase == Phase.RESULT and _round_gain.has(pid):
			var rise := minf(_phase_t, 0.4) * 60.0
			UiTheme.draw_text(self, "+%d" % int(_round_gain[pid]), feet + Vector2(118, -150 - rise), POPUP_SIZE,
				UiTheme.GOLD if winner else UiTheme.PAPER, 10, UiTheme.INK)


## Sombrero de vaquero en coordenadas locales (u = 1, origen en el centro de
## la cabeza), con la cinta del color del jugador. Se arma una vez por color.
func _hat(band: Color) -> Array:
	if _hats.has(band):
		return _hats[band]
	var b := GameArt.TriBatch.new()
	var ink := UiTheme.INK
	var felt := UiTheme.QD_HAT
	# Copa (dos mitades convexas con la hendidura arriba) y su contorno.
	b.polygon(PackedVector2Array([Vector2(-26.5, -23), Vector2(0, -23), Vector2(0, -48.5), Vector2(-23.5, -55)]), ink)
	b.polygon(PackedVector2Array([Vector2(0, -23), Vector2(26.5, -23), Vector2(23.5, -55), Vector2(0, -48.5)]), ink)
	b.polygon(PackedVector2Array([Vector2(-23, -25), Vector2(0, -25), Vector2(0, -45), Vector2(-20, -51)]), felt)
	b.polygon(PackedVector2Array([Vector2(0, -25), Vector2(23, -25), Vector2(20, -51), Vector2(0, -45)]), felt.darkened(0.14))
	b.quad(Vector2(-15, -47), Vector2(-11, -46), Vector2(-13, -32), Vector2(-17, -32), Color(1, 1, 1, 0.25))
	# Cinta del color del jugador.
	b.quad(Vector2(-22.4, -35), Vector2(22.4, -35), Vector2(23, -27), Vector2(-23, -27), ink)
	b.quad(Vector2(-22, -33.5), Vector2(22, -33.5), Vector2(22.6, -28.5), Vector2(-22.6, -28.5), band)
	# Ala curvada hacia arriba en las puntas: tramos de un arco con contorno.
	var n := 14
	var pts_top: Array[Vector2] = []
	var pts_bot: Array[Vector2] = []
	for k in n + 1:
		var x := lerpf(-54.0, 54.0, float(k) / n)
		var curl := pow(absf(x) / 54.0, 3.0) * 13.0
		var thick := lerpf(4.6, 2.6, absf(x) / 54.0)
		pts_top.append(Vector2(x, -26.0 - curl - thick))
		pts_bot.append(Vector2(x, -26.0 - curl + thick))
	for k in n:
		var o := 3.2
		b.quad(pts_top[k] + Vector2(-o * (1 if k == 0 else 0), -o), pts_top[k + 1] + Vector2(o * (1 if k == n - 1 else 0), -o),
			pts_bot[k + 1] + Vector2(o * (1 if k == n - 1 else 0), o), pts_bot[k] + Vector2(-o * (1 if k == 0 else 0), o), ink)
	for k in n:
		var mid_a := (pts_top[k] + pts_bot[k]) / 2.0
		var mid_b := (pts_top[k + 1] + pts_bot[k + 1]) / 2.0
		b.quad(pts_top[k], pts_top[k + 1], mid_b, mid_a, felt.lightened(0.08))
		b.quad(mid_a, mid_b, pts_bot[k + 1], pts_bot[k], UiTheme.QD_HAT_DARK)
	var tpl := [b.points, b.colors]
	_hats[band] = tpl
	return tpl
