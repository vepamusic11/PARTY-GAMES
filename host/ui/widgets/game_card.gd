class_name GameCard
extends Button
## Tarjeta de minijuego en el lobby. OK del control remoto la marca o
## desmarca para la competencia. Si no se puede jugar con la cantidad de
## jugadores elegida queda deshabilitada, pero sigue siendo navegable para
## que se pueda leer el motivo ("Solo 2 jugadores").
##
## Ilustración: la miniatura del juego (assets/thumbs/<id>.webp, generada con
## tools/make_thumbnails.gd) con esquinas redondeadas. Si el juego todavía no
## tiene miniatura, se dibuja un "escenario" genérico con el ícono del control.

const CONTROL_NAMES := {
	Protocol.LAYOUT_JOYSTICK: "Joystick",
	Protocol.LAYOUT_SLIDER_H: "Deslizar",
	Protocol.LAYOUT_ONE_BUTTON: "Un botón",
	Protocol.LAYOUT_JOYSTICK_AB: "Joystick + A/B",
}

## Miniaturas: assets/thumbs/<id>.webp (ver tools/make_thumbnails.gd).
const THUMB_DIR := "res://assets/thumbs/"
const THUMB_EXT := ".webp"

var info: Dictionary
var unavailable_reason := ""
var _thumb: Texture2D  ## null: el juego no tiene miniatura (dibujo de respaldo).

## id -> Texture2D (o null si no hay): cada miniatura se carga una sola vez
## y la comparten la tarjeta y la intro.
static var _thumb_cache := {}


func _init(p_info: Dictionary) -> void:
	info = p_info
	_thumb = thumbnail(str(info.get("id", "")))
	# La miniatura se achica mucho: con mipmaps no aparece serrucho.
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	toggle_mode = true
	focus_mode = Control.FOCUS_ALL
	custom_minimum_size = Vector2(270, 206)
	for style in ["normal", "hover", "pressed", "disabled", "focus", "hover_pressed"]:
		add_theme_stylebox_override(style, StyleBoxEmpty.new())
	toggled.connect(func(_on: bool) -> void: queue_redraw())
	focus_entered.connect(_on_focus.bind(true))
	focus_exited.connect(_on_focus.bind(false))
	resized.connect(func() -> void: pivot_offset = size / 2.0)


func set_unavailable(reason: String) -> void:
	unavailable_reason = reason
	disabled = not reason.is_empty()
	queue_redraw()


func is_selected() -> bool:
	return button_pressed and not disabled


static func players_text(p_info: Dictionary) -> String:
	var lo := int(p_info.min_players)
	var hi := int(p_info.max_players)
	if lo == hi:
		return "%d jugador%s" % [lo, "" if lo == 1 else "es"]
	return "%d–%d jugadores" % [lo, hi]


static func thumbnail_path(game_id: String) -> String:
	return THUMB_DIR + game_id + THUMB_EXT


## Miniatura del juego, o null si no tiene (juego nuevo sin generar).
static func thumbnail(game_id: String) -> Texture2D:
	if game_id.is_empty():
		return null
	if not _thumb_cache.has(game_id):
		var path := thumbnail_path(game_id)
		_thumb_cache[game_id] = load(path) as Texture2D if ResourceLoader.exists(path) else null
	return _thumb_cache[game_id]


## Dibuja `tex` llenando `rect` (recorta lo que sobra, centrado) con esquinas
## redondeadas: un solo polígono con coordenadas de textura, sin shaders.
## El borde se suaviza con una línea del color de fondo (`edge`).
static func draw_thumbnail(ci: CanvasItem, tex: Texture2D, rect: Rect2, radius: float,
		modulate: Color = Color.WHITE, edge: Color = Color.TRANSPARENT) -> void:
	var tex_size := tex.get_size()
	var src := Rect2(Vector2.ZERO, tex_size)
	if rect.size.x / rect.size.y > tex_size.x / tex_size.y:
		src.size.y = tex_size.x * rect.size.y / rect.size.x
	else:
		src.size.x = tex_size.y * rect.size.x / rect.size.y
	src.position = (tex_size - src.size) / 2.0
	var points := _round_rect_points(rect, radius)
	var uvs := PackedVector2Array()
	for p in points:
		uvs.append((src.position + (p - rect.position) / rect.size * src.size) / tex_size)
	ci.draw_colored_polygon(points, modulate, uvs, tex)
	if edge.a > 0.0:
		points.append(points[0])
		ci.draw_polyline(points, edge, 2.0, true)


static func _round_rect_points(rect: Rect2, radius: float, steps: int = 8) -> PackedVector2Array:
	var r := minf(radius, minf(rect.size.x, rect.size.y) / 2.0)
	var pts := PackedVector2Array()
	var corners := [
		[Vector2(rect.end.x - r, rect.position.y + r), -PI / 2.0],
		[Vector2(rect.end.x - r, rect.end.y - r), 0.0],
		[Vector2(rect.position.x + r, rect.end.y - r), PI / 2.0],
		[Vector2(rect.position.x + r, rect.position.y + r), PI],
	]
	for c in corners:
		for k in steps + 1:
			pts.append((c[0] as Vector2) + Vector2.from_angle(float(c[1]) + PI / 2.0 * k / steps) * r)
	return pts


func _on_focus(focused: bool) -> void:
	create_tween().tween_property(self, "scale", Vector2.ONE * (1.05 if focused else 1.0), 0.12)
	queue_redraw()


func _draw() -> void:
	var r := Rect2(Vector2(10, 10), size - Vector2(20, 20))
	var a := 0.55 if disabled else 1.0
	var accent: Color = info.get("accent", UiTheme.ACCENT)
	if disabled:
		accent = accent.lerp(UiTheme.MUTED, 0.6)
	if has_focus():
		UiTheme.draw_round_rect(self, r.grow(12), Color(UiTheme.INK, 0.5), 40)
		UiTheme.draw_round_rect(self, r.grow(9), UiTheme.ACCENT, 38)
	UiTheme.draw_round_rect(self, r, Color(UiTheme.PAPER, a), 30, 6.0 if is_selected() else 0.0, UiTheme.SUCCESS, true)

	# Ilustración: la miniatura del juego; si no tiene, un "escenario" con
	# cielo en degradé del color del juego, piso a cuadros y el ícono del control.
	var art := Rect2(r.position + Vector2(10, 10), Vector2(r.size.x - 20, r.size.y * 0.5))
	if _thumb != null:
		_draw_thumb_art(art, accent)
	else:
		_draw_art(art, accent, a)
	# Tipo de control como etiqueta sobre la ilustración, abajo a la izquierda
	# (el centro queda libre para la foto y la línea de abajo, para la
	# cantidad de jugadores o el motivo por el que no se puede jugar).
	var control_name: String = CONTROL_NAMES.get(info.get("layout"), "Control")
	var cw := UiTheme.FONT_BOLD.get_string_size(control_name, HORIZONTAL_ALIGNMENT_LEFT, -1, 20).x + 24.0
	var chip := Rect2(Vector2(art.position.x + 10, art.end.y - 10 - 32), Vector2(cw, 32))
	UiTheme.draw_round_rect(self, chip, Color(UiTheme.PAPER, 0.92 * a), 16)
	UiTheme.draw_text(self, control_name, chip.get_center(), 20, Color(UiTheme.INK, a))

	# Marca de selección
	var badge := Vector2(art.end.x - 26, art.position.y + 26)
	if is_selected():
		draw_circle(badge, 24, UiTheme.PAPER)
		draw_circle(badge, 20, UiTheme.SUCCESS)
		UiTheme.draw_check(self, badge, 24, UiTheme.PAPER, 5.0)
	elif disabled:
		draw_circle(badge, 24, Color(UiTheme.INK, 0.55))
		UiTheme.draw_glyph(self, "lock", badge, 30, UiTheme.PAPER)
	else:
		draw_circle(badge, 22, Color(UiTheme.PAPER, 0.9 * a))
		draw_arc(badge, 16, 0, TAU, 24, Color(UiTheme.INK_SOFT, 0.5 * a), 3.0, true)

	var text_x := r.position.x + 20
	UiTheme.draw_text_left(self, str(info.get("title", "")), Vector2(text_x, art.end.y + 30), 28,
		Color(UiTheme.INK, a), r.size.x - 40)
	var meta := unavailable_reason if disabled else players_text(info)
	var meta_x := text_x
	if not disabled:
		UiTheme.draw_glyph(self, "people", Vector2(text_x + 14, art.end.y + 66), 26, UiTheme.INK_SOFT)
		meta_x += 36
	UiTheme.draw_text_left(self, meta, Vector2(meta_x, art.end.y + 66), 24,
		UiTheme.DANGER if disabled else UiTheme.INK_SOFT, r.size.x - 40 - (meta_x - text_x), false)


func _draw_thumb_art(art: Rect2, accent: Color) -> void:
	var frame := Color(accent.darkened(0.25), 0.55 if disabled else 1.0)
	UiTheme.draw_round_rect(self, art, frame, 22)
	var photo := art.grow(-4)
	if disabled:
		# No se puede jugar: la foto apagada (gris y transparente sobre el papel).
		draw_thumbnail(self, _thumb, photo, 18, Color(1, 1, 1, 0.5), frame)
		var veil := _round_rect_points(photo, 18)
		draw_colored_polygon(veil, Color(UiTheme.MUTED, 0.45))
	else:
		draw_thumbnail(self, _thumb, photo, 18, Color.WHITE, frame)


func _draw_art(art: Rect2, accent: Color, a: float) -> void:
	UiTheme.draw_round_rect(self, art, Color(accent.darkened(0.25), a), 22)
	var sky := art.grow(-4)
	var horizon := sky.position.y + sky.size.y * 0.52
	var top := Color(accent.lightened(0.35), a)
	var mid := Color(accent, a)
	# Cielo: degradé vertical en un solo polígono.
	draw_polygon(PackedVector2Array([
		Vector2(sky.position.x + 14, sky.position.y), Vector2(sky.end.x - 14, sky.position.y),
		Vector2(sky.end.x, horizon), Vector2(sky.position.x, horizon),
	]), PackedColorArray([top, top, mid, mid]))
	# Piso: baldosas en perspectiva (cada fila más ancha que la anterior).
	var batch := UiTheme.ShapeBatch.new()
	var rows := 4
	var light := Color(accent.lightened(0.55), a)
	var dark := Color(accent.lightened(0.2), a)
	for row in rows:
		var t0 := float(row) / rows
		var t1 := float(row + 1) / rows
		var y0 := lerpf(horizon, sky.end.y - 4.0, t0 * t0)
		var y1 := lerpf(horizon, sky.end.y - 4.0, t1 * t1)
		var cols := 6
		for col in cols:
			var spread0 := lerpf(0.55, 1.0, t0)
			var spread1 := lerpf(0.55, 1.0, t1)
			var cx := sky.get_center().x
			var hw := sky.size.x / 2.0
			var x00 := cx + (float(col) / cols * 2.0 - 1.0) * hw * spread0
			var x01 := cx + (float(col + 1) / cols * 2.0 - 1.0) * hw * spread0
			var x10 := cx + (float(col) / cols * 2.0 - 1.0) * hw * spread1
			var x11 := cx + (float(col + 1) / cols * 2.0 - 1.0) * hw * spread1
			batch.polygon(PackedVector2Array([Vector2(x00, y0), Vector2(x01, y0), Vector2(x11, y1), Vector2(x10, y1)]),
				light if (row + col) % 2 == 0 else dark)
	# Destellos en el cielo.
	for k in 3:
		var p := sky.position + Vector2(sky.size.x * (0.2 + 0.3 * k), sky.size.y * (0.18 + 0.1 * (k % 2)))
		batch.polygon(UiTheme.star_points(p, 7.0 + 3.0 * (k % 2)), Color(1, 1, 1, 0.55 * a))
	batch.flush(self)
	var icon_c := Vector2(art.get_center().x + art.size.x * 0.14, horizon + 4.0)
	UiTheme.draw_ellipse(self, icon_c + Vector2(0, art.size.y * 0.26), art.size.y * 0.32, art.size.y * 0.08, Color(UiTheme.INK, 0.22 * a))
	UiTheme.draw_control_icon(self, icon_c, art.size.y * 0.28, str(info.get("layout", "")), a)

