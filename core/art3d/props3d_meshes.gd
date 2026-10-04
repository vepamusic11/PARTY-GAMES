class_name Props3DMeshes
extends RefCounted
## Mallas de las piezas 3D del escenario y de la UI (estrellas, bloques,
## medallas, trofeo…), armadas por código. Ver `Props3D` y ADR 0016.
##
## Recetas (todas en unidades de "px lógicos": una estrella de radio 40 mide
## 40 px en la TV a 1920×1080):
## - `rounded_box(tamaño, radio)`: caja con cantos redondeados, como un
##   ladrillo de juguete. Normales exactas (se calculan, no se promedian).
##   Ejemplo: un bloque del marco del tablero es rounded_box((110, 34, 18), 6).
## - `pillow(contorno, grosor)`: figura plana "inflada" como un almohadón
##   (el centro más alto, el borde redondeado). Sirve para cualquier contorno
##   que se vea entero desde un punto (figura "estrellada" respecto del
##   centro). Ejemplo: la estrella dorada de las esquinas.
## - `lathe(perfil)`: superficie de revolución (torno). Ejemplo: la copa del
##   trofeo, las medallas y las monedas (un disco con el borde levantado).
## - `faceted_lathe(perfil)`: igual, pero con caras planas (gema tallada).
##
## Las mallas se arman una sola vez por proceso y quedan en caché.

static var _cache: Dictionary = {}


# --- Contornos 2D ---------------------------------------------------------------------

## Estrella de 5 puntas con puntas redondeadas (x derecha, y arriba), radio
## de las puntas `r`. `inner`: radio de los valles respecto de `r`.
static func star_outline(r: float, inner := 0.5, smooth := 3) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in 10:
		var a := PI / 2.0 + PI * i / 5.0
		pts.append(Vector2(cos(a), sin(a)) * (r if i % 2 == 0 else r * inner))
	pts = chaikin(pts, smooth)
	# El redondeo achica las puntas: se vuelve a llevar la punta a `r`.
	var far := 0.0
	for p in pts:
		far = maxf(far, p.length())
	var k := r / far
	for i in pts.size():
		pts[i] *= k
	return pts


## Suavizado de Chaikin: corta cada esquina en 1/4 y 3/4 de sus lados. Con
## 2–3 pasadas las puntas quedan redondeadas como un juguete de plástico.
static func chaikin(pts: PackedVector2Array, passes: int) -> PackedVector2Array:
	var cur := pts
	for p in passes:
		var nxt := PackedVector2Array()
		var n := cur.size()
		for i in n:
			var a := cur[i]
			var b := cur[(i + 1) % n]
			nxt.append(a.lerp(b, 0.25))
			nxt.append(a.lerp(b, 0.75))
		cur = nxt
	return cur


# --- Recetas --------------------------------------------------------------------------

## Caja de `size` (x ancho, y alto, z profundidad) centrada en el origen, con
## cantos de radio `radius`. Cada cara es una grilla que se "redondea"
## empujando cada punto hacia la caja interior (la de lado size − 2·radio):
## el punto queda a `radius` de esa caja y la normal es la dirección del empuje.
static func rounded_box(size: Vector3, radius: float, steps := 4) -> ArrayMesh:
	var key := "rbox:%s:%.2f:%d" % [size, radius, steps]
	if _cache.has(key):
		return _cache[key]
	var h := size / 2.0
	var r := minf(radius, minf(h.x, minf(h.y, h.z)) - 0.01)
	var inner := h - Vector3(r, r, r)
	var cx := _box_axis(h.x, r, steps)
	var cy := _box_axis(h.y, r, steps)
	var cz := _box_axis(h.z, r, steps)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# Cada cara: (eje fijo, signo, eje u, eje v). u × v apunta hacia afuera.
	var faces := [[2, 1.0, 0, 1], [2, -1.0, 1, 0], [0, 1.0, 1, 2], [0, -1.0, 2, 1], [1, 1.0, 2, 0], [1, -1.0, 0, 2]]
	var axes := [cx, cy, cz]
	for f: Array in faces:
		var us: PackedFloat32Array = axes[f[2]]
		var vs: PackedFloat32Array = axes[f[3]]
		for i in us.size() - 1:
			for j in vs.size() - 1:
				var quad := [[i, j], [i + 1, j], [i + 1, j + 1], [i, j + 1]]
				var vq: Array[Vector3] = []
				var nq: Array[Vector3] = []
				for q: Array in quad:
					var p := Vector3.ZERO
					p[f[0]] = h[f[0]] * f[1]
					p[f[2]] = us[q[0]]
					p[f[3]] = vs[q[1]]
					var c := p.clamp(-inner, inner)
					var d := (p - c)
					var n := d.normalized() if d.length() > 1e-5 else Vector3.ZERO
					if n == Vector3.ZERO:
						n[f[0]] = f[1]
					vq.append(c + n * r)
					nq.append(n)
				for t in [0, 1, 2, 0, 2, 3]:
					st.set_normal(nq[t])
					st.add_vertex(vq[t])
	var mesh := _fix_winding(st, Vector3.ZERO)
	_cache[key] = mesh
	return mesh


## Coordenadas de la grilla sobre un eje de la caja: más puntos en los cantos
## (donde se curva) y ninguno de más en lo plano.
static func _box_axis(half: float, r: float, steps: int) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	var inner := half - r
	for k in steps + 1:
		out.append(-inner - r * cos(PI / 2.0 * k / steps))
	for k in steps + 1:
		var v := inner + r * sin(PI / 2.0 * k / steps)
		if k == 0 and absf(v - out[out.size() - 1]) < 1e-4:
			continue
		out.append(v)
	return out


## Almohadón: el contorno (en XY, visto desde +Z) inflado con grosor `depth`
## de cada lado. Cada anillo es el contorno achicado hacia `center` con perfil
## de elipse (lo del medio a altura `depth`, el borde vertical). Es cerrado
## (tiene cara de atrás): lo necesita el contorno de tinta de casco invertido.
static func pillow(key: String, outline: PackedVector2Array, depth: float, rings := 10,
		center := Vector2.ZERO) -> ArrayMesh:
	if _cache.has(key):
		return _cache[key]
	var n := outline.size()
	var verts := PackedVector3Array()
	var idx := PackedInt32Array()
	# Anillos de adelante (k = 1..rings, del centro al borde) y de atrás
	# (espejados, sin repetir el borde). 0 = punta de adelante, 1 = de atrás.
	verts.append(Vector3(center.x, center.y, depth))
	verts.append(Vector3(center.x, center.y, -depth))
	for side in 2:
		var z_sign := 1.0 if side == 0 else -1.0
		var last := rings if side == 0 else rings - 1
		for k in range(1, last + 1):
			var t := float(k) / rings
			var s := sin(t * PI / 2.0)
			var z := cos(t * PI / 2.0) * depth * z_sign
			for i in n:
				var p := center + (outline[i] - center) * s
				verts.append(Vector3(p.x, p.y, z))
	var front := func(k: int, i: int) -> int: return 2 + (k - 1) * n + i % n
	var back := func(k: int, i: int) -> int:
		return front.call(rings, i) if k == rings else 2 + rings * n + (k - 1) * n + i % n
	for i in n:
		idx.append_array([0, front.call(1, i + 1), front.call(1, i)])
		idx.append_array([1, back.call(1, i), back.call(1, i + 1)])
	for k in range(1, rings):
		for i in n:
			var a: int = front.call(k, i)
			var b: int = front.call(k, i + 1)
			var c: int = front.call(k + 1, i)
			var d: int = front.call(k + 1, i + 1)
			idx.append_array([a, b, c, b, d, c])
			a = back.call(k, i)
			b = back.call(k, i + 1)
			c = back.call(k + 1, i)
			d = back.call(k + 1, i + 1)
			idx.append_array([a, c, b, b, c, d])
	var mesh := _indexed(verts, idx, Vector3(center.x, center.y, 0.0))
	_cache[key] = mesh
	return mesh


## Superficie de revolución alrededor del eje Y. profile: (radio, y) de abajo
## hacia arriba; empieza y termina con radio 0 (cerrada). Para un aro (el
## perfil es un lazo que no toca el eje, ej. el borde de una medalla),
## `ring` = (radio, y) del centro del lazo: sirve para saber qué es "adentro".
static func lathe(key: String, profile: PackedVector2Array, segs := 40, ring := Vector2(-1, 0)) -> ArrayMesh:
	if _cache.has(key):
		return _cache[key]
	var verts := PackedVector3Array()
	var n := profile.size()
	for i in n:
		for j in segs:
			var a := TAU * j / segs
			verts.append(Vector3(sin(a) * profile[i].x, profile[i].y, cos(a) * profile[i].x))
	var idx := PackedInt32Array()
	for i in n - 1:
		for j in segs:
			var a := i * segs + j
			var b := i * segs + (j + 1) % segs
			idx.append_array([a, b, a + segs, b, b + segs, a + segs])
	var mesh := _indexed(verts, idx, Vector3.ZERO, true, ring)
	_cache[key] = mesh
	return mesh


## Como lathe, pero con caras planas y pocos lados: una gema tallada.
static func faceted_lathe(key: String, profile: PackedVector2Array, segs := 8) -> ArrayMesh:
	if _cache.has(key):
		return _cache[key]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var cy := (profile[0].y + profile[profile.size() - 1].y) / 2.0
	var ring := func(i: int, j: int) -> Vector3:
		var a := TAU * (j + 0.5 * (i % 2)) / segs  # Anillos alternados: facetas en rombo.
		return Vector3(sin(a) * profile[i].x, profile[i].y, cos(a) * profile[i].x)
	for i in profile.size() - 1:
		for j in segs:
			var a: Vector3 = ring.call(i, j)
			var b: Vector3 = ring.call(i, j + 1)
			var c: Vector3 = ring.call(i + 1, j)
			var d: Vector3 = ring.call(i + 1, j + 1)
			for tri: Array in [[a, b, c], [b, d, c]]:
				var n: Vector3 = (tri[1] - tri[0]).cross(tri[2] - tri[0])
				if n.length() < 1e-6:
					continue
				n = n.normalized()
				var mid: Vector3 = (tri[0] + tri[1] + tri[2]) / 3.0
				if n.dot(mid - Vector3(0, cy, 0)) < 0.0:  # Hacia afuera (la gema es convexa).
					n = -n
				for v: Vector3 in tri:
					st.set_normal(n)
					st.add_vertex(v)
	var mesh := _fix_winding(st, Vector3(0, cy, 0))
	_cache[key] = mesh
	return mesh


## Esfera unidad (radio 1).
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


## Toro (aro) de radio 1 y grosor `thickness`, en el plano XZ.
static func torus(thickness: float, segs := 32) -> Mesh:
	var key := "torus:%.3f:%d" % [thickness, segs]
	if not _cache.has(key):
		var m := TorusMesh.new()
		m.inner_radius = 1.0 - thickness
		m.outer_radius = 1.0 + thickness
		m.rings = segs
		m.ring_segments = 12
		_cache[key] = m
	return _cache[key]


## Cono (o tronco de cono) de radio de base 1 y alto 1, con la base en y = 0.
static func cone(top := 0.0, segs := 24) -> Mesh:
	var key := "cone:%.3f:%d" % [top, segs]
	if not _cache.has(key):
		var prof := PackedVector2Array([Vector2(0, 0), Vector2(1, 0), Vector2(1, 0.02)])
		for k in 7:  # Punta redondeada.
			var t := float(k + 1) / 8.0
			prof.append(Vector2(lerpf(1.0, top, t) + (0.0 if top > 0.0 else 0.06 * sin(t * PI)), t))
		prof.append(Vector2(maxf(top, 0.08), 0.99))
		prof.append(Vector2(0, 1.0))
		_cache[key] = lathe("cone_mesh:%.3f" % top, prof, segs)
	return _cache[key]


# --- Armado -----------------------------------------------------------------------

## Malla con índices y normales suaves (se promedian las de los triángulos
## que comparten cada vértice). Si la mayoría apunta hacia adentro (hacia
## `inside`, o hacia el eje Y si `axis`), se invierte el orden de los
## triángulos: Godot toma como frente el sentido horario.
static func _indexed(verts: PackedVector3Array, idx: PackedInt32Array, inside: Vector3, axis := false,
		ring := Vector2(-1, 0)) -> ArrayMesh:
	for attempt in 2:
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		for v in verts:
			st.add_vertex(v)
		for i in idx:
			st.add_index(i)
		st.generate_normals()
		var mesh := st.commit()
		var arrays := mesh.surface_get_arrays(0)
		var pos: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var score := 0.0
		for i in pos.size():
			var c := Vector3(0, pos[i].y, 0) if axis else inside
			if ring.x >= 0.0:  # Aro: lo de adentro es el círculo central del lazo.
				c = Vector3(pos[i].x, 0, pos[i].z).normalized() * ring.x + Vector3(0, ring.y, 0)
			score += signf(normals[i].dot(pos[i] - c))
		if score >= 0.0 or attempt == 1:
			return mesh
		for t in range(0, idx.size(), 3):
			var tmp := idx[t + 1]
			idx[t + 1] = idx[t + 2]
			idx[t + 2] = tmp
	return null


## Para mallas con normales ya puestas: da vuelta los triángulos si el frente
## (según el orden de los vértices) no coincide con la normal.
static func _fix_winding(st: SurfaceTool, _inside: Vector3) -> ArrayMesh:
	var arrays := st.commit_to_arrays()
	var pos: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var nrm: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var score := 0.0
	for t in range(0, pos.size() - 2, 3):
		var face := (pos[t + 1] - pos[t]).cross(pos[t + 2] - pos[t])
		score += signf(face.dot(nrm[t] + nrm[t + 1] + nrm[t + 2]))
	# Godot: frente = horario visto desde la cámara, o sea la normal
	# geométrica (regla de la mano derecha) apunta hacia ADENTRO.
	if score > 0.0:
		for t in range(0, pos.size() - 2, 3):
			var tmp := pos[t + 1]
			pos[t + 1] = pos[t + 2]
			pos[t + 2] = tmp
			var tn := nrm[t + 1]
			nrm[t + 1] = nrm[t + 2]
			nrm[t + 2] = tn
		arrays[Mesh.ARRAY_VERTEX] = pos
		arrays[Mesh.ARRAY_NORMAL] = nrm
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh
