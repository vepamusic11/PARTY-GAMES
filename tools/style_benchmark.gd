extends SceneTree
## Mide cuánto cuesta cada post-proceso de estilo (docs/ESTILOS.md) sobre la
## pantalla del lobby de la TV: mismos cuadros con y sin shader.
##
##   xvfb-run -a -s "-screen 0 1920x1080x24" godot --path . --rendering-driver opengl3 \
##     --audio-driver Dummy -s res://tools/style_benchmark.gd -- --frames=300
##
## Imprime una tabla Markdown con, por estilo: tiempo de cuadro total (ms),
## tiempo de proceso (Performance.TIME_PROCESS) y tiempo de dibujo del
## viewport medido por Godot (CPU y GPU). Con xvfb el "GPU" es llvmpipe (Mesa
## por software): los números sirven para comparar estilos entre sí, no como
## presupuesto real de una TV (eso hay que medirlo en el dispositivo).

const StyleLayer := preload("res://tools/styles/style_layer.gd")
const PORT := 47996
const WARMUP := 30

var _frames := 300


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--frames="):
			_frames = maxi(30, arg.trim_prefix("--frames=").to_int())
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	var host := HostMain.new()
	host.server_port = PORT
	host.announce = false
	root.add_child(host)
	await _frames_wait(10)
	var vp_rid := root.get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(vp_rid, true)

	var rows: Array[String] = []
	var base_ms := 0.0
	# "copia": shader que solo devuelve la pantalla tal cual; aísla el costo de
	# copiar la pantalla (hint_screen_texture) del costo del estilo en sí.
	for style: String in ["", "copia"] + StyleLayer.STYLES:
		var layer: CanvasLayer = null
		if style == "copia":
			layer = _passthrough_layer()
		elif style != "":
			layer = StyleLayer.attach(root, style)
		var r := await _measure(vp_rid)
		if style == "":
			base_ms = r.frame
		var extra := "—" if style == "" else "%+.2f" % (r.frame - base_ms)
		rows.append("| %s | %.2f | %s | %.2f | %.2f | %.2f |" % [
			{"": "actual (sin shader)", "copia": "solo copia de pantalla"}.get(style, style), r.frame, extra, r.process, r.cpu, r.gpu])
		if layer:
			layer.queue_free()
			await _frames_wait(2)

	print("\nLobby de la TV, %d cuadros por estilo (promedios en ms):\n" % _frames)
	print("| Estilo | Cuadro total | Diferencia vs. actual | TIME_PROCESS | Dibujo CPU | Dibujo GPU |")
	print("|---|---|---|---|---|---|")
	for row in rows:
		print(row)
	print("\nGPU: ", RenderingServer.get_video_adapter_name(), " (", RenderingServer.get_video_adapter_vendor(), ")")
	quit(0)


func _passthrough_layer() -> CanvasLayer:
	var layer := CanvasLayer.new()
	layer.layer = 128
	var rect := ColorRect.new()
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var shader := Shader.new()
	shader.code = "shader_type canvas_item;\nuniform sampler2D s : hint_screen_texture, filter_nearest;\nvoid fragment() { COLOR = vec4(texture(s, SCREEN_UV).rgb, 1.0); }"
	var mat := ShaderMaterial.new()
	mat.shader = shader
	rect.material = mat
	layer.add_child(rect)
	root.add_child(layer)
	return layer


## Promedia `_frames` cuadros después de un calentamiento.
func _measure(vp_rid: RID) -> Dictionary:
	await _frames_wait(WARMUP)
	var frame_us := 0
	var process_s := 0.0
	var cpu_ms := 0.0
	var gpu_ms := 0.0
	var last := Time.get_ticks_usec()
	for i in _frames:
		await process_frame
		var now := Time.get_ticks_usec()
		frame_us += now - last
		last = now
		process_s += Performance.get_monitor(Performance.TIME_PROCESS)
		cpu_ms += RenderingServer.viewport_get_measured_render_time_cpu(vp_rid)
		gpu_ms += RenderingServer.viewport_get_measured_render_time_gpu(vp_rid)
	var n := float(_frames)
	return {"frame": frame_us / n / 1000.0, "process": process_s / n * 1000.0, "cpu": cpu_ms / n, "gpu": gpu_ms / n}


func _frames_wait(n: int) -> void:
	for i in n:
		await process_frame
