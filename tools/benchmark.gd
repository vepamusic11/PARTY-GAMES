extends SceneTree
## Benchmark de rendimiento con render real: arma cada pantalla de la TV
## (lobby, intro "¿Cómo se juega?", resumen de ronda, podio y cada
## minijuego del registry) y del celular (unirse, espera y joystick), la
## deja correr N frames con jugadores e inputs simulados y mide cuánto
## cuesta cada frame.
##
##   xvfb-run -a -s "-screen 0 1920x1080x24" godot --path . --rendering-driver opengl3 \
##     --audio-driver Dummy -s res://tools/benchmark.gd
##   … -- --frames=600               (más frames por escena; default 300)
##   … -- --only=lobby,dodge         (solo algunas escenas)
##   … -- --json=/tmp/bench.json     (además guarda la tabla en JSON)
##
## Igual que tools/capture_screens.gd necesita una pantalla (real o xvfb):
## con --headless no se dibuja nada y los números no sirven.
##
## Qué mide (ver docs/PERFORMANCE.md):
##   proceso   Performance.TIME_PROCESS. En Godot 4 incluye _process, _draw
##             y además el envío del render (RenderingServer.draw), así que
##             con render por software (xvfb/llvmpipe) lo domina la GPU falsa.
##   scripts   CPU de la escena, sin el render: desde que arranca el frame
##             (física) hasta frame_pre_draw. Es _physics_process, _process,
##             _draw de GDScript, layout de Controls y tweens. Es lo que más
##             se parece a lo que gasta la CPU de la TV.
##   render    frame_pre_draw -> frame_post_draw (render de Godot + driver).
##   frame     tiempo entre frames (lo que ve el jugador; tope 60 fps).
##   draws     Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME.
##   objetos   Performance.OBJECT_COUNT.
##   dib/s     frames que realmente se dibujaron por segundo (con el modo de
##             bajo consumo del celular, lo que no cambia no se redibuja).
##
## Corre con tope de 60 fps sin vsync (como la TV): así cada frame tiene un
## paso de física, igual que en el aparato.

const DEFAULT_FRAMES := 300
const WARMUP_FRAMES := 45
const TARGET_FPS := 60
const PHONE := Vector2i(2340, 1080)
const NAMES := ["Pablo", "Sofi", "Tomi", "Juli"]

var _frames := DEFAULT_FRAMES
var _only: Array[String] = []
var _json_path := ""
var _results: Array[Dictionary] = []

# Estado de la medición (lo llenan las señales del motor).
var _measuring := false
var _in_frame := false
var _process_seen := false
var _frame_start_us := 0
var _pre_draw_us := 0
var _last_start_us := 0
var _script_samples: Array[float] = []
var _render_samples: Array[float] = []
var _period_samples: Array[float] = []
var _draws_counted := 0
## Escena de juego activa: se reinicia si termina antes de juntar los frames.
var _game: MiniGame
var _game_id := ""
var _game_layout := ""
var _game_players: Array[Dictionary] = []
var _game_t := 0.0
var _restarts := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--frames="):
			_frames = maxi(10, int(arg.trim_prefix("--frames=")))
		elif arg.begins_with("--only="):
			for id in arg.trim_prefix("--only=").split(",", false):
				_only.append(id.strip_edges())
		elif arg.begins_with("--json="):
			_json_path = arg.trim_prefix("--json=")
	if DisplayServer.get_name() == "headless":
		printerr("El benchmark necesita una pantalla: correlo con xvfb-run (ver el comentario del script).")
		quit(1)
		return
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = TARGET_FPS
	physics_frame.connect(_on_physics_frame)
	process_frame.connect(_on_process_frame)
	RenderingServer.frame_pre_draw.connect(func() -> void: _pre_draw_us = Time.get_ticks_usec())
	RenderingServer.frame_post_draw.connect(_on_frame_drawn)

	print("\n=== Party Games · benchmark (%d frames por escena, %s) ===\n" % [_frames, _renderer_name()])
	await _bench("lobby", _make_lobby)
	await _bench("game_intro", _make_intro)
	await _bench("round_summary", _make_summary)
	await _bench("final", _make_final)
	for info in MiniGameRegistry.all_info():
		await _bench_game(info)
	await _bench("ctrl_join", _make_controller.bind(""))
	await _bench("ctrl_wait", _make_controller.bind(Protocol.LAYOUT_WAIT))
	await _bench("ctrl_joy", _make_controller.bind(Protocol.LAYOUT_JOYSTICK))
	_print_table()
	if not _json_path.is_empty():
		_save_json()
	quit(0)


# --- Medición -------------------------------------------------------------------

func _wanted(scene: String) -> bool:
	return _only.is_empty() or scene in _only


## Construye la escena, la deja estabilizarse y mide _frames frames.
func _bench(scene: String, build: Callable) -> void:
	if not _wanted(scene):
		return
	var node: Node = build.call()
	await _measure(scene)
	node.queue_free()
	OS.low_processor_usage_mode = false  # Lo puede prender el control del celular.
	await _frames_wait(3)


func _bench_game(info: Dictionary) -> void:
	if not _wanted(info.id):
		return
	_game_id = info.id
	_game_layout = info.layout
	_game_players = _fake_players(mini(int(info.max_players), Protocol.MAX_PLAYERS))
	_restarts = -1
	_start_game()
	await _measure(info.id)
	if is_instance_valid(_game):
		_game.queue_free()
	_game = null
	_game_id = ""
	await _frames_wait(3)


func _measure(scene: String) -> void:
	await _frames_wait(WARMUP_FRAMES)
	var process: Array[float] = []
	var physics: Array[float] = []
	var draw_calls: Array[float] = []
	var objects: Array[float] = []
	_script_samples.clear()
	_render_samples.clear()
	_period_samples.clear()
	_draws_counted = 0
	_measuring = true
	var start_us := Time.get_ticks_usec()
	for i in _frames:
		await process_frame
		process.append(Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0)
		physics.append(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0)
		draw_calls.append(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
		objects.append(Performance.get_monitor(Performance.OBJECT_COUNT))
	_measuring = false
	var wall := (Time.get_ticks_usec() - start_us) / 1_000_000.0
	var row := {
		"scene": scene,
		"process_avg_ms": _avg(process),
		"process_p95_ms": _p95(process),
		"physics_avg_ms": _avg(physics),
		"script_avg_ms": _avg(_script_samples),
		"script_p95_ms": _p95(_script_samples),
		"render_avg_ms": _avg(_render_samples),
		"frame_avg_ms": _avg(_period_samples),
		"frame_p95_ms": _p95(_period_samples),
		"draw_calls": _avg(draw_calls),
		"objects": _avg(objects),
		"draws_per_sec": _draws_counted / maxf(wall, 0.001),
		"restarts": maxi(_restarts, 0) if not _game_id.is_empty() else 0,
	}
	_results.append(row)
	print("  %-14s proceso %6.2f ms  scripts %5.2f ms (p95 %5.2f)  render %6.2f ms  draws %4.0f  objetos %5.0f" % [
		scene, row.process_avg_ms, row.script_avg_ms, row.script_p95_ms, row.render_avg_ms, row.draw_calls, row.objects])


## El frame arranca con el primer paso de física o, si no hay, con el proceso.
func _on_frame_start() -> void:
	if _in_frame:
		return
	_in_frame = true
	_process_seen = false
	_frame_start_us = Time.get_ticks_usec()
	if _measuring and _last_start_us > 0:
		_period_samples.append((_frame_start_us - _last_start_us) / 1000.0)
	_last_start_us = _frame_start_us


func _on_process_frame() -> void:
	if _in_frame and _process_seen:
		# El frame anterior no se dibujó (modo de bajo consumo): empieza otro.
		_in_frame = false
	_on_frame_start()
	_process_seen = true


func _on_physics_frame() -> void:
	if _process_seen:
		_in_frame = false
	_on_frame_start()
	if _game_id.is_empty():
		return
	# Inputs simulados y reinicio del juego si terminó (siempre medimos un juego vivo).
	if is_instance_valid(_game) and _game.is_finished():
		_game.queue_free()
		_start_game()
	_feed_game_input()


func _on_frame_drawn() -> void:
	if _in_frame and _measuring and _pre_draw_us >= _frame_start_us:
		_script_samples.append((_pre_draw_us - _frame_start_us) / 1000.0)
		_render_samples.append((Time.get_ticks_usec() - _pre_draw_us) / 1000.0)
		_draws_counted += 1
	_in_frame = false
	_process_seen = false


# --- Escenas de la TV -----------------------------------------------------------

func _tv_root() -> Control:
	var tv := Control.new()
	tv.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	tv.theme = UiTheme.build()
	tv.add_child(PartyBackground.new())
	root.add_child(tv)
	return tv


func _make_lobby() -> Node:
	var tv := _tv_root()
	var lobby := LobbyScreen.new()
	tv.add_child(lobby)
	lobby._stepper.set_value(4)
	lobby.set_room("K7QX", "192.168.0.10  ·  puerto %d" % Protocol.WS_PORT)
	lobby.refresh(_fake_players(4))
	lobby.focus_default()
	return tv


func _make_intro() -> Node:
	var tv := _tv_root()
	var intro := GameIntroScreen.new()
	tv.add_child(intro)
	intro.show_intro(MiniGameRegistry.info("arena"), 1, 4, _fake_players(4))
	intro.paused = true  # Que no avance sola durante la medición.
	return tv


func _make_summary() -> Node:
	var tv := _tv_root()
	var summary := RoundSummaryScreen.new()
	tv.add_child(summary)
	var ids: Array[String] = []
	for info in MiniGameRegistry.all_info():
		ids.append(str(info.id))
	var players := _fake_players(4)
	var t := Tournament.new(ids, players)
	t.advance(players.size())
	var s := t.record(_fake_result(players, 0), players)
	summary.show_summary(s, t.standings(), str(MiniGameRegistry.info(t.peek_next(players.size())).get("title", "")))
	summary.paused = true  # Que no avance solo durante la medición.
	return tv


func _make_final() -> Node:
	var tv := _tv_root()
	var final := FinalScreen.new()
	tv.add_child(final)
	var players := _fake_players(4)
	var ids: Array[String] = ["arena", "tap_race", "dodge"]
	var t := Tournament.new(ids, players)
	var titles: Array[String] = []
	for i in ids.size():
		t.advance(players.size())
		titles.append(str(t.record(_fake_result(players, i), players).title))
	final.show_final(t.standings(), titles)
	return tv


# --- Minijuegos -----------------------------------------------------------------

func _start_game() -> void:
	_game = MiniGameRegistry.create(_game_id)
	root.add_child(_game)
	_game.setup(_game_players.duplicate(true))
	_game_t = 0.0
	_restarts += 1


## Inputs "humanos" según el control del juego. Se mandan en cada frame
## (más de lo que manda un celular real: peor caso).
func _feed_game_input() -> void:
	if not is_instance_valid(_game) or _game.is_finished():
		return
	_game_t += 1.0 / TARGET_FPS
	var t := _game_t
	for p in _game_players:
		var k := float(p.slot)
		var axis := Vector2.ZERO
		var btn := 0
		match _game_layout:
			Protocol.LAYOUT_JOYSTICK:
				axis = Vector2(cos(t * 1.3 + k * 1.7), sin(t * 0.9 + k * 2.3))
			Protocol.LAYOUT_SLIDER_H:
				axis = Vector2(sin(t * 2.0 + k), 0.0)
			Protocol.LAYOUT_ONE_BUTTON:
				if _game_id == "stop_clock":
					# Frenan de a uno; el último nunca, así el reloj sigue corriendo.
					btn = Protocol.BTN_A if k < 3.0 and t > 4.0 + k * 1.5 else 0
				else:
					btn = Protocol.BTN_A if int(t * (6.0 + k)) % 2 == 0 else 0
		_game.on_input(p.id, {"seq": -1, "axis": axis, "btn": btn})


# --- Celular --------------------------------------------------------------------

## Pantalla del celular a tamaño real, como raíz (igual que en el teléfono).
func _make_controller(layout: String) -> Node:
	root.size = PHONE
	var ctrl := ControllerMain.new()
	root.add_child(ctrl)
	if not layout.is_empty():
		ctrl._join_screen.visible = false
		ctrl._play_screen.visible = true
		ctrl._header.text = "4P · Juli"
		ctrl._on_layout_changed(layout, {})
	ctrl.tree_exited.connect(func() -> void: root.size = Vector2i(1920, 1080))
	return ctrl


# --- Datos inventados -----------------------------------------------------------

func _fake_players(n: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for i in n:
		out.append({"id": i + 1, "slot": i, "name": NAMES[i], "color": Protocol.player_color(i), "connected": true})
	return out


func _fake_result(players: Array[Dictionary], round_index: int) -> Dictionary:
	var scores := {}
	for i in players.size():
		scores[players[i].id] = 10 + ((i + round_index) % players.size()) * 7
	return MiniGame.result_from_scores(scores)


# --- Salida ---------------------------------------------------------------------

func _print_table() -> void:
	print("\n| Escena | Proceso prom. (ms) | Proceso p95 (ms) | Scripts prom. (ms) | Scripts p95 (ms) | Física (ms) | Render (ms) | Frame prom. (ms) | Frame p95 (ms) | Draw calls | Objetos | Dibujos/s |")
	print("|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|")
	for r in _results:
		print("| %s | %.2f | %.2f | %.2f | %.2f | %.2f | %.2f | %.2f | %.2f | %.0f | %.0f | %.0f |" % [
			r.scene, r.process_avg_ms, r.process_p95_ms, r.script_avg_ms, r.script_p95_ms, r.physics_avg_ms,
			r.render_avg_ms, r.frame_avg_ms, r.frame_p95_ms, r.draw_calls, r.objects, r.draws_per_sec])
	print("")


func _save_json() -> void:
	var data := {
		"godot": Engine.get_version_info().string,
		"renderer": _renderer_name(),
		"frames": _frames,
		"target_fps": TARGET_FPS,
		"date": Time.get_datetime_string_from_system(true),
		"scenes": _results,
	}
	var f := FileAccess.open(_json_path, FileAccess.WRITE)
	if f == null:
		printerr("No se pudo escribir ", _json_path)
		return
	f.store_string(JSON.stringify(data, "  "))
	print("JSON guardado en ", _json_path)


func _renderer_name() -> String:
	return "%s · %s" % [RenderingServer.get_current_rendering_driver_name(), RenderingServer.get_video_adapter_name()]


static func _avg(values: Array[float]) -> float:
	if values.is_empty():
		return 0.0
	var total := 0.0
	for v in values:
		total += v
	return total / values.size()


static func _p95(values: Array[float]) -> float:
	if values.is_empty():
		return 0.0
	var sorted := values.duplicate()
	sorted.sort()
	return sorted[mini(sorted.size() - 1, int(ceil(sorted.size() * 0.95)) - 1)]


func _frames_wait(n: int) -> void:
	for i in n:
		await process_frame
