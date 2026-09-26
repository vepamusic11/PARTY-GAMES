class_name Transition
extends Control
## Barrido entre pantallas: filas de bloques de colores (los de
## `UiTheme.BRICKS`) entran por la izquierda, tapan la pantalla y siguen de
## largo por la derecha. El cambio de pantalla ocurre en el medio, cuando
## todo está tapado, así nunca se ve un "salto" de una pantalla a otra.
##
##   t = 0      0,21 s (tapado)      0,42 s
##   ▓▓░░░░      ▓▓▓▓▓▓               ░░░░▓▓
##   ▓░░░░░  ->  ▓▓▓▓▓▓  ->  cambio   ░░░░░▓
##
## Uso: `play(callable)`. El callable corre al quedar tapada la pantalla.
## Reglas que garantiza:
##   - **Orden**: los cambios pedidos se ejecutan en el mismo orden en que se
##     pidieron (lobby -> intro -> juego -> resumen -> podio), aunque lleguen
##     varios durante el mismo barrido.
##   - **Input**: mientras corre se tragan las teclas del control remoto (un
##     OK doble no dispara dos acciones), pero nunca más de lo que dura.
##   - Con `duration = 0` el cambio es inmediato (tests).

signal covered
signal finished

const DURATION := 0.42   ## Segundos del barrido completo (tapar + destapar).
const ROWS := 8
const BRICK_W := 240.0
const STAGGER := 0.12    ## Retraso de la última fila, en fracción del barrido: forma la diagonal.
const GAP := 4.0         ## Separación entre bloques (se ve la "tinta" de fondo).

var duration := DURATION

var _t := 0.0
var _running := false
var _covered := false
var _flushing := false
var _pending: Array[Callable] = []


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	process_mode = Node.PROCESS_MODE_ALWAYS
	z_index = 30  # Encima de todas las pantallas, incluso del menú de pausa.
	visible = false


## Pide un cambio de pantalla. `on_covered` corre cuando la pantalla queda
## tapada (o enseguida si `duration` es 0).
func play(on_covered: Callable = Callable()) -> void:
	Sfx.play("whoosh")
	if on_covered.is_valid():
		_pending.append(on_covered)
	if _flushing:
		return  # Se ejecuta en esta misma pasada, después de los anteriores.
	if duration <= 0.0 or not is_inside_tree():
		_flush()
		return
	if _running and _covered:
		# Ya se está destapando: el cambio va enseguida (los anteriores ya
		# corrieron, así que el orden se respeta).
		_flush()
		return
	if not _running:
		_t = 0.0
		_covered = false
		_running = true
		visible = true
		mouse_filter = Control.MOUSE_FILTER_STOP


func is_running() -> bool:
	return _running


## Termina el barrido ya: ejecuta lo pendiente y desaparece. Para tests y
## capturas que no quieren esperar.
func finish_now() -> void:
	_flush()
	_stop()


func _process(delta: float) -> void:
	if not _running:
		return
	_t += delta / maxf(duration, 0.001)
	if not _covered and _t >= 0.5:
		_covered = true
		_flush()
		covered.emit()
	if _t >= 1.0:
		_stop()
	else:
		queue_redraw()


func _input(event: InputEvent) -> void:
	if _running and not (event is InputEventMouseMotion):
		get_viewport().set_input_as_handled()


func _flush() -> void:
	if _flushing:
		return
	_flushing = true
	while not _pending.is_empty():
		var fn: Callable = _pending.pop_front()
		if fn.is_valid():
			fn.call()
	_flushing = false


func _stop() -> void:
	var was_running := _running
	_running = false
	_covered = false
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if was_running:
		finished.emit()


# --- Dibujo ---------------------------------------------------------------------

## Posición horizontal de la fila `row`: de afuera a la izquierda a 0
## (tapando) y de ahí a afuera por la derecha.
func _row_offset(row: int) -> float:
	var delay := STAGGER * float(row) / float(ROWS - 1)
	var span := 0.5 - STAGGER
	if _t < 0.5:
		var k := _ease(clampf((_t - delay) / span, 0.0, 1.0))
		return -(size.x + BRICK_W * 2.0) * (1.0 - k)
	var k2 := _ease(clampf((_t - 0.5 - delay) / span, 0.0, 1.0))
	return (size.x + BRICK_W / 2.0) * k2


static func _ease(x: float) -> float:
	return x * x * (3.0 - 2.0 * x)  # smoothstep: arranca y frena suave.


func _draw() -> void:
	if not _running:
		return
	var row_h := size.y / ROWS
	var strip_w := size.x + BRICK_W
	for row in ROWS:
		var x := _row_offset(row)
		var y := row * row_h
		# Las filas impares van corridas medio bloque, como una pared.
		var start := x - (BRICK_W / 2.0 if row % 2 == 1 else 0.0)
		draw_rect(Rect2(start, y, strip_w + BRICK_W / 2.0, row_h), UiTheme.INK)
		var i := 0
		var bx := start
		while bx < start + strip_w + BRICK_W / 2.0:
			var c: Color = UiTheme.BRICKS[(i + row * 3) % UiTheme.BRICKS.size()]
			var r := Rect2(bx + GAP / 2.0, y + GAP / 2.0, BRICK_W - GAP, row_h - GAP)
			UiTheme.draw_round_rect(self, r, c.darkened(0.2), 12)
			UiTheme.draw_round_rect(self, Rect2(r.position, r.size - Vector2(0, 10)), c, 12)
			for k in 2:
				var stud := Vector2(r.position.x + r.size.x * (0.3 + 0.4 * k), r.position.y + r.size.y * 0.4)
				draw_circle(stud, row_h * 0.12, c.lightened(0.28))
			bx += BRICK_W
			i += 1
