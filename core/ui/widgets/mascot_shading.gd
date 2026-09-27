class_name MascotShading
extends RefCounted
## Sombreado "de juguete 3D" para las mascotas (lo usa PlayerAvatar.draw_mascot).
##
## Concepto: *sombreado por vértice* (Gouraud). La placa de video pinta cada
## triángulo mezclando suavemente los colores de sus tres vértices. Si una
## figura se arma con anillos concéntricos (centro → borde) y a cada vértice
## se le da el color que tendría una esfera iluminada desde arriba a la
## izquierda, el resultado es un degradé suave de luz a sombra, como un
## juguete de plástico. Ejemplo: la cabeza son 4 anillos de 36 puntos; el
## vértice de arriba a la izquierda sale casi blanco, el de abajo a la
## derecha, el color oscurecido, y la placa rellena todo lo del medio.
##
## Concepto: *borde suavizado* (antialiasing). Alrededor de cada figura va un
## anillo de ~1 px cuyo color exterior es transparente: el borde se funde con
## el fondo en vez de verse escalonado.
##
## El contorno de tinta va en la misma malla: tres anillos más alrededor del
## borde (el color se funde en la tinta en ~1 px, la tinta y el borde
## suavizado de afuera). Una sola figura por pieza en vez de dos apiladas.
##
## Rendimiento (ver docs/PERFORMANCE.md):
## - Todo va dentro de un UiTheme.ShapeBatch: sin texturas ni shaders, así la
##   mascota entera sigue siendo uno o dos draw calls.
## - La malla de cada forma (círculo, cuerpo, oreja…) se arma una sola vez en
##   espacio unidad (Shape). Por frame solo se transforma (en C++,
##   Transform2D * PackedVector2Array) y se copian arreglos ya hechos.
## - Los colores por vértice dependen solo de la forma, el material, el color
##   del jugador y el giro (en 16 pasos): se calculan una vez y quedan en
##   caché. Los índices corridos a cada posición del lote, también.

## Materiales (cómo reparte la luz cada figura).
enum { PLASTIC, FACE, METAL, EYE, FLAT, GLOW }

const FEATHER := 1.0   ## Ancho del borde suavizado, en píxeles del lienzo.
const INNER_FEATHER := 0.9  ## Paso suave del color a la tinta (px).
const LIGHT_BINS := 16 ## Pasos de giro para los que se precalcula la luz.

## Luz principal: arriba a la izquierda y hacia la cámara.
static var _light := Vector3(-0.48, -0.62, 0.62).normalized()
static var _colors: Dictionary = {}    # clave (forma, material, giro, color) -> PackedColorArray
static var _shifted: Dictionary = {}   # clave (forma, variante, base) -> PackedInt32Array
static var _ink_ids: Dictionary = {}   # color de tinta (rgba32) -> 1..14
static var _next_id := 0


## Malla unidad de una figura: centro + anillos (de adentro hacia el borde)
## y, aparte, el borde para el anillo suavizado.
class Shape:
	extends RefCounted
	var id := 0
	var core := PackedVector2Array()     ## Centro + anillos (el último es el borde).
	var edge := PackedVector2Array()     ## Borde (se agranda ~1 px al dibujar).
	var sphere := PackedVector2Array()   ## Coordenada en el disco unidad de cada vértice (luz).
	## Índices por variante: 0 solo relleno, 1 + borde suavizado, 2 + contorno de tinta.
	var indices: Array[PackedInt32Array] = []
	var extent := Vector2.ONE            ## Semiejes del borde (para medir el suavizado en px).
	var feather := true


## Arma una Shape a partir de un contorno convexo (o estrellado respecto de
## su centro). rings: escalas de cada anillo, de menor a 1.0.
static func make_shape(outline: PackedVector2Array, rings: PackedFloat32Array, feather := true) -> Shape:
	var s := Shape.new()
	s.id = _next_id
	_next_id += 1
	s.feather = feather
	var n := outline.size()
	var c := Vector2.ZERO
	var lo := outline[0]
	var hi := outline[0]
	for p in outline:
		c += p
		lo = lo.min(p)
		hi = hi.max(p)
	c /= n
	s.extent = ((hi - lo) / 2.0).max(Vector2(0.001, 0.001))
	# Dirección de cada punto del borde en el disco unidad (para la luz).
	var dirs := PackedVector2Array()
	for p in outline:
		var d := (p - c) / s.extent
		dirs.append(d.normalized() if not d.is_zero_approx() else Vector2.ZERO)
	s.core.append(c)
	s.sphere.append(Vector2.ZERO)
	for k in rings.size():
		for i in n:
			s.core.append(c + (outline[i] - c) * rings[k])
			s.sphere.append(dirs[i] * rings[k])
	s.edge = outline
	var tris := PackedInt32Array()
	# Abanico del centro al primer anillo.
	for i in n:
		tris.append_array([0, 1 + i, 1 + (i + 1) % n])
	# Tiras entre anillos; los anillos de afuera (suavizado o tinta) siguen
	# a core en el mismo orden.
	s.indices = [PackedInt32Array(), PackedInt32Array(), PackedInt32Array()]
	for k in rings.size() + 2:
		if k == rings.size() - 1:
			s.indices[0] = tris.duplicate()
		elif k == rings.size():
			s.indices[1] = tris.duplicate()
		var a0 := 1 + k * n
		for i in n:
			var a := a0 + i
			var b := a0 + (i + 1) % n
			tris.append_array([a, b, a + n, b, b + n, a + n])
	s.indices[2] = tris
	return s


## Arco grueso (ojos felices, boca triste) de radio 1 entre los ángulos a0 y
## a1, con un borde suavizado de `feather` a cada lado (en unidades de la
## figura). Se dibuja con el material GLOW: la luz de GLOW deja opaco lo de
## adentro y transparente el borde, justo lo que hace falta.
static func make_arc(a0: float, a1: float, steps: int, width: float, feather: float) -> Shape:
	var s := Shape.new()
	s.id = _next_id
	_next_id += 1
	s.feather = false
	var radii := [1.0 - width / 2.0 - feather, 1.0 - width / 2.0, 1.0 + width / 2.0, 1.0 + width / 2.0 + feather]
	for i in steps + 1:
		var a := lerpf(a0, a1, float(i) / steps)
		for k in 4:
			s.core.append(Vector2(cos(a), sin(a)) * radii[k])
			s.sphere.append(Vector2.ZERO if k == 1 or k == 2 else Vector2.RIGHT)
	var tris := PackedInt32Array()
	for i in steps:
		for k in 3:
			var a := i * 4 + k
			tris.append_array([a, a + 1, a + 4, a + 1, a + 5, a + 4])
	s.indices = [tris, tris, tris]
	return s


## Contorno de una elipse unidad (o superelipse: exponent > 2 la hace más
## "cuadrada"). taper > 0 ensancha la parte de abajo (cuerpo); < 0, la achica.
static func blob_outline(segments: int, exponent := 2.0, taper := 0.0) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var e := 2.0 / exponent
	for i in segments:
		var a := TAU * i / segments
		var x := signf(cos(a)) * pow(absf(cos(a)), e)
		var y := signf(sin(a)) * pow(absf(sin(a)), e)
		pts.append(Vector2(x * (1.0 + taper * y), y))
	return pts


## Contorno de un polígono convexo con las esquinas redondeadas (radio r):
## sirve para orejas, cuernos y hojas. Agrandar r agranda todo el contorno
## de manera pareja (así se arma el contorno de tinta).
static func rounded_outline(corners: PackedVector2Array, r: float, step := 0.4) -> PackedVector2Array:
	var n := corners.size()
	var c := Vector2.ZERO
	for p in corners:
		c += p
	c /= n
	var pts := PackedVector2Array()
	for i in n:
		var p0 := corners[(i - 1 + n) % n]
		var p1 := corners[i]
		var p2 := corners[(i + 1) % n]
		var n1 := (p1 - p0).orthogonal().normalized()
		if n1.dot((p0 + p1) / 2.0 - c) < 0.0:
			n1 = -n1
		var n2 := (p2 - p1).orthogonal().normalized()
		if n2.dot((p1 + p2) / 2.0 - c) < 0.0:
			n2 = -n2
		var a1 := n1.angle()
		var delta := wrapf(n2.angle() - a1, -PI, PI)
		var steps := maxi(1, ceili(absf(delta) / step))
		for k in steps + 1:
			var a := a1 + delta * k / steps
			pts.append(p1 + Vector2(cos(a), sin(a)) * r)
	return pts


## Lote de la mascota: un UiTheme.ShapeBatch (círculos, arcos, polígonos)
## que además sabe agregar figuras sombreadas (add).
##
## Por qué un método del lote y no una función que recibe el lote: en
## GDScript, `batch.points.append_array(...)` desde afuera trae el arreglo,
## lo copia entero al modificarlo (copy-on-write) y lo vuelve a guardar. Con
## ~40 figuras por mascota eso eran ~40 copias de todo el lote. Adentro del
## lote, `points.append_array` agrega sin copiar.
class Batch:
	extends UiTheme.ShapeBatch

	## Agrega la figura. scale.x negativo la espeja (la luz se corrige sola:
	## sigue viniendo de arriba a la izquierda). ink_w > 0: con contorno de
	## tinta de ese ancho (px del lienzo).
	func add(s: Shape, material: int, col: Color, pos: Vector2, scale: Vector2, rot := 0.0,
			ink_w := 0.0, ink := UiTheme.INK) -> void:
		var base := points.size()
		var variant := 2 if ink_w > 0.0 else (1 if s.feather else 0)
		points.append_array(Transform2D(rot, scale, 0.0, pos) * s.core)
		if variant > 0:
			# Los anillos de afuera se agrandan en píxeles, no en proporción.
			var k := Vector2(signf(scale.x) / s.extent.x, signf(scale.y) / s.extent.y)
			if variant == 2:
				points.append_array(Transform2D(rot, scale + k * INNER_FEATHER, 0.0, pos) * s.edge)
				points.append_array(Transform2D(rot, scale + k * ink_w, 0.0, pos) * s.edge)
				points.append_array(Transform2D(rot, scale + k * (ink_w + FEATHER), 0.0, pos) * s.edge)
			else:
				points.append_array(Transform2D(rot, scale + k * FEATHER, 0.0, pos) * s.edge)
		colors.append_array(MascotShading._colors_for(s, material, col, rot, scale.x < 0.0, variant, ink))
		indices.append_array(MascotShading._indices_for(s, variant, base))


## Índices de la figura corridos a la posición `base` del lote (en caché:
## el mismo dibujo arma el mismo lote en cada frame).
static func _indices_for(s: Shape, variant: int, base: int) -> PackedInt32Array:
	var key := (s.id * 4 + variant) * 1000000 + base
	var idx: PackedInt32Array = _shifted.get(key, PackedInt32Array())
	if idx.is_empty():
		idx = s.indices[variant].duplicate()
		for i in idx.size():
			idx[i] += base
		if _shifted.size() > 4096:  # Tope de memoria: se vuelve a llenar solo.
			_shifted.clear()
		_shifted[key] = idx
	return idx


static func _colors_for(s: Shape, material: int, col: Color, rot: float, mirrored: bool, variant: int,
		ink: Color) -> PackedColorArray:
	# Color redondeado a 64 niveles por canal: lo que se anima (el foco del
	# robot, la lágrima que se desvanece) no llena la caché con un color
	# nuevo por frame, y a simple vista es el mismo color.
	col = Color(roundf(col.r * 63.0) / 63.0, roundf(col.g * 63.0) / 63.0, roundf(col.b * 63.0) / 63.0,
		roundf(col.a * 63.0) / 63.0)
	var lit := material != FLAT and material != GLOW
	var bin := posmod(roundi(rot / TAU * LIGHT_BINS), LIGHT_BINS) if lit else 0
	var flip := 1 if (lit and mirrored) else 0
	# Parte "variante": 0 sin anillos, 1 suavizado, 2+ tinta (una por color de tinta).
	var ring := variant
	if variant == 2:
		var ink_key := ink.to_rgba32()
		ring = int(_ink_ids.get(ink_key, 0))
		if ring == 0:
			if _ink_ids.size() >= 13:
				_ink_ids.clear()
				_colors.clear()
			ring = 2 + _ink_ids.size()
			_ink_ids[ink_key] = ring
	var key := (ring << 48) | (col.to_rgba32() << 16) | (s.id << 9) | (material << 6) | (bin << 1) | flip
	var cached: PackedColorArray = _colors.get(key, PackedColorArray())
	if not cached.is_empty():
		return cached
	var out := PackedColorArray()
	if material == FLAT:
		out.resize(s.sphere.size())
		out.fill(col)
	else:
		var angle := TAU * bin / LIGHT_BINS
		for q in s.sphere:
			var v := q
			if flip:
				v.x = -v.x
			out.append(shade(material, col, v.rotated(angle)))
	var n := s.edge.size()
	if variant == 1:
		var edge0 := out.size() - n
		for i in n:
			out.append(Color(out[edge0 + i], 0.0))
	elif variant == 2:
		var rings := PackedColorArray()
		rings.resize(n * 3)
		rings.fill(ink)
		for i in n:
			rings[n * 2 + i] = Color(ink, 0.0)
		out.append_array(rings)
	if _colors.size() > 4096:
		_colors.clear()
	_colors[key] = out
	return out


## Color de un punto de la figura. q: posición en el disco unidad, ya girada
## a como se ve en pantalla (y hacia abajo).
static func shade(material: int, col: Color, q: Vector2) -> Color:
	var r := minf(q.length(), 1.0)
	var n := Vector3(q.x, q.y, sqrt(maxf(0.0, 1.0 - r * r)))
	var d := n.dot(_light)          # -1 (a la sombra) .. 1 (de frente a la luz)
	match material:
		FLAT:
			return col
		GLOW:  # Mancha de luz: opaca al centro, se desvanece hasta el borde.
			return Color(col, col.a * (1.0 - _smooth(0.0, 1.0, r)))
		FACE:  # Blanco mate: gris azulado en el borde y bajo la "capucha".
			var c := UiTheme.MASCOT_FACE_SHADE.lerp(UiTheme.PAPER, _smooth(-0.1, 0.75, d))
			return c.lerp(UiTheme.MASCOT_FACE_SHADE.darkened(0.12), _smooth(0.78, 1.0, r) * _smooth(0.1, -0.8, q.y) * 0.8)
		EYE:  # Negro brillante, con un reflejo azulado abajo.
			return col.lerp(UiTheme.MASCOT_EYE_GLOSS, _smooth(0.1, 1.0, q.y) * 0.7 * _smooth(0.3, 1.0, r))
		METAL:  # Cromado: contraste fuerte y una banda clara que refleja el cielo.
			var m := col.darkened(0.5).lerp(col, _smooth(-0.5, 0.3, d))
			m = m.lerp(UiTheme.PAPER, _smooth(0.55, 0.95, d) * 0.9)
			return m.lerp(col.lightened(0.3), _smooth(0.55, 1.0, q.y) * _smooth(0.6, 1.0, r) * 0.6)
	# PLASTIC: plástico de juguete. Sombra propia → color → luz, más la luz
	# que rebota del piso en el borde de abajo.
	var lum := col.get_luminance()
	var dark := lum < 0.2
	var low := col.lightened(0.02) if dark else col.darkened(0.5 if lum < 0.8 else 0.32)
	low = low.lerp(UiTheme.MASCOT_SHADE_TINT, 0.1)
	var mid := col.lightened(0.14) if dark else col
	var high := col.lightened(0.45 if dark else (0.1 if lum > 0.85 else 0.3))
	var out: Color
	if d < 0.35:
		out = low.lerp(mid, _smooth(-0.3, 0.35, d))
	else:
		out = mid.lerp(high, _smooth(0.55, 1.0, d))
	out = out.lerp(mid.lightened(0.1), _smooth(0.75, 1.0, r) * _smooth(0.2, 0.95, q.y) * 0.5)
	if dark:  # Luz de contorno: separa el cuerpo negro de la tinta.
		out = out.lerp(UiTheme.MASCOT_RIM, _smooth(0.8, 1.0, r) * 0.45)
	return out


## smoothstep que acepta from > to (curva invertida).
static func _smooth(from: float, to: float, x: float) -> float:
	var t := clampf((x - from) / (to - from), 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)
