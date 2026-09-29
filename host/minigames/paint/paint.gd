extends MiniGame
## Pintar el piso: cada mascota pinta de su color la baldosa que pisa. Si la
## baldosa era de otro jugador, se la roba. Gana quien tenga más baldosas
## cuando se acaba el tiempo.
##
## Power-ups (uno a la vez, en una baldosa al azar):
##   - Brocha gigante: durante unos segundos pinta 3×3 alrededor de la mascota.
##   - Velocidad: durante unos segundos corre ×1,6.
## Cada uno tiene un ícono distinto (brocha / rayo): no dependen del color.
##
## Las baldosas pintadas usan un tono más suave que la mascota y un patrón
## propio por lugar (1P liso, 2P rayas, 3P puntos, 4P cuadritos), así se
## distinguen aunque no se vean bien los colores (daltonismo).
##
## Puntaje: cantidad de baldosas propias al final (también con 1 jugador).
##
## Rendimiento: el campo es una grilla de COLS×ROWS enteros (dueño por
## baldosa) y los patrones se precalculan una vez; en cada frame solo se
## recorren las baldosas sin crear arrays nuevos.
##
## Escenario 2.5D (ADR 0019): si hay render, el tablero, su marco y los
## juguetes de alrededor son una escena 3D horneada una vez con cámara en
## perspectiva (Board25DBaker) y el juego se dibuja encima PROYECTADO con la
## misma cámara (BoardView25D): baldosas pintadas acostadas en el piso,
## mascotas y premios parados, más chicos atrás. Las reglas siguen en las
## coordenadas planas de FIELD (tests y bots no cambian). Sin render
## (--headless) o mientras se hornea, se dibuja plano como siempre.

enum State { COUNTDOWN, PLAYING, TIME_UP }
enum PowerUp { BRUSH, SPEED }
enum Pattern { PLAIN, STRIPES, DOTS, GRID }

const DURATION_SEC := 45.0
const COUNTDOWN_SEC := 3.0
const GO_SEC := 0.8               ## Cuánto se ve "¡YA!" después del 1.
const END_WAIT_SEC := 1.5         ## Cuánto se ve "¡Tiempo!" antes de terminar.

const COLS := 20
const ROWS := 11
const CELL := 74.0
## Mismo espacio que Arena, con baldosas cuadradas y lugar para el HUD arriba.
const FIELD := Rect2(220, 172, COLS * CELL, ROWS * CELL)
const EMPTY := -1                 ## Baldosa sin pintar.

const SPEED := 620.0              ## Igual que Arena.
const SPEED_BOOST := 1.6
## Tamaño de la mascota. Medido contra la maqueta (docs/design/
## referencia_juego_pintar.webp): ahí la cabeza de la mascota de adelante
## mide ~1,5 baldosas de ancho y la de atrás ~1,2; con 0,8 las nuestras
## medían ~0,85 (con 1,3 miden ~1,4 y ~1,2). Con la escala por profundidad del 2.5D (0,93–1,07) todos
## los tamaños caen en el mismo nivel del atlas (MascotAtlas.TIERS_U 1,45):
## un solo horneado por jugador, el de la intro.
const MASCOT_SCALE := 1.3
## A este tamaño la intro no precalienta sola la caminata (MascotAtlas.GAME_WALK_MAX_U:
## los juegos con mascotas grandes no suelen caminar); acá sí caminan.
const MASCOT_PREWARM := [[MASCOT_SCALE, ["walk@0"]]]
const NAME_OFFSET := 26.0         ## Nombre debajo de los pies.
## Los pies llegan casi al borde: así se pueden pintar todas las baldosas.
const MOVE_MARGIN_X := 20.0
const MOVE_MARGIN_Y := 16.0

const POWER_SEC := 4.0            ## Duración del efecto.
const FIRST_POWER_SEC := 4.0      ## El primero aparece antes, para enseñarlo.
const POWER_EVERY_SEC := 8.0
const POWER_LIFE_SEC := 7.0       ## Si nadie lo agarra, desaparece.
const BRUSH_RADIUS := 1           ## 1 -> área de 3×3.
const PICKUP_RADIUS := 52.0
const POWER_BADGE := 34.0         ## Radio del círculo del power-up en el piso.

const POP_SEC := 0.18             ## Animación al pintar una baldosa.
const TILE_HOP := 7.0             ## Cuánto se levanta la baldosa al saltar (px).
const PAINT_SOFTEN := 0.5         ## Cuánto se aclara el color del jugador.
const PATTERN_WIDTH := 7.0
const DOT_RADIUS := 7.5
## Muestra del patrón debajo de cada píldora del marcador.
const LEGEND_SIZE := 40.0

var _state := State.COUNTDOWN
var _countdown := COUNTDOWN_SEC
var _time_left := DURATION_SEC
var _end_wait := END_WAIT_SEC
var _anim := 0.0                  # reloj solo para animaciones

var _pos: Dictionary = {}         # player_id -> Vector2 (pies)
var _axis: Dictionary = {}        # player_id -> Vector2
var _tiles: Dictionary = {}       # player_id -> baldosas propias
var _brush_left: Dictionary = {}  # player_id -> segundos de brocha gigante
var _speed_left: Dictionary = {}  # player_id -> segundos de velocidad
## Dueño de cada baldosa (player_id o EMPTY), índice = fila * COLS + columna.
var _owner := PackedInt32Array()
var _painted_at := PackedFloat32Array()  # _anim cuando se pintó (animación)

## Power-up en el piso: {} o {kind: PowerUp, cell: Vector2i, life: float}.
var _powerup: Dictionary = {}
var _powerup_timer := FIRST_POWER_SEC
var _rng := RandomNumberGenerator.new()

# Dibujo precalculado en setup (nada se crea por baldosa en cada frame).
var _fill: Dictionary = {}        # player_id -> Color suave
var _mark: Dictionary = {}        # player_id -> Color del patrón
var _pattern: Dictionary = {}     # player_id -> Pattern
## Baldosa de cada jugador ya armada (relieve + patrón) como triángulos en
## coordenadas locales: [PackedVector2Array, PackedColorArray] (GameArt.tile_template).
var _tile: Dictionary = {}        # player_id -> Array
var _floor: Array[Node2D] = []            # una capa por fila con las baldosas quietas (ver _draw_tiles)
var _floor_tiles: Array[PackedInt32Array] = []  # lo que muestra cada fila: dueño por baldosa

## Vista 2.5D del campo (una por proceso: la cámara no cambia) y si este
## cuadro se dibuja con ella (hay escenario horneado).
static var _board_view: BoardView25D
var _v25 := false


static func get_info() -> Dictionary:
	return {
		"id": "paint",
		"title": "Pintar el piso",
		"description": "Pisá las baldosas para pintarlas de tu color y robale las suyas a los demás. Gana quien pinte más.",
		"min_players": 1,
		"max_players": 4,
		"layout": Protocol.LAYOUT_JOYSTICK,
		"layout_data": {},
		"accent": UiTheme.BRICKS[6],
		"score_label": "baldosas",
	}


## Cámara y proyección del escenario 2.5D de este juego (ADR 0019).
static func board_view() -> BoardView25D:
	if _board_view == null:
		_board_view = BoardView25D.make(FIELD, CELL, "paint")
	return _board_view


## Durante la intro: el escenario 2.5D se lee del disco o se hornea.
static func prewarm_art(host: Node) -> void:
	Board25DBaker.request(host, board_view())


# --- Reglas puras (testeadas) ---------------------------------------------------

## Celda de la grilla que corresponde a una posición de pantalla. Los bordes
## derecho e inferior del campo cuentan como la última celda; fuera del
## campo devuelve (-1, -1).
static func cell_at(pos: Vector2) -> Vector2i:
	if pos.x < FIELD.position.x or pos.y < FIELD.position.y or pos.x > FIELD.end.x or pos.y > FIELD.end.y:
		return Vector2i(-1, -1)
	return Vector2i(
		clampi(floori((pos.x - FIELD.position.x) / CELL), 0, COLS - 1),
		clampi(floori((pos.y - FIELD.position.y) / CELL), 0, ROWS - 1))


## Área que pinta una mascota parada en `center`: un cuadrado de
## (2·radius + 1) celdas de lado, recortado a la grilla. Celda inválida -> vacío.
static func brush_rect(center: Vector2i, radius: int) -> Rect2i:
	if center.x < 0 or center.y < 0 or center.x >= COLS or center.y >= ROWS:
		return Rect2i()
	var side := 2 * radius + 1
	return Rect2i(center - Vector2i(radius, radius), Vector2i(side, side)).intersection(Rect2i(0, 0, COLS, ROWS))


static func cell_center(cell: Vector2i) -> Vector2:
	return FIELD.position + (Vector2(cell) + Vector2(0.5, 0.5)) * CELL


# --- Ciclo del juego --------------------------------------------------------------

func setup(p_players: Array[Dictionary]) -> void:
	super.setup(p_players)
	_rng.randomize()
	_owner.resize(COLS * ROWS)
	_owner.fill(EMPTY)
	_painted_at.resize(COLS * ROWS)
	_painted_at.fill(-POP_SEC)
	# Cada uno arranca en una esquina (mismo orden que Arena).
	var starts: Array[Vector2i] = [Vector2i(1, 1), Vector2i(COLS - 2, ROWS - 2), Vector2i(COLS - 2, 1), Vector2i(1, ROWS - 2)]
	for p in players:
		var pid: int = p.id
		# Un color muy claro (blanco) se oscurece: si no, no se ve sobre el piso.
		var col: Color = UiTheme.on_light(p.color)
		_pos[pid] = cell_center(starts[posmod(p.slot, starts.size())])
		_axis[pid] = Vector2.ZERO
		_tiles[pid] = 0
		_brush_left[pid] = 0.0
		_speed_left[pid] = 0.0
		_fill[pid] = col.lerp(UiTheme.PAPER, PAINT_SOFTEN)
		_mark[pid] = col
		_pattern[pid] = posmod(p.slot, 4)
		_tile[pid] = GameArt.tile_template(CELL, _fill[pid], col, _pattern[pid], PATTERN_WIDTH, DOT_RADIUS)


func on_input(player_id: int, input: Dictionary) -> void:
	if not _axis.has(player_id):
		return
	var axis: Variant = input.get("axis", Vector2.ZERO)
	_axis[player_id] = (axis as Vector2).limit_length(1.0) if axis is Vector2 else Vector2.ZERO


## Para los bots (ver MiniGame.bot_view): mascotas, dueño de cada baldosa
## y power-up. Solo lectura.
func bot_view() -> Dictionary:
	return {
		"pos": _pos, "owner": _owner, "cols": COLS, "rows": ROWS, "cell": CELL, "field": FIELD,
		"powerup": _powerup, "playing": _state == State.PLAYING, "empty": EMPTY, "speed": SPEED,
	}


func _physics_process(delta: float) -> void:
	if is_finished():
		return
	_anim += delta
	match _state:
		State.COUNTDOWN:
			_countdown -= delta
			if _countdown <= 0.0:
				_state = State.PLAYING
				_paint_all()
		State.PLAYING:
			if _countdown > -GO_SEC:
				_countdown -= delta
			_time_left = maxf(_time_left - delta, 0.0)
			_tick_powers(delta)
			_move_players(delta)
			_paint_all()
			_check_pickup()
			_tick_spawn(delta)
			if _time_left <= 0.0:
				_state = State.TIME_UP
				_end_wait = END_WAIT_SEC
				_time_up_fx()
		State.TIME_UP:
			for pid: int in _pos:
				advance_walk(pid, 0.0, delta)
			_end_wait -= delta
			if _end_wait <= 0.0:
				finish(result_from_scores(_tiles, "Más baldosas gana"))
	queue_redraw()


func _move_players(delta: float) -> void:
	for pid: int in _pos:
		var p: Vector2 = _pos[pid] + (_axis[pid] as Vector2) * _speed_of(pid) * delta
		advance_walk(pid, (_axis[pid] as Vector2).length() * _speed_of(pid) / SPEED, delta, 3.0)
		p.x = clampf(p.x, FIELD.position.x + MOVE_MARGIN_X, FIELD.end.x - MOVE_MARGIN_X)
		p.y = clampf(p.y, FIELD.position.y + MOVE_MARGIN_Y, FIELD.end.y - MOVE_MARGIN_Y)
		_pos[pid] = p
		juice().stop_dust(pid, (_axis[pid] as Vector2).length(), _screen(p))


func _speed_of(pid: int) -> float:
	return SPEED * (SPEED_BOOST if float(_speed_left.get(pid, 0.0)) > 0.0 else 1.0)


func _paint_all() -> void:
	for pid: int in _pos:
		var radius := BRUSH_RADIUS if float(_brush_left[pid]) > 0.0 else 0
		_paint_area(pid, _pos[pid], radius)


## Pinta el área de la mascota (ver brush_rect). Las baldosas ajenas se
## roban: bajan del contador del dueño anterior. Devuelve cuántas ganó.
func _paint_area(pid: int, pos: Vector2, radius: int) -> int:
	var area := brush_rect(cell_at(pos), radius)
	var gained := 0
	for y in range(area.position.y, area.end.y):
		for x in range(area.position.x, area.end.x):
			var i := y * COLS + x
			var prev := _owner[i]
			if prev == pid:
				continue
			if prev != EMPTY and _tiles.has(prev):
				_tiles[prev] = int(_tiles[prev]) - 1
			_owner[i] = pid
			_tiles[pid] = int(_tiles.get(pid, 0)) + 1
			_painted_at[i] = _anim
			gained += 1
	return gained


func _tick_powers(delta: float) -> void:
	for pid: int in _pos:
		_brush_left[pid] = maxf(float(_brush_left[pid]) - delta, 0.0)
		_speed_left[pid] = maxf(float(_speed_left[pid]) - delta, 0.0)


func _tick_spawn(delta: float) -> void:
	if not _powerup.is_empty():
		_powerup.life -= delta
		if _powerup.life <= 0.0:
			_powerup = {}
			_powerup_timer = POWER_EVERY_SEC
		return
	_powerup_timer -= delta
	if _powerup_timer <= 0.0:
		_spawn_powerup(_random_power_cell(), _rng.randi() % 2)


## Pone un power-up en `cell` (lo usan también los tests).
func _spawn_powerup(cell: Vector2i, kind: int) -> void:
	_powerup = {"kind": kind, "cell": cell, "life": POWER_LIFE_SEC}
	_powerup_timer = POWER_EVERY_SEC


## Celda al azar, en lo posible lejos de todas las mascotas.
func _random_power_cell() -> Vector2i:
	var cell := Vector2i.ZERO
	for attempt in 12:
		cell = Vector2i(_rng.randi_range(0, COLS - 1), _rng.randi_range(0, ROWS - 1))
		var far := true
		for pid: int in _pos:
			var c := cell_at(_pos[pid])
			if absi(c.x - cell.x) <= 3 and absi(c.y - cell.y) <= 3:
				far = false
				break
		if far:
			break
	return cell


func _check_pickup() -> void:
	if _powerup.is_empty():
		return
	var at := cell_center(_powerup.cell)
	for pid: int in _pos:
		if (_pos[pid] as Vector2).distance_to(at) < PICKUP_RADIUS:
			if _powerup.kind == PowerUp.BRUSH:
				_brush_left[pid] = POWER_SEC
			else:
				_speed_left[pid] = POWER_SEC
			_pickup_fx(pid, at, _powerup.kind)
			_powerup = {}
			_powerup_timer = POWER_EVERY_SEC
			return


## Agarrar un power-up: sonido, vibración, brillo y el nombre del poder en
## una píldora del color del jugador.
func _pickup_fx(pid: int, at: Vector2, kind: int) -> void:
	play_sfx("power")
	notify_player(pid, "point")
	if not is_inside_tree():
		return
	juice().sparkles(_screen(at))
	juice().shine(_screen(at), 80.0)
	# Ficha chica arriba del globito 1P–4P, a la escala de la mascota (no tapa el tablero).
	var d := _depth(_pos[pid])
	juice().float_text("¡Brocha!" if kind == PowerUp.BRUSH else "¡Rápido!", _screen(_pos[pid]) + Vector2(0, -196.0 * MASCOT_SCALE) * d,
		player_by_id(pid).get("color", UiTheme.GOLD), d)


## "¡Tiempo!": cartel con golpe de escala y confeti sobre los que van ganando.
func _time_up_fx() -> void:
	var best := _best_score()
	var party := {}
	for pid: int in _tiles:
		if best > 0 and int(_tiles[pid]) == best:
			party[pid] = _screen(_pos[pid])
	celebrate("¡Tiempo!", party)


# --- Dibujo ---------------------------------------------------------------------

func _draw() -> void:
	var v25 := draw_board_25d(board_view())
	if v25 != _v25:
		_v25 = v25
		for y in _floor_tiles.size():  # Cambió la proyección: se redibujan todas las filas.
			_floor_tiles[y] = PackedInt32Array()
	if not _v25:
		draw_sky()
		draw_play_field(FIELD, CELL)
	_draw_tiles()
	if not _powerup.is_empty():
		_draw_powerup()
	# Mascotas de arriba hacia abajo (la de más abajo queda adelante).
	var order := players.duplicate()
	order.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return (_pos[a.id] as Vector2).y < (_pos[b.id] as Vector2).y)
	var best := _best_score()
	for p in order:
		_draw_player(p, best)
	# Globitos 1P–4P y nombres encima de todas las mascotas.
	draw_player_tags(order.map(func(p: Dictionary) -> Array:
		var d := _depth(_pos[p.id])
		return [p, _screen(_pos[p.id]), MASCOT_SCALE * d, NAME_OFFSET * d]))
	draw_hud(_tiles, clock_text(_time_left), "clock")
	# "¡Tiempo!" lo muestra el cartel de los efectos (_time_up_fx).
	if _state != State.TIME_UP:
		draw_countdown(_countdown, GO_SEC)


## Rendimiento: las baldosas quietas están en capas propias, una por fila
## (`_floor`), que se redibujan solo cuando cambia alguna baldosa de esa
## fila; acá se dibujan nada más las que están "saltando" (recién pintadas).
## Con 4 jugadores se pintan decenas de baldosas por segundo: por fila, cada
## cambio redibuja 20 baldosas y no 220. Las baldosas no se superponen entre
## sí, así que se ve igual que dibujando todas acá.
func _draw_tiles() -> void:
	if _floor.is_empty():
		for y in ROWS:
			var layer := Node2D.new()
			layer.show_behind_parent = true  # Detrás de lo que dibuja _draw (power-up, mascotas…).
			layer.draw.connect(_draw_floor_row.bind(y))
			add_child(layer, false, Node.INTERNAL_MODE_FRONT)
			_floor.append(layer)
			_floor_tiles.append(PackedInt32Array())
	var still := _owner.duplicate()
	var popping := GameArt.TriBatch.new()
	for y in ROWS:
		for x in COLS:
			var i := y * COLS + x
			var pid := _owner[i]
			if pid == EMPTY:
				continue
			# Al pintarse, la baldosa "salta": crece de chica a su tamaño
			# pasándose un poco (rebote) y se levanta un instante del piso.
			var k := clampf((_anim - _painted_at[i]) / POP_SEC, 0.0, 1.0)
			if k >= 1.0:
				continue  # Quieta: la dibuja _floor.
			still[i] = EMPTY
			var s := lerpf(0.55, 1.0, UiTheme.ease_pop(k))
			if _v25:  # Achicada en su celda del piso y levantada en la pantalla.
				var grow := Transform2D(0.0, Vector2(s, s), 0.0, Vector2.ONE * CELL * (1.0 - s) / 2.0)
				var hop := Transform2D(0.0, Vector2(0, -sin(k * PI) * TILE_HOP))
				_add_tile(popping, pid, hop * board_view().cell_xform(Vector2i(x, y)) * grow)
				continue
			var origin := FIELD.position + Vector2(x, y) * CELL + Vector2.ONE * CELL * (1.0 - s) / 2.0 \
				- Vector2(0, sin(k * PI) * TILE_HOP)
			_add_tile(popping, pid, Transform2D(0.0, Vector2(s, s), 0.0, origin))
	popping.flush(self)
	for y in ROWS:
		var row := still.slice(y * COLS, (y + 1) * COLS)
		if row != _floor_tiles[y]:
			_floor_tiles[y] = row
			_floor[y].queue_redraw()


## Una fila de baldosas quietas (tamaño normal): toda la fila en un solo
## lote de triángulos (un draw call), armado con las baldosas precalculadas.
func _draw_floor_row(y: int) -> void:
	var tiles := _floor_tiles[y]
	var batch := GameArt.TriBatch.new()
	for x in tiles.size():
		var pid := tiles[x]
		if pid == EMPTY:
			continue
		if _v25:  # Acostada en el piso del tablero 2.5D (ver BoardView25D.cell_xform).
			_add_tile(batch, pid, board_view().cell_xform(Vector2i(x, y)))
		else:
			_add_tile(batch, pid, Transform2D(0.0, FIELD.position + Vector2(x, y) * CELL))
	batch.flush(_floor[y])


## Baldosa del jugador (relieve y patrón, ver GameArt.tile_template) ubicada con `xform`.
func _add_tile(batch: GameArt.TriBatch, pid: int, xform: Transform2D) -> void:
	var tile: Array = _tile[pid]
	batch.template(tile[0], tile[1], xform)


func _draw_powerup() -> void:
	var life: float = _powerup.life
	if life < 1.5 and fmod(_anim, 0.3) < 0.12:
		return  # Parpadea antes de desaparecer.
	var at := cell_center(_powerup.cell)
	if not _v25:
		_draw_power_badge(_powerup.kind, at + Vector2(0, sin(_anim * 5.0) * 4.0), 1.0, true)
		return
	# 2.5D: sombra acostada en el piso y la ficha parada, flotando encima.
	var d := _depth(at)
	var shadow := GameArt.TriBatch.new()
	var r := POWER_BADGE * (0.85 - 0.08 * sin(_anim * 5.0))
	shadow.shape(GameArt.circle_tris(24), board_view().floor_xform(at) * Transform2D(0.0, Vector2(r, r * 0.75), 0.0, at + Vector2(0, 8)),
		UiTheme.BOARD25D_POWER_SHADOW)
	shadow.flush(self)
	var c := _screen(at) + Vector2(0, sin(_anim * 5.0) * 4.0 - UiTheme.BOARD25D_POWER_HOVER) * d
	_draw_power_badge(_powerup.kind, c, d, true)


## Ficha dorada con el ícono del power-up (brocha o rayo). Con `glow`, halo
## que late y rayos que giran: se ve de lejos que es un premio.
func _draw_power_badge(kind: int, c: Vector2, u: float, glow: bool = false) -> void:
	var r := POWER_BADGE * u
	var batch := GameArt.TriBatch.new()
	if glow:
		GameArt.add_glow(batch, c, r + 44.0, UiTheme.GLOW, _anim)
	if Props3D.is_ready():  # Ficha 3D horneada (aro dorado y cara blanca), ADR 0016.
		batch.flush(self)
		var body := r + 8.0 * u
		Props3D.draw(self, "token", Rect2(c - Vector2(body, body), Vector2(body, body) * 2.0))
	else:
		_add_power_badge_2d(batch, c, r, u)
	batch.flush(self)
	draw_set_transform(c, -0.6 if kind == PowerUp.BRUSH else 0.0, Vector2(u, u))
	if kind == PowerUp.BRUSH:
		_draw_brush_icon()
	else:
		_draw_bolt_icon()
	draw_set_transform(Vector2.ZERO)


## Ficha 2D (sin atlas 3D): aro dorado, cara blanca y brillo.
func _add_power_badge_2d(batch: GameArt.TriBatch, c: Vector2, r: float, u: float) -> void:
	batch.feather_circle(c + Vector2(0, 4.0 * u), r + 9.0 * u, UiTheme.INK)
	batch.feather_circle(c, r + 9.0 * u, UiTheme.INK)
	batch.circle(c + Vector2(0, 4.0 * u), r + 9.0 * u, UiTheme.INK, 32)
	batch.circle(c, r + 9.0 * u, UiTheme.INK, 32)
	batch.circle(c, r + 6.0 * u, UiTheme.GOLD.darkened(0.2), 32)
	batch.circle(c + Vector2(0, -1.5 * u), r + 4.5 * u, UiTheme.GOLD, 32)
	batch.circle(c, r - 1.0 * u, UiTheme.PAPER_DIM, 32)
	batch.circle(c + Vector2(0, -2.0 * u), r - 3.0 * u, UiTheme.PAPER, 32)
	batch.ellipse(c + Vector2(-r * 0.45, -r * 0.62), r * 0.3, r * 0.14, Color(1, 1, 1, 0.8), -0.6)


## Brocha en coordenadas locales (unos 56 px de alto, centrada en 0,0).
func _draw_brush_icon() -> void:
	var handle := Rect2(-5, -28, 10, 22)
	var ferrule := Rect2(-10, -8, 20, 10)
	draw_rect(handle.grow(3.0), UiTheme.INK)
	draw_rect(handle, UiTheme.BRONZE)
	draw_rect(ferrule.grow(3.0), UiTheme.INK)
	draw_rect(ferrule, UiTheme.SILVER)
	var bristles := PackedVector2Array([Vector2(-11, 2), Vector2(11, 2), Vector2(9, 18), Vector2(0, 27), Vector2(-9, 18)])
	draw_colored_polygon(bristles, UiTheme.rainbow(_anim * 0.4))
	bristles.append(bristles[0])
	draw_polyline(bristles, UiTheme.INK, 4.0, true)


## Rayo en coordenadas locales.
func _draw_bolt_icon() -> void:
	var bolt := PackedVector2Array([
		Vector2(4, -26), Vector2(-15, 4), Vector2(-2, 4), Vector2(-6, 26), Vector2(15, -5), Vector2(2, -5)])
	draw_colored_polygon(bolt, UiTheme.GOLD)
	bolt.append(bolt[0])
	draw_polyline(bolt, UiTheme.INK, 4.0, true)


func _draw_player(p: Dictionary, best: int) -> void:
	var pid: int = p.id
	var at: Vector2 = _pos[pid]       # En el campo (reglas).
	var feet := _screen(at)           # En la pantalla.
	var d := _depth(at)               # Más chica atrás (2.5D).
	var axis: Vector2 = _axis[pid]
	var moving := _state == State.PLAYING and axis.length() > 0.1
	var brush: float = _brush_left[pid]
	var speed: float = _speed_left[pid]
	# Brocha gigante: marco punteado del área de 3×3 que está pintando.
	if brush > 0.0:
		var area := brush_rect(cell_at(at), BRUSH_RADIUS)
		var r := Rect2(FIELD.position + Vector2(area.position) * CELL, Vector2(area.size) * CELL)
		if _v25:
			board_view().draw_dashed_rect(self, r.grow(-3.0), UiTheme.INK, 5.0, 14.0, 8.0)
		else:
			UiTheme.draw_dashed_rect(self, r.grow(-3.0), UiTheme.INK, 5.0, 0.0, 14.0, 8.0)
	# Velocidad: estelas detrás de la mascota.
	if speed > 0.0 and moving:
		var back := -axis.normalized()
		var side := Vector2(-back.y, back.x)
		for k in 3:
			var o := feet + (Vector2(0, -30) + side * (k - 1) * 18.0 + back * 34.0) * d
			draw_line(o, o + back * (26.0 + k % 2 * 14.0) * d, Color(UiTheme.INK, 0.45), 5.0, true)
	var mood := PlayerAvatar.Mood.NORMAL
	if _state == State.TIME_UP or is_finished():
		mood = PlayerAvatar.Mood.HAPPY if int(_tiles[pid]) == best else PlayerAvatar.Mood.NORMAL
	var anim := mascot_anim(pid, axis)
	anim["wave"] = mood == PlayerAvatar.Mood.HAPPY
	PlayerAvatar.draw_mascot(self, feet, MASCOT_SCALE * d, p.color, PlayerAvatar.style_of(p), mood, 0.0, celebrate_hop(pid), false, anim)
	# Power-up activo: ícono chico al costado con el tiempo que le queda.
	var active := maxf(brush, speed)
	if active > 0.0:
		var c := feet + Vector2(56, -64) * d
		_draw_power_badge(PowerUp.BRUSH if brush >= speed else PowerUp.SPEED, c, 0.55 * d)
		# Cuánto le queda: arco blanco sobre el aro dorado.
		draw_arc(c, (POWER_BADGE * 0.55 + 3.0) * d, -PI / 2.0, -PI / 2.0 + TAU * active / POWER_SEC, 32, UiTheme.PAPER, 4.0, true)


## Debajo de cada píldora del marcador, una muestra del patrón del jugador:
## así "2P" se asocia a las rayas aunque no se distinga el color. Va en la
## capa cacheada del marcador (MiniGame._draw_hud_extra): no cuesta por frame.
func _draw_hud_extra(ci: CanvasItem, player: Dictionary, pill: Rect2) -> void:
	var pid: int = player.id
	if not _tile.has(pid):
		return
	var s := LEGEND_SIZE / CELL
	var r := Rect2(pill.get_center().x - LEGEND_SIZE / 2.0, pill.end.y + 9.0, LEGEND_SIZE, LEGEND_SIZE)
	var batch := GameArt.TriBatch.new()
	batch.round_rect(r.grow(4.0), 8.0, UiTheme.INK)
	batch.rect(r.grow(-1.0), UiTheme.TILE_GROUT)
	_add_tile(batch, pid, Transform2D(0.0, Vector2(s, s), 0.0, r.position))
	batch.flush(ci)


## Dónde se dibuja un punto del campo: proyectado sobre el tablero 2.5D, o
## igual si se dibuja plano.
func _screen(p: Vector2) -> Vector2:
	return board_view().project(p) if _v25 else p


## Escala de lo que está parado en `p` (mascotas, premios, estelas): más
## chico atrás en 2.5D (con tope, ver UiTheme.BOARD25D_SCALE_*); 1 en plano.
func _depth(p: Vector2) -> float:
	if not _v25:
		return 1.0
	return clampf(board_view().scale_at(p), UiTheme.BOARD25D_SCALE_MIN, UiTheme.BOARD25D_SCALE_MAX)


func _best_score() -> int:
	var best := 0
	for pid: int in _tiles:
		best = maxi(best, int(_tiles[pid]))
	return best
