extends SceneTree
## ¿El precalentado de la intro alcanza? Para cada juego del registry hace lo
## mismo que la TV (MascotAtlas.prewarm_game con el MASCOT_SCALE y las poses
## extra del juego, ver HostMain._prewarm_mascots), espera a que se hornee
## todo, juega la partida entera con 4 bots y cuenta las poses que se
## hornearon tarde (pedidas recién al dibujar: un tirón chico en la TV).
## Necesita pantalla (xvfb):
##
##   xvfb-run -a -s "-screen 0 1920x1080x24" godot --path . --rendering-driver opengl3 \
##     --audio-driver Dummy -s res://tools/mascot_prewarm_check.gd -- --only=sumo,karts
##   … -- --max-sec=90   (tope de segundos por partida; default 120)
##
## Sale con 1 si algún juego horneó poses tarde.

const NAMES := ["Pablo", "Sofi", "Tomi", "Juli"]
const STYLES := [0, 6, 4, 5]

var _only: Array[String] = []
var _max_sec := 120.0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--only="):
			_only.assign(arg.trim_prefix("--only=").split(",", false))
		elif arg.begins_with("--max-sec="):
			_max_sec = maxf(5.0, arg.trim_prefix("--max-sec=").to_float())
	if not MascotAtlas.available():
		printerr("Sin render (¿--headless?): no hay nada que hornear.")
		quit(1)
		return
	var total_late := 0
	for script in MiniGameRegistry.GAMES:
		var info: Dictionary = script.call("get_info")
		if not _only.is_empty() and not str(info.id) in _only:
			continue
		var late := await _check_game(str(info.id), mini(int(info.max_players), Protocol.MAX_PLAYERS))
		total_late += late
	print("Total de poses horneadas tarde: %d" % total_late)
	quit(0 if total_late == 0 else 1)


## Juega una partida con bots y devuelve cuántas poses se hornearon tarde.
func _check_game(id: String, n: int) -> int:
	var players: Array[Dictionary] = []
	for i in n:
		players.append({"id": i + 1, "slot": i, "name": NAMES[i], "color": Protocol.player_color(i),
			"style": STYLES[i], "connected": true, "bot": true, "difficulty": Bot.Difficulty.NORMAL})
	MascotAtlas.clear()
	MascotAtlas.prewarm_game(players, MiniGameRegistry.mascot_scale(id), MiniGameRegistry.mascot_prewarm(id))
	var t0 := Time.get_ticks_msec()
	while not MascotAtlas.is_idle() and Time.get_ticks_msec() - t0 < 60000:
		await process_frame
	var prewarmed := MascotAtlas.pose_count()
	var bake_sec := (Time.get_ticks_msec() - t0) / 1000.0
	var mem_mb := MascotAtlas.memory_bytes() / 1048576.0
	MascotAtlas.late_poses.clear()
	var game := MiniGameRegistry.create(id)
	root.add_child(game)
	game.setup(players.duplicate(true))
	var driver := BotDriver.new()
	root.add_child(driver)
	driver.auto_step = true
	driver.start(game, game.players)
	var start := Time.get_ticks_msec()
	while not game.is_finished() and Time.get_ticks_msec() - start < _max_sec * 1000.0:
		await process_frame
	# El festejo del final se sigue dibujando un rato (la TV muestra el resumen después).
	for i in 90:
		await process_frame
	var late := MascotAtlas.late_poses.size()
	var keys := MascotAtlas.late_poses.keys()
	keys.sort()
	print("%-12s precalentadas %3d (%.1f s, %.1f MB) · tarde %2d%s · partida %.0f s%s" % [id, prewarmed, bake_sec, mem_mb, late,
		(": " + ", ".join(keys)) if late > 0 else "", (Time.get_ticks_msec() - start) / 1000.0,
		"" if game.is_finished() else " (cortada)"])
	driver.queue_free()
	game.queue_free()
	await process_frame
	return late
