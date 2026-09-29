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

static var _materials: Dictionary = {}


## Nodo 3D con la capa `layer` del escenario para la vista `view`.
static func build(view: BoardView25D, layer: String) -> Node3D:
	var root := Node3D.new()
	root.name = "Board25D_" + layer
	if layer == LAYER_BOARD:
		_board(root, view)
	else:
		_back(root, view)
	return root


## Suelta materiales y mallas del armado (después de hornear no se usan).
static func release_build_caches() -> void:
	_materials.clear()


## Medio ancho y medio largo del tablero con el marco (unidades del mundo).
static func outer_half(view: BoardView25D) -> Vector2:
	return view.plane.size / 2.0 + Vector2.ONE * UiTheme.BOARD25D_FRAME_W


# --- Tablero -----------------------------------------------------------------------

static func _board(root: Node3D, view: BoardView25D) -> void:
	var half := view.plane.size / 2.0
	var fw := UiTheme.BOARD25D_FRAME_W
	var base := UiTheme.BOARD25D_BASE
	var tile_h := UiTheme.BOARD25D_TILE_H
	# Base: la "caja" del tablero debajo de las baldosas (se ve en las juntas).
	var slab := _part(root, Props3DMeshes.rounded_box(Vector3(half.x * 2.0 + 4.0, base, half.y * 2.0 + 4.0), 4.0),
		_plastic(UiTheme.BOARD25D_GROUT, 0.0, 0.0, 0.0))
	slab.position = Vector3(0, -tile_h * 0.6 - base / 2.0, 0)
	# Baldosas a cuadros: cajitas con los cantos redondeados (el borde toma luz).
	var gap := UiTheme.BOARD25D_TILE_GAP
	var tile := Props3DMeshes.rounded_box(Vector3(view.cell - gap * 2.0, tile_h, view.cell - gap * 2.0), UiTheme.BOARD25D_TILE_ROUND)
	var light := _plastic(UiTheme.BOARD25D_TILE_LIGHT, 0.0, 0.12, 0.0)
	var dark := _plastic(UiTheme.BOARD25D_TILE_DARK, 0.0, 0.12, 0.0)
	for y in view.rows:
		for x in view.cols:
			var t := _part(root, tile, light if (x + y) % 2 == 0 else dark)
			var c := view.to_world(view.plane.position + (Vector2(x, y) + Vector2(0.5, 0.5)) * view.cell)
			t.position = c + Vector3(0, -tile_h / 2.0, 0)
	# Sombra suave del marco sobre el piso (arriba y a la izquierda, como si la
	# luz viniera de atrás): tiras transparentes con degradé, sin luces reales.
	_edge_shade(root, half)
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


## Sombra del marco sobre el piso: dos tiras (arriba y a la izquierda) que
## van de tinta transparente a nada, apenas sobre las baldosas.
static func _edge_shade(root: Node3D, half: Vector2) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var y := 0.6
	var w := UiTheme.BOARD25D_EDGE_SHADE_W
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
static func _plastic(col: Color, ink: float, coat := 0.22, spec := 0.95) -> Material:
	var key := "p|%s|%.2f|%.2f|%.2f" % [col.to_html(), ink, coat, spec]
	if _materials.has(key):
		return _materials[key]
	var lum := col.get_luminance()
	var dark := lum < 0.2
	var low := col.lightened(0.02) if dark else col.darkened(0.42 if lum < 0.8 else 0.16)
	low = low.lerp(UiTheme.MASCOT_SHADE_TINT, 0.14)
	var mid := col.lightened(0.1) if dark else col
	var high := col.lightened(0.45 if dark else (0.08 if lum > 0.85 else UiTheme.BOARD25D_LIGHT))
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
