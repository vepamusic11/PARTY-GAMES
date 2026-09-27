class_name GlyphBadge
extends Control
## Ícono chico dentro de un círculo de color: numeritos de pasos ("1", "2",
## "3"), el celular junto a "¡Sumate!", el Wi-Fi, el play del botón "¡A
## jugar!". Si `text` no está vacío dibuja el texto; si no, el ícono
## `glyph` de UiTheme.draw_glyph. Con `bg` transparente queda solo el ícono.

var glyph := ""
var text := ""
var bg := UiTheme.ACCENT
var fg := UiTheme.PAPER
var outline := true


func _init(p_glyph: String = "", p_bg: Color = UiTheme.ACCENT, p_fg: Color = UiTheme.PAPER,
		p_size: float = 56.0, p_text: String = "") -> void:
	glyph = p_glyph
	bg = p_bg
	fg = p_fg
	text = p_text
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(p_size, p_size)
	size_flags_vertical = Control.SIZE_SHRINK_CENTER


func _draw() -> void:
	var c := size / 2.0
	var r := minf(size.x, size.y) / 2.0
	if bg.a > 0.0:
		if outline:
			draw_circle(c + Vector2(0, 3), r - 1.0, bg.darkened(0.3))
		draw_circle(c, r - 3.0, bg)
		# Brillo arriba: mismo lenguaje "juguete" que las mascotas.
		UiTheme.draw_ellipse(self, c - Vector2(0, r * 0.42), r * 0.5, r * 0.2, Color(1, 1, 1, 0.28))
	if not text.is_empty():
		UiTheme.draw_text(self, text, c, int(r * 1.1), fg, maxi(3, int(r * 0.14)), bg.darkened(0.45))
	elif not glyph.is_empty():
		UiTheme.draw_glyph(self, glyph, c, r * (1.05 if bg.a > 0.0 else 1.7), fg)
