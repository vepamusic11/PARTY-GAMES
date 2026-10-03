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
##   --game=ID       otro juego con tablero 2.5D en un estado fijo: arena,
##                   dodge, pool, karts, pingpong, tap_race o hurdles. Con --compare arma la comparación
##                   antes (plano) | ahora (2.5D) y abajo dos detalles a
##                   tamaño real (ej. --compare=res://docs/img/pool_25d_comparacion.png)
## Guarda <juego>_25d.png (y <juego>_plano.png) a 1920×1080 e imprime los tiempos del horneado.

const REFERENCE := "res://docs/design/referencia_juego_pintar.webp"
const Paint := preload("res://host/minigames/paint/paint.gd")
## Detalles a tamaño real de la comparación de cada juego (960 × 540 de la
## captura 2.5D): [origen del recorte, título].
const DETAILS := {
	"arena": [[Vector2i(0, 540), "Ahora, detalle: marco, mascota y estrellas"], [Vector2i(760, 150), "Ahora, detalle: atrás, más chico"]],
	"dodge": [[Vector2i(300, 200), "Ahora, detalle: bloques cayendo y sombras"], [Vector2i(960, 540), "Ahora, detalle: bloque apoyado"]],
	"pool": [[Vector2i(120, 80), "Ahora, detalle: puntería y guía de tiro"], [Vector2i(960, 520), "Ahora, detalle: troneras y bandas"]],
	"karts": [[Vector2i(760, 540), "Ahora, detalle: largada, cordones y karts"], [Vector2i(60, 120), "Ahora, detalle: curva de atrás y árboles"]],
	"pingpong": [[Vector2i(480, 360), "Ahora, detalle: red, pelota y paleta"], [Vector2i(900, 500), "Ahora, detalle: mascota y canto de la mesa"]],
	"tap_race": [[Vector2i(0, 200), "Ahora, detalle: carteles y carriles de atrás"], [Vector2i(900, 520), "Ahora, detalle: meta y mascotas de adelante"]],
	"hurdles": [[Vector2i(0, 160), "Ahora, detalle: carril de atrás"], [Vector2i(700, 540), "Ahora, detalle: vallas y pozo de adelante"]],
}
## Jugadores como en la maqueta: [nombre, color (Protocol.MASCOT_COLORS), estilo].
const PLAYERS := [["Pablo", 0, 4], ["Sofi", 1, 1], ["Tomi", 2, 2], ["Juli", 3, 3]]

var _out := "/tmp/pintar25d/"


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var compare := ""
	var flat := false
	var game_id := "paint"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--game="):
			game_id = arg.trim_prefix("--game=")
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
	if game_id != "paint":
		quit(await _run_game(game_id, compare))
		return
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



# --- Otros juegos con tablero 2.5D (Arena, Esquivar, Pool) ---------------------------

## Captura el juego `id` en 2.5D y plano, en el mismo estado fijo, y (con
## `compare`) arma la comparación. Devuelve el código de salida.
func _run_game(id: String, compare: String) -> int:
	var script: GDScript = MiniGameRegistry._script(id)
	if script == null or not DETAILS.has(id):
		printerr("--game: arena, dodge, pool, karts, pingpong, tap_race o hurdles")
		return 1
	var players := _players()
	MascotAtlas.prewarm_game(players, MiniGameRegistry.mascot_scale(id), MiniGameRegistry.mascot_prewarm(id))
	var view: BoardView25D = script.call("board_view")
	var t0 := Time.get_ticks_msec()
	var ok: bool = await Board25DBaker.ensure(root, view)
	print("Escenario 2.5D de %s: %s en %d ms %s" % [id, "listo" if ok else "FALLÓ", Time.get_ticks_msec() - t0, Board25DBaker.last_report])
	while not MascotAtlas.is_idle():
		await process_frame
	var shot := await _capture_game(script, id, players)
	shot.save_png(_out + id + "_25d.png")
	print("  ", _out + id + "_25d.png")
	Board25DBaker.enabled = false
	var before := await _capture_game(script, id, players)
	Board25DBaker.enabled = true
	before.save_png(_out + id + "_plano.png")
	print("  ", _out + id + "_plano.png")
	if compare != "":
		var panels := [[before, "Antes: tablero plano", true], [shot, "Ahora: 2.5D horneado (captura real)", true]]
		for d: Array in DETAILS[id]:
			panels.append([shot.get_region(Rect2i(d[0], Vector2i(960, 540))), d[1], false])
		await _compose(panels, compare)
	return 0 if ok else 1


## El juego en un estado fijo parecido a una partida (quieto: el estado lo pone la herramienta).
func _capture_game(script: GDScript, id: String, players: Array[Dictionary]) -> Image:
	var game: Node2D = script.new()
	root.add_child(game)
	game.setup(players)
	game.set_physics_process(false)
	match id:
		"arena":
			_arena_state(game)
		"dodge":
			_dodge_state(game)
		"pool":
			_pool_state(game)
		"karts":
			_karts_state(game)
		"pingpong":
			_pingpong_state(game)
		"tap_race":
			_tap_race_state(game)
		"hurdles":
			_hurdles_state(game)
	for i in 40:
		await process_frame
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	game.queue_free()
	await process_frame
	return img


## Arena: cada uno yendo hacia una estrella, marcador a mitad de partida.
func _arena_state(game: Node2D) -> void:
	var f: Rect2 = game.ARENA
	game._pos[1] = f.position + Vector2(640, 700)
	game._pos[2] = f.position + Vector2(1420, 470)
	game._pos[3] = f.position + Vector2(980, 90)
	game._pos[4] = f.position + Vector2(170, 420)
	var stars: Array[Vector2] = [f.position + Vector2(760, 640), f.position + Vector2(1290, 210), f.position + Vector2(420, 170),
		f.position + Vector2(300, 700), f.position + Vector2(1120, 560)]
	game._stars = stars
	game._axis[1] = Vector2(0.8, -0.3)
	game._score = {1: 7, 2: 5, 3: 6, 4: 3}
	game._time_left = 18.0
	game.anim_time = 4.0


## Esquivar: bloques cayendo a distintas alturas (con su sombra y aviso), uno
## apoyado, 4P eliminado (translúcido) y el resto esquivando.
func _dodge_state(game: Node2D) -> void:
	var f: Rect2 = game.FIELD
	game._countdown = -5.0
	game._elapsed = 17.0
	game._anim = 17.0
	game._pos[1] = f.position + Vector2(380, 560)
	game._pos[2] = f.position + Vector2(820, 300)
	game._pos[3] = f.position + Vector2(1240, 620)
	game._pos[4] = f.position + Vector2(1450, 250)
	game._out_time[4] = 11.4
	game._axis[1] = Vector2(-0.6, 0.2)
	game._axis[3] = Vector2(0.5, -0.5)
	var b := UiTheme.BRICKS
	game._blocks = [
		{"ground": f.position + Vector2(470, 470), "size": 120.0, "fall": 1.0, "t": 0.82, "color": b[4]},
		{"ground": f.position + Vector2(980, 420), "size": 100.0, "fall": 1.0, "t": 0.45, "color": b[0]},
		{"ground": f.position + Vector2(300, 200), "size": 110.0, "fall": 1.0, "t": 0.25, "color": b[2]},
		{"ground": f.position + Vector2(1120, 700), "size": 126.0, "fall": 1.0, "t": 1.15, "color": b[5]},
		{"ground": f.position + Vector2(1500, 560), "size": 96.0, "fall": 1.0, "t": 0.65, "color": b[6]},
	]


## Pool: 1P apuntando con fuerza (flecha y guía), doradas por la mesa, 3P
## esperando reaparecer y una bola cayendo en una tronera.
func _pool_state(game: Node2D) -> void:
	game._state = 1  # PLAYING
	game._countdown = -5.0
	game._time = 20.0
	game._time_left = 31.0
	var play: Rect2 = game.PLAY
	var at := {1: play.position + Vector2(260, 200), 2: play.position + Vector2(1080, 520), 3: play.position + Vector2(1150, 160),
		4: play.position + Vector2(300, 560)}
	for pid: int in at:
		var i: int = game._ball[pid]
		game._phys.place(i, at[pid])
		game._pos[pid] = at[pid]
	game._aim[1] = {"dir": Vector2(0.86, 0.5).normalized(), "power": 0.85, "t": 19.9}
	game._aim[2] = {"dir": Vector2(-1, -0.35).normalized(), "power": 0.5, "t": 19.9}
	# La última, pegada a la banda de adelante: la tapa la banda (vuelta 3).
	var spots: Array[Vector2] = [play.get_center(), play.get_center() + Vector2(60, -40), play.position + Vector2(640, 420),
		play.position + Vector2(900, 250), play.position + Vector2(180, 380), play.end - Vector2(120, 90), play.end - Vector2(470, 22)]
	for k in game._golds.size():
		game._phys.place(game._golds[k], spots[k % spots.size()])
	game._score = {1: 6, 2: 3, 3: 2, 4: 5}
	game._respawn[3] = 0.8
	game._phys.on_table[game._ball[3]] = 0
	game._effects.append({"kind": "pocket", "pos": game.pockets()[4], "t": 0.15, "power": 1.0})
	game._effects.append({"kind": "hit", "pos": play.position + Vector2(640, 420) + Vector2(-20, 10), "t": 0.1, "power": 0.8})


## Karts: a mitad de carrera, el pelotón repartido por la pista (uno con
## turbo, otro patinando en un charco), vuelta 2/3.
func _karts_state(game: Node2D) -> void:
	game._phase = 1  # RACING
	game._countdown = -5.0
	game._elapsed = 24.0
	game.anim_time = 24.0
	var tr: RefCounted = game.track()
	var spots := {1: [0.12, -30.0, 0.0, 0.0], 2: [0.155, 20.0, 0.9, 0.0], 3: [0.30, 24.0, 0.0, 0.6], 4: [0.62, -20.0, 0.0, 0.0]}
	for pid: int in spots:
		var k: RefCounted = game._karts[pid]
		var s: float = spots[pid][0] * tr.length
		k.pos = tr.point_at(s, spots[pid][1])
		k.heading = (tr.frame_at(s)[1] as Vector2).angle()
		k.vel = Vector2.from_angle(k.heading) * 300.0
		k.turbo = spots[pid][2]
		k.slip = spots[pid][3]
		k.dist = tr.length * (1.0 + spots[pid][0])
		k.steer = 0.3 if pid == 1 else 0.0
	game._effects.append({"pos": (game._karts[4] as RefCounted).pos + Vector2(20, -10), "t": 0.12, "power": 0.7})


## Ping Pong: la pelota recién golpeada por el de abajo, con estela, 3 a 2.
func _pingpong_state(game: Node2D) -> void:
	var t: Rect2 = game.TABLE
	game._ball = t.position + Vector2(300, 520)
	game._vel = Vector2(-0.35, -1.0).normalized() * 700.0
	game._serve_delay = 0.0
	game._since_hit = 0.3
	game._trail_col = (game.players[1] as Dictionary).color
	var trail := PackedVector2Array()
	for k in 7:
		trail.append(game._ball - game._vel * 0.016 * (7 - k))
	game._trail = trail
	game._paddle_x[game.players[0].id] = t.position.x + 260.0
	game._paddle_x[game.players[1].id] = t.position.x + 330.0
	game._score = {game.players[0].id: 2, game.players[1].id: 3}
	game.anim_time = 6.0


## Carrera de toques: a mitad de carrera, cada uno en un punto distinto.
func _tap_race_state(game: Node2D) -> void:
	game._countdown = -5.0
	var taps := {1: 22, 2: 31, 3: 12, 4: 27}
	for pid: int in taps:
		game._taps[pid] = taps[pid]
	game.anim_time = 9.0


## Carrera de obstáculos: cada uno en otro tramo (uno saltando una valla,
## otro sobre un escalón, otro caído en un pozo, otro corriendo).
func _hurdles_state(game: Node2D) -> void:
	game._countdown = -5.0
	game._elapsed = 14.0
	game.anim_time = 14.0
	game.use_course(game.build_course(7))
	var xs := {1: 2300.0, 2: 3100.0, 3: 1700.0, 4: 2650.0}
	for pid: int in xs:
		var r: RefCounted = game._runners[pid]
		r.x = xs[pid]
		r.speed = 380.0
	(game._runners[1] as RefCounted).y = 70.0
	(game._runners[1] as RefCounted).vy = 120.0
	(game._runners[1] as RefCounted).grounded = false
	# 3P: cayó en un pozo justo delante (se hunde y se tapa con el frente del pozo).
	var course: Array = game._course
	for o: Dictionary in course:
		if int(o.kind) == 1 and float(o.x) > 1400.0:  # PIT
			var r3: RefCounted = game._runners[3]
			r3.x = float(o.x) + float(o.w) * 0.5
			r3.fall = 0.6
			r3.pit_x0 = float(o.x)
			r3.pit_x1 = float(o.x) + float(o.w)
			break


## Comparación genérica: 2 × 2 paneles de 960 × 540 con título (los que
## tienen `true` se achican de 1920 × 1080; los otros son recortes a tamaño real).
func _compose(panels: Array, path: String) -> void:
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
