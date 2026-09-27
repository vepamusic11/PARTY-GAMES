class_name TvReadyCard
extends Control
## Jugador en la intro "¿Cómo se juega?": su mascota asomando por arriba de
## una tarjeta con el degradé de su color, la etiqueta 1P–4P, el nombre y
## si ya está listo.
##
##        ( o o )          <- la cabeza sale de la tarjeta
##   (2P)─┤     ├──(✓)     <- etiqueta y, al estar listo, check verde
##   │     Sofi     │
##   │    ¡Listo!   │      <- o "Tocá tu celular" mientras tanto
##   ╰──────────────╯
##
## "Listo" lo decide la TV cuando el jugador toca su celular durante la
## intro (ver GameIntroScreen.on_player_input): el celular no manda ningún
## mensaje nuevo, solo el input de siempre.
##
## Rendimiento: la tarjeta y la etiqueta se dibujan al cambiar de estado; lo
## único que anima por frame es la mascota (respira y parpadea).

const OVERHANG := 34.0        ## Alto libre arriba de la tarjeta para la cabeza.
const LABELS_HEIGHT := 72.0   ## Nombre + estado, abajo.
const RADIUS := 26.0
const TAG_SIZE := Vector2(64, 38)
const CHECK_R := 22.0

var slot := 0
var color := Color.WHITE
var player_id := 0
var checked := false  ## Ya tocó su celular: "¡Listo!".
var _avatar: PlayerAvatar
var _name: Label
var _status: Label
var _front: Control


func _init(player: Dictionary = {}) -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = UiTheme.INTRO_CARD_SIZE
	slot = int(player.get("slot", 0))
	player_id = int(player.get("id", 0))
	color = player.get("color", Protocol.player_color(slot))
	_avatar = PlayerAvatar.new()
	_avatar.slot = slot
	_avatar.color = color
	_avatar.style = PlayerAvatar.style_of(player)
	_avatar.mood = PlayerAvatar.Mood.NORMAL
	_avatar.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_avatar.offset_left = 22
	_avatar.offset_right = -22
	_avatar.offset_top = -4
	_avatar.offset_bottom = -LABELS_HEIGHT - 2.0
	add_child(_avatar)
	var box := VBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	box.offset_top = -LABELS_HEIGHT - 6.0
	box.offset_bottom = -8
	box.offset_left = 8
	box.offset_right = -8
	box.add_theme_constant_override("separation", -6)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(box)
	_name = UiTheme.label(str(player.get("name", "")), 30, UiTheme.INK, true)  # Label: texto plano.
	_name.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_name.clip_text = true
	_name.custom_minimum_size = Vector2(0, 38)
	box.add_child(_name)
	_status = UiTheme.label("", 24, UiTheme.INTRO_WAIT_TEXT, true)
	box.add_child(_status)
	# Etiqueta 1P y check encima de la mascota (un brazo puede pasar por ahí).
	_front = Control.new()
	_front.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_front.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_front.draw.connect(_draw_front)
	add_child(_front)
	resized.connect(func() -> void: pivot_offset = Vector2(size.x / 2.0, size.y))
	_apply()


func is_ready() -> bool:
	return checked


func status_text() -> String:
	return _status.text


## Marca al jugador como listo: check, "¡Listo!", mascota feliz y un saltito.
func set_ready(on: bool, animate: bool = true) -> void:
	if on == checked:
		return
	checked = on
	_apply()
	if on and animate and is_inside_tree():
		Sfx.play("pop", -4.0, 1.0 + slot * 0.08)
		if not UiTheme.reduce_motion:
			_avatar.hop(1)
			create_tween().tween_property(self, "scale", Vector2.ONE, 0.28).from(Vector2.ONE * 1.1) \
				.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _apply() -> void:
	_avatar.mood = PlayerAvatar.Mood.HAPPY if checked else PlayerAvatar.Mood.NORMAL
	_status.text = "¡Listo!" if checked else "Tocá tu celular"
	_status.add_theme_color_override("font_color", UiTheme.INTRO_READY_TEXT if checked else UiTheme.INTRO_WAIT_TEXT)
	queue_redraw()
	_front.queue_redraw()


func _card_rect() -> Rect2:
	return Rect2(Vector2(4, OVERHANG), Vector2(size.x - 8, size.y - OVERHANG - 4))


func _draw() -> void:
	var r := _card_rect()
	UiTheme.draw_round_rect(self, r.grow(3), UiTheme.INK if checked else Color(UiTheme.INK, 0.0), RADIUS + 3)
	UiTheme.draw_round_rect(self, r, UiTheme.PAPER, RADIUS, 0, UiTheme.INK, true)
	var inner := r.grow(-5)
	# Degradé del color del jugador; más suave mientras no está listo.
	var top := color.lerp(UiTheme.PAPER, 0.3 if checked else 0.62)
	UiTheme.draw_gradient_round_rect(self, inner, top, color.lerp(UiTheme.PAPER, 0.92), RADIUS - 5)
	var halo := Vector2(inner.get_center().x, inner.position.y + (inner.size.y - LABELS_HEIGHT) * 0.42)
	var glow := UiTheme.ShapeBatch.new()
	for k in 4:
		glow.circle(halo, inner.size.x * (0.42 - 0.08 * k), UiTheme.HALO)
	glow.flush(self)
	var base := Rect2(Vector2(inner.position.x, inner.end.y - LABELS_HEIGHT - 4), Vector2(inner.size.x, LABELS_HEIGHT + 4))
	UiTheme.draw_gradient_round_rect(self, base, Color(UiTheme.PAPER, 0.0), Color(UiTheme.PAPER, 0.9), RADIUS - 5)


## Etiqueta 1P–4P (arriba a la izquierda) y check de "listo" (a la derecha).
func _draw_front() -> void:
	var r := _card_rect()
	var tag := Rect2(r.position + Vector2(-4, -12), TAG_SIZE)
	UiTheme.draw_round_rect(_front, Rect2(tag.position + Vector2(0, 4), tag.size).grow(3), UiTheme.INK, TAG_SIZE.y / 2.0 + 3)
	UiTheme.draw_round_rect(_front, tag, color, TAG_SIZE.y / 2.0, 3, UiTheme.INK)
	UiTheme.draw_gradient_round_rect(_front, Rect2(tag.position + Vector2(8, 4), Vector2(tag.size.x - 16, tag.size.y * 0.4)),
		UiTheme.GLOSS_TOP, UiTheme.GLOSS_BOTTOM, 8)
	var tag_text := UiTheme.text_on(color)
	UiTheme.draw_text(_front, UiTheme.player_tag(slot), tag.get_center(), 24, tag_text, 5,
		UiTheme.INK if tag_text == UiTheme.PAPER else UiTheme.PAPER)
	if checked:
		var c := Vector2(r.end.x - CHECK_R + 2.0, r.position.y + 4.0)
		UiTheme.draw_bevel_circle(_front, c, CHECK_R, UiTheme.SUCCESS)
		UiTheme.draw_check(_front, c - Vector2(0, 2), CHECK_R * 1.1, UiTheme.PAPER, 6.0)
