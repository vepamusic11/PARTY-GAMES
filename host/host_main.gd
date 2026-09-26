class_name HostMain
extends Control
## Pantalla principal de la TV. Orquesta la sesión:
##   LOBBY   -> los jugadores se unen; se elige cuántos juegan y qué
##              minijuegos entran en la competencia
##   PLAYING -> corre un minijuego de la competencia
##   RESULTS -> resumen de la ronda (puntos de cada jugador) y, al final,
##              el podio. Desde el podio se juega otra vez o se vuelve al lobby.
##
## Este script solo coordina: la lógica de puntos vive en Tournament y cada
## pantalla en host/ui/. Toda la UI se navega con el D-pad del control
## remoto (requisito de Google TV y Apple TV): no hace falta mouse ni táctil.

## Puerto y anuncio en la red configurables antes de agregarlo al árbol
## (los tests usan otro puerto y sin anuncio UDP).
var server_port := Protocol.WS_PORT
var announce := true

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
var _pause: PauseMenu


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = UiTheme.build()
	add_child(server)
	add_child(beacon)
	server.player_joined.connect(func(_p: Dictionary) -> void: _refresh_lobby())
	server.player_reconnected.connect(func(_p: Dictionary) -> void: _refresh_lobby())
	server.player_disconnected.connect(_on_player_gone)
	server.player_left.connect(_on_player_gone)
	server.input_received.connect(_on_input)

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


func _exit_tree() -> void:
	beacon.stop()
	server.stop()


# --- Flujo de la competencia ------------------------------------------------------

## Arranca una competencia con los juegos elegidos. Devuelve false si no se
## puede (fase incorrecta, sin jugadores o sin juegos válidos).
func start_tournament(game_ids: Array[String], shuffle: bool = false) -> bool:
	if phase != Protocol.PHASE_LOBBY:
		return false
	var players := server.get_players()
	if players.is_empty():
		return false
	var t := Tournament.new(game_ids, players, shuffle)
	if t.game_ids.is_empty():
		return false
	tournament = t
	server.accepting_new_players = false
	_lobby.visible = false
	_play_next()
	return true


func _play_next() -> void:
	_summary.hide_summary()
	var id := tournament.advance(server.get_players().size())
	if id.is_empty():
		_show_final()
		return
	var info := MiniGameRegistry.info(id)
	_game = MiniGameRegistry.create(id)
	_game.finished.connect(_on_game_finished)
	_game_layer.add_child(_game)
	_game.setup(server.get_players())
	_background.visible = false  # El juego dibuja su propio fondo.
	phase = Protocol.PHASE_PLAYING
	server.set_phase(phase)
	server.set_layout(info.layout, info.layout_data)


func _on_game_finished(result: Dictionary) -> void:
	if not is_instance_valid(_game) or tournament == null:
		return
	var summary := tournament.record(result, _game.players)
	_end_game()
	_enter_results()
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


func _enter_results() -> void:
	_background.visible = true
	phase = Protocol.PHASE_RESULTS
	server.set_phase(phase)
	server.set_layout(Protocol.LAYOUT_WAIT)


func _end_game() -> void:
	_pause.close()
	if is_instance_valid(_game):
		_game.queue_free()
	_game = null


func _back_to_lobby() -> void:
	_end_game()
	tournament = null
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
		_pause.open(str(MiniGameRegistry.info(tournament.current_game_id).get("title", "")), true)
	elif phase == Protocol.PHASE_RESULTS and _summary.visible:
		_summary.paused = true
		_pause.open("Resumen de la ronda", false)
	else:
		return
	get_viewport().set_input_as_handled()


func _resume() -> void:
	_pause.close()
	if is_instance_valid(_game):
		_game.process_mode = Node.PROCESS_MODE_INHERIT
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

func _on_input(player_id: int, input: Dictionary) -> void:
	if phase == Protocol.PHASE_PLAYING and is_instance_valid(_game) and not _pause.visible:
		_game.on_input(player_id, input)


## Desconexión temporal o salida definitiva: el juego recibe input neutro.
## Si no queda nadie, se vuelve al lobby.
func _on_player_gone(player_id: int) -> void:
	if phase == Protocol.PHASE_PLAYING and is_instance_valid(_game):
		_game.on_player_disconnected(player_id)
	if phase != Protocol.PHASE_LOBBY and server.get_players().is_empty():
		_back_to_lobby()
	_refresh_lobby()


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

	_summary = RoundSummaryScreen.new()
	_summary.continue_requested.connect(_play_next)
	add_child(_summary)

	_final = FinalScreen.new()
	_final.play_again_requested.connect(_play_again)
	_final.lobby_requested.connect(_back_to_lobby)
	add_child(_final)

	_pause = PauseMenu.new()
	_pause.resume_requested.connect(_resume)
	_pause.skip_requested.connect(_skip_game)
	_pause.quit_requested.connect(_quit_tournament)
	add_child(_pause)


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
	return "TV %s" % model if model != "GenericDevice" else "Party Games TV"
