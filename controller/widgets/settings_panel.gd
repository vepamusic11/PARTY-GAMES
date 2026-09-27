class_name SettingsPanel
extends Control
## Ajustes del celular, en un panel sobre un velo (se abre con el engranaje
## de la barra de arriba, también en medio de un juego):
##
##   Sonido · Vibración · Zurdo · Tamaño del control · Modo desarrollador
##
## Cada cambio se aplica y se guarda al instante en el archivo local de
## ajustes (el mismo del apodo): sonido y vibración con Sfx.save_prefs
## (sección [audio]) y el resto con PhoneSettings (sección [controller]).
## Emite `changed` para que ControllerMain lo aplique al control en pantalla.
##
## Los interruptores no dependen solo del color: la perilla cambia de lado y
## encendidos llevan una tilde. Todo se toca (≥ 112 px de alto).

signal changed
signal closed

var settings: PhoneSettings
var settings_path := ""

var _panel: PanelContainer
var _sound: _Row
var _vibration: _Row
var _lefty: _Row
var _dev: _Row
var _sizes: Array[ToyButton] = []


func _init(p_settings: PhoneSettings, p_path: String) -> void:
	settings = p_settings
	settings_path = p_path
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP  # Nada de abajo recibe toques.
	visible = false
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	_panel = PanelContainer.new()
	_panel.add_theme_stylebox_override("panel", UiTheme.panel_style(UiTheme.PAPER, UiTheme.RADIUS + 12, 32))
	_panel.custom_minimum_size = Vector2(1180, 0)
	center.add_child(_panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 12)
	_panel.add_child(col)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 18)
	col.add_child(head)
	var badge := _GearBadge.new()
	badge.custom_minimum_size = Vector2(76, 76)
	head.add_child(badge)
	var title := UiTheme.label("Ajustes", 52, UiTheme.INK, true, HORIZONTAL_ALIGNMENT_LEFT)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	var done := ToyButton.new("Listo", "", UiTheme.ACCENT, 38)
	done.custom_minimum_size = Vector2(220, UiTheme.PHONE_SETTING_ROW_H - 12.0)
	done.pressed.connect(close)
	head.add_child(done)

	_sound = _row(col, "speaker", "Sonido", "Efectos del celular al tocar y al sumar puntos")
	_sound.toggled_on.connect(func(on: bool) -> void:
		Sfx.muted = not on
		_save())
	_vibration = _row(col, "vibrate", "Vibración", "El celular vibra al tocar y cuando te pasa algo")
	_vibration.toggled_on.connect(func(on: bool) -> void:
		Haptics.enabled = on
		_save())
	_lefty = _row(col, "swap", "Zurdo", "Joystick a la derecha y botón a la izquierda")
	_lefty.toggled_on.connect(func(on: bool) -> void:
		settings.lefty = on
		_save())

	# Tamaño del control: tres opciones, la elegida en amarillo y hundida.
	var size_bg := PanelContainer.new()
	var size_style := UiTheme.panel_style(UiTheme.PAPER_DIM, UiTheme.RADIUS, 0)
	size_style.shadow_size = 0
	size_style.content_margin_right = 14
	size_bg.add_theme_stylebox_override("panel", size_style)
	col.add_child(size_bg)
	var size_row := HBoxContainer.new()
	size_row.custom_minimum_size = Vector2(0, UiTheme.PHONE_SETTING_ROW_H - 8.0)
	size_row.add_theme_constant_override("separation", 14)
	size_bg.add_child(size_row)
	var size_info := _Row.new("size", "Tamaño del control", "Para manos chicas o grandes", false)
	size_info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_info.mouse_filter = Control.MOUSE_FILTER_IGNORE
	size_row.add_child(size_info)
	for i in UiTheme.PHONE_CONTROL_SIZE_NAMES.size():
		var b := ToyButton.new(UiTheme.PHONE_CONTROL_SIZE_NAMES[i], "", UiTheme.PAPER_DIM, 32)
		b.custom_minimum_size = Vector2(170, UiTheme.PHONE_SETTING_ROW_H - 24.0)
		b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		b.pressed.connect(_pick_size.bind(i))
		size_row.add_child(b)
		_sizes.append(b)

	_dev = _row(col, "signal", "Modo desarrollador", "Muestra la latencia con la TV en milisegundos")
	_dev.toggled_on.connect(func(on: bool) -> void:
		settings.dev_mode = on
		_save())


func open() -> void:
	sync()
	visible = true
	if is_inside_tree():
		modulate.a = 0.0
		_panel.scale = Vector2.ONE * 0.94
		_panel.pivot_offset = _panel.size / 2.0
		var tw := create_tween().set_parallel()
		tw.tween_property(self, "modulate:a", 1.0, 0.18)
		tw.tween_property(_panel, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func close() -> void:
	if not visible:
		return
	visible = false
	Sfx.play("select")
	Haptics.buzz("tap")
	closed.emit()


## Muestra lo que está guardado (el modo desarrollador también se puede
## prender con 5 toques en el logo, fuera de este panel).
func sync() -> void:
	_sound.on = not Sfx.muted
	_vibration.on = Haptics.enabled
	_lefty.on = settings.lefty
	_dev.on = settings.dev_mode
	for i in _sizes.size():
		_sizes[i].color = UiTheme.ACCENT if i == settings.control_size else UiTheme.PAPER_DIM
		_sizes[i].press = 0.35 if i == settings.control_size else 0.0
		_sizes[i].queue_redraw()


func _pick_size(i: int) -> void:
	settings.control_size = i
	_save()


func _save() -> void:
	Sfx.save_prefs(settings_path)
	settings.save_to(settings_path)
	sync()
	Sfx.play("select")
	Haptics.buzz("tap")
	changed.emit()


func _row(parent: Control, glyph: String, title: String, sub: String) -> _Row:
	var r := _Row.new(glyph, title, sub, true)
	parent.add_child(r)
	return r


func _gui_input(event: InputEvent) -> void:
	# Tocar el velo (fuera del panel) cierra, como en cualquier app.
	if event is InputEventMouseButton and (event as InputEventMouseButton).pressed \
			and not _panel.get_global_rect().has_point((event as InputEventMouseButton).global_position):
		close()
		accept_event()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), UiTheme.PHONE_SCRIM)


## Fila de un ajuste: ícono en un círculo, título, explicación y (si es un
## interruptor) el Sí/No a la derecha. Toda la fila se puede tocar.
class _Row:
	extends BaseButton
	signal toggled_on(on: bool)
	var glyph := ""
	var title := ""
	var sub := ""
	var has_switch := true
	var on := false:
		set(v):
			on = v
			queue_redraw()

	func _init(p_glyph: String, p_title: String, p_sub: String, p_switch: bool) -> void:
		glyph = p_glyph
		title = p_title
		sub = p_sub
		has_switch = p_switch
		focus_mode = Control.FOCUS_NONE
		custom_minimum_size = Vector2(0, UiTheme.PHONE_SETTING_ROW_H)
		pressed.connect(func() -> void:
			on = not on
			toggled_on.emit(on))
		button_down.connect(queue_redraw)
		button_up.connect(queue_redraw)

	func _draw() -> void:
		var r := Rect2(Vector2(0, 4), size - Vector2(0, 8))
		if has_switch:
			UiTheme.draw_round_rect(self, r, UiTheme.PAPER_DIM.darkened(0.05) if is_pressed() else UiTheme.PAPER_DIM, UiTheme.RADIUS)
		var ic := Vector2(r.position.x + r.size.y * 0.55, r.get_center().y)
		draw_circle(ic, r.size.y * 0.36, UiTheme.PAPER)
		if glyph == "swap":
			# Flechas a los dos lados: cambia de mano.
			UiTheme.draw_arrow(self, ic + Vector2(-r.size.y * 0.13, -r.size.y * 0.1), r.size.y * 0.22, Vector2.LEFT, UiTheme.INK)
			UiTheme.draw_arrow(self, ic + Vector2(r.size.y * 0.13, r.size.y * 0.1), r.size.y * 0.22, Vector2.RIGHT, UiTheme.INK)
		elif glyph == "size":
			# Tres perillas de menor a mayor.
			for k in 3:
				draw_circle(ic + Vector2((k - 1) * r.size.y * 0.2, r.size.y * 0.12 - k * r.size.y * 0.04), r.size.y * (0.06 + 0.035 * k), UiTheme.INK)
		else:
			UiTheme.draw_phone_glyph(self, glyph, ic, r.size.y * 0.42, UiTheme.INK)
		var x := ic.x + r.size.y * 0.55
		var right := r.end.x - (UiTheme.PHONE_SWITCH.x + 36.0 if has_switch else 12.0)
		UiTheme.draw_text_left(self, title, Vector2(x, r.get_center().y - r.size.y * 0.17), UiTheme.PHONE_TEXT_SETTING, UiTheme.INK, right - x)
		UiTheme.draw_text_left(self, sub, Vector2(x, r.get_center().y + r.size.y * 0.21), UiTheme.PHONE_TEXT_SETTING_SUB, UiTheme.INK_SOFT, right - x, false)
		if has_switch:
			_draw_switch(Rect2(Vector2(r.end.x - UiTheme.PHONE_SWITCH.x - 24.0, r.get_center().y - UiTheme.PHONE_SWITCH.y / 2.0), UiTheme.PHONE_SWITCH))

	func _draw_switch(t: Rect2) -> void:
		var rad := t.size.y / 2.0
		UiTheme.draw_round_rect(self, t.grow(4), UiTheme.INK, rad + 4)
		UiTheme.draw_round_rect(self, t, UiTheme.SUCCESS if on else UiTheme.MUTED, rad)
		var knob := Vector2(t.end.x - rad if on else t.position.x + rad, t.get_center().y)
		draw_circle(knob + Vector2(0, 3), rad - 6.0, UiTheme.SHADOW)
		draw_circle(knob, rad - 6.0, UiTheme.PAPER)
		if on:
			UiTheme.draw_check(self, knob, rad * 0.8, UiTheme.SUCCESS, 7.0)


class _GearBadge:
	extends Control

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var c := size / 2.0
		var r := minf(size.x, size.y) / 2.0
		UiTheme.draw_bevel_circle(self, c, r - UiTheme.BEVEL_OUTLINE - 1.0, UiTheme.BRICKS[5])
		UiTheme.draw_gear(self, c - Vector2(0, 3), r * 1.1, UiTheme.PAPER, UiTheme.BRICKS[5])
