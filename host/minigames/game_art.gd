class_name GameArt
extends RefCounted
## Arte común de los minijuegos en la TV (ver docs/design/referencia_juego_pintar.webp):
##   - escenario de juguetes desenfocado detrás de todo (`stage_texture`);
##   - tablero con volumen: sombra proyectada, marco de bloques con bisel,
##     canto de abajo, estrellas en las esquinas y baldosas con relieve
##     (`paint_board`);
##   - marcador: píldora por jugador [1P | mascota | puntaje] y reloj en una
##     píldora oscura con borde arcoíris (`paint_hud`);
##   - globito 1P–4P sobre la cabeza de la mascota y nombre abajo
##     (`draw_player_tag`);
##   - brillo y halo de power-ups (`add_glow`).
##
## Lo usan MiniGame (capas cacheadas: fondo y marcador) y cada juego para lo
## suyo. Colores y medidas: UiTheme (sección "Juegos"). Decisión: ADR 0009.
##
## Rendimiento (ver docs/PERFORMANCE.md):
##   - El escenario es UNA textura chica (480×270) armada una sola vez por
##     proceso con Image y desenfocada achicándola y agrandándola: 1 draw call.
##   - Todo lo demás va en TriBatch: una lista de triángulos sin índices en un
##     solo canvas_item_add_triangle_array (un draw call por lote). Las formas
##     se precalculan en coordenadas locales (circle_tris, round_rect_tris) y
##     se ubican con Transform2D * PackedVector2Array (en C++), así armar un
##     lote por frame casi no cuesta CPU en GDScript.

const SCREEN := Vector2(1920, 1080)
## El escenario se arma a 1/4 de la resolución: al estirarlo con filtro
## lineal ya queda desenfocado (y además se le pasa un desenfoque barato).
const STAGE_DOWNSCALE := 4
## Las mascotas del marcador se dibujan al doble en su textura: se ven nítidas.
const PORTRAIT_SUPERSAMPLE := 2
const PORTRAIT_SCALE := 0.8       ## Escala de la mascota dentro de la píldora.

static var _stage: Texture2D
static var _stage_gen := -1
static var _shapes: Dictionary = {}   # clave -> PackedVector2Array (triángulos locales)
static var _patterns: Dictionary = {} # [colores, veces] -> PackedColorArray repetido
static var _label_widths: Dictionary = {}  # texto -> ancho (globito y nombre)
static var _bubbles: Dictionary = {}  # [color, dirección, alfa] -> globito armado [puntos, colores]


# --- Lote de triángulos -----------------------------------------------------------

## Junta figuras rellenas en UNA lista de triángulos (un draw call al hacer
## flush). Respeta el orden: lo agregado después queda encima. A diferencia de
## UiTheme.ShapeBatch no usa índices: agregar una forma precalculada son dos
## append_array (en C++), sin bucles en GDScript.
class TriBatch:
	extends RefCounted

	var points := PackedVector2Array()
	var colors := PackedColorArray()

	## Triángulos locales (de a 3 puntos) ubicados con `xform`, de un color.
	func shape(tris: PackedVector2Array, xform: Transform2D, col: Color) -> void:
		points.append_array(xform * tris)
		var c := PackedColorArray()
		c.resize(tris.size())
		c.fill(col)
		colors.append_array(c)

	## Triángulos locales con color por vértice (ver GameArt.tile_template).
	func template(tris: PackedVector2Array, cols: PackedColorArray, xform: Transform2D) -> void:
		points.append_array(xform * tris)
		colors.append_array(cols)

	func tri(a: Vector2, b: Vector2, c: Vector2, col: Color) -> void:
		points.append_array(PackedVector2Array([a, b, c]))
		colors.append_array(PackedColorArray([col, col, col]))

	## Cuadrilátero convexo (puntos en orden).
	func quad(a: Vector2, b: Vector2, c: Vector2, d: Vector2, col: Color) -> void:
		points.append_array(PackedVector2Array([a, b, c, a, c, d]))
		colors.append_array(PackedColorArray([col, col, col, col, col, col]))

	func quad_colors(a: Vector2, b: Vector2, c: Vector2, d: Vector2, ca: Color, cb: Color, cc: Color, cd: Color) -> void:
		points.append_array(PackedVector2Array([a, b, c, a, c, d]))
		colors.append_array(PackedColorArray([ca, cb, cc, ca, cc, cd]))

	func rect(r: Rect2, col: Color) -> void:
		quad(r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y), col)

	## Segmento grueso (como draw_line sin antialiasing).
	func line(a: Vector2, b: Vector2, col: Color, width: float) -> void:
		var n := (b - a).normalized().orthogonal() * (width / 2.0)
		quad(a + n, b + n, b - n, a - n, col)

	func circle(center: Vector2, r: float, col: Color, segs: int = 24) -> void:
		shape(GameArt.circle_tris(segs), Transform2D(0.0, Vector2(r, r), 0.0, center), col)

	func ellipse(center: Vector2, rx: float, ry: float, col: Color, rotation: float = 0.0) -> void:
		shape(GameArt.circle_tris(20), Transform2D(rotation, Vector2(rx, ry), 0.0, center), col)

	## Degradé radial: `inner` en el centro y `outer` en el borde (halo).
	func radial(center: Vector2, r: float, inner: Color, outer: Color, segs: int = 32) -> void:
		points.append_array(Transform2D(0.0, Vector2(r, r), 0.0, center) * GameArt.circle_tris(segs))
		# El primer punto de cada triángulo es el centro.
		colors.append_array(GameArt.pattern_colors(PackedColorArray([inner, outer, outer]), segs))

	## Rectángulo redondeado (radio en px); con radio = alto/2 es una píldora.
	func round_rect(r: Rect2, radius: float, col: Color) -> void:
		shape(GameArt.round_rect_tris(r.size, radius), Transform2D(0.0, r.get_center()), col)

	func capsule(r: Rect2, col: Color) -> void:
		round_rect(r, minf(r.size.x, r.size.y) / 2.0, col)

	## Rectángulo con las esquinas ochavadas (`k` px): 6 triángulos en vez de
	## los ~36 de uno redondeado. Para lo chico y repetido (baldosas, bloques).
	func chamfer_rect(r: Rect2, k: float, col: Color) -> void:
		k = minf(k, minf(r.size.x, r.size.y) / 2.0)
		var x0 := r.position.x
		var y0 := r.position.y
		var x1 := r.end.x
		var y1 := r.end.y
		polygon(PackedVector2Array([Vector2(x0 + k, y0), Vector2(x1 - k, y0), Vector2(x1, y0 + k), Vector2(x1, y1 - k),
			Vector2(x1 - k, y1), Vector2(x0 + k, y1), Vector2(x0, y1 - k), Vector2(x0, y0 + k)]), col)

	## Anillo entre dos rectángulos redondeados con el mismo centro (un
	## contorno sin relleno); `radius` es el del de adentro.
	func ring_round_rect(outer_r: Rect2, inner_r: Rect2, radius: float, col: Color) -> void:
		var o := GameArt.round_rect_outline(outer_r.size, radius + (outer_r.size.x - inner_r.size.x) / 2.0)
		var inn := GameArt.round_rect_outline(inner_r.size, radius)
		var co := outer_r.get_center()
		var cc := inner_r.get_center()
		for i in o.size():
			var j := (i + 1) % o.size()
			quad(co + o[i], co + o[j], cc + inn[j], cc + inn[i], col)

	## Borde suavizado (antialiasing barato) de un rectángulo redondeado: una
	## franja de `width` px por fuera que va de `col` a transparente. Se usa
	## en el contorno de afuera (el que se ve contra el fondo).
	func feather_round_rect(r: Rect2, radius: float, col: Color, width: float = 1.6) -> void:
		var key := Vector3(r.size.x, r.size.y, radius + width * 1000.0)
		var ring: PackedVector2Array = GameArt._shapes.get(key, PackedVector2Array())
		if ring.is_empty():
			ring = GameArt._remember(key, GameArt.ring_tris(GameArt.round_rect_outline(r.size, radius),
				GameArt.round_rect_outline(r.size + Vector2(width, width) * 2.0, radius + width)))
		_feather_ring(ring, Transform2D(0.0, r.get_center()), col)

	func feather_capsule(r: Rect2, col: Color, width: float = 1.6) -> void:
		feather_round_rect(r, minf(r.size.x, r.size.y) / 2.0, col, width)

	func feather_circle(center: Vector2, r: float, col: Color, segs: int = 32, width: float = 1.6) -> void:
		var key := Vector3(-2.0, segs, r + width * 1000.0)
		var ring: PackedVector2Array = GameArt._shapes.get(key, PackedVector2Array())
		if ring.is_empty():
			var inner := PackedVector2Array()
			var outer := PackedVector2Array()
			for i in segs:
				var d := Vector2.from_angle(TAU * i / segs)
				inner.append(d * r)
				outer.append(d * (r + width))
			ring = GameArt._remember(key, GameArt.ring_tris(inner, outer))
		_feather_ring(ring, Transform2D(0.0, center), col)

	## Anillo (GameArt.ring_tris) que va de `col` adentro a transparente afuera.
	func _feather_ring(ring: PackedVector2Array, xform: Transform2D, col: Color) -> void:
		points.append_array(xform * ring)
		var clear := Color(col, 0.0)
		colors.append_array(GameArt.pattern_colors(PackedColorArray([col, clear, clear, col, clear, col]), ring.size() / 6))

	## Anillo difuso entre dos contornos ya calculados (sin caché: para lo que
	## se dibuja una vez, como la sombra del tablero).
	func _feather(inner: PackedVector2Array, outer: PackedVector2Array, c: Vector2, col: Color) -> void:
		_feather_ring(GameArt.ring_tris(inner, outer), Transform2D(0.0, c), col)

	## Polígono convexo (abanico desde el primer punto).
	func polygon(pts: PackedVector2Array, col: Color) -> void:
		var n := pts.size()
		if n < 3:
			return
		var tris := PackedVector2Array()
		tris.resize((n - 2) * 3)
		for i in range(1, n - 1):
			tris[(i - 1) * 3] = pts[0]
			tris[(i - 1) * 3 + 1] = pts[i]
			tris[(i - 1) * 3 + 2] = pts[i + 1]
		shape(tris, Transform2D.IDENTITY, col)

	## Estrella con contorno de tinta y brillo, como UiTheme.draw_star.
	func star(center: Vector2, r: float, col: Color, rotation: float = 0.0, outline: float = 5.0) -> void:
		if outline > 0.0:
			_star(center, r + outline, 0.5, rotation, UiTheme.INK)
		_star(center, r, 0.48, rotation, col)
		var shine := center + Vector2(-r * 0.12, -r * 0.12)
		_star(shine, r * 0.35, 0.5, rotation, Color(1, 1, 1, 0.55))

	func _star(center: Vector2, r: float, inner: float, rotation: float, col: Color) -> void:
		shape(GameArt.star_tris(inner), Transform2D(rotation, Vector2(r, r), 0.0, center), col)

	## Dibuja lo acumulado en `ci` (un solo comando) sin vaciar el lote: para
	## un lote fijo que se arma una vez y se manda en cada frame.
	func draw(ci: CanvasItem) -> void:
		if not points.is_empty():
			RenderingServer.canvas_item_add_triangle_array(ci.get_canvas_item(), PackedInt32Array(), points, colors)

	## Dibuja lo acumulado en `ci` (un solo comando) y vacía el lote.
	func flush(ci: CanvasItem) -> void:
		if points.is_empty():
			return
		RenderingServer.canvas_item_add_triangle_array(ci.get_canvas_item(), PackedInt32Array(), points, colors)
		points = PackedVector2Array()
		colors = PackedColorArray()


# --- Formas precalculadas (coordenadas locales) -----------------------------------

## Círculo unitario como lista de triángulos (abanico desde el centro).
static func circle_tris(segs: int) -> PackedVector2Array:
	var key := Vector3(-1.0, segs, 0.0)
	if _shapes.has(key):
		return _shapes[key]
	var tris := PackedVector2Array()
	for i in segs:
		tris.append_array([Vector2.ZERO, Vector2.from_angle(TAU * i / segs), Vector2.from_angle(TAU * (i + 1) / segs)])
	return _remember(key, tris)


## Rectángulo redondeado de `size`, centrado en (0, 0), como triángulos.
static func round_rect_tris(size: Vector2, radius: float) -> PackedVector2Array:
	var key := Vector3(size.x, size.y, radius)
	if _shapes.has(key):
		return _shapes[key]
	var pts := round_rect_outline(size, radius)
	var tris := PackedVector2Array()
	for i in pts.size():
		tris.append_array([Vector2.ZERO, pts[i], pts[(i + 1) % pts.size()]])
	return _remember(key, tris)


## Borde de un rectángulo redondeado centrado en (0, 0), en sentido horario
## desde la esquina de arriba a la izquierda. Siempre con la misma cantidad de
## puntos (sirve para armar anillos entre dos tamaños).
static func round_rect_outline(size: Vector2, radius: float, corner_steps: int = 8) -> PackedVector2Array:
	var r := clampf(radius, 0.0, minf(size.x, size.y) / 2.0)
	var h := size / 2.0
	var centers := [Vector2(-h.x + r, -h.y + r), Vector2(h.x - r, -h.y + r), Vector2(h.x - r, h.y - r), Vector2(-h.x + r, h.y - r)]
	var pts := PackedVector2Array()
	for k in 4:
		var start := PI + k * PI / 2.0
		for i in corner_steps + 1:
			pts.append(centers[k] + Vector2.from_angle(start + PI / 2.0 * i / corner_steps) * r)
	return pts


## Estrella unitaria (5 puntas, radio 1) como triángulos desde el centro.
static func star_tris(inner: float) -> PackedVector2Array:
	var key := Vector3(-3.0, inner, 0.0)
	if _shapes.has(key):
		return _shapes[key]
	var pts := UiTheme.star_points(Vector2.ZERO, 1.0, inner)
	var tris := PackedVector2Array()
	for i in 10:
		tris.append_array([Vector2.ZERO, pts[i], pts[(i + 1) % 10]])
	return _remember(key, tris)


## Rayos de un halo (radio 1), como triángulos desde el centro.
static func rays_tris(rays: int) -> PackedVector2Array:
	var key := Vector3(-4.0, rays, 0.0)
	if _shapes.has(key):
		return _shapes[key]
	var tris := PackedVector2Array()
	for i in rays:
		var a := TAU * i / rays
		tris.append_array([Vector2.ZERO, Vector2.from_angle(a - 0.12), Vector2.from_angle(a + 0.12)])
	return _remember(key, tris)


## Anillo entre dos contornos con la misma cantidad de puntos, como
## triángulos: de a 6 puntos, [adentro, afuera, afuera, adentro, afuera, adentro].
static func ring_tris(inner: PackedVector2Array, outer: PackedVector2Array) -> PackedVector2Array:
	var n := inner.size()
	var pts := PackedVector2Array()
	pts.resize(n * 6)
	for i in n:
		var j := (i + 1) % n
		var k := i * 6
		pts[k] = inner[i]
		pts[k + 1] = outer[i]
		pts[k + 2] = outer[j]
		pts[k + 3] = inner[i]
		pts[k + 4] = outer[j]
		pts[k + 5] = inner[j]
	return pts


## `pattern` repetido `times` veces (colores por vértice de formas que se
## repiten: anillos difusos, halos). Se guarda: armarlo en cada frame costaría.
static func pattern_colors(pattern: PackedColorArray, times: int) -> PackedColorArray:
	var key := [pattern, times]
	var hit: PackedColorArray = _patterns.get(key, PackedColorArray())
	if not hit.is_empty():
		return hit
	var out := PackedColorArray()
	for i in times:
		out.append_array(pattern)
	if _patterns.size() > 256:
		_patterns.clear()
	_patterns[key] = out
	return out


static func _remember(key: Vector3, tris: PackedVector2Array) -> PackedVector2Array:
	if _shapes.size() > 512:  # Tope de memoria (ej. muchos textos distintos en el reloj).
		_shapes.clear()
	_shapes[key] = tris
	return tris


# --- Escenario de juguetes desenfocado --------------------------------------------

## Cielo, nubes, piso de baldosas y pilas de bloques y estrellas a los
## costados, desenfocado (como la foto de fondo de la maqueta). Se arma una
## sola vez por proceso: una imagen chica que se estira a toda la pantalla.
static func stage_texture() -> Texture2D:
	if _stage != null and _stage_gen == Props3D.generation:
		return _stage
	_stage_gen = Props3D.generation  # Si se hornean las piezas 3D, se rearma con ellas.
	var s := 1.0 / STAGE_DOWNSCALE
	var w := int(SCREEN.x * s)
	var h := int(SCREEN.y * s)
	var img := Image.create_empty(w, h, false, Image.FORMAT_RGBA8)
	# Cielo en degradé.
	for y in h:
		img.fill_rect(Rect2i(0, y, w, 1), UiTheme.SKY_TOP.lerp(UiTheme.SKY_BOTTOM, clampf(y / (h * 0.72), 0.0, 1.0)))
	# Nubes.
	for c: Vector3 in [Vector3(250, 120, 60), Vector3(720, 70, 44), Vector3(1230, 96, 52), Vector3(1660, 150, 58), Vector3(1880, 60, 40)]:
		_img_cloud(img, Vector2(c.x, c.y), c.z)
	# Piso de baldosas grandes (más altas hacia adelante, como en perspectiva).
	var y0 := 770.0
	var row := 0
	while y0 < SCREEN.y:
		var rh := 34.0 + row * 16.0
		var tw := 118.0 + row * 26.0
		var x0 := -tw * 0.5 * (row % 2)
		var col := 0
		while x0 < SCREEN.x:
			_img_rect(img, Rect2(x0, y0, tw, rh), UiTheme.STAGE_FLOOR if (col + row) % 2 == 0 else UiTheme.STAGE_FLOOR_ALT)
			x0 += tw
			col += 1
		y0 += rh
		row += 1
	# Pilas de bloques a los costados (lo del centro lo tapa el tablero).
	var b := UiTheme.BRICKS
	for block: Array in [
		# Izquierda: torre con bandera, torre baja y bloques sueltos.
		[Rect2(-30, 770, 200, 130), b[5]], [Rect2(-20, 650, 180, 120), b[0]], [Rect2(-10, 540, 160, 110), b[2]],
		[Rect2(0, 440, 140, 100), b[3]], [Rect2(170, 800, 150, 110), b[6]], [Rect2(190, 700, 120, 100), b[4]],
		[Rect2(280, 870, 120, 90), b[1]],
		# Derecha.
		[Rect2(1740, 760, 210, 140), b[1]], [Rect2(1760, 630, 180, 130), b[6]], [Rect2(1780, 520, 150, 110), b[4]],
		[Rect2(1590, 810, 160, 110), b[3]], [Rect2(1610, 710, 130, 100), b[7]], [Rect2(1500, 880, 120, 90), b[5]],
		# Adelante, grandes (más cerca: casi siempre asoman por abajo).
		[Rect2(-90, 950, 360, 200), b[2]], [Rect2(1660, 960, 330, 190), b[7]], [Rect2(420, 1010, 260, 130), b[3]],
		[Rect2(1250, 1015, 260, 130), b[0]], [Rect2(830, 1040, 260, 110), b[5]],
	]:
		_img_block(img, block[0], block[1])
	# Bandera arriba de la torre izquierda.
	_img_rect(img, Rect2(66, 250, 10, 190), UiTheme.INK_SOFT)
	_img_poly(img, PackedVector2Array([Vector2(76, 252), Vector2(186, 292), Vector2(76, 336)]), b[0])
	_img_poly(img, UiTheme.star_points(Vector2(112, 293), 20.0), UiTheme.GOLD)
	_img_disc(img, Vector2(71, 246), 12.0, UiTheme.GOLD)
	# Estrellas de juguete.
	for st: Vector3 in [Vector3(1830, 400, 64), Vector3(120, 610, 42), Vector3(1560, 640, 40), Vector3(330, 640, 34), Vector3(1880, 900, 36)]:
		if _img_piece(img, "star", Rect2(st.x - st.z, st.y - st.z, st.z * 2.0, st.z * 2.0)):
			continue
		_img_poly(img, UiTheme.star_points(Vector2(st.x, st.y), st.z + 8.0, 0.5), UiTheme.GOLD.darkened(0.25))
		_img_poly(img, UiTheme.star_points(Vector2(st.x, st.y - 4.0), st.z, 0.5), UiTheme.GOLD)
	# Desenfoque barato: achicar a la mitad y volver a agrandar (una vez).
	img.resize(w / 2, h / 2, Image.INTERPOLATE_BILINEAR)
	img.resize(w, h, Image.INTERPOLATE_BILINEAR)
	_stage = ImageTexture.create_from_image(img)
	return _stage


static func _img_rect(img: Image, r: Rect2, col: Color) -> void:
	var s := 1.0 / STAGE_DOWNSCALE
	var p := Vector2i((r.position * s).round())
	var e := Vector2i((r.end * s).round())
	var clip := Rect2i(p, e - p).intersection(Rect2i(Vector2i.ZERO, img.get_size()))
	if clip.has_area():
		img.fill_rect(clip, col)


static func _img_disc(img: Image, c: Vector2, r: float, col: Color) -> void:
	var s := 1.0 / STAGE_DOWNSCALE
	var cc := c * s
	var rr := r * s
	for dy in range(-ceili(rr), ceili(rr) + 1):
		var half := sqrt(maxf(rr * rr - dy * dy, 0.0))
		_img_rect(img, Rect2((cc.x - half) / s, (cc.y + dy) / s, half * 2.0 / s, 1.0 / s), col)


## Polígono cualquiera (estrellas, bandera): píxel por píxel en su caja.
static func _img_poly(img: Image, pts: PackedVector2Array, col: Color) -> void:
	var s := 1.0 / STAGE_DOWNSCALE
	var scaled := Transform2D(0.0, Vector2(s, s), 0.0, Vector2.ZERO) * pts
	var box := Rect2(scaled[0], Vector2.ZERO)
	for p in scaled:
		box = box.expand(p)
	for y in range(floori(box.position.y), ceili(box.end.y) + 1):
		for x in range(floori(box.position.x), ceili(box.end.x) + 1):
			if x >= 0 and y >= 0 and x < img.get_width() and y < img.get_height() \
					and Geometry2D.is_point_in_polygon(Vector2(x + 0.5, y + 0.5), scaled):
				img.set_pixel(x, y, col)


static func _img_cloud(img: Image, c: Vector2, r: float) -> void:
	_img_disc(img, c + Vector2(-r * 0.9, r * 0.25), r * 0.7, UiTheme.STAGE_CLOUD)
	_img_disc(img, c + Vector2(r * 0.9, r * 0.3), r * 0.65, UiTheme.STAGE_CLOUD)
	_img_disc(img, c, r, UiTheme.STAGE_CLOUD)
	_img_rect(img, Rect2(c.x - r * 1.5, c.y + r * 0.2, r * 3.0, r * 0.6), UiTheme.STAGE_CLOUD)


## Bloque de juguete visto de frente y un poco de arriba: tapa clara con
## botones, frente del color y costado oscuro.
static func _img_block(img: Image, r: Rect2, col: Color) -> void:
	var idx := UiTheme.BRICKS.find(col)
	if idx >= 0 and _img_piece(img, "block_%d" % idx, r):
		return
	var top := r.size.y * 0.3
	var side := r.size.x * 0.16
	_img_rect(img, Rect2(r.position.x, r.position.y + top, r.size.x, r.size.y - top), col)
	_img_rect(img, Rect2(r.end.x - side, r.position.y + top, side, r.size.y - top), col.darkened(0.25))
	_img_rect(img, Rect2(r.position.x, r.end.y - 10.0, r.size.x, 10.0), col.darkened(0.35))
	_img_rect(img, Rect2(r.position.x, r.position.y, r.size.x, top), col.lightened(0.3))
	for k in 2:
		var stud := Vector2(r.position.x + r.size.x * (0.3 + 0.36 * k), r.position.y + top * 0.5)
		_img_disc(img, stud, minf(r.size.x * 0.11, top * 0.45), col.lightened(0.5))


## Pieza 3D horneada (Props3D.image) pegada en la imagen del escenario con
## su cuerpo en `r` (px de pantalla). false si no hay atlas.
static func _img_piece(img: Image, name: String, r: Rect2) -> bool:
	var src := Props3D.image(name)
	if src == null:
		return false
	var reg: Array = Props3D.regions()[name]
	var dest := Props3D.dest_rect(Rect2(Vector2.ZERO, (reg[0] as Rect2).size), reg[1], r)
	var s := 1.0 / STAGE_DOWNSCALE
	var p := Vector2i((dest.position * s).round())
	var sz := Vector2i((dest.size * s).round())
	if sz.x < 2 or sz.y < 2:
		return false
	var piece := src.duplicate() as Image
	piece.resize(sz.x, sz.y, Image.INTERPOLATE_BILINEAR)
	img.blend_rect(piece, Rect2i(Vector2i.ZERO, sz), p)
	return true


# --- Tablero con volumen ------------------------------------------------------------

## Rectángulo que el tablero de `rect` tapa por completo (opaco): el
## escenario no hace falta dibujarlo ahí (menos píxeles pintados dos veces).
static func board_cover(rect: Rect2) -> Rect2:
	return rect.grow(UiTheme.BOARD_FRAME - 6.0)


## Tablero: sombra proyectada (flota sobre el escenario), marco de bloques con
## bisel (luz arriba, sombra abajo), canto de abajo, bloques con estrella en
## las esquinas y piso de baldosas con relieve. `rect` es el área de juego
## (adentro del marco) y `cell` el lado de cada baldosa. Va en una capa
## cacheada: se dibuja una vez, en un solo lote (1 draw call).
## Rendimiento (la GPU de la TV paga cada píxel pintado): figuras de pocos
## triángulos (esquinas ochavadas, no redondeadas) y casi sin capas que se
## tapen entre sí: debajo del piso solo va la junta.
static func paint_board(ci: CanvasItem, rect: Rect2, cell: float) -> void:
	var f := UiTheme.BOARD_FRAME
	var depth := UiTheme.BOARD_DEPTH
	var outer := rect.grow(f)
	var body := outer.grow_side(SIDE_BOTTOM, depth)
	var b := TriBatch.new()
	add_soft_shadow(b, body, 24.0)
	# Contorno de tinta: solo el anillo de afuera y las bandas debajo del
	# marco (el piso no lo necesita).
	var edge := body.grow(5.0)
	b.feather_round_rect(edge, 24.0, UiTheme.INK)
	b.ring_round_rect(edge, body, 19.0, UiTheme.INK)
	b.rect(Rect2(outer.position, Vector2(outer.size.x, f)), UiTheme.INK)
	b.rect(Rect2(outer.position.x, rect.end.y, outer.size.x, f + depth), UiTheme.INK)
	b.rect(Rect2(outer.position.x, rect.position.y, f, rect.size.y), UiTheme.INK)
	b.rect(Rect2(rect.end.x, rect.position.y, f, rect.size.y), UiTheme.INK)
	# Marco: bloques arriba, abajo y a los costados (las esquinas las tapan
	# los bloques con estrella). Con piezas 3D (Props3D) el lote se corta
	# acá: los bloques van como sprites del atlas (un draw call entre todos,
	# misma textura) y el piso sigue en otro lote.
	var use_3d := Props3D.is_ready()
	var bricks: Array = []  # [rect, nombre de la pieza]
	var i := 0
	for side in 4:
		var horizontal := side < 2
		var length := outer.size.x if horizontal else rect.size.y
		var n := maxi(1, roundi(length / UiTheme.BOARD_BRICK))
		var step := length / n
		for k in n:
			var col: Color = UiTheme.BRICKS[(i * 3 + side) % UiTheme.BRICKS.size()]
			i += 1
			var r: Rect2
			match side:
				0: r = Rect2(outer.position.x + k * step, outer.position.y, step, f)
				1: r = Rect2(outer.position.x + k * step, rect.end.y, step, f)
				2: r = Rect2(outer.position.x, rect.position.y + k * step, f, step)
				_: r = Rect2(rect.end.x, rect.position.y + k * step, f, step)
			if side == 1:  # Canto de abajo: la cara de adelante del bloque.
				b.chamfer_rect(Rect2(r.position.x + 1.0, r.end.y - 4.0, r.size.x - 2.0, depth + 2.0), 3.0, col.darkened(0.45))
			if use_3d:
				bricks.append([r, Props3D.brick_name((i - 1) * 3 + side, side >= 2)])
			else:
				_add_brick(b, r, col)
	if use_3d:
		b.flush(ci)
		draw_pieces(ci, bricks)
	# Piso: baldosas con relieve (luz arriba, labio oscuro abajo) y la junta
	# solo en las rendijas: cada píxel del piso se pinta una sola vez.
	var g := UiTheme.TILE_GAP
	var gx := rect.position.x
	while gx <= rect.end.x + 0.5:
		b.rect(Rect2(gx - g, rect.position.y, g * 2.0, rect.size.y).intersection(rect), UiTheme.TILE_GROUT)
		gx += cell
	var gy := rect.position.y
	while gy <= rect.end.y + 0.5:
		b.rect(Rect2(rect.position.x, gy - g, rect.size.x, g * 2.0).intersection(rect), UiTheme.TILE_GROUT)
		gy += cell
	b.rect(Rect2(rect.end.x - g, rect.position.y, g, rect.size.y), UiTheme.TILE_GROUT)
	b.rect(Rect2(rect.position.x, rect.end.y - g, rect.size.x, g), UiTheme.TILE_GROUT)
	var row := 0
	var y := rect.position.y
	while y < rect.end.y - 1.0:
		var x := rect.position.x
		var column := 0
		while x < rect.end.x - 1.0:
			var tile := Rect2(x, y, minf(cell, rect.end.x - x), minf(cell, rect.end.y - y))
			_add_tile(b, tile, UiTheme.FLOOR if (row + column) % 2 == 0 else UiTheme.FIELD_TILE)
			x += cell
			column += 1
		y += cell
		row += 1
	# El marco le hace sombra al piso (arriba y a la izquierda) y un filete de tinta.
	var shade := Color(UiTheme.INK, 0.2)
	var clear := Color(UiTheme.INK, 0.0)
	b.quad_colors(rect.position, Vector2(rect.end.x, rect.position.y), Vector2(rect.end.x, rect.position.y + 22.0),
		rect.position + Vector2(0, 22.0), shade, shade, clear, clear)
	b.quad_colors(rect.position, rect.position + Vector2(16.0, 0), Vector2(rect.position.x + 16.0, rect.end.y),
		Vector2(rect.position.x, rect.end.y), shade, clear, clear, shade)
	var ink := UiTheme.INK
	b.rect(Rect2(rect.position - Vector2(3, 3), Vector2(rect.size.x + 6, 3)), ink)
	b.rect(Rect2(rect.position.x - 3, rect.end.y, rect.size.x + 6, 3), ink)
	b.rect(Rect2(rect.position.x - 3, rect.position.y, 3, rect.size.y), ink)
	b.rect(Rect2(rect.end.x, rect.position.y, 3, rect.size.y), ink)
	# Esquinas: bloque más grande con una estrella arriba.
	var cs := UiTheme.BOARD_CORNER
	var corners := [outer.position, Vector2(outer.end.x - f, outer.position.y),
		Vector2(outer.position.x, rect.end.y), Vector2(rect.end.x, rect.end.y)]
	for k in 4:
		var center: Vector2 = corners[k] + Vector2(f, f) / 2.0
		var r := Rect2(center - Vector2(cs, cs) / 2.0, Vector2(cs, cs))
		var col: Color = UiTheme.BRICKS[0] if k != 3 else UiTheme.BRICKS[5]
		var corner_edge := r.grow(4.0).grow_side(SIDE_BOTTOM, depth if k >= 2 else 6.0)
		b.feather_round_rect(corner_edge, 14.0, UiTheme.INK)
		b.round_rect(corner_edge, 14.0, UiTheme.INK)
		if k >= 2:
			b.chamfer_rect(Rect2(r.position.x, r.end.y - 8.0, cs, depth + 8.0), 8.0, col.darkened(0.45))
		if use_3d:
			continue
		_add_brick(b, r, col, 10.0)
		b.star(center + Vector2(0, -3), cs * 0.36, UiTheme.GOLD, 0.0, 4.0)
	b.flush(ci)
	if use_3d:
		for k in 4:
			var center: Vector2 = corners[k] + Vector2(f, f) / 2.0
			Props3D.draw(ci, corner_piece(k), Rect2(center - Vector2(cs, cs) / 2.0, Vector2(cs, cs)))


## Piezas 3D anotadas como [rect, nombre] (bloques del marco, esquinas):
## todas del mismo atlas, así el motor las junta en un draw call.
static func draw_pieces(ci: CanvasItem, pieces: Array) -> void:
	for pc: Array in pieces:
		Props3D.draw(ci, pc[1], pc[0])


## Nombre de la pieza 3D del bloque con estrella de la esquina `k` (0–3).
static func corner_piece(k: int) -> String:
	return "corner_%d" % (0 if k != 3 else 5)


## Bloque del marco con bisel: borde oscuro, labio de abajo, cara del color
## con la mitad de arriba más clara (luz), línea de brillo y un reflejo.
static func _add_brick(b: TriBatch, r: Rect2, col: Color, chamfer: float = 6.0) -> void:
	b.chamfer_rect(r.grow(-1.0), chamfer, col.darkened(0.38))
	var face := Rect2(r.position + Vector2(3.0, 2.5), r.size - Vector2(6.0, 10.0))
	b.chamfer_rect(Rect2(face.position.x, face.get_center().y, face.size.x, face.size.y / 2.0), chamfer - 1.0, col)
	b.chamfer_rect(Rect2(face.position, Vector2(face.size.x, face.size.y / 2.0 + 1.0)), chamfer - 1.0, col.lightened(0.14))
	b.chamfer_rect(Rect2(face.position + Vector2(5.0, 3.0), Vector2(face.size.x - 10.0, minf(6.0, face.size.y * 0.22))), 3.0, col.lightened(0.5))
	b.chamfer_rect(Rect2(face.position + Vector2(6.0, face.size.y * 0.6 - 2.0), Vector2(6.0, 4.0)), 1.5, Color(1, 1, 1, 0.6))


## Baldosa del piso: cara, labio oscuro abajo y línea de luz arriba, sin
## superponerse (cubren justo la baldosa menos la junta).
static func _add_tile(b: TriBatch, r: Rect2, col: Color) -> void:
	var inner := r.grow(-UiTheme.TILE_GAP)
	if inner.size.x <= 12.0 or inner.size.y <= 12.0:
		b.rect(inner, col)
		return
	var lip := UiTheme.TILE_LIP
	b.rect(Rect2(inner.position, Vector2(inner.size.x, 2.0)), col.lerp(Color.WHITE, UiTheme.TILE_SHINE.a))
	b.rect(Rect2(inner.position + Vector2(0, 2.0), inner.size - Vector2(0, lip + 2.0)), col)
	b.rect(Rect2(inner.position.x, inner.end.y - lip, inner.size.x, lip), col.darkened(UiTheme.TILE_SHADE))


## Sombra suave debajo de `rect` (tablero, mesa): lo hace "flotar". Solo se
## pinta lo que asoma (abajo y el borde difuso), no el centro que queda tapado.
static func add_soft_shadow(b: TriBatch, rect: Rect2, radius: float, drop: float = 30.0, blur: float = 30.0) -> void:
	var s := Rect2(rect.position + Vector2(0, drop), rect.size)
	var col := UiTheme.BOARD_SHADOW
	b._feather(round_rect_outline(s.size, radius), round_rect_outline(s.size + Vector2(blur, blur) * 2.0, radius + blur), s.get_center(), col)
	b.round_rect(Rect2(s.position.x, s.end.y - drop - radius * 2.0, s.size.x, drop + radius * 2.0), radius, col)
	b.rect(Rect2(s.position.x, s.position.y + radius, radius, s.size.y - radius * 2.0 - drop), col)
	b.rect(Rect2(s.end.x - radius, s.position.y + radius, radius, s.size.y - radius * 2.0 - drop), col)


## Sombra proyectada de algo que no es un tablero (ej. la mesa de Ping
## Pong), en un draw call.
static func draw_drop_shadow(ci: CanvasItem, rect: Rect2) -> void:
	var b := TriBatch.new()
	add_soft_shadow(b, rect, 24.0)
	b.flush(ci)


## Escenario (stage_texture) sin la parte que tapa `cover`: cuatro franjas
## alrededor (con la misma textura, el motor las junta en un draw call).
static func paint_stage(ci: CanvasItem, cover: Rect2) -> void:
	var tex := stage_texture()
	var k := 1.0 / STAGE_DOWNSCALE
	var c := cover.intersection(Rect2(Vector2.ZERO, SCREEN))
	if not c.has_area():
		ci.draw_texture_rect(tex, Rect2(Vector2.ZERO, SCREEN), false)
		return
	for r: Rect2 in [Rect2(0, 0, SCREEN.x, c.position.y), Rect2(0, c.end.y, SCREEN.x, SCREEN.y - c.end.y),
			Rect2(0, c.position.y, c.position.x, c.size.y), Rect2(c.end.x, c.position.y, SCREEN.x - c.end.x, c.size.y)]:
		if r.has_area():
			ci.draw_texture_rect_region(tex, r, Rect2(r.position * k, r.size * k))


## Baldosa pintada con relieve y patrón, en coordenadas locales (0..cell),
## como triángulos con color por vértice: se ubica con TriBatch.template.
## `pattern`: 0 liso, 1 rayas, 2 puntos, 3 cuadritos (ver Pintar el piso).
static func tile_template(cell: float, fill: Color, mark: Color, pattern: int, width: float, dot_r: float) -> Array:
	var b := TriBatch.new()
	var g := UiTheme.TILE_GAP
	var k := UiTheme.TILE_CHAMFER
	var inner := Rect2(g, g, cell - 2.0 * g, cell - 2.0 * g)
	var face := Rect2(inner.position, inner.size - Vector2(0, UiTheme.TILE_LIP))
	b.chamfer_rect(Rect2(inner.position.x, face.end.y - k, inner.size.x, UiTheme.TILE_LIP + k), k, fill.darkened(0.22))
	b.chamfer_rect(face, k, fill)
	var area := face.grow(-(width / 2.0 + 2.0))
	match pattern:
		1:  # Rayas diagonales.
			var span := area.size.x + area.size.y
			for stripe in range(1, 8):
				var seg := _diagonal_in(area, area.position.x + area.position.y + span * stripe / 8.0)
				if seg.size() == 2:
					b.line(seg[0], seg[1], mark, width)
		2:  # Puntos (el cinco del dado), con un brillito.
			for p in [Vector2(0.27, 0.27), Vector2(0.73, 0.27), Vector2(0.5, 0.5), Vector2(0.27, 0.73), Vector2(0.73, 0.73)]:
				var c: Vector2 = face.position + face.size * p
				b.circle(c, dot_r, mark, 14)
				b.circle(c + Vector2(-dot_r * 0.3, -dot_r * 0.35), dot_r * 0.35, Color(1, 1, 1, 0.35), 8)
		3:  # Cuadritos.
			for t: float in [1.0 / 3.0, 2.0 / 3.0]:
				var x := face.position.x + face.size.x * t
				var y := face.position.y + face.size.y * t
				b.line(Vector2(x, area.position.y), Vector2(x, area.end.y), mark, width)
				b.line(Vector2(area.position.x, y), Vector2(area.end.x, y), mark, width)
	b.rect(Rect2(face.position + Vector2(6.0, 2.5), Vector2(face.size.x - 12.0, 3.5)), Color(1, 1, 1, 0.45))
	return [b.points, b.colors]


## Tramo de la recta x + y = c dentro de `r` (vacío si no la cruza).
static func _diagonal_in(r: Rect2, c: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in [Vector2(c - r.position.y, r.position.y), Vector2(r.position.x, c - r.position.x),
			Vector2(c - r.end.y, r.end.y), Vector2(r.end.x, c - r.end.x)]:
		if p.x >= r.position.x - 0.01 and p.x <= r.end.x + 0.01 and p.y >= r.position.y - 0.01 and p.y <= r.end.y + 0.01:
			var dup := false
			for q in out:
				dup = dup or q.distance_to(p) < 0.5
			if not dup:
				out.append(p)
	return out.slice(0, 2)


# --- Marcador -----------------------------------------------------------------------

## Dónde va cada cosa del marcador: [rect del reloj, rects de las píldoras].
## Las píldoras se reparten a los dos lados del reloj (1P 2P [reloj] 3P 4P).
static func hud_layout(n: int, center_w: float) -> Array:
	var pill := UiTheme.HUD_PILL
	var gap := UiTheme.HUD_GAP
	var x := (SCREEN.x - (n * pill.x + center_w + n * gap)) / 2.0
	var half := ceili(n / 2.0)
	var pill_y := UiTheme.HUD_TOP + (UiTheme.HUD_CLOCK_H - pill.y) / 2.0
	var clock := Rect2()
	var pills: Array[Rect2] = []
	for i in n + 1:
		if i == half:
			clock = Rect2(x, UiTheme.HUD_TOP, center_w, UiTheme.HUD_CLOCK_H)
			x += center_w + gap
		if i < n:
			pills.append(Rect2(Vector2(x, pill_y), pill))
			x += pill.x + gap
	return [clock, pills]


## Ancho del reloj: se adapta al texto ("0:28", "Meta: 40").
static func hud_center_width(center: String, icon: String) -> float:
	var tw := UiTheme.FONT_BOLD.get_string_size(center, HORIZONTAL_ALIGNMENT_LEFT, -1, UiTheme.HUD_CLOCK_SIZE).x
	return maxf(236.0, tw + (104.0 if icon != "" else 64.0))


## Marcador sin los números: píldoras, mascotas, etiquetas 1P–4P y reloj
## (casi nunca cambia). entries: [{tag, color, portrait (Texture2D o null)}]
## en el orden de los jugadores. Devuelve el rect de cada píldora (para que
## un juego agregue algo debajo, ej. la muestra de su patrón).
## Todas las formas van en un lote; después las mascotas y las etiquetas.
## Los números y el texto del reloj: paint_hud_text (capa aparte).
static func paint_hud(ci: CanvasItem, entries: Array, center: String, icon: String) -> Array[Rect2]:
	var layout := hud_layout(entries.size(), hud_center_width(center, icon))
	var clock: Rect2 = layout[0]
	var pills: Array[Rect2] = layout[1]
	var b := TriBatch.new()
	for i in entries.size():
		_add_pill(b, pills[i], entries[i].color)
	_add_clock(b, clock)
	var icon_at := Vector2(clock.position.x + 50.0, clock.get_center().y)
	var star_3d := icon == "star" and Props3D.is_ready()
	if icon != "" and not star_3d:
		_add_icon(b, icon, icon_at)
	b.flush(ci)
	if star_3d:
		Props3D.draw_centered(ci, "star", icon_at, Vector2(44, 44))
	var portrait := UiTheme.HUD_PORTRAIT
	for i in entries.size():
		var tex: Texture2D = entries[i].get("portrait")
		if tex != null:
			var r := pills[i]
			ci.draw_texture_rect(tex, Rect2(r.position.x + 104.0 - portrait.x / 2.0, r.end.y - portrait.y + 2.0, portrait.x, portrait.y), false)
	for i in entries.size():
		var r := pills[i]
		var col: Color = entries[i].color
		var fg := UiTheme.text_on(col)
		UiTheme.draw_text(ci, entries[i].tag, Vector2(r.position.x + 37.0, r.get_center().y - 1.0), UiTheme.HUD_TAG_SIZE,
			fg, 6, UiTheme.INK if fg == UiTheme.PAPER else UiTheme.PAPER)
	return pills


## Números del marcador (en el orden de los jugadores) y texto del reloj,
## en los mismos lugares que paint_hud.
static func paint_hud_text(ci: CanvasItem, scores: Array[String], center: String, icon: String) -> void:
	var layout := hud_layout(scores.size(), hud_center_width(center, icon))
	var clock: Rect2 = layout[0]
	var pills: Array[Rect2] = layout[1]
	for i in scores.size():
		var r := pills[i]
		UiTheme.draw_text(ci, scores[i], Vector2((r.position.x + 148.0 + r.end.x - 8.0) / 2.0, r.get_center().y), UiTheme.HUD_SCORE_SIZE, UiTheme.PAPER)
	var text_x := clock.get_center().x
	if icon != "":
		text_x = (clock.position.x + 80.0 + clock.end.x - 22.0) / 2.0
	UiTheme.draw_text(ci, center, Vector2(text_x, clock.get_center().y), UiTheme.HUD_CLOCK_SIZE, UiTheme.PAPER, 6, UiTheme.INK)


## Píldora de un jugador: contorno, aro claro, labio oscuro abajo, cara del
## color con brillo y, a la derecha, el pozo oscuro del puntaje.
static func _add_pill(b: TriBatch, r: Rect2, col: Color) -> void:
	b.feather_capsule(r.grow(4.0).grow_side(SIDE_BOTTOM, 3.0), UiTheme.INK)
	b.capsule(r.grow(4.0).grow_side(SIDE_BOTTOM, 3.0), UiTheme.INK)
	b.capsule(r, col.lightened(0.4))
	var body := r.grow(-3.0)
	b.capsule(body, col.darkened(0.3))
	b.capsule(Rect2(body.position, body.size - Vector2(0, 6.0)), col)
	b.capsule(Rect2(body.position + Vector2(16.0, 4.0), Vector2(body.size.x * 0.46, body.size.y * 0.26)), Color(1, 1, 1, 0.3))
	var well := Rect2(r.position.x + 148.0, r.position.y + 9.0, r.size.x - 156.0, r.size.y - 18.0)
	b.capsule(well.grow(3.0), col.darkened(0.45))
	b.capsule(well, UiTheme.CHIP_DARK)
	b.capsule(Rect2(well.position + Vector2(10.0, 3.0), Vector2(well.size.x - 20.0, 5.0)), Color(1, 1, 1, 0.12))


## Reloj: píldora oscura con borde arcoíris (anillo con color por vértice).
static func _add_clock(b: TriBatch, r: Rect2) -> void:
	b.feather_capsule(r.grow(11.0), UiTheme.INK)
	b.capsule(r.grow(11.0), UiTheme.INK)
	var outer := round_rect_outline(r.grow(8.0).size, (r.size.y + 16.0) / 2.0)
	var inner := round_rect_outline(r.grow(2.0).size, (r.size.y + 4.0) / 2.0)
	var c := r.get_center()
	var n := outer.size()
	for i in n:
		var j := (i + 1) % n
		var ci := Color.from_hsv(float(i) / n, 0.72, 1.0)
		var cj := Color.from_hsv(float(j) / n, 0.72, 1.0)
		b.quad_colors(c + outer[i], c + outer[j], c + inner[j], c + inner[i], ci, cj, cj, ci)
	b.capsule(r.grow(2.0), UiTheme.INK)
	b.capsule(r, UiTheme.CHIP_DARK)
	b.capsule(Rect2(r.position + Vector2(24.0, 5.0), Vector2(r.size.x - 48.0, r.size.y * 0.3)), Color(1, 1, 1, 0.08))


## Íconos del reloj: "clock" (cronómetro), "flag" (meta) y "star" (puntos).
static func _add_icon(b: TriBatch, icon: String, c: Vector2) -> void:
	match icon:
		"clock":
			b.round_rect(Rect2(c + Vector2(-6, -30), Vector2(12, 9)), 3.0, UiTheme.PAPER)
			b.line(c + Vector2(13, -17), c + Vector2(19, -23), UiTheme.PAPER, 6.0)
			b.circle(c + Vector2(0, 2), 22.0, UiTheme.PAPER, 28)
			b.circle(c + Vector2(0, 2), 16.5, UiTheme.CHIP_DARK, 28)
			b.line(c + Vector2(0, 2), c + Vector2(7, -8), UiTheme.ACCENT, 5.0)
			b.circle(c + Vector2(0, 2), 3.5, UiTheme.ACCENT, 10)
		"flag":
			b.rect(Rect2(c + Vector2(-16, -26), Vector2(6, 52)), UiTheme.PAPER)
			for k in 3:
				for j in 2:
					var sq := Rect2(c + Vector2(-10 + k * 10.0, -24 + j * 10.0), Vector2(10, 10))
					b.rect(sq, UiTheme.PAPER if (k + j) % 2 == 0 else UiTheme.INK_SOFT)
		_:
			b.star(c, 22.0, UiTheme.GOLD, 0.0, 4.0)


# --- Mascota del marcador -----------------------------------------------------------

## Textura con la mascota de un jugador para el marcador. Se dibuja UNA vez en
## un SubViewport chico (al doble de tamaño, así se ve nítida): el marcador
## pinta una textura (1 draw call) en vez de ~15 figuras por mascota.
## El viewport queda como hijo de `parent` (se libera con él).
static func make_portrait(parent: Node, col: Color, style: int) -> Texture2D:
	var k := float(PORTRAIT_SUPERSAMPLE)
	var vp := SubViewport.new()
	vp.size = Vector2i(UiTheme.HUD_PORTRAIT * k)
	vp.transparent_bg = true
	vp.disable_3d = true
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	var drawer := Node2D.new()
	var feet := Vector2(UiTheme.HUD_PORTRAIT.x / 2.0, UiTheme.HUD_PORTRAIT.y - 6.0) * k
	drawer.draw.connect(func() -> void:
		PlayerAvatar.draw_mascot(drawer, feet, PORTRAIT_SCALE * k, col, style))
	vp.add_child(drawer)
	parent.add_child(vp)
	MascotAtlas.redraw_on_bake(drawer, vp)  # Mascota 3D horneada apenas esté (ADR 0012).
	MascotAtlas.pin(col, style, PORTRAIT_SCALE * k, "idle@0")  # Se dibuja una vez: que no se suelte.
	return vp.get_texture()


# --- Globito 1P–4P y nombre -----------------------------------------------------------

## Globito del color del jugador con su etiqueta ("1P") arriba de la cabeza
## de la mascota (con contorno y piquito) y el nombre debajo de los pies con
## contorno. Si arriba no entra (lo taparía el marcador), va al costado de la
## cabeza. `u`: escala de la mascota; `name_offset`: px debajo de los pies
## (negativo = sin nombre). Para varios jugadores, draw_player_tags (menos
## draw calls).
static func draw_player_tag(ci: CanvasItem, slot: int, col: Color, player_name: String, feet: Vector2, u: float,
		name_offset: float = 26.0, alpha: float = 1.0) -> void:
	draw_player_tags(ci, [[slot, col, player_name, feet, u, name_offset, alpha]])


## Globitos y nombres de varios jugadores: todos los globitos en un lote y
## todos los textos después (primero los contornos y después los rellenos:
## así el motor junta las letras en pocos draw calls).
## tags: [[slot, color, nombre, pies, u, name_offset, alpha], ...]
static func draw_player_tags(ci: CanvasItem, tags: Array) -> void:
	var b := TriBatch.new()
	var labels: Array = []  # [texto, centro, color, color del contorno]
	for t: Array in tags:
		_add_tag(b, labels, t[0], t[1], t[2], t[3], t[4], t[5], t[6])
	b.flush(ci)
	var font := UiTheme.FONT_BOLD
	var size := UiTheme.PLAYER_NAME_SIZE
	var half_h := (font.get_ascent(size) - font.get_descent(size)) / 2.0
	var at: Array[Vector2] = []
	for l: Array in labels:
		var center: Vector2 = l[1]
		at.append(Vector2(center.x - _label_width(l[0]) / 2.0, center.y + half_h))
	for i in labels.size():
		var outline: Color = labels[i][3]
		if outline.a > 0.0:  # La etiqueta del globito no lleva contorno (ya tiene fondo).
			ci.draw_string_outline(font, at[i], labels[i][0], HORIZONTAL_ALIGNMENT_LEFT, -1, size, UiTheme.TAG_OUTLINE, outline)
	for i in labels.size():
		ci.draw_string(font, at[i], labels[i][0], HORIZONTAL_ALIGNMENT_LEFT, -1, size, labels[i][2])


## Ancho de un texto del globito o del nombre (se guarda: se pide en cada frame).
static func _label_width(text: String) -> float:
	var w: float = _label_widths.get(text, -1.0)
	if w < 0.0:
		w = UiTheme.FONT_BOLD.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, UiTheme.PLAYER_NAME_SIZE).x
		if _label_widths.size() > 64:
			_label_widths.clear()
		_label_widths[text] = w
	return w


static func _add_tag(b: TriBatch, labels: Array, slot: int, col: Color, player_name: String, feet: Vector2, u: float,
		name_offset: float, alpha: float) -> void:
	var size := UiTheme.TAG_BUBBLE
	var tip := feet + Vector2(0, -118.0 * u)
	var out := Vector2.UP  # Hacia dónde queda el globito respecto del piquito.
	var center := tip + Vector2(0, -8.0 - size.y / 2.0)
	if center.y - size.y / 2.0 < UiTheme.HUD_TOP + UiTheme.HUD_CLOCK_H + 12.0:
		out = Vector2.RIGHT if feet.x < SCREEN.x - 240.0 else Vector2.LEFT
		tip = feet + Vector2(out.x * (40.0 * u + 4.0), -54.0 * u)
		center = tip + Vector2(out.x * (8.0 + size.x / 2.0), 0)
	# El globito (forma y colores) se arma una vez por color y dirección; en
	# cada frame solo se ubica (dos append_array).
	var key := [col, out, alpha]
	var tpl: Array = _bubbles.get(key, [])
	if tpl.is_empty():
		tpl = _bubble_template(col, out, center - tip, alpha)
		if _bubbles.size() > 64:
			_bubbles.clear()
		_bubbles[key] = tpl
	b.template(tpl[0], tpl[1], Transform2D(0.0, tip))
	labels.append([UiTheme.player_tag(slot), center + Vector2(0, -1.0), Color(UiTheme.text_on(col), alpha), Color.TRANSPARENT])
	if name_offset >= 0.0:
		labels.append([player_name, feet + Vector2(0, name_offset), Color(UiTheme.PAPER, alpha), Color(UiTheme.INK, alpha)])


## Globito con el piquito en (0, 0) que apunta en contra de `out`; `center`:
## centro del globito respecto del piquito. Devuelve [puntos, colores].
static func _bubble_template(col: Color, out: Vector2, center: Vector2, alpha: float) -> Array:
	var size := UiTheme.TAG_BUBBLE
	var r := Rect2(center - size / 2.0, size)
	var side := out.orthogonal()
	var ink := Color(UiTheme.INK, alpha)
	var body := Color(col, alpha)
	var b := TriBatch.new()
	b.feather_capsule(r.grow(3.5), ink)
	b.capsule(r.grow(3.5), ink)
	b.tri(-out * 5.0, out * 10.0 + side * 12.0, out * 10.0 - side * 12.0, ink)
	b.capsule(r, Color(col.darkened(0.25), alpha))
	b.capsule(Rect2(r.position, r.size - Vector2(0, 4.0)), body)
	b.tri(Vector2.ZERO, out * 10.0 + side * 8.0, out * 10.0 - side * 8.0, body)
	b.capsule(Rect2(r.position + Vector2(9.0, 3.0), Vector2(r.size.x - 18.0, r.size.y * 0.3)), Color(1, 1, 1, 0.3 * alpha))
	return [b.points, b.colors]


# --- Brillo ---------------------------------------------------------------------------

## Halo de un premio o power-up: degradé radial que late y rayos que giran.
## `t`: reloj de animación del juego.
static func add_glow(b: TriBatch, c: Vector2, r: float, col: Color, t: float, rays: int = 10) -> void:
	var pulse := 1.0 + 0.08 * sin(t * 5.0)
	var clear := Color(col, 0.0)
	b.points.append_array(Transform2D(t * 0.9, Vector2.ONE * r * 1.35 * pulse, 0.0, c) * rays_tris(rays))
	b.colors.append_array(pattern_colors(PackedColorArray([Color(col, 0.85), clear, clear]), rays))
	b.radial(c, r * pulse, Color(col, 0.95), clear)
