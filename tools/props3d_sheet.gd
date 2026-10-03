extends SceneTree
## Hoja de piezas 3D (core/art3d, ADR 0016): cada pieza horneada como la ve
## la TV, y al lado su versión 2D de antes (el respaldo sin render).
##
##   xvfb-run -a -s "-screen 0 1920x1080x24" godot --path . --rendering-driver opengl3 \
##     --audio-driver Dummy -s res://tools/props3d_sheet.gd -- --out=docs/img/piezas_3d.png
##
## Opciones (después de --):
##   --out=RUTA      imagen de salida (default docs/img/piezas_3d.png)
##   --atlas=RUTA    además guarda el atlas crudo (para revisar bordes y celdas)
##   --width=1920    ancho de la imagen (default 1600)
##
## Siempre hornea de cero (no usa la caché en disco) e imprime el tiempo y
## la memoria del atlas. Necesita pantalla (xvfb): con --headless no hay render.

const SIZE := Vector2i(1920, 1080)


class _Canvas:
	extends Control

	var calls: Array[Callable] = []

	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), UiTheme.SKY_BOTTOM)
		draw_rect(Rect2(0, 560, size.x, size.y - 560), UiTheme.FLOOR)
		UiTheme.draw_text(self, "Piezas 3D horneadas · abajo: 2D de respaldo (sin render) y 3D", Vector2(size.x / 2.0, 44), 40, UiTheme.PAPER, 8)
		for c in calls:
			c.call(self)


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var out := "res://docs/img/piezas_3d.png"
	var atlas_out := ""
	var width := 1600
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			out = arg.trim_prefix("--out=")
		elif arg.begins_with("--atlas="):
			atlas_out = arg.trim_prefix("--atlas=")
		elif arg.begins_with("--width="):
			width = clampi(int(arg.trim_prefix("--width=")), 320, 3840)
	if DisplayServer.get_name() == "headless":
		printerr("props3d_sheet necesita pantalla (xvfb-run).")
		quit(1)
		return
	root.size = SIZE
	var ok := await Props3DBaker.bake(root)
	if not ok:
		printerr("No se pudo hornear el atlas.")
		quit(1)
		return
	print("Horneado: ", Props3DBaker.last_report)
	if atlas_out != "":
		var raw := Props3D.texture() as CanvasTexture
		var img := (raw.diffuse_texture as Texture2D).get_image()
		img.clear_mipmaps()
		img.save_png(atlas_out)
	var canvas := _Canvas.new()
	canvas.size = Vector2(SIZE)
	root.add_child(canvas)
	var names := ["star", "star_white", "corner_0", "corner_5", "medal_1", "medal_2", "medal_3", "token", "coin", "gem", "ball", "crown", "trophy"]
	var x := 80.0
	for n: String in names:
		var reg: Array = Props3D.regions()[n]
		var body: Rect2 = reg[1]
		var scale := 110.0 / maxf(body.size.x, body.size.y)
		var sz: Vector2 = body.size * scale
		var at := Vector2(x, 130)
		canvas.calls.append(func(ci: CanvasItem) -> void:
			Props3D.draw(ci, n, Rect2(at, sz))
			UiTheme.draw_text(ci, n, at + Vector2(sz.x / 2.0, 150), 20, UiTheme.INK))
		x += 136.0
	# Bloques del marco y del fondo.
	x = 80.0
	for i in UiTheme.BRICKS.size():
		var at := Vector2(x, 330)
		var idx := i
		canvas.calls.append(func(ci: CanvasItem) -> void:
			Props3D.draw(ci, Props3D.brick_name(idx, false), Rect2(at, Vector2(112, 40)))
			Props3D.draw(ci, Props3D.brick_name(idx, true), Rect2(at + Vector2(130, -40), Vector2(40, 112)))
			Props3D.draw(ci, "block_%d" % idx, Rect2(at + Vector2(0, 90), Vector2(80, 80)))
			Props3D.draw(ci, "block_far_%d" % idx, Rect2(at + Vector2(100, 110), Vector2(50, 50)), Color.WHITE, true))
		x += 220.0
	# Comparación con el 2D de antes (lo que se ve sin render).
	canvas.calls.append(func(ci: CanvasItem) -> void:
		UiTheme.draw_text(ci, "2D", Vector2(40, 640), 28, UiTheme.INK)
		UiTheme.draw_text(ci, "3D", Vector2(40, 800), 28, UiTheme.INK)
		UiTheme.draw_text(ci, "2D", Vector2(960, 1000), 28, UiTheme.INK)
		UiTheme.draw_text(ci, "3D", Vector2(1580, 1000), 28, UiTheme.INK)
		var c := Vector2(160, 640)
		for k in 3:
			UiTheme.draw_medal_2d(ci, c + Vector2(k * 120, 0), 40.0, k + 1)
			Props3D.draw_centered(ci, "medal_%d" % (k + 1), c + Vector2(k * 120, 160), Vector2(80, 80))
			UiTheme.draw_text(ci, UiTheme.place_text(k + 1), c + Vector2(k * 120 + 2, 161), 40, UiTheme.INK)
		c = Vector2(560, 640)
		UiTheme.draw_star_2d(ci, c, 44.0)
		Props3D.draw_centered(ci, "star", c + Vector2(0, 160), Vector2(88, 88))
		# Esquina de un tablero: arriba el 2D (Props3D apagado), abajo el 3D.
		var board := Rect2(720, 640, 480, 240)
		Props3D.enabled = false
		GameArt.paint_board(ci, board, 80.0)
		Props3D.enabled = true
		GameArt.paint_board(ci, Rect2(board.position + Vector2(620, 0), board.size), 80.0))
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	var shot := root.get_texture().get_image()
	if width != SIZE.x:
		shot.resize(width, int(float(SIZE.y) * width / SIZE.x), Image.INTERPOLATE_LANCZOS)
	shot.save_png(out)
	print("Hoja: ", out)
	quit(0)
