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
const STUDIO_BG := Color("#000D22")     ## Fondo de la presentación IO-GAMES (el de su logo).
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


## Las tres capas van en un solo lote (ShapeBatch): un draw call, no tres.
static func draw_star(ci: CanvasItem, center: Vector2, r: float, color: Color = GOLD, rotation: float = 0.0) -> void:
	var batch := ShapeBatch.new()
	batch.star(star_points(center, r + 5.0, 0.5, rotation), center, INK)
	batch.star(star_points(center, r, 0.48, rotation), center, color)
	var shine := center + Vector2(-r * 0.12, -r * 0.12)
	batch.star(star_points(shine, r * 0.35, 0.5, rotation), shine, Color(1, 1, 1, 0.55))
	batch.flush(ci)


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
const BG_SKY_TOP := Color("#3C8CE6")
const BG_SKY_MID := Color("#6DB9F7")
const BG_HAZE := Color("#D3E9FF")        ## Bruma del horizonte: lo lejano se mezcla con este color.
const BG_GLOW := Color(1.0, 0.98, 0.9, 0.42)   ## Luz ambiente arriba al centro.
const BG_BEAM := Color(1.0, 1.0, 1.0, 0.12)    ## Haces de luz del escenario.
const BG_CLOUD_SHADE := Color("#C9DDF6")  ## Panza de las nubes.
const BG_FLOOR_A := Color("#F1F3FC")
const BG_FLOOR_B := Color("#CCD5EF")
const BG_VIGNETTE := Color(0.06, 0.12, 0.38, 0.30)  ## Bordes más oscuros: la UI del centro resalta.
const BG_SPARKLE := Color("#FFF4C2")      ## Brillos que titilan.
const BG_HAZE_FAR := 0.42   ## Cuánto se mezclan con la bruma las torres de atrás.
const BG_HAZE_NEAR := 0.2  ## …y las de adelante.
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
	return BRICKS[(i * 2 + 1) % BRICKS.size()]


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
