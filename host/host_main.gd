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

var server := HostServer.new()
var beacon := DiscoveryBeacon.new()
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
## Último "standing" enviado a cada jugador (player_id -> payload), para
## reenviarlo si el celular se reconecta durante el resumen o el podio.
var _standings_sent: Dictionary = {}
var _feedback_last_ms: Dictionary = {}  # player_id -> ticks del último aviso


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = UiTheme.build()
	Sfx.load_prefs(SETTINGS_PATH)
	add_child(Sfx.new())
	add_child(server)
	add_child(beacon)
	server.player_joined.connect(func(_p: Dictionary) -> void:
		Sfx.play("join")
		_refresh_lobby())
	server.player_reconnected.connect(_on_player_reconnected)
	server.player_disconnected.connect(_on_player_gone)
	server.player_left.connect(_on_player_gone)
	server.input_received.connect(_on_input)
	server.player_updated.connect(_on_player_updated)

	_build_ui()
	var err := server.start(server_port)
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
		add_child(SplashScreen.new())


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
	_intro.show_intro(info, tournament.round_number(), tournament.total_rounds(), players)


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
	_background.visible = false  # El juego dibuja su propio fondo.


func _on_game_finished(result: Dictionary, game: MiniGame) -> void:
	if not is_instance_valid(_game) or game != _game or tournament == null:
		return
	var summary := tournament.record(result, _game.players)
	_end_game()
	_enter_results()
	_send_standings(summary.rows, summary.round, summary.total_rounds, false)
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
	phase = Protocol.PHASE_LOBBY
	server.accepting_new_players = true
	server.set_phase(phase)
	server.set_layout(Protocol.LAYOUT_WAIT)
	_refresh_lobby()
	_lobby.focus_default()


func _play_again() -> void:
	_back_to_lobby()
	if _lobby.can_start():
		start_tournament(_lobby.selected_game_ids(), _lobby.shuffle)


# --- Pausa ------------------------------------------------------------------------

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

## Durante la intro todavía no hay juego: el input se descarta.
func _on_input(player_id: int, input: Dictionary) -> void:
	if phase == Protocol.PHASE_PLAYING and is_instance_valid(_game) and not _pause.visible and not _intro.visible:
		_game.on_input(player_id, input)


## Si vuelve durante el resumen o el podio, recupera su resultado.
func _on_player_reconnected(player: Dictionary) -> void:
	if phase == Protocol.PHASE_RESULTS and _standings_sent.has(player.id):
		server.send_to(player.id, Protocol.T_STANDING, _standings_sent[player.id])
	_refresh_lobby()


## Un jugador cambió su color o estilo desde el celular (solo pasa en el
## lobby: HostServer lo rechaza en otras fases). El lobby se redibuja con
## los datos nuevos (player.color, player.style).
func _on_player_updated(_player: Dictionary) -> void:
	_refresh_lobby()


## Desconexión temporal o salida definitiva: el juego recibe input neutro.
## Si no queda nadie, se vuelve al lobby.
func _on_player_gone(player_id: int) -> void:
	Sfx.play("back")
	if phase == Protocol.PHASE_PLAYING and is_instance_valid(_game):
		_game.on_player_disconnected(player_id)
	if phase != Protocol.PHASE_LOBBY and server.get_players().is_empty():
		_go(func() -> void:
			if phase != Protocol.PHASE_LOBBY and server.get_players().is_empty():
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
	_pause.set_sound_on(not Sfx.muted)
	Sfx.play("select")


func _refresh_lobby() -> void:
	_lobby.refresh(server.get_players())


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
	add_child(_lobby)

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
	add_child(_pause)
	_pause.set_sound_on(not Sfx.muted)
	get_viewport().gui_focus_changed.connect(_on_focus_changed)

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
