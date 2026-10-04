class_name HostCard
extends BaseButton
## Tarjeta grande de una TV encontrada en la Wi-Fi: ícono de TV, nombre,
## dirección y un tilde cuando está elegida. El nombre llega por la red:
## se dibuja con draw_string (texto plano, nunca BBCode).

var host_name := ""
var ip := ""
var selected := false:
	set(v):
		selected = v
		queue_redraw()
var _press := 0.0:
	set(v):
		_press = v
		queue_redraw()


func _init(p_name: String = "", p_ip: String = "", p_selected: bool = false) -> void:
	host_name = p_name
	ip = p_ip
	selected = p_selected
	focus_mode = Control.FOCUS_NONE
	custom_minimum_size = Vector2(0, UiTheme.PHONE_HOST_CARD_HEIGHT)
	button_down.connect(func() -> void: create_tween().tween_property(self, "_press", 1.0, 0.05))
	button_up.connect(func() -> void:
		create_tween().tween_property(self, "_press", 0.0, 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT))


func _draw() -> void:
	var bg := UiTheme.ACCENT.lerp(UiTheme.PAPER, 0.6) if selected else UiTheme.PAPER
	var face := UiTheme.draw_toy_key(self, Rect2(Vector2(6, 4), size - Vector2(12, 14)), bg, _press, UiTheme.RADIUS, 10.0)
	if selected:
		UiTheme.draw_round_rect(self, face.grow(UiTheme.FOCUS_WIDTH), Color.TRANSPARENT, UiTheme.RADIUS + UiTheme.FOCUS_WIDTH,
			UiTheme.FOCUS_WIDTH, UiTheme.ACCENT)
	var h := face.size.y
	var badge := Vector2(face.position.x + h * 0.55, face.get_center().y)
	draw_circle(badge + Vector2(0, 4), h * 0.36, UiTheme.BRICKS[5].darkened(UiTheme.PHONE_BEVEL_DARKEN))
	draw_circle(badge, h * 0.36, UiTheme.BRICKS[5])
	UiTheme.draw_phone_glyph(self, "tv", badge, h * 0.42, UiTheme.PAPER)
	var x := badge.x + h * 0.55
	var right := face.end.x - h * 0.95
	UiTheme.draw_text_left(self, host_name, Vector2(x, face.get_center().y - h * 0.16), int(h * 0.34), UiTheme.INK, right - x)
	UiTheme.draw_text_left(self, ip, Vector2(x, face.get_center().y + h * 0.22), int(h * 0.25), UiTheme.INK_SOFT, right - x, false)
	var mark := Vector2(face.end.x - h * 0.5, face.get_center().y)
	if selected:
		draw_circle(mark, h * 0.3, UiTheme.INK)
		draw_circle(mark, h * 0.3 - 4.0, UiTheme.SUCCESS)
		UiTheme.draw_check(self, mark, h * 0.3, UiTheme.PAPER, 7.0)
	else:
		draw_circle(mark, h * 0.3, UiTheme.PAPER_DIM)
		UiTheme.draw_arrow(self, mark + Vector2(h * 0.03, 0), h * 0.3, Vector2.RIGHT, UiTheme.INK_SOFT)
