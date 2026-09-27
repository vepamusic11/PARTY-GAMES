extends SceneTree
## Costo de las mascotas 3D (prototipo, ver docs/ARTE.md) comparado con la
## mascota 2D por código: 4 mascotas caminando al tamaño de los juegos
## (u = 0,8) y al del lobby (u = 3,6), en tres caminos:
##   2d        PlayerAvatar.draw_mascot en cada cuadro (lo de hoy)
##   3d_vivo   un SubViewport 3D por jugador, renderizado en cada cuadro
##   horneado  sprites 2D sacados de un atlas (Mascot3DBaker), cambiando de cuadro
## y además cuánto tarda hornear y cuánta memoria ocupa.
##
##   xvfb-run -a -s "-screen 0 1920x1080x24" godot --path . --rendering-driver opengl3 \
##     --audio-driver Dummy -s res://tools/mascot3d_benchmark.gd -- --json=/tmp/m3d.json
##   … -- --frames=600
##
## Mismas columnas que tools/benchmark.gd (ver docs/PERFORMANCE.md): "scripts"
## es la CPU de la escena sin el render (el número a vigilar); "render" es el
## render de Godot + driver (en xvfb, GPU por software: sirve para comparar).

const DEFAULT_FRAMES := 300
const WARMUP_FRAMES := 45
const PLAYERS := 4

var _frames := DEFAULT_FRAMES
var _json_path := ""
var _results: Array[Dictionary] = []
var _bakes: Array[Dictionary] = []

var _measuring := false
var _frame_start_us := 0
var _pre_draw_us := 0
var _script_samples: Array[float] = []
var _render_samples: Array[float] = []
var _in_frame := false


## 4 mascotas 2D por código, redibujadas en cada cuadro (como en los juegos).
class _Mascots2D:
	extends Node2D
	var u := 0.8
	var t := 0.0

	func _process(delta: float) -> void:
		t += delta
		queue_redraw()

	func _draw() -> void:
		for i in PLAYERS:
			var feet := Vector2(360.0 + i * 400.0, 700.0)
			PlayerAvatar.draw_mascot(self, feet, u, Protocol.player_color(i), i, PlayerAvatar.Mood.NORMAL, 0.0, 0.0,
				false, {"t": t, "walk": fposmod(t * 1.6 + i * 0.25, 1.0), "look": Vector2(1, 0)})


## 4 mascotas 3D en vivo (Mascot3DLive) que caminan.
class _Live:
	extends Node2D

	func _process(delta: float) -> void:
		for c in get_children():
			var m := c as Mascot3DLive
			m.walk = fposmod(m.walk + delta * 1.6, 1.0)


## 4 sprites horneados que avanzan por los 8 cuadros de la caminata.
class _Baked:
	extends Node2D
	var frames: Array = []   # Por jugador: Array[Texture2D]
	var sprites: Array[Sprite2D] = []
	var t := 0.0

	func _process(delta: float) -> void:
		t += delta
		for i in sprites.size():
			var f: Array = frames[i]
			sprites[i].texture = f[int(fposmod(t * 1.6 + i * 0.25, 1.0) * f.size()) % f.size()]


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--frames="):
			_frames = maxi(10, int(arg.trim_prefix("--frames=")))
		elif arg.begins_with("--json="):
			_json_path = arg.trim_prefix("--json=")
	if DisplayServer.get_name() == "headless":
		printerr("El benchmark necesita pantalla: correlo con xvfb-run.")
		quit(1)
		return
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 60
	root.size = Vector2i(1920, 1080)
	var bg := ColorRect.new()
	bg.color = UiTheme.SKY_BOTTOM
	bg.size = Vector2(1920, 1080)
	root.add_child(bg)
	physics_frame.connect(_on_frame_start)
	process_frame.connect(_on_frame_start)
	RenderingServer.frame_pre_draw.connect(func() -> void: _pre_draw_us = Time.get_ticks_usec())
	RenderingServer.frame_post_draw.connect(_on_frame_drawn)
	print("\n=== Mascotas 3D · benchmark (%d frames, %s) ===\n" % [_frames, RenderingServer.get_video_adapter_name()])

	await _bench("vacio", func() -> Node: return Node2D.new())
	for u in [0.8, 3.6]:
		var tag := "juego" if u < 1.0 else "lobby"
		await _bench("2d_" + tag, func() -> Node:
			var n := _Mascots2D.new()
			n.u = u
			return n)
		await _bench("3d_vivo_" + tag, _make_live.bind(u, Viewport.MSAA_4X))
		if u < 1.0:
			await _bench("3d_vivo_sin_msaa_" + tag, _make_live.bind(u, Viewport.MSAA_DISABLED))
		var baked := await _make_baked(u)
		await _bench("horneado_" + tag, func() -> Node: return baked)
	await _bench_bakes()
	_print_table()
	if not _json_path.is_empty():
		var f := FileAccess.open(_json_path, FileAccess.WRITE)
		f.store_string(JSON.stringify({"frames": _results, "bakes": _bakes}, "  "))
		print("JSON: ", _json_path)
	quit(0)


func _make_live(u: float, msaa: int) -> Node:
	var n := _Live.new()
	var px := Mascot3DBaker.cell_for_u(u)
	for i in PLAYERS:
		var m := Mascot3DLive.new().setup({"color": Protocol.player_color(i), "style": i}, px, msaa)
		m.position = Vector2(360.0 + i * 400.0, 700.0)
		m.walk = i * 0.25
		m.look = Vector2(1, 0)
		n.add_child(m)
	return n


func _make_baked(u: float) -> Node:
	var n := _Baked.new()
	var px := Mascot3DBaker.cell_for_u(u)
	var walk: Array[String] = []
	for k in 8:
		walk.append("walk_%d" % k)
	for i in PLAYERS:
		var tex := await Mascot3DBaker.bake(root, {"color": Protocol.player_color(i), "style": i}, walk, px)
		var frames: Array = []
		for k in walk:
			frames.append(tex[k])
		n.frames.append(frames)
		var s := Sprite2D.new()
		s.centered = false
		s.offset = -Mascot3DBaker.feet_offset(px)
		s.position = Vector2(360.0 + i * 400.0, 700.0)
		n.add_child(s)
		n.sprites.append(s)
	return n


func _bench(scene: String, build: Callable) -> void:
	var node: Node = build.call()
	if node.get_parent() == null:
		root.add_child(node)
	for i in WARMUP_FRAMES:
		await process_frame
	var draw_calls: Array[float] = []
	var vmem: Array[float] = []
	_script_samples.clear()
	_render_samples.clear()
	_measuring = true
	for i in _frames:
		await process_frame
		draw_calls.append(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
		vmem.append(Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0)
	_measuring = false
	var row := {
		"scene": scene,
		"script_avg_ms": _avg(_script_samples), "script_p95_ms": _p95(_script_samples),
		"render_avg_ms": _avg(_render_samples), "render_p95_ms": _p95(_render_samples),
		"draw_calls": _avg(draw_calls), "video_mem_mb": _avg(vmem),
		"objects": Performance.get_monitor(Performance.OBJECT_COUNT),
	}
	_results.append(row)
	print("  %-24s scripts %5.2f ms (p95 %5.2f)  render %6.2f ms (p95 %6.2f)  draws %4.0f  vram %6.1f MB" % [
		scene, row.script_avg_ms, row.script_p95_ms, row.render_avg_ms, row.render_p95_ms, row.draw_calls, row.video_mem_mb])
	node.queue_free()
	for i in 3:
		await process_frame


## Horneado: primera vez (incluye compilar shaders) y siguientes, para un
## juego (21 poses a u = 0,8) y para el lobby (10 poses a u = 3,6).
func _bench_bakes() -> void:
	print("\n  Horneado (4 jugadores):")
	var lobby: Array[String] = ["normal", "blink", "look", "wave_0", "wave_1", "wave_2", "wave_3", "sad", "surprised", "jump"]
	for spec in [["juego", 0.8, Mascot3DBaker.GAME_POSES], ["lobby", 3.6, lobby], ["juego", 0.8, Mascot3DBaker.GAME_POSES]]:
		var px := Mascot3DBaker.cell_for_u(spec[1])
		var t0 := Time.get_ticks_usec()
		var bytes := 0
		var worst := 0.0
		var parts := {"build_ms": 0.0, "render_ms": 0.0, "readback_ms": 0.0, "pack_ms": 0.0}
		for i in PLAYERS:
			var t1 := Time.get_ticks_usec()
			await Mascot3DBaker.bake(root, {"color": Protocol.player_color(i), "style": i}, spec[2], px)
			worst = maxf(worst, (Time.get_ticks_usec() - t1) / 1000.0)
			bytes += int(Mascot3DBaker.last_report.get("bytes", 0))
			for k in parts:
				parts[k] += float(Mascot3DBaker.last_report.get(k, 0.0))
		var total := (Time.get_ticks_usec() - t0) / 1000.0
		var row := {"set": spec[0], "poses": (spec[2] as Array).size(), "cell_px": px,
			"atlas": str(Mascot3DBaker.last_report.get("atlas", "")), "total_ms": total, "worst_player_ms": worst,
			"mem_mb": bytes / 1048576.0}
		row.merge(parts)
		_bakes.append(row)
		print("    %-6s %2d poses × %3d px  atlas %s  total %7.1f ms (peor jugador %6.1f; armar %.0f, render %.0f, leer %.0f, empaquetar %.0f)  %.1f MB" % [
			spec[0], row.poses, px, row.atlas, total, worst, parts.build_ms, parts.render_ms, parts.readback_ms,
			parts.pack_ms, row.mem_mb])


func _on_frame_start() -> void:
	if _in_frame:
		return
	_in_frame = true
	_frame_start_us = Time.get_ticks_usec()


func _on_frame_drawn() -> void:
	if _in_frame and _measuring and _pre_draw_us >= _frame_start_us:
		_script_samples.append((_pre_draw_us - _frame_start_us) / 1000.0)
		_render_samples.append((Time.get_ticks_usec() - _pre_draw_us) / 1000.0)
	_in_frame = false


func _print_table() -> void:
	print("\n| Escena | Scripts prom. (ms) | Scripts p95 (ms) | Render prom. (ms) | Draw calls | VRAM (MB) |")
	print("|---|---:|---:|---:|---:|---:|")
	for r in _results:
		print("| %s | %.2f | %.2f | %.2f | %.0f | %.1f |" % [r.scene, r.script_avg_ms, r.script_p95_ms,
			r.render_avg_ms, r.draw_calls, r.video_mem_mb])


static func _avg(a: Array[float]) -> float:
	if a.is_empty():
		return 0.0
	var s := 0.0
	for v in a:
		s += v
	return s / a.size()


static func _p95(a: Array[float]) -> float:
	if a.is_empty():
		return 0.0
	var b := a.duplicate()
	b.sort()
	return b[mini(b.size() - 1, int(b.size() * 0.95))]
