extends SceneTree
## Genera las miniaturas de los juegos (assets/thumbs/<id>.webp) que muestran
## la tarjeta del lobby y la pantalla "¿Cómo se juega?". Corre cada juego del
## registry de verdad, con jugadores de prueba que juegan solos, y guarda una
## foto recortada al área de juego (sin el marcador de arriba).
##
##   xvfb-run -a -s "-screen 0 1920x1080x24" godot --path . --rendering-driver opengl3 \
##     --audio-driver Dummy -s res://tools/make_thumbnails.gd
##   … -- --only=dodge            (un solo juego; ej. el que acabás de agregar)
##   … -- --out=/tmp/thumbs       (otra carpeta, para revisar sin pisar assets/)
##   … -- --full                  (además guarda <id>_full.png: la TV entera,
##                                 para elegir el recorte)
##
## Después, `godot --headless --path . --import` para que Godot importe los
## archivos nuevos (sin eso la tarjeta usa el dibujo de respaldo).
##
## Determinista: el juego avanza con pasos fijos de 1/60 s (no con el reloj
## real) y su generador de azar (`_rng`, si tiene) usa una semilla fija.
## Necesita pantalla (real o xvfb): con --headless Godot no dibuja.
##
## Encuadre: la foto es 16:9, pero la tarjeta del lobby muestra solo la
## franja del medio (CARD_BAND, ≈ 2,8:1) y chica (≈ 250 px de ancho): conviene
## un primer plano (recortes de 550–800 px de la TV). Lo importante (jugadores, pelota, reloj) tiene
## que quedar en esa franja; la intro "¿Cómo se juega?" muestra la foto entera.

const OUT_DIR := "res://assets/thumbs/"
const EXT := ".webp"
const SIZE := Vector2i(640, 360)
const WEBP_QUALITY := 0.9
const STEP := 1.0 / 60.0
const SEED := 2026
const NAMES: Array[String] = ["Pablo", "Sofi", "Tomi", "Juli"]
const TV := Vector2i(1920, 1080)
## Proporción (ancho / alto) de la franja que muestra la tarjeta del lobby.
const CARD_BAND := 2.8

## Cómo se saca la foto de cada juego:
##   sec     segundos de juego antes de la foto (incluye la cuenta regresiva).
##   crop    rectángulo de la TV (1920×1080) que se guarda, en 16:9.
##   orbit   (joystick, juegos con `_pos`) los jugadores de prueba caminan en
##           ronda alrededor de `c` con radios `r`; `spread` separa a cada uno
##           hacia su esquina (ej. para que en Pintar cada uno pinte su zona).
##   items   lista del juego con lo que vale la pena mostrar: "_stars"
##           (posiciones) o "_blocks" (diccionarios con "ground"; cuentan los
##           que ya están llegando al piso).
##   chase   cada jugador corre a su `item` más cercano (como un jugador real).
##   evade   los jugadores se apartan de los `items` que les van a caer encima.
##   follow  el recorte (del tamaño de `crop`) se ubica donde más jugadores e
##           `items` entran en la franja de la tarjeta.
##   wait    después de `sec`, seguir hasta que la franja tenga al menos
##           {players, items} y nadie esté eliminado (tope: 15 s más).
##   ball_in (juegos con `_ball`) después de `sec`, esperar a que la pelota
##           pase por ese rectángulo (así sale en la foto).
##   seed    semilla propia (si la común no deja nada lindo en el encuadre).
## Un juego que no esté acá usa DEFAULT_SHOT: el campo estándar de
## draw_play_field, con los jugadores dando vueltas por el centro.
const DEFAULT_SHOT := {
	"sec": 5.0, "crop": Rect2(400, 250, 1120, 630),
	"orbit": {"c": Vector2(960, 600), "r": Vector2(260, 170), "spread": Vector2.ZERO},
}
const SHOTS := {
	"arena": {
		"sec": 3.0, "crop": Rect2(0, 0, 520, 293), "items": "_stars", "chase": true, "follow": true, "seed": 1,
		"wait": {"players": 2, "items": 1},
	},
	"pingpong": {"sec": 2.0, "crop": Rect2(1150, 720, 640, 360), "ball_in": Rect2(1170, 790, 140, 110)},
	"tap_race": {"sec": 8.0, "crop": Rect2(1015, 135, 760, 428)},
	"stop_clock": {"sec": 4.6, "crop": Rect2(620, 100, 820, 461)},
	"dodge": {
		"sec": 9.0, "crop": Rect2(0, 0, 480, 270), "items": "_blocks", "evade": true, "follow": true, "seed": 1,
		"wait": {"players": 2, "items": 1},
		"orbit": {"c": Vector2(960, 610), "r": Vector2(170, 80), "spread": Vector2.ZERO},
	},
	"paint": {
		"sec": 9.0, "crop": Rect2(740, 406, 440, 248),
		"orbit": {"c": Vector2(960, 600), "r": Vector2(50, 25), "spread": Vector2(120, 40)},
	},
	"sumo": {"sec": 3.85, "crop": Rect2(692, 405, 480, 270)},
	"karts": {"sec": 8.0, "crop": Rect2(0, 0, 620, 349), "follow": true},
	"scroller": {
		"sec": 6.5, "crop": Rect2(360, 200, 1000, 562), "seed": 3,
		"orbit": {"c": Vector2(1150, 380), "r": Vector2(110, 70), "spread": Vector2(70, 110)},
	},
	# Memoria: la secuencia de la ronda 1 con un botón encendido; los
	# jugadores de prueba no la repiten (con el joystick girando no pasan por
	# el centro), así que la foto es mientras la TV la muestra.
	"memory": {"sec": 4.1, "crop": Rect2(210, 200, 1088, 612)},
	"quickdraw": {"sec": 1.15, "crop": Rect2(480, 330, 960, 540)},
	# Pool loco: los de prueba apuntan (joystick estirado) hacia las doradas del centro.
	"pool": {
		"sec": 12.0, "crop": Rect2(300, 148, 1000, 562),
		"orbit": {"c": Vector2(960, 578), "r": Vector2(30, 20), "spread": Vector2.ZERO},
	},
}

var _out_dir := OUT_DIR
var _only := ""
var _full := false
var _seed_override := -1  ## `--seed=N`: probar otra semilla para elegir encuadre.
var _viewport: SubViewport


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			_out_dir = arg.trim_prefix("--out=").trim_suffix("/") + "/"
		elif arg.begins_with("--only="):
			_only = arg.trim_prefix("--only=")
		elif arg == "--full":
			_full = true
		elif arg.begins_with("--seed="):
			_seed_override = int(arg.trim_prefix("--seed="))
	DirAccess.make_dir_recursive_absolute(_out_dir)
	_viewport = SubViewport.new()
	_viewport.size = TV
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(_viewport)
	var made := 0
	for info in MiniGameRegistry.all_info():
		if _only != "" and info.id != _only:
			continue
		await _make(info)
		made += 1
	if made == 0:
		printerr("No hay ningún juego con id '%s' en el registry." % _only)
		quit(1)
		return
	print("Miniaturas guardadas en ", ProjectSettings.globalize_path(_out_dir))
	print("Ahora: godot --headless --path . --import")
	quit(0)


func _make(info: Dictionary) -> void:
	var shot: Dictionary = SHOTS.get(info.id, DEFAULT_SHOT)
	var game := MiniGameRegistry.create(info.id)
	# El juego no corre solo: lo avanza este script con pasos fijos.
	game.process_mode = Node.PROCESS_MODE_DISABLED
	_viewport.add_child(game)
	game.setup(_players(int(info.max_players)))
	_seed(game, _seed_override if _seed_override >= 0 else int(shot.get("seed", SEED)))
	var steps := roundi(float(shot.sec) / STEP)
	var max_steps := steps + roundi(15.0 / STEP)  # Tope de la espera (`ball_in`, `wait`).
	var i := 0
	while i < max_steps and not game.is_finished():
		if i >= steps and i % 5 == 0 and _ready_for_shot(shot, game, _crop(shot, game)):
			break
		for k in game.players.size():
			game.on_input(game.players[k].id, _bot_input(info, shot, game, k, i))
		game._physics_process(STEP)
		game._process(STEP)
		# Cada tanto un frame real: el reloj real avanza (Carrera de toques
		# limita toques por segundo con él) y la ventana sigue viva.
		if i % 4 == 0:
			await process_frame
		i += 1
	var hud: Variant = game.get("_hud")
	if hud is CanvasItem:
		(hud as CanvasItem).visible = false  # La foto va sin marcador.
	game.queue_redraw()
	await process_frame
	await RenderingServer.frame_post_draw
	var img := _viewport.get_texture().get_image()
	if _full:
		img.save_png(_out_dir + info.id + "_full.png")
	var thumb := img.get_region(Rect2i(_crop(shot, game)))
	thumb.resize(SIZE.x, SIZE.y, Image.INTERPOLATE_LANCZOS)
	var path: String = _out_dir + info.id + EXT
	thumb.save_webp(path, true, WEBP_QUALITY)
	_ensure_import_settings(path)
	print("  %s%s  (%d KB)" % [info.id, EXT, FileAccess.get_file_as_bytes(path).size() / 1024])
	game.queue_free()
	await process_frame


## Jugadores de prueba con la apariencia clásica de cada lugar (1P rojo con
## antena, 2P azul con orejas, …), como los que ve cualquiera la primera vez.
func _players(n: int) -> Array[Dictionary]:
	var list: Array[Dictionary] = []
	for i in n:
		list.append({"id": i + 1, "slot": i, "name": NAMES[i % NAMES.size()], "color": Protocol.player_color(i),
			"color_index": i, "style": i, "connected": true})
	return list


## Semilla fija para el azar del juego (bloques, estrellas, saque…). Los
## juegos la eligen en setup(); se pisa después y, si el juego ya sorteó
## algo (las estrellas de Arena), se vuelve a sortear con la semilla.
func _seed(game: MiniGame, value: int) -> void:
	var rng: Variant = game.get("_rng")
	if not rng is RandomNumberGenerator:
		return
	(rng as RandomNumberGenerator).seed = value
	if game.has_method("_random_star"):
		var stars: Array = game.get("_stars")
		for i in stars.size():
			stars[i] = game.call("_random_star")


## Rectángulo de la TV que se guarda: `crop`, o con `follow` el del mismo
## tamaño que muestra más jugadores y `items` en la franja de la tarjeta.
func _crop(shot: Dictionary, game: MiniGame) -> Rect2:
	var crop: Rect2 = shot.crop
	if not shot.get("follow", false):
		return crop
	var best := crop
	var best_score := -1.0
	var free := Vector2(TV) - crop.size
	for y in range(0, int(free.y) + 1, 40):
		for x in range(0, int(free.x) + 1, 40):
			var r := Rect2(Vector2(x, y), crop.size)
			var n := _count_in_band(shot, game, r)
			# A igual puntaje, el más centrado en la TV.
			var score := n.x * 3.0 + n.y - r.get_center().distance_to(Vector2(TV) / 2.0) / 10000.0
			if score > best_score:
				best_score = score
				best = r
	return best


## Franja del medio del recorte: lo que se ve en la tarjeta del lobby.
func _card_band(crop: Rect2) -> Rect2:
	var h := crop.size.x / CARD_BAND
	return Rect2(crop.position.x, crop.get_center().y - h / 2.0, crop.size.x, h)


## Cuántos jugadores (x) e `items` (y) se ven en la franja de la tarjeta:
## enteros y sin quedar tapados por el chip del control (abajo a la
## izquierda) ni por el tilde (arriba a la derecha).
func _count_in_band(shot: Dictionary, game: MiniGame, crop: Rect2) -> Vector2:
	var band := _card_band(crop)
	var n := Vector2.ZERO
	for p in _player_positions(game):
		# La mascota se dibuja hacia arriba de los pies (≈ 90 px) y el nombre abajo.
		if band.grow_individual(-30, -85, -30, -30).has_point(p) and _visible_in_card(band, p - Vector2(0, 40)):
			n.x += 1
	for item in _items(shot, game):
		if band.grow(-30).has_point(item) and _visible_in_card(band, item):
			n.y += 1
	return n


func _visible_in_card(band: Rect2, p: Vector2) -> bool:
	var chip := Rect2(band.position.x, band.position.y + band.size.y * 0.55, band.size.x * 0.4, band.size.y * 0.45)
	var badge := Rect2(band.end.x - band.size.x * 0.2, band.position.y, band.size.x * 0.2, band.size.y * 0.5)
	return not chip.has_point(p) and not badge.has_point(p)


## ¿Ya se puede sacar la foto? (ver `ball_in` y `wait` en SHOTS).
func _ready_for_shot(shot: Dictionary, game: MiniGame, crop: Rect2) -> bool:
	var ball: Variant = game.get("_ball")
	if shot.has("ball_in") and ball is Vector2:
		return (shot.ball_in as Rect2).has_point(ball)
	if shot.has("wait"):
		var out: Variant = game.get("_out_time")
		if out is Dictionary and not (out as Dictionary).is_empty():
			return false  # Alguien eliminado: se ve apagado, mejor otro momento.
		var n := _count_in_band(shot, game, crop)
		return n.x >= int(shot.wait.players) and n.y >= int(shot.wait.items)
	return true


func _player_positions(game: MiniGame) -> Array[Vector2]:
	var list: Array[Vector2] = []
	var pos: Variant = game.get("_pos")
	if pos is Dictionary:
		for v: Variant in (pos as Dictionary).values():
			if v is Vector2:
				list.append(v)
	return list


## Posiciones de los `items` del juego (estrellas, dónde caen los bloques…).
func _items(shot: Dictionary, game: MiniGame, only_landing: bool = true) -> Array[Vector2]:
	var list: Array[Vector2] = []
	var raw: Variant = game.get(str(shot.get("items", ""))) if shot.has("items") else null
	if raw is Array:
		for v: Variant in raw:
			if v is Vector2:
				list.append(v)
			elif v is Dictionary and (v as Dictionary).get("ground") is Vector2:
				# Bloques: solo los que ya llegan al piso (en el aire se ve la sombra).
				if not only_landing or float(v.get("t", 0.0)) >= float(v.get("fall", 0.0)) - 0.25:
					list.append(v.ground)
	return list


## Cómo juega cada jugador de prueba `k` en el paso `i`:
##   joystick  va a su estrella (`chase`) o camina en ronda (`orbit`) y se
##             aparta de lo que cae (`evade`); en Empujones van al centro a chocar.
##   botón     toca a ritmos distintos (en Reloj exacto dos ya frenaron).
##   deslizar  sigue la pelota con un poco de error.
func _bot_input(info: Dictionary, shot: Dictionary, game: MiniGame, k: int, i: int) -> Dictionary:
	var t := i * STEP
	var axis := Vector2.ZERO
	var btn := 0
	var pos: Variant = game.get("_pos")
	var me: Vector2 = (pos as Dictionary).get(game.players[k].id, Vector2.ZERO) if pos is Dictionary else Vector2.ZERO
	match str(info.layout):
		Protocol.LAYOUT_JOYSTICK:
			if info.id == "sumo":
				var center: Vector2 = _const(game, "CENTER", MiniGame.SCREEN / 2.0)
				axis = ((center - me).limit_length(80.0) / 80.0).rotated(sin(t * 2.0 + k) * 0.6)
			elif pos is Dictionary and shot.get("chase", false):
				var target := _chase_target(shot, game, k, me)
				if target != Vector2.INF:
					axis = ((target - me) / 90.0).limit_length(1.0)
			elif pos is Dictionary and shot.has("orbit"):
				var o: Dictionary = shot.orbit
				var corner := Vector2(-1 if k % 2 == 0 else 1, -1 if k < 2 else 1)
				var angle := t * 1.3 + k * TAU / 4.0
				var target: Vector2 = o.c + corner * (o.spread as Vector2) \
					+ Vector2(cos(angle), sin(angle)) * (o.r as Vector2)
				axis = ((target - me) / 90.0).limit_length(1.0)
			else:
				axis = Vector2.from_angle(t * (1.1 + k * 0.35) + k * 2.1)
			if shot.get("evade", false):
				for item in _items(shot, game, false):
					var away := me - item
					if away.length() < 190.0:
						axis += away.normalized() * 2.0 * (1.0 - away.length() / 190.0)
				axis = axis.limit_length(1.0)
		Protocol.LAYOUT_ONE_BUTTON:
			if info.id == "stop_clock":
				btn = Protocol.BTN_A if k in [1, 3] and absf(t - (3.9 + k * 0.1)) < 0.05 else 0
			else:
				var period: int = [8, 9, 10, 11][k % 4]  # Pasos entre toques.
				btn = Protocol.BTN_A if i % period < floori(period / 2.0) else 0
		Protocol.LAYOUT_SLIDER_H:
			var ball: Variant = game.get("_ball")
			var table: Variant = _const(game, "TABLE", null)
			if ball is Vector2 and table is Rect2:
				var r: Rect2 = table
				var x := (ball as Vector2).x + sin(t * 3.0 + k) * 50.0
				axis.x = clampf((x - r.position.x) / r.size.x * 2.0 - 1.0, -1.0, 1.0)
			else:
				axis.x = sin(t * 1.5 + k * 1.7)
	return {"seq": i, "axis": axis, "btn": btn}


## `item` al que va el jugador `k`: el más cercano que no tenga a otro
## jugador más cerca (así no corren todos a la misma estrella).
func _chase_target(shot: Dictionary, game: MiniGame, k: int, me: Vector2) -> Vector2:
	var others := _player_positions(game)
	others.erase(me)
	var best := Vector2.INF
	for item in _items(shot, game):
		var mine := me.distance_to(item)
		var taken := false
		for o in others:
			if o.distance_to(item) < mine:
				taken = true
		if not taken and (best == Vector2.INF or mine < me.distance_to(best)):
			best = item
	return best


## Constante del script del juego (ej. el centro de la isla o la mesa).
func _const(game: MiniGame, const_name: String, fallback: Variant) -> Variant:
	return (game.get_script() as Script).get_script_constant_map().get(const_name, fallback)


## Las miniaturas se ven chicas en la tarjeta: con mipmaps se achican sin
## serrucho. Si el archivo es nuevo, se deja un .import con esa opción antes
## de que Godot lo importe (los que ya existen no se tocan).
func _ensure_import_settings(path: String) -> void:
	if not path.begins_with("res://") or FileAccess.file_exists(path + ".import"):
		return
	var f := FileAccess.open(path + ".import", FileAccess.WRITE)
	if f == null:
		return
	f.store_string('[remap]\n\nimporter="texture"\ntype="CompressedTexture2D"\n\n[params]\n\nmipmaps/generate=true\n')
