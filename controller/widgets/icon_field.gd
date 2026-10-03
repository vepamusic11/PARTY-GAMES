class_name IconField
extends LineEdit
## Campo de texto del celular con un ícono a la izquierda (apodo, IP).
## Hundido (borde de arriba más grueso, como un hueco) y alto para tocarlo
## cómodo; con foco, borde amarillo e ícono de color.

var glyph := ""
var glyph_color := UiTheme.BRICKS[5]


func _init(p_glyph: String = "", placeholder: String = "", max_len: int = 0) -> void:
	glyph = p_glyph
	placeholder_text = placeholder
	max_length = max_len
	custom_minimum_size = Vector2(0, UiTheme.PHONE_FIELD_HEIGHT)
	var normal := StyleBoxFlat.new()
	normal.bg_color = UiTheme.PAPER
	normal.set_corner_radius_all(UiTheme.RADIUS)
	normal.set_border_width_all(4)
	normal.border_width_top = 8
	normal.border_color = Color(UiTheme.INK_SOFT, 0.3)
	normal.content_margin_left = UiTheme.PHONE_FIELD_HEIGHT + 8
	normal.content_margin_right = 28
	var focus := normal.duplicate() as StyleBoxFlat
	focus.border_color = UiTheme.ACCENT
	focus.set_border_width_all(6)
	focus.border_width_top = 8
	add_theme_stylebox_override("normal", normal)
	add_theme_stylebox_override("focus", focus)
	add_theme_font_size_override("font_size", 44)
	add_theme_font_override("font", UiTheme.FONT_BOLD)


func _draw() -> void:
	if glyph.is_empty():
		return
	var c := Vector2(size.y * 0.58, size.y / 2.0 + 2.0)
	var r := size.y * 0.3
	var focused := has_focus()
	draw_circle(c, r, glyph_color if focused else UiTheme.PAPER_DIM)
	UiTheme.draw_phone_glyph(self, glyph, c, r * 1.15, UiTheme.PAPER if focused else UiTheme.INK_SOFT)
