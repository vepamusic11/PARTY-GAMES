class_name BoardView25D
extends RefCounted
## Vista "2.5D horneada" de un tablero: la cámara en perspectiva del
## escenario 3D (Board25DBaker) y las cuentas para dibujar el juego en 2D
## encima, como si estuviera apoyado sobre ese tablero. Decisión: ADR 0019.
##
## La lógica de los juegos no cambia: posiciones, choques y celdas siguen en
## las coordenadas planas de siempre (ej. Paint.FIELD, 1480 × 814 px con
## baldosas de 74). Lo único que cambia es DÓNDE se dibuja cada cosa:
##   pantalla = project(punto del plano)
##
## Conceptos (con ejemplos de Pintar el piso):
## - *Cámara en perspectiva*: lo lejano se ve más chico. La cámara mira el
##   tablero desde adelante y arriba (BOARD25D_PITCH_DEG = 65° sobre el
##   piso), así la fila de arriba del tablero mide ~1360 px de ancho en
##   pantalla y la de abajo ~1590: el tablero "se aleja", como en la maqueta.
## - *Homografía*: cómo se ve un plano a través de una cámara en perspectiva.
##   Es una fórmula de 9 números que lleva cualquier punto del plano (x, y) a
##   la pantalla: ((a·x + b·y + c) / (g·x + h·y + i), (d·x + e·y + f) / (g·x + h·y + i)).
##   La división hace que lo lejano se achique. Ejemplo: el centro de la
##   baldosa (0, 0) está en (257, 209) del plano y en (309, 227) de la pantalla;
##   el de la (19, 10), en (1663, 949) del plano y en (1711, 895) de la pantalla.
##   Como el tablero es plano, la homografía es EXACTA (no una aproximación).
## - *Transformación local del piso* (`floor_xform`): cerca de un punto, la
##   homografía se parece mucho a una transformación 2D común (escala +
##   inclinación). Con eso se dibuja cualquier figura 2D "acostada" en el piso
##   (una baldosa pintada, una sombra, el marco de la brocha) con las
##   funciones de siempre y en un solo lote. Ejemplo: la baldosa pintada de
##   una fila de atrás sale ~13 % más angosta y un poco más baja que una de
##   adelante; el error en las esquinas de una baldosa es < 0,5 px.
## - *Cosas paradas* (mascotas, premios): se dibujan de frente, con los pies
##   en `project(p)` y escaladas por `scale_at(p)` (las de atrás, más chicas),
##   ordenadas de atrás hacia adelante.
##
## Todo es matemática pura: funciona igual en --headless (tests) y no
## renderiza nada. Si no hay escenario horneado, el juego dibuja plano
## (`MiniGame.draw_board_25d` devuelve false).

## Plano lógico del tablero (coordenadas del juego) y lado de cada celda.
var plane: Rect2
var cell: float
var cols: int
var rows: int
## Pantalla a la que proyecta (px lógicos de la TV).
var screen := Vector2(1920, 1080)
## Cámara (ver UiTheme, "Escenario 2.5D"): grados sobre el piso, campo de
## visión vertical (grados), distancia al punto que mira (unidades del mundo =
## px del plano) y ese punto, relativo al centro del plano (x, y del plano).
var pitch_deg: float
var fov_deg: float
var distance: float
var target := Vector2.ZERO
## Receta del escenario (colores, entorno): la usa Board25DBaker y entra en
## la firma de la caché. Ver Board25DScene.
var recipe := "board"
## Datos propios de la receta (ej. Pool: ancho de las bandas y troneras).
## Entran en la firma de la caché solo si hay alguno.
var extras: Dictionary = {}

var _cam: Transform3D
var _proj: Projection
var _world_to_screen: Projection  # Proyección * vista, con el paso a píxeles.
var _h: Basis                     # Homografía plano -> pantalla (columnas).
var _h_inv: Basis
var _cells: Array[Transform2D] = []


## Vista con la cámara de UiTheme para un tablero de cols × rows celdas de
## lado `p_cell` que ocupa `p_plane` en el plano del juego.
static func make(p_plane: Rect2, p_cell: float, p_recipe: String = "board") -> BoardView25D:
	var v := BoardView25D.new()
	v.plane = p_plane
	v.cell = p_cell
	v.cols = roundi(p_plane.size.x / p_cell)
	v.rows = roundi(p_plane.size.y / p_cell)
	v.pitch_deg = UiTheme.BOARD25D_PITCH_DEG
	v.fov_deg = UiTheme.BOARD25D_FOV_DEG
	v.distance = UiTheme.BOARD25D_DISTANCE
	v.target = UiTheme.BOARD25D_TARGET
	v.recipe = p_recipe
	v.update()
	return v


## Como `make`, pero con la cámara alejada o acercada para que el plano
## ocupe en pantalla el mismo ancho que el tablero de Pintar el piso
## (UiTheme.BOARD25D_FIT_WIDTH): así un campo más ancho (Arena, 1600 px) o
## más angosto (Pool, 1420 px) se ve encuadrado igual que la maqueta.
## Ejemplo: Arena -> distancia × 1,08 (las mascotas atrás ~0,86, adelante ~0,99).
static func make_fit(p_plane: Rect2, p_cell: float, p_recipe: String) -> BoardView25D:
	var v := make(p_plane, p_cell, p_recipe)
	v.distance = UiTheme.BOARD25D_DISTANCE * p_plane.size.x / UiTheme.BOARD25D_FIT_WIDTH
	v.update()
	return v


## Recalcula la cámara y la homografía (después de cambiar algún parámetro).
func update() -> void:
	var a := deg_to_rad(pitch_deg)
	var look := to_world(plane.get_center() + target)
	var eye := look + Vector3(0.0, sin(a), cos(a)) * distance
	_cam = Transform3D(Basis(), eye).looking_at(look, Vector3.UP)
	_proj = Projection.create_perspective(fov_deg, screen.x / screen.y, near(), far())
	# NDC (-1..1, y arriba) -> píxeles (0..ancho, y abajo).
	var to_px := Projection(Vector4(screen.x / 2.0, 0, 0, 0), Vector4(0, -screen.y / 2.0, 0, 0),
		Vector4(0, 0, 1, 0), Vector4(screen.x / 2.0, screen.y / 2.0, 0, 1))
	_world_to_screen = to_px * _proj * Projection(_cam.affine_inverse())
	# Homografía: un punto del plano (x, y) es el punto del mundo
	# x·(1,0,0) + y·(0,0,1) + origen; se proyecta cada término y se quedan
	# las filas x, y, w (la z de la pantalla no hace falta).
	var ex := _world_to_screen * Vector4(1, 0, 0, 0)
	var ez := _world_to_screen * Vector4(0, 0, 1, 0)
	var o := _world_to_screen * Vector4(-plane.get_center().x, 0, -plane.get_center().y, 1)
	_h = Basis(Vector3(ex.x, ex.y, ex.w), Vector3(ez.x, ez.y, ez.w), Vector3(o.x, o.y, o.w))
	_h_inv = _h.inverse()
	_cells.clear()


## Punto del mundo 3D (unidades = px del plano; y hacia arriba) para un punto
## del plano del juego a `height` sobre el piso. El centro del plano es el origen.
func to_world(p: Vector2, height: float = 0.0) -> Vector3:
	var c := plane.get_center()
	return Vector3(p.x - c.x, height, p.y - c.y)


## Punto del plano (coordenadas del juego) -> pantalla.
func project(p: Vector2) -> Vector2:
	var q := _h * Vector3(p.x, p.y, 1.0)
	return Vector2(q.x, q.y) / q.z


## Pantalla -> punto del plano (inversa de project).
func unproject(s: Vector2) -> Vector2:
	var q := _h_inv * Vector3(s.x, s.y, 1.0)
	return Vector2(q.x, q.y) / q.z


## Punto del mundo 3D -> pantalla (para cosas en altura: el marco, algo que salta).
func project_3d(w: Vector3) -> Vector2:
	var c := _world_to_screen * Vector4(w.x, w.y, w.z, 1.0)
	return Vector2(c.x, c.y) / c.w


## Varios puntos del plano a la vez (bordes de un área, una polilínea, o
## los vértices de triángulos armados en coordenadas del plano con un
## GameArt.TriBatch: las rectas siguen rectas, así que un triángulo proyectado
## es exacto aunque sea largo, como la guía de tiro de Pool).
func project_points(pts: PackedVector2Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	out.resize(pts.size())
	for i in pts.size():
		out[i] = project(pts[i])
	return out


## Cuánto se agranda en pantalla algo del plano en `p` (1 = como en el juego
## plano). Ejemplo: ~0,93 en la fila de atrás y ~1,07 en la de adelante.
## Para escalar lo que está parado (mascotas, premios).
func scale_at(p: Vector2) -> float:
	return floor_xform(p).x.length()


## Transformación 2D que dibuja figuras del plano (en coordenadas del juego)
## acostadas en el piso cerca de `p`: la mejor aproximación lineal de la
## homografía en ese punto (su derivada). Uso:
##   ci.draw_set_transform_matrix(view.floor_xform(p))   # y dibujar como siempre
func floor_xform(p: Vector2) -> Transform2D:
	var q := _h * Vector3(p.x, p.y, 1.0)
	var s := Vector2(q.x, q.y) / q.z
	# Derivada de (u / w) = (u' · w − u · w') / w², por columnas de la homografía.
	var dx := (Vector2(_h.x.x, _h.x.y) - s * _h.x.z) / q.z
	var dy := (Vector2(_h.y.x, _h.y.y) - s * _h.y.z) / q.z
	return Transform2D(dx, dy, s - dx * p.x - dy * p.y)


## Transformación de la celda (col, fila): lleva las coordenadas locales de
## una baldosa (0..cell, como GameArt.tile_template) a la pantalla. En caché.
func cell_xform(c: Vector2i) -> Transform2D:
	if _cells.is_empty():
		_cells.resize(cols * rows)
		for y in rows:
			for x in cols:
				var origin := plane.position + Vector2(x, y) * cell
				_cells[y * cols + x] = floor_xform(origin + Vector2.ONE * cell / 2.0) * Transform2D(0.0, origin)
	return _cells[clampi(c.y, 0, rows - 1) * cols + clampi(c.x, 0, cols - 1)]


## Punto del plano a `height` sobre el piso -> pantalla (una bola de pool
## en su centro, una estrella que flota).
func project_up(p: Vector2, height: float) -> Vector2:
	return project_3d(to_world(p, height))


## Esquinas de un rectángulo del plano en pantalla (sentido horario).
func quad(r: Rect2) -> PackedVector2Array:
	return project_points(PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]))


## Borde punteado de un rectángulo del plano, acostado en el piso (ej. el
## área de la brocha gigante). Mismo trazo que UiTheme.draw_dashed_rect.
func draw_dashed_rect(ci: CanvasItem, r: Rect2, col: Color, width: float, dash: float, gap: float) -> void:
	var q := quad(r)
	for i in 4:
		var a := q[i]
		var b := q[(i + 1) % 4]
		var length := a.distance_to(b)
		var dir := (b - a) / maxf(length, 0.001)
		var t := 0.0
		while t < length:
			ci.draw_line(a + dir * t, a + dir * minf(t + dash, length), col, width, true)
			t += dash + gap


## Datos que definen el escenario horneado: si cambia algo, se vuelve a hornear.
func signature_parts() -> Array:
	var parts: Array = [plane, cell, screen, pitch_deg, fov_deg, distance, target, recipe]
	if not extras.is_empty():
		parts.append(extras)
	return parts


## Parámetros de la Camera3D del horneado (misma cámara que las cuentas).
func camera_transform() -> Transform3D:
	return _cam


func near() -> float:
	return maxf(distance * 0.25, 10.0)


func far() -> float:
	return distance * 4.0
