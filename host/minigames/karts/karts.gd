extends MiniGame
## Karts de mascotas: carrera de 3 vueltas vista desde arriba, con la pista
## entera en pantalla. El kart acelera solo: el joystick dobla con el eje X;
## hacia abajo frena (dobla más cerrado) y hacia arriba da un turbo suave (a
## cambio, con el joystick en diagonal se dobla menos).
##
## En la pista: turbos en el piso (flechas), charcos resbalosos (el kart
## patina de costado un segundo) y choques suaves entre karts. Los bordes de
## bloques son paredes blanditas: frenan y enderezan el kart, no lo paran.
## Goma elástica sutil: el que va último recibe turbos 20 % más largos.
##
## Resultado: orden de llegada. Si se acaba el tiempo (90 s, o 15 s después
## de que llega el primero), los que no llegaron quedan por distancia
## recorrida. Puntaje ("vueltas"): las vueltas recorridas; los que llegaron
## tienen 3 y unas centésimas según el orden (el primero, más), así el modo
## competencia los ordena por llegada.
##
## Física determinista a pasos fijos de 1/60 s (`advance` acumula el delta
## real): la misma carrera con los mismos controles da siempre lo mismo, sin
## importar los fps. La pista (`Track`) y las reglas puras son testeables.

const LAPS := 3
const TIME_LIMIT_SEC := 90.0
const FINISH_GRACE_SEC := 15.0      ## Cuánto tienen los demás cuando llega el primero.
const CLOCK_WARN_SEC := 15.0        ## Desde acá el marcador muestra el reloj en vez de la vuelta.
const COUNTDOWN_SEC := 3.0
const GO_SEC := 0.8
const END_DELAY_SEC := 2.2          ## Se ve "¡Meta!"/"¡Tiempo!" antes de terminar.
const BANNER_SEC := 2.2
const FIXED_DT := 1.0 / 60.0

# --- Pista ----------------------------------------------------------------------
## Pasto dentro del marco de bloques (el marco va por fuera, como en los demás juegos).
const FIELD := Rect2(150, 150, 1620, 850)
const GRASS_STRIPE := 90.0          ## Ancho de las franjas del pasto (y celda de la vista 2.5D).
## Puntos de control del centro de la pista (sentido horario, se suavizan con
## Catmull-Rom). La largada queda en la recta de abajo, yendo a la derecha.
const TRACK_POINTS: Array[Vector2] = [
	Vector2(670, 862), Vector2(979, 862), Vector2(1288, 862), Vector2(1539, 821), Vector2(1626, 638),
	Vector2(1587, 416), Vector2(1433, 298), Vector2(1211, 296), Vector2(1066, 377), Vector2(950, 527),
	Vector2(805, 546), Vector2(680, 425), Vector2(545, 300), Vector2(405, 298), Vector2(294, 462), Vector2(306, 696),
	Vector2(439, 840),
]
const START_AT := Vector2(1000, 862)
const SAMPLE_STEP := 12.0           ## Distancia entre puntos de la pista (px).
const HALF_WIDTH := 84.0            ## Mitad del ancho del asfalto.
const CURB := 18.0                  ## Ancho del borde de bloques.
const CURB_SAMPLES := 4             ## Largo de cada bloque del borde (en puntos de pista).
const SEARCH_WINDOW := 8            ## Puntos a cada lado donde se busca el más cercano.
## Turbos: [fracción de la vuelta, desplazamiento lateral (+ derecha)].
const PADS: Array[Vector2] = [Vector2(0.155, -34.0), Vector2(0.47, 30.0), Vector2(0.74, -26.0)]
const PAD_SIZE := Vector2(92, 62)   ## Largo (a lo largo de la pista) × ancho.
## Charcos: [fracción de la vuelta, desplazamiento lateral, radio].
const PUDDLES: Array[Vector3] = [Vector3(0.30, 28.0, 40.0), Vector3(0.575, -30.0, 38.0), Vector3(0.87, 24.0, 40.0)]
## Grilla de largada: [metros detrás de la línea, desplazamiento lateral].
const GRID: Array[Vector2] = [Vector2(48, -38), Vector2(48, 38), Vector2(122, -38), Vector2(122, 38)]

# --- Kart -----------------------------------------------------------------------
const MAX_SPEED := 380.0            ## px/s en asfalto, sin turbo.
const ACCEL := 430.0                ## px/s² hasta la velocidad buscada.
const TURBO_ACCEL := 1100.0
const DECEL := 560.0
const TURN_RATE := 3.3              ## rad/s con el joystick a fondo y a velocidad.
const TURN_FULL_SPEED := 0.4        ## Desde esta fracción de MAX_SPEED dobla a pleno.
const STEER_RESPONSE := 11.0        ## Inercia del volante (1/s): con 60 ms de demora se siente bien.
const GRIP := 9.0                   ## Cuánto se come el derrape por segundo (1/s).
const SLIP_GRIP := 1.0              ## En un charco: casi sin agarre.
const SLIP_STEER := 0.5
const SLIP_SPEED := 0.85
const SLIP_SEC := 1.0
const BRAKE := 0.6                  ## Joystick abajo a fondo: 40 % de la velocidad.
const BOOST := 0.08                 ## Joystick arriba a fondo: +8 %.
const AXIS_DEADZONE := 0.3
const TURBO_FACTOR := 1.55
const TURBO_SEC := 1.1
const RUBBER_BAND := 1.2            ## El último recibe turbos 20 % más largos.
const KART_RADIUS := 27.0           ## Cuerpo para choques (entre karts y con el borde).
const BUMP_RESTITUTION := 0.45      ## Choques suaves: rebotan poco.
const BUMP_SLOW := 0.92             ## Y pierden un poco de velocidad.
const WALL_BOUNCE := 0.25
const WALL_SLOW := 0.6              ## Rozando el borde, velocidad buscada × 0,6.
const WALL_ALIGN := 3.0             ## El borde endereza el kart (1/s).
const FINISHED_SPEED := 0.6         ## Los que ya llegaron dan una vuelta tranquila.
const AUTOPILOT_LOOKAHEAD := 110.0

# --- Dibujo ---------------------------------------------------------------------
const MASCOT_SCALE := 0.56
## Poses extra que se hornean en la intro (MascotAtlas.prewarm_game): cara de
## susto al patinar en un charco, mirando hacia donde va el kart.
const MASCOT_PREWARM := [[MASCOT_SCALE, ["look_l@3", "look_r@3", "look_u@3", "look_d@3"]]]
const SEAT_OFFSET := 12.0           ## Los pies de la mascota, abajo del centro del kart.
const NAME_OFFSET := -1.0            ## Sin nombre abajo: en el pelotón se tapaban (el globito 1P–4P alcanza).
const KART_LEN := 82.0
const KART_WIDE := 50.0
const COUNT_SIZE := 260
const BANNER_SIZE := 76
const TAB_TEXT_SIZE := 28
const TAB_SIZE := Vector2(136, 44)
const MEDAL_R := 22.0
const SPARK_SEC := 0.35
const HIT_FX_MIN := 140.0           ## Choques más suaves no muestran estrellitas.
const HIT_FX_COOLDOWN := 0.3
const WRONG_WAY_SEC := 0.8         ## Tras este tiempo yendo para atrás, aparece "¡Al revés!".
const HINT_SIZE := 28

enum Phase { COUNTDOWN, RACING, ENDING }


## Un kart: estado físico y de carrera. Todo lo que cambia en un paso fijo.
class Kart:
	extends RefCounted
	var pid := 0
	var slot := 0
	var pos := Vector2.ZERO
	var vel := Vector2.ZERO
	var heading := 0.0
	var steer := 0.0                ## Volante real (sigue al joystick con inercia).
	var axis := Vector2.ZERO        ## Último joystick recibido.
	var turbo := 0.0                ## Segundos de turbo que quedan.
	var slip := 0.0                 ## Segundos patinando.
	var seg := 0                    ## Punto de la pista más cercano.
	var s := 0.0                    ## Posición a lo largo de la vuelta (0..largo).
	var lat := 0.0                  ## Distancia al centro de la pista (+ derecha).
	var dist := 0.0                 ## Recorrido total desde la línea (con vueltas).
	var finish_time := -1.0         ## Segundos de carrera al llegar (-1: no llegó).
	var on_pad := -1
	var in_puddle := -1
	var on_wall := false
	var wrong_way := 0.0            ## Segundos yendo para atrás (muestra "¡Al revés!").

	func finished() -> bool:
		return finish_time >= 0.0

	## Estado físico completo (para comparar en los tests de determinismo).
	func snapshot() -> Array:
		return [pos, vel, heading, steer, turbo, slip, seg, s, lat, dist, finish_time]


## Centro de la pista como polilínea cerrada, con puntos cada ~SAMPLE_STEP px
## y el punto 0 en la línea de largada. Sirve para dibujarla y para saber en
## qué parte de la vuelta está cada kart.
class Track:
	extends RefCounted
	var pts := PackedVector2Array()
	var nrm := PackedVector2Array()     ## Normal hacia la derecha del sentido de carrera.
	var cum := PackedFloat64Array()     ## Distancia desde la línea hasta cada punto.
	var length := 0.0

	func _init(control: Array[Vector2], step: float, start: Vector2) -> void:
		# Curva suave por los puntos de control (Catmull-Rom cerrada).
		var dense := PackedVector2Array()
		var n := control.size()
		for i in n:
			var p0 := control[(i - 1 + n) % n]
			var p1 := control[i]
			var p2 := control[(i + 1) % n]
			var p3 := control[(i + 2) % n]
			for k in 40:
				dense.append(p1.cubic_interpolate(p2, p0, p3, k / 40.0))
		# Puntos a distancias iguales.
		var total := 0.0
		for i in dense.size():
			total += dense[i].distance_to(dense[(i + 1) % dense.size()])
		var count := maxi(8, roundi(total / step))
		var each := total / count
		var out := PackedVector2Array([dense[0]])
		var want := each
		var walked := 0.0
		for i in dense.size():
			var a := dense[i]
			var b := dense[(i + 1) % dense.size()]
			var seg_len := a.distance_to(b)
			while walked + seg_len >= want and out.size() < count:
				out.append(a.lerp(b, (want - walked) / seg_len))
				want += each
			walked += seg_len
		# Empieza en la línea de largada.
		var first := 0
		for i in out.size():
			if out[i].distance_squared_to(start) < out[first].distance_squared_to(start):
				first = i
		for i in out.size():
			pts.append(out[(first + i) % out.size()])
		var m := pts.size()
		for i in m:
			var t := (pts[(i + 1) % m] - pts[(i - 1 + m) % m]).normalized()
			nrm.append(Vector2(-t.y, t.x))
			cum.append(length)
			length += pts[i].distance_to(pts[(i + 1) % m])

	func size() -> int:
		return pts.size()

	## Diferencia de posición en la vuelta, por el camino más corto (cruzar la
	## línea hacia adelante suma poco, no casi una vuelta para atrás).
	func wrap_delta(ds: float) -> float:
		if ds > length / 2.0:
			return ds - length
		if ds < -length / 2.0:
			return ds + length
		return ds

	## Tramo más cercano a `p`: [índice, s (posición en la vuelta), lateral
	## (+ derecha)]. Busca cerca de `hint` (un kart no se teletransporta);
	## hint < 0 busca en toda la pista.
	func locate(p: Vector2, hint: int, window: int = SEARCH_WINDOW) -> Array:
		var m := pts.size()
		var from := hint - window
		var to := hint + window
		if hint < 0:
			from = 0
			to = m - 1
		var best_d := INF
		var best := [0, 0.0, 0.0]
		for j in range(from, to + 1):
			var i := posmod(j, m)
			var a := pts[i]
			var b := pts[(i + 1) % m]
			var ab := b - a
			var t := clampf((p - a).dot(ab) / ab.length_squared(), 0.0, 1.0)
			var q := a + ab * t
			var d := p.distance_squared_to(q)
			if d < best_d:
				best_d = d
				var dir := ab.normalized()
				best = [i, fposmod(cum[i] + ab.length() * t, length), (p - q).dot(Vector2(-dir.y, dir.x))]
		return best

	## Punto del centro y tangente en la posición `s` de la vuelta.
	func frame_at(s: float) -> Array:
		s = fposmod(s, length)
		var m := pts.size()
		var i := clampi(int(s / length * m), 0, m - 1)
		while i > 0 and cum[i] > s:
			i -= 1
		while i < m - 1 and cum[i + 1] <= s:
			i += 1
		var a := pts[i]
		var b := pts[(i + 1) % m]
		var seg_len := a.distance_to(b)
		var t := clampf((s - cum[i]) / seg_len, 0.0, 1.0) if seg_len > 0.0 else 0.0
		return [a.lerp(b, t), (b - a).normalized()]

	func point_at(s: float, lateral: float = 0.0) -> Vector2:
		var f := frame_at(s)
		var dir: Vector2 = f[1]
		return (f[0] as Vector2) + Vector2(-dir.y, dir.x) * lateral

	## Radio de curvatura más chico (px), con puntos a `span` de distancia.
	func min_radius(span: int = 3) -> float:
		var m := pts.size()
		var best := INF
		for i in m:
			var a := pts[(i - span + m) % m]
			var b := pts[i]
			var c := pts[(i + span) % m]
			var cross := absf((b - a).cross(c - b))
			if cross > 0.0001:
				best = minf(best, a.distance_to(b) * b.distance_to(c) * a.distance_to(c) / (2.0 * cross))
		return best

	## Distancia de `p` al centro de la pista (búsqueda completa: solo para
	## armar el decorado una vez).
	func distance_to(p: Vector2) -> float:
		return absf(float(locate(p, -1)[2]))


static var _track: Track


## La pista es la misma para todas las partidas: se arma una vez por proceso.
static func track() -> Track:
	if _track == null:
		_track = Track.new(TRACK_POINTS, SAMPLE_STEP, START_AT)
	return _track


# --- Escenario 2.5D (ADR 0019) ------------------------------------------------------
#
# Con render, el pasto, la pista entera (asfalto, cordones de bloques con
# volumen, turbos, charcos, largada), los árboles y el marco son una escena
# 3D horneada una vez con cámara en perspectiva (receta "karts" de
# Board25DScene, con la geometría de la pista en `view.extras`); los karts,
# las mascotas, los efectos y las flechas que se prenden se dibujan en 2D
# proyectados encima. La física sigue en las coordenadas planas de FIELD.
# Sin render (--headless) o mientras se hornea, se dibuja plano como siempre.

static var _board_view: BoardView25D
var _v25 := false


## Cámara y proyección del escenario 2.5D: el campo encuadrado como el de
## Pintar el piso (BoardView25D.make_fit) y la pista para la receta.
static func board_view() -> BoardView25D:
	if _board_view == null:
		var v := BoardView25D.make_fit(FIELD, GRASS_STRIPE, Board25DScene.RECIPE_KARTS)
		v.extras = scene_extras()
		_board_view = v
	return _board_view


## Durante la intro: el escenario 2.5D se lee del disco o se hornea.
static func prewarm_art(host: Node, _players: Array = []) -> void:
	Board25DBaker.request(host, board_view())


## Geometría de la pista para la escena 3D (Board25DScene, receta "karts"),
## en coordenadas del plano: puntos y normales del centro, anchos, turbos
## [x, y, ángulo], charcos [x, y, radio, ángulo], grilla de largada, línea
## de largada y decorado. Entra en la firma de la caché: si cambia la
## pista, se vuelve a hornear.
static func scene_extras() -> Dictionary:
	var tr := track()
	var pads: Array[Vector3] = []
	for i in PADS.size():
		var xf := _pad_frame(i)
		pads.append(Vector3(xf.origin.x, xf.origin.y, xf.get_rotation()))
	var puddles: Array = []
	for i in PUDDLES.size():
		var c := _puddle_center(i)
		puddles.append([c.x, c.y, PUDDLES[i].z, (tr.frame_at(PUDDLES[i].x * tr.length)[1] as Vector2).angle()])
	var grid: Array[Vector3] = []
	for spot in GRID:
		var g := tr.point_at(-spot.x, spot.y)
		grid.append(Vector3(g.x, g.y, (tr.frame_at(-spot.x)[1] as Vector2).angle()))
	var f := tr.frame_at(0.0)
	return {
		"pts": tr.pts, "nrm": tr.nrm, "half_width": HALF_WIDTH, "curb": CURB, "curb_samples": CURB_SAMPLES,
		"pad_size": PAD_SIZE, "pads": pads, "puddles": puddles, "grid": grid, "grid_len": KART_LEN,
		"start": Vector3((f[0] as Vector2).x, (f[0] as Vector2).y, (f[1] as Vector2).angle()), "decor": decor_layout(),
	}


## Dónde se dibuja un punto del plano: proyectado sobre el escenario 2.5D, o
## igual si se dibuja plano.
func _screen(p: Vector2) -> Vector2:
	return board_view().project(p) if _v25 else p


## Escala de lo que está parado en `p` (mascota, medalla): más chico atrás
## en 2.5D (con tope, UiTheme.BOARD25D_SCALE_*); 1 en plano.
func _depth(p: Vector2) -> float:
	if not _v25:
		return 1.0
	return clampf(board_view().scale_at(p), UiTheme.BOARD25D_SCALE_MIN, UiTheme.BOARD25D_SCALE_MAX)


var _karts: Dictionary = {}         # player_id -> Kart
var _ids: Array[int] = []           # jugadores en orden de lugar (1P, 2P…): orden fijo = determinista
var _phase := Phase.COUNTDOWN
var _countdown := COUNTDOWN_SEC
var _elapsed := 0.0                 # segundos de carrera (desde el "¡YA!")
var _acc := 0.0                     # tiempo real acumulado que falta simular
var _ticks := 0                     # pasos fijos simulados
var _finish_order: Array[int] = []
var _first_finish := -1.0
var _last_lap_shown := false
var _banner := ""
var _banner_t := 0.0
var _end_text := ""
var _end_timer := 0.0
var _result: Dictionary = {}
var _effects: Array = []            # {pos, t, power}
var _pair_fx: Dictionary = {}       # Vector2i(a, b) -> segundos del último efecto
var _rng := RandomNumberGenerator.new()
var _kart_tpl: Dictionary = {}      # color -> [puntos, colores] del chasis
var _tabs: Node2D                   # pestañas de vuelta debajo del marcador
var _tabs_key: Array = []

## Posición de cada kart por jugador (la usan las herramientas de miniaturas).
var _pos: Dictionary:
	get:
		var out := {}
		for pid: int in _karts:
			out[pid] = (_karts[pid] as Kart).pos
		return out


static func get_info() -> Dictionary:
	return {
		"id": "karts",
		"title": "Karts de mascotas",
		"description": "Carrera de 3 vueltas: el kart acelera solo, vos doblás. Pisá los turbos y esquivá los charcos.",
		"min_players": 1,
		"max_players": 4,
		"layout": Protocol.LAYOUT_JOYSTICK,
		"layout_data": {},
		"accent": UiTheme.ACCENT_KARTS,
		"score_label": "vueltas",
	}


func setup(p_players: Array[Dictionary]) -> void:
	super.setup(p_players)
	_rng.randomize()
	for p in players:
		var k := Kart.new()
		k.pid = p.id
		k.slot = p.slot
		_karts[p.id] = k
		_ids.append(p.id)
	# Quién sale adelante rota al azar (los de atrás arrancan 74 px atrás).
	place_on_grid(_rng.randi() % maxi(_ids.size(), 1))


## Ubica a los karts en la grilla de largada, detrás de la línea. `shift`
## rota qué lugar le toca a cada uno.
func place_on_grid(shift: int) -> void:
	var tr := track()
	var n := _ids.size()
	for i in n:
		var k: Kart = _karts[_ids[i]]
		var spot: Vector2 = GRID[(i + shift) % n] if n > 1 else Vector2(GRID[0].x, 0.0)
		var f := tr.frame_at(-spot.x)
		k.pos = tr.point_at(-spot.x, spot.y)
		k.heading = (f[1] as Vector2).angle()
		k.vel = Vector2.ZERO
		var loc := tr.locate(k.pos, -1)
		k.seg = loc[0]
		k.s = loc[1]
		k.lat = loc[2]
		k.dist = -spot.x


func on_input(player_id: int, input: Dictionary) -> void:
	if not _karts.has(player_id) or _phase == Phase.ENDING:
		return  # Con el cartel final ya no se maneja (frenan solos).
	var axis: Variant = input.get("axis", Vector2.ZERO)
	var v: Vector2 = (axis as Vector2) if axis is Vector2 else Vector2.ZERO
	if not v.is_finite():
		v = Vector2.ZERO
	(_karts[player_id] as Kart).axis = v.limit_length(1.0)


func _physics_process(delta: float) -> void:
	if is_finished():
		return
	advance(delta)
	queue_redraw()


## Avanza el juego `delta` segundos reales en pasos fijos de FIXED_DT: a
## 30 fps se hacen dos pasos por frame y a 60 uno, con el mismo resultado.
func advance(delta: float) -> void:
	_acc += clampf(delta, 0.0, 0.25)  # Un tirón largo no simula segundos de golpe.
	while _acc >= FIXED_DT - 0.000001 and not is_finished():
		_acc -= FIXED_DT
		step_fixed()
	_acc = maxf(_acc, 0.0)


## Como en los demás juegos (ver tools/benchmark.gd, LATE_SCENES): avanzar a mano.
func step(delta: float) -> void:
	advance(delta)


## Un paso fijo de juego (1/60 s).
func step_fixed() -> void:
	var dt := FIXED_DT
	_ticks += 1
	_update_effects(dt)
	_banner_t = maxf(_banner_t - dt, 0.0)
	match _phase:
		Phase.COUNTDOWN:
			var before := _countdown
			_countdown -= dt
			tick_countdown(before, _countdown)
			if _countdown <= 0.0:
				_phase = Phase.RACING
		Phase.RACING:
			if _countdown > -GO_SEC:
				_countdown -= dt
			_elapsed += dt
			_simulate(dt, true)
			_check_end()
		Phase.ENDING:
			if _countdown > -GO_SEC:
				_countdown -= dt
			_simulate(dt, false)  # Siguen andando mientras se ve el cartel (sin contar vueltas).
			_end_timer -= dt
			if _end_timer <= 0.0:
				finish(_result)


# --- Física pura (testeable) ----------------------------------------------------

## Velocidad que busca el kart según el joystick y lo que está pisando.
static func target_speed(axis: Vector2, turbo: bool, slipping: bool, on_wall: bool) -> float:
	var v := MAX_SPEED
	if axis.y > AXIS_DEADZONE:
		v *= 1.0 - BRAKE * minf(axis.y, 1.0)
	elif axis.y < -AXIS_DEADZONE:
		v *= 1.0 + BOOST * minf(-axis.y, 1.0)
	if turbo:
		v *= TURBO_FACTOR
	if slipping:
		v *= SLIP_SPEED
	if on_wall:
		v *= WALL_SLOW
	return v


## Cuánto dura un turbo: 20 % más para el que va último (goma elástica).
static func turbo_duration(is_last: bool) -> float:
	return TURBO_SEC * (RUBBER_BAND if is_last else 1.0)


## Un paso de manejo (sin pista ni choques): volante con inercia, velocidad
## hacia la buscada, giro según la velocidad y derrape que el agarre se come.
static func drive(k: Kart, axis: Vector2, dt: float) -> void:
	var slipping := k.slip > 0.0
	k.steer = lerpf(k.steer, clampf(axis.x, -1.0, 1.0), 1.0 - exp(-STEER_RESPONSE * dt))
	var fwd := Vector2.from_angle(k.heading)
	var right := Vector2(-fwd.y, fwd.x)
	var f := k.vel.dot(fwd)
	var l := k.vel.dot(right)
	var target := target_speed(axis, k.turbo > 0.0, slipping, k.on_wall)
	var accel := TURBO_ACCEL if k.turbo > 0.0 else ACCEL
	f = move_toward(f, target, (accel if f < target else DECEL) * dt)
	l *= exp(-(SLIP_GRIP if slipping else GRIP) * dt)
	var turn := k.steer * TURN_RATE * clampf(f / (MAX_SPEED * TURN_FULL_SPEED), -1.0, 1.0)
	if slipping:
		turn *= SLIP_STEER
	k.vel = fwd * f + right * l
	k.heading = wrapf(k.heading + turn * dt, -PI, PI)
	k.pos += k.vel * dt
	k.turbo = maxf(k.turbo - dt, 0.0)
	k.slip = maxf(k.slip - dt, 0.0)


## Choque suave entre dos karts del mismo peso: se separan y rebotan poco
## (BUMP_RESTITUTION). Devuelve la velocidad de acercamiento (0 si no chocan).
static func bump(a: Kart, b: Kart) -> float:
	var d := b.pos - a.pos
	var dist := d.length()
	var min_dist := KART_RADIUS * 2.0
	if dist >= min_dist:
		return 0.0
	var n := d / dist if dist > 0.001 else Vector2.RIGHT
	var overlap := (min_dist - dist) / 2.0
	a.pos -= n * overlap
	b.pos += n * overlap
	var closing := (a.vel - b.vel).dot(n)
	if closing <= 0.0:
		return 0.0
	var j := closing * (1.0 + BUMP_RESTITUTION) / 2.0
	a.vel = (a.vel - n * j) * BUMP_SLOW
	b.vel = (b.vel + n * j) * BUMP_SLOW
	return closing


## Borde de la pista: si el kart se pasa, vuelve adentro, pierde la
## velocidad hacia afuera (rebota un poco) y se endereza de a poco.
## Devuelve la velocidad con la que pegó contra el borde (0 si no tocó).
static func keep_on_track(k: Kart, tr: Track, dt: float) -> float:
	var loc := tr.locate(k.pos, k.seg)
	var lat: float = loc[2]
	var limit := HALF_WIDTH - KART_RADIUS
	k.on_wall = absf(lat) > limit
	var impact := 0.0
	if k.on_wall:
		var side := signf(lat)
		var f := tr.frame_at(loc[1])
		var dir: Vector2 = f[1]
		var n := Vector2(-dir.y, dir.x) * side  # Hacia afuera.
		k.pos -= n * (absf(lat) - limit)
		var out := k.vel.dot(n)
		if out > 0.0:
			k.vel -= n * out * (1.0 + WALL_BOUNCE)
			impact = out
		var along := dir if Vector2.from_angle(k.heading).dot(dir) >= 0.0 else -dir
		# Más fuerte si apunta contra el borde: así nadie queda trabado.
		var into := maxf(Vector2.from_angle(k.heading).dot(n), 0.0)
		k.heading = lerp_angle(k.heading, along.angle(), minf(WALL_ALIGN * (1.0 + 3.0 * into) * dt, 1.0))
		loc = tr.locate(k.pos, loc[0])
	var ds := tr.wrap_delta(float(loc[1]) - k.s)
	k.seg = loc[0]
	k.s = loc[1]
	k.lat = loc[2]
	k.dist += ds
	return impact


## Vuelta en la que va (1..LAPS) según lo recorrido.
static func lap_of(dist: float, lap_len: float) -> int:
	return clampi(floori(dist / lap_len) + 1, 1, LAPS)


## Orden de carrera: primero los que llegaron (por tiempo de llegada) y
## después por distancia recorrida. A igualdad, el lugar (1P, 2P…).
static func race_order(karts: Array) -> Array[int]:
	var list := karts.duplicate()
	list.sort_custom(func(a: Kart, b: Kart) -> bool:
		if a.finished() != b.finished():
			return a.finished()
		if a.finished() and a.finish_time != b.finish_time:
			return a.finish_time < b.finish_time
		if not a.finished() and a.dist != b.dist:
			return a.dist > b.dist
		return a.slot < b.slot)
	var out: Array[int] = []
	for k: Kart in list:
		out.append(k.pid)
	return out


## Puntaje final: vueltas recorridas. Los que llegaron tienen LAPS más unas
## centésimas por orden de llegada (el primero, más); los demás, menos de LAPS.
static func final_scores(karts: Array, lap_len: float) -> Dictionary:
	var order := race_order(karts)
	var by_id := {}
	for k: Kart in karts:
		by_id[k.pid] = k
	var scores := {}
	for i in order.size():
		var k: Kart = by_id[order[i]]
		if k.finished():
			scores[k.pid] = LAPS + (order.size() - i) * 0.01
		else:
			scores[k.pid] = clampf(floorf(k.dist / lap_len * 1000.0) / 1000.0, 0.0, LAPS - 0.001)
	return scores


# --- Carrera ----------------------------------------------------------------------

## `racing`: false con el cartel final (el resultado ya está decidido).
func _simulate(dt: float, racing: bool) -> void:
	var tr := track()
	var order := race_order(_karts.values())
	var last_id: int = order.back() if order.size() > 1 else -1
	for pid in _ids:
		var k: Kart = _karts[pid]
		var axis := _autopilot(k, tr) if k.finished() else k.axis
		drive(k, axis, dt)
	# Choques (los que ya llegaron no molestan a los que siguen corriendo).
	for i in _ids.size():
		for j in range(i + 1, _ids.size()):
			var a: Kart = _karts[_ids[i]]
			var b: Kart = _karts[_ids[j]]
			if a.finished() or b.finished():
				continue
			var hit := bump(a, b)
			if hit >= HIT_FX_MIN:
				_bump_fx(a, b, hit)
	for pid in _ids:
		var k: Kart = _karts[pid]
		var before := k.dist
		var impact := keep_on_track(k, tr, dt)
		if impact >= HIT_FX_MIN * 1.4:
			_effects.append({"pos": k.pos + Vector2.from_angle(k.heading) * KART_RADIUS, "t": 0.0, "power": 0.5})
		_check_items(k, tr, pid == last_id)
		if racing:
			_check_laps(k, before, dt, tr)
		k.wrong_way = k.wrong_way + dt if racing and k.dist < before - 0.5 and not k.finished() else 0.0


## Los que ya llegaron manejan solos, más despacio, por el medio de la pista.
func _autopilot(k: Kart, tr: Track) -> Vector2:
	var target := tr.point_at(k.s + AUTOPILOT_LOOKAHEAD, k.lat * 0.5)
	var diff := angle_difference(k.heading, (target - k.pos).angle())
	# Joystick hacia abajo lo justo para ir a FINISHED_SPEED (ver target_speed).
	return Vector2(clampf(diff * 2.5, -1.0, 1.0), (1.0 - FINISHED_SPEED) / BRAKE)


func _check_items(k: Kart, tr: Track, is_last: bool) -> void:
	var pad := -1
	for i in PADS.size():
		var along := tr.wrap_delta(k.s - PADS[i].x * tr.length)
		if absf(along) <= PAD_SIZE.x / 2.0 and absf(k.lat - PADS[i].y) <= PAD_SIZE.y / 2.0 + KART_RADIUS * 0.4:
			pad = i
	if pad != -1 and pad != k.on_pad and not k.finished():
		k.turbo = maxf(k.turbo, turbo_duration(is_last))
		play_sfx("whoosh", 1.5)
		notify_player(k.pid, "tap")
	k.on_pad = pad
	var puddle := -1
	for i in PUDDLES.size():
		var c := _puddle_center(i)
		if k.pos.distance_to(c) <= PUDDLES[i].z + KART_RADIUS * 0.4:
			puddle = i
	if puddle != -1 and puddle != k.in_puddle and not k.finished():
		k.slip = SLIP_SEC
		play_sfx("whoosh", 0.7)
		notify_player(k.pid, "hit")
	k.in_puddle = puddle


func _check_laps(k: Kart, before: float, dt: float, tr: Track) -> void:
	if k.finished():
		return
	var lap_len := tr.length
	var lap_before := floori(before / lap_len)
	var lap_now := floori(k.dist / lap_len)
	if lap_now <= lap_before or lap_now <= 0:
		return
	if lap_now >= LAPS:
		# Momento exacto del cruce dentro del paso (desempata llegadas juntas).
		var frac := clampf((LAPS * lap_len - before) / maxf(k.dist - before, 0.0001), 0.0, 1.0)
		k.finish_time = _elapsed - dt + frac * dt
		_finish_order.append(k.pid)
		if _first_finish < 0.0:
			_first_finish = _elapsed
		var first := _finish_order.size() == 1
		play_sfx("win" if first else "point")
		notify_player(k.pid, "win" if first else "point")
	elif lap_now == LAPS - 1:
		notify_player(k.pid, "count")
		if not _last_lap_shown:
			_last_lap_shown = true
			_show_banner("¡Última vuelta!")
			play_sfx("join")
	else:
		play_sfx("tick")


func _show_banner(text: String) -> void:
	_banner = text
	_banner_t = BANNER_SEC


func _check_end() -> void:
	var all_in := true
	for pid in _ids:
		all_in = all_in and (_karts[pid] as Kart).finished()
	var time_up := _elapsed >= TIME_LIMIT_SEC or (_first_finish >= 0.0 and _elapsed >= _first_finish + FINISH_GRACE_SEC)
	if all_in or time_up:
		_start_end("¡Meta!" if all_in else "¡Tiempo!")


## Decide el resultado ya y lo emite después de END_DELAY_SEC.
func _start_end(text: String) -> void:
	var tr := track()
	var karts := _karts.values()
	var order := race_order(karts)
	var anyone_in := not _finish_order.is_empty()
	_result = {
		"winners": [order[0]] if not order.is_empty() else [],
		"scores": final_scores(karts, tr.length),
		"summary": "Gana el primero en cruzar la meta" if anyone_in else "Nadie llegó: gana el que más avanzó",
	}
	_end_text = text
	_end_timer = END_DELAY_SEC
	_phase = Phase.ENDING
	play_sfx("fanfare")
	for pid in _ids:
		var k: Kart = _karts[pid]
		if not k.finished():
			k.axis = Vector2(0, 1)  # Frenan despacito mientras se ve el cartel.


## Tiempo que queda (el tope de 90 s, o los 15 s de gracia tras el primero).
func time_left() -> float:
	var left := TIME_LIMIT_SEC - _elapsed
	if _first_finish >= 0.0:
		left = minf(left, _first_finish + FINISH_GRACE_SEC - _elapsed)
	return maxf(left, 0.0)


## Puesto de cada jugador ahora mismo: {player_id: 1..n}.
func places() -> Dictionary:
	var order := race_order(_karts.values())
	var out := {}
	for i in order.size():
		out[order[i]] = i + 1
	return out


static var _puddle_centers := PackedVector2Array()
static var _pad_frames: Array[Transform2D] = []


## Centro de cada charco (se calcula una vez: se consulta en cada paso).
static func _puddle_center(i: int) -> Vector2:
	if _puddle_centers.is_empty():
		for p: Vector3 in PUDDLES:
			_puddle_centers.append(track().point_at(p.x * track().length, p.y))
	return _puddle_centers[i]


## Ubicación y dirección de cada turbo (una vez).
static func _pad_frame(i: int) -> Transform2D:
	if _pad_frames.is_empty():
		var tr := track()
		for pad: Vector2 in PADS:
			var s := pad.x * tr.length
			_pad_frames.append(Transform2D((tr.frame_at(s)[1] as Vector2).angle(), tr.point_at(s, pad.y)))
	return _pad_frames[i]


# --- Efectos ----------------------------------------------------------------------

func _bump_fx(a: Kart, b: Kart, impact: float) -> void:
	var pair := Vector2i(a.pid, b.pid)
	if _elapsed - float(_pair_fx.get(pair, -INF)) < HIT_FX_COOLDOWN:
		return
	_pair_fx[pair] = _elapsed
	_effects.append({"pos": (a.pos + b.pos) / 2.0, "t": 0.0, "power": clampf(impact / MAX_SPEED, 0.3, 1.0)})
	play_sfx("pong", 0.7)


func _update_effects(dt: float) -> void:
	for e in _effects:
		e.t += dt
	_effects = _effects.filter(func(e: Dictionary) -> bool: return e.t < SPARK_SEC)


# --- Dibujo ------------------------------------------------------------------------

func _draw() -> void:
	_v25 = draw_board_25d(board_view())
	if not _v25:
		draw_static(_paint_scene)
	_refresh_tabs()
	var t := anim_time
	var fx := GameArt.TriBatch.new()
	for i in PADS.size():
		_add_pad_lights(fx, i, t)
	_to_screen(fx).flush(self)
	# Karts de arriba hacia abajo: el de más abajo tapa al de más arriba.
	var sorted := players.duplicate()
	sorted.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return (_karts[a.id] as Kart).pos.y < (_karts[b.id] as Kart).pos.y)
	var tags: Array = []
	var order := race_order(_karts.values())
	var leader: int = order[0] if not order.is_empty() else -1
	for p: Dictionary in sorted:
		var k: Kart = _karts[p.id]
		# El kart se arma acostado en el plano y, en 2.5D, se proyecta vértice
		# por vértice (exacto: queda apoyado en el asfalto en perspectiva).
		var body := GameArt.TriBatch.new()
		_add_kart(body, k, p.color, t)
		_to_screen(body).flush(self)
		var d := _depth(k.pos)
		var feet := _screen(k.pos + Vector2(0, SEAT_OFFSET))
		var mood := PlayerAvatar.Mood.NORMAL
		if k.finished() or (_phase == Phase.ENDING and leader == k.pid):
			mood = PlayerAvatar.Mood.HAPPY
		elif k.slip > 0.0:
			mood = PlayerAvatar.Mood.SURPRISED
		var anim := mascot_anim(p.id, Vector2.from_angle(k.heading))
		anim["wave"] = mood == PlayerAvatar.Mood.HAPPY
		PlayerAvatar.draw_mascot(self, feet, MASCOT_SCALE * d, p.color, PlayerAvatar.style_of(p), mood, 0.0, 0.0, false, anim)
		var rim := GameArt.TriBatch.new()
		_add_cockpit(rim, feet, p.color, d)
		rim.flush(self)
		tags.append([p, feet, MASCOT_SCALE * d, NAME_OFFSET])
	draw_player_tags(tags)
	_draw_effects()
	for p: Dictionary in sorted:
		var k: Kart = _karts[p.id]
		var d := _depth(k.pos)
		if k.finished():
			var place := _finish_order.find(k.pid) + 1
			UiTheme.draw_medal(self, _screen(k.pos) + Vector2(52, -46) * d, MEDAL_R * d, place)
		elif k.wrong_way >= WRONG_WAY_SEC and fmod(anim_time, 0.6) < 0.4:
			UiTheme.draw_text(self, "¡Al revés!", _screen(k.pos) + Vector2(0, 50) * d, roundi(HINT_SIZE * d), UiTheme.PAPER, 8, UiTheme.DANGER)
	_draw_banners()
	var center := _hud_center()
	draw_hud(places(), center[0], center[1])


## Triángulos armados en coordenadas del plano -> pantalla: en 2.5D, cada
## vértice por la homografía (las rectas siguen rectas); plano, igual.
func _to_screen(b: GameArt.TriBatch) -> GameArt.TriBatch:
	if _v25:
		b.points = board_view().project_points(b.points)
	return b


## Números del marcador como puesto ("1°", "2°"…): el número de cada
## píldora es el puesto en vivo (reemplaza al de MiniGame, mismo lugar).
func _draw_hud_text_layer() -> void:
	if _hud_state.is_empty():
		return
	var head: Array = _hud_state[0]
	var texts: Array[String] = []
	for i in range(1, _hud_state.size(), 3):
		texts.append(UiTheme.place_text(int(_hud_state[i + 2])))
	GameArt.paint_hud_text(_hud_text, texts, head[0], head[1])


func _hud_center() -> Array:
	var left := time_left()
	if _phase != Phase.COUNTDOWN and left <= CLOCK_WARN_SEC:
		return [clock_text(left), "clock"]
	var leader: Kart = _karts[race_order(_karts.values()).front()] if not _karts.is_empty() else null
	var lap := lap_of(leader.dist, track().length) if leader != null else 1
	return ["Vuelta %d/%d" % [lap, LAPS], "flag"]


func _draw_banners() -> void:
	var mid := Vector2(SCREEN.x / 2.0, 470)
	if _phase == Phase.COUNTDOWN:
		draw_text_centered("%d" % ceili(_countdown), mid, COUNT_SIZE, UiTheme.PAPER, 22)
	elif _countdown > -GO_SEC:
		draw_text_centered("¡YA!", mid, COUNT_SIZE, UiTheme.ACCENT, 22)
	if _phase == Phase.ENDING:
		draw_text_centered(_end_text, mid, COUNT_SIZE / 2, UiTheme.ACCENT, 18)
	elif _banner_t > 0.0:
		var pop := 1.0 + 0.15 * maxf(0.0, (_banner_t - BANNER_SEC + 0.25) / 0.25)
		draw_text_centered(_banner, mid, roundi(BANNER_SIZE * pop), UiTheme.ACCENT, 14)


func _draw_effects() -> void:
	if _effects.is_empty():
		return
	var b := GameArt.TriBatch.new()
	for e in _effects:
		var k: float = e.t / SPARK_SEC
		var power: float = e.power
		var d := _depth(e.pos)
		var at0 := _screen(e.pos)
		for i in 5:
			var a := TAU * i / 5.0 + (e.pos as Vector2).x * 0.01
			var at: Vector2 = at0 + Vector2.from_angle(a) * lerpf(10.0, 40.0 + 30.0 * power, k) * d
			b.star(at, (7.0 + 7.0 * power) * (1.0 - k * 0.8) * d, UiTheme.GOLD, k * 2.0, 3.0)
	b.flush(self)


## Kart visto desde arriba, rotado según hacia dónde va: sombra, ruedas (las
## de adelante giran con el volante), chasis del color del jugador con
## bisel, trompa con faroles y, con turbo, llamas atrás. Patinando, se
## bambolea. El chasis (lo que no se mueve) es una plantilla por color.
func _add_kart(b: GameArt.TriBatch, k: Kart, col: Color, t: float) -> void:
	var wobble := sin(t * 22.0) * 0.35 * (k.slip / SLIP_SEC) if k.slip > 0.0 else 0.0
	var xf := Transform2D(k.heading + wobble, k.pos)
	b.shape(GameArt.round_rect_tris(Vector2(KART_LEN + 6.0, KART_WIDE + 12.0), 16.0),
		Transform2D(k.heading + wobble, k.pos + Vector2(0, 9)), UiTheme.SHADOW)
	if k.turbo > 0.0:
		var flick := 0.75 + 0.25 * sin(t * 40.0 + k.slot)
		b.radial(xf * Vector2(-KART_LEN / 2.0 - 10.0, 0), 46.0 * flick, Color(UiTheme.GLOW, 0.8), Color(UiTheme.GLOW, 0.0), 20)
		for side in [-1.0, 1.0]:
			var base := Vector2(-KART_LEN / 2.0 - 4.0, side * 12.0)
			var tip := base + Vector2(-34.0 * flick - 12.0, 0)
			b.tri(xf * (base + Vector2(0, -10)), xf * tip, xf * (base + Vector2(0, 10)), UiTheme.WARNING)
			b.tri(xf * (base + Vector2(0, -6)), xf * (base + Vector2(-22.0 * flick - 6.0, 0)), xf * (base + Vector2(0, 6)), UiTheme.GOLD)
	if k.slip > 0.0:
		# Gotas que salpican alrededor mientras patina.
		for i in 6:
			var a := t * 7.0 + TAU * i / 6.0
			var d := 44.0 + 6.0 * sin(t * 13.0 + i)
			b.circle(k.pos + Vector2.from_angle(a) * d, 7.0, UiTheme.INK, 10)
			b.circle(k.pos + Vector2.from_angle(a) * d, 5.0, UiTheme.KARTS_PUDDLE_SHINE, 10)
	var wheel := GameArt.round_rect_tris(Vector2(20, 12), 4.0)
	var wy := KART_WIDE / 2.0 + 1.0
	for w in [Vector2(KART_LEN / 2.0 - 16.0, -wy), Vector2(KART_LEN / 2.0 - 16.0, wy)]:
		b.shape(wheel, xf * Transform2D(k.steer * 0.45, w as Vector2), UiTheme.INK)
	var tpl := _kart_template(col)
	b.template(tpl[0], tpl[1], xf)


## Chasis en coordenadas locales (x = adelante), armado una vez por color.
func _kart_template(col: Color) -> Array:
	if _kart_tpl.has(col):
		return _kart_tpl[col]
	var b := GameArt.TriBatch.new()
	var h := KART_LEN / 2.0
	var w := KART_WIDE / 2.0
	var ink := UiTheme.INK
	# Ruedas de atrás (las de adelante giran: van aparte).
	for y in [-w - 1.0, w + 1.0]:
		b.chamfer_rect(Rect2(-h + 5.0, y - 6.5, 22.0, 13.0), 4.0, ink)
	# Contorno, canto oscuro y cara del chasis con luz arriba.
	b.chamfer_rect(Rect2(-h - 3.0, -w - 3.0, KART_LEN + 6.0, KART_WIDE + 6.0), 14.0, ink)
	b.chamfer_rect(Rect2(-h, -w, KART_LEN, KART_WIDE), 12.0, col.darkened(0.35))
	b.chamfer_rect(Rect2(-h + 2.0, -w + 2.0, KART_LEN - 4.0, KART_WIDE - 7.0), 10.0, col)
	b.chamfer_rect(Rect2(-h + 8.0, -w + 4.0, KART_LEN - 22.0, 6.0), 3.0, col.lightened(0.45))
	# Trompa: paragolpes claro con dos faroles.
	b.chamfer_rect(Rect2(h - 12.0, -w + 5.0, 12.0, KART_WIDE - 10.0), 5.0, col.lightened(0.3))
	for y in [-w + 11.0, w - 11.0]:
		b.circle(Vector2(h - 5.0, y), 4.5, ink, 10)
		b.circle(Vector2(h - 5.0, y), 3.0, UiTheme.GOLD, 10)
	# Alerón atrás.
	b.chamfer_rect(Rect2(-h - 6.0, -w + 2.0, 9.0, KART_WIDE - 4.0), 3.0, ink)
	b.chamfer_rect(Rect2(-h - 4.0, -w + 4.0, 5.0, KART_WIDE - 8.0), 2.0, col.darkened(0.2))
	_kart_tpl[col] = [b.points, b.colors]
	return _kart_tpl[col]


## Borde del asiento delante de la mascota (siempre derecho, en pantalla):
## tapa los pies y la hace ver sentada adentro del kart.
func _add_cockpit(b: GameArt.TriBatch, feet: Vector2, col: Color, d: float = 1.0) -> void:
	var r := Rect2(feet + Vector2(-27, -12) * d, Vector2(54, 20) * d)
	b.capsule(r.grow(3.0 * d), UiTheme.INK)
	b.capsule(r, col.darkened(0.3))
	b.capsule(Rect2(r.position, r.size - Vector2(0, 5) * d), col)
	b.capsule(Rect2(r.position + Vector2(10, 3) * d, Vector2(r.size.x - 20 * d, 4 * d)), Color(1, 1, 1, 0.4))


## Flechas del turbo que se prenden en secuencia (lo fijo está en la escena).
func _add_pad_lights(b: GameArt.TriBatch, i: int, t: float) -> void:
	var xf := _pad_frame(i)
	var lit := int(t * 6.0) % 3
	b.template(_chevron_tris(), GameArt.pattern_colors(PackedColorArray([Color(UiTheme.PAPER, 0.85)]), _chevron_tris().size()),
		xf * Transform2D(0.0, Vector2(-22.0 + lit * 22.0, 0)))


static var _chevron: PackedVector2Array


## Flecha ">" del turbo (local: x = adelante), como triángulos.
static func _chevron_tris() -> PackedVector2Array:
	if _chevron.is_empty():
		var s := 16.0
		var th := 7.0
		for side in [-1.0, 1.0]:
			var a := Vector2(-s * 0.5, side * s)
			var c := Vector2(s * 0.5, 0)
			_chevron.append_array([a, c, c + Vector2(-th, 0), a, c + Vector2(-th, 0), a + Vector2(-th, 0)])
	return _chevron


# --- Escena fija (se dibuja una vez, ver MiniGame.draw_static) --------------------

func _paint_scene(ci: CanvasItem) -> void:
	GameArt.paint_stage(ci, GameArt.board_cover(FIELD))
	var b := GameArt.TriBatch.new()
	# Con piezas 3D (Props3D) los bloques del marco y las esquinas van como
	# sprites del atlas: el lote se corta después del marco y al final.
	var bricks: Array = []
	var corners: Array = []
	_add_board(b, FIELD, bricks)
	if not bricks.is_empty():
		b.flush(ci)
		GameArt.draw_pieces(ci, bricks)
	_add_grass(b, FIELD)
	_add_decor(b)
	_add_track(b)
	_add_items(b)
	# El marco le hace sombra al pasto (arriba y a la izquierda).
	var shade := Color(UiTheme.INK, 0.2)
	var clear := Color(UiTheme.INK, 0.0)
	var r := FIELD
	b.quad_colors(r.position, Vector2(r.end.x, r.position.y), Vector2(r.end.x, r.position.y + 22.0),
		r.position + Vector2(0, 22.0), shade, shade, clear, clear)
	b.quad_colors(r.position, r.position + Vector2(16.0, 0), Vector2(r.position.x + 16.0, r.end.y),
		Vector2(r.position.x, r.end.y), shade, clear, clear, shade)
	_add_frame_corners(b, FIELD, corners)
	b.flush(ci)
	GameArt.draw_pieces(ci, corners)


## Marco de bloques con sombra, igual al tablero de los demás juegos
## (GameArt.paint_board) pero con pasto en vez de baldosas.
func _add_board(b: GameArt.TriBatch, rect: Rect2, pieces: Array) -> void:
	var f := UiTheme.BOARD_FRAME
	var depth := UiTheme.BOARD_DEPTH
	var outer := rect.grow(f)
	var body := outer.grow_side(SIDE_BOTTOM, depth)
	GameArt.add_soft_shadow(b, body, 24.0)
	var edge := body.grow(5.0)
	b.feather_round_rect(edge, 24.0, UiTheme.INK)
	b.ring_round_rect(edge, body, 19.0, UiTheme.INK)
	b.rect(Rect2(outer.position, Vector2(outer.size.x, f)), UiTheme.INK)
	b.rect(Rect2(outer.position.x, rect.end.y, outer.size.x, f + depth), UiTheme.INK)
	b.rect(Rect2(outer.position.x, rect.position.y, f, rect.size.y), UiTheme.INK)
	b.rect(Rect2(rect.end.x, rect.position.y, f, rect.size.y), UiTheme.INK)
	var i := 0
	for side in 4:
		var horizontal := side < 2
		var length := outer.size.x if horizontal else rect.size.y
		var n := maxi(1, roundi(length / UiTheme.BOARD_BRICK))
		var step := length / n
		for k in n:
			var col: Color = UiTheme.BRICKS[(i * 3 + side) % UiTheme.BRICKS.size()]
			i += 1
			var r: Rect2
			match side:
				0: r = Rect2(outer.position.x + k * step, outer.position.y, step, f)
				1: r = Rect2(outer.position.x + k * step, rect.end.y, step, f)
				2: r = Rect2(outer.position.x, rect.position.y + k * step, f, step)
				_: r = Rect2(rect.end.x, rect.position.y + k * step, f, step)
			if side == 1:
				b.chamfer_rect(Rect2(r.position.x + 1.0, r.end.y - 4.0, r.size.x - 2.0, depth + 2.0), 3.0, col.darkened(0.45))
			if Props3D.is_ready():
				pieces.append([r, Props3D.brick_name((i - 1) * 3 + side, side >= 2)])
			else:
				GameArt._add_brick(b, r, col)


func _add_frame_corners(b: GameArt.TriBatch, rect: Rect2, pieces: Array) -> void:
	var f := UiTheme.BOARD_FRAME
	var depth := UiTheme.BOARD_DEPTH
	var outer := rect.grow(f)
	var ink := UiTheme.INK
	b.rect(Rect2(rect.position - Vector2(3, 3), Vector2(rect.size.x + 6, 3)), ink)
	b.rect(Rect2(rect.position.x - 3, rect.end.y, rect.size.x + 6, 3), ink)
	b.rect(Rect2(rect.position.x - 3, rect.position.y, 3, rect.size.y), ink)
	b.rect(Rect2(rect.end.x, rect.position.y, 3, rect.size.y), ink)
	var cs := UiTheme.BOARD_CORNER
	var corners := [outer.position, Vector2(outer.end.x - f, outer.position.y),
		Vector2(outer.position.x, rect.end.y), Vector2(rect.end.x, rect.end.y)]
	for k in 4:
		var center: Vector2 = corners[k] + Vector2(f, f) / 2.0
		var r := Rect2(center - Vector2(cs, cs) / 2.0, Vector2(cs, cs))
		var col: Color = UiTheme.BRICKS[0] if k != 3 else UiTheme.BRICKS[5]
		var corner_edge := r.grow(4.0).grow_side(SIDE_BOTTOM, depth if k >= 2 else 6.0)
		b.feather_round_rect(corner_edge, 14.0, ink)
		b.round_rect(corner_edge, 14.0, ink)
		if k >= 2:
			b.chamfer_rect(Rect2(r.position.x, r.end.y - 8.0, cs, depth + 8.0), 8.0, col.darkened(0.45))
		if Props3D.is_ready():
			pieces.append([r, GameArt.corner_piece(k)])
			continue
		GameArt._add_brick(b, r, col, 10.0)
		b.star(center + Vector2(0, -3), cs * 0.36, UiTheme.GOLD, 0.0, 4.0)


## Pasto cortado en franjas (cada píxel se pinta una vez) con matitas.
func _add_grass(b: GameArt.TriBatch, rect: Rect2) -> void:
	var stripe := GRASS_STRIPE
	var x := rect.position.x
	var k := 0
	while x < rect.end.x - 0.5:
		var w := minf(stripe, rect.end.x - x)
		b.rect(Rect2(x, rect.position.y, w, rect.size.y), UiTheme.KARTS_GRASS if k % 2 == 0 else UiTheme.KARTS_GRASS_ALT)
		x += stripe
		k += 1


## Árboles, matas, flores y pilas de bloques en el pasto, lejos de la pista.
## Lugares al azar pero siempre los mismos (semilla fija): decor_layout().
func _add_decor(b: GameArt.TriBatch) -> void:
	for d: Array in decor_layout():
		match d[0]:
			"tree": _add_tree(b, d[1], d[2])
			"bush": _add_bush(b, d[1], d[2])
			_: _add_flower(b, d[1], d[3])


static var _decor: Array = []


## Dónde va cada árbol, mata y flor del pasto: [tipo, centro, radio, índice
## de color] (una vez por proceso). Lo comparten el dibujo plano y la
## escena 2.5D horneada, así el decorado es el mismo en los dos.
static func decor_layout() -> Array:
	if not _decor.is_empty():
		return _decor
	var tr := track()
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var placed: Array[Vector3] = []
	var area := FIELD.grow(-34.0)
	var kinds := {"tree": 0, "bush": 0, "flower": 0}
	for attempt in 500:
		var p := Vector2(rng.randf_range(area.position.x, area.end.x), rng.randf_range(area.position.y, area.end.y))
		var roll := rng.randf()
		var kind := "flower" if roll < 0.45 else ("bush" if roll < 0.75 else "tree")
		var r := 12.0 if kind == "flower" else (22.0 if kind == "bush" else rng.randf_range(34.0, 44.0))
		var limit := {"tree": 9, "bush": 12, "flower": 26}
		if int(kinds[kind]) >= int(limit[kind]):
			continue
		if tr.distance_to(p) < HALF_WIDTH + CURB + r + 14.0:
			continue
		if not area.grow(-r * 0.5).has_point(p):
			continue
		var free := true
		for q in placed:
			free = free and p.distance_to(Vector2(q.x, q.y)) > r + q.z + 10.0
		if not free:
			continue
		placed.append(Vector3(p.x, p.y, r))
		kinds[kind] = int(kinds[kind]) + 1
		_decor.append([kind, p, r, rng.randi() % UiTheme.BRICKS.size() if kind == "flower" else 0])
	return _decor


func _add_tree(b: GameArt.TriBatch, c: Vector2, r: float) -> void:
	var leaf := UiTheme.KARTS_TREE
	b.ellipse(c + Vector2(6, r * 0.45), r * 1.05, r * 0.6, UiTheme.SHADOW)
	b.circle(c, r + 4.0, UiTheme.INK, 24)
	b.circle(c, r, leaf.darkened(0.25), 24)
	b.circle(c + Vector2(-r * 0.12, -r * 0.14), r * 0.8, leaf, 22)
	for a in 5:
		var d := Vector2.from_angle(TAU * a / 5.0 + r) * r * 0.5
		b.circle(c + d + Vector2(-r * 0.1, -r * 0.14), r * 0.28, leaf.lightened(0.12), 12)
	b.circle(c + Vector2(-r * 0.35, -r * 0.4), r * 0.2, Color(1, 1, 1, 0.35), 12)


func _add_bush(b: GameArt.TriBatch, c: Vector2, r: float) -> void:
	var leaf := UiTheme.KARTS_TREE.lightened(0.15)
	b.ellipse(c + Vector2(4, r * 0.5), r * 1.2, r * 0.45, UiTheme.SHADOW)
	for d in [Vector2(-r * 0.55, 2), Vector2(r * 0.55, 2), Vector2(0, -r * 0.3)]:
		b.circle(c + (d as Vector2), r * 0.7 + 3.0, UiTheme.INK, 16)
	for d in [Vector2(-r * 0.55, 2), Vector2(r * 0.55, 2), Vector2(0, -r * 0.3)]:
		b.circle(c + (d as Vector2), r * 0.7, leaf, 16)
		b.circle(c + (d as Vector2) + Vector2(-r * 0.15, -r * 0.2), r * 0.25, leaf.lightened(0.25), 10)


func _add_flower(b: GameArt.TriBatch, c: Vector2, color_index: int) -> void:
	var petal: Color = UiTheme.BRICKS[color_index].lightened(0.2)
	for a in 5:
		b.circle(c + Vector2.from_angle(TAU * a / 5.0) * 5.5, 4.5, petal, 8)
	b.circle(c, 3.5, UiTheme.GOLD, 8)


## Pista: contorno de tinta, borde de bloques de colores con bisel a los dos
## lados, asfalto con líneas blancas, línea de largada a cuadros y grilla.
func _add_track(b: GameArt.TriBatch) -> void:
	var tr := track()
	var m := tr.size()
	var outer := HALF_WIDTH + CURB
	# Tinta por fuera de los bordes (y un filo difuso).
	for side in [-1.0, 1.0]:
		_band(b, tr, side * (outer + 4.0), side * (outer + 6.0), Color(UiTheme.INK, 0.0), UiTheme.INK)
		_band(b, tr, side * outer, side * (outer + 4.0), UiTheme.INK, UiTheme.INK)
	# Bloques del borde: canto oscuro afuera, cara del color y luz adentro,
	# con una juntura de tinta entre bloque y bloque.
	var blocks := int(ceil(float(m) / CURB_SAMPLES))
	for side in [-1.0, 1.0]:
		for k in blocks:
			var col: Color = UiTheme.BRICKS[(k * 3 + (0 if side < 0.0 else 5)) % UiTheme.BRICKS.size()]
			var i0 := k * CURB_SAMPLES
			var i1 := mini(i0 + CURB_SAMPLES, m)
			_band_range(b, tr, i0, i1, side * (outer - 5.0), side * outer, col.darkened(0.35))
			_band_range(b, tr, i0, i1, side * (HALF_WIDTH + 5.0), side * (outer - 5.0), col)
			_band_range(b, tr, i0, i1, side * HALF_WIDTH, side * (HALF_WIDTH + 5.0), col.lightened(0.4))
			var p := tr.pts[i0]
			var n := tr.nrm[i0]
			b.line(p + n * side * HALF_WIDTH, p + n * side * outer, UiTheme.INK, 2.5)
	# Asfalto, con una franja apenas más clara al medio y líneas al costado.
	_band(b, tr, -HALF_WIDTH, HALF_WIDTH, UiTheme.KARTS_ROAD, UiTheme.KARTS_ROAD)
	_band(b, tr, -HALF_WIDTH * 0.55, HALF_WIDTH * 0.55, UiTheme.KARTS_ROAD_LIGHT, UiTheme.KARTS_ROAD_LIGHT)
	for side in [-1.0, 1.0]:
		_band(b, tr, side * HALF_WIDTH, side * (HALF_WIDTH - 3.0), Color(UiTheme.INK, 0.5), Color(UiTheme.INK, 0.5))
		_band(b, tr, side * (HALF_WIDTH - 11.0), side * (HALF_WIDTH - 15.0), UiTheme.KARTS_ROAD_LINE, UiTheme.KARTS_ROAD_LINE)
	# Línea del medio, punteada.
	var i := 6
	while i < m - 4:
		_band_range(b, tr, i, i + 2, -2.5, 2.5, UiTheme.KARTS_ROAD_LINE)
		i += 5
	_add_start_line(b, tr)


## Franja entre dos distancias laterales a lo largo de toda la pista (con
## color distinto adentro y afuera: sirve para bordes difusos).
func _band(b: GameArt.TriBatch, tr: Track, lat0: float, lat1: float, c0: Color, c1: Color) -> void:
	var m := tr.size()
	for i in m:
		var j := (i + 1) % m
		b.quad_colors(tr.pts[i] + tr.nrm[i] * lat0, tr.pts[j] + tr.nrm[j] * lat0,
			tr.pts[j] + tr.nrm[j] * lat1, tr.pts[i] + tr.nrm[i] * lat1, c0, c0, c1, c1)


func _band_range(b: GameArt.TriBatch, tr: Track, i0: int, i1: int, lat0: float, lat1: float, col: Color) -> void:
	var m := tr.size()
	for i in range(i0, i1):
		var a := i % m
		var c := (i + 1) % m
		b.quad(tr.pts[a] + tr.nrm[a] * lat0, tr.pts[c] + tr.nrm[c] * lat0, tr.pts[c] + tr.nrm[c] * lat1,
			tr.pts[a] + tr.nrm[a] * lat1, col)


## Línea de largada a cuadros (dos filas) y los lugares de la grilla.
func _add_start_line(b: GameArt.TriBatch, tr: Track) -> void:
	var f := tr.frame_at(0.0)
	var xf := Transform2D((f[1] as Vector2).angle(), f[0])
	var cols := 12
	var sq := HALF_WIDTH * 2.0 / cols
	b.template(PackedVector2Array([Vector2(-sq - 3, -HALF_WIDTH), Vector2(sq + 3, -HALF_WIDTH), Vector2(sq + 3, HALF_WIDTH),
		Vector2(-sq - 3, -HALF_WIDTH), Vector2(sq + 3, HALF_WIDTH), Vector2(-sq - 3, HALF_WIDTH)]),
		GameArt.pattern_colors(PackedColorArray([UiTheme.INK]), 6), xf)
	for r in 2:
		for c in cols:
			var col := UiTheme.PAPER if (r + c) % 2 == 0 else UiTheme.INK
			var p0 := Vector2(-sq + r * sq, -HALF_WIDTH + c * sq)
			b.template(PackedVector2Array([p0, p0 + Vector2(sq, 0), p0 + Vector2(sq, sq), p0, p0 + Vector2(sq, sq), p0 + Vector2(0, sq)]),
				GameArt.pattern_colors(PackedColorArray([col]), 6), xf)
	# Lugares de la grilla: corchetes blancos detrás de la línea.
	for spot in GRID:
		var g := tr.frame_at(-spot.x)
		var gx := Transform2D((g[1] as Vector2).angle(), tr.point_at(-spot.x, spot.y))
		var line := Color(UiTheme.PAPER, 0.8)
		for e in [[Vector2(KART_LEN / 2.0 + 6, -28), Vector2(KART_LEN / 2.0 + 6, 28)],
				[Vector2(KART_LEN / 2.0 + 6, -28), Vector2(-KART_LEN / 2.0 + 4, -28)],
				[Vector2(KART_LEN / 2.0 + 6, 28), Vector2(-KART_LEN / 2.0 + 4, 28)]]:
			b.line(gx * (e[0] as Vector2), gx * (e[1] as Vector2), line, 4.0)


## Turbos (base oscura con tres flechas) y charcos (agua con brillo).
func _add_items(b: GameArt.TriBatch) -> void:
	for i in PADS.size():
		var xf := _pad_frame(i)
		var r := Rect2(-PAD_SIZE / 2.0, PAD_SIZE)
		b.template(_chamfer_local(r.grow(4.0), 12.0), GameArt.pattern_colors(PackedColorArray([UiTheme.INK]), 18), xf)
		b.template(_chamfer_local(r, 10.0), GameArt.pattern_colors(PackedColorArray([UiTheme.WARNING.darkened(0.2)]), 18), xf)
		b.template(_chamfer_local(r.grow(-5.0), 7.0), GameArt.pattern_colors(PackedColorArray([UiTheme.WARNING]), 18), xf)
		for k in 3:
			b.template(_chevron_tris(), GameArt.pattern_colors(PackedColorArray([UiTheme.GOLD.lightened(0.2)]), _chevron_tris().size()),
				xf * Transform2D(0.0, Vector2(-22.0 + k * 22.0, 0)))
	for i in PUDDLES.size():
		var c := _puddle_center(i)
		var r := PUDDLES[i].z
		var angle := (track().frame_at(PUDDLES[i].x * track().length)[1] as Vector2).angle()
		var lobes := [Vector3(0, 0, 1.0), Vector3(-0.55, 0.25, 0.62), Vector3(0.5, -0.3, 0.6)]
		for l: Vector3 in lobes:
			b.ellipse(c + Vector2(l.x, l.y).rotated(angle) * r, r * l.z * 1.2 + 4.0, r * l.z * 0.85 + 4.0, UiTheme.INK, angle)
		for l: Vector3 in lobes:
			b.ellipse(c + Vector2(l.x, l.y).rotated(angle) * r, r * l.z * 1.2, r * l.z * 0.85, UiTheme.KARTS_PUDDLE, angle)
		b.ellipse(c + Vector2(-r * 0.25, -r * 0.2), r * 0.45, r * 0.18, UiTheme.KARTS_PUDDLE_SHINE, angle)
		b.ellipse(c + Vector2(r * 0.35, r * 0.2), r * 0.18, r * 0.08, UiTheme.KARTS_PUDDLE_SHINE, angle)


## Rectángulo con esquinas ochavadas en coordenadas locales, como triángulos.
static func _chamfer_local(r: Rect2, k: float) -> PackedVector2Array:
	var t := GameArt.TriBatch.new()
	t.chamfer_rect(r, k, Color.WHITE)
	return t.points


# --- Pestañas de vuelta (debajo del marcador) ---------------------------------------
#
# Debajo de la píldora de cada jugador, "2/3" (vuelta en la que va) o, si ya
# llegó, su puesto con una bandera. Es una capa propia que se redibuja solo
# cuando cambia alguna vuelta (no en cada frame). Cuelga de la capa del
# marcador (MiniGame._hud), detrás de las píldoras: se ve y se oculta con él.

func _refresh_tabs() -> void:
	if _tabs == null:
		if _hud == null:
			return  # Todavía no se armaron las capas (se llama después de draw_static).
		_tabs = Node2D.new()
		_tabs.name = "LapTabs"
		_tabs.show_behind_parent = true
		_tabs.draw.connect(_draw_tabs)
		_hud.add_child(_tabs)
	var center: Array = _hud_center()
	var key: Array = [GameArt.hud_center_width(center[0], center[1])]
	for p in players:
		var k: Kart = _karts[p.id]
		key.append_array([lap_of(k.dist, track().length), _finish_order.find(k.pid) + 1])
	if key != _tabs_key:
		_tabs_key = key
		_tabs.queue_redraw()


func _draw_tabs() -> void:
	if _tabs_key.is_empty():
		return
	var pills: Array = GameArt.hud_layout(players.size(), _tabs_key[0])[1]
	var b := GameArt.TriBatch.new()
	var texts: Array = []
	for i in mini(players.size(), pills.size()):
		var pill: Rect2 = pills[i]
		var lap: int = _tabs_key[1 + i * 2]
		var place: int = _tabs_key[2 + i * 2]
		var r := Rect2(Vector2(pill.get_center().x - TAB_SIZE.x / 2.0, pill.end.y - 4.0), TAB_SIZE)
		var fill := UiTheme.place_color(place) if place > 0 else UiTheme.CHIP_DARK
		b.round_rect(r.grow(3.0), 14.0, UiTheme.INK)
		b.round_rect(r, 12.0, fill)
		b.round_rect(Rect2(r.position + Vector2(10, 3), Vector2(r.size.x - 20, 5)), 2.5, Color(1, 1, 1, 0.18))
		# Banderita a cuadros a la izquierda.
		var fx := r.position + Vector2(18, 13)
		b.rect(Rect2(fx, Vector2(3, 24)), UiTheme.text_on(fill))
		for c in 3:
			for rr in 2:
				b.rect(Rect2(fx + Vector2(3 + c * 6, rr * 6), Vector2(6, 6)), UiTheme.PAPER if (c + rr) % 2 == 0 else UiTheme.INK)
		var text := UiTheme.place_text(place) if place > 0 else "%d/%d" % [lap, LAPS]
		texts.append([text, r.get_center() + Vector2(14, 3), UiTheme.text_on(fill)])
	b.flush(_tabs)
	for t: Array in texts:
		UiTheme.draw_text(_tabs, t[0], t[1], TAB_TEXT_SIZE, t[2])
