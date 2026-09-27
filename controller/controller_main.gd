class_name ControllerMain
extends Control
## Pantalla del celular. Tres estados:
##   JOIN    -> elegir TV (tarjetas de las descubiertas o IP manual), apodo
##              y código de sala (en fichas de colores, como en la TV)
##   WAIT    -> unido; esperando que la TV arranque un juego. Tarjeta con la
##              mascota grande, la etiqueta 1P–4P y el apodo. En el lobby
##              muestra al lado el selector de mascota (LookPicker).
##              Durante el resumen de ronda y el podio muestra además el
##              resultado propio (puesto, puntos y total) que manda la TV
##              con "standing", con medalla, rayos y papelitos.
##   PLAY    -> muestra el control que pidió la TV (joystick, slider o botón)
##
## Look "de consola": botones y perillas con bisel, brillo y sombra
## (UiTheme.draw_toy_key / draw_toy_disc) que se aplastan al tocarlos.
## Los cambios de estado entran con transiciones cortas (≤ 0,3 s).
##
## Una vez unido, el celular es "tu control personalizado": fondo con tu
## color, tu mascota y tu 1P–4P gigantes y translúcidos (PhoneBackdrop),
## arriba una línea con qué hacer en el juego actual, la señal de Wi-Fi
## (verde/naranja/roja y con 3/2/1 barras), el engranaje de Ajustes
## (SettingsPanel: sonido, vibración, zurdo, tamaño del control y modo
## desarrollador) y "Salir", que hay que mantener apretado 1 s (HoldButton).
## La latencia en milisegundos solo se ve en modo desarrollador (5 toques en
## el logo de la pantalla de unirse, o el ajuste).

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
const FADE_SEC := 0.25            ## Transición entre pantallas.
const LATENCY_OK_MS := 120        ## Hasta acá la señal se ve verde…
const LATENCY_SLOW_MS := 250      ## …hasta acá naranja; más, roja.
const DEV_TAPS := 5               ## Toques seguidos en el logo para el modo desarrollador…
const DEV_TAP_WINDOW_MS := 1500   ## …con menos de esto entre uno y otro.
const HINT_MAX_LENGTH := 48       ## Instrucción que manda la TV (opcional): se recorta.
## Qué hacer, según el control, si la TV no manda una instrucción propia
## (`hint` en los datos del layout).
const LAYOUT_HINTS := {
	Protocol.LAYOUT_JOYSTICK: "Mové tu mascota con el joystick",
	Protocol.LAYOUT_SLIDER_H: "Deslizá el dedo para mover tu paleta",
	Protocol.LAYOUT_ONE_BUTTON: "Tocá el botón cuando la TV te diga",
	Protocol.LAYOUT_JOYSTICK_AB: "Movete con el joystick y usá A y B",
}

var client := ControllerClient.new()
var discovery := DiscoveryListener.new()
## Archivo local de ajustes (apodo, apariencia, sonido y PhoneSettings). Los
## tests lo cambian antes de agregar el nodo para no tocar el real.
var settings_path := SETTINGS_PATH
var settings := PhoneSettings.new()

var _background: PartyBackground
var _backdrop: PhoneBackdrop
var _power_saving := false

var _join_screen: Control
var _hosts_box: VBoxContainer
var _name_edit: LineEdit
var _code_edit: LineEdit
var _ip_edit: LineEdit
var _join_mascot: PlayerAvatar
var _join_status_panel: PanelContainer
var _join_status_badge: GlyphBadge
var _join_status: Label
var _discovery_failed := false

var _play_screen: Control
var _header: Label
var _header_avatar: PlayerAvatar
var _header_tag: _Tag
var _wait_view: Control
var _player_card: PlayerCard
var _wait_avatar: PlayerAvatar
var _wait_sub: Label
var _standing_panel: PanelContainer
var _standing_bg: _StandingBg
var _standing_round: Label
var _standing_cheer: Label
var _standing_medal: _Medal
var _standing_main: Label
var _standing_total: Label
var _confetti: ConfettiBurst
var _look_picker: LookPicker
var _phase := Protocol.PHASE_LOBBY
var _latency: Label
var _latency_ms := -1
var _signal: SignalIcon
var _leave: HoldButton
var _settings_button: ToyButton
var _settings_panel: SettingsPanel
var _instruction: Label
var _instruction_gap: Control
var _toast: PanelContainer
var _toast_label: Label
var _toast_tween: Tween
var _logo_taps := 0
var _logo_last_tap_ms := -DEV_TAP_WINDOW_MS
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
	Sfx.load_prefs(settings_path)
	settings.load_from(settings_path)
	add_child(Sfx.new())
	add_child(client)
	add_child(discovery)
	client.joined.connect(_on_joined)
	client.rejected.connect(_on_rejected)
	client.connection_lost.connect(_on_connection_lost)
	client.reconnected.connect(func() -> void:
		_update_header()
		_signal.level = SignalIcon.level_for_ms(client.rtt_ms))
	client.gave_up.connect(func() -> void: _show_join("Se cortó la conexión con la TV. Volvé a unirte cuando quieras."))
	client.layout_changed.connect(_on_layout_changed)
	client.phase_changed.connect(_on_phase_changed)
	client.standing_received.connect(_show_standing)
	client.feedback_received.connect(_on_feedback)
	client.appearance_changed.connect(_on_appearance_changed)
	discovery.hosts_changed.connect(_on_hosts_changed)
	_build_ui()
	_discovery_failed = discovery.start() != OK
	_on_hosts_changed(discovery.get_hosts())
	_show_join("")
	_apply_settings()


func _exit_tree() -> void:
	if _power_saving:
		OS.low_processor_usage_mode = false


func _process(delta: float) -> void:
	if client.rtt_ms >= 0 and _signal.level != SignalIcon.LOST:
		_update_latency(roundi(client.rtt_ms))
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
	elif _active_layout is JoystickAB:
		axis = (_active_layout as JoystickAB).value
		btn = (_active_layout as JoystickAB).buttons
	# Solo mandar si cambió, o como keepalive: ahorra batería y red.
	if axis != _last_sent_axis or btn != _last_sent_btn or _since_last_send >= KEEPALIVE_SEC:
		client.send_input(axis, btn)
		_last_sent_axis = axis
		_last_sent_btn = btn
		_since_last_send = 0.0


## Señal para todos (Wi-Fi con 3/2/1 barras en verde/naranja/rojo) y los
## milisegundos solo en modo desarrollador. Nada se redibuja si no cambia:
## el ícono solo al cambiar de franja y el texto solo si cambió el número.
func _update_latency(ms: int) -> void:
	_signal.level = SignalIcon.level_for_ms(ms)
	if settings.dev_mode and ms != _latency_ms:
		_latency_ms = ms
		_latency.text = "%d ms" % ms


# --- Eventos de red -------------------------------------------------------------

func _on_joined(info: Dictionary) -> void:
	Sfx.play("join")
	Haptics.buzz("go")
	_save_name(info.name)
	_join_screen.visible = false
	_play_screen.visible = true
	_fade_in(_play_screen, Vector2(0, 40))
	_signal.level = SignalIcon.level_for_ms(client.rtt_ms)
	_update_header()


func _on_rejected(reason: String) -> void:
	var messages := {
		Protocol.R_BAD_ROOM: "Ese código no es el de la TV. Fijate las 4 fichas de colores en la pantalla.",
		Protocol.R_ROOM_FULL: "¡La sala está llena! Pedile a quien tiene el control de la TV que sume un lugar.",
		Protocol.R_GAME_IN_PROGRESS: "Están en medio de una partida. Esperá a que termine y volvé a probar.",
		Protocol.R_BAD_NAME: "Ese apodo no se puede usar. Probá con otro.",
		Protocol.R_BAD_VERSION: "Esta app y la de la TV son de versiones distintas. Actualizá las dos.",
		"unreachable": "No encontramos la TV. ¿Están los dos en la misma Wi-Fi?",
	}
	_show_join(messages.get(reason, "No se pudo unir (%s). Probá de nuevo." % reason))


func _on_connection_lost() -> void:
	_header.text = "Reconectando…"
	_player_card.set_status("Reconectando…", UiTheme.WARNING)
	_signal.level = SignalIcon.LOST


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
		Protocol.LAYOUT_JOYSTICK_AB:
			var pad := JoystickAB.new()
			pad.color = color
			pad.label_a = str(data.get("a", ""))
			pad.label_b = str(data.get("b", ""))
			_active_layout = pad
	_apply_settings()
	_set_instruction(instruction_for(layout, data) if _active_layout else "")
	var was_waiting := _wait_view.visible
	_wait_view.visible = _active_layout == null
	if _wait_view.visible and not was_waiting:
		_fade_in(_wait_view, Vector2(0, 30))
	if layout != Protocol.LAYOUT_WAIT:
		_clear_standing()  # Empieza un juego nuevo: el resultado anterior ya no aplica.
		_set_mood(PlayerAvatar.Mood.NORMAL)
		Sfx.play("select")
		Haptics.buzz("point")
	if _active_layout:
		_active_layout.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_active_layout.mouse_filter = Control.MOUSE_FILTER_STOP
		_layout_host.add_child(_active_layout)
		# Entra con un "pop" corto. Solo visual: recibe toques desde el primer frame.
		_active_layout.pivot_offset = _layout_host.size / 2.0
		_active_layout.scale = Vector2.ONE * 0.92
		_active_layout.modulate.a = 0.0
		var tw := _active_layout.create_tween().set_parallel()
		tw.tween_property(_active_layout, "scale", Vector2.ONE, FADE_SEC).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tw.tween_property(_active_layout, "modulate:a", 1.0, FADE_SEC * 0.6)
	_last_sent_btn = -1
	_update_power_mode()
	_update_picker()


## Qué hacer en el juego actual, en una línea: la instrucción que manda la
## TV en los datos del layout (`hint`, opcional; texto plano, recortado) o,
## si no manda, una según el control.
static func instruction_for(layout: String, data: Dictionary) -> String:
	var hint: Variant = data.get("hint", "")
	if typeof(hint) == TYPE_STRING:
		var clean := (hint as String).replace("\n", " ").replace("\t", " ").strip_edges().left(HINT_MAX_LENGTH)
		if not clean.is_empty():
			return clean
	return LAYOUT_HINTS.get(layout, "")


func _set_instruction(text: String) -> void:
	_instruction.text = text
	_instruction.visible = not text.is_empty()
	_instruction_gap.visible = text.is_empty()
	if _instruction.visible:
		_fade_in(_instruction)


## Aplica los ajustes al control en pantalla y a la barra: zurdo y tamaño,
## lado de la mascota del fondo (el contrario al control) y latencia visible.
func _apply_settings() -> void:
	var control_right := false
	if _active_layout is VirtualJoystick:
		(_active_layout as VirtualJoystick).lefty = settings.lefty
		(_active_layout as VirtualJoystick).control_scale = settings.control_scale()
		control_right = settings.lefty
	elif _active_layout is BigButton:
		(_active_layout as BigButton).lefty = settings.lefty
		(_active_layout as BigButton).control_scale = settings.control_scale()
		control_right = not settings.lefty
	elif _active_layout is SliderPad:
		(_active_layout as SliderPad).control_scale = settings.control_scale()
	elif _active_layout is JoystickAB:
		# Zurdo: botones a la izquierda y joystick a la derecha (en espejo).
		(_active_layout as JoystickAB).left_handed = settings.lefty
	# El slider ocupa todo el ancho: la mascota del fondo queda a la derecha.
	# Joystick + A/B ocupa los dos lados: sin mascota de fondo que tape los botones.
	_backdrop.set_watermark(_active_layout != null and not _active_layout is JoystickAB, not control_right)
	_latency.visible = settings.dev_mode
	if not settings.dev_mode:
		_latency_ms = -1  # Al volver a prenderlo, se actualiza en el próximo frame.


## Sin control activo: animaciones a IDLE_ANIM_FPS y modo de bajo consumo.
## El modo de bajo consumo es global del proceso: solo se toca si este
## control es la app (raíz de la ventana). En las capturas y los tests la
## TV corre en el mismo proceso y no se debe frenar.
func _update_power_mode() -> void:
	var idle := _active_layout == null
	var fps := IDLE_ANIM_FPS if idle else 0.0
	_background.anim_fps = fps
	for avatar: PlayerAvatar in [_header_avatar, _wait_avatar, _join_mascot]:
		avatar.anim_fps = fps
	var owns_window := is_inside_tree() and get_viewport() == get_tree().root
	if owns_window and idle != _power_saving:
		_power_saving = idle
		OS.low_processor_usage_mode = idle


func _on_phase_changed(phase: String) -> void:
	_phase = phase
	if phase != Protocol.PHASE_RESULTS:
		_clear_standing()
	if phase == Protocol.PHASE_LOBBY:
		_set_mood(PlayerAvatar.Mood.HAPPY)  # Saluda mientras se elige mascota.
	_update_picker()


## La TV confirmó color y estilo (al unirse, al cambiarlos o cuando otro
## jugador ocupa o libera un color).
func _on_appearance_changed() -> void:
	_update_header()
	_update_picker()


## El jugador tocó el selector: se ve al instante (la mascota grande es la
## vista previa), se guarda como preferencia y se pide a la TV, que confirma
## o corrige con "appearance".
func _on_look_picked(color_index: int, style: int) -> void:
	Sfx.play("select")
	Haptics.buzz("tap")
	_save_look(color_index, style)
	var color := Protocol.mascot_color(color_index)
	for avatar: PlayerAvatar in [_header_avatar, _wait_avatar]:
		avatar.color = color
		avatar.style = style
	_player_card.set_player(_player_card.slot, color, client.player_info.get("name", ""))
	_header_tag.color = color
	_header_tag.queue_redraw()
	_set_backdrop(color, _player_card.slot, style)
	_wait_avatar.hop(1)
	client.send_look(color_index, style)


## Selector visible solo en el lobby, sin control ni resultado en pantalla,
## y si la TV entiende de apariencias (una TV vieja no manda colorIndex).
func _update_picker() -> void:
	if _look_picker == null:
		return
	var info := client.player_info
	var supported := int(info.get("color_index", -1)) >= 0 and int(info.get("style", -1)) >= 0
	var shown := supported and _phase == Protocol.PHASE_LOBBY and _active_layout == null and not _standing_panel.visible
	if shown and not _look_picker.visible:
		_fade_in(_look_picker, Vector2(40, 0))
	_look_picker.visible = shown
	_wait_sub.text = "Elegí tu mascota mientras la TV arranca" if shown else "El juego empieza cuando la TV lo elija"
	if supported:
		_look_picker.set_look(info.color_index, info.style, info.get("taken", []))


## La TV pide vibrar/sonar por algo que le pasó a este jugador en el juego.
## El tipo ya viene validado (Protocol.parse_feedback).
func _on_feedback(kind: String) -> void:
	Haptics.buzz(kind)
	Sfx.play(kind)


## Resultado propio (ya validado por Protocol.parse_standing). En el
## resumen de ronda: medalla con el puesto, "+70" y "Total 170 · vas 2°".
## En el podio: "¡Terminaste 1°!" y el total. Festejo acorde al puesto
## (frase, rayos detrás de la medalla y papelitos si quedó en el podio).
func _show_standing(data: Dictionary) -> void:
	var celebrate := int(data.place) == 1 or (bool(data.final) and int(data.rank) == 1)
	Sfx.play("win" if celebrate else "pop")
	Haptics.buzz("win" if celebrate else "point")
	var is_final: bool = data.final
	var rank: int = data.rank
	var place: int = data.place
	var medal_place := rank if is_final else place
	_standing_round.text = "Resultado final" if is_final else "Ronda %d/%d" % [data.round, data.total_rounds]
	_standing_cheer.text = _cheer_text(is_final, medal_place)
	_standing_medal.place = medal_place
	_standing_medal.visible = medal_place > 0
	_standing_medal.queue_redraw()
	_standing_bg.place = medal_place
	_standing_bg.queue_redraw()
	_set_headline_size(_standing_main, STANDING_FINAL_SIZE if is_final else STANDING_POINTS_SIZE)
	_standing_main.add_theme_color_override("font_color", UiTheme.GOLD if medal_place == 1 else UiTheme.ACCENT)
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
		_fade_in(_standing_panel, Vector2(60, 0))
	_standing_medal.pop()
	_set_mood(mood_for_standing(data))
	if medal_place == 1:
		_wait_avatar.hop()
	if medal_place >= 1 and medal_place <= 3:
		_confetti.burst(70 if medal_place == 1 else 36)


## La mascota reacciona a cómo te va: feliz si vas ganando (o ganaste la
## ronda, o quedaste en el podio final), triste si vas último, normal si no.
static func mood_for_standing(data: Dictionary) -> int:
	var rank := int(data.get("rank", 0))
	var players := int(data.get("players", 0))
	if rank == 1 or int(data.get("place", 0)) == 1 or (bool(data.get("final", false)) and rank >= 1 and rank <= 3):
		return PlayerAvatar.Mood.HAPPY
	if players > 1 and rank >= players:
		return PlayerAvatar.Mood.SAD
	return PlayerAvatar.Mood.NORMAL


func _set_mood(mood: int) -> void:
	for avatar: PlayerAvatar in [_wait_avatar, _header_avatar]:
		if avatar.mood != mood:
			avatar.mood = mood
			avatar.queue_redraw()


static func _cheer_text(is_final: bool, place: int) -> String:
	if is_final:
		match place:
			1: return "¡Ganaste la competencia!"
			2, 3: return "¡Llegaste al podio!"
		return "¡Gracias por jugar!"
	match place:
		0: return "Esta ronda no jugaste"
		1: return "¡Ganaste la ronda!"
		2: return "¡Casi, casi!"
		3: return "¡Bien ahí!"
	return "¡La próxima es tuya!"


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
	_confetti.stop()
	_update_picker()


func _on_hosts_changed(hosts: Array[Dictionary]) -> void:
	for c in _hosts_box.get_children():
		c.queue_free()
	if hosts.is_empty():
		var empty := _EmptyHosts.new()
		empty.failed = _discovery_failed
		_hosts_box.add_child(empty)
		return
	# Una sola TV y nada elegido todavía: se elige sola (un toque menos).
	if hosts.size() == 1 and _selected_host.is_empty() and _ip_edit.text.strip_edges().is_empty():
		_selected_host = hosts[0]
		_ip_edit.text = hosts[0].ip
	for h in hosts:
		var card := HostCard.new(h.name, "%s · puerto %d" % [h.ip, h.port], _selected_host.get("ip") == h.ip)
		card.pressed.connect(func() -> void:
			Sfx.play("select")
			Haptics.buzz("tap")
			_selected_host = h
			_ip_edit.text = h.ip
			_on_hosts_changed(discovery.get_hosts()))
		_hosts_box.add_child(card)


# --- Acciones -------------------------------------------------------------------

func _on_join_pressed() -> void:
	var player_name := Protocol.sanitize_name(_name_edit.text)
	var code := Protocol.normalize_room_code(_code_edit.text)
	var ip := _ip_edit.text.strip_edges()
	if player_name.is_empty():
		_set_join_status("Contanos cómo te llamás: escribí tu apodo.", true)
		return
	if not Protocol.is_valid_room_code(code):
		_set_join_status("El código son 4 letras o números: copialo de las fichas de la TV.", true)
		return
	if not ip.is_valid_ip_address():
		_set_join_status("Tocá tu TV en la lista, o escribí la dirección que muestra la TV.", true)
		return
	var port := int(_selected_host.get("port", Protocol.WS_PORT)) if _selected_host.get("ip") == ip else Protocol.WS_PORT
	_set_join_status("Conectando con la TV…", false)
	client.join(ip, port, code, player_name, _load_look())


func _on_leave_pressed() -> void:
	client.leave()
	_show_join("")


func _show_join(message: String) -> void:
	if is_instance_valid(_active_layout):
		_active_layout.queue_free()
	_active_layout = null
	_wait_view.visible = true
	_clear_standing()
	_set_instruction("")
	_settings_panel.visible = false
	var was_hidden := not _join_screen.visible
	_play_screen.visible = false
	_join_screen.visible = true
	if was_hidden:
		_fade_in(_join_screen, Vector2(0, 40))
	_set_join_status(message, true)
	_update_power_mode()


## Aviso debajo del botón "Unirme": amable y con ícono. Error: fondo cálido
## y "!"; información ("Conectando…"): fondo celeste y Wi-Fi. Vacío: oculto.
func _set_join_status(message: String, is_error: bool) -> void:
	_join_status.text = message
	_join_status_panel.visible = not message.is_empty()
	var style := _join_status_panel.get_theme_stylebox("panel") as StyleBoxFlat
	style.bg_color = UiTheme.PHONE_ERROR_BG if is_error else UiTheme.PHONE_INFO_BG
	style.border_color = UiTheme.WARNING if is_error else UiTheme.BRICKS[5]
	_join_status_badge.bg = UiTheme.WARNING if is_error else UiTheme.BRICKS[5]
	_join_status_badge.text = "!" if is_error else ""
	_join_status_badge.glyph = "" if is_error else "wifi"
	_join_status_badge.queue_redraw()
	if is_error and not message.is_empty() and _join_screen.visible:
		# Sacudida corta: se nota que algo falta sin asustar.
		var x := _join_status_panel.position.x
		var tw := _join_status_panel.create_tween()
		for dx: float in [14.0, -10.0, 6.0, 0.0]:
			tw.tween_property(_join_status_panel, "position:x", x + dx, 0.05)


func _update_header() -> void:
	var info := client.player_info
	var slot := int(info.get("id", 1)) - 1
	var color: Color = info.get("color", Color.WHITE)
	_header.text = str(info.get("name", ""))
	_header_tag.slot = slot
	_header_tag.color = color
	_header_tag.queue_redraw()
	for avatar in [_header_avatar, _wait_avatar]:
		avatar.slot = slot
		avatar.style = int(info.get("style", -1))  # -1 (TV vieja): el del lugar.
		avatar.color = color
	_player_card.set_player(slot, color, str(info.get("name", "")))
	_player_card.set_status("¡Listo para jugar!")
	_set_backdrop(color, slot, int(info.get("style", -1)))


## Fondo con el color del jugador; el texto que va directo encima se
## adapta (tinta o blanco, UiTheme.text_on) para que se lea con blanco y negro.
func _set_backdrop(color: Color, slot: int, style: int) -> void:
	_backdrop.set_player(color, slot, style)
	# Mascota 3D (ADR 0012): la propia queda horneada; la anterior (si cambió
	# de look en el selector) se suelta sola.
	MascotAtlas.keep_only("phone", [{"color": color, "style": slot if style < 0 else style}])
	_wait_sub.add_theme_color_override("font_color", _backdrop.ink())


## Transición de entrada: aparece y se desliza desde `from` (≤ 0,3 s).
## Solo visual: la pantalla ya recibe toques.
func _fade_in(node: Control, from: Vector2 = Vector2.ZERO) -> void:
	if not node.is_inside_tree():
		return
	node.modulate.a = 0.0
	var tw := node.create_tween().set_parallel()
	tw.tween_property(node, "modulate:a", 1.0, FADE_SEC)
	if from != Vector2.ZERO and node.get_parent() is not Container:
		var target := node.position
		node.position = target + from
		tw.tween_property(node, "position", target, FADE_SEC).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


# --- UI -------------------------------------------------------------------------

func _build_ui() -> void:
	_background = PartyBackground.new()
	_background.bricks = false
	_background.towers = false
	_background.checker_floor = false
	add_child(_background)
	_backdrop = PhoneBackdrop.new()
	_backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_backdrop.visible = false
	add_child(_backdrop)
	_build_join_screen()
	_build_play_screen()
	_confetti = ConfettiBurst.new()
	add_child(_confetti)
	_build_toast()
	_settings_panel = SettingsPanel.new(settings, settings_path)
	_settings_panel.changed.connect(_apply_settings)
	add_child(_settings_panel)


## Pantalla para unirse, en dos columnas (celular apaisado):
##   izquierda: logo + mascota que saluda y el paso 1 (TVs encontradas)
##   derecha:   pasos 2 y 3 (apodo y código en fichas) y "Unirme"
func _build_join_screen() -> void:
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, UiTheme.PHONE_MARGIN)
	add_child(margin)
	_join_screen = margin
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", UiTheme.PHONE_MARGIN)
	margin.add_child(cols)

	# Columna izquierda
	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.size_flags_stretch_ratio = 0.85
	left.add_theme_constant_override("separation", 12)
	cols.add_child(left)
	var brand := HBoxContainer.new()
	brand.custom_minimum_size = Vector2(0, 250)
	brand.add_theme_constant_override("separation", 0)
	left.add_child(brand)
	_join_mascot = PlayerAvatar.new()
	_join_mascot.mood = PlayerAvatar.Mood.HAPPY
	_join_mascot.custom_minimum_size = Vector2(190, 0)
	var look := _load_look()
	_join_mascot.color = Protocol.mascot_color(int(look.get("color", 0)))
	_join_mascot.style = int(look.get("style", -1))
	brand.add_child(_join_mascot)
	var logo := UiTheme.logo_rect()
	logo.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# 5 toques seguidos en el logo: modo desarrollador (latencia en ms).
	logo.mouse_filter = Control.MOUSE_FILTER_STOP
	logo.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton and (event as InputEventMouseButton).pressed:
			_on_logo_tapped())
	brand.add_child(logo)
	var tv_panel := _panel()
	tv_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left.add_child(tv_panel)
	var tv_col := VBoxContainer.new()
	tv_col.add_theme_constant_override("separation", 18)
	tv_panel.add_child(tv_col)
	tv_col.add_child(_step(1, "Elegí tu TV"))
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tv_col.add_child(scroll)
	_hosts_box = VBoxContainer.new()
	_hosts_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_hosts_box.add_theme_constant_override("separation", 16)
	scroll.add_child(_hosts_box)
	tv_col.add_child(UiTheme.label("¿No aparece? Escribí la dirección que muestra la TV:", 28, UiTheme.INK_SOFT, true,
		HORIZONTAL_ALIGNMENT_LEFT))
	_ip_edit = IconField.new("wifi", "Ej.: 192.168.0.10", 15)
	tv_col.add_child(_ip_edit)

	# Columna derecha
	var right := _panel()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cols.add_child(right)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 18)
	right.add_child(col)
	col.add_child(_step(2, "Tu apodo"))
	_name_edit = IconField.new("person", "¿Cómo te llamás?", Protocol.NAME_MAX_LENGTH)
	_name_edit.text = _load_name()
	col.add_child(_name_edit)
	col.add_child(_spacer())
	col.add_child(_step(3, "Código de la TV"))
	_code_edit = CodeEntry.new()
	col.add_child(_code_edit)
	col.add_child(UiTheme.label("Lo ves en la TV, en fichas de colores como estas.", 28, UiTheme.INK_SOFT, true))
	col.add_child(_spacer())
	_join_status_panel = PanelContainer.new()
	var status_style := UiTheme.panel_style(UiTheme.PHONE_ERROR_BG, UiTheme.RADIUS, 14)
	status_style.shadow_size = 0
	status_style.set_border_width_all(3)
	_join_status_panel.add_theme_stylebox_override("panel", status_style)
	col.add_child(_join_status_panel)
	var status_row := HBoxContainer.new()
	status_row.add_theme_constant_override("separation", 16)
	_join_status_panel.add_child(status_row)
	_join_status_badge = GlyphBadge.new("", UiTheme.WARNING, UiTheme.PAPER, 60, "!")
	status_row.add_child(_join_status_badge)
	_join_status = UiTheme.label("", 32, UiTheme.INK, true, HORIZONTAL_ALIGNMENT_LEFT)
	_join_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_join_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	status_row.add_child(_join_status)
	var join := ToyButton.new("¡Unirme!", "play", UiTheme.ACCENT, 56)
	join.custom_minimum_size = Vector2(0, 150)
	join.pressed.connect(_on_join_pressed)
	col.add_child(join)


## Pantalla una vez unido. Arriba, de izquierda a derecha: quién soy
## (mascota, 1P–4P y apodo), qué hacer en este juego (una línea), la señal
## de Wi-Fi (y los ms en modo desarrollador), Ajustes y "Salir" (mantener).
## Abajo, el control que pidió la TV o la vista de espera "¡Mirá la TV!".
func _build_play_screen() -> void:
	_play_screen = VBoxContainer.new()
	_play_screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_play_screen)
	var top_margin := MarginContainer.new()
	for side in ["left", "right", "top"]:
		top_margin.add_theme_constant_override("margin_" + side, UiTheme.PHONE_MARGIN)
	_play_screen.add_child(top_margin)
	var top := HBoxContainer.new()
	top.custom_minimum_size = Vector2(0, UiTheme.PHONE_BAR_HEIGHT)
	top.add_theme_constant_override("separation", 18)
	top_margin.add_child(top)
	# Quién soy: mascota, etiqueta 1P–4P y apodo en una píldora.
	var me := PanelContainer.new()
	var me_style := UiTheme.panel_style(UiTheme.PAPER, int(UiTheme.PHONE_BAR_HEIGHT / 2.0), 6)
	me_style.content_margin_right = 36
	me.add_theme_stylebox_override("panel", me_style)
	me.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	top.add_child(me)
	var me_row := HBoxContainer.new()
	me_row.add_theme_constant_override("separation", 14)
	me.add_child(me_row)
	_header_avatar = PlayerAvatar.new()
	_header_avatar.custom_minimum_size = Vector2(76, 92)
	me_row.add_child(_header_avatar)
	_header_tag = _Tag.new()
	_header_tag.custom_minimum_size = Vector2(92, 60)
	_header_tag.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	me_row.add_child(_header_tag)
	_header = UiTheme.label("", 44, UiTheme.INK, true, HORIZONTAL_ALIGNMENT_LEFT)
	me_row.add_child(_header)
	# Qué hacer en este juego: una línea "de cartel" (blanco con contorno de
	# tinta), legible sobre cualquier color de fondo.
	_instruction = UiTheme.headline("", UiTheme.PHONE_TEXT_BAR + 6)
	_instruction.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_instruction.clip_text = true
	_instruction.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_instruction.visible = false
	top.add_child(_instruction)
	_instruction_gap = Control.new()
	_instruction_gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_instruction_gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(_instruction_gap)
	# Señal: Wi-Fi con barras de color para todos; ms solo en modo desarrollador.
	var signal_pill := PanelContainer.new()
	var pill_style := UiTheme.panel_style(UiTheme.PAPER, 40, 10)
	pill_style.content_margin_left = 20
	pill_style.content_margin_right = 20
	signal_pill.add_theme_stylebox_override("panel", pill_style)
	signal_pill.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	top.add_child(signal_pill)
	var signal_row := HBoxContainer.new()
	signal_row.add_theme_constant_override("separation", 8)
	signal_pill.add_child(signal_row)
	_signal = SignalIcon.new(60)
	signal_row.add_child(_signal)
	_latency = UiTheme.label("— ms", 30, UiTheme.INK_SOFT, true)
	_latency.custom_minimum_size = Vector2(110, 0)
	_latency.visible = false
	signal_row.add_child(_latency)
	_settings_button = ToyButton.new("", "gear", UiTheme.PAPER, 30)
	_settings_button.custom_minimum_size = Vector2(UiTheme.PHONE_BAR_HEIGHT + 12.0, 0)
	_settings_button.pressed.connect(_open_settings)
	top.add_child(_settings_button)
	_leave = HoldButton.new("Salir", "exit", UiTheme.PAPER, 32)
	_leave.custom_minimum_size = Vector2(220, 0)
	_leave.held.connect(_on_leave_pressed)
	_leave.released_early.connect(func() -> void: show_toast("Mantené apretado «Salir» para irte"))
	top.add_child(_leave)
	_layout_host = Control.new()
	_layout_host.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_play_screen.add_child(_layout_host)

	# Vista de espera: tarjeta con la mascota + "¡Mirá la TV!" y, a la
	# derecha, el selector (lobby) o el resultado propio (resumen y podio).
	# Detrás de la tarjeta, rayos de fiesta (los dibuja el fondo, una vez).
	var wait_view := HBoxContainer.new()
	wait_view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	wait_view.offset_bottom = -UiTheme.PHONE_MARGIN
	wait_view.alignment = BoxContainer.ALIGNMENT_CENTER
	wait_view.add_theme_constant_override("separation", 64)
	_layout_host.add_child(wait_view)
	_wait_view = wait_view
	var wait_box := VBoxContainer.new()
	wait_box.alignment = BoxContainer.ALIGNMENT_CENTER
	wait_box.custom_minimum_size = Vector2(620, 0)
	wait_box.add_theme_constant_override("separation", 14)
	wait_view.add_child(wait_box)
	var look_row := HBoxContainer.new()
	look_row.alignment = BoxContainer.ALIGNMENT_CENTER
	look_row.add_theme_constant_override("separation", 16)
	wait_box.add_child(look_row)
	var tv := _TvBadge.new()
	tv.custom_minimum_size = Vector2(92, 92)
	look_row.add_child(tv)
	look_row.add_child(UiTheme.headline("¡Mirá la TV!", 72))
	_player_card = PlayerCard.new()
	_player_card.custom_minimum_size = Vector2(560, 580)
	_player_card.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	wait_box.add_child(_player_card)
	_wait_avatar = _player_card.avatar
	_wait_sub = UiTheme.label("El juego empieza cuando la TV lo elija", 34, UiTheme.INK, true)
	_wait_sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	wait_box.add_child(_wait_sub)
	_build_standing_panel(wait_view)
	_look_picker = LookPicker.new()
	_look_picker.visible = false
	_look_picker.look_changed.connect(_on_look_picked)
	wait_view.add_child(_look_picker)
	for node: Control in [wait_view, wait_box, _player_card]:
		node.item_rect_changed.connect(_update_rays)
	wait_view.visibility_changed.connect(_update_rays)
	# Unido: el fondo es el del jugador (quieto) y el cielo con nubes se
	# oculta (deja de animarse). Sigue a la pantalla, se muestre como se muestre.
	_play_screen.visibility_changed.connect(func() -> void:
		_backdrop.visible = _play_screen.visible
		_background.visible = not _play_screen.visible)
	_play_screen.visible = false


## Rayos de fiesta detrás de la tarjeta mientras se espera (el fondo los
## dibuja una vez; solo se vuelven a dibujar si la tarjeta se movió).
func _update_rays() -> void:
	if _backdrop == null or _player_card == null:
		return
	var at := Vector2.INF
	if _wait_view.visible and _player_card.is_inside_tree():
		# Relativo a la pantalla (no al fondo): así no importa si la pantalla
		# está entrando con su transición (se desliza unos píxeles).
		at = _player_card.get_global_rect().get_center() - _play_screen.get_global_rect().position
	_backdrop.set_rays(at, _player_card.size.length() * 0.75)


## Aviso corto arriba al centro (ej. "Mantené apretado «Salir»…"). Se va
## solo; no queda nada animando.
func _build_toast() -> void:
	var row := HBoxContainer.new()
	row.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	row.offset_top = UiTheme.PHONE_MARGIN + UiTheme.PHONE_BAR_HEIGHT + 18.0
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(row)
	_toast = PanelContainer.new()
	var style := UiTheme.panel_style(UiTheme.CHIP_DARK, 36, 14)
	style.content_margin_left = 36
	style.content_margin_right = 36
	_toast.add_theme_stylebox_override("panel", style)
	_toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toast.visible = false
	row.add_child(_toast)
	_toast_label = UiTheme.label("", UiTheme.PHONE_TEXT_BAR, UiTheme.PAPER, true)
	_toast.add_child(_toast_label)


func show_toast(text: String) -> void:
	_toast_label.text = text
	_toast.visible = true
	_toast.modulate.a = 1.0
	if _toast_tween:
		_toast_tween.kill()
	if not is_inside_tree():
		return
	_toast_tween = create_tween()
	_toast_tween.tween_interval(UiTheme.PHONE_TOAST_SEC)
	_toast_tween.tween_property(_toast, "modulate:a", 0.0, 0.3)
	_toast_tween.tween_callback(func() -> void: _toast.visible = false)


func _open_settings() -> void:
	Sfx.play("select")
	Haptics.buzz("tap")
	_settings_panel.open()


## 5 toques seguidos en el logo (pantalla de unirse) prenden o apagan el
## modo desarrollador. Queda guardado.
func _on_logo_tapped() -> void:
	var now := Time.get_ticks_msec()
	_logo_taps = _logo_taps + 1 if now - _logo_last_tap_ms <= DEV_TAP_WINDOW_MS else 1
	_logo_last_tap_ms = now
	if _logo_taps < DEV_TAPS:
		return
	_logo_taps = 0
	settings.dev_mode = not settings.dev_mode
	settings.save_to(settings_path)
	_apply_settings()
	Haptics.buzz("go")
	_set_join_status("Modo desarrollador: se ve la latencia." if settings.dev_mode else "Modo desarrollador apagado.", false)


func _build_standing_panel(parent: Control) -> void:
	_standing_panel = PanelContainer.new()
	_standing_panel.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	_standing_panel.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_standing_panel.custom_minimum_size = Vector2(1060, 0)
	_standing_panel.visible = false
	parent.add_child(_standing_panel)
	_standing_bg = _StandingBg.new()
	_standing_panel.add_child(_standing_bg)
	var pad := MarginContainer.new()
	for side in ["left", "right"]:
		pad.add_theme_constant_override("margin_" + side, 48)
	pad.add_theme_constant_override("margin_top", 40)
	pad.add_theme_constant_override("margin_bottom", 48)
	_standing_panel.add_child(pad)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	pad.add_child(col)
	var chip := PanelContainer.new()
	var chip_style := UiTheme.panel_style(UiTheme.CHIP_DARK, 30, 8)
	chip_style.shadow_size = 0
	chip_style.content_margin_left = 34
	chip_style.content_margin_right = 34
	chip.add_theme_stylebox_override("panel", chip_style)
	chip.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	col.add_child(chip)
	_standing_round = UiTheme.label("", 38, UiTheme.PAPER, true)
	chip.add_child(_standing_round)
	_standing_cheer = UiTheme.headline("", 64)
	col.add_child(_standing_cheer)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 24)
	col.add_child(row)
	_standing_medal = _Medal.new()
	_standing_medal.custom_minimum_size = Vector2(330, 330)
	row.add_child(_standing_medal)
	var text := VBoxContainer.new()
	text.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_child(text)
	_standing_main = UiTheme.headline("", STANDING_POINTS_SIZE, UiTheme.ACCENT)
	text.add_child(_standing_main)
	_standing_total = UiTheme.label("", 56, UiTheme.INK, true)
	text.add_child(_standing_total)


## Espacio flexible: reparte el alto sobrante entre los pasos.
func _spacer() -> Control:
	var s := Control.new()
	s.size_flags_vertical = Control.SIZE_EXPAND_FILL
	s.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return s


func _panel() -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", UiTheme.panel_style(UiTheme.PAPER, UiTheme.RADIUS + 12, 30))
	return p


## Encabezado de paso: número en un círculo de color (como en la TV) + título.
func _step(n: int, text: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	var colors := [UiTheme.BRICKS[2], UiTheme.BRICKS[5], UiTheme.BRICKS[7]]
	row.add_child(GlyphBadge.new("", colors[(n - 1) % colors.size()], UiTheme.PAPER, 64, str(n)))
	row.add_child(UiTheme.label(text, 44, UiTheme.INK, true, HORIZONTAL_ALIGNMENT_LEFT))
	return row


func _load_name() -> String:
	var cfg := ConfigFile.new()
	if cfg.load(settings_path) == OK:
		return Protocol.sanitize_name(cfg.get_value("player", "name", ""))
	return ""


func _save_name(player_name: String) -> void:
	var cfg := ConfigFile.new()
	cfg.load(settings_path)
	cfg.set_value("player", "name", player_name)
	cfg.save(settings_path)


## Apariencia preferida guardada en el celular (como el apodo). Se valida
## igual que lo que llega por red: un archivo editado a mano no rompe nada.
func _load_look() -> Dictionary:
	var cfg := ConfigFile.new()
	if cfg.load(settings_path) != OK:
		return {}
	return Protocol.parse_look({
		"color": cfg.get_value("player", "color", -1),
		"style": cfg.get_value("player", "style", -1),
	})


func _save_look(color_index: int, style: int) -> void:
	var cfg := ConfigFile.new()
	cfg.load(settings_path)
	cfg.set_value("player", "color", color_index)
	cfg.set_value("player", "style", style)
	cfg.save(settings_path)


## Televisor dentro de un círculo con bisel, junto a "¡Mirá la TV!".
class _TvBadge:
	extends Control

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var c := size / 2.0
		var r := minf(size.x, size.y) / 2.0
		UiTheme.draw_bevel_circle(self, c, r - UiTheme.BEVEL_OUTLINE - 1.0, UiTheme.ACCENT)
		UiTheme.draw_phone_glyph(self, "tv", c - Vector2(0, 3), r * 1.05, UiTheme.INK)


## Etiqueta 1P–4P del encabezado, con el color del jugador.
class _Tag:
	extends Control
	var slot := 0
	var color := UiTheme.PAPER

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var face := UiTheme.draw_toy_key(self, Rect2(Vector2(4, 2), size - Vector2(8, 4)), color, 0.0, size.y * 0.45, 6.0, 4.0)
		UiTheme.draw_text(self, UiTheme.player_tag(slot), face.get_center(), int(face.size.y * 0.66), UiTheme.PAPER, 6, UiTheme.INK)


## Todavía no apareció ninguna TV: tarjeta punteada con el Wi-Fi y qué
## hacer. Estática (sin animación de "buscando": ahorra batería).
class _EmptyHosts:
	extends Control
	var failed := false

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		custom_minimum_size = Vector2(0, UiTheme.PHONE_HOST_CARD_HEIGHT + 20.0)

	func _draw() -> void:
		var r := Rect2(Vector2(4, 4), size - Vector2(8, 8))
		UiTheme.draw_round_rect(self, r, UiTheme.PAPER_DIM, UiTheme.RADIUS)
		# Borde punteado ("todavía no hay nada acá"), con los guiones en un
		# solo lote: con draw_dashed_rect serían ~100 comandos.
		var batch := UiTheme.ShapeBatch.new()
		var inner := r.grow(-4)
		var corner := float(UiTheme.RADIUS)
		var ink := Color(UiTheme.INK_SOFT, 0.5)
		for edge: Array in [[inner.position + Vector2(corner, 0), Vector2(inner.end.x - corner, inner.position.y)],
				[Vector2(inner.position.x + corner, inner.end.y), inner.end - Vector2(corner, 0)],
				[inner.position + Vector2(0, corner), Vector2(inner.position.x, inner.end.y - corner)],
				[Vector2(inner.end.x, inner.position.y + corner), inner.end - Vector2(0, corner)]]:
			var a: Vector2 = edge[0]
			var b: Vector2 = edge[1]
			var length := a.distance_to(b)
			var dir := (b - a) / maxf(length, 1.0)
			var n := Vector2(-dir.y, dir.x) * 2.0
			var t := 0.0
			while t < length:
				var p0 := a + dir * t
				var p1 := a + dir * minf(t + 14.0, length)
				batch.polygon(PackedVector2Array([p0 - n, p1 - n, p1 + n, p0 + n]), ink)
				t += 24.0
		var h := r.size.y
		var badge := Vector2(r.position.x + h * 0.5, r.get_center().y)
		batch.circle(badge, h * 0.3, UiTheme.PAPER)
		batch.flush(self)
		UiTheme.draw_glyph(self, "wifi", badge, h * 0.36, UiTheme.WARNING if failed else UiTheme.BRICKS[5])
		var x := badge.x + h * 0.48
		var title := "No pudimos buscar TVs" if failed else "Buscando TVs en tu Wi-Fi…"
		var hint := "Escribí abajo la dirección que muestra la TV." if failed else "Abrí PARTY-GAME en la TV y usá la misma Wi-Fi."
		UiTheme.draw_text_left(self, title, Vector2(x, r.get_center().y - h * 0.15), int(h * 0.24), UiTheme.INK, r.end.x - x - 16.0)
		UiTheme.draw_text_left(self, hint, Vector2(x, r.get_center().y + h * 0.18), int(h * 0.18), UiTheme.INK_SOFT,
			r.end.x - x - 16.0, false)


## Fondo del resultado: tarjeta blanca con una franja del color de la
## medalla arriba y papelitos quietos alrededor. Se dibuja una vez por
## resultado (sin animación continua).
class _StandingBg:
	extends Control
	var place := 0

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var r := Rect2(Vector2(6, 6), size - Vector2(12, 12))
		UiTheme.draw_round_rect(self, r, UiTheme.PAPER, UiTheme.RADIUS + 16, 0.0, UiTheme.INK, true)
		# Franja de arriba con el color de la medalla (oro, plata, bronce).
		var band := UiTheme.place_color(place) if place > 0 else UiTheme.PAPER_DIM
		var band_h := 104.0
		UiTheme.draw_round_rect(self, Rect2(r.position, Vector2(r.size.x, band_h)), band.lerp(UiTheme.PAPER, 0.45), UiTheme.RADIUS + 16)
		draw_rect(Rect2(r.position + Vector2(0, band_h * 0.5), Vector2(r.size.x, band_h * 0.5)), band.lerp(UiTheme.PAPER, 0.45))
		UiTheme.draw_dashed_line(self, r.position + Vector2(24, band_h), Vector2(r.end.x - 24, r.position.y + band_h),
			Color(UiTheme.INK, 0.15), 4.0)
		# Papelitos fijos (siempre los mismos: semilla fija), en un solo lote.
		var rng := RandomNumberGenerator.new()
		rng.seed = 5
		var batch := UiTheme.ShapeBatch.new()
		for i in 22:
			var p := Vector2(rng.randf_range(r.position.x + 30.0, r.end.x - 30.0), rng.randf_range(r.position.y + 20.0, r.end.y - 20.0))
			var angle := rng.randf_range(-1.2, 1.2)
			# Solo en los bordes: el centro queda libre para el texto.
			if absf(p.x - r.get_center().x) < r.size.x * 0.36 and absf(p.y - r.get_center().y) < r.size.y * 0.3:
				continue
			var col: Color = UiTheme.BRICKS[i % UiTheme.BRICKS.size()]
			batch.polygon(ConfettiBurst.piece_points(p, Vector2(14, 24), angle), Color(col, 0.85))
		batch.flush(self)


## Medalla con el puesto de la ronda (o el final en el podio), con rayos de
## sol detrás si quedó en el podio. Entra con un rebote (pop).
class _Medal:
	extends Control
	var place := 1
	var appear := 1.0:
		set(v):
			appear = v
			queue_redraw()

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func pop() -> void:
		if not is_inside_tree():
			return
		appear = 0.0
		create_tween().tween_property(self, "appear", 1.0, 0.45).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

	func _draw() -> void:
		var c := size / 2.0
		var full := minf(size.x, size.y) / 2.0
		var r := (full * 0.66) * appear
		if r <= 1.0:
			return
		if place >= 1 and place <= 3:
			var ray := Color(UiTheme.place_color(place).lerp(UiTheme.PAPER, 0.3), 0.55)
			var batch := UiTheme.ShapeBatch.new()
			for i in 12:
				var a := TAU * i / 12.0 + 0.2
				batch.polygon(PackedVector2Array([
					c + Vector2.from_angle(a - 0.12) * r * 0.9, c + Vector2.from_angle(a) * full * appear,
					c + Vector2.from_angle(a + 0.12) * r * 0.9,
				]), ray)
			batch.flush(self)
			for k in 3:
				var a := -PI * 0.8 + k * 0.7
				UiTheme.draw_star(self, c + Vector2.from_angle(a) * full * 0.86 * appear, full * 0.1 * appear, UiTheme.GOLD, a)
		UiTheme.draw_medal(self, c, r, place)
