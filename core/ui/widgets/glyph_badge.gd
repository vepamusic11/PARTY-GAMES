class_name GlyphBadge
extends Control
## Ícono chico dentro de un círculo de color: numeritos de pasos ("1", "2",
## "3"), el celular junto a "¡Sumate!", el Wi-Fi, el joystick de "¿A qué
## jugamos?". Si `text` no está vacío dibuja el texto; si no, el ícono
## `glyph` de UiTheme.draw_glyph. Con `bg` transparente queda solo el ícono.
##
## El círculo lleva el mismo bisel que las fichas y botones del lobby
## (contorno, labio oscuro abajo y brillo arriba): se lee como una pieza de
## juguete, no como un punto plano.

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
			UiTheme.draw_bevel_circle(self, c, r - UiTheme.BEVEL_OUTLINE - 1.0, bg)
		else:
			draw_circle(c, r - 3.0, bg)
		c.y -= maxf(3.0, r * 0.14) * 0.5  # El contenido va sobre la cara de arriba.
	if not text.is_empty():
		UiTheme.draw_text(self, text, c, int(r * 1.05), fg, maxi(4, int(r * 0.18)), UiTheme.INK)
	elif not glyph.is_empty():
		UiTheme.draw_glyph(self, glyph, c, r * (1.0 if bg.a > 0.0 else 1.7), fg)
