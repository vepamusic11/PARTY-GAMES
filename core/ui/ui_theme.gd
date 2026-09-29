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
const SKY_TOP := Color("#2B9CF5")
const SKY_BOTTOM := Color("#BFE4FF")
const STUDIO_BG := Color("#000D22")     ## Fondo de la presentación IO-GAMES (el de su logo).
const INK := Color("#1D2140")          ## Texto principal y contornos.
const INK_SOFT := Color("#565C85")     ## Texto secundario.
const MUTED := Color("#9AA0BE")        ## Deshabilitado / pistas.
const PAPER := Color("#FFFFFF")        ## Tarjetas y paneles.
const PAPER_DIM := Color("#EAEEFB")
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
## Piso a cuadros: fondo claro y baldosas del fondo de fiesta y del campo de juego.
const FLOOR := Color("#F4F6FB")
const FLOOR_TILE := Color("#E1E6F1")
const FIELD_TILE := Color("#E3E8F2")
const LEAF := Color("#8BE36B")          ## Hojitas del brote de la mascota 4P.
## Umbral de "color muy claro" y cuánto oscurecerlo (ver on_light).
const LIGHT_COLOR_LUMINANCE := 0.8
const LIGHT_COLOR_DARKEN := 0.4
## Desde qué luminancia un fondo es "claro" y lleva texto en tinta (text_on).
const TEXT_ON_LIGHT_LUMINANCE := 0.55

# --- Medidas ------------------------------------------------------------------
const SAFE_MARGIN := 64      ## Margen contra el *overscan* (TVs que recortan bordes).
const RADIUS := 28
const FOCUS_WIDTH := 8.0
## Botones táctiles del celular: más grandes que el mínimo cómodo (88 px),
## porque se tocan mirando la TV.
const TOUCH_TARGET := 128.0

# Estilo reutilizado para dibujar rectángulos redondeados sin crear
# objetos en cada frame (los minijuegos dibujan 60 veces por segundo).
static var _box: StyleBoxFlat
# Senos y cosenos precalculados de ellipse_points (sin trigonometría por frame).
static var _unit_circles: Dictionary = {}  # steps -> [PackedFloat64Array cos, PackedFloat64Array sin]


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


## Color de jugador visible sobre superficies claras (pisos, papel). Los
## muy claros (el blanco de la paleta) se oscurecen; el resto queda igual.
## Ejemplo: en Pintar, una baldosa "blanca" sobre el piso claro no se vería.
## Color de texto legible sobre un fondo cualquiera: tinta sobre fondos
## claros y blanco sobre oscuros. Ejemplo: el nombre de un jugador que eligió
## blanco va en tinta; el de uno que eligió negro, en blanco.
static func text_on(bg: Color) -> Color:
	return INK if bg.get_luminance() > TEXT_ON_LIGHT_LUMINANCE else PAPER


static func on_light(col: Color) -> Color:
	return col.darkened(LIGHT_COLOR_DARKEN) if col.get_luminance() > LIGHT_COLOR_LUMINANCE else col


static func rainbow(t: float) -> Color:
	return Color.from_hsv(fposmod(t, 1.0), 0.75, 1.0)


# --- Dibujo (sirve para Control y para Node2D) -----------------------------------

static func draw_round_rect(ci: CanvasItem, rect: Rect2, color: Color, radius: float = RADIUS,
		border: float = 0.0, border_color: Color = INK, shadow: bool = false) -> void:
	if _box == null:
		_box = StyleBoxFlat.new()
		_box.shadow_offset = Vector2(0, 8)
		_box.corner_detail = 8
	_box.bg_color = color
	_box.set_corner_radius_all(int(radius))
	_box.set_border_width_all(int(border))
	_box.border_color = border_color
	_box.shadow_color = SHADOW if shadow else Color.TRANSPARENT
	_box.shadow_size = 12 if shadow else 0
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
	if steps <= 0:
		return pts
	var unit: Array = _unit_circles.get(steps, [])
	if unit.is_empty():
		var cosines := PackedFloat64Array()
		var sines := PackedFloat64Array()
		for i in steps:
			var a := TAU * i / steps
			cosines.append(cos(a))
			sines.append(sin(a))
		unit = [cosines, sines]
		_unit_circles[steps] = unit
	var cosines: PackedFloat64Array = unit[0]
	var sines: PackedFloat64Array = unit[1]
	pts.resize(steps)  # Una sola reserva en vez de crecer punto a punto.
	# Mismas operaciones que calculando el seno y coseno en cada llamada:
	# los puntos salen idénticos (bit a bit) y se ven igual.
	for i in steps:
		pts[i] = center + Vector2(cosines[i] * rx, sines[i] * ry).rotated(rotation)
	return pts


static func draw_ellipse(ci: CanvasItem, center: Vector2, rx: float, ry: float, color: Color, rotation: float = 0.0) -> void:
	ci.draw_colored_polygon(ellipse_points(center, rx, ry, rotation), color)


static func star_points(center: Vector2, r: float, inner: float = 0.48, rotation: float = 0.0) -> PackedVector2Array:
	var pts := PackedVector2Array()
	pts.resize(10)  # Una sola reserva en vez de crecer punto a punto.
	for i in 10:
		var a := -PI / 2.0 + rotation + PI * i / 5.0
		var rr := r if i % 2 == 0 else r * inner
		pts[i] = center + Vector2(cos(a), sin(a)) * rr
	return pts


## Estrella dorada (o blanca) de juguete 3D horneada (Props3D, ADR 0016); si
## no hay atlas (tests, sin render) u otro color, la 2D de siempre. Con
## `rotation` la 3D usa draw_set_transform y después lo deja en identidad.
static func draw_star(ci: CanvasItem, center: Vector2, r: float, color: Color = GOLD, rotation: float = 0.0) -> void:
	var piece := "star" if color == GOLD else ("star_white" if color == PAPER else "")
	if piece != "" and Props3D.is_ready():
		var body := Rect2(Vector2(-r, -r), Vector2(r, r) * 2.0)
		if is_zero_approx(rotation):
			Props3D.draw(ci, piece, Rect2(center + body.position, body.size))
		else:
			ci.draw_set_transform(center, rotation)
			Props3D.draw(ci, piece, body)
			ci.draw_set_transform(Vector2.ZERO)
		return
	draw_star_2d(ci, center, r, color, rotation)


## Estrella 2D: las tres capas van en un solo lote (ShapeBatch): un draw call, no tres.
static func draw_star_2d(ci: CanvasItem, center: Vector2, r: float, color: Color = GOLD, rotation: float = 0.0) -> void:
	var batch := ShapeBatch.new()
	batch.star(star_points(center, r + 5.0, 0.5, rotation), center, INK)
	batch.star(star_points(center, r, 0.48, rotation), center, color)
	var shine := center + Vector2(-r * 0.12, -r * 0.12)
	batch.star(star_points(shine, r * 0.35, 0.5, rotation), shine, Color(1, 1, 1, 0.55))
	batch.flush(ci)


## Medalla redonda con el puesto ("1°" en oro, "2°" plata, "3°" bronce): de
## metal 3D horneada (Props3D) con el número encima, o la 2D si no hay atlas.
static func draw_medal(ci: CanvasItem, center: Vector2, r: float, place: int) -> void:
	var body := r + maxf(3.0, r * 0.08)  # El disco 3D incluye el aro: un poco más grande que la cara 2D.
	if place >= 1 and place <= 3 and Props3D.draw(ci, "medal_%d" % place, Rect2(center - Vector2(body, body), Vector2(body, body) * 2.0)):
		draw_text(ci, place_text(place), center + Vector2(2, 1) * (r / 30.0), int(r), INK)
		return
	draw_medal_2d(ci, center, r, place)


static func draw_medal_2d(ci: CanvasItem, center: Vector2, r: float, place: int) -> void:
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
		Protocol.LAYOUT_JOYSTICK_AB:
			# Joystick a la izquierda; A (blanco, grande) y B (neutro) a la derecha.
			var base := c + Vector2(-s * 0.8, s * 0.05)
			ci.draw_circle(base, s * 0.62 + line, ink)
			ci.draw_circle(base, s * 0.62, Color(PAPER, 0.35 * a))
			var knob := base + Vector2(s * 0.2, -s * 0.18)
			ci.draw_circle(knob, s * 0.32 + line, ink)
			ci.draw_circle(knob, s * 0.32, white)
			for key: Array in [["B", Vector2(s * 0.28, -s * 0.36), s * 0.3, Color(PHONE_KEY_NEUTRAL, a)],
					["A", Vector2(s * 0.9, s * 0.26), s * 0.38, white]]:
				var kc: Vector2 = c + key[1]
				ci.draw_circle(kc, key[2] + line, ink)
				ci.draw_circle(kc, key[2], key[3])
				draw_text(ci, key[0], kc, int(key[2] * 1.1), ink)
		_:
			draw_star_2d(ci, c, s, white)  # Ícono plano: sin 3D.


## Íconos simples de interfaz, dibujados (la tipografía no los trae).
## `s` es el tamaño aproximado del ícono (alto). Ejemplo: el lobby usa
## "phone" junto a "¡Sumate desde tu celular!" y "lock" en los juegos que no
## se pueden jugar con la cantidad elegida.
##   phone · wifi · gamepad · lock · play · plus · people · order
static func draw_glyph(ci: CanvasItem, glyph: String, c: Vector2, s: float, color: Color = INK) -> void:
	var w := maxf(3.0, s * 0.12)
	match glyph:
		"phone":
			var body := Rect2(c - Vector2(s * 0.3, s * 0.5), Vector2(s * 0.6, s))
			draw_round_rect(ci, body, color, s * 0.12)
			var detail := color.lerp(INK, 0.7)
			draw_round_rect(ci, Rect2(body.position + Vector2(s * 0.08, s * 0.1), body.size - Vector2(s * 0.16, s * 0.3)), detail, s * 0.05)
			ci.draw_circle(Vector2(c.x, body.end.y - s * 0.1), s * 0.05, detail)
		"wifi":
			var base := c + Vector2(0, s * 0.38)
			ci.draw_circle(base, s * 0.1, color)
			for i in 3:
				var r := s * (0.3 + 0.24 * i)
				ci.draw_arc(base, r, -PI * 0.78, -PI * 0.22, 16, color, w, true)
		"gamepad":
			var pad := Rect2(c - Vector2(s * 0.62, s * 0.3), Vector2(s * 1.24, s * 0.62))
			draw_round_rect(ci, pad, color, s * 0.3)
			var detail := color.lerp(INK, 0.7)
			var cross := c + Vector2(-s * 0.3, 0)
			ci.draw_rect(Rect2(cross - Vector2(s * 0.14, s * 0.04), Vector2(s * 0.28, s * 0.08)), detail)
			ci.draw_rect(Rect2(cross - Vector2(s * 0.04, s * 0.14), Vector2(s * 0.08, s * 0.28)), detail)
			ci.draw_circle(c + Vector2(s * 0.26, -s * 0.06), s * 0.07, detail)
			ci.draw_circle(c + Vector2(s * 0.38, s * 0.08), s * 0.07, detail)
		"lock":
			ci.draw_arc(c - Vector2(0, s * 0.08), s * 0.24, PI, TAU, 16, color, w * 1.2, true)
			ci.draw_line(c + Vector2(-s * 0.24, -s * 0.08), c + Vector2(-s * 0.24, s * 0.05), color, w * 1.2)
			ci.draw_line(c + Vector2(s * 0.24, -s * 0.08), c + Vector2(s * 0.24, s * 0.05), color, w * 1.2)
			draw_round_rect(ci, Rect2(c + Vector2(-s * 0.36, 0), Vector2(s * 0.72, s * 0.5)), color, s * 0.1)
		"play":
			draw_arrow(ci, c + Vector2(s * 0.1, 0), s, Vector2.RIGHT, color)
		"plus":
			ci.draw_rect(Rect2(c - Vector2(s * 0.4, s * 0.09), Vector2(s * 0.8, s * 0.18)), color)
			ci.draw_rect(Rect2(c - Vector2(s * 0.09, s * 0.4), Vector2(s * 0.18, s * 0.8)), color)
		"people":
			for k in [-1, 1]:
				var hc := c + Vector2(k * s * 0.22, -s * 0.18)
				ci.draw_circle(hc, s * 0.17, color)
				draw_round_rect(ci, Rect2(hc + Vector2(-s * 0.26, s * 0.22), Vector2(s * 0.52, s * 0.34)), color, s * 0.16)
		"order":
			draw_arrow(ci, c - Vector2(s * 0.18, s * 0.22), s * 0.5, Vector2.UP, color)
			ci.draw_line(c + Vector2(-s * 0.18, -s * 0.2), c + Vector2(-s * 0.18, s * 0.4), color, w)
			draw_arrow(ci, c + Vector2(s * 0.18, s * 0.22), s * 0.5, Vector2.DOWN, color)
			ci.draw_line(c + Vector2(s * 0.18, -s * 0.4), c + Vector2(s * 0.18, s * 0.2), color, w)


## Logo de la marca (PARTY-GAME). Se carga recién cuando se usa: los juegos
## no pagan la memoria de la imagen si no lo muestran.
const LOGO_PATH := "res://assets/brand/party_game_logo.png"
const STUDIO_LOGO_PATH := "res://assets/brand/io_games_logo.png"


static func logo_rect(texture_path: String = LOGO_PATH) -> TextureRect:
	var t := TextureRect.new()
	t.texture = load(texture_path)
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	t.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return t


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
	# Los fondos van en un lote (un draw call); los textos, después.
	var batch := ShapeBatch.new()
	batch.polygon(hex_points(rect.grow(4.0)), Color(INK, alpha))
	batch.polygon(hex_points(rect), Color(PAPER, alpha))
	var inner := rect.grow(-5.0)
	var h := inner.size.y
	var k := h * 0.42
	var ym := inner.position.y + h / 2.0
	var x0 := inner.position.x
	var x1 := inner.end.x
	var y0 := inner.position.y
	var y1 := inner.end.y
	if tag.is_empty():
		batch.polygon(hex_points(inner), Color(CHIP_DARK, alpha))
		batch.flush(ci)
		draw_text(ci, text, inner.get_center(), int(h * 0.62), Color(PAPER, alpha))
	else:
		var slant := h * 0.16
		var xt := x0 + k + h * 1.05
		batch.polygon(PackedVector2Array([
			Vector2(x0 + k, y0), Vector2(xt + slant, y0), Vector2(xt - slant, y1), Vector2(x0 + k, y1), Vector2(x0, ym),
		]), Color(tag_color, alpha))
		batch.polygon(PackedVector2Array([
			Vector2(xt + slant, y0), Vector2(x1 - k, y0), Vector2(x1, ym), Vector2(x1 - k, y1), Vector2(xt - slant, y1),
		]), Color(CHIP_DARK, alpha))
		batch.flush(ci)
		var fs := int(h * 0.6)
		var tag_text := text_on(tag_color)
		var tag_outline := INK if tag_text == PAPER else PAPER
		draw_text(ci, tag, Vector2((x0 + k * 0.6 + xt) / 2.0, ym), fs, Color(tag_text, alpha), maxi(4, fs / 6), Color(tag_outline, alpha))
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


# --- Figuras en lote ------------------------------------------------------------

## Junta varias figuras rellenas (círculos, elipses, polígonos) en UN solo
## triangle array. Cada draw_circle / draw_colored_polygon de Godot es un
## comando aparte: arma su propio buffer de vértices y cuesta un draw call.
## Una mascota tiene ~30 figuras; en lote son unos pocos tramos. Se respeta el orden: lo que se
## agrega después queda encima, igual que dibujando una por una.
##
##   var batch := UiTheme.ShapeBatch.new()
##   batch.circle(p, 10.0, UiTheme.INK)
##   batch.circle(p, 8.0, color)
##   batch.flush(self)   # antes de dibujar cualquier otra cosa (texto, líneas…)
##
## Los círculos usan la misma geometría que CanvasItem.draw_circle (64
## segmentos desde el centro) y los polígonos convexos cubren los mismos
## píxeles: el resultado se ve igual.
class ShapeBatch:
	extends RefCounted

	const CIRCLE_SEGMENTS := 64
	const FEATHER_SIZE := 1.25  ## Borde suavizado de las líneas (igual que el motor).

	# Plantillas de índices por forma y su versión corrida a cada posición
	# del lote (se reusan entre frames: el mismo dibujo arma el mismo lote).
	static var _circle_unit := PackedVector2Array()   # 65 puntos del borde + centro
	static var _templates: Dictionary = {}             # id -> PackedInt32Array
	static var _shifted: Dictionary = {}               # id * 1e6 + base -> PackedInt32Array

	var points := PackedVector2Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()

	## Círculo relleno, como CanvasItem.draw_circle (sin antialiasing).
	## `offset`: como si antes se hubiera hecho draw_set_transform(offset)
	## (se suma después, igual que lo haría ese transform).
	func circle(center: Vector2, radius: float, color: Color, offset := Vector2.ZERO) -> void:
		if _circle_unit.is_empty():
			# Igual que RenderingServer.canvas_item_add_circle, que calcula en
			# float de 32 bits: se redondea igual para obtener los mismos vértices.
			var step := _f32(TAU / CIRCLE_SEGMENTS)
			for i in CIRCLE_SEGMENTS + 1:
				var a := _f32(i * step)
				_circle_unit.append(Vector2(cos(a), sin(a)))
			_circle_unit.append(Vector2.ZERO)
		# Transform2D * arreglo = radio * punto + centro para todos los puntos
		# de una vez (en C++), con las mismas operaciones que draw_circle.
		var pts := Transform2D(0.0, Vector2(radius, radius), 0.0, center) * _circle_unit
		if offset != Vector2.ZERO:
			pts = Transform2D(0.0, offset) * pts
		_add(pts, color, -1)

	static func _f32(x: float) -> float:
		return Vector2(x, 0.0).x  # Vector2 guarda float de 32 bits.

	## Elipse rellena, como UiTheme.draw_ellipse.
	func ellipse(center: Vector2, rx: float, ry: float, color: Color, rotation: float = 0.0) -> void:
		polygon(UiTheme.ellipse_points(center, rx, ry, rotation), color)

	## Polígono convexo (o con forma de estrella respecto de su primer punto).
	func polygon(pts: PackedVector2Array, color: Color) -> void:
		if pts.size() >= 3:
			_add(pts, color, pts.size())

	## Estrella (u otro polígono "estrellado" respecto de `center`): abanico
	## desde el centro, cubre lo mismo que draw_colored_polygon.
	func star(pts: PackedVector2Array, center: Vector2, color: Color) -> void:
		if pts.size() < 3:
			return
		var with_center := pts.duplicate()
		with_center.append(center)
		_add(with_center, color, -pts.size())

	## Línea gruesa con antialiasing, como CanvasItem.draw_polyline(..., true):
	## mismo algoritmo que el motor (tira central + dos bordes que se
	## desvanecen), pero dentro del lote. Una draw_polyline con antialiasing
	## son TRES comandos (y tres draw calls); acá no suma ninguno.
	## Las cuentas de vectores ya son en float de 32 bits (como el motor) y las
	## demás se redondean igual; solo seno, coseno y atan2 pueden diferir en
	## el último bit: a lo sumo 1/255 en algún píxel del borde suavizado.
	func polyline(pts: PackedVector2Array, color: Color, width: float) -> void:
		var n := pts.size()
		if n < 2:
			return
		var loop := pts[0].is_equal_approx(pts[n - 1])
		var first_dir := Vector2.ZERO
		for i in range(1, n):
			first_dir = (pts[i] - pts[i - 1]).normalized()
			if not first_dir.is_zero_approx():
				break
		var last_dir := Vector2.ZERO
		for i in range(n - 1, 0, -1):
			last_dir = (pts[i] - pts[i - 1]).normalized()
			if not last_dir.is_zero_approx():
				break
		var border_size := FEATHER_SIZE * (width if width < 1.0 else 1.0)
		var clear := Color(color, 0.0)
		var count := n * 2
		var main := PackedVector2Array()
		var left := PackedVector2Array()
		var right := PackedVector2Array()
		main.resize(count + (0 if loop else 4))
		left.resize(count + (0 if loop else 5))
		right.resize(count + (0 if loop else 5))
		var main_c := PackedColorArray()
		var left_c := PackedColorArray()
		var right_c := PackedColorArray()
		main_c.resize(main.size())
		left_c.resize(left.size())
		right_c.resize(right.size())
		var prev_dir := Vector2.ZERO
		for i in n:
			var is_first := i == 0
			var is_last := i == n - 1
			var seg_dir := prev_dir
			if not is_last:
				seg_dir = (pts[i + 1] - pts[i]).normalized()
				if seg_dir.is_zero_approx():
					seg_dir = prev_dir
			if is_first and loop:
				prev_dir = last_dir
			elif is_last and loop:
				prev_dir = first_dir
			var base_off: Vector2
			if is_first and not loop:
				base_off = first_dir.orthogonal()
			elif is_last and not loop:
				base_off = last_dir.orthogonal()
			else:
				base_off = ShapeBatch._edge_offset(seg_dir, prev_dir)
			var edge := base_off * (width * 0.5)
			var border := base_off * border_size
			var pos := pts[i]
			var j := i * 2 + (0 if loop else 2)
			main[j] = pos + edge
			main[j + 1] = pos - edge
			left[j] = pos + edge
			left[j + 1] = pos + edge + border
			right[j] = pos - edge
			right[j + 1] = pos - edge - border
			main_c[j] = color
			main_c[j + 1] = color
			left_c[j] = color
			left_c[j + 1] = clear
			right_c[j] = color
			right_c[j + 1] = clear
			if is_first and not loop:
				var begin := -seg_dir * border_size
				main[0] = pos + edge + begin
				main[1] = pos - edge + begin
				left[0] = pos + edge + begin
				left[1] = pos + edge + begin + border
				right[0] = pos - edge + begin
				right[1] = pos - edge + begin - border
				for k in 2:
					main_c[k] = clear
					left_c[k] = clear
					right_c[k] = clear
			if is_last and not loop:
				var end := prev_dir * border_size
				var e := count + 2
				main[e] = pos + edge + end
				main[e + 1] = pos - edge + end
				main_c[e] = clear
				main_c[e + 1] = clear
				left[e] = pos + edge
				left[e + 1] = pos + edge + end + border
				left[e + 2] = pos + edge + end
				right[e] = pos - edge
				right[e + 1] = pos - edge + end - border
				right[e + 2] = pos - edge + end
				left_c[e] = color
				left_c[e + 1] = clear
				left_c[e + 2] = clear
				right_c[e] = color
				right_c[e + 1] = clear
				right_c[e + 2] = clear
			prev_dir = seg_dir
		strip(main, main_c)
		strip(left, left_c)
		strip(right, right_c)

	## Tira de triángulos (como PRIMITIVE_TRIANGLE_STRIP) con color por vértice.
	func strip(pts: PackedVector2Array, cols: PackedColorArray) -> void:
		var base := points.size()
		points.append_array(pts)
		colors.append_array(cols)
		for i in pts.size() - 2:
			indices.append_array([base + i, base + i + 1, base + i + 2])

	## Igual que compute_polyline_edge_offset_clamped del motor: dirección del
	## borde en la unión de dos segmentos (con un tope en las puntas agudas).
	static func _edge_offset(seg_dir: Vector2, prev_dir: Vector2) -> Vector2:
		var length := 1.0
		var bisector := (prev_dir * seg_dir.length() - seg_dir * prev_dir.length()).normalized()
		# atan2f/sinf del motor: se redondea a float de 32 bits igual que él.
		var sin_angle := _f32(sin(_f32(atan2(bisector.cross(prev_dir), bisector.dot(prev_dir)))))
		if not is_zero_approx(sin_angle) and not seg_dir.is_equal_approx(prev_dir):
			length = clampf(_f32(1.0 / sin_angle), -3.0, 3.0)
		else:
			bisector = seg_dir.orthogonal()
		if bisector.is_zero_approx():
			bisector = seg_dir.orthogonal()
		return bisector * length

	## Arco como CanvasItem.draw_arc(..., true): mismos puntos y polyline().
	func arc(center: Vector2, radius: float, start: float, end: float, point_count: int, color: Color, width: float) -> void:
		var pts := PackedVector2Array()
		pts.resize(point_count)
		# Mismas cuentas que el motor, en float de 32 bits (_f32 en cada paso).
		start = _f32(start)
		var delta := _f32(clampf(_f32(_f32(end) - start), -TAU, TAU))
		var last := _f32(point_count - 1.0)
		for i in point_count:
			var theta := _f32(_f32(_f32(i / last) * delta) + start)
			pts[i] = center + Vector2(cos(theta), sin(theta)) * radius
		polyline(pts, color, width)

	## Dibuja lo acumulado en `ci` (un solo comando) y vacía el lote.
	func flush(ci: CanvasItem) -> void:
		if points.is_empty():
			return
		RenderingServer.canvas_item_add_triangle_array(ci.get_canvas_item(), indices, points, colors)
		points.clear()
		colors.clear()
		indices.clear()

	## kind: -1 círculo de 64; n > 0 abanico convexo de n puntos; n < 0
	## abanico desde el centro (último punto) de |n| puntos en el borde.
	func _add(pts: PackedVector2Array, color: Color, kind: int) -> void:
		var base := points.size()
		points.append_array(pts)
		var fill := PackedColorArray()
		fill.resize(pts.size())
		fill.fill(color)
		colors.append_array(fill)
		indices.append_array(ShapeBatch._indices(kind, base))

	static func _indices(kind: int, base: int) -> PackedInt32Array:
		var key := (kind + 1000) * 1000000 + base
		var shifted: PackedInt32Array = _shifted.get(key, PackedInt32Array())
		if not shifted.is_empty():
			return shifted
		var template: PackedInt32Array = _templates.get(kind, PackedInt32Array())
		if template.is_empty():
			if kind == -1:  # Igual que RenderingServer.canvas_item_add_circle.
				for i in CIRCLE_SEGMENTS:
					template.append_array([CIRCLE_SEGMENTS + 1, i, i + 1])
			elif kind > 0:
				for i in range(1, kind - 1):
					template.append_array([0, i, i + 1])
			else:
				var n := -kind
				for i in n:
					template.append_array([n, i, (i + 1) % n])
			_templates[kind] = template
		shifted = template.duplicate()
		for i in shifted.size():
			shifted[i] += base
		if _shifted.size() > 4096:  # Tope de memoria: se vuelve a llenar solo.
			_shifted.clear()
		_shifted[key] = shifted
		return shifted


# --- Fondo (agente) -------------------------------------------------------------
## Escenario de fiesta detrás de la UI (PartyBackground), barrido entre
## pantallas (Transition) y confeti del podio (Confetti). El fondo va más
## suave y desenfocado que la UI: tarjetas y textos tienen que seguir
## destacando.
const BG_SKY_TOP := Color("#1F8BEF")
const BG_SKY_MID := Color("#43ADF8")
const BG_HAZE := Color("#B2DBFF")        ## Bruma del horizonte: lo lejano se mezcla con este color (celeste, no blanco: la maqueta no lava el fondo).
const BG_GLOW := Color(1.0, 0.98, 0.9, 0.26)   ## Luz ambiente arriba al centro.
const BG_BEAM := Color(1.0, 1.0, 1.0, 0.12)    ## Haces de luz del escenario.
const BG_CLOUD_SHADE := Color("#C9DDF6")  ## Panza de las nubes.
const BG_FLOOR_A := Color("#F5F7FF")
const BG_FLOOR_B := Color("#D4DCF9")
const BG_VIGNETTE := Color(0.06, 0.12, 0.38, 0.20)  ## Bordes más oscuros: la UI del centro resalta.
const BG_SPARKLE := Color("#FFF4C2")      ## Brillos que titilan.
const BG_HAZE_FAR := 0.3   ## Cuánto se mezclan con la bruma las torres de atrás.
const BG_HAZE_NEAR := 0.1  ## …y las de adelante.
const BG_BLUR_STEP := 1.1   ## Separación entre muestras del desenfoque (px de la textura a media resolución).


## Puntos de un rectángulo redondeado (convexo: sirve para ShapeBatch.polygon).
## `steps`: segmentos por esquina.
static func round_rect_points(rect: Rect2, radius: float, steps: int = 4) -> PackedVector2Array:
	var r := minf(radius, minf(rect.size.x, rect.size.y) / 2.0)
	var pts := PackedVector2Array()
	pts.resize((steps + 1) * 4)
	var centers := [rect.end - Vector2(r, r), Vector2(rect.position.x + r, rect.end.y - r),
		rect.position + Vector2(r, r), Vector2(rect.end.x - r, rect.position.y + r)]
	var k := 0
	for corner in 4:
		var c: Vector2 = centers[corner]
		for i in steps + 1:
			var a := PI / 2.0 * corner + PI / 2.0 * i / steps
			pts[k] = c + Vector2(cos(a), sin(a)) * r
			k += 1
	return pts


## Degradé radial (centro `inner` → borde `outer`) en un solo triangle array.
## `ry` <= 0: círculo.
static func draw_radial(ci: CanvasItem, center: Vector2, rx: float, inner: Color, outer: Color,
		ry: float = -1.0, steps: int = 40) -> void:
	var ring := ellipse_points(center, rx, ry if ry > 0.0 else rx, 0.0, steps)
	var pts := PackedVector2Array([center])
	pts.append_array(ring)
	var cols := PackedColorArray()
	cols.resize(steps + 1)
	cols.fill(outer)
	cols[0] = inner
	var idx := PackedInt32Array()
	for i in steps:
		idx.append_array([0, 1 + i, 1 + (i + 1) % steps])
	RenderingServer.canvas_item_add_triangle_array(ci.get_canvas_item(), idx, pts, cols)


# --- Celular (agente) -----------------------------------------------------------
## Tokens y dibujos de la app del celular: controles "de consola" (bisel,
## brillo y sombra), fichas del código de sala y los íconos que usa.
## Medidas pensadas para un celular apaisado de 1080 px de alto.
##
## Concepto: *bisel*. Una tecla de juguete tiene una cara de color y un
## canto más oscuro debajo; al apretarla, la cara baja sobre el canto
## (squash). Así se "siente" el toque aunque la pantalla sea plana.

const PHONE_MARGIN := 28                     ## Margen de las pantallas del celular.
const PHONE_BAR_HEIGHT := 112.0              ## Barra superior (Salir, 4P, sonido…).
const PHONE_FIELD_HEIGHT := 104.0            ## Campos de texto (apodo, IP).
const PHONE_HOST_CARD_HEIGHT := 128.0        ## Tarjeta de cada TV encontrada.
const PHONE_TILE_SIZE := Vector2(150, 172)   ## Fichas del código de sala.
const PHONE_KEY_DEPTH := 14.0                ## Alto del canto de los botones grandes.
const PHONE_BEVEL_DARKEN := 0.3              ## Canto respecto de la cara.
const PHONE_SHINE := Color(1, 1, 1, 0.5)     ## Reflejo chico "de plástico".
const PHONE_SHINE_SOFT := Color(1, 1, 1, 0.22)  ## Brillo ancho de la mitad de arriba.
const PHONE_DISH := Color("#2A3163")         ## Hueco del joystick y canal del slider.
const PHONE_DISH_RIM := Color("#454E8C")     ## Aro interno del hueco.
const PHONE_TINT := 0.82                     ## Mezcla color del jugador → papel en tarjetas.
const PHONE_ERROR_BG := Color("#FFE9E6")     ## Fondo de los avisos de error (amables, no rojos).
const PHONE_INFO_BG := Color("#E4F2FF")      ## Fondo de "Conectando…" y ayudas.
const PHONE_GLASS := Color(1, 1, 1, 0.55)    ## Paneles translúcidos sobre el cielo.
const PHONE_PRESS_SQUASH := 0.08             ## Cuánto se ensancha la perilla al tocarla.
const PHONE_KEY_NEUTRAL := Color("#D5DBEA")  ## Botón B de joystick_ab: neutro (A lleva el color del jugador).


## Tecla de juguete dentro de `rect` (incluye el canto): sombra, canto
## oscuro, cara de color con contorno de tinta y brillo arriba.
## `press` 0..1 baja la cara. Devuelve el rectángulo de la cara, para
## dibujar encima el texto o el ícono.
static func draw_toy_key(ci: CanvasItem, rect: Rect2, color: Color, press: float = 0.0,
		radius: float = RADIUS, depth: float = PHONE_KEY_DEPTH, outline: float = 4.0) -> Rect2:
	var lift := depth * (1.0 - 0.8 * clampf(press, 0.0, 1.0))
	var body := Rect2(rect.position + Vector2(0, depth), rect.size - Vector2(0, depth))
	var face := Rect2(body.position - Vector2(0, lift), body.size)
	# Contorno como borde del mismo StyleBox: canto y cara son un comando cada uno.
	draw_round_rect(ci, body.grow(outline), color.darkened(PHONE_BEVEL_DARKEN), radius + outline, outline, INK, true)
	draw_round_rect(ci, face.grow(outline), color, radius + outline, outline, INK)
	# Brillo: franja clara arriba y un reflejo chico a la izquierda.
	var band := Rect2(face.position + Vector2(outline + 4.0, outline + 2.0),
		Vector2(face.size.x - (outline + 4.0) * 2.0, face.size.y * 0.42))
	draw_round_rect(ci, band, PHONE_SHINE_SOFT, minf(radius, band.size.y / 2.0))
	var gloss_h := clampf(face.size.y * 0.12, 6.0, 18.0)
	draw_round_rect(ci, Rect2(face.position + Vector2(radius * 0.7, face.size.y * 0.1), Vector2(minf(face.size.x * 0.22, 90.0), gloss_h)),
		PHONE_SHINE, gloss_h / 2.0)
	return face


## Disco de juguete (botón de arcade, perilla del joystick): sombra, canto,
## cara con contorno y brillo. `press` 0..1 lo baja y lo aplasta un poco
## (squash: más ancho y más bajo). Devuelve el centro de la cara.
static func draw_toy_disc(ci: CanvasItem, c: Vector2, r: float, color: Color, press: float = 0.0,
		depth: float = -1.0) -> Vector2:
	if depth < 0.0:
		depth = r * 0.16
	press = clampf(press, 0.0, 1.0)
	var outline := maxf(4.0, r * 0.05)
	var lift := depth * (1.0 - 0.8 * press)
	var sx := r * (1.0 + PHONE_PRESS_SQUASH * press)
	var sy := r * (1.0 - PHONE_PRESS_SQUASH * press)
	var steps := 64
	var base := c + Vector2(0, depth)
	var face := base - Vector2(0, lift)
	var batch := ShapeBatch.new()
	batch.polygon(ellipse_points(base + Vector2(0, r * 0.1), sx + outline * 2.0, sy * 0.9 + outline, 0.0, steps), SHADOW)
	batch.polygon(ellipse_points(base, sx + outline, sy + outline, 0.0, steps), INK)
	batch.polygon(ellipse_points(base, sx, sy, 0.0, steps), color.darkened(PHONE_BEVEL_DARKEN))
	batch.polygon(ellipse_points(face, sx + outline, sy + outline, 0.0, steps), INK)
	batch.polygon(ellipse_points(face, sx, sy, 0.0, steps), color)
	# Mitad de abajo un poco más oscura: da volumen (se ve "abombado").
	batch.polygon(ellipse_points(face + Vector2(0, sy * 0.18), sx * 0.86, sy * 0.78, 0.0, steps), color.darkened(0.06))
	batch.polygon(ellipse_points(face - Vector2(0, sy * 0.06), sx * 0.8, sy * 0.72, 0.0, steps), color)
	batch.polygon(ellipse_points(face - Vector2(0, sy * 0.4), sx * 0.6, sy * 0.3, 0.0, steps), PHONE_SHINE_SOFT)
	batch.polygon(ellipse_points(face + Vector2(-sx * 0.38, -sy * 0.46), sx * 0.15, sy * 0.09, -0.6, 24), PHONE_SHINE)
	batch.flush(ci)
	return face


## Color de la ficha `i` del código de sala: el mismo orden que la TV,
## así el código se ve igual en los dos.
static func code_tile_color(i: int) -> Color:
	return CODE_TILE_COLORS[i % CODE_TILE_COLORS.size()]


## Fichas del código: amarillo dorado, verde, azul y rosa, como la maqueta
## (la primera era el naranja de los bloques; la maqueta la tiene dorada).
const CODE_TILE_COLORS: Array[Color] = [Color("#FFB728"), BRICKS[3], BRICKS[5], BRICKS[7]]


## Ficha grande de una letra del código (como en la TV). `lit`: es la que
## sigue por escribir (anillo de foco). Sin letra: ficha apagada.
static func draw_letter_tile(ci: CanvasItem, rect: Rect2, letter: String, color: Color, lit: bool = false) -> void:
	var empty := letter.is_empty()
	var face := draw_toy_key(ci, rect, PAPER_DIM if empty else color, 0.0, RADIUS * 0.8, rect.size.y * 0.07)
	if lit:
		draw_round_rect(ci, face.grow(FOCUS_WIDTH + 2.0), Color.TRANSPARENT, RADIUS * 0.8 + FOCUS_WIDTH, FOCUS_WIDTH, ACCENT)
	var size := int(face.size.y * 0.66)
	var c := face.get_center()
	if empty:
		# Guion bajo: "acá va una letra".
		draw_round_rect(ci, Rect2(c + Vector2(-face.size.x * 0.22, face.size.y * 0.18), Vector2(face.size.x * 0.44, 8.0)), MUTED, 4.0)
		return
	var px := maxi(6, size / 7)
	draw_text(ci, letter, c + Vector2(0, maxf(3.0, size / 18.0)), size, Color(INK, 0.6), px, Color(INK, 0.6))
	draw_text(ci, letter, c, size, PAPER, px, INK)


## Íconos que usa el celular además de los de draw_glyph:
##   tv · person · speaker · vibrate · exit · signal
## (otro nombre se pasa a draw_glyph). `off` tacha el ícono (sonido apagado).
static func draw_phone_glyph(ci: CanvasItem, glyph: String, c: Vector2, s: float, color: Color = INK,
		off: bool = false) -> void:
	var w := maxf(3.0, s * 0.11)
	match glyph:
		"tv":
			var screen := Rect2(c - Vector2(s * 0.55, s * 0.4), Vector2(s * 1.1, s * 0.7))
			draw_round_rect(ci, screen, color, s * 0.12)
			draw_round_rect(ci, screen.grow(-s * 0.1), color.lerp(INK, 0.55), s * 0.06)
			ci.draw_line(Vector2(c.x - s * 0.22, screen.end.y + s * 0.14), Vector2(c.x + s * 0.22, screen.end.y + s * 0.14), color, w, true)
			ci.draw_line(Vector2(c.x, screen.end.y), Vector2(c.x, screen.end.y + s * 0.14), color, w)
		"person":
			ci.draw_circle(c - Vector2(0, s * 0.2), s * 0.22, color)
			draw_round_rect(ci, Rect2(c + Vector2(-s * 0.38, s * 0.08), Vector2(s * 0.76, s * 0.4)), color, s * 0.2)
		"speaker":
			ci.draw_colored_polygon(PackedVector2Array([
				c + Vector2(-s * 0.45, -s * 0.15), c + Vector2(-s * 0.22, -s * 0.15), c + Vector2(s * 0.08, -s * 0.42),
				c + Vector2(s * 0.08, s * 0.42), c + Vector2(-s * 0.22, s * 0.15), c + Vector2(-s * 0.45, s * 0.15),
			]), color)
			if not off:
				ci.draw_arc(c + Vector2(s * 0.06, 0), s * 0.22, -PI * 0.3, PI * 0.3, 12, color, w, true)
				ci.draw_arc(c + Vector2(s * 0.06, 0), s * 0.4, -PI * 0.3, PI * 0.3, 12, color, w, true)
		"vibrate":
			var body := Rect2(c - Vector2(s * 0.2, s * 0.38), Vector2(s * 0.4, s * 0.76))
			draw_round_rect(ci, body, color, s * 0.08)
			draw_round_rect(ci, body.grow(-s * 0.07), color.lerp(INK, 0.55), s * 0.04)
			if not off:
				for k: int in [-1, 1]:
					var x := c.x + k * s * 0.34
					ci.draw_polyline(PackedVector2Array([Vector2(x, c.y - s * 0.26), Vector2(x + k * s * 0.08, c.y - s * 0.1),
						Vector2(x, c.y + s * 0.06), Vector2(x + k * s * 0.08, c.y + s * 0.22)]), color, w * 0.8, true)
		"exit":
			ci.draw_arc(c, s * 0.34, -PI * 0.3, PI * 1.3, 20, color, w, true)
			ci.draw_line(c - Vector2(0, s * 0.46), c + Vector2(0, s * 0.02), color, w, true)
		"signal":
			for i in 3:
				var h := s * (0.3 + 0.25 * i)
				draw_round_rect(ci, Rect2(c + Vector2(-s * 0.42 + i * s * 0.3, s * 0.4 - h), Vector2(s * 0.22, h)), color, s * 0.06)
		_:
			draw_glyph(ci, glyph, c, s, color)
	if off:
		ci.draw_line(c + Vector2(-s, -s) * 0.45, c + Vector2(s, s) * 0.45, DANGER, w * 1.2, true)


# --- Lobby (agente) ---------------------------------------------------------------
# Relieve "de juguete brillante" del lobby (fichas del código, botones, flechas
# del selector): contorno de tinta, labio oscuro abajo (sombra), cuerpo, luz
# arriba en degradé y un brillo chico. Todo dibujado, sin texturas.
#
# Concepto: *bisel*. Un botón plano parece una etiqueta; con luz arriba y
# sombra abajo el ojo lo lee como una pieza que sobresale y se puede apretar.
# Ejemplo: la ficha "K" del código es un bloque de juguete, no un recuadro.

const BEVEL_DEPTH := 8.0                  ## Alto del labio inferior (relieve).
const BEVEL_OUTLINE := 4.0                ## Contorno de tinta alrededor.
const BEVEL_SHADE := 0.3                  ## Cuánto se oscurece el labio.
const GLOSS_TOP := Color(1, 1, 1, 0.55)   ## Luz arriba del degradé del cuerpo.
const GLOSS_BOTTOM := Color(1, 1, 1, 0.0)
const SPECULAR := Color(1, 1, 1, 0.8)     ## Brillo chico arriba a la izquierda.
const SPARKLE := Color("#FF9F2E")         ## Rayitas del botón principal con foco.
const GLASS := Color(1, 1, 1, 0.4)        ## Tarjeta translúcida (lugar libre).
const GLASS_EDGE := Color(1, 1, 1, 0.9)
const HALO := Color(1, 1, 1, 0.2)         ## Resplandor detrás de la mascota.
const KEY_CAP := Color("#232846")         ## Teclas de las pistas del control remoto.


## Rectángulo redondeado con degradé vertical (`top` arriba, `bottom` abajo).
## Un solo polígono: un comando de dibujo.
static func draw_gradient_round_rect(ci: CanvasItem, rect: Rect2, top: Color, bottom: Color,
		radius: float = RADIUS) -> void:
	if rect.size.x <= 0.0 or rect.size.y <= 0.0:
		return
	var pts := round_rect_points(rect, radius, 6)
	var cols := PackedColorArray()
	cols.resize(pts.size())
	for i in pts.size():
		cols[i] = top.lerp(bottom, clampf((pts[i].y - rect.position.y) / rect.size.y, 0.0, 1.0))
	ci.draw_polygon(pts, cols)


## Pieza con bisel brillante. `rect` es el cuerpo sin apretar; el labio ocupa
## `depth` px más abajo. Apretada, el cuerpo baja y el labio casi no se ve.
static func draw_bevel(ci: CanvasItem, rect: Rect2, base: Color, radius: float,
		pressed: bool = false, outline_color: Color = INK, depth: float = BEVEL_DEPTH,
		outline: float = BEVEL_OUTLINE) -> void:
	var body := Rect2(rect.position + Vector2(0, depth * 0.7 if pressed else 0.0), rect.size)
	var whole := Rect2(rect.position, rect.size + Vector2(0, depth))
	draw_round_rect(ci, whole.grow(outline), outline_color, radius + outline, 0, INK, not pressed)
	draw_round_rect(ci, Rect2(rect.position + Vector2(0, depth), rect.size), base.darkened(BEVEL_SHADE), radius)
	draw_round_rect(ci, body, base, radius)
	var gloss := Rect2(body.position + Vector2(3, 3), Vector2(body.size.x - 6, body.size.y * 0.6))
	draw_gradient_round_rect(ci, gloss, Color(GLOSS_TOP, GLOSS_TOP.a * base.a), GLOSS_BOTTOM,
		minf(radius - 3.0, gloss.size.y / 2.0))
	var spec_h := maxf(5.0, body.size.y * 0.1)
	var spec := Rect2(body.position + Vector2(minf(radius * 0.7, body.size.x * 0.2), body.size.y * 0.1),
		Vector2(minf(body.size.x * 0.22, 110.0), spec_h))
	draw_round_rect(ci, spec, Color(SPECULAR, SPECULAR.a * base.a), spec_h / 2.0)


## Círculo con bisel (flechas del selector, numeritos): contorno, labio y brillo.
static func draw_bevel_circle(ci: CanvasItem, center: Vector2, r: float, base: Color,
		outline_color: Color = INK) -> void:
	var batch := ShapeBatch.new()
	var lip := maxf(3.0, r * 0.14)
	batch.circle(center + Vector2(0, lip * 0.5), r + BEVEL_OUTLINE, outline_color)
	batch.circle(center + Vector2(0, lip * 0.5), r, base.darkened(BEVEL_SHADE))
	batch.circle(center - Vector2(0, lip * 0.5), r, base)
	batch.ellipse(center - Vector2(r * 0.1, r * 0.5), r * 0.5, r * 0.2, Color(1, 1, 1, 0.45 * base.a))
	batch.flush(ci)


## Destellos del botón principal con foco: dos abanicos de rayitas a los
## costados de `rect` (uno hacia la izquierda y otro arriba a la derecha),
## cada uno con una estrellita. Van a los costados (no abajo) para no tapar
## las pistas del pie. Devuelve [origen, dirección, estrella] de cada abanico.
static func sparkle_fans(rect: Rect2) -> Array:
	var corner := rect.size.y * 0.15
	return [
		[Vector2(rect.position.x, rect.get_center().y), Vector2.LEFT,
			Vector2(rect.position.x - 46, rect.position.y + 2)],
		[Vector2(rect.end.x - corner, rect.position.y + corner), Vector2(1, -1).normalized(),
			Vector2(rect.end.x + 2, rect.end.y - 16)],
	]


## Un abanico de 3 rayitas (trazo que se afina hacia adentro, punta redonda,
## contorno de tinta) y su estrellita. Se dibuja una sola vez: la animación
## ("late") se hace escalando el nodo desde `origin`, sin redibujar.
## Un solo lote: un comando de dibujo.
static func draw_sparkle_fan(ci: CanvasItem, origin: Vector2, dir: Vector2, star: Vector2,
		color: Color = SPARKLE) -> void:
	var batch := ShapeBatch.new()
	for pass_i in 2:
		var col := INK if pass_i == 0 else color
		var w := 14.0 if pass_i == 0 else 8.0
		for k in 3:
			var d := dir.rotated((k - 1) * 0.62)
			var a := origin + d * 18.0
			var b := a + d * (32.0 if k == 1 else 24.0)
			var n := Vector2(-d.y, d.x) * (w / 2.0)
			batch.polygon(PackedVector2Array([a - n * 0.55, b - n, b + n, a + n * 0.55]), col)
			batch.circle(b, w / 2.0, col)
			batch.circle(a, w * 0.28, col)
	batch.star(star_points(star, 16.0, 0.45), star, INK)
	batch.star(star_points(star, 12.0, 0.45), star, GOLD)
	batch.flush(ci)


## Píldora (contador "6 de 7 elegidos", teclas): fondo, contorno claro y sombra.
static func chip_style(bg: Color, pad_h: int = 22, pad_v: int = 8,
		border: Color = GLASS_EDGE) -> StyleBoxFlat:
	var s := panel_style(bg, 999, pad_v)
	s.content_margin_left = pad_h
	s.content_margin_right = pad_h
	s.set_border_width_all(3)
	s.border_color = border
	s.shadow_size = 8
	s.shadow_offset = Vector2(0, 4)
	return s


# --- Mascotas (agente) ---
# Materiales de las mascotas (PlayerAvatar + MascotShading). El color del
# cuerpo lo elige cada jugador; estos son los que no cambian.
const MASCOT_FACE_SHADE := Color("#C8D1E6")  ## Borde sombreado de la cara blanca.
const MASCOT_EYE := Color("#11132A")         ## Ojos.
const MASCOT_EYE_GLOSS := Color("#4A5590")   ## Reflejo azulado abajo de los ojos.
const MASCOT_SHADE_TINT := Color("#26307A")  ## Tinte frío de las sombras del plástico.
const MASCOT_RIM := Color("#8C96C8")         ## Luz de contorno de los colores oscuros.
const MASCOT_SHOE := Color("#262B4D")        ## Zapatos.
const MASCOT_EAR_INNER := Color("#EE5A32")   ## Interior de las orejas de gato.
const MASCOT_BUNNY_INNER := Color("#FFB3C7") ## Interior de las orejas de conejo.
const MASCOT_METAL := Color("#C3CADB")       ## Piezas de metal del robot.

# --- Juegos (agente) ------------------------------------------------------------
# Tokens del arte de los minijuegos (host/minigames/game_art.gd): escenario de
# juguetes desenfocado, tablero con volumen, marcador con píldoras por jugador,
# globito 1P–4P sobre la mascota y brillo de los power-ups.

## Escenario detrás del tablero (se dibuja una vez y se desenfoca).
const STAGE_FLOOR := Color("#5FA8EE")
const STAGE_FLOOR_ALT := Color("#86C3F6")
const STAGE_CLOUD := Color("#F2F9FF")
## Tablero: sombra proyectada, marco de bloques con bisel y baldosas con relieve.
const BOARD_SHADOW := Color(0.03, 0.1, 0.32, 0.42)
const BOARD_FRAME := 40.0        ## Grosor del marco de bloques.
const BOARD_DEPTH := 16.0        ## Canto de abajo (el tablero "flota").
const BOARD_CORNER := 64.0       ## Bloque con estrella de cada esquina.
const BOARD_BRICK := 112.0       ## Largo aproximado de cada bloque del marco.
const TILE_GROUT := Color("#C9D2E6")   ## Junta entre baldosas.
const TILE_GAP := 2.0
const TILE_LIP := 5.0            ## Cara de abajo de la baldosa (relieve).
const TILE_CHAMFER := 4.0      ## Esquinas ochavadas de las baldosas.
const TILE_SHINE := Color(1, 1, 1, 0.7)
const TILE_SHADE := 0.08         ## Cuánto se oscurece la cara de abajo de una baldosa.
## Marcador de los juegos: píldora [1P | mascota | puntaje] y reloj central.
const HUD_PILL := Vector2(264, 70)
const HUD_CLOCK_H := 78.0
const HUD_TOP := 14.0
const HUD_GAP := 18.0
const HUD_TAG_SIZE := 32
const HUD_SCORE_SIZE := 40
const HUD_CLOCK_SIZE := 46
const HUD_PORTRAIT := Vector2(84, 104)   ## Mascota dentro de la píldora (px lógicos).
## Globito con la etiqueta 1P–4P sobre la cabeza de la mascota.
const TAG_BUBBLE := Vector2(62, 38)
const PLAYER_NAME_SIZE := 26     ## Etiqueta del globito y nombre (mismo tamaño: se dibujan juntos).
const TAG_OUTLINE := 6
## Brillo y halo de power-ups y premios.
const GLOW := Color("#FFD84A")
## Mesa de Ping Pong.
const TABLE_BLUE := Color("#2F6FDB")
const TABLE_BLUE_DARK := Color("#1F4FB0")


# --- Karts (agente) ---------------------------------------------------------------
const ACCENT_KARTS := Color("#FF6B3D")      ## Tarjeta de Karts de mascotas en el lobby.
const KARTS_GRASS := Color("#7ED35E")       ## Pasto en franjas (dos verdes).
const KARTS_GRASS_ALT := Color("#71C852")
const KARTS_TREE := Color("#3E9E48")        ## Copas de árboles y matas.
const KARTS_ROAD := Color("#646C8F")        ## Asfalto.
const KARTS_ROAD_LIGHT := Color("#6C7497")  ## Franja del medio del asfalto (gastada).
const KARTS_ROAD_LINE := Color(1, 1, 1, 0.8)
const KARTS_PUDDLE := Color("#4AA8F2")      ## Charcos resbalosos.
const KARTS_PUDDLE_SHINE := Color("#CDEBFF")


# --- Scroller (agente) -----------------------------------------------------------
## ¡Que no te deje la cámara!: color de la tarjeta y de las flechas de impulso.
const ACCENT_SCROLLER := Color("#84CC16")


# --- Memoria (agente) -------------------------------------------------------------
# Memoria de colores (host/minigames/memory/memory.gd): tablero de Simón con
# cuatro botones que se iluminan, uno por dirección del joystick. Cada botón
# tiene además su forma (estrella, corazón, rombo, círculo): no depende solo
# del color.

const ACCENT_MEMORY := Color("#D946EF")   ## Tarjeta del lobby.
## Botones del tablero en el orden de las direcciones: arriba (estrella),
## derecha (corazón), abajo (rombo) e izquierda (círculo).
const MEMORY_PADS: Array[Color] = [Color("#FFC21F"), Color("#F0444F"), Color("#3E7BFA"), Color("#2FBF63")]
const MEMORY_LIT_MIX := 0.18                 ## Cuánto se aclara un botón encendido (hacia blanco).
const MEMORY_DIM := Color(0.08, 0.1, 0.25, 0.38)  ## Botones apagados mientras la TV muestra la secuencia.
const MEMORY_RIM := Color("#2D3266")         ## Aro de plástico del tablero.
const MEMORY_RIM_LIGHT := Color("#4C55A0")   ## Brillo de arriba del aro.
const MEMORY_STUD := Color("#FFF4C2")        ## Lucecitas del aro.
const MEMORY_SOCKET := Color("#343A63")      ## Ficha vacía (todavía no la repetiste).
const MEMORY_CARD := Color(1, 1, 1, 0.88)    ## Tarjeta de cada jugador y de la ayuda.


# --- Pulido (agente) ---
# Resumen de ronda y podio con el arte de los juegos (marcador en píldoras,
# chapitas [1P | nombre] y puntos ganados en una placa que no pisa a la mascota).

## Marcador de arriba del resumen (ScoreBar): el mismo de los juegos
## (GameArt.paint_hud) con este aire arriba y abajo.
const SUMMARY_BAR_PAD := 12.0
const SUMMARY_BAR_H := HUD_CLOCK_H + 2.0 * SUMMARY_BAR_PAD
## Placa de los puntos ganados en la ronda ("+70", PointsBadge).
const SUMMARY_TITLE_SIZE := 72     ## Nombre del juego en el resumen de ronda (título "de logo").
const POINTS_BADGE_SIZE := 64      ## Tamaño del número.
const POINTS_BADGE_H := 92.0       ## Alto de la placa.
const POINTS_BADGE_PAD := 30.0     ## Aire a cada lado del número.
const POINTS_BADGE_GAP := 36.0     ## Separación mínima entre la placa y la mascota (orejas, antena).
## Chapita del jugador fuera de los juegos: [1P | Nombre  extra] (NamePlate).
const PLATE_H := 60.0
const PLATE_NAME_SIZE := 34
const PLATE_TAG_SIZE := 26
const PLATE_EXTRA_SIZE := 26
const PLATE_MAX_W := 460.0
## Contorno de tinta de las placas y chapitas (más grueso que el de los
## textos: separa la placa de cualquier fondo, incluida una mascota del mismo color).
const PLATE_OUTLINE := 5.0
const PLATE_LIP := 6.0             ## Canto de abajo (relieve).
const PLATE_GLOSS := Color(1, 1, 1, 0.3)
## Podio: puntos totales en un visor oscuro sobre el bloque.
const PODIUM_SCORE_SIZE := 36
const PODIUM_WELL_H := 58.0


# --- Efectos (agente) -----------------------------------------------------------
## Respuesta visual a cada acción (*juice*): partículas, números flotantes,
## sacudida, pausa de impacto y zoom. Ver host/minigames/juice.gd,
## core/ui/widgets/fx_particles.gd y docs/adr/0011-efectos.md.

## "Reducir movimiento" (accesibilidad, menú de pausa): sin sacudida ni zoom,
## sin golpes de escala y con menos partículas. Se guarda con los ajustes.
static var reduce_motion := false

## Duraciones (segundos).
const DUR_POP := 0.3            ## Golpe de escala de un texto o número al aparecer.
const DUR_FLOAT := 0.9          ## Número flotante "+1": sube y se desvanece.
const DUR_SHAKE := 0.24         ## Sacudida de cámara.
const DUR_HITSTOP := 0.07       ## Pausa de impacto (50–80 ms).
const DUR_ZOOM := 0.4           ## Zoom sutil (ej. al frenar en Reloj exacto).
const DUR_FINALE := 1.4         ## "¡Tiempo!": festejo antes de pasar al resumen.
## Curvas: EASE_POP es el rebote de "back out" (se pasa y vuelve).
const EASE_POP := 2.2           ## Cuánto se pasa el rebote (1,7 = suave; 3 = exagerado).
const EASE_POP_FROM := 1.7      ## Escala inicial del golpe de escala ("¡Tiempo!" entra grande).

## Medidas.
const FX_SHAKE_MAX := 9.0       ## px de la sacudida más fuerte (leve a propósito).
const FX_ZOOM := 0.035          ## Zoom sutil: +3,5 %.
const FX_MAX_PARTICLES := 192   ## Tope del pool de partículas de cada juego.
const FX_REDUCED := 0.35        ## Fracción de partículas con "Reducir movimiento".
const FX_FLOAT_SIZE := 34       ## Textos flotantes ("+1", "¡Rápido!"): ficha de juguete chica que no tapa el juego.
const FX_FLOAT_RISE := 70.0
const FX_BANNER_SIZE := 200     ## "¡Tiempo!", "¡Meta!".

## Colores.
const FX_DUST := Color(0.58, 0.63, 0.78, 0.75)   ## Polvo sobre el piso claro.
const FX_SPARK := Color("#FFF1B8")               ## Chispas y destellos.
const FX_SHINE := Color(1.0, 0.93, 0.55, 0.9)    ## Anillo de brillo al juntar un premio.
const FX_WATER := Color(1, 1, 1, 0.85)           ## Gotas del chapuzón en Empujones.


## Rebote "back out": 0 -> 1 pasándose un poco (EASE_POP) antes de asentarse.
static func ease_pop(k: float) -> float:
	k = clampf(k, 0.0, 1.0) - 1.0
	return 1.0 + (EASE_POP + 1.0) * k * k * k + EASE_POP * k * k


## Escala de un golpe de escala `t` segundos después de empezar: de
## EASE_POP_FROM (grande) a 1 con rebote. Con "Reducir movimiento", siempre 1.
static func pop_scale(t: float, dur: float = DUR_POP) -> float:
	if reduce_motion or t >= dur:
		return 1.0
	return lerpf(EASE_POP_FROM, 1.0, ease_pop(maxf(t, 0.0) / dur))


## Escala de algo que aparece `t` segundos después de nacer: de 0 a 1 con
## rebote (ej. una estrella nueva en Arena). Con "Reducir movimiento", 1.
static func appear_scale(t: float, dur: float = DUR_POP) -> float:
	if reduce_motion or t >= dur:
		return 1.0
	return ease_pop(maxf(t, 0.0) / dur)


## Ajustes de efectos (sección [video] del archivo de ajustes de la TV).
static func load_effects_prefs(path: String) -> void:
	var cfg := ConfigFile.new()
	if cfg.load(path) == OK:
		reduce_motion = bool(cfg.get_value("video", "reduce_motion", false))


static func save_effects_prefs(path: String) -> void:
	var cfg := ConfigFile.new()
	cfg.load(path)  # Conserva el resto de las secciones (sonido, apodo…).
	cfg.set_value("video", "reduce_motion", reduce_motion)
	cfg.save(path)


# --- Desenfunde (agente) ---
## Duelo del Oeste al atardecer (host/minigames/quickdraw/).
const ACCENT_QUICKDRAW := Color("#B7791F")    ## Tarjeta del lobby.
const QD_SKY_TOP := Color("#5A3D8F")          ## Cielo: violeta arriba…
const QD_SKY_MID := Color("#E4674A")          ## …naranja…
const QD_SKY_LOW := Color("#FFA95A")          ## …y amarillo en el horizonte.
const QD_HORIZON := Color("#FFD98C")
const QD_SUN := Color("#FFF0B3")
const QD_SUN_GLOW := Color(1.0, 0.86, 0.55, 0.55)
const QD_MESA_FAR := Color("#C45C78")         ## Mesetas lejanas (siluetas).
const QD_MESA_NEAR := Color("#9A4166")
const QD_SAND_FAR := Color("#F4C27E")         ## Arena: más clara lejos…
const QD_SAND_NEAR := Color("#DE9C58")        ## …más oscura adelante.
const QD_STREET := Color("#F7D39A")
const QD_RUT := Color(0.55, 0.32, 0.15, 0.22) ## Huellas de carreta.
const QD_SHADE := Color(0.3, 0.1, 0.2, 0.28)  ## Sombras sobre la arena.
const QD_SALOON := Color("#D8664F")
const QD_SHERIFF := Color("#4FA3A5")
const QD_TRIM := Color("#FFF1D6")             ## Marcos, carteles de las fachadas y texto del cartel.
const QD_WINDOW := Color("#3B2342")
const QD_WINDOW_LIT := Color("#FFC56B")
const QD_WOOD := Color("#B7773F")
const QD_WOOD_LIGHT := Color("#D39456")
const QD_WOOD_DARK := Color("#7E4A22")
const QD_WOOD_INK := Color("#4A2912")         ## Contorno del texto sobre madera.
const QD_ROPE := Color("#E8C48A")
const QD_CACTUS := Color("#4E9F57")
const QD_TUMBLE := Color("#C9975A")           ## Planta rodadora.
const QD_TUMBLE_DARK := Color("#7A5530")
const QD_HAT := Color("#8B5A2B")              ## Sombrero de vaquero (la cinta es del color del jugador).
const QD_HAT_DARK := Color("#5E3A1A")
const QD_POPGUN := Color("#5A6CD6")           ## Cebita de corcho de juguete.
const QD_CORK := Color("#E0A868")
const QD_SMOKE := Color(1, 1, 1, 0.85)


# --- Bots (agente) --------------------------------------------------------------
# Jugadores virtuales (host/bots/, ADR 0010): llevan una placa "BOT" en el
# lobby, el marcador de los juegos y el resumen de ronda, además de su
# nombre ("Bot Robi") y la mascota robot. Así no dependen del color.

const BOT_BADGE := Color("#4B5C9E")          ## Placa "BOT": azul acero, como el metal del robot.
const BOT_BADGE_LIGHT := Color("#8C9BD6")    ## Aro claro de la placa.
const BOT_BADGE_SIZE := Vector2(74, 34)      ## Tamaño con escala 1 (texto de 24 px: legible a 3 m).
const BOT_BADGE_FONT := 24
const BOT_MENU_WIDTH := 640.0                ## Menú "Lugar 3P" del lobby (agregar/cambiar/quitar bot).
const BOT_MENU_BUTTON := Vector2(0, 86)
const BOT_TEXT := "BOT"


## Placa "BOT" centrada en `center`: píldora con contorno de tinta, labio
## oscuro abajo, brillo arriba y el texto en blanco. `s` escala todo.
static func draw_bot_badge(ci: CanvasItem, center: Vector2, s: float = 1.0) -> void:
	var size := BOT_BADGE_SIZE * s
	var r := Rect2(center - size / 2.0, size)
	var radius := size.y / 2.0
	draw_round_rect(ci, Rect2(r.position + Vector2(0, 3.0 * s), r.size).grow(3.0 * s), INK, radius + 3.0 * s)
	draw_round_rect(ci, r, BOT_BADGE.darkened(0.3), radius)
	draw_round_rect(ci, Rect2(r.position, r.size - Vector2(0, 4.0 * s)), BOT_BADGE, radius, 2, BOT_BADGE_LIGHT)
	draw_round_rect(ci, Rect2(r.position + Vector2(8.0 * s, 3.0 * s), Vector2(size.x * 0.5, size.y * 0.28)),
		Color(1, 1, 1, 0.3), size.y * 0.14)
	draw_text(ci, BOT_TEXT, center - Vector2(0, 2.0 * s), int(BOT_BADGE_FONT * s), PAPER, int(4 * s), INK)


# --- Pool (agente) ---------------------------------------------------------------
# Mesa de Pool loco (host/minigames/pool/pool.gd): paño verde adentro del
# tablero de bloques, bandas, troneras y bolas doradas.

const POOL_FELT := Color("#2E9E57")          ## Paño.
const POOL_FELT_LIGHT := Color(0.75, 1.0, 0.75, 0.18)  ## Luz de lámpara en el centro del paño.
const POOL_CUSHION := Color("#1F7F45")       ## Bandas (más oscuras que el paño).
const POOL_CUSHION_EDGE := Color("#63CF8A")  ## Filo de luz de las bandas.
const POOL_MARK := Color(1, 1, 1, 0.22)      ## Marcas del paño (punto del centro).
const POOL_SIGHT := Color(1, 1, 1, 0.85)     ## Puntitos de las bandas.
const POOL_POCKET := Color("#0B0E22")        ## Fondo de las troneras.
const POOL_POCKET_RIM := Color("#3A4070")    ## Borde de las troneras.
const POOL_BALL_SHADOW := Color(0.02, 0.12, 0.05, 0.38)  ## Sombra de las bolas sobre el paño.
const POOL_SHINE := Color(1, 1, 1, 0.8)      ## Reflejo de las bolas.
const POOL_AIM_DOT := Color(1, 1, 1, 0.75)   ## Puntitos de la guía de tiro.
const POOL_HINT_BG := Color(0.07, 0.08, 0.2, 0.75)  ## Cartel "cómo se tira".


# --- Mascotas 2 (agente) ---
# Piezas nuevas de las mascotas (expresiones, bailes, robot rediseñado).
const MASCOT_SOCKET := Color("#2E3458")      ## Zócalo de goma de la antena del robot.
const MASCOT_BOLT := Color("#A3ABC2")        ## Tornillos de la frente del robot (metal más oscuro).


# --- Obstáculos (agente) ---
# Carrera de obstáculos (host/minigames/hurdles/): tarjeta del lobby, pozos y
# plataformas. Las vallas y los escalones usan BRICKS.
const ACCENT_HURDLES := Color("#5B6CFF")   ## Color de la tarjeta en el lobby.
const HURDLES_PIT := Color("#2B3470")      ## Pozo: arriba (boca).
const HURDLES_PIT_DEEP := Color("#141838") ## Pozo: abajo (fondo).
const HURDLES_GROUND := Color("#3CC46B")   ## Ladrillos del piso de los carriles (pasto)…
const HURDLES_GROUND_ALT := Color("#56D17F") ## …alternados con este tono.
const HURDLES_BUSH := Color("#CDEBD6")     ## Arbustos lejanos del fondo (pálidos: no distraen)…
const HURDLES_BUSH_LIGHT := Color("#E2F5E8") ## …y su brillo.
const HURDLES_POST := Color("#F4F6FB")     ## Patas blancas de las vallas.
const HURDLES_RAIL := Color(0.11, 0.13, 0.25, 0.28)  ## Riel de progreso de cada carril.


# --- Celular 2 (agente) ---
# Celular en juego "como un control de consola personalizado": fondo con el
# color del jugador, "Salir" manteniendo apretado, señal de Wi-Fi, instrucción
# del juego y panel de ajustes (ver controller/).

const PHONE_BACKDROP_TOP_MIX := 0.58      ## Arriba del degradé: color → papel.
const PHONE_BACKDROP_BOTTOM_MIX := 0.22   ## Abajo del degradé (más color).
const PHONE_BACKDROP_DARK_LUMINANCE := 0.2  ## Colores más oscuros (grafito, negro): degradé oscuro.
const PHONE_BACKDROP_DARK_LIFT := 0.2     ## Cuánto se aclara arriba un color oscuro.
const PHONE_BACKDROP_LIGHT_SHADE := 0.14  ## Cuánto se oscurece abajo un color muy claro (blanco).
const PHONE_PATTERN_ALPHA := 0.09         ## Patrón sutil (cruces y puntos) del fondo.
const PHONE_PATTERN_STEP := 120.0         ## Separación del patrón.
const PHONE_WATERMARK_ALPHA := 0.2        ## Mascota grande translúcida del fondo.
const PHONE_TAG_WATERMARK_ALPHA := 0.12   ## "4P" gigante del fondo.
const PHONE_RAYS_ALPHA := 0.16            ## Rayos detrás de la tarjeta en "¡Mirá la TV!".
const PHONE_SCRIM := Color(0.07, 0.1, 0.3, 0.6)  ## Velo detrás del panel de ajustes.
const PHONE_HOLD_SEC := 1.0               ## "Salir": mantener apretado este tiempo.
const PHONE_HOLD_RING := DANGER           ## Anillo de progreso de "Salir".
const PHONE_TOAST_SEC := 1.8              ## Avisos cortos ("Mantené apretado para salir").
const PHONE_CONTROL_SCALES: Array[float] = [0.8, 1.0, 1.2]  ## Tamaño del control: chico, normal, grande.
const PHONE_CONTROL_SIZE_NAMES: Array[String] = ["Chico", "Normal", "Grande"]
const PHONE_CONTROL_SIDE := 0.3           ## Centro del control, en fracción del ancho desde su borde.
const PHONE_BUTTON_RADIUS := 0.33         ## Botón grande: radio respecto del alto (tamaño normal)…
const PHONE_BUTTON_RADIUS_MAX := 0.37     ## …y el máximo, para que la carcasa entre en la pantalla.
const PHONE_DARK_KNOB_RIM := Color(1, 1, 1, 0.45)  ## Aro claro de la perilla/botón si el jugador es negro o grafito.
const PHONE_SIGNAL_OFF := Color(0.34, 0.36, 0.52, 0.28)  ## Barras de señal apagadas.
const PHONE_TEXT_BAR := 34                ## Texto de la barra superior (instrucción, avisos).
const PHONE_TEXT_SETTING := 40            ## Título de cada ajuste.
const PHONE_TEXT_SETTING_SUB := 28        ## Explicación de cada ajuste.
const PHONE_SETTING_ROW_H := 120.0        ## Alto de cada fila de ajustes (≥ TOUCH_TARGET casi).
const PHONE_SWITCH := Vector2(132, 72)    ## Interruptor Sí/No.


## Engranaje (botón de ajustes): rueda con 8 dientes y agujero, en un lote.
static func draw_gear(ci: CanvasItem, c: Vector2, s: float, color: Color, hole: Color) -> void:
	var batch := ShapeBatch.new()
	var r := s * 0.34
	for i in 8:
		var a := TAU * i / 8.0
		var d := Vector2.from_angle(a)
		var n := Vector2(-d.y, d.x) * s * 0.09
		batch.polygon(PackedVector2Array([c + d * r * 0.8 - n, c + d * s * 0.48 - n * 0.8,
			c + d * s * 0.48 + n * 0.8, c + d * r * 0.8 + n]), color)
	batch.circle(c, r, color)
	batch.circle(c, s * 0.14, hole)
	batch.flush(ci)


# --- Pantallas (agente) ---
# Tokens y dibujos de la intro "¿Cómo se juega?", el menú de pausa, los avisos
# de la TV (PlayerToasts), el selector TV/celular y la presentación IO-GAMES.
#
# Concepto: *reducir movimiento*. Pauta de accesibilidad: a algunas personas
# los rebotes, deslizamientos y destellos las marean o distraen. Con
# `reduce_motion` las pantallas solo hacen fundidos cortos (sin rebote, sin
# partículas, sin brillos que recorren). Ejemplo: la intro aparece entera con
# un fundido en vez de que cada tarjeta entre saltando.

## Reducir movimiento: usa `reduce_motion` de la sección "Efectos" (una sola
## preferencia para juegos y pantallas; la guardan load/save_effects_prefs).

## Título "de logo" (intro): relleno amarillo con brillo arriba, contorno de
## tinta, borde blanco por fuera y sombra dura, como el logo de PARTY-GAME.
const TITLE_FILL := Color("#FFC83D")
const TITLE_FILL_TOP := Color("#FFF1A8")   ## Mitad de arriba del relleno (brillo).
const TITLE_FILL_BOTTOM := Color("#FFA52E") ## Parte de abajo del relleno (naranja, como el logo).
const TITLE_RIM := Color("#FFFFFF")         ## Borde blanco exterior.
const TITLE_SHADOW := Color("#1D214099")    ## Sombra dura debajo (tinta al 60 %).
const TITLE_OUTLINE_RATIO := 0.16           ## Contorno de tinta respecto del tamaño de letra.
const TITLE_RIM_RATIO := 0.3                ## Borde blanco (incluye el contorno).

## Intro "¿Cómo se juega?".
const INTRO_TITLE_SIZE := 104
const INTRO_STEP_FONT := 36
const INTRO_STEP_ICON := 76.0
const INTRO_CARD_SIZE := Vector2(196, 214)  ## Tarjeta de cada jugador (mascota + 1P + nombre + estado).
const INTRO_READY_TEXT := Color("#1C8A52")  ## "¡Listo!" en texto: 4,6:1 sobre blanco (SUCCESS da 2,7:1).
const INTRO_WAIT_TEXT := Color("#565C85")   ## "Tocá tu celular" (= INK_SOFT).
const INTRO_ENTER_DELAY := 0.16             ## Espera a que el barrido destape la pantalla.
const INTRO_ENTER_STAGGER := 0.07           ## Retraso entre tarjetas que entran en cadena.
const INTRO_ENTER_DUR := 0.32
const INTRO_SLIDE := 70.0                   ## Cuánto se deslizan los paneles al entrar.

## Avisos de la TV (se conectó / se fue / volvió).
const TOAST_TOP := 110.0         ## Debajo del marcador de los juegos (HUD_TOP + HUD_PILL.y + 26).
const TOAST_HEIGHT := 92.0
const TOAST_GAP := 12.0
const TOAST_FONT := 32
const TOAST_COMPACT_FONT := 28
const TOAST_SHOW_SEC := 3.2      ## Cuánto se ve un aviso común.
const TOAST_EXPAND_SEC := 4.0    ## "Se desconectó" se ve grande este tiempo y después se achica.
const TOAST_MAX := 3
const TOAST_BG := Color("#FFFFFF")
const TOAST_ALERT := Color("#F28C28")  ## Borde de "se desconectó" (= WARNING).

## Menú de pausa.
const PAUSE_SHADE := Color("#1D214099")  ## Velo sobre el juego congelado (tinta al 60 %).
const PAUSE_WIDTH := 760.0
const PAUSE_BUTTON_H := 96.0
const PAUSE_DANGER := Color("#E5484D")   ## Botón "Sí, terminar" (= DANGER).

## Selector TV / celular.
const DEVICE_CARD_SIZE := Vector2(600, 520)

## Presentación IO-GAMES: colores del neón del logo.
const STUDIO_CYAN := Color("#2FD6FF")
const STUDIO_MAGENTA := Color("#C04BFF")
const STUDIO_GLOW := Color("#2F7BFF59")  ## Resplandor detrás del logo (35 %).
const SPLASH_TOTAL := 2.3   ## Segundos de la presentación completa (tope 2,5).


## Texto "de logo" centrado en `center`: sombra, borde blanco, contorno de
## tinta y relleno. `fill` y el tamaño los elige quien llama.
static func draw_logo_text(ci: CanvasItem, text: String, center: Vector2, size: int,
		fill: Color = TITLE_FILL) -> void:
	var font := FONT_BOLD
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	var pos := Vector2(center.x - w / 2.0, center.y + (font.get_ascent(size) - font.get_descent(size)) / 2.0)
	var ink := maxi(6, int(size * TITLE_OUTLINE_RATIO))
	var rim := maxi(ink + 6, int(size * TITLE_RIM_RATIO))
	ci.draw_string_outline(font, pos + Vector2(0, size * 0.09), text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, rim, TITLE_SHADOW)
	ci.draw_string_outline(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, rim, TITLE_RIM)
	ci.draw_string_outline(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, ink, INK)
	ci.draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, fill)


## Íconos de las pantallas (además de draw_glyph y draw_phone_glyph):
##   trophy · clock · eye · skip · flag · motion · question · check · star
## Otro nombre pasa a draw_phone_glyph (y de ahí a draw_glyph).
static func draw_screen_glyph(ci: CanvasItem, glyph: String, c: Vector2, s: float, color: Color = INK) -> void:
	var w := maxf(3.0, s * 0.12)
	match glyph:
		"trophy":
			var cup := PackedVector2Array([c + Vector2(-s * 0.36, -s * 0.4), c + Vector2(s * 0.36, -s * 0.4),
				c + Vector2(s * 0.28, -s * 0.02), c + Vector2(0, s * 0.12), c + Vector2(-s * 0.28, -s * 0.02)])
			ci.draw_colored_polygon(cup, color)
			# Asas: medio aro a cada lado.
			ci.draw_arc(c + Vector2(s * 0.34, -s * 0.24), s * 0.14, -PI / 2.0, PI / 2.0, 10, color, w, true)
			ci.draw_arc(c + Vector2(-s * 0.34, -s * 0.24), s * 0.14, PI / 2.0, PI * 1.5, 10, color, w, true)
			ci.draw_rect(Rect2(c + Vector2(-s * 0.06, s * 0.1), Vector2(s * 0.12, s * 0.18)), color)
			draw_round_rect(ci, Rect2(c + Vector2(-s * 0.26, s * 0.26), Vector2(s * 0.52, s * 0.16)), color, s * 0.05)
		"clock":
			ci.draw_arc(c, s * 0.4, 0.0, TAU, 32, color, w * 1.1, true)
			ci.draw_line(c, c + Vector2(0, -s * 0.26), color, w, true)
			ci.draw_line(c, c + Vector2(s * 0.2, s * 0.06), color, w, true)
			ci.draw_circle(c, w * 0.7, color)
		"eye":
			var pts := PackedVector2Array()
			for i in 17:
				var t := float(i) / 16.0
				pts.append(c + Vector2(lerpf(-s * 0.46, s * 0.46, t), -sin(t * PI) * s * 0.3))
			for i in range(15, 0, -1):
				var t := float(i) / 16.0
				pts.append(c + Vector2(lerpf(-s * 0.46, s * 0.46, t), sin(t * PI) * s * 0.3))
			ci.draw_colored_polygon(pts, color)
			ci.draw_circle(c, s * 0.19, color.lerp(INK, 0.75))
			ci.draw_circle(c + Vector2(-s * 0.06, -s * 0.06), s * 0.06, PAPER)
		"skip":
			draw_arrow(ci, c + Vector2(-s * 0.16, 0), s * 0.62, Vector2.RIGHT, color)
			draw_arrow(ci, c + Vector2(s * 0.16, 0), s * 0.62, Vector2.RIGHT, color)
			ci.draw_rect(Rect2(c + Vector2(s * 0.36, -s * 0.34), Vector2(w, s * 0.68)), color)
		"flag":
			ci.draw_line(c + Vector2(-s * 0.3, -s * 0.44), c + Vector2(-s * 0.3, s * 0.46), color, w, true)
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(-s * 0.3, -s * 0.42), c + Vector2(s * 0.4, -s * 0.26),
				c + Vector2(-s * 0.3, -s * 0.06)]), color)
		"motion":
			for k in 3:
				var y := c.y + (k - 1) * s * 0.28
				var pts := PackedVector2Array()
				for i in 9:
					var t := float(i) / 8.0
					pts.append(Vector2(c.x + lerpf(-s * 0.42, s * 0.42, t), y + sin(t * TAU) * s * 0.08))
				ci.draw_polyline(pts, color, w * 0.9, true)
		"question":
			draw_text(ci, "?", c + Vector2(0, s * 0.04), int(s * 1.05), color)
		"check":
			draw_check(ci, c, s * 0.8, color, w * 1.3)
		"star":
			ci.draw_colored_polygon(star_points(c, s * 0.48, 0.5), color)
		_:
			draw_phone_glyph(ci, glyph, c, s, color)


# --- Piezas 3D (agente) ---
# Estrellas, bloques del marco, medallas, corona, trofeo, monedas y gemas
# modeladas en 3D con el plástico de las mascotas y horneadas a un atlas
# (core/art3d, ADR 0016). Medidas en px lógicos (1920×1080).
const PROP_RES := 2.0              ## Px del atlas por px lógico (nítido a 4K).
const PROP_RES_STAR := 3.0         ## Estrellas (también se ven grandes: emblema de la transición).
const PROP_RES_BG := 1.0           ## Bloques del fondo (se ven chicos y desenfocados).
const PROP_SUPERSAMPLE := 4        ## Se renderiza 4× más grande y se promedia (bordes limpios).
const PROP_INK := 3.0              ## Contorno de tinta de las piezas.
const PROP_INK_THIN := 1.0         ## Contorno fino (bloques del marco: la junta entre bloques).
const PROP_BRICK_LIGHT := 0.12      ## Cuánto se aclara la tapa de los bloques del marco (color vivo, como la maqueta).
const PROP_TILT_DEG := 34.0        ## Bloques del tablero: cuánto se ve el canto de adelante.
const PROP_TOWER_TURN_DEG := 24.0  ## Bloques del fondo: cuánto se ve el costado.
const PROP_TOWER_TILT_DEG := 24.0  ## …y la tapa con botones.
const PROP_STAR_SHADE := Color("#F0892A")    ## Sombra naranja de las estrellas doradas.
const PROP_GEM := Color("#35C9E8")           ## Gema de premio.
const PROP_TROPHY_BASE := Color("#2E3570")   ## Pie del trofeo.
const PROP_JEWEL := Color("#F0524F")         ## Piedras de la corona.
const PROP_BALL := Color("#FFFFFF")          ## Pelota de Ping Pong.


# --- Estilos de música (agente) ---
# Selector "◀ ● Estilo: Fiesta ▶" de la pausa (MusicStyleStepper, ADR 0017).

const MUSIC_STYLE_DOT := 11.0      ## Radio del punto de color del estilo.
const MUSIC_STYLE_DOT_GAP := 12.0  ## Espacio entre el punto y el nombre.


## Color que identifica cada estilo de música (acompaña al nombre, nunca lo reemplaza).
static func music_style_color(style_id: String) -> Color:
	match style_id:
		"original": return ACCENT
		"fiesta": return BRICKS[7]
		"latino": return BRICKS[1]
		"relajado": return BRICKS[4]
		"retro": return BRICKS[6]
	return MUTED


# --- Lobby maqueta (agente) ---
# Lobby más cerca de docs/design/referencia_lobby.webp: tarjetas de jugador
# en degradé pastel del color del jugador, fichas del código y botón
# "¡A jugar!" con más volumen, y dioramas 3D de los juegos (ADR 0018).

const CARD_ART_FRACTION := 0.56       ## Alto de la ilustración en la tarjeta del juego (la maqueta: 58 %).
const DIORAMA_HAZE := 0.06            ## Bruma sobre el fondo desenfocado de los dioramas (poca: el fondo queda saturado).
const DIORAMA_ZOOM := 0.8            ## La cámara de cada diorama se acerca al blanco (1 = la receta tal cual)…
const DIORAMA_CAM_DROP := 0.86        ## …y baja (multiplica su altura sobre el blanco): el escenario llena la tarjeta.

# Tarjeta del jugador (SeatCard alta): degradé pastel del color del jugador
# con marco claro y un resplandor, como la maqueta.
const SEAT_TINT_TOP := 0.38            ## Color del jugador → papel: arriba…
const SEAT_TINT_BOTTOM := 0.86         ## …y abajo (degradé pastel).
const SEAT_LIGHT_TINT := Color("#8CC8FF")  ## Base del degradé para colores muy claros (blanco): si no, la tarjeta sería blanca.
const SEAT_RIM := Color(1, 1, 1, 0.92)     ## Marco claro de la tarjeta.
const SEAT_RIM_W := 5.0
const SEAT_GLOW := Color(1, 1, 1, 0.16)    ## Resplandor detrás de la mascota (se apila en anillos).
const SEAT_SHADOW := Color(0.07, 0.1, 0.3, 0.22)
const SEAT_SHADOW_Y := 8.0
const SEAT_GLASS := Color(1, 1, 1, 0.34)   ## Lugar libre: tarjeta de vidrio.
const SEAT_GLASS_TOP := Color(1, 1, 1, 0.5)
const SEAT_PLUS_DISC := Color(1, 1, 1, 0.75)  ## Disco del "+" grande del lugar libre.
const SEAT_NAME_BASE_TOP := 0.3            ## Base clara del nombre: opacidad arriba (tapa los pies de la mascota)…
const SEAT_NAME_BASE_BOTTOM := 0.92        ## …y abajo.
const SEAT_TAG_SIZE := Vector2(80, 46)     ## Pastilla 1P–4P.
const SEAT_TAG_FONT := 28

# Piezas "de juguete" del lobby (fichas del código, botones): sin contorno de
# tinta, con canto oscuro abajo, cuerpo en degradé, brillo arriba y un
# borde apenas más oscuro, como los bloques de la maqueta.
const TOY_DEPTH := 12.0                ## Alto del canto de abajo.
const TOY_LIP_SHADE := 0.3             ## Canto: cuánto se oscurece el color.
const TOY_TOP_LIGHT := 0.1             ## Cuerpo: arriba, el color apenas aclarado (la maqueta es color pleno)…
const TOY_BOTTOM_SHADE := 0.08         ## …abajo, apenas oscurecido.
const TOY_EDGE_SHADE := 0.42           ## Borde fino alrededor de la pieza.
const TOY_EDGE_W := 2.5
const TOY_GLOSS := Color(1, 1, 1, 0.26)    ## Brillo de la mitad de arriba (suave: no lava el color).
const TOY_SPEC := Color(1, 1, 1, 0.5)      ## Reflejo chico arriba a la izquierda.
const TOY_SHADOW := Color(0.07, 0.1, 0.3, 0.25)
const CODE_TILE_SIZE := Vector2(108, 146)  ## Fichas del código de sala en la TV.
const CODE_TILE_RADIUS := 24.0
const CODE_TILE_GAP := 12
const CODE_LETTER_OUTLINE := 12

# Botón "¡A jugar!": amarillo con bisel fuerte, ▶ grande y destellos.
const START_SIZE := Vector2(660, 118)
const START_FONT := 44
const START_TOP := Color("#FFD435")
const START_BOTTOM := Color("#FFAE18")
const START_LIP := Color("#E58B10")
const START_DEPTH := 14.0
const BUTTON_LIGHT_LIP := Color("#C3CCE3")   ## Canto de los botones blancos ("Orden").

# Selector de música del lobby (MusicStyleStepper compacto, junto al título).
const MUSIC_PILL_SIZE := Vector2(430, 68)
const MUSIC_PILL_FONT := 28


## Base del degradé de la tarjeta de un jugador de color `col`.
static func seat_tint(col: Color) -> Color:
	return col if col.get_luminance() < LIGHT_COLOR_LUMINANCE else SEAT_LIGHT_TINT


## Rectángulo redondeado con degradé vertical dentro de un lote.
static func batch_gradient_round_rect(batch: ShapeBatch, rect: Rect2, radius: float, top: Color,
		bottom: Color, steps: int = 6) -> void:
	if rect.size.x <= 0.0 or rect.size.y <= 0.0:
		return
	var pts := round_rect_points(rect, radius, steps)
	var base := batch.points.size()
	batch.points.append_array(pts)
	for p in pts:
		batch.colors.append(top.lerp(bottom, clampf((p.y - rect.position.y) / rect.size.y, 0.0, 1.0)))
	for i in range(1, pts.size() - 1):
		batch.indices.append_array([base, base + i, base + i + 1])


## Borde suavizado (antialiasing) de un rectángulo redondeado dentro del lote:
## una línea fina del color de la figura sobre su contorno.
static func batch_round_rect_edge(batch: ShapeBatch, rect: Rect2, radius: float, color: Color,
		width: float = 1.0, steps: int = 6) -> void:
	var pts := round_rect_points(rect, radius, steps)
	pts.append(pts[0])
	batch.polyline(pts, color, width)


## Tarjeta del jugador en el lobby: sombra, marco claro, degradé pastel de
## su color y un resplandor detrás de la mascota (centro `glow`). Un lote.
static func draw_seat_card(ci: CanvasItem, rect: Rect2, col: Color, radius: float, glow: Vector2) -> void:
	var base := seat_tint(col)
	var batch := ShapeBatch.new()
	batch.polygon(round_rect_points(Rect2(rect.position + Vector2(0, SEAT_SHADOW_Y), rect.size).grow(2.0), radius + 2.0, 6),
		SEAT_SHADOW)
	batch.polygon(round_rect_points(rect, radius, 6), SEAT_RIM)
	var inner := rect.grow(-SEAT_RIM_W)
	batch_gradient_round_rect(batch, inner, radius - SEAT_RIM_W, base.lerp(PAPER, SEAT_TINT_TOP),
		base.lerp(PAPER, SEAT_TINT_BOTTOM))
	var rx := inner.size.x * 0.5
	for k in 4:  # Anillos suaves apilados: resplandor sin textura.
		batch.ellipse(glow, rx * (1.0 - 0.2 * k), rx * (0.9 - 0.18 * k), SEAT_GLOW)
	batch_round_rect_edge(batch, rect, radius, SEAT_RIM)
	batch.flush(ci)


## Tarjeta de vidrio (lugar libre): translúcida con marco claro.
static func draw_glass_card(ci: CanvasItem, rect: Rect2, radius: float) -> void:
	var batch := ShapeBatch.new()
	batch_gradient_round_rect(batch, rect, radius, SEAT_GLASS_TOP, SEAT_GLASS)
	batch_round_rect_edge(batch, rect.grow(-1.5), radius - 1.5, SEAT_RIM, 3.0)
	batch.flush(ci)


## Pieza de juguete del lobby (ficha del código, botón) dentro de `rect`
## (cuerpo + canto): sombra, borde fino, canto oscuro, cuerpo en degradé
## `top` → `bottom`, brillo arriba y reflejo chico. Un lote (un draw call).
## `press` 0..1 baja el cuerpo. Devuelve el rectángulo del cuerpo (para el
## texto o el ícono).
static func draw_toy_block(ci: CanvasItem, rect: Rect2, top: Color, bottom: Color, lip: Color,
		radius: float, depth: float = TOY_DEPTH, press: float = 0.0) -> Rect2:
	var sink := depth * 0.75 * clampf(press, 0.0, 1.0)
	var body := Rect2(rect.position + Vector2(0, sink), rect.size - Vector2(0, depth))
	var whole := rect  # Cuerpo + canto (dos rectángulos redondeados corridos = uno más alto).
	var edge := lip.darkened(TOY_EDGE_SHADE)
	var batch := ShapeBatch.new()
	batch.polygon(round_rect_points(Rect2(whole.position + Vector2(0, depth * 0.6), whole.size).grow(1.0), radius + 1.0, 6),
		TOY_SHADOW)
	batch.polygon(round_rect_points(whole.grow(TOY_EDGE_W), radius + TOY_EDGE_W, 6), edge)
	batch.polygon(round_rect_points(whole, radius, 6), lip)
	batch.polygon(round_rect_points(body.grow(TOY_EDGE_W * 0.6), radius + TOY_EDGE_W * 0.6, 6), edge.lerp(lip, 0.5))
	batch_gradient_round_rect(batch, body, radius, top, bottom)
	var gloss := Rect2(body.position + Vector2(5, 4), Vector2(body.size.x - 10, body.size.y * 0.48))
	batch_gradient_round_rect(batch, gloss, minf(radius - 4.0, gloss.size.y / 2.0), TOY_GLOSS, Color(TOY_GLOSS, 0.0))
	var spec_h := clampf(body.size.y * 0.1, 5.0, 12.0)
	var spec := Rect2(body.position + Vector2(minf(radius * 0.75, body.size.x * 0.2), body.size.y * 0.1),
		Vector2(minf(body.size.x * 0.2, 90.0), spec_h))
	batch.polygon(round_rect_points(spec, spec_h / 2.0, 4), TOY_SPEC)
	batch_round_rect_edge(batch, whole.grow(TOY_EDGE_W), radius + TOY_EDGE_W, edge)
	batch.flush(ci)
	return body


## Ficha de color `col` (código de sala): degradé del mismo color.
static func draw_toy_tile(ci: CanvasItem, rect: Rect2, col: Color, radius: float = CODE_TILE_RADIUS,
		depth: float = TOY_DEPTH) -> Rect2:
	return draw_toy_block(ci, rect, col.lightened(TOY_TOP_LIGHT), col.darkened(TOY_BOTTOM_SHADE),
		col.darkened(TOY_LIP_SHADE), radius, depth)


## Nota musical (♪) en un lote: cabeza inclinada, plica y banderita.
static func draw_music_note(ci: CanvasItem, c: Vector2, s: float, color: Color) -> void:
	var batch := ShapeBatch.new()
	var head := c + Vector2(-s * 0.14, s * 0.28)
	batch.ellipse(head, s * 0.2, s * 0.14, color, -0.4)
	var x := head.x + s * 0.17
	batch.polygon(PackedVector2Array([Vector2(x - s * 0.07, head.y - s * 0.02), Vector2(x - s * 0.07, c.y - s * 0.44),
		Vector2(x, c.y - s * 0.44), Vector2(x, head.y - s * 0.02)]), color)
	batch.polygon(PackedVector2Array([Vector2(x - s * 0.02, c.y - s * 0.44), Vector2(x + s * 0.24, c.y - s * 0.24),
		Vector2(x + s * 0.24, c.y - s * 0.08), Vector2(x - s * 0.02, c.y - s * 0.26)]), color)
	batch.flush(ci)

# Fondo del lobby más lleno y vivo (PartyBackground, como la maqueta).
const BG_MID_TOWER_BLOCK := 50.0            ## Bloques de la fila de torres del medio.
const BG_MID_TOWER_GAP := Vector2(0.045, 0.075)  ## Separación entre torres del medio (fracción del ancho).
const BG_HAZE_FRONT := 0.0                  ## Torres de adelante: color puro (antes, BG_HAZE_NEAR).

# --- Escenario 2.5D (agente) ---
# Tablero y entorno de juguetes en 3D horneados una vez a una textura, con
# cámara en perspectiva; el juego se dibuja en 2D proyectado encima
# (core/art3d/board_view_25d.gd, ADR 0019). Medidas en unidades del mundo =
# px del plano del juego (una baldosa de Pintar el piso mide 74).

## Cámara: grados sobre el piso (90 = desde arriba), campo de visión vertical,
## distancia al punto que mira y ese punto (relativo al centro del tablero).
## Ajustada para que el tablero ocupe lo mismo que en la maqueta.
const BOARD25D_PITCH_DEG := 65.0
const BOARD25D_FOV_DEG := 28.0
const BOARD25D_DISTANCE := 2182.0
const BOARD25D_TARGET := Vector2(0, 3)
## Tablero 3D: marco (ancho y cuánto sobresale del piso), base debajo de las
## baldosas, bloque de las esquinas, baldosas y contornos de tinta.
const BOARD25D_FRAME_W := 58.0
const BOARD25D_FRAME_H := 40.0
const BOARD25D_BASE := 44.0
const BOARD25D_CORNER := 90.0
const BOARD25D_CORNER_RISE := 14.0    ## Las esquinas sobresalen un poco más que el marco.
const BOARD25D_STAR_LIFT_DEG := 38.0  ## La estrella de la esquina se levanta hacia la cámara.
const BOARD25D_BRICK_ROUND := 11.0    ## Radio de los cantos de los bloques del marco.
const BOARD25D_TILE_H := 12.0
const BOARD25D_TILE_GAP := 2.5
const BOARD25D_TILE_ROUND := 5.0
const BOARD25D_INK := 3.2
const BOARD25D_INK_THIN := 2.2
const BOARD25D_LIGHT := 0.26          ## Cuánto se aclara la cara iluminada del plástico.
const BOARD25D_GROUT := Color("#B9C4DD")   ## Junta entre baldosas (la base del tablero).
const BOARD25D_EDGE_SHADE_W := 46.0   ## Sombra del marco sobre el piso.
const BOARD25D_EDGE_SHADE_ALPHA := 0.22
## Sala alrededor del tablero (se desenfoca): piso celeste a cuadros y sombra.
const BOARD25D_GROUND_TILE := 250.0
const BOARD25D_GROUND_A := Color("#5DAEF3")
const BOARD25D_GROUND_B := Color("#93CCF8")
const BOARD25D_SHADOW := Color(0.04, 0.12, 0.36, 0.5)
## Horneado: supermuestreo del tablero, azulejos por lado (la textura de
## render más grande es de 1920×1080) y desenfoque del entorno (se arma a
## 1/BACK_DIV de la pantalla y se le pasa el desenfoque gaussiano del fondo
## BLUR_PASSES veces, con muestras cada BLUR_STEP px).
const BOARD25D_SUPERSAMPLE := 2
const BOARD25D_TILES := 2
const BOARD25D_BACK_DIV := 2
const BOARD25D_BLUR_STEP := 1.5
const BOARD25D_BLUR_PASSES := 2
## Mascotas y premios parados sobre el tablero: escala por profundidad, con
## tope para que el cuadro horneado de la mascota no cambie de tamaño (ADR 0012).
const BOARD25D_SCALE_MIN := 0.86
const BOARD25D_SCALE_MAX := 1.25
## Premio sobre el piso: cuánto flota (px) y su sombra acostada.
const BOARD25D_POWER_HOVER := 16.0
const BOARD25D_POWER_SHADOW := Color(0.08, 0.1, 0.3, 0.28)
## Juguetes de alrededor: celeste extra, cuánto se mezclan con la bruma
## (lo de lejos es más claro) y hasta dónde llega el piso detrás del tablero.
const BOARD25D_TOY_SKY := Color("#63B7F7")
const BOARD25D_TOY_HAZE := 0.0
const BOARD25D_GROUND_BACK := 150.0
## Baldosas del tablero a cuadros (claras y grises, como la maqueta).
const BOARD25D_TILE_LIGHT := Color("#F6F8FC")
const BOARD25D_TILE_DARK := Color("#DDE3EE")

# --- Tablero 2.5D de Arena, Esquivar y Pool (agente, ADR 0019) ---
## Ancho del plano que la cámara encuadra como la maqueta (el de Pintar el
## piso): BoardView25D.make_fit aleja la cámara para un campo más ancho
## (Arena y Esquivar, 1600 px) y la acerca para uno más angosto (Pool, 1420 px).
const BOARD25D_FIT_WIDTH := 1480.0
## Esquivar: baldosas lila (se distingue de Arena, que tiene el mismo campo;
## las sombras y el aviso de los bloques se leen igual de bien).
const BOARD25D_DODGE_TILE_LIGHT := Color("#F7F4FD")
const BOARD25D_DODGE_TILE_DARK := Color("#E4DDF4")
## Esquivar: alto de un bloque de juguete (fracción de su lado) y z de la
## capa de los bloques en el aire (por delante del marcador mientras caen).
const BOARD25D_BLOCK_RISE := 0.75
const BOARD25D_AIR_Z := 1
## Pool: alto y canto de las bandas, aro de las troneras, lugar entre la
## tronera y la banda, miras, marcas del paño y sombra de las bandas sobre el paño.
const BOARD25D_POOL_CUSHION_H := 20.0
const BOARD25D_POOL_CUSHION_ROUND := 7.0
const BOARD25D_POOL_RIM := 6.0
const BOARD25D_POOL_POCKET_GAP := 4.0
const BOARD25D_POOL_SIGHT_R := 5.5
const BOARD25D_POOL_MARK_DOT := 7.0
const BOARD25D_POOL_MARK_RING := 141.0
const BOARD25D_POOL_SHADE_W := 22.0
## Pool: cuánto se aclara el paño 3D (la luz de arriba del plástico lo
## oscurece; así queda del tono del paño plano, POOL_FELT).
const BOARD25D_POOL_FELT_LIFT := 0.12

# --- Ayuda de eliminados (agente) ---
# Ayuda de los eliminados (docs/MODOS.md §11, ADR 0020): burbuja de Esquivar,
# salvavidas de Empujones, mascota traslúcida del ayudante, marcador de "a
# quién ayudo" y el cartel "Tomi ayudó a Sofi · −10" (HelpFx, TvHelpOverlay).
## Burbuja (Esquivar): relleno celeste translúcido, borde claro y brillo.
const HELP_BUBBLE_FILL := Color(0.62, 0.9, 1.0, 0.32)
const HELP_BUBBLE_RIM := Color("#BFF3FF")
const HELP_BUBBLE_SHINE := Color(1, 1, 1, 0.75)
## Radio y centro de la burbuja (× u de la mascota; el centro, sobre los pies).
const HELP_BUBBLE_R := 118.0
const HELP_BUBBLE_LIFT := 92.0
## Salvavidas (Empujones): gajos rojos y blancos, a la altura de la panza.
const HELP_BUOY_RED := Color("#F0524F")
const HELP_BUOY_WHITE := Color("#FFFFFF")
const HELP_BUOY_R := 64.0
const HELP_BUOY_W := 20.0
const HELP_BUOY_LIFT := 44.0
const HELP_BUOY_FLAT := 0.42            ## Achatado (visto desde arriba en diagonal).
## Últimos segundos de la ayuda: titila (fracción de la duración).
const HELP_BLINK_FROM := 0.25
## Mascota traslúcida del ayudante al lado del ayudado.
const HELP_GHOST_ALPHA := 0.55
const HELP_GHOST_SCALE := 0.9           ## Respecto de la mascota del ayudado.
const HELP_GHOST_SIDE := 118.0          ## Cuánto al costado (× u).
## Marcador "a quién ayudo" sobre el candidato elegido (ficha con 1P–4P del ayudante).
const HELP_MARKER_LIFT := 262.0         ## Sobre los pies (× u): arriba del globito 1P–4P.
const HELP_MARKER_SIZE := Vector2(92, 52)
const HELP_MARKER_FONT := 28
## Cartel "Tomi ayudó a Sofi · −10": ficha de juguete abajo al centro.
const HELP_BANNER_FONT := 30
const HELP_BANNER_H := 64.0
const HELP_BANNER_BOTTOM := 18.0        ## Del borde de abajo de la pantalla.
const HELP_BANNER_SEC := 2.8
const HELP_BANNER_TAG := Vector2(62, 42)
const HELP_BANNER_COST := Color("#E5484D")   ## "−10" (lo que costó).
## Resumen de la ronda: línea "Tomi −10 por ayudar a Sofi".
const HELP_SUMMARY_FONT := 28


# --- Tablero 2.5D de Karts (agente, ADR 0019) ---
## Karts: la pista entera va horneada en 3D con el pasto (franjas), el
## asfalto y las marcas planas, los cordones de bloques con volumen, los
## turbos como bloques con flechas, los charcos y los árboles como esferas
## de plástico. Medidas en unidades del mundo (px del plano).
const BOARD25D_KARTS_CURB_H := 11.0       ## Alto de los bloques del cordón (ancho: Karts.CURB).
const BOARD25D_KARTS_CURB_ROUND := 4.0    ## Canto de los bloques del cordón.
const BOARD25D_KARTS_PAD_H := 7.0         ## Alto del bloque del turbo.
const BOARD25D_KARTS_TREE_SINK := 0.12    ## Cuánto se hunde la copa (fracción del radio): apoya en el pasto.
const BOARD25D_KARTS_MARK_Y := 0.6        ## Altura de las marcas planas sobre el pasto (asfalto, líneas, charcos).
const BOARD25D_KARTS_INK_BAND := 5.0      ## Tinta por fuera del cordón.
## Cuánto se aclara la cara de arriba del pasto, los turbos y las copas 3D
## (menos que BOARD25D_LIGHT: vistos de arriba son casi todo cara iluminada
## y con el valor de las baldosas quedaban lavados; así quedan del tono de
## los tokens KARTS_* del dibujo plano).
const BOARD25D_KARTS_LIGHT := 0.06

# --- Sala de juguetes 3D como cielo de los juegos sin tablero (agente, ADR 0019) ---
## Área que rodean los juguetes en la receta "stage" (MiniGame.draw_sky):
## el tablero de Pintar el piso, así el fondo queda como en los juegos 2.5D.
const BOARD25D_STAGE_AREA := Rect2(220, 133, 1480, 814)

# --- Carriles 2.5D de Carrera de toques y de obstáculos (agente, ADR 0019) ---
## Altura de las marcas planas sobre las baldosas y opacidad de la
## división entre carriles (tinta mezclada con la baldosa clara).
const BOARD25D_LANE_MARK_Y := 0.6
const BOARD25D_LANE_DIVIDER_ALPHA := 0.45

# --- Mesa 2.5D de Ping Pong (agente, ADR 0019) ---
## La mesa es la pieza (sin marco de bloques): cuánto sobresale la tapa del
## área de juego, grosor y canto de la tapa, ancho de la línea blanca, alto
## de la red, cuánto se levanta la cara de la paleta sobre su base y cuánto
## se aclara la tapa (vista de arriba, casi toda cara iluminada).
const BOARD25D_PP_EDGE := 18.0
const BOARD25D_PP_TOP_H := 30.0
const BOARD25D_PP_ROUND := 12.0
const BOARD25D_PP_LINE := 6.0
const BOARD25D_PP_NET_H := 34.0
const BOARD25D_PP_PADDLE_RISE := 6.0
const BOARD25D_PP_LIGHT := 0.08
