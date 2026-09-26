extends MiniGame
## Carrera de toques: cada toque del botón avanza tu auto. El primero en
## llegar a la meta gana. Cuenta solo "flancos de subida" (soltar y volver a
## tocar), así mantener el dedo apretado no suma.

const TAPS_TO_WIN := 40
const MAX_TAPS_PER_SEC := 14  ## Tope humano: frena scripts o controles trucados.
const TRACK_LEFT := 260.0
const TRACK_RIGHT := 1700.0
const LANE_HEIGHT := 180.0

var _taps: Dictionary = {}       # player_id -> int
var _was_down: Dictionary = {}   # player_id -> bool
var _tap_times: Dictionary = {}  # player_id -> Array[int] (ms del último segundo)
var _countdown := 3.0


static func get_info() -> Dictionary:
	return {
		"id": "tap_race",
		"title": "Carrera de toques",
		"description": "Tocá el botón lo más rápido que puedas. Primero en llegar a la meta gana.",
		"min_players": 1,
		"max_players": 4,
		"layout": Protocol.LAYOUT_ONE_BUTTON,
		"layout_data": {"label": "¡TOCÁ!"},
	}


func setup(p_players: Array[Dictionary]) -> void:
	super.setup(p_players)
	for p in players:
		_taps[p.id] = 0
		_was_down[p.id] = false
		_tap_times[p.id] = []


func on_input(player_id: int, input: Dictionary) -> void:
	if not _taps.has(player_id) or is_finished():
		return
	var down := (int(input.btn) & Protocol.BTN_A) != 0
	if down and not _was_down[player_id] and _countdown <= 0.0:
		_register_tap(player_id)
	_was_down[player_id] = down


func _register_tap(player_id: int) -> void:
	var now := Time.get_ticks_msec()
	var times: Array = _tap_times[player_id]
	while not times.is_empty() and now - int(times[0]) > 1000:
		times.pop_front()
	if times.size() >= MAX_TAPS_PER_SEC:
		return
	times.append(now)
	_taps[player_id] += 1
	if _taps[player_id] >= TAPS_TO_WIN:
		finish({"winners": [player_id], "scores": _taps.duplicate(), "summary": "Primero en la meta"})


func _physics_process(delta: float) -> void:
	if _countdown > -1.0:
		_countdown -= delta
	queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, SCREEN), Color("#2C2C2A"))
	var top := (SCREEN.y - LANE_HEIGHT * players.size()) / 2.0
	draw_line(Vector2(TRACK_RIGHT, top - 20), Vector2(TRACK_RIGHT, top + LANE_HEIGHT * players.size() + 20), Color.WHITE, 8.0)
	for i in players.size():
		var p: Dictionary = players[i]
		var y := top + LANE_HEIGHT * i + LANE_HEIGHT / 2.0
		draw_line(Vector2(TRACK_LEFT, y + LANE_HEIGHT / 2.0), Vector2(TRACK_RIGHT, y + LANE_HEIGHT / 2.0), Color("#444441"), 2.0)
		var progress := float(_taps[p.id]) / TAPS_TO_WIN
		var x := lerpf(TRACK_LEFT, TRACK_RIGHT - 60.0, progress)
		draw_rect(Rect2(x - 50, y - 30, 100, 60), p.color)
		draw_string(ThemeDB.fallback_font, Vector2(40, y + 12), p.name, HORIZONTAL_ALIGNMENT_LEFT, 200, 32, p.color)
	if _countdown > 0.0:
		draw_text_centered("%d" % ceili(_countdown), SCREEN / 2.0, 200)
	elif _countdown > -0.8:
		draw_text_centered("¡YA!", SCREEN / 2.0, 200, Color("#FAC775"))
