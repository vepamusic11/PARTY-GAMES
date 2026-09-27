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
##
## Bots (ADR 0010): los lugares libres y los que tienen un bot también se
## eligen con el D-pad. OK abre BotMenu: elegir la dificultad suma un bot
## (o la cambia) y "Quitar bot" lo saca. Así juega una persona sola contra
## bots, o se completa la mesa (2 personas + 2 bots). El lobby solo pide:
## HostMain le pasa el pedido a HostServer.

signal start_requested(game_ids: Array[String], shuffle: bool)
signal capacity_changed(count: int)
signal bot_add_requested(slot: int, difficulty: int)
signal bot_remove_requested(player_id: int)
signal bot_difficulty_requested(player_id: int, difficulty: int)

const DEFAULT_PLAYERS := 2
const JOIN_WIDTH := 508          ## Columna "¡Sumate!" (entran los pasos en letra grande).
const COLUMN_GAP := 30
const CODE_TILE := Vector2(100, 128)
const CODE_GAP := 14
const STEP_FONT := 26
const START_SIZE := Vector2(580, 104)
const SHUFFLE_SIZE := Vector2(420, 88)

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
var _bot_menu: BotMenu
var _menu_slot := -1  # lugar cuyo menú de bot está abierto


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build()
	refresh([])


# --- API ------------------------------------------------------------------------

func set_room(code: String, address: String) -> void:
	for c in _code_box.get_children():
		c.queue_free()
	for i in code.length():
		var tile := _CodeTile.new()
		tile.letter = code[i]
		tile.color = UiTheme.BRICKS[(i * 2 + 1) % UiTheme.BRICKS.size()]
		tile.custom_minimum_size = CODE_TILE
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
		var p := _player_in_slot(i)
		var locked := i >= player_count and p.is_empty()
		_seats[i].show_player(p, locked)
		# Lugar libre o con bot: se elige con el D-pad para sumar/cambiar un bot.
		_seats[i].selectable = (p.is_empty() and not locked) or bool(p.get("bot", false))
	for id: String in _cards:
		var card: GameCard = _cards[id]
		var ok := MiniGameRegistry.can_play(card.info, player_count)
		card.set_unavailable("" if ok else "Solo " + GameCard.players_text(card.info))
	_update_start()
	# Si el lugar con foco dejó de ser elegible (entró una persona), el foco
	# vuelve a un lugar con sentido. Solo con el lobby a la vista.
	if is_inside_tree() and is_visible_in_tree() and not _bot_menu.visible:
		focus_default()


## Abre el menú de bots del lugar `slot` (OK sobre su tarjeta).
func open_bot_menu(slot: int) -> void:
	var p := _player_in_slot(slot)
	var has_bot := bool(p.get("bot", false))
	if not p.is_empty() and not has_bot:
		return  # Una persona: no se toca.
	_menu_slot = slot
	_bot_menu.open(slot, has_bot, int(p.get("difficulty", Bot.Difficulty.NORMAL)),
		p.get("color", Protocol.player_color(slot)))


func is_bot_menu_open() -> bool:
	return _bot_menu.visible


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

func _player_in_slot(slot: int) -> Dictionary:
	for p in _players:
		if p.slot == slot:
			return p
	return {}


func _on_bot_difficulty(difficulty: int) -> void:
	var p := _player_in_slot(_menu_slot)
	if p.is_empty():
		bot_add_requested.emit(_menu_slot, difficulty)
	elif p.get("bot", false):
		bot_difficulty_requested.emit(p.id, difficulty)


func _on_bot_remove() -> void:
	var p := _player_in_slot(_menu_slot)
	if p.get("bot", false):
		bot_remove_requested.emit(p.id)


## Al cerrar el menú, el foco vuelve a la tarjeta del lugar (si sigue
## siendo elegible) o a donde tenga sentido.
func _on_bot_menu_closed() -> void:
	var slot := _menu_slot
	_menu_slot = -1
	(func() -> void:
		if slot >= 0 and _seats[slot].selectable and is_visible_in_tree():
			_seats[slot].grab_focus()
		else:
			focus_default()).call_deferred()


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
	# Mascota anfitriona: grande, abajo a la izquierda, asomándose desde
	# afuera de la pantalla. Va primero para quedar detrás de los paneles
	# (nunca tapa información).
	var host_mascot := PlayerAvatar.new()
	host_mascot.color = Protocol.player_color(0)
	host_mascot.mood = PlayerAvatar.Mood.HAPPY
	host_mascot.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	host_mascot.offset_left = -24
	host_mascot.offset_right = host_mascot.offset_left + 250
	host_mascot.offset_top = -270
	host_mascot.offset_bottom = 60
	add_child(host_mascot)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, UiTheme.SAFE_MARGIN)
	margin.add_theme_constant_override("margin_top", UiTheme.SAFE_MARGIN - 8)
	add_child(margin)
	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", COLUMN_GAP)
	margin.add_child(columns)
	columns.add_child(_build_join_column())
	columns.add_child(_build_setup_column())
	_bot_menu = BotMenu.new()
	_bot_menu.difficulty_chosen.connect(_on_bot_difficulty)
	_bot_menu.remove_requested.connect(_on_bot_remove)
	_bot_menu.closed.connect(_on_bot_menu_closed)
	add_child(_bot_menu)


## Columna izquierda: cómo unirse, en tres pasos numerados.
func _build_join_column() -> Control:
	var col := VBoxContainer.new()
	col.custom_minimum_size = Vector2(JOIN_WIDTH, 0)
	col.add_theme_constant_override("separation", 6)
	var logo := UiTheme.logo_rect()
	logo.custom_minimum_size = Vector2(0, 170)
	col.add_child(logo)

	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UiTheme.panel_style(UiTheme.PAPER, UiTheme.RADIUS + 8, 18))
	col.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	panel.add_child(box)
	var title := HBoxContainer.new()
	title.add_theme_constant_override("separation", 12)
	title.add_child(GlyphBadge.new("phone", UiTheme.BRICKS[5], UiTheme.PAPER, 66))
	title.add_child(UiTheme.label("¡Sumate desde tu celular!", 34, UiTheme.INK, true, HORIZONTAL_ALIGNMENT_LEFT))
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
	_code_box.add_theme_constant_override("separation", CODE_GAP)
	_code_box.custom_minimum_size = Vector2(0, CODE_TILE.y + 6)
	box.add_child(_code_box)
	var help := HBoxContainer.new()
	help.add_theme_constant_override("separation", 12)
	help.add_child(GlyphBadge.new("wifi", UiTheme.BRICKS[4], UiTheme.PAPER, 54))
	var help_text := VBoxContainer.new()
	help_text.add_theme_constant_override("separation", -6)
	help_text.add_child(UiTheme.label("¿No aparece la TV?", 26, UiTheme.INK, true, HORIZONTAL_ALIGNMENT_LEFT))
	help_text.add_child(UiTheme.label("Escribí esta dirección:", 24, UiTheme.INK_SOFT, true, HORIZONTAL_ALIGNMENT_LEFT))
	help.add_child(help_text)
	box.add_child(help)
	var address_box := PanelContainer.new()
	var address_style := UiTheme.chip_style(UiTheme.PAPER_DIM, 20, 10, Color(UiTheme.INK_SOFT, 0.25))
	address_style.shadow_size = 0
	address_box.add_theme_stylebox_override("panel", address_style)
	box.add_child(address_box)
	_address = UiTheme.label("", 28, UiTheme.INK, true)
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
	var style := UiTheme.panel_style(UiTheme.PAPER_DIM, 32, 5)
	style.content_margin_right = 12
	style.shadow_size = 0
	pill.add_theme_stylebox_override("panel", style)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	pill.add_child(row)
	row.add_child(GlyphBadge.new("", color, UiTheme.PAPER, 54, str(n)))
	var l := UiTheme.label(text, STEP_FONT, UiTheme.INK, true, HORIZONTAL_ALIGNMENT_LEFT)
	l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	l.clip_text = true
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(l)
	return pill


## Columna derecha: A QUÉ se juega. Con 7 juegos entra todo sin desplazar;
## con más, la grilla se desplaza sola siguiendo el foco.
func _build_setup_column() -> Control:
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 6)

	# Quiénes juegan: 4 lugares y, al final, cuántos.
	var seats := HBoxContainer.new()
	seats.add_theme_constant_override("separation", 14)
	col.add_child(seats)
	for i in Protocol.MAX_PLAYERS:
		var seat := SeatCard.new(i)
		seat.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		seat.activated.connect(open_bot_menu)
		seats.add_child(seat)
		_seats.append(seat)
	_stepper = Stepper.new()
	_stepper.caption = "¿Cuántos juegan?"
	_stepper.inset_top = SeatCard.OVERHANG - 2.0
	_stepper.value = player_count
	_stepper.custom_minimum_size = Vector2(0, SeatCard.TALL_HEIGHT)
	_stepper.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_stepper.value_changed.connect(_on_count_changed)
	seats.add_child(_stepper)

	var games_header := HBoxContainer.new()
	games_header.add_theme_constant_override("separation", 14)
	col.add_child(games_header)
	games_header.add_child(GlyphBadge.new("gamepad", UiTheme.BRICKS[6], UiTheme.PAPER, 64))
	var games_title := _section_title("¿A qué jugamos?")
	games_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	games_header.add_child(games_title)
	var pill := PanelContainer.new()
	pill.add_theme_stylebox_override("panel", UiTheme.chip_style(UiTheme.CHIP_DARK, 24, 6))
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
		pad.add_theme_constant_override("margin_" + side, 10 if side in ["left", "right"] else 12)
	scroll.add_child(pad)
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 14)
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
	_shuffle_btn = _BrightButton.new(UiTheme.PAPER, 30, "order")
	_shuffle_btn.toggle_mode = true
	_shuffle_btn.custom_minimum_size = SHUFFLE_SIZE
	_shuffle_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_shuffle_btn.toggled.connect(func(on: bool) -> void:
		shuffle = on
		_shuffle_btn.text = "Orden: al azar" if on else "Orden: como en la lista")
	_shuffle_btn.text = "Orden: como en la lista"
	actions.add_child(_shuffle_btn)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	actions.add_child(spacer)
	_start = _BrightButton.new(UiTheme.ACCENT, 38, "play", true)
	_start.custom_minimum_size = START_SIZE
	_start.pressed.connect(_on_start_pressed)
	actions.add_child(_start)

	var hints := KeyHint.new()
	hints.add_hint(["up", "down", "left", "right"], "Moverse") \
		.add_hint(["OK"], "Elegir juego · sumar bot") \
		.add_hint(["left", "right"], "Cambiar cantidad")
	col.add_child(hints)
	return col


func _section_title(text: String, size: int = 50) -> Label:
	var l := UiTheme.headline(text, size)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	return l


## Ficha del código de sala: bloque de juguete con bisel (luz arriba, labio
## oscuro abajo, contorno) y la letra blanca con contorno, como el logo.
class _CodeTile:
	extends Control
	var letter := ""
	var color := UiTheme.ACCENT

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var o := UiTheme.BEVEL_OUTLINE
		var body := Rect2(Vector2(o, o), size - Vector2(o * 2.0, o * 2.0 + UiTheme.BEVEL_DEPTH))
		UiTheme.draw_bevel(self, body, color, 22.0)
		var c := body.get_center() + Vector2(0, 2)
		var font_size := int(body.size.y * 0.72)
		UiTheme.draw_text(self, letter, c + Vector2(0, 5), font_size, UiTheme.INK, 10, UiTheme.INK)
		UiTheme.draw_text(self, letter, c, font_size, UiTheme.PAPER, 10, UiTheme.INK)


## Botón del lobby dibujado a mano: píldora con bisel brillante, ícono y
## texto. El principal (¡A jugar!) es amarillo y, con foco, tira destellos
## animados alrededor. El texto se dibuja acá (la fuente del tema queda
## transparente) para que vaya encima del bisel.
##
## Rendimiento: el botón se dibuja solo cuando cambia (texto, foco, apretado).
## Los destellos van en una capa aparte (`_Sparkles`) que no se redibuja al
## animarse, y solo corre mientras el botón tiene el foco.
class _BrightButton:
	extends Button
	var base := UiTheme.PAPER
	var glyph := ""
	var font_px := 30
	var _sparkles: _Sparkles

	func _init(p_base: Color, p_font_px: int, p_glyph: String, p_sparkles: bool = false) -> void:
		base = p_base
		font_px = p_font_px
		glyph = p_glyph
		focus_mode = Control.FOCUS_ALL
		add_theme_font_override("font", UiTheme.FONT_BOLD)
		add_theme_font_size_override("font_size", font_px)
		for st in ["normal", "hover", "pressed", "disabled", "focus", "hover_pressed"]:
			add_theme_stylebox_override(st, StyleBoxEmpty.new())
		for key in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color",
				"font_hover_pressed_color", "font_disabled_color"]:
			add_theme_color_override(key, Color(UiTheme.INK, 0.0))
		focus_entered.connect(_on_state_changed)
		focus_exited.connect(_on_state_changed)
		if p_sparkles:
			_sparkles = _Sparkles.new()
			_sparkles.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			add_child(_sparkles)

	func _ready() -> void:
		_on_state_changed()

	func _notification(what: int) -> void:
		# `disabled` cambia sin señal: se revisa al redibujar el botón.
		if what == NOTIFICATION_DRAW and _sparkles != null:
			_sparkles.set_running.call_deferred(has_focus() and not disabled)

	func _on_state_changed() -> void:
		queue_redraw()

	## Cuerpo del botón (sin labio) dentro de su rectángulo.
	func body_rect() -> Rect2:
		var o := UiTheme.BEVEL_OUTLINE
		return Rect2(Vector2(o + 2.0, o + 2.0), size - Vector2(o * 2.0 + 4.0, o * 2.0 + 4.0 + UiTheme.BEVEL_DEPTH))

	func _draw() -> void:
		var depth := UiTheme.BEVEL_DEPTH
		var o := UiTheme.BEVEL_OUTLINE
		var r := body_rect()
		var radius := r.size.y / 2.0
		var pressed := get_draw_mode() == DRAW_PRESSED or get_draw_mode() == DRAW_HOVER_PRESSED
		if has_focus():
			var ring := Rect2(r.position, r.size + Vector2(0, depth)).grow(o + 10.0)
			var ring_col := UiTheme.PAPER if base == UiTheme.ACCENT else UiTheme.ACCENT
			UiTheme.draw_round_rect(self, ring.grow(3), Color(UiTheme.INK, 0.55), ring.size.y / 2.0 + 3.0)
			UiTheme.draw_round_rect(self, ring, ring_col, ring.size.y / 2.0)
		var fill := base
		var ink := UiTheme.INK
		if disabled:
			fill = UiTheme.PAPER_DIM
			ink = UiTheme.MUTED
		UiTheme.draw_bevel(self, r, fill, radius, pressed, UiTheme.INK if not disabled else Color(UiTheme.INK, 0.35))
		var body := Rect2(r.position + Vector2(0, depth * 0.7 if pressed else 0.0), r.size)
		var icon_size := body.size.y * 0.5
		var icon_c := Vector2(body.position.x + radius + 4.0, body.get_center().y)
		if not glyph.is_empty():
			UiTheme.draw_glyph(self, glyph, icon_c, icon_size, ink)
		var left := icon_c.x + icon_size * 0.6 if not glyph.is_empty() else body.position.x
		var text_c := Vector2((left + body.end.x - radius * 0.5) / 2.0, body.get_center().y)
		# Si el texto no entra ("Esperando 3 jugadores…"), se achica un poco.
		var px := font_px
		var avail := body.end.x - radius * 0.5 - left
		while px > 24 and UiTheme.FONT_BOLD.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x > avail:
			px -= 2
		UiTheme.draw_text(self, text, text_c, px, ink)


## Capa de destellos del botón principal: solo existe a la vista con el
## foco puesto. Cada abanico es un Node2D que se dibuja una vez (con el
## origen en su posición); para que "laten" solo se cambia su escala, a 30
## cuadros por segundo (cambiar la escala no redibuja nada).
class _Sparkles:
	extends Control
	const PULSE_SPEED := 6.0
	const PULSE_FPS := 30.0
	var _t := 0.0
	var _since := 0.0
	var _fans: Array[Node2D] = []

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		visible = false
		for i in 2:
			var fan := Node2D.new()
			fan.draw.connect(_draw_fan.bind(fan, i))
			add_child(fan)
			_fans.append(fan)
		resized.connect(_refresh_fans)

	func _refresh_fans() -> void:
		for i in _fans.size():
			_fans[i].position = _fan_data(i)[0]
			_fans[i].queue_redraw()

	func set_running(on: bool) -> void:
		if on == visible:
			return
		visible = on
		set_process(on)
		if on:
			_refresh_fans()

	func _ready() -> void:
		set_process(visible)

	func _fan_data(i: int) -> Array:
		var button := get_parent() as _BrightButton
		var r := button.body_rect()
		var whole := Rect2(r.position, r.size + Vector2(0, UiTheme.BEVEL_DEPTH))
		return UiTheme.sparkle_fans(whole.grow(UiTheme.BEVEL_OUTLINE + 10.0))[i]

	func _draw_fan(fan: Node2D, i: int) -> void:
		var data := _fan_data(i)
		var origin: Vector2 = data[0]
		UiTheme.draw_sparkle_fan(fan, Vector2.ZERO, data[1], data[2] - origin)

	func _process(delta: float) -> void:
		_t += delta
		_since += delta
		if _since < 1.0 / PULSE_FPS:
			return
		_since = 0.0
		for i in _fans.size():
			_fans[i].scale = Vector2.ONE * (0.92 + 0.14 * sin(_t * PULSE_SPEED + i * PI))
