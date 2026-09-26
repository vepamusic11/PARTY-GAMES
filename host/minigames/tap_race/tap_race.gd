extends MiniGame
## Carrera de toques: cada toque del botón avanza tu auto. El primero en
## llegar a la meta gana. Cuenta solo "flancos de subida" (soltar y volver a
## tocar), así mantener el dedo apretado no suma.

const TAPS_TO_WIN := 40
const MAX_TAPS_PER_SEC := 14  ## Tope humano: frena scripts o controles trucados.
const TRACK_LEFT := 320.0
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
		"accent": Color("#FF9F2E"),
		"score_label": "toques",
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
		play_sfx("win")
		notify_player(player_id, "win")
		finish({"winners": [player_id], "scores": _taps.duplicate(), "summary": "Primero en la meta"})


func _physics_process(delta: float) -> void:
	if _countdown > -1.0:
		var before := _countdown
		_countdown -= delta
		tick_countdown(before, _countdown)
	queue_redraw()


func _draw() -> void:
	draw_sky()
	var lanes := Rect2(TRACK_LEFT - 40, (SCREEN.y - LANE_HEIGHT * players.size()) / 2.0 + 40, TRACK_RIGHT - TRACK_LEFT + 140, LANE_HEIGHT * players.size())
	draw_play_field(lanes, LANE_HEIGHT / 2.0)
	# Meta a cuadros
	var cell := 30.0
	var fy := lanes.position.y
	var k := 0
	while fy < lanes.end.y:
		for c in 2:
			draw_rect(Rect2(TRACK_RIGHT + c * cell, fy, cell, minf(cell, lanes.end.y - fy)), UiTheme.INK if (k + c) % 2 == 0 else Color.WHITE)
		fy += cell
		k += 1
	for i in players.size():
		var p: Dictionary = players[i]
		var y := lanes.position.y + LANE_HEIGHT * i
		if i > 0:
			UiTheme.draw_dashed_line(self, Vector2(lanes.position.x, y), Vector2(TRACK_RIGHT, y), Color(UiTheme.INK, 0.25), 4.0, 24.0, 16.0)
		var progress := float(_taps[p.id]) / TAPS_TO_WIN
		var x := lerpf(TRACK_LEFT + 20.0, TRACK_RIGHT - 30.0, progress)
		var hop := absf(sin(float(_taps[p.id]) * PI / 2.0)) * 6.0
		PlayerAvatar.draw_mascot(self, Vector2(x, y + LANE_HEIGHT - 16), 1.3, p.color, p.slot,
			PlayerAvatar.Mood.HAPPY if _taps[p.id] >= TAPS_TO_WIN else PlayerAvatar.Mood.NORMAL, 0.0, hop, false,
			# Cada toque es medio paso: la mascota corre al ritmo del dedo.
			{"t": anim_time + p.slot, "walk": _taps[p.id] * 0.5 if _taps[p.id] > 0 else -1.0,
				"look": Vector2(1, 0), "wave": _taps[p.id] >= TAPS_TO_WIN})
		var tag := Rect2(24, y + LANE_HEIGHT / 2.0 - 30, lanes.position.x - 60, 60)
		UiTheme.draw_round_rect(self, tag.grow(3), UiTheme.INK, 30)
		UiTheme.draw_round_rect(self, tag, p.color, 28)
		UiTheme.draw_text_left(self, p.name, Vector2(tag.position.x + 18, tag.get_center().y), 28, UiTheme.PAPER, tag.size.x - 30)
	var center := "Meta: %d" % TAPS_TO_WIN
	draw_hud(_taps, center)
	if _countdown > 0.0:
		draw_text_centered("%d" % ceili(_countdown), SCREEN / 2.0, 260, UiTheme.PAPER, 22)
	elif _countdown > -0.8:
		draw_text_centered("¡YA!", SCREEN / 2.0, 260, UiTheme.ACCENT, 22)
