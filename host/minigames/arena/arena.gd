extends MiniGame
## Arena: cada jugador mueve un círculo con el joystick y junta estrellas.
## Es el prototipo técnico: sirve para sentir la latencia real del control.

const DURATION_SEC := 30.0
const SPEED := 620.0
const RADIUS := 36.0
const STAR_RADIUS := 22.0
const STAR_COUNT := 5
const ARENA := Rect2(160, 140, 1600, 860)

var _pos: Dictionary = {}     # player_id -> Vector2
var _axis: Dictionary = {}    # player_id -> Vector2
var _score: Dictionary = {}   # player_id -> int
var _stars: Array[Vector2] = []
var _time_left := DURATION_SEC
var _rng := RandomNumberGenerator.new()


static func get_info() -> Dictionary:
	return {
		"id": "arena",
		"title": "Arena de estrellas",
		"description": "Mové tu círculo y juntá la mayor cantidad de estrellas en 30 segundos.",
		"min_players": 1,
		"max_players": 4,
		"layout": Protocol.LAYOUT_JOYSTICK,
		"layout_data": {},
		"accent": Color("#3E7BFA"),
		"score_label": "estrellas",
	}


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


func on_input(player_id: int, input: Dictionary) -> void:
	if _axis.has(player_id):
		_axis[player_id] = input.axis


func _physics_process(delta: float) -> void:
	if is_finished():
		return
	_time_left -= delta
	for pid: int in _pos:
		var p: Vector2 = _pos[pid] + (_axis[pid] as Vector2) * SPEED * delta
		p.x = clampf(p.x, ARENA.position.x + RADIUS, ARENA.end.x - RADIUS)
		p.y = clampf(p.y, ARENA.position.y + RADIUS, ARENA.end.y - RADIUS)
		_pos[pid] = p
		for i in _stars.size():
			if p.distance_to(_stars[i]) < RADIUS + STAR_RADIUS:
				_score[pid] += 1
				_stars[i] = _random_star()
				play_sfx("point", 1.0 + 0.04 * p.x / SCREEN.x)
				notify_player(pid, "point")
	queue_redraw()
	if _time_left <= 0.0:
		finish(result_from_scores(_score, "Más estrellas gana"))


func _random_star() -> Vector2:
	var margin := 60.0
	return Vector2(
		_rng.randf_range(ARENA.position.x + margin, ARENA.end.x - margin),
		_rng.randf_range(ARENA.position.y + margin, ARENA.end.y - margin))


func _draw() -> void:
	draw_sky()
	draw_play_field(ARENA)
	var spin := Time.get_ticks_msec() / 1000.0
	for i in _stars.size():
		UiTheme.draw_star(self, _stars[i], STAR_RADIUS + 6.0, UiTheme.GOLD, sin(spin * 2.0 + i) * 0.25)
	# Se dibuja de arriba hacia abajo: el que está más abajo queda "adelante".
	var order := players.duplicate()
	order.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return (_pos[a.id] as Vector2).y < (_pos[b.id] as Vector2).y)
	for p in order:
		var pos: Vector2 = _pos[p.id]
		var moving := (_axis[p.id] as Vector2).length() > 0.1
		var bob := sin(spin * 14.0) * 3.0 if moving else 0.0
		PlayerAvatar.draw_mascot(self, pos + Vector2(0, RADIUS), 0.8, p.color, p.slot, PlayerAvatar.Mood.NORMAL, 0.0, absf(bob))
		draw_text_centered(p.name, pos + Vector2(0, RADIUS + 24), 26, UiTheme.PAPER, 6)
	draw_hud(_score, clock_text(_time_left))
