extends MiniGame
## Carrera de obstáculos: vista de costado, un carril por jugador. Las
## mascotas corren solas hacia la derecha; el botón salta (con anticipación y
## squash & stretch) y mantenerlo apretado salta un poco más alto, hasta un
## límite. Vallas, pozos, escalones y plataformas: tropezar frena ~1 s con
## cara de susto. Todos tienen la MISMA secuencia de obstáculos (generada con
## una semilla), así que la carrera es justa. Gana el primero en llegar a la
## meta; si se acaba el tiempo, el que llegó más lejos.
##
## Concepto: *física determinista con pasos fijos*. `step(delta)` junta el
## tiempo y avanza la simulación de a DT (1/60 s) con `_tick()`: con las
## mismas entradas en los mismos pasos, el resultado es siempre el mismo (lo
## verifican los tests). Coordenadas del mundo: x en px desde la largada,
## y = altura sobre el piso (hacia arriba).
##
## Cámara: *scroll lateral por carril*. Cada carril sigue a su mascota (fija a
## CAM_X px del borde) y el piso y los obstáculos pasan por debajo; el riel de
## arriba a la derecha de cada carril muestra cuánto falta para la meta.
##
## Rendimiento (docs/PERFORMANCE.md): lo que pasa por los carriles (piso,
## pozos, vallas, meta) va en UN lote de triángulos por frame, dibujado en una
## capa recortada al tablero (`_world`, Control con clip_contents: el recorte
## es un scissor, sin draw calls extra). Ladrillos, vallas y meta se
## precalculan como plantillas y en cada frame solo se ubican
## (TriBatch.template). Carteles de carril y rieles: draw_static (una vez).
##
## Escenario 2.5D (ADR 0019): con render, los carriles (baldosas y
## divisiones) y la sala de juguetes son una escena 3D horneada con cámara
## en perspectiva, una por cantidad de jugadores. Lo que pasa por cada
## carril se sigue armando en las coordenadas planas de siempre y se lleva a
## la pantalla con la transformación del piso en la línea del suelo de ese
## carril (`_lane_xf`: a lo largo del carril la proyección es exacta; los
## ladrillos y pozos quedan acostados en perspectiva) y lo que está parado
## (vallas, escalones, plataformas, meta, matas, mascotas) como cartel de
## frente en su punto del suelo, más chico atrás. Como el recorte de un
## Control es un rectángulo, en 2.5D la capa no recorta: lo que asoma por
## los costados del tablero se tapa con el propio escenario horneado
## (MiniGame.draw_board_25d_cover). Sin render, se dibuja plano como siempre.

enum Kind { HURDLE, PIT, BLOCK, PLATFORM }

# --- Reglas y física ----------------------------------------------------------------
const DT := 1.0 / 60.0              ## Paso fijo de la simulación.
const MAX_TICKS := 5                ## Tope de pasos por frame (si la TV se traba, no se "teletransporta").
const COUNTDOWN_SEC := 3.0
const GO_SEC := 0.8
const DURATION_SEC := 60.0          ## Si nadie llega, gana el que llegó más lejos.
const END_SEC := 1.6                ## Festejo antes de terminar.
const COURSE_LEN := 12000.0         ## px de la largada a la meta.
const PX_PER_M := 30.0              ## 12000 px = 400 m (el marcador muestra metros).
const RUN_SPEED := 380.0            ## px/s (≈ 32 s sin tropezar).
const ACCEL := 900.0                ## px/s² para volver a correr después de frenar.
const CATCHUP_MAX := 0.06           ## Goma elástica sutil: el que va atrás corre hasta 6 % más rápido.
const CATCHUP_FROM := 300.0         ## …desde esta distancia al que va primero…
const CATCHUP_FULL := 1500.0        ## …y el máximo desde esta.
const GRAVITY := 2400.0
const JUMP_SPEED := 640.0           ## Salto corto (tocar): ≈ 80 px de alto, ≈ 0,53 s en el aire.
const HOLD_GRAVITY := 0.45          ## Mantener apretado: menos gravedad mientras sube…
const HOLD_MAX_SEC := 0.2           ## …durante este tiempo como máximo (salto largo ≈ 140 px).
const MAX_JUMP_HEIGHT := 150.0      ## Límite garantizado del salto más alto (lo verifican los tests).
const ANTICIPATION_SEC := 0.05      ## Se agacha antes de saltar (3 pasos).
const JUMP_BUFFER_SEC := 0.12       ## Un toque un poco antes de aterrizar igual salta.
const STUMBLE_SEC := 1.0            ## Tropezar frena este tiempo…
const STUMBLE_SPEED := 70.0         ## …a esta velocidad.
const PIT_SEC := 1.1                ## Caer en un pozo: tiempo hasta volver a salir del otro lado.
const PIT_TRIGGER := 18.0           ## px por debajo del piso: ya cayó (antes, todavía se salva).
const PIT_SINK := 26.0              ## Visual: cuánto se hunde la mascota en el pozo.
const FOOT_R := 16.0                ## Medio ancho de los pies (choques).
const HURDLE_H := 50.0
const HURDLE_HIT := 24.0            ## Distancia horizontal (centro a centro) a la que la valla toca.
const PIT_EDGE := 12.0              ## Bordes del pozo que todavía sostienen (perdona un poco).
const STEP_SNAP := 18.0             ## Un escalón de hasta esto se sube sin tropezar.
const BLOCK_H := 56.0
const PLATFORM_H := 60.0
const PLATFORM_T := 24.0            ## Grosor de la plataforma flotante.
const NO_FLOOR := -1000000.0     ## Altura de apoyo sobre un pozo (no hay piso).

# --- Generación del recorrido --------------------------------------------------------
const GRID := 60.0                  ## Todo se alinea a los ladrillos del piso.
const FIRST_OBSTACLE_X := 1080.0
const FINISH_CLEAR := 900.0         ## Tramo libre antes de la meta.
const GAP_START := 640.0            ## Espacio entre obstáculos al principio…
const GAP_END := 420.0              ## …y al final (más difícil).
const GAP_JITTER := 240.0
const DOUBLE_GAP := 300.0           ## Doble valla.

# --- Dibujo -------------------------------------------------------------------------
const BOARD_X := 104.0
const BOARD_W := 1712.0
const LANES_SPACE := 800.0
const LANE_H_MIN := 200.0
const LANE_H_MAX := 290.0
const GROUND_H := 40.0
const CAM_X := 360.0                ## La mascota va fija a esta distancia del borde izquierdo.
const MASCOT_SCALE := 0.8
## Poses extra que se hornean en la intro (MascotAtlas.prewarm_game): cara de
## susto corriendo (y mirando abajo al caer) y festejo corriendo al llegar.
const MASCOT_PREWARM := [[MASCOT_SCALE, ["walk_r@3", "walk_r@1", "look_d@3"]]]
const PERIOD := GRID * 2.0          ## El piso alterna dos tonos de ladrillo.
const TAG_SIZE := Vector2(236, 48)  ## Cartel [1P | nombre] de cada carril.
const RAIL_W := 300.0
const FINISH_TOP := 66.0            ## La meta llega hasta acá desde arriba del carril (debajo del cartel).
const CHECK := 20.0                 ## Cuadros de la meta.
const BUSH_PERIOD := 560.0          ## Arbustos del fondo: se repiten cada tanto…
const BUSH_PARALLAX := 0.45         ## …y pasan más lento que el piso (parecen lejos).

## Un corredor: todo lo que la simulación sabe de un jugador.
class Runner:
	extends RefCounted
	var x := 0.0
	var y := 0.0            ## Altura sobre el piso.
	var vy := 0.0
	var speed := 0.0
	var grounded := true
	var crouch := -1.0      ## Anticipación que falta (< 0: no se está agachando).
	var hold := 0.0         ## Tiempo de salto largo ya usado.
	var buffer := 0.0       ## Toque guardado esperando tocar el piso.
	var held := false       ## El botón está apretado.
	var pressed := false    ## Hubo un toque (flanco de subida) desde el último paso.
	var stumble := 0.0      ## Tropiezo que falta.
	var fall := 0.0         ## > 0: cayó en un pozo (falta esto para salir).
	var respawn_x := 0.0
	var pit_x0 := 0.0       ## Pozo en el que cayó (para taparle los pies).
	var pit_x1 := 0.0
	var floor_h := 0.0      ## Altura de lo que tiene debajo (sombra).
	var cursor := 0         ## Primer obstáculo que todavía le importa.
	var knocked := {}       ## Índice de valla tirada -> segundos de carrera.
	var trips := 0
	var squash := 0.0       ## Visual: > 0 aplastada, < 0 estirada.


var _course: Array = []            # [{kind, x, w, h}] ordenado por x
var _starts := PackedFloat32Array() # x de cada obstáculo (búsqueda binaria al dibujar)
var _runners: Dictionary = {}      # player_id -> Runner
var _rng := RandomNumberGenerator.new()
var _acc := 0.0
var _countdown := COUNTDOWN_SEC
var _elapsed := 0.0
var _ending := false
var _end_timer := 0.0
var _end_text := ""
var _result: Dictionary = {}
var _winners: Array[int] = []

var _lane_h := LANE_H_MIN
var _board := Rect2()
var _world: Control                # Capa recortada al tablero con lo que pasa por los carriles.
var _batch := GameArt.TriBatch.new()
static var _templates: Dictionary = {}  # clave -> [puntos, colores] en coordenadas locales

## Vistas 2.5D por cantidad de carriles y si este cuadro se dibuja con una.
static var _board_views: Dictionary = {}
var _v25 := false


## Alto de cada carril y tablero para `n` jugadores (centrado en la pantalla).
static func lane_height(n: int) -> float:
	return clampf(LANES_SPACE / maxi(n, 1), LANE_H_MIN, LANE_H_MAX)


static func board_rect(n: int) -> Rect2:
	var h := lane_height(n) * maxi(n, 1)
	return Rect2(BOARD_X, (SCREEN.y - h) / 2.0 + 40.0, BOARD_W, h)


## Cámara y proyección del escenario 2.5D para `n` carriles (el campo
## encuadrado como el de Pintar el piso, BoardView25D.make_fit).
static func board_view(n: int = 4) -> BoardView25D:
	n = clampi(n, 1, Protocol.MAX_PLAYERS)
	if not _board_views.has(n):
		var v := BoardView25D.make_fit(board_rect(n), lane_height(n) / 2.0, Board25DScene.RECIPE_HURDLES)
		v.extras = {"rows": n, "lane_h": lane_height(n), "divider": 4.0, "dash": []}
		_board_views[n] = v
	return _board_views[n]


## Durante la intro: el escenario 2.5D de esta cantidad de jugadores.
static func prewarm_art(host: Node, p_players: Array = []) -> void:
	Board25DBaker.request(host, board_view(maxi(p_players.size(), 1)))


static func get_info() -> Dictionary:
	return {
		"id": "hurdles",
		"title": "Carrera de obstáculos",
		"description": "Tu mascota corre sola: tocá para saltar vallas y pozos (mantené: salta más alto). Tropezar frena. ¡El primero en la meta gana!",
		"min_players": 1,
		"max_players": 4,
		"layout": Protocol.LAYOUT_ONE_BUTTON,
		"layout_data": {"label": "¡SALTÁ!", "hint": "Tocá para saltar; mantené: más alto"},
		"accent": UiTheme.ACCENT_HURDLES,
		"score_label": "metros",
	}


func setup(p_players: Array[Dictionary]) -> void:
	super.setup(p_players)
	_rng.randomize()
	for p in players:
		_runners[p.id] = Runner.new()
	var n := maxi(players.size(), 1)
	_lane_h = lane_height(n)
	_board = board_rect(n)
	_world = Control.new()
	_world.name = "Course"
	_world.position = _board.position
	_world.size = _board.size
	_world.clip_contents = true
	_world.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_world.focus_mode = Control.FOCUS_NONE
	_world.show_behind_parent = true  # Detrás de las mascotas; delante del tablero.
	_world.draw.connect(_draw_world)
	add_child(_world, false, Node.INTERNAL_MODE_BACK)


## Usa este recorrido en vez de uno generado (tests).
func use_course(course: Array) -> void:
	_course = course.duplicate(true)
	_starts = PackedFloat32Array()
	for o: Dictionary in _course:
		_starts.append(float(o.x))


## El recorrido se arma recién al empezar a correr (así una semilla puesta
## después de setup, como la de las miniaturas, se respeta).
func _ensure_course() -> void:
	if _starts.is_empty() and _course.is_empty():
		use_course(build_course(_rng.randi()))


## Recorrido determinista: la misma semilla da siempre los mismos
## obstáculos. Más apretado y con dobles vallas hacia el final.
static func build_course(seed_value: int) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var list: Array = []
	var x := FIRST_OBSTACLE_X
	while x < COURSE_LEN - FINISH_CLEAR:
		var k := x / COURSE_LEN
		var roll := rng.randf()
		var end := x
		if roll < 0.4 or k < 0.12:
			list.append(_obstacle(Kind.HURDLE, x, 0.0, HURDLE_H))
			end = x + GRID
			if k > 0.3 and rng.randf() < 0.35:
				list.append(_obstacle(Kind.HURDLE, x + DOUBLE_GAP, 0.0, HURDLE_H))
				end = x + DOUBLE_GAP + GRID
		elif roll < 0.65:
			var w := GRID * 2.0 if k < 0.3 or rng.randf() < 0.5 else GRID * 3.0
			list.append(_obstacle(Kind.PIT, x, w, 0.0))
			end = x + w
		elif roll < 0.85 or k < 0.25:
			var w := GRID * rng.randi_range(3, 5)
			list.append(_obstacle(Kind.BLOCK, x, w, BLOCK_H))
			end = x + w
		else:
			# Pozo ancho con una plataforma en el medio: saltar a la plataforma y de ahí al otro lado.
			list.append(_obstacle(Kind.PIT, x, GRID * 6.0, 0.0))
			list.append(_obstacle(Kind.PLATFORM, x + GRID * 2.0, GRID * 2.0, PLATFORM_H))
			end = x + GRID * 6.0
		var gap := lerpf(GAP_START, GAP_END, k) + rng.randf_range(0.0, GAP_JITTER)
		x = ceilf((end + gap) / GRID) * GRID
	return list


static func _obstacle(kind: Kind, x: float, w: float, h: float) -> Dictionary:
	return {"kind": kind, "x": x, "w": w, "h": h}


func on_input(player_id: int, input: Dictionary) -> void:
	if not _runners.has(player_id) or is_finished():
		return
	var r: Runner = _runners[player_id]
	var down := (int(input.get("btn", 0)) & Protocol.BTN_A) != 0
	if down and not r.held:
		r.pressed = true  # El toque se guarda aunque suelte antes del próximo paso.
	r.held = down


func _physics_process(delta: float) -> void:
	if is_finished():
		return
	step(delta)
	_world.queue_redraw()
	queue_redraw()


## Avanza la carrera `delta` segundos en pasos fijos de DT (los tests la
## llaman a mano).
func step(delta: float) -> void:
	_ensure_course()
	_acc = minf(_acc + delta, DT * MAX_TICKS)
	while _acc >= DT - 0.000001:
		_acc -= DT
		_tick()


func _tick() -> void:
	if is_finished():
		return
	if _ending:
		_end_timer -= DT
		_step_runners(false)
		if _end_timer <= 0.0:
			finish(_result)
		return
	if _countdown > -GO_SEC:
		var before := _countdown
		_countdown -= DT
		tick_countdown(before, _countdown)
	var racing := _countdown <= 0.0
	if racing:
		_elapsed += DT
	_step_runners(racing)
	if racing:
		_check_end()


func _step_runners(racing: bool) -> void:
	var leader := -INF
	for pid: int in _runners:
		leader = maxf(leader, (_runners[pid] as Runner).x)
	for p in players:
		_step_runner(_runners[p.id], p.id, racing, leader)


## Un paso de un corredor: salto, velocidad, choques y apoyo.
func _step_runner(r: Runner, pid: int, racing: bool, leader: float) -> void:
	r.squash = move_toward(r.squash, 0.0, DT * 2.5)
	if not racing:
		r.pressed = false
	# En un pozo: se hunde y sale del otro lado.
	if r.fall > 0.0:
		r.fall -= DT
		if r.fall <= 0.0:
			r.x = r.respawn_x
			r.y = 0.0
			r.vy = 0.0
			r.grounded = true
			r.speed = 0.0
			r.floor_h = 0.0
			r.squash = 0.3
		return
	# Toque: se guarda un momento; en el piso, se agacha y después salta.
	if r.pressed:
		r.buffer = JUMP_BUFFER_SEC
		r.pressed = false
	else:
		r.buffer = maxf(r.buffer - DT, 0.0)
	if r.grounded and r.crouch < 0.0 and r.buffer > 0.0 and r.stumble <= 0.0:
		r.crouch = ANTICIPATION_SEC
		r.buffer = 0.0
	if r.crouch >= 0.0:
		r.crouch -= DT
		r.squash = 0.28
		if r.crouch <= 0.000001:
			r.crouch = -1.0
			r.vy = JUMP_SPEED
			r.grounded = false
			r.hold = 0.0
			r.squash = -0.3
			play_sfx("pop", 1.3)
	# Velocidad: corre solo; tropezado, casi frena; el que va atrás, un poquito más rápido.
	var target := 0.0
	if racing:
		var gap := clampf((leader - r.x - CATCHUP_FROM) / (CATCHUP_FULL - CATCHUP_FROM), 0.0, 1.0)
		target = RUN_SPEED * (1.0 + CATCHUP_MAX * gap)
	if r.stumble > 0.0:
		r.stumble -= DT
		target = minf(target, STUMBLE_SPEED)
	r.speed = move_toward(r.speed, target, ACCEL * DT)
	var x_old := r.x
	var x_new := x_old + r.speed * DT
	var y_old := r.y
	if not r.grounded:
		var g := GRAVITY
		if r.held and r.vy > 0.0 and r.hold < HOLD_MAX_SEC:
			g *= HOLD_GRAVITY
			r.hold += DT
		r.vy -= g * DT
		r.y += r.vy * DT
	# Choques con los obstáculos cercanos.
	while r.cursor < _course.size() and float(_course[r.cursor].x) + float(_course[r.cursor].w) + GRID < x_old:
		r.cursor += 1
	var i := r.cursor
	while i < _course.size() and float(_course[i].x) - GRID < x_new + FOOT_R:
		var o: Dictionary = _course[i]
		var ox := float(o.x)
		match int(o.kind):
			Kind.HURDLE:
				if not r.knocked.has(i) and absf(x_new - ox) < HURDLE_HIT and r.y < float(o.h) - 4.0:
					r.knocked[i] = _elapsed
					_trip(r, pid)
			Kind.BLOCK:
				var h := float(o.h)
				if x_old + FOOT_R <= ox and x_new + FOOT_R > ox and r.y < h - STEP_SNAP:
					# Contra la pared del escalón: tropieza y se trepa (queda arriba).
					_trip(r, pid)
					x_new = ox + FOOT_R * 0.5
					r.y = h
					y_old = h
					r.vy = 0.0
					r.grounded = true
					r.crouch = -1.0
		i += 1
	# Apoyo: piso, escalón, plataforma o nada (pozo).
	var support := _support(r, x_new, y_old)
	if r.grounded:
		if support == NO_FLOOR or support < r.y - 0.5:
			r.grounded = false  # Se terminó el piso: cae (sin impulso).
			r.vy = 0.0
		else:
			r.y = support
	elif r.vy <= 0.0 and support != NO_FLOOR and r.y <= support and y_old >= support - PIT_TRIGGER:
		r.squash = clampf(-r.vy / JUMP_SPEED, 0.12, 1.0) * 0.3
		r.y = support
		r.vy = 0.0
		r.grounded = true
	if not r.grounded and r.y < -PIT_TRIGGER:
		_fall_in_pit(r, pid, x_new)
		return
	r.x = x_new
	r.floor_h = support if support != NO_FLOOR else minf(r.y, 0.0)
	if r.grounded and r.crouch < 0.0:
		advance_walk(pid, r.speed / RUN_SPEED, DT, 3.2)


## Altura de lo que hay debajo de los pies en `x` (NO_FLOOR sobre un pozo).
## Las plataformas sostienen solo si viene de arriba (`y_from`).
func _support(r: Runner, x: float, y_from: float) -> float:
	var s := 0.0
	var over_pit := false
	var i := r.cursor
	while i < _course.size() and float(_course[i].x) - GRID < x + FOOT_R:
		var o: Dictionary = _course[i]
		var x0 := float(o.x)
		var x1 := x0 + float(o.w)
		match int(o.kind):
			Kind.PIT:
				if x > x0 + PIT_EDGE and x < x1 - PIT_EDGE:
					over_pit = true
			Kind.BLOCK:
				if x + FOOT_R * 0.5 > x0 and x - FOOT_R * 0.5 < x1:
					s = maxf(s, float(o.h))
			Kind.PLATFORM:
				if x + FOOT_R * 0.5 > x0 and x - FOOT_R * 0.5 < x1 and y_from >= float(o.h) - PIT_TRIGGER:
					return float(o.h)
		i += 1
	return NO_FLOOR if over_pit and s == 0.0 else s


func _trip(r: Runner, pid: int) -> void:
	r.stumble = STUMBLE_SEC
	r.speed = minf(r.speed, STUMBLE_SPEED)
	r.buffer = 0.0
	r.crouch = -1.0
	r.trips += 1
	play_sfx("hit")
	notify_player(pid, "hit")


func _fall_in_pit(r: Runner, pid: int, x: float) -> void:
	r.fall = PIT_SEC
	r.respawn_x = x
	r.pit_x0 = x - FOOT_R
	r.pit_x1 = x + FOOT_R
	for i in range(r.cursor, _course.size()):
		var o: Dictionary = _course[i]
		if float(o.x) > x + FOOT_R:
			break
		if int(o.kind) == Kind.PIT and x <= float(o.x) + float(o.w) + FOOT_R:
			r.pit_x0 = float(o.x)
			r.pit_x1 = float(o.x) + float(o.w)
			r.respawn_x = r.pit_x1 + FOOT_R + 4.0
	r.x = x
	r.stumble = 0.0
	r.crouch = -1.0
	r.buffer = 0.0
	r.speed = 0.0
	r.vy = 0.0
	r.trips += 1
	play_sfx("lose")
	notify_player(pid, "hit")


## ¿Alguien llegó o se acabó el tiempo? Deja el resultado listo y festeja
## END_SEC antes de terminar.
func _check_end() -> void:
	var best := -INF
	var first: Array[int] = []
	for p in players:
		var r: Runner = _runners[p.id]
		if r.x < COURSE_LEN or r.fall > 0.0:
			continue
		# Cuánto hace que cruzó dentro de este paso: el que más, llegó antes.
		var ago := (r.x - COURSE_LEN) / maxf(r.speed, 1.0)
		if ago > best + 0.000001:
			best = ago
			first = [p.id]
		elif absf(ago - best) <= 0.000001:
			first.append(p.id)
	if not first.is_empty():
		_winners = first
		_result = {"winners": first.duplicate(), "scores": meters(), "summary": "Primero en la meta"}
		_end_text = "¡Meta!"
		play_sfx("win")
		for pid in first:
			notify_player(pid, "win")
	elif _elapsed >= DURATION_SEC - 0.000001:
		_result = result_from_scores(meters(), "Se acabó el tiempo: gana el que llegó más lejos")
		_winners.assign(_result.winners)
		_end_text = "¡Tiempo!"
		play_sfx("stop")
		for pid in _winners:
			notify_player(pid, "win")
	else:
		return
	_ending = true
	_end_timer = END_SEC


## Metros recorridos de cada jugador (con un decimal; la meta es el máximo).
func meters() -> Dictionary:
	var out := {}
	for p in players:
		var r: Runner = _runners[p.id]
		out[p.id] = snappedf(clampf(r.x, 0.0, COURSE_LEN) / PX_PER_M, 0.1)
	return out


func _mood(pid: int) -> int:
	var r: Runner = _runners[pid]
	if _ending and pid in _winners:
		return PlayerAvatar.Mood.HAPPY
	if r.stumble > 0.0 or r.fall > 0.0:
		return PlayerAvatar.Mood.SURPRISED
	return PlayerAvatar.Mood.NORMAL


# --- Dibujo ---------------------------------------------------------------------------

func _lane_top(i: int) -> float:
	return _board.position.y + _lane_h * i


func _draw() -> void:
	_ensure_course()
	var v25 := draw_board_25d(board_view(players.size()))
	if v25 != _v25:
		_v25 = v25
		# En 2.5D la capa de los carriles dibuja en px de pantalla y no recorta
		# (el recorte de un Control es un rectángulo; lo que asoma por los
		# costados lo tapa el escenario, ver abajo).
		_world.clip_contents = not v25
		_world.position = Vector2.ZERO if v25 else _board.position
		_world.queue_redraw()
	if not _v25:
		draw_sky()
		draw_play_field(_board, _lane_h / 2.0)
	draw_static(_paint_lanes)
	if _v25:
		_draw_side_cover()
	var mascot_x := _board.position.x + CAM_X
	var tags: Array = []
	var marks := GameArt.TriBatch.new()
	for i in players.size():
		var p: Dictionary = players[i]
		var r: Runner = _runners[p.id]
		var ground := _lane_top(i) + _lane_h - GROUND_H
		var mood := _mood(p.id)
		var anim := mascot_anim(p.id, Vector2(1, 0))
		anim["squash"] = r.squash
		anim["wave"] = mood == PlayerAvatar.Mood.HAPPY
		# Pies en el suelo del carril, en pantalla, y escala por profundidad.
		var base := _screen(Vector2(mascot_x, ground))
		var d := _depth(Vector2(mascot_x, ground))
		if r.fall > 0.0:
			# Se hunde de golpe hasta la cintura y se sacude, trabada en el pozo; el
			# frente del pozo (después) le tapa las piernas.
			var k := 1.0 - r.fall / PIT_SEC
			var s := lerpf(1.0, 0.85, k) * d
			var sink := PIT_SINK * minf(k * 5.0, 1.0) * d
			var xform := Transform2D(sin(k * TAU * 2.0) * 0.18, Vector2(s, s), 0.0, base + Vector2(0, sink))
			draw_set_transform_matrix(xform)
			PlayerAvatar.draw_mascot(self, Vector2.ZERO, MASCOT_SCALE, p.color, PlayerAvatar.style_of(p), mood,
				0.0, 0.0, false, {"t": anim.t, "look": Vector2(0, 1), "xform": xform})
			draw_set_transform(Vector2.ZERO)
			var front := GameArt.TriBatch.new()
			_add_pit_front(front, r, i)
			if _v25:
				front.points = _lane_xf(i) * front.points
			front.flush(self)
			tags.append([p, base + Vector2(0, sink), MASCOT_SCALE * s, -1.0])
			continue
		var feet := base - Vector2(0, r.floor_h * d)
		var lift := (r.y - r.floor_h) * d
		if r.stumble > 0.0:
			# Tropezón: se va para adelante y vuelve.
			var k := 1.0 - r.stumble / STUMBLE_SEC
			var xform := Transform2D(sin(minf(k * 2.0, 1.0) * PI) * 0.45, feet - Vector2(0, lift))
			draw_set_transform_matrix(xform)
			anim["xform"] = xform
			PlayerAvatar.draw_mascot(self, Vector2(0, lift), MASCOT_SCALE * d, p.color, PlayerAvatar.style_of(p), mood,
				0.0, lift, false, anim)
			draw_set_transform(Vector2.ZERO)
		else:
			PlayerAvatar.draw_mascot(self, feet, MASCOT_SCALE * d, p.color, PlayerAvatar.style_of(p), mood, 0.0, lift, false, anim)
		tags.append([p, feet - Vector2(0, lift), MASCOT_SCALE * d, -1.0])
	# Marcador de cada riel (dónde va cada uno respecto de la meta).
	for i in players.size():
		var p: Dictionary = players[i]
		var rail := _rail_rect(i)
		var c := Vector2(rail.position.x + rail.size.x * clampf((_runners[p.id] as Runner).x / COURSE_LEN, 0.0, 1.0), rail.get_center().y)
		var d := 1.0
		if _v25:
			var xf := _top_xf(i)
			c = xf * (c - _board.position)
			d = xf.x.length()
		marks.circle(c, 13.0 * d, UiTheme.INK, 16)
		marks.circle(c, 9.5 * d, p.color, 16)
		marks.circle(c + Vector2(-3, -3) * d, 3.0 * d, Color(1, 1, 1, 0.6), 8)
	marks.flush(self)
	draw_player_tags(tags)  # Sin marcador de salida: carriles apilados, cada uno con su cartel [1P | nombre].
	draw_hud(meters(), clock_text(DURATION_SEC - _elapsed), "clock")
	if _countdown > 0.0:
		draw_text_centered("%d" % ceili(_countdown), SCREEN / 2.0, 260, UiTheme.PAPER, 22)
	elif _countdown > -GO_SEC:
		draw_text_centered("¡YA!", SCREEN / 2.0, 260, UiTheme.ACCENT, 22)
	elif _ending:
		draw_text_centered(_end_text, SCREEN / 2.0, 200, UiTheme.ACCENT, 20)


## Frente del pozo delante de la mascota que cayó: le tapa los pies. En
## coordenadas del tablero (0,0 = esquina): en 2.5D se lleva a la pantalla
## con la transformación del carril.
func _add_pit_front(b: GameArt.TriBatch, r: Runner, lane: int) -> void:
	var cam := r.x - CAM_X
	var ground := _lane_h * lane + _lane_h - GROUND_H
	var x0 := maxf(r.pit_x0 - cam, 0.0)
	var x1 := minf(r.pit_x1 - cam, _board.size.x)
	if x1 <= x0:
		return
	var o := Vector2.ZERO if _v25 else _board.position
	b.quad_colors(o + Vector2(x0, ground + 6.0), o + Vector2(x1, ground + 6.0), o + Vector2(x1, ground + GROUND_H), o + Vector2(x0, ground + GROUND_H),
		UiTheme.HURDLES_PIT, UiTheme.HURDLES_PIT, UiTheme.HURDLES_PIT_DEEP, UiTheme.HURDLES_PIT_DEEP)


# --- 2.5D: de las coordenadas del tablero a la pantalla ------------------------------

## Dónde se dibuja un punto del plano (px de la pantalla del dibujo plano):
## proyectado en 2.5D, igual en plano.
func _screen(p: Vector2) -> Vector2:
	return board_view(players.size()).project(p) if _v25 else p


## Escala de lo que está parado en `p`: más chico atrás en 2.5D; 1 en plano.
func _depth(p: Vector2) -> float:
	if not _v25:
		return 1.0
	return clampf(board_view(players.size()).scale_at(p), UiTheme.BOARD25D_SCALE_MIN, UiTheme.BOARD25D_SCALE_MAX)


## Transformación que lleva las coordenadas del tablero (0,0 = esquina) a
## la pantalla acostadas en el piso del carril `i`, tomada en la línea del
## suelo: a lo largo del carril es exacta; los ladrillos del piso (40 px de
## alto) quedan a menos de 1 px. Identidad (más el origen del tablero) en plano.
func _lane_xf(i: int) -> Transform2D:
	var ground := _lane_top(i) + _lane_h - GROUND_H
	return _floor_xf(Vector2(_board.get_center().x, ground))


## Lo mismo, tomada arriba del carril (carteles y rieles).
func _top_xf(i: int) -> Transform2D:
	return _floor_xf(Vector2(_board.get_center().x, _lane_top(i) + 36.0))


func _floor_xf(at: Vector2) -> Transform2D:
	if not _v25:
		return Transform2D(0.0, _board.position)
	return board_view(players.size()).floor_xform(at) * Transform2D(0.0, _board.position)


## Cartel de frente (valla, escalón, meta) apoyado en `(x, ground)` del
## tablero: en 2.5D, en su punto del suelo proyectado y escalado por la
## profundidad del carril (sin acostarlo); en plano, solo el traslado.
func _stand_xf(lane: int, x: float, ground: float) -> Transform2D:
	if not _v25:
		return Transform2D(0.0, Vector2(x, ground))
	var xf := _lane_xf(lane)
	var d := xf.x.length()
	return Transform2D(0.0, Vector2(d, d), 0.0, xf * Vector2(x, ground))


## Tapa con el escenario horneado lo que asoma por los costados del tablero
## (la capa de los carriles no recorta en 2.5D): dos polígonos, del borde de
## la pantalla al borde del tablero (que en perspectiva es una línea inclinada).
func _draw_side_cover() -> void:
	var v := board_view(players.size())
	var q := v.quad(_board)
	var pad := 6.0
	var top := q[0].y - pad
	var bottom := q[3].y + pad
	draw_board_25d_cover(v, [
		PackedVector2Array([Vector2(0, top), Vector2(q[0].x + 1.0, top), Vector2(q[3].x + 1.0, bottom), Vector2(0, bottom)]),
		PackedVector2Array([Vector2(q[1].x - 1.0, top), Vector2(SCREEN.x, top), Vector2(SCREEN.x, bottom), Vector2(q[2].x - 1.0, bottom)]),
	])


## Riel de progreso de un carril (arriba a la derecha).
func _rail_rect(lane: int) -> Rect2:
	return Rect2(_board.end.x - RAIL_W - 72.0, _lane_top(lane) + 32.0, RAIL_W, 10.0)


func _tag_rect(lane: int) -> Rect2:
	return Rect2(_board.position.x + 16.0, _lane_top(lane) + 14.0, TAG_SIZE.x, TAG_SIZE.y)


## Lo fijo de los carriles (se dibuja una vez, en la capa de fondo): cartel
## [1P | nombre] con relieve y riel de progreso con la banderita de la meta.
func _paint_lanes(ci: CanvasItem) -> void:
	var b := GameArt.TriBatch.new()
	for i in players.size():
		var col: Color = players[i].color
		var tag := _tag_rect(i)
		# En 2.5D: cartel de frente (legible) en su lugar proyectado; el riel,
		# acostado en el carril; la banderita, de frente en la punta del riel.
		var tag_xf := _bill_xf(i, tag.get_center())
		var tb := GameArt.TriBatch.new()
		var t := Rect2(-tag.size / 2.0, tag.size)
		tb.feather_capsule(t.grow(4.0).grow_side(SIDE_BOTTOM, 3.0), UiTheme.INK)
		tb.capsule(t.grow(4.0).grow_side(SIDE_BOTTOM, 3.0), UiTheme.INK)
		tb.capsule(t, col.darkened(0.3))
		tb.capsule(Rect2(t.position, t.size - Vector2(0, 6.0)), col)
		tb.capsule(Rect2(t.position + Vector2(14.0, 4.0), Vector2(t.size.x * 0.6, 12.0)), Color(1, 1, 1, 0.3))
		tb.capsule(Rect2(t.position + Vector2(7.0, 8.0), Vector2(52.0, t.size.y - 20.0)), UiTheme.CHIP_DARK)
		b.template(tb.points, tb.colors, tag_xf)
		var rail := _rail_rect(i)
		var rb := GameArt.TriBatch.new()
		rb.capsule(Rect2(rail.position - _board.position, rail.size), UiTheme.HURDLES_RAIL)
		b.template(rb.points, rb.colors, _top_xf(i))
		# Banderita a cuadros al final del riel.
		var pole := Vector2(rail.end.x + 18.0, rail.get_center().y + 14.0)
		var fb := GameArt.TriBatch.new()
		fb.rect(Rect2(-3.0, -44.0, 6.0, 44.0), UiTheme.INK)
		fb.rect(Rect2(1.0, -44.0, 36.0, 24.0), UiTheme.INK)
		for cy in 2:
			for cx in 3:
				fb.rect(Rect2(3.0 + cx * 11.0, -42.0 + cy * 10.0, 11.0, 10.0), UiTheme.PAPER if (cx + cy) % 2 == 0 else UiTheme.CHIP_DARK)
		b.template(fb.points, fb.colors, _bill_xf(i, pole))
	b.flush(ci)
	for i in players.size():
		var p: Dictionary = players[i]
		var tag := _tag_rect(i)
		var xf := _bill_xf(i, tag.get_center())
		var d := xf.x.length()
		var left := xf * Vector2(-tag.size.x / 2.0, -3.0)
		UiTheme.draw_text(ci, UiTheme.player_tag(p.slot), left + Vector2(33.0, 0) * d, roundi(24 * d), UiTheme.PAPER)
		UiTheme.draw_text_left(ci, p.name, left + Vector2(70.0, 0) * d, roundi(24 * d),
			UiTheme.text_on(p.color), (tag.size.x - 16.0 - 70.0) * d)


## Cartel de frente centrado en `at` (px del dibujo plano) arriba del carril
## `i`: en 2.5D, proyectado con _top_xf y escalado; en plano, solo el traslado.
func _bill_xf(i: int, at: Vector2) -> Transform2D:
	if not _v25:
		return Transform2D(0.0, at)
	var xf := _top_xf(i)
	var d := xf.x.length()
	return Transform2D(0.0, Vector2(d, d), 0.0, xf * (at - _board.position))


## Lo que pasa por los carriles, en coordenadas de `_world` (0,0 = esquina
## del tablero): piso de ladrillos, pozos, escalones, plataformas, vallas y
## meta. Un solo lote (un draw call).
func _draw_world() -> void:
	var b := _batch
	var w := _board.size.x
	var ground_tpl := _ground_template()
	var bush_tpl := _bush_template()
	for i in players.size():
		var r: Runner = _runners[players[i].id]
		var top := _lane_h * i
		var ground := top + _lane_h - GROUND_H
		var cam := r.x - CAM_X
		# Plano: todo en un lote en coordenadas del tablero. 2.5D: lo acostado
		# (matas de fondo, piso, largada, pozos) se arma igual y se lleva a la
		# pantalla con la transformación del carril; lo parado va de frente
		# (ver _stand_xf) directo en el lote de pantalla.
		var flat := GameArt.TriBatch.new() if _v25 else b
		flat.template(bush_tpl[0], bush_tpl[1], Transform2D(0.0, Vector2(-fposmod(cam * BUSH_PARALLAX, BUSH_PERIOD), ground)))
		if _v25:
			flat.points = _lane_xf(i) * flat.points
			b.points.append_array(flat.points)
			b.colors.append_array(flat.colors)
			flat = GameArt.TriBatch.new()
		flat.template(ground_tpl[0], ground_tpl[1], Transform2D(0.0, Vector2(-fposmod(cam, PERIOD), ground)))
		# Largada: raya blanca en el piso.
		if cam < 10.0 and cam > -w:
			flat.rect(Rect2(-cam - 4.0, ground, 8.0, GROUND_H), UiTheme.HURDLES_POST)
		var k := maxi(_starts.bsearch(cam - GRID * 7.0), 0)
		var stand := GameArt.TriBatch.new() if _v25 else b
		while k < _course.size() and _starts[k] < cam + w + GRID:
			_add_obstacle(flat, stand, _course[k], k, r, cam, ground, i)
			k += 1
		var fx := COURSE_LEN - cam
		if fx > -CHECK * 3.0 and fx < w + CHECK * 3.0:
			var tpl := _finish_template(ground - (top + FINISH_TOP))
			stand.template(tpl[0], tpl[1], _stand_xf(i, fx, ground))
		if _v25:
			b.points.append_array(_lane_xf(i) * flat.points)
			b.colors.append_array(flat.colors)
			b.points.append_array(stand.points)
			b.colors.append_array(stand.colors)
		elif i < players.size() - 1:
			# Filete de tinta entre carriles (en 2.5D va horneado en el escenario).
			b.rect(Rect2(0.0, top + _lane_h - 2.0, w, 4.0), UiTheme.INK)
	b.flush(_world)


## Un obstáculo: los pozos, acostados en el piso (`flat`, coordenadas del
## tablero); vallas, escalones y plataformas, parados (`stand`, ubicados con
## _stand_xf). En plano `flat` y `stand` son el mismo lote.
func _add_obstacle(flat: GameArt.TriBatch, stand: GameArt.TriBatch, o: Dictionary, index: int, r: Runner, cam: float,
		ground: float, lane: int) -> void:
	var x := float(o.x) - cam
	var ow := float(o.w)
	var h := float(o.h)
	match int(o.kind):
		Kind.PIT:
			flat.rect(Rect2(x, ground - 3.0, ow, 3.0), UiTheme.HURDLES_PIT)
			flat.quad_colors(Vector2(x, ground), Vector2(x + ow, ground), Vector2(x + ow, ground + GROUND_H), Vector2(x, ground + GROUND_H),
				UiTheme.HURDLES_PIT, UiTheme.HURDLES_PIT, UiTheme.HURDLES_PIT_DEEP, UiTheme.HURDLES_PIT_DEEP)
			# Paredes del pozo: la de la derecha, iluminada; la de la izquierda, en sombra.
			flat.rect(Rect2(x, ground - 3.0, 4.0, GROUND_H + 3.0), UiTheme.INK)
			flat.rect(Rect2(x + ow - 10.0, ground, 10.0, GROUND_H), UiTheme.HURDLES_PIT.lightened(0.18))
			flat.rect(Rect2(x + ow - 4.0, ground - 3.0, 4.0, GROUND_H + 3.0), UiTheme.INK)
		Kind.BLOCK:
			var tpl := _block_template(ow, h, index % UiTheme.BRICKS.size())
			stand.template(tpl[0], tpl[1], _stand_xf(lane, x, ground))
		Kind.PLATFORM:
			var tpl := _platform_template(ow)
			stand.template(tpl[0], tpl[1], _stand_xf(lane, x, ground) * Transform2D(0.0, Vector2(0, -h)))
		Kind.HURDLE:
			var tpl := _hurdle_template(UiTheme.BRICKS[index % UiTheme.BRICKS.size()])
			var base := _stand_xf(lane, x, ground)
			if r.knocked.has(index):
				# Valla tirada: cae para adelante girando sobre la pata de adelante.
				var k := clampf((_elapsed - float(r.knocked[index])) / 0.22, 0.0, 1.0)
				var pivot := Vector2(26.0, 0.0)
				var xf := base * Transform2D(0.0, pivot) * Transform2D(k * 1.25, Vector2.ZERO) * Transform2D(0.0, -pivot)
				stand.template(tpl[0], tpl[1], xf)
			else:
				stand.template(tpl[0], tpl[1], base)


# --- Plantillas (triángulos locales con color, se arman una vez) -------------------------

## Ladrillo con bisel (como los del marco del tablero): labio oscuro, cara
## con la mitad de arriba más clara y una línea de brillo.
static func _brick_template(size: Vector2, col: Color) -> Array:
	var key := ["brick", size, col]
	if _templates.has(key):
		return _templates[key]
	var b := GameArt.TriBatch.new()
	var k := minf(5.0, size.y * 0.2)
	b.chamfer_rect(Rect2(Vector2(1.0, 0.0), size - Vector2(2.0, 1.0)), k, col.darkened(0.38))
	var face := Rect2(Vector2(3.0, 2.5), size - Vector2(6.0, 9.0))
	b.chamfer_rect(Rect2(face.position.x, face.get_center().y, face.size.x, face.size.y / 2.0), k - 1.0, col)
	b.chamfer_rect(Rect2(face.position, Vector2(face.size.x, face.size.y / 2.0 + 1.0)), k - 1.0, col.lightened(0.14))
	b.chamfer_rect(Rect2(face.position + Vector2(5.0, 3.0), Vector2(face.size.x - 10.0, minf(5.0, face.size.y * 0.2))), 2.0, col.lightened(0.5))
	_templates[key] = [b.points, b.colors]
	return _templates[key]


## Escalón: dos filas de ladrillos de colores con contorno de tinta.
## Origen: esquina de abajo a la izquierda, sobre el piso.
static func _block_template(w: float, h: float, shift: int) -> Array:
	var key := ["block", w, h, shift]
	if _templates.has(key):
		return _templates[key]
	var b := GameArt.TriBatch.new()
	var rows := 2
	var bh := h / rows
	b.rect(Rect2(-3.0, -h - 3.0, w + 6.0, h + 3.0), UiTheme.INK)
	for row in rows:
		for c in roundi(w / GRID):
			var col: Color = UiTheme.BRICKS[(shift * 3 + row * 5 + c * 2) % UiTheme.BRICKS.size()]
			var tpl := _brick_template(Vector2(GRID, bh), col)
			b.template(tpl[0], tpl[1], Transform2D(0.0, Vector2(c * GRID, -h + row * bh)))
	_templates[key] = [b.points, b.colors]
	return _templates[key]


## Plataforma flotante: una fila de ladrillos amarillos y naranjas.
## Origen: borde izquierdo de su cara de arriba (donde se pisa).
static func _platform_template(w: float) -> Array:
	var key := ["platform", w]
	if _templates.has(key):
		return _templates[key]
	var b := GameArt.TriBatch.new()
	b.rect(Rect2(-3.0, -3.0, w + 6.0, PLATFORM_T + 7.0), UiTheme.INK)
	for c in roundi(w / GRID):
		var tpl := _brick_template(Vector2(GRID, PLATFORM_T), UiTheme.BRICKS[2 if c % 2 == 0 else 1])
		b.template(tpl[0], tpl[1], Transform2D(0.0, Vector2(c * GRID, 0.0)))
	_templates[key] = [b.points, b.colors]
	return _templates[key]


## Piso de un carril: fila de ladrillos de colores (repite cada PERIOD) con
## un filete de tinta arriba, del ancho del tablero más un período.
func _ground_template() -> Array:
	var key := ["ground", _board.size.x]
	if _templates.has(key):
		return _templates[key]
	var b := GameArt.TriBatch.new()
	var length := _board.size.x + PERIOD + GRID
	b.rect(Rect2(0.0, -3.0, length, GROUND_H + 3.0), UiTheme.INK)
	var n := ceili(length / GRID)
	for c in n:
		var tpl := _brick_template(Vector2(GRID, GROUND_H), UiTheme.HURDLES_GROUND if c % 2 == 0 else UiTheme.HURDLES_GROUND_ALT)
		b.template(tpl[0], tpl[1], Transform2D(0.0, Vector2(c * GRID, 0.0)))
	_templates[key] = [b.points, b.colors]
	return _templates[key]


## Arbustos del fondo (se ven detrás del piso, más lento: dan profundidad).
## Tiras del ancho del tablero más un período; origen: línea del piso.
func _bush_template() -> Array:
	var key := ["bushes", _board.size.x]
	if _templates.has(key):
		return _templates[key]
	var b := GameArt.TriBatch.new()
	var x := 0.0
	var k := 0
	while x < _board.size.x + BUSH_PERIOD:
		# Dos matas por período, de distinto tamaño: una grande y una chica.
		var big := k % 2 == 0
		var r := 46.0 if big else 30.0
		var c := Vector2(x + (90.0 if big else 20.0), 6.0)
		b.circle(c + Vector2(-r * 0.9, -r * 0.2), r * 0.72, UiTheme.HURDLES_BUSH, 20)
		b.circle(c + Vector2(r * 0.9, -r * 0.15), r * 0.78, UiTheme.HURDLES_BUSH, 20)
		b.circle(c + Vector2(0, -r * 0.55), r, UiTheme.HURDLES_BUSH, 24)
		b.circle(c + Vector2(-r * 0.25, -r * 0.95), r * 0.35, UiTheme.HURDLES_BUSH_LIGHT, 14)
		x += BUSH_PERIOD / 2.0
		k += 1
	_templates[key] = [b.points, b.colors]
	return _templates[key]


## Valla: dos patas blancas con base y un travesaño del color con rayas
## blancas. Origen: centro de la base, sobre el piso.
static func _hurdle_template(col: Color) -> Array:
	var key := ["hurdle", col]
	if _templates.has(key):
		return _templates[key]
	var b := GameArt.TriBatch.new()
	var h := HURDLE_H
	for lx: float in [-20.0, 20.0]:
		b.rect(Rect2(lx - 12.0, -8.0, 24.0, 8.0), UiTheme.INK)
		b.rect(Rect2(lx - 6.0, -h + 4.0, 12.0, h - 4.0), UiTheme.INK)
		b.rect(Rect2(lx - 9.0, -5.0, 18.0, 4.0), UiTheme.HURDLES_POST)
		b.rect(Rect2(lx - 3.0, -h + 6.0, 6.0, h - 9.0), UiTheme.HURDLES_POST)
	var bar := Rect2(-32.0, -h - 4.0, 64.0, 18.0)
	b.round_rect(bar.grow(3.5), 7.0, UiTheme.INK)
	b.round_rect(bar, 5.0, col.darkened(0.3))
	b.round_rect(Rect2(bar.position, bar.size - Vector2(0, 4.0)), 5.0, col)
	for sx: float in [-14.0, 6.0]:
		b.quad(Vector2(sx, bar.position.y + 1.0), Vector2(sx + 9.0, bar.position.y + 1.0),
			Vector2(sx + 1.0, bar.end.y - 4.0), Vector2(sx - 8.0, bar.end.y - 4.0), UiTheme.HURDLES_POST)
	b.rect(Rect2(bar.position + Vector2(5.0, 2.0), Vector2(bar.size.x - 10.0, 3.0)), Color(1, 1, 1, 0.45))
	_templates[key] = [b.points, b.colors]
	return _templates[key]


## Meta: franja a cuadros de `height` px sobre el piso, con postes de tinta
## y un banderín arriba. Origen: base, sobre el piso.
static func _finish_template(height: float) -> Array:
	var key := ["finish", height]
	if _templates.has(key):
		return _templates[key]
	var b := GameArt.TriBatch.new()
	var w := CHECK * 2.0
	b.rect(Rect2(-4.0, -height - 4.0, w + 8.0, height + 4.0), UiTheme.INK)
	var y := -height
	var row := 0
	while y < -0.5:
		var hh := minf(CHECK, -y)
		for c in 2:
			b.rect(Rect2(c * CHECK, y, CHECK, hh), UiTheme.PAPER if (row + c) % 2 == 0 else UiTheme.CHIP_DARK)
		y += CHECK
		row += 1
	b.tri(Vector2(w + 4.0, -height - 4.0), Vector2(w + 44.0, -height + 12.0), Vector2(w + 4.0, -height + 28.0), UiTheme.INK)
	b.tri(Vector2(w + 4.0, -height + 1.0), Vector2(w + 34.0, -height + 12.0), Vector2(w + 4.0, -height + 23.0), UiTheme.BRICKS[0])
	_templates[key] = [b.points, b.colors]
	return _templates[key]
