class_name Board25DScene
extends RefCounted
## Escenario 3D de un tablero, armado por código con el plástico de las
## mascotas (toy_plastic + contorno de tinta): piso de baldosas, marco
## grueso de bloques arcoíris, bloques con estrella en las esquinas y un
## entorno de juguetes alrededor. Lo hornea Board25DBaker a una textura
## (ADR 0019); en cada cuadro no hay 3D.
##
## Dos capas, porque se tratan distinto al hornear:
##   - "back": piso de la sala, sombra del tablero y juguetes de alrededor.
##     Se renderiza a media resolución y se DESENFOCA (profundidad de campo:
##     lo que no es el tablero queda fuera de foco, como en la maqueta).
##   - "board": el tablero (base, baldosas, marco, esquinas). Nítido, con
##     supermuestreo, sobre fondo transparente.
##
## Unidades del mundo = px del plano del juego (ver BoardView25D): una baldosa
## de Pintar el piso mide 74. El piso de las baldosas (donde se paran las
## mascotas) está en y = 0; x a la derecha, z hacia la cámara.
##
## Concepto: *luz de estudio en el shader* (ver docs/ARTE.md). No hay luces
## reales: toy_plastic ilumina desde arriba a la izquierda respecto de la
## cámara. Con la cámara mirando el tablero desde arriba, la tapa de cada
## bloque queda clara, el frente (el que mira a la cámara) en sombra de color
## y el canto redondeado con el brillo nítido: eso es el "volumen".

const SHADER_TOY := preload("res://core/mascot3d/toy_plastic.gdshader")
const SHADER_INK := preload("res://core/mascot3d/ink_outline.gdshader")

const LAYER_BACK := "back"
const LAYER_BOARD := "board"

## Recetas (BoardView25D.recipe). Cualquier otra ("paint", "arena"): el
## tablero de baldosas a cuadros de la maqueta.
##   - "dodge": el mismo tablero con baldosas lila (Esquivar se distingue de
##     Arena, que tiene el mismo campo) donde las sombras de los bloques se leen bien.
##   - "pool": mesa de paño con bandas, troneras con aro, miras y la marca del
##     centro, dentro del mismo marco de bloques. Usa `view.extras`:
##     "cushion" (ancho de las bandas), "pocket_r" (radio de las troneras) y
##     "pockets" (centros, en coordenadas del plano), los de la física del juego.
##   - "karts": pasto en franjas con la pista entera horneada (asfalto y
##     marcas planas, cordones de bloques con volumen, turbos, charcos,
##     largada), árboles y matas como esferas de plástico. La geometría viene
##     en `view.extras` (ver Karts.scene_extras).
const RECIPE_DODGE := "dodge"
const RECIPE_POOL := "pool"
const RECIPE_KARTS := "karts"
##   - "pingpong": mesa de ping pong (tapa azul con canto redondeado, línea
##     blanca del borde y del medio, red con volumen y postes) sin marco de
##     bloques, sobre la sala de juguetes.
const RECIPE_PINGPONG := "pingpong"
##   - "tap_race" y "hurdles" (carriles): el tablero de baldosas a cuadros
##     con una división entre carril y carril y, si `view.extras` trae
##     "finish", una meta a cuadros. Extras: "rows" (carriles), "lane_h",
##     "divider" (ancho de la división; 0 = ninguna), "dash" ([largo, paso]
##     para una división punteada, o []), "finish" ([x, ancho] en el plano).
const RECIPE_TAP_RACE := "tap_race"
const RECIPE_HURDLES := "hurdles"
##   - "stage": solo la sala de juguetes (piso, bloques, bandera, estrellas),
##     desenfocada entera y sin tablero: el cielo de los juegos sin tablero
##     2.5D (MiniGame.draw_sky), en vez del escenario pintado a mano.
const RECIPE_STAGE := "stage"

static var _materials: Dictionary = {}


## Nodo 3D con la capa `layer` del escenario para la vista `view`.
static func build(view: BoardView25D, layer: String) -> Node3D:
	var root := Node3D.new()
	root.name = "Board25D_" + layer
	if layer == LAYER_BOARD:
		match view.recipe:
			RECIPE_STAGE:
				pass  # Sin tablero: la capa queda vacía (el baker la saltea).
			RECIPE_POOL:
				_pool(root, view)
			RECIPE_KARTS:
				_karts(root, view)
			RECIPE_PINGPONG:
				_pingpong(root, view)
			RECIPE_TAP_RACE, RECIPE_HURDLES:
				_board(root, view)
				_lanes(root, view)
			_:
				_board(root, view)
	else:
		_back(root, view)
	return root


## Suelta materiales y mallas del armado (después de hornear no se usan).
static func release_build_caches() -> void:
	_materials.clear()


## Tokens propios de una receta que no empiezan con BOARD25D_ (ej. los
## colores POOL_* de la mesa): entran en la firma de la caché del horneado.
static func recipe_tokens(recipe: String) -> Array:
	if recipe == RECIPE_POOL:
		return [UiTheme.POOL_FELT, UiTheme.POOL_FELT_LIGHT, UiTheme.POOL_CUSHION, UiTheme.POOL_CUSHION_EDGE, UiTheme.POOL_MARK,
			UiTheme.POOL_SIGHT, UiTheme.POOL_POCKET, UiTheme.POOL_POCKET_RIM]
	if recipe == RECIPE_PINGPONG:
		return [UiTheme.TABLE_BLUE, UiTheme.TABLE_BLUE_DARK, UiTheme.PAPER]
	if recipe == RECIPE_KARTS:
		return [UiTheme.KARTS_GRASS, UiTheme.KARTS_GRASS_ALT, UiTheme.KARTS_TREE, UiTheme.KARTS_ROAD, UiTheme.KARTS_ROAD_LIGHT,
			UiTheme.KARTS_ROAD_LINE, UiTheme.KARTS_PUDDLE, UiTheme.KARTS_PUDDLE_SHINE, UiTheme.WARNING, UiTheme.PAPER, UiTheme.SHADOW]
	return []


## Medio ancho y medio largo del tablero con el marco (unidades del mundo).
static func outer_half(view: BoardView25D) -> Vector2:
	return view.plane.size / 2.0 + Vector2.ONE * UiTheme.BOARD25D_FRAME_W


# --- Tablero -----------------------------------------------------------------------

static func _board(root: Node3D, view: BoardView25D) -> void:
	var half := view.plane.size / 2.0
	var base := UiTheme.BOARD25D_BASE
	var tile_h := UiTheme.BOARD25D_TILE_H
	# Base: la "caja" del tablero debajo de las baldosas (se ve en las juntas).
	var slab := _part(root, Props3DMeshes.rounded_box(Vector3(half.x * 2.0 + 4.0, base, half.y * 2.0 + 4.0), 4.0),
		_plastic(UiTheme.BOARD25D_GROUT, 0.0, 0.0, 0.0))
	slab.position = Vector3(0, -tile_h * 0.6 - base / 2.0, 0)
	# Baldosas a cuadros: cajitas con los cantos redondeados (el borde toma luz).
	var gap := UiTheme.BOARD25D_TILE_GAP
	# Lado de cada baldosa: `cell`, o un poco menos en un eje si el campo no
	# es múltiplo (Arena: 1600 × 860 con 80 -> 20 × 11 baldosas de 80 × 78).
	var side := view.plane.size / Vector2(view.cols, view.rows)
	var tile := Props3DMeshes.rounded_box(Vector3(side.x - gap * 2.0, tile_h, side.y - gap * 2.0), UiTheme.BOARD25D_TILE_ROUND)
	var dodge := view.recipe == RECIPE_DODGE
	var light := _plastic(UiTheme.BOARD25D_DODGE_TILE_LIGHT if dodge else UiTheme.BOARD25D_TILE_LIGHT, 0.0, 0.12, 0.0)
	var dark := _plastic(UiTheme.BOARD25D_DODGE_TILE_DARK if dodge else UiTheme.BOARD25D_TILE_DARK, 0.0, 0.12, 0.0)
	for y in view.rows:
		for x in view.cols:
			var t := _part(root, tile, light if (x + y) % 2 == 0 else dark)
			var c := view.to_world(view.plane.position + (Vector2(x, y) + Vector2(0.5, 0.5)) * side)
			t.position = c + Vector3(0, -tile_h / 2.0, 0)
	# Sombra suave del marco sobre el piso (arriba y a la izquierda, como si la
	# luz viniera de atrás): tiras transparentes con degradé, sin luces reales.
	_edge_shade(root, half)
	_frame(root, half)


## Marco: bloques arcoíris a los cuatro lados del plano (medio tamaño
## `half`) y, en las esquinas, un bloque más alto con una estrella dorada.
## Lo comparten todas las recetas.
static func _frame(root: Node3D, half: Vector2) -> void:
	var fw := UiTheme.BOARD25D_FRAME_W
	var base := UiTheme.BOARD25D_BASE
	var tile_h := UiTheme.BOARD25D_TILE_H
	# Marco: bloques arcoíris a los cuatro lados (las esquinas, aparte).
	var top_y := UiTheme.BOARD25D_FRAME_H
	var bottom_y := -tile_h - base
	var h := top_y - bottom_y
	var mid_y := (top_y + bottom_y) / 2.0
	var brick_len := UiTheme.BOARD_BRICK
	var i := 0
	for side in 4:
		var horizontal := side < 2
		var length := half.x * 2.0 if horizontal else half.y * 2.0
		var n := maxi(1, roundi(length / brick_len))
		var step := length / n
		for k in n:
			var col: Color = UiTheme.BRICKS[(i * 3 + side) % UiTheme.BRICKS.size()]
			i += 1
			var along := -length / 2.0 + (k + 0.5) * step
			var size := Vector3(step - 2.0, h, fw - 2.0) if horizontal else Vector3(fw - 2.0, h, step - 2.0)
			var b := _part(root, Props3DMeshes.rounded_box(size, UiTheme.BOARD25D_BRICK_ROUND), _plastic(col, UiTheme.BOARD25D_INK_THIN))
			match side:
				0: b.position = Vector3(along, mid_y, -half.y - fw / 2.0)
				1: b.position = Vector3(along, mid_y, half.y + fw / 2.0)
				2: b.position = Vector3(-half.x - fw / 2.0, mid_y, along)
				_: b.position = Vector3(half.x + fw / 2.0, mid_y, along)
	# Esquinas: bloque más grande y más alto con una estrella dorada arriba.
	var cs := UiTheme.BOARD25D_CORNER
	var corner_h := h + UiTheme.BOARD25D_CORNER_RISE
	for k in 4:
		var sx := -1.0 if k % 2 == 0 else 1.0
		var sz := -1.0 if k < 2 else 1.0
		var col: Color = UiTheme.BRICKS[0] if k != 3 else UiTheme.BRICKS[5]
		var p := Vector3(sx * (half.x + fw / 2.0), bottom_y + corner_h / 2.0, sz * (half.y + fw / 2.0))
		var blk := _part(root, Props3DMeshes.rounded_box(Vector3(cs, corner_h, cs), UiTheme.BOARD25D_BRICK_ROUND + 2.0),
			_plastic(col, UiTheme.BOARD25D_INK))
		blk.position = p
		var star := _part(root, Props3DMeshes.pillow("star40", Props3DMeshes.star_outline(40.0, 0.5), 10.0),
			_star_material())
		star.scale = Vector3.ONE * cs / 80.0 * 1.05
		# Acostada sobre la tapa y un poco levantada hacia la cámara (se lee la forma).
		star.rotation_degrees = Vector3(-90.0 + UiTheme.BOARD25D_STAR_LIFT_DEG, 0, 0)
		star.position = p + Vector3(0, corner_h / 2.0 + 6.0, 4.0)


# --- Mesa de pool ------------------------------------------------------------------

## Mesa de Pool loco: el plano es el paño (Pool.FELT) y adentro, a
## `cushion` de cada borde, está el área donde ruedan las bolas (Pool.PLAY).
## Paño de plástico mate con la luz de la lámpara y las marcas del centro,
## bandas con volumen cortadas en cada tronera, troneras con aro, miras
## blancas en las bandas y el marco de bloques de siempre alrededor.
static func _pool(root: Node3D, view: BoardView25D) -> void:
	var half := view.plane.size / 2.0
	var cushion: float = view.extras.get("cushion", 36.0)
	var pocket_r: float = view.extras.get("pocket_r", 36.0)
	var inner := half - Vector2.ONE * cushion  # Medio tamaño del área de juego.
	var depth := UiTheme.BOARD25D_TILE_H + UiTheme.BOARD25D_BASE
	# Paño: una caja con la tapa en y = 0 (donde ruedan las bolas).
	var felt := _part(root, Props3DMeshes.rounded_box(Vector3(half.x * 2.0 + 4.0, depth, half.y * 2.0 + 4.0), 4.0),
		_plastic(UiTheme.POOL_FELT.lightened(UiTheme.BOARD25D_POOL_FELT_LIFT), 0.0, 0.0, 0.0))
	felt.position = Vector3(0, -depth / 2.0, 0)
	# Luz de la lámpara, marcas del centro y sombra de las bandas: figuras
	# planas apenas sobre el paño (color por vértice, transparentes).
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_flat_ellipse(st, Vector2.ZERO, inner * Vector2(1.0, 1.24), 0.3, UiTheme.POOL_FELT_LIGHT, Color(UiTheme.POOL_FELT_LIGHT, 0.0))
	_flat_ring(st, Vector2.ZERO, 0.0, UiTheme.BOARD25D_POOL_MARK_DOT, 0.5, UiTheme.POOL_MARK)
	_flat_ring(st, Vector2.ZERO, UiTheme.BOARD25D_POOL_MARK_RING - 3.0, UiTheme.BOARD25D_POOL_MARK_RING + 3.0, 0.5, UiTheme.POOL_MARK)
	var marks := MeshInstance3D.new()
	marks.mesh = st.commit()
	marks.material_override = _vertex_color_material()
	marks.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(marks)
	_edge_shade(root, inner, UiTheme.BOARD25D_POOL_SHADE_W)
	# Bandas: un tramo entre cada par de troneras (las de las esquinas y las
	# del medio de los lados largos), con el canto redondeado que toma luz.
	var h := UiTheme.BOARD25D_POOL_CUSHION_H
	var gap := pocket_r + UiTheme.BOARD25D_POOL_POCKET_GAP
	var band := _plastic(UiTheme.POOL_CUSHION, UiTheme.BOARD25D_INK_THIN, 0.22, 0.6)
	var r := UiTheme.BOARD25D_POOL_CUSHION_ROUND
	for sz: float in [-1.0, 1.0]:
		var z := sz * (inner.y + cushion / 2.0)
		for sx: float in [-1.0, 1.0]:  # Lados largos: de la esquina al medio.
			var length := inner.x - gap * 2.0
			var b := _part(root, Props3DMeshes.rounded_box(Vector3(length, h, cushion - 2.0), r), band)
			b.position = Vector3(sx * (gap + length / 2.0), h / 2.0, z)
	for sx: float in [-1.0, 1.0]:  # Lados cortos: de esquina a esquina.
		var length := inner.y * 2.0 - gap * 2.0
		var b := _part(root, Props3DMeshes.rounded_box(Vector3(cushion - 2.0, h, length), r), band)
		b.position = Vector3(sx * (inner.x + cushion / 2.0), h / 2.0, 0)
	# Esquinas del riel (detrás de la tronera de la esquina): del color de las bandas.
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			var c := _part(root, Props3DMeshes.rounded_box(Vector3(cushion, h * 0.7, cushion), r), band)
			c.position = Vector3(sx * (inner.x + cushion / 2.0), h * 0.35, sz * (inner.y + cushion / 2.0))
	# Miras: botoncitos blancos en las bandas, entre las troneras.
	var sight := _plastic(Color(UiTheme.POOL_SIGHT, 1.0), 0.0, 0.3, 0.9)
	var dot := UiTheme.BOARD25D_POOL_SIGHT_R
	for k: int in [1, 2, 3, 5, 6, 7]:
		for sz: float in [-1.0, 1.0]:
			var m := _part(root, Props3DMeshes.sphere(8, 12), sight)
			m.scale = Vector3(dot, dot * 0.45, dot)
			m.position = Vector3(-inner.x + inner.x * 2.0 * k / 8.0, h, sz * (inner.y + cushion / 2.0))
	for k in [1, 2, 3]:
		for sx: float in [-1.0, 1.0]:
			var m := _part(root, Props3DMeshes.sphere(8, 12), sight)
			m.scale = Vector3(dot, dot * 0.45, dot)
			m.position = Vector3(sx * (inner.x + cushion / 2.0), h, -inner.y + inner.y * 2.0 * k / 4.0)
	# Troneras: agujero oscuro (sin luz: se ve negro desde cualquier lado) y
	# un aro con volumen alrededor, a la altura de las bandas.
	var hole := _flat_material(Color(UiTheme.POOL_POCKET, 1.0))
	var rim := _plastic(UiTheme.POOL_POCKET_RIM, UiTheme.BOARD25D_INK, 0.3, 0.9)
	var center := view.plane.get_center()
	for p: Vector2 in view.extras.get("pockets", PackedVector2Array()):
		var w := Vector3(p.x - center.x, 0.0, p.y - center.y)
		var disc := _part(root, Props3DMeshes.cone(1.0, 32), hole)
		var hole_r := pocket_r - UiTheme.BOARD25D_POOL_RIM * 0.5
		disc.scale = Vector3(hole_r, 1.0, hole_r)
		disc.position = w + Vector3(0, h * 0.5 - 1.0, 0)
		# Aro: toro de radio `pocket_r` y grosor RIM (afuera llega a pocket_r + RIM),
		# estirado en alto hasta la altura de las bandas.
		var t := UiTheme.BOARD25D_POOL_RIM / pocket_r
		var ring := _part(root, Props3DMeshes.torus(t, 36), rim)
		ring.scale = Vector3(pocket_r, h * 0.5 / t, pocket_r)
		ring.position = w + Vector3(0, h * 0.5, 0)
	_frame(root, half)


# --- Pista de karts ------------------------------------------------------------------

## Karts de mascotas: el plano es el pasto (Karts.FIELD) en franjas de dos
## verdes (cajitas como las baldosas) y encima la pista entera, que no
## cambia en toda la carrera: asfalto y marcas como figuras planas de color
## por vértice (mismos colores que el dibujo plano), cordones de bloques
## arcoíris con volumen y contorno a los dos lados, turbos como bloques
## naranjas con flechas, charcos, línea de largada a cuadros y corchetes de
## la grilla; árboles y matas como esferas de plástico con sombra. Todo sale
## de `view.extras` (Karts.scene_extras): puntos y normales del centro de la
## pista, anchos, turbos, charcos, grilla, largada y decorado.
static func _karts(root: Node3D, view: BoardView25D) -> void:
	var half := view.plane.size / 2.0
	var base := UiTheme.BOARD25D_BASE
	var tile_h := UiTheme.BOARD25D_TILE_H
	var slab := _part(root, Props3DMeshes.rounded_box(Vector3(half.x * 2.0 + 4.0, base, half.y * 2.0 + 4.0), 4.0),
		_plastic(UiTheme.KARTS_GRASS_ALT.darkened(0.2), 0.0, 0.0, 0.0))
	slab.position = Vector3(0, -tile_h * 0.6 - base / 2.0, 0)
	# Pasto en franjas: cajitas de todo el alto del campo, sin junta.
	var lit := UiTheme.BOARD25D_KARTS_LIGHT
	var grass := [_plastic(UiTheme.KARTS_GRASS, 0.0, 0.0, 0.0, lit), _plastic(UiTheme.KARTS_GRASS_ALT, 0.0, 0.0, 0.0, lit)]
	var stripe := view.plane.size.x / view.cols
	var strip_mesh := Props3DMeshes.rounded_box(Vector3(stripe + 0.5, tile_h, half.y * 2.0), 2.0)
	for x in view.cols:
		var t := _part(root, strip_mesh, grass[x % 2])
		t.position = Vector3(-half.x + (x + 0.5) * stripe, -tile_h / 2.0, 0)
	_edge_shade(root, half)
	_frame(root, half)
	var c := view.plane.get_center()
	var pts: PackedVector2Array = view.extras.get("pts", PackedVector2Array())
	var nrm: PackedVector2Array = view.extras.get("nrm", PackedVector2Array())
	if pts.size() < 3 or nrm.size() != pts.size():
		return
	var hw: float = view.extras.get("half_width", 84.0)
	var curb: float = view.extras.get("curb", 18.0)
	var samples: int = maxi(int(view.extras.get("curb_samples", 4)), 1)
	var outer := hw + curb
	var y := UiTheme.BOARD25D_KARTS_MARK_Y
	# Marcas planas (opacas, color por vértice; las transparencias del dibujo
	# plano vienen ya mezcladas con el asfalto): tinta por fuera del cordón,
	# asfalto, franja gastada del medio, líneas del costado, punteada del
	# medio, largada y corchetes de la grilla.
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var road := UiTheme.KARTS_ROAD
	var ink_band := UiTheme.BOARD25D_KARTS_INK_BAND
	for side: float in [-1.0, 1.0]:
		_track_band(st, pts, nrm, c, side * outer, side * (outer + ink_band), y, UiTheme.INK)
	_track_band(st, pts, nrm, c, -hw, hw, y, road)
	_track_band(st, pts, nrm, c, -hw * 0.55, hw * 0.55, y, UiTheme.KARTS_ROAD_LIGHT)
	var line := road.lerp(Color(UiTheme.KARTS_ROAD_LINE, 1.0), UiTheme.KARTS_ROAD_LINE.a)
	for side: float in [-1.0, 1.0]:
		_track_band(st, pts, nrm, c, side * hw, side * (hw - 3.0), y, road.lerp(UiTheme.INK, 0.5))
		_track_band(st, pts, nrm, c, side * (hw - 11.0), side * (hw - 15.0), y, line)
	var m := pts.size()
	var i := 6
	while i < m - 4:
		_track_band(st, pts, nrm, c, -2.5, 2.5, y, line, i, i + 2)
		i += 5
	# Largada a cuadros (dos filas) y corchetes de la grilla.
	var start: Vector3 = view.extras.get("start", Vector3.ZERO)
	var sxf := Transform2D(start.z, Vector2(start.x, start.y) - c)
	var cols := 12
	var sq := hw * 2.0 / cols
	_flat_quad_2d(st, sxf, Rect2(-sq - 3.0, -hw, (sq + 3.0) * 2.0, hw * 2.0), y + 0.1, UiTheme.INK)
	for r in 2:
		for k in cols:
			_flat_quad_2d(st, sxf, Rect2(-sq + r * sq, -hw + k * sq, sq, sq), y + 0.2, UiTheme.PAPER if (r + k) % 2 == 0 else UiTheme.INK)
	var grid_len: float = view.extras.get("grid_len", 82.0)
	var bracket := road.lerp(UiTheme.PAPER, 0.8)
	for g: Vector3 in view.extras.get("grid", []):
		var gxf := Transform2D(g.z, Vector2(g.x, g.y) - c)
		_flat_quad_2d(st, gxf, Rect2(grid_len / 2.0 + 4.0, -28.0, 4.0, 56.0), y + 0.1, bracket)
		_flat_quad_2d(st, gxf, Rect2(-grid_len / 2.0 + 4.0, -30.0, grid_len + 2.0, 4.0), y + 0.1, bracket)
		_flat_quad_2d(st, gxf, Rect2(-grid_len / 2.0 + 4.0, 26.0, grid_len + 2.0, 4.0), y + 0.1, bracket)
	# Charcos: tres lóbulos con contorno de tinta y dos brillos.
	for pd: Array in view.extras.get("puddles", []):
		var pc := Vector2(pd[0], pd[1]) - c
		var r: float = pd[2]
		var angle: float = pd[3]
		var lobes := [Vector3(0, 0, 1.0), Vector3(-0.55, 0.25, 0.62), Vector3(0.5, -0.3, 0.6)]
		for l: Vector3 in lobes:
			_flat_ellipse_2d(st, pc + Vector2(l.x, l.y).rotated(angle) * r, Vector2(r * l.z * 1.2 + 4.0, r * l.z * 0.85 + 4.0), angle, y + 0.3, UiTheme.INK)
		for l: Vector3 in lobes:
			_flat_ellipse_2d(st, pc + Vector2(l.x, l.y).rotated(angle) * r, Vector2(r * l.z * 1.2, r * l.z * 0.85), angle, y + 0.4, UiTheme.KARTS_PUDDLE)
		_flat_ellipse_2d(st, pc + Vector2(-r * 0.25, -r * 0.2), Vector2(r * 0.45, r * 0.18), angle, y + 0.5, UiTheme.KARTS_PUDDLE_SHINE)
		_flat_ellipse_2d(st, pc + Vector2(r * 0.35, r * 0.2), Vector2(r * 0.18, r * 0.08), angle, y + 0.5, UiTheme.KARTS_PUDDLE_SHINE)
	# Sombras de árboles y matas, acostadas en el pasto.
	for d: Array in view.extras.get("decor", []):
		var dc: Vector2 = d[1] - c
		var r: float = d[2]
		if d[0] == "tree":
			_flat_ellipse_2d(st, dc + Vector2(6.0, r * 0.45), Vector2(r * 1.05, r * 0.6), 0.0, y, UiTheme.KARTS_GRASS_ALT.lerp(UiTheme.INK, 0.28))
		elif d[0] == "bush":
			_flat_ellipse_2d(st, dc + Vector2(4.0, r * 0.5), Vector2(r * 1.2, r * 0.45), 0.0, y, UiTheme.KARTS_GRASS_ALT.lerp(UiTheme.INK, 0.28))
	var marks := MeshInstance3D.new()
	marks.mesh = st.commit()
	marks.material_override = _marks_material()
	marks.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(marks)
	# Cordones: un bloque arcoíris por tramo de `samples` puntos, a cada lado,
	# orientado con la pista; canto redondeado y contorno fino.
	var curb_h := UiTheme.BOARD25D_KARTS_CURB_H
	var blocks := ceili(float(m) / samples)
	for side: float in [-1.0, 1.0]:
		for k in blocks:
			var i0 := k * samples
			var i1 := mini(i0 + samples, m)
			var col: Color = UiTheme.BRICKS[(k * 3 + (0 if side < 0.0 else 5)) % UiTheme.BRICKS.size()]
			var a := pts[i0] + nrm[i0] * side * (hw + curb / 2.0)
			var b := pts[i1 % m] + nrm[i1 % m] * side * (hw + curb / 2.0)
			var length := a.distance_to(b)
			if length < 1.0:
				continue
			var mid := (a + b) / 2.0 - c
			var blk := _part(root, Props3DMeshes.rounded_box(Vector3(length - 2.0, curb_h, curb - 2.0), UiTheme.BOARD25D_KARTS_CURB_ROUND, 3),
				_plastic(col, UiTheme.BOARD25D_INK_THIN))
			blk.position = Vector3(mid.x, curb_h / 2.0, mid.y)
			blk.rotation = Vector3(0, -(b - a).angle(), 0)
	# Turbos: bloque naranja con contorno y tres flechas claras arriba.
	var pad_size: Vector2 = view.extras.get("pad_size", Vector2(92, 62))
	var pad_h := UiTheme.BOARD25D_KARTS_PAD_H
	var chev := SurfaceTool.new()
	chev.begin(Mesh.PRIMITIVE_TRIANGLES)
	for pad: Vector3 in view.extras.get("pads", []):
		var pc := Vector2(pad.x, pad.y) - c
		var blk := _part(root, Props3DMeshes.rounded_box(Vector3(pad_size.x, pad_h, pad_size.y), 5.0, 3),
			_plastic(UiTheme.WARNING, UiTheme.BOARD25D_INK_THIN, 0.22, 0.95, lit))
		blk.position = Vector3(pc.x, pad_h / 2.0, pc.y)
		blk.rotation = Vector3(0, -pad.z, 0)
		var pxf := Transform2D(pad.z, pc)
		var gold := UiTheme.GOLD.lightened(0.2)
		for k in 3:
			var xf := pxf * Transform2D(0.0, Vector2(-22.0 + k * 22.0, 0))
			var s := 16.0
			var th := 7.0
			for side: float in [-1.0, 1.0]:
				var pa := Vector2(-s * 0.5, side * s)
				var pcn := Vector2(s * 0.5, 0)
				_flat_tri_2d(chev, xf, pa, pcn, pcn + Vector2(-th, 0), pad_h + 0.3, gold)
				_flat_tri_2d(chev, xf, pa, pcn + Vector2(-th, 0), pa + Vector2(-th, 0), pad_h + 0.3, gold)
	var chevrons := MeshInstance3D.new()
	chevrons.mesh = chev.commit()
	chevrons.material_override = _marks_material()
	chevrons.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(chevrons)
	# Árboles (copa gorda con cinco bultos), matas (tres bolas) y flores
	# (cinco pétalos y el centro dorado): esferas de plástico con contorno.
	var leaf := UiTheme.KARTS_TREE
	var tree_mat := _plastic(leaf, UiTheme.BOARD25D_INK_THIN, 0.24, 0.9, lit + 0.08)
	var lobe_mat := _plastic(leaf.lightened(0.12), 0.0, 0.24, 0.9, lit + 0.08)
	var bush_mat := _plastic(leaf.lightened(0.15), UiTheme.BOARD25D_INK_THIN, 0.24, 0.9, lit + 0.08)
	var sink := UiTheme.BOARD25D_KARTS_TREE_SINK
	var sphere := Props3DMeshes.sphere(12, 20)
	for d: Array in view.extras.get("decor", []):
		var dc: Vector2 = d[1] - c
		var r: float = d[2]
		match d[0]:
			"tree":
				_ball(root, sphere, tree_mat, Vector3(dc.x, r * (1.0 - sink), dc.y), r)
				for a in 5:
					var off := Vector2.from_angle(TAU * a / 5.0 + r) * r * 0.55
					_ball(root, sphere, lobe_mat, Vector3(dc.x + off.x, r * (1.0 - sink) + r * 0.35, dc.y + off.y), r * 0.42)
			"bush":
				for off: Vector2 in [Vector2(-r * 0.55, 2), Vector2(r * 0.55, 2), Vector2(0, -r * 0.3)]:
					_ball(root, sphere, bush_mat, Vector3(dc.x + off.x, r * 0.7 * (1.0 - sink), dc.y + off.y), r * 0.7)
			_:
				var petal := _plastic((UiTheme.BRICKS[int(d[3]) % UiTheme.BRICKS.size()] as Color).lightened(0.2), 0.0, 0.3, 0.9)
				for a in 5:
					var off := Vector2.from_angle(TAU * a / 5.0) * 5.5
					_ball(root, sphere, petal, Vector3(dc.x + off.x, 3.5, dc.y + off.y), 4.5)
				_ball(root, sphere, _plastic(UiTheme.GOLD, 0.0, 0.3, 0.9), Vector3(dc.x, 5.0, dc.y), 3.5)


static func _ball(root: Node3D, mesh: Mesh, mat: Material, at: Vector3, r: float) -> void:
	var b := _part(root, mesh, mat)
	b.position = at
	b.scale = Vector3.ONE * r


## Franja a lo largo de la pista entre dos distancias laterales (como
## Karts._band), a la altura `y`, con los puntos relativos al centro `c`.
## `i0`/`i1`: solo ese tramo de puntos (por defecto toda la vuelta).
static func _track_band(st: SurfaceTool, pts: PackedVector2Array, nrm: PackedVector2Array, c: Vector2, lat0: float, lat1: float,
		y: float, col: Color, i0 := 0, i1 := -1) -> void:
	var m := pts.size()
	var last := m if i1 < 0 else i1
	for i in range(i0, last):
		var a := i % m
		var b := (i + 1) % m
		var p0 := pts[a] + nrm[a] * lat0 - c
		var p1 := pts[b] + nrm[b] * lat0 - c
		var p2 := pts[b] + nrm[b] * lat1 - c
		var p3 := pts[a] + nrm[a] * lat1 - c
		_quad(st, [Vector3(p0.x, y, p0.y), Vector3(p1.x, y, p1.y), Vector3(p2.x, y, p2.y), Vector3(p3.x, y, p3.y)], [col, col, col, col])


## Rectángulo del plano (coordenadas locales `r` llevadas por `xf`) acostado a la altura `y`.
static func _flat_quad_2d(st: SurfaceTool, xf: Transform2D, r: Rect2, y: float, col: Color) -> void:
	var q := [xf * r.position, xf * Vector2(r.end.x, r.position.y), xf * r.end, xf * Vector2(r.position.x, r.end.y)]
	_quad(st, q.map(func(p: Vector2) -> Vector3: return Vector3(p.x, y, p.y)), [col, col, col, col])


static func _flat_tri_2d(st: SurfaceTool, xf: Transform2D, a: Vector2, b: Vector2, c: Vector2, y: float, col: Color) -> void:
	for p: Vector2 in [xf * a, xf * c, xf * b]:
		st.set_color(col)
		st.set_normal(Vector3.UP)
		st.add_vertex(Vector3(p.x, y, p.y))


## Elipse del plano (centro, radios, giro) acostada a la altura `y`.
static func _flat_ellipse_2d(st: SurfaceTool, c: Vector2, radii: Vector2, rotation: float, y: float, col: Color, segs := 24) -> void:
	for i in segs:
		var a := c + (Vector2.from_angle(TAU * i / segs) * radii).rotated(rotation)
		var b := c + (Vector2.from_angle(TAU * (i + 1) / segs) * radii).rotated(rotation)
		for v: Vector2 in [c, b, a]:
			st.set_color(col)
			st.set_normal(Vector3.UP)
			st.add_vertex(Vector3(v.x, y, v.y))


# --- Carriles (Carrera de toques, Carrera de obstáculos) ----------------------------------

## Sobre el tablero de baldosas: la división entre carriles (una línea de
## tinta, entera o punteada, acostada sobre las baldosas) y la meta a
## cuadros (dos columnas de todo el alto, sobre una base de tinta).
static func _lanes(root: Node3D, view: BoardView25D) -> void:
	var half := view.plane.size / 2.0
	var rows: int = maxi(int(view.extras.get("rows", 1)), 1)
	var lane_h: float = view.extras.get("lane_h", view.plane.size.y / rows)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var y := UiTheme.BOARD25D_LANE_MARK_Y
	var w: float = view.extras.get("divider", 4.0)
	var dash: Array = view.extras.get("dash", [])
	var o := Transform2D()
	var ink := UiTheme.BOARD25D_TILE_LIGHT.lerp(UiTheme.INK, UiTheme.BOARD25D_LANE_DIVIDER_ALPHA)
	if w > 0.0:
		for i in range(1, rows):
			var ly := -half.y + lane_h * i
			if dash.is_empty():
				_flat_quad_2d(st, o, Rect2(-half.x, ly - w / 2.0, half.x * 2.0, w), y, ink)
			else:
				var x := -half.x
				while x < half.x:
					_flat_quad_2d(st, o, Rect2(x, ly - w / 2.0, minf(float(dash[0]), half.x - x), w), y, ink)
					x += float(dash[1])
	var finish: Array = view.extras.get("finish", [])
	if finish.size() == 2:
		var fx: float = finish[0] - view.plane.get_center().x
		var fw: float = finish[1]
		var cell := fw / 2.0
		_flat_quad_2d(st, o, Rect2(fx - 4.0, -half.y, fw + 8.0, half.y * 2.0), y + 0.1, UiTheme.INK)
		var fy := -half.y
		var k := 0
		while fy < half.y:
			for c in 2:
				_flat_quad_2d(st, o, Rect2(fx + c * cell, fy, cell, minf(cell, half.y - fy)), y + 0.2, UiTheme.INK if (k + c) % 2 == 0 else UiTheme.PAPER)
			fy += cell
			k += 1
	var marks := MeshInstance3D.new()
	marks.mesh = st.commit()
	marks.material_override = _marks_material()
	marks.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(marks)


# --- Mesa de ping pong ------------------------------------------------------------------

## Ping Pong: el plano es la mesa (PingPong.TABLE). Tapa azul gruesa con el
## canto redondeado y contorno de tinta (sin marco de bloques: la mesa es la
## pieza), un borde y una línea del medio blancos pintados en la tapa, y la
## red cruzada en el medio, con volumen, postes y su sombra. La sala de
## juguetes de siempre alrededor.
static func _pingpong(root: Node3D, view: BoardView25D) -> void:
	var half := view.plane.size / 2.0
	var edge := UiTheme.BOARD25D_PP_EDGE
	var depth := UiTheme.BOARD25D_PP_TOP_H
	var top := _part(root, Props3DMeshes.rounded_box(Vector3(half.x * 2.0 + edge * 2.0, depth, half.y * 2.0 + edge * 2.0), UiTheme.BOARD25D_PP_ROUND),
		_plastic(UiTheme.TABLE_BLUE, UiTheme.BOARD25D_INK, 0.2, 0.0, UiTheme.BOARD25D_PP_LIGHT))
	top.position = Vector3(0, -depth / 2.0, 0)
	# Rodapié oscuro debajo de la tapa (el canto grueso de la maqueta).
	var skirt := _part(root, Props3DMeshes.rounded_box(Vector3(half.x * 2.0 + edge * 1.4, depth * 0.8, half.y * 2.0 + edge * 1.4), 6.0),
		_plastic(UiTheme.TABLE_BLUE_DARK, 0.0, 0.0, 0.0))
	skirt.position = Vector3(0, -depth - depth * 0.4 + 1.0, 0)
	# Marcas blancas: borde, línea del medio (a lo largo) y sombra de la red.
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var y := 0.5
	var line := UiTheme.BOARD25D_PP_LINE
	var white := UiTheme.PAPER
	var mid := UiTheme.TABLE_BLUE.lerp(UiTheme.PAPER, 0.5)
	var o := Transform2D()
	_flat_quad_2d(st, o, Rect2(-half.x, -half.y, half.x * 2.0, line), y, white)
	_flat_quad_2d(st, o, Rect2(-half.x, half.y - line, half.x * 2.0, line), y, white)
	_flat_quad_2d(st, o, Rect2(-half.x, -half.y, line, half.y * 2.0), y, white)
	_flat_quad_2d(st, o, Rect2(half.x - line, -half.y, line, half.y * 2.0), y, white)
	_flat_quad_2d(st, o, Rect2(-1.5, -half.y, 3.0, half.y * 2.0), y + 0.1, mid)
	_flat_quad_2d(st, o, Rect2(-half.x - 24.0, 3.0, half.x * 2.0 + 48.0, UiTheme.BOARD25D_PP_NET_H * 0.45), y + 0.2,
		UiTheme.TABLE_BLUE.lerp(UiTheme.INK, 0.35))
	var marks := MeshInstance3D.new()
	marks.mesh = st.commit()
	marks.material_override = _marks_material()
	marks.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(marks)
	# Red: una pared fina blanca con contorno, un cordón oscuro arriba y dos
	# postes de tinta que sobresalen de la mesa.
	var net_h := UiTheme.BOARD25D_PP_NET_H
	var net := _part(root, Props3DMeshes.rounded_box(Vector3(half.x * 2.0 + 48.0, net_h, 4.0), 1.5, 2),
		_plastic(UiTheme.PAPER, UiTheme.BOARD25D_INK_THIN, 0.1, 0.0, 0.05))
	net.position = Vector3(0, net_h / 2.0, 0)
	var cord := _part(root, Props3DMeshes.rounded_box(Vector3(half.x * 2.0 + 48.0, 6.0, 7.0), 2.5, 2), _plastic(UiTheme.INK.lightened(0.2), 0.0, 0.2, 0.9))
	cord.position = Vector3(0, net_h - 1.0, 0)
	for sx: float in [-1.0, 1.0]:
		var post := _part(root, Props3DMeshes.rounded_box(Vector3(10.0, net_h + 8.0, 10.0), 3.0, 2), _plastic(UiTheme.INK.lightened(0.2), 0.0, 0.2, 0.9))
		post.position = Vector3(sx * (half.x + 24.0), (net_h + 8.0) / 2.0, 0)


## Elipse plana a la altura `y` (xz), de `inner` en el centro a `outer` en el borde.
static func _flat_ellipse(st: SurfaceTool, c: Vector2, radii: Vector2, y: float, inner: Color, outer: Color, segs := 48) -> void:
	for i in segs:
		var a := Vector2.from_angle(TAU * i / segs) * radii + c
		var b := Vector2.from_angle(TAU * (i + 1) / segs) * radii + c
		for v: Array in [[c, inner], [b, outer], [a, outer]]:
			st.set_color(v[1])
			st.set_normal(Vector3.UP)
			st.add_vertex(Vector3((v[0] as Vector2).x, y, (v[0] as Vector2).y))


## Anillo plano (o disco, con r_in = 0) a la altura `y`, de un color.
static func _flat_ring(st: SurfaceTool, c: Vector2, r_in: float, r_out: float, y: float, col: Color, segs := 48) -> void:
	for i in segs:
		var d0 := Vector2.from_angle(TAU * i / segs)
		var d1 := Vector2.from_angle(TAU * (i + 1) / segs)
		var pts := [c + d0 * r_in, c + d1 * r_in, c + d1 * r_out, c + d0 * r_out]
		_quad(st, pts.map(func(p: Vector2) -> Vector3: return Vector3(p.x, y, p.y)), [col, col, col, col])


## Sombra del marco sobre el piso: dos tiras (arriba y a la izquierda) que
## van de tinta transparente a nada, apenas sobre las baldosas.
static func _edge_shade(root: Node3D, half: Vector2, w: float = UiTheme.BOARD25D_EDGE_SHADE_W) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var y := 0.6
	var dark := Color(UiTheme.INK, UiTheme.BOARD25D_EDGE_SHADE_ALPHA)
	var clear := Color(UiTheme.INK, 0.0)
	# Tira de arriba (z = -half.y) y de la izquierda (x = -half.x).
	_quad(st, [Vector3(-half.x, y, -half.y), Vector3(half.x, y, -half.y), Vector3(half.x, y, -half.y + w), Vector3(-half.x, y, -half.y + w)],
		[dark, dark, clear, clear])
	_quad(st, [Vector3(-half.x, y, -half.y), Vector3(-half.x + w * 0.7, y, -half.y), Vector3(-half.x + w * 0.7, y, half.y), Vector3(-half.x, y, half.y)],
		[dark, clear, clear, dark])
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = _vertex_color_material()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)


# --- Entorno (se desenfoca) ------------------------------------------------------------

static func _back(root: Node3D, view: BoardView25D) -> void:
	var o := outer_half(view)
	var floor_y := -UiTheme.BOARD25D_TILE_H - UiTheme.BOARD25D_BASE
	# Piso de la sala: baldosas grandes celestes a cuadros.
	var g := UiTheme.BOARD25D_GROUND_TILE
	var ground := Props3DMeshes.rounded_box(Vector3(g - 6.0, 20.0, g - 6.0), 8.0)
	var ga := _plastic(UiTheme.BOARD25D_GROUND_A, 0.0, 0.1, 0.0)
	var gb := _plastic(UiTheme.BOARD25D_GROUND_B, 0.0, 0.1, 0.0)
	var n_x := ceili((o.x + 700.0) / g)
	# Atrás el piso termina cerca del marco: arriba, en las esquinas, se ve el
	# cielo (como en la maqueta).
	for zi in range(-ceili((o.y + UiTheme.BOARD25D_GROUND_BACK) / g), ceili((o.y + 420.0) / g) + 1):
		for xi in range(-n_x, n_x + 1):
			var t := _part(root, ground, ga if posmod(xi + zi, 2) == 0 else gb)
			t.position = Vector3(xi * g, floor_y - 10.0, zi * g)
	# Sombra del tablero sobre el piso (se desenfoca con el resto).
	if view.recipe != RECIPE_STAGE:
		var shadow := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(o.x * 2.0 + 60.0, 1.0, o.y * 2.0 + 50.0)
		shadow.mesh = box
		shadow.material_override = _flat_material(UiTheme.BOARD25D_SHADOW)
		shadow.position = Vector3(26.0, floor_y + 0.8, 34.0)
		root.add_child(shadow)
	# Juguetes: mayoría azules y celestes (como la maqueta) con toques de
	# color. Posiciones relativas al borde del tablero (sirven para tableros
	# de otro tamaño); los de los costados quedan cortados por el borde de la
	# pantalla, como una foto. [x, z, ancho, alto, largo, color, botones, giro, (altura)]
	var b := UiTheme.BRICKS
	var sky := UiTheme.BOARD25D_TOY_SKY
	var toys := [
		# Izquierda, de atrás hacia adelante: una pila pegada a la otra.
		[-o.x - 150, -o.y - 60, 180, 70, 150, b[7], Vector2i(2, 2), 6.0],
		[-o.x - 130, -o.y + 110, 220, 120, 190, b[2], Vector2i(2, 2), -6.0],
		[-o.x - 120, -o.y + 300, 200, 80, 180, b[3], Vector2i(2, 2), 10.0],
		[-o.x - 130, o.y - 280, 210, 100, 180, b[5], Vector2i(2, 2), -4.0],
		[-o.x - 115, o.y - 90, 190, 70, 170, sky, Vector2i(2, 2), 8.0],
		[-o.x - 150, o.y + 130, 260, 150, 210, b[2], Vector2i(3, 2), 6.0],
		# Atrás del marco: fila de bloques azules y celestes, bajos.
		[-o.x + 250, -o.y - 95, 210, 60, 110, b[5], Vector2i(4, 2), 0.0],
		[-o.x + 500, -o.y - 100, 190, 70, 110, sky, Vector2i(3, 2), 3.0],
		[0.0, -o.y - 95, 200, 55, 110, b[4], Vector2i(4, 2), -2.0],
		[o.x - 520, -o.y - 100, 210, 65, 110, b[5], Vector2i(4, 2), -3.0],
		[o.x - 260, -o.y - 95, 190, 70, 110, sky, Vector2i(3, 2), 4.0],
		# Derecha, de atrás hacia adelante.
		[o.x + 140, -o.y - 70, 220, 110, 180, b[5], Vector2i(3, 2), -6.0],
		[o.x + 125, -o.y + 150, 200, 90, 180, b[3], Vector2i(2, 2), 8.0],
		[o.x + 130, o.y - 340, 210, 120, 180, b[6], Vector2i(2, 2), -6.0],
		[o.x + 120, o.y - 130, 200, 80, 180, b[2], Vector2i(2, 2), 5.0],
		[o.x + 160, o.y + 130, 260, 140, 210, b[4], Vector2i(3, 2), -8.0],
		# Adelante, abajo (asoman por el borde de la pantalla).
		[-o.x + 330, o.y + 190, 260, 60, 140, b[5], Vector2i(4, 2), 0.0],
		[o.x - 330, o.y + 190, 260, 60, 140, b[7], Vector2i(4, 2), 0.0],
	]
	for t: Array in toys:
		var y0: float = floor_y + (float(t[8]) if t.size() > 8 else 0.0)
		var col := (t[5] as Color).lerp(UiTheme.BG_HAZE, UiTheme.BOARD25D_TOY_HAZE)
		_toy(root, Vector3(t[0], y0, t[1]), Vector3(t[2], t[3], t[4]), col, t[6], t[7])
	# Bandera sobre la pila de atrás a la izquierda y estrellas de juguete.
	_flag(root, Vector3(-o.x - 40, floor_y, -o.y - 90))
	for s: Array in [[o.x + 120, floor_y + 190, o.y - 330, 62.0, 12.0], [-o.x - 110, floor_y + 175, -o.y + 130, 40.0, -10.0],
			[o.x + 130, floor_y + 160, -o.y - 60, 44.0, 8.0]]:
		var star := _part(root, Props3DMeshes.pillow("star40", Props3DMeshes.star_outline(40.0, 0.5), 10.0), _star_material())
		star.scale = Vector3.ONE * float(s[3]) / 40.0
		star.rotation_degrees = Vector3(-35.0, 0, float(s[4]))
		star.position = Vector3(s[0], s[1], s[2])


## Bloque de juguete: caja redondeada con botones arriba. `pos`: centro de la
## base; `size`: ancho, alto, largo; `studs`: botones a lo ancho y a lo largo.
static func _toy(root: Node3D, pos: Vector3, size: Vector3, col: Color, studs: Vector2i, turn_deg: float) -> void:
	var holder := Node3D.new()
	holder.position = pos
	holder.rotation_degrees = Vector3(0, turn_deg, 0)
	root.add_child(holder)
	var mat := _plastic(col, UiTheme.BOARD25D_INK * 0.8)
	var body := _part(holder, Props3DMeshes.rounded_box(size, 12.0), mat)
	body.position = Vector3(0, size.y / 2.0, 0)
	var cell := Vector2(size.x / studs.x, size.z / studs.y)
	var r := minf(cell.x, cell.y) * 0.3
	for sx in studs.x:
		for sz in studs.y:
			var stud := _part(holder, Props3DMeshes.cone(0.92), mat)
			stud.position = Vector3(-size.x / 2.0 + (sx + 0.5) * cell.x, size.y - 2.0, -size.z / 2.0 + (sz + 0.5) * cell.y)
			stud.scale = Vector3(r, r * 0.75, r)


## Bandera: palo, banderín rojo con una estrella y una bolita dorada arriba.
static func _flag(root: Node3D, base: Vector3) -> void:
	var pole := _part(root, Props3DMeshes.cone(1.0), _plastic(UiTheme.PAPER_DIM, UiTheme.BOARD25D_INK * 0.6))
	pole.position = base
	pole.scale = Vector3(6.0, 230.0, 6.0)
	var ball := _part(root, Props3DMeshes.sphere(), _plastic(UiTheme.GOLD, UiTheme.BOARD25D_INK * 0.6))
	ball.position = base + Vector3(0, 236.0, 0)
	ball.scale = Vector3.ONE * 13.0
	var pennant := PackedVector2Array([Vector2(0, 0), Vector2(120, -40), Vector2(0, -84)])
	var flag := _part(root, Props3DMeshes.pillow("pennant", Props3DMeshes.chaikin(pennant, 2), 5.0, 6, Vector2(38, -42)),
		_plastic(UiTheme.BRICKS[0], UiTheme.BOARD25D_INK * 0.6))
	flag.position = base + Vector3(4.0, 226.0, 0)
	flag.rotation_degrees = Vector3(-30.0, -20.0, 0)
	var star := _part(root, Props3DMeshes.pillow("star40", Props3DMeshes.star_outline(40.0, 0.5), 10.0), _star_material())
	star.scale = Vector3.ONE * 0.42
	star.position = base + Vector3(40.0, 190.0, 8.0)
	star.rotation_degrees = flag.rotation_degrees


# --- Piezas y materiales -------------------------------------------------------------------

static func _part(parent: Node3D, mesh: Mesh, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi


static func _quad(st: SurfaceTool, pts: Array, cols: Array) -> void:
	for k: int in [0, 2, 1, 0, 3, 2]:
		st.set_color(cols[k])
		st.set_normal(Vector3.UP)
		st.add_vertex(pts[k])


## Plástico de juguete (misma rampa que Props3D / Mascot3D). `ink`: contorno
## en unidades del mundo (0 = sin contorno); `coat`: brillo ancho de barniz;
## `spec`: reflejo nítido (0 en las caras planas grandes: con la normal
## constante, el reflejo "pintado" prendería baldosas enteras de blanco).
## `light`: cuánto se aclara la cara iluminada (por defecto BOARD25D_LIGHT;
## menos en superficies grandes vistas de arriba, como el pasto, para que
## queden del tono del token y no lavadas).
static func _plastic(col: Color, ink: float, coat := 0.22, spec := 0.95, light := -1.0) -> Material:
	var key := "p|%s|%.2f|%.2f|%.2f|%.2f" % [col.to_html(), ink, coat, spec, light]
	if _materials.has(key):
		return _materials[key]
	var lum := col.get_luminance()
	var dark := lum < 0.2
	var low := col.lightened(0.02) if dark else col.darkened(0.42 if lum < 0.8 else 0.16)
	low = low.lerp(UiTheme.MASCOT_SHADE_TINT, 0.14)
	var mid := col.lightened(0.1) if dark else col
	var lit := UiTheme.BOARD25D_LIGHT if light < 0.0 else light
	var high := col.lightened(0.45 if dark else (0.08 if lum > 0.85 else lit))
	var m := ShaderMaterial.new()
	m.shader = SHADER_TOY
	var params := {"low_color": low, "mid_color": mid, "high_color": high, "bounce_color": mid.lightened(0.18),
		"bounce_strength": 0.3, "rim_color": Color.WHITE, "rim_strength": 0.2, "spec_strength": spec,
		"spec_size": 0.012, "coat_strength": coat, "edge_color": low, "edge_strength": 0.25}
	for k: String in params:
		m.set_shader_parameter(k, params[k])
	if ink > 0.0:
		var hull := ShaderMaterial.new()
		hull.shader = SHADER_INK
		hull.set_shader_parameter("ink", UiTheme.INK)
		hull.set_shader_parameter("width", ink)
		m.next_pass = hull
	_materials[key] = m
	return m


## Estrella dorada con sombra naranja (como la de las piezas 3D).
static func _star_material() -> Material:
	if _materials.has("star"):
		return _materials["star"]
	var col := UiTheme.GOLD
	var m := ShaderMaterial.new()
	m.shader = SHADER_TOY
	var params := {"low_color": UiTheme.PROP_STAR_SHADE, "mid_color": col, "high_color": col.lerp(UiTheme.PAPER, 0.55),
		"bounce_color": col.lightened(0.2), "bounce_strength": 0.45, "rim_color": Color.WHITE, "rim_strength": 0.25,
		"spec_strength": 1.0, "spec_size": 0.02, "coat_strength": 0.3}
	for k: String in params:
		m.set_shader_parameter(k, params[k])
	var hull := ShaderMaterial.new()
	hull.shader = SHADER_INK
	hull.set_shader_parameter("ink", UiTheme.INK)
	hull.set_shader_parameter("width", UiTheme.BOARD25D_INK)
	m.next_pass = hull
	_materials["star"] = m
	return m


## Color plano semitransparente (sombra del tablero).
static func _flat_material(col: Color) -> Material:
	var key := "flat|" + col.to_html()
	if not _materials.has(key):
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.albedo_color = col
		_materials[key] = m
	return _materials[key]


## Color por vértice opaco (marcas planas de la pista de Karts): sin
## transparencia, así el orden lo decide la profundidad y no el centro de
## cada malla (las transparentes se ordenan entre sí por distancia).
static func _marks_material() -> Material:
	if not _materials.has("marks"):
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.vertex_color_use_as_albedo = true
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		_materials["marks"] = m
	return _materials["marks"]


## Color por vértice con transparencia (degradés: sombra del marco).
static func _vertex_color_material() -> Material:
	if not _materials.has("vcol"):
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.vertex_color_use_as_albedo = true
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		_materials["vcol"] = m
	return _materials["vcol"]
