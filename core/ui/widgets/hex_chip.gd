class_name HexChip
extends Control
## Chip de marcador [ 1P | 345 ]. El número se anima contando hacia el
## valor nuevo (set_value), así se nota cuánto sumó cada jugador.

var tag := ""
var tag_color := Color.WHITE
var text := ""
var rainbow := false
var display_value := 0.0:
	set(v):
		display_value = v
		text = str(roundi(v))
		queue_redraw()


func _init(p_tag: String = "", p_tag_color: Color = Color.WHITE, p_text: String = "") -> void:
	tag = p_tag
	tag_color = p_tag_color
	text = p_text
	custom_minimum_size = Vector2(250, 62)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func set_text(value: String) -> void:
	text = value
	queue_redraw()


func set_value(value: int, animate: bool = true, duration: float = 0.9) -> void:
	if not animate or not is_inside_tree():
		display_value = value
		return
	create_tween().tween_property(self, "display_value", float(value), duration) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


func _draw() -> void:
	UiTheme.draw_hex_chip(self, Rect2(Vector2(6, 6), size - Vector2(12, 12)), tag, tag_color, text, rainbow)
