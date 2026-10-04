extends SceneTree
## Prueba de partida real (ver docs/PRUEBA_REAL.md): la TV (HostMain) y
## celulares simulados que se conectan por WebSocket de verdad (127.0.0.1),
## se unen con apodo y apariencia, mandan entrada como un celular (30 por
## segundo, con keepalive) y juegan competencias completas solas.
##
##   godot --headless --path . -s res://tools/playtest.gd -- --scenario=full4
##   xvfb-run -a -s "-screen 0 1920x1080x24" godot --path . --rendering-driver opengl3 \
##       --audio-driver Dummy -s res://tools/playtest.gd -- --scenario=full4
##
## Escenarios (--scenario=):
##   full4   4 celulares, todos los juegos que admiten 4, ayudas activadas
##   duo     2 celulares (suma Ping Pong, que es solo de a 2)
##   mixed   2 celulares + 2 bots
##   solo    1 celular + 3 bots
##   chaos   4 celulares con sucesos de la vida real: bloqueo de 10 s en cada
##           juego (con y sin corte del Wi-Fi), en el resumen y en el podio;
##           uno que se va en medio de un juego, otro que quiere entrar tarde,
##           la TV que pausa; y después en el lobby: mismo apodo y alguien
##           que cierra la app y vuelve a entrar
##   long    competencias seguidas (2 celulares + 2 bots) durante --minutes,
##           midiendo memoria, objetos y nodos huérfanos
##   room    --humans=N celulares y --bots=M bots (ej. 2 + 1, 3 + 0)
## En chaos, --humans elige cuántos celulares (default 4; el último es el que
## se va en medio de un juego).
##
## Opciones:
##   --lag=100-300     demora (ms, con jitter) de cada mensaje en los dos
##                     sentidos, con un proxy TCP en el medio
##   --games=a,b       solo esos juegos (default: todos los del registry)
##   --summary=5       segundos en el resumen antes de seguir (default: los
##                     15 s de la cuenta regresiva de la TV)
##   --minutes=25      duración del escenario long
##   --port=29400      puerto de la TV (el proxy usa +50)
##   --json=/tmp/x.json  además guarda los resultados
##   --slow-ms=40      TV lenta: cada cuadro tarda además estos ms (OS.delay_msec)
##   --max-fps=20      TV lenta: tope de cuadros por segundo (Engine.max_fps)
##   --lobby=60        segundos en el lobby antes de arrancar (como la gente
##                     eligiendo mascota): mide el horneado del primer arranque
##   --census          memoria de texturas por dueño (tools/texture_census.gd)
##                     a los 4 s de cada juego y en cada muestra de memoria
##
## La entrada viaja SIEMPRE por la red. Los celulares "dirigidos" deciden qué
## apretar con el mismo cerebro que los bots de la TV (mirando el juego, como
## una persona mira la TV); los demás mueven el joystick y tocan al azar.
## Sale con código 1 si encontró problemas (fases trabadas, celulares que no
## recibieron su resultado o su control, reconexiones fallidas…). Los errores
## del motor (SCRIPT ERROR, push_error) salen en el log: buscarlos con grep.

const DEFAULT_PORT := 29400
const PROXY_OFFSET := 50
## Límites para avisar que una pantalla se trabó (segundos).
const STUCK_SEC := {"intro": 20.0, "game": 200.0, "summary": 25.0, "transition": 6.0, "lobby": 0.0}
const NAMES := ["Pablo", "Sofi", "Tomi", "Juli"]
const LOOKS := [{"color": 0, "style": 1}, {"color": 5, "style": 6}, {"color": 6, "style": 4}, {"color": 7, "style": 2}]
const LOCK_SEC := 10.0

var _host: HostMain
var _phones: Array = []  # PhoneSim
var _proxy: LagProxy
var _scenario := "full4"
var _port := DEFAULT_PORT
var _lag := Vector2i.ZERO
var _games: Array[String] = []
var _summary_wait := -1.0
var _minutes := 25.0
var _json_path := ""
var _humans := -1
var _bots := 0
var _slow_ms := 0
var _lobby_wait := 0.0

var _t0 := 0
var _screen := ""
var _screen_since := 0
var _stuck_reported := false
var _last_frame_us := 0
var _problems: Array[String] = []
var _notes: Array[String] = []
var _game_secs: Dictionary = {}     # game_id -> Array[float]
var _frame_ms: Dictionary = {}      # "game:id" | pantalla -> PackedFloat32Array (ms entre cuadros)
var _proc_ms: Dictionary = {}       # idem, Performance.TIME_PROCESS en ms
var _mem: Array = []                # muestras de memoria
var _tournaments := 0
var _rounds := 0
var _game_index := -1
var _chaos_done: Dictionary = {}
## Horneado (mascotas 3D y tablero 2.5D) desde que aparece la intro de cada
## juego hasta que no queda nada pendiente: game_id -> segundos (o -1 si el
## juego arrancó antes de terminar). Con user:// vacío = primer ingreso.
var _bake_sec: Dictionary = {}
var _bake_game := ""
var _bake_from := 0
var _boot_ready_sec := -1.0
var _census := false
const TextureCensus := preload("res://tools/texture_census.gd")


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--scenario="):
			_scenario = arg.trim_prefix("--scenario=")
		elif arg.begins_with("--port="):
			_port = int(arg.trim_prefix("--port="))
		elif arg.begins_with("--lag="):
			var parts := arg.trim_prefix("--lag=").split("-")
			_lag = Vector2i(int(parts[0]), int(parts[parts.size() - 1]))
		elif arg.begins_with("--games="):
			for id in arg.trim_prefix("--games=").split(",", false):
				_games.append(id.strip_edges())
		elif arg.begins_with("--summary="):
			_summary_wait = float(arg.trim_prefix("--summary="))
		elif arg.begins_with("--minutes="):
			_minutes = float(arg.trim_prefix("--minutes="))
		elif arg.begins_with("--json="):
			_json_path = arg.trim_prefix("--json=")
		elif arg.begins_with("--humans="):
			_humans = clampi(int(arg.trim_prefix("--humans=")), 1, 4)
		elif arg.begins_with("--bots="):
			_bots = clampi(int(arg.trim_prefix("--bots=")), 0, 3)
		elif arg.begins_with("--lobby="):
			_lobby_wait = maxf(0.0, float(arg.trim_prefix("--lobby=")))
		elif arg.begins_with("--slow-ms="):
			_slow_ms = maxi(0, int(arg.trim_prefix("--slow-ms=")))
		elif arg == "--census":
			_census = true
		elif arg.begins_with("--max-fps="):
			Engine.max_fps = maxi(1, int(arg.trim_prefix("--max-fps=")))
	if _games.is_empty():
		for info in MiniGameRegistry.all_info():
			_games.append(str(info.id))
	HelpSession.enabled = true  # Ayudas de los eliminados activadas.
	_t0 = Time.get_ticks_msec()
	_host = HostMain.new()
	_host.server_port = _port
	_host.announce = false
	root.add_child(_host)
	await _frames(5)
	if not _host.server.is_listening():
		printerr("La TV no pudo abrir el puerto %d" % _port)
		quit(2)
		return
	var join_port := _host.server.port
	if _lag.y > 0:
		_proxy = LagProxy.new()
		_proxy.target_port = _host.server.port
		_proxy.lag = _lag
		root.add_child(_proxy)
		if _proxy.start(_host.server.port + PROXY_OFFSET) != OK:
			printerr("No se pudo abrir el proxy")
			quit(2)
			return
		join_port = _proxy.port
	_log("TV en el puerto %d, sala %s, escenario %s%s" % [_host.server.port, _host.server.room_code, _scenario,
		"" if _lag.y == 0 else ", demora %d–%d ms" % [_lag.x, _lag.y]])
	process_frame.connect(_on_frame)

	match _scenario:
		"full4":
			await _setup_room(4, 0, join_port)
			await _play_tournament()
		"duo":
			await _setup_room(2, 0, join_port)
			await _play_tournament()
		"mixed":
			await _setup_room(2, 2, join_port)
			await _play_tournament()
		"solo":
			await _setup_room(1, 3, join_port)
			await _play_tournament()
		"room":
			await _setup_room(maxi(_humans, 1), _bots, join_port)
			await _play_tournament()
		"chaos":
			await _setup_room(4 if _humans < 0 else maxi(_humans, 2), _bots, join_port)
			await _play_tournament(true)
			await _lobby_chaos(join_port)
		"long":
			await _long_session(join_port)
		_:
			printerr("Escenario desconocido: %s" % _scenario)
			quit(2)
			return
	_report()
	quit(1 if not _problems.is_empty() else 0)


# --- Sala ---------------------------------------------------------------------------

func _setup_room(humans: int, bots: int, join_port: int) -> void:
	_host._lobby._stepper.set_value(humans + bots)
	for i in humans:
		var ph := _new_phone(NAMES[i], LOOKS[i], i % 2 == 0)
		ph.join(join_port, _host.server.room_code)
		await _until(func() -> bool: return ph.joined(), 5000)
		if not ph.joined():
			_problem("%s no se pudo unir (%s)" % [ph.nick, ph.rejects])
	for i in bots:
		if not _host.add_bot(Bot.Difficulty.NORMAL):
			_problem("no se pudo sumar un bot")
	await _seconds(1.0)
	# Apariencia: cada celular cambia de estilo desde el lobby (como en el selector).
	for ph in _phones:
		ph.client.send_look(int(ph.look.color), (int(ph.look.style) + 1) % 7)
	await _seconds(1.0)
	var players := _host.server.get_players()
	var names: Array[String] = []
	for p in players:
		names.append("%s%s(c%d,e%d)" % [p.name, " [bot] " if p.bot else " ", p.color_index, p.style])
	_log("En la sala: %s" % ", ".join(names))
	if _lobby_wait > 0.0:
		await _seconds(_lobby_wait)
		if _boot_ready_sec < 0.0:
			_note("a los %.0f s en el lobby todavía se horneaba (%d poses pendientes)" % [_lobby_wait, MascotAtlas.pending_count()])
	if players.size() != humans + bots:
		_problem("se esperaban %d jugadores y hay %d" % [humans + bots, players.size()])
	for ph in _phones:
		var p := _player(ph.player_id())
		if p.is_empty() or int(p.style) != (int(ph.look.style) + 1) % 7:
			_problem("%s: el cambio de estilo no llegó a la TV (%s)" % [ph.nick, p])


func _new_phone(nick: String, look: Dictionary, directed: bool) -> PhoneSim:
	var ph := PhoneSim.new()
	ph.host = _host
	ph.nick = nick
	ph.look = look
	ph.directed = directed
	root.add_child(ph)
	_phones.append(ph)
	return ph


func _player(player_id: int) -> Dictionary:
	for p in _host.server.get_players():
		if int(p.id) == player_id:
			return p
	return {}


# --- Competencia ----------------------------------------------------------------

## Juega una competencia entera con los juegos elegidos y espera el podio.
func _play_tournament(chaos: bool = false) -> void:
	var ids: Array[String] = []
	ids.assign(_games)
	if not _host.start_tournament(ids):
		_problem("no arrancó la competencia")
		return
	_tournaments += 1
	_game_index = -1
	# La competencia arranca tras el barrido: recién ahí deja el lobby.
	await _until(func() -> bool: return _host.phase != Protocol.PHASE_LOBBY, 5000)
	var started := Time.get_ticks_msec()
	var last_screen := ""
	var summary_since := -1
	while Time.get_ticks_msec() - started < 45 * 60 * 1000:
		await process_frame
		if _host.phase == Protocol.PHASE_LOBBY:
			_problem("la competencia volvió al lobby sola (%s)" % _screen)
			return
		if _screen != last_screen:
			last_screen = _screen
			if _screen.begins_with("game:"):
				_game_index += 1
				_check_game_start.call_deferred(_screen)
				if chaos:
					_chaos_in_game.call_deferred(_screen, _game_index)
			elif _screen == "summary":
				_rounds += 1
				summary_since = Time.get_ticks_msec()
				_check_standings.call_deferred(false)
				if chaos and not _chaos_done.has("summary_lock"):
					_chaos_done["summary_lock"] = true
					_lock_phone.call_deferred(_phones[1], true, "en el resumen")
			elif _screen == "final":
				break
		if _screen == "summary" and _summary_wait >= 0.0 and summary_since >= 0 \
				and Time.get_ticks_msec() - summary_since > _summary_wait * 1000.0:
			summary_since = -1
			_host._summary._on_continue()
	if _screen != "final":
		_problem("la competencia no llegó al podio en 45 min (%s)" % _screen)
		return
	_log("Podio: %s" % _standings_text())
	if _scenario != "long":
		_sample_memory("podio")
	await _check_standings(true)
	if chaos:
		await _lock_phone(_phones[0], true, "en el podio")
	await _seconds(2.0)


func _standings_text() -> String:
	var out: Array[String] = []
	for s in _host.tournament.standings():
		out.append("%d° %s %d" % [s.place, s.name, s.total])
	return ", ".join(out)


## 1,5 s después de empezar el juego, cada celular conectado tiene el control
## del juego (o el de ayudar, si ya quedó afuera).
func _check_game_start(screen: String) -> void:
	await _seconds(1.5)
	if _screen != screen:
		return
	for ph in _phones:
		if not ph.active or ph.frozen or not ph.joined():
			continue
		var pid: int = ph.player_id()
		var expected := _host.server.current_layout
		if _host.help.handles(pid):
			expected = Protocol.LAYOUT_JOYSTICK_AB
		if ph.layout != expected:
			_problem("%s: en %s el celular muestra %s y la TV espera %s" % [ph.nick, screen, ph.layout, expected])


## Después del resumen (o el podio), cada celular conectado recibió SU resultado.
func _check_standings(is_final: bool) -> void:
	await _seconds(1.5)
	var round_no := _host.tournament.history.size() if _host.tournament else -1
	for ph in _phones:
		if not ph.active or ph.frozen or not ph.joined() or _player(ph.player_id()).is_empty():
			continue
		var last: Dictionary = ph.standings.back() if not ph.standings.is_empty() else {}
		if last.is_empty() or bool(last.get("final", false)) != is_final or int(last.get("round", -1)) != round_no:
			_problem("%s: no recibió su resultado %s (ronda %d, último %s)" % [ph.nick, "final" if is_final else "de la ronda", round_no, last])


# --- Sucesos de la vida real (chaos) ----------------------------------------------

func _chaos_in_game(screen: String, index: int) -> void:
	var game_id := screen.trim_prefix("game:")
	# Un bloqueo de 10 s en cada juego, rotando el celular y el tipo de corte.
	await _seconds(3.0 + float(index % 3) * 2.0)
	if _screen != screen:
		_note("%s terminó antes del bloqueo de prueba" % game_id)
		return
	var candidates := _phones.filter(func(ph: PhoneSim) -> bool: return ph.active and ph.joined() and not ph.frozen)
	if candidates.is_empty():
		return
	var ph: PhoneSim = candidates[index % candidates.size()]
	match index:
		2:
			# Uno que se va en medio de un juego (mantiene apretado "Salir").
			var leaver: PhoneSim = _phones[_phones.size() - 1]
			if _phones.size() <= 2:
				return  # Con 2, que se vaya uno deja a uno solo: se prueba aparte.
			if leaver.active and leaver.joined():
				_log("%s se va en medio de %s" % [leaver.nick, game_id])
				var pid := leaver.player_id()
				leaver.leave()
				await _until(func() -> bool: return _player(pid).is_empty(), 3000)
				if not _player(pid).is_empty():
					_problem("%s se fue y la TV no liberó su lugar" % leaver.nick)
			return
		3:
			# Alguien llega tarde: la TV lo rechaza con "game_in_progress".
			var late := _new_phone("Tardío", {"color": 2, "style": 3}, false)
			late.join(_join_port(), _host.server.room_code)
			await _until(func() -> bool: return not late.rejects.is_empty() or late.joined(), 4000)
			if late.joined() or late.rejects != ["game_in_progress"]:
				_problem("el que llega tarde debería ver game_in_progress (%s, unido=%s)" % [late.rejects, late.joined()])
			else:
				_log("Tardío no pudo entrar en medio de %s: %s (como se espera)" % [game_id, late.rejects])
			late.active = false
		4:
			# La TV pausa (Atrás) en medio del juego y sigue a los 4 s.
			await _tv_pause(screen)
			return
	await _lock_phone(ph, index % 2 == 1, "en " + game_id)


## Bloquea un celular LOCK_SEC segundos. `drop`: además se corta su conexión
## (el sistema mató el Wi-Fi o el socket); sin `drop`, la conexión queda
## abierta pero muda (app suspendida, el socket sigue vivo).
func _lock_phone(ph: PhoneSim, drop: bool, where: String) -> void:
	if not ph.active or not ph.joined():
		return
	var pid := ph.player_id()
	var slot := int(_player(pid).get("slot", -1))
	_log("%s bloquea el celular %d s %s (%s)" % [ph.nick, LOCK_SEC, where, "se corta el Wi-Fi" if drop else "socket abierto"])
	ph.freeze(true, drop)
	var t := Time.get_ticks_msec()
	var saw_disconnect := false
	while Time.get_ticks_msec() - t < LOCK_SEC * 1000.0:
		await process_frame
		var p := _player(pid)
		if not p.is_empty() and not bool(p.connected):
			saw_disconnect = true
	ph.freeze(false, false)
	if not saw_disconnect:
		_note("%s: con el celular bloqueado %s la TV lo siguió viendo conectado (%s)" % [ph.nick, where, "corte" if drop else "socket abierto"])
	var back := Time.get_ticks_msec()
	await _until(func() -> bool: return ph.joined() and bool(_player(pid).get("connected", false)), 8000)
	var p := _player(pid)
	if p.is_empty() or not bool(p.connected) or not ph.joined() or ph.player_id() != pid or int(p.slot) != slot:
		_problem("%s no volvió a su lugar tras el bloqueo %s (jugador %s, estado %d)" % [ph.nick, where, p, ph.client.state])
		return
	await _seconds(0.8)
	var expected := _host.server.current_layout
	if _host.help.handles(pid):
		expected = Protocol.LAYOUT_JOYSTICK_AB
	if ph.layout != expected:
		_problem("%s volvió %s con el control %s y la TV espera %s" % [ph.nick, where, ph.layout, expected])
	if _host.phase == Protocol.PHASE_RESULTS and _host._standings_sent.has(pid):
		var last: Dictionary = ph.standings.back() if not ph.standings.is_empty() else {}
		if last != _host._standings_sent[pid]:
			_problem("%s volvió %s sin su resultado (%s)" % [ph.nick, where, last])
	_log("%s volvió %s en %.1f s, mismo lugar %dP" % [ph.nick, where, (Time.get_ticks_msec() - back) / 1000.0, slot + 1])


func _tv_pause(screen: String) -> void:
	_log("La TV pausa (Atrás) en %s" % screen)
	var game: MiniGame = _host._game
	if not is_instance_valid(game):
		return
	_press_back()
	await _frames(3)
	if not _host._pause.visible or game.can_process():
		_problem("Atrás no pausó el juego")
		return
	var anim := game.anim_time
	await _seconds(4.0)
	if not is_instance_valid(game) or _screen != "pause":
		_problem("el juego se cerró o cambió de pantalla durante la pausa (%s)" % _screen)
		return
	if absf(game.anim_time - anim) > 0.001:
		_problem("el juego siguió corriendo en pausa")
	_press_back()
	await _frames(3)
	if _host._pause.visible or not game.can_process():
		_problem("Atrás no despausó el juego")
	else:
		_log("La TV siguió después de la pausa")


func _press_back() -> void:
	for pressed in [true, false]:
		var ev := InputEventAction.new()
		ev.action = "ui_cancel"
		ev.pressed = pressed
		Input.parse_input_event(ev)
	Input.flush_buffered_events()


## Ya en el lobby: llega el que no pudo entrar, otro con el mismo apodo, y
## alguien cierra la app (sin "Salir") y la vuelve a abrir.
func _lobby_chaos(join_port: int) -> void:
	_host._final.lobby_requested.emit()
	await _until(func() -> bool: return _host.phase == Protocol.PHASE_LOBBY and _screen == "lobby", 5000)
	await _seconds(1.0)
	for ph in _phones:
		if ph.active and ph.joined() and ph.layout != Protocol.LAYOUT_WAIT:
			_problem("%s sigue con un control en el lobby (%s)" % [ph.nick, ph.layout])
	_host._lobby._stepper.set_value(4)
	var late := _new_phone("Tardío", {"color": 2, "style": 3}, false)
	late.join(join_port, _host.server.room_code)
	await _until(func() -> bool: return late.joined() or not late.rejects.is_empty(), 4000)
	_log("Tardío en el lobby: unido=%s %s" % [late.joined(), late.rejects])
	if not late.joined():
		_problem("después de la partida, el que llegó tarde no puede entrar (%s)" % [late.rejects])
	# Mismo apodo que otro (Pablo).
	var twin := _new_phone("Pablo", {"color": 0, "style": 0}, false)
	twin.join(join_port, _host.server.room_code)
	await _until(func() -> bool: return twin.joined() or not twin.rejects.is_empty(), 4000)
	_log("Otro \"Pablo\": unido=%s %s; en la TV: %s" % [twin.joined(), twin.rejects, _names()])
	if twin.joined():
		var pablos := _host.server.get_players().filter(func(p: Dictionary) -> bool: return p.name == "Pablo")
		if pablos.size() == 2 and pablos[0].slot != pablos[1].slot:
			_note("Dos \"Pablo\" en la sala: se distinguen por 1P–4P y el color (%dP y %dP)" % [pablos[0].slot + 1, pablos[1].slot + 1])
	# Alguien cierra la app en el lobby (el sistema corta el socket, sin "Salir").
	var victim: PhoneSim = null
	for ph in _phones:
		if ph.active and ph.joined() and ph.nick == "Sofi":
			victim = ph
	if victim == null:
		return
	var vid := victim.player_id()
	_log("Sofi cierra la app en el lobby (sin \"Salir\")")
	victim.kill_app()
	await _until(func() -> bool: return not bool(_player(vid).get("connected", true)), 4000)
	_log("En la TV: %s" % _names())
	await _seconds(2.0)
	var again := _new_phone("Sofi", victim.look, false)
	again.join(join_port, _host.server.room_code)
	await _until(func() -> bool: return again.joined() or not again.rejects.is_empty(), 4000)
	_log("Sofi abre la app de nuevo: unido=%s %s; en la TV: %s" % [again.joined(), again.rejects, _names()])
	if not again.joined():
		_problem("Sofi cerró la app en el lobby y al volver no puede entrar (%s)" % [again.rejects])
	elif _host.server.get_players().filter(func(p: Dictionary) -> bool: return p.name == "Sofi").size() > 1:
		_problem("Sofi cerró la app y volvió: quedó dos veces en la sala (%s)" % _names())
	await _seconds(1.0)


func _names() -> String:
	var out: Array[String] = []
	for p in _host.server.get_players():
		out.append("%dP %s%s" % [p.slot + 1, p.name, "" if p.connected else " (desconectado)"])
	return ", ".join(out)


func _join_port() -> int:
	return _proxy.port if _proxy else _host.server.port


# --- Sesión larga -------------------------------------------------------------------

func _long_session(join_port: int) -> void:
	if _summary_wait < 0.0:
		_summary_wait = 3.0
	await _setup_room(2, 2, join_port)
	_sample_memory("inicio")
	var until := Time.get_ticks_msec() + int(_minutes * 60000.0)
	while Time.get_ticks_msec() < until:
		await _play_tournament()
		if _screen != "final":
			return
		_sample_memory("podio %d" % _tournaments)
		_host._final.play_again_requested.emit()
		await _until(func() -> bool: return _screen.begins_with("intro"), 6000)
		if not _screen.begins_with("intro"):
			_problem("\"Jugar otra vez\" no arrancó otra competencia (%s)" % _screen)
			return
		# Arrancó sola: _play_tournament la vuelve a pedir; acá se la deja seguir.
		await _follow_running_tournament()
		if _screen != "final":
			return
		_sample_memory("podio %d" % _tournaments)
		_host._final.lobby_requested.emit()
		await _until(func() -> bool: return _screen == "lobby", 6000)
		await _seconds(1.0)


## Sigue una competencia que ya arrancó (por "Jugar otra vez").
func _follow_running_tournament() -> void:
	_tournaments += 1
	var started := Time.get_ticks_msec()
	var last := ""
	var summary_since := -1
	while Time.get_ticks_msec() - started < 45 * 60 * 1000:
		await process_frame
		if _screen != last:
			last = _screen
			if _screen.begins_with("game:"):
				_check_game_start.call_deferred(_screen)
			elif _screen == "summary":
				_rounds += 1
				summary_since = Time.get_ticks_msec()
				_check_standings.call_deferred(false)
			elif _screen == "final" or _screen == "lobby":
				break
		if _screen == "summary" and summary_since >= 0 and Time.get_ticks_msec() - summary_since > _summary_wait * 1000.0:
			summary_since = -1
			_host._summary._on_continue()
	_log("Podio: %s" % _standings_text())


func _sample_memory(label: String) -> void:
	var m := {
		"label": label,
		"min": (Time.get_ticks_msec() - _t0) / 60000.0,
		"static_mb": Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0,
		"objects": int(Performance.get_monitor(Performance.OBJECT_COUNT)),
		"nodes": int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),
		"orphans": int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)),
		"resources": int(Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT)),
		"texture_mb": Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED) / 1048576.0,
		"mascots_mb": MascotAtlas.memory_bytes() / 1048576.0,
		"boards_mb": Board25DBaker.memory_bytes() / 1048576.0,
	}
	if _census:
		m["census"] = TextureCensus.take(self)
		_log("  " + TextureCensus.line(m.census))
	_mem.append(m)
	_log("Memoria (%s): %.1f MB estática, %d objetos, %d nodos, %d huérfanos, %d recursos, %.1f MB texturas (mascotas %.1f, tableros %.1f)" % [
		label, m.static_mb, m.objects, m.nodes, m.orphans, m.resources, m.texture_mb, m.mascots_mb, m.boards_mb])


# --- Monitor por cuadro -------------------------------------------------------------

func _on_frame() -> void:
	if _slow_ms > 0:
		OS.delay_msec(_slow_ms)  # TV lenta: cada cuadro cuesta más.
	var now_us := Time.get_ticks_usec()
	var s := _screen_now()
	var idle := MascotAtlas.is_idle() and Board25DBaker.is_idle()
	if _boot_ready_sec < 0.0 and idle and s == "lobby":
		_boot_ready_sec = (Time.get_ticks_msec() - _t0) / 1000.0
		_log("Lobby con todo horneado a los %.1f s de abrir" % _boot_ready_sec)
	if s.begins_with("intro:") and s != _screen:
		_bake_game = s.trim_prefix("intro:")
		_bake_from = Time.get_ticks_msec()
	if not _bake_game.is_empty() and not _bake_sec.has(_bake_game):
		if idle:
			_bake_sec[_bake_game] = (Time.get_ticks_msec() - _bake_from) / 1000.0
			_bake_game = ""
		elif s.begins_with("game:"):
			_bake_sec[_bake_game] = -1.0
			_note("%s arrancó con el horneado sin terminar (%.1f s de intro; se ve la mascota 2D un rato)" % [
				_bake_game, (Time.get_ticks_msec() - _bake_from) / 1000.0])
			_bake_game = ""
	if s != _screen:
		var secs := (Time.get_ticks_msec() - _screen_since) / 1000.0
		if _screen.begins_with("game:"):
			var id := _screen.trim_prefix("game:")
			if not _game_secs.has(id):
				_game_secs[id] = []
			_game_secs[id].append(secs)
			_log("  %s terminó en %.1f s" % [id, secs])
		if s.begins_with("game:") or s == "summary" or s == "final" or s.begins_with("intro"):
			_log("→ %s" % s)
		if _census and (s.begins_with("game:") or s == "final" or s == "lobby"):
			create_timer(4.0).timeout.connect(func() -> void:
				if _screen == s:
					_sample_memory(s))
		_screen = s
		_screen_since = Time.get_ticks_msec()
		_stuck_reported = false
	elif _last_frame_us > 0:
		var key := s.get_slice(":", 0) if not s.begins_with("game:") else s
		if not _frame_ms.has(key):
			_frame_ms[key] = PackedFloat32Array()
			_proc_ms[key] = PackedFloat32Array()
		_frame_ms[key].append((now_us - _last_frame_us) / 1000.0)
		_proc_ms[key].append(Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0)
		var kind := s.get_slice(":", 0)
		var limit: float = STUCK_SEC.get(kind, 0.0)
		if limit > 0.0 and not _stuck_reported and Time.get_ticks_msec() - _screen_since > limit * 1000.0:
			_stuck_reported = true
			_problem("%s lleva más de %.0f s" % [s, limit])
	_last_frame_us = now_us
	if _scenario == "long" and not _mem.is_empty() and (Time.get_ticks_msec() - _t0) / 60000.0 - float(_mem.back().min) > 2.0:
		_sample_memory("cada 2 min")


func _screen_now() -> String:
	if _host._pause.visible:
		return "pause"
	if _host._final.visible:
		return "final"
	if _host._summary.visible:
		return "summary"
	if is_instance_valid(_host._game) and _host.tournament:
		return "game:" + _host.tournament.current_game_id
	if _host._intro.visible and _host.tournament:
		return "intro:" + _host.tournament.current_game_id
	if _host._lobby.visible:
		return "lobby"
	return "transition"


# --- Informe --------------------------------------------------------------------------

func _report() -> void:
	print("\n=== Prueba real · %s · %.1f min · %d competencias, %d rondas ===" % [
		_scenario, (Time.get_ticks_msec() - _t0) / 60000.0, _tournaments, _rounds])
	print("\nDuración de cada juego (s):")
	for id: String in _game_secs:
		var a: Array = _game_secs[id]
		print("  %-11s %s" % [id, ", ".join(a.map(func(x: float) -> String: return "%.1f" % x))])
	if not _bake_sec.is_empty():
		print("\nHorneado al entrar a cada juego (s desde la intro; -1 = no llegó antes del juego):")
		for id: String in _bake_sec:
			print("  %-11s %.1f" % [id, _bake_sec[id]])
	print("\nTiempo entre cuadros (ms): p50 / p95 / p99 / máx  ·  Process p95")
	var keys := _frame_ms.keys()
	keys.sort()
	for k: String in keys:
		var f := _sorted(_frame_ms[k])
		var p := _sorted(_proc_ms[k])
		if f.size() < 10:
			continue
		print("  %-18s %6.1f %6.1f %6.1f %7.1f  ·  %5.1f  (%d cuadros)" % [k, _pct(f, 0.5), _pct(f, 0.95), _pct(f, 0.99), f[f.size() - 1], _pct(p, 0.95), f.size()])
	if _census:
		print("\nFuentes (tamaño/contorno: KB de glifos): " + TextureCensus.font_detail())
	if not _mem.is_empty():
		print("\nMemoria:")
		for m in _mem:
			print("  %5.1f min  %-12s %7.1f MB  %6d obj  %5d nodos  %3d huérf.  %5d rec.  %6.1f MB tex" % [
				m.min, m.label, m.static_mb, m.objects, m.nodes, m.orphans, m.resources, m.texture_mb])
	print("\nNotas (%d):" % _notes.size())
	for n in _notes:
		print("  · " + n)
	print("\nProblemas (%d):" % _problems.size())
	for p in _problems:
		print("  ✗ " + p)
	print("")
	if not _json_path.is_empty():
		var f := FileAccess.open(_json_path, FileAccess.WRITE)
		if f:
			f.store_string(JSON.stringify({"scenario": _scenario, "games": _game_secs, "bake": _bake_sec, "boot_ready": _boot_ready_sec, "memory": _mem,
				"notes": _notes, "problems": _problems, "tournaments": _tournaments, "rounds": _rounds}, "  "))


func _sorted(a: PackedFloat32Array) -> PackedFloat32Array:
	var b := a.duplicate()
	b.sort()
	return b


func _pct(a: PackedFloat32Array, q: float) -> float:
	return a[clampi(int(q * (a.size() - 1)), 0, a.size() - 1)] if a.size() > 0 else 0.0


func _log(text: String) -> void:
	print("[%6.1f s] %s" % [(Time.get_ticks_msec() - _t0) / 1000.0, text])


func _problem(text: String) -> void:
	_problems.append(text)
	_log("✗ PROBLEMA: " + text)


func _note(text: String) -> void:
	_notes.append(text)
	_log("· nota: " + text)


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _seconds(s: float) -> void:
	await create_timer(s).timeout


func _until(cond: Callable, timeout_ms: int = 5000) -> void:
	var start := Time.get_ticks_msec()
	while not cond.call() and Time.get_ticks_msec() - start < timeout_ms:
		await process_frame


# --- Celular simulado ------------------------------------------------------------------

## Un celular: ControllerClient real (el mismo de la app) y entrada a 30 por
## segundo con keepalive, como ControllerMain. "Dirigido": decide con el
## cerebro de los bots mirando el juego (como una persona mira la TV).
class PhoneSim extends Node:
	const SEND_RATE_HZ := 30.0
	const KEEPALIVE_SEC := 0.25

	var host: HostMain
	var client := ControllerClient.new()
	var nick := ""
	var look: Dictionary = {}
	var directed := true
	var active := true
	var frozen := false
	var layout := Protocol.LAYOUT_WAIT
	var layout_data: Dictionary = {}
	var standings: Array = []
	var rejects: Array[String] = []
	var feedbacks := 0
	var gave_up := false
	var _brain: Bot
	var _brain_game: Object
	var _send_elapsed := 0.0
	var _since_send := 0.0
	var _last_axis := Vector2(INF, INF)
	var _last_btn := -1
	var _t := 0.0
	var _rng := RandomNumberGenerator.new()
	var _wander := 0.0
	var _press_left := 0.0
	var _next_press := 1.0
	var _ready_at := -1.0

	func _ready() -> void:
		name = "Phone_" + nick
		add_child(client)
		_rng.randomize()
		client.layout_changed.connect(func(l: String, d: Dictionary) -> void:
			layout = l
			layout_data = d
			_brain = null
			_ready_at = _rng.randf_range(0.5, 3.0))
		client.standing_received.connect(func(s: Dictionary) -> void: standings.append(s))
		client.rejected.connect(func(r: String) -> void: rejects.append(r))
		client.feedback_received.connect(func(_k: String) -> void: feedbacks += 1)
		client.gave_up.connect(func() -> void: gave_up = true)

	func join(port: int, room: String) -> void:
		client.join("127.0.0.1", port, room, nick, look)

	func joined() -> bool:
		return active and client.state == ControllerClient.State.JOINED

	func player_id() -> int:
		return int(client.player_info.get("id", 0))

	func leave() -> void:
		client.leave()
		active = false

	## Cierra la app de golpe: el sistema cierra el socket sin "Salir".
	func kill_app() -> void:
		active = false
		client.queue_free()

	## Pantalla bloqueada: la app deja de correr. Con `drop`, además se corta
	## la conexión (el socket se cierra sin aviso de la app).
	func freeze(on: bool, drop: bool) -> void:
		frozen = on
		if on and drop:
			client._ws.close(1001, "")
			client._ws.poll()
		client.process_mode = Node.PROCESS_MODE_DISABLED if on else Node.PROCESS_MODE_INHERIT

	func _process(delta: float) -> void:
		if frozen or not joined():
			return
		_t += delta
		_send_elapsed += delta
		_since_send += delta
		if _send_elapsed < 1.0 / SEND_RATE_HZ or layout == Protocol.LAYOUT_WAIT:
			return
		var dt := _send_elapsed
		_send_elapsed = 0.0
		var out := _decide(dt)
		var axis: Vector2 = out.axis
		var btn: int = out.btn
		if axis != _last_axis or btn != _last_btn or _since_send >= KEEPALIVE_SEC:
			client.send_input(axis, btn)
			_last_axis = axis
			_last_btn = btn
			_since_send = 0.0

	func _decide(dt: float) -> Dictionary:
		var pid := player_id()
		var game: MiniGame = host._game if is_instance_valid(host._game) else null
		# Intro "¿Cómo se juega?": toca una vez para marcar "¡Listo!".
		if game == null:
			_ready_at -= dt
			return {"axis": Vector2.ZERO, "btn": Protocol.BTN_A if _ready_at <= 0.0 and _ready_at > -0.2 else 0}
		var helping := host.help.handles(pid)
		if directed:
			if _brain == null or _brain_game != game:
				var p := {}
				for pl in host.server.get_players():
					if int(pl.id) == pid:
						p = pl.duplicate()
				p["difficulty"] = Bot.Difficulty.NORMAL
				var id := str(game.get_info().id)
				_brain = BotDriver.create_bot(id, p, MiniGameRegistry.info(id))
				_brain_game = game
			var view := {"help": host.help.bot_view(pid)} if helping else game.bot_view()
			var o := _brain.tick(view, dt)
			var a: Vector2 = o.get("axis", Vector2.ZERO) if o.get("axis") is Vector2 else Vector2.ZERO
			return {"axis": a, "btn": int(o.get("btn", 0))}
		return _random_input(dt, str(game.get_info().id), helping)

	## Como alguien que juega sin mucha idea: joystick con vaivén, toques al azar.
	func _random_input(dt: float, game_id: String, helping: bool) -> Dictionary:
		_wander += _rng.randf_range(-2.5, 2.5) * dt
		var axis := Vector2.from_angle(_wander + _t * 0.7)
		var btn := 0
		_next_press -= dt
		_press_left -= dt
		if _next_press <= 0.0:
			_press_left = 0.12
			var fast := game_id == "tap_race" or game_id == "hurdles"
			_next_press = _rng.randf_range(0.12, 0.3) if fast else _rng.randf_range(0.8, 3.0)
		if _press_left > 0.0:
			btn = Protocol.BTN_A
		if helping:
			return {"axis": axis, "btn": btn}
		match layout:
			Protocol.LAYOUT_JOYSTICK:
				if game_id == "scroller":
					axis = Vector2(0.55, 0.7 * sin(_t * 1.3))  # Hacia la derecha, como se explica.
				return {"axis": axis, "btn": 0}
			Protocol.LAYOUT_SLIDER_H:
				return {"axis": Vector2(sin(_t * 1.7), 0.0), "btn": 0}
			Protocol.LAYOUT_ONE_BUTTON:
				return {"axis": Vector2.ZERO, "btn": btn}
			Protocol.LAYOUT_JOYSTICK_AB:
				return {"axis": axis, "btn": btn}
		return {"axis": Vector2.ZERO, "btn": 0}


# --- Proxy con demora -------------------------------------------------------------------

## Proxy TCP que demora cada pedazo de datos lag.x..lag.y ms en los dos
## sentidos, sin desordenar (como una Wi-Fi cargada: jitter, no pérdidas).
class LagProxy extends Node:
	var target_port := 0
	var lag := Vector2i(100, 300)
	var port := 0
	var _server := TCPServer.new()
	var _pairs: Array = []
	var _rng := RandomNumberGenerator.new()

	func start(p: int) -> Error:
		_rng.randomize()
		var err := _server.listen(p, "127.0.0.1")
		port = p
		return err

	func _process(_delta: float) -> void:
		while _server.is_connection_available():
			var a := _server.take_connection()
			var b := StreamPeerTCP.new()
			b.connect_to_host("127.0.0.1", target_port)
			_pairs.append({"a": a, "b": b, "to_b": [], "to_a": [], "rel_b": 0, "rel_a": 0})
		var now := Time.get_ticks_msec()
		for pair: Dictionary in _pairs.duplicate():
			var a: StreamPeerTCP = pair.a
			var b: StreamPeerTCP = pair.b
			a.poll()
			b.poll()
			var a_ok := a.get_status() == StreamPeerTCP.STATUS_CONNECTED
			var b_ok := b.get_status() == StreamPeerTCP.STATUS_CONNECTED
			var b_wait := b.get_status() == StreamPeerTCP.STATUS_CONNECTING
			if a_ok:
				_pump(pair, a, "to_b", "rel_b", now)
			if b_ok:
				_pump(pair, b, "to_a", "rel_a", now)
				_flush(pair.to_b, b, now)
			if a_ok:
				_flush(pair.to_a, a, now)
			# Un lado se cerró: se entrega lo pendiente y se cierra el otro.
			if (not a_ok and (pair.to_b as Array).is_empty() and not b_wait) or (not b_ok and not b_wait and (pair.to_a as Array).is_empty()):
				a.disconnect_from_host()
				b.disconnect_from_host()
				_pairs.erase(pair)

	func _pump(pair: Dictionary, s: StreamPeerTCP, queue: String, rel: String, now: int) -> void:
		var n := s.get_available_bytes()
		if n <= 0:
			return
		var r := s.get_partial_data(n)
		if r[0] != OK or (r[1] as PackedByteArray).is_empty():
			return
		var release := maxi(int(pair[rel]), now + _rng.randi_range(lag.x, lag.y))
		pair[rel] = release
		(pair[queue] as Array).append([release, r[1]])

	func _flush(queue: Array, s: StreamPeerTCP, now: int) -> void:
		while not queue.is_empty() and int(queue[0][0]) <= now:
			s.put_data(queue[0][1])
			queue.pop_front()
