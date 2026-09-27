class_name Transition
extends Control
## Barrido entre pantallas: filas de bloques de colores (los de
## `UiTheme.BRICKS`, con volumen y brillo) entran por la izquierda con una
## estrella en la punta, tapan la pantalla y siguen de largo por la derecha.
## Con todo tapado aparece un instante una estrella grande en el centro. El
## cambio de pantalla ocurre en el medio, cuando todo está tapado, así nunca
## se ve un "salto" de una pantalla a otra.
##
##   t = 0      0,21 s (tapado)      0,42 s
##   ▓▓░░░░      ▓▓▓▓▓▓               ░░░░▓▓
##   ▓░░░░░  ->  ▓▓★▓▓▓  ->  cambio   ░░░░░▓
##
## Uso: `play(callable)`. El callable corre al quedar tapada la pantalla.
## Reglas que garantiza:
##   - **Orden**: los cambios pedidos se ejecutan en el mismo orden en que se
##     pidieron (lobby -> intro -> juego -> resumen -> podio), aunque lleguen
##     varios durante el mismo barrido.
##   - **Input**: mientras corre se tragan las teclas del control remoto (un
##     OK doble no dispara dos acciones), pero nunca más de lo que dura.
##   - Con `duration = 0` el cambio es inmediato (tests).
##
## Rendimiento: cada fila es un nodo hijo que se dibuja UNA vez (un lote de
## figuras, un draw call) y se redibuja solo si cambia el tamaño; durante el
## barrido solo se mueve su `position.x`. La estrella del centro, igual.

signal covered
signal finished

const DURATION := 0.42   ## Segundos del barrido completo (tapar + destapar).
const ROWS := 8
const BRICK_W := 240.0
const STAGGER := 0.12    ## Retraso de la última fila, en fracción del barrido: forma la diagonal.
const GAP := 4.0         ## Separación entre bloques (se ve la "tinta" de fondo).
const TRAIL := 90.0      ## Largo de la estela de luz en las puntas de cada fila.

var duration := DURATION

var _t := 0.0
var _running := false
var _covered := false
var _flushing := false
var _pending: Array[Callable] = []
var _rows: Array[Control] = []
var _emblem: Node2D


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	process_mode = Node.PROCESS_MODE_ALWAYS
	z_index = 30  # Encima de todas las pantallas, incluso del menú de pausa.
	visible = false
	for row in ROWS:
		var strip := Control.new()
		strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		strip.draw.connect(_draw_row.bind(strip, row))
		add_child(strip)
		_rows.append(strip)
	_emblem = Node2D.new()
	_emblem.draw.connect(_draw_emblem)
	add_child(_emblem)
	resized.connect(_on_resized)
	_on_resized()


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
		_place()


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
		_place()


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


# --- Movimiento -------------------------------------------------------------------

## Posición horizontal de la fila `row`: de afuera a la izquierda a 0
## (tapando) y de ahí a afuera por la derecha.
func _row_offset(row: int) -> float:
	var delay := STAGGER * float(row) / float(ROWS - 1)
	var span := 0.5 - STAGGER
	if _t < 0.5:
		var k := _ease(clampf((_t - delay) / span, 0.0, 1.0))
		return -(_length() + TRAIL + 60.0) * (1.0 - k)
	var k2 := _ease(clampf((_t - 0.5 - delay) / span, 0.0, 1.0))
	return (size.x + BRICK_W / 2.0 + TRAIL) * k2


static func _ease(x: float) -> float:
	return x * x * (3.0 - 2.0 * x)  # smoothstep: arranca y frena suave.


## Mueve las filas y la estrella del centro (sin redibujar nada).
func _place() -> void:
	for row in ROWS:
		# Las filas impares van corridas medio bloque, como una pared.
		var shift := BRICK_W / 2.0 if row % 2 == 1 else 0.0
		_rows[row].position = Vector2(_row_offset(row) - shift, row * size.y / ROWS)
	# Estrella: aparece mientras todo está tapado (t ≈ 0,32 … 0,68).
	var k := clampf((_t - 0.32) / 0.36, 0.0, 1.0)
	var pop := sin(k * PI)
	_emblem.visible = pop > 0.01
	_emblem.position = size / 2.0
	_emblem.scale = Vector2.ONE * (0.35 + 0.75 * pop)
	_emblem.rotation = (k - 0.5) * 1.2


## Largo de cada fila: bloques enteros (sin uno cortado en la punta) y
## medio bloque de más para las filas corridas.
func _length() -> float:
	return ceilf((size.x + BRICK_W * 1.5) / BRICK_W) * BRICK_W


func _on_resized() -> void:
	for strip in _rows:
		strip.size = Vector2(_length(), size.y / ROWS)
		strip.queue_redraw()
	_emblem.queue_redraw()


# --- Dibujo (una vez por fila) ----------------------------------------------------

func _draw_row(strip: Control, row: int) -> void:
	var row_h := size.y / ROWS
	var length := _length()
	var batch := UiTheme.ShapeBatch.new()
	# Estelas de luz en las dos puntas (la de adelante al entrar, la de atrás al salir).
	var glow: Color = UiTheme.BRICKS[(row * 3) % UiTheme.BRICKS.size()].lightened(0.3)
	strip.draw_polygon(PackedVector2Array([Vector2(-TRAIL, 0), Vector2(0, 0), Vector2(0, row_h), Vector2(-TRAIL, row_h)]),
		PackedColorArray([Color(glow, 0.0), Color(glow, 0.8), Color(glow, 0.8), Color(glow, 0.0)]))
	strip.draw_polygon(PackedVector2Array([Vector2(length, 0), Vector2(length + TRAIL, 0), Vector2(length + TRAIL, row_h), Vector2(length, row_h)]),
		PackedColorArray([Color(glow, 0.8), Color(glow, 0.0), Color(glow, 0.0), Color(glow, 0.8)]))
	batch.polygon(PackedVector2Array([Vector2.ZERO, Vector2(length, 0), Vector2(length, row_h), Vector2(0, row_h)]), UiTheme.INK)
	var i := 0
	var bx := 0.0
	var stud_r := row_h * 0.12
	while bx < length:
		var c: Color = UiTheme.BRICKS[(i + row * 3) % UiTheme.BRICKS.size()]
		var r := Rect2(bx + GAP / 2.0, GAP / 2.0, BRICK_W - GAP, row_h - GAP)
		batch.polygon(UiTheme.round_rect_points(r, 12.0), c.darkened(0.22))
		var face := Rect2(r.position, r.size - Vector2(0, 10))
		batch.polygon(UiTheme.round_rect_points(face, 12.0), c)
		var shine := Rect2(face.position + Vector2(14, 7), Vector2(face.size.x - 28, 9))
		batch.polygon(UiTheme.round_rect_points(shine, 4.5, 2), Color(1, 1, 1, 0.3))
		for k in 2:
			var stud := Vector2(r.position.x + r.size.x * (0.3 + 0.4 * k), r.position.y + r.size.y * 0.42)
			batch.circle(stud + Vector2(0, 4), stud_r, c.darkened(0.15))
			batch.circle(stud, stud_r, c.lightened(0.28))
			batch.circle(stud - Vector2(stud_r, stud_r) * 0.35, stud_r * 0.3, Color(1, 1, 1, 0.55))
		bx += BRICK_W
		i += 1
	# Estrellas en las puntas de la fila.
	for x in [length + 6.0, -6.0]:
		var p := Vector2(x, row_h / 2.0)
		var rs := row_h * 0.3
		batch.star(UiTheme.star_points(p, rs + 5.0, 0.5, row * 0.4), p, UiTheme.INK)
		batch.star(UiTheme.star_points(p, rs, 0.48, row * 0.4), p, UiTheme.GOLD)
		var hl := p - Vector2(rs, rs) * 0.12
		batch.star(UiTheme.star_points(hl, rs * 0.35, 0.5, row * 0.4), hl, Color(1, 1, 1, 0.55))
	batch.flush(strip)


func _draw_emblem() -> void:
	var r := minf(size.x, size.y) * 0.09
	UiTheme.draw_radial(_emblem, Vector2.ZERO, r * 2.2, Color(UiTheme.GOLD, 0.55), Color(UiTheme.GOLD, 0.0))
	UiTheme.draw_star(_emblem, Vector2.ZERO, r, UiTheme.GOLD)
