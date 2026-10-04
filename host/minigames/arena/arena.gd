extends MiniGame
## Arena: cada jugador mueve un círculo con el joystick y junta estrellas.
## Es el prototipo técnico: sirve para sentir la latencia real del control.
##
## Escenario 2.5D (ADR 0019, como Pintar el piso): si hay render, el tablero
## y los juguetes de alrededor son una escena 3D horneada una vez con cámara
## en perspectiva y el juego se dibuja encima proyectado: las mascotas
## paradas en su punto del piso (más chicas atrás, ordenadas de atrás hacia
## adelante) y las estrellas flotando sobre su sombra. Las reglas, los
## choques y los bots siguen en las coordenadas planas de ARENA. Sin render
## (--headless) o mientras se hornea, se dibuja plano como siempre.

const DURATION_SEC := 30.0
const COUNTDOWN_SEC := 3.0        ## "3, 2, 1, ¡YA!": tiempo para encontrar tu mascota antes de moverse.
const GO_SEC := 0.8               ## Cuánto se ve "¡YA!" después del 1.
const SPEED := 620.0
const RADIUS := 36.0
const STAR_RADIUS := 22.0
const STAR_COUNT := 5
## Una estrella nueva no nace a menos de esto de ninguna mascota: si naciera
## encima, alguien se lleva un punto sin moverse (o, en la cuenta regresiva,
## la tiene servida al "¡YA!"). Pasaba en ~1 de cada 300 partidas.
const STAR_CLEAR_PX := 150.0
const STAR_TRIES := 12
const ARENA := Rect2(160, 140, 1600, 860)
const CELL := 80.0                ## Baldosas del tablero (solo dibujo).
const MASCOT_SCALE := 0.8
const NAME_OFFSET := 24.0

var _pos: Dictionary = {}     # player_id -> Vector2
var _axis: Dictionary = {}    # player_id -> Vector2
var _score: Dictionary = {}   # player_id -> int
var _stars: Array[Vector2] = []
var _star_born: Array[float] = []   # anim_time en que apareció cada estrella (entra con rebote)
var _time_left := DURATION_SEC
var _countdown := COUNTDOWN_SEC
var _rng := RandomNumberGenerator.new()

## Vista 2.5D del campo (una por proceso) y si este cuadro se dibuja con ella.
static var _board_view: BoardView25D
var _v25 := false


static func get_info() -> Dictionary:
	return {
		"id": "arena",
		"title": "Arena de estrellas",
		"description": "Mové tu mascota con el joystick y juntá estrellas. A los 30 segundos gana quien tenga más.",
		"min_players": 1,
		"max_players": 4,
		"layout": Protocol.LAYOUT_JOYSTICK,
		"layout_data": {"hint": "Movete y juntá las estrellas"},
		"accent": Color("#3E7BFA"),
		"score_label": "estrellas",
	}


## Cámara y proyección del escenario 2.5D (ADR 0019): el campo encuadrado
## como el de Pintar el piso (BoardView25D.make_fit).
static func board_view() -> BoardView25D:
	if _board_view == null:
		_board_view = BoardView25D.make_fit(ARENA, CELL, "arena")
	return _board_view


## Durante la intro: el escenario 2.5D se lee del disco o se hornea.
static func prewarm_art(host: Node, _players: Array = []) -> void:
	Board25DBaker.request(host, board_view())


func setup(p_players: Array[Dictionary]) -> void:
	super.setup(p_players)
	_rng.randomize()
	var corners := [ARENA.position + Vector2(120, 120), ARENA.end - Vector2(120, 120),
		Vector2(ARENA.end.x - 120, ARENA.position.y + 120), Vector2(ARENA.position.x + 120, ARENA.end.y - 120)]
	for p in players:
		_pos[p.id] = corners[p.slot % corners.size()]
		_axis[p.id] = Vector2.ZERO
		_score[p.id] = 0
	for i in STAR_COUNT:
		_stars.append(_random_star())
		_star_born.append(-1.0)


func on_input(player_id: int, input: Dictionary) -> void:
	if _axis.has(player_id):
		_axis[player_id] = input.axis


## Para los bots (ver MiniGame.bot_view): mascotas y estrellas. Solo lectura.
func bot_view() -> Dictionary:
	return {"pos": _pos, "stars": _stars, "field": ARENA, "speed": SPEED, "time_left": _time_left, "countdown": _countdown}


func _physics_process(delta: float) -> void:
	if is_finished():
		return
	if in_finale():  # "¡Tiempo!": quietos, los ganadores festejan.
		for pid: int in _pos:
			advance_walk(pid, 0.0, delta)
		request_redraw()
		return
	if _countdown > -GO_SEC:
		var before := _countdown
		_countdown -= delta
		tick_countdown(before, _countdown)
	if _countdown > 0.0:
		request_redraw()
		return  # Nadie se mueve hasta el "¡YA!": tiempo para encontrar tu mascota.
	_time_left -= delta
	# Orden al azar en cada paso: si dos tocan la misma estrella a la vez, no
	# gana siempre 1P (lo encontró tools/simulate.gd con bots: 1P ganaba la
	# mitad de las partidas entre bots iguales; ver ADR 0010).
	var order := _pos.keys()
	order.shuffle()
	for pid: int in order:
		var p: Vector2 = _pos[pid] + (_axis[pid] as Vector2) * SPEED * delta
		advance_walk(pid, (_axis[pid] as Vector2).length(), delta, 3.0)
		p.x = clampf(p.x, ARENA.position.x + RADIUS, ARENA.end.x - RADIUS)
		p.y = clampf(p.y, ARENA.position.y + RADIUS, ARENA.end.y - RADIUS)
		_pos[pid] = p
		juice().stop_dust(pid, (_axis[pid] as Vector2).length(), _feet(p))
		for i in _stars.size():
			if p.distance_to(_stars[i]) < RADIUS + STAR_RADIUS:
				_score[pid] += 1
				_collect_fx(pid, _stars[i])
				_stars[i] = _random_star()
				_star_born[i] = anim_time
				play_sfx("point", 1.0 + 0.04 * p.x / SCREEN.x)
				notify_player(pid, "point")
	request_redraw()
	if _time_left <= 0.0:
		_time_left = 0.0
		var result := result_from_scores(_score, "Más estrellas gana")
		var winners := {}
		for pid: int in result.winners:
			winners[pid] = _feet(_pos[pid])
		finish_after(result, "¡Tiempo!", winners)


## Brillo al juntar una estrella: estrellitas, anillo de luz y "+1" del color
## del jugador (solo efectos: el puntaje ya se sumó).
func _collect_fx(pid: int, at: Vector2) -> void:
	var star := _star_center(at)
	juice().sparkles(star)
	juice().shine(star)
	# Arriba del globito 1P–4P (que no lo tape).
	var head := _feet(_pos[pid]) + Vector2(0, -130 - RADIUS) * _depth(_pos[pid])
	juice().float_text("+1", head, player_by_id(pid).get("color", UiTheme.GOLD))


func _star_bob(i: int) -> Vector2:
	return Vector2(0, sin(anim_time * 3.0 + i) * 3.0)


func _star_grow(i: int) -> float:
	return UiTheme.appear_scale(anim_time - _star_born[i]) if _star_born[i] >= 0.0 else 1.0


func _random_star() -> Vector2:
	var margin := 60.0
	var star := Vector2.ZERO
	for i in STAR_TRIES:  # Con 4 mascotas casi siempre sale al primer intento.
		star = Vector2(
			_rng.randf_range(ARENA.position.x + margin, ARENA.end.x - margin),
			_rng.randf_range(ARENA.position.y + margin, ARENA.end.y - margin))
		if _clear_of_players(star):
			break
	return star


func _clear_of_players(star: Vector2) -> bool:
	for pid: int in _pos:
		if (_pos[pid] as Vector2).distance_to(star) < STAR_CLEAR_PX:
			return false
	return true


func _draw() -> void:
	_v25 = draw_board_25d(board_view())
	if not _v25:
		draw_sky()
		draw_play_field(ARENA)
	# Estrellas con halo: todas en un lote (un draw call), halos primero. En
	# 2.5D flotan sobre su punto del piso, con una sombra acostada debajo.
	var batch := GameArt.TriBatch.new()
	if _v25:
		var shadows := GameArt.TriBatch.new()
		for i in _stars.size():
			var r := (STAR_RADIUS + 4.0) * _star_grow(i) * (0.9 - 0.08 * sin(anim_time * 3.0 + i))
			shadows.ellipse(_stars[i], r, r * 0.7, UiTheme.BOARD25D_POWER_SHADOW)
		batch.points = board_view().project_points(shadows.points)
		batch.colors = shadows.colors
	for i in _stars.size():
		var d := _depth(_stars[i])
		GameArt.add_glow(batch, _star_center(_stars[i]), (STAR_RADIUS + 26.0) * d, UiTheme.GLOW, anim_time + i * 0.7, 8)
	var use_3d := Props3D.is_ready()
	if not use_3d:
		for i in _stars.size():
			var grow := _star_grow(i)
			if grow > 0.01:
				batch.star(_star_center(_stars[i]) + _star_bob(i), (STAR_RADIUS + 6.0) * grow * _depth(_stars[i]), UiTheme.GOLD,
					sin(anim_time * 2.0 + i) * 0.25)
	batch.flush(self)
	if use_3d:
		# Estrellas 3D horneadas (Props3D): mismo atlas -> un draw call entre las 5.
		var r := STAR_RADIUS + 8.0
		for i in _stars.size():
			var grow := _star_grow(i) * _depth(_stars[i])
			if grow > 0.01:
				draw_set_transform(_star_center(_stars[i]) + _star_bob(i), sin(anim_time * 2.0 + i) * 0.25, Vector2(grow, grow))
				Props3D.draw(self, "star", Rect2(-r, -r, r * 2.0, r * 2.0))
		draw_set_transform(Vector2.ZERO)
	# Se dibuja de arriba hacia abajo: el que está más abajo queda "adelante".
	var order := players.duplicate()
	order.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return (_pos[a.id] as Vector2).y < (_pos[b.id] as Vector2).y)
	for p in order:
		var pos: Vector2 = _pos[p.id]
		var party := is_celebrating(p.id)
		var anim := mascot_anim(p.id, _axis[p.id])
		anim["wave"] = party
		PlayerAvatar.draw_mascot(self, _feet(pos), MASCOT_SCALE * _depth(pos), p.color, PlayerAvatar.style_of(p),
			PlayerAvatar.Mood.HAPPY if party else PlayerAvatar.Mood.NORMAL, 0.0, celebrate_hop(p.id), false, anim)
	# Globitos 1P–4P y nombres encima de todas las mascotas; al arrancar, la
	# flecha "¿cuál soy yo?" de cada uno.
	var tags: Array = order.map(func(p: Dictionary) -> Array:
		var d := _depth(_pos[p.id])
		return [p, _feet(_pos[p.id]), MASCOT_SCALE * d, NAME_OFFSET * d])
	draw_player_tags(tags)
	draw_start_markers(tags)
	draw_hud(_score, clock_text(_time_left), "clock")
	draw_countdown(_countdown, GO_SEC)


## Pies de la mascota en la pantalla. Plano: abajo del círculo de choque
## (como siempre). 2.5D: parada en su punto del piso, proyectado.
func _feet(pos: Vector2) -> Vector2:
	return board_view().project(pos) if _v25 else pos + Vector2(0, RADIUS)


## Centro de una estrella en la pantalla: en 2.5D flota sobre su punto del
## piso (se ve dónde está: su sombra); plano, en su lugar.
func _star_center(at: Vector2) -> Vector2:
	if not _v25:
		return at
	return board_view().project(at) - Vector2(0, STAR_RADIUS + 8.0 + UiTheme.BOARD25D_POWER_HOVER) * _depth(at)


## Escala de lo que está parado en `p`: más chico atrás en 2.5D; 1 en plano.
func _depth(p: Vector2) -> float:
	if not _v25:
		return 1.0
	return clampf(board_view().scale_at(p), UiTheme.BOARD25D_SCALE_MIN, UiTheme.BOARD25D_SCALE_MAX)
