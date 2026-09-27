extends MiniGame
## Ping Pong para 2: la mesa es vertical en el centro de la TV.
## El celular muestra un slider horizontal: la posición del dedo es la
## posición de la paleta (control absoluto, no velocidad).

const POINTS_TO_WIN := 5
const TABLE := Rect2(610, 130, 700, 900)
const PADDLE_SIZE := Vector2(150, 22)
const PADDLE_MARGIN := 50.0
const BALL_RADIUS := 16.0
const BALL_START_SPEED := 620.0
const BALL_SPEEDUP := 1.06
const PADDLE_FOLLOW := 18.0  ## Suavizado: evita saltos si llegan inputs con jitter.

var _paddle_x: Dictionary = {}   # player_id -> x actual
var _target_x: Dictionary = {}   # player_id -> x objetivo (del slider)
var _score: Dictionary = {}
var _top_id := 0
var _bottom_id := 0
var _ball := Vector2.ZERO
var _vel := Vector2.ZERO
var _serve_delay := 1.0
var _rng := RandomNumberGenerator.new()


static func get_info() -> Dictionary:
	return {
		"id": "pingpong",
		"title": "Ping Pong",
		"description": "Deslizá el dedo para mover la paleta. Gana el primero en llegar a 5.",
		"min_players": 2,
		"max_players": 2,
		"layout": Protocol.LAYOUT_SLIDER_H,
		"layout_data": {},
		"accent": Color("#2EC4D6"),
		"score_label": "puntos",
	}


func setup(p_players: Array[Dictionary]) -> void:
	super.setup(p_players)
	_rng.randomize()
	_top_id = players[0].id
	_bottom_id = players[1].id
	for p in players:
		_paddle_x[p.id] = TABLE.get_center().x
		_target_x[p.id] = TABLE.get_center().x
		_score[p.id] = 0
	_reset_ball(1 if _rng.randf() < 0.5 else -1)


func on_input(player_id: int, input: Dictionary) -> void:
	if not _target_x.has(player_id):
		return
	var half := PADDLE_SIZE.x / 2.0
	# Sin invertir el eje del jugador de arriba: los dos miran la misma TV
	# desde el sillón, así que "derecha" es la misma para ambos.
	var t := ((input.axis as Vector2).x + 1.0) / 2.0
	_target_x[player_id] = lerpf(TABLE.position.x + half, TABLE.end.x - half, t)


func _physics_process(delta: float) -> void:
	if is_finished():
		return
	for pid: int in _paddle_x:
		_paddle_x[pid] = lerpf(_paddle_x[pid], _target_x[pid], clampf(PADDLE_FOLLOW * delta, 0.0, 1.0))
	if _serve_delay > 0.0:
		_serve_delay -= delta
	else:
		_step_ball(delta)
	queue_redraw()


func _step_ball(delta: float) -> void:
	_ball += _vel * delta
	if _ball.x < TABLE.position.x + BALL_RADIUS or _ball.x > TABLE.end.x - BALL_RADIUS:
		_vel.x = -_vel.x
		_ball.x = clampf(_ball.x, TABLE.position.x + BALL_RADIUS, TABLE.end.x - BALL_RADIUS)
	_check_paddle(_top_id, TABLE.position.y + PADDLE_MARGIN, 1)
	_check_paddle(_bottom_id, TABLE.end.y - PADDLE_MARGIN, -1)
	if _ball.y < TABLE.position.y:
		_point(_bottom_id, 1)
	elif _ball.y > TABLE.end.y:
		_point(_top_id, -1)


## dir = dirección vertical en la que la paleta devuelve la pelota.
func _check_paddle(pid: int, y: float, dir: int) -> void:
	if signf(_vel.y) == dir:
		return
	if absf(_ball.y - y) > BALL_RADIUS + PADDLE_SIZE.y / 2.0:
		return
	var offset := (_ball.x - float(_paddle_x[pid])) / (PADDLE_SIZE.x / 2.0)
	if absf(offset) > 1.15:
		return
	var speed := _vel.length() * BALL_SPEEDUP
	# Pegarle con el borde de la paleta desvía más la pelota.
	_vel = Vector2(offset * 0.8, dir).normalized() * speed
	play_sfx("pong", 1.0 + minf(speed / BALL_START_SPEED - 1.0, 0.5))
	notify_player(pid, "tap")
	_ball.y = y + dir * (BALL_RADIUS + PADDLE_SIZE.y / 2.0)


func _point(winner_id: int, next_dir: int) -> void:
	_score[winner_id] += 1
	play_sfx("point")
	notify_player(winner_id, "point")
	notify_player(_bottom_id if winner_id == _top_id else _top_id, "lose")
	if _score[winner_id] >= POINTS_TO_WIN:
		finish(result_from_scores(_score, "Primero a %d puntos" % POINTS_TO_WIN))
		return
	_reset_ball(next_dir)


func _reset_ball(dir: int) -> void:
	_ball = TABLE.get_center()
	_vel = Vector2(_rng.randf_range(-0.5, 0.5), dir).normalized() * BALL_START_SPEED
	_serve_delay = 1.0


func _draw() -> void:
	draw_sky()
	draw_static(_draw_table)
	for pid: int in [_top_id, _bottom_id]:
		var p := player_by_id(pid)
		var top := pid == _top_id
		var y := TABLE.position.y + PADDLE_MARGIN if top else TABLE.end.y - PADDLE_MARGIN
		var rect := Rect2(Vector2(_paddle_x[pid] - PADDLE_SIZE.x / 2.0, y - PADDLE_SIZE.y / 2.0), PADDLE_SIZE)
		UiTheme.draw_round_rect(self, rect.grow(4), UiTheme.INK, 14)
		UiTheme.draw_round_rect(self, rect, p.color, 11)
		# Mascota y nombre al costado de su lado de la mesa
		var side := _mascot_feet(top)
		# Siguen la pelota con la mirada.
		var look := (_ball - (side + Vector2(0, -80))).normalized()
		PlayerAvatar.draw_mascot(self, side, 1.6, p.color, PlayerAvatar.style_of(p),
			PlayerAvatar.Mood.HAPPY if _score[pid] > _score[_other(pid)] else PlayerAvatar.Mood.NORMAL,
			0.0, 0.0, false, {"t": anim_time + p.slot, "look": look})
	UiTheme.draw_ellipse(self, _ball + Vector2(6, 10), BALL_RADIUS, BALL_RADIUS * 0.7, Color(0, 0, 0, 0.25))
	draw_circle(_ball, BALL_RADIUS + 3.0, UiTheme.INK)
	draw_circle(_ball, BALL_RADIUS, Color.WHITE)
	draw_hud(_score, "Gana: %d" % POINTS_TO_WIN, "star")


## Lo fijo (se dibuja una vez, ver MiniGame.draw_static): la mesa con canto
## y sombra proyectada (flota sobre el escenario, como el tablero), sus líneas
## y la red, y el globito 1P–2P y el nombre de cada mascota (no se mueven).
func _draw_table(ci: CanvasItem) -> void:
	GameArt.draw_drop_shadow(ci, TABLE.grow(22).grow_side(SIDE_BOTTOM, 18))
	UiTheme.draw_round_rect(ci, TABLE.grow(22).grow_side(SIDE_BOTTOM, 18), UiTheme.INK, 30)
	UiTheme.draw_round_rect(ci, TABLE.grow(18).grow_side(SIDE_BOTTOM, 10), UiTheme.TABLE_BLUE_DARK.darkened(0.35), 26)
	UiTheme.draw_round_rect(ci, TABLE.grow(18), UiTheme.TABLE_BLUE_DARK, 26)
	ci.draw_rect(TABLE, UiTheme.TABLE_BLUE)
	ci.draw_rect(TABLE, UiTheme.PAPER, false, 6.0)
	ci.draw_line(Vector2(TABLE.get_center().x, TABLE.position.y), Vector2(TABLE.get_center().x, TABLE.end.y), Color(UiTheme.PAPER, 0.5), 3.0)
	var net_y := TABLE.get_center().y
	ci.draw_line(Vector2(TABLE.position.x - 24, net_y), Vector2(TABLE.end.x + 24, net_y), UiTheme.INK, 10.0)
	ci.draw_line(Vector2(TABLE.position.x - 24, net_y), Vector2(TABLE.end.x + 24, net_y), UiTheme.PAPER, 5.0)
	var tags: Array = []
	for pid: int in [_top_id, _bottom_id]:
		var p := player_by_id(pid)
		var side := _mascot_feet(pid == _top_id)
		tags.append([p.slot, p.color, p.name, side, 1.6, -1.0, 1.0])
		UiTheme.draw_text(ci, p.name, side + Vector2(0, 40), 40, UiTheme.PAPER, 8, UiTheme.INK)
	GameArt.draw_player_tags(ci, tags)


## Dónde apoya la mascota de cada lado: al costado de su mitad de la mesa.
static func _mascot_feet(top: bool) -> Vector2:
	return Vector2(TABLE.end.x + 250, TABLE.position.y + 260 if top else TABLE.end.y - 90)


func _other(pid: int) -> int:
	return _bottom_id if pid == _top_id else _top_id
