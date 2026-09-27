extends SceneTree
## Tests automáticos, sin dependencias externas. Se corren headless:
##   godot --headless --path . -s res://tests/run_tests.gd
## Sale con código 0 si todo pasa y 1 si algo falla (lo usa la CI).

## Puertos de test por DEBAJO del rango efímero de Linux (32768–60999). En
## ese rango el sistema elige al azar el puerto local de cada conexión
## saliente: si un cliente de un test anterior quedaba en, por ejemplo, el
## 47994, la TV del test siguiente no podía abrir ese puerto y fallaba de
## forma intermitente en la CI.
const TEST_PORT := 28990

var _passed := 0
var _failed := 0
var _current := ""


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	print("\n=== Party Games · tests ===\n")
	for method in get_method_list():
		var n: String = method.name
		if n.begins_with("test_"):
			_current = n
			var before := _failed
			await call(n)
			print(("  ok    " if _failed == before else "  FALLA ") + n)
	print("\n%d ok, %d fallas\n" % [_passed, _failed])
	await process_frame
	quit(1 if _failed > 0 else 0)


func check(cond: bool, what: String) -> void:
	if cond:
		_passed += 1
	else:
		_failed += 1
		printerr("    [%s] %s" % [_current, what])


## Como check, pero devuelve el resultado: para cortar un test cuyo resto
## no tiene sentido (y no romper con un error de script) si esto falla.
func check_that(cond: bool, what: String) -> bool:
	check(cond, what)
	return cond


# --- Protocolo ------------------------------------------------------------------

func test_room_code_generation() -> void:
	var seen := {}
	for i in 200:
		var code := Protocol.generate_room_code()
		check(Protocol.is_valid_room_code(code), "código inválido generado: %s" % code)
		seen[code] = true
	check(seen.size() > 150, "los códigos se repiten demasiado (%d únicos de 200)" % seen.size())


func test_room_code_validation() -> void:
	check(Protocol.is_valid_room_code("AB23"), "AB23 debería ser válido")
	check(not Protocol.is_valid_room_code("AB2"), "longitud corta")
	check(not Protocol.is_valid_room_code("ABCDE"), "longitud larga")
	check(not Protocol.is_valid_room_code("AB0I"), "0 e I son ambiguos, no están en el alfabeto")
	check(not Protocol.is_valid_room_code("abcd"), "minúsculas sin normalizar")
	check(not Protocol.is_valid_room_code(1234), "no string")
	check(Protocol.normalize_room_code(" ab 23 ") == "AB23", "normalización")


func test_token() -> void:
	var a := Protocol.generate_token()
	var b := Protocol.generate_token()
	check(a.length() == 32 and Protocol.is_valid_token(a), "formato de token")
	check(a != b, "tokens únicos")
	check(not Protocol.is_valid_token("zz" + a.substr(2)), "hex inválido")
	check(not Protocol.is_valid_token(null), "null")


func test_sanitize_name() -> void:
	check(Protocol.sanitize_name("  Pablo  ") == "Pablo", "recorta espacios")
	check(Protocol.sanitize_name("Pa\nb\tlo\u0007") == "Pablo", "quita caracteres de control")
	check(Protocol.sanitize_name("x".repeat(50)).length() == Protocol.NAME_MAX_LENGTH, "trunca")
	check(Protocol.sanitize_name("Ñandú 🎮") == "Ñandú 🎮", "acepta unicode")
	check(Protocol.sanitize_name(42) == "", "no string")
	check(Protocol.sanitize_name("   ") == "", "vacío")


func test_decode() -> void:
	check(Protocol.decode("") == {}, "vacío")
	check(Protocol.decode("no json") == {}, "json inválido")
	check(Protocol.decode("[1,2]") == {}, "no objeto")
	check(Protocol.decode('{"v":1}') == {}, "sin type")
	check(Protocol.decode('{"type":"x"}') == {}, "sin versión")
	var big := '{"v":1,"type":"input","pad":"%s"}' % "x".repeat(Protocol.MAX_MESSAGE_BYTES)
	check(Protocol.decode(big) == {}, "mensaje demasiado grande")
	var ok := Protocol.decode(Protocol.encode(Protocol.T_PING, {"t": 5}))
	check(ok.get("type") == Protocol.T_PING and int(ok.get("t")) == 5, "ida y vuelta encode/decode")
	check(Protocol.is_supported_version(ok), "versión soportada")
	check(not Protocol.is_supported_version({"v": 99}), "versión futura")


func test_parse_input() -> void:
	var r := Protocol.parse_input({"seq": 3, "axis": [0.5, -0.25], "btn": 1})
	check(r.seq == 3 and r.axis == Vector2(0.5, -0.25) and r.btn == 1, "input válido")
	r = Protocol.parse_input({"seq": 1, "axis": [50, -50], "btn": 255})
	check((r.axis as Vector2).length() <= 1.0001, "recorta el eje a longitud 1")
	check(r.btn == Protocol.BTN_MASK, "enmascara botones desconocidos")
	check(Protocol.parse_input({"seq": 1, "axis": [1]}) == {}, "eje incompleto")
	check(Protocol.parse_input({"seq": 1, "axis": ["a", 0]}) == {}, "eje no numérico")
	check(Protocol.parse_input({"axis": [0, 0]}) == {}, "sin seq")


func test_parse_standing() -> void:
	var ok := {"round": 1, "total_rounds": 3, "place": 2, "points": 70, "total": 170, "rank": 2, "players": 4, "final": false}
	var r := Protocol.parse_standing(ok)
	check(r == ok, "standing válido (%s)" % r)
	# Tal como llega por la red: JSON convierte los números en float.
	r = Protocol.parse_standing(Protocol.decode(Protocol.encode(Protocol.T_STANDING, ok)))
	check(r == ok and typeof(r.total) == TYPE_INT, "ida y vuelta por JSON")
	var bad := ok.duplicate()
	bad.place = "2"
	check(Protocol.parse_standing(bad) == {}, "tipo incorrecto")
	bad = ok.duplicate()
	bad.final = 1
	check(Protocol.parse_standing(bad) == {}, "final no booleano")
	bad = ok.duplicate()
	bad.total = NAN
	check(Protocol.parse_standing(bad) == {}, "NaN")
	bad = ok.duplicate()
	bad.points = INF
	check(Protocol.parse_standing(bad) == {}, "infinito")
	for key in ok:
		bad = ok.duplicate()
		bad.erase(key)
		check(Protocol.parse_standing(bad) == {}, "falta %s" % key)
	check(Protocol.parse_standing({}) == {}, "vacío")
	var wild := {"round": 500, "total_rounds": -3, "place": 9, "points": -50, "total": 1e300, "rank": 0, "players": 99, "final": true}
	r = Protocol.parse_standing(wild)
	check(r.round == Protocol.MAX_ROUNDS and r.total_rounds == Protocol.MAX_ROUNDS, "rondas recortadas (%s)" % r)
	check(r.place == Protocol.MAX_PLAYERS and r.rank == 1 and r.players == Protocol.MAX_PLAYERS, "puestos recortados (%s)" % r)
	check(r.points == 0 and r.total == Protocol.MAX_STANDING_POINTS, "puntos recortados (%s)" % r)
	r = Protocol.parse_standing({"round": 1, "total_rounds": 1, "place": 0, "points": 0, "total": 0, "rank": 3, "players": 2, "final": true})
	check(r.place == 0 and r.players == 3, "place 0 = sin puesto; players nunca menor que rank")


# --- Código de terceros (ver CREDITS.md) -------------------------------------------

## QR para unirse (`addons/pmc_qr/`, MIT). Compara módulo por módulo con un QR
## hecho por un codificador independiente (segno, en Python) con el mismo
## texto, versión, corrección y máscara, guardado en tests/data/. Si una
## actualización del addon rompe la codificación, falla acá y no en el
## celular de alguien en el sillón. La referencia se regenera con
## `segno.make(url, error="m", mode="byte", version=3, mask=2).matrix`
## (una fila de 0/1 por línea).
func test_join_qr() -> void:
	var tool: Script = load("res://tools/make_join_qr.gd")
	var url: String = tool.join_url("192.168.1.87", Protocol.WS_PORT, "AB23")
	check(url == "partygame://join?ip=192.168.1.87&code=AB23", "enlace para unirse: %s" % url)
	check((tool.join_url("10.0.0.2", 47800, "XY99") as String).ends_with("&port=47800"), "el puerto va solo si no es el de siempre")
	var auto: PMCQrMatrix = tool.encode(url)
	if not check_that(auto != null and auto.version == 3 and auto.size == 29, "el enlace típico entra en la versión 3 (29 × 29)"):
		return
	check((tool.encode(url) as PMCQrMatrix).modules == auto.modules, "determinista: mismo texto, mismo QR (se puede cachear)")
	var golden := FileAccess.get_file_as_string("res://tests/data/qr_join_v3m_mask2.txt").strip_edges().split("\n")
	var fixed := PMCQr.encode_advanced(url, PMCQr.ECC_M, 3, 3, 2, "byte")
	if not check_that(golden.size() == 29 and fixed != null and fixed.size == 29, "referencia de 29 filas"):
		return
	var diff := 0
	for y in 29:
		for x in 29:
			if (golden[y][x] == "1") != fixed.get_module(x, y):
				diff += 1
	check(diff == 0, "%d módulos distintos de la referencia independiente" % diff)
	check(PMCQr.encode("x".repeat(3000), PMCQr.ECC_M) == null, "texto demasiado largo -> null, sin error")
	# Imagen: margen de 4 módulos claro y patrón localizador oscuro, con colores de UiTheme.
	var img: Image = tool.to_image(auto, 4)
	check(img.get_width() == (29 + 8) * 4, "ancho con margen: %d" % img.get_width())
	var paper := img.get_pixel(0, 0)
	var ink := img.get_pixel(16, 16)
	check(absf(paper.r - UiTheme.PAPER.r) < 0.01 and absf(ink.r - UiTheme.INK.r) < 0.01 and absf(ink.b - UiTheme.INK.b) < 0.01, "tinta sobre papel")


# --- Minijuegos -----------------------------------------------------------------

func test_registry_games_are_valid() -> void:
	var ids := {}
	for info in MiniGameRegistry.all_info():
		check(not ids.has(info.id), "id duplicado: %s" % info.id)
		ids[info.id] = true
		check(info.layout in Protocol.LAYOUTS, "%s: layout desconocido" % info.id)
		check(info.min_players >= 1 and info.max_players <= Protocol.MAX_PLAYERS and info.min_players <= info.max_players,
			"%s: rango de jugadores" % info.id)
		check(MiniGameRegistry.create(info.id) is MiniGame, "%s: se puede instanciar" % info.id)
	check(MiniGameRegistry.create("no-existe") == null, "id inexistente devuelve null")


func test_games_run_headless() -> void:
	for info in MiniGameRegistry.all_info():
		var game := MiniGameRegistry.create(info.id)
		var players: Array[Dictionary] = []
		for i in info.max_players:
			players.append({"id": i + 1, "slot": i, "name": "P%d" % (i + 1), "color": Protocol.player_color(i), "connected": true})
		root.add_child(game)
		game.setup(players)
		for f in 30:
			for p in players:
				game.on_input(p.id, {"seq": f, "axis": Vector2(1, 0.3), "btn": f % 2})
			await physics_frame
		game.on_player_disconnected(1)
		await physics_frame
		check(is_instance_valid(game), "%s: sigue vivo tras 30 frames" % info.id)
		game.queue_free()


## Esquivar: si un bloque aplasta a uno de dos jugadores, gana el otro y
## el juego termina una sola vez.
func test_dodge_elimination() -> void:
	var game: Variant = MiniGameRegistry.create("dodge")  # sin tipo: usa métodos propios del juego
	var players := _fake_players(2)
	root.add_child(game)
	game.setup(players)
	var results: Array = []
	game.finished.connect(func(r: Dictionary) -> void: results.append(r))
	game._spawn_block(game._pos[1], 120.0, 0.0)  # cae ya, sobre Pablo
	for i in 12:  # (la pausa de impacto congela unos frames)
		await physics_frame
	check(game.in_finale() and results.is_empty(), "festeja antes de terminar (¡Último en pie!)")
	check(game.is_celebrating(2) and not game.is_celebrating(1), "festeja la que sigue en pie")
	game._finale_left = 0.0  # Sin esperar el festejo entero.
	await process_frame
	await process_frame
	check(results.size() == 1, "termina al quedar uno en pie (%d)" % results.size())
	if results.size() == 1:
		var r: Dictionary = results[0]
		check(r.winners == [2], "gana Sofi, la que sigue en pie (%s)" % [r.winners])
		check(float(r.scores[2]) >= float(r.scores[1]), "el que sigue en pie tiene el máximo puntaje")
	game._spawn_block(game._pos[2], 120.0, 0.0)
	game.finish({"winners": [1], "scores": {}})
	await physics_frame
	await physics_frame
	check(results.size() == 1, "finished se emite una sola vez (%d)" % results.size())
	check(game.get_info().score_label == "segundos", "puntaje en segundos")
	game.queue_free()
	await process_frame


## Pintar el piso: posición -> celda (con bordes), pintar y robar, brocha
## 3×3 recortada y que el conteo final coincida con los puntajes.
func test_paint_rules() -> void:
	var script: Script = preload("res://host/minigames/paint/paint.gd")
	var field: Rect2 = script.FIELD
	var cell: float = script.CELL
	var cols: int = script.COLS
	var rows: int = script.ROWS
	check(cols * rows >= 200 and field.end.y <= MiniGame.SCREEN.y - UiTheme.SAFE_MARGIN, "grilla de ~20×11 dentro del margen")
	# Posición -> celda
	check(script.cell_at(field.position) == Vector2i(0, 0), "esquina superior izquierda = (0, 0)")
	check(script.cell_at(field.position + Vector2(cell - 0.01, cell - 0.01)) == Vector2i(0, 0), "justo antes del borde sigue en (0, 0)")
	check(script.cell_at(field.position + Vector2(cell, 0)) == Vector2i(1, 0), "en el borde pasa a la siguiente columna")
	check(script.cell_at(field.end) == Vector2i(cols - 1, rows - 1), "el borde inferior derecho es la última celda")
	check(script.cell_at(field.end - Vector2(0.01, 0.01)) == Vector2i(cols - 1, rows - 1), "dentro de la última celda")
	check(script.cell_at(field.position - Vector2(1, 0)) == Vector2i(-1, -1), "fuera del campo (izquierda) es inválida")
	check(script.cell_at(field.end + Vector2(0, 1)) == Vector2i(-1, -1), "fuera del campo (abajo) es inválida")
	check(script.cell_at(script.cell_center(Vector2i(7, 4))) == Vector2i(7, 4), "el centro de una celda vuelve a esa celda")
	# Brocha: 3×3 en el medio, recortada en bordes y esquinas.
	check(script.brush_rect(Vector2i(5, 5), 1) == Rect2i(4, 4, 3, 3), "brocha 3×3 en el medio")
	check(script.brush_rect(Vector2i(0, 0), 1) == Rect2i(0, 0, 2, 2), "brocha recortada en la esquina superior izquierda")
	check(script.brush_rect(Vector2i(cols - 1, rows - 1), 1) == Rect2i(cols - 2, rows - 2, 2, 2), "brocha recortada en la esquina inferior derecha")
	check(script.brush_rect(Vector2i(cols - 1, 5), 1) == Rect2i(cols - 2, 4, 2, 3), "brocha recortada en el borde derecho")
	check(script.brush_rect(Vector2i(3, 3), 0) == Rect2i(3, 3, 1, 1), "sin brocha pinta una sola celda")
	check(script.brush_rect(Vector2i(-1, -1), 1).size == Vector2i.ZERO, "celda inválida no pinta nada")

	# Pintar y robar (sin agregar al árbol: no corre _physics_process).
	var game: Variant = MiniGameRegistry.create("paint")
	game.setup(_fake_players(2))
	var at: Vector2 = script.cell_center(Vector2i(10, 5))
	check(game._paint_area(1, at, 0) == 1 and game._tiles[1] == 1, "Pablo pinta una baldosa")
	check(game._paint_area(1, at, 0) == 0 and game._tiles[1] == 1, "pisar la propia no suma")
	check(game._paint_area(2, at, 0) == 1 and game._tiles[1] == 0 and game._tiles[2] == 1, "Sofi se la roba")
	check(game._paint_area(1, field.position, 1) == 4 and game._tiles[1] == 4, "brocha en la esquina pinta 4")
	check(game._paint_area(2, at, 1) == 8 and game._tiles[2] == 9, "brocha en el medio pinta 9 (una ya era suya)")
	check(game._paint_area(1, field.position - Vector2(50, 50), 1) == 0, "fuera del campo no pinta")
	# Power-ups: velocidad ×1,6 y brocha 3×3 al agarrarlos.
	game._pos[1] = script.cell_center(Vector2i(15, 8))
	game._spawn_powerup(Vector2i(15, 8), script.PowerUp.SPEED)
	game._check_pickup()
	check(game._powerup.is_empty() and is_equal_approx(game._speed_of(1), script.SPEED * script.SPEED_BOOST), "velocidad ×1,6")
	game._spawn_powerup(Vector2i(15, 8), script.PowerUp.BRUSH)
	game._check_pickup()
	var before: int = game._tiles[1]
	game._paint_all()
	check(game._tiles[1] == before + 9, "con la brocha pinta 3×3 (%d)" % (game._tiles[1] - before))
	game.free()

	# Final: "¡Tiempo!" y después los puntajes = baldosas de cada uno.
	for n in [1, 3]:
		var g: Variant = MiniGameRegistry.create("paint")
		var results: Array = []
		g.finished.connect(func(r: Dictionary) -> void: results.append(r))
		root.add_child(g)
		g.setup(_fake_players(n))
		g._paint_area(1, field.position, 1)
		if n > 1:
			g._paint_area(2, field.end, 1)
			g._paint_area(3, field.position, 0)  # le roba una a Pablo
		g._countdown = 0.0
		g._state = g.State.PLAYING
		g._time_left = 0.01
		await physics_frame
		await physics_frame
		check(g._state == g.State.TIME_UP and results.is_empty(), "%d jug.: muestra ¡Tiempo! antes de terminar" % n)
		g._end_wait = 0.0
		await physics_frame
		await physics_frame
		check(results.size() == 1, "%d jug.: termina una sola vez" % n)
		if results.size() == 1:
			var counted := {}
			for owner: int in g._owner:
				if owner != script.EMPTY:
					counted[owner] = int(counted.get(owner, 0)) + 1
			var ok := true
			for p in g.players:
				ok = ok and int(results[0].scores[p.id]) == int(counted.get(p.id, 0))
			check(ok, "%d jug.: puntajes = baldosas pintadas (%s vs %s)" % [n, results[0].scores, counted])
			check(int(results[0].scores[1]) > 0, "%d jug.: con la brocha inicial Pablo tiene baldosas" % n)
		g.queue_free()
	check(script.get_info().score_label == "baldosas", "puntaje en baldosas")


## Empujones: choque entre círculos, caída fuera de la isla, bonus por
## tirar a un rival y un único `finished` con los que siguen en pie.
func test_sumo_physics() -> void:
	var script: Script = load("res://host/minigames/sumo/sumo.gd")
	# Choque: A embiste a B (quieto) hacia la derecha.
	var r: Dictionary = script.resolve_collision(Vector2(0, 0), Vector2(500, 0), Vector2(60, 0), Vector2.ZERO, 72.0)
	check(r.hit, "detecta el choque si se superponen")
	var vb: Vector2 = r.vb
	var va: Vector2 = r.va
	check(vb.x > 500.0 and absf(vb.y) < 0.001, "B sale en la dirección del empujón y con bonus (%s)" % vb)
	check(va.x < vb.x, "A queda más lento que B (%s)" % va)
	check((r.pb as Vector2).distance_to(r.pa) >= 72.0 - 0.01, "los cuerpos quedan separados")
	check((vb - va).dot(Vector2.RIGHT) > 0.0, "después del choque se alejan")
	var diag: Dictionary = script.resolve_collision(Vector2(0, 0), Vector2(300, 300), Vector2(40, 40), Vector2(-100, -100), 72.0)
	check((diag.vb as Vector2).normalized().dot(Vector2(1, 1).normalized()) > 0.99, "en diagonal también conserva la dirección")
	var apart: Dictionary = script.resolve_collision(Vector2(0, 0), Vector2(-100, 0), Vector2(200, 0), Vector2(100, 0), 72.0)
	check(not apart.hit and apart.va == Vector2(-100, 0), "sin contacto no cambia nada")
	check(script.is_off_platform(Vector2(1000, 0), Vector2.ZERO, 400.0) and not script.is_off_platform(Vector2(390, 0), Vector2.ZERO, 400.0),
		"cae solo si el centro sale de la isla")
	check(script.platform_radius(10.0) == script.RADIUS_START and script.platform_radius(40.0) < script.RADIUS_START,
		"la isla se achica recién después de los 15 s")
	check(script.step_velocity(Vector2.ZERO, Vector2.RIGHT, 10.0).length() <= script.MAX_SPEED + 0.01, "velocidad máxima con el joystick")

	# Partida: 3 jugadores, avanzada a mano (sin _physics_process).
	var game: Variant = MiniGameRegistry.create("sumo")
	var players := _fake_players(3)
	root.add_child(game)
	game.set_physics_process(false)
	game.setup(players)
	var results: Array = []
	game.finished.connect(func(res: Dictionary) -> void: results.append(res))
	var center: Vector2 = script.CENTER
	var edge: float = script.RADIUS_START
	game._pos[1] = center + Vector2(-200, 0)
	game._pos[2] = center + Vector2(200, 0)
	game._pos[3] = center + Vector2(0, 250)
	game.on_input(1, {"seq": 0, "axis": Vector2(1, 0), "btn": 0})
	game.step(1.0)  # cuenta regresiva: nadie se mueve
	check(game._pos[1] == center + Vector2(-200, 0), "sin movimiento durante la cuenta regresiva")
	game._countdown = 0.0
	# Sofi (2) embiste a Pablo (1), que está al borde.
	game._pos[1] = center + Vector2(edge - 50, 0)
	game._pos[2] = center + Vector2(edge - 115, 0)
	game._vel[2] = Vector2(500, 0)
	game.on_input(1, {"seq": 1, "axis": Vector2.ZERO, "btn": 0})
	for i in 30:
		game.step(1.0 / 60.0)
	check(game._out_time.has(1), "Pablo se cae de la isla")
	check(not game._out_time.has(2), "Sofi sigue en pie")
	check(game._kos[2] == 1, "Sofi suma el rival tirado")
	# Tomi (3) se tira solo: nadie se lleva el bonus.
	game._pos[3] = center + Vector2(0, edge + 20)
	for i in 5:
		game.step(1.0 / 60.0)
	check(game._kos[2] == 1 and game._kos[1] == 0, "caerse solo no le da bonus a nadie")
	check(results.is_empty(), "espera la animación de caída antes de terminar")
	for i in 120:
		game.step(1.0 / 60.0)
	check(results.size() == 1, "termina al quedar uno en pie (%d)" % results.size())
	if results.size() == 1:
		var res: Dictionary = results[0]
		check(res.winners == [2], "gana Sofi (%s)" % [res.winners])
		check(float(res.scores[2]) >= float(res.scores[1]) + 5.0, "el bonus de +5 entra en el puntaje (%s)" % [res.scores])
		check(is_equal_approx(float(res.scores[3]), snappedf(float(res.scores[3]), 0.1)), "puntaje con un decimal")
	game.finish({"winners": [1], "scores": {}})
	for i in 60:
		game.step(1.0 / 60.0)
	check(results.size() == 1, "finished se emite una sola vez (%d)" % results.size())
	game.queue_free()
	await process_frame


## Pool loco: tiro al soltar el joystick, física de círculos (choque,
## fricción, bandas, troneras), puntos, reaparición y determinismo.
func test_pool_rules() -> void:
	var script: Script = load("res://host/minigames/pool/pool.gd")
	var physics: Script = load("res://host/minigames/pool/pool_physics.gd")
	# Apuntar y soltar.
	var aim: Dictionary = script.new_aim()
	check(script.track_aim(aim, Vector2(0.8, 0), 0.0) == Vector2.ZERO, "estirar el joystick no tira")
	check(script.track_aim(aim, Vector2(0.9, 0), 0.03) == Vector2.ZERO, "seguir estirado no tira")
	var shot: Vector2 = script.track_aim(aim, Vector2.ZERO, 0.06)
	check(shot.is_equal_approx(Vector2(0.9, 0)), "al soltar tira con dirección y fuerza (%s)" % shot)
	check(script.track_aim(aim, Vector2.ZERO, 0.1) == Vector2.ZERO, "soltado no vuelve a tirar")
	script.track_aim(aim, Vector2(0, -1), 1.0)
	script.track_aim(aim, Vector2(0, -0.4), 1.03)  # La perilla volviendo al centro.
	shot = script.track_aim(aim, Vector2.ZERO, 1.06)
	check(shot.is_equal_approx(Vector2(0, -1)), "tira con lo más estirado, no con lo que mandó al volver (%s)" % shot)
	script.track_aim(aim, Vector2(0.2, 0), 2.0)
	check(script.track_aim(aim, Vector2.ZERO, 2.1) == Vector2.ZERO, "un roce apenas estirado no tira")
	check(script.shot_speed(1.0) == script.SHOT_MAX_SPEED and script.shot_speed(script.ARM_MIN) == script.SHOT_MIN_SPEED
		and script.shot_speed(0.6) > script.SHOT_MIN_SPEED and script.shot_speed(0.6) < script.SHOT_MAX_SPEED,
		"más estirado, más fuerza")
	check(script.credited({"by": 2, "t": 1.0}, 3.0) == 2 and script.credited({"by": 2, "t": 1.0}, 1.1 + script.CREDIT_SEC) == -1
		and script.credited({}, 0.0) == -1, "los puntos son del último que tocó la bola, si fue hace poco")

	# Física pura: choque de frente entre bolas iguales, fricción, banda y tronera.
	var t: Variant = physics.new(Rect2(0, 0, 2000, 1000))
	var a: int = t.add_ball(Vector2(500, 500), 20.0, 1.0)
	var b: int = t.add_ball(Vector2(600, 500), 20.0, 1.0)
	t.vel[a] = Vector2(800, 0)
	var hits := 0
	for s in 30:
		hits += (t.step().hits as Array).size()
	check(hits >= 1, "detecta el choque")
	check((t.vel[b] as Vector2).x > 500.0 and (t.vel[a] as Vector2).x < 100.0, "B sale con la velocidad de A y A casi frena (%s, %s)" % [t.vel[a], t.vel[b]])
	check((t.pos[b] as Vector2).distance_to(t.pos[a]) >= 40.0 - 0.01, "las bolas no quedan superpuestas")
	var f: Variant = physics.new(Rect2(0, 0, 6000, 1000))
	var fi: int = f.add_ball(Vector2(100, 500), 20.0)
	f.vel[fi] = Vector2(1900, 0)
	for s in 120 * 12:
		f.step()
	check(f.speed(fi) == 0.0 and (f.pos[fi] as Vector2).x > 1000.0, "la fricción la frena del todo (%s)" % f.pos[fi])
	var c: Variant = physics.new(Rect2(0, 0, 500, 500))
	var ci: int = c.add_ball(Vector2(470, 250), 20.0)
	c.vel[ci] = Vector2(600, 0)
	for s in 20:
		c.step()
	check((c.vel[ci] as Vector2).x < 0.0 and (c.pos[ci] as Vector2).x <= 480.0, "rebota en la banda")
	var d: Variant = physics.new(Rect2(0, 0, 500, 500), PackedVector2Array([Vector2(500, 500)]), 44.0)
	var di: int = d.add_ball(Vector2(400, 400), 20.0)
	d.vel[di] = Vector2(500, 500)
	var fell := false
	for s in 60:
		fell = fell or not (d.step().pocketed as Array).is_empty()
	check(fell and not d.is_on_table(di), "cae en la tronera")

	# Partida con 3 jugadores, avanzada a mano.
	var game: Variant = MiniGameRegistry.create("pool")
	root.add_child(game)
	game.set_physics_process(false)
	game.setup(_fake_players(3))
	var results: Array = []
	game.finished.connect(func(res: Dictionary) -> void: results.append(res))
	var dt := 1.0 / 60.0
	var p1: int = game._ball[1]
	var p2: int = game._ball[2]
	var p3: int = game._ball[3]
	game.on_input(1, {"seq": 0, "axis": Vector2(1, 0), "btn": 0})
	game.step(dt)
	game.on_input(1, {"seq": 1, "axis": Vector2.ZERO, "btn": 0})
	game.step(dt)
	check(game._phys.speed(p1) == 0.0, "en la cuenta regresiva no se tira")
	while game._state == 0:
		game.step(dt)
	game.on_input(1, {"seq": 2, "axis": Vector2(0, 1), "btn": 0})
	game.step(dt)
	check(game._phys.speed(p1) == 0.0, "estirado todavía no tira")
	game.on_input(1, {"seq": 3, "axis": Vector2.ZERO, "btn": 0})
	game.step(dt)
	check((game._phys.vel[p1] as Vector2).y > 1000.0, "al soltar, la bola sale hacia donde apuntaba (%s)" % game._phys.vel[p1])
	game.on_input(1, {"seq": 4, "axis": Vector2(1, 0), "btn": 0})
	game.step(dt)
	game.on_input(1, {"seq": 5, "axis": Vector2.ZERO, "btn": 0})
	game.step(dt)
	check((game._phys.vel[p1] as Vector2).x < 1.0, "no se puede volver a tirar enseguida")
	# Datos raros del control: no rompen nada.
	game.on_input(1, {"seq": 6, "axis": "hola", "btn": 0})
	game.on_input(99, {"seq": 7, "axis": Vector2.ONE, "btn": 0})
	game.step(dt)

	# Dorada a la tronera de abajo a la derecha: 2P se lleva los puntos.
	var play: Rect2 = script.PLAY
	var gold: int = game._golds[0]
	game._phys.place(p1, play.position + Vector2(200, 400))
	game._phys.place(gold, play.end - Vector2(90, 90))
	game._phys.place(p2, play.end - Vector2(170, 170))
	game._cooldown[2] = 0.0
	game.on_input(2, {"seq": 8, "axis": Vector2(1, 1).normalized() * 0.7, "btn": 0})
	game.step(dt)
	game.on_input(2, {"seq": 9, "axis": Vector2.ZERO, "btn": 0})
	for s in 90:
		game.step(dt)
	check(game._score[2] == script.GOLD_POINTS, "meter una dorada suma %d (%s)" % [script.GOLD_POINTS, game._score])
	check(not game._phys.is_on_table(gold) or game._gold_wait.is_empty(), "la dorada cae")
	for s in roundi((script.GOLD_RESPAWN_SEC + script.RESPAWN_SEC + 0.2) / dt):
		game.step(dt)
	check(game._phys.is_on_table(gold), "la dorada vuelve a la mesa")
	check(game._phys.is_on_table(p2) and game._respawn.is_empty(), "si tu bola cae, reaparece")

	# 1P mete la bola de 3P en la tronera de arriba al medio.
	var top: Vector2 = script.pockets()[1]
	game._phys.place(p3, top + Vector2(0, 75))
	game._phys.place(p1, top + Vector2(0, 190))
	game._cooldown[1] = 0.0
	var before: int = game._score[1]
	game.on_input(1, {"seq": 10, "axis": Vector2(0, -0.8), "btn": 0})
	game.step(dt)
	game.on_input(1, {"seq": 11, "axis": Vector2.ZERO, "btn": 0})
	for s in 40:
		game.step(dt)
	check(game._score[1] == before + script.RIVAL_POINTS, "meter la bola de otro suma %d (%s)" % [script.RIVAL_POINTS, game._score])
	check(game._respawn.has(3) and not game._phys.is_on_table(p3), "la bola de 3P cayó y espera")
	var score3: int = game._score[3]
	for s in roundi(script.RESPAWN_SEC * 0.5 / dt):
		game.step(dt)
	check(not game._phys.is_on_table(p3), "no reaparece antes de %.1f s" % script.RESPAWN_SEC)
	for s in roundi(script.RESPAWN_SEC * 0.5 / dt) + 3:
		game.step(dt)
	check(game._phys.is_on_table(p3) and (game._pos[3] as Vector2).is_equal_approx(script.start_spot(2)),
		"a los %.1f s reaparece en su lugar de salida" % script.RESPAWN_SEC)
	check(game._score[3] == score3, "caerse no resta puntos")

	# Fin: una sola vez, gana el que más puntos tiene.
	game._time_left = 0.01
	for s in roundi((script.END_WAIT_SEC + 0.3) / dt):
		game.step(dt)
	check(results.size() == 1, "termina al acabarse el tiempo (%d)" % results.size())
	if results.size() == 1:
		check(results[0].winners == [2], "gana el de más puntos (%s)" % [results[0]])
	game.finish({"winners": [1], "scores": {}})
	check(results.size() == 1, "finished se emite una sola vez")
	game.queue_free()

	# Determinismo: misma semilla y mismos inputs -> misma partida.
	var runs: Array = []
	for r in 2:
		var g: Variant = MiniGameRegistry.create("pool")
		root.add_child(g)
		g.set_physics_process(false)
		g.setup(_fake_players(4))
		g._rng.seed = 77
		for frame in 60 * 14:
			for k in 4:
				var stretched := (frame + k * 7) % 45 < 25
				var axis := Vector2.from_angle(frame * 0.013 + k * 1.9) * (0.5 + 0.12 * k) if stretched else Vector2.ZERO
				g.on_input(k + 1, {"seq": frame, "axis": axis, "btn": 0})
			g.step(dt)
		runs.append([g._phys.pos, g._phys.vel, g._score.duplicate(), g._respawn.duplicate()])
		g.queue_free()
	check(runs[0] == runs[1], "misma semilla y mismos tiros: misma partida")
	check(runs[0][0] != PackedVector2Array(), "la partida de prueba se jugó")
	await process_frame


func test_result_from_scores() -> void:
	var r := MiniGame.result_from_scores({1: 3, 2: 5, 3: 5})
	check(r.winners == [2, 3], "empate devuelve ambos ganadores")


func test_registry_optional_defaults() -> void:
	for info in MiniGameRegistry.all_info():
		check(typeof(info.get("accent")) == TYPE_COLOR, "%s: accent es un color" % info.id)
		check(typeof(info.get("score_label")) == TYPE_STRING and not str(info.score_label).is_empty(),
			"%s: score_label es un texto" % info.id)
	check(MiniGameRegistry.info("arena").score_label == "estrellas", "el juego puede sobrescribir los valores por defecto")
	# Cada juego tiene su color de tarjeta: dos iguales se confunden en el lobby.
	var accents := {}
	for info in MiniGameRegistry.all_info():
		var key := (info.accent as Color).to_html(false)
		check(not accents.has(key), "%s repite el color de %s" % [info.id, accents.get(key, "")])
		accents[key] = info.id


## ¡Que no te deje la cámara!: recorrido determinista, física pura
## (bloques sólidos, empujones), eliminación por el borde de la cámara, por
## sierra y por pozo, y fin por último en pie y por tiempo.
func test_scroller_rules() -> void:
	var script: Script = load("res://host/minigames/scroller/scroller.gd")
	var same := true
	var differs := false
	for i in 30:
		var a: Array = script.build_segment(1234, i)
		same = same and a == script.build_segment(1234, i)
		differs = differs or a != script.build_segment(98765, i)
	check(same, "scroller: la misma semilla arma siempre el mismo recorrido")
	check(differs, "scroller: otra semilla arma otro recorrido")
	check(script.build_segment(1234, 0).is_empty(), "scroller: la salida no tiene obstáculos")
	var easy_first := true
	var hard_later := false
	for s in 20:
		easy_first = easy_first and script.template_for(s, 1) in script.EASY and script.template_for(s, 2) in script.EASY
		for i in range(7, 12):
			hard_later = hard_later or script.template_for(s, i) in script.HARD
	check(easy_first and hard_later, "scroller: primero tramos fáciles, después difíciles")
	check(script.camera_speed(0.0) < script.camera_speed(30.0) and script.camera_speed(200.0) == script.CAM_SPEED_END,
		"scroller: la cámara acelera de a poco hasta un tope")
	var wall: Array = script.push_out_of_rect(Vector2(95, 50), Vector2(300, 0), Rect2(100, 0, 100, 100), 30.0)
	check(wall[2] and (wall[0] as Vector2).x <= 70.01 and (wall[1] as Vector2).x <= 0.0, "scroller: un bloque es sólido y frena (%s)" % [wall])
	var inside: Array = script.push_out_of_rect(Vector2(190, 50), Vector2.ZERO, Rect2(100, 0, 100, 100), 30.0)
	check((inside[0] as Vector2).x >= 230.0 - 0.01, "scroller: si quedó adentro sale por el lado más cercano (%s)" % [inside])
	var push: Dictionary = script.resolve_push(Vector2.ZERO, Vector2(400, 0), Vector2(50, 0), Vector2.ZERO)
	check(push.hit and (push.vb as Vector2).x > 400.0 and (push.va as Vector2).x < (push.vb as Vector2).x,
		"scroller: embestir empuja al otro con bonus (%s)" % [push])
	var saw := {"kind": "saw", "c": Vector2(500, 300), "r": 50.0, "amp": Vector2(0, 100), "speed": PI / 2.0, "phase": 0.0}
	check(script.hazard_hits(saw, Vector2(500, 400), 1.0) and not script.hazard_hits(saw, Vector2(500, 300), 1.0),
		"scroller: la sierra lastima donde está en ese momento (va y viene)")

	# Partida en un recorrido vacío, avanzada a mano (sin _physics_process).
	var game: Variant = MiniGameRegistry.create("scroller")
	root.add_child(game)
	game.set_physics_process(false)
	game.setup(_fake_players(3))
	game.set_course_seed(7)
	for i in 60:
		game._segments[i] = []
	var results: Array = []
	game.finished.connect(func(res: Dictionary) -> void: results.append(res))
	var start: Vector2 = game._pos[1]
	game.on_input(1, {"seq": 0, "axis": Vector2(1, 0), "btn": 0})
	game.step(1.0)
	check(game._pos[1] == start and game._cam == 0.0, "scroller: nadie se mueve (ni la cámara) en la cuenta regresiva")
	game._countdown = 0.0
	# Empujón: Sofi (2) embiste a Tomi (3), que está quieto.
	game._pos[2] = Vector2(600, 300)
	game._vel[2] = Vector2(450, 0)
	game._pos[3] = Vector2(655, 300)
	game._vel[3] = Vector2.ZERO
	game.step(1.0 / 60.0)
	check((game._vel[3] as Vector2).x > 300.0 and (game._pos[3] as Vector2).x > 655.0, "scroller: Tomi sale empujado (%s)" % [game._vel[3]])
	# Pablo (1) se queda quieto y la cámara lo deja atrás; los otros corren.
	game.on_input(1, {"seq": 1, "axis": Vector2.ZERO, "btn": 0})
	game.on_input(2, {"seq": 1, "axis": Vector2(1, -0.3), "btn": 0})
	game.on_input(3, {"seq": 1, "axis": Vector2(1, 0.3), "btn": 0})
	var guard := 0
	while not game._out.has(1) and guard < 600:
		game.step(1.0 / 60.0)
		guard += 1
	check(game._out.has(1) and game._out[1].kind == "camera", "scroller: el que se queda atrás queda eliminado por la cámara")
	check((game._pos[1] as Vector2).x < game._cam + 1.0, "scroller: se eliminó al pasar el borde izquierdo")
	check(not game._out.has(2) and not game._out.has(3), "scroller: los que corren siguen en pie")
	check(results.is_empty(), "scroller: con dos en pie sigue el juego")
	# Una sierra aparece justo donde está Sofi: choque mortal.
	var sofi: Vector2 = game._pos[2]
	var seg := floori(sofi.x / script.SEG_W)
	game._segments[seg] = [{"kind": "saw", "c": sofi, "r": 40.0, "amp": Vector2.ZERO, "speed": 1.0, "phase": 0.0}]
	game.step(1.0 / 60.0)
	check(game._out.has(2) and game._out[2].kind == "hit", "scroller: chocar una sierra elimina")
	check(results.is_empty(), "scroller: espera que se vea la última eliminación antes de terminar")
	for i in 150:
		game.step(1.0 / 60.0)
	check(results.size() == 1, "scroller: termina al quedar uno en pie (%d)" % results.size())
	if results.size() == 1:
		var res: Dictionary = results[0]
		check(res.winners == [3], "scroller: gana Tomi, el último en pie (%s)" % [res.winners])
		check(int(res.scores[1]) <= int(res.scores[2]) and int(res.scores[1]) <= int(res.scores[3]),
			"scroller: el que se quedó atrás hizo menos metros (%s)" % [res.scores])
		check(game._is_seated(1) and game._is_seated(2), "scroller: los eliminados terminan en la tribuna")
	game.finish({"winners": [1], "scores": {}})
	check(results.size() == 1, "scroller: finished se emite una sola vez")
	game.queue_free()

	# Pozo y fin por tiempo: ganan los que siguen en pie, ordenados por metros.
	var timed: Variant = MiniGameRegistry.create("scroller")
	root.add_child(timed)
	timed.set_physics_process(false)
	timed.setup(_fake_players(3))
	timed.set_course_seed(7)
	for i in 60:
		timed._segments[i] = []
	var timed_results: Array = []
	timed.finished.connect(func(res: Dictionary) -> void: timed_results.append(res))
	timed._countdown = 0.0
	timed._pos[3] = Vector2(900, 500)
	timed._segments[0] = [{"kind": "pit", "rect": Rect2(820, 420, 160, 160)}]
	timed.step(1.0 / 60.0)
	check(timed._out.has(3) and timed._out[3].kind == "pit", "scroller: pisar un pozo elimina")
	timed._elapsed = script.DURATION_SEC - 0.05
	timed._pos[1] = Vector2(1500, 200)
	timed._pos[2] = Vector2(1100, 400)
	for i in 120:
		timed.step(1.0 / 60.0)
	check(timed_results.size() == 1, "scroller: termina por tiempo")
	if timed_results.size() == 1:
		var res: Dictionary = timed_results[0]
		check(res.winners.size() == 2 and 1 in res.winners and 2 in res.winners, "scroller: ganan los dos en pie (%s)" % [res.winners])
		var entries: Array[Dictionary] = []
		for pid: int in [1, 2, 3]:
			entries.append({"id": pid, "score": float(res.scores[pid]), "winner": pid in res.winners})
		var places := Tournament.rank(entries)
		check(places[1] == 1 and places[2] == 2 and places[3] == 3, "scroller: en pie primero y ordenados por metros (%s)" % [places])
	timed.queue_free()

	# Determinismo: misma semilla e inputs, misma partida (con obstáculos reales).
	var runs: Array = []
	for run in 2:
		var g: Variant = MiniGameRegistry.create("scroller")
		root.add_child(g)
		g.set_physics_process(false)
		g.setup(_fake_players(4))
		g.set_course_seed(42)
		for f in 900:
			for k in 4:
				g.on_input(k + 1, {"seq": f, "axis": Vector2(cos(f * 0.03 + k), sin(f * 0.05 + k * 2.0)) * 0.9 + Vector2(0.5, 0), "btn": 0})
			g.step(1.0 / 60.0)
		runs.append([g._pos.duplicate(), g._out.keys(), g._cam, g._live_scores()])
		g.queue_free()
	check(runs[0] == runs[1], "scroller: misma semilla y mismos inputs dan la misma partida")
	await process_frame



func test_stop_clock_scoring() -> void:
	var sc = preload("res://host/minigames/stop_clock/stop_clock.gd")  # Sin tipo: métodos propios del juego.
	check(sc.score_for(10.0) == 1000, "frenar justo en 10.00 da 1000")
	check(sc.score_for(10.25) == 750 and sc.score_for(9.75) == 750, "250 ms de error, pasado o corto, da 750")
	check(sc.score_for(9.9) == 900, "redondea el error a milisegundos (%d)" % sc.score_for(9.9))
	check(sc.score_for(11.0) == 0 and sc.score_for(15.0) == 0 and sc.score_for(0.0) == 0, "nunca es negativo")

	var game = MiniGameRegistry.create("stop_clock")
	root.add_child(game)
	game.process_mode = Node.PROCESS_MODE_DISABLED  # El test maneja el tiempo a mano.
	game.setup(_fake_players(2))
	var results: Array = []
	game.finished.connect(func(r: Dictionary) -> void: results.append(r))
	var down := {"seq": 1, "axis": Vector2.ZERO, "btn": Protocol.BTN_A}
	var up := {"seq": 2, "axis": Vector2.ZERO, "btn": 0}
	game.on_input(1, down)
	check(not game.has_stopped(1), "apretar durante la cuenta regresiva no frena")
	game._physics_process(3.5)
	game.on_input(1, down)
	check(not game.has_stopped(1), "mantener apretado desde la cuenta no cuenta como toque")
	game._physics_process(9.5)
	game.on_input(1, up)
	game.on_input(1, down)
	check(game.has_stopped(1) and is_equal_approx(game.stop_time(1), 10.0), "frena en 10.00 (%.3f)" % game.stop_time(1))
	game.on_input(1, up)
	game._physics_process(1.0)
	game.on_input(1, down)
	check(is_equal_approx(game.stop_time(1), 10.0), "frena una sola vez")
	game._physics_process(5.0)
	check(game.is_revealing() and is_equal_approx(game.stop_time(2), 15.0), "quien no frena se detiene solo a los 15 s")
	check(results.is_empty(), "revela los tiempos antes de terminar")
	game._physics_process(2.1)
	check(results.size() == 1 and results[0].winners == [1] and results[0].scores == {1: 1000, 2: 0},
		"resultado final (%s)" % [results])
	game.queue_free()
	await process_frame

# --- Efectos ("juice") -------------------------------------------------------------

## Partículas: pool fijo que se reutiliza (nunca crece) y se apaga solo.
func test_fx_particles_pool() -> void:
	var fx := FxParticles.new(32)
	check(fx.alive_count() == 0 and not fx.is_processing(), "arranca vacío y sin _process")
	fx.burst(FxParticles.Kind.STAR, Vector2(100, 100), 500, UiTheme.GOLD, 300.0, 10.0, 0.5)
	check(fx.alive_count() == 32 and fx.is_processing(), "500 pedidas: quedan 32 vivas (%d), el pool no crece" % fx.alive_count())
	check(fx._pos.size() == 32 and fx._dur.size() == 32 and fx._col.size() == 32, "los arreglos siguen del tamaño del pool")
	fx._process(0.2)
	fx.emit(FxParticles.Kind.SPARK, Vector2.ZERO, Vector2.RIGHT * 100.0, 5.0, 2.0, UiTheme.PAPER)
	check(fx.alive_count() == 32, "emitir con el pool lleno pisa la más vieja (%d)" % fx.alive_count())
	for i in 3:
		fx._process(0.5)
	check(fx.alive_count() == 1, "las de 0,5 s se liberan; la de 2 s sigue (%d)" % fx.alive_count())
	fx._process(2.0)
	fx._process(0.016)
	check(fx.alive_count() == 0 and not fx.is_processing(), "sin partículas apaga su _process")
	for round in 5:
		fx.burst(FxParticles.Kind.CONFETTI, Vector2.ZERO, 20, UiTheme.PAPER, 200.0, 8.0, 0.3)
		fx._process(1.0)
	check(fx._pos.size() == 32 and fx.alive_count() == 0, "muchos estallidos seguidos reutilizan los mismos lugares")
	UiTheme.reduce_motion = true
	fx.burst(FxParticles.Kind.PUFF, Vector2.ZERO, 20, UiTheme.FX_DUST, 100.0, 8.0, 0.5)
	check(fx.alive_count() == roundi(20 * UiTheme.FX_REDUCED), "con Reducir movimiento salen menos (%d)" % fx.alive_count())
	UiTheme.reduce_motion = false
	fx.free()


## "Reducir movimiento": sin sacudida ni zoom en ningún juego (y siguen andando).
func test_reduce_motion_no_shake() -> void:
	var game: Variant = MiniGameRegistry.create("arena")
	root.add_child(game)
	game.setup(_fake_players(2))
	await process_frame
	game.juice().shake(1.0)
	await process_frame
	await process_frame
	check(game.transform != Transform2D.IDENTITY and game.juice().shake_offset() != Vector2.ZERO, "sin el ajuste, la sacudida mueve el juego")
	await create_timer(UiTheme.DUR_SHAKE + 0.15).timeout
	await process_frame
	check(game.transform == Transform2D.IDENTITY, "la sacudida es breve: vuelve a su lugar")
	UiTheme.reduce_motion = true
	game.juice().shake(1.0)
	game.juice().zoom_punch(Vector2(500, 500))
	for i in 3:
		await process_frame
	check(game.transform == Transform2D.IDENTITY and game.juice().shake_offset() == Vector2.ZERO, "con Reducir movimiento no hay sacudida ni zoom")
	check(UiTheme.pop_scale(0.0) == 1.0, "con Reducir movimiento no hay golpe de escala")
	game.queue_free()
	# Todos los juegos, con golpes de verdad (Esquivar: un bloque cae sobre 1P).
	for info in MiniGameRegistry.all_info():
		var g: Variant = MiniGameRegistry.create(info.id)
		var players := _fake_players(info.max_players)
		root.add_child(g)
		g.setup(players)
		if info.id == "dodge":
			g._countdown = 0.0
			g._spawn_block(g._pos[1], 120.0, 0.0)
		var moved := false
		for f in 20:
			for p in players:
				g.on_input(p.id, {"seq": f, "axis": Vector2(1, 0.3), "btn": f % 2})
			await physics_frame
			moved = moved or g.transform != Transform2D.IDENTITY
		check(is_instance_valid(g) and not moved, "%s: corre sin sacudirse con Reducir movimiento" % info.id)
		g.queue_free()
	UiTheme.reduce_motion = false
	await process_frame


## Momento final: "¡Tiempo!" con cartel, festejo de los ganadores y un solo finished.
func test_game_finale() -> void:
	var game: Variant = MiniGameRegistry.create("arena")
	root.add_child(game)
	game.setup(_fake_players(2))
	var results: Array = []
	game.finished.connect(func(r: Dictionary) -> void: results.append(r))
	game._score[2] = 3
	game._time_left = 0.01
	await physics_frame
	await physics_frame
	check(game.in_finale() and results.is_empty(), "al llegar a 0:00 festeja antes de terminar")
	check(game.juice().has_banner() and game.is_celebrating(2) and not game.is_celebrating(1), "cartel ¡Tiempo! y festeja el ganador")
	check(game.celebrate_hop(2) >= 0.0 and game.juice().particles.alive_count() > 0, "confeti sobre el ganador")
	var pos: Vector2 = game._pos[2]
	game.on_input(2, {"seq": 9, "axis": Vector2(1, 0), "btn": 0})
	await physics_frame
	check(game._pos[2] == pos, "durante el festejo nadie se mueve")
	game._finale_left = 0.0
	await process_frame
	await process_frame
	check(results.size() == 1 and results[0].winners == [2], "termina una sola vez con el resultado de 0:00 (%s)" % [results])
	game.finish({"winners": [1], "scores": {}})
	check(results.size() == 1, "finished no se repite")
const QUICKDRAW := preload("res://host/minigames/quickdraw/quickdraw.gd")


## Desenfunde: juego con el tiempo y el reloj real a mano (determinista).
func _quickdraw(n: int, clock: Array) -> Variant:
	var game = MiniGameRegistry.create("quickdraw")  # Sin tipo: métodos propios del juego.
	root.add_child(game)
	game.process_mode = Node.PROCESS_MODE_DISABLED  # El test maneja el tiempo a mano.
	game.wall_clock_usec = func() -> int: return clock[0]
	game.setup(_fake_players(n))
	return game


## Avanza `seconds` en pasos de 1/60 s; el reloj real sube igual.
func _qd_step(game: Variant, clock: Array, seconds: float) -> void:
	for i in roundi(seconds * 60.0):
		clock[0] += 16667
		game._physics_process(1.0 / 60.0)


func _qd_tap(game: Variant, pid: int) -> void:
	game.on_input(pid, {"seq": 1, "axis": Vector2.ZERO, "btn": Protocol.BTN_A})
	game.on_input(pid, {"seq": 2, "axis": Vector2.ZERO, "btn": 0})


## Tocar antes del ¡YA! pierde la ronda; el primero en tocar después gana.
func test_quickdraw_early_and_first() -> void:
	var clock := [1000000]
	var game = _quickdraw(3, clock)
	_qd_step(game, clock, 1.0 / 60.0)
	check(game.round_number() == 1 and not game.is_go(), "empieza la ronda 1 esperando")
	game._go_at = 2.51
	game._trick = -1
	_qd_tap(game, 1)
	check(not game.is_early(1), "durante \"Ronda 1\" todavía no cuenta")
	_qd_step(game, clock, 1.0)
	check(game.sign_text()[0] == "Preparados…", "el cartel dice Preparados…")
	_qd_tap(game, 1)
	check(game.is_early(1) and not game.is_go(), "tocar antes del ¡YA! es muy temprano")
	_qd_step(game, clock, 1.5)
	check(game.is_go() and game.sign_text() == ["¡YA!", true], "sale el ¡YA! a su tiempo")
	_qd_tap(game, 1)
	check(game.reaction_ms(1) == QUICKDRAW.NO_TIME, "el que se adelantó no dispara en esa ronda")
	_qd_step(game, clock, 0.4)
	clock[0] += 3000  # Llega 3 ms después del último paso de física.
	_qd_tap(game, 3)
	_qd_step(game, clock, 0.15)
	_qd_tap(game, 2)
	_qd_tap(game, 2)
	check(game.reaction_ms(3) == 403 and game.reaction_ms(2) == 550,
		"tiempos medidos por la TV (%d, %d)" % [game.reaction_ms(3), game.reaction_ms(2)])
	_qd_step(game, clock, 1.0 / 60.0)
	check(game.is_result() and game.round_winners() == [3], "gana el primero en tocar (%s)" % [game.round_winners()])
	check(game.points() == {1: 0, 2: QUICKDRAW.speed_bonus(550), 3: 100 + QUICKDRAW.speed_bonus(403)},
		"puntos: victoria + velocidad (%s)" % [game.points()])
	check(game.sign_text()[0] == "¡Ganó Tomi!", "el cartel anuncia al ganador")
	game.queue_free()
	await process_frame



## Los carteles trampa no son el ¡YA!: tocar durante uno es muy temprano.
func test_quickdraw_tricks() -> void:
	var clock := [0]
	var game = _quickdraw(2, clock)
	_qd_step(game, clock, 1.0 / 60.0)
	game._trick = 0          # "¡YA…mate!"
	game._trick_at = 1.5
	game._go_at = 3.3
	_qd_step(game, clock, 1.55)
	check(game.trick_showing() == 0 and game.sign_text() == ["¡YA…", false] and not game.is_go(), "primero asoma \"¡YA…\"")
	_qd_tap(game, 1)
	check(game.is_early(1), "tocar con \"¡YA…\" es muy temprano")
	_qd_step(game, clock, 0.5)
	check(game.sign_text()[0] == "¡YA…mate!" and not game.is_go(), "se completa \"¡YA…mate!\"")
	_qd_step(game, clock, 1.3)
	check(game.is_go() and not game.is_early(2), "el ¡YA! real llega después")
	# Todos los carteles trampa dicen otra cosa, y el sorteo deja tiempo antes del ¡YA!.
	for trick: Dictionary in QUICKDRAW.TRICKS:
		check(trick.text != "¡YA!" and trick.tease != "¡YA!", "cartel trampa distinto: %s" % trick.text)
	var tricks := 0
	for r in 200:
		game._start_round(2)
		if game._trick >= 0:
			tricks += 1
			check(game._trick_at >= QUICKDRAW.ROUND_INTRO and game._trick_at + QUICKDRAW.TRICK_TIME + QUICKDRAW.TRICK_LEAD_MIN <= game._go_at + 0.0001,
				"el cartel trampa termina antes del ¡YA! (%.2f / %.2f)" % [game._trick_at, game._go_at])
	check(tricks > 50 and tricks < 150, "a veces hay trampa (%d de 200)" % tricks)
	game._start_round(1)
	check(game._trick == -1, "la ronda 1 nunca tiene trampa")
	game.queue_free()
	await process_frame


## Puntos, empates en una ronda (misma lectura de la red) y desempate final.
func test_quickdraw_points_and_tiebreak() -> void:
	var qd = QUICKDRAW
	check(qd.speed_bonus(200.0) == 50 and qd.speed_bonus(400.0) == 40 and qd.speed_bonus(700.0) == 20, "bonus por velocidad")
	check(qd.speed_bonus(1000.0) == 0 and qd.speed_bonus(5000.0) == 0 and qd.speed_bonus(0.0) == 50, "bonus acotado")
	check(qd.rank_winners({1: 300, 2: 300, 3: 100}, {1: 250000, 2: 240000, 3: 100000}) == [2],
		"a igual puntaje gana el de mejor reacción")
	check(qd.rank_winners({1: 300, 2: 300}, {1: 250000, 2: 250000}) == [1, 2], "empate total: ganan los dos")
	check(qd.rank_winners({1: 0, 2: 0}, {}) == [1, 2], "nadie disparó: empate")
	check(qd.rank_winners({1: 140, 2: 140}, {2: 300000}) == [2], "quien nunca disparó a tiempo pierde el desempate")

	var clock := [0]
	var game = _quickdraw(2, clock)
	_qd_step(game, clock, 1.0 / 60.0)
	game._go_at = 2.0
	_qd_step(game, clock, 2.0)
	check(game.is_go(), "¡YA!")
	_qd_step(game, clock, 0.3)
	_qd_tap(game, 1)
	clock[0] += 900  # Otro mensaje de la misma lectura de la red: mismo sello.
	_qd_tap(game, 2)
	_qd_step(game, clock, 1.0 / 60.0)
	check(game.round_winners() == [1, 2] and game.points()[1] == game.points()[2] and game.points()[1] >= 100,
		"llegan juntos: empatan y ganan los dos (%s)" % [game.points()])
	# Un jugador con latencia medida (futuro HostServer) se compensa, con tope.
	game.players[1]["latency_ms"] = 40
	check(game.latency_ms(2) == 40.0, "latencia de ida del jugador")
	game.players[1]["latency_ms"] = 9999
	check(game.latency_ms(2) == QUICKDRAW.MAX_LATENCY_COMP_MS, "latencia recortada")
	game.players[1]["latency_ms"] = "mucha"
	check(game.latency_ms(2) == 0.0, "latencia inválida se ignora")
	game.queue_free()
	await process_frame


## Misma semilla y mismos toques: misma partida (y termina una sola vez).
func test_quickdraw_deterministic_seed() -> void:
	var runs: Array = []
	for s in [7, 7, 8]:
		var clock := [0]
		var game = _quickdraw(3, clock)
		game._rng.seed = s  # Después de setup: la ronda 1 se sortea en el primer paso.
		var results: Array = []
		game.finished.connect(func(r: Dictionary) -> void: results.append(r))
		for i in 60 * 70:
			if game.is_finished():
				break
			# 1P toca cada 1,3 s (a veces temprano); 2P siempre 0,25 s después del ¡YA!; 3P nunca.
			if i % 78 == 0:
				_qd_tap(game, 1)
			if game.is_go() and is_equal_approx(game._phase_t, 0.25):
				_qd_tap(game, 2)
			_qd_step(game, clock, 1.0 / 60.0)
		check(results.size() == 1, "semilla %d: termina una sola vez" % s)
		check(game.history.size() == QUICKDRAW.ROUNDS, "semilla %d: juega las 5 rondas" % s)
		runs.append([game.history.map(func(h: Dictionary) -> Array: return [h.go_at, h.trick, h.winners, h.react, h.early]),
			results[0] if not results.is_empty() else {}])
		game.queue_free()
	check(runs[0] == runs[1], "misma semilla, misma partida")
	check(runs[0][0] != runs[2][0], "otra semilla, otra partida")
	check(not runs[0][1].is_empty() and int(runs[0][1].scores[2]) >= 5 * QUICKDRAW.speed_bonus(250),
		"2P dispara a tiempo en las 5 rondas (%s)" % [runs[0][1]])
	await process_frame

# --- Sonido y vibración ------------------------------------------------------------

func test_sfx_synthesis() -> void:
	for sound_name: String in Sfx.RECIPES:
		var stream := Sfx.synth(Sfx.RECIPES[sound_name])
		var seconds := 0.0
		for n: Array in Sfx.RECIPES[sound_name]:
			seconds += float(n[2])
		var expected_bytes := 0
		for n: Array in Sfx.RECIPES[sound_name]:
			expected_bytes += int(float(n[2]) * Sfx.MIX_RATE) * 2
		check(stream.data.size() == expected_bytes and stream.data.size() > 0, "%s: duración correcta" % sound_name)
		check(stream.format == AudioStreamWAV.FORMAT_16_BITS and not stream.stereo, "%s: PCM16 mono" % sound_name)
		check(seconds <= 1.2, "%s: efecto corto (%.2f s)" % [sound_name, seconds])
	# El volumen nunca satura: el pico queda por debajo del máximo de 16 bits.
	var peak := 0
	var data := Sfx.synth(Sfx.RECIPES["fanfare"]).data
	for i in range(0, data.size(), 2):
		peak = maxi(peak, absi(data.decode_s16(i)))
	check(peak > 3000 and peak < 32767, "volumen audible y sin saturar (pico %d)" % peak)
	Sfx.play("no-existe")  # Sin nodo ni nombre válido: no hace nada ni rompe.
	for kind in Protocol.FEEDBACK_KINDS:
		check(Sfx.has_sound(kind) and Haptics.duration_ms(kind) > 0, "feedback %s tiene sonido y vibración" % kind)


func test_parse_feedback() -> void:
	check(Protocol.parse_feedback({"kind": "point"}) == "point", "tipo válido")
	check(Protocol.parse_feedback({"kind": "explotar"}) == "", "tipo desconocido")
	check(Protocol.parse_feedback({"kind": 3}) == "", "tipo no string")
	check(Protocol.parse_feedback({}) == "", "sin tipo")


func test_mascot_walk_anim() -> void:
	var game := MiniGame.new()
	game.setup(_fake_players(2))
	check(game.mascot_anim(1).walk < 0.0, "quieta al empezar")
	game.advance_walk(1, 1.0, 0.5, 2.0)
	check(is_equal_approx(game.mascot_anim(1).walk, 1.0), "a velocidad máxima da 2 pasos por segundo")
	game.advance_walk(1, 0.02, 0.5)
	check(game.mascot_anim(1).walk < 0.0, "si casi no se mueve, deja de caminar")
	check(game.mascot_anim(2, Vector2(1, 0)).look == Vector2(1, 0), "la mirada sigue la dirección pedida")
	game.free()


## Prototipo de mascotas 3D (core/mascot3d, docs/ARTE.md). Sin pantalla
## (--headless) no se renderiza: se verifica que arma la escena sin errores
## y que el horneado devuelve vacío; con pantalla, además las texturas.
func test_mascot3d_prototype() -> void:
	var M := PlayerAvatar.Mood
	for s in PlayerAvatar.STYLE_NAMES.size():
		var m := Mascot3D.new().setup(Protocol.MASCOT_COLORS[(s * 3) % Protocol.MASCOT_COLORS.size()], s)
		root.add_child(m)
		check(m.mesh_count() >= 30, "estilo %d: la mascota tiene sus piezas (%d)" % [s, m.mesh_count()])
		var expected := {M.NORMAL: ["eyes_open"], M.HAPPY: ["eyes_happy", "mouth_happy"],
			M.SAD: ["eyes_sad", "mouth_sad"], M.SURPRISED: ["eyes_surprised", "mouth_surprised"]}
		for mood: int in expected:
			m.apply(mood, {"t": 1.0, "walk": 0.25, "wave": true, "squash": 0.3, "look": Vector2(1, -0.4)})
			var want: Array = expected[mood].duplicate()
			if mood == M.NORMAL and s == PlayerAvatar.STYLE_ROBOT:
				want.append("mouth_robot")
			want.sort()
			check(m.visible_features() == want, "estilo %d, ánimo %d: cara %s" % [s, mood, m.visible_features()])
		m.apply(M.NORMAL, {"blink": true})
		check("eyes_blink" in m.visible_features(), "estilo %d: parpadea" % s)
		m.apply(M.NORMAL, {"squash": 9.0})
		check(m.get_child(0).scale.y > 0.5, "el aplastado se recorta (no da vuelta la mascota)")
		m.free()
	var poses: Array = ["normal", "happy", "no-existe", {"name": "propia", "mood": M.SAD, "anim": {"t": 0.2}}, 42]
	var tex := await Mascot3DBaker.bake(root, {"color": 7, "style": 4}, poses, 64)
	if DisplayServer.get_name() == "headless":
		check(tex.is_empty() and Mascot3DBaker.last_report.get("headless", false), "sin pantalla arma la escena y no hornea")
	else:
		check(tex.size() == 3 and tex.has("propia"), "hornea las poses válidas (%s)" % [tex.keys()])
		check(tex.values().all(func(t: Texture2D) -> bool: return t.get_size() == Vector2(64, 64)), "celdas de 64 px")
	# Datos raros (color inválido, estilo fuera de rango, sin poses): nunca rompe.
	check((await Mascot3DBaker.bake(root, {"color": "zzz", "style": 99}, [], 64)).is_empty(), "sin poses no hay nada")
	check((await Mascot3DBaker.bake(null, {}, ["normal"], 64)).is_empty(), "sin nodo donde colgarse no hornea")
	var feet := Mascot3DBaker.feet_offset(144.0)
	check(feet.x == 72.0 and feet.y > 130.0 and feet.y < 144.0, "los pies quedan abajo y al centro de la celda")
	await process_frame


func test_tick_countdown() -> void:
	var game := MiniGame.new()
	game.setup(_fake_players(3))
	var got: Array = []
	game.feedback.connect(func(pid: int, kind: String) -> void: got.append([pid, kind]))
	game.tick_countdown(2.1, 1.9)
	check(got.is_empty(), "3 -> 2 solo suena en la TV")
	game.tick_countdown(0.05, -0.01)
	check(got.size() == 3 and got.all(func(g: Array) -> bool: return g[1] == "go"), "al llegar a 0 vibran todos los celulares")
	game.tick_countdown(-0.01, -0.03)
	check(got.size() == 3, "después de 0 no repite")
	game.free()


# --- Competencia ------------------------------------------------------------------

func test_tournament_rank() -> void:
	var places := Tournament.rank([
		{"id": 1, "score": 12.0, "winner": false},
		{"id": 2, "score": 9.0, "winner": false},
		{"id": 3, "score": 9.0, "winner": false},
		{"id": 4, "score": 2.0, "winner": false},
	] as Array[Dictionary])
	check(places == {1: 1, 2: 2, 3: 2, 4: 4}, "empates comparten puesto y el siguiente se saltea (%s)" % places)
	places = Tournament.rank([
		{"id": 1, "score": 50.0, "winner": false},
		{"id": 2, "score": 10.0, "winner": true},
	] as Array[Dictionary])
	check(places[2] == 1 and places[1] == 2, "el ganador declarado por el juego va primero")
	check(Tournament.points_for_place(1) == 100 and Tournament.points_for_place(4) == 30, "puntos por puesto")
	check(Tournament.points_for_place(9) == 30 and Tournament.points_for_place(0) == 100, "puestos fuera de rango se recortan")


func test_tournament_flow() -> void:
	var players := _fake_players(3)
	var t := Tournament.new(["arena", "pingpong", "no-existe", "arena", "tap_race"] as Array[String], players)
	check(t.game_ids == (["arena", "pingpong", "tap_race"] as Array[String]), "descarta ids desconocidos y repetidos")
	check(t.advance(3) == "arena", "empieza por el primero")
	check(t.round_number() == 1, "ronda 1 en curso")
	var s := t.record({"winners": [1], "scores": {1: 12, 2: 9, 3: 9}}, players)
	check(s.round == 1 and s.title == "Arena de estrellas" and s.score_label == "estrellas", "resumen con metadatos del juego")
	check(s.rows.size() == 3 and s.rows[0].slot == 0, "una fila por jugador, ordenadas por lugar")
	check(s.rows[0].points == 100 and s.rows[1].points == 70 and s.rows[2].points == 70, "puntos de la ronda")
	check(s.rows[1].total_before == 0 and s.rows[1].total == 70, "total antes y después")
	check(t.peek_next(3) == "tap_race", "peek saltea juegos que no admiten 3 jugadores")
	check(t.advance(3) == "tap_race" and t.skipped == (["pingpong"] as Array[String]), "Ping Pong (2 jugadores) se saltea")
	check(t.total_rounds() == 2, "las rondas salteadas no cuentan")
	t.record({"winners": [3], "scores": {1: 20, 2: 30, 3: 40}}, players)
	check(t.advance(3) == "" and t.is_over(), "termina cuando no quedan juegos")
	var st := t.standings()
	check(st[0].id == 3 and st[0].total == 170 and st[0].place == 1, "tabla general: primero Tomi con 170 (%s)" % [st[0]])
	check(st[1].total == 150 and st[2].total == 140, "tabla general ordenada por puntos")


func test_tournament_ties_and_skip() -> void:
	var players := _fake_players(2)
	var t := Tournament.new(["pingpong", "tap_race"] as Array[String], players, true)
	check(t.game_ids.size() == 2 and "pingpong" in t.game_ids and "tap_race" in t.game_ids, "mezclar conserva los juegos")
	t.advance(2)
	t.skip_current()
	check(t.skipped.size() == 1 and t.total_rounds() == 1, "saltar un juego no da puntos ni cuenta como ronda")
	t.advance(2)
	t.record({"winners": [1, 2], "scores": {1: 5, 2: 5}}, players)
	var st := t.standings()
	check(st[0].place == 1 and st[1].place == 1 and st[0].total == 100 and st[1].total == 100, "empate total: ambos primeros")


func test_tournament_survives_bad_results() -> void:
	var players := _fake_players(2)
	var t := Tournament.new(["arena"] as Array[String], players)
	t.advance(2)
	var s := t.record({"winners": "x", "scores": {1: NAN, 2: "mucho"}}, players)
	check(s.rows.size() == 2, "resultado inválido no rompe")
	t = Tournament.new(["arena"] as Array[String], players)
	t.advance(2)
	s = t.record({}, players)
	check(s.rows[0].place == 1 and s.rows[1].place == 1, "sin puntajes: todos empatan")
	check(Tournament.new([] as Array[String], players).advance(2) == "", "sin juegos no hay rondas")


# --- Lobby ------------------------------------------------------------------------

func test_lobby_screen() -> void:
	var lobby := LobbyScreen.new()
	root.add_child(lobby)
	var capacity: Array[int] = []
	lobby.capacity_changed.connect(func(n: int) -> void: capacity.append(n))
	lobby.refresh(_fake_players(1))
	check(lobby.player_count == LobbyScreen.DEFAULT_PLAYERS, "arranca en %d jugadores" % LobbyScreen.DEFAULT_PLAYERS)
	check(not lobby.can_start(), "no arranca si falta gente")
	lobby.refresh(_fake_players(2))
	check(lobby.can_start(), "con 2 de 2 se puede empezar")
	check(lobby.selected_game_ids().size() == MiniGameRegistry.all_info().size(), "por defecto entran todos los juegos")
	lobby.refresh(_fake_players(3))
	check(lobby.player_count == 3 and capacity.has(3), "la cantidad sube sola si entra más gente")
	check(not "pingpong" in lobby.selected_game_ids(), "juegos incompatibles con 3 quedan afuera")
	(lobby._cards["arena"] as GameCard).button_pressed = false
	var ids := lobby.selected_game_ids()
	check(not "arena" in ids and "tap_race" in ids, "desmarcar un juego lo saca (%s)" % [ids])
	for id: String in ids:
		(lobby._cards[id] as GameCard).button_pressed = false
	check(not lobby.can_start(), "sin juegos no se puede empezar")
	lobby._stepper.set_value(1)
	check(lobby.player_count == 3, "no se puede bajar de la cantidad de conectados")
	lobby.queue_free()
	await process_frame


## Cada juego del registry tiene su miniatura para la tarjeta del lobby y la
## intro. Un juego nuevo sin miniatura falla acá con el comando para generarla.
func test_games_have_thumbnails() -> void:
	for info in MiniGameRegistry.all_info():
		var path := GameCard.thumbnail_path(info.id)
		var how := ("generala con: xvfb-run -a -s \"-screen 0 1920x1080x24\" godot --path . --rendering-driver opengl3 "
			+ "--audio-driver Dummy -s res://tools/make_thumbnails.gd -- --only=%s ; después: godot --headless --path . --import") % info.id
		check(FileAccess.file_exists(path), "%s: falta la miniatura %s; %s" % [info.id, path, how])
		if FileAccess.file_exists(path):
			var tex := GameCard.thumbnail(info.id)
			check(tex != null, "%s: la miniatura existe pero Godot no la importó (godot --headless --path . --import)" % info.id)
			if tex != null:
				check(tex.get_width() >= 320 and absf(tex.get_width() / float(tex.get_height()) - 16.0 / 9.0) < 0.05,
					"%s: miniatura 16:9 de al menos 320 px (%dx%d)" % [info.id, tex.get_width(), tex.get_height()])
				check(GameCard.thumbnail(info.id) == tex, "%s: la miniatura se carga una sola vez (cache)" % info.id)


## Una tarjeta sin miniatura (juego recién agregado) usa el dibujo de respaldo
## y sigue funcionando: marcar, deshabilitar y dibujar.
func test_game_card_without_thumbnail() -> void:
	var info := {"id": "juego_sin_foto", "title": "Juego nuevo", "min_players": 1, "max_players": 4,
		"layout": Protocol.LAYOUT_ONE_BUTTON, "accent": UiTheme.ACCENT}
	check(GameCard.thumbnail("juego_sin_foto") == null and GameCard.thumbnail("") == null, "sin archivo: null")
	var card := GameCard.new(info)
	root.add_child(card)
	card.size = Vector2(300, 206)
	check(card._thumb == null, "la tarjeta queda sin foto")
	card.button_pressed = true
	check(card.is_selected(), "se puede marcar")
	await process_frame
	card.set_unavailable("Solo 2 jugadores")
	check(card.disabled and not card.is_selected(), "se puede deshabilitar")
	await process_frame
	check(is_instance_valid(card), "se dibuja sin miniatura")
	card.queue_free()
	# Con miniatura: mismo comportamiento.
	var first: Dictionary = MiniGameRegistry.all_info()[0]
	var with_photo := GameCard.new(first)
	root.add_child(with_photo)
	with_photo.size = Vector2(300, 206)
	check(with_photo._thumb == GameCard.thumbnail(first.id), "la tarjeta usa la miniatura del juego")
	with_photo.set_unavailable("Solo 2 jugadores")
	await process_frame
	check(is_instance_valid(with_photo), "se dibuja con miniatura deshabilitada")
	with_photo.queue_free()
	await process_frame


func test_seat_card_uses_player_look() -> void:
	var seat := SeatCard.new(1)
	root.add_child(seat)
	seat.show_player({}, false)
	check(seat._avatar.color == Protocol.player_color(1) and seat._avatar.style == -1,
		"lugar libre: color y estilo del lugar")
	var black := Color("#16171D")
	seat.show_player({"id": 7, "slot": 1, "name": "Juli", "connected": true, "color": black,
		"style": PlayerAvatar.STYLE_ROBOT}, false)
	check(seat._avatar.color == black and seat._avatar.style == PlayerAvatar.STYLE_ROBOT,
		"usa el color y el estilo elegidos por el jugador")
	check(seat.state == SeatCard.State.READY and seat._name.text == "Juli", "muestra al jugador listo")
	seat.show_player({}, true)
	check(seat.state == SeatCard.State.LOCKED, "fuera de la cantidad: no juega")
	seat.queue_free()
	await process_frame


## Contraste WCAG: (L1 + 0,05) / (L2 + 0,05) con luminancia relativa (lineal).
func _contrast(a: Color, b: Color) -> float:
	var la := a.srgb_to_linear().get_luminance()
	var lb := b.srgb_to_linear().get_luminance()
	return (maxf(la, lb) + 0.05) / (minf(la, lb) + 0.05)


func test_text_on_contrast() -> void:
	# Nombres sobre el color del jugador (Carrera, Reloj exacto): texto grande,
	# mínimo 3:1 (WCAG AA para texto grande) con cualquier color de la paleta.
	var worst := 99.0
	for c: Color in Protocol.MASCOT_COLORS:
		worst = minf(worst, _contrast(c, UiTheme.text_on(c)))
	check(worst >= 3.0, "text_on da contraste ≥ 3:1 en toda la paleta (peor: %.2f)" % worst)
	check(UiTheme.text_on(Color.WHITE) == UiTheme.INK and UiTheme.text_on(Color.BLACK) == UiTheme.PAPER,
		"tinta sobre blanco y blanco sobre negro")


func test_splash_screen() -> void:
	var splash := SplashScreen.new()
	root.add_child(splash)
	var done := [false]
	splash.finished.connect(func() -> void: done[0] = true)
	var key := InputEventKey.new()
	key.keycode = KEY_ENTER
	key.pressed = true
	splash._input(key)
	var t0 := Time.get_ticks_msec()
	while not done[0] and Time.get_ticks_msec() - t0 < 2000:
		await process_frame
	check(done[0], "cualquier tecla saltea la presentación")
	await process_frame
	check(not is_instance_valid(splash), "la presentación se libera al terminar")
	var host := HostMain.new()
	check(not host.show_splash, "la TV de los tests arranca sin presentación")
	host.free()


# --- Integración host <-> control por WebSocket real --------------------------

func test_join_play_reconnect() -> void:
	var server := HostServer.new()
	root.add_child(server)
	check(server.start(TEST_PORT, "127.0.0.1") == OK, "el servidor abre el puerto")
	var joined: Array = []
	var inputs: Array = []
	server.player_joined.connect(func(p: Dictionary) -> void: joined.append(p))
	server.input_received.connect(func(pid: int, i: Dictionary) -> void: inputs.append([pid, i]))

	# Código incorrecto -> rechazado
	var bad := _client()
	var rejected: Array = []
	bad.rejected.connect(func(r: String) -> void: rejected.append(r))
	bad.join("127.0.0.1", TEST_PORT, "ZZZZ" if server.room_code != "ZZZZ" else "YYYY", "Intruso")
	await _until(func() -> bool: return not rejected.is_empty())
	check(rejected == [Protocol.R_BAD_ROOM], "código incorrecto rechazado (%s)" % [rejected])

	# Código correcto -> unido como jugador 1
	var c1 := _client()
	var info: Array = []
	c1.joined.connect(func(i: Dictionary) -> void: info.append(i))
	c1.join("127.0.0.1", TEST_PORT, server.room_code.to_lower(), "Pablo")
	await _until(func() -> bool: return not info.is_empty())
	check(not info.is_empty() and info[0].id == 1, "se une como jugador 1")
	check(joined.size() == 1 and joined[0].name == "Pablo", "el host registra el jugador")
	check(not joined[0].has("token"), "el token no se expone a la lógica del juego")

	# Input llega validado
	c1.send_input(Vector2(0.5, 0), Protocol.BTN_A)
	await _until(func() -> bool: return not inputs.is_empty())
	check(not inputs.is_empty() and inputs[0][0] == 1 and inputs[0][1].btn == Protocol.BTN_A, "input recibido")

	# Latencia medida
	await _until(func() -> bool: return c1.rtt_ms >= 0, 2500)
	check(c1.rtt_ms >= 0, "se mide la latencia")

	# Sala llena
	var others: Array[ControllerClient] = []
	for i in 3:
		var c := _client()
		c.join("127.0.0.1", TEST_PORT, server.room_code, "J%d" % i)
		others.append(c)
	await _until(func() -> bool: return joined.size() == 4)
	var fifth := _client()
	var r5: Array = []
	fifth.rejected.connect(func(r: String) -> void: r5.append(r))
	fifth.join("127.0.0.1", TEST_PORT, server.room_code, "Quinto")
	await _until(func() -> bool: return not r5.is_empty())
	check(r5 == [Protocol.R_ROOM_FULL], "quinto jugador rechazado")

	# Layout se propaga
	var layouts: Array = []
	c1.layout_changed.connect(func(l: String, _d: Dictionary) -> void: layouts.append(l))
	server.set_layout(Protocol.LAYOUT_JOYSTICK)
	await _until(func() -> bool: return Protocol.LAYOUT_JOYSTICK in layouts)
	check(Protocol.LAYOUT_JOYSTICK in layouts, "el control recibe el layout")

	# Reconexión: se corta la conexión y vuelve con el mismo id
	var reconnected: Array = []
	c1.reconnected.connect(func() -> void: reconnected.append(true))
	c1._ws.close()
	await _until(func() -> bool: return not reconnected.is_empty(), 5000)
	check(not reconnected.is_empty() and c1.player_info.id == 1, "reconecta y recupera su lugar")
	check(server.get_players().size() == 4, "no se duplica el jugador")

	# Partida en curso: no entran nuevos
	var p4 := others[2]
	p4.leave()
	await _until(func() -> bool: return server.get_players().size() == 3)
	check(server.get_players().size() == 3, "leave libera el lugar")
	server.accepting_new_players = false
	var late := _client()
	var rl: Array = []
	late.rejected.connect(func(r: String) -> void: rl.append(r))
	late.join("127.0.0.1", TEST_PORT, server.room_code, "Tarde")
	await _until(func() -> bool: return not rl.is_empty())
	check(rl == [Protocol.R_GAME_IN_PROGRESS], "no entran jugadores durante la partida")

	server.stop()
	server.queue_free()
	for c in root.get_children():
		if c is ControllerClient:
			c.queue_free()
	await process_frame


func test_room_capacity() -> void:
	var server := HostServer.new()
	root.add_child(server)
	server.start(TEST_PORT + 2, "127.0.0.1")
	server.max_players = 2
	for n in ["A", "B"]:
		_client().join("127.0.0.1", TEST_PORT + 2, server.room_code, n)
	await _until(func() -> bool: return server.get_players().size() == 2)
	var third := _client()
	var r: Array = []
	third.rejected.connect(func(reason: String) -> void: r.append(reason))
	third.join("127.0.0.1", TEST_PORT + 2, server.room_code, "C")
	await _until(func() -> bool: return not r.is_empty())
	check(r == [Protocol.R_ROOM_FULL], "la capacidad elegida en la TV limita la sala (%s)" % [r])
	server.max_players = 99
	check(server.max_players == Protocol.MAX_PLAYERS, "la capacidad se recorta al máximo del protocolo")
	server.stop()
	server.queue_free()
	await _free_clients()


## Flujo completo en la TV con controles reales: lobby -> intro -> juego ->
## resumen -> intro -> juego -> pausa/saltar -> podio -> jugar otra vez -> lobby.
## Sin barrido entre pantallas (ver test_screen_transition).
func test_host_tournament_flow() -> void:
	var host := HostMain.new()
	host.server_port = TEST_PORT + 3
	host.announce = false
	host.transition_seconds = 0.0
	root.add_child(host)
	await process_frame
	var c1 := _client()
	var layouts: Array = []
	c1.layout_changed.connect(func(l: String, _d: Dictionary) -> void: layouts.append(l))
	c1.join("127.0.0.1", TEST_PORT + 3, host.server.room_code, "Pablo")
	_client().join("127.0.0.1", TEST_PORT + 3, host.server.room_code, "Sofi")
	await _until(func() -> bool: return host.server.get_players().size() == 2)
	check(host._lobby.can_start(), "lobby listo con 2 jugadores")
	check(not host.start_tournament([] as Array[String]), "sin juegos no arranca")

	check(host.start_tournament(["tap_race", "pingpong"] as Array[String]), "arranca la competencia")
	check(not host.start_tournament(["tap_race"] as Array[String]), "no arranca dos veces")
	check(host.phase == Protocol.PHASE_PLAYING and host._intro.visible and host._game == null, "primero la intro")
	check(not host.server.accepting_new_players, "no entran jugadores nuevos durante la competencia")
	await _until(func() -> bool: return Protocol.LAYOUT_ONE_BUTTON in layouts)
	check(Protocol.LAYOUT_ONE_BUTTON in layouts, "el celular recibe el control del juego ya en la intro")
	host.skip_intro()
	check(host._game != null and not host._intro.visible, "saltar la intro arranca el juego")

	host._game.finish({"winners": [2], "scores": {1: 30, 2: 40}})
	check(host.phase == Protocol.PHASE_RESULTS and host._summary.visible, "resumen de ronda al terminar")
	check(host.tournament.totals == {1: 70, 2: 100}, "puntos acumulados (%s)" % host.tournament.totals)

	var cancel := InputEventAction.new()
	cancel.action = "ui_cancel"
	cancel.pressed = true
	host._unhandled_input(cancel)
	check(host._pause.visible and host._summary.paused, "Atrás en el resumen abre el menú y frena la cuenta")
	host._unhandled_input(cancel)
	check(not host._pause.visible and not host._summary.paused, "Atrás de nuevo lo cierra")

	host._summary._on_continue()
	check(host.phase == Protocol.PHASE_PLAYING and host.tournament.current_game_id == "pingpong", "sigue Ping Pong")
	check(host._intro.visible and not host._summary.visible, "con su intro")
	host.skip_intro()
	host._unhandled_input(cancel)
	check(host._pause.visible and host._game.process_mode == Node.PROCESS_MODE_DISABLED, "pausa congela el juego")
	host._skip_game()
	check(host._final.visible and host.tournament.is_over(), "saltar el último juego lleva al podio")
	check(host.tournament.history.size() == 1, "el juego salteado no suma ronda")

	host._play_again()
	check(host.phase == Protocol.PHASE_PLAYING and host.tournament.history.is_empty(), "jugar otra vez reinicia los puntos")
	host._quit_tournament()
	check(host.phase == Protocol.PHASE_LOBBY and host._lobby.visible, "terminar sin rondas jugadas vuelve al lobby")
	check(host.server.accepting_new_players, "en el lobby vuelven a entrar jugadores")

	host.queue_free()
	await _free_clients()


## Cada celular recibe SU resultado ("standing") al terminar un juego de la
## competencia y en el podio, y lo recupera si se reconecta.
func test_host_port_fallback() -> void:
	# Si el puerto habitual está ocupado, la TV abre el siguiente libre.
	var port := TEST_PORT + 50
	var blocker := TCPServer.new()
	check(blocker.listen(port, "*") == OK, "ocupa el puerto de prueba")
	var host := HostMain.new()
	host.server_port = port
	host.announce = false
	root.add_child(host)
	await process_frame
	check(host.server.is_listening() and host.server.port == port + 1,
		"abre el siguiente puerto (%d)" % host.server.port)
	host.queue_free()
	blocker.stop()
	await process_frame


func test_host_sends_standing() -> void:
	var port := TEST_PORT + 4
	var host := HostMain.new()
	host.server_port = port
	host.announce = false
	host.transition_seconds = 0.0
	root.add_child(host)
	await process_frame
	check(host.server.is_listening(), "la TV abre el puerto %d" % port)
	var c1 := _client()
	var c2 := _client()
	var got1: Array[Dictionary] = []
	var got2: Array[Dictionary] = []
	c1.standing_received.connect(func(d: Dictionary) -> void: got1.append(d))
	c2.standing_received.connect(func(d: Dictionary) -> void: got2.append(d))
	c1.join("127.0.0.1", port, host.server.room_code, "Pablo")
	await _until(func() -> bool: return host.server.get_players().size() == 1)
	c2.join("127.0.0.1", port, host.server.room_code, "Sofi")
	await _until(func() -> bool: return host.server.get_players().size() == 2)
	if not check_that(host.start_tournament(["tap_race", "arena"] as Array[String]), "arranca la competencia"):
		host.queue_free()
		await _free_clients()
		return
	host.skip_intro()
	await process_frame
	check(got1.is_empty() and got2.is_empty(), "sin standing mientras se juega")

	host._game.finish({"winners": [2], "scores": {1: 30, 2: 40}})
	await _until(func() -> bool: return not got1.is_empty() and not got2.is_empty())
	check(not got1.is_empty() and not got2.is_empty(), "ambos celulares reciben su resultado")
	if got1.is_empty() or got2.is_empty():
		host.queue_free()
		await _free_clients()
		return
	check(got1[0] == {"round": 1, "total_rounds": 2, "place": 2, "points": 70, "total": 70, "rank": 2, "players": 2, "final": false},
		"Pablo: 2° en la ronda, +70 (%s)" % got1[0])
	check(got2[0].place == 1 and got2[0].points == 100 and got2[0].total == 100 and got2[0].rank == 1, "Sofi: 1°, +100 (%s)" % got2[0])
	check((host._standings_sent[1] as Dictionary).keys().size() == 8 and not host._standings_sent[1].has("token"),
		"solo datos propios, sin token ni datos de otros")

	host._summary._on_continue()
	check(host.tournament.current_game_id == "arena", "sigue Arena")
	host.skip_intro()
	host._game.finish({"winners": [1], "scores": {1: 12, 2: 3}})
	await _until(func() -> bool: return got1.size() == 2 and got2.size() == 2)
	check(got1.size() == 2 and got1[1].round == 2 and got1[1].place == 1 and got1[1].total == 170, "ronda 2: Pablo 1° con 170")
	host._summary._on_continue()
	check(host._final.visible, "podio")
	await _until(func() -> bool: return got1.size() == 3 and got2.size() == 3)
	check(got1.size() == 3 and got1[2].final and got1[2].rank == 1 and got1[2].total == 170, "podio: Pablo termina 1° (%s)" % [got1.back()])
	check(got2.size() == 3 and got2[2].final and got2[2].rank == 1 and got2[2].total == 170, "podio: empate, Sofi también 1°")

	# Reconexión durante el podio: vuelve a recibir su resultado.
	var reconnected: Array = []
	c1.reconnected.connect(func() -> void: reconnected.append(true))
	c1._ws.close()
	await _until(func() -> bool: return got1.size() == 4, 5000)
	check(not reconnected.is_empty() and got1.size() == 4 and got1[3].final, "al reconectarse recupera el resultado")

	host.queue_free()
	await _free_clients()


## Intro "¿Cómo se juega?" antes de cada juego: se ve la ronda, el celular ya
## tiene el control, el input se ignora, avanza con OK o con el tiempo y
## "Atrás" abre la pausa (con "Saltar este juego").
func test_game_intro() -> void:
	var port := TEST_PORT + 40
	var host := HostMain.new()
	host.server_port = port
	host.announce = false
	host.transition_seconds = 0.0
	root.add_child(host)
	await process_frame
	var c1 := _client()
	var layouts: Array = []
	c1.layout_changed.connect(func(l: String, _d: Dictionary) -> void: layouts.append(l))
	c1.join("127.0.0.1", port, host.server.room_code, "Pablo")
	await _until(func() -> bool: return host.server.get_players().size() == 1)
	_client().join("127.0.0.1", port, host.server.room_code, "Sofi")
	await _until(func() -> bool: return host.server.get_players().size() == 2)
	var inputs: Array = []
	host.server.input_received.connect(func(pid: int, _i: Dictionary) -> void: inputs.append(pid))

	check(host.start_tournament(["tap_race", "arena", "stop_clock"] as Array[String]), "arranca la competencia")
	var intro := host._intro
	check(intro.visible and host._game == null and host.phase == Protocol.PHASE_PLAYING, "la intro va antes del primer juego")
	check(intro._round.text == "Ronda 1/3", "muestra la ronda (%s)" % intro._round.text)
	check(intro._title.text == "Carrera de toques" and intro._description.text == MiniGameRegistry.info("tap_race").description,
		"título y descripción del juego")
	check(intro._art.layout == Protocol.LAYOUT_ONE_BUTTON, "ilustra el control del juego")
	check(intro._players_row.get_child_count() == 2 and intro._players_label.text == "2 jugadores", "muestra quiénes juegan")
	check(intro._continue.has_focus(), "el foco queda en el botón para el D-pad")
	await _until(func() -> bool: return Protocol.LAYOUT_ONE_BUTTON in layouts)
	check(Protocol.LAYOUT_ONE_BUTTON in layouts, "el celular ya muestra el control durante la intro")

	# Input del celular durante la intro: llega a la TV pero se descarta.
	c1.send_input(Vector2.ZERO, Protocol.BTN_A)
	await _until(func() -> bool: return not inputs.is_empty())
	check(not inputs.is_empty(), "el input llega al servidor")
	check(intro.visible and host._game == null, "el celular no puede saltar la intro")
	host._on_input(1, {"seq": 99, "axis": Vector2.ZERO, "btn": Protocol.BTN_A})
	check(host._game == null, "input directo durante la intro: sin efecto")

	# Pausa durante la intro: congela la cuenta regresiva.
	var cancel := InputEventAction.new()
	cancel.action = "ui_cancel"
	cancel.pressed = true
	host._unhandled_input(cancel)
	check(host._pause.visible and intro.paused and host._pause._skip.visible, "Atrás en la intro abre la pausa (con Saltar)")
	intro._process(GameIntroScreen.AUTO_CONTINUE_SEC + 1.0)
	check(intro.visible and host._game == null, "en pausa la intro no avanza sola")
	host._unhandled_input(cancel)
	check(not host._pause.visible and not intro.paused and intro._continue.has_focus(), "Atrás de nuevo vuelve a la intro")

	# Avanza con OK.
	intro._continue.pressed.emit()
	check(not intro.visible and host._game != null and host.tournament.current_game_id == "tap_race", "OK arranca el juego")
	var taps: Dictionary = host._game.get("_taps")
	check(taps.get(1, -1) == 0, "lo apretado durante la intro no cuenta (%s)" % [taps])
	host._game.finish({"winners": [1], "scores": {1: 40, 2: 10}})
	check(host._summary.visible, "resumen")
	host._summary._on_continue()

	# Segunda intro: avanza sola con el tiempo.
	check(intro.visible and intro._round.text == "Ronda 2/3" and intro._title.text == "Arena de estrellas", "intro de la ronda 2")
	check(host._game == null and not host._summary.visible, "sin juego ni resumen detrás")
	intro._process(GameIntroScreen.AUTO_CONTINUE_SEC / 2.0)
	check(intro.visible and intro._ring.seconds == ceili(GameIntroScreen.AUTO_CONTINUE_SEC / 2.0), "cuenta regresiva visible")
	intro._process(GameIntroScreen.AUTO_CONTINUE_SEC / 2.0 + 0.1)
	check(not intro.visible and host._game != null and host.tournament.current_game_id == "arena", "a los 6 s arranca solo")
	host._game.finish({"winners": [2], "scores": {1: 3, 2: 9}})
	host._summary._on_continue()

	# Tercera intro: "Saltar este juego" desde la pausa lleva al podio.
	check(intro.visible and host.tournament.current_game_id == "stop_clock", "intro de la ronda 3")
	host._unhandled_input(cancel)
	host._pause._skip.pressed.emit()
	check(not intro.visible and not host._pause.visible and host._final.visible, "saltar desde la intro lleva al podio")
	check(host.tournament.history.size() == 2 and "stop_clock" in host.tournament.skipped, "el juego salteado no suma ronda")

	host.queue_free()
	await _free_clients()


## Barrido entre pantallas: corre los cambios en orden, cuando la pantalla
## está tapada; no dura más de 0,45 s y traga el input solo mientras corre.
func test_screen_transition() -> void:
	check(Transition.DURATION <= 0.45, "dura como máximo 0,45 s")
	var tr := Transition.new()
	root.add_child(tr)
	var calls: Array[String] = []
	tr.play(func() -> void:
		calls.append("a")
		tr.play(func() -> void: calls.append("anidado")))
	tr.play(func() -> void: calls.append("b"))
	check(calls.is_empty() and tr.is_running() and tr.visible, "el cambio espera a que la pantalla esté tapada")
	var start := Time.get_ticks_msec()
	await _until(func() -> bool: return not calls.is_empty(), 1000)
	check(calls == ["a", "b", "anidado"], "los cambios corren en el orden pedido (%s)" % [calls])
	tr.play(func() -> void: calls.append("c"))
	check(calls.back() == "c", "si ya se está destapando, el cambio va enseguida")
	await _until(func() -> bool: return not tr.is_running(), 1000)
	var elapsed := Time.get_ticks_msec() - start
	check(not tr.is_running() and not tr.visible, "termina y desaparece")
	check(elapsed < int(Transition.DURATION * 1000.0) + 250, "no se estira (%d ms)" % elapsed)
	tr.play(func() -> void: calls.append("d"))
	tr.finish_now()
	check(calls.back() == "d" and not tr.is_running(), "finish_now corre lo pendiente")
	tr.queue_free()

	# En la TV: el barrido traga "Atrás" mientras corre y después ya no.
	var port := TEST_PORT + 41
	var host := HostMain.new()
	host.server_port = port
	host.announce = false
	root.add_child(host)
	await process_frame
	_client().join("127.0.0.1", port, host.server.room_code, "Pablo")
	await _until(func() -> bool: return host.server.get_players().size() == 1)
	check(host.start_tournament(["tap_race"] as Array[String]), "arranca la competencia")
	check(host._lobby.visible and not host._intro.visible and host._transition.is_running(), "el lobby sigue hasta que el barrido tapa")
	await _until(func() -> bool: return not host._transition.is_running(), 1000)
	check(host._intro.visible and not host._lobby.visible, "después del barrido: intro")
	host.skip_intro()
	check(host._game == null and host._intro.visible, "el juego arranca recién con la pantalla tapada")
	var cancel := InputEventAction.new()
	cancel.action = "ui_cancel"
	cancel.pressed = true
	root.push_input(cancel)
	check(not host._pause.visible, "durante el barrido se ignora Atrás")
	await _until(func() -> bool: return not host._transition.is_running(), 1000)
	check(host._game != null and not host._intro.visible, "después del barrido: juego")
	root.push_input(cancel)
	check(host._pause.visible, "terminado el barrido, Atrás vuelve a abrir la pausa")
	host.queue_free()
	await _free_clients()


func test_controller_standing_view() -> void:
	var ctrl := ControllerMain.new()
	root.add_child(ctrl)
	await process_frame
	ctrl._show_standing({"round": 1, "total_rounds": 3, "place": 2, "points": 70, "total": 170, "rank": 2, "players": 4, "final": false})
	check(ctrl._standing_panel.visible and ctrl._standing_medal.place == 2, "muestra el panel con la medalla del puesto")
	check(ctrl._standing_main.text == "+70" and ctrl._standing_total.text == "Total 170 · vas 2°", "textos de la ronda")
	check(ctrl._standing_round.text == "Ronda 1/3", "ronda")
	ctrl._on_layout_changed(Protocol.LAYOUT_JOYSTICK, {})
	check(not ctrl._standing_panel.visible, "se limpia cuando empieza otro juego")
	ctrl._on_layout_changed(Protocol.LAYOUT_WAIT, {})
	ctrl._show_standing({"round": 3, "total_rounds": 3, "place": 0, "points": 0, "total": 170, "rank": 1, "players": 4, "final": true})
	check(ctrl._standing_main.text == "¡Terminaste 1°!" and ctrl._standing_total.text == "170 pts", "podio final")
	ctrl._on_phase_changed(Protocol.PHASE_LOBBY)
	check(not ctrl._standing_panel.visible, "se limpia al volver al lobby")
	ctrl.queue_free()
	await process_frame


## Un aviso del juego llega solo al celular de ese jugador, validado y con
## límite de frecuencia.
func test_feedback_relay() -> void:
	var host := HostMain.new()
	host.server_port = TEST_PORT + 6
	host.announce = false
	host.transition_seconds = 0.0
	root.add_child(host)
	await process_frame
	var c1 := _client()
	var c2 := _client()
	var got1: Array = []
	var got2: Array = []
	c1.feedback_received.connect(func(k: String) -> void: got1.append(k))
	c2.feedback_received.connect(func(k: String) -> void: got2.append(k))
	c1.join("127.0.0.1", TEST_PORT + 6, host.server.room_code, "Pablo")
	await _until(func() -> bool: return host.server.get_players().size() == 1)
	c2.join("127.0.0.1", TEST_PORT + 6, host.server.room_code, "Sofi")
	await _until(func() -> bool: return host.server.get_players().size() == 2)
	host._lobby._stepper.set_value(2)
	check(host.start_tournament(["arena"] as Array[String]), "arranca Arena")
	host.skip_intro()
	var game := host._game
	# Juego congelado: si una estrella cae sobre alguien, Arena mandaría su
	# propio aviso y el test dependería del azar.
	game.process_mode = Node.PROCESS_MODE_DISABLED
	var p1: int = c1.player_info.id
	game.notify_player(p1, "point")
	game.notify_player(p1, "point")      # Muy seguido: se descarta.
	game.notify_player(p1, "explotar")   # Tipo inválido: no se manda.
	await _until(func() -> bool: return not got1.is_empty())
	await _frames(10)
	check(got1 == ["point"], "llega un solo aviso válido al jugador correcto (%s)" % [got1])
	check(got2.is_empty(), "el otro celular no recibe nada")
	host.queue_free()
	await _free_clients()


## Celular: sin control en pantalla anima a pocos cuadros por segundo y
## entra en bajo consumo; con un control activo vuelve a 60 fps.
func test_controller_power_mode() -> void:
	var ctrl := ControllerMain.new()
	root.add_child(ctrl)
	await process_frame
	check(ctrl._background.anim_fps == ControllerMain.IDLE_ANIM_FPS, "esperando: nubes a pocos fps")
	check(ctrl._wait_avatar.anim_fps == ControllerMain.IDLE_ANIM_FPS, "esperando: mascota a pocos fps")
	check(OS.low_processor_usage_mode, "esperando: modo de bajo consumo")
	ctrl._on_layout_changed(Protocol.LAYOUT_JOYSTICK, {})
	check(ctrl._background.anim_fps == 0.0 and not OS.low_processor_usage_mode, "jugando: sin bajo consumo (latencia)")
	ctrl._on_layout_changed(Protocol.LAYOUT_WAIT, {})
	check(OS.low_processor_usage_mode, "vuelve a bajo consumo al esperar")
	ctrl.queue_free()
	await process_frame
	check(not OS.low_processor_usage_mode, "al salir deja el modo como estaba")


## El cielo, el campo y el marcador de los juegos se dibujan en capas
## propias que no se redibujan en cada frame (ver MiniGame "Capas cacheadas").
func test_minigame_cached_layers() -> void:
	var game := MiniGameRegistry.create("tap_race")
	root.add_child(game)
	game.setup(_fake_players(2))
	for i in 3:
		await process_frame
	check(game.get_child_count() == 0 and game.get_child_count(true) == 2, "capas internas (no aparecen en get_children)")
	check(game._backdrop_ops.size() == 2 and game._backdrop_ops[0] == ["sky"], "fondo: cielo + campo (%s)" % [game._backdrop_ops])
	check(game._hud_state.size() == 1 + 2 * 3, "marcador con 2 jugadores")
	var hud_before: Array = game._hud_state.duplicate()
	game.on_input(1, {"seq": 1, "axis": Vector2.ZERO, "btn": 0})
	await process_frame
	check(game._hud_state == hud_before, "sin cambios, el marcador no se toca")
	game.queue_free()
	await process_frame


## Empujones y Pintar el piso: el fondo pesado (agua, isla, baldosas) va en
## capas que solo se redibujan cuando cambia lo que muestran.
func test_sumo_paint_cached_layers() -> void:
	var sumo: Variant = MiniGameRegistry.create("sumo")
	root.add_child(sumo)
	sumo.setup(_fake_players(2))
	for i in 3:
		await process_frame
	check(sumo._water != null and sumo._waves.show_behind_parent, "sumo: agua e isla en capas detrás del juego")
	check(sumo._complete_rings() == 3, "sumo: 3 anillos enteros al empezar (%d)" % sumo._complete_rings())
	var edge_key: Array = sumo._layer_keys[sumo._edge]
	sumo._radius = 300.0
	sumo.queue_redraw()
	await process_frame
	check(sumo._layer_keys[sumo._edge] != edge_key and sumo._complete_rings() == 2, "sumo: al achicarse cambia el borde y se pierde un anillo")
	sumo.queue_free()
	var paint: Variant = MiniGameRegistry.create("paint")
	root.add_child(paint)
	paint.setup(_fake_players(2))
	await process_frame
	check(paint._floor.size() == paint.ROWS, "paint: una capa por fila de baldosas")
	paint._anim = 5.0
	paint._paint_area(1, paint.cell_center(Vector2i(3, 2)), 0)
	paint.queue_redraw()
	await process_frame
	check(paint._floor_tiles[2][3] == paint.EMPTY, "paint: la baldosa recién pintada no está en la capa (salta aparte)")
	paint._anim = 6.0
	paint.queue_redraw()
	await process_frame
	check(paint._floor_tiles[2][3] == 1, "paint: al terminar el salto pasa a la capa de su fila")
	paint.queue_free()
	await process_frame


func test_rejects_raw_garbage() -> void:
	var server := HostServer.new()
	root.add_child(server)
	server.start(TEST_PORT + 1, "127.0.0.1")
	var ws := WebSocketPeer.new()
	ws.connect_to_url("ws://127.0.0.1:%d" % (TEST_PORT + 1))
	await _until(func() -> bool:
		ws.poll()
		return ws.get_ready_state() == WebSocketPeer.STATE_OPEN)
	ws.send_text('{"v":%d,"type":"input","seq":1,"axis":[0,0],"btn":1}' % Protocol.VERSION)  # input sin haberse unido
	await _until(func() -> bool:
		ws.poll()
		return ws.get_ready_state() == WebSocketPeer.STATE_CLOSED)
	check(ws.get_ready_state() == WebSocketPeer.STATE_CLOSED, "cierra conexiones que no se unieron")
	check(server.get_players().is_empty(), "no crea jugadores")
	server.stop()
	server.queue_free()


# --- Apariencia del jugador (color y estilo, ver docs/adr/0007) ---------------

func test_parse_look() -> void:
	check(Protocol.MASCOT_STYLES == PlayerAvatar.STYLE_NAMES.size(), "Protocol.MASCOT_STYLES coincide con los estilos de PlayerAvatar")
	check(Protocol.MASCOT_COLOR_NAMES.size() == Protocol.MASCOT_COLORS.size(), "un nombre por color")
	check(Protocol.MASCOT_COLORS.slice(0, 4) == Protocol.PLAYER_COLORS, "los 4 primeros son los colores de siempre (1P–4P)")
	var unique := {}
	for c in Protocol.MASCOT_COLORS:
		unique[c.to_html()] = true
	check(unique.size() == Protocol.MASCOT_COLORS.size(), "colores sin repetir")
	check(Protocol.parse_color_index(3) == 3 and Protocol.parse_color_index(9.0) == 9, "enteros y floats sin decimales (JSON)")
	for bad: Variant in [-1, 10, 2.5, "3", true, null, [1], {"a": 1}, NAN, INF, -INF, 1e300, -0.5]:
		check(Protocol.parse_color_index(bad) == -1, "color inválido descartado: %s" % [bad])
	check(Protocol.parse_style_index(6) == 6 and Protocol.parse_style_index(7) == -1, "rango de estilos")
	check(Protocol.parse_style_index("robot") == -1 and Protocol.parse_style_index(-3) == -1, "estilo con tipo raro o negativo")
	check(Protocol.parse_look({}) == {}, "join viejo: sin campos, nada")
	check(Protocol.parse_look({"color": 7.0, "style": 4}) == {"color": 7, "style": 4}, "ambos válidos")
	check(Protocol.parse_look({"color": "blanco", "style": 4}) == {"style": 4}, "solo el válido")
	check(Protocol.parse_look({"color": 99, "style": 1.5}) == {}, "ambos inválidos")
	var app := Protocol.parse_appearance({"color": 2, "style": 5, "taken": [0, 0, 2, "x", 9, 3.5, 99, null]})
	check(app.color == 2 and app.style == 5, "appearance válido")
	check(app.taken == ([0, 9] as Array[int]), "taken sin inválidos, repetidos ni el propio (%s)" % [app.taken])
	check(Protocol.parse_appearance({"color": 2, "style": 5, "taken": "todos"}).taken.is_empty(), "taken con tipo raro: vacío")
	check(Protocol.parse_appearance({"color": 2}).is_empty() and Protocol.parse_appearance({"color": -1, "style": 0}).is_empty(), "appearance incompleto: {}")


func test_style_of() -> void:
	check(PlayerAvatar.style_of({"slot": 2}) == 2, "sin style: el clásico del lugar")
	check(PlayerAvatar.style_of({"slot": 0, "style": PlayerAvatar.STYLE_ROBOT}) == PlayerAvatar.STYLE_ROBOT, "usa el estilo elegido")
	check(PlayerAvatar.style_of({"slot": 1, "style": 7}) == 0 and PlayerAvatar.style_of({"style": -1}) == 6, "fuera de rango: da la vuelta")
	check(PlayerAvatar.style_of({"style": "gato"}) == 0 and PlayerAvatar.style_of({}) == 0, "tipos raros: 0 (nunca falla)")
	var avatar := PlayerAvatar.new()
	avatar.slot = 1
	avatar.style = PlayerAvatar.STYLE_BUNNY
	check(avatar.style == PlayerAvatar.STYLE_BUNNY, "el Control acepta un estilo distinto del lugar")
	avatar.free()
	check(UiTheme.on_light(Protocol.MASCOT_COLORS[7]).get_luminance() < 0.6, "el blanco se oscurece sobre pisos claros")
	check(UiTheme.on_light(Protocol.MASCOT_COLORS[9]) == Protocol.MASCOT_COLORS[9], "el negro queda igual")


## Todas las expresiones y animaciones se dibujan hasta el final (sin errores
## de script) con cualquier estilo y color, blanco y negro incluidos, chicas
## y grandes; las claves nuevas de anim son opcionales (y toleran valores
## fuera de rango).
func test_mascot_expressions_draw() -> void:
	var anims := [{}, {"t": 2.3}, {"t": 5.0, "walk": 0.3, "look": Vector2(1, 0)}, {"t": 1.0, "dance": 1.0},
		{"t": 7.7, "dance": 0.6, "dance_kind": PlayerAvatar.DANCE_SPIN}, {"t": 10.2, "dance": 1.0, "dance_kind": 99},
		{"t": 0.4, "defeat": 1.0, "greet": 0.5, "flop": 2.0, "squash": 0.4, "wave": true},
		{"t": 3.3, "dance": 5.0, "dance_kind": PlayerAvatar.DANCE_ARMS, "defeat": -2.0}]
	var colors: Array[Color] = Protocol.MASCOT_COLORS
	var moods := PlayerAvatar.Mood.size()
	var styles := PlayerAvatar.STYLE_NAMES.size()
	var expected := 0
	var probe := Control.new()
	probe.size = Vector2(400, 300)
	probe.draw.connect(func() -> void:
		for m in moods:
			for st in styles:
				for a in anims.size():
					for u in [0.7, 2.4]:
						PlayerAvatar.draw_mascot(probe, Vector2(200, 280), u, colors[(m + st + a) % colors.size()], st, m,
							0.5, 4.0, false, anims[a])
				# Blanco, negro y la silueta vacía, con cada ánimo y estilo.
				for c in [Color.WHITE, Color.BLACK, colors[colors.size() - 1]]:
					PlayerAvatar.draw_mascot(probe, Vector2(200, 280), 1.0, c, st, m, 0.0, 0.0, false, {"t": 1.5, "dance": 1.0})
				PlayerAvatar.draw_mascot(probe, Vector2(200, 280), 1.0, Color.RED, st, m, 0.0, 0.0, true, {"dance": 1.0})
		PlayerAvatar.draw_mascot(probe, Vector2(200, 280), 1.0, Color.RED, 0)  # API vieja: sin anim.
	)
	expected = moods * styles * (anims.size() * 2 + 4) + 1
	var before := PlayerAvatar.drawn
	root.add_child(probe)
	await _frames(3)
	check(PlayerAvatar.drawn - before == expected, "todas las combinaciones terminan de dibujarse (%d de %d)" % [PlayerAvatar.drawn - before, expected])
	probe.queue_free()
	check(PlayerAvatar.Mood.NORMAL == 0 and PlayerAvatar.Mood.SURPRISED == 3, "los ánimos viejos conservan su número")

	# El nodo: baile, derrota, saludo y dormirse.
	var av := PlayerAvatar.new()
	av.size = Vector2(160, 224)
	root.add_child(av)
	av.celebrate(PlayerAvatar.DANCE_SPIN, 0.1)
	await _until(func() -> bool: return av.dance >= 1.0)
	check(av.dance >= 1.0 and av.dance_kind == PlayerAvatar.DANCE_SPIN, "celebrate() baila")
	await _until(func() -> bool: return av.dance <= 0.0)
	check(av.dance <= 0.0, "celebrate(kind, segundos) para sola")
	av.lose()
	await _until(func() -> bool: return av.defeat >= 1.0)
	check(av.defeat >= 1.0, "lose() se desanima")
	av.lose(false)
	av.say_hello()
	await _until(func() -> bool: return av.greet >= 1.0)
	check(av.shown_mood() == PlayerAvatar.Mood.HAPPY, "saludando pone cara feliz")
	await _until(func() -> bool: return av.greet <= 0.0 and av.defeat <= 0.0)
	av.sleep_after = 0.05
	await _until(func() -> bool: return av.is_asleep())
	check(av.shown_mood() == PlayerAvatar.Mood.SLEEPY, "sin actividad se duerme")
	av.mood = PlayerAvatar.Mood.SAD
	check(av.shown_mood() == PlayerAvatar.Mood.SAD, "dormida solo con ánimo normal")
	av.mood = PlayerAvatar.Mood.NORMAL
	av.wake()
	check(not av.is_asleep() and av.shown_mood() == PlayerAvatar.Mood.NORMAL, "wake() la despierta")
	var drawn_before := PlayerAvatar.drawn
	av.celebrate()
	await _frames(3)
	check(PlayerAvatar.drawn > drawn_before, "el nodo bailando se redibuja")
	av.queue_free()


## El estilo elegido llega a los juegos, al torneo y a las pantallas de la TV.
func test_games_use_player_style() -> void:
	# Todas las llamadas a draw_mascot de los juegos pasan el estilo del
	# jugador (PlayerAvatar.style_of), no el número de lugar.
	var files: Array[String] = []
	for dir in DirAccess.get_directories_at("res://host/minigames"):
		for f in DirAccess.get_files_at("res://host/minigames/" + dir):
			if f.ends_with(".gd"):
				files.append("res://host/minigames/%s/%s" % [dir, f])
	var calls := 0
	for path in files:
		var src := FileAccess.get_file_as_string(path)
		var at := src.find("draw_mascot(")
		while at >= 0:
			var args := _call_args(src, at + "draw_mascot(".length())
			calls += 1
			check(args.size() >= 5 and args[4] == "PlayerAvatar.style_of(p)", "%s: draw_mascot usa el estilo del jugador (%s)" % [path.get_file(), args.slice(4, 5)])
			at = src.find("draw_mascot(", at + 1)
	check(calls >= 7, "se revisaron las llamadas de los juegos (%d)" % calls)

	var players := _fake_players(2)
	players[0]["style"] = PlayerAvatar.STYLE_HORNS
	players[0]["color"] = Protocol.MASCOT_COLORS[9]
	var t := Tournament.new(["arena"] as Array[String], players)
	t.advance(2)
	var s := t.record({"winners": [1], "scores": {1: 3, 2: 1}}, players)
	check(s.rows[0].style == PlayerAvatar.STYLE_HORNS and s.rows[1].style == 1, "el resumen de ronda lleva el estilo (o el del lugar)")
	check(t.standings()[0].style == PlayerAvatar.STYLE_HORNS, "la tabla general lleva el estilo")
	var bar := ScoreBar.new()
	bar.setup([{"id": 1, "slot": 0, "total": 5, "color": Protocol.MASCOT_COLORS[9]}] as Array[Dictionary], "Ronda 1/1")
	check(bar._chips.size() == 1, "el marcador acepta el color del jugador")
	bar.free()
	# Un juego real con estilos elegidos corre sin errores.
	var game := MiniGameRegistry.create("paint")
	root.add_child(game)
	game.setup(players)
	for i in 3:
		await process_frame
	check(game._mark[1] == Protocol.MASCOT_COLORS[9], "Pintar usa el color elegido")
	game.queue_free()
	await process_frame


## Red: join con y sin apariencia, colores únicos, "look" solo en el lobby.
func test_player_look_network() -> void:
	var port := TEST_PORT + 7
	var server := HostServer.new()
	root.add_child(server)
	server.start(port, "127.0.0.1")
	var updated: Array = []
	server.player_updated.connect(func(p: Dictionary) -> void: updated.append(p))

	# A pide blanco + robot.
	var a := _client()
	var a_app: Array = []
	a.appearance_changed.connect(func() -> void: a_app.append(a.player_info.duplicate()))
	a.join("127.0.0.1", port, server.room_code, "Ana", {"color": 7, "style": PlayerAvatar.STYLE_ROBOT})
	await _until(func() -> bool: return not a_app.is_empty())
	var pa: Dictionary = server.get_players()[0]
	check(pa.color_index == 7 and pa.color == Protocol.MASCOT_COLORS[7] and pa.style == PlayerAvatar.STYLE_ROBOT, "join con color y estilo (%s)" % [pa])
	check(a.player_info.color_index == 7 and a.player_info.style == PlayerAvatar.STYLE_ROBOT, "el celular recibe su apariencia")
	check(not pa.has("token"), "el jugador público sigue sin token")

	# B pide el mismo blanco: le toca el de su lugar (2P azul).
	var b := _client()
	var b_app: Array = []
	b.appearance_changed.connect(func() -> void: b_app.append(b.player_info.duplicate()))
	b.join("127.0.0.1", port, server.room_code, "Beto", {"color": 7})
	await _until(func() -> bool: return server.get_players().size() == 2 and not b_app.is_empty())
	var pb: Dictionary = server.get_players()[1]
	check(pb.color_index == 1 and pb.style == 1, "color ocupado: se asigna uno libre; estilo por defecto = lugar (%s)" % [pb])
	check(b.player_info.color_index == 1 and 7 in (b.player_info.taken as Array), "el celular sabe que el blanco está ocupado")

	# C es un control viejo: join sin campos nuevos.
	var ws := WebSocketPeer.new()
	ws.connect_to_url("ws://127.0.0.1:%d" % port)
	await _until(func() -> bool:
		ws.poll()
		return ws.get_ready_state() == WebSocketPeer.STATE_OPEN)
	ws.send_text(JSON.stringify({"v": Protocol.VERSION, "type": "join", "room": server.room_code, "name": "Viejo"}))
	await _until(func() -> bool:
		ws.poll()
		return server.get_players().size() == 3)
	var pc: Dictionary = server.get_players()[2]
	check(pc.color == Protocol.player_color(2) and pc.style == 2, "join viejo: color y estilo del lugar como siempre")

	# D manda basura en los campos opcionales: igual entra, con lo de su lugar.
	var ws2 := WebSocketPeer.new()
	ws2.connect_to_url("ws://127.0.0.1:%d" % port)
	await _until(func() -> bool:
		ws2.poll()
		return ws2.get_ready_state() == WebSocketPeer.STATE_OPEN)
	ws2.send_text(JSON.stringify({"v": Protocol.VERSION, "type": "join", "room": server.room_code, "name": "Raro", "color": "negro", "style": [99]}))
	await _until(func() -> bool:
		ws2.poll()
		return server.get_players().size() == 4)
	check(server.get_players().size() == 4 and server.get_players()[3].color_index == 3 and server.get_players()[3].style == 3, "campos inválidos se ignoran (no rechaza)")
	var colors := {}
	for p in server.get_players():
		colors[p.color_index] = true
	check(colors.size() == 4, "colores únicos entre los 4 jugadores")

	# look: A pide el azul de B (ocupado) y el conejo -> cambia solo el estilo.
	updated.clear()
	a_app.clear()
	a.send_look(1, PlayerAvatar.STYLE_BUNNY)
	await _until(func() -> bool: return not a_app.is_empty())
	pa = server.get_players()[0]
	check(pa.color_index == 7 and pa.style == PlayerAvatar.STYLE_BUNNY, "look: color ocupado se conserva el propio, el estilo cambia (%s)" % [pa])
	check(updated.size() == 1 and updated[0].style == PlayerAvatar.STYLE_BUNNY, "se emite player_updated")
	check(a.player_info.color_index == 7, "el celular recibe la corrección del color")

	# look: A pasa a negro; B se entera de que el blanco se liberó.
	a.send_look(9, PlayerAvatar.STYLE_BUNNY)
	await _until(func() -> bool: return 9 in (b.player_info.taken as Array))
	check(server.get_players()[0].color_index == 9 and not 7 in (b.player_info.taken as Array), "cambio de color avisado a los demás")

	# look con basura: se ignora sin romper nada.
	updated.clear()
	ws.send_text('{"v":%d,"type":"look","color":[1],"style":{"a":1}}' % Protocol.VERSION)
	ws.send_text('{"v":%d,"type":"look","color":1e999}' % Protocol.VERSION)
	ws.send_text('{"v":%d,"type":"look"}' % Protocol.VERSION)
	await _frames(10)
	ws.poll()
	check(updated.is_empty() and server.get_players()[2].color_index == 2, "look inválido ignorado")

	# Fuera del lobby, look se rechaza.
	server.set_phase(Protocol.PHASE_PLAYING)
	a.send_look(4, 0)
	await _frames(10)
	check(updated.is_empty() and server.get_players()[0].color_index == 9, "look rechazado durante la partida")
	server.set_phase(Protocol.PHASE_LOBBY)
	server.accepting_new_players = false  # Ya arrancó la competencia (barrido a la intro).
	a.send_look(4, 0)
	await _frames(10)
	check(updated.is_empty(), "look rechazado cuando la competencia ya arrancó")
	server.accepting_new_players = true

	# Límite de frecuencia: una ráfaga no pasa entera.
	for i in 30:
		ws.send_text(JSON.stringify({"v": Protocol.VERSION, "type": "look", "style": i % Protocol.MASCOT_STYLES}))
	await _frames(15)
	ws.poll()
	check(updated.size() <= HostServer.LOOK_RATE_LIMIT_PER_SEC, "look con límite de frecuencia (%d)" % updated.size())

	# Si A se va, su color queda libre para los demás.
	a.leave()
	await _until(func() -> bool: return server.get_players().size() == 3 and not 9 in (b.player_info.taken as Array))
	check(not 9 in (b.player_info.taken as Array), "al salir se libera su color")
	ws.close()
	ws2.close()
	server.stop()
	server.queue_free()
	await _free_clients()


## Celular: el selector aparece en el lobby con lo que confirmó la TV y se
## esconde fuera del lobby o con una TV vieja.
func test_controller_look_picker() -> void:
	var ctrl := ControllerMain.new()
	root.add_child(ctrl)
	await process_frame
	ctrl.client.player_info = {"id": 2, "name": "Sofi", "color": Protocol.MASCOT_COLORS[3], "color_index": 3,
		"style": PlayerAvatar.STYLE_HORNS, "taken": [0, 1] as Array[int]}
	ctrl._on_phase_changed(Protocol.PHASE_LOBBY)
	ctrl._on_appearance_changed()
	var picker := ctrl._look_picker
	check(picker.visible and picker.color_index == 3 and picker.style == PlayerAvatar.STYLE_HORNS, "selector visible en el lobby con lo confirmado")
	check(picker._swatches[0].disabled and not picker._swatches[3].disabled and picker._swatches[3].selected, "colores ocupados deshabilitados")
	check(ctrl._wait_avatar.style == PlayerAvatar.STYLE_HORNS and ctrl._wait_avatar.color == Protocol.MASCOT_COLORS[3], "la mascota grande muestra la apariencia")
	for sw in picker._swatches:
		check(sw.custom_minimum_size.x >= 88 and sw.custom_minimum_size.y >= 88, "botón de color ≥ 88 px")
	ctrl._on_phase_changed(Protocol.PHASE_PLAYING)
	check(not picker.visible, "se esconde durante la partida")
	ctrl._on_phase_changed(Protocol.PHASE_LOBBY)
	ctrl.client.player_info = {"id": 1, "name": "Viejo", "color": Color.RED, "color_index": -1, "style": -1, "taken": []}
	ctrl._on_appearance_changed()
	check(not picker.visible and ctrl._wait_avatar.style == -1, "TV vieja (sin colorIndex): sin selector, estilo del lugar")
	ctrl.queue_free()
	await process_frame

	# Selector suelto (sin guardar preferencias): flechas y colores.
	var lp := LookPicker.new()
	root.add_child(lp)
	var got: Array = []
	lp.look_changed.connect(func(c: int, s: int) -> void: got.append([c, s]))
	lp.set_look(2, 6, [4, "x", 99])
	check(got.is_empty() and lp.taken == ([4] as Array[int]), "set_look no emite y filtra ocupados inválidos")
	lp.step_style(1)
	check(got == [[2, 0]], "después de Conejo vuelve a Antena")
	lp._on_color_pressed(4)
	check(got.size() == 1, "un color ocupado no se puede elegir")
	lp._on_color_pressed(9)
	check(got.back() == [9, 0] and lp._color_label.text == "Negro", "elige negro")
	lp.set_look(99, -1)
	check(lp.color_index == Protocol.MASCOT_COLORS.size() - 1 and lp.style == Protocol.MASCOT_STYLES - 1, "valores fuera de rango se recortan")
	lp.queue_free()
	await process_frame


## Celular: pantalla para unirse (tarjetas de TV, código en fichas, avisos)
## y festejo del resultado que no queda animando.
func test_controller_join_screen() -> void:
	var ctrl := ControllerMain.new()
	root.add_child(ctrl)
	await process_frame
	ctrl._selected_host = {}
	ctrl._ip_edit.text = ""
	ctrl._on_hosts_changed([{"ip": "192.168.0.5", "port": 47999, "name": "Living"}] as Array[Dictionary])
	check(ctrl._ip_edit.text == "192.168.0.5" and ctrl._selected_host.get("port") == 47999, "una sola TV: se elige sola")
	await process_frame
	var cards := ctrl._hosts_box.get_children().filter(func(c: Node) -> bool: return c is HostCard and not c.is_queued_for_deletion())
	check(cards.size() == 1 and (cards[0] as HostCard).selected, "tarjeta de la TV elegida")
	check((cards[0] as HostCard).custom_minimum_size.y >= 88, "tarjeta de TV ≥ 88 px")
	ctrl._code_edit.text = "ab1"
	ctrl._code_edit._on_text_changed("ab1")
	check(ctrl._code_edit.text == "AB1", "el código pasa a mayúsculas")
	ctrl._name_edit.text = ""
	ctrl._on_join_pressed()
	check(ctrl._join_status_panel.visible and ctrl._join_status.text.contains("apodo"), "aviso amable si falta el apodo")
	ctrl._show_join("")
	check(not ctrl._join_status_panel.visible, "sin mensaje, sin aviso")
	# Resultado en el podio: papelitos que se apagan solos al empezar otro juego.
	ctrl._show_standing({"round": 1, "total_rounds": 3, "place": 1, "points": 100, "total": 100, "rank": 1, "players": 2, "final": false})
	check(ctrl._confetti.is_processing() and ctrl._standing_cheer.text == "¡Ganaste la ronda!", "festeja el primer puesto")
	ctrl._on_layout_changed(Protocol.LAYOUT_ONE_BUTTON, {"label": "A"})
	check(not ctrl._confetti.is_processing(), "los papelitos se cortan al empezar otro juego")
	ctrl.queue_free()
	await process_frame


## Celular: ajustes (zurdo invierte el control, tamaño, sonido y vibración),
## latencia oculta por defecto, todo guardado en el archivo local, y "Salir"
## que hay que mantener apretado 1 s.
func test_controller_settings_and_hold() -> void:
	var path := "user://test_phone_settings.cfg"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	var was_muted := Sfx.muted
	var was_vibrating := Haptics.enabled
	Sfx.muted = false
	Haptics.enabled = true
	var ctrl := ControllerMain.new()
	ctrl.settings_path = path
	root.add_child(ctrl)
	await process_frame
	check(not ctrl.settings.dev_mode and not ctrl._latency.visible, "la latencia en ms está oculta por defecto")
	check(ctrl._signal.visible, "el ícono de señal se ve para todos")
	ctrl._update_latency(300)
	check(ctrl._signal.level == SignalIcon.BAD and ctrl._latency.text == "— ms", "latencia alta: señal roja, sin ms fuera del modo desarrollador")
	ctrl._update_latency(40)
	check(ctrl._signal.level == SignalIcon.GOOD, "latencia baja: 3 barras")

	# Zurdo: el joystick pasa a la derecha y el botón a la izquierda.
	ctrl._on_layout_changed(Protocol.LAYOUT_JOYSTICK, {})
	var joy := ctrl._active_layout as VirtualJoystick
	joy.size = Vector2(2000, 900)
	check(not joy.lefty and joy.rest_position().x < 1000.0, "diestro: joystick a la izquierda")
	check(ctrl._backdrop.show_watermark and ctrl._backdrop.watermark_right, "mascota del fondo del lado libre (derecha)")
	ctrl._settings_panel._lefty.pressed.emit()
	check(ctrl.settings.lefty and joy.lefty and joy.rest_position().x > 1000.0, "zurdo: joystick a la derecha")
	check(not ctrl._backdrop.watermark_right, "zurdo: la mascota del fondo pasa a la izquierda")
	ctrl._on_layout_changed(Protocol.LAYOUT_ONE_BUTTON, {"label": "A"})
	var btn := ctrl._active_layout as BigButton
	btn.size = Vector2(2000, 900)
	check(btn.lefty and btn.button_center().x < 1000.0, "zurdo: botón a la izquierda")
	check(ctrl._backdrop.watermark_right, "zurdo con botón: la mascota del fondo a la derecha")
	# Joystick + A/B: el ajuste zurdo lo pone en espejo, también en vivo.
	ctrl._on_layout_changed(Protocol.LAYOUT_JOYSTICK_AB, {"a": "Patear"})
	var pad := ctrl._active_layout as JoystickAB
	check(pad != null and pad.left_handed, "zurdo: joystick + A/B en espejo")
	check(not ctrl._backdrop.show_watermark, "joystick + A/B: sin mascota de fondo tapando botones")
	ctrl._settings_panel._lefty.pressed.emit()
	check(not ctrl.settings.lefty and not pad.left_handed, "diestro en vivo: joystick + A/B vuelve")
	ctrl._settings_panel._lefty.pressed.emit()
	ctrl._on_layout_changed(Protocol.LAYOUT_ONE_BUTTON, {"label": "A"})
	btn = ctrl._active_layout as BigButton
	btn.size = Vector2(2000, 900)
	ctrl._settings_panel._pick_size(PhoneSettings.SIZE_LARGE)
	check(btn.control_scale > 1.0, "tamaño grande se aplica al control en pantalla")
	check(ctrl._instruction.visible and ctrl._instruction.text == ControllerMain.LAYOUT_HINTS[Protocol.LAYOUT_ONE_BUTTON],
		"instrucción del control arriba")

	# Modo desarrollador: 5 toques seguidos en el logo.
	for i in 4:
		ctrl._on_logo_tapped()
	check(not ctrl.settings.dev_mode, "4 toques no alcanzan")
	ctrl._on_logo_tapped()
	check(ctrl.settings.dev_mode and ctrl._latency.visible, "5 toques en el logo: se ve la latencia")
	ctrl._update_latency(86)
	check(ctrl._latency.text == "86 ms", "modo desarrollador: ms")
	ctrl._settings_panel._sound.pressed.emit()
	ctrl._settings_panel._vibration.pressed.emit()
	check(Sfx.muted and not Haptics.enabled, "sonido y vibración se apagan desde Ajustes")
	ctrl.queue_free()
	await process_frame

	# Otra vez la app: los ajustes quedaron guardados.
	Sfx.muted = false
	Haptics.enabled = true
	var again := ControllerMain.new()
	again.settings_path = path
	root.add_child(again)
	await process_frame
	check(again.settings.lefty and again.settings.control_size == PhoneSettings.SIZE_LARGE and again.settings.dev_mode,
		"zurdo, tamaño y modo desarrollador persisten")
	check(Sfx.muted and not Haptics.enabled, "sonido y vibración persisten")
	check(again._latency.visible, "al abrir de nuevo, sigue en modo desarrollador")

	# "Salir": un toque corto no sale (avisa); mantener 1 s sí.
	again._on_joined({"name": "Juli"})
	check(again._play_screen.visible, "unido")
	again._leave.begin_hold()
	again._leave.advance(0.3)
	again._leave.end_hold()
	check(again._play_screen.visible and not again._join_screen.visible, "toque corto en Salir: no sale")
	check(again._toast.visible and again._toast_label.text.contains("Mantené"), "toque corto: avisa que hay que mantener")
	again._leave.begin_hold()
	again._leave.advance(0.6)
	check(again._play_screen.visible, "a mitad de camino todavía no sale")
	again._leave.advance(0.5)
	check(not again._play_screen.visible and again._join_screen.visible, "mantener 1 s: sale")
	again.queue_free()
	await process_frame

	# Un archivo roto o editado a mano no rompe nada.
	var cfg := ConfigFile.new()
	cfg.set_value("controller", "lefty", "sí")
	cfg.set_value("controller", "control_size", 99)
	cfg.set_value("controller", "dev_mode", 1)
	cfg.save(path)
	var loaded := PhoneSettings.new()
	loaded.load_from(path)
	check(not loaded.lefty and loaded.control_size == PhoneSettings.SIZE_LARGE and not loaded.dev_mode, "valores inválidos: por defecto o recortados")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	Sfx.muted = was_muted
	Haptics.enabled = was_vibrating


## Celular: instrucción del juego (la de la TV si viene, recortada), la
## mascota que reacciona a cómo te va y fondo legible con cualquier color.
func test_controller_instruction_and_mood() -> void:
	check(ControllerMain.instruction_for(Protocol.LAYOUT_JOYSTICK, {}) == ControllerMain.LAYOUT_HINTS[Protocol.LAYOUT_JOYSTICK], "sin hint: la del control")
	check(ControllerMain.instruction_for(Protocol.LAYOUT_JOYSTICK, {"hint": "  Mové para juntar estrellas "}) == "Mové para juntar estrellas", "hint de la TV")
	check(ControllerMain.instruction_for(Protocol.LAYOUT_ONE_BUTTON, {"hint": 42}) == ControllerMain.LAYOUT_HINTS[Protocol.LAYOUT_ONE_BUTTON], "hint que no es texto: se ignora")
	check(ControllerMain.instruction_for(Protocol.LAYOUT_ONE_BUTTON, {"hint": "x".repeat(500)}).length() == ControllerMain.HINT_MAX_LENGTH, "hint largo: se recorta")
	check(ControllerMain.instruction_for(Protocol.LAYOUT_WAIT, {}) == "", "esperando: sin instrucción")
	var base := {"round": 1, "total_rounds": 3, "place": 2, "points": 70, "total": 170, "rank": 2, "players": 4, "final": false}
	check(ControllerMain.mood_for_standing(base) == PlayerAvatar.Mood.NORMAL, "en el medio: normal")
	base.rank = 1
	check(ControllerMain.mood_for_standing(base) == PlayerAvatar.Mood.HAPPY, "vas ganando: feliz")
	base.rank = 4
	base.place = 4
	check(ControllerMain.mood_for_standing(base) == PlayerAvatar.Mood.SAD, "vas último: triste")
	for col: Color in Protocol.MASCOT_COLORS:
		var ink := PhoneBackdrop.ink_for(col)
		for bg: Color in PhoneBackdrop.gradient(col):
			var hi := maxf(ink.get_luminance(), bg.get_luminance())
			var lo := minf(ink.get_luminance(), bg.get_luminance())
			check(hi - lo > 0.35, "texto legible sobre el fondo del color %s" % col.to_html(false))


## Argumentos de nivel superior de una llamada (desde después del "(").
func _call_args(src: String, from: int) -> Array[String]:
	var args: Array[String] = []
	var depth := 0
	var cur := ""
	for i in range(from, src.length()):
		var ch := src[i]
		if ch in "([{":
			depth += 1
		elif ch in ")]}":
			if depth == 0:
				args.append(cur.strip_edges())
				return args
			depth -= 1
		elif ch == "," and depth == 0:
			args.append(cur.strip_edges())
			cur = ""
			continue
		cur += ch
	return args


# --- Memoria de colores ------------------------------------------------------

const MEMORY := preload("res://host/minigames/memory/memory.gd")


## Joystick -> botón: zona muerta, umbral, diagonales y flanco (centro ->
## dirección cuenta UNA vez; mantener o temblar sin volver al centro, no).
func test_memory_press_edges() -> void:
	check(MEMORY.direction_of(Vector2.ZERO) == MEMORY.CENTER, "quieto = centro")
	check(MEMORY.direction_of(Vector2(0, -0.2)) == MEMORY.CENTER, "dentro de la zona muerta = centro")
	check(MEMORY.direction_of(Vector2(0, -0.5)) == MEMORY.NO_DIRECTION, "entre zona muerta y umbral no cuenta")
	check(MEMORY.direction_of(Vector2(0, -1)) == MEMORY.UP, "arriba = estrella")
	check(MEMORY.direction_of(Vector2(1, 0)) == MEMORY.RIGHT, "derecha = corazón")
	check(MEMORY.direction_of(Vector2(0, 1)) == MEMORY.DOWN, "abajo = rombo")
	check(MEMORY.direction_of(Vector2(-1, 0)) == MEMORY.LEFT, "izquierda = círculo")
	check(MEMORY.direction_of(Vector2(0.3, -0.9)) == MEMORY.UP, "casi arriba (18°) cuenta como arriba")
	check(MEMORY.direction_of(Vector2(0.7, 0.7)) == MEMORY.NO_DIRECTION, "en diagonal no cuenta")
	check(MEMORY.direction_of(Vector2(NAN, 1)) == MEMORY.CENTER, "datos inválidos = centro")

	var game: Variant = _memory_game(1, 3)
	# Empuja durante la secuencia y lo mantiene al empezar su turno: no cuenta.
	var first: int = MEMORY.sequence_for_seed(3, 1)[0]
	_memory_axis(game, 1, Vector2.ZERO)
	_memory_axis(game, 1, MEMORY.DIRS[first])
	if not check_that(_memory_until_input(game), "llega el turno de repetir"):
		game.free()
		return
	for f in 10:
		_memory_axis(game, 1, MEMORY.DIRS[first])
		game.step(1.0 / 60.0)
	check(game._progress[1] == 0, "mantener desde antes del turno no cuenta")
	# Tiembla entre el umbral y la zona muerta: tampoco (no volvió al centro).
	_memory_axis(game, 1, MEMORY.DIRS[first] * 0.5)
	_memory_axis(game, 1, MEMORY.DIRS[first])
	check(game._progress[1] == 0, "temblar sin volver al centro no cuenta")
	_memory_axis(game, 1, Vector2(0.1, 0.1))
	_memory_axis(game, 1, MEMORY.DIRS[first])
	check(game._progress[1] == 1 and game.scores()[1] == 1, "centro -> dirección cuenta y completa la ronda 1")
	# Ronda 2: mantener la primera no cuenta como la segunda.
	check_that(_memory_until_input(game), "llega la ronda 2")
	var seq: Array[int] = game.sequence()
	_memory_axis(game, 1, Vector2.ZERO)
	for f in 10:
		_memory_axis(game, 1, MEMORY.DIRS[seq[0]])
	check(game._progress[1] == 1 and game.is_alive(1), "mantener apretado cuenta una sola vez (%d)" % game._progress[1])
	game.free()


## Quien se equivoca queda afuera y ya no juega; los demás siguen. Gana el
## último en pie y quien no repite a tiempo también queda afuera.
func test_memory_error_eliminates() -> void:
	var game: Variant = _memory_game(3, 5)
	var results: Array = []
	game.finished.connect(func(r: Dictionary) -> void: results.append(r))
	if not check_that(_memory_until_input(game), "llega el turno de repetir"):
		game.free()
		return
	var s: int = game.sequence()[0]
	_memory_press(game, 1, (s + 1) % 4)
	check(not game.is_alive(1), "equivocarse elimina")
	_memory_press(game, 2, s)
	_memory_press(game, 3, s)
	check(game.is_alive(2) and game.is_alive(3), "los que aciertan siguen")
	check(_memory_until_input(game) and game.sequence().size() == 2, "la secuencia crece en 1")
	_memory_press(game, 1, game.sequence()[0])
	check(game._progress[1] == 0, "un eliminado ya no juega")
	_memory_press(game, 2, (game.sequence()[0] + 2) % 4)
	for d: int in game.sequence():
		_memory_press(game, 3, d)
	_memory_run(game)
	check(results.size() == 1, "termina una sola vez al quedar uno en pie (%d)" % results.size())
	if results.size() == 1:
		check(results[0].winners == [3], "gana Tomi, el último en pie (%s)" % [results[0].winners])
		check(results[0].scores == {1: 0, 2: 1, 3: 2}, "puntos por rondas completadas (%s)" % [results[0].scores])
	game.free()
	# Sin mover el joystick: se le acaba el tiempo y queda afuera.
	game = _memory_game(1, 9)
	_memory_until_input(game)
	for f in ceili(MEMORY.input_time(1) * 60.0) + 2:
		game.step(1.0 / 60.0)
	check(not game.is_alive(1), "no repetir a tiempo elimina")
	game.free()


## Misma semilla, misma secuencia (la que arma el juego ronda a ronda) y
## cada ronda se muestra más rápido.
func test_memory_sequence_seed() -> void:
	var a: Array[int] = MEMORY.sequence_for_seed(42, 12)
	check(a == MEMORY.sequence_for_seed(42, 12), "misma semilla, misma secuencia")
	check(a != MEMORY.sequence_for_seed(43, 12), "otra semilla, otra secuencia")
	var long: Array[int] = MEMORY.sequence_for_seed(7, 300)
	var ok := true
	for i in long.size():
		ok = ok and long[i] >= 0 and long[i] < 4 and (i < 2 or not (long[i] == long[i - 1] and long[i] == long[i - 2]))
	check(ok, "símbolos válidos y nunca tres iguales seguidos")
	var game: Variant = _memory_game(1, 42)
	for r in 5:
		if not _memory_until_input(game):
			break
		for d: int in game.sequence():
			_memory_press(game, 1, d)
	check(game.sequence() == MEMORY.sequence_for_seed(42, 5), "el juego arma la secuencia de su semilla (%s)" % [game.sequence()])
	check(game.scores()[1] == 5 and game.is_alive(1), "repitió 5 rondas sin errores")
	check(MEMORY.step_time(1) > MEMORY.step_time(6) and MEMORY.step_time(6) > MEMORY.step_time(11), "cada ronda más rápida")
	check(is_equal_approx(MEMORY.step_time(40), MEMORY.STEP_FAST), "con tope de velocidad")
	game.free()


## Si los últimos se equivocan en la misma ronda, empatan (y ganan todos).
func test_memory_tie() -> void:
	var game: Variant = _memory_game(2, 11)
	var results: Array = []
	game.finished.connect(func(r: Dictionary) -> void: results.append(r))
	_memory_until_input(game)
	for pid in [1, 2]:
		_memory_press(game, pid, game.sequence()[0])
	_memory_until_input(game)
	for pid in [1, 2]:
		_memory_press(game, pid, (game.sequence()[0] + 1) % 4)
	_memory_run(game)
	check(results.size() == 1 and results[0].winners == [1, 2], "empate: ganan los dos")
	if results.size() == 1:
		check(results[0].scores == {1: 1, 2: 1}, "con las mismas rondas (%s)" % [results[0].scores])
	game.free()


## Tope de tiempo: gana quien completó más rondas (desempate por rondas).
func test_memory_time_limit() -> void:
	var game: Variant = _memory_game(2, 13)
	var results: Array = []
	game.finished.connect(func(r: Dictionary) -> void: results.append(r))
	_memory_until_input(game)
	for pid in [1, 2]:
		_memory_press(game, pid, game.sequence()[0])
	_memory_until_input(game)
	var seq: Array[int] = game.sequence()
	_memory_press(game, 1, seq[0])
	_memory_press(game, 1, seq[1])
	_memory_press(game, 2, seq[0])  # Sofi va por la mitad cuando se acaba el tiempo.
	game._play_t = MEMORY.TOTAL_TIME - 0.01
	game.step(1.0 / 60.0)
	check(game.time_left() <= 0.0, "llegó al tope de tiempo")
	_memory_run(game)
	check(results.size() == 1, "termina por tiempo")
	if results.size() == 1:
		check(results[0].winners == [1], "gana Pablo, que completó más rondas (%s)" % [results[0].winners])
		check(results[0].scores == {1: 2, 2: 1}, "puntos por rondas (%s)" % [results[0].scores])
		check("tiempo" in str(results[0].summary), "el resumen dice que fue por tiempo")
	game.free()


func _memory_game(n: int, seed_value: int) -> Variant:
	var game: Variant = MiniGameRegistry.create("memory")
	game.setup(_fake_players(n))
	game._rng.seed = seed_value
	return game


func _memory_axis(game: Variant, pid: int, axis: Vector2) -> void:
	game.on_input(pid, {"seq": 0, "axis": axis, "btn": 0})


## Una pulsación completa: centro, dirección y de vuelta al centro.
func _memory_press(game: Variant, pid: int, dir: int) -> void:
	_memory_axis(game, pid, Vector2.ZERO)
	_memory_axis(game, pid, MEMORY.DIRS[dir])
	_memory_axis(game, pid, Vector2.ZERO)


## Avanza hasta el próximo turno de repetir (false si termina antes).
func _memory_until_input(game: Variant) -> bool:
	if game.accepting_input():
		game.step(1.0 / 60.0)  # Sale del turno actual si ya estaba.
	for i in 60 * 30:
		if game.is_finished():
			return false
		if game.accepting_input():
			return true
		game.step(1.0 / 60.0)
	return false


## Avanza hasta que termina (tope de seguridad).
func _memory_run(game: Variant) -> void:
	for i in 60 * 120:
		if game.is_finished():
			return
		game.step(1.0 / 60.0)
# --- Bots (ADR 0010) ------------------------------------------------------------

## Cada bot juega su juego entero (en todas las dificultades), sin errores,
## termina, y NUNCA genera una entrada fuera de rango (eje ≤ 1, solo
## botones conocidos): son entradas de celular, nada más.
func test_bots_play_every_game() -> void:
	for info in MiniGameRegistry.all_info():
		for d in Bot.PROFILES.size():
			var players := BotMatch.bot_players(int(info.max_players), d)
			var r := BotMatch.run(root, info.id, players, 400.0, 0, Callable(), true)
			check(r.finished, "%s (%s): los bots terminan el juego (%.0f s)" % [info.id, Bot.difficulty_name(d), r.seconds])
			check(r.invalid_outputs == 0, "%s: %d entradas fuera de rango" % [info.id, r.invalid_outputs])
			var bad := 0
			for e: Array in r.raw_log:
				var axis: Vector2 = e[1]
				if not (is_finite(axis.x) and is_finite(axis.y)) or axis.length() > 1.0001 or (int(e[2]) & ~Protocol.BTN_MASK) != 0:
					bad += 1
			check(not r.raw_log.is_empty() and bad == 0, "%s: %d de %d entradas crudas fuera de rango" % [info.id, bad, r.raw_log.size()])
			check((r.result.get("scores", {}) as Dictionary).size() == players.size(), "%s: puntaje para cada bot" % info.id)
	await process_frame


## Un juego sin bot propio (ej. uno nuevo) igual se juega: el Bot base manda
## entradas suaves y válidas según el control.
func test_bot_fallback_for_new_games() -> void:
	var p := BotMatch.bot_players(1)[0]
	for layout in Protocol.LAYOUTS:
		var bot := BotDriver.create_bot("juego_nuevo", p, {"id": "juego_nuevo", "layout": layout}, 5)
		check(bot.get_script() == Bot, "sin bot propio usa el Bot base")
		var moved := false
		var pressed := false
		var ok := true
		for i in 600:
			var out := bot.tick({}, 1.0 / 60.0)
			ok = ok and Bot.is_valid_output(out)
			moved = moved or (out.axis as Vector2).length() > 0.1
			pressed = pressed or out.btn != 0
		check(ok, "%s: entradas válidas" % layout)
		check(moved == (layout in [Protocol.LAYOUT_JOYSTICK, Protocol.LAYOUT_SLIDER_H]), "%s: mueve el eje solo si el control lo tiene" % layout)
		check(pressed == (layout == Protocol.LAYOUT_ONE_BUTTON), "%s: aprieta solo si el control es un botón" % layout)
	check(not Bot.is_valid_output({"axis": Vector2(2, 0), "btn": 0}), "detecta eje fuera de rango")
	check(not Bot.is_valid_output({"axis": Vector2.ZERO, "btn": 4}), "detecta botón desconocido")
	check(not Bot.is_valid_output({"axis": Vector2(NAN, 0), "btn": 0}), "detecta NaN")


## Los bots juegan "bien" según su dificultad (umbrales holgados: hay azar).
func test_bot_skill() -> void:
	var hard := Bot.Difficulty.HARD
	# Arena: el difícil, solo, junta estrellas.
	var r := BotMatch.run(root, "arena", BotMatch.bot_players(1, hard))
	check(int(r.result.scores[1]) >= 30, "Arena: el bot difícil junta estrellas (%d)" % int(r.result.scores[1]))
	# Ping Pong: los difíciles devuelven casi todas las pelotas que les llegan.
	var taps := {1: 0, 2: 0}
	var players := BotMatch.bot_players(2, hard)
	var game: Variant = MiniGameRegistry.create("pingpong")
	game.process_mode = Node.PROCESS_MODE_DISABLED
	root.add_child(game)
	game.setup(players)
	game.feedback.connect(func(pid: int, kind: String) -> void:
		if kind == "tap":
			taps[pid] += 1)
	var driver := BotDriver.new()
	driver.auto_step = false
	driver.start(game, players)
	var t := 0.0
	while not game.is_finished() and t < 400.0:
		driver.step(BotMatch.STEP)
		game.simulate_frame(BotMatch.STEP)
		t += BotMatch.STEP
	var points: int = game._score[1] + game._score[2]
	var returns: int = taps[1] + taps[2]
	check(returns >= 20 and float(returns) / (returns + points) >= 0.75,
		"Ping Pong: los difíciles devuelven pelotas (%d devoluciones, %d puntos)" % [returns, points])
	driver.free()
	game.free()
	# Carrera: el normal llega a la meta en un tiempo humano.
	r = BotMatch.run(root, "tap_race", BotMatch.bot_players(1))
	check(r.finished and r.seconds < 12.0, "Carrera: el bot normal llega a la meta (%.1f s)" % r.seconds)
	# Reloj exacto: el difícil frena cerca de 10.00 (promedio de 3).
	var total := 0
	for i in 3:
		total += int(BotMatch.run(root, "stop_clock", BotMatch.bot_players(1, hard)).result.scores[1])
	check(total / 3 >= 800, "Reloj: el bot difícil frena cerca de 10 s (%d de 1000)" % (total / 3))
	# Pintar: el difícil, solo, pinta casi todo.
	r = BotMatch.run(root, "paint", BotMatch.bot_players(1, hard))
	check(int(r.result.scores[1]) >= 120, "Pintar: el bot difícil pinta el piso (%d baldosas)" % int(r.result.scores[1]))
	# Esquivar y Empujones: contra alguien que no toca el control, gana el bot.
	for id in ["dodge", "sumo"]:
		var wins := 0
		for i in 3:
			var vs := BotMatch.bot_players(2, hard)
			vs[0].bot = false  # 1P: una persona que no toca nada.
			r = BotMatch.run(root, id, vs, 180.0, 0, func(_g: MiniGame, _pid: int, _t: float) -> Dictionary: return {})
			if r.result.get("winners", []) == [2]:
				wins += 1
		check(wins >= 2, "%s: el bot difícil le gana a un jugador quieto (%d de 3)" % [id, wins])
	await process_frame


## El driver solo maneja a los bots: la entrada de una persona no se toca, y
## la del bot llega por on_input ya validada (como la de la red).
func test_bot_driver_only_moves_bots() -> void:
	var players := BotMatch.bot_players(2)
	players[0].bot = false
	var game: Variant = MiniGameRegistry.create("arena")
	game.process_mode = Node.PROCESS_MODE_DISABLED
	root.add_child(game)
	game.setup(players)
	var driver := BotDriver.new()
	driver.auto_step = false
	driver.seed_value = 11  # Reproducible: sin semilla, el último cuadro podía caer justo al frenar.
	driver.start(game, players)
	check(driver.bots.size() == 1 and driver.bots[0].player_id == 2, "un bot, solo para el jugador bot")
	var human_moved := false
	var bot_max := 0.0
	for i in 60:
		driver.step(BotMatch.STEP)
		game.simulate_frame(BotMatch.STEP)
		human_moved = human_moved or game._axis[1] != Vector2.ZERO
		bot_max = maxf(bot_max, (game._axis[2] as Vector2).length())
	check(not human_moved, "la persona no se mueve sola")
	check(bot_max > 0.2, "el bot mueve su joystick (%.2f)" % bot_max)
	driver.stop()
	check(driver.bots.is_empty() and driver.game == null, "stop suelta el juego")
	driver.free()
	game.free()


## Lobby con bots: sumar desde la tarjeta del lugar (menú con el D-pad),
## cambiar la dificultad, quitarlo; las personas tienen prioridad (lugar y
## color); los bots no reciben nada por la red.
func test_host_bots_lobby() -> void:
	var port := TEST_PORT + 60
	var host := HostMain.new()
	host.server_port = port
	host.announce = false
	host.transition_seconds = 0.0
	root.add_child(host)
	await process_frame
	var c1 := _client()
	c1.join("127.0.0.1", port, host.server.room_code, "Pablo")
	await _until(func() -> bool: return host.server.get_players().size() == 1)
	var lobby := host._lobby
	check(lobby.player_count == 2 and lobby._seats[1].selectable and not lobby._seats[0].selectable,
		"el lugar libre se puede elegir; el de una persona no")
	# OK sobre el lugar 2P -> menú -> "Difícil".
	var accept := InputEventAction.new()
	accept.action = "ui_accept"
	accept.pressed = true
	lobby._seats[1]._gui_input(accept)
	check(lobby.is_bot_menu_open(), "OK en un lugar libre abre el menú del bot")
	lobby._bot_menu._choices[Bot.Difficulty.HARD].pressed.emit()
	await process_frame
	var players := host.server.get_players()
	if not check_that(players.size() == 2, "se suma un bot (%d jugadores)" % players.size()):
		host.queue_free()
		await _free_clients()
		return
	check(players[1].bot and players[1].slot == 1, "el bot va en 2P")
	check(players[1].name == "Bot Robi" and players[1].style == PlayerAvatar.STYLE_ROBOT and players[1].difficulty == Bot.Difficulty.HARD,
		"bot con nombre, mascota robot y la dificultad elegida (%s)" % players[1])
	check(not players[0].bot, "la persona no es bot")
	check(host.server.get_human_count() == 1, "cuenta solo personas")
	check(lobby.can_start(), "1 persona + 1 bot: se puede empezar")
	check(lobby._seats[1].is_bot and lobby._seats[1]._status.text == "Bot · Difícil", "la tarjeta dice que es un bot")
	check(not lobby.is_bot_menu_open() and lobby._seats[1].has_focus(), "al elegir se cierra y el foco vuelve al lugar")
	# Cambiar la dificultad y quitarlo desde el mismo menú.
	lobby.open_bot_menu(1)
	check(lobby._bot_menu._remove.visible, "con bot, el menú ofrece quitarlo")
	lobby._bot_menu._choices[Bot.Difficulty.EASY].pressed.emit()
	check(host.server.get_players()[1].difficulty == Bot.Difficulty.EASY, "cambia la dificultad")
	lobby.open_bot_menu(1)
	lobby._bot_menu._remove.pressed.emit()
	check(host.server.get_players().size() == 1, "quitar bot libera el lugar")
	lobby.open_bot_menu(1)
	var cancel := InputEventAction.new()
	cancel.action = "ui_cancel"
	cancel.pressed = true
	lobby._bot_menu._unhandled_input(cancel)
	check(not lobby.is_bot_menu_open() and host.server.get_players().size() == 1, "Atrás cierra el menú sin cambiar nada")

	# Personas primero: sala llena (1 persona + 1 bot de 2) y entra otra.
	check(host.add_bot(Bot.Difficulty.NORMAL), "suma un bot")
	var bot_color: int = host.server.get_players()[1].color_index
	await _frames(10)
	check(c1.player_info.has("taken") and not bot_color in (c1.player_info.taken as Array),
		"el color de un bot no figura como ocupado en el celular (%s)" % [c1.player_info.get("taken")])
	var c2 := _client()
	var rejected: Array = []
	c2.rejected.connect(func(r: String) -> void: rejected.append(r))
	c2.join("127.0.0.1", port, host.server.room_code, "Sofi", {"color": bot_color})
	await _until(func() -> bool: return host.server.get_human_count() == 2)
	players = host.server.get_players()
	check(rejected.is_empty() and players.size() == 2 and not players[0].bot and not players[1].bot,
		"una persona reemplaza al bot si no hay lugar (%s)" % [rejected])
	check(players[1].name == "Sofi" and players[1].color_index == bot_color, "y se queda con el color que pidió")
	# Un bot nunca le quita el color a una persona: si una persona lo pide, el bot se cambia.
	host._lobby._stepper.set_value(4)
	check(host.add_bot(), "suma un bot en 3P")
	var bot3: Dictionary = host.server.get_players()[2]
	var colors := {}
	for p in host.server.get_players():
		colors[p.color_index] = true
	check(bot3.bot and colors.size() == 3, "colores únicos con bots")
	var c3 := _client()
	c3.join("127.0.0.1", port, host.server.room_code, "Tomi", {"color": bot3.color_index})
	await _until(func() -> bool: return host.server.get_human_count() == 3)
	players = host.server.get_players()
	check(players.size() == 4 and players[3].name == "Tomi" and players[3].color_index == bot3.color_index,
		"Tomi entra con el color que tenía el bot")
	check(players[2].bot and players[2].color_index != bot3.color_index, "el bot se cambió de color")

	# Durante la competencia no se suman ni se quitan bots.
	check(host.start_tournament(["tap_race"] as Array[String]), "arranca con 3 personas + 1 bot")
	check(not host.add_bot() and not host.remove_bot(3), "no se tocan los bots en plena competencia")
	host.queue_free()
	await _free_clients()


## Competencia completa: 1 persona (simulada) + 3 bots de las 3 dificultades,
## todos los juegos que admiten 4, hasta el podio. Los juegos avanzan a mano
## (pasos de 1/60 s) para que el test sea rápido.
func test_competition_one_human_three_bots() -> void:
	var port := TEST_PORT + 61
	var host := HostMain.new()
	host.server_port = port
	host.announce = false
	host.transition_seconds = 0.0
	root.add_child(host)
	await process_frame
	var c1 := _client()
	c1.join("127.0.0.1", port, host.server.room_code, "Pablo")
	await _until(func() -> bool: return host.server.get_players().size() == 1)
	host._lobby._stepper.set_value(4)
	for d in [Bot.Difficulty.EASY, Bot.Difficulty.NORMAL, Bot.Difficulty.HARD]:
		check(host.add_bot(d), "suma bot %s" % Bot.difficulty_name(d))
	check(host._lobby.can_start(), "1 persona + 3 bots: lista para empezar")
	var ids := host._lobby.selected_game_ids()
	if not check_that(host.start_tournament(ids), "arranca la competencia"):
		host.queue_free()
		await _free_clients()
		return
	host.bots.auto_step = false
	var rounds := 0
	var bot_rows_ok := true
	var badges := 0
	var seq := 0
	while host.phase == Protocol.PHASE_PLAYING and rounds < 20:
		host.skip_intro()
		var game := host._game
		if not check_that(is_instance_valid(game), "arranca el juego %d" % (rounds + 1)):
			break
		check(host.bots.bots.size() == 3, "%s: 3 bots jugando" % host.tournament.current_game_id)
		var t := 0.0
		while is_instance_valid(game) and not game.is_finished() and t < 200.0:
			# La persona: mueve el joystick en círculos y toca el botón (como un celular).
			seq += 1
			var input := Protocol.parse_input({"seq": seq, "axis": [cos(t), sin(t * 1.3)], "btn": int(t * 6.0) % 2})
			host._on_input(1, input)
			host.bots.step(BotMatch.STEP)
			game.simulate_frame(BotMatch.STEP)
			t += BotMatch.STEP
		rounds += 1
		if not check_that(host._summary.visible, "resumen de la ronda %d (%.0f s)" % [rounds, t]):
			break
		var summary: Dictionary = host.tournament.history.back()
		for row: Dictionary in summary.rows:
			bot_rows_ok = bot_rows_ok and row.bot == (row.id != 1)
		for col in host._summary._columns.get_children():
			badges += col.find_children("*", "BotBadge", true, false).size()
		host._summary._on_continue()
	check(host._final.visible and host.phase == Protocol.PHASE_RESULTS, "termina en el podio")
	var playable := 0
	for id in ids:
		if MiniGameRegistry.can_play(MiniGameRegistry.info(id), 4):
			playable += 1
	check(rounds == playable and rounds >= 6, "se jugaron todos los juegos para 4 (%d de %d)" % [rounds, playable])
	check(bot_rows_ok, "el resumen marca quiénes son bots")
	check(badges >= 3, "placa BOT en el resumen (%d)" % badges)
	var standings := host.tournament.standings()
	check(standings.size() == 4 and int(standings[0].total) > 0, "tabla final con los 4")
	check(host.bots.bots.is_empty(), "sin juego, los bots no juegan")
	host.queue_free()
	await _free_clients()


## Pausa: los bots se congelan con el juego (no "juegan solos" con el menú abierto).
func test_bots_freeze_on_pause() -> void:
	var port := TEST_PORT + 62
	var host := HostMain.new()
	host.server_port = port
	host.announce = false
	host.transition_seconds = 0.0
	root.add_child(host)
	await process_frame
	var c1 := _client()
	c1.join("127.0.0.1", port, host.server.room_code, "Pablo")
	await _until(func() -> bool: return host.server.get_players().size() == 1)
	host.add_bot(Bot.Difficulty.HARD)
	host.start_tournament(["arena"] as Array[String])
	host.skip_intro()
	await _physics_frames(30)
	var game: Variant = host._game
	check((game._axis[2] as Vector2).length() > 0.1, "el bot se mueve durante el juego")
	var cancel := InputEventAction.new()
	cancel.action = "ui_cancel"
	cancel.pressed = true
	host._unhandled_input(cancel)
	var before: Vector2 = game._pos[2]
	await _physics_frames(20)
	check(game._pos[2] == before, "en pausa el bot no se mueve")
	host._unhandled_input(cancel)
	await _physics_frames(20)
	check(game._pos[2] != before, "al seguir, vuelve a jugar")
	host.queue_free()
	await _free_clients()


## Tarjeta del lugar con un bot: placa BOT, dificultad y se puede elegir.
func test_seat_card_bot() -> void:
	var seat := SeatCard.new(2)
	root.add_child(seat)
	seat.show_player({"id": 3, "slot": 2, "name": "Bot Robi", "connected": true, "color": Protocol.player_color(2),
		"style": PlayerAvatar.STYLE_ROBOT, "bot": true, "difficulty": Bot.Difficulty.EASY}, false)
	check(seat.is_bot and seat._status.text == "Bot · Fácil", "muestra que es un bot y su dificultad")
	seat.selectable = true
	check(seat.focus_mode == Control.FOCUS_ALL, "elegible con el D-pad")
	seat.show_player({}, false)
	seat.grab_focus()
	check(seat._name.text == "Sumar bot", "lugar libre con foco: dice qué hace OK")
	seat.selectable = false
	check(seat.focus_mode == Control.FOCUS_NONE, "una persona: no se elige")
	seat.queue_free()
	await process_frame


func _physics_frames(n: int) -> void:
	for i in n:
		await physics_frame
# --- Layout joystick_ab (joystick + A y B, ver docs/adr/0014) -------------------

func test_parse_input_button_b() -> void:
	var r := Protocol.parse_input({"seq": 1, "axis": [0, 0], "btn": Protocol.BTN_B})
	check(r.btn == Protocol.BTN_B, "B solo")
	r = Protocol.parse_input({"seq": 2, "axis": [0.5, 0], "btn": Protocol.BTN_A | Protocol.BTN_B})
	check(r.btn == Protocol.BTN_A | Protocol.BTN_B and r.axis == Vector2(0.5, 0), "A y B a la vez, con el joystick movido")
	r = Protocol.parse_input(Protocol.decode(Protocol.encode(Protocol.T_INPUT, {"seq": 3, "axis": [0, 0], "btn": 2.0})))
	check(not r.is_empty() and r.btn == Protocol.BTN_B, "B tal como llega por la red (float)")
	r = Protocol.parse_input({"seq": 4, "axis": [0, 0], "btn": 4 | Protocol.BTN_B})
	check(r.btn == Protocol.BTN_B, "bits desconocidos (C, D…) se descartan")


func test_joystick_ab_layout_valid() -> void:
	check(Protocol.LAYOUT_JOYSTICK_AB in Protocol.LAYOUTS, "joystick_ab está en LAYOUTS")
	check(Protocol.VERSION >= 2, "layout nuevo con VERSION nueva (un control v1 no lo sabe dibujar)")
	check(GameCard.CONTROL_NAMES.has(Protocol.LAYOUT_JOYSTICK_AB), "nombre del control en la tarjeta del lobby")
	var pad := JoystickAB.new()
	pad.size = Vector2(2340, 920)
	for button in [Protocol.BTN_A, Protocol.BTN_B]:
		check(pad.button_radius(button) * 2.0 >= 128.0, "botón %d ≥ 128 px" % button)
	# Celular chico y angosto: los botones no bajan de 128 px.
	pad.size = Vector2(1280, 560)
	for button in [Protocol.BTN_A, Protocol.BTN_B]:
		check(pad.button_radius(button) * 2.0 >= 128.0, "celular chico: botón %d ≥ 128 px" % button)
	var gap := pad.button_center(Protocol.BTN_A).distance_to(pad.button_center(Protocol.BTN_B))
	check(gap > pad.button_radius(Protocol.BTN_A) + pad.button_radius(Protocol.BTN_B), "A y B no se pisan")
	pad.free()


## Dos (y tres) dedos a la vez: caminar con el joystick y apretar A y B.
func test_joystick_ab_multitouch() -> void:
	var pad := JoystickAB.new()
	root.add_child(pad)
	pad.size = Vector2(2340, 920)
	await process_frame
	var stick := pad.stick_rect().get_center()
	var a := pad.button_center(Protocol.BTN_A)
	var b := pad.button_center(Protocol.BTN_B)
	check(pad.part_at(stick) == pad._stick and pad.part_at(a) == pad._a and pad.part_at(b) == pad._b, "cada zona va a su pieza")
	pad._gui_input(_touch(0, stick, true))
	pad._gui_input(_drag(0, stick + Vector2(100, 0)))
	check(pad.value.x > 0.5 and pad.buttons == 0, "dedo 1: joystick a la derecha (%s)" % pad.value)
	pad._gui_input(_touch(1, a + Vector2(20, 10), true))
	check(pad.buttons == Protocol.BTN_A and pad.value.x > 0.5, "dedo 2 en A sin soltar el joystick")
	pad._gui_input(_drag(0, stick + Vector2(0, -100)))
	check(pad.value.y < -0.5 and pad.buttons == Protocol.BTN_A, "se mueve el joystick con A apretado")
	pad._gui_input(_touch(2, b, true))
	check(pad.buttons == Protocol.BTN_A | Protocol.BTN_B, "tercer dedo: A y B a la vez")
	pad._gui_input(_drag(1, stick))  # El dedo de A se arrastra hacia el joystick: sigue siendo A.
	check(pad.value.y < -0.5 and pad.buttons == Protocol.BTN_A | Protocol.BTN_B, "cada dedo sigue en su pieza")
	pad._gui_input(_touch(1, stick, false))
	check(pad.buttons == Protocol.BTN_B and pad.value != Vector2.ZERO, "suelta A: queda B y el joystick")
	pad._gui_input(_touch(3, stick + Vector2(-200, 0), true))
	check(pad.value.y < -0.5, "un segundo dedo en la zona del joystick no le roba el control")
	pad._gui_input(_touch(0, stick, false))
	check(pad.value == Vector2.ZERO and pad.buttons == Protocol.BTN_B, "suelta el joystick: vuelve al centro")
	pad._gui_input(_touch(2, b, false))
	pad._gui_input(_touch(3, stick, false))
	check(pad.value == Vector2.ZERO and pad.buttons == 0, "sin dedos: todo suelto")
	# La app pasa a segundo plano con dedos apoyados: se suelta todo.
	pad._gui_input(_touch(4, a, true))
	pad.propagate_notification(Control.NOTIFICATION_APPLICATION_FOCUS_OUT)
	check(pad.buttons == 0 and pad._routes.is_empty(), "al perder el foco no queda A apretado")
	pad.queue_free()
	await process_frame


func test_joystick_ab_left_handed() -> void:
	var pad := JoystickAB.new()
	root.add_child(pad)
	pad.size = Vector2(2340, 920)
	await process_frame
	var a_right := pad.button_center(Protocol.BTN_A)
	var b_right := pad.button_center(Protocol.BTN_B)
	var stick_right := pad.stick_rect()
	check(a_right.x > pad.size.x / 2.0 and stick_right.get_center().x < pad.size.x / 2.0, "diestro: joystick a la izquierda, botones a la derecha")
	pad._gui_input(_touch(0, a_right, true))
	check(pad.buttons == Protocol.BTN_A, "A apretado antes de cambiar")
	pad.left_handed = true
	check(pad.buttons == 0, "cambiar a zurdo suelta los dedos")
	var a_left := pad.button_center(Protocol.BTN_A)
	check(is_equal_approx(a_left.x, pad.size.x - a_right.x) and is_equal_approx(a_left.y, a_right.y), "zurdo: A en espejo")
	check(is_equal_approx(pad.button_center(Protocol.BTN_B).x, pad.size.x - b_right.x), "zurdo: B en espejo")
	check(pad.stick_rect().get_center().x > pad.size.x / 2.0 and is_equal_approx(pad.stick_rect().end.x, pad.size.x), "zurdo: joystick a la derecha")
	check(is_equal_approx(pad._stick.position.x, pad.stick_rect().position.x), "la pieza del joystick se mueve")
	var a_face: Vector2 = pad._a.position + pad._a.size / 2.0
	check(a_face.x < pad.size.x / 2.0, "la pieza de A se mueve a la izquierda")
	pad._gui_input(_touch(0, a_right, true))  # Donde antes estaba A ahora está el joystick.
	check(pad.buttons == 0 and pad._routes.get(0) == pad._stick, "el mismo toque ahora es joystick")
	pad._gui_input(_touch(1, a_left, true))
	check(pad.buttons == Protocol.BTN_A, "A del lado izquierdo")
	pad.queue_free()
	await process_frame


func test_minigame_track_buttons() -> void:
	var game := MiniGame.new()
	check(game.track_buttons(1, {"btn": Protocol.BTN_A}) == Protocol.BTN_A, "flanco de subida de A")
	check(game.track_buttons(1, {"btn": Protocol.BTN_A}) == 0, "A sostenido no vuelve a disparar")
	check(game.track_buttons(1, {"btn": Protocol.BTN_A | Protocol.BTN_B}) == Protocol.BTN_B, "B se suma con A apretado")
	check(game.pressed_a(1) and game.pressed_b(1) and not game.pressed_b(2), "estado por jugador")
	check(game.track_buttons(1, {"btn": 255}) == 0, "bits desconocidos se descartan")
	game.track_buttons(1, {})
	check(not game.pressed_a(1) and not game.pressed_b(1), "sin btn = todo suelto")
	game.free()


## Red: la TV manda joystick_ab (con textos), el celular manda A y B, y un
## control v1 (que no conoce el layout) es rechazado con "bad_version".
func test_joystick_ab_network() -> void:
	var port := TEST_PORT + 14  # 14: el número del ADR (evita choques con otros tests).
	var server := HostServer.new()
	root.add_child(server)
	check(server.start(port, "127.0.0.1") == OK, "el servidor abre el puerto")
	var inputs: Array = []
	server.input_received.connect(func(_pid: int, i: Dictionary) -> void: inputs.append(i))
	var c := _client()
	var layouts: Array = []
	c.layout_changed.connect(func(l: String, d: Dictionary) -> void: layouts.append([l, d]))
	c.join("127.0.0.1", port, server.room_code, "Pablo")
	await _until(func() -> bool: return server.get_players().size() == 1)
	server.set_layout(Protocol.LAYOUT_JOYSTICK_AB, {"a": "Patear", "b": "Saltar"})
	await _until(func() -> bool: return layouts.any(func(x: Array) -> bool: return x[0] == Protocol.LAYOUT_JOYSTICK_AB))
	var got: Array = layouts.filter(func(x: Array) -> bool: return x[0] == Protocol.LAYOUT_JOYSTICK_AB)
	check(not got.is_empty() and got[0][1].get("a") == "Patear", "el control recibe joystick_ab con sus textos")
	c.send_input(Vector2(-0.4, 0.2), Protocol.BTN_A | Protocol.BTN_B)
	await _until(func() -> bool: return not inputs.is_empty())
	check(not inputs.is_empty() and inputs[0].btn == Protocol.BTN_A | Protocol.BTN_B, "la TV recibe A y B")
	check(not inputs.is_empty() and inputs[0].axis.is_equal_approx(Vector2(-0.4, 0.2)), "y el joystick")

	# Control v1: no conoce joystick_ab. Se lo rechaza al unirse (no queda
	# mirando "Mirá la TV" sin poder jugar).
	var ws := WebSocketPeer.new()
	ws.connect_to_url("ws://127.0.0.1:%d" % port)
	await _until(func() -> bool:
		ws.poll()
		return ws.get_ready_state() == WebSocketPeer.STATE_OPEN)
	ws.send_text(JSON.stringify({"v": 1, "type": "join", "room": server.room_code, "name": "Viejo"}))
	var reasons: Array = []
	await _until(func() -> bool:
		ws.poll()
		while ws.get_available_packet_count() > 0:
			var msg := Protocol.decode(ws.get_packet().get_string_from_utf8())
			if msg.get("type") == Protocol.T_REJECT:
				reasons.append(msg.get("reason"))
		return not reasons.is_empty() or ws.get_ready_state() == WebSocketPeer.STATE_CLOSED)
	check(reasons == [Protocol.R_BAD_VERSION] or ws.get_close_reason() == Protocol.R_BAD_VERSION,
		"control v1 rechazado con bad_version (%s)" % [reasons])
	check(server.get_players().size() == 1, "el control viejo no ocupa lugar")
	server.stop()
	server.queue_free()
	await _free_clients()


## El celular arma el layout nuevo; uno que no conoce (de una TV más nueva)
## no rompe: queda en la espera, sin control y sin mandar botones.
func test_controller_joystick_ab_and_unknown_layout() -> void:
	var ctrl := ControllerMain.new()
	root.add_child(ctrl)
	await process_frame
	ctrl._on_layout_changed(Protocol.LAYOUT_JOYSTICK_AB, {"a": "Patear con mucha fuerza", "b": 7})
	var pad := ctrl._active_layout as JoystickAB
	check_that(pad != null, "arma el JoystickAB")
	if pad:
		check(pad.label_a == "Patear con m" and pad.label_b == "7", "textos recortados y convertidos (%s / %s)" % [pad.label_a, pad.label_b])
		check(not ctrl._wait_view.visible, "sin pantalla de espera")
	ctrl._on_layout_changed("joystick_abcd", {"a": 1})
	check(ctrl._active_layout == null and ctrl._wait_view.visible, "layout desconocido: queda esperando sin romper")
	ctrl._on_layout_changed(Protocol.LAYOUT_JOYSTICK_AB, {})
	check(ctrl._active_layout is JoystickAB, "vuelve a armarlo")
	ctrl.queue_free()
	await process_frame


func _touch(index: int, pos: Vector2, pressed: bool) -> InputEventScreenTouch:
	var t := InputEventScreenTouch.new()
	t.index = index
	t.position = pos
	t.pressed = pressed
	return t


func _drag(index: int, pos: Vector2) -> InputEventScreenDrag:
	var d := InputEventScreenDrag.new()
	d.index = index
	d.position = pos
	return d


# --- Utilidades -----------------------------------------------------------------

func _fake_players(n: int) -> Array[Dictionary]:
	var names := ["Pablo", "Sofi", "Tomi", "Juli"]
	var out: Array[Dictionary] = []
	for i in n:
		out.append({"id": i + 1, "slot": i, "name": names[i], "color": Protocol.player_color(i), "connected": true})
	return out


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _free_clients() -> void:
	for c in root.get_children():
		if c is ControllerClient:
			c.queue_free()
	await process_frame


func _client() -> ControllerClient:
	var c := ControllerClient.new()
	root.add_child(c)
	return c


func _until(cond: Callable, timeout_ms: int = 3000) -> void:
	var start := Time.get_ticks_msec()
	while not cond.call() and Time.get_ticks_msec() - start < timeout_ms:
		await process_frame


# --- Karts de mascotas ---------------------------------------------------------------

const KARTS := preload("res://host/minigames/karts/karts.gd")


## Pista: entra entera en el pasto (con bordes), sin curvas más cerradas que
## su ancho, y ubicar un punto en la vuelta funciona.
func test_karts_track() -> void:
	var tr: Variant = KARTS.track()
	var edge: float = KARTS.HALF_WIDTH + KARTS.CURB
	check(tr.length > 3000.0 and tr.size() > 200, "pista cerrada de largo razonable (%.0f px)" % tr.length)
	check(tr.min_radius() > edge, "ninguna curva más cerrada que el ancho de la pista (%.0f)" % tr.min_radius())
	var inside := true
	for i in tr.size():
		for side: float in [-1.0, 1.0]:
			inside = inside and KARTS.FIELD.grow(-6.0).has_point(tr.pts[i] + tr.nrm[i] * side * (edge + 6.0))
	check(inside, "la pista entera (con bordes) entra en el pasto")
	check(KARTS.FIELD.position.y - UiTheme.BOARD_FRAME >= UiTheme.HUD_TOP + UiTheme.HUD_CLOCK_H,
		"el marco no queda debajo del marcador")
	var loc: Array = tr.locate(tr.point_at(500.0, 30.0), -1)
	check(absf(float(loc[1]) - 500.0) < 2.0 and absf(float(loc[2]) - 30.0) < 2.0, "ubica s y lateral (%s)" % [loc])
	check(is_equal_approx(tr.wrap_delta(tr.length - 10.0), -10.0) and is_equal_approx(tr.wrap_delta(-tr.length + 10.0), 10.0),
		"cruzar la línea no cuenta como una vuelta entera")
	var start: Vector2 = tr.frame_at(0.0)[1]
	check(start.x > 0.99, "la largada va hacia la derecha")
	for pad: Vector2 in KARTS.PADS:
		check(absf(pad.y) + KARTS.PAD_SIZE.y / 2.0 <= KARTS.HALF_WIDTH, "turbo dentro del asfalto")
	for puddle: Vector3 in KARTS.PUDDLES:
		check(absf(puddle.y) + puddle.z <= KARTS.HALF_WIDTH, "charco dentro del asfalto")


## Manejo: acelera solo hasta la velocidad máxima, frena con el joystick
## abajo, dobla con el X y en un charco patina (conserva el derrape).
func test_karts_driving() -> void:
	var k: Variant = KARTS.Kart.new()
	for i in 180:
		KARTS.drive(k, Vector2.ZERO, KARTS.FIXED_DT)
	check(absf(k.vel.length() - KARTS.MAX_SPEED) < 1.0 and absf(k.heading) < 0.0001, "acelera solo y va derecho (%s)" % k.vel)
	for i in 120:
		KARTS.drive(k, Vector2(0, 1), KARTS.FIXED_DT)
	check(absf(k.vel.length() - KARTS.MAX_SPEED * (1.0 - KARTS.BRAKE)) < 1.0, "abajo frena (%.0f)" % k.vel.length())
	check(KARTS.target_speed(Vector2(0, -1), false, false, false) > KARTS.MAX_SPEED, "arriba: turbo suave")
	check(KARTS.target_speed(Vector2.ZERO, true, false, false) > KARTS.target_speed(Vector2(0, -1), false, false, false),
		"el turbo del piso es más fuerte que el suave")
	var before: float = k.heading
	for i in 10:
		KARTS.drive(k, Vector2(1, 0), KARTS.FIXED_DT)
	check(k.heading > before, "el X a la derecha dobla a la derecha")
	# Derrape: la misma velocidad de costado dura más en un charco.
	var dry: Variant = KARTS.Kart.new()
	var wet: Variant = KARTS.Kart.new()
	for kk: Variant in [dry, wet]:
		kk.vel = Vector2(300, 200)
	wet.slip = KARTS.SLIP_SEC
	for i in 20:
		KARTS.drive(dry, Vector2.ZERO, KARTS.FIXED_DT)
		KARTS.drive(wet, Vector2.ZERO, KARTS.FIXED_DT)
	check(absf(wet.vel.y) > absf(dry.vel.y) * 4.0, "en el charco resbala (%.0f vs %.0f)" % [wet.vel.y, dry.vel.y])
	# Choque suave: se separan y el que embiste frena.
	var a: Variant = KARTS.Kart.new()
	var b: Variant = KARTS.Kart.new()
	a.vel = Vector2(300, 0)
	b.pos = Vector2(40, 0)
	check(KARTS.bump(a, b) > 0.0 and a.pos.distance_to(b.pos) >= KARTS.KART_RADIUS * 2.0 - 0.01, "choque: se separan")
	check(a.vel.x < 300.0 and b.vel.x > 0.0 and b.vel.x < 300.0, "choque suave: rebote parcial (%s, %s)" % [a.vel, b.vel])


## Pone un kart en la pista: `dist` recorrido (con vueltas), a velocidad
## máxima y mirando hacia adelante (o hacia atrás).
func _karts_put(game: Variant, pid: int, dist: float, lateral: float = 0.0, backwards: bool = false) -> void:
	var tr: Variant = KARTS.track()
	var s := fposmod(dist, tr.length)
	var k: Variant = game._karts[pid]
	var dir: Vector2 = tr.frame_at(s)[1]
	if backwards:
		dir = -dir
	k.pos = tr.point_at(s, lateral)
	k.heading = dir.angle()
	k.vel = dir * KARTS.MAX_SPEED
	var loc: Array = tr.locate(k.pos, -1)
	k.seg = loc[0]
	k.s = loc[1]
	k.lat = loc[2]
	k.dist = dist


func _karts_game(n: int, results: Array) -> Variant:
	var game: Variant = MiniGameRegistry.create("karts")
	root.add_child(game)
	game.set_physics_process(false)
	game.setup(_fake_players(n))
	game.finished.connect(func(r: Dictionary) -> void: results.append(r))
	return game


## Vueltas: nadie se mueve en la cuenta regresiva, cruzar la línea suma una
## vuelta, ir marcha atrás no, "¡Última vuelta!" y orden de llegada.
func test_karts_laps_and_finish_order() -> void:
	var results: Array = []
	var game: Variant = _karts_game(3, results)
	var L: float = KARTS.track().length
	var start: Vector2 = game._karts[1].pos
	game.on_input(1, {"seq": 0, "axis": Vector2(1, -1), "btn": 0})
	for i in 60:
		game.step_fixed()
	check(game._karts[1].pos == start, "quieto durante la cuenta regresiva")
	for i in 125:
		game.step_fixed()
	check(game._phase == KARTS.Phase.RACING and game._karts[1].pos != start, "después del ¡YA! acelera solo")
	game.on_input(1, {"seq": 1, "axis": Vector2.ZERO, "btn": 0})
	# Pablo cruza la línea: segunda vuelta.
	_karts_put(game, 1, L - 20.0)
	_karts_put(game, 2, 400.0)
	_karts_put(game, 3, 300.0, -40.0)
	for i in 10:
		game.step_fixed()
	check(game._karts[1].dist > L and KARTS.lap_of(game._karts[1].dist, L) == 2, "cruzar la línea suma una vuelta")
	check(game.places()[1] == 1, "Pablo va primero")
	# Sofi cruza la línea marcha atrás: no suma, resta.
	_karts_put(game, 2, 10.0, 40.0, true)
	for i in 20:
		game.step_fixed()
	check(game._karts[2].dist < 0.0 and KARTS.lap_of(game._karts[2].dist, L) == 1, "marcha atrás no cuenta vuelta (%.0f)" % game._karts[2].dist)
	# Pablo empieza la última vuelta.
	_karts_put(game, 1, 2.0 * L - 10.0)
	for i in 5:
		game.step_fixed()
	check(game._banner == "¡Última vuelta!" and game._banner_t > 0.0, "cartel de última vuelta")
	check(game._hud_center()[0] == "Vuelta 3/3", "el marcador muestra la vuelta del que va primero (%s)" % [game._hud_center()])
	# Llegada: Tomi, Pablo y Sofi (en ese orden, en fila por el mismo carril).
	_karts_put(game, 3, 3.0 * L - 15.0)
	_karts_put(game, 1, 3.0 * L - 80.0)
	_karts_put(game, 2, 3.0 * L - 145.0)
	for i in 40:
		game.step_fixed()
	check(game._finish_order == [3, 1, 2], "orden de llegada (%s)" % [game._finish_order])
	check(game._phase == KARTS.Phase.ENDING and results.is_empty(), "muestra ¡Meta! antes de terminar")
	for i in 200:
		game.step_fixed()
	check(results.size() == 1, "termina una sola vez (%d)" % results.size())
	if results.size() == 1:
		var r: Dictionary = results[0]
		check(r.winners == [3], "gana Tomi (%s)" % [r.winners])
		var entries: Array[Dictionary] = []
		for pid: int in r.scores:
			entries.append({"id": pid, "score": float(r.scores[pid]), "winner": pid in r.winners})
		var places := Tournament.rank(entries)
		check(places[3] == 1 and places[1] == 2 and places[2] == 3, "la competencia respeta el orden de llegada (%s)" % [places])
		check(float(r.scores[2]) >= KARTS.LAPS, "los que llegaron tienen las 3 vueltas (%s)" % [r.scores])
	game.finish({"winners": [1], "scores": {}})
	check(results.size() == 1, "finished se emite una sola vez")
	check(KARTS.get_info().score_label == "vueltas", "puntaje en vueltas")
	game.queue_free()
	await process_frame


## Goma elástica: el que va último recibe un turbo 20 % más largo; el
## primero, el normal. Los charcos hacen patinar.
func test_karts_rubber_band() -> void:
	check(is_equal_approx(KARTS.turbo_duration(true), KARTS.TURBO_SEC * 1.2), "último: turbo 20 % más largo")
	check(is_equal_approx(KARTS.turbo_duration(false), KARTS.TURBO_SEC), "los demás: turbo normal")
	var results: Array = []
	var game: Variant = _karts_game(2, results)
	var L: float = KARTS.track().length
	game._countdown = 0.0
	game._phase = KARTS.Phase.RACING
	var pad: Vector2 = KARTS.PADS[0]
	# Sofi (última) pisa el turbo.
	_karts_put(game, 1, pad.x * L + 900.0)
	_karts_put(game, 2, pad.x * L - 8.0, pad.y)
	game.step_fixed()
	check(is_equal_approx(game._karts[2].turbo, KARTS.TURBO_SEC * KARTS.RUBBER_BAND), "Sofi, última, turbo largo (%.2f)" % game._karts[2].turbo)
	# Pablo (primero) pisa otro turbo: el normal.
	var pad2: Vector2 = KARTS.PADS[1]
	_karts_put(game, 1, L + pad2.x * L - 8.0, pad2.y)
	game.step_fixed()
	check(is_equal_approx(game._karts[1].turbo, KARTS.TURBO_SEC), "Pablo, primero, turbo normal (%.2f)" % game._karts[1].turbo)
	# Con turbo va más rápido (sin pista: solo el manejo).
	var fast: Variant = KARTS.Kart.new()
	fast.vel = Vector2(KARTS.MAX_SPEED, 0)
	fast.turbo = KARTS.TURBO_SEC
	for i in 30:
		KARTS.drive(fast, Vector2.ZERO, KARTS.FIXED_DT)
	check(fast.vel.length() > KARTS.MAX_SPEED * 1.2, "con turbo supera la velocidad máxima (%.0f)" % fast.vel.length())
	# Charco: patina.
	var puddle: Vector3 = KARTS.PUDDLES[0]
	_karts_put(game, 1, 2.0 * L + puddle.x * L, puddle.y)
	game.step_fixed()
	check(game._karts[1].slip > 0.0, "el charco hace patinar")
# --- Carrera de obstáculos -----------------------------------------------------------

const HURDLES := preload("res://host/minigames/hurdles/hurdles.gd")


## Juego de Carrera de obstáculos con `n` jugadores y el recorrido dado,
## avanzado a mano (sin _physics_process) y ya pasada la cuenta regresiva.
func _hurdles_game(n: int, course: Array) -> Variant:
	var game: Variant = MiniGameRegistry.create("hurdles")  # Sin tipo: métodos propios del juego.
	root.add_child(game)
	game.set_physics_process(false)
	game.setup(_fake_players(n))
	game.use_course(course)
	_hurdles_run(game, HURDLES.COUNTDOWN_SEC + 0.1)
	return game


func _hurdles_run(game: Variant, seconds: float, jumper: int = 0) -> void:
	for i in roundi(seconds / HURDLES.DT):
		if jumper > 0:
			_hurdles_bot(game, jumper)
		game.step(HURDLES.DT)


## Jugador "que sabe": toca cuando el próximo obstáculo está por llegar.
func _hurdles_bot(game: Variant, pid: int) -> void:
	var r: Variant = game._runners[pid]
	var down := false
	for o: Dictionary in game._course:
		var d: float = float(o.x) - r.x
		if d < 90.0 and d > 40.0:
			down = true
	game.on_input(pid, {"seq": 0, "axis": Vector2.ZERO, "btn": Protocol.BTN_A if down else 0})


func _hurdles_press(game: Variant, pid: int, down: bool) -> void:
	game.on_input(pid, {"seq": 0, "axis": Vector2.ZERO, "btn": Protocol.BTN_A if down else 0})


## Salto: anticipación (se agacha antes de despegar), squash & stretch,
## tocar da el salto corto y mantener uno más alto pero con límite; en el aire
## no se vuelve a saltar.
func test_hurdles_jump() -> void:
	var game: Variant = _hurdles_game(1, [])
	var r: Variant = game._runners[1]
	check(r.grounded and r.speed > 0.0 and r.x > 0.0, "después del ¡YA! corre solo")
	_hurdles_press(game, 1, true)
	_hurdles_press(game, 1, false)  # Toque corto: suelta antes del próximo paso.
	game.step(HURDLES.DT)
	check(r.grounded and r.squash > 0.2, "anticipación: agachada antes de saltar (squash %.2f)" % r.squash)
	var peak := 0.0
	var stretched := false
	var air := 0
	for i in 120:
		game.step(HURDLES.DT)
		peak = maxf(peak, r.y)
		stretched = stretched or r.squash < -0.1
		if not r.grounded:
			air += 1
		elif air > 0:
			break
	check(stretched, "al despegar se estira")
	check(r.grounded and r.squash > 0.0, "al aterrizar se aplasta")
	check(peak > 70.0 and peak < 95.0, "salto corto ≈ 80 px (%.1f)" % peak)
	check(air * HURDLES.DT > 0.4 and air * HURDLES.DT < 0.65, "salto corto ≈ 0,5 s en el aire (%.2f)" % (air * HURDLES.DT))
	# Mantener apretado todo el salto: más alto, pero nunca más que el límite.
	_hurdles_press(game, 1, true)
	var high := 0.0
	for i in 60:
		game.step(HURDLES.DT)
		high = maxf(high, r.y)
	check(high > peak + 30.0, "mantener salta más alto (%.1f contra %.1f)" % [high, peak])
	check(high <= HURDLES.MAX_JUMP_HEIGHT, "el salto largo tiene límite (%.1f)" % high)
	# Un toque en el aire (bajando) no vuelve a saltar.
	_hurdles_press(game, 1, false)
	_hurdles_press(game, 1, true)
	_hurdles_press(game, 1, false)
	for i in 30:
		game.step(HURDLES.DT)
		if not r.grounded and r.vy < -200.0 and r.y > 30.0:
			break
	check(not r.grounded and r.vy < 0.0, "está bajando")
	_hurdles_press(game, 1, true)
	_hurdles_press(game, 1, false)
	game.step(HURDLES.DT)
	check(r.vy < 0.0, "en el aire no se vuelve a saltar")
	game.queue_free()
	await process_frame


## Fin por tiempo: a los 90 s (o 15 s después del primero) los que no
## llegaron quedan por distancia recorrida.
func test_karts_time_limit() -> void:
	var results: Array = []
	var game: Variant = _karts_game(3, results)
	var L: float = KARTS.track().length
	game._countdown = 0.0
	game._phase = KARTS.Phase.RACING
	game._elapsed = KARTS.TIME_LIMIT_SEC - 0.05
	_karts_put(game, 1, 1.5 * L)
	_karts_put(game, 2, 2.2 * L)
	_karts_put(game, 3, 0.4 * L)
	check(game._hud_center()[1] == "clock", "al final el marcador muestra el reloj")
	for i in 10:
		game.step_fixed()
	check(game._phase == KARTS.Phase.ENDING and game._end_text == "¡Tiempo!", "a los 90 s: ¡Tiempo!")
	for i in 200:
		game.step_fixed()
	check(results.size() == 1, "termina una sola vez")
	if results.size() == 1:
		var r: Dictionary = results[0]
		check(r.winners == [2], "gana el que más avanzó (%s)" % [r.winners])
		var s: Dictionary = r.scores
		check(float(s[2]) > float(s[1]) and float(s[1]) > float(s[3]), "por distancia (%s)" % [s])
		check(absf(float(s[2]) - 2.2) < 0.05 and float(s[2]) < KARTS.LAPS, "puntaje = vueltas recorridas (%s)" % [s])
	game.queue_free()
	# Llega uno: los demás tienen 15 s más.
	results.clear()
	var g2: Variant = _karts_game(2, results)
	g2._countdown = 0.0
	g2._phase = KARTS.Phase.RACING
	g2._elapsed = 30.0
	_karts_put(g2, 1, 3.0 * L - 10.0)
	_karts_put(g2, 2, 1.5 * L)
	for i in 5:
		g2.step_fixed()
	check(g2._karts[1].finished() and g2._phase == KARTS.Phase.RACING, "llegó uno: la carrera sigue")
	g2._elapsed = g2._first_finish + KARTS.FINISH_GRACE_SEC - 0.02
	for i in 5:
		g2.step_fixed()
	check(g2._phase == KARTS.Phase.ENDING and g2._end_text == "¡Tiempo!", "15 s después del primero: ¡Tiempo!")
	for i in 200:
		g2.step_fixed()
	check(results.size() == 1 and results[0].winners == [1] and float(results[0].scores[2]) < KARTS.LAPS,
		"gana el que llegó; el otro, por distancia")
	g2.queue_free()
	await process_frame


## Física determinista: la misma carrera con los mismos controles da
## exactamente lo mismo, a 60 o a 30 fps (pasos fijos), con choques incluidos.
func test_karts_deterministic() -> void:
	var runs: Array = []
	for fps: int in [60, 60, 30, 144]:
		var game: Variant = MiniGameRegistry.create("karts")
		game.setup(_fake_players(4))
		game.place_on_grid(1)
		# Los controles cambian cada 4 pasos fijos (1/15 s): así los frames
		# de 30 fps no parten un cambio al medio.
		while game._ticks < 60 * 15:
			var block := floori(game._ticks / 4.0)
			for pid: int in game._karts:
				game.on_input(pid, {"seq": block, "axis": Vector2(sin(block * 0.37 + pid), cos(block * 0.23 + pid * 2.0) * 0.7), "btn": 0})
			if fps == 144:
				game.advance(1.0 / fps)  # Frames más cortos que el paso: a veces ninguno.
			else:
				for k in roundi(60.0 / fps):
					game.step_fixed()
		var snap: Array = []
		for pid: int in game._karts:
			snap.append(game._karts[pid].snapshot())
		runs.append(snap)
		game.free()
	check(runs[0] == runs[1], "misma entrada, mismo resultado")
	check(runs[0] == runs[2], "a 30 fps da lo mismo que a 60")
	check(runs[0] == runs[3], "con frames de 144 Hz (advance acumula) da lo mismo")
	# Nadie se sale de la pista.
	var lat_ok := true
	for snap: Array in runs[0]:
		lat_ok = lat_ok and absf(float(snap[8])) <= KARTS.HALF_WIDTH - KARTS.KART_RADIUS + 1.0
	check(lat_ok, "todos siguen dentro de la pista")
## Tropiezos: la valla frena ~1 s con cara de susto (y se cae), el pozo
## demora y devuelve del otro lado, contra el escalón se tropieza y se trepa.
## Quien salta a tiempo no pierde nada.
func test_hurdles_trip() -> void:
	var hurdle := [{"kind": HURDLES.Kind.HURDLE, "x": 600.0, "w": 0.0, "h": HURDLES.HURDLE_H}]
	var game: Variant = _hurdles_game(2, hurdle)
	var a: Variant = game._runners[1]
	var b: Variant = game._runners[2]
	var tripped_at := -1.0
	var lost := -1.0
	for i in roundi(4.0 / HURDLES.DT):
		_hurdles_bot(game, 2)
		game.step(HURDLES.DT)
		if tripped_at < 0.0 and a.stumble > 0.0:
			tripped_at = game._elapsed
			check(a.speed <= HURDLES.STUMBLE_SPEED, "tropezar frena en seco (%.0f)" % a.speed)
			check(game._mood(1) == PlayerAvatar.Mood.SURPRISED, "cara de susto al tropezar")
			check(a.knocked.has(0), "la valla se cae")
		if tripped_at >= 0.0 and lost < 0.0 and a.stumble <= 0.0 and a.speed >= HURDLES.RUN_SPEED * 0.99:
			lost = game._elapsed - tripped_at
	check(lost > 0.9 and lost < 1.6, "tropezar frena ≈ 1 s (%.2f)" % lost)
	check(a.trips == 1 and b.trips == 0, "tropieza el que no salta (%d, %d)" % [a.trips, b.trips])
	check(b.x > a.x + 250.0, "el que saltó a tiempo va adelante (%.0f, %.0f)" % [b.x, a.x])
	check(game._mood(1) == PlayerAvatar.Mood.NORMAL, "después del tropezón vuelve la cara normal")
	game.queue_free()

	var pit := [{"kind": HURDLES.Kind.PIT, "x": 600.0, "w": 120.0, "h": 0.0}]
	game = _hurdles_game(2, pit)
	a = game._runners[1]
	b = game._runners[2]
	var fell := false
	for i in roundi(4.0 / HURDLES.DT):
		_hurdles_bot(game, 2)
		game.step(HURDLES.DT)
		if a.fall > 0.0 and not fell:
			fell = true
			check(a.x > 600.0 and a.x < 720.0, "cae dentro del pozo (%.0f)" % a.x)
			check(game._mood(1) == PlayerAvatar.Mood.SURPRISED, "cara de susto al caer")
	check(fell and a.x > 720.0 and a.grounded and a.y == 0.0, "sale del otro lado del pozo (%.0f)" % a.x)
	check(b.trips == 0 and b.x > a.x + 250.0, "el que saltó el pozo va adelante (%.0f, %.0f)" % [b.x, a.x])
	game.queue_free()

	var block := [{"kind": HURDLES.Kind.BLOCK, "x": 600.0, "w": 180.0, "h": HURDLES.BLOCK_H}]
	game = _hurdles_game(2, block)
	a = game._runners[1]
	b = game._runners[2]
	var on_top := false
	var b_on_top := false
	for i in roundi(4.0 / HURDLES.DT):
		_hurdles_bot(game, 2)
		game.step(HURDLES.DT)
		on_top = on_top or (a.grounded and a.y == HURDLES.BLOCK_H)
		b_on_top = b_on_top or (b.grounded and b.y == HURDLES.BLOCK_H)
	check(a.trips == 1 and on_top, "contra el escalón tropieza y se trepa (%d)" % a.trips)
	check(b.trips == 0 and b_on_top, "saltando cae arriba del escalón sin tropezar (%d)" % b.trips)
	check(a.grounded and a.y == 0.0 and b.y == 0.0, "al terminar el escalón bajan al piso")
	game.queue_free()

	# Pozo ancho con plataforma: saltando dos veces se cruza.
	var wide := [{"kind": HURDLES.Kind.PIT, "x": 600.0, "w": 360.0, "h": 0.0},
		{"kind": HURDLES.Kind.PLATFORM, "x": 720.0, "w": 120.0, "h": HURDLES.PLATFORM_H}]
	game = _hurdles_game(1, wide)
	a = game._runners[1]
	var on_platform := false
	for i in roundi(4.0 / HURDLES.DT):
		var down: bool = (a.x > 540.0 and a.x < 580.0) or (a.grounded and a.y == HURDLES.PLATFORM_H and a.x > 770.0)
		_hurdles_press(game, 1, down)
		game.step(HURDLES.DT)
		on_platform = on_platform or (a.grounded and a.y == HURDLES.PLATFORM_H)
	check(on_platform, "se puede aterrizar en la plataforma")
	check(a.trips == 0 and a.x > 1000.0, "cruza el pozo ancho sin caer (%d, %.0f)" % [a.trips, a.x])
	game.queue_free()
	await process_frame


## Meta: el primero que cruza gana (una sola vez, después del festejo); si
## cruzan en el mismo instante, empatan.
func test_hurdles_finish() -> void:
	var game: Variant = _hurdles_game(3, [])
	var results: Array = []
	game.finished.connect(func(res: Dictionary) -> void: results.append(res))
	game._runners[1].x = HURDLES.COURSE_LEN - 400.0
	game._runners[2].x = HURDLES.COURSE_LEN - 10.0
	game._runners[3].x = HURDLES.COURSE_LEN - 2000.0
	_hurdles_run(game, 0.2)
	check(results.is_empty() and game._ending, "al cruzar festeja antes de terminar")
	check(game._mood(2) == PlayerAvatar.Mood.HAPPY and game._mood(1) == PlayerAvatar.Mood.NORMAL, "el ganador festeja")
	_hurdles_run(game, HURDLES.END_SEC + 0.2)
	check(results.size() == 1, "termina una vez (%d)" % results.size())
	if results.size() == 1:
		var res: Dictionary = results[0]
		check(res.winners == [2], "gana Sofi, la primera en la meta (%s)" % [res.winners])
		check(float(res.scores[2]) == HURDLES.COURSE_LEN / HURDLES.PX_PER_M, "la meta vale el recorrido entero (%s)" % [res.scores])
		check(float(res.scores[1]) > float(res.scores[3]), "los demás, por distancia (%s)" % [res.scores])
	game.finish({"winners": [1], "scores": {}})
	_hurdles_run(game, 1.0)
	check(results.size() == 1, "finished se emite una sola vez (%d)" % results.size())
	check(HURDLES.get_info().score_label == "metros", "puntaje en metros")
	game.queue_free()

	# Llegan juntos: empate.
	game = _hurdles_game(2, [])
	results = []
	game.finished.connect(func(res: Dictionary) -> void: results.append(res))
	game._runners[1].x = HURDLES.COURSE_LEN - 5.0
	game._runners[2].x = HURDLES.COURSE_LEN - 5.0
	_hurdles_run(game, HURDLES.END_SEC + 0.5)
	check(results.size() == 1 and results[0].winners == [1, 2], "cruzar a la vez es empate (%s)" % [results])
	game.queue_free()
	await process_frame


## Tiempo: si nadie llega, gana el que llegó más lejos (y si están iguales,
## empatan).
func test_hurdles_time_up() -> void:
	for tie in [false, true]:
		var game: Variant = _hurdles_game(2, [])
		var results: Array = []
		game.finished.connect(func(res: Dictionary) -> void: results.append(res))
		game._elapsed = HURDLES.DURATION_SEC - 0.5
		game._runners[1].x = 5000.0
		game._runners[2].x = 5000.0 if tie else 4000.0
		_hurdles_run(game, 0.6)
		check(game._ending and game._end_text == "¡Tiempo!", "se acaba el tiempo")
		_hurdles_run(game, HURDLES.END_SEC + 0.2)
		check(results.size() == 1, "termina una vez (%d)" % results.size())
		if results.size() == 1:
			var want := [1, 2] if tie else [1]
			check(results[0].winners == want, "por distancia: %s (%s)" % [want, results[0]])
		game.queue_free()
	await process_frame


## Determinismo: la misma semilla da el mismo recorrido y, con las mismas
## entradas, la misma carrera; el recorrido es jugable (ordenado, dentro de la
## pista, con aire entre obstáculos).
func test_hurdles_determinism() -> void:
	var c1: Array = HURDLES.build_course(1234)
	check(c1 == HURDLES.build_course(1234), "misma semilla, mismo recorrido")
	check(c1 != HURDLES.build_course(4321), "otra semilla, otro recorrido")
	check(c1.size() >= 12, "recorrido con obstáculos (%d)" % c1.size())
	var ok := true
	for i in c1.size():
		var o: Dictionary = c1[i]
		ok = ok and float(o.x) >= HURDLES.FIRST_OBSTACLE_X and float(o.x) + float(o.w) < HURDLES.COURSE_LEN - 400.0
		if i > 0 and int(o.kind) != HURDLES.Kind.PLATFORM:
			var prev: Dictionary = c1[i - 1]
			if int(prev.kind) == HURDLES.Kind.PLATFORM:
				prev = c1[i - 2]
			ok = ok and float(o.x) - (float(prev.x) + float(prev.w)) >= 240.0
	check(ok, "obstáculos ordenados, separados y dentro de la pista")
	var kinds := {}
	for s in range(1, 6):
		for o: Dictionary in HURDLES.build_course(s):
			kinds[int(o.kind)] = true
	check(kinds.size() == 4, "hay vallas, pozos, escalones y plataformas (%s)" % [kinds.keys()])
	# Dos carreras con la misma semilla y las mismas entradas: idénticas.
	var runs: Array = []
	for n in 2:
		var game: Variant = MiniGameRegistry.create("hurdles")
		root.add_child(game)
		game.set_physics_process(false)
		game.setup(_fake_players(3))
		game._rng.seed = 99
		for i in roundi(25.0 / HURDLES.DT):
			for pid in [1, 2, 3]:
				var btn := Protocol.BTN_A if (i + pid * 7) % (9 + pid * 4) < 3 + pid else 0
				game.on_input(pid, {"seq": i, "axis": Vector2.ZERO, "btn": btn})
			game.step(HURDLES.DT)
		var snap := []
		for pid in [1, 2, 3]:
			var r: Variant = game._runners[pid]
			snap.append([r.x, r.y, r.trips, r.knocked.size()])
		runs.append(snap)
		game.queue_free()
	check(runs[0] == runs[1], "misma semilla y entradas: misma carrera (%s)" % [runs])
	check(float(runs[0][0][0]) > 3000.0, "en 25 s se avanza (%s)" % [runs[0]])
	# Pasos fijos: avanzar con frames de distinto largo da lo mismo.
	var g1: Variant = _hurdles_game(1, [])
	var g2: Variant = _hurdles_game(1, [])
	for i in 60:
		g1.step(HURDLES.DT)
	for i in 20:
		g2.step(HURDLES.DT * 3.0)
	check(is_equal_approx(g1._runners[1].x, g2._runners[1].x), "pasos fijos: igual con frames de 1/60 que de 1/20 (%.3f, %.3f)" % [g1._runners[1].x, g2._runners[1].x])
	g1.queue_free()
	g2.queue_free()
# --- Música y mezcla (ADR 0015) -------------------------------------------------

func test_audio_buses_and_volumes() -> void:
	AudioMix.ensure_buses()
	AudioMix.ensure_buses()  # Idempotente: no duplica buses.
	for bus_name: String in [AudioMix.BUS_MUSIC, AudioMix.BUS_SFX]:
		var idx := AudioServer.get_bus_index(bus_name)
		if not check_that(idx != -1, "existe el bus %s" % bus_name):
			return
		check(AudioServer.get_bus_send(idx) == &"Master", "%s sale por Master" % bus_name)
	var names := {}
	for i in AudioServer.bus_count:
		names[AudioServer.get_bus_name(i)] = true
	check(names.size() == AudioServer.bus_count, "sin buses repetidos")
	var before_music := AudioMix.get_volume(AudioMix.BUS_MUSIC)
	var before_sfx := AudioMix.get_volume(AudioMix.BUS_SFX)
	AudioMix.set_volume(AudioMix.BUS_MUSIC, 0.4)
	check(is_equal_approx(snappedf(AudioMix.get_volume(AudioMix.BUS_MUSIC), 0.01), 0.4), "volumen de música 40 %")
	AudioMix.set_volume(AudioMix.BUS_SFX, 7.0)
	check(is_equal_approx(AudioMix.get_volume(AudioMix.BUS_SFX), 1.0), "volumen recortado a 100 %")
	AudioMix.set_volume(AudioMix.BUS_SFX, 0.0)
	check(AudioMix.get_volume(AudioMix.BUS_SFX) == 0.0 and AudioServer.is_bus_mute(AudioServer.get_bus_index(AudioMix.BUS_SFX)),
		"0 % silencia el bus")
	# Guardar y leer sin pisar otras secciones; valores basura se ignoran.
	var path := "user://test_audio_prefs.cfg"
	var cfg := ConfigFile.new()
	cfg.set_value("player", "name", "Pablo")
	cfg.save(path)
	AudioMix.save_prefs(path)
	AudioMix.set_volume(AudioMix.BUS_MUSIC, 1.0)
	AudioMix.set_volume(AudioMix.BUS_SFX, 1.0)
	AudioMix.load_prefs(path)
	check(is_equal_approx(snappedf(AudioMix.get_volume(AudioMix.BUS_MUSIC), 0.01), 0.4)
		and AudioMix.get_volume(AudioMix.BUS_SFX) == 0.0, "los volúmenes se recuerdan")
	cfg.load(path)
	check(cfg.get_value("player", "name", "") == "Pablo", "guardar no borra otras secciones")
	cfg.set_value("audio", "music_volume", "fuerte")
	cfg.set_value("audio", "sfx_volume", -3)
	cfg.save(path)
	AudioMix.load_prefs(path)
	check(AudioMix.get_volume(AudioMix.BUS_SFX) == 0.0, "valor fuera de rango se recorta")
	check(is_equal_approx(snappedf(AudioMix.get_volume(AudioMix.BUS_MUSIC), 0.01), 0.4), "valor no numérico se ignora")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	AudioMix.prefs_path = ""
	AudioMix.set_volume(AudioMix.BUS_MUSIC, before_music)
	AudioMix.set_volume(AudioMix.BUS_SFX, before_sfx)


func test_music_crossfade() -> void:
	var music := Music.new()
	root.add_child(music)
	await process_frame
	Music.play("lobby")
	check(music.current == "lobby", "suena la pista del lobby")
	var stream := music._stream("lobby")
	check(stream is AudioStreamOggVorbis and (stream as AudioStreamOggVorbis).loop, "la pista es OGG en bucle")
	var peak_sum := _advance_music(music, Music.FADE + 0.2)
	check(peak_sum <= 1.001, "el fundido de entrada no pasa de 1 (%.3f)" % peak_sum)
	check(is_equal_approx(music.gains()[music._active], 1.0), "la pista llega a volumen pleno")
	Music.play("lobby")
	check(is_equal_approx(music.gains()[music._active], 1.0) and not music.is_processing(),
		"pedir la misma pista no la reinicia")
	for track: String in ["summary", "game_action", "podium"]:
		Music.play(track)
		peak_sum = _advance_music(music, 0.3)
		Music.play("lobby" if track != "podium" else "summary")  # Cambio a mitad del fundido.
		peak_sum = maxf(peak_sum, _advance_music(music, Music.FADE + 0.2))
		check(peak_sum <= 1.001, "nunca dos pistas fuertes a la vez (%s, suma %.3f)" % [track, peak_sum])
		var loud := 0
		for i in 2:
			if music.gains()[i] > 0.01:
				loud += 1
		check(loud == 1, "terminado el fundido suena una sola pista (%s)" % track)
		check(not music._players[1 - music._active].playing, "la pista que se fue se detiene")
	# Con jingle: primero el logo sonoro, la pista entra al terminar.
	Music.play("podium", "party")
	check(music._jingle_player.playing, "suena el jingle")
	_advance_music(music, 0.2)
	check(music._players[music._active].stream != music._stream("podium") or music.gains()[music._active] < 0.01,
		"la pista espera al jingle")
	_advance_music(music, Jingles.duration("party") + Music.FADE)
	check(music._players[music._active].stream == music._stream("podium")
		and is_equal_approx(music.gains()[music._active], 1.0), "después del jingle entra la pista")
	Music.stop()
	_advance_music(music, Music.FADE + 0.1)
	check(music.current == "" and music.gains()[0] == 0.0 and music.gains()[1] == 0.0, "stop baja todo")
	check(not music.is_processing(), "quieta, la música no gasta _process")
	music.queue_free()
	await process_frame
	Music.play("lobby")  # Sin nodo: no hace nada ni rompe.
	Music.duck()


## Avanza la música de a pasos de 1/60 s; devuelve la mayor suma de volúmenes.
func _advance_music(music: Music, seconds: float) -> float:
	var peak := 0.0
	var t := 0.0
	while t < seconds:
		music.advance(1.0 / 60.0)
		peak = maxf(peak, music.gains()[0] + music.gains()[1])
		t += 1.0 / 60.0
	return peak


func test_music_ducking() -> void:
	var music := Music.new()
	root.add_child(music)
	await process_frame
	Music.play("game_play")
	_advance_music(music, Music.FADE + 0.1)
	var p := music._players[music._active]
	var full_db := p.volume_db
	Music.on_sfx("tick")
	check(music.duck_db() == 0.0, "un efecto menor no baja la música")
	Music.on_sfx("go")
	check(is_equal_approx(music.duck_db(), Music.DUCK_DB), "\"¡YA!\" baja la música %.0f dB" % Music.DUCK_DB)
	check(is_equal_approx(p.volume_db, full_db + Music.DUCK_DB), "el reproductor baja")
	_advance_music(music, Music.DUCK_HOLD * 0.5)
	check(is_equal_approx(music.duck_db(), Music.DUCK_DB), "se queda abajo durante DUCK_HOLD")
	_advance_music(music, Music.DUCK_HOLD + Music.DUCK_RELEASE + 0.1)
	check(music.duck_db() == 0.0 and is_equal_approx(p.volume_db, full_db), "el ducking vuelve al nivel original")
	check(not music.is_processing(), "terminado el ducking, se apaga _process")
	# Con el nodo Sfx en el árbol, Sfx.play("win") también baja la música.
	var sfx := Sfx.new()
	root.add_child(sfx)
	await process_frame
	var was_muted := Sfx.muted
	Sfx.muted = false
	Sfx.play("win")
	check(music.duck_db() < 0.0, "Sfx.play(\"win\") dispara el ducking")
	Sfx.muted = was_muted
	sfx.queue_free()
	music.queue_free()
	await process_frame


func test_music_mute() -> void:
	var music := Music.new()
	root.add_child(music)
	await process_frame
	var was_muted := Sfx.muted
	Music.play("lobby")
	Sfx.muted = true
	Music.sync_mute()
	check(AudioMix.is_muted(), "Sonido: No silencia el bus Master")
	check(music.is_paused() and music._players[music._active].stream_paused, "la música queda en pausa")
	Music.play("summary")
	check(music._players[music._active].stream_paused, "una pista nueva con sonido apagado arranca en pausa")
	Sfx.muted = false
	Music.sync_mute()
	check(not AudioMix.is_muted() and not music._players[music._active].stream_paused, "Sonido: Sí la reanuda")
	Sfx.muted = was_muted
	Music.sync_mute()
	music.queue_free()
	await process_frame


func test_music_tracks_and_jingles() -> void:
	for track: String in Music.TRACKS:
		check(ResourceLoader.exists(Music.TRACKS[track]), "existe la pista %s" % track)
	for info in MiniGameRegistry.all_info():
		check(Music.TRACKS.has(Music.track_for_game(info.id)), "%s tiene música" % info.id)
	check(Music.track_for_game("juego-nuevo") == Music.DEFAULT_GAME_TRACK, "un juego sin grupo usa la pista por defecto")
	for jingle_name: String in Jingles.SCORES:
		var a := Jingles.render(jingle_name)
		var b := Jingles.render(jingle_name)
		var seconds := a.data.size() / 2.0 / Jingles.MIX_RATE
		check(a.data == b.data, "%s: siempre suena igual" % jingle_name)
		check(seconds > 1.0 and seconds < 3.0 and absf(seconds - Jingles.duration(jingle_name)) < 0.01,
			"%s: jingle corto (%.2f s)" % [jingle_name, seconds])
		var peak := 0
		for i in range(0, a.data.size(), 2):
			peak = maxi(peak, absi(a.data.decode_s16(i)))
		check(peak > 5000 and peak < 32767, "%s: audible y sin saturar (pico %d)" % [jingle_name, peak])
	check(Jingles.render("no-existe") == null, "jingle desconocido")
	for sound_name: String in SfxFiles.FILES:
		check(Sfx.RECIPES.has(sound_name), "%s grabado tiene receta de respaldo" % sound_name)
	check(SfxFiles.load_streams().size() == SfxFiles.FILES.size(), "cargan los efectos grabados")


## Cada archivo de assets/audio tiene su licencia al lado y figura en CREDITS.md.
func test_audio_licenses() -> void:
	var credits := FileAccess.get_file_as_string("res://CREDITS.md")
	if not check_that(not credits.is_empty(), "existe CREDITS.md"):
		return
	var count := 0
	for sub in DirAccess.get_directories_at("res://assets/audio"):
		var dir := "res://assets/audio/%s" % sub
		var licenses: Array[String] = []
		for f in DirAccess.get_files_at(dir):
			if f.begins_with("LICENSE"):
				licenses.append(f)
		for f in DirAccess.get_files_at(dir):
			if not (f.get_extension() in ["ogg", "wav", "mp3"]):
				continue
			count += 1
			check(not licenses.is_empty(), "%s/%s tiene archivo de licencia al lado" % [sub, f])
			check(credits.contains("assets/audio/%s/%s" % [sub, f]), "%s/%s figura en CREDITS.md" % [sub, f])
		for lic in licenses:
			var text := FileAccess.get_file_as_string("%s/%s" % [dir, lic])
			check(text.contains("CC0"), "%s/%s es CC0" % [sub, lic])
	check(count >= 9, "se revisaron los archivos de audio (%d)" % count)


func test_volume_stepper() -> void:
	var before := AudioMix.get_volume(AudioMix.BUS_MUSIC)
	AudioMix.prefs_path = ""
	AudioMix.set_volume(AudioMix.BUS_MUSIC, 0.5)
	var stepper := VolumeStepper.new(AudioMix.BUS_MUSIC, "Música")
	root.add_child(stepper)
	check(stepper.value == 5, "arranca en el volumen actual")
	check(stepper.focus_mode == Control.FOCUS_ALL and stepper.custom_minimum_size.y > 0, "navegable con el D-pad")
	var right := InputEventAction.new()
	right.action = "ui_right"
	right.pressed = true
	stepper._gui_input(right)
	check(stepper.value == 6 and is_equal_approx(snappedf(AudioMix.get_volume(AudioMix.BUS_MUSIC), 0.01), 0.6),
		"▶ sube la música un 10 %")
	stepper.set_value(-4)
	check(stepper.value == 0 and AudioMix.get_volume(AudioMix.BUS_MUSIC) == 0.0, "no baja de 0")
	stepper.queue_free()
	await process_frame
	AudioMix.set_volume(AudioMix.BUS_MUSIC, before)


func test_controller_has_no_music() -> void:
	var ctrl := ControllerMain.new()
	root.add_child(ctrl)
	await process_frame
	var has_music := false
	var has_sfx := false
	for child in ctrl.get_children():
		has_music = has_music or child is Music
		has_sfx = has_sfx or child is Sfx
	check(has_sfx and not has_music, "el celular tiene efectos pero no música")
	ctrl.queue_free()
	await process_frame
