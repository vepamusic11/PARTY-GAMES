class_name ConfettiBurst
extends Control
## Cañonazo de papelitos del celular al ver el resultado: salen de las dos
## esquinas de abajo, suben, caen y se terminan. Dura DURATION segundos y
## después no gasta nada (se apaga _process): nada de animaciones continuas
## mientras el celular espera (ver docs/PERFORMANCE.md).

const DURATION := 2.2
const GRAVITY := 2200.0

var _pieces: Array[Dictionary] = []
var _left := 0.0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_rng.seed = 23
	set_process(false)


func burst(count: int = 60) -> void:
	_pieces.clear()
	for i in count:
		var from_left := i % 2 == 0
		var angle := deg_to_rad(_rng.randf_range(58.0, 80.0))
		var speed := _rng.randf_range(1300.0, 2100.0)
		var vel := Vector2(cos(angle) * (1.0 if from_left else -1.0), -sin(angle)) * speed
		_pieces.append({
			"pos": Vector2(0.0 if from_left else size.x, size.y + 20.0),
			"vel": vel,
			"rot": _rng.randf_range(0, TAU),
			"spin": _rng.randf_range(-9, 9),
			"size": Vector2(_rng.randf_range(14, 24), _rng.randf_range(22, 36)),
			"color": UiTheme.BRICKS[_rng.randi() % UiTheme.BRICKS.size()],
		})
	_left = DURATION
	set_process(true)


## Corta el festejo (ej. empieza otro juego).
func stop() -> void:
	if _pieces.is_empty():
		return
	_pieces.clear()
	set_process(false)
	queue_redraw()


func _process(delta: float) -> void:
	_left -= delta
	if _left <= 0.0 or not is_visible_in_tree():
		_pieces.clear()
		set_process(false)
		queue_redraw()
		return
	for p in _pieces:
		p.vel.y += GRAVITY * delta
		p.vel.x *= 1.0 - 0.8 * delta  # Aire: frena de costado.
		p.pos += p.vel * delta
		p.rot += p.spin * delta
	queue_redraw()


## Todos los papelitos en un solo lote (un comando de dibujo, no uno por papelito).
func _draw() -> void:
	if _pieces.is_empty():
		return
	var batch := UiTheme.ShapeBatch.new()
	for p in _pieces:
		var s: Vector2 = p.size
		# El "giro" en 3D se simula achicando el ancho con el coseno.
		var w := maxf(s.x * absf(cos(p.rot)), 2.0)
		batch.polygon(piece_points(p.pos, Vector2(w, s.y), p.rot * 0.3), p.color)
	batch.flush(self)


## Rectángulo `size` centrado en `center` y girado `angle` (un papelito).
static func piece_points(center: Vector2, size: Vector2, angle: float) -> PackedVector2Array:
	var x := Vector2.from_angle(angle) * size.x / 2.0
	var y := Vector2.from_angle(angle + PI / 2.0) * size.y / 2.0
	return PackedVector2Array([center - x - y, center + x - y, center + x + y, center - x + y])
