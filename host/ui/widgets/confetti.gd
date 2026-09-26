class_name Confetti
extends Control
## Lluvia de papelitos para el podio final. Se dibuja por código y se
## recicla: cada papelito que sale por abajo vuelve a entrar por arriba.

const PIECES := 110

var _pieces: Array[Dictionary] = []
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_rng.seed = 11


func burst() -> void:
	_pieces.clear()
	for i in PIECES:
		_pieces.append(_new_piece(_rng.randf_range(-size.y, 0.0)))


func _new_piece(y: float) -> Dictionary:
	return {
		"pos": Vector2(_rng.randf_range(0, maxf(size.x, 1.0)), y),
		"vel": Vector2(_rng.randf_range(-40, 40), _rng.randf_range(160, 320)),
		"rot": _rng.randf_range(0, TAU),
		"spin": _rng.randf_range(-6, 6),
		"size": Vector2(_rng.randf_range(10, 18), _rng.randf_range(16, 28)),
		"color": UiTheme.BRICKS[_rng.randi() % UiTheme.BRICKS.size()],
	}


func _process(delta: float) -> void:
	# is_visible_in_tree: con el podio oculto (su padre) tampoco anima.
	if _pieces.is_empty() or not is_visible_in_tree():
		return
	for i in _pieces.size():
		var p := _pieces[i]
		p.pos += p.vel * delta + Vector2(sin(p.rot) * 30.0 * delta, 0)
		p.rot += p.spin * delta
		if p.pos.y > size.y + 30:
			_pieces[i] = _new_piece(-30.0)
	queue_redraw()


func _draw() -> void:
	for p in _pieces:
		var s: Vector2 = p.size
		# El "giro" en 3D se simula achicando el ancho con el coseno.
		var w := s.x * absf(cos(p.rot))
		draw_set_transform(p.pos, p.rot * 0.3, Vector2.ONE)
		draw_rect(Rect2(-w / 2.0, -s.y / 2.0, maxf(w, 2.0), s.y), p.color)
	draw_set_transform(Vector2.ZERO)
