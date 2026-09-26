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


func test_result_from_scores() -> void:
	var r := MiniGame.result_from_scores({1: 3, 2: 5, 3: 5})
	check(r.winners == [2, 3], "empate devuelve ambos ganadores")


func test_registry_optional_defaults() -> void:
	for info in MiniGameRegistry.all_info():
		check(typeof(info.get("accent")) == TYPE_COLOR, "%s: accent es un color" % info.id)
		check(typeof(info.get("score_label")) == TYPE_STRING and not str(info.score_label).is_empty(),
			"%s: score_label es un texto" % info.id)
	check(MiniGameRegistry.info("arena").score_label == "estrellas", "el juego puede sobrescribir los valores por defecto")



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


## Flujo completo en la TV con controles reales: lobby -> juego -> resumen ->
## siguiente juego -> pausa/saltar -> podio -> jugar otra vez -> lobby.
func test_host_tournament_flow() -> void:
	var host := HostMain.new()
	host.server_port = TEST_PORT + 3
	host.announce = false
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
	check(host.phase == Protocol.PHASE_PLAYING and host._game != null, "fase de juego")
	check(not host.server.accepting_new_players, "no entran jugadores nuevos durante la competencia")
	await _until(func() -> bool: return Protocol.LAYOUT_ONE_BUTTON in layouts)
	check(Protocol.LAYOUT_ONE_BUTTON in layouts, "el celular recibe el control del juego")

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


# --- Utilidades -----------------------------------------------------------------

func _fake_players(n: int) -> Array[Dictionary]:
	var names := ["Pablo", "Sofi", "Tomi", "Juli"]
	var out: Array[Dictionary] = []
	for i in n:
		out.append({"id": i + 1, "slot": i, "name": names[i], "color": Protocol.player_color(i), "connected": true})
	return out


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
