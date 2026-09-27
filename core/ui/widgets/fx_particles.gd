class_name FxParticles
extends Node2D
## Partículas baratas en lote: estrellitas, polvo, chispas, gotas, confeti y
## anillos de brillo. Las usan los juegos de la TV (ver host/minigames/juice.gd)
## y sirven para cualquier pantalla.
##
## Concepto: *pool* de partículas. En vez de crear un nodo (o un diccionario)
## por partícula y borrarlo al terminar, hay una cantidad FIJA de lugares
## (`capacity`) guardados en arreglos empaquetados. Emitir ocupa el lugar
## siguiente en ronda: si estaban todos ocupados, se pisa el más viejo. Así la
## memoria nunca crece, no hay basura que juntar y el costo por frame tiene
## techo, aunque un juego pida mil partículas de golpe.
##
## Ejemplo: al juntar una estrella en Arena, `burst(Kind.STAR, pos, 8, GOLD,
## 380, 14, 0.55)` ocupa 8 lugares; medio segundo después vuelven a estar
## libres. Con 4 jugadores juntando estrellas a la vez se usan ~40 de 192.
##
## Rendimiento (docs/PERFORMANCE.md): TODAS las partículas vivas van en un
## solo canvas_item_add_triangle_array (un draw call). Las formas son
## triángulos precalculados en coordenadas locales que se ubican con
## Transform2D * PackedVector2Array (en C++). Sin partículas vivas el nodo
## apaga su _process y no se redibuja.

enum Kind {
	STAR,      ## Estrellita con contorno: aparece, gira y se achica.
	SPARK,     ## Chispa alargada en la dirección en que vuela.
	DOT,       ## Gota o puntito que se achica (chapuzón, estela).
	PUFF,      ## Polvo: nube que crece y se desvanece (frenar, aterrizar).
	CONFETTI,  ## Papelito que gira y "da vueltas" (se aplasta en un eje).
	RING,      ## Anillo que se expande y se desvanece (brillo, onda de choque).
}

var capacity := UiTheme.FX_MAX_PARTICLES
## Semilla del azar de los estallidos (capturas y tests reproducibles).
var rng := RandomNumberGenerator.new()

var _pos := PackedVector2Array()
var _vel := PackedVector2Array()
var _age := PackedFloat32Array()
var _dur := PackedFloat32Array()    # 0 = lugar libre
var _size := PackedFloat32Array()
var _rot := PackedFloat32Array()
var _spin := PackedFloat32Array()
var _grav := PackedFloat32Array()
var _drag := PackedFloat32Array()
var _kind := PackedInt32Array()
var _col := PackedColorArray()
var _next := 0
var _alive := 0
## Lugares [0, _hi) que pueden estar ocupados: los bucles no recorren el resto
## del pool. Vuelve a 0 cuando no queda ninguna viva.
var _hi := 0

# Lote que se arma en cada _draw (se reusa: no se crean arreglos por frame).
var _pts := PackedVector2Array()
var _cols := PackedColorArray()
var _tris: Array[PackedVector2Array] = []  # forma (Kind + 1; 0 = contorno de estrella) -> triángulos
var _fills: Array[PackedColorArray] = []   # forma -> colores de relleno (se reusan)

static var _shapes: Dictionary = {}  # Kind (y -1: contorno de estrella) -> triángulos locales


func _init(p_capacity: int = UiTheme.FX_MAX_PARTICLES) -> void:
	capacity = maxi(p_capacity, 1)
	_pos.resize(capacity)
	_vel.resize(capacity)
	_age.resize(capacity)
	_dur.resize(capacity)
	_size.resize(capacity)
	_rot.resize(capacity)
	_spin.resize(capacity)
	_grav.resize(capacity)
	_drag.resize(capacity)
	_kind.resize(capacity)
	_col.resize(capacity)
	_dur.fill(0.0)
	for shape in range(-1, Kind.size()):
		var tris := _shape(shape)
		var fill := PackedColorArray()
		fill.resize(tris.size())
		_tris.append(tris)
		_fills.append(fill)
	set_process(false)


## Partículas vivas ahora.
func alive_count() -> int:
	return _alive


## Una partícula. `vel` en px/s, `size` en px (radio), `dur` en segundos,
## `grav` px/s² hacia abajo, `drag` frenado (1/s), `spin` rad/s.
func emit(kind: int, pos: Vector2, vel: Vector2, size: float, dur: float, col: Color,
		grav: float = 0.0, drag: float = 0.0, spin: float = 0.0, rot: float = 0.0) -> void:
	var i := _next
	_next = (_next + 1) % capacity
	_hi = maxi(_hi, i + 1)
	if _dur[i] <= 0.0:
		_alive += 1
	_kind[i] = kind
	_pos[i] = pos
	_vel[i] = vel
	_size[i] = size
	_dur[i] = maxf(dur, 0.01)
	_age[i] = 0.0
	_col[i] = col
	_grav[i] = grav
	_drag[i] = drag
	_spin[i] = spin
	_rot[i] = rot
	if not is_processing():
		set_process(true)


## `count` partículas desde `pos` en direcciones al azar dentro de `spread`
## radianes alrededor de `dir` (Vector2.ZERO = para todos lados), con
## velocidad entre 55 % y 100 % de `speed`. Con "Reducir movimiento" sale
## una fracción (UiTheme.FX_REDUCED, al menos una).
func burst(kind: int, pos: Vector2, count: int, col: Color, speed: float, size: float, dur: float,
		dir: Vector2 = Vector2.ZERO, spread: float = TAU, grav: float = 0.0, drag: float = 3.0) -> void:
	var n := count
	if UiTheme.reduce_motion:
		n = maxi(1, roundi(count * UiTheme.FX_REDUCED))
	var base := dir.angle() if dir != Vector2.ZERO else 0.0
	for i in n:
		# Repartidas parejo con un poco de azar: no se amontonan de un lado.
		var a := base + (float(i) + rng.randf_range(0.15, 0.85)) / n * spread - spread / 2.0
		var v := Vector2.from_angle(a) * speed * rng.randf_range(0.55, 1.0)
		emit(kind, pos, v, size * rng.randf_range(0.7, 1.15), dur * rng.randf_range(0.8, 1.1), col,
			grav, drag, rng.randf_range(-7.0, 7.0), rng.randf() * TAU)


## Borra todas las partículas (ej. al reiniciar).
func clear() -> void:
	_dur.fill(0.0)
	_alive = 0
	_hi = 0
	_next = 0
	queue_redraw()


func _process(delta: float) -> void:
	if _alive <= 0:
		set_process(false)
		queue_redraw()  # Un último dibujo vacío: borra lo que quedaba.
		return
	var alive := 0
	for i in _hi:
		if _dur[i] <= 0.0:
			continue
		var age := _age[i] + delta
		if age >= _dur[i]:
			_dur[i] = 0.0
			continue
		alive += 1
		_age[i] = age
		var v := _vel[i]
		if _drag[i] > 0.0:
			v *= exp(-_drag[i] * delta)
		v.y += _grav[i] * delta
		_vel[i] = v
		_pos[i] += v * delta
		_rot[i] += _spin[i] * delta
	_alive = alive
	if alive == 0:  # Todas libres: el próximo estallido arranca de 0.
		_hi = 0
		_next = 0
	queue_redraw()


func _draw() -> void:
	if _alive <= 0:
		return
	_pts.clear()
	_cols.clear()
	for i in _hi:
		if _dur[i] <= 0.0:
			continue
		var k := _age[i] / _dur[i]
		var s := _size[i]
		var col := _col[i]
		var p := _pos[i]
		match _kind[i]:
			Kind.STAR:
				# Aparece rápido (15 % de su vida) y después se achica.
				var grow := k / 0.15 if k < 0.15 else 1.0 - (k - 0.15) / 0.85
				s *= grow
				_add(-1, Transform2D(_rot[i], Vector2(s, s) * 1.35, 0.0, p), Color(UiTheme.INK, col.a * 0.85))
				_add(Kind.STAR, Transform2D(_rot[i], Vector2(s, s), 0.0, p), col)
			Kind.SPARK:
				var v := _vel[i]
				var along := s * (1.0 + v.length() / 160.0) * (1.0 - k)
				_add(Kind.SPARK, Transform2D(v.angle(), Vector2(along, s * 0.4 * (1.0 - k)), 0.0, p), col)
			Kind.DOT:
				var r := s * (1.0 - k)
				_add(Kind.DOT, Transform2D(0.0, Vector2(r, r), 0.0, p), col)
			Kind.PUFF:
				var r := s * (0.6 + 0.8 * k)
				_add(Kind.DOT, Transform2D(0.0, Vector2(r, r * 0.8), 0.0, p), Color(col, col.a * (1.0 - k)))
			Kind.CONFETTI:
				# El papelito "da vueltas": se aplasta en un eje con el giro.
				var flip := cos(_rot[i] * 1.7)
				var fade := clampf((1.0 - k) / 0.25, 0.0, 1.0)
				_add(Kind.CONFETTI, Transform2D(_rot[i], Vector2(s, s * 0.6 * maxf(absf(flip), 0.15)), 0.0, p), Color(col, col.a * fade))
			Kind.RING:
				var e := 1.0 - (1.0 - k) * (1.0 - k)
				var r := lerpf(s * 0.3, s, e)
				_add(Kind.RING, Transform2D(0.0, Vector2(r, r), 0.0, p), Color(col, col.a * (1.0 - k)))
	if not _pts.is_empty():
		RenderingServer.canvas_item_add_triangle_array(get_canvas_item(), PackedInt32Array(), _pts, _cols)


func _add(shape: int, xform: Transform2D, col: Color) -> void:
	_pts.append_array(xform * _tris[shape + 1])
	var fill := _fills[shape + 1]
	fill.fill(col)
	_cols.append_array(fill)


## Triángulos de cada forma, de radio 1 y centrados en (0, 0). Se arman una
## vez por proceso.
static func _shape(shape: int) -> PackedVector2Array:
	if _shapes.has(shape):
		return _shapes[shape]
	var tris := PackedVector2Array()
	match shape:
		Kind.STAR, -1:
			var pts := UiTheme.star_points(Vector2.ZERO, 1.0, 0.5 if shape == -1 else 0.46)
			for i in 10:
				tris.append_array([Vector2.ZERO, pts[i], pts[(i + 1) % 10]])
		Kind.SPARK:
			# Rombo alargado sobre el eje x (se estira con la velocidad).
			tris.append_array([Vector2(-1, 0), Vector2(0, -1), Vector2(1, 0), Vector2(-1, 0), Vector2(1, 0), Vector2(0, 1)])
		Kind.DOT:
			const SEGS := 12
			for i in SEGS:
				tris.append_array([Vector2.ZERO, Vector2.from_angle(TAU * i / SEGS), Vector2.from_angle(TAU * (i + 1) / SEGS)])
		Kind.CONFETTI:
			tris.append_array([Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, -1), Vector2(1, 1), Vector2(-1, 1)])
		Kind.RING:
			const SEGS := 28
			const INNER := 0.8
			for i in SEGS:
				var a := Vector2.from_angle(TAU * i / SEGS)
				var b := Vector2.from_angle(TAU * (i + 1) / SEGS)
				tris.append_array([a * INNER, a, b, a * INNER, b, b * INNER])
	_shapes[shape] = tris
	return tris
