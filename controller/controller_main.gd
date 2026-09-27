class_name ControllerMain
extends Control
## Pantalla del celular. Tres estados:
##   JOIN    -> elegir TV (descubierta o IP manual), apodo y código de sala
##   WAIT    -> unido; esperando que la TV arranque un juego. Durante el
##              resumen de ronda y el podio muestra además el resultado propio
##              (puesto, puntos y total) que manda la TV con "standing".
##   PLAY    -> muestra el control que pidió la TV (joystick, slider o botón)

const SEND_RATE_HZ := 30.0
const KEEPALIVE_SEC := 0.25   ## Reenvía el estado aunque no cambie (por si se perdió).
const SETTINGS_PATH := "user://settings.cfg"
const STANDING_POINTS_SIZE := 124  ## "+70": corto, va bien grande.
const STANDING_FINAL_SIZE := 92    ## "¡Terminaste 1°!": más largo.
## Batería: mientras no hay un control en pantalla (unirse, esperar, ver el
## resultado) las nubes y la mascota se animan a estos cuadros por segundo y
## Godot entra en modo de bajo consumo (no dibuja frames que no cambian).
## Con un control activo vuelve todo a 60 fps: la latencia del input no cambia.
## 30 y no menos: la mascota de espera saluda con los brazos y a menos fps
## el saludo se vería a saltos.
const IDLE_ANIM_FPS := 30.0

var client := ControllerClient.new()
var discovery := DiscoveryListener.new()

var _background: PartyBackground
var _power_saving := false

var _join_screen: Control
var _hosts_box: VBoxContainer
var _name_edit: LineEdit
var _code_edit: LineEdit
var _ip_edit: LineEdit
var _join_status: Label

var _play_screen: Control
var _header: Label
var _header_avatar: PlayerAvatar
var _wait_view: Control
var _wait_avatar: PlayerAvatar
var _wait_sub: Label
var _standing_panel: PanelContainer
var _standing_round: Label
var _standing_medal: _Medal
var _standing_main: Label
var _standing_total: Label
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
	theme = UiTheme.build()
	DisplayServer.screen_set_keep_on(true)
	Sfx.load_prefs(SETTINGS_PATH)
	add_child(Sfx.new())
	add_child(client)
	add_child(discovery)
	client.joined.connect(_on_joined)
	client.rejected.connect(_on_rejected)
	client.connection_lost.connect(func() -> void: _header.text = "Reconectando…")
	client.reconnected.connect(func() -> void: _update_header())
	client.gave_up.connect(func() -> void: _show_join("Se perdió la conexión con la TV."))
	client.layout_changed.connect(_on_layout_changed)
	client.phase_changed.connect(_on_phase_changed)
	client.standing_received.connect(_show_standing)
	client.feedback_received.connect(_on_feedback)
	discovery.hosts_changed.connect(_on_hosts_changed)
	_build_ui()
	if discovery.start() != OK:
		_join_status.text = "No se pudo buscar TVs automáticamente. Ingresá la IP."
	_show_join("")


func _exit_tree() -> void:
	if _power_saving:
		OS.low_processor_usage_mode = false


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
	Sfx.play("join")
	Haptics.buzz("go")
	_save_name(info.name)
	_join_screen.visible = false
	_play_screen.visible = true
	_update_header()


func _on_rejected(reason: String) -> void:
	var messages := {
		Protocol.R_BAD_ROOM: "Código incorrecto. Mirá el código en la TV.",
		Protocol.R_ROOM_FULL: "La sala está llena. Pedile a quien tiene el control de la TV que sume un lugar.",
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
	_wait_view.visible = _active_layout == null
	if layout != Protocol.LAYOUT_WAIT:
		_clear_standing()  # Empieza un juego nuevo: el resultado anterior ya no aplica.
		Sfx.play("select")
		Haptics.buzz("point")
	if _active_layout:
		_active_layout.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_active_layout.mouse_filter = Control.MOUSE_FILTER_STOP
		_layout_host.add_child(_active_layout)
	_last_sent_btn = -1
	_update_power_mode()


## Sin control activo: animaciones a IDLE_ANIM_FPS y modo de bajo consumo.
## El modo de bajo consumo es global del proceso: solo se toca si este
## control es la app (raíz de la ventana). En las capturas y los tests la
## TV corre en el mismo proceso y no se debe frenar.
func _update_power_mode() -> void:
	var idle := _active_layout == null
	var fps := IDLE_ANIM_FPS if idle else 0.0
	_background.anim_fps = fps
	for avatar: PlayerAvatar in [_header_avatar, _wait_avatar]:
		avatar.anim_fps = fps
	var owns_window := is_inside_tree() and get_viewport() == get_tree().root
	if owns_window and idle != _power_saving:
		_power_saving = idle
		OS.low_processor_usage_mode = idle


func _on_phase_changed(phase: String) -> void:
	if phase != Protocol.PHASE_RESULTS:
		_clear_standing()


## Resultado propio (ya validado por Protocol.parse_standing). En el
## resumen de ronda: medalla con el puesto, "+70" y "Total 170 · vas 2°".
## En el podio: "¡Terminaste 1°!" y el total.
## La TV pide vibrar/sonar por algo que le pasó a este jugador en el juego.
## El tipo ya viene validado (Protocol.parse_feedback).
func _on_feedback(kind: String) -> void:
	Haptics.buzz(kind)
	Sfx.play(kind)


func _show_standing(data: Dictionary) -> void:
	var celebrate := int(data.place) == 1 or (bool(data.final) and int(data.rank) == 1)
	Sfx.play("win" if celebrate else "pop")
	Haptics.buzz("win" if celebrate else "point")
	var is_final: bool = data.final
	var rank: int = data.rank
	var place: int = data.place
	var medal_place := rank if is_final else place
	_standing_round.text = "Resultado final" if is_final else "Ronda %d/%d" % [data.round, data.total_rounds]
	_standing_medal.place = medal_place
	_standing_medal.visible = medal_place > 0
	_standing_medal.queue_redraw()
	_set_headline_size(_standing_main, STANDING_FINAL_SIZE if is_final else STANDING_POINTS_SIZE)
	if is_final:
		_standing_main.text = "¡Terminaste %s!" % UiTheme.place_text(rank)
		_standing_total.text = "%d pts" % data.total
	elif place > 0:
		_standing_main.text = "+%d" % data.points
		_standing_total.text = "Total %d · vas %s" % [data.total, UiTheme.place_text(rank)]
	else:  # No jugó esta ronda: solo la tabla general.
		_standing_main.text = "Total %d" % data.total
		_standing_total.text = "Vas %s" % UiTheme.place_text(rank)
	_wait_sub.visible = false
	if not _standing_panel.visible:
		_standing_panel.visible = true
		_standing_panel.modulate.a = 0.0
		create_tween().tween_property(_standing_panel, "modulate:a", 1.0, 0.3)
	if medal_place == 1:
		_wait_avatar.hop()


## Cambia el tamaño de un UiTheme.headline manteniendo su contorno proporcional.
static func _set_headline_size(l: Label, size: int) -> void:
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_constant_override("outline_size", maxi(6, size / 7))
	l.add_theme_constant_override("shadow_outline_size", maxi(6, size / 7))
	l.add_theme_constant_override("shadow_offset_y", maxi(3, size / 18))


func _clear_standing() -> void:
	if _standing_panel == null:
		return
	_standing_panel.visible = false
	_wait_sub.visible = true


func _on_hosts_changed(hosts: Array[Dictionary]) -> void:
	for c in _hosts_box.get_children():
		c.queue_free()
	if hosts.is_empty():
		_hosts_box.add_child(_label("Buscando TVs en tu Wi-Fi…", 32, UiTheme.INK_SOFT))
		return
	for h in hosts:
		var b := Button.new()
		b.text = "%s  (%s)" % [h.name, h.ip]
		b.toggle_mode = true
		b.button_pressed = _selected_host.get("ip") == h.ip
		b.custom_minimum_size = Vector2(0, 104)
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
	_clear_standing()
	_play_screen.visible = false
	_join_screen.visible = true
	_join_status.text = message
	_update_power_mode()


func _update_header() -> void:
	var info := client.player_info
	var slot := int(info.get("id", 1)) - 1
	var color: Color = info.get("color", Color.WHITE)
	_header.text = "%s · %s" % [UiTheme.player_tag(slot), info.get("name", "")]
	for avatar in [_header_avatar, _wait_avatar]:
		avatar.slot = slot
		avatar.color = color


# --- UI -------------------------------------------------------------------------

func _build_ui() -> void:
	_background = PartyBackground.new()
	_background.bricks = false
	_background.towers = false
	_background.checker_floor = false
	add_child(_background)

	# Pantalla para unirse: una tarjeta centrada, legible en celular apaisado.
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 40)
	add_child(margin)
	_join_screen = margin
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(1100, 0)
	card.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	margin.add_child(card)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	card.add_child(scroll)
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 20)
	scroll.add_child(col)

	var logo := UiTheme.logo_rect()
	logo.custom_minimum_size = Vector2(0, 150)
	col.add_child(logo)
	col.add_child(_section("1. Elegí la TV"))
	_hosts_box = VBoxContainer.new()
	_hosts_box.add_theme_constant_override("separation", 12)
	col.add_child(_hosts_box)
	_on_hosts_changed([])
	_ip_edit = _line_edit("…o escribí la IP que muestra la TV", 15)
	col.add_child(_ip_edit)

	col.add_child(_section("2. Tu apodo"))
	_name_edit = _line_edit("Apodo", Protocol.NAME_MAX_LENGTH)
	_name_edit.text = _load_name()
	col.add_child(_name_edit)

	col.add_child(_section("3. Código de la TV"))
	_code_edit = _line_edit("ABCD", Protocol.ROOM_CODE_LENGTH)
	_code_edit.text_changed.connect(func(t: String) -> void:
		var caret := _code_edit.caret_column
		_code_edit.text = t.to_upper()
		_code_edit.caret_column = caret)
	col.add_child(_code_edit)

	var join := Button.new()
	join.text = "Unirme"
	join.custom_minimum_size = Vector2(0, 120)
	join.add_theme_font_size_override("font_size", 46)
	join.add_theme_stylebox_override("normal", UiTheme.button_style(UiTheme.ACCENT))
	join.add_theme_stylebox_override("hover", UiTheme.button_style(UiTheme.ACCENT.lightened(0.1)))
	join.add_theme_stylebox_override("pressed", UiTheme.button_style(UiTheme.ACCENT, true))
	join.pressed.connect(_on_join_pressed)
	col.add_child(join)
	_join_status = _label("", 30, UiTheme.DANGER)
	_join_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(_join_status)

	# Pantalla de juego
	_play_screen = VBoxContainer.new()
	_play_screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_play_screen)
	var top_margin := MarginContainer.new()
	for side in ["left", "right", "top"]:
		top_margin.add_theme_constant_override("margin_" + side, 24)
	_play_screen.add_child(top_margin)
	var top := HBoxContainer.new()
	top.custom_minimum_size = Vector2(0, 100)
	top.add_theme_constant_override("separation", 16)
	top_margin.add_child(top)
	var leave := Button.new()
	leave.text = "Salir"
	leave.custom_minimum_size = Vector2(170, 0)
	leave.add_theme_font_size_override("font_size", 30)
	leave.pressed.connect(_on_leave_pressed)
	top.add_child(leave)
	_header_avatar = PlayerAvatar.new()
	_header_avatar.custom_minimum_size = Vector2(90, 100)
	top.add_child(_header_avatar)
	_header = UiTheme.headline("", 44)
	_header.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(_header)
	_latency = UiTheme.label("", 28, UiTheme.INK_SOFT, true)
	_latency.custom_minimum_size = Vector2(160, 0)
	top.add_child(_latency)
	top.add_child(_toggle_button(func() -> String: return "Sonido: " + ("No" if Sfx.muted else "Sí"),
		func() -> void: Sfx.muted = not Sfx.muted))
	top.add_child(_toggle_button(func() -> String: return "Vibrar: " + ("Sí" if Haptics.enabled else "No"),
		func() -> void: Haptics.enabled = not Haptics.enabled))
	_layout_host = Control.new()
	_layout_host.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_play_screen.add_child(_layout_host)

	# Vista de espera: mascota + "¡Mirá la TV!" y, a la derecha, el panel
	# con el resultado propio (solo durante el resumen y el podio).
	var wait_view := HBoxContainer.new()
	wait_view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	wait_view.alignment = BoxContainer.ALIGNMENT_CENTER
	wait_view.add_theme_constant_override("separation", 72)
	_layout_host.add_child(wait_view)
	_wait_view = wait_view
	var wait_box := VBoxContainer.new()
	wait_box.alignment = BoxContainer.ALIGNMENT_CENTER
	wait_box.custom_minimum_size = Vector2(760, 0)
	wait_view.add_child(wait_box)
	_wait_avatar = PlayerAvatar.new()
	_wait_avatar.mood = PlayerAvatar.Mood.HAPPY
	_wait_avatar.custom_minimum_size = Vector2(0, 330)
	wait_box.add_child(_wait_avatar)
	var wait := UiTheme.headline("¡Mirá la TV!", 64)
	wait_box.add_child(wait)
	_wait_sub = UiTheme.label("El juego empieza cuando la TV lo elija", 34, UiTheme.INK, true)
	_wait_sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	wait_box.add_child(_wait_sub)
	_build_standing_panel(wait_view)
	_play_screen.visible = false


func _build_standing_panel(parent: Control) -> void:
	_standing_panel = PanelContainer.new()
	_standing_panel.add_theme_stylebox_override("panel", UiTheme.panel_style(UiTheme.PAPER, UiTheme.RADIUS + 8, 44))
	_standing_panel.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_standing_panel.custom_minimum_size = Vector2(980, 0)
	_standing_panel.visible = false
	parent.add_child(_standing_panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 16)
	_standing_panel.add_child(col)
	_standing_round = UiTheme.label("", 44, UiTheme.INK_SOFT, true)
	col.add_child(_standing_round)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 40)
	col.add_child(row)
	_standing_medal = _Medal.new()
	_standing_medal.custom_minimum_size = Vector2(260, 260)
	row.add_child(_standing_medal)
	var text := VBoxContainer.new()
	text.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_child(text)
	_standing_main = UiTheme.headline("", STANDING_POINTS_SIZE, UiTheme.ACCENT)
	text.add_child(_standing_main)
	_standing_total = UiTheme.label("", 56, UiTheme.INK, true)
	text.add_child(_standing_total)


func _section(text: String) -> Label:
	return UiTheme.label(text, 34, UiTheme.INK, true, HORIZONTAL_ALIGNMENT_LEFT)


## Botón que alterna una preferencia de audio, la guarda y muestra su estado.
func _toggle_button(caption: Callable, toggle: Callable) -> Button:
	var b := Button.new()
	b.text = caption.call()
	b.custom_minimum_size = Vector2(230, 0)
	b.add_theme_font_size_override("font_size", 26)
	b.pressed.connect(func() -> void:
		toggle.call()
		Sfx.save_prefs(SETTINGS_PATH)
		b.text = caption.call()
		Sfx.play("select")
		Haptics.buzz("tap"))
	return b


func _label(text: String, size: int, color: Color = UiTheme.INK,
		align: HorizontalAlignment = HORIZONTAL_ALIGNMENT_CENTER) -> Label:
	return UiTheme.label(text, size, color, false, align)


func _line_edit(placeholder: String, max_len: int) -> LineEdit:
	var e := LineEdit.new()
	e.placeholder_text = placeholder
	e.max_length = max_len
	e.custom_minimum_size = Vector2(0, 96)
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


## Medalla con el puesto de la ronda (o el final en el podio).
class _Medal:
	extends Control
	var place := 1

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var r := minf(size.x, size.y) / 2.0 - 14.0
		UiTheme.draw_medal(self, size / 2.0, r, place)
