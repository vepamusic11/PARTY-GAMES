extends Control
## Punto de entrada. La misma app corre en la TV (host) y en el celular
## (control); acá se decide qué modo arrancar:
##   1. Argumento de línea de comandos: `godot -- --host` o `-- --controller`
##   2. Dispositivo sin pantalla táctil con Android (Google TV / Android TV) -> host
##   3. Si no, se muestra un selector (útil en desarrollo y en tablets)
##
## En la PC (desarrollo) con `--host` o `--controller`, la ventana no ocupa
## toda la pantalla: la TV va a la izquierda (16:9) y el control a la derecha
## (apaisado, proporción de celular), así se ven las dos a la vez. Ejemplo:
## en un monitor de 1920×1080, la TV queda de ~1150×647 y el control de
## ~720×332 al lado. `--fullscreen` pone la ventana en pantalla completa.
##
## Selector: el fondo de escenario, el logo y dos tarjetas grandes ilustradas
## (TV / celular) que se eligen con ◀ ▶ y OK del control remoto, o tocando.
##
##          PARTY-GAME
##   ¿Qué es este dispositivo?
##   ╭───────────╮  ╭───────────╮
##   │ (TV con   │  │ (celular  │
##   │ mascotas) │  │ joystick) │
##   │ Pantalla  │  │ Control   │
##   ╰───────────╯  ╰───────────╯
##   [◀ ▶] Elegir   [OK] Confirmar

const ARG_HOST := "--host"
const ARG_CONTROLLER := "--controller"
const ARG_FULLSCREEN := "--fullscreen"
const DESKTOP_TV_SHARE := 0.6        ## Parte del ancho de la pantalla para la ventana de la TV.
const DESKTOP_PHONE_ASPECT := 2.17   ## Celular apaisado (ej. 2340×1080).
const DESKTOP_GAP := 16              ## Separación entre las ventanas y con el borde.
const DESKTOP_TOP := 48              ## Margen de arriba: deja a la vista la barra de título.

var _tv_card: TvDeviceCard
var _phone_card: TvDeviceCard


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var args := OS.get_cmdline_user_args()
	if ARG_HOST in args:
		_fit_desktop_window(true, ARG_FULLSCREEN in args)
		_launch(HostMain.new())
	elif ARG_CONTROLLER in args:
		_fit_desktop_window(false, ARG_FULLSCREEN in args)
		_launch(ControllerMain.new())
	elif OS.has_feature("android") and not DisplayServer.is_touchscreen_available():
		_launch(HostMain.new())
	else:
		_build_selector()


## Solo en la PC y con ventana real (no en celulares, TVs, tests ni capturas).
func _fit_desktop_window(is_tv: bool, fullscreen: bool) -> void:
	if not OS.has_feature("pc") or DisplayServer.get_name() == "headless" or get_viewport() != get_tree().root:
		return
	if fullscreen:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
		return
	var area := DisplayServer.screen_get_usable_rect()
	var tv_w := int(area.size.x * DESKTOP_TV_SHARE) - DESKTOP_GAP * 2
	var tv := Vector2i(tv_w, int(tv_w * 9.0 / 16.0))
	var rect := Rect2i(area.position + Vector2i(DESKTOP_GAP, DESKTOP_TOP), tv)
	if not is_tv:
		var w := area.size.x - tv.x - DESKTOP_GAP * 3
		rect = Rect2i(area.position + Vector2i(tv.x + DESKTOP_GAP * 2, DESKTOP_TOP),
			Vector2i(w, int(w / DESKTOP_PHONE_ASPECT)))
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(rect.size)
	DisplayServer.window_set_position(rect.position)


func _launch(screen: Control) -> void:
	for c in get_children():
		c.queue_free()
	_tv_card = null
	_phone_card = null
	if screen is HostMain:
		(screen as HostMain).show_splash = true  # Al abrir la app de verdad, no en tests.
	add_child(screen)


func _build_selector() -> void:
	theme = UiTheme.build()
	add_child(PartyBackground.new())
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, UiTheme.SAFE_MARGIN)
	add_child(margin)
	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 22)
	margin.add_child(box)
	var logo := UiTheme.logo_rect()
	logo.custom_minimum_size = Vector2(0, 190)
	box.add_child(logo)
	box.add_child(UiTheme.headline("¿Qué es este dispositivo?", 56))
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 64)
	box.add_child(row)
	_tv_card = TvDeviceCard.new(TvDeviceCard.Kind.TV, "Pantalla (TV)", "Muestra el juego a todos")
	_tv_card.pressed.connect(func() -> void: _launch(HostMain.new()))
	row.add_child(_tv_card)
	_phone_card = TvDeviceCard.new(TvDeviceCard.Kind.PHONE, "Control (celular)", "Tu control para jugar")
	_phone_card.pressed.connect(func() -> void: _launch(ControllerMain.new()))
	row.add_child(_phone_card)
	# D-pad: ◀ ▶ entre las tarjetas (y no se "escapa" hacia arriba o abajo).
	_tv_card.focus_neighbor_right = _tv_card.get_path_to(_phone_card)
	_tv_card.focus_neighbor_left = _tv_card.get_path_to(_phone_card)
	_phone_card.focus_neighbor_left = _phone_card.get_path_to(_tv_card)
	_phone_card.focus_neighbor_right = _phone_card.get_path_to(_tv_card)
	for card in [_tv_card, _phone_card]:
		card.focus_neighbor_top = card.get_path_to(card)
		card.focus_neighbor_bottom = card.get_path_to(card)
	var hints_row := CenterContainer.new()
	box.add_child(hints_row)
	var hints := KeyHint.new()
	hints.add_hint(["left", "right"], "Elegir").add_hint(["OK"], "Confirmar")
	hints_row.add_child(hints)
	# En un celular (pantalla táctil) lo más probable es "Control": arranca
	# resaltada. En la PC (sin pantalla táctil), "Pantalla".
	if DisplayServer.is_touchscreen_available():
		_phone_card.grab_focus()
	else:
		_tv_card.grab_focus()
