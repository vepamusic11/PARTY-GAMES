class_name PauseMenu
extends Control
## Menú que abre el botón "Atrás" del control remoto durante la competencia.
##
##   ╭──────────────── Pausa ────────────────╮   <- franja de cielo
##   │        [ Arena de estrellas ]         │
##   │  (▶) Seguir jugando                   │   <- foco al abrir
##   │  (»|) Saltar este juego               │   (solo en partida)
##   │  (⚑) Salir de la competencia          │   -> pide confirmación
##   │  (🔊) Sonido: Sí   (≈) Movimiento…    │
##   │  [OK] Elegir   [Atrás] Volver al juego│
##   ╰═══════════════════════════════════════╯   <- labio (bisel)
##
##   Seguir jugando          -> cierra el menú
##   Saltar este juego       -> pasa al siguiente sin dar puntos
##   Salir de la competencia -> "¿Salir de la competencia?" [No, seguir] [Sí, salir]
##                              y recién con "Sí" muestra el podio con los
##                              puntos hasta ahora. El foco arranca en "No":
##                              un OK de más nunca corta la partida.
##   Sonido: Sí/No           -> silencia la TV (se recuerda entre sesiones)
##   Movimiento              -> "reducir movimiento" (UiTheme.reduce_motion):
##                              sin rebotes, deslizamientos, sacudidas ni zoom
##                              y menos partículas. Lo guarda HostMain (ADR 0011).
##   ◀ Música ▶ / ◀ Efectos ▶ -> volumen de cada bus (VolumeStepper, ADR 0015)
##   ◀ Estilo ▶               -> estilo de música (MusicStyleStepper, ADR 0017)
##
## "Atrás" con la confirmación abierta vuelve a la lista (no cierra el menú).

signal resume_requested
signal skip_requested
signal quit_requested
signal sound_toggled
signal motion_toggled

const BAND_HEIGHT := 118.0

var _subtitle: Label
var _panel: _BevelPanel
var _list: VBoxContainer
var _confirm: VBoxContainer
var _resume: TvButton
var _skip: TvButton
var _quit: TvButton
var _sound: TvButton
var _motion: TvButton
var _confirm_no: TvButton
var _confirm_yes: TvButton
var _hints: KeyHint
var _confirm_hints: KeyHint


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	visible = false
	z_index = 20
	var shade := ColorRect.new()
	shade.color = UiTheme.PAUSE_SHADE
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(shade)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	_panel = _BevelPanel.new()
	center.add_child(_panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 16)
	box.custom_minimum_size = Vector2(UiTheme.PAUSE_WIDTH, 0)
	_panel.add_child(box)

	var title_row := HBoxContainer.new()
	title_row.alignment = BoxContainer.ALIGNMENT_CENTER
	title_row.custom_minimum_size = Vector2(0, BAND_HEIGHT - 30.0)
	title_row.add_theme_constant_override("separation", 18)
	box.add_child(title_row)
	title_row.add_child(_Badge.new("pause", UiTheme.ACCENT, 76.0))
	title_row.add_child(UiTheme.headline("Pausa", 72))
	_subtitle = UiTheme.label("", 30, UiTheme.INK_SOFT, true)
	_subtitle.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	box.add_child(_subtitle)

	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 10)
	box.add_child(_list)
	_resume = _button("Seguir jugando", "play", UiTheme.SUCCESS)
	_resume.pressed.connect(func() -> void: resume_requested.emit())
	_list.add_child(_resume)
	_skip = _button("Saltar este juego", "skip", UiTheme.BRICKS[5])
	_skip.pressed.connect(func() -> void: skip_requested.emit())
	_list.add_child(_skip)
	_quit = _button("Salir de la competencia", "flag", UiTheme.DANGER)
	_quit.pressed.connect(_show_confirm)
	_list.add_child(_quit)
	var toggles := HBoxContainer.new()
	toggles.add_theme_constant_override("separation", 12)
	_list.add_child(toggles)
	_sound = _button("Sonido: Sí", "speaker", UiTheme.BRICKS[4])
	_sound.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_sound.font_px = 30
	_sound.pressed.connect(func() -> void: sound_toggled.emit())
	toggles.add_child(_sound)
	_motion = _button("", "motion", UiTheme.BRICKS[6])
	_motion.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_motion.font_px = 30
	_motion.pressed.connect(func() -> void: motion_toggled.emit())
	toggles.add_child(_motion)
	_update_motion_label()
	# Volúmenes (ADR 0015): cada uno aplica y guarda su ajuste solo.
	_list.add_child(VolumeStepper.new(AudioMix.BUS_MUSIC, "Música"))
	_list.add_child(VolumeStepper.new(AudioMix.BUS_SFX, "Efectos"))
	_list.add_child(MusicStyleStepper.new())  # Estilo de música (ADR 0017).

	_confirm = VBoxContainer.new()
	_confirm.add_theme_constant_override("separation", 18)
	_confirm.visible = false
	box.add_child(_confirm)
	var warn := CenterContainer.new()
	warn.add_child(_Badge.new("flag", UiTheme.DANGER, 96.0))
	_confirm.add_child(warn)
	_confirm.add_child(UiTheme.headline("¿Salir de la competencia?", 50))
	var body := UiTheme.label("La competencia termina acá y se muestra el podio con los puntos de las rondas jugadas.",
		30, UiTheme.INK, true)
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.custom_minimum_size = Vector2(UiTheme.PAUSE_WIDTH - 40.0, 0)
	_confirm.add_child(body)
	var choices := HBoxContainer.new()
	choices.add_theme_constant_override("separation", 14)
	_confirm.add_child(choices)
	_confirm_no = _button("No, seguir", "play", UiTheme.SUCCESS)
	_confirm_no.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_confirm_no.pressed.connect(_hide_confirm)
	choices.add_child(_confirm_no)
	_confirm_yes = TvButton.new("Sí, salir", UiTheme.PAUSE_DANGER, "flag")
	_confirm_yes.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_confirm_yes.pressed.connect(func() -> void: quit_requested.emit())
	choices.add_child(_confirm_yes)

	var hint_row := CenterContainer.new()
	box.add_child(hint_row)
	var hint_box := HBoxContainer.new()
	hint_row.add_child(hint_box)
	_hints = KeyHint.new()
	_hints.add_hint(["OK"], "Elegir").add_hint(["Atrás"], "Volver al juego")
	hint_box.add_child(_hints)
	_confirm_hints = KeyHint.new()
	_confirm_hints.add_hint(["OK"], "Elegir").add_hint(["Atrás"], "No")
	_confirm_hints.visible = false
	hint_box.add_child(_confirm_hints)


func open(subtitle: String, can_skip: bool) -> void:
	_subtitle.text = subtitle
	_subtitle.visible = not subtitle.is_empty()
	_skip.visible = can_skip
	_set_confirm(false)
	_update_motion_label()
	visible = true
	_resume.grab_focus()
	_pop_in()


func set_sound_on(on: bool) -> void:
	_sound.glyph_off = not on
	_sound.set_label("Sonido: Sí" if on else "Sonido: No")


func close() -> void:
	_set_confirm(false)
	visible = false


## La confirmación de "Salir de la competencia" está a la vista.
func is_confirming() -> bool:
	return visible and _confirm.visible


func _unhandled_input(event: InputEvent) -> void:
	# Atrás con la pregunta abierta: vuelve a la lista (no cierra el menú).
	if is_confirming() and event.is_action_pressed("ui_cancel"):
		_hide_confirm()
		get_viewport().set_input_as_handled()


func _show_confirm() -> void:
	Sfx.play("whoosh")
	_set_confirm(true)
	_confirm_no.grab_focus()
	_pop_in()


func _hide_confirm() -> void:
	_set_confirm(false)
	_quit.grab_focus()


func _set_confirm(on: bool) -> void:
	_confirm.visible = on
	_list.visible = not on
	_hints.visible = not on
	_confirm_hints.visible = on


## HostMain lo llama después de cambiar y guardar el ajuste.
func set_motion_reduced(_reduced: bool) -> void:
	_update_motion_label()


func _update_motion_label() -> void:
	_motion.set_label("Movimiento: Reducido" if UiTheme.reduce_motion else "Movimiento: Normal")


func _pop_in() -> void:
	if not is_inside_tree():
		return
	_panel.pivot_offset = _panel.size / 2.0
	var tw := create_tween().set_parallel()
	tw.tween_property(self, "modulate:a", 1.0, 0.14).from(0.0)
	if not UiTheme.reduce_motion:
		tw.tween_property(_panel, "scale", Vector2.ONE, 0.22).from(Vector2.ONE * 0.92) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _button(text: String, glyph: String, glyph_bg: Color) -> TvButton:
	var b := TvButton.new(text, UiTheme.PAPER, glyph, glyph_bg)
	b.align_left = true
	return b


## Panel con bisel: contorno de tinta, labio oscuro abajo, cuerpo blanco y
## una franja de cielo arriba con el título. Solo se dibuja al cambiar de
## tamaño.
class _BevelPanel:
	extends PanelContainer
	const RADIUS := 44.0
	const LIP := 14.0

	func _init() -> void:
		var pad := StyleBoxEmpty.new()
		pad.content_margin_left = 40
		pad.content_margin_right = 40
		pad.content_margin_top = 20
		pad.content_margin_bottom = 30 + LIP
		add_theme_stylebox_override("panel", pad)
		resized.connect(func() -> void: pivot_offset = size / 2.0)

	func _draw() -> void:
		var o := UiTheme.BEVEL_OUTLINE + 2.0
		var body := Rect2(Vector2(o, o), size - Vector2(o * 2.0, o * 2.0 + LIP))
		var whole := Rect2(body.position, body.size + Vector2(0, LIP))
		UiTheme.draw_round_rect(self, whole.grow(o), UiTheme.INK, RADIUS + o, 0, UiTheme.INK, true)
		UiTheme.draw_round_rect(self, Rect2(body.position + Vector2(0, LIP), body.size), UiTheme.PAPER_DIM.darkened(0.16), RADIUS)
		UiTheme.draw_round_rect(self, body, UiTheme.PAPER, RADIUS)
		# Franja de cielo arriba: se dibuja más alta y se tapa su borde de
		# abajo con papel, así queda recta abajo y redondeada arriba.
		var band := Rect2(body.position, Vector2(body.size.x, PauseMenu.BAND_HEIGHT + RADIUS))
		UiTheme.draw_gradient_round_rect(self, band, UiTheme.BG_SKY_TOP, UiTheme.BG_SKY_MID, RADIUS)
		draw_rect(Rect2(body.position + Vector2(0, PauseMenu.BAND_HEIGHT), Vector2(body.size.x, RADIUS + 2.0)), UiTheme.PAPER)
		draw_rect(Rect2(body.position + Vector2(0, PauseMenu.BAND_HEIGHT - 2.0), Vector2(body.size.x, 4.0)), Color(UiTheme.INK, 0.25))
		UiTheme.draw_gradient_round_rect(self, Rect2(body.position + Vector2(18, 8), Vector2(body.size.x - 36, 34)),
			Color(UiTheme.PAPER, 0.45), Color(UiTheme.PAPER, 0.0), 17)


## Ícono en un círculo con bisel: "pause" (dos barras, junto al título) o
## cualquiera de UiTheme.draw_screen_glyph (la bandera de "¿Salir…?").
class _Badge:
	extends Control
	var glyph := ""
	var color := UiTheme.ACCENT

	func _init(p_glyph: String, p_color: Color, p_size: float) -> void:
		glyph = p_glyph
		color = p_color
		custom_minimum_size = Vector2(p_size, p_size)
		size_flags_vertical = Control.SIZE_SHRINK_CENTER
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var c := size / 2.0
		var r := minf(size.x, size.y) / 2.0 - UiTheme.BEVEL_OUTLINE - 2.0
		UiTheme.draw_bevel_circle(self, c, r, color)
		c.y -= 3.0
		if glyph != "pause":
			UiTheme.draw_screen_glyph(self, glyph, c, r * 1.1, UiTheme.PAPER)
			return
		for k: int in [-1, 1]:
			var bar := Rect2(c + Vector2(k * r * 0.26 - r * 0.12, -r * 0.4), Vector2(r * 0.24, r * 0.8))
			UiTheme.draw_round_rect(self, bar.grow(3), UiTheme.INK, r * 0.14)
			UiTheme.draw_round_rect(self, bar, UiTheme.PAPER, r * 0.1)
