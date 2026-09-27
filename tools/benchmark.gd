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
##   … -- --bots                     (los jugadores de los juegos son bots
##                                    "Normal" en vez de entradas inventadas:
##                                    mide cuánto cuestan los bots; ADR 0010)
##   … -- --no-audio                 (sin música ni efectos, para comparar)
##   … -- --mascots=both             (cada escena dos veces seguidas, con las
##                                    mascotas 2D por código y con las 3D
##                                    horneadas, alternando cuál va primero;
##                                    también 2d o 3d. Default: 3d, como el
##                                    juego. ADR 0012)
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
## Juegos que cambian mucho con el tiempo: además se miden adelantados estos
## segundos (escena "<id>_tarde"), con los jugadores quietos para que el
## juego no termine antes de tiempo. Ej. en Empujones la isla se achica desde los 15 s.
## El juego tiene que tener step(delta) (como sumo, para los tests).
const LATE_SCENES := {"sumo": 20.0}

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
var _late_sec := 0.0  ## > 0: adelantar el juego antes de medir (ver LATE_SCENES).
var _use_bots := false  ## --bots: los jugadores los maneja un BotDriver.
var _driver := BotDriver.new()
## Como en la TV: música sonando y efectos (con ducking) durante la medición.
var _audio := true
## Mascotas a medir: "2d" (por código), "3d" (horneadas, MascotAtlas) o las dos.
var _mascot_modes: Array[String] = ["3d"]
var _mode_turn := 0  ## Alterna qué modo va primero en cada escena.
var _music_tracks: Array = []


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
		elif arg == "--bots":
			_use_bots = true
		elif arg == "--no-audio":
			_audio = false
		elif arg.begins_with("--mascots="):
			var m := arg.trim_prefix("--mascots=")
			_mascot_modes.assign(["2d", "3d"] if m == "both" else [m])
	_driver.auto_step = false
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

	if _audio:
		root.add_child(Sfx.new())
		root.add_child(Music.new())
		_music_tracks = Music.TRACKS.keys()
	print("\n=== Party Games · benchmark (%d frames por escena, %s%s%s) ===\n" % [_frames, _renderer_name(),
		", juegos con bots" if _use_bots else "", "" if _audio else ", sin audio"])
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
	_driver.free()
	quit(0)


# --- Medición -------------------------------------------------------------------

func _wanted(scene: String) -> bool:
	return _only.is_empty() or scene in _only or scene.trim_suffix("_tarde") in _only


## Modos de mascota para la próxima escena (alternando el orden si son dos).
func _modes() -> Array[String]:
	var out := _mascot_modes.duplicate()
	if out.size() > 1 and _mode_turn % 2 == 1:
		out.reverse()
	_mode_turn += 1
	return out


## Nombre de la fila: con sufijo ·2d/·3d solo si se miden los dos modos.
func _row_name(scene: String, mode: String) -> String:
	return scene if _mascot_modes.size() == 1 else "%s·%s" % [scene, mode]


## Construye la escena, la deja estabilizarse y mide _frames frames.
func _bench(scene: String, build: Callable) -> void:
	if not _wanted(scene):
		return
	for mode in _modes():
		MascotAtlas.enabled = mode == "3d"
		var node: Node = build.call()
		await _measure(_row_name(scene, mode), mode)
		node.queue_free()
		OS.low_processor_usage_mode = false  # Lo puede prender el control del celular.
		await _frames_wait(3)
	MascotAtlas.enabled = true


func _bench_game(info: Dictionary) -> void:
	if not _wanted(info.id):
		return
	for mode in _modes():
		MascotAtlas.enabled = mode == "3d"
		await _bench_game_mode(info, mode)
	MascotAtlas.enabled = true


func _bench_game_mode(info: Dictionary, mode: String) -> void:
	_game_id = info.id
	_game_layout = info.layout
	_game_players = _fake_players(mini(int(info.max_players), Protocol.MAX_PLAYERS))
	if _use_bots:
		for p in _game_players:
			p["bot"] = true
			p["difficulty"] = Bot.Difficulty.NORMAL
	_restarts = -1
	_start_game()
	await _measure(_row_name(info.id, mode), mode)
	if is_instance_valid(_game):
		_game.queue_free()
	if LATE_SCENES.has(info.id) and _wanted(info.id + "_tarde") and not _use_bots:
		await _frames_wait(3)
		_late_sec = LATE_SCENES[info.id]
		_restarts = -1
		_start_game()
		await _measure(_row_name(info.id + "_tarde", mode), mode)
		_late_sec = 0.0
		if is_instance_valid(_game):
			_game.queue_free()
	_game = null
	_game_id = ""
	await _frames_wait(3)


func _measure(scene: String, mode: String = "3d") -> void:
	if _audio:  # Cambio de pista al entrar (fundido cruzado dentro del calentamiento).
		Music.play(str(_music_tracks[_results.size() % _music_tracks.size()]))
	await _frames_wait(WARMUP_FRAMES)
	if mode == "3d" and MascotAtlas.available():
		# Como en la TV, las mascotas se hornean antes (lobby / intro): no se mide el horneado.
		var players := _game_players if not _game_id.is_empty() else _fake_players(4)
		MascotAtlas.prewarm_screens(players)
		if not _game_id.is_empty():
			MascotAtlas.prewarm_game(players, _mascot_scale(_game_id))
		for i in 2:
			var t0 := Time.get_ticks_msec()
			while not MascotAtlas.is_idle() and Time.get_ticks_msec() - t0 < 60000:
				await process_frame
			await _frames_wait(WARMUP_FRAMES)  # Poses que se piden recién al dibujar (parpadeo, saludo).
	var jobs_before := int(MascotAtlas.stats.jobs)
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
		if _audio and i % 60 == 0:
			Sfx.play("go")  # Efecto importante: dispara el ducking de la música.
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
		"mascots": mode,
		"bakes_during": int(MascotAtlas.stats.jobs) - jobs_before,
		"atlas_mb": MascotAtlas.memory_bytes() / 1048576.0,
	}
	_results.append(row)
	print("  %-17s proceso %6.2f ms  scripts %5.2f ms (p95 %5.2f)  render %6.2f ms  draws %4.0f  objetos %5.0f  atlas %4.1f MB%s" % [
		scene, row.process_avg_ms, row.script_avg_ms, row.script_p95_ms, row.render_avg_ms, row.draw_calls, row.objects,
		row.atlas_mb, "  (horneó %d durante la medición)" % row.bakes_during if row.bakes_during > 0 else ""])


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
	if _use_bots:
		_driver.start(_game, _game.players)
	_game_t = 0.0
	_restarts += 1
	if _late_sec > 0.0 and _game.has_method("step"):
		for i in int(_late_sec * TARGET_FPS):
			if _game.is_finished():
				break
			_feed_game_input()
			_game.call("step", 1.0 / TARGET_FPS)


## Inputs "humanos" según el control del juego. Se mandan en cada frame
## (más de lo que manda un celular real: peor caso).
func _feed_game_input() -> void:
	if not is_instance_valid(_game) or _game.is_finished():
		return
	if _use_bots:
		_driver.step(1.0 / TARGET_FPS)  # Los bots deciden y mandan su entrada (medido en "scripts").
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
				if _late_sec > 0.0:
					axis = Vector2.ZERO  # Quietos: nadie se cae y el juego no termina.
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

## MASCOT_SCALE del juego (u de sus mascotas), para precalentar el atlas.
func _mascot_scale(game_id: String) -> float:
	for script in MiniGameRegistry.GAMES:
		if script.call("get_info").id == game_id:
			return float(script.get_script_constant_map().get("MASCOT_SCALE", 0.8))
	return 0.8


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
		"bots": _use_bots,
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
