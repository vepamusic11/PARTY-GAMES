class_name Confetti
extends Control
## Fiesta para el podio final: papelitos que giran en 3D, estrellas,
## serpentinas que ondean, puntitos y destellos que titilan. `burst()` arranca
## con dos cañonazos desde las esquinas de abajo y una lluvia desde arriba;
## después cada pieza que sale por abajo vuelve a entrar por arriba.
##
## Rendimiento: TODAS las piezas van en un solo triangle array por frame (un
## draw call; antes era uno por papelito). Cada tipo tiene una plantilla de
## puntos hecha una vez (las serpentinas, una por cuadro de su ondeo) y en
## cada frame solo se transforma con `Transform2D * PackedVector2Array` (en
## C++). Los índices y colores de cada pieza se arman una vez en `burst()`.

const PIECES := 110
const GRAVITY := 900.0
## Tipos de pieza. Cada lugar del arreglo tiene siempre el mismo tipo (se
## recicla igual), así índices y colores no cambian entre frames.
enum Kind { PAPER, STAR, STREAMER, DOT, SPARKLE }
const PATTERN: Array[Kind] = [Kind.PAPER, Kind.PAPER, Kind.STAR, Kind.PAPER, Kind.STREAMER,
	Kind.PAPER, Kind.DOT, Kind.PAPER, Kind.SPARKLE, Kind.PAPER, Kind.STREAMER, Kind.STAR]
const STREAMER_FRAMES := 16
const STREAMER_SEGMENTS := 7

static var _templates: Dictionary = {}   # Kind -> PackedVector2Array (tamaño 1)
static var _streamer: Array[PackedVector2Array] = []
static var _local_indices: Dictionary = {}  # Kind -> PackedInt32Array

var _rng := RandomNumberGenerator.new()
var _kind := PackedInt32Array()
var _pos := PackedVector2Array()
var _vel := PackedVector2Array()
var _rot := PackedFloat32Array()
var _spin := PackedFloat32Array()
var _flip := PackedFloat32Array()      # fase del giro 3D / del ondeo / del titilar
var _drag := PackedFloat32Array()      # freno del aire: velocidad final = GRAVITY / drag
var _size := PackedVector2Array()
var _colors: Array[PackedColorArray] = []   # por pieza: colores de sus vértices
var _backs: Array[PackedColorArray] = []    # papelitos: el dorso (más oscuro)
var _indices := PackedInt32Array()


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_rng.seed = 11
	_build_templates()


func burst() -> void:
	_kind.resize(PIECES)
	_pos.resize(PIECES)
	_vel.resize(PIECES)
	_rot.resize(PIECES)
	_spin.resize(PIECES)
	_flip.resize(PIECES)
	_drag.resize(PIECES)
	_size.resize(PIECES)
	_colors.clear()
	_backs.clear()
	_indices = PackedInt32Array()
	var base := 0
	for i in PIECES:
		var kind := PATTERN[i % PATTERN.size()]
		_kind[i] = kind
		var c: Color = UiTheme.BRICKS[_rng.randi() % UiTheme.BRICKS.size()]
		if kind == Kind.STAR:
			c = UiTheme.GOLD if _rng.randf() < 0.6 else c
		_colors.append(_vertex_colors(kind, c, false))
		_backs.append(_vertex_colors(kind, c, true))
		var local: PackedInt32Array = _local_indices[kind]
		for idx in local:
			_indices.append(idx + base)
		base += _vertex_count(kind)
		# La mitad sale de los cañones de abajo; el resto llueve desde arriba.
		if i % 2 == 0:
			_spawn(i, Vector2.ZERO)
			var left := i % 4 == 0
			_pos[i] = Vector2(-20.0 if left else size.x + 20.0, size.y + 20.0)
			var dir_x := 1.0 if left else -1.0
			_vel[i] = Vector2(dir_x * _rng.randf_range(400.0, 2400.0), -_rng.randf_range(2000.0, 4200.0))
		else:
			_spawn(i, Vector2(_rng.randf_range(0, maxf(size.x, 1.0)), _rng.randf_range(-size.y, 0.0)))


## Pieza nueva (o reciclada) en `p`, cayendo.
func _spawn(i: int, p: Vector2) -> void:
	var kind := _kind[i]
	_pos[i] = p
	var fall := _rng.randf_range(170.0, 320.0)
	match kind:
		Kind.STREAMER:
			fall = _rng.randf_range(120.0, 190.0)
			_size[i] = Vector2(_rng.randf_range(8.0, 11.0), _rng.randf_range(70.0, 110.0))
		Kind.STAR:
			_size[i] = Vector2.ONE * _rng.randf_range(12.0, 20.0)
		Kind.DOT:
			_size[i] = Vector2.ONE * _rng.randf_range(5.0, 8.0)
		Kind.SPARKLE:
			fall = _rng.randf_range(90.0, 150.0)
			_size[i] = Vector2.ONE * _rng.randf_range(14.0, 24.0)
		_:
			_size[i] = Vector2(_rng.randf_range(10, 18), _rng.randf_range(16, 28))
	_drag[i] = GRAVITY / fall
	_vel[i] = Vector2(_rng.randf_range(-40, 40), fall)
	_rot[i] = _rng.randf_range(0, TAU)
	_spin[i] = _rng.randf_range(-6, 6) if kind != Kind.STREAMER else _rng.randf_range(-1.5, 1.5)
	_flip[i] = _rng.randf_range(0, TAU)


func _process(delta: float) -> void:
	# is_visible_in_tree: con el podio oculto (su padre) tampoco anima.
	if _pos.is_empty() or not is_visible_in_tree():
		return
	var limit := size.y + 60.0
	for i in PIECES:
		var v := _vel[i]
		v.y += GRAVITY * delta
		v -= v * minf(_drag[i] * delta, 1.0)
		_vel[i] = v
		_pos[i] += v * delta + Vector2(sin(_rot[i]) * 30.0 * delta, 0)
		_rot[i] += _spin[i] * delta
		_flip[i] += delta * (4.0 if _kind[i] != Kind.STREAMER else 7.0)
		if _pos[i].y > limit and v.y > 0.0:
			_spawn(i, Vector2(_rng.randf_range(0, maxf(size.x, 1.0)), -40.0))
	queue_redraw()


func _draw() -> void:
	if _pos.is_empty():
		return
	var pts := PackedVector2Array()
	var cols := PackedColorArray()
	var paper: PackedVector2Array = _templates[Kind.PAPER]
	var star: PackedVector2Array = _templates[Kind.STAR]
	var dot: PackedVector2Array = _templates[Kind.DOT]
	var sparkle: PackedVector2Array = _templates[Kind.SPARKLE]
	for i in PIECES:
		var s := _size[i]
		match _kind[i]:
			Kind.PAPER:
				# El "giro" en 3D se simula achicando el ancho con el coseno;
				# de dorso se ve más oscuro.
				var c := cos(_flip[i])
				pts.append_array(Transform2D(_rot[i] * 0.3, Vector2(maxf(s.x * absf(c), 2.0), s.y), 0.0, _pos[i]) * paper)
				cols.append_array(_colors[i] if c >= 0.0 else _backs[i])
				continue
			Kind.STAR:
				pts.append_array(Transform2D(_rot[i], Vector2(s.x * maxf(absf(cos(_flip[i] * 0.5)), 0.25), s.y), 0.0, _pos[i]) * star)
			Kind.STREAMER:
				var frame := int(_flip[i] / TAU * STREAMER_FRAMES) % STREAMER_FRAMES
				pts.append_array(Transform2D(_rot[i] * 0.5, s, 0.0, _pos[i]) * _streamer[frame])
			Kind.DOT:
				pts.append_array(Transform2D(0.0, s, 0.0, _pos[i]) * dot)
			Kind.SPARKLE:
				var k := absf(sin(_flip[i] * 0.8))
				pts.append_array(Transform2D(_rot[i] * 0.2, s * (0.25 + 0.75 * k), 0.0, _pos[i]) * sparkle)
		cols.append_array(_colors[i])
	RenderingServer.canvas_item_add_triangle_array(get_canvas_item(), _indices, pts, cols)


# --- Plantillas (una vez por proceso) ---------------------------------------------

static func _vertex_count(kind: int) -> int:
	return (_templates[kind] as PackedVector2Array).size() if kind != Kind.STREAMER else _streamer[0].size()


## Colores por vértice: el centro de estrellas, puntos y destellos va más
## claro (brillo); las serpentinas alternan tono en cada tramo (se ve el giro).
func _vertex_colors(kind: int, c: Color, back: bool) -> PackedColorArray:
	var out := PackedColorArray()
	var n := _vertex_count(kind)
	out.resize(n)
	match kind:
		Kind.PAPER:
			out.fill(c.darkened(0.3) if back else c)
		Kind.STREAMER:
			for v in n:
				out[v] = c if (v / 2) % 2 == 0 else c.darkened(0.2)
		Kind.SPARKLE:
			out.fill(Color(UiTheme.BG_SPARKLE, 0.0))
			for v in n - 1:
				out[v] = Color(UiTheme.BG_SPARKLE, 0.9) if v % 2 == 0 else Color(UiTheme.PAPER, 0.9)
			out[n - 1] = UiTheme.PAPER
		_:
			out.fill(c)
			out[n - 1] = c.lightened(0.5)  # Centro.
	return out


static func _build_templates() -> void:
	if not _templates.is_empty():
		return
	_templates[Kind.PAPER] = PackedVector2Array([Vector2(-0.5, -0.5), Vector2(0.5, -0.5), Vector2(0.5, 0.5), Vector2(-0.5, 0.5)])
	_local_indices[Kind.PAPER] = PackedInt32Array([0, 1, 2, 0, 2, 3])
	# Estrella de 5 puntas y destello de 4, con el centro al final (abanico).
	var star := UiTheme.star_points(Vector2.ZERO, 1.0, 0.48)
	star.append(Vector2.ZERO)
	_templates[Kind.STAR] = star
	_local_indices[Kind.STAR] = _fan(10)
	var sparkle := PackedVector2Array()
	for k in 8:
		var a := -PI / 2.0 + PI / 4.0 * k
		sparkle.append(Vector2(cos(a), sin(a)) * (1.0 if k % 2 == 0 else 0.22))
	sparkle.append(Vector2.ZERO)
	_templates[Kind.SPARKLE] = sparkle
	_local_indices[Kind.SPARKLE] = _fan(8)
	_templates[Kind.DOT] = _with_center(UiTheme.ellipse_points(Vector2.ZERO, 1.0, 1.0, 0.0, 12))
	_local_indices[Kind.DOT] = _fan(12)
	# Serpentina: cinta que ondea. Un cuadro por fase del ondeo; ancho 1 y
	# largo 1 (se escalan con el tamaño de la pieza).
	for f in STREAMER_FRAMES:
		var phase := TAU * f / STREAMER_FRAMES
		var pts := PackedVector2Array()
		for j in STREAMER_SEGMENTS + 1:
			var y := float(j) / STREAMER_SEGMENTS - 0.5
			var x := sin(phase + j * 0.95) * 1.6
			var half := 0.5 * (0.35 + 0.65 * absf(cos(phase + j * 0.95)))  # la cinta se tuerce
			pts.append(Vector2(x - half, y))
			pts.append(Vector2(x + half, y))
		_streamer.append(pts)
	var strip := PackedInt32Array()
	for j in STREAMER_SEGMENTS:
		var a := j * 2
		strip.append_array([a, a + 1, a + 2, a + 1, a + 3, a + 2])
	_local_indices[Kind.STREAMER] = strip


static func _with_center(ring: PackedVector2Array) -> PackedVector2Array:
	ring.append(Vector2.ZERO)
	return ring


## Abanico desde el centro (último punto) para `n` puntos de borde.
static func _fan(n: int) -> PackedInt32Array:
	var out := PackedInt32Array()
	for i in n:
		out.append_array([n, i, (i + 1) % n])
	return out
