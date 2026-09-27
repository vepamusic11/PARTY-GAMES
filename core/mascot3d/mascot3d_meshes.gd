class_name Mascot3DMeshes
extends RefCounted
## Mallas de las mascotas 3D, armadas por código (sin archivos de modelo).
##
## Todo sale de cuatro recetas:
## - `sphere()`: esfera unidad. Escalada da cabeza, orejas, manos, zapatos, ojos.
## - `lathe(perfil)`: superficie de revolución (como un torno de alfarero).
##   Ejemplo: el cuerpo es un perfil "más ancho abajo" que gira alrededor del eje vertical.
## - `tube(puntos, radios)`: tubo que sigue una curva con radio variable.
##   Ejemplo: antena, tallito del brote, cuernos (se afinan hacia la punta),
##   ojos felices (arco), cejas y bocas en arco.
## - `extrude(contorno)`: figura plana con espesor (boca abierta, rejilla del robot).
##
## Las mallas se arman una vez por proceso y quedan en caché: todas las
## mascotas comparten los mismos buffers de vértices en la GPU.

static var _cache: Dictionary = {}


## Esfera unidad (radio 1). rings/segs bajos alcanzan: lo que se ve de cerca
## es el sombreado, y el contorno de tinta tapa el borde facetado.
static func sphere(rings := 16, segs := 28) -> Mesh:
	var key := "sphere:%d:%d" % [rings, segs]
	if not _cache.has(key):
		var m := SphereMesh.new()
		m.radius = 1.0
		m.height = 2.0
		m.rings = rings
		m.radial_segments = segs
		_cache[key] = m
	return _cache[key]


## Cilindro unidad (radio 1, alto 1, eje Y).
static func cylinder(segs := 24) -> Mesh:
	var key := "cyl:%d" % segs
	if not _cache.has(key):
		var m := CylinderMesh.new()
		m.top_radius = 1.0
		m.bottom_radius = 1.0
		m.height = 1.0
		m.radial_segments = segs
		m.rings = 1
		_cache[key] = m
	return _cache[key]


## Toro (anillo) de radio mayor 1 y radio de tubo `thickness`, en el plano XZ.
static func torus(thickness: float, segs := 24) -> Mesh:
	var key := "torus:%.3f:%d" % [thickness, segs]
	if not _cache.has(key):
		var m := TorusMesh.new()
		m.inner_radius = 1.0 - thickness
		m.outer_radius = 1.0 + thickness
		m.rings = segs
		m.ring_segments = 10
		_cache[key] = m
	return _cache[key]


## Superficie de revolución alrededor del eje Y. profile: puntos (radio, y)
## de abajo hacia arriba; conviene que empiece y termine con radio 0 (cerrada).
## depth: escala del radio en Z (1 = redondo; < 1, aplastado adelante-atrás).
static func lathe(key: String, profile: PackedVector2Array, segs := 28, depth := 1.0) -> Mesh:
	if _cache.has(key):
		return _cache[key]
	var verts := PackedVector3Array()
	var n := profile.size()
	for i in n:
		for j in segs + 1:
			# La costura (primer y último vértice de cada anillo) queda atrás, donde no se ve.
			var a := PI + TAU * j / segs
			var p := profile[i]
			verts.append(Vector3(sin(a) * p.x, p.y, cos(a) * p.x * depth))
	var idx := PackedInt32Array()
	for i in n - 1:
		for j in segs:
			var a := i * (segs + 1) + j
			var b := a + segs + 1
			idx.append_array([a, a + 1, b, a + 1, b + 1, b])
	var mesh := _build(verts, idx, func(v: Vector3) -> Vector3: return Vector3(0, v.y, 0))
	_cache[key] = mesh
	return mesh


## Perfil de una superelipse para lathe: exponent > 2 la hace más "de
## caramelo" (lados rectos); taper > 0 ensancha la parte de abajo.
static func blob_profile(rx: float, ry: float, cy: float, exponent := 2.0, taper := 0.0, steps := 18) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var e := 2.0 / exponent
	for i in steps + 1:
		var a := -PI / 2.0 + PI * i / steps
		var s := sin(a)
		var c := cos(a)
		var y := signf(s) * pow(absf(s), e)
		var r := pow(absf(c), e) * (1.0 - taper * y)
		pts.append(Vector2(maxf(r * rx, 0.0), cy + y * ry))
	pts[0].x = 0.0
	pts[steps].x = 0.0
	return pts


## Tubo que sigue `points` con radio `radii[i]` en cada punto y puntas
## redondeadas (media esfera). Sirve para antenas, cuernos, cejas y arcos.
static func tube(key: String, points: PackedVector3Array, radii: PackedFloat32Array, sides := 10,
		round_caps := true) -> Mesh:
	if _cache.has(key):
		return _cache[key]
	var n := points.size()
	# Tangentes y marco que "viaja" por la curva sin retorcerse (transporte paralelo).
	var tangents := PackedVector3Array()
	for i in n:
		var t := points[mini(i + 1, n - 1)] - points[maxi(i - 1, 0)]
		tangents.append(t.normalized())
	var up := Vector3.FORWARD if absf(tangents[0].dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT
	var normal := tangents[0].cross(up).normalized()
	var rings_c := PackedVector3Array()
	var rings_n := PackedVector3Array()
	var rings_r := PackedFloat32Array()
	var rings_t := PackedVector3Array()
	var cap := 4 if round_caps else 0
	# Tapa del principio: anillos que se cierran hacia atrás.
	for k in range(cap, 0, -1):
		var ang := PI / 2.0 * k / cap
		rings_c.append(points[0] - tangents[0] * radii[0] * sin(ang))
		rings_r.append(radii[0] * cos(ang))
		rings_t.append(tangents[0])
		rings_n.append(normal)
	for i in n:
		if i > 0:
			var axis := tangents[i - 1].cross(tangents[i])
			if axis.length() > 1e-5:
				normal = normal.rotated(axis.normalized(), tangents[i - 1].angle_to(tangents[i]))
		rings_c.append(points[i])
		rings_r.append(radii[i])
		rings_t.append(tangents[i])
		rings_n.append(normal)
	for k in range(1, cap + 1):
		var ang := PI / 2.0 * k / cap
		rings_c.append(points[n - 1] + tangents[n - 1] * radii[n - 1] * sin(ang))
		rings_r.append(radii[n - 1] * cos(ang))
		rings_t.append(tangents[n - 1])
		rings_n.append(normal)
	var verts := PackedVector3Array()
	var m := rings_c.size()
	for i in m:
		var t := rings_t[i]
		var nrm := rings_n[i]
		var bin := t.cross(nrm)
		for j in sides:
			var a := TAU * j / sides
			var d := nrm * cos(a) + bin * sin(a)
			verts.append(rings_c[i] + d * rings_r[i])
	var idx := PackedInt32Array()
	for i in m - 1:
		for j in sides:
			var a := i * sides + j
			var b := i * sides + (j + 1) % sides
			idx.append_array([a, b, a + sides, b, b + sides, a + sides])
	var mesh := _build(verts, idx, func(v: Vector3) -> Vector3: return _nearest_on_polyline(points, v))
	_cache[key] = mesh
	return mesh


static func _nearest_on_polyline(pts: PackedVector3Array, v: Vector3) -> Vector3:
	var best := pts[0]
	var best_d := INF
	for i in pts.size() - 1:
		var q := Geometry3D.get_closest_point_to_segment(v, pts[i], pts[i + 1])
		var d := q.distance_squared_to(v)
		if d < best_d:
			best_d = d
			best = q
	return best


## Figura plana (contorno convexo en XY) con espesor `depth` hacia +Z y
## canto redondeado. Para bocas y la rejilla del robot.
static func extrude(key: String, outline: PackedVector2Array, depth: float) -> Mesh:
	if _cache.has(key):
		return _cache[key]
	var n := outline.size()
	var c := Vector2.ZERO
	for p in outline:
		c += p
	c /= n
	# Tres anillos: atrás, frente (algo más chico: canto redondeado) y el centro.
	var verts := PackedVector3Array()
	for p in outline:
		verts.append(Vector3(p.x, p.y, 0.0))
	for p in outline:
		var q := c + (p - c) * 0.9
		verts.append(Vector3(q.x, q.y, depth))
	verts.append(Vector3(c.x, c.y, depth * 1.15))
	var idx := PackedInt32Array()
	for i in n:
		var j := (i + 1) % n
		idx.append_array([i, j, n + i, j, n + j, n + i, n + i, n + j, 2 * n])
	var back := Vector3(c.x, c.y, -depth * 4.0)
	var mesh := _build(verts, idx, func(_v: Vector3) -> Vector3: return back)
	_cache[key] = mesh
	return mesh


## Contorno de una elipse (o media elipse: `half` = sonrisa con el borde de arriba recto).
static func ellipse_outline(rx: float, ry: float, steps := 20, half := false) -> PackedVector2Array:
	var pts := PackedVector2Array()
	if half:
		for i in steps + 1:
			var a := PI + PI * i / steps  # De izquierda a derecha por abajo.
			pts.append(Vector2(cos(a) * rx, sin(a) * ry))
		return pts
	for i in steps:
		var a := TAU * i / steps
		pts.append(Vector2(cos(a) * rx, sin(a) * ry))
	return pts


## Superelipse (rectángulo redondeado) de semiejes rx, ry.
static func rounded_rect_outline(rx: float, ry: float, steps := 24, exponent := 4.0) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var e := 2.0 / exponent
	for i in steps:
		var a := TAU * i / steps
		pts.append(Vector2(signf(cos(a)) * pow(absf(cos(a)), e) * rx, signf(sin(a)) * pow(absf(sin(a)), e) * ry))
	return pts


## Estrella de `points` puntas (radio 1 afuera, `inner` adentro), con la
## primera punta hacia arriba. Para ojos de estrella y estrellitas de mareo.
static func star_outline(points: int, inner: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in points * 2:
		var a := PI / 2.0 + PI * i / points
		var r := 1.0 if i % 2 == 0 else inner
		pts.append(Vector2(cos(a), sin(a)) * r)
	return pts


## Punto de la superficie de un elipsoide (semiejes r, centro en el origen)
## que se ve en (x, y) de frente. Para apoyar ojos y bocas sobre la cabeza.
static func ellipsoid_point(r: Vector3, p: Vector2) -> Vector3:
	var k := 1.0 - (p.x / r.x) * (p.x / r.x) - (p.y / r.y) * (p.y / r.y)
	return Vector3(p.x, p.y, r.z * sqrt(maxf(k, 0.0)))


## Normal del elipsoide en el punto que se ve en (x, y) de frente.
static func ellipsoid_normal(r: Vector3, p: Vector2) -> Vector3:
	var q := ellipsoid_point(r, p)
	return Vector3(q.x / (r.x * r.x), q.y / (r.y * r.y), q.z / (r.z * r.z)).normalized()


## Parche de la cara: la superficie de la cabeza (elipsoide de semiejes
## `head`) dentro de una elipse vista de frente (centro `center`, semiejes
## `radii`), levantada `bulge` como una almohadilla con el borde metido
## debajo de la cabeza (así el borde es limpio, sin parpadeo de profundidad).
static func face_pad(key: String, head: Vector3, center: Vector2, radii: Vector2, bulge: float,
		rings := 16, segs := 48) -> Mesh:
	if _cache.has(key):
		return _cache[key]
	var verts := PackedVector3Array()
	verts.append(face_point(head, center, radii, bulge, center))
	for i in range(1, rings + 1):
		var s := float(i) / rings
		for j in segs:
			var a := TAU * j / segs
			var p := center + Vector2(cos(a) * radii.x, sin(a) * radii.y) * s
			verts.append(face_point(head, center, radii, bulge, p))
	var idx := PackedInt32Array()
	for j in segs:
		idx.append_array([0, 1 + (j + 1) % segs, 1 + j])
	for i in rings - 1:
		for j in segs:
			var a := 1 + i * segs + j
			var b := 1 + i * segs + (j + 1) % segs
			idx.append_array([a, b, a + segs, b, b + segs, a + segs])
	var mesh := _build(verts, idx, func(_v: Vector3) -> Vector3: return Vector3.ZERO)
	_cache[key] = mesh
	return mesh


## Punto de la almohadilla de la cara que se ve en (x, y) de frente.
static func face_point(head: Vector3, center: Vector2, radii: Vector2, bulge: float, p: Vector2) -> Vector3:
	var s := minf(((p - center) / radii).length(), 1.0)
	var k := 1.0 - (p.x / head.x) * (p.x / head.x) - (p.y / head.y) * (p.y / head.y)
	var z := head.z * sqrt(maxf(k, 0.0))
	# El borde se hunde bien por debajo de la cabeza: si quedara casi al ras,
	# las facetas de la esfera y las de la cara se cruzarían y el borde
	# se vería serruchado.
	return Vector3(p.x, p.y, z + bulge * sqrt(maxf(1.0 - pow(s, 4.0), 0.0)) - 0.16 * pow(s, 8.0))


## Normal de la almohadilla en (x, y) (por diferencias finitas).
static func face_normal(head: Vector3, center: Vector2, radii: Vector2, bulge: float, p: Vector2) -> Vector3:
	var e := 0.02
	var dx := face_point(head, center, radii, bulge, p + Vector2(e, 0)) - face_point(head, center, radii, bulge, p - Vector2(e, 0))
	var dy := face_point(head, center, radii, bulge, p + Vector2(0, e)) - face_point(head, center, radii, bulge, p - Vector2(0, e))
	return dx.cross(dy).normalized()


## Arma la malla con normales suaves y la da vuelta si quedó "del revés".
## Concepto: *orden de los vértices* (winding). La placa decide qué cara de
## un triángulo es "el frente" según si sus vértices giran en un sentido u
## otro; Godot toma como frente el sentido horario. En vez de cuidar el
## orden a mano en cada receta, se compara la normal con un punto de
## adentro (`inside`) y, si la mayoría apunta hacia adentro, se invierte.
static func _build(verts: PackedVector3Array, idx: PackedInt32Array, inside: Callable) -> ArrayMesh:
	for attempt in 2:
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		for v in verts:
			st.add_vertex(v)
		for i in idx:
			st.add_index(i)
		st.generate_normals()
		var mesh := st.commit()
		# SurfaceTool junta los vértices repetidos (costuras, polos): se leen de la malla.
		var arrays := mesh.surface_get_arrays(0)
		var pos: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var score := 0.0
		for i in pos.size():
			score += signf(normals[i].dot(pos[i] - inside.call(pos[i])))
		if score >= 0.0 or attempt == 1:
			return mesh
		for t in range(0, idx.size(), 3):  # Invertir el orden de cada triángulo.
			var tmp := idx[t + 1]
			idx[t + 1] = idx[t + 2]
			idx[t + 2] = tmp
	return null
