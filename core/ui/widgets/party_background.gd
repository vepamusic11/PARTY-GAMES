class_name PartyBackground
extends Control
## Fondo "de fiesta": cielo en degradé con nubes que se mueven lento,
## torres de bloques de colores al fondo, piso a cuadros y un borde de
## bloques arriba y abajo. Cada capa se puede apagar (el celular usa solo
## el cielo para no distraer del control).
##
## Todo se dibuja por código: sin texturas que importar ni escalar, y se
## ve nítido en cualquier resolución (720p, 1080p o 4K).
##
## Rendimiento: solo las nubes se mueven. Este nodo dibuja cielo + nubes en
## cada frame; torres, piso y bordes (cientos de bloques) van en una capa
## hija (`_front`) que se dibuja una sola vez y de nuevo solo si cambia el
## tamaño o las capas. Godot reutiliza lo que ya dibujó un CanvasItem
## mientras no se llame a queue_redraw(): la capa estática no gasta CPU.
## Quedan en el mismo orden que antes (cielo, nubes, torres, piso, bordes)
## porque los hijos se dibujan después que el padre.

@export var bricks := true:
	set(v):
		bricks = v
		_refresh_front()
@export var towers := true:
	set(v):
		towers = v
		_refresh_front()
@export var checker_floor := true:
	set(v):
		checker_floor = v
		_refresh_front()
## Cuadros por segundo de la animación de las nubes. 0 = en cada frame (TV).
## El celular lo baja mientras espera para gastar menos batería (ver
## ControllerMain): con el modo de bajo consumo de Godot, si nada pide
## redibujar, no se dibuja el frame.
var anim_fps := 0.0

const BRICK_H := 34.0
const BRICK_W := 96.0
const TOWER_BLOCK := 54.0

var _t := 0.0
var _clouds: Array[Vector3] = []   # x (0..1), y (0..1), escala
var _towers: Array[Vector2i] = []  # (columna, altura en bloques)
var _front: Control                # capa estática: torres, piso y bordes
var _anim_slot := -1


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7  # Siempre el mismo paisaje: la TV no "parpadea" entre pantallas.
	for i in 7:
		_clouds.append(Vector3(i / 7.0 + rng.randf_range(0.0, 0.08), rng.randf_range(0.08, 0.45), rng.randf_range(0.7, 1.4)))
	var col := 0
	while col < 44:
		_towers.append(Vector2i(col, rng.randi_range(2, 7)))
		col += rng.randi_range(1, 3)
	_front = Control.new()
	_front.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_front.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_front.draw.connect(_draw_front)
	add_child(_front)
	resized.connect(_refresh_front)
	_refresh_front()
	set_process(is_visible_in_tree())


func _notification(what: int) -> void:
	# Oculto (ej. durante un minijuego) no anima: no gasta CPU en cada frame.
	if what == NOTIFICATION_VISIBILITY_CHANGED and is_inside_tree():
		set_process(is_visible_in_tree())


func _process(delta: float) -> void:
	_t += delta
	if anim_fps <= 0.0:
		queue_redraw()
		return
	# Reloj común (no _t): varios nodos con el mismo anim_fps se redibujan en
	# el mismo frame, así el celular dibuja pocas veces por segundo.
	var slot := int(Time.get_ticks_msec() * anim_fps / 1000.0)
	if slot != _anim_slot:
		_anim_slot = slot
		queue_redraw()


func _draw() -> void:
	var s := size
	draw_polygon(PackedVector2Array([Vector2.ZERO, Vector2(s.x, 0), s, Vector2(0, s.y)]),
		PackedColorArray([UiTheme.SKY_TOP, UiTheme.SKY_TOP, UiTheme.SKY_BOTTOM, UiTheme.SKY_BOTTOM]))
	for c in _clouds:
		var x := fposmod(c.x * (s.x + 500.0) + _t * 14.0 * c.z, s.x + 500.0) - 250.0
		_draw_cloud(Vector2(x, c.y * s.y), 60.0 * c.z)


## Pide redibujar la capa estática (tamaño o capas distintas).
func _refresh_front() -> void:
	if _front == null:
		return
	_front.visible = towers or checker_floor or bricks
	_front.queue_redraw()


## Capa estática: se dibuja sobre `_front`, que tiene el mismo tamaño.
func _draw_front() -> void:
	var floor_y := size.y * 0.84
	if towers:
		_draw_towers(_front, floor_y)
	if checker_floor:
		_draw_floor(_front, floor_y)
	if bricks:
		_draw_brick_row(_front, 0.0)
		_draw_brick_row(_front, size.y - BRICK_H)


## Los 5 círculos de cada nube van en un lote (un draw call en vez de cinco).
func _draw_cloud(p: Vector2, r: float) -> void:
	var white := Color(1, 1, 1, 0.92)
	var batch := UiTheme.ShapeBatch.new()
	batch.circle(p + Vector2(0, r * 0.1), r * 0.8, Color(1, 1, 1, 0.25))
	for o in [Vector2(-r * 0.9, r * 0.2), Vector2(-r * 0.3, -r * 0.25), Vector2(r * 0.4, -r * 0.1), Vector2(r * 1.0, r * 0.25)]:
		batch.circle(p + o, r * (0.55 if absf(o.x) > r * 0.5 else 0.72), white)
	batch.flush(self)
	UiTheme.draw_round_rect(self, Rect2(p.x - r * 1.4, p.y, r * 2.8, r * 0.7), white, r * 0.35)


func _draw_towers(ci: CanvasItem, floor_y: float) -> void:
	for t in _towers:
		var x := t.x * TOWER_BLOCK
		if x > size.x:
			break
		for j in t.y:
			var c: Color = UiTheme.BRICKS[(t.x * 3 + j) % UiTheme.BRICKS.size()]
			var r := Rect2(x, floor_y - (j + 1) * TOWER_BLOCK, TOWER_BLOCK - 3.0, TOWER_BLOCK - 3.0)
			UiTheme.draw_round_rect(ci, r, Color(c.lerp(UiTheme.SKY_BOTTOM, 0.35), 0.8), 8)


func _draw_floor(ci: CanvasItem, floor_y: float) -> void:
	var cell := 80.0
	ci.draw_rect(Rect2(0, floor_y, size.x, size.y - floor_y), UiTheme.FLOOR)
	var row := 0
	var y := floor_y
	while y < size.y:
		var x := -cell if row % 2 == 0 else 0.0
		while x < size.x:
			ci.draw_rect(Rect2(x, y, cell, cell), UiTheme.FLOOR_TILE)
			x += cell * 2.0
		y += cell
		row += 1
	ci.draw_rect(Rect2(0, floor_y, size.x, 6), Color(UiTheme.INK, 0.12))


## Los botones de los bloques van todos en un lote al final de la fila: no
## se tocan con los bloques vecinos, así que el orden no cambia nada.
func _draw_brick_row(ci: CanvasItem, y: float) -> void:
	var studs := UiTheme.ShapeBatch.new()
	var i := 0
	var x := 0.0
	while x < size.x:
		var c: Color = UiTheme.BRICKS[i % UiTheme.BRICKS.size()]
		var r := Rect2(x + 1.0, y + 1.0, BRICK_W - 2.0, BRICK_H - 2.0)
		UiTheme.draw_round_rect(ci, r, c.darkened(0.2), 7)
		UiTheme.draw_round_rect(ci, Rect2(r.position, r.size - Vector2(0, 5)), c, 7)
		for k in 2:
			var stud := Vector2(r.position.x + r.size.x * (0.3 + 0.4 * k), r.position.y + r.size.y * 0.42)
			studs.circle(stud, 7.0, c.lightened(0.28))
		x += BRICK_W
		i += 1
	studs.flush(ci)
