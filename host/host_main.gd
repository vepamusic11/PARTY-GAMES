class_name HostMain
extends Control
## Pantalla principal de la TV. Orquesta la sesión:
##   LOBBY   -> los jugadores se unen; se elige cuántos juegan y qué
##              minijuegos entran en la competencia
##   PLAYING -> primero la intro "¿Cómo se juega?" (los celulares ya muestran
##              el control, pero su input se ignora) y después el minijuego
##   RESULTS -> resumen de la ronda (puntos de cada jugador) y, al final,
##              el podio. Desde el podio se juega otra vez o se vuelve al lobby.
##
## Este script solo coordina: la lógica de puntos vive en Tournament y cada
## pantalla en host/ui/. Toda la UI se navega con el D-pad del control
## remoto (requisito de Google TV y Apple TV): no hace falta mouse ni táctil.
##
## Los cambios de pantalla pasan por `_go()`: un barrido de bloques
## (Transition) tapa la pantalla y el cambio ocurre recién ahí, en el orden
## en que se pidieron.
##
## Bots (ADR 0010): el lobby puede sumar jugadores virtuales en lugares
## libres (HostServer.add_bot). Durante el juego, BotDriver genera su
## entrada en cada paso de física y la pasa por el mismo camino que la de un
## celular (on_input). La pausa también los congela.

## Puerto y anuncio en la red configurables antes de agregarlo al árbol
## (los tests usan otro puerto y sin anuncio UDP).
var server_port := Protocol.WS_PORT
var announce := true
## Duración del barrido entre pantallas; 0 = cambio inmediato (tests).
var transition_seconds := Transition.DURATION
## Presentación "IO-GAMES presenta" al abrir. La pide app/boot.gd; los
## tests y las herramientas arrancan directo en el lobby.
var show_splash := false

const SETTINGS_PATH := "user://tv_settings.cfg"
## Mínimo entre dos avisos "feedback" al mismo celular: un juego no puede
## inundar la red aunque pida vibrar en cada frame.
const FEEDBACK_MIN_MS := 80
## Puertos consecutivos que prueba la TV si el habitual está ocupado.
const PORT_ATTEMPTS := 5

var server := HostServer.new()
var beacon := DiscoveryBeacon.new()
var bots := BotDriver.new()
## Ayuda de los eliminados (MODOS.md §11, ADR 0020): el que quedó afuera
## elige a quién ayudar y paga con puntos de la competencia.
var help := HelpSession.new()
var phase := Protocol.PHASE_LOBBY
var tournament: Tournament

var _game: MiniGame
var _background: PartyBackground
var _game_layer: Control
var _lobby: LobbyScreen
var _summary: RoundSummaryScreen
var _final: FinalScreen
var _intro: GameIntroScreen
var _pause: PauseMenu
var _transition: Transition
var _toasts: TvToasts  ## Avisos "se sumó / se desconectó / volvió".
var _help_overlay: TvHelpOverlay  ## A quién ayuda cada eliminado y el cartel "Tomi ayudó a Sofi · −10".
## Último "standing" enviado a cada jugador (player_id -> payload), para
## reenviarlo si el celular se reconecta durante el resumen o el podio.
var _standings_sent: Dictionary = {}
var _feedback_last_ms: Dictionary = {}  # player_id -> ticks del último aviso


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = UiTheme.build()
	Sfx.load_prefs(SETTINGS_PATH)
	UiTheme.load_effects_prefs(SETTINGS_PATH)
	AudioMix.load_prefs(SETTINGS_PATH)
	MusicStyles.load_prefs(SETTINGS_PATH)
	HelpSession.load_prefs(SETTINGS_PATH)
	add_child(Sfx.new())
	add_child(Music.new())
	Music.sync_mute()
	add_child(server)
	add_child(beacon)
	add_child(bots)
	add_child(help)
	bots.help = help
	bots.input_sink = _route_game_input
	help.layout_needed.connect(_send_help_layout)
	help.feedback.connect(_on_game_feedback)
	server.player_joined.connect(func(_p: Dictionary) -> void:
		Sfx.play("join")
		_refresh_lobby())
	server.player_reconnected.connect(_on_player_reconnected)
	server.player_disconnected.connect(_on_player_gone)
	server.player_left.connect(_on_player_gone)
	server.input_received.connect(_on_input)
	server.player_updated.connect(_on_player_updated)

	# Piezas 3D (estrellas, bloques, medallas…) horneadas a un atlas: de la
	# caché en disco al instante, o en unos cuadros la primera vez (ADR 0016).
	Props3DBaker.ensure(self)
	_build_ui()
	# Si el puerto está ocupado (otra app, u otra conexión que el sistema puso
	# justo ahí), prueba los siguientes: el lobby y el anuncio muestran el real.
	var err := ERR_CANT_CREATE
	for offset in PORT_ATTEMPTS:
		err = server.start(server_port + offset)
		if err == OK:
			break
	if err != OK:
		_lobby.set_status("No se pudo abrir el puerto %d (error %d). ¿Hay otra instancia abierta?" % [server_port, err])
		return
	if announce:
		beacon.start(server.port, _device_name())
	_lobby.set_room(server.room_code, "%s  ·  puerto %d" % [", ".join(_local_ipv4()), server.port])
	server.max_players = _lobby.player_count
	_refresh_lobby()
	_lobby.focus_default()
	if show_splash:
		var splash := SplashScreen.new()
		# Logo sonoro de IO-GAMES en la presentación y de PARTY-GAME al llegar al lobby.
		splash.finished.connect(func() -> void: Music.play("lobby", "party"))
		add_child(splash)
		Music.jingle("studio")
	else:
		Music.play("lobby", "party")


func _exit_tree() -> void:
	beacon.stop()
	server.stop()


# --- Flujo de la competencia ------------------------------------------------------

## Arranca una competencia con los juegos elegidos. Devuelve false si no se
## puede (fase incorrecta, sin jugadores o sin juegos válidos).
## La competencia se crea ya; la intro del primer juego aparece tras el barrido.
func start_tournament(game_ids: Array[String], shuffle: bool = false) -> bool:
	if phase != Protocol.PHASE_LOBBY or tournament != null:
		return false
	var players := server.get_players()
	if players.is_empty():
		return false
	var t := Tournament.new(game_ids, players, shuffle)
	if t.game_ids.is_empty():
		return false
	tournament = t
	server.accepting_new_players = false
	_go(_begin_tournament)
	return true


## Saltea la intro "¿Cómo se juega?" y arranca el juego (como apretar OK).
## Lo usan los tests y tools/capture_screens.gd.
func skip_intro() -> void:
	if _intro.visible:
		_intro.skip()


## Pide un cambio de pantalla: corre `fn` cuando el barrido tapa la pantalla.
func _go(fn: Callable) -> void:
	_transition.play(fn)


func _begin_tournament() -> void:
	if tournament == null or phase != Protocol.PHASE_LOBBY:
		return
	if server.get_players().is_empty():  # Se fueron todos durante el barrido.
		_back_to_lobby()
		return
	_lobby.visible = false
	_toasts.enabled = true
	_play_next()


## Pasa al siguiente juego: muestra su intro y ya manda el layout, así los
## celulares muestran el control mientras la gente lee cómo se juega.
func _play_next() -> void:
	if tournament == null:
		return
	_summary.hide_summary()
	_standings_sent.clear()
	var players := server.get_players()
	var id := tournament.advance(players.size())
	if id.is_empty():
		_show_final()
		return
	var info := MiniGameRegistry.info(id)
	_background.visible = true
	phase = Protocol.PHASE_PLAYING
	server.set_phase(phase)
	server.set_layout(info.layout, info.layout_data)
	Music.play(Music.track_for_game(id))
	_intro.show_intro(info, tournament.round_number(), tournament.total_rounds(), players)
	_prewarm_mascots(id, players)


## Termina la intro y arranca el minijuego en curso. Recién desde acá el
## input de los celulares llega al juego.
func _start_game() -> void:
	if phase != Protocol.PHASE_PLAYING or tournament == null or is_instance_valid(_game):
		return
	var id := tournament.current_game_id
	if id.is_empty():
		return
	_intro.hide_intro()
	_pause.close()
	var game := MiniGameRegistry.create(id)
	_game = game
	game.finished.connect(func(result: Dictionary) -> void: _go(_on_game_finished.bind(result, game)))
	game.feedback.connect(_on_game_feedback)
	_game_layer.add_child(game)
	game.setup(server.get_players())
	bots.start(game, game.players)
	help.start(game, tournament)
	_help_overlay.refresh()
	_background.visible = false  # El juego dibuja su propio fondo.


func _on_game_finished(result: Dictionary, game: MiniGame) -> void:
	if not is_instance_valid(_game) or game != _game or tournament == null:
		return
	var summary := tournament.record(result, _game.players)
	_end_game()
	_enter_results()
	_send_standings(summary.rows, summary.round, summary.total_rounds, false)
	Music.play("summary")
	var next_id := tournament.peek_next(server.get_players().size())
	_summary.show_summary(summary, tournament.standings(), str(MiniGameRegistry.info(next_id).get("title", "")))


func _show_final() -> void:
	_end_game()
	_summary.hide_summary()
	_enter_results()
	var titles: Array[String] = []
	for round_summary in tournament.history:
		titles.append(str(round_summary.title))
	_final.show_final(tournament.standings(), titles)
	Music.play("podium")
	if not tournament.history.is_empty():
		var played := tournament.history.size()
		_send_standings([], played, played, true)


## Manda a cada celular SU resultado: puesto y puntos de la ronda (si la
## jugó) y total y puesto en la tabla general. Solo datos propios: ni tokens
## ni puntajes de otros. Es informativo; el control no decide nada con esto.
## `round_rows` vacío = podio final (sin puesto de ronda).
func _send_standings(round_rows: Array, round_no: int, total_rounds: int, is_final: bool) -> void:
	_standings_sent.clear()
	var table := tournament.standings()
	var round_by_id := {}
	for row: Dictionary in round_rows:
		round_by_id[row.id] = row
	for s in table:
		var row: Dictionary = round_by_id.get(s.id, {})
		var payload := {
			"round": round_no,
			"total_rounds": total_rounds,
			"place": int(row.get("place", 0)),   # 0 = no jugó esta ronda
			"points": int(row.get("points", 0)),
			"total": int(s.total),
			"rank": int(s.place),
			"players": table.size(),
			"final": is_final,
		}
		_standings_sent[s.id] = payload
		server.send_to(s.id, Protocol.T_STANDING, payload)


func _enter_results() -> void:
	_background.visible = true
	phase = Protocol.PHASE_RESULTS
	server.set_phase(phase)
	server.set_layout(Protocol.LAYOUT_WAIT)


func _end_game() -> void:
	bots.stop()
	help.stop()
	_help_overlay.clear()
	_pause.close()
	_intro.hide_intro()
	if is_instance_valid(_game):
		_game.queue_free()
	_game = null


func _back_to_lobby() -> void:
	_end_game()
	tournament = null
	_standings_sent.clear()
	_summary.hide_summary()
	_final.hide_final()
	_background.visible = true
	_lobby.visible = true
	_toasts.enabled = false  # En el lobby lo muestran las tarjetas de los lugares.
	phase = Protocol.PHASE_LOBBY
	server.accepting_new_players = true
	server.set_phase(phase)
	server.set_layout(Protocol.LAYOUT_WAIT)
	_refresh_lobby()
	_lobby.focus_default()
	Music.play("lobby")


func _play_again() -> void:
	_back_to_lobby()
	if _lobby.can_start():
		start_tournament(_lobby.selected_game_ids(), _lobby.shuffle)


# --- Bots -------------------------------------------------------------------------

## Suma un bot en un lugar libre (solo en el lobby). slot -1 = el primero libre.
## Si "¿Cuántos juegan?" no alcanza, la sube (como cuando entra una persona).
func add_bot(difficulty: int = Bot.Difficulty.NORMAL, slot: int = -1) -> bool:
	if phase != Protocol.PHASE_LOBBY or tournament != null:
		return false
	if server.get_players().size() >= server.max_players and server.max_players < Protocol.MAX_PLAYERS:
		server.max_players += 1
	if server.add_bot(difficulty, slot).is_empty():
		Sfx.play("back")
		return false
	return true


func remove_bot(player_id: int) -> bool:
	if phase != Protocol.PHASE_LOBBY or tournament != null:
		return false
	return server.remove_bot(player_id)


func set_bot_difficulty(player_id: int, difficulty: int) -> bool:
	if phase != Protocol.PHASE_LOBBY or tournament != null:
		return false
	return server.set_bot_difficulty(player_id, difficulty)


# --- Pausa ------------------------------------------------------------------------

## Google TV / Android TV: el "Atrás" del control remoto no llega como tecla
## sino como pedido de "volver" de la ventana. Con `quit_on_go_back=false`
## (project.godot) no cierra la app: se convierte en `ui_cancel`, así hace
## exactamente lo mismo que Escape en la PC (pausa, cerrar la pregunta de
## salir, cerrar el menú de bots…).
func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST and is_inside_tree():
		for pressed in [true, false]:
			var back := InputEventAction.new()
			back.action = "ui_cancel"
			back.pressed = pressed
			Input.parse_input_event(back)


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("ui_cancel"):
		return
	if _pause.visible:
		_resume()
	elif phase == Protocol.PHASE_PLAYING and is_instance_valid(_game):
		_game.process_mode = Node.PROCESS_MODE_DISABLED
		Sfx.play("whoosh")
		_pause.open(str(MiniGameRegistry.info(tournament.current_game_id).get("title", "")), true)
	elif phase == Protocol.PHASE_PLAYING and _intro.visible:
		_intro.paused = true
		_pause.open(str(MiniGameRegistry.info(tournament.current_game_id).get("title", "")), true)
	elif phase == Protocol.PHASE_RESULTS and _summary.visible:
		_summary.paused = true
		Sfx.play("whoosh")
		_pause.open("Resumen de la ronda", false)
	else:
		return
	get_viewport().set_input_as_handled()


func _resume() -> void:
	_pause.close()
	if is_instance_valid(_game):
		_game.process_mode = Node.PROCESS_MODE_INHERIT
	if _intro.visible:
		_intro.paused = false
		_intro.focus_continue()
	if _summary.visible:
		_summary.paused = false
		_summary.focus_continue()


func _skip_game() -> void:
	if phase != Protocol.PHASE_PLAYING or tournament == null:
		return
	tournament.skip_current()
	_end_game()
	_background.visible = true
	_play_next()


func _quit_tournament() -> void:
	if tournament == null or tournament.history.is_empty():
		_back_to_lobby()
		return
	tournament.skip_current()
	_show_final()


# --- Red --------------------------------------------------------------------------

## Durante la intro todavía no hay juego: el input se descarta (solo marca
## "¡Listo!" en la intro).
func _on_input(player_id: int, input: Dictionary) -> void:
	if _intro.visible and not _pause.visible:
		_intro.on_player_input(player_id, input)
	if phase == Protocol.PHASE_PLAYING and is_instance_valid(_game) and not _pause.visible and not _intro.visible:
		_route_game_input(player_id, input)


## Entrada de un jugador durante el juego (celular o bot): si ya quedó afuera
## y tiene ayudas, va a la sesión de ayudas; si no, al juego.
func _route_game_input(player_id: int, input: Dictionary) -> void:
	if not is_instance_valid(_game):
		return
	help.poll()
	if help.handles(player_id):
		help.on_input(player_id, input)
	else:
		_game.on_input(player_id, input)


## Control del eliminado que ayuda (joystick_ab con el hint "Elegí a quién
## ayudar"), solo a su celular. Sin cambios de protocolo.
func _send_help_layout(player_id: int) -> void:
	var l := help.layout_for(player_id)
	server.send_to(player_id, Protocol.T_LAYOUT, {"layout": l[0], "data": l[1]})


## Si vuelve durante el resumen o el podio, recupera su resultado.
func _on_player_reconnected(player: Dictionary) -> void:
	if phase == Protocol.PHASE_RESULTS and _standings_sent.has(player.id):
		server.send_to(player.id, Protocol.T_STANDING, _standings_sent[player.id])
	if help.handles(player.id):
		_send_help_layout(player.id)  # Volvió siendo ayudante: su control, no el del juego.
	_refresh_lobby()


## Un jugador cambió su color o estilo desde el celular (solo pasa en el
## lobby: HostServer lo rechaza en otras fases). El lobby se redibuja con
## los datos nuevos (player.color, player.style).
func _on_player_updated(_player: Dictionary) -> void:
	_refresh_lobby()


## Desconexión temporal o salida definitiva: el juego recibe input neutro.
## Si no queda ninguna persona (solo bots, o nadie), se vuelve al lobby.
func _on_player_gone(player_id: int) -> void:
	Sfx.play("back")
	if phase == Protocol.PHASE_PLAYING and is_instance_valid(_game):
		_game.on_player_disconnected(player_id)
	if phase != Protocol.PHASE_LOBBY and server.get_human_count() == 0:
		_go(func() -> void:
			if phase != Protocol.PHASE_LOBBY and server.get_human_count() == 0:
				_back_to_lobby())
	_refresh_lobby()


## Reenvía al celular del jugador un pedido de vibración/sonido del juego.
func _on_game_feedback(player_id: int, kind: String) -> void:
	if not kind in Protocol.FEEDBACK_KINDS:
		return
	var now := Time.get_ticks_msec()
	if now - int(_feedback_last_ms.get(player_id, -FEEDBACK_MIN_MS)) < FEEDBACK_MIN_MS:
		return
	_feedback_last_ms[player_id] = now
	server.send_to(player_id, Protocol.T_FEEDBACK, {"kind": kind})


## Sonidos de navegación: mover el foco y confirmar. No consume el evento.
func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_accept"):
		var focused := get_viewport().gui_get_focus_owner()
		if focused is BaseButton:
			Sfx.play("back" if (focused as BaseButton).disabled else "select")


func _on_focus_changed(_control: Control) -> void:
	Sfx.play("tick")


func _toggle_sound() -> void:
	Sfx.muted = not Sfx.muted
	Sfx.save_prefs(SETTINGS_PATH)
	Music.sync_mute()
	_pause.set_sound_on(not Sfx.muted)
	Sfx.play("select")


func _toggle_motion() -> void:
	UiTheme.reduce_motion = not UiTheme.reduce_motion
	UiTheme.save_effects_prefs(SETTINGS_PATH)
	_pause.set_motion_reduced(UiTheme.reduce_motion)
	Sfx.play("select")


func _refresh_lobby() -> void:
	var players := server.get_players()
	_lobby.refresh(players)
	# Mascotas 3D (ADR 0012): hornea a los que llegan o cambian de look y
	# suelta a los que se fueron.
	var looks := players.map(MascotAtlas.look_of)
	looks.append({"color": Protocol.player_color(0), "style": 0})  # Mascota anfitriona del lobby.
	MascotAtlas.keep_only("tv", looks)
	MascotAtlas.prewarm_screens(players)


## Mientras se lee la intro "¿Cómo se juega?", hornea las mascotas al
## tamaño del juego (su MASCOT_SCALE, si lo declara), sus poses extra
## (MASCOT_PREWARM) y verifica las de pantalla: al arrancar el juego ya están.
func _prewarm_mascots(game_id: String, players: Array[Dictionary]) -> void:
	for script in MiniGameRegistry.GAMES:
		if script.call("get_info").id == game_id:
			script.call("prewarm_art", self)  # Ej. el escenario 2.5D horneado (ADR 0019).
	MascotAtlas.prewarm_game(players, MiniGameRegistry.mascot_scale(game_id), MiniGameRegistry.mascot_prewarm(game_id))


# --- UI ---------------------------------------------------------------------------

func _build_ui() -> void:
	_background = PartyBackground.new()
	add_child(_background)
	_game_layer = Control.new()
	_game_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_game_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_game_layer)

	_lobby = LobbyScreen.new()
	_lobby.start_requested.connect(start_tournament)
	_lobby.capacity_changed.connect(func(n: int) -> void: server.max_players = n)
	_lobby.bot_add_requested.connect(func(slot: int, difficulty: int) -> void: add_bot(difficulty, slot))
	_lobby.bot_remove_requested.connect(remove_bot)
	_lobby.bot_difficulty_requested.connect(set_bot_difficulty)
	_lobby.helps_toggled.connect(func(on: bool) -> void:
		HelpSession.enabled = on
		HelpSession.save_prefs(SETTINGS_PATH))
	add_child(_lobby)

	_help_overlay = TvHelpOverlay.new()
	add_child(_help_overlay)
	_help_overlay.watch(help)

	_intro = GameIntroScreen.new()
	_intro.continue_requested.connect(_go.bind(_start_game))
	add_child(_intro)

	_summary = RoundSummaryScreen.new()
	_summary.continue_requested.connect(_go.bind(_play_next))
	add_child(_summary)

	_final = FinalScreen.new()
	_final.play_again_requested.connect(_go.bind(_play_again))
	_final.lobby_requested.connect(_go.bind(_back_to_lobby))
	add_child(_final)

	_pause = PauseMenu.new()
	_pause.resume_requested.connect(_resume)
	_pause.skip_requested.connect(_go.bind(_skip_game))
	_pause.quit_requested.connect(_go.bind(_quit_tournament))
	_pause.sound_toggled.connect(_toggle_sound)
	_pause.motion_toggled.connect(_toggle_motion)
	add_child(_pause)
	_pause.set_sound_on(not Sfx.muted)
	_pause.set_motion_reduced(UiTheme.reduce_motion)
	get_viewport().gui_focus_changed.connect(_on_focus_changed)

	_toasts = TvToasts.new()
	_toasts.enabled = false  # Arranca en el lobby.
	add_child(_toasts)
	_toasts.watch(server)

	_transition = Transition.new()
	_transition.duration = transition_seconds
	add_child(_transition)


static func _local_ipv4() -> Array[String]:
	var out: Array[String] = []
	for ip in IP.get_local_addresses():
		if ip.contains(".") and not ip.begins_with("127.") and not ip.begins_with("169.254."):
			out.append(ip)
	if out.is_empty():
		out.append("sin red")
	return out


static func _device_name() -> String:
	var model := OS.get_model_name()
	return "TV %s" % model if model != "GenericDevice" else "PARTY-GAME TV"
