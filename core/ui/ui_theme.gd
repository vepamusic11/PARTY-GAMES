class_name UiTheme
extends RefCounted
## Sistema visual compartido por la TV y el celular: paleta, tipografía,
## estilos de los controles de Godot y funciones de dibujo reutilizables.
##
## Regla: ninguna pantalla ni minijuego define colores o tamaños "sueltos";
## todo sale de acá. Cambiar la identidad visual = tocar un solo archivo.
##
## Concepto: *design tokens*. Son constantes con nombre de intención
## (INK = "tinta del texto", ACCENT = "llamado a la acción") en vez de
## valores crudos (#1D2140). Ejemplo: si mañana el foco pasa de amarillo a
## blanco, se cambia ACCENT y se actualizan todas las pantallas a la vez.

const FONT_BOLD := preload("res://assets/fonts/Fredoka-Bold.ttf")
const FONT_SEMI := preload("res://assets/fonts/Fredoka-SemiBold.ttf")

# --- Paleta -------------------------------------------------------------------
const SKY_TOP := Color("#4FB3F6")
const SKY_BOTTOM := Color("#CDEBFF")
const INK := Color("#1D2140")          ## Texto principal y contornos.
const INK_SOFT := Color("#565C85")     ## Texto secundario.
const MUTED := Color("#9AA0BE")        ## Deshabilitado / pistas.
const PAPER := Color("#FFFFFF")        ## Tarjetas y paneles.
const PAPER_DIM := Color("#EEF2FA")
const CHIP_DARK := Color("#1C1F33")    ## Fondo de números (marcadores).
const ACCENT := Color("#FFC83D")       ## Foco del D-pad y acción principal.
const SUCCESS := Color("#27B26B")
const WARNING := Color("#F28C28")
const DANGER := Color("#E5484D")
const SHADOW := Color(0.07, 0.1, 0.3, 0.22)
const GOLD := Color("#FFC53D")
const SILVER := Color("#C9D1E0")
const BRONZE := Color("#E0955A")
## Colores de los bloques decorativos (bordes y torres del fondo).
const BRICKS: Array[Color] = [
	Color("#F0524F"), Color("#FF9F2E"), Color("#FFD23F"), Color("#3CC46B"),
	Color("#2EC4D6"), Color("#3E7BFA"), Color("#9B5DE5"), Color("#F26CB5"),
]

# --- Medidas ------------------------------------------------------------------
const SAFE_MARGIN := 64      ## Margen contra el *overscan* (TVs que recortan bordes).
const RADIUS := 28
const FOCUS_WIDTH := 8.0

# Estilo reutilizado para dibujar rectángulos redondeados sin crear
# objetos en cada frame (los minijuegos dibujan 60 veces por segundo).
static var _box: StyleBoxFlat


## Tema de Godot con los estilos de Button, LineEdit, paneles y scroll.
## Se asigna a la raíz de cada pantalla (`theme = UiTheme.build()`).
static func build() -> Theme:
	var t := Theme.new()
	t.default_font = FONT_SEMI
	t.default_font_size = 30
	t.set_color("font_color", "Label", INK)

	t.set_font("font", "Button", FONT_BOLD)
	t.set_font_size("font_size", "Button", 34)
	for key in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_hover_pressed_color"]:
		t.set_color(key, "Button", INK)
	t.set_color("font_disabled_color", "Button", MUTED)
	t.set_stylebox("normal", "Button", button_style(PAPER))
	t.set_stylebox("hover", "Button", button_style(Color("#F7F9FF")))
	t.set_stylebox("pressed", "Button", button_style(PAPER_DIM, true))
	t.set_stylebox("disabled", "Button", button_style(Color(1, 1, 1, 0.5)))
	t.set_stylebox("focus", "Button", focus_ring())

	var edit := StyleBoxFlat.new()
	edit.bg_color = PAPER
	edit.set_corner_radius_all(22)
	edit.set_border_width_all(4)
	edit.border_color = Color(INK_SOFT, 0.35)
	edit.content_margin_left = 28
	edit.content_margin_right = 28
	var edit_focus := edit.duplicate() as StyleBoxFlat
	edit_focus.border_color = ACCENT
	edit_focus.set_border_width_all(6)
	t.set_stylebox("normal", "LineEdit", edit)
	t.set_stylebox("focus", "LineEdit", edit_focus)
	t.set_font_size("font_size", "LineEdit", 40)
	t.set_color("font_color", "LineEdit", INK)
	t.set_color("font_placeholder_color", "LineEdit", MUTED)
	t.set_color("caret_color", "LineEdit", INK)
	t.set_color("selection_color", "LineEdit", Color(ACCENT, 0.5))

	t.set_stylebox("panel", "PanelContainer", panel_style())
	t.set_stylebox("panel", "ScrollContainer", StyleBoxEmpty.new())
	var grabber := StyleBoxFlat.new()
	grabber.bg_color = Color(INK, 0.35)
	grabber.set_corner_radius_all(6)
	grabber.content_margin_left = 6
	grabber.content_margin_right = 6
	t.set_stylebox("grabber", "VScrollBar", grabber)
	t.set_stylebox("grabber_highlight", "VScrollBar", grabber)
	t.set_stylebox("grabber_pressed", "VScrollBar", grabber)
	t.set_stylebox("scroll", "VScrollBar", StyleBoxEmpty.new())
	return t


# --- Estilos ------------------------------------------------------------------

## Botón "de juguete": borde inferior más oscuro que simula relieve.
## Al apretarlo el relieve baja, como una tecla física.
static func button_style(bg: Color, pressed: bool = false) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.set_corner_radius_all(RADIUS)
	s.border_color = bg.darkened(0.18)
	s.border_width_bottom = 3 if pressed else 9
	s.content_margin_left = 32
	s.content_margin_right = 32
	s.content_margin_top = 20 if pressed else 14
	s.content_margin_bottom = 14
	s.shadow_color = SHADOW
	s.shadow_size = 4 if pressed else 10
	s.shadow_offset = Vector2(0, 4 if pressed else 8)
	return s


## Anillo de foco: tiene que verse desde el sillón (3 metros).
static func focus_ring(radius: int = RADIUS + 6) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.draw_center = false
	s.set_border_width_all(int(FOCUS_WIDTH))
	s.border_color = ACCENT
	s.set_corner_radius_all(radius)
	s.set_expand_margin_all(10)
	s.shadow_color = Color(INK, 0.55)
	s.shadow_size = 6
	return s


static func panel_style(bg: Color = PAPER, radius: int = RADIUS + 8, pad: int = 32) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.set_corner_radius_all(radius)
	s.set_content_margin_all(pad)
	s.shadow_color = SHADOW
	s.shadow_size = 18
	s.shadow_offset = Vector2(0, 10)
	return s


# --- Fábricas de nodos ----------------------------------------------------------

static func label(text: String, size: int = 30, color: Color = INK, bold: bool = false,
		align: HorizontalAlignment = HORIZONTAL_ALIGNMENT_CENTER) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = align
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	if bold:
		l.add_theme_font_override("font", FONT_BOLD)
	return l


## Texto "de cartel": relleno de color, contorno grueso y sombra dura.
## Es el estilo de los "+100" y títulos de las referencias.
static func headline(text: String, size: int, fill: Color = PAPER, outline: Color = INK) -> Label:
	var l := label(text, size, fill, true)
	var px := maxi(6, size / 7)
	l.add_theme_constant_override("outline_size", px)
	l.add_theme_color_override("font_outline_color", outline)
	l.add_theme_color_override("font_shadow_color", Color(INK, 0.6))
	l.add_theme_constant_override("shadow_offset_x", 0)
	l.add_theme_constant_override("shadow_offset_y", maxi(3, size / 18))
	l.add_theme_constant_override("shadow_outline_size", px)
	return l


# --- Textos de apoyo ------------------------------------------------------------

## "1P", "2P"… como en los marcadores de las consolas.
static func player_tag(slot: int) -> String:
	return "%dP" % (slot + 1)


static func place_text(place: int) -> String:
	return "%d°" % place


static func place_color(place: int) -> Color:
	match place:
		1: return GOLD
		2: return SILVER
		3: return BRONZE
	return PAPER_DIM


static func rainbow(t: float) -> Color:
	return Color.from_hsv(fposmod(t, 1.0), 0.75, 1.0)


# --- Dibujo (sirve para Control y para Node2D) -----------------------------------

static func draw_round_rect(ci: CanvasItem, rect: Rect2, color: Color, radius: float = RADIUS,
		border: float = 0.0, border_color: Color = INK, shadow: bool = false) -> void:
	if _box == null:
		_box = StyleBoxFlat.new()
	_box.bg_color = color
	_box.set_corner_radius_all(int(radius))
	_box.set_border_width_all(int(border))
	_box.border_color = border_color
	_box.shadow_color = SHADOW if shadow else Color.TRANSPARENT
	_box.shadow_size = 12 if shadow else 0
	_box.shadow_offset = Vector2(0, 8)
	_box.corner_detail = 8
	_box.draw(ci.get_canvas_item(), rect)


## Borde punteado (ej. "acá falta un jugador"). Omite las esquinas redondeadas.
static func draw_dashed_rect(ci: CanvasItem, rect: Rect2, color: Color, width: float = 4.0,
		corner: float = RADIUS, dash: float = 14.0, gap: float = 10.0) -> void:
	var tl := rect.position
	var br := rect.end
	draw_dashed_line(ci, tl + Vector2(corner, 0), Vector2(br.x - corner, tl.y), color, width, dash, gap)
	draw_dashed_line(ci, Vector2(tl.x + corner, br.y), br - Vector2(corner, 0), color, width, dash, gap)
	draw_dashed_line(ci, tl + Vector2(0, corner), Vector2(tl.x, br.y - corner), color, width, dash, gap)
	draw_dashed_line(ci, Vector2(br.x, tl.y + corner), br - Vector2(0, corner), color, width, dash, gap)


static func draw_dashed_line(ci: CanvasItem, a: Vector2, b: Vector2, color: Color, width: float = 4.0,
		dash: float = 14.0, gap: float = 10.0) -> void:
	var length := a.distance_to(b)
	if length <= 0.0:
		return
	var dir := (b - a) / length
	var t := 0.0
	while t < length:
		ci.draw_line(a + dir * t, a + dir * minf(t + dash, length), color, width)
		t += dash + gap


## Texto centrado en `center` (horizontal y verticalmente).
static func draw_text(ci: CanvasItem, text: String, center: Vector2, size: int, color: Color = INK,
		outline: int = 0, outline_color: Color = INK, bold: bool = true) -> void:
	var font: Font = FONT_BOLD if bold else FONT_SEMI
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	var baseline := center.y + (font.get_ascent(size) - font.get_descent(size)) / 2.0
	var pos := Vector2(center.x - w / 2.0, baseline)
	if outline > 0:
		ci.draw_string_outline(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, outline, outline_color)
	ci.draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)


## Texto alineado a la izquierda, con recorte si no entra en `max_width`.
static func draw_text_left(ci: CanvasItem, text: String, pos_left_center: Vector2, size: int,
		color: Color = INK, max_width: float = -1.0, bold: bool = true) -> void:
	var font: Font = FONT_BOLD if bold else FONT_SEMI
	var baseline := pos_left_center.y + (font.get_ascent(size) - font.get_descent(size)) / 2.0
	ci.draw_string(font, Vector2(pos_left_center.x, baseline), text, HORIZONTAL_ALIGNMENT_LEFT,
		max_width, size, color, TextServer.JUSTIFICATION_NONE)


static func ellipse_points(center: Vector2, rx: float, ry: float, rotation: float = 0.0, steps: int = 28) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in steps:
		var a := TAU * i / steps
		pts.append(center + Vector2(cos(a) * rx, sin(a) * ry).rotated(rotation))
	return pts


static func draw_ellipse(ci: CanvasItem, center: Vector2, rx: float, ry: float, color: Color, rotation: float = 0.0) -> void:
	ci.draw_colored_polygon(ellipse_points(center, rx, ry, rotation), color)


static func star_points(center: Vector2, r: float, inner: float = 0.48, rotation: float = 0.0) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in 10:
		var a := -PI / 2.0 + rotation + PI * i / 5.0
		var rr := r if i % 2 == 0 else r * inner
		pts.append(center + Vector2(cos(a), sin(a)) * rr)
	return pts


static func draw_star(ci: CanvasItem, center: Vector2, r: float, color: Color = GOLD, rotation: float = 0.0) -> void:
	var outline := star_points(center, r, 0.48, rotation)
	ci.draw_colored_polygon(star_points(center, r + 5.0, 0.5, rotation), INK)
	ci.draw_colored_polygon(outline, color)
	ci.draw_colored_polygon(star_points(center + Vector2(-r * 0.12, -r * 0.12), r * 0.35, 0.5, rotation), Color(1, 1, 1, 0.55))


## Medalla redonda con el puesto ("1°" en oro, "2°" plata, "3°" bronce).
static func draw_medal(ci: CanvasItem, center: Vector2, r: float, place: int) -> void:
	ci.draw_circle(center, r + maxf(4.0, r * 0.1), INK)
	ci.draw_circle(center, r, place_color(place))
	ci.draw_circle(center + Vector2(-r, -r) * 0.27, r / 3.0, Color(1, 1, 1, 0.4))
	draw_text(ci, place_text(place), center + Vector2(2, 1) * (r / 30.0), int(r), INK)


static func draw_check(ci: CanvasItem, center: Vector2, s: float, color: Color = PAPER, width: float = 6.0) -> void:
	ci.draw_polyline(PackedVector2Array([
		center + Vector2(-0.5, 0.0) * s, center + Vector2(-0.15, 0.35) * s, center + Vector2(0.5, -0.35) * s,
	]), color, width, true)


## Flecha triangular (la tipografía no trae ◀ ▶: se dibujan).
static func draw_arrow(ci: CanvasItem, center: Vector2, s: float, dir: Vector2, color: Color) -> void:
	var d := dir.normalized()
	var n := Vector2(-d.y, d.x)
	ci.draw_colored_polygon(PackedVector2Array([
		center + d * s * 0.6, center - d * s * 0.4 + n * s * 0.55, center - d * s * 0.4 - n * s * 0.55,
	]), color)


## Ícono del control que muestra el celular en un juego (joystick, slider o
## botón). Lo usan la tarjeta del lobby y la pantalla "¿Cómo se juega?".
## `s` es el radio del elemento principal; `a`, la opacidad.
static func draw_control_icon(ci: CanvasItem, c: Vector2, s: float, layout: String, a: float = 1.0) -> void:
	var white := Color(PAPER, a)
	var ink := Color(INK, a)
	var line := maxf(4.0, s * 0.06)
	match layout:
		Protocol.LAYOUT_JOYSTICK:
			ci.draw_circle(c, s + line, ink)
			ci.draw_circle(c, s, Color(PAPER, 0.35 * a))
			var knob := c + Vector2(s * 0.35, -s * 0.3)
			ci.draw_circle(knob, s * 0.5 + line, ink)
			ci.draw_circle(knob, s * 0.5, white)
		Protocol.LAYOUT_SLIDER_H:
			var bar := Rect2(c.x - s * 1.5, c.y - s * 0.2, s * 3.0, s * 0.4)
			draw_round_rect(ci, bar.grow(line), ink, s * 0.24)
			draw_round_rect(ci, bar, Color(PAPER, 0.45 * a), s * 0.2)
			var knob := Vector2(c.x + s * 0.5, c.y)
			ci.draw_circle(knob, s * 0.5 + line, ink)
			ci.draw_circle(knob, s * 0.5, white)
		Protocol.LAYOUT_ONE_BUTTON:
			var depth := maxf(6.0, s * 0.1)
			ci.draw_circle(c + Vector2(0, depth), s + line, ink)
			ci.draw_circle(c + Vector2(0, depth), s, white.darkened(0.2))
			ci.draw_circle(c, s + line, ink)
			ci.draw_circle(c, s, white)
			draw_text(ci, "A", c, int(s), ink)
		_:
			draw_star(ci, c, s, white)


static func hex_points(r: Rect2) -> PackedVector2Array:
	var k := r.size.y * 0.42
	var m := r.position.y + r.size.y / 2.0
	return PackedVector2Array([
		Vector2(r.position.x + k, r.position.y), Vector2(r.end.x - k, r.position.y), Vector2(r.end.x, m),
		Vector2(r.end.x - k, r.end.y), Vector2(r.position.x + k, r.end.y), Vector2(r.position.x, m),
	])


## Chip hexagonal de marcador: [ 1P | 345 ]. Con `tag` vacío es un chip
## informativo (ej. "Ronda 2/3"); `rainbow` le pone borde arcoíris.
static func draw_hex_chip(ci: CanvasItem, rect: Rect2, tag: String, tag_color: Color, text: String,
		rainbow_border: bool = false, alpha: float = 1.0) -> void:
	var outer := hex_points(rect.grow(4.0))
	ci.draw_colored_polygon(outer, Color(INK, alpha))
	ci.draw_colored_polygon(hex_points(rect), Color(PAPER, alpha))
	var inner := rect.grow(-5.0)
	var h := inner.size.y
	var k := h * 0.42
	var ym := inner.position.y + h / 2.0
	var x0 := inner.position.x
	var x1 := inner.end.x
	var y0 := inner.position.y
	var y1 := inner.end.y
	if tag.is_empty():
		ci.draw_colored_polygon(hex_points(inner), Color(CHIP_DARK, alpha))
		draw_text(ci, text, inner.get_center(), int(h * 0.62), Color(PAPER, alpha))
	else:
		var slant := h * 0.16
		var xt := x0 + k + h * 1.05
		ci.draw_colored_polygon(PackedVector2Array([
			Vector2(x0 + k, y0), Vector2(xt + slant, y0), Vector2(xt - slant, y1), Vector2(x0 + k, y1), Vector2(x0, ym),
		]), Color(tag_color, alpha))
		ci.draw_colored_polygon(PackedVector2Array([
			Vector2(xt + slant, y0), Vector2(x1 - k, y0), Vector2(x1, ym), Vector2(x1 - k, y1), Vector2(xt - slant, y1),
		]), Color(CHIP_DARK, alpha))
		var fs := int(h * 0.6)
		draw_text(ci, tag, Vector2((x0 + k * 0.6 + xt) / 2.0, ym), fs, Color(PAPER, alpha), maxi(4, fs / 6), Color(INK, alpha))
		var font := FONT_BOLD
		var tw := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var right := x1 - k * 0.9
		draw_text(ci, text, Vector2(maxf(right - tw / 2.0, xt + slant + tw / 2.0 + 8.0), ym), fs, Color(PAPER, alpha))
	if rainbow_border:
		var pts := hex_points(rect.grow(2.0))
		pts.append(pts[0])
		var colors := PackedColorArray()
		for i in pts.size():
			colors.append(Color(rainbow(float(i) / 6.0), alpha))
		ci.draw_polyline_colors(pts, colors, 6.0, true)
