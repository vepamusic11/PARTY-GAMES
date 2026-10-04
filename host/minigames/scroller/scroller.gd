extends MiniGame
## ¡Que no te deje la cámara!: la cámara avanza sola hacia la derecha, cada
## vez más rápido, por un recorrido de bloques de juguete con sierras,
## molinetes, pozos, pasillos que se angostan y flechas de impulso. Cada
## mascota se mueve libre con el joystick (con inercia) y se puede empujar a
## los demás. Queda eliminado el que se queda atrás (sale por el borde
## izquierdo de la cámara) o toca un obstáculo mortal (sierra, molinete o
## pozo); los bloques son sólidos: no matan, pero te frenan.
##
## Termina cuando queda uno en pie o a los DURATION_SEC segundos: ganan los
## que siguen en pie, ordenados por distancia (el torneo ordena a los
## ganadores por puntaje). Puntaje: metros recorridos desde la salida.
##
## Recorrido: tramos prediseñados (TEMPLATES) elegidos y espejados con una
## semilla por partida (`build_segment`, pura): el mismo para todos y
## siempre igual con la misma semilla. Los tramos se van haciendo más
## difíciles a medida que avanza la cámara.
##
## Mundo y pantalla: las posiciones (`_pos`, los obstáculos) están en
## coordenadas del mundo (x crece hacia la derecha sin límite; y va de 0 a
## WORLD_H). La cámara muestra de `_cam` a `_cam + VIEW.size.x`, dentro del
## rectángulo VIEW de la TV.
##
## Capas de dibujo (rendimiento, ver docs/PERFORMANCE.md):
##   _backdrop (MiniGame.draw_static)  escenario, marco de la cámara y tribuna: una vez
##   _world (Control recortado a VIEW, detrás del juego):
##     _seg_root  un Node2D por tramo visible, dibujado UNA vez (piso, bloques,
##                pozos, bases); en cada frame solo se mueve su position.x
##     _dyn       sierras, molinetes y flechas animadas: un lote por frame
##   este nodo   avisos del borde, mascotas, globitos, efectos, tribuna, textos
##
## La física vive en funciones estáticas puras (`step_velocity`,
## `resolve_push`, `push_out_of_rect`, `hazard_hits`…) para testearla sin escena.

const DURATION_SEC := 75.0
const COUNTDOWN_SEC := 3.0
const GO_SEC := 0.8               ## Cuánto se ve "¡YA!" después del 1.
const END_DELAY_SEC := 1.4        ## Pausa final: se ve la última eliminación.

# --- Cámara y mundo ------------------------------------------------------------
## Lo que ve la cámara, en la TV. Arriba queda el marcador y abajo la tribuna.
const VIEW := Rect2(104, 140, 1712, 700)
const WORLD_H := 700.0            ## Alto del mundo (= VIEW.size.y).
const SEG_W := 1000.0             ## Ancho de cada tramo del recorrido.
const CELL := 100.0               ## Baldosas del piso.
## Arranque amable (prueba real con primerizos, docs/PRUEBA_REAL.md): las
## mascotas salen más adentro de la cámara (antes a 300 px del borde: a quien
## no entendía que había que correr lo dejaba en ~2 s) y la cámara arranca
## despacito durante un período de gracia, más largo y con una velocidad de
## crucero más baja cuantos menos jugadores hay. Quien no se mueve queda
## afuera a los ~5–6 s (antes ~2 s), mientras la TV dice "¡Corré a la derecha!".
const START_X := 560.0            ## x (mundo) donde arrancan las mascotas (alternan ±START_STAGGER).
const START_STAGGER := 60.0
const START_LINE := 740.0         ## Línea de salida: desde acá se cuentan los metros.
const PX_PER_M := 50.0            ## Un tramo = 20 m.
const CAM_SPEED_GRACE := 45.0     ## px/s al "¡YA!": la cámara arranca despacito…
const GRACE_SEC := 3.0            ## …y en este tiempo llega a su velocidad de arranque (con 4 jugadores).
const GRACE_EXTRA_PER_MISSING := 1.0  ## Segundos más de gracia por cada jugador menos de 4 (2 jugadores: 5 s).
const CAM_SPEED_START := 140.0    ## px/s al terminar la gracia con 4 jugadores (ver start_speed).
const CAM_SPEED_START_FACTOR: Array[float] = [1.0, 1.0, 0.8, 0.9, 1.0]  ## Por cantidad de jugadores (índice = jugadores).
const CAM_SPEED_END := 320.0      ## px/s CAM_RAMP_SEC después de la gracia.
const CAM_RAMP_SEC := 55.0
const GO_RIGHT_TEXT := "¡Corré a la derecha!"  ## Cartel durante la gracia.
const SPEEDUP_AT: Array[float] = [20.0, 38.0, 55.0]  ## Cartel "¡Más rápido!".

# --- Jugadores -------------------------------------------------------------------
const ACCEL := 1800.0             ## px/s² con el joystick a fondo.
const FRICTION := 3.2             ## Frenado del piso (proporcional a la velocidad).
const MAX_SPEED := 470.0          ## Tope con el joystick (empujones e impulsos lo superan).
const BODY_RADIUS := 30.0         ## Huella de la mascota (en los pies) para choques.
const RAM_BONUS := 0.5            ## Empujón extra al embestir (como en Empujones).
const TOP_LIMIT := 72.0           ## y mínima de los pies: la cabeza no se sale del marco.
const BOTTOM_LIMIT := 30.0        ## Distancia mínima de los pies al borde de abajo.
const RIGHT_LIMIT := 60.0         ## No se puede pasar el borde derecho de la cámara.
const WARN_DIST := 300.0          ## A menos de esto del borde izquierdo: aviso y cara de susto.
const BOOST_SPEED := 780.0        ## Velocidad hacia la derecha al pisar una flecha.
## Qué parte de la huella cuenta al tocar algo mortal (perdona roces).
const HAZARD_GRACE := 0.55
const MASCOT_SCALE := 0.72
const NAME_OFFSET := 24.0

# --- Obstáculos ---------------------------------------------------------------------
const ARM_W := 34.0               ## Grosor del brazo de los molinetes.
const BLOCK_DEPTH := 16.0         ## Cara de adelante de los bloques (relieve).
const STUD_STEP := 50.0           ## Separación de los botoncitos de los bloques.

# --- Eliminación y efectos ---------------------------------------------------------
const FLY_SEC := 1.1              ## Sale volando (sierra, molinete o cámara).
const FALL_SEC := 0.7             ## Se cae al pozo.
const FLY_GRAVITY := 2200.0
const HOP_SEC := 0.35             ## Saltito al llegar a la tribuna.
const POPUP_SEC := 1.1
const BUMP_FX_SEC := 0.4
const BUMP_MIN_SPEED := 180.0     ## Choques más suaves no muestran estrellitas.
const BUMP_COOLDOWN := 0.3
const ANNOUNCE_SEC := 1.8

# --- Tribuna ------------------------------------------------------------------------
const TRIB := Rect2(104, 922, 1712, 94)
const TRIB_TITLE_W := 212.0
const TRIB_SCALE := 0.58
## Poses extra que se hornean en la intro (MascotAtlas.prewarm_game): cara de
## susto caminando cerca del borde, festejo caminando al final y la mascota
## triste en la tribuna (con su último paso).
const MASCOT_PREWARM := [[MASCOT_SCALE, ["walk@3", "walk@1"]], [TRIB_SCALE, ["walk_f@2"]]]

## Tramos prediseñados, en coordenadas del tramo (x 0..SEG_W, y 0..WORLD_H).
##   ["block", Rect2]                          bloque sólido (frena, no mata)
##   ["pit", Rect2]                            pozo (mortal)
##   ["boost", Rect2]                          flechas de impulso (hacia la derecha)
##   ["saw", centro, radio, amplitud, vel]      sierra que va y viene (mortal)
##   ["spinner", centro, medio largo, vel]     molinete que gira (mortal)
## Todos dejan libre el borde izquierdo y el derecho entre y 160 y 540, así
## dos tramos seguidos siempre se pueden pasar.
const TEMPLATES := {
	# Fáciles
	"bloques": [["block", Rect2(240, 100, 200, 160)], ["block", Rect2(620, 440, 200, 160)]],
	"pasillo": [["block", Rect2(160, 0, 700, 200)], ["block", Rect2(160, 500, 700, 200)],
		["boost", Rect2(320, 300, 380, 100)]],
	"pozo": [["pit", Rect2(360, 190, 300, 320)]],
	"flechas": [["boost", Rect2(120, 90, 320, 110)], ["block", Rect2(540, 250, 160, 200)],
		["boost", Rect2(580, 510, 320, 110)]],
	"sierra_lenta": [["saw", Vector2(500, 350), 54.0, Vector2(0, 200), 1.3]],
	# Medianos
	"sierra": [["saw", Vector2(500, 350), 58.0, Vector2(0, 230), 1.9], ["block", Rect2(140, 0, 180, 120)],
		["block", Rect2(700, 580, 180, 120)]],
	"embudo": [["block", Rect2(0, 0, 240, 90)], ["block", Rect2(240, 0, 240, 170)], ["block", Rect2(480, 0, 260, 230)],
		["block", Rect2(0, 610, 240, 90)], ["block", Rect2(240, 530, 240, 170)], ["block", Rect2(480, 470, 260, 230)],
		["boost", Rect2(790, 290, 170, 120)]],
	"molinete": [["spinner", Vector2(500, 350), 200.0, 1.5]],
	"pozos": [["pit", Rect2(150, 0, 240, 320)], ["pit", Rect2(610, 380, 240, 320)]],
	# Difíciles
	"sierras": [["saw", Vector2(290, 210), 56.0, Vector2(0, 150), 2.3], ["saw", Vector2(710, 490), 56.0, Vector2(0, 150), -2.3]],
	"pasillo_sierra": [["block", Rect2(0, 0, 1000, 160)], ["block", Rect2(0, 540, 1000, 160)],
		["saw", Vector2(500, 350), 50.0, Vector2(340, 0), 1.4]],
	"molinetes": [["spinner", Vector2(270, 230), 170.0, 2.0], ["spinner", Vector2(730, 470), 170.0, -2.0]],
	"puente": [["pit", Rect2(200, 0, 600, 270)], ["pit", Rect2(200, 430, 600, 270)],
		["boost", Rect2(240, 285, 520, 130)]],
}
const EASY: Array[String] = ["bloques", "pasillo", "pozo", "flechas", "sierra_lenta"]
const MEDIUM: Array[String] = ["sierra", "embudo", "molinete", "pozos"]
const HARD: Array[String] = ["sierras", "pasillo_sierra", "molinetes", "puente"]

var _pos: Dictionary = {}         # player_id -> Vector2 (pies, en el mundo)
var _vel: Dictionary = {}         # player_id -> Vector2
var _axis: Dictionary = {}        # player_id -> Vector2
var _on_boost: Dictionary = {}    # player_id -> bool (para sonar al pisar la flecha)
## Eliminados: player_id -> {kind: "camera"|"hit"|"pit", t, pos (pantalla;
## en "pit", mundo), vel, spin, grow, meters}
var _out: Dictionary = {}
var _effects: Array = []          # {pos (mundo), t, power}
var _pair_fx: Dictionary = {}     # Vector2i(a, b) -> segundos de juego del último efecto
var _popups: Array = []           # {text, pos (pantalla), t}
var _segments: Dictionary = {}    # índice de tramo -> Array de obstáculos (mundo)
var _course_seed := -1
var _cam := 0.0                   # x del mundo en el borde izquierdo de la cámara
var _cam_speed := CAM_SPEED_START
var _countdown := COUNTDOWN_SEC
var _elapsed := 0.0
var _anim := 0.0
var _next_speedup := 0
var _announce := ""
var _announce_t := 0.0
var _ending := false
var _end_timer := 0.0
var _result: Dictionary = {}
var _rng := RandomNumberGenerator.new()

var _world: Control               # recorta el mundo a VIEW
var _seg_root: Node2D
var _dyn: Node2D
var _seg_nodes: Dictionary = {}   # índice de tramo -> Node2D

static var _gear: PackedVector2Array  # sierra unitaria (dientes), se arma una vez


static func get_info() -> Dictionary:
	return {
		"id": "scroller",
		"title": "¡Que no te deje la cámara!",
		"description": "Corré hacia la derecha: la cámara avanza sola y no te espera. Esquivá sierras y pozos, y empujá a los demás. El último en pie gana.",
		"min_players": 2,
		"max_players": 4,
		"layout": Protocol.LAYOUT_JOYSTICK,
		"layout_data": {"hint": "¡Corré a la derecha! La cámara no espera"},
		"accent": UiTheme.ACCENT_SCROLLER,
		"score_label": "metros",
	}


func _ready() -> void:
	_world = Control.new()
	_world.position = VIEW.position
	_world.size = VIEW.size
	_world.clip_contents = true
	_world.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_world.show_behind_parent = true  # Detrás de las mascotas y los avisos.
	add_child(_world)
	_seg_root = Node2D.new()
	_world.add_child(_seg_root)
	_dyn = Node2D.new()
	_dyn.draw.connect(_draw_dyn)
	_world.add_child(_dyn)
	# Los tramos se crean en el primer paso (_sync_view): recién ahí se
	# sortea la semilla, así las miniaturas pueden fijarla después de setup().


func setup(p_players: Array[Dictionary]) -> void:
	super.setup(p_players)
	_rng.randomize()
	var n := players.size()
	for i in n:
		var p: Dictionary = players[i]
		# En zigzag: los globitos y nombres de dos vecinos no se pisan.
		_pos[p.id] = Vector2(START_X + (START_STAGGER if i % 2 == 1 else -START_STAGGER), WORLD_H * (i + 1) / (n + 1))
		_vel[p.id] = Vector2.ZERO
		_axis[p.id] = Vector2.ZERO


func on_input(player_id: int, input: Dictionary) -> void:
	if not _axis.has(player_id) or _out.has(player_id):
		return
	var axis: Variant = input.get("axis", Vector2.ZERO)
	_axis[player_id] = (axis as Vector2).limit_length(1.0) if axis is Vector2 else Vector2.ZERO


## Para los bots (ver MiniGame.bot_view): lo que se ve en la TV. Los
## obstáculos van por tramo (`segments`: índice -> Array, en coordenadas del
## mundo; los cercanos a cada jugador ya están armados). Solo lectura.
func bot_view() -> Dictionary:
	return {
		"pos": _pos, "vel": _vel, "out": _out, "cam": _cam, "cam_speed": _cam_speed, "countdown": _countdown,
		"elapsed": _elapsed, "segments": _segments, "seg_w": SEG_W, "view_w": VIEW.size.x,
		"top": TOP_LIMIT, "bottom": WORLD_H - BOTTOM_LIMIT, "right_limit": RIGHT_LIMIT,
		"body_radius": BODY_RADIUS, "max_speed": MAX_SPEED, "friction": FRICTION, "accel": ACCEL,
	}


## Fija la semilla del recorrido (tests y miniaturas). Sin llamarla, la
## partida sortea una al empezar.
func set_course_seed(value: int) -> void:
	_course_seed = value & 0x7FFFFFFF
	_segments.clear()
	for i: int in _seg_nodes:
		(_seg_nodes[i] as Node).queue_free()
	_seg_nodes.clear()


func _physics_process(delta: float) -> void:
	if is_finished():
		return
	step(delta)
	_sync_view()
	queue_redraw()


## Un paso de juego. Separado de _physics_process para que los tests lo
## puedan avanzar a mano.
func step(delta: float) -> void:
	_ensure_course()
	_anim += delta
	_announce_t = maxf(_announce_t - delta, 0.0)
	_update_outs(delta)
	_update_effects(delta)
	if _ending:
		_end_timer -= delta
		if _end_timer <= 0.0:
			finish(_result)
		return
	if _countdown > -GO_SEC:
		var before := _countdown
		_countdown -= delta
		tick_countdown(before, _countdown)
	if _countdown > 0.0:
		return  # Nadie se mueve (ni la cámara) hasta el "¡YA!".
	_elapsed = minf(_elapsed + delta, DURATION_SEC)
	_cam_speed = camera_speed(_elapsed, players.size())
	_cam += _cam_speed * delta
	_move_players(delta)
	_collide_players()
	_solve_world()
	_check_outs()
	_check_speedup()
	_check_end()


# --- Física y recorrido (puro, testeable) -----------------------------------------

## Velocidad de la cámara: durante la gracia sube de CAM_SPEED_GRACE a la de
## arranque (más baja con menos jugadores) y después acelera de a poco hasta
## CAM_SPEED_END a lo largo de CAM_RAMP_SEC.
static func camera_speed(elapsed: float, player_count: int = 4) -> float:
	var grace := grace_sec(player_count)
	var start := start_speed(player_count)
	if elapsed < grace:
		return lerpf(CAM_SPEED_GRACE, start, elapsed / grace)
	return lerpf(start, CAM_SPEED_END, clampf((elapsed - grace) / CAM_RAMP_SEC, 0.0, 1.0))


## Velocidad de crucero al terminar la gracia: 140 px/s con 4, 126 con 3 y 112 con 2.
static func start_speed(player_count: int) -> float:
	return CAM_SPEED_START * CAM_SPEED_START_FACTOR[clampi(player_count, 0, 4)]


## Período de gracia después del "¡YA!": 3 s con 4 jugadores, 4 s con 3, 5 s con 2.
static func grace_sec(player_count: int) -> float:
	return GRACE_SEC + maxi(4 - player_count, 0) * GRACE_EXTRA_PER_MISSING


## ¿Se está en la gracia del arranque? (cartel "¡Corré a la derecha!").
func in_grace() -> bool:
	return _countdown <= 0.0 and not _ending and _elapsed < grace_sec(players.size())


## Nueva velocidad: fricción, aceleración del joystick y tope. Si un empujón
## o una flecha te lanzó más rápido que MAX_SPEED, se conserva y se frena de a poco.
static func step_velocity(v: Vector2, axis: Vector2, delta: float) -> Vector2:
	var drifted := v * exp(-FRICTION * delta)
	var out := drifted + axis.limit_length(1.0) * ACCEL * delta
	return out.limit_length(maxf(MAX_SPEED, drifted.length()))


## Choque entre dos mascotas (círculos del mismo peso): las separa, rebotan
## y el que embiste le da un empujón extra al otro (RAM_BONUS × su velocidad
## hacia él). Devuelve {pa, va, pb, vb, hit, impact}.
static func resolve_push(pa: Vector2, va: Vector2, pb: Vector2, vb: Vector2,
		min_dist: float = BODY_RADIUS * 2.0) -> Dictionary:
	var out := {"pa": pa, "va": va, "pb": pb, "vb": vb, "hit": false, "impact": 0.0}
	var d := pb - pa
	var dist := d.length()
	if dist >= min_dist:
		return out
	var n := d / dist if dist > 0.001 else Vector2.RIGHT
	var overlap := (min_dist - dist) / 2.0
	out.pa = pa - n * overlap
	out.pb = pb + n * overlap
	out.hit = true
	var a_in := va.dot(n)
	var b_in := -vb.dot(n)
	var closing := a_in + b_in
	if closing <= 0.0:
		return out
	out.va = va - n * (closing + RAM_BONUS * maxf(b_in, 0.0))
	out.vb = vb + n * (closing + RAM_BONUS * maxf(a_in, 0.0))
	out.impact = closing
	return out


## Saca una huella circular de un bloque (rectángulo sólido) y le quita la
## velocidad que iba contra él. Devuelve [pos, vel, tocó].
static func push_out_of_rect(pos: Vector2, vel: Vector2, r: Rect2, radius: float = BODY_RADIUS) -> Array:
	var closest := Vector2(clampf(pos.x, r.position.x, r.end.x), clampf(pos.y, r.position.y, r.end.y))
	var d := pos - closest
	var dist := d.length()
	if dist >= radius:
		return [pos, vel, false]
	var n: Vector2
	var out_pos: Vector2
	if dist > 0.001:
		n = d / dist
		out_pos = closest + n * radius
	else:
		# El centro quedó adentro: sale por el lado más cercano.
		var gaps := [pos.x - r.position.x, r.end.x - pos.x, pos.y - r.position.y, r.end.y - pos.y]
		var k := 0
		for i in 4:
			if gaps[i] < gaps[k]:
				k = i
		n = [Vector2.LEFT, Vector2.RIGHT, Vector2.UP, Vector2.DOWN][k]
		out_pos = pos + n * (float(gaps[k]) + radius)
	var into := vel.dot(n)
	if into < 0.0:
		vel -= n * into
	return [out_pos, vel, true]


## Se queda atrás si el centro de los pies pasa el borde izquierdo de la cámara.
static func is_left_behind(x: float, cam: float) -> bool:
	return x < cam


static func meters(x: float) -> int:
	return maxi(0, floori((x - START_LINE) / PX_PER_M))


static func saw_center(o: Dictionary, t: float) -> Vector2:
	return (o.c as Vector2) + (o.amp as Vector2) * sin(t * float(o.speed) + float(o.phase))


static func spinner_angle(o: Dictionary, t: float) -> float:
	return float(o.phase) + float(o.speed) * t


## ¿La huella en `pos` toca este obstáculo mortal en el segundo `t`?
static func hazard_hits(o: Dictionary, pos: Vector2, t: float) -> bool:
	match o.kind:
		"saw":
			return pos.distance_to(saw_center(o, t)) < float(o.r) + BODY_RADIUS * HAZARD_GRACE
		"spinner":
			var dir := Vector2.from_angle(spinner_angle(o, t)) * float(o.len)
			var c: Vector2 = o.c
			var q := Geometry2D.get_closest_point_to_segment(pos, c - dir, c + dir)
			return pos.distance_to(q) < ARM_W / 2.0 + BODY_RADIUS * HAZARD_GRACE
		"pit":
			# Se cae cuando el centro de los pies está sobre el pozo.
			return (o.rect as Rect2).grow(-BODY_RADIUS * 0.4).has_point(pos)
	return false


## Tramo `i` del recorrido con la semilla `seed`, en coordenadas del mundo.
## Pura: la misma semilla da siempre el mismo recorrido. El tramo 0 es la salida.
static func build_segment(seed: int, i: int) -> Array:
	var out: Array = []
	if i <= 0:
		return out
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([seed, i, "forma"])
	var flip := rng.randi() % 2 == 1
	var x0 := i * SEG_W
	for e: Array in TEMPLATES[template_for(seed, i)]:
		match str(e[0]):
			"block", "pit", "boost":
				var r: Rect2 = e[1]
				var placed := Rect2(r.position.x + x0, WORLD_H - r.end.y if flip else r.position.y, r.size.x, r.size.y)
				var o := {"kind": e[0], "rect": placed}
				if e[0] == "block":
					o["col"] = rng.randi() % UiTheme.BRICKS.size()
				out.append(o)
			"saw":
				var c: Vector2 = e[1]
				var amp: Vector2 = e[3]
				out.append({"kind": "saw", "c": Vector2(c.x + x0, WORLD_H - c.y if flip else c.y), "r": e[2],
					"amp": Vector2(amp.x, -amp.y if flip else amp.y), "speed": e[4], "phase": rng.randf() * TAU})
			"spinner":
				var c: Vector2 = e[1]
				out.append({"kind": "spinner", "c": Vector2(c.x + x0, WORLD_H - c.y if flip else c.y), "len": e[2],
					"speed": -float(e[3]) if flip else float(e[3]), "phase": rng.randf() * TAU})
	return out


## Qué tramo prediseñado va en el lugar `i`: sorteado entre los de su
## dificultad, sin repetir el sorteado para el lugar anterior.
static func template_for(seed: int, i: int) -> String:
	var pool := pool_for(i)
	var k := _raw_pick(seed, i, pool.size())
	if i > 1 and pool[k] == pool_for(i - 1)[_raw_pick(seed, i - 1, pool_for(i - 1).size())]:
		k = (k + 1) % pool.size()
	return pool[k]


## Dificultad por tramo: al principio fáciles, después se suman los medianos
## y desde el tramo 7 (≈ 25 s de juego) medianos y difíciles.
static func pool_for(i: int) -> Array[String]:
	var out: Array[String] = []
	if i <= 2:
		out.append_array(EASY)
	elif i <= 6:
		out.append_array(EASY)
		out.append_array(MEDIUM)
	else:
		out.append_array(MEDIUM)
		out.append_array(HARD)
	return out


static func _raw_pick(seed: int, i: int, n: int) -> int:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([seed, i, "tramo"])
	return rng.randi() % n


# --- Lógica del juego ---------------------------------------------------------------

func _ensure_course() -> void:
	if _course_seed < 0:
		_course_seed = _rng.randi() & 0x7FFFFFFF


func _segment(i: int) -> Array:
	if i < 0:
		return []
	if not _segments.has(i):
		_ensure_course()
		_segments[i] = build_segment(_course_seed, i)
	return _segments[i]


## Obstáculos de los tramos alrededor de x (el anterior, el suyo y el siguiente).
func _objects_near(x: float) -> Array:
	var i := floori(x / SEG_W)
	return _segment(i - 1) + _segment(i) + _segment(i + 1)


func _alive_ids() -> Array[int]:
	var out: Array[int] = []
	for p in players:
		if not _out.has(p.id):
			out.append(p.id)
	return out


func _move_players(delta: float) -> void:
	for pid in _alive_ids():
		var v := step_velocity(_vel[pid], _axis[pid], delta)
		var boosting := false
		for o: Dictionary in _objects_near((_pos[pid] as Vector2).x):
			if o.kind == "boost" and (o.rect as Rect2).has_point(_pos[pid]):
				boosting = true
		if boosting:
			v.x = maxf(v.x, BOOST_SPEED)
			if not _on_boost.get(pid, false):
				play_sfx("whoosh")
		_on_boost[pid] = boosting
		_vel[pid] = v
		advance_walk(pid, minf(v.length() / MAX_SPEED, 1.0), delta, 3.2)
		_pos[pid] += v * delta


func _collide_players() -> void:
	var alive := _alive_ids()
	for i in alive.size():
		for j in range(i + 1, alive.size()):
			var a: int = alive[i]
			var b: int = alive[j]
			var r := resolve_push(_pos[a], _vel[a], _pos[b], _vel[b])
			if not r.hit:
				continue
			_pos[a] = r.pa
			_vel[a] = r.va
			_pos[b] = r.pb
			_vel[b] = r.vb
			var pair := Vector2i(a, b)
			if float(r.impact) >= BUMP_MIN_SPEED and _elapsed - float(_pair_fx.get(pair, -INF)) >= BUMP_COOLDOWN:
				_pair_fx[pair] = _elapsed
				_effects.append({"pos": ((r.pa as Vector2) + (r.pb as Vector2)) / 2.0, "t": 0.0,
					"power": clampf(float(r.impact) / (MAX_SPEED * 1.5), 0.3, 1.0)})
				play_sfx("tap", 0.8)


## Bloques sólidos, techo, piso y borde derecho de la cámara.
func _solve_world() -> void:
	for pid in _alive_ids():
		var p: Vector2 = _pos[pid]
		var v: Vector2 = _vel[pid]
		for _pass in 2:  # Dos pasadas: salir de un bloque puede meterte en el de al lado.
			for o: Dictionary in _objects_near(p.x):
				if o.kind == "block":
					var res := push_out_of_rect(p, v, o.rect)
					p = res[0]
					v = res[1]
		if p.y < TOP_LIMIT:
			p.y = TOP_LIMIT
			v.y = maxf(v.y, 0.0)
		elif p.y > WORLD_H - BOTTOM_LIMIT:
			p.y = WORLD_H - BOTTOM_LIMIT
			v.y = minf(v.y, 0.0)
		var right := _cam + VIEW.size.x - RIGHT_LIMIT
		if p.x > right:
			p.x = right
			v.x = minf(v.x, _cam_speed)
		_pos[pid] = p
		_vel[pid] = v


func _check_outs() -> void:
	for pid in _alive_ids():
		var p: Vector2 = _pos[pid]
		if is_left_behind(p.x, _cam):
			_eliminate(pid, "camera", Vector2.LEFT)
			continue
		for o: Dictionary in _objects_near(p.x):
			if o.kind != "block" and o.kind != "boost" and hazard_hits(o, p, _elapsed):
				var from: Vector2 = saw_center(o, _elapsed) if o.kind == "saw" else (o.c if o.has("c") else p)
				_eliminate(pid, "pit" if o.kind == "pit" else "hit", (p - from).normalized())
				break


## Elimina a un jugador y arranca su animación: sale volando (cámara,
## sierra, molinete) o se cae dando vueltas (pozo). Después va a la tribuna.
func _eliminate(pid: int, kind: String, away: Vector2) -> void:
	var p: Vector2 = _pos[pid]
	var screen := _screen(p)
	var side := 1.0 if away.x >= 0.0 else -1.0
	var o := {"kind": kind, "t": 0.0, "pos": screen, "vel": Vector2.ZERO, "spin": 0.0, "grow": 1.0, "meters": meters(p.x)}
	match kind:
		"camera":
			o.vel = Vector2(-260.0, -820.0)
			o.spin = -9.0
			o.grow = 1.2
		"hit":
			o.vel = Vector2(side * 380.0, -980.0)
			o.spin = 10.0 * side
			o.grow = 1.6
		"pit":
			o.pos = p  # Se queda en el pozo: se mueve con el mundo.
	_out[pid] = o
	_vel[pid] = Vector2.ZERO
	_axis[pid] = Vector2.ZERO
	var text: String = {"camera": "¡Te dejó!", "hit": "¡Auch!", "pit": "¡Al pozo!"}[kind]
	var at := screen + Vector2(0, -120.0)
	at.x = clampf(at.x, VIEW.position.x + 150.0, VIEW.end.x - 150.0)
	at.y = maxf(at.y, VIEW.position.y + 70.0)
	_popups.append({"text": text, "pos": at, "t": 0.0})
	_effects.append({"pos": p + Vector2(0, -30.0), "t": 0.0, "power": 1.0})
	play_sfx("hit")
	notify_player(pid, "hit")


func _update_outs(delta: float) -> void:
	for pid: int in _out:
		var o: Dictionary = _out[pid]
		o.t += delta
		if o.kind != "pit" and o.t <= FLY_SEC:
			o.vel += Vector2(0, FLY_GRAVITY * delta)
			o.pos += (o.vel as Vector2) * delta


func _anim_sec(o: Dictionary) -> float:
	return FALL_SEC if o.kind == "pit" else FLY_SEC


func _is_seated(pid: int) -> bool:
	return _out.has(pid) and float(_out[pid].t) >= _anim_sec(_out[pid])


func _update_effects(delta: float) -> void:
	for e in _effects:
		e.t += delta
	_effects = _effects.filter(func(e: Dictionary) -> bool: return e.t < BUMP_FX_SEC)
	for p in _popups:
		p.t += delta
	_popups = _popups.filter(func(p: Dictionary) -> bool: return p.t < POPUP_SEC)


func _check_speedup() -> void:
	if _next_speedup < SPEEDUP_AT.size() and _elapsed >= SPEEDUP_AT[_next_speedup]:
		_next_speedup += 1
		_announce = "¡Más rápido!"
		_announce_t = ANNOUNCE_SEC
		play_sfx("whoosh", 1.3)


func _check_end() -> void:
	var alive := _alive_ids()
	if alive.is_empty() or (players.size() >= 2 and alive.size() <= 1) or _elapsed >= DURATION_SEC:
		_start_end(alive)


## Decide el resultado ya, pero lo emite después de END_DELAY_SEC para que se
## vea la última eliminación. Ganan los que siguen en pie; el torneo los
## ordena por metros (y a los eliminados también).
func _start_end(alive: Array[int]) -> void:
	var scores := _live_scores()
	if alive.is_empty():
		_result = result_from_scores(scores, "Más metros gana")
	else:
		_result = {"winners": alive, "scores": scores,
			"summary": "Último en pie gana" if alive.size() == 1 else "Ganan los que siguen en pie"}
	for pid in alive:
		_vel[pid] = Vector2.ZERO
		_axis[pid] = Vector2.ZERO
	if _elapsed >= DURATION_SEC:
		_announce = "¡Tiempo!"
	else:
		_announce = "¡Último en pie!" if alive.size() == 1 else "¡Afuera todos!"
	_announce_t = END_DELAY_SEC + 1.0
	_ending = true
	_end_timer = END_DELAY_SEC


## Metros de cada uno: los eliminados quedan fijos, los demás siguen sumando.
func _live_scores() -> Dictionary:
	var out := {}
	for p in players:
		out[p.id] = int(_out[p.id].meters) if _out.has(p.id) else meters((_pos[p.id] as Vector2).x)
	return out


# --- Vista ----------------------------------------------------------------------------

## x de la cámara redondeada al píxel (todo lo que se dibuja usa la misma).
func _view_x() -> float:
	return roundf(_cam)


func _screen(world: Vector2) -> Vector2:
	return VIEW.position + Vector2(world.x - _view_x(), world.y)


## Crea los tramos que entran en la cámara, borra los que ya pasaron y los
## corre: cada tramo se dibujó una sola vez y acá solo cambia su position.x.
func _sync_view() -> void:
	if _world == null:
		return
	_ensure_course()
	var vx := _view_x()
	var first := floori(vx / SEG_W)
	var last := floori((vx + VIEW.size.x) / SEG_W)
	for i: int in _seg_nodes.keys():
		if i < first or i > last:
			(_seg_nodes[i] as Node).queue_free()
			_seg_nodes.erase(i)
	for i in range(first, last + 1):
		if not _seg_nodes.has(i):
			var n := Node2D.new()
			n.draw.connect(_paint_segment.bind(n, i))
			_seg_root.add_child(n)
			_seg_nodes[i] = n
		(_seg_nodes[i] as Node2D).position.x = i * SEG_W - vx
	for i: int in _segments.keys():
		if i < first - 1:
			_segments.erase(i)
	_dyn.position.x = -vx
	_dyn.queue_redraw()


## ¿Está en peligro? (cerca del borde de la cámara o de algo mortal): cara de susto.
func _in_danger(pid: int) -> bool:
	var p: Vector2 = _pos[pid]
	if p.x - _cam < WARN_DIST * 0.6:
		return true
	for o: Dictionary in _objects_near(p.x):
		match o.kind:
			"saw":
				if p.distance_to(saw_center(o, _elapsed)) < float(o.r) + 110.0:
					return true
			"spinner":
				if p.distance_to(o.c) < float(o.len) + 60.0:
					return true
			"pit":
				if (o.rect as Rect2).grow(45.0).has_point(p):
					return true
	return false


# --- Dibujo ------------------------------------------------------------------------

func _draw() -> void:
	_ensure_course()
	draw_sky()
	draw_static(_draw_static_art)  # Marco de la cámara y tribuna: fijos.
	var b := GameArt.TriBatch.new()
	_add_view_overlay(b)
	b.flush(self)
	_draw_rec()
	# Mascotas en pie: de arriba hacia abajo (la de más abajo queda adelante).
	var order := players.filter(func(p: Dictionary) -> bool: return not _out.has(p.id))
	order.sort_custom(func(a: Dictionary, c: Dictionary) -> bool: return (_pos[a.id] as Vector2).y < (_pos[c.id] as Vector2).y)
	for p in order:
		_draw_player(p)
	var tags: Array = order.map(func(p: Dictionary) -> Array: return [p, _screen(_pos[p.id]), MASCOT_SCALE, NAME_OFFSET])
	draw_player_tags(tags)
	draw_start_markers(tags)
	for p in players:
		if _out.has(p.id) and not _is_seated(p.id):
			_draw_out(p)
	_draw_effects()
	_draw_tribune()
	for pop in _popups:
		var k: float = pop.t / POPUP_SEC
		UiTheme.draw_text(self, pop.text, (pop.pos as Vector2) - Vector2(0, 50.0 * k), 44,
			Color(UiTheme.GOLD, 1.0 - k * k), 10, Color(UiTheme.INK, 1.0 - k * k))
	draw_hud(_live_scores(), clock_text(DURATION_SEC - _elapsed), "clock")
	var center := VIEW.get_center()
	if _countdown > 0.0:
		draw_text_centered("%d" % ceili(_countdown), center, 240, UiTheme.PAPER, 22)
	elif _countdown > -GO_SEC:
		draw_text_centered("¡YA!", center, 240, UiTheme.ACCENT, 22)
	elif _announce_t > 0.0:
		var pop_k := clampf((ANNOUNCE_SEC - _announce_t) * 6.0, 0.0, 1.0) if not _ending else 1.0
		LowMemory.draw_text_sized(self, _announce, Vector2(center.x, VIEW.position.y + 110.0), int(lerpf(40.0, 64.0, pop_k)),
			64, UiTheme.ACCENT, 14)
	elif in_grace():
		_draw_go_right_hint(Vector2(center.x, VIEW.end.y - 64.0))  # Abajo: las mascotas salen arriba y en el medio.


## Durante la gracia del arranque: "¡Corré a la derecha!" con dos flechas que
## avanzan (quietas con "Reducir movimiento"). Es lo primero que hay que
## entender en este juego; la cámara mientras tanto va despacito.
func _draw_go_right_hint(at: Vector2) -> void:
	var size := 56
	var w := UiTheme.FONT_BOLD.get_string_size(GO_RIGHT_TEXT, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	var slide := 0.0 if UiTheme.reduce_motion else fmod(_anim * 1.6, 1.0) * 26.0
	for side in [-1.0, 1.0]:
		var c := at + Vector2(side * (w / 2.0 + 70.0) + slide, 0)
		UiTheme.draw_arrow(self, c, 58.0, Vector2.RIGHT, UiTheme.INK)
		UiTheme.draw_arrow(self, c, 46.0, Vector2.RIGHT, UiTheme.ACCENT)
	draw_text_centered(GO_RIGHT_TEXT, at, size, UiTheme.ACCENT, 14)


func _draw_player(p: Dictionary) -> void:
	var mood := PlayerAvatar.Mood.NORMAL
	if _ending:
		mood = PlayerAvatar.Mood.HAPPY
	elif _countdown <= 0.0 and _in_danger(p.id):
		mood = PlayerAvatar.Mood.SURPRISED
	var anim := mascot_anim(p.id, (_vel[p.id] as Vector2) / MAX_SPEED)
	anim["wave"] = mood == PlayerAvatar.Mood.HAPPY
	PlayerAvatar.draw_mascot(self, _screen(_pos[p.id]), MASCOT_SCALE, p.color, PlayerAvatar.style_of(p), mood,
		0.0, 0.0, false, anim)


## Eliminado en el aire (o cayendo al pozo): gira, con estrellitas de mareo.
func _draw_out(p: Dictionary) -> void:
	var o: Dictionary = _out[p.id]
	var k := clampf(float(o.t) / _anim_sec(o), 0.0, 1.0)
	var feet: Vector2
	var s: float
	var spin: float
	if o.kind == "pit":
		feet = _screen(o.pos)
		s = 1.0 - k * k
		spin = k * PI * 2.2
	else:
		feet = o.pos
		s = lerpf(1.0, float(o.grow), k)
		spin = float(o.spin) * float(o.t)
	if s <= 0.02:
		return
	# Gira alrededor del cuerpo (no de los pies).
	var body := 45.0 * MASCOT_SCALE
	var xform := Transform2D(spin, Vector2(s, s), 0.0, feet - Vector2(0, body))
	draw_set_transform_matrix(xform)
	PlayerAvatar.draw_mascot(self, Vector2(0, body), MASCOT_SCALE, p.color, PlayerAvatar.style_of(p), PlayerAvatar.Mood.SURPRISED,
		0.0, 0.0, false, {"xform": xform})
	draw_set_transform(Vector2.ZERO)
	var b := GameArt.TriBatch.new()
	_add_dizzy(b, feet - Vector2(0, 118.0 * MASCOT_SCALE * s), 30.0 * s)
	b.flush(self)


## Estrellitas que giran sobre la cabeza (mareo).
func _add_dizzy(b: GameArt.TriBatch, c: Vector2, r: float) -> void:
	for i in 3:
		var a := _anim * 5.0 + TAU * i / 3.0
		b.star(c + Vector2(cos(a) * r, sin(a) * r * 0.35), 9.0, UiTheme.GOLD, a, 3.0)


func _draw_effects() -> void:
	if _effects.is_empty():
		return
	var b := GameArt.TriBatch.new()
	for e in _effects:
		var k: float = e.t / BUMP_FX_SEC
		var c := _screen(e.pos)
		var power: float = e.power
		b.circle(c, lerpf(10.0, 44.0 * power + 12.0, k), Color(UiTheme.PAPER, 0.55 * (1.0 - k)), 20)
		for i in 5:
			var a := TAU * i / 5.0 + c.x * 0.01
			b.star(c + Vector2.from_angle(a) * lerpf(12.0, 40.0 + 40.0 * power, k),
				(8.0 + 7.0 * power) * (1.0 - k * 0.8), UiTheme.GOLD, k * 2.0, 3.0)
	b.flush(self)


## Los eliminados en su lugar de la tribuna (fijo por jugador: 1P, 2P…),
## tristes y mareados, con su nombre y los metros que hicieron.
func _draw_tribune() -> void:
	var seated: Array = []
	for p in players:
		if _is_seated(p.id):
			seated.append(p)
	if seated.is_empty():
		return
	var b := GameArt.TriBatch.new()
	# Tapa el lugar reservado (mascota vacía y "¡En carrera!", ver _draw_static_art).
	for p: Dictionary in seated:
		var seat := _seat_rect(p.slot)
		b.rect(Rect2(seat.position.x + 6.0, TRIB.position.y + 6.0, 124.0, TRIB.size.y - 32.0), UiTheme.PAPER_DIM)
		b.rect(Rect2(seat.position.x + 124.0, TRIB.position.y + 6.0, seat.size.x - 130.0, TRIB.size.y - 12.0), UiTheme.PAPER_DIM)
	b.flush(self)
	for p: Dictionary in seated:
		var o: Dictionary = _out[p.id]
		var since := float(o.t) - _anim_sec(o)
		var hop := sin(clampf(since / HOP_SEC, 0.0, 1.0) * PI) * 26.0
		var feet := _seat_feet(p.slot) - Vector2(0, hop)
		PlayerAvatar.draw_mascot(self, feet, TRIB_SCALE, p.color, PlayerAvatar.style_of(p), PlayerAvatar.Mood.SAD,
			0.0, 0.0, false, mascot_anim(p.id))
		_add_dizzy(b, feet - Vector2(0, 118.0 * TRIB_SCALE), 24.0)
	b.flush(self)
	for p: Dictionary in seated:
		var x := _seat_rect(p.slot).position.x + 128.0
		var w := _seat_rect(p.slot).size.x - 140.0
		UiTheme.draw_text_left(self, "%s %s" % [UiTheme.player_tag(p.slot), p.name], Vector2(x, TRIB.position.y + 32.0), 26,
			UiTheme.INK, w)
		UiTheme.draw_text_left(self, "%d m" % int(_out[p.id].meters), Vector2(x, TRIB.position.y + 66.0), 24,
			UiTheme.INK_SOFT, w, false)


func _seat_rect(slot: int) -> Rect2:
	var w := (TRIB.size.x - TRIB_TITLE_W) / 4.0
	return Rect2(TRIB.position.x + TRIB_TITLE_W + (slot % 4) * w, TRIB.position.y, w, TRIB.size.y)


func _seat_feet(slot: int) -> Vector2:
	var r := _seat_rect(slot)
	return Vector2(r.position.x + 68.0, r.end.y - 16.0)


## Encima del mundo y debajo de las mascotas: sombra del marco sobre el piso,
## aviso rojo del borde izquierdo (late más fuerte cuanto más cerca está
## alguien) y las esquinas de visor de la cámara.
func _add_view_overlay(b: GameArt.TriBatch) -> void:
	var v := VIEW
	var shade := Color(UiTheme.INK, 0.2)
	var clear := Color(UiTheme.INK, 0.0)
	b.quad_colors(v.position, Vector2(v.end.x, v.position.y), Vector2(v.end.x, v.position.y + 22.0),
		v.position + Vector2(0, 22.0), shade, shade, clear, clear)
	# Aviso del borde: el más cercano manda.
	var danger := 0.0
	if not _ending and _countdown <= 0.0:
		for pid in _alive_ids():
			danger = maxf(danger, clampf(1.0 - ((_pos[pid] as Vector2).x - _cam) / WARN_DIST, 0.0, 1.0))
	if danger > 0.0:
		var pulse := 0.55 + 0.45 * sin(_anim * lerpf(6.0, 16.0, danger))
		var red := Color(UiTheme.DANGER, (0.25 + 0.5 * danger) * pulse)
		var fade := Color(UiTheme.DANGER, 0.0)
		var w := lerpf(90.0, 220.0, danger)
		b.quad_colors(v.position, v.position + Vector2(w, 0), Vector2(v.position.x + w, v.end.y),
			Vector2(v.position.x, v.end.y), red, fade, fade, red)
		b.rect(Rect2(v.position, Vector2(10.0, v.size.y)), Color(UiTheme.DANGER, 0.5 + 0.5 * pulse))
	# Esquinas de visor (tinta y papel).
	var arm := 56.0
	var th := 8.0
	var inset := 20.0
	for k in 4:
		var sx := 1.0 if k % 2 == 0 else -1.0
		var sy := 1.0 if k < 2 else -1.0
		var corner := Vector2(v.position.x + inset if sx > 0.0 else v.end.x - inset,
			v.position.y + inset if sy > 0.0 else v.end.y - inset)
		for pass_i in 2:
			var g := 3.0 if pass_i == 0 else 0.0
			var col := UiTheme.INK if pass_i == 0 else UiTheme.PAPER
			b.rect(_span(corner, corner + Vector2(sx * arm, sy * th)).grow(g), col)
			b.rect(_span(corner, corner + Vector2(sx * th, sy * arm)).grow(g), col)


static func _span(a: Vector2, c: Vector2) -> Rect2:
	return Rect2(Vector2(minf(a.x, c.x), minf(a.y, c.y)), (c - a).abs())


## "● REC" arriba a la derecha de la cámara (el punto titila).
func _draw_rec() -> void:
	var at := Vector2(VIEW.end.x - 150.0, VIEW.position.y + 50.0)
	var on := fmod(_anim, 1.0) < 0.6 or _countdown > 0.0
	draw_circle(at, 15.0, UiTheme.INK)
	draw_circle(at, 11.0, UiTheme.DANGER if on else UiTheme.INK_SOFT)
	UiTheme.draw_text(self, "REC", at + Vector2(56.0, 0), 30, UiTheme.PAPER, 8)


## Lo fijo: escenario alrededor, marco de la cámara (con el borde izquierdo
## a rayas rojas: el que "te deja") y la tribuna con un banco por jugador.
func _draw_static_art(ci: CanvasItem) -> void:
	var b := GameArt.TriBatch.new()
	_add_frame(b, ci)
	_add_tribune_panel(b)
	b.flush(ci)
	UiTheme.draw_text(ci, "Tribuna", Vector2(TRIB.position.x + TRIB_TITLE_W / 2.0, TRIB.get_center().y), 32, UiTheme.INK)
	# Lugar reservado de cada uno: mascota "vacía" y su nombre apagado (al
	# eliminarlo, encima se dibujan la mascota y el nombre de verdad).
	for p in players:
		var feet := _seat_feet(p.slot)
		PlayerAvatar.draw_mascot(ci, feet, TRIB_SCALE, p.color, PlayerAvatar.style_of(p), PlayerAvatar.Mood.NORMAL,
			0.0, 0.0, true)
		var seat := _seat_rect(p.slot)
		UiTheme.draw_text_left(ci, "%s %s" % [UiTheme.player_tag(p.slot), p.name], Vector2(seat.position.x + 128.0,
			TRIB.position.y + 32.0), 26, UiTheme.MUTED, seat.size.x - 140.0)
		UiTheme.draw_text_left(ci, "¡En carrera!", Vector2(seat.position.x + 128.0, TRIB.position.y + 66.0), 24,
			UiTheme.MUTED, seat.size.x - 140.0, false)


## Con piezas 3D (Props3D) los bloques y las esquinas van como sprites del
## atlas: el lote se dibuja en `ci` antes de cada tanda de sprites.
func _add_frame(b: GameArt.TriBatch, ci: CanvasItem) -> void:
	var pieces: Array = []
	var f := UiTheme.BOARD_FRAME
	var depth := UiTheme.BOARD_DEPTH
	var v := VIEW
	var outer := v.grow(f)
	var body := outer.grow_side(SIDE_BOTTOM, depth)
	GameArt.add_soft_shadow(b, body, 24.0)
	var edge := body.grow(5.0)
	b.feather_round_rect(edge, 24.0, UiTheme.INK)
	b.ring_round_rect(edge, body, 19.0, UiTheme.INK)
	b.rect(Rect2(outer.position, Vector2(outer.size.x, f)), UiTheme.INK)
	b.rect(Rect2(outer.position.x, v.end.y, outer.size.x, f + depth), UiTheme.INK)
	b.rect(Rect2(outer.position.x, v.position.y, f, v.size.y), UiTheme.INK)
	b.rect(Rect2(v.end.x, v.position.y, f, v.size.y), UiTheme.INK)
	# Bloques arriba, abajo y a la derecha.
	var i := 0
	for side in [0, 1, 3]:
		var horizontal: bool = side < 2
		var length := outer.size.x if horizontal else v.size.y
		var n := maxi(1, roundi(length / UiTheme.BOARD_BRICK))
		var step_len := length / n
		for k in n:
			var col: Color = UiTheme.BRICKS[(i * 3 + side) % UiTheme.BRICKS.size()]
			i += 1
			var r: Rect2
			match side:
				0: r = Rect2(outer.position.x + k * step_len, outer.position.y, step_len, f)
				1: r = Rect2(outer.position.x + k * step_len, v.end.y, step_len, f)
				_: r = Rect2(v.end.x, v.position.y + k * step_len, f, step_len)
			if side == 1:  # Canto de abajo.
				b.chamfer_rect(Rect2(r.position.x + 1.0, r.end.y - 4.0, r.size.x - 2.0, depth + 2.0), 3.0, col.darkened(0.45))
			if Props3D.is_ready():
				pieces.append([r, Props3D.brick_name((i - 1) * 3 + side, side >= 2)])
			else:
				_add_bevel_brick(b, r, col)
	if not pieces.is_empty():
		b.flush(ci)
		GameArt.draw_pieces(ci, pieces)
		pieces.clear()
	# Borde izquierdo: franja de peligro a rayas (el borde que te deja atrás).
	var left := Rect2(outer.position.x, v.position.y, f, v.size.y).grow_individual(-2.0, 0.0, -2.0, 0.0)
	b.rect(left, UiTheme.DANGER.darkened(0.2))
	b.rect(left.grow_individual(-4.0, 0.0, -4.0, 0.0), UiTheme.DANGER)
	var stripe := 44.0
	var y := left.position.y + 6.0
	while y + stripe * 0.5 + (left.size.x - 8.0) <= left.end.y - 6.0:
		var x0 := left.position.x + 4.0
		var x1 := left.end.x - 4.0
		var h := x1 - x0
		b.quad(Vector2(x0, y + h), Vector2(x1, y), Vector2(x1, y + stripe * 0.5), Vector2(x0, y + h + stripe * 0.5), UiTheme.PAPER)
		y += stripe
	b.rect(Rect2(left.position.x + 4.0, left.position.y, left.size.x - 8.0, 4.0), Color(1, 1, 1, 0.35))
	# Filete de tinta alrededor de la vista.
	b.rect(Rect2(v.position - Vector2(3, 3), Vector2(v.size.x + 6, 3)), UiTheme.INK)
	b.rect(Rect2(v.position.x - 3, v.end.y, v.size.x + 6, 3), UiTheme.INK)
	b.rect(Rect2(v.position.x - 3, v.position.y, 3, v.size.y), UiTheme.INK)
	b.rect(Rect2(v.end.x, v.position.y, 3, v.size.y), UiTheme.INK)
	# Esquinas: bloque más grande con una estrella.
	var cs := UiTheme.BOARD_CORNER
	var corners := [outer.position, Vector2(outer.end.x - f, outer.position.y),
		Vector2(outer.position.x, v.end.y), Vector2(v.end.x, v.end.y)]
	for k in 4:
		var c: Vector2 = corners[k] + Vector2(f, f) / 2.0
		var r := Rect2(c - Vector2(cs, cs) / 2.0, Vector2(cs, cs))
		var col: Color = UiTheme.BRICKS[0] if k != 3 else UiTheme.BRICKS[5]
		var corner_edge := r.grow(4.0).grow_side(SIDE_BOTTOM, depth if k >= 2 else 6.0)
		b.feather_round_rect(corner_edge, 14.0, UiTheme.INK)
		b.round_rect(corner_edge, 14.0, UiTheme.INK)
		if k >= 2:
			b.chamfer_rect(Rect2(r.position.x, r.end.y - 8.0, cs, depth + 8.0), 8.0, col.darkened(0.45))
		if Props3D.is_ready():
			pieces.append([r, GameArt.corner_piece(k)])
			continue
		_add_bevel_brick(b, r, col, 10.0)
		b.star(c + Vector2(0, -3), cs * 0.36, UiTheme.GOLD, 0.0, 4.0)
	if not pieces.is_empty():
		b.flush(ci)
		GameArt.draw_pieces(ci, pieces)


## Bloque del marco con bisel (como el tablero de los demás juegos).
static func _add_bevel_brick(b: GameArt.TriBatch, r: Rect2, col: Color, chamfer: float = 6.0) -> void:
	b.chamfer_rect(r.grow(-1.0), chamfer, col.darkened(0.38))
	var face := Rect2(r.position + Vector2(3.0, 2.5), r.size - Vector2(6.0, 10.0))
	b.chamfer_rect(Rect2(face.position.x, face.get_center().y, face.size.x, face.size.y / 2.0), chamfer - 1.0, col)
	b.chamfer_rect(Rect2(face.position, Vector2(face.size.x, face.size.y / 2.0 + 1.0)), chamfer - 1.0, col.lightened(0.14))
	b.chamfer_rect(Rect2(face.position + Vector2(5.0, 3.0), Vector2(face.size.x - 10.0, minf(6.0, face.size.y * 0.22))), 3.0, col.lightened(0.5))


func _add_tribune_panel(b: GameArt.TriBatch) -> void:
	var r := TRIB
	b.feather_round_rect(r.grow(4.0), UiTheme.RADIUS + 4.0, UiTheme.INK)
	b.round_rect(r.grow(4.0), UiTheme.RADIUS + 4.0, UiTheme.INK)
	b.round_rect(r, UiTheme.RADIUS, Color(UiTheme.PAPER_DIM, 0.96))
	b.round_rect(Rect2(r.position + Vector2(10, 10), Vector2(TRIB_TITLE_W - 20, r.size.y - 20)), 20.0, UiTheme.PAPER)
	for p in players:
		var feet := _seat_feet(p.slot)
		var bench := Rect2(feet.x - 58.0, feet.y - 10.0, 116.0, 22.0)
		var col: Color = UiTheme.BRICKS[(int(p.slot) * 3 + 1) % UiTheme.BRICKS.size()]
		b.capsule(bench.grow(3.0), UiTheme.INK)
		b.capsule(bench, col.darkened(0.2))
		b.capsule(Rect2(bench.position, bench.size - Vector2(0, 5.0)), col)


# --- Tramos (se dibujan una vez) -------------------------------------------------------

## Tramo `i` en su nodo (coordenadas locales: x 0..SEG_W). Tres lotes: piso,
## marca de metros (texto) y obstáculos.
func _paint_segment(ci: Node2D, i: int) -> void:
	var off := Vector2(-i * SEG_W, 0)
	var b := GameArt.TriBatch.new()
	_add_floor(b, i)
	var objs := _segment(i)
	for o: Dictionary in objs:
		match o.kind:
			"pit": _add_pit(b, o.rect, off)
			"boost": _add_boost_pad(b, o.rect, off)
			"saw": _add_saw_track(b, o, off)
			"spinner": _add_spinner_base(b, o, off)
	b.flush(ci)
	if i > 0:
		UiTheme.draw_text(ci, "%d m" % meters(i * SEG_W + START_LINE), Vector2(START_LINE, WORLD_H - 44.0), 40,
			Color(UiTheme.INK, 0.2))
	var blocks := objs.filter(func(o: Dictionary) -> bool: return o.kind == "block")
	blocks.sort_custom(func(a: Dictionary, c: Dictionary) -> bool: return (a.rect as Rect2).position.y < (c.rect as Rect2).position.y)
	for o: Dictionary in blocks:
		_add_wall(b, Rect2((o.rect as Rect2).position + off, (o.rect as Rect2).size), int(o.col))
	if i == 0:
		_add_start(b)
	b.flush(ci)


## Piso de baldosas con relieve (como el tablero) y una línea cada 20 m.
func _add_floor(b: GameArt.TriBatch, i: int) -> void:
	var g := UiTheme.TILE_GAP
	b.rect(Rect2(0, 0, SEG_W, WORLD_H), UiTheme.TILE_GROUT)
	var cols := roundi(SEG_W / CELL)
	var rows := ceili(WORLD_H / CELL)
	for row in rows:
		for col in cols:
			var r := Rect2(col * CELL, row * CELL, CELL, minf(CELL, WORLD_H - row * CELL)).grow(-g)
			var fill := UiTheme.FLOOR if (row + col + i * cols) % 2 == 0 else UiTheme.FIELD_TILE
			var lip := UiTheme.TILE_LIP
			b.rect(Rect2(r.position, Vector2(r.size.x, 2.0)), fill.lerp(Color.WHITE, UiTheme.TILE_SHINE.a))
			b.rect(Rect2(r.position + Vector2(0, 2.0), r.size - Vector2(0, lip + 2.0)), fill)
			b.rect(Rect2(r.position.x, r.end.y - lip, r.size.x, lip), fill.darkened(UiTheme.TILE_SHADE))
	if i > 0:
		var y := 0.0
		while y < WORLD_H:
			b.rect(Rect2(START_LINE - 3.0, y + 8.0, 6.0, 24.0), Color(UiTheme.INK, 0.12))
			y += 44.0


## Salida: franja a cuadros y flechas pintadas en el piso.
func _add_start(b: GameArt.TriBatch) -> void:
	var sq := 35.0
	var rows := ceili(WORLD_H / sq)
	for row in rows:
		for col in 2:
			var r := Rect2(START_LINE - sq + col * sq, row * sq, sq, minf(sq, WORLD_H - row * sq))
			b.rect(r, UiTheme.INK if (row + col) % 2 == 0 else UiTheme.PAPER)
	for k in 3:
		_add_chevron(b, Vector2(600.0 + k * 110.0, WORLD_H / 2.0), 70.0, 130.0, 30.0, Color(UiTheme.ACCENT_SCROLLER, 0.35))


## Pared de bloques de juguete (con botoncitos), partida en bloques de ~180 px.
func _add_wall(b: GameArt.TriBatch, r: Rect2, col_index: int) -> void:
	var nx := maxi(1, roundi(r.size.x / 180.0))
	var ny := maxi(1, roundi(r.size.y / 120.0))
	var cell := r.size / Vector2(nx, ny)
	b.rect(Rect2(r.position + Vector2(10.0, 14.0), r.size), UiTheme.SHADOW)  # Sombra en el piso.
	b.chamfer_rect(r.grow(4.0), 12.0, UiTheme.INK)
	for yy in ny:
		for xx in nx:
			var col: Color = UiTheme.BRICKS[(col_index + xx * 3 + yy * 5) % UiTheme.BRICKS.size()]
			_add_toy_block(b, Rect2(r.position + cell * Vector2(xx, yy), cell), col)


## Bloque de juguete visto desde arriba: cara de adelante oscura, tapa con
## brillo y botoncitos.
func _add_toy_block(b: GameArt.TriBatch, r: Rect2, col: Color) -> void:
	var top := Rect2(r.position, r.size - Vector2(0, BLOCK_DEPTH))
	b.chamfer_rect(r.grow(-1.0), 8.0, col.darkened(0.4))
	b.chamfer_rect(top.grow(-1.0), 8.0, col)
	b.chamfer_rect(Rect2(top.position + Vector2(8.0, 5.0), Vector2(top.size.x - 16.0, 7.0)), 3.0, col.lightened(0.4))
	var nx := maxi(1, floori((top.size.x - 12.0) / STUD_STEP))
	var ny := maxi(1, floori((top.size.y - 12.0) / STUD_STEP))
	var gap := Vector2((top.size.x) / nx, (top.size.y) / ny)
	for yy in ny:
		for xx in nx:
			var c := top.position + gap * Vector2(xx + 0.5, yy + 0.5) + Vector2(0, 3.0)
			b.circle(c + Vector2(0, 3.5), 12.0, col.darkened(0.3), 14)
			b.circle(c, 12.0, col.lightened(0.12), 14)
			b.circle(c + Vector2(-4.0, -4.0), 3.5, Color(1, 1, 1, 0.55), 8)


## Pozo: borde de precaución amarillo y negro, pared de adentro y fondo oscuro.
func _add_pit(b: GameArt.TriBatch, rect: Rect2, off: Vector2) -> void:
	var r := Rect2(rect.position + off, rect.size)
	var rim := 14.0
	b.chamfer_rect(r.grow(rim + 4.0), 16.0, UiTheme.INK)
	b.chamfer_rect(r.grow(rim), 14.0, UiTheme.ACCENT)
	# Rayas de precaución en los bordes de arriba y abajo.
	for band_y in [r.position.y - rim, r.end.y]:
		var x := r.position.x - rim + 6.0
		while x + rim + 16.0 <= r.end.x + rim - 6.0:
			b.quad(Vector2(x, band_y + rim), Vector2(x + rim, band_y), Vector2(x + rim + 16.0, band_y),
				Vector2(x + 16.0, band_y + rim), UiTheme.INK)
			x += 40.0
	b.chamfer_rect(r, 10.0, UiTheme.INK)
	var wall := Color(UiTheme.INK_SOFT, 1.0)
	b.chamfer_rect(Rect2(r.position + Vector2(4.0, 4.0), Vector2(r.size.x - 8.0, 30.0)), 6.0, wall)
	b.quad_colors(Vector2(r.position.x + 4.0, r.position.y + 34.0), Vector2(r.end.x - 4.0, r.position.y + 34.0),
		Vector2(r.end.x - 4.0, r.position.y + 90.0), Vector2(r.position.x + 4.0, r.position.y + 90.0),
		Color(wall, 0.8), Color(wall, 0.8), Color(wall, 0.0), Color(wall, 0.0))
	# Brillitos en el fondo: se ve hondo.
	for k in 3:
		var p := r.position + Vector2(r.size.x * (0.25 + 0.25 * k), r.size.y * (0.55 + 0.15 * sin(k * 2.3)))
		b.star(p, 7.0, Color(UiTheme.PAPER, 0.25), k * 0.6, 0.0)


func _add_boost_pad(b: GameArt.TriBatch, rect: Rect2, off: Vector2) -> void:
	var r := Rect2(rect.position + off, rect.size)
	var col := UiTheme.ACCENT_SCROLLER
	b.chamfer_rect(r.grow(4.0), 14.0, UiTheme.INK)
	b.chamfer_rect(r, 12.0, col.darkened(0.3))
	b.chamfer_rect(Rect2(r.position, r.size - Vector2(0, 8.0)), 12.0, col)
	b.chamfer_rect(Rect2(r.position + Vector2(10.0, 6.0), Vector2(r.size.x - 20.0, 7.0)), 3.0, col.lightened(0.45))


## Canaleta por donde va y viene la sierra.
func _add_saw_track(b: GameArt.TriBatch, o: Dictionary, off: Vector2) -> void:
	var amp: Vector2 = o.amp
	if amp.length() < 1.0:
		return
	var c: Vector2 = (o.c as Vector2) + off
	var a := c - amp
	var z := c + amp
	var w := 26.0
	var r := _span(a, z).grow(w / 2.0)
	b.capsule(r.grow(4.0), Color(UiTheme.INK, 0.5))
	b.capsule(r, Color(UiTheme.INK, 0.28))
	b.circle(a, 10.0, UiTheme.INK_SOFT, 16)
	b.circle(z, 10.0, UiTheme.INK_SOFT, 16)


## Base del molinete: círculo de peligro por donde barre el brazo.
func _add_spinner_base(b: GameArt.TriBatch, o: Dictionary, off: Vector2) -> void:
	var c: Vector2 = (o.c as Vector2) + off
	var reach := float(o.len) + ARM_W / 2.0
	b.circle(c, reach + 6.0, Color(UiTheme.DANGER, 0.14), 48)
	# Aro punteado (arquitos) marcando el alcance.
	for k in 24:
		var a0 := TAU * k / 24.0
		var a1 := a0 + TAU / 48.0
		b.quad(c + Vector2.from_angle(a0) * (reach - 3.0), c + Vector2.from_angle(a0) * (reach + 3.0),
			c + Vector2.from_angle(a1) * (reach + 3.0), c + Vector2.from_angle(a1) * (reach - 3.0), Color(UiTheme.DANGER, 0.55))
	b.circle(c, 40.0, UiTheme.INK, 24)
	b.circle(c, 34.0, UiTheme.INK_SOFT, 24)


# --- Obstáculos animados (un lote por frame) ------------------------------------------

func _draw_dyn() -> void:
	var b := GameArt.TriBatch.new()
	var t := _elapsed
	var objs: Array = []
	for i: int in _seg_nodes:
		objs.append_array(_segment(i))
	for o: Dictionary in objs:
		if o.kind == "boost":
			_add_chevrons(b, o.rect)
	for o: Dictionary in objs:
		match o.kind:
			"saw": _add_saw(b, saw_center(o, t), float(o.r), t * 9.0 * signf(float(o.speed)))
			"spinner": _add_spinner(b, o.c, float(o.len), spinner_angle(o, t))
	b.flush(_dyn)


## Tres flechas que se encienden de izquierda a derecha.
func _add_chevrons(b: GameArt.TriBatch, r: Rect2) -> void:
	var n := maxi(2, floori(r.size.x / 90.0))
	var h := minf(r.size.y * 0.62, 70.0)
	for k in n:
		var wave := fposmod(_anim * 2.2 - float(k) / n, 1.0)
		var a := 0.45 + 0.55 * (1.0 - wave)
		var c := Vector2(r.position.x + r.size.x * (k + 0.5) / n, r.get_center().y - 3.0)
		_add_chevron(b, c, h * 0.55, h, 16.0, Color(UiTheme.PAPER, a))


## ">" centrado en c: ancho w, alto h y grosor th.
static func _add_chevron(b: GameArt.TriBatch, c: Vector2, w: float, h: float, th: float, col: Color) -> void:
	var tip := c + Vector2(w / 2.0, 0)
	var top := c + Vector2(-w / 2.0, -h / 2.0)
	var bottom := c + Vector2(-w / 2.0, h / 2.0)
	b.quad(top, top + Vector2(th, 0), tip + Vector2(th, 0), tip, col)
	b.quad(tip, tip + Vector2(th, 0), bottom + Vector2(th, 0), bottom, col)


## Sierra: halo rojo, dientes de metal que giran, disco rojo con agujeros.
func _add_saw(b: GameArt.TriBatch, c: Vector2, r: float, spin: float) -> void:
	var clear := Color(UiTheme.DANGER, 0.0)
	b.radial(c, r * (1.75 + 0.1 * sin(_anim * 6.0)), Color(UiTheme.DANGER, 0.45), clear)
	b.ellipse(c + Vector2(0, r * 0.45), r * 1.02, r * 0.5, UiTheme.SHADOW)
	var gear := _gear_tris()
	b.shape(gear, Transform2D(spin, Vector2(r + 5.0, r + 5.0), 0.0, c), UiTheme.INK)
	b.shape(gear, Transform2D(spin, Vector2(r, r), 0.0, c), UiTheme.SILVER)
	b.circle(c, r * 0.74, UiTheme.INK, 24)
	b.circle(c, r * 0.68, UiTheme.DANGER, 24)
	b.circle(c + Vector2(-r * 0.12, -r * 0.14), r * 0.44, UiTheme.DANGER.lightened(0.18), 20)
	for k in 3:
		b.circle(c + Vector2.from_angle(spin + TAU * k / 3.0) * r * 0.42, r * 0.12, UiTheme.INK, 10)
	b.circle(c, r * 0.2, UiTheme.INK, 14)
	b.circle(c, r * 0.13, UiTheme.PAPER, 12)


## Molinete: brazo a rayas rojas y blancas que gira sobre un eje dorado.
func _add_spinner(b: GameArt.TriBatch, c: Vector2, half: float, angle: float) -> void:
	var size := Vector2(half * 2.0 + ARM_W, ARM_W)
	b.shape(GameArt.round_rect_tris(size + Vector2(8.0, 8.0), (ARM_W + 8.0) / 2.0),
		Transform2D(angle, c + Vector2(0, 16.0)), UiTheme.SHADOW)
	b.shape(GameArt.round_rect_tris(size + Vector2(8.0, 8.0), (ARM_W + 8.0) / 2.0), Transform2D(angle, c), UiTheme.INK)
	b.shape(GameArt.round_rect_tris(size, ARM_W / 2.0), Transform2D(angle, c), UiTheme.DANGER)
	var dir := Vector2.from_angle(angle)
	var nrm := dir.orthogonal() * (ARM_W / 2.0 - 3.0)
	var stripes := 8
	for k in stripes:
		if k % 2 == 1:
			continue
		var s0 := -half + 2.0 * half * k / stripes
		var s1 := -half + 2.0 * half * (k + 1) / stripes
		b.quad(c + dir * s0 + nrm, c + dir * s1 + nrm, c + dir * s1 - nrm, c + dir * s0 - nrm, UiTheme.PAPER)
	b.shape(GameArt.round_rect_tris(Vector2(half * 2.0, 6.0), 3.0), Transform2D(angle, c - nrm * 0.5), Color(1, 1, 1, 0.35))
	for s in [-1.0, 1.0]:
		var end: Vector2 = c + dir * half * s
		b.circle(end, ARM_W / 2.0 + 2.0, UiTheme.INK, 16)
		b.circle(end, ARM_W / 2.0 - 2.0, UiTheme.GOLD, 16)
	b.circle(c, 26.0, UiTheme.INK, 20)
	b.circle(c, 21.0, UiTheme.GOLD, 20)
	b.star(c, 12.0, UiTheme.PAPER, angle, 0.0)


## Sierra unitaria (radio 1): 12 dientes inclinados, como triángulos.
static func _gear_tris() -> PackedVector2Array:
	if not _gear.is_empty():
		return _gear
	var teeth := 12
	var tris := PackedVector2Array()
	for i in teeth:
		var a0 := TAU * i / teeth
		var a1 := TAU * (i + 1) / teeth
		var base0 := Vector2.from_angle(a0) * 0.8
		var tip := Vector2.from_angle(lerpf(a0, a1, 0.7))
		var base1 := Vector2.from_angle(a1) * 0.8
		tris.append_array([Vector2.ZERO, base0, tip, Vector2.ZERO, tip, base1])
	_gear = tris
	return _gear
