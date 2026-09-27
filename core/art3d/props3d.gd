class_name Props3D
extends RefCounted
## Piezas 3D del escenario y de la UI (estrellas, bloques del marco, medallas,
## corona, trofeo, monedas, gemas, pelota), con el mismo plástico y contorno
## de tinta que las mascotas 3D, **horneadas una vez** a un atlas de sprites.
## Decisión: docs/adr/0016-piezas-3d-horneadas.md.
##
## Concepto: *pieza horneada*. La estrella dorada de las esquinas del tablero
## se arma en 3D (un "almohadón" con forma de estrella), se renderiza una sola
## vez al arrancar la TV (o se lee del disco, ver Props3DBaker) y queda como
## un rectángulo dentro de una textura grande (el atlas). En cada cuadro el
## juego dibuja ese rectángulo como cualquier sprite 2D: el costo es el de
## una textura, no el de un modelo 3D.
##
## Uso desde el dibujo 2D (siempre con respaldo):
##   if not Props3D.draw(ci, "star", Rect2(center - Vector2(r, r), Vector2(r, r) * 2.0)):
##       ...dibujo 2D de siempre...
## `rect` es el "cuerpo" nominal de la pieza (para la estrella, el cuadrado
## que contiene sus puntas; para un bloque, su rectángulo en el tablero). El
## sprite es un poco más grande (contorno, brillo): Props3D lo ubica solo.
##
## Sin placa de video (tests con --headless) o si el horneado falla, `draw`
## devuelve false y cada función dibuja su versión 2D: no cambia nada.

## Grupo de nodos a los que se avisa cuando el atlas queda listo
## (método `_on_props3d_ready`), para rearmar lo que se preparó una vez.
const GROUP := &"props3d"

## Versión de las recetas: subirla invalida la caché en disco.
const VERSION := 2

## Apagado a mano (benchmark A/B, o si una TV no se lleva bien con el 3D).
static var enabled := true
## Sube cada vez que cambia el atlas (para cachés que dependen de él).
static var generation := 0

static var _texture: Texture2D          # CanvasTexture con mipmaps sobre el atlas
static var _regions: Dictionary = {}    # nombre -> [Rect2 celda (px del atlas), Rect2 cuerpo (relativo a la celda)]
static var _images: Dictionary = {}     # nombre -> Image chica (para componer en Image, ej. GameArt.stage_texture)
static var _materials: Dictionary = {}


## ¿Está el atlas listo para dibujar?
static func is_ready() -> bool:
	return enabled and _texture != null


## ¿Existe la pieza `name` en el atlas?
static func has(name: String) -> bool:
	return is_ready() and _regions.has(name)


## Dibuja la pieza con su cuerpo nominal en `rect` (coordenadas del
## CanvasItem). `modulate` sirve para transparencia (aparecer, parpadear).
## Devuelve false si no hay atlas: el que llama dibuja la versión 2D.
static func draw(ci: CanvasItem, name: String, rect: Rect2, modulate := Color.WHITE, mirror := false) -> bool:
	if not is_ready():
		return false
	var reg: Array = _regions.get(name, [])
	if reg.is_empty():
		return false
	var dest := dest_rect(reg[0], reg[1], rect)
	if mirror:  # Espejado horizontal: ancho negativo.
		dest = Rect2(Vector2(2.0 * rect.get_center().x - dest.position.x, dest.position.y), Vector2(-dest.size.x, dest.size.y))
	ci.draw_texture_rect_region(_texture, dest, reg[0], modulate)
	return true


## Tamaño del cuerpo de la pieza en px del atlas (para mantener sus
## proporciones), o cero si no hay atlas.
static func body_size(name: String) -> Vector2:
	if not has(name):
		return Vector2.ZERO
	return (_regions[name][1] as Rect2).size


## Pieza centrada en `center` con su cuerpo de `size` (ej. estrella de radio r: size = 2r).
static func draw_centered(ci: CanvasItem, name: String, center: Vector2, size: Vector2, modulate := Color.WHITE) -> bool:
	return draw(ci, name, Rect2(center - size / 2.0, size), modulate)


## Dónde va el sprite entero para que su cuerpo caiga en `target`.
## cell: rectángulo de la pieza en el atlas; body: su cuerpo dentro de la celda.
## Ejemplo: celda de 200×120 px con el cuerpo en (10, 10, 180, 100) y target
## (0, 0, 90, 50) -> escala 0,5 -> sprite en (−5, −5, 100, 60).
static func dest_rect(cell: Rect2, body: Rect2, target: Rect2) -> Rect2:
	var k := target.size / body.size
	return Rect2(target.position - body.position * k, cell.size * k)


## Imagen chica de una pieza (solo las marcadas con "keep"), para componer
## con Image.blend_rect. Vacía si no hay atlas.
static func image(name: String) -> Image:
	if not is_ready():
		return null
	return _images.get(name)


## Nombre del bloque del marco para el color `i` de UiTheme.BRICKS.
static func brick_name(i: int, vertical: bool) -> String:
	return ("brick_v_%d" if vertical else "brick_h_%d") % (i % UiTheme.BRICKS.size())


## Instala un atlas horneado (lo llama Props3DBaker). regions: nombre ->
## [celda, cuerpo]. keep: nombres cuya Image chica se guarda.
static func install(atlas: Image, regions: Dictionary, keep: Array) -> void:
	_images.clear()
	for n: String in keep:
		if regions.has(n):
			var cell: Rect2 = regions[n][0]
			_images[n] = atlas.get_region(Rect2i(cell))
	if not atlas.has_mipmaps():
		atlas.generate_mipmaps()
	var tex := CanvasTexture.new()
	tex.diffuse_texture = ImageTexture.create_from_image(atlas)
	# Con mipmaps: una estrella horneada a 80 px de radio dibujada a 11 px no titila.
	tex.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_texture = tex
	_regions = regions
	generation += 1


## Olvida el atlas (vuelve el dibujo 2D). Para tests y el benchmark A/B.
static func clear() -> void:
	_texture = null
	_regions = {}
	_images.clear()
	generation += 1


## Suelta las mallas y materiales del armado (después de hornear no se
## usan: todo quedó en el atlas).
static func release_build_caches() -> void:
	_materials.clear()
	Props3DMeshes._cache.clear()


## Textura del atlas (para la hoja de piezas).
static func texture() -> Texture2D:
	return _texture


static func regions() -> Dictionary:
	return _regions


# --- Catálogo ---------------------------------------------------------------------

## Todas las piezas: datos puros (sin Callables) para poder armar la firma de
## la caché en disco. kind: receta de `build`; res: px del atlas por px
## lógico; body: cuerpo nominal en px lógicos (x derecha, y abajo, relativo al
## origen de la pieza) o vacío = la caja que ocupa la pieza vista de frente.
static func catalog() -> Array[Dictionary]:
	var list: Array[Dictionary] = []
	var res := UiTheme.PROP_RES
	# Las estrellas se ven también grandes (emblema de la transición, ~100 px de radio): más resolución.
	var star_res := UiTheme.PROP_RES_STAR
	list.append({"name": "star", "kind": "star", "color": UiTheme.GOLD, "res": star_res, "body": Rect2(-40, -40, 80, 80), "keep": true})
	list.append({"name": "star_white", "kind": "star", "color": UiTheme.PAPER, "res": star_res, "body": Rect2(-40, -40, 80, 80)})
	for i in UiTheme.BRICKS.size():
		var c: Color = UiTheme.BRICKS[i]
		list.append({"name": brick_name(i, false), "kind": "brick", "color": c, "res": res, "size": Vector2(112, 40), "body": Rect2(-56, -20, 112, 40)})
		list.append({"name": brick_name(i, true), "kind": "brick", "color": c, "res": res, "size": Vector2(40, 112), "body": Rect2(-20, -56, 40, 112)})
	for i in [0, 5]:
		list.append({"name": "corner_%d" % i, "kind": "corner", "color": UiTheme.BRICKS[i], "res": res, "body": Rect2(-32, -32, 64, 64)})
	for place in [1, 2, 3]:
		list.append({"name": "medal_%d" % place, "kind": "medal", "color": UiTheme.place_color(place), "res": res, "body": Rect2(-40, -40, 80, 80)})
	list.append({"name": "token", "kind": "token", "color": UiTheme.GOLD, "res": res, "body": Rect2(-40, -40, 80, 80)})
	list.append({"name": "coin", "kind": "coin", "color": UiTheme.GOLD, "res": res, "body": Rect2(-40, -40, 80, 80)})
	list.append({"name": "gem", "kind": "gem", "color": UiTheme.PROP_GEM, "res": res, "body": Rect2(-40, -40, 80, 80)})
	list.append({"name": "ball", "kind": "ball", "color": UiTheme.PROP_BALL, "res": res, "body": Rect2(-20, -20, 40, 40)})
	list.append({"name": "crown", "kind": "crown", "color": UiTheme.GOLD, "res": res, "body": Rect2()})
	list.append({"name": "trophy", "kind": "trophy", "color": UiTheme.GOLD, "res": res, "body": Rect2()})
	# Bloques de juguete con botones para los fondos (torres del lobby y
	# escenario de los juegos): color puro, y mezclados con la bruma
	# (lejos / cerca) como las torres de PartyBackground.
	var bg := UiTheme.PROP_RES_BG
	for i in UiTheme.BRICKS.size():
		var c: Color = UiTheme.BRICKS[i]
		list.append({"name": "block_%d" % i, "kind": "block", "color": c, "res": bg, "body": Rect2(), "keep": true})
		list.append({"name": "block_far_%d" % i, "kind": "block", "color": c.lerp(UiTheme.BG_HAZE, UiTheme.BG_HAZE_FAR), "res": bg, "body": Rect2()})
		list.append({"name": "block_near_%d" % i, "kind": "block", "color": c.lerp(UiTheme.BG_HAZE, UiTheme.BG_HAZE_NEAR), "res": bg, "body": Rect2()})
	return list


## Firma de la caché en disco: cambia si cambia cualquier receta o token.
static func signature() -> String:
	var parts := [VERSION, UiTheme.PROP_SUPERSAMPLE, UiTheme.PROP_INK, UiTheme.PROP_INK_THIN, UiTheme.PROP_TILT_DEG, UiTheme.PROP_BRICK_LIGHT,
		UiTheme.PROP_TOWER_TURN_DEG, UiTheme.PROP_TOWER_TILT_DEG, UiTheme.PROP_STAR_SHADE, UiTheme.INK, catalog()]
	return "%08x" % (str(parts).hash() & 0xffffffff)


# --- Armado de cada pieza (en px lógicos; y hacia arriba, mirando a +Z) --------------

## Nodo 3D de la pieza `def` del catálogo, en unidades de px lógicos.
static func build(def: Dictionary) -> Node3D:
	var col: Color = def.color
	var root := Node3D.new()
	root.name = def.name
	match def.kind:
		"star":
			var outline := Props3DMeshes.star_outline(40.0, 0.5)
			var node := _part(root, Props3DMeshes.pillow("star40", outline, 10.0), _star_material(col, UiTheme.PROP_INK))
			node.rotation_degrees = Vector3(-10, 0, 0)
		"brick":
			_brick(root, def.size, col)
		"corner":
			_corner(root, col)
		"medal":
			_disc(root, col, true)
		"coin":
			_disc(root, col, true)
			var star := _part(root, Props3DMeshes.pillow("coinstar", Props3DMeshes.star_outline(17.0, 0.5), 3.0),
				_metal_material(col.lightened(0.15), 0.0))
			star.position = Vector3(0, 0, 5.0)
			root.rotation_degrees = Vector3(-10, 0, 0)
		"token":
			_disc(root, col, false)
		"gem":
			var prof := PackedVector2Array([Vector2(0, -38), Vector2(22, -18), Vector2(40, 2), Vector2(40, 8),
				Vector2(27, 24), Vector2(0, 26)])
			var gem := _part(root, Props3DMeshes.faceted_lathe("gem", prof, 8), _gem_material(col))
			gem.rotation_degrees = Vector3(22, 12, 0)
			# Las caras planas cortarían el contorno de tinta (cada cara se infla
			# para su lado): el contorno sale de la misma gema con normales suaves.
			var hull := _part(root, Props3DMeshes.lathe("gem_hull", prof, 16), _ink_material(UiTheme.PROP_INK))
			hull.rotation_degrees = gem.rotation_degrees
		"ball":
			var b := _part(root, Props3DMeshes.sphere(), _plastic_material(col, UiTheme.PROP_INK))
			b.scale = Vector3.ONE * 20.0
		"crown":
			_crown(root, col)
		"trophy":
			_trophy(root, col)
		"block":
			_block(root, col)
	return root


static func _part(parent: Node3D, mesh: Mesh, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi


## Bloque del marco del tablero: ladrillo liso con cantos redondeados, visto
## desde arriba e inclinado (se ve la tapa y el canto de adelante, como el
## bisel 2D). `size`: su rectángulo en el tablero (ancho × alto en pantalla).
static func _brick(root: Node3D, size: Vector2, col: Color) -> void:
	var a := deg_to_rad(UiTheme.PROP_TILT_DEG)
	var thick := 22.0
	var gap := 1.0  # Junta entre bloques: se ve la tinta de abajo.
	# Alto en pantalla = tapa · cos(a) + grosor · sen(a).
	var top := (size.y - gap - thick * sin(a)) / cos(a)
	var mesh := Props3DMeshes.rounded_box(Vector3(size.x - gap, top, thick), 8.0)
	var box := _part(root, mesh, _plastic_material(col, UiTheme.PROP_INK_THIN, 0.24, UiTheme.PROP_BRICK_LIGHT))
	box.rotation = Vector3(-a, 0, 0)


## Bloque grande de la esquina con una estrella dorada acostada arriba.
static func _corner(root: Node3D, col: Color) -> void:
	var a := deg_to_rad(UiTheme.PROP_TILT_DEG)
	var tilt := Node3D.new()
	tilt.rotation = Vector3(-a, 0, 0)
	root.add_child(tilt)
	var thick := 22.0
	var top := (60.0 - thick * sin(a)) / cos(a)
	_part(tilt, Props3DMeshes.rounded_box(Vector3(60, top, thick), 9.0), _plastic_material(col, UiTheme.PROP_INK, 0.24, UiTheme.PROP_BRICK_LIGHT))
	var star := _part(tilt, Props3DMeshes.pillow("star40", Props3DMeshes.star_outline(40.0, 0.5), 10.0),
		_star_material(UiTheme.GOLD, UiTheme.PROP_INK * 0.8))
	star.scale = Vector3.ONE * 0.68
	star.position = Vector3(0, 1.0, thick / 2.0 + 1.0)


## Disco con el borde levantado: medalla (metal del puesto), moneda, o ficha
## de premio (aro dorado y cara blanca, donde va el ícono 2D encima).
static func _disc(root: Node3D, col: Color, metal_face: bool) -> void:
	var rim := PackedVector2Array([Vector2(29, -6), Vector2(40, -6), Vector2(40, 2.5), Vector2(38.5, 6),
		Vector2(35.5, 7.5), Vector2(32, 6.5), Vector2(29.5, 4.5), Vector2(29, -6)])
	var ring := _part(root, Props3DMeshes.lathe("disc_rim", rim, 48, Vector2(34.5, 0.5)), _metal_material(col, UiTheme.PROP_INK))
	ring.rotation_degrees = Vector3(90, 0, 0)
	var face := PackedVector2Array([Vector2(0, -5.5), Vector2(29.8, -5.5), Vector2(29.8, 4.2), Vector2(20, 5.2),
		Vector2(10, 5.7), Vector2(0, 5.8)])
	var mat := _metal_material(col.darkened(0.06), 0.0) if metal_face else _plastic_material(UiTheme.PAPER, 0.0)
	var f := _part(root, Props3DMeshes.lathe("disc_face", face, 48), mat)
	f.rotation_degrees = Vector3(90, 0, 0)
	root.rotation_degrees = Vector3(-8, 0, 0)


## Corona de juguete: aro dorado con seis puntas y una piedra roja en cada una.
static func _crown(root: Node3D, col: Color) -> void:
	var holder := Node3D.new()
	holder.rotation_degrees = Vector3(18, 0, 0)
	root.add_child(holder)
	var band := PackedVector2Array([Vector2(36, -10), Vector2(44, -10), Vector2(45, 0), Vector2(44, 10),
		Vector2(36, 10), Vector2(35, 0), Vector2(36, -10)])
	var metal := _metal_material(col, UiTheme.PROP_INK)
	_part(holder, Props3DMeshes.lathe("crown_band", band, 48, Vector2(40, 0)), metal)
	for k in 6:
		var ang := TAU * k / 6.0
		var p := Vector3(sin(ang), 0, cos(ang)) * 40.0
		var spike := _part(holder, Props3DMeshes.cone(), metal)
		spike.position = p + Vector3(0, 8, 0)
		spike.scale = Vector3(11, 30, 7)
		spike.rotation = Vector3(0, ang, 0)
		var jewel := _part(holder, Props3DMeshes.sphere(), _plastic_material(UiTheme.PROP_JEWEL, UiTheme.PROP_INK))
		jewel.position = p + Vector3(0, 40, 0)
		jewel.scale = Vector3.ONE * 6.5


## Trofeo: pie oscuro, copa dorada con asas y una estrella en el frente.
static func _trophy(root: Node3D, col: Color) -> void:
	var base := _part(root, Props3DMeshes.rounded_box(Vector3(64, 18, 40), 6.0), _plastic_material(UiTheme.PROP_TROPHY_BASE, UiTheme.PROP_INK))
	base.position = Vector3(0, 9, 0)
	var cup := PackedVector2Array([Vector2(0, 18), Vector2(24, 18), Vector2(24, 24), Vector2(14, 28), Vector2(8, 34),
		Vector2(6, 46), Vector2(9, 52), Vector2(6, 56), Vector2(14, 60), Vector2(30, 70), Vector2(38, 86),
		Vector2(40, 102), Vector2(42, 108), Vector2(38, 110), Vector2(0, 106)])
	var metal := _metal_material(col, UiTheme.PROP_INK)
	_part(root, Props3DMeshes.lathe("trophy_cup", cup, 48), metal)
	for side in [-1.0, 1.0]:
		var handle := _part(root, Props3DMeshes.torus(0.28), metal)
		handle.position = Vector3(side * 38.0, 88, 0)
		handle.rotation_degrees = Vector3(90, 0, 0)
		handle.scale = Vector3(15, 15, 15)
	var star := _part(root, Props3DMeshes.pillow("star40", Props3DMeshes.star_outline(40.0, 0.5), 10.0),
		_star_material(UiTheme.PAPER, 0.0))
	star.scale = Vector3.ONE * 0.36
	star.position = Vector3(0, 86, 36)
	star.rotation_degrees = Vector3(-8, 0, 0)
	root.rotation_degrees = Vector3(10, 0, 0)


## Bloque de juguete con cuatro botones (torres del fondo, escenario de los
## juegos), girado para que se vea la tapa y el costado derecho. Para las
## torres de la derecha se dibuja espejado.
static func _block(root: Node3D, col: Color) -> void:
	var holder := Node3D.new()
	holder.rotation = Vector3(deg_to_rad(UiTheme.PROP_TOWER_TILT_DEG), -deg_to_rad(UiTheme.PROP_TOWER_TURN_DEG), 0)
	root.add_child(holder)
	var mat := _plastic_material(col, UiTheme.PROP_INK * 0.7)
	_part(holder, Props3DMeshes.rounded_box(Vector3(60, 60, 60), 8.0), mat)
	for x in [-14.0, 14.0]:
		for z in [-14.0, 14.0]:
			var stud := _part(holder, Props3DMeshes.cone(0.92), mat)
			stud.position = Vector3(x, 29, z)
			stud.scale = Vector3(9, 8, 9)


# --- Materiales (el shader de plástico de las mascotas) --------------------------------

const SHADER_TOY := preload("res://core/mascot3d/toy_plastic.gdshader")
const SHADER_INK := preload("res://core/mascot3d/ink_outline.gdshader")


## Plástico de color (misma rampa que Mascot3D para Kind.PLASTIC).
## `light`: cuánto se aclara la cara iluminada (< 0 = como las mascotas).
## Los bloques del marco usan menos: la tapa mira a la luz y se veía pastel.
static func _plastic_material(col: Color, ink: float, coat := 0.18, light := -1.0) -> Material:
	var lum := col.get_luminance()
	var dark := lum < 0.2
	var low := col.lightened(0.02) if dark else col.darkened(0.5 if lum < 0.8 else 0.28)
	low = low.lerp(UiTheme.MASCOT_SHADE_TINT, 0.12)
	var mid := col.lightened(0.12) if dark else col
	var high := col.lightened(0.45 if dark else (0.1 if lum > 0.85 else 0.32))
	if light >= 0.0:
		high = col.lightened(light)
	return _material("plastic%.2f|%.2f" % [coat, light], col, ink, {"low_color": low, "mid_color": mid, "high_color": high,
		"bounce_color": mid.lightened(0.18), "bounce_strength": 0.35, "rim_color": Color.WHITE, "rim_strength": 0.22,
		"spec_strength": 0.95, "spec_size": 0.015, "coat_strength": coat})


## Metal lustrado (oro, plata, bronce), como Kind.METAL de las mascotas.
static func _metal_material(col: Color, ink: float) -> Material:
	return _material("metal", col, ink, {"low_color": col.darkened(0.45), "mid_color": col,
		"high_color": col.lerp(UiTheme.PAPER, 0.75), "bounce_color": col.lightened(0.3), "bounce_strength": 0.55,
		"rim_color": Color.WHITE, "rim_strength": 0.3, "spec_strength": 1.0, "spec_size": 0.025, "coat_strength": 0.35})


## Estrella: dorada con sombra naranja (como la maqueta), o blanca.
static func _star_material(col: Color, ink: float) -> Material:
	var shade := UiTheme.PROP_STAR_SHADE if col == UiTheme.GOLD else col.darkened(0.2)
	return _material("star", col, ink, {"low_color": shade, "mid_color": col,
		"high_color": col.lerp(UiTheme.PAPER, 0.55), "bounce_color": col.lightened(0.2), "bounce_strength": 0.45,
		"rim_color": Color.WHITE, "rim_strength": 0.25, "spec_strength": 1.0, "spec_size": 0.02, "coat_strength": 0.3})


## Gema: color intenso y brillos fuertes en las facetas.
static func _gem_material(col: Color) -> Material:
	return _material("gem", col, 0.0, {"low_color": col.darkened(0.5), "mid_color": col,
		"high_color": col.lerp(UiTheme.PAPER, 0.7), "bounce_color": col.lightened(0.4), "bounce_strength": 0.6,
		"rim_color": Color.WHITE, "rim_strength": 0.4, "spec_strength": 1.0, "spec_size": 0.04, "coat_strength": 0.4})


## En caché por (tipo, color, contorno). El ancho del contorno está en px
## lógicos; Props3DBaker escala cada pieza por su `res`, y el contorno (en
## unidades del mundo) se ajusta con set_ink_scale.
static func _material(kind: String, col: Color, ink: float, params: Dictionary) -> Material:
	var key := "%s|%s|%.2f" % [kind, col.to_html(), ink]
	if _materials.has(key):
		return _materials[key]
	var m := ShaderMaterial.new()
	m.shader = SHADER_TOY
	for k: String in params:
		m.set_shader_parameter(k, params[k])
	if ink > 0.0:
		var pass2 := ShaderMaterial.new()
		pass2.shader = SHADER_INK
		pass2.set_shader_parameter("ink", UiTheme.INK)
		pass2.set_shader_parameter("width", ink)
		pass2.set_meta("ink_px", ink)
		m.next_pass = pass2
	_materials[key] = m
	return m


## Solo el contorno de tinta (casco invertido), para piezas de caras planas.
static func _ink_material(ink: float) -> Material:
	var key := "ink|%.2f" % ink
	if not _materials.has(key):
		var m := ShaderMaterial.new()
		m.shader = SHADER_INK
		m.set_shader_parameter("ink", UiTheme.INK)
		m.set_shader_parameter("width", ink)
		m.set_meta("ink_px", ink)
		_materials[key] = m
	return _materials[key]


## El contorno del shader se mide en unidades del mundo: al hornear con `res`
## px del atlas por px lógico, el mundo está escalado y el contorno también.
## Se usan materiales propios por escala (duplicados) para no pisar otros.
static func material_for_res(m: Material, res: float) -> Material:
	var ink_only := m is ShaderMaterial and (m as ShaderMaterial).shader == SHADER_INK
	if (m.next_pass == null and not ink_only) or is_equal_approx(res, 1.0):
		return m
	var key := "%d@%.2f" % [m.get_instance_id(), res]
	if _materials.has(key):
		return _materials[key]
	if ink_only:
		var hull := m.duplicate() as ShaderMaterial
		hull.set_shader_parameter("width", float(m.get_meta("ink_px", 3.0)) * res)
		_materials[key] = hull
		return hull
	var copy := m.duplicate() as ShaderMaterial
	var ink := (m.next_pass as ShaderMaterial).duplicate() as ShaderMaterial
	ink.set_shader_parameter("width", float(m.next_pass.get_meta("ink_px", 3.0)) * res)
	copy.next_pass = ink
	_materials[key] = copy
	return copy
