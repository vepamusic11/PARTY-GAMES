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
## Reloj del juego en ms (suma de los delta de _physics_process): el tope de
## toques por segundo se mide en tiempo de juego, así una pausa no lo altera
## y las simulaciones aceleradas (tools/simulate.gd) dan lo mismo que en vivo.
var _clock_ms := 0.0
## Meta, separadores y carteles de los carriles: no cambian en toda la
## carrera, así que el lote de triángulos se arma una sola vez y en cada frame
## solo se vuelve a mandar (ver _draw).
var _track := GameArt.TriBatch.new()


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
	if not _taps.has(player_id) or is_finished() or in_finale():
		return
	var down := (int(input.btn) & Protocol.BTN_A) != 0
	if down and not _was_down[player_id] and _countdown <= 0.0:
		_register_tap(player_id)
	_was_down[player_id] = down


## Para los bots (ver MiniGame.bot_view): cuenta regresiva y toques. Solo lectura.
func bot_view() -> Dictionary:
	return {"countdown": _countdown, "taps": _taps, "goal": TAPS_TO_WIN}


func _register_tap(player_id: int) -> void:
	var now := int(_clock_ms)
	var times: Array = _tap_times[player_id]
	while not times.is_empty() and now - int(times[0]) > 1000:
		times.pop_front()
	if times.size() >= MAX_TAPS_PER_SEC:
		return
	times.append(now)
	_taps[player_id] += 1
	# Cada toque levanta un poco de polvo detrás de la mascota.
	var feet := _feet_of(player_id)
	juice().dust(feet + Vector2(-24, -6), 2, Vector2(-1, -0.4), 10.0)
	if _taps[player_id] >= TAPS_TO_WIN:
		play_sfx("win")
		notify_player(player_id, "win")
		finish_after({"winners": [player_id], "scores": _taps.duplicate(), "summary": "Primero en la meta"},
			"¡Meta!", {player_id: feet}, "")


## Pies de la mascota del jugador en su carril (mismas cuentas que _draw).
func _feet_of(player_id: int) -> Vector2:
	for i in players.size():
		if players[i].id == player_id:
			var y := _lanes().position.y + LANE_HEIGHT * i
			var x := lerpf(TRACK_LEFT + 20.0, TRACK_RIGHT - 30.0, float(_taps[player_id]) / TAPS_TO_WIN)
			return Vector2(x, y + LANE_HEIGHT - 16)
	return Vector2.ZERO


func _lanes() -> Rect2:
	return Rect2(TRACK_LEFT - 40, (SCREEN.y - LANE_HEIGHT * players.size()) / 2.0 + 40, TRACK_RIGHT - TRACK_LEFT + 140, LANE_HEIGHT * players.size())


func _physics_process(delta: float) -> void:
	_clock_ms += delta * 1000.0
	if _countdown > -1.0:
		var before := _countdown
		_countdown -= delta
		tick_countdown(before, _countdown)
	queue_redraw()


func _draw() -> void:
	draw_sky()
	var lanes := _lanes()
	draw_play_field(lanes, LANE_HEIGHT / 2.0)
	# Meta a cuadros, separadores de carril y carteles con el nombre: todo en
	# un lote (un draw call) armado una vez; los textos y las mascotas van después.
	if _track.points.is_empty():
		_build_track(lanes)
	_track.draw(self)
	for i in players.size():
		var p: Dictionary = players[i]
		var y := lanes.position.y + LANE_HEIGHT * i
		var progress := float(_taps[p.id]) / TAPS_TO_WIN
		var x := lerpf(TRACK_LEFT + 20.0, TRACK_RIGHT - 30.0, progress)
		var hop := absf(sin(float(_taps[p.id]) * PI / 2.0)) * 6.0 + celebrate_hop(p.id)
		PlayerAvatar.draw_mascot(self, Vector2(x, y + LANE_HEIGHT - 16), 1.3, p.color, PlayerAvatar.style_of(p),
			PlayerAvatar.Mood.HAPPY if _taps[p.id] >= TAPS_TO_WIN else PlayerAvatar.Mood.NORMAL, 0.0, hop, false,
			# Cada toque es medio paso: la mascota corre al ritmo del dedo.
			{"t": anim_time + p.slot, "walk": _taps[p.id] * 0.5 if _taps[p.id] > 0 else -1.0,
				"look": Vector2(1, 0), "wave": _taps[p.id] >= TAPS_TO_WIN})
		var tag := _lane_tag(lanes, i)
		UiTheme.draw_text(self, UiTheme.player_tag(p.slot), Vector2(tag.position.x + 33.0, tag.get_center().y - 2.0), 26, UiTheme.PAPER)
		UiTheme.draw_text_left(self, p.name, Vector2(tag.position.x + 68.0, tag.get_center().y - 2.0), 26,
			UiTheme.text_on(p.color), tag.end.x - 16.0 - (tag.position.x + 68.0))
	var center := "Meta: %d" % TAPS_TO_WIN
	draw_hud(_taps, center, "flag")
	draw_countdown(_countdown)


## Cartel del carril `i`: a la izquierda de la pista.
func _lane_tag(lanes: Rect2, i: int) -> Rect2:
	var y := lanes.position.y + LANE_HEIGHT * i
	return Rect2(UiTheme.SAFE_MARGIN, y + LANE_HEIGHT / 2.0 - 32.0, lanes.position.x - UiTheme.SAFE_MARGIN - 60.0, 64.0)


func _build_track(lanes: Rect2) -> void:
	var batch := _track
	var cell := 30.0
	batch.rect(Rect2(TRACK_RIGHT - 4.0, lanes.position.y, cell * 2.0 + 8.0, lanes.size.y), UiTheme.INK)
	var fy := lanes.position.y
	var k := 0
	while fy < lanes.end.y:
		for c in 2:
			batch.rect(Rect2(TRACK_RIGHT + c * cell, fy, cell, minf(cell, lanes.end.y - fy)), UiTheme.INK if (k + c) % 2 == 0 else UiTheme.PAPER)
		fy += cell
		k += 1
	for i in players.size():
		var y := lanes.position.y + LANE_HEIGHT * i
		if i > 0:
			var x := lanes.position.x
			while x < TRACK_RIGHT - 8.0:
				batch.line(Vector2(x, y), Vector2(minf(x + 24.0, TRACK_RIGHT - 8.0), y), Color(UiTheme.INK, 0.25), 4.0)
				x += 40.0
		# Cartel del carril: [1P | nombre] del color del jugador, con relieve.
		var tag := _lane_tag(lanes, i)
		var col: Color = players[i].color
		batch.capsule(tag.grow(4.0).grow_side(SIDE_BOTTOM, 3.0), UiTheme.INK)
		batch.capsule(tag, col.darkened(0.3))
		batch.capsule(Rect2(tag.position, tag.size - Vector2(0, 6.0)), col)
		batch.capsule(Rect2(tag.position + Vector2(14.0, 4.0), Vector2(tag.size.x * 0.6, 14.0)), Color(1, 1, 1, 0.3))
		batch.capsule(Rect2(tag.position + Vector2(7.0, 9.0), Vector2(52.0, tag.size.y - 20.0)), UiTheme.CHIP_DARK)
