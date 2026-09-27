extends SceneTree
## Tests automáticos, sin dependencias externas. Se corren headless:
##   godot --headless --path . -s res://tests/run_tests.gd
## Sale con código 0 si todo pasa y 1 si algo falla (lo usa la CI).

const TEST_PORT := 47990

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
	await physics_frame
	await physics_frame
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
func test_host_sends_standing() -> void:
	var port := TEST_PORT + 4
	var host := HostMain.new()
	host.server_port = port
	host.announce = false
	host.transition_seconds = 0.0
	root.add_child(host)
	await process_frame
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
	check(host.start_tournament(["tap_race", "arena"] as Array[String]), "arranca la competencia")
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
	ws.send_text('{"v":1,"type":"input","seq":1,"axis":[0,0],"btn":1}')  # input sin haberse unido
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
	ws.send_text(JSON.stringify({"v": 1, "type": "join", "room": server.room_code, "name": "Viejo"}))
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
	ws2.send_text(JSON.stringify({"v": 1, "type": "join", "room": server.room_code, "name": "Raro", "color": "negro", "style": [99]}))
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
	ws.send_text('{"v":1,"type":"look","color":[1],"style":{"a":1}}')
	ws.send_text('{"v":1,"type":"look","color":1e999}')
	ws.send_text('{"v":1,"type":"look"}')
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
		ws.send_text(JSON.stringify({"v": 1, "type": "look", "style": i % Protocol.MASCOT_STYLES}))
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
