extends SceneTree
## Prueba real del horneado de MascotAtlas (necesita pantalla: xvfb):
## precalienta las poses de 4 jugadores como en la TV, espera a que termine,
## mide tiempos por cuadro, memoria y poses, y guarda una hoja 2D vs 3D
## (misma llamada a PlayerAvatar.draw_mascot, con el 3D apagado y prendido).
## Sale con 1 si algo no se horneó.
##
##   xvfb-run -a -s "-screen 0 1920x1080x24" godot --path . --rendering-driver opengl3 \
##     --audio-driver Dummy -s res://tools/mascot_atlas_check.gd -- --out=/tmp/atlas.png

const LOOKS := [
	{"color": 0, "style": 0}, {"color": 5, "style": 6}, {"color": 7, "style": 4}, {"color": 9, "style": 5},
]

var _out := "/tmp/mascot_atlas_check.png"


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			_out = arg.trim_prefix("--out=")
	if not MascotAtlas.available():
		printerr("Sin render (¿--headless?): no hay nada que hornear.")
		quit(1)
		return
	var players: Array = []
	for i in LOOKS.size():
		players.append({"id": i + 1, "slot": i, "color": Protocol.mascot_color(LOOKS[i].color), "style": LOOKS[i].style})
	# Cuadros de la escena sin hornear (base) y mientras hornea: la diferencia
	# es lo que el horneado "traba" la TV (acá con render por software).
	var base := await _frame_times(90)
	MascotAtlas.log_jobs = "--log" in OS.get_cmdline_user_args()
	var t0 := Time.get_ticks_msec()
	MascotAtlas.prewarm_game(players, 0.8)
	var baking: Array[float] = []
	var last := Time.get_ticks_usec()
	while not MascotAtlas.is_idle() and Time.get_ticks_msec() - t0 < 60000:
		await process_frame
		var now := Time.get_ticks_usec()
		baking.append((now - last) / 1000.0)
		last = now
	var wall := Time.get_ticks_msec() - t0
	var s := MascotAtlas.stats
	print("Horneado (4 jugadores, juego u=0,8 + avisos + pantallas): %d poses en %d trabajos, %.2f s, %d cuadros" % [
		MascotAtlas.pose_count(), s.jobs, wall / 1000.0, baking.size()])
	print("  CPU del horneado: total %.0f ms · peor cuadro de trabajo %.1f ms" % [s.cpu_ms, s.worst_frame_ms])
	print("  Cuadro de la escena: base %s · horneando %s" % [_stats(base), _stats(baking)])
	print("  Memoria: %.1f MB · fallas: %d" % [MascotAtlas.memory_bytes() / 1048576.0, s.failures])
	var ok: bool = MascotAtlas.pose_count() > 0 and int(s.failures) == 0 and MascotAtlas.is_idle()

	# Hoja: arriba 2D, abajo 3D horneado (tamaños de juego y de pantalla).
	var vp := SubViewport.new()
	vp.size = Vector2i(1500, 900)
	vp.transparent_bg = false
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(vp)
	var bg := ColorRect.new()
	bg.color = UiTheme.SKY_BOTTOM
	bg.size = Vector2(vp.size)
	vp.add_child(bg)
	var canvas := Control.new()
	canvas.size = Vector2(vp.size)
	vp.add_child(canvas)
	var moods := [PlayerAvatar.Mood.NORMAL, PlayerAvatar.Mood.HAPPY, PlayerAvatar.Mood.SAD]
	canvas.draw.connect(func() -> void:
		for row in 2:
			MascotAtlas.enabled = row == 1
			var y0 := 20.0 + row * 440.0
			for i in LOOKS.size():
				var p: Dictionary = players[i]
				# Juego: quieta, caminando y feliz saludando.
				var x := 60.0 + i * 170.0
				PlayerAvatar.draw_mascot(canvas, Vector2(x, y0 + 120), 0.8, p.color, p.style, moods[0], 0.0, 0.0, false,
					{"t": 0.5, "look": Vector2.ZERO})
				PlayerAvatar.draw_mascot(canvas, Vector2(x + 80, y0 + 120), 0.8, p.color, p.style, moods[0], 0.0, 0.0, false,
					{"t": 0.5, "walk": 0.25, "look": Vector2(1, 0)})
				PlayerAvatar.draw_mascot(canvas, Vector2(x + 40, y0 + 240), 0.8, p.color, p.style, moods[1], 0.0, 0.0, false,
					{"t": 0.1, "wave": true})
				# Pantalla (u = 1,8, como las tarjetas del lobby).
				PlayerAvatar.draw_mascot(canvas, Vector2(780 + i * 180, y0 + 400), 1.8, p.color, p.style,
					moods[i % moods.size()], 0.0, 0.0, false, {"t": 0.1, "wave": i % moods.size() == 1})
		MascotAtlas.enabled = true)
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	vp.get_texture().get_image().save_png(_out)
	print("Hoja 2D (arriba) vs 3D horneado (abajo): ", _out)
	quit(0 if ok else 1)


func _frame_times(n: int) -> Array[float]:
	var out: Array[float] = []
	var last := Time.get_ticks_usec()
	for i in n:
		await process_frame
		var now := Time.get_ticks_usec()
		out.append((now - last) / 1000.0)
		last = now
	return out


static func _stats(v: Array[float]) -> String:
	if v.is_empty():
		return "-"
	var sorted := v.duplicate()
	sorted.sort()
	var avg := 0.0
	for x in v:
		avg += x
	return "prom. %.1f ms, p95 %.1f ms, máx. %.1f ms" % [avg / v.size(), sorted[int(sorted.size() * 0.95)], sorted[-1]]
