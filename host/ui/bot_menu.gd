class_name BotMenu
extends Control
## Menú del lobby para un lugar (1P–4P) con bots (ADR 0010). Se abre con OK
## sobre la tarjeta de un lugar libre o con bot:
##
##   ╭──────────────────────────────╮
##   │ (robot)  Lugar 3P            │
##   │  Sumá un bot: ¿qué tan bien   │
##   │  juega?                       │
##   │ [ Fácil · para empezar      ] │
##   │ [ Normal · parejo           ] │  <- foco en la dificultad actual
##   │ [ Difícil · ¡no perdona!    ] │
##   │ [ Quitar bot                ] │  (solo si ya hay un bot)
##   │ [ Cancelar                  ] │
##   ╰──────────────────────────────╯
##
## Todo con el D-pad: ▲▼ entre opciones (el foco no se escapa del menú), OK
## elige y Atrás cierra sin cambiar nada.

signal difficulty_chosen(difficulty: int)
signal remove_requested
signal closed

const HINTS: Array[String] = ["para empezar", "parejo", "¡no perdona!"]

var _avatar: PlayerAvatar
var _title: Label
var _subtitle: Label
var _choices: Array[Button] = []
var _remove: Button
var _cancel: Button
var _current: int = Bot.Difficulty.NORMAL


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
	panel.add_theme_stylebox_override("panel", UiTheme.panel_style(UiTheme.PAPER, 40, 40))
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 16)
	box.custom_minimum_size = Vector2(UiTheme.BOT_MENU_WIDTH, 0)
	panel.add_child(box)
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 18)
	box.add_child(header)
	_avatar = PlayerAvatar.new()
	_avatar.style = PlayerAvatar.STYLE_ROBOT
	_avatar.mood = PlayerAvatar.Mood.HAPPY
	_avatar.custom_minimum_size = Vector2(120, 130)
	header.add_child(_avatar)
	var texts := VBoxContainer.new()
	texts.alignment = BoxContainer.ALIGNMENT_CENTER
	texts.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(texts)
	_title = UiTheme.label("", 56, UiTheme.INK, true, HORIZONTAL_ALIGNMENT_LEFT)
	texts.add_child(_title)
	_subtitle = UiTheme.label("", 28, UiTheme.INK_SOFT, true, HORIZONTAL_ALIGNMENT_LEFT)
	_subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	texts.add_child(_subtitle)
	for d in Bot.DIFFICULTY_NAMES.size():
		var b := _button("")
		b.pressed.connect(_choose.bind(d))
		box.add_child(b)
		_choices.append(b)
	_remove = _button("Quitar bot")
	_remove.pressed.connect(func() -> void:
		visible = false
		remove_requested.emit()
		closed.emit())
	box.add_child(_remove)
	_cancel = _button("Cancelar")
	_cancel.pressed.connect(_close)
	box.add_child(_cancel)


## Abre el menú del lugar `slot`. has_bot: ya hay un bot (cambiar o quitar);
## si no, elegir la dificultad lo agrega. `color`: el del bot o el del lugar.
func open(slot: int, has_bot: bool, difficulty: int, color: Color) -> void:
	_current = clampi(difficulty, 0, _choices.size() - 1)
	_title.text = "Lugar %s" % UiTheme.player_tag(slot)
	_subtitle.text = "Cambiá qué tan bien juega o quitalo." if has_bot else "Sumá un bot: ¿qué tan bien juega?"
	_avatar.color = color
	for d in _choices.size():
		var mark := " (ahora)" if has_bot and d == _current else ""
		_choices[d].text = "%s · %s%s" % [Bot.difficulty_name(d), HINTS[d], mark]
	_remove.visible = has_bot
	visible = true
	_wire_focus()
	_choices[_current].grab_focus()


func is_open() -> bool:
	return visible


## Primero el pedido y después "closed" (quien escucha sabe de qué lugar era).
func _choose(difficulty: int) -> void:
	visible = false
	difficulty_chosen.emit(difficulty)
	closed.emit()


func _close() -> void:
	if not visible:
		return
	visible = false
	closed.emit()


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		_close()
		get_viewport().set_input_as_handled()


## El foco da la vuelta dentro del menú (▲ en la primera va a la última) y
## ◀ ▶ no hacen nada: nunca se escapa a la pantalla de atrás.
func _wire_focus() -> void:
	var items: Array[Button] = []
	for b in _choices + [_remove, _cancel]:
		if b.visible:
			items.append(b)
	for i in items.size():
		var b := items[i]
		b.focus_neighbor_top = b.get_path_to(items[posmod(i - 1, items.size())])
		b.focus_neighbor_bottom = b.get_path_to(items[posmod(i + 1, items.size())])
		b.focus_neighbor_left = b.get_path_to(b)
		b.focus_neighbor_right = b.get_path_to(b)


func _button(text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = UiTheme.BOT_MENU_BUTTON
	return b
