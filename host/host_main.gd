class_name HostMain
extends Control
## Pantalla principal de la TV. Orquesta la sesión:
##   LOBBY  -> los jugadores se unen, alguien elige un juego con el control remoto
##   PLAYING -> corre el minijuego; los inputs de los celulares van al juego
##   RESULTS -> muestra el ganador unos segundos y vuelve al LOBBY
##
## Toda la UI se navega con el D-pad del control remoto (requisito de
## Google TV y Apple TV), no hace falta mouse ni pantalla táctil.

const RESULTS_SECONDS := 5.0

var server := HostServer.new()
var beacon := DiscoveryBeacon.new()
var phase := Protocol.PHASE_LOBBY

var _game: MiniGame
var _lobby: Control
var _results: Control
var _results_label: Label
var _code_label: Label
var _address_label: Label
var _status_label: Label
var _slot_labels: Array[Label] = []
var _game_buttons: Dictionary = {}  # game_id -> Button


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(server)
	add_child(beacon)
	server.player_joined.connect(func(_p: Dictionary) -> void: _refresh_lobby())
	server.player_reconnected.connect(func(_p: Dictionary) -> void: _refresh_lobby())
	server.player_disconnected.connect(_on_player_disconnected)
	server.player_left.connect(_on_player_left)
	server.input_received.connect(_on_input)

	_build_ui()
	var err := server.start()
	if err != OK:
		_status_label.text = "No se pudo abrir el puerto %d (error %d). ¿Otra instancia abierta?" % [Protocol.WS_PORT, err]
		return
	beacon.start(server.port, _device_name())
	_code_label.text = server.room_code
	_address_label.text = "IP: %s   ·   puerto %d" % [", ".join(_local_ipv4()), server.port]
	_refresh_lobby()


func _exit_tree() -> void:
	beacon.stop()
	server.stop()


# --- Flujo de la sesión -------------------------------------------------------

func start_game(game_id: String) -> void:
	if phase != Protocol.PHASE_LOBBY:
		return
	var players := server.get_players()
	var info := MiniGameRegistry.info(game_id)
	if info.is_empty() or not MiniGameRegistry.can_play(info, players.size()):
		return
	_game = MiniGameRegistry.create(game_id)
	_game.finished.connect(_on_game_finished)
	add_child(_game)
	_game.setup(players)
	_lobby.visible = false
	phase = Protocol.PHASE_PLAYING
	server.accepting_new_players = false
	server.set_phase(phase)
	server.set_layout(info.layout, info.layout_data)


func _on_game_finished(result: Dictionary) -> void:
	phase = Protocol.PHASE_RESULTS
	server.set_phase(phase)
	server.set_layout(Protocol.LAYOUT_WAIT)
	var names: Array[String] = []
	for pid: int in result.get("winners", []):
		for p in server.get_players():
			if p.id == pid:
				names.append(p.name)
	_results_label.text = "¡Ganó %s!\n%s" % [" y ".join(names) if not names.is_empty() else "nadie", result.get("summary", "")]
	_results.visible = true
	await get_tree().create_timer(RESULTS_SECONDS).timeout
	_back_to_lobby()


func _back_to_lobby() -> void:
	if is_instance_valid(_game):
		_game.queue_free()
	_game = null
	_results.visible = false
	_lobby.visible = true
	phase = Protocol.PHASE_LOBBY
	server.accepting_new_players = true
	server.set_phase(phase)
	server.set_layout(Protocol.LAYOUT_WAIT)
	_refresh_lobby()


func _on_input(player_id: int, input: Dictionary) -> void:
	if phase == Protocol.PHASE_PLAYING and is_instance_valid(_game):
		_game.on_input(player_id, input)


func _on_player_disconnected(player_id: int) -> void:
	if phase == Protocol.PHASE_PLAYING and is_instance_valid(_game):
		_game.on_player_disconnected(player_id)
	_refresh_lobby()


func _on_player_left(player_id: int) -> void:
	if phase == Protocol.PHASE_PLAYING and is_instance_valid(_game):
		_game.on_player_disconnected(player_id)
	_refresh_lobby()


func _unhandled_input(event: InputEvent) -> void:
	# "Atrás" del control remoto durante una partida: volver al lobby.
	if event.is_action_pressed("ui_cancel") and phase == Protocol.PHASE_PLAYING:
		_back_to_lobby()
		get_viewport().set_input_as_handled()


# --- UI -----------------------------------------------------------------------

func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.color = Color("#1b1b2f")
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	_lobby = VBoxContainer.new()
	_lobby.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_lobby.add_theme_constant_override("separation", 28)
	_lobby.alignment = BoxContainer.ALIGNMENT_CENTER
	add_child(_lobby)

	_lobby.add_child(_label("Party Games", 72))
	_lobby.add_child(_label("Abrí la app en tu celular, elegí esta TV e ingresá el código", 32, Color("#B4B2A9")))
	_code_label = _label("····", 160, Color("#FAC775"))
	_lobby.add_child(_code_label)
	_address_label = _label("", 26, Color("#888780"))
	_lobby.add_child(_address_label)

	var slots := HBoxContainer.new()
	slots.alignment = BoxContainer.ALIGNMENT_CENTER
	slots.add_theme_constant_override("separation", 40)
	_lobby.add_child(slots)
	for i in Protocol.MAX_PLAYERS:
		var l := _label("", 36)
		l.custom_minimum_size = Vector2(360, 90)
		slots.add_child(l)
		_slot_labels.append(l)

	var games := HBoxContainer.new()
	games.alignment = BoxContainer.ALIGNMENT_CENTER
	games.add_theme_constant_override("separation", 30)
	_lobby.add_child(games)
	for info in MiniGameRegistry.all_info():
		var b := Button.new()
		b.custom_minimum_size = Vector2(420, 120)
		b.add_theme_font_size_override("font_size", 34)
		b.pressed.connect(start_game.bind(info.id))
		games.add_child(b)
		_game_buttons[info.id] = b

	_status_label = _label("", 28, Color("#F09595"))
	_lobby.add_child(_status_label)

	_results = CenterContainer.new()
	_results.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_results.visible = false
	_results.z_index = 10
	var panel := PanelContainer.new()
	_results.add_child(panel)
	_results_label = _label("", 80)
	panel.add_child(_results_label)
	add_child(_results)


func _refresh_lobby() -> void:
	var players := server.get_players()
	for i in _slot_labels.size():
		var l := _slot_labels[i]
		var p: Dictionary = {}
		for candidate in players:
			if candidate.slot == i:
				p = candidate
		if p.is_empty():
			l.text = "Jugador %d\n(libre)" % (i + 1)
			l.add_theme_color_override("font_color", Color("#5F5E5A"))
		else:
			l.text = "%s%s" % [p.name, "" if p.connected else "\n(reconectando…)"]
			l.add_theme_color_override("font_color", p.color)

	var first_enabled: Button = null
	for info in MiniGameRegistry.all_info():
		var b: Button = _game_buttons[info.id]
		var ok := MiniGameRegistry.can_play(info, players.size())
		b.disabled = not ok
		var range_text := "%d" % info.min_players if info.min_players == info.max_players \
			else "%d–%d" % [info.min_players, info.max_players]
		b.text = "%s\n%s jugadores" % [info.title, range_text]
		if ok and first_enabled == null:
			first_enabled = b
	var focused := get_viewport().gui_get_focus_owner()
	if first_enabled and (focused == null or (focused is Button and (focused as Button).disabled)):
		first_enabled.grab_focus()


func _label(text: String, size: int, color: Color = Color.WHITE) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


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
