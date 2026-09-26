class_name PauseMenu
extends Control
## Menú que abre el botón "Atrás" del control remoto durante la competencia.
##   Seguir jugando        -> cierra el menú
##   Saltar este juego     -> pasa al siguiente sin dar puntos (solo en partida)
##   Terminar competencia  -> muestra el podio con los puntos hasta ahora
##   Sonido: Sí/No         -> silencia la TV (se recuerda entre sesiones)
## Antes, "Atrás" cortaba la partida sin preguntar: un toque accidental
## arruinaba la ronda.

signal resume_requested
signal skip_requested
signal quit_requested
signal sound_toggled

var _subtitle: Label
var _resume: Button
var _skip: Button
var _sound: Button


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	visible = false
	z_index = 20
	var shade := ColorRect.new()
	shade.color = Color(UiTheme.INK, 0.6)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(shade)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UiTheme.panel_style(UiTheme.PAPER, 40, 48))
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 22)
	box.custom_minimum_size = Vector2(620, 0)
	panel.add_child(box)
	box.add_child(UiTheme.label("Pausa", 64, UiTheme.INK, true))
	_subtitle = UiTheme.label("", 28, UiTheme.INK_SOFT)
	box.add_child(_subtitle)
	_resume = _button("Seguir jugando", resume_requested)
	box.add_child(_resume)
	_skip = _button("Saltar este juego", skip_requested)
	box.add_child(_skip)
	box.add_child(_button("Terminar competencia", quit_requested))
	_sound = _button("Sonido: Sí", sound_toggled)
	box.add_child(_sound)


func open(subtitle: String, can_skip: bool) -> void:
	_subtitle.text = subtitle
	_skip.visible = can_skip
	visible = true
	_resume.grab_focus()


func set_sound_on(on: bool) -> void:
	_sound.text = "Sonido: Sí" if on else "Sonido: No"


func close() -> void:
	visible = false


func _button(text: String, sig: Signal) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 92)
	b.pressed.connect(func() -> void: sig.emit())
	return b
