class_name ToyButton
extends BaseButton
## Botón "de juguete" del celular: cara de color con bisel, brillo y
## sombra, con ícono (UiTheme.draw_phone_glyph) y texto opcionales.
## Al tocarlo la cara baja sobre el canto (squash) y rebota al soltar.
## Sin foco: en el celular todo se toca (el foco con D-pad es de la TV).

var text := "":
	set(v):
		text = v
		queue_redraw()
var glyph := ""
var color := UiTheme.PAPER
var font_size := 34
var ink := UiTheme.INK
## Ícono tachado (ej. sonido apagado).
var off := false:
	set(v):
		off = v
		queue_redraw()
## 0 = arriba, 1 = apretado del todo. Lo anima _animate_press.
var press := 0.0:
	set(v):
		press = v
		queue_redraw()
## Dónde quedó el ícono en el último _draw (lo usa HoldButton para su anillo).
var icon_center := Vector2.ZERO
var icon_size := 0.0


func _init(p_text: String = "", p_glyph: String = "", p_color: Color = UiTheme.PAPER, p_font_size: int = 34) -> void:
	text = p_text
	glyph = p_glyph
	color = p_color
	font_size = p_font_size
	focus_mode = Control.FOCUS_NONE
	button_down.connect(_animate_press.bind(true))
	button_up.connect(_animate_press.bind(false))


func _animate_press(down: bool) -> void:
	var tw := create_tween()
	if down:
		tw.tween_property(self, "press", 1.0, 0.05)
	else:
		tw.tween_property(self, "press", 0.0, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _draw() -> void:
	var depth := minf(UiTheme.PHONE_KEY_DEPTH, size.y * 0.12)
	var radius := minf(UiTheme.RADIUS, size.y * 0.32)
	var face := UiTheme.draw_toy_key(self, Rect2(Vector2(4, 2), size - Vector2(8, 10)), color, press, radius, depth)
	var c := face.get_center()
	var icon := face.size.y * 0.46
	icon_size = icon
	icon_center = c
	if text.is_empty():
		_draw_icon(c, icon)
		return
	var tw := UiTheme.FONT_BOLD.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var gap := icon * 0.35
	var total := tw + (icon + gap if not glyph.is_empty() else 0.0)
	var x := c.x - total / 2.0
	if not glyph.is_empty():
		icon_center = Vector2(x + icon / 2.0, c.y)
		_draw_icon(icon_center, icon)
		x += icon + gap
	UiTheme.draw_text(self, text, Vector2(x + tw / 2.0, c.y), font_size, ink)


## "gear" (ajustes) es propio del celular; el resto, los íconos de UiTheme.
func _draw_icon(c: Vector2, s: float) -> void:
	if glyph == "gear":
		UiTheme.draw_gear(self, c, s * 1.1, ink, color)
	else:
		UiTheme.draw_phone_glyph(self, glyph, c, s, ink, off)
