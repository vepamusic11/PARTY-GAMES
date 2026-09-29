extends SceneTree
## Vista previa del escenario 2.5D horneado (ADR 0019) con Pintar el piso en
## un estado fijo parecido a la maqueta (docs/design/referencia_juego_pintar.webp):
## las 4 mascotas de la maqueta (rojo robot, azul oso, amarillo gato, verde
## brote), baldosas pintadas de los 4, el rayo y el reloj en 0:40.
##
##   xvfb-run -a -s "-screen 0 1920x1080x24" godot --path . --rendering-driver opengl3 \
##     --audio-driver Dummy -s res://tools/board25d_preview.gd -- --out=/tmp/pintar25d
##
## Opciones (después de --):
##   --out=DIR       carpeta de salida (default /tmp/pintar25d)
##   --no-cache      hornea de nuevo aunque haya caché en disco (para iterar la receta)
##   --compare=PNG   además arma la comparación: arriba maqueta | 2.5D, abajo
##                   antes (plano) | detalle del 2.5D a tamaño real
##                   (ej. --compare=res://docs/img/pintar_25d_comparacion.png)
##   --flat          también captura el mismo estado dibujado plano (antes)
## Guarda paint_25d.png (y paint_plano.png) a 1920×1080 e imprime los tiempos del horneado.

const REFERENCE := "res://docs/design/referencia_juego_pintar.webp"
const Paint := preload("res://host/minigames/paint/paint.gd")
## Jugadores como en la maqueta: [nombre, color (Protocol.MASCOT_COLORS), estilo].
const PLAYERS := [["Pablo", 0, 4], ["Sofi", 1, 1], ["Tomi", 2, 2], ["Juli", 3, 3]]

var _out := "/tmp/pintar25d/"


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var compare := ""
	var flat := false
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			_out = arg.trim_prefix("--out=").trim_suffix("/") + "/"
		elif arg == "--no-cache":
			Board25DBaker.use_disk_cache = false
		elif arg.begins_with("--compare="):
			compare = arg.trim_prefix("--compare=")
		elif arg == "--flat":
			flat = true
	DirAccess.make_dir_recursive_absolute(_out)
	await Props3DBaker.ensure(root)
	var players := _players()
	MascotAtlas.prewarm_game(players, Paint.MASCOT_SCALE)
	var t0 := Time.get_ticks_msec()
	var ok: bool = await Board25DBaker.ensure(root, Paint.board_view())
	print("Escenario 2.5D: %s en %d ms %s" % ["listo" if ok else "FALLÓ", Time.get_ticks_msec() - t0, Board25DBaker.last_report])
	while not MascotAtlas.is_idle():
		await process_frame
	var shot := await _capture(players)
	shot.save_png(_out + "paint_25d.png")
	print("  ", _out + "paint_25d.png")
	var before: Image = null
	if flat or compare != "":
		Board25DBaker.enabled = false
		before = await _capture(players)
		before.save_png(_out + "paint_plano.png")
		print("  ", _out + "paint_plano.png")
		Board25DBaker.enabled = true
	if compare != "":
		await _compare(shot, before, compare)
	quit(0 if ok else 1)


func _players() -> Array[Dictionary]:
	var list: Array[Dictionary] = []
	for i in PLAYERS.size():
		list.append({"id": i + 1, "slot": i, "name": PLAYERS[i][0], "color": Protocol.MASCOT_COLORS[PLAYERS[i][1]],
			"style": PLAYERS[i][2], "connected": true})
	return list


## Juego en un estado fijo (el de la maqueta, aproximado) y captura.
func _capture(players: Array[Dictionary]) -> Image:
	var game: Node2D = Paint.new()
	root.add_child(game)
	game.setup(players)
	game.set_physics_process(false)  # Quieto: el estado lo pone la herramienta.
	# 1P: franjas arriba a la izquierda y un camino en el medio; 2P: rayas en
	# diagonal; 3P: puntos arriba a la derecha; 4P: un rincón abajo.
	var paint := {
		1: [Rect2i(0, 0, 10, 1), Rect2i(0, 1, 2, 1), Rect2i(11, 2, 2, 3), Rect2i(13, 4, 1, 4), Rect2i(14, 7, 2, 4), Rect2i(16, 10, 2, 1)],
		2: [Rect2i(9, 2, 1, 7), Rect2i(10, 1, 1, 2), Rect2i(10, 8, 2, 1), Rect2i(11, 9, 3, 1), Rect2i(18, 3, 2, 3), Rect2i(17, 9, 3, 2)],
		3: [Rect2i(12, 0, 2, 2), Rect2i(14, 1, 4, 1), Rect2i(17, 0, 2, 1), Rect2i(11, 5, 1, 4), Rect2i(15, 4, 2, 1), Rect2i(18, 7, 2, 2)],
		4: [Rect2i(0, 9, 3, 2), Rect2i(3, 10, 2, 1)],
	}
	for pid: int in paint:
		for r: Rect2i in paint[pid]:
			for y in range(r.position.y, r.end.y):
				for x in range(r.position.x, r.end.x):
					game._paint_area(pid, Paint.cell_center(Vector2i(x, y)), 0)
	game._pos[1] = Paint.cell_center(Vector2i(12, 10)) + Vector2(0, 20)
	game._pos[2] = Paint.cell_center(Vector2i(19, 3)) + Vector2(-10, 20)
	game._pos[3] = Paint.cell_center(Vector2i(14, 1)) + Vector2(0, 20)
	game._pos[4] = Paint.cell_center(Vector2i(1, 8)) + Vector2(0, 20)
	game._spawn_powerup(Vector2i(7, 7), 1)
	game._state = 1  # PLAYING
	game._countdown = -5.0
	game._time_left = 40.0
	game._anim = 10.0
	for i in 40:
		await process_frame
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	game.queue_free()
	await process_frame
	return img


## Comparación: arriba la maqueta y el 2.5D lado a lado (960 px cada uno);
## abajo el mismo estado dibujado plano (antes) y un recorte del 2.5D a
## tamaño real (esquina de abajo a la izquierda: marco, estrella, baldosas).
func _compare(shot: Image, before: Image, path: String) -> void:
	var ref := Image.load_from_file(ProjectSettings.globalize_path(REFERENCE))
	var w := 960
	var h := 540
	var gap := 24
	var head := 60
	var vp := SubViewport.new()
	vp.size = Vector2i(w * 2 + gap, (h + head) * 2)
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	root.add_child(vp)
	var bg := ColorRect.new()
	bg.color = UiTheme.INK
	bg.size = Vector2(vp.size)
	vp.add_child(bg)
	var detail := shot.get_region(Rect2i(0, 1080 - h, w, h))
	var panels := [[ref, "Maqueta", true], [shot, "Ahora: 2.5D horneado (captura real)", true],
		[before, "Antes: tablero plano", true], [detail, "Ahora, detalle a tamaño real", false]]
	for i in panels.size():
		var img: Image = (panels[i][0] as Image).duplicate()
		if panels[i][2]:
			img.resize(w, h, Image.INTERPOLATE_LANCZOS)
		var at := Vector2((i % 2) * (w + gap), (i / 2) * (h + head))
		var tr := TextureRect.new()
		tr.texture = ImageTexture.create_from_image(img)
		tr.position = at + Vector2(0, head)
		vp.add_child(tr)
		var label := UiTheme.label(panels[i][1], 30, UiTheme.PAPER)
		label.position = at + Vector2(16, 10)
		vp.add_child(label)
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var out := vp.get_texture().get_image()
	out.save_png(ProjectSettings.globalize_path(path) if path.begins_with("res://") else path)
	print("  ", path)
	vp.queue_free()
