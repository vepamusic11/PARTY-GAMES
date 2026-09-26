class_name ControllerMain
extends Control
## Pantalla del celular. Tres estados:
##   JOIN    -> elegir TV (descubierta o IP manual), apodo y código de sala
##   WAIT    -> unido; esperando que la TV arranque un juego
##   PLAY    -> muestra el control que pidió la TV (joystick, slider o botón)

const SEND_RATE_HZ := 30.0
const KEEPALIVE_SEC := 0.25   ## Reenvía el estado aunque no cambie (por si se perdió).
const SETTINGS_PATH := "user://settings.cfg"

var client := ControllerClient.new()
var discovery := DiscoveryListener.new()

var _join_screen: Control
var _hosts_box: VBoxContainer
var _name_edit: LineEdit
var _code_edit: LineEdit
var _ip_edit: LineEdit
var _join_status: Label

var _play_screen: Control
var _header: Label
var _latency: Label
var _layout_host: Control
var _active_layout: Control
var _selected_host: Dictionary = {}

var _send_elapsed := 0.0
var _since_last_send := 0.0
var _last_sent_axis := Vector2(INF, INF)
var _last_sent_btn := -1


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	DisplayServer.screen_set_keep_on(true)
	add_child(client)
	add_child(discovery)
	client.joined.connect(_on_joined)
	client.rejected.connect(_on_rejected)
	client.connection_lost.connect(func() -> void: _header.text = "Reconectando…")
	client.reconnected.connect(func() -> void: _update_header())
	client.gave_up.connect(func() -> void: _show_join("Se perdió la conexión con la TV."))
	client.layout_changed.connect(_on_layout_changed)
	discovery.hosts_changed.connect(_on_hosts_changed)
	_build_ui()
	if discovery.start() != OK:
		_join_status.text = "No se pudo buscar TVs automáticamente. Ingresá la IP."
	_show_join("")


func _process(delta: float) -> void:
	if client.rtt_ms >= 0:
		_latency.text = "%d ms" % roundi(client.rtt_ms)
	_send_elapsed += delta
	_since_last_send += delta
	if _send_elapsed < 1.0 / SEND_RATE_HZ or _active_layout == null:
		return
	_send_elapsed = 0.0
	var axis := Vector2.ZERO
	var btn := 0
	if _active_layout is VirtualJoystick:
		axis = (_active_layout as VirtualJoystick).value
	elif _active_layout is SliderPad:
		axis = (_active_layout as SliderPad).value
	elif _active_layout is BigButton:
		btn = Protocol.BTN_A if (_active_layout as BigButton).pressed else 0
	# Solo mandar si cambió, o como keepalive: ahorra batería y red.
	if axis != _last_sent_axis or btn != _last_sent_btn or _since_last_send >= KEEPALIVE_SEC:
		client.send_input(axis, btn)
		_last_sent_axis = axis
		_last_sent_btn = btn
		_since_last_send = 0.0


# --- Eventos de red -------------------------------------------------------------

func _on_joined(info: Dictionary) -> void:
	_save_name(info.name)
	_join_screen.visible = false
	_play_screen.visible = true
	_update_header()


func _on_rejected(reason: String) -> void:
	var messages := {
		Protocol.R_BAD_ROOM: "Código incorrecto. Mirá el código en la TV.",
		Protocol.R_ROOM_FULL: "La sala está llena (máximo 4 jugadores).",
		Protocol.R_GAME_IN_PROGRESS: "Hay una partida en curso. Esperá a que termine.",
		Protocol.R_BAD_NAME: "Elegí un apodo válido.",
		Protocol.R_BAD_VERSION: "Versión distinta a la de la TV. Actualizá ambas apps.",
		"unreachable": "No se pudo conectar con la TV. ¿Están en la misma Wi-Fi?",
	}
	_show_join(messages.get(reason, "No se pudo unir (%s)." % reason))


func _on_layout_changed(layout: String, data: Dictionary) -> void:
	if is_instance_valid(_active_layout):
		_active_layout.queue_free()
	_active_layout = null
	var color: Color = client.player_info.get("color", Color.WHITE)
	match layout:
		Protocol.LAYOUT_JOYSTICK:
			var j := VirtualJoystick.new()
			j.color = color
			_active_layout = j
		Protocol.LAYOUT_SLIDER_H:
			var s := SliderPad.new()
			s.color = color
			_active_layout = s
		Protocol.LAYOUT_ONE_BUTTON:
			var b := BigButton.new()
			b.color = color
			b.label = str(data.get("label", "A")).left(12)
			_active_layout = b
	for c in _layout_host.get_children():
		if c != _active_layout and c is Label:
			c.visible = _active_layout == null
	if _active_layout:
		_active_layout.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_active_layout.mouse_filter = Control.MOUSE_FILTER_STOP
		_layout_host.add_child(_active_layout)
	_last_sent_btn = -1


func _on_hosts_changed(hosts: Array[Dictionary]) -> void:
	for c in _hosts_box.get_children():
		c.queue_free()
	if hosts.is_empty():
		_hosts_box.add_child(_label("Buscando TVs en tu Wi-Fi…", 34, Color("#888780")))
		return
	for h in hosts:
		var b := Button.new()
		b.text = "%s  (%s)" % [h.name, h.ip]
		b.toggle_mode = true
		b.button_pressed = _selected_host.get("ip") == h.ip
		b.custom_minimum_size = Vector2(0, 110)
		b.add_theme_font_size_override("font_size", 36)
		b.pressed.connect(func() -> void:
			_selected_host = h
			_ip_edit.text = h.ip
			_on_hosts_changed(discovery.get_hosts()))
		_hosts_box.add_child(b)


# --- Acciones -------------------------------------------------------------------

func _on_join_pressed() -> void:
	var player_name := Protocol.sanitize_name(_name_edit.text)
	var code := Protocol.normalize_room_code(_code_edit.text)
	var ip := _ip_edit.text.strip_edges()
	if player_name.is_empty():
		_join_status.text = "Escribí tu apodo."
		return
	if not Protocol.is_valid_room_code(code):
		_join_status.text = "El código tiene 4 letras/números, como aparece en la TV."
		return
	if not ip.is_valid_ip_address():
		_join_status.text = "Elegí una TV de la lista o escribí su IP."
		return
	var port := int(_selected_host.get("port", Protocol.WS_PORT)) if _selected_host.get("ip") == ip else Protocol.WS_PORT
	_join_status.text = "Conectando…"
	client.join(ip, port, code, player_name)


func _on_leave_pressed() -> void:
	client.leave()
	_show_join("")


func _show_join(message: String) -> void:
	if is_instance_valid(_active_layout):
		_active_layout.queue_free()
	_active_layout = null
	_play_screen.visible = false
	_join_screen.visible = true
	_join_status.text = message


func _update_header() -> void:
	var info := client.player_info
	_header.text = "Jugador %d · %s" % [info.get("id", 0), info.get("name", "")]
	_header.add_theme_color_override("font_color", info.get("color", Color.WHITE))


# --- UI -------------------------------------------------------------------------

func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.color = Color("#1b1b2f")
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	# Pantalla para unirse
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 60)
	add_child(margin)
	_join_screen = margin
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	margin.add_child(scroll)
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 24)
	scroll.add_child(col)

	col.add_child(_label("Party Games · Control", 56))
	col.add_child(_label("1. Elegí la TV", 36, Color("#B4B2A9"), HORIZONTAL_ALIGNMENT_LEFT))
	_hosts_box = VBoxContainer.new()
	_hosts_box.add_theme_constant_override("separation", 12)
	col.add_child(_hosts_box)
	_on_hosts_changed([])
	_ip_edit = _line_edit("…o escribí la IP que muestra la TV", 15)
	col.add_child(_ip_edit)

	col.add_child(_label("2. Tu apodo", 36, Color("#B4B2A9"), HORIZONTAL_ALIGNMENT_LEFT))
	_name_edit = _line_edit("Apodo", Protocol.NAME_MAX_LENGTH)
	_name_edit.text = _load_name()
	col.add_child(_name_edit)

	col.add_child(_label("3. Código de la TV", 36, Color("#B4B2A9"), HORIZONTAL_ALIGNMENT_LEFT))
	_code_edit = _line_edit("ABCD", Protocol.ROOM_CODE_LENGTH)
	_code_edit.text_changed.connect(func(t: String) -> void:
		var caret := _code_edit.caret_column
		_code_edit.text = t.to_upper()
		_code_edit.caret_column = caret)
	col.add_child(_code_edit)

	var join := Button.new()
	join.text = "Unirme"
	join.custom_minimum_size = Vector2(0, 130)
	join.add_theme_font_size_override("font_size", 48)
	join.pressed.connect(_on_join_pressed)
	col.add_child(join)
	_join_status = _label("", 32, Color("#F09595"))
	_join_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(_join_status)

	# Pantalla de juego
	_play_screen = VBoxContainer.new()
	_play_screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_play_screen)
	var top := HBoxContainer.new()
	top.custom_minimum_size = Vector2(0, 110)
	_play_screen.add_child(top)
	var leave := Button.new()
	leave.text = "Salir"
	leave.custom_minimum_size = Vector2(180, 0)
	leave.add_theme_font_size_override("font_size", 30)
	leave.pressed.connect(_on_leave_pressed)
	top.add_child(leave)
	_header = _label("", 40)
	_header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(_header)
	_latency = _label("", 28, Color("#888780"))
	_latency.custom_minimum_size = Vector2(160, 0)
	top.add_child(_latency)
	_layout_host = Control.new()
	_layout_host.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_play_screen.add_child(_layout_host)
	var wait := _label("Mirá la TV: esperando que empiece un juego", 44, Color("#B4B2A9"))
	wait.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	wait.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_layout_host.add_child(wait)
	_play_screen.visible = false


func _label(text: String, size: int, color: Color = Color.WHITE,
		align: HorizontalAlignment = HORIZONTAL_ALIGNMENT_CENTER) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = align
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


func _line_edit(placeholder: String, max_len: int) -> LineEdit:
	var e := LineEdit.new()
	e.placeholder_text = placeholder
	e.max_length = max_len
	e.custom_minimum_size = Vector2(0, 100)
	e.add_theme_font_size_override("font_size", 40)
	return e


func _load_name() -> String:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) == OK:
		return Protocol.sanitize_name(cfg.get_value("player", "name", ""))
	return ""


func _save_name(player_name: String) -> void:
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_PATH)
	cfg.set_value("player", "name", player_name)
	cfg.save(SETTINGS_PATH)
