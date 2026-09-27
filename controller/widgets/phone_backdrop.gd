class_name PhoneBackdrop
extends Control
## Fondo del celular una vez unido, "como la carcasa de un control
## personalizado": degradé suave con el color del jugador, un patrón sutil
## de cruces y puntos (el plástico texturado de un joystick) y, mientras se
## juega, su etiqueta 1P–4P y su mascota gigantes y translúcidas del lado
## libre (el opuesto al control).
##
## Se lee con cualquier color: con blanco el degradé baja a gris claro y con
## grafito o negro queda oscuro. Lo que va directo encima usa `ink()`
## (UiTheme.text_on del color del medio del degradé).
##
## Batería: el fondo se dibuja UNA vez (y de nuevo solo si cambian el color,
## el tamaño o el modo). La mascota translúcida se prepara una sola vez en un
## SubViewport (UPDATE_ONCE): dibujada directo con transparencia se verían
## las piezas superpuestas (brazos, cara, accesorio).

const MASCOT_TEX := Vector2i(320, 448)  ## Mascota del fondo: 80 × 112 unidades a u = 4.
const TAG_SIZE := 0.3      ## "4P" gigante: alto de letra respecto del alto de la pantalla.
const TAG_Y := 0.3         ## Centro del "4P", en fracción del alto.
const MASCOT_H := 0.58     ## Alto de la mascota respecto del de la pantalla.
const MASCOT_CROP := 0.08  ## Cuánto se sale la mascota por abajo (se ve "asomada").

var color := UiTheme.PAPER
var slot := 0
var style := -1
## Etiqueta y mascota gigantes (solo mientras hay un control en pantalla).
var show_watermark := false
## Lado de la marca de agua: el contrario al del control.
var watermark_right := true
## Rayos de fiesta ("¡Mirá la TV!"): centro (INF = sin rayos) y largo.
var rays_at := Vector2.INF
var rays_radius := 0.0

var _mascot_vp: SubViewport
var _mascot: PlayerAvatar
var _mascot_rect: TextureRect


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mascot_vp = SubViewport.new()
	_mascot_vp.size = MASCOT_TEX
	_mascot_vp.transparent_bg = true
	_mascot_vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	add_child(_mascot_vp)
	_mascot = PlayerAvatar.new()
	_mascot.animate = false
	_mascot.mood = PlayerAvatar.Mood.HAPPY
	_mascot.size = Vector2(MASCOT_TEX)
	_mascot_vp.add_child(_mascot)
	_mascot_rect = TextureRect.new()
	_mascot_rect.texture = _mascot_vp.get_texture()
	_mascot_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_mascot_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_mascot_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mascot_rect.modulate = Color(1, 1, 1, UiTheme.PHONE_WATERMARK_ALPHA)
	_mascot_rect.visible = false
	add_child(_mascot_rect)


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_place_mascot()


## Colores de arriba y abajo del degradé para el color de un jugador.
static func gradient(col: Color) -> Array[Color]:
	var lum := col.get_luminance()
	if lum < UiTheme.PHONE_BACKDROP_DARK_LUMINANCE:
		return [col.lightened(UiTheme.PHONE_BACKDROP_DARK_LIFT), col]
	if lum > UiTheme.LIGHT_COLOR_LUMINANCE:
		return [UiTheme.PAPER, col.darkened(UiTheme.PHONE_BACKDROP_LIGHT_SHADE)]
	return [col.lerp(UiTheme.PAPER, UiTheme.PHONE_BACKDROP_TOP_MIX), col.lerp(UiTheme.PAPER, UiTheme.PHONE_BACKDROP_BOTTOM_MIX)]


## Color de texto legible directo sobre el fondo de este color.
static func ink_for(col: Color) -> Color:
	var g := gradient(col)
	return UiTheme.text_on(g[0].lerp(g[1], 0.5))


func ink() -> Color:
	return ink_for(color)


## Cambia el jugador. Solo redibuja (y vuelve a preparar la mascota) si
## cambió algo.
func set_player(p_color: Color, p_slot: int, p_style: int) -> void:
	if p_color == color and p_slot == slot and p_style == style:
		return
	color = p_color
	slot = p_slot
	style = p_style
	_mascot.color = color
	_mascot.slot = slot
	_mascot.style = style
	_mascot.queue_redraw()  # color y slot no redibujan solos.
	_mascot_vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	queue_redraw()


func set_watermark(show: bool, right: bool) -> void:
	if show == show_watermark and right == watermark_right:
		return
	show_watermark = show
	watermark_right = right
	_mascot_rect.visible = show
	_place_mascot()
	queue_redraw()


func set_rays(at: Vector2, radius: float) -> void:
	if at == rays_at and is_equal_approx(radius, rays_radius):
		return
	rays_at = at
	rays_radius = radius
	queue_redraw()


## Color de los rayos: luz blanca sobre los colores; sobre el blanco, dorada.
static func rays_color(col: Color) -> Color:
	var lum := col.get_luminance()
	if lum > UiTheme.LIGHT_COLOR_LUMINANCE:
		return Color(UiTheme.ACCENT, UiTheme.PHONE_RAYS_ALPHA * 2.0)
	if lum < UiTheme.PHONE_BACKDROP_DARK_LUMINANCE:
		return Color(UiTheme.PAPER, UiTheme.PHONE_RAYS_ALPHA)
	return Color(UiTheme.PAPER, UiTheme.PHONE_RAYS_ALPHA * 2.5)


## Centro horizontal de la marca de agua.
func watermark_x() -> float:
	var side := size.x * UiTheme.PHONE_CONTROL_SIDE
	return size.x - side if watermark_right else side


func _place_mascot() -> void:
	var h := size.y * MASCOT_H
	var w := h * MASCOT_TEX.x / MASCOT_TEX.y
	_mascot_rect.size = Vector2(w, h)
	_mascot_rect.position = Vector2(watermark_x() - w / 2.0, size.y - h * (1.0 - MASCOT_CROP))


func _draw() -> void:
	var g := gradient(color)
	var r := Rect2(Vector2.ZERO, size)
	draw_polygon(PackedVector2Array([r.position, Vector2(r.end.x, 0), r.end, Vector2(0, r.end.y)]),
		PackedColorArray([g[0], g[0], g[1], g[1]]))
	# Patrón: filas alternadas de cruces y puntos, corridas media celda.
	var mark := Color(ink(), UiTheme.PHONE_PATTERN_ALPHA)
	var step := UiTheme.PHONE_PATTERN_STEP
	var batch := UiTheme.ShapeBatch.new()
	var row := 0
	var y := step * 0.5
	while y < size.y + step:
		var x := step * (0.25 if row % 2 == 0 else 0.75)
		var col := 0
		while x < size.x + step:
			var p := Vector2(x, y)
			if (row + col) % 2 == 0:
				var a := step * 0.12
				var b := step * 0.035
				batch.polygon(PackedVector2Array([p + Vector2(-a, -b), p + Vector2(a, -b), p + Vector2(a, b), p + Vector2(-a, b)]), mark)
				batch.polygon(PackedVector2Array([p + Vector2(-b, -a), p + Vector2(b, -a), p + Vector2(b, a), p + Vector2(-b, a)]), mark)
			else:
				batch.circle(p, step * 0.06, mark)
			x += step
			col += 1
		y += step * 0.5
		row += 1
	batch.flush(self)
	if rays_at.is_finite():
		_draw_rays()
	if show_watermark:
		# "4P" gigante: se distingue sin depender del color (como en la TV).
		var fs := int(size.y * TAG_SIZE)
		UiTheme.draw_text(self, UiTheme.player_tag(slot), Vector2(watermark_x(), size.y * TAG_Y), fs,
			Color(ink(), UiTheme.PHONE_TAG_WATERMARK_ALPHA))


## Abanico de rayos que se desvanecen hacia afuera: un solo arreglo de
## triángulos con color por vértice (un comando de dibujo).
func _draw_rays() -> void:
	const COUNT := 16
	var inner := rays_color(color)
	var outer := Color(inner, 0.0)
	var pts := PackedVector2Array()
	var cols := PackedColorArray()
	var idx := PackedInt32Array()
	for i in COUNT:
		var a := TAU * i / COUNT + 0.1
		var half := TAU / COUNT * 0.25
		var base := pts.size()
		pts.append(rays_at)
		pts.append(rays_at + Vector2.from_angle(a - half) * rays_radius)
		pts.append(rays_at + Vector2.from_angle(a + half) * rays_radius)
		cols.append(inner)
		cols.append(outer)
		cols.append(outer)
		idx.append_array([base, base + 1, base + 2])
	RenderingServer.canvas_item_add_triangle_array(get_canvas_item(), idx, pts, cols)
