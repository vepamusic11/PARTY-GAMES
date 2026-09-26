class_name LobbyScreen
extends Control
## Lobby de la TV: cómo unirse, quiénes están, cuántos juegan y qué
## minijuegos entran en la competencia.
##
##   ┌──────────────┬──────────────────────────────────────────┐
##   │ PARTY GAMES  │ ¿Cuántos juegan?          [◀ 3 jugadores ▶] │
##   │ ¡Sumate!     │ [1P Pablo] [2P Sofi] [3P Esperando] [4P —] │
##   │ 1. Abrí…     │ ¿A qué jugamos?               2 de 3 elegidos│
##   │ [K][7][Q][X] │ [Arena ✓] [Ping Pong] [Carrera ✓]           │
##   │ IP…          │ [Orden: de la lista]          [¡A jugar!]   │
##   └──────────────┴──────────────────────────────────────────┘
##
## Navegación con D-pad: ▲▼ entre filas, ◀▶ entre tarjetas o para cambiar
## la cantidad de jugadores, OK para marcar/desmarcar o empezar.

signal start_requested(game_ids: Array[String], shuffle: bool)
signal capacity_changed(count: int)

const DEFAULT_PLAYERS := 2

var player_count := DEFAULT_PLAYERS
var shuffle := false

var _players: Array[Dictionary] = []
var _cards: Dictionary = {}  # game_id -> GameCard
var _seats: Array[SeatCard] = []
var _stepper: Stepper
var _start: Button
var _shuffle_btn: Button
var _code_box: HBoxContainer
var _address: Label
var _status: Label
var _selection: Label


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build()
	refresh([])


# --- API ------------------------------------------------------------------------

func set_room(code: String, address: String) -> void:
	for c in _code_box.get_children():
		c.queue_free()
	for i in code.length():
		var tile := PanelContainer.new()
		var style := UiTheme.panel_style(UiTheme.BRICKS[(i * 2 + 1) % UiTheme.BRICKS.size()], 20, 6)
		style.border_width_bottom = 8
		style.border_color = style.bg_color.darkened(0.25)
		tile.add_theme_stylebox_override("panel", style)
		tile.custom_minimum_size = Vector2(96, 124)
		tile.add_child(UiTheme.headline(code[i], 86))
		_code_box.add_child(tile)
	_address.text = address


func set_status(message: String) -> void:
	_status.text = message
	_status.visible = not message.is_empty()


## players: HostServer.get_players(). Se llama cada vez que alguien entra,
## sale o se reconecta.
func refresh(players: Array[Dictionary]) -> void:
	_players = players
	_stepper.set_range(maxi(1, players.size()), Protocol.MAX_PLAYERS)
	player_count = _stepper.value
	for i in _seats.size():
		var p: Dictionary = {}
		for candidate in players:
			if candidate.slot == i:
				p = candidate
		_seats[i].show_player(p, i >= player_count and p.is_empty())
	for id: String in _cards:
		var card: GameCard = _cards[id]
		var ok := MiniGameRegistry.can_play(card.info, player_count)
		card.set_unavailable("" if ok else "Solo para " + GameCard.players_text(card.info))
	_update_start()


func selected_game_ids() -> Array[String]:
	var ids: Array[String] = []
	for info in MiniGameRegistry.all_info():
		var card: GameCard = _cards[info.id]
		if card.is_selected():
			ids.append(info.id)
	return ids


func can_start() -> bool:
	return _missing_players() == 0 and not selected_game_ids().is_empty()


## Pone el foco donde tiene sentido si nada lo tiene (al volver al lobby).
func focus_default() -> void:
	var focused := get_viewport().gui_get_focus_owner() if is_inside_tree() else null
	if focused != null and is_ancestor_of(focused) and focused.is_visible_in_tree():
		return
	if can_start():
		_start.grab_focus()
	else:
		_stepper.grab_focus()


# --- Lógica interna ---------------------------------------------------------------

func _missing_players() -> int:
	return maxi(0, player_count - _players.size())


func _update_start() -> void:
	var ids := selected_game_ids()
	var missing := _missing_players()
	_selection.text = "%d de %d elegidos" % [ids.size(), _cards.size()]
	if missing > 0:
		_start.text = "Esperando %d jugador%s…" % [missing, "" if missing == 1 else "es"]
	elif ids.is_empty():
		_start.text = "Elegí al menos un juego"
	else:
		_start.text = "¡A jugar!  ·  %d juego%s" % [ids.size(), "" if ids.size() == 1 else "s"]
	_start.disabled = missing > 0 or ids.is_empty()


func _on_count_changed(value: int) -> void:
	player_count = value
	capacity_changed.emit(value)
	refresh(_players)


func _on_start_pressed() -> void:
	if can_start():
		start_requested.emit(selected_game_ids(), shuffle)


# --- UI -------------------------------------------------------------------------

func _build() -> void:
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, UiTheme.SAFE_MARGIN)
	margin.add_theme_constant_override("margin_top", UiTheme.SAFE_MARGIN - 8)
	add_child(margin)
	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 40)
	margin.add_child(columns)
	columns.add_child(_build_join_column())
	columns.add_child(_build_setup_column())


func _build_join_column() -> Control:
	var col := VBoxContainer.new()
	col.custom_minimum_size = Vector2(500, 0)
	col.add_theme_constant_override("separation", 22)
	col.add_child(_logo())

	var panel := PanelContainer.new()
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 18)
	panel.add_child(box)
	box.add_child(UiTheme.label("¡Sumate desde tu celular!", 38, UiTheme.INK, true, HORIZONTAL_ALIGNMENT_LEFT))
	var steps := ["Abrí Party Games en el celular", "Elegí esta TV de la lista", "Escribí tu apodo y este código:"]
	for i in steps.size():
		box.add_child(_step_row(i + 1, steps[i]))
	_code_box = HBoxContainer.new()
	_code_box.alignment = BoxContainer.ALIGNMENT_CENTER
	_code_box.add_theme_constant_override("separation", 14)
	_code_box.custom_minimum_size = Vector2(0, 150)
	box.add_child(_code_box)
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(spacer)
	box.add_child(UiTheme.label("¿No aparece la TV? Escribí esta dirección:", 24, UiTheme.INK_SOFT, false, HORIZONTAL_ALIGNMENT_LEFT))
	_address = UiTheme.label("", 28, UiTheme.INK, true, HORIZONTAL_ALIGNMENT_LEFT)
	_address.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_address)
	_status = UiTheme.label("", 26, UiTheme.DANGER, true, HORIZONTAL_ALIGNMENT_LEFT)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.visible = false
	box.add_child(_status)
	return col


func _build_setup_column() -> Control:
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 18)

	var players_header := HBoxContainer.new()
	players_header.add_theme_constant_override("separation", 24)
	col.add_child(players_header)
	var players_title := _section_title("¿Cuántos juegan?")
	players_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	players_header.add_child(players_title)
	_stepper = Stepper.new()
	_stepper.value = player_count
	_stepper.value_changed.connect(_on_count_changed)
	players_header.add_child(_stepper)

	var seats := HBoxContainer.new()
	seats.add_theme_constant_override("separation", 20)
	col.add_child(seats)
	for i in Protocol.MAX_PLAYERS:
		var seat := SeatCard.new(i)
		seat.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		seats.add_child(seat)
		_seats.append(seat)

	var games_header := HBoxContainer.new()
	col.add_child(games_header)
	var games_title := _section_title("¿A qué jugamos?")
	games_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	games_header.add_child(games_title)
	_selection = UiTheme.label("", 28, UiTheme.INK, true, HORIZONTAL_ALIGNMENT_RIGHT)
	_selection.add_theme_constant_override("outline_size", 8)
	_selection.add_theme_color_override("font_outline_color", UiTheme.PAPER)
	games_header.add_child(_selection)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	col.add_child(scroll)
	var pad := MarginContainer.new()  # Espacio para el anillo de foco y el zoom.
	pad.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for side in ["left", "right", "top", "bottom"]:
		pad.add_theme_constant_override("margin_" + side, 16)
	scroll.add_child(pad)
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 18)
	grid.add_theme_constant_override("v_separation", 18)
	pad.add_child(grid)
	for info in MiniGameRegistry.all_info():
		var card := GameCard.new(info)
		card.button_pressed = true  # Por defecto entran todos.
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		card.toggled.connect(func(_on: bool) -> void: _update_start())
		grid.add_child(card)
		_cards[info.id] = card

	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 24)
	col.add_child(actions)
	_shuffle_btn = Button.new()
	_shuffle_btn.toggle_mode = true
	_shuffle_btn.custom_minimum_size = Vector2(380, 96)
	_shuffle_btn.add_theme_font_size_override("font_size", 30)
	_shuffle_btn.toggled.connect(func(on: bool) -> void:
		shuffle = on
		_shuffle_btn.text = "Orden: al azar" if on else "Orden: como en la lista")
	_shuffle_btn.text = "Orden: como en la lista"
	actions.add_child(_shuffle_btn)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	actions.add_child(spacer)
	_start = Button.new()
	_start.custom_minimum_size = Vector2(520, 96)
	_start.add_theme_font_size_override("font_size", 36)
	_start.add_theme_stylebox_override("normal", UiTheme.button_style(UiTheme.ACCENT))
	_start.add_theme_stylebox_override("hover", UiTheme.button_style(UiTheme.ACCENT.lightened(0.1)))
	_start.add_theme_stylebox_override("pressed", UiTheme.button_style(UiTheme.ACCENT, true))
	_start.pressed.connect(_on_start_pressed)
	actions.add_child(_start)

	var hints := KeyHint.new()
	hints.add_hint(["up", "down", "left", "right"], "Moverse") \
		.add_hint(["OK"], "Elegir / quitar juego") \
		.add_hint(["left", "right"], "Cambiar cantidad")
	col.add_child(hints)
	return col


func _logo() -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 0)
	row.custom_minimum_size = Vector2(0, 110)
	var i := 0
	for ch in "PARTY GAMES":
		if ch == " ":
			var gap := Control.new()
			gap.custom_minimum_size = Vector2(26, 0)
			row.add_child(gap)
			continue
		var l := UiTheme.headline(ch, 84, UiTheme.BRICKS[i % UiTheme.BRICKS.size()], UiTheme.PAPER)
		l.add_theme_color_override("font_shadow_color", UiTheme.INK)
		row.add_child(l)
		i += 1
	return row


func _section_title(text: String) -> Label:
	var l := UiTheme.headline(text, 44)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	return l


func _step_row(n: int, text: String) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	var badge := PanelContainer.new()
	var style := UiTheme.panel_style(UiTheme.ACCENT, 26, 0)
	style.shadow_size = 0
	badge.add_theme_stylebox_override("panel", style)
	badge.custom_minimum_size = Vector2(52, 52)
	badge.add_child(UiTheme.label(str(n), 30, UiTheme.INK, true))
	row.add_child(badge)
	var l := UiTheme.label(text, 28, UiTheme.INK, false, HORIZONTAL_ALIGNMENT_LEFT)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(l)
	return row
