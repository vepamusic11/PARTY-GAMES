class_name LobbyScreen
extends Control
## Lobby de la TV: cómo unirse, quiénes están, cuántos juegan y qué
## minijuegos entran en la competencia.
##
##   ┌──────────────┬──────────────────────────────────────────────┐
##   │ [LOGO]       │ [1P Pablo] [2P Sofi] [3P  +  ] [4P —] [◀ 3 ▶] │
##   │ ¡Sumate!     │ 🎮 ¿A qué jugamos?              (6 de 7 elegidos)│
##   │ ① Abrí…      │ [Arena ✓] [Ping Pong 🔒] [Carrera ✓] [Reloj ✓] │
##   │ ② Elegí…     │ [Esquivar ✓] [Pintar ✓] [Empujones ✓]          │
##   │ ③ Escribí…   │                                                │
##   │ [K][7][Q][X] │ [⇅ Orden: como en la lista]     [▶ ¡A jugar!]  │
##   │ Wi-Fi: IP    │ ◀▶ Moverse   OK Elegir   ◀▶ Cambiar cantidad    │
##   │  (mascota)   │                                                │
##   └──────────────┴──────────────────────────────────────────────┘
##
## Maqueta de referencia: docs/design/lobby.md.
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
		tile.custom_minimum_size = Vector2(90, 112)
		tile.add_child(UiTheme.headline(code[i], 80))
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
		card.set_unavailable("" if ok else "Solo " + GameCard.players_text(card.info))
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
	# Mascota que se asoma abajo a la izquierda y saluda: la "anfitriona".
	# Va primero para quedar detrás de los paneles.
	var host_mascot := PlayerAvatar.new()
	host_mascot.color = Protocol.player_color(0)
	host_mascot.mood = PlayerAvatar.Mood.HAPPY
	host_mascot.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	host_mascot.offset_left = UiTheme.SAFE_MARGIN - 10
	host_mascot.offset_right = host_mascot.offset_left + 150
	host_mascot.offset_top = -218
	host_mascot.offset_bottom = -16
	add_child(host_mascot)
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


## Columna izquierda: cómo unirse, en tres pasos numerados.
func _build_join_column() -> Control:
	var col := VBoxContainer.new()
	col.custom_minimum_size = Vector2(480, 0)
	col.add_theme_constant_override("separation", 10)
	var logo := UiTheme.logo_rect()
	logo.custom_minimum_size = Vector2(0, 178)
	col.add_child(logo)

	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UiTheme.panel_style(UiTheme.PAPER, UiTheme.RADIUS + 8, 22))
	col.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	panel.add_child(box)
	var title := HBoxContainer.new()
	title.add_theme_constant_override("separation", 12)
	title.add_child(GlyphBadge.new("phone", UiTheme.BRICKS[5], UiTheme.PAPER, 60))
	title.add_child(UiTheme.label("¡Sumate desde tu celular!", 32, UiTheme.INK, true, HORIZONTAL_ALIGNMENT_LEFT))
	box.add_child(title)
	var steps := [
		[UiTheme.BRICKS[2], "Abrí PARTY-GAME en el celular"],
		[UiTheme.BRICKS[5], "Elegí esta TV de la lista"],
		[UiTheme.BRICKS[7], "Escribí tu apodo y este código:"],
	]
	for i in steps.size():
		box.add_child(_step_row(i + 1, steps[i][0], steps[i][1]))
	_code_box = HBoxContainer.new()
	_code_box.alignment = BoxContainer.ALIGNMENT_CENTER
	_code_box.add_theme_constant_override("separation", 12)
	_code_box.custom_minimum_size = Vector2(0, 124)
	box.add_child(_code_box)
	var help := HBoxContainer.new()
	help.add_theme_constant_override("separation", 12)
	help.add_child(GlyphBadge.new("wifi", Color.TRANSPARENT, UiTheme.BRICKS[5], 44))
	var help_text := VBoxContainer.new()
	help_text.add_theme_constant_override("separation", -4)
	help_text.add_child(UiTheme.label("¿No aparece la TV?", 24, UiTheme.INK, true, HORIZONTAL_ALIGNMENT_LEFT))
	help_text.add_child(UiTheme.label("Escribí esta dirección:", 24, UiTheme.INK_SOFT, false, HORIZONTAL_ALIGNMENT_LEFT))
	help.add_child(help_text)
	box.add_child(help)
	var address_box := PanelContainer.new()
	address_box.add_theme_stylebox_override("panel", UiTheme.panel_style(UiTheme.PAPER_DIM, 18, 10))
	box.add_child(address_box)
	_address = UiTheme.label("", 26, UiTheme.INK, true)
	_address.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	address_box.add_child(_address)
	_status = UiTheme.label("", 24, UiTheme.DANGER, true, HORIZONTAL_ALIGNMENT_LEFT)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.visible = false
	box.add_child(_status)
	return col


## Paso numerado: (①) texto, sobre una píldora clara.
func _step_row(n: int, color: Color, text: String) -> Control:
	var pill := PanelContainer.new()
	var style := UiTheme.panel_style(UiTheme.PAPER_DIM, 26, 6)
	style.content_margin_right = 14
	pill.add_theme_stylebox_override("panel", style)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	pill.add_child(row)
	row.add_child(GlyphBadge.new("", color, UiTheme.PAPER, 44, str(n)))
	var l := UiTheme.label(text, 24, UiTheme.INK, true, HORIZONTAL_ALIGNMENT_LEFT)
	l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	l.clip_text = true
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(l)
	return pill


## Columna derecha: A QUÉ se juega. Entran 3 filas de 4 tarjetas (12 juegos)
## sin tener que desplazarse.
func _build_setup_column() -> Control:
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 10)

	# Quiénes juegan: 4 lugares y, al final, cuántos.
	var seats := HBoxContainer.new()
	seats.add_theme_constant_override("separation", 16)
	col.add_child(seats)
	for i in Protocol.MAX_PLAYERS:
		var seat := SeatCard.new(i)
		seat.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		seats.add_child(seat)
		_seats.append(seat)
	_stepper = Stepper.new()
	_stepper.caption = "¿Cuántos juegan?"
	_stepper.value = player_count
	_stepper.custom_minimum_size = Vector2(0, 250)
	_stepper.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_stepper.value_changed.connect(_on_count_changed)
	seats.add_child(_stepper)

	var games_header := HBoxContainer.new()
	games_header.add_theme_constant_override("separation", 12)
	col.add_child(games_header)
	games_header.add_child(GlyphBadge.new("gamepad", UiTheme.BRICKS[5], UiTheme.PAPER, 58))
	var games_title := _section_title("¿A qué jugamos?")
	games_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	games_header.add_child(games_title)
	var pill := PanelContainer.new()
	var pill_style := UiTheme.panel_style(UiTheme.CHIP_DARK, 24, 8)
	pill_style.content_margin_left = 22
	pill_style.content_margin_right = 22
	pill.add_theme_stylebox_override("panel", pill_style)
	pill.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	games_header.add_child(pill)
	_selection = UiTheme.label("", 28, UiTheme.PAPER, true)
	pill.add_child(_selection)

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
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 16)
	grid.add_theme_constant_override("v_separation", 14)
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
	_shuffle_btn.custom_minimum_size = Vector2(380, 92)
	_shuffle_btn.add_theme_font_size_override("font_size", 30)
	_shuffle_btn.toggled.connect(func(on: bool) -> void:
		shuffle = on
		_shuffle_btn.text = "Orden: al azar" if on else "Orden: como en la lista")
	_shuffle_btn.text = "Orden: como en la lista"
	_with_icon(_shuffle_btn, GlyphBadge.new("order", Color.TRANSPARENT, UiTheme.INK, 40))
	actions.add_child(_shuffle_btn)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	actions.add_child(spacer)
	_start = Button.new()
	_start.custom_minimum_size = Vector2(520, 92)
	_start.add_theme_font_size_override("font_size", 36)
	_start.add_theme_stylebox_override("normal", UiTheme.button_style(UiTheme.ACCENT))
	_start.add_theme_stylebox_override("hover", UiTheme.button_style(UiTheme.ACCENT.lightened(0.1)))
	_start.add_theme_stylebox_override("pressed", UiTheme.button_style(UiTheme.ACCENT, true))
	_start.pressed.connect(_on_start_pressed)
	_with_icon(_start, GlyphBadge.new("play", Color.TRANSPARENT, UiTheme.INK, 44))
	actions.add_child(_start)

	var hints := KeyHint.new()
	hints.add_hint(["up", "down", "left", "right"], "Moverse") \
		.add_hint(["OK"], "Elegir / quitar juego") \
		.add_hint(["left", "right"], "Cambiar cantidad")
	col.add_child(hints)
	return col


## Ícono a la izquierda del texto del botón (dibujado, sin textura). El
## texto se corre a la derecha para no pisarlo.
func _with_icon(button: Button, icon: GlyphBadge) -> void:
	icon.set_anchors_and_offsets_preset(Control.PRESET_CENTER_LEFT)
	icon.offset_left = 26
	icon.offset_right = 26 + icon.custom_minimum_size.x
	icon.offset_top = -icon.custom_minimum_size.y / 2.0
	icon.offset_bottom = icon.custom_minimum_size.y / 2.0
	button.add_child(icon)
	# El estilo del tema recién se conoce dentro del árbol: se ajusta en ready.
	button.ready.connect(_make_room_for_icon.bind(button, icon), CONNECT_ONE_SHOT)


func _make_room_for_icon(button: Button, icon: GlyphBadge) -> void:
	for state in ["normal", "hover", "pressed", "disabled", "focus", "hover_pressed"]:
		var sb := button.get_theme_stylebox(state)
		if sb != null:
			sb = sb.duplicate()
			sb.content_margin_left += icon.custom_minimum_size.x + 12
			button.add_theme_stylebox_override(state, sb)


func _section_title(text: String, size: int = 44) -> Label:
	var l := UiTheme.headline(text, size)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	return l
