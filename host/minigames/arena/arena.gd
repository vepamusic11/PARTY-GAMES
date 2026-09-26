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
	queue_redraw()
	if _time_left <= 0.0:
		finish(result_from_scores(_score, "Más estrellas gana"))


func _random_star() -> Vector2:
	var margin := 60.0
	return Vector2(
		_rng.randf_range(ARENA.position.x + margin, ARENA.end.x - margin),
		_rng.randf_range(ARENA.position.y + margin, ARENA.end.y - margin))


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, SCREEN), Color("#1b1b2f"))
	draw_rect(ARENA, Color("#26264a"))
	draw_rect(ARENA, Color("#5a5a9a"), false, 4.0)
	draw_text_centered("%d" % ceili(maxf(_time_left, 0.0)), Vector2(ARENA.end.x - 40, 70), 64, Color("#FAC775"))
	for s in _stars:
		draw_circle(s, STAR_RADIUS, Color("#FAC775"))
	var hud_x := 200.0
	for p in players:
		var col: Color = p.color
		draw_circle(_pos[p.id], RADIUS, col)
		draw_string(ThemeDB.fallback_font, Vector2(hud_x, 80), "%s: %d" % [p.name, _score[p.id]],
			HORIZONTAL_ALIGNMENT_LEFT, -1, 32, col)
		hud_x += 360.0
