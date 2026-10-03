class_name PlayerCard
extends Control
## Tarjeta del jugador en el celular mientras espera: la mascota grande
## (vista previa del selector), la etiqueta 1P–4P, el apodo y el estado.
## Mismo lenguaje que las tarjetas del lobby de la TV (SeatCard): fondo
## teñido con el color del jugador y un halo detrás de la mascota.
##
## Estático: solo la mascota se anima (a los cuadros por segundo que le
## ponga ControllerMain); la tarjeta se redibuja cuando cambia algo.

var avatar: PlayerAvatar
var slot := 0
var color := UiTheme.PAPER
var _name: Label
var _status: Label


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var box := VBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	box.offset_top = 64
	box.offset_bottom = -30
	box.add_theme_constant_override("separation", 2)
	add_child(box)
	avatar = PlayerAvatar.new()
	avatar.mood = PlayerAvatar.Mood.HAPPY
	avatar.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(avatar)
	# El apodo llega de la red: Label (texto plano).
	_name = UiTheme.label("", 52, UiTheme.INK, true)
	_name.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_name.clip_text = true
	box.add_child(_name)
	_status = UiTheme.label("", 34, UiTheme.SUCCESS, true)
	box.add_child(_status)


func set_player(p_slot: int, p_color: Color, player_name: String) -> void:
	slot = p_slot
	color = p_color
	_name.text = player_name
	queue_redraw()


func set_status(text: String, status_color: Color = UiTheme.SUCCESS) -> void:
	_status.text = text
	_status.add_theme_color_override("font_color", status_color)


func _draw() -> void:
	var r := Rect2(Vector2(6, 6), size - Vector2(12, 12))
	UiTheme.draw_round_rect(self, r, UiTheme.PAPER, UiTheme.RADIUS + 12, 0.0, UiTheme.INK, true)
	var inner := r.grow(-10)
	UiTheme.draw_round_rect(self, inner, color.lerp(UiTheme.PAPER, UiTheme.PHONE_TINT), UiTheme.RADIUS + 4)
	# Halo y "piso" de la mascota: de un solo lote (un draw call).
	var halo := Vector2(inner.get_center().x, inner.position.y + inner.size.y * 0.4)
	var glow := UiTheme.ShapeBatch.new()
	for k in 3:
		glow.circle(halo, inner.size.x * (0.42 - 0.1 * k), Color(color.lerp(UiTheme.PAPER, 0.62 - 0.12 * k), 0.5))
	glow.flush(self)
	# Etiqueta 1P–4P: se distingue sin depender del color.
	var tag := Rect2(r.position + Vector2(20, 18), Vector2(104, 58))
	UiTheme.draw_toy_key(self, tag, color, 0.0, 29.0, 6.0, 4.0)
	UiTheme.draw_text(self, UiTheme.player_tag(slot), tag.get_center() - Vector2(0, 3), 38, UiTheme.PAPER, 6, UiTheme.INK)
