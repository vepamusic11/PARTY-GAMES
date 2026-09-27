extends Control
## Punto de entrada. La misma app corre en la TV (host) y en el celular
## (control); acá se decide qué modo arrancar:
##   1. Argumento de línea de comandos: `godot -- --host` o `-- --controller`
##   2. Dispositivo sin pantalla táctil con Android (Google TV / Android TV) -> host
##   3. Si no, se muestra un selector (útil en desarrollo y en tablets)

const ARG_HOST := "--host"
const ARG_CONTROLLER := "--controller"


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var args := OS.get_cmdline_user_args()
	if ARG_HOST in args:
		_launch(HostMain.new())
	elif ARG_CONTROLLER in args:
		_launch(ControllerMain.new())
	elif OS.has_feature("android") and not DisplayServer.is_touchscreen_available():
		_launch(HostMain.new())
	else:
		_build_selector()


func _launch(screen: Control) -> void:
	for c in get_children():
		c.queue_free()
	if screen is HostMain:
		(screen as HostMain).show_splash = true  # Al abrir la app de verdad, no en tests.
	add_child(screen)


func _build_selector() -> void:
	theme = UiTheme.build()
	add_child(PartyBackground.new())
	var box := VBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 40)
	add_child(box)
	var logo := UiTheme.logo_rect()
	logo.custom_minimum_size = Vector2(0, 260)
	box.add_child(logo)
	box.add_child(UiTheme.headline("¿Qué es este dispositivo?", 56))
	var tv := _big_button("Pantalla (TV)", func() -> void: _launch(HostMain.new()))
	box.add_child(tv)
	box.add_child(_big_button("Control (celular)", func() -> void: _launch(ControllerMain.new())))
	tv.grab_focus()


func _big_button(text: String, action: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(700, 160)
	b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	b.add_theme_font_size_override("font_size", 52)
	b.pressed.connect(action)
	return b
