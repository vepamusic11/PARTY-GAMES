class_name GameDiorama
extends RefCounted
## Dioramas 3D de los juegos para las tarjetas del lobby (ADR 0018): una
## escena chica y colorida de cada juego (el tablero de Arena con estrellas y
## joystick, la mesa de ping pong, el reloj gigante…) armada con piezas de
## juguete y el mismo plástico que las mascotas (toy_plastic.gdshader).
## `tools/make_dioramas.gd` la renderiza una vez a `assets/thumbs/diorama/`
## y la tarjeta muestra esa imagen: en la TV no se hace nada de 3D.
##
## Concepto: *diorama*. Una maqueta en miniatura de una escena, vista desde
## arriba y un poco de costado, con el fondo desenfocado (como una foto con
## poca profundidad de campo). Ejemplo: la tarjeta de Pool loco es una mesa
## de juguete con las bolas amontonadas y dos mascotas mirándola.
##
## Cada juego tiene una receta en `build`; uno que no la tenga (juego nuevo)
## usa `_generic`: el escenario redondo con baldosas de su color (`accent`)
## y el control que usa (joystick, botón o deslizador) como pieza grande,
## igual que en la maqueta (`docs/design/referencia_lobby.webp`).
##
## Unidades: las de Mascot3D (una mascota mide ~11 de alto). El escenario
## redondo mide 2 × ARENA_R de ancho. Las piezas se arman con las recetas de
## `Props3DMeshes` (cajas redondeadas, tornos, almohadones).

const SHADER_TOY := preload("res://core/mascot3d/toy_plastic.gdshader")
const SHADER_INK := preload("res://core/mascot3d/ink_outline.gdshader")

const ARENA_R := 40.0          ## Radio del escenario redondo.
const TILE_R := 4.6            ## Radio de cada baldosa hexagonal.
const INK := 0.32              ## Contorno de las piezas (unidades del mundo).
const INK_THIN := 0.2

## Recetas con nombre (las demás usan la genérica).
const RECIPES: Array[String] = ["arena", "pingpong", "tap_race", "stop_clock", "dodge", "paint", "sumo",
	"karts", "scroller", "memory", "quickdraw", "pool", "hurdles"]

static var _materials: Dictionary = {}


## Escena del juego `info` (de MiniGameRegistry): {"fg": Node3D del frente,
## "bg": Node3D del fondo (se desenfoca), "camera": {pos, target, fov}}.
static func build(info: Dictionary) -> Dictionary:
	var id := str(info.get("id", ""))
	var fg := Node3D.new()
	fg.name = "Diorama_" + id
	var bg := Node3D.new()
	bg.name = "Fondo_" + id
	var accent: Color = info.get("accent", UiTheme.BRICKS[5])
	var cam := default_camera()
	match id:
		"arena": cam = _arena(fg, bg)
		"pingpong": cam = _pingpong(fg, bg)
		"tap_race": cam = _tap_race(fg, bg)
		"stop_clock": cam = _stop_clock(fg, bg)
		"dodge": cam = _dodge(fg, bg)
		"paint": cam = _paint(fg, bg)
		"sumo": cam = _sumo(fg, bg)
		"karts": cam = _karts(fg, bg)
		"scroller": cam = _scroller(fg, bg)
		"memory": cam = _memory(fg, bg)
		"quickdraw": cam = _quickdraw(fg, bg)
		"pool": cam = _pool(fg, bg)
		"hurdles": cam = _hurdles(fg, bg)
		_: _generic(fg, bg, accent, str(info.get("layout", Protocol.LAYOUT_JOYSTICK)))
	return {"fg": fg, "bg": bg, "camera": cam, "sky": sky_for(id, accent)}


static func has_recipe(game_id: String) -> bool:
	return game_id in RECIPES


## Cámara de siempre: desde adelante y arriba, mirando el centro del escenario.
static func default_camera() -> Dictionary:
	return {"pos": Vector3(0, 46, 78), "target": Vector3(0, 2, 2), "fov": 34.0}


## Cielo (arriba, abajo) detrás del fondo desenfocado.
static func sky_for(game_id: String, accent: Color) -> Array[Color]:
	match game_id:
		"quickdraw":
			return [UiTheme.QD_SKY_MID, UiTheme.QD_HORIZON]
		"memory", "stop_clock":
			return [accent.darkened(0.35), accent.lerp(UiTheme.PAPER, 0.35)]
	return [UiTheme.BG_SKY_TOP, UiTheme.BG_SKY_MID.lerp(UiTheme.PAPER, 0.35)]


# --- Materiales ------------------------------------------------------------------------

## Plástico de juguete de color `col`, con contorno de tinta de `ink`
## unidades (0 = sin contorno). `lit`: cuánto se aclara la cara iluminada.
## Las caras de arriba (pisos, tapas) miran a la luz: con `flat` el color
## iluminado es el color mismo (no pastel), como las baldosas de la maqueta.
static func plastic(col: Color, ink := INK, lit := 0.28, flat := false, coat := 0.2) -> ShaderMaterial:
	var key := "p|%s|%.2f|%.2f|%s|%.2f" % [col.to_html(), ink, lit, flat, coat]
	if _materials.has(key):
		return _materials[key]
	var lum := col.get_luminance()
	var dark := lum < 0.2
	var low := col.lightened(0.04) if dark else col.darkened(0.48 if lum < 0.8 else 0.28)
	low = low.lerp(UiTheme.MASCOT_SHADE_TINT, 0.14)
	var mid := col.darkened(0.1) if flat else col
	var high := col.lightened(0.08 if flat else lit)
	if dark:
		mid = col.lightened(0.1)
		high = col.lightened(0.4)
	var m := ShaderMaterial.new()
	m.shader = SHADER_TOY
	var params := {"low_color": low, "mid_color": mid, "high_color": high,
		"bounce_color": mid.lightened(0.15), "bounce_strength": 0.3, "rim_color": Color.WHITE, "rim_strength": 0.25,
		"spec_strength": 0.9, "spec_size": 0.02, "coat_strength": coat, "edge_color": col.darkened(0.25),
		"edge_strength": 0.25, "sky_strength": 0.25}
	for k: String in params:
		m.set_shader_parameter(k, params[k])
	if ink > 0.0:
		m.next_pass = _ink(ink)
	_materials[key] = m
	return m


## Metal dorado o plateado (estrellas, aros).
static func metal(col: Color, ink := INK) -> ShaderMaterial:
	var key := "m|%s|%.2f" % [col.to_html(), ink]
	if _materials.has(key):
		return _materials[key]
	var m := ShaderMaterial.new()
	m.shader = SHADER_TOY
	var params := {"low_color": col.darkened(0.42).lerp(UiTheme.PROP_STAR_SHADE, 0.3), "mid_color": col,
		"high_color": col.lerp(UiTheme.PAPER, 0.6), "bounce_color": col.lightened(0.3), "bounce_strength": 0.5,
		"rim_color": Color.WHITE, "rim_strength": 0.3, "spec_strength": 1.0, "spec_size": 0.03, "coat_strength": 0.35}
	for k: String in params:
		m.set_shader_parameter(k, params[k])
	if ink > 0.0:
		m.next_pass = _ink(ink)
	_materials[key] = m
	return m


static func _ink(width: float) -> ShaderMaterial:
	var key := "ink|%.2f" % width
	if not _materials.has(key):
		var m := ShaderMaterial.new()
		m.shader = SHADER_INK
		m.set_shader_parameter("ink", UiTheme.INK)
		m.set_shader_parameter("width", width)
		m.set_shader_parameter("min_px", 0.0)
		_materials[key] = m
	return _materials[key]


## Suelta materiales y mallas (después de renderizar).
static func release() -> void:
	_materials.clear()


# --- Piezas ----------------------------------------------------------------------------

static func _part(parent: Node3D, mesh: Mesh, mat: Material, pos := Vector3.ZERO, scl := Vector3.ONE,
		rot_deg := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position = pos
	mi.scale = scl
	mi.rotation_degrees = rot_deg
	parent.add_child(mi)
	return mi


static func _node(parent: Node3D, pos := Vector3.ZERO, rot_deg := Vector3.ZERO, scl := 1.0) -> Node3D:
	var n := Node3D.new()
	n.position = pos
	n.rotation_degrees = rot_deg
	n.scale = Vector3.ONE * scl
	parent.add_child(n)
	return n


static func _box(parent: Node3D, size: Vector3, col: Color, pos := Vector3.ZERO, radius := -1.0,
		ink := INK, flat := false, rot_deg := Vector3.ZERO) -> MeshInstance3D:
	if radius < 0.0:
		radius = minf(minf(size.x, size.y), size.z) * 0.22
	return _part(parent, Props3DMeshes.rounded_box(size, radius, 3), plastic(col, ink, 0.28, flat), pos, Vector3.ONE, rot_deg)


## Cilindro (con canto redondeado arriba) de radio `r` y alto `h`, base en y = 0.
static func _cylinder(parent: Node3D, r: float, h: float, col: Color, pos := Vector3.ZERO, ink := INK,
		segs := 32, flat := false) -> MeshInstance3D:
	var bevel := minf(r, h) * 0.18
	var prof := PackedVector2Array([Vector2(0, 0), Vector2(r - bevel, 0), Vector2(r, bevel), Vector2(r, h - bevel),
		Vector2(r - bevel * 0.3, h - bevel * 0.3), Vector2(r - bevel, h), Vector2(0, h)])
	var key := "dcyl:%.2f:%.2f:%d" % [r, h, segs]
	return _part(parent, Props3DMeshes.lathe(key, prof, segs), plastic(col, ink, 0.28, flat), pos)


static func _sphere(parent: Node3D, r: float, col: Color, pos: Vector3, ink := INK) -> MeshInstance3D:
	return _part(parent, Props3DMeshes.sphere(), plastic(col, ink), pos, Vector3.ONE * r)


## Baldosa hexagonal con el canto de arriba biselado (torno de 6 lados).
static func _hex_tile(parent: Node3D, pos: Vector3, r: float, h: float, col: Color) -> void:
	var prof := PackedVector2Array([Vector2(0, 0), Vector2(r, 0), Vector2(r, h * 0.55), Vector2(r * 0.86, h), Vector2(0, h)])
	var key := "hex:%.2f:%.2f" % [r, h]
	_part(parent, Props3DMeshes.lathe(key, prof, 6), plastic(col, 0.0, 0.2, true, 0.12), pos, Vector3.ONE, Vector3(0, 30, 0))


## Estrella dorada "almohadón" (la de Props3D), parada o acostada.
static func _star(parent: Node3D, pos: Vector3, size: float, rot_deg := Vector3(-8, 0, 0), col := UiTheme.GOLD) -> void:
	var mesh := Props3DMeshes.pillow("star40", Props3DMeshes.star_outline(40.0, 0.5), 10.0)
	_part(parent, mesh, metal(col, INK), pos, Vector3.ONE * size / 40.0, rot_deg)


## Escenario redondo: base con canto, mosaico de baldosas hexagonales de
## `colors` y un aro de bloques de colores alrededor (el "estadio").
static func _round_stage(root: Node3D, colors: Array, rim: Array = UiTheme.BRICKS, seed := 7,
		radius := ARENA_R) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	_cylinder(root, radius + 1.5, 3.0, UiTheme.INK.lerp(UiTheme.PAPER, 0.25), Vector3(0, -3.0, 0), INK, 64)
	var dx := TILE_R * sqrt(3.0)
	var rows := int(radius / (TILE_R * 1.5)) + 1
	for row in range(-rows, rows + 1):
		var z := row * TILE_R * 1.5
		var off := dx * 0.5 if row % 2 != 0 else 0.0
		var cols := int(radius / dx) + 1
		for c in range(-cols, cols + 1):
			var x := c * dx + off
			if Vector2(x, z).length() > radius - TILE_R * 0.7:
				continue
			var col: Color = colors[rng.randi() % colors.size()]
			_hex_tile(root, Vector3(x, 0, z), TILE_R * 0.93, 0.9 + rng.randf() * 0.25, col)
	# Aro de bloques (el "estadio"): en la mitad de atrás más altos.
	var n := 28
	for k in n:
		var a := TAU * (k + 0.5) / n
		var p := Vector3(sin(a), 0, cos(a)) * (radius + 3.2)
		var back := cos(a) < 0.0
		var h := 5.0 if back else 2.6
		var b := _box(root, Vector3(radius * TAU / n - 0.6, h, 3.6), rim[k % rim.size()], p + Vector3(0, h / 2.0 - 0.6, 0),
			1.1, INK_THIN, true)
		b.rotation = Vector3(0, a, 0)


## Piso rectangular de baldosas cuadradas (tablero, pista).
static func _tile_floor(root: Node3D, size: Vector2, cell: float, colors: Array, pos := Vector3.ZERO,
		pattern := "checker", seed := 3) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	_box(root, Vector3(size.x + 1.6, 3.0, size.y + 1.6), UiTheme.INK.lerp(UiTheme.PAPER, 0.3), pos + Vector3(0, -1.6, 0), 1.0, INK)
	var nx := int(round(size.x / cell))
	var nz := int(round(size.y / cell))
	for i in nx:
		for j in nz:
			var col: Color
			match pattern:
				"checker": col = colors[(i + j) % colors.size()]
				"random": col = colors[rng.randi() % colors.size()]
				_: col = colors[j % colors.size()]
			var p := pos + Vector3(-size.x / 2.0 + (i + 0.5) * cell, 0.3, -size.y / 2.0 + (j + 0.5) * cell)
			_box(root, Vector3(cell - 0.35, 0.8, cell - 0.35), col, p, 0.3, 0.0, true)


## Bloque de juguete con cuatro botones arriba.
static func _toy_block(parent: Node3D, pos: Vector3, size: float, col: Color, rot_y := 0.0, ink := INK) -> Node3D:
	var n := _node(parent, pos, Vector3(0, rot_y, 0))
	_box(n, Vector3.ONE * size, col, Vector3(0, size / 2.0, 0), size * 0.14, ink)
	var mat := plastic(col, ink * 0.7)
	for x in [-0.24, 0.24]:
		for z in [-0.24, 0.24]:
			_part(n, Props3DMeshes.cone(0.92), mat, Vector3(x * size, size * 0.98, z * size), Vector3(0.15, 0.13, 0.15) * size)
	return n


## Fondo "estadio": torres de bloques de colores alrededor (se desenfoca).
static func _towers(bg: Node3D, radius := 70.0, count := 16, seed := 11, z_min := -200.0) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	for k in count:
		var a := lerpf(-1.25, 1.25, float(k) / (count - 1)) + rng.randf_range(-0.05, 0.05)
		var r := radius + rng.randf_range(-6.0, 14.0)
		var base := Vector3(sin(a) * r * 1.35, -4.0, -cos(a) * r)
		if base.z < z_min:
			continue
		var stack := 2 + rng.randi() % 3
		var size := rng.randf_range(10.0, 15.0)
		for s in stack:
			var col: Color = UiTheme.BRICKS[rng.randi() % UiTheme.BRICKS.size()]
			_toy_block(bg, base + Vector3(rng.randf_range(-1, 1), s * size * 1.02, 0), size, col, rng.randf_range(-25, 25), 0.0)
	# Estrellas doradas sobre las torres y nubes.
	for k in 5:
		var a := lerpf(-1.0, 1.0, k / 4.0)
		_star(bg, Vector3(sin(a) * radius * 1.3, 42.0 + rng.randf_range(0, 12), -cos(a) * radius - 10), 7.0,
			Vector3(0, rng.randf_range(-30, 30), rng.randf_range(-20, 20)))


## Mascota 3D (Mascot3D) del lugar `slot` (color y estilo por defecto).
static func _mascot(parent: Node3D, slot: int, pos: Vector3, rot_y := 0.0, mood := PlayerAvatar.Mood.HAPPY,
		anim := {}, scl := 1.0) -> Mascot3D:
	var m := Mascot3D.new()
	m.setup(Protocol.player_color(slot), slot)
	parent.add_child(m)
	m.apply(mood, anim)
	m.position = pos
	m.rotation_degrees = Vector3(0, rot_y, 0)
	m.scale = Vector3.ONE * scl
	return m


# --- Piezas de los controles (la pieza grande de las recetas genéricas) --------------------

## Joystick de arcade: base oscura, palanca y bocha de color.
static func _joystick(parent: Node3D, pos: Vector3, col: Color, scl := 1.0) -> Node3D:
	var n := _node(parent, pos, Vector3(0, -15, 0), scl)
	_cylinder(n, 7.0, 3.2, UiTheme.PHONE_DISH, Vector3.ZERO, INK, 40)
	_cylinder(n, 5.2, 4.0, UiTheme.PHONE_DISH_RIM, Vector3.ZERO, INK_THIN, 40)
	var stick := _node(n, Vector3(0, 3.5, 0), Vector3(0, 0, -12))
	_cylinder(stick, 0.9, 8.5, UiTheme.MASCOT_METAL, Vector3.ZERO, INK_THIN, 16)
	_sphere(stick, 3.6, col, Vector3(0, 10.5, 0))
	return n


## Botón de arcade grande: carcasa y cúpula de color.
static func _big_button(parent: Node3D, pos: Vector3, col: Color, scl := 1.0) -> Node3D:
	var n := _node(parent, pos, Vector3.ZERO, scl)
	_cylinder(n, 8.5, 3.0, UiTheme.PHONE_DISH, Vector3.ZERO, INK, 48)
	var dome := PackedVector2Array([Vector2(0, 0), Vector2(6.6, 0), Vector2(6.6, 2.2), Vector2(6.2, 3.4), Vector2(5.2, 4.3),
		Vector2(3.4, 4.9), Vector2(0, 5.1)])
	_part(n, Props3DMeshes.lathe("dio_dome", dome, 40), plastic(col), Vector3(0, 2.6, 0))
	return n


## Deslizador: canal y perilla de color.
static func _slider(parent: Node3D, pos: Vector3, col: Color, scl := 1.0) -> Node3D:
	var n := _node(parent, pos, Vector3(0, -12, 0), scl)
	_box(n, Vector3(22, 2.4, 6), UiTheme.PHONE_DISH, Vector3(0, 1.2, 0), 1.2)
	_box(n, Vector3(18, 1.0, 1.6), UiTheme.PHONE_DISH_RIM, Vector3(0, 2.6, 0), 0.5, 0.0)
	_cylinder(n, 3.6, 3.0, col, Vector3(4, 2.4, 0), INK, 32)
	return n


# --- Recetas ----------------------------------------------------------------------------

## Genérica: escenario con baldosas del color del juego y su control grande.
static func _generic(fg: Node3D, bg: Node3D, accent: Color, layout: String) -> void:
	var colors := [accent, accent.lightened(0.25), accent.darkened(0.15), accent.lerp(UiTheme.PAPER, 0.5),
		accent.lerp(UiTheme.BRICKS[6], 0.4)]
	_round_stage(fg, colors)
	_towers(bg)
	match layout:
		Protocol.LAYOUT_ONE_BUTTON:
			_big_button(fg, Vector3(-18, 0.8, 14), UiTheme.BRICKS[0], 1.3)
		Protocol.LAYOUT_SLIDER_H:
			_slider(fg, Vector3(-16, 0.8, 14), UiTheme.BRICKS[0], 1.2)
		_:
			_joystick(fg, Vector3(-19, 0.8, 12), UiTheme.BRICKS[0], 1.25)
	_star(fg, Vector3(14, 9, -8), 5.0)
	_mascot(fg, 1, Vector3(8, 0.8, 10), -20)


## Arena de estrellas: mosaico azul y violeta, estrellas y el joystick.
static func _arena(fg: Node3D, bg: Node3D) -> Dictionary:
	_round_stage(fg, [UiTheme.BRICKS[5], UiTheme.BRICKS[6], UiTheme.BRICKS[4], UiTheme.BRICKS[5].lightened(0.3),
		UiTheme.BRICKS[7], UiTheme.BRICKS[2]], UiTheme.BRICKS, 5)
	_towers(bg)
	_joystick(fg, Vector3(-24, 0.8, 12), UiTheme.BRICKS[0], 1.25)
	_star(fg, Vector3(2, 9.5, -14), 7.5, Vector3(-5, 12, 0))
	_star(fg, Vector3(20, 6, 6), 5.0, Vector3(-10, -20, 8))
	_star(fg, Vector3(-6, 5, 2), 4.0, Vector3(-10, 25, -6))
	_mascot(fg, 0, Vector3(9, 0.8, -2), 0, PlayerAvatar.Mood.HAPPY, {"walk": 0.25, "look": Vector2(-1, 0), "t": 0.3})
	_mascot(fg, 2, Vector3(24, 0.8, -12), -30, PlayerAvatar.Mood.HAPPY, {"wave": true, "t": 0.2}, 0.9)
	return default_camera()


## Ping Pong: mesa azul con la red, dos paletas y la pelota.
static func _pingpong(fg: Node3D, bg: Node3D) -> Dictionary:
	_round_stage(fg, [UiTheme.BRICKS[4], UiTheme.BRICKS[4].lightened(0.25), UiTheme.BRICKS[5].lightened(0.2), UiTheme.PAPER_DIM],
		UiTheme.BRICKS, 9)
	_towers(bg)
	var table := _node(fg, Vector3(0, 0.8, 0), Vector3(0, 0, 0))
	_box(table, Vector3(44, 2.4, 24), UiTheme.TABLE_BLUE, Vector3(0, 9.0, 0), 0.8, INK, true)
	for x in [-18.0, 18.0]:
		for z in [-9.0, 9.0]:
			_box(table, Vector3(1.8, 8.0, 1.8), UiTheme.INK.lerp(UiTheme.PAPER, 0.35), Vector3(x, 4.0, z), 0.5, INK_THIN)
	# Líneas blancas y la red.
	_box(table, Vector3(43, 0.3, 0.7), UiTheme.PAPER, Vector3(0, 10.25, 11.2), 0.1, 0.0, true)
	_box(table, Vector3(43, 0.3, 0.7), UiTheme.PAPER, Vector3(0, 10.25, -11.2), 0.1, 0.0, true)
	_box(table, Vector3(0.7, 0.3, 23), UiTheme.PAPER, Vector3(-21.3, 10.25, 0), 0.1, 0.0, true)
	_box(table, Vector3(0.7, 0.3, 23), UiTheme.PAPER, Vector3(21.3, 10.25, 0), 0.1, 0.0, true)
	_box(table, Vector3(43, 0.3, 0.4), UiTheme.PAPER, Vector3(0, 10.25, 0), 0.1, 0.0, true)
	_box(table, Vector3(0.6, 3.6, 26), UiTheme.PAPER, Vector3(0, 12.0, 0), 0.25, INK_THIN)
	# Paletas del color de cada jugador y la pelota en el aire.
	for side in [-1, 1]:
		var col: Color = Protocol.player_color(0 if side < 0 else 1)
		var pad := _node(fg, Vector3(side * 25.0, 14.0, 4.0 * side), Vector3(0, 90 * side, 20 * side))
		_cylinder(pad, 4.2, 1.0, col, Vector3.ZERO, INK, 32).rotation_degrees = Vector3(90, 0, 0)
		_box(pad, Vector3(1.6, 5.0, 1.4), UiTheme.QD_WOOD, Vector3(0, -6.2, 0.5), 0.5, INK_THIN)
	_sphere(fg, 1.4, UiTheme.PAPER, Vector3(-7, 17, 3), INK_THIN)
	_mascot(fg, 0, Vector3(-30, 0.8, 12), 40, PlayerAvatar.Mood.HAPPY, {"wave": true, "t": 0.1})
	_mascot(fg, 1, Vector3(30, 0.8, 10), -40, PlayerAvatar.Mood.SURPRISED, {})
	return {"pos": Vector3(0, 44, 70), "target": Vector3(0, 7, 2), "fov": 36.0}


## Carrera de toques: pista a cuadros naranja y amarilla con la meta, el
## botón gigante y dos mascotas corriendo.
static func _tap_race(fg: Node3D, bg: Node3D) -> Dictionary:
	_round_stage(fg, [UiTheme.BRICKS[1], UiTheme.BRICKS[2], UiTheme.BRICKS[1].lightened(0.25), UiTheme.BRICKS[2].lightened(0.3)],
		UiTheme.BRICKS, 13)
	_towers(bg)
	# Meta a cuadros.
	for i in 12:
		for j in 2:
			var col := UiTheme.INK if (i + j) % 2 == 0 else UiTheme.PAPER
			_box(fg, Vector3(2.6, 0.6, 2.6), col, Vector3(22 + j * 2.6, 1.9, -14 + i * 2.6), 0.2, 0.0, true)
	_big_button(fg, Vector3(-21, 0.8, 12), UiTheme.BRICKS[3], 1.35)
	_mascot(fg, 0, Vector3(4, 0.8, -6), 0, PlayerAvatar.Mood.HAPPY, {"walk": 0.3, "look": Vector2(1, 0), "t": 0.4})
	_mascot(fg, 1, Vector3(-4, 0.8, 6), 0, PlayerAvatar.Mood.ANGRY, {"walk": 0.8, "look": Vector2(1, 0), "t": 0.9})
	return default_camera()


## Reloj exacto: un reloj despertador gigante sobre el escenario violeta.
static func _stop_clock(fg: Node3D, bg: Node3D) -> Dictionary:
	_round_stage(fg, [UiTheme.BRICKS[6], UiTheme.BRICKS[7], UiTheme.BRICKS[6].lightened(0.25), UiTheme.BRICKS[7].darkened(0.15)],
		UiTheme.BRICKS, 17)
	_towers(bg)
	var clock := _node(fg, Vector3(4, 13.5, -6), Vector3(-14, 0, 0), 0.85)
	var rim := PackedVector2Array([Vector2(0, -2.6), Vector2(13.2, -2.6), Vector2(14.2, -1.4), Vector2(14.2, 1.6),
		Vector2(13.2, 2.6), Vector2(11.4, 2.6), Vector2(11.4, 1.2), Vector2(0, 1.2)])
	_part(clock, Props3DMeshes.lathe("dio_clock", rim, 56), plastic(UiTheme.BRICKS[6].lightened(0.1)), Vector3.ZERO,
		Vector3.ONE, Vector3(90, 0, 0))
	_cylinder(clock, 11.5, 0.6, UiTheme.PAPER, Vector3(0, 0, 1.0), 0.0, 56).rotation_degrees = Vector3(90, 0, 0)
	for k in 12:
		var a := TAU * k / 12.0
		var big := k % 3 == 0
		var mark := _box(clock, Vector3(0.9 if big else 0.6, 2.2 if big else 1.4, 0.5), UiTheme.INK,
			Vector3(sin(a) * 9.2, cos(a) * 9.2, 1.9), 0.2, 0.0)
		mark.rotation = Vector3(0, 0, -a)
	var hand1 := _box(clock, Vector3(1.0, 7.2, 0.5), UiTheme.INK, Vector3(0, 3.2, 2.3), 0.3, 0.0)
	hand1.rotation_degrees = Vector3(0, 0, 0)
	var hand2 := _node(clock, Vector3(0, 0, 2.6), Vector3(0, 0, -115))
	_box(hand2, Vector3(0.8, 9.0, 0.4), UiTheme.DANGER, Vector3(0, 4.0, 0), 0.3, 0.0)
	_sphere(clock, 1.1, UiTheme.INK, Vector3(0, 0, 2.8), 0.0)
	# Campanas y patas.
	for side in [-1, 1]:
		var bell := PackedVector2Array([Vector2(0, 0), Vector2(4.6, 0), Vector2(4.4, 1.6), Vector2(3.4, 3.4), Vector2(0, 4.2)])
		_part(clock, Props3DMeshes.lathe("dio_bell", bell, 32), metal(UiTheme.GOLD), Vector3(side * 9.0, 11.0, -1.0),
			Vector3.ONE, Vector3(0, 0, -side * 32.0))
		_box(clock, Vector3(1.6, 5.0, 1.6), UiTheme.BRICKS[6].darkened(0.2), Vector3(side * 8.0, -14.0, 0), 0.6, INK_THIN,
			false, Vector3(0, 0, side * 20.0))
	_big_button(fg, Vector3(-24, 0.8, 14), UiTheme.BRICKS[0], 1.1)
	_mascot(fg, 3, Vector3(21, 0.8, 10), -25, PlayerAvatar.Mood.SURPRISED, {})
	return default_camera()


## Esquivar: bloques de juguete que caen (con su sombra) y mascotas que escapan.
static func _dodge(fg: Node3D, bg: Node3D) -> Dictionary:
	_tile_floor(fg, Vector2(76, 44), 7.6, [UiTheme.PAPER, UiTheme.BG_SKY_MID.lerp(UiTheme.PAPER, 0.45)], Vector3(0, 0, 0))
	_towers(bg)
	var drops := [[Vector3(-14, 16, -6), 0], [Vector3(10, 22, -12), 5], [Vector3(22, 12, 4), 3], [Vector3(-26, 24, -14), 7]]
	for d: Array in drops:
		var p: Vector3 = d[0]
		_toy_block(fg, p, 8.0, UiTheme.BRICKS[int(d[1])], 20.0 * (int(d[1]) - 3))
		# Sombra en el piso: donde va a caer.
		_cylinder(fg, 5.2, 0.2, UiTheme.INK.lerp(UiTheme.FLOOR, 0.55), Vector3(p.x, 1.1, p.z), 0.0, 32, true)
	_toy_block(fg, Vector3(-2, 1.1, 10), 8.0, UiTheme.BRICKS[2], 12.0)
	_mascot(fg, 0, Vector3(-12, 1.1, 8), 0, PlayerAvatar.Mood.SURPRISED, {"walk": 0.3, "look": Vector2(1, 0)})
	_mascot(fg, 1, Vector3(14, 1.1, 12), 0, PlayerAvatar.Mood.HAPPY, {"walk": 0.7, "look": Vector2(-1, 0)})
	return {"pos": Vector3(0, 38, 50), "target": Vector3(0, 4, 2), "fov": 36.0}


## Pintar el piso: baldosas pintadas de los cuatro colores.
static func _paint(fg: Node3D, bg: Node3D) -> Dictionary:
	var tints: Array = []
	for s in 4:
		tints.append(Protocol.player_color(s).lerp(UiTheme.PAPER, 0.2))
	var size := Vector2(72, 42)
	var cell := 6.0
	_box(fg, Vector3(size.x + 1.6, 3.0, size.y + 1.6), UiTheme.INK.lerp(UiTheme.PAPER, 0.3), Vector3(0, -1.6, 0), 1.0, INK)
	var rng := RandomNumberGenerator.new()
	rng.seed = 21
	for i in int(size.x / cell):
		for j in int(size.y / cell):
			# Cada jugador pintó su esquina (con bordes irregulares).
			var u := float(i) / (size.x / cell) + rng.randf_range(-0.12, 0.12)
			var v := float(j) / (size.y / cell) + rng.randf_range(-0.12, 0.12)
			var q := (1 if u > 0.5 else 0) + (2 if v > 0.5 else 0)
			var col: Color = tints[q] if rng.randf() > 0.18 else UiTheme.FLOOR
			var p := Vector3(-size.x / 2.0 + (i + 0.5) * cell, 0.3, -size.y / 2.0 + (j + 0.5) * cell)
			_box(fg, Vector3(cell - 0.4, 0.8, cell - 0.4), col, p, 0.4, 0.0, true)
	_towers(bg)
	_mascot(fg, 0, Vector3(-18, 0.8, -8), 0, PlayerAvatar.Mood.HAPPY, {"walk": 0.2, "look": Vector2(1, 0)})
	_mascot(fg, 1, Vector3(18, 0.8, -8), 0, PlayerAvatar.Mood.HAPPY, {"walk": 0.6, "look": Vector2(-1, 0)})
	_mascot(fg, 2, Vector3(-16, 0.8, 12), 0, PlayerAvatar.Mood.ANGRY, {"walk": 0.4, "look": Vector2(1, 0)})
	_mascot(fg, 3, Vector3(16, 0.8, 12), -20, PlayerAvatar.Mood.HAPPY, {"wave": true, "t": 0.3})
	return {"pos": Vector3(0, 36, 48), "target": Vector3(0, 1, 3), "fov": 38.0}


## Empujones: isla redonda sobre el agua y mascotas empujándose.
static func _sumo(fg: Node3D, bg: Node3D) -> Dictionary:
	_cylinder(fg, 60.0, 1.0, UiTheme.KARTS_PUDDLE, Vector3(0, -4.0, 0), 0.0, 64, true)
	for k in 9:
		var a := TAU * k / 9.0
		_cylinder(fg, 2.2 + (k % 3), 0.3, UiTheme.KARTS_PUDDLE_SHINE, Vector3(sin(a) * 46, -2.9, cos(a) * 30), 0.0, 24, true)
	_cylinder(fg, 30.0, 4.0, UiTheme.QD_SAND_NEAR, Vector3(0, -3.2, 0), INK, 64)
	_cylinder(fg, 28.0, 1.2, UiTheme.BRICKS[3], Vector3(0, 0.0, 0), 0.0, 64, true)
	_cylinder(fg, 20.0, 0.3, UiTheme.BRICKS[3].lightened(0.2), Vector3(0, 1.1, 0), 0.0, 64, true)
	_cylinder(fg, 10.0, 0.35, UiTheme.PAPER, Vector3(0, 1.2, 0), 0.0, 48, true)
	_cylinder(fg, 8.8, 0.45, UiTheme.BRICKS[3].lightened(0.2), Vector3(0, 1.3, 0), 0.0, 48, true)
	_towers(bg, 80.0)
	_mascot(fg, 0, Vector3(-6, 1.2, 0), 0, PlayerAvatar.Mood.ANGRY, {"walk": 0.3, "look": Vector2(1, 0)})
	_mascot(fg, 1, Vector3(5.5, 1.2, 1), -70, PlayerAvatar.Mood.SURPRISED, {})
	_mascot(fg, 2, Vector3(-16, 1.2, 14), 0, PlayerAvatar.Mood.HAPPY, {"walk": 0.7, "look": Vector2(1, 0)})
	_mascot(fg, 3, Vector3(18, 1.2, -12), -40, PlayerAvatar.Mood.DIZZY, {})
	return {"pos": Vector3(0, 44, 66), "target": Vector3(0, 1, 2), "fov": 36.0}


## Karts: curva de asfalto con cordón de colores, pasto y dos karts.
static func _karts(fg: Node3D, bg: Node3D) -> Dictionary:
	_box(fg, Vector3(110, 3.0, 60), UiTheme.KARTS_GRASS, Vector3(0, -1.6, 0), 1.0, INK, true)
	var road := _node(fg, Vector3(0, 0, 0), Vector3(0, -12, 0))
	_box(road, Vector3(120, 1.0, 18), UiTheme.KARTS_ROAD, Vector3(0, 0.2, 2), 0.5, 0.0, true)
	for k in 14:
		_box(road, Vector3(7.4, 1.4, 2.0), UiTheme.BRICKS[0] if k % 2 == 0 else UiTheme.PAPER, Vector3(-52 + k * 8.0, 0.6, -8.2), 0.4, INK_THIN, true)
		_box(road, Vector3(7.4, 1.4, 2.0), UiTheme.BRICKS[5] if k % 2 == 0 else UiTheme.PAPER, Vector3(-52 + k * 8.0, 0.6, 12.2), 0.4, INK_THIN, true)
		if k % 2 == 0:
			_box(road, Vector3(4.0, 0.2, 0.7), UiTheme.PAPER, Vector3(-52 + k * 8.0, 0.8, 2), 0.1, 0.0, true)
	for p in [Vector3(-34, 0, -22), Vector3(30, 0, -24), Vector3(48, 0, -14), Vector3(-52, 0, -12)]:
		_sphere(fg, 6.0, UiTheme.KARTS_TREE, p + Vector3(0, 9, 0))
		_cylinder(fg, 1.2, 5.0, UiTheme.QD_WOOD, p, INK_THIN, 12)
	_kart(road, Vector3(-8, 0.8, 5), 0)
	_kart(road, Vector3(14, 0.8, -1), 1)
	_star(fg, Vector3(-22, 7, 0), 3.6, Vector3(-5, 20, 0))
	_towers(bg, 90.0)
	return {"pos": Vector3(0, 40, 64), "target": Vector3(2, 1, 2), "fov": 36.0}


static func _kart(parent: Node3D, pos: Vector3, slot: int) -> void:
	var col := Protocol.player_color(slot)
	var k := _node(parent, pos, Vector3(0, 90, 0))
	_box(k, Vector3(7.0, 2.4, 12.0), col, Vector3(0, 2.4, 0), 1.0)
	_box(k, Vector3(6.0, 1.0, 3.0), col.darkened(0.2), Vector3(0, 3.8, -4.4), 0.4, INK_THIN)
	for x in [-3.6, 3.6]:
		for z in [-3.8, 3.8]:
			_cylinder(k, 1.7, 1.6, UiTheme.INK.lerp(UiTheme.PAPER, 0.15), Vector3(x, 1.7, z), INK_THIN, 20) \
				.rotation_degrees = Vector3(0, 0, 90)
	var m := _mascot(k, slot, Vector3(0, 3.2, 1.0), -70, PlayerAvatar.Mood.HAPPY, {"wave": true, "t": 0.1 * slot}, 0.72)


## ¡Que no te deje la cámara!: plataformas de bloques, flechas y una sierra.
static func _scroller(fg: Node3D, bg: Node3D) -> Dictionary:
	_tile_floor(fg, Vector2(80, 40), 8.0, [UiTheme.PAPER, UiTheme.ACCENT_SCROLLER.lerp(UiTheme.PAPER, 0.7)])
	for k in 3:
		var arrow := _node(fg, Vector3(-26 + k * 10, 1.2, 10), Vector3(0, 0, 0))
		_box(arrow, Vector3(5, 0.6, 1.6), UiTheme.ACCENT_SCROLLER, Vector3(-1.4, 0, 1.6), 0.3, 0.0, true, Vector3(0, 40, 0))
		_box(arrow, Vector3(5, 0.6, 1.6), UiTheme.ACCENT_SCROLLER, Vector3(-1.4, 0, -1.6), 0.3, 0.0, true, Vector3(0, -40, 0))
	# Sierra (disco con dientes) y plataformas elevadas.
	var saw := _node(fg, Vector3(20, 9, -6), Vector3(0, 0, 0))
	_cylinder(saw, 6.0, 1.2, UiTheme.MASCOT_METAL, Vector3.ZERO, INK, 12).rotation_degrees = Vector3(90, 0, 0)
	_sphere(saw, 1.6, UiTheme.DANGER, Vector3(0, 0, 0.8), INK_THIN)
	_box(fg, Vector3(1.2, 9.0, 1.2), UiTheme.INK.lerp(UiTheme.PAPER, 0.3), Vector3(20, 4.5, -6.8), 0.4, INK_THIN)
	for k in 4:
		_box(fg, Vector3(9.0, 3.0, 8.0), UiTheme.BRICKS[(k * 3) % 8], Vector3(-30 + k * 18, 1.6, -14), 1.0)
	_towers(bg)
	_mascot(fg, 0, Vector3(-4, 1.2, 2), 0, PlayerAvatar.Mood.HAPPY, {"walk": 0.3, "look": Vector2(1, 0)})
	_mascot(fg, 2, Vector3(-16, 1.2, 8), 0, PlayerAvatar.Mood.SURPRISED, {"walk": 0.8, "look": Vector2(1, 0)})
	_mascot(fg, 3, Vector3(6, 4.6, -14), 60, PlayerAvatar.Mood.HAPPY, {"wave": true})
	return {"pos": Vector3(-4, 34, 50), "target": Vector3(-2, 3, 0), "fov": 36.0}


## Memoria de colores: tablero redondo con los cuatro botones de colores.
static func _memory(fg: Node3D, bg: Node3D) -> Dictionary:
	_round_stage(fg, [UiTheme.ACCENT_MEMORY, UiTheme.BRICKS[6], UiTheme.ACCENT_MEMORY.lightened(0.25), UiTheme.BRICKS[7]],
		UiTheme.BRICKS, 23)
	_towers(bg)
	var board := _node(fg, Vector3(0, 1.0, -2), Vector3(0, 0, 0))
	_cylinder(board, 19.0, 3.0, UiTheme.MEMORY_RIM, Vector3.ZERO, INK, 64)
	for q in 4:
		var col: Color = UiTheme.MEMORY_PADS[q]
		if q == 1:
			col = col.lerp(UiTheme.PAPER, UiTheme.MEMORY_LIT_MIX)  # Uno encendido.
		var a := TAU * (q + 0.5) / 4.0
		var pad := _box(board, Vector3(12.0, 2.0, 12.0), col, Vector3(sin(a) * 8.0, 3.2 + (0.6 if q == 1 else 0.0), cos(a) * 8.0),
			3.2, INK, false, Vector3(0, rad_to_deg(a) + 45.0, 0))
		pad.scale = Vector3(1, 1, 1)
	_cylinder(board, 6.0, 4.4, UiTheme.MEMORY_RIM_LIGHT, Vector3(0, 0.5, 0), INK, 40)
	_star(board, Vector3(0, 7.0, 0), 3.4, Vector3(-60, 0, 0), UiTheme.PAPER)
	_mascot(fg, 1, Vector3(-26, 0.8, 12), 40, PlayerAvatar.Mood.SURPRISED, {})
	_mascot(fg, 2, Vector3(26, 0.8, 12), -40, PlayerAvatar.Mood.HAPPY, {"wave": true})
	return {"pos": Vector3(0, 42, 58), "target": Vector3(0, 3, 0), "fov": 34.0}


## Desenfunde: calle del pueblo al atardecer, cactus, barril y dos mascotas
## frente a frente.
static func _quickdraw(fg: Node3D, bg: Node3D) -> Dictionary:
	_box(fg, Vector3(110, 3.0, 60), UiTheme.QD_SAND_FAR, Vector3(0, -1.6, 0), 1.0, INK, true)
	_box(fg, Vector3(110, 0.4, 16), UiTheme.QD_STREET, Vector3(0, 0.1, 4), 0.2, 0.0, true)
	for p: Vector3 in [Vector3(-38, 0, -14), Vector3(34, 0, -18), Vector3(8, 0, -24)]:
		_cactus(fg, p)
	for p: Vector3 in [Vector3(-22, 0, 16), Vector3(26, 0, 18)]:
		_cylinder(fg, 3.4, 7.0, UiTheme.QD_WOOD, p, INK, 20)
		_cylinder(fg, 3.6, 0.8, UiTheme.QD_WOOD_DARK, p + Vector3(0, 2.0, 0), 0.0, 20)
		_cylinder(fg, 3.6, 0.8, UiTheme.QD_WOOD_DARK, p + Vector3(0, 5.0, 0), 0.0, 20)
	# Sol y mesetas del fondo.
	_cylinder(bg, 18.0, 1.0, UiTheme.QD_SUN, Vector3(0, 30, -120), 0.0, 48).rotation_degrees = Vector3(90, 0, 0)
	for k in 5:
		var x := -110 + k * 55.0
		_box(bg, Vector3(40, 26 + (k % 2) * 10, 12), UiTheme.QD_MESA_FAR if k % 2 == 0 else UiTheme.QD_MESA_NEAR,
			Vector3(x, 8, -90 - (k % 2) * 10), 3.0, 0.0)
	var a := _mascot(fg, 1, Vector3(-14, 0.4, 4), 35, PlayerAvatar.Mood.ANGRY, {"look": Vector2(1, 0)})
	var b := _mascot(fg, 2, Vector3(14, 0.4, 4), -35, PlayerAvatar.Mood.ANGRY, {"look": Vector2(-1, 0)})
	_hat(a)
	_hat(b)
	return {"pos": Vector3(0, 26, 54), "target": Vector3(0, 6, 2), "fov": 34.0}


static func _cactus(parent: Node3D, pos: Vector3) -> void:
	var n := _node(parent, pos)
	_cylinder(n, 2.4, 13.0, UiTheme.QD_CACTUS, Vector3.ZERO, INK, 20)
	for side in [-1, 1]:
		var arm := _node(n, Vector3(side * 2.2, 5.0 + side, 0))
		_cylinder(arm, 1.4, 3.4, UiTheme.QD_CACTUS, Vector3.ZERO, INK_THIN, 16).rotation_degrees = Vector3(0, 0, -side * 90.0)
		_cylinder(arm, 1.4, 5.0, UiTheme.QD_CACTUS, Vector3(side * 3.0, -0.2, 0), INK_THIN, 16)


## Sombrero de vaquero sobre la cabeza de una mascota 3D.
static func _hat(m: Mascot3D) -> void:
	var n := _node(m, Vector3(0, 9.1, 0), Vector3(0, 0, 8))
	_cylinder(n, 5.6, 0.5, UiTheme.QD_HAT, Vector3.ZERO, INK_THIN, 32)
	_cylinder(n, 3.0, 3.2, UiTheme.QD_HAT, Vector3(0, 0.3, 0), INK_THIN, 24)
	_cylinder(n, 3.05, 0.8, m.color, Vector3(0, 0.6, 0), 0.0, 24)


## Pool loco: mesa verde con troneras y las bolas en triángulo.
static func _pool(fg: Node3D, bg: Node3D) -> Dictionary:
	_round_stage(fg, [UiTheme.BRICKS[2], UiTheme.BRICKS[1], UiTheme.BRICKS[2].lightened(0.25), UiTheme.PAPER_DIM], UiTheme.BRICKS, 29)
	_towers(bg)
	var t := _node(fg, Vector3(0, 0.8, -2))
	_box(t, Vector3(52, 6.0, 30), UiTheme.POOL_CUSHION, Vector3(0, 6.0, 0), 2.0)
	_box(t, Vector3(46, 1.0, 24), UiTheme.POOL_FELT, Vector3(0, 8.8, 0), 0.4, 0.0, true)
	for x in [-24.0, 0.0, 24.0]:
		for z in [-13.0, 13.0]:
			_cylinder(t, 2.0, 0.6, UiTheme.POOL_POCKET, Vector3(x, 8.9, z), 0.0, 20, true)
	for x in [-20.0, 20.0]:
		for z in [-10.0, 10.0]:
			_box(t, Vector3(3, 4, 3), UiTheme.POOL_CUSHION.darkened(0.2), Vector3(x, 1.5, z), 0.8, INK_THIN)
	var cols := [UiTheme.GOLD, UiTheme.BRICKS[0], UiTheme.BRICKS[5], UiTheme.BRICKS[3], UiTheme.BRICKS[6], UiTheme.BRICKS[1]]
	var i := 0
	for row in 3:
		for k in row + 1:
			_sphere(t, 1.5, cols[i % cols.size()], Vector3(8 + row * 2.7, 10.8, (k - row / 2.0) * 3.1), INK_THIN)
			i += 1
	_sphere(t, 1.5, UiTheme.PAPER, Vector3(-12, 10.8, 2), INK_THIN)
	_mascot(fg, 0, Vector3(-32, 0.8, 10), 50, PlayerAvatar.Mood.ANGRY, {"look": Vector2(1, 0)})
	_mascot(fg, 3, Vector3(31, 0.8, 12), -45, PlayerAvatar.Mood.HAPPY, {"wave": true})
	return {"pos": Vector3(0, 48, 66), "target": Vector3(0, 6, 0), "fov": 36.0}


## Carrera de obstáculos: carriles de pasto con vallas y mascotas saltando.
static func _hurdles(fg: Node3D, bg: Node3D) -> Dictionary:
	_box(fg, Vector3(100, 3.0, 44), UiTheme.HURDLES_GROUND, Vector3(0, -1.6, 0), 1.0, INK, true)
	for lane in 4:
		var z := -15.0 + lane * 10.0
		_box(fg, Vector3(98, 0.4, 8.6), UiTheme.HURDLES_GROUND_ALT if lane % 2 == 0 else UiTheme.HURDLES_GROUND,
			Vector3(0, 0.1, z), 0.2, 0.0, true)
		for k in 3:
			var x := -24.0 + k * 24.0 + lane * 3.0
			var h := _node(fg, Vector3(x, 0, z))
			for s in [-1, 1]:
				_box(h, Vector3(0.9, 6.0, 0.9), UiTheme.HURDLES_POST, Vector3(0, 3.0, s * 3.6), 0.3, INK_THIN)
			_box(h, Vector3(1.2, 1.6, 8.4), UiTheme.BRICKS[(lane + k) % 2 * 2 + 0] if k % 2 == 0 else UiTheme.GOLD,
				Vector3(0, 5.6, 0), 0.4, INK_THIN)
	_towers(bg, 80.0)
	_mascot(fg, 0, Vector3(-10, 3.0, -15), -35, PlayerAvatar.Mood.HAPPY, {"walk": 0.5, "look": Vector2(1, 0)})
	_mascot(fg, 1, Vector3(-18, 0.3, -5), -35, PlayerAvatar.Mood.ANGRY, {"walk": 0.2, "look": Vector2(1, 0)})
	_mascot(fg, 2, Vector3(6, 0.3, 5), -35, PlayerAvatar.Mood.HAPPY, {"walk": 0.7, "look": Vector2(1, 0)})
	_mascot(fg, 3, Vector3(-4, 0.3, 15), -35, PlayerAvatar.Mood.SURPRISED, {"walk": 0.4, "look": Vector2(1, 0)})
	return {"pos": Vector3(-6, 30, 46), "target": Vector3(-4, 3, 0), "fov": 36.0}
