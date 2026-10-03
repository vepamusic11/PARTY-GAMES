class_name Props3DBaker
extends RefCounted
## Hornea las piezas 3D de `Props3D` a un atlas (una textura) una sola vez.
##
## Pasos (ver ADR 0016):
##   1. Se arman todas las piezas del catálogo y se calcula cuánto ocupa cada
##      una vista de frente (su "celda"). Las celdas se acomodan en estantes
##      dentro de un atlas de ATLAS_W px de ancho.
##   2. Todas las piezas van a un único mundo 3D, cada una sobre su celda. Una
##      cámara ortográfica recorre el atlas de a un "azulejo" (TILE × TILE
##      px): cada azulejo se renderiza SUPERSAMPLE veces más grande y otro
##      SubViewport lo achica promediando (props3d_downsample.gdshader, bordes
##      limpios). Se leen los píxeles y se pegan en el atlas.
##   3. El atlas se guarda en user://props3d/ (PNG + JSON con las celdas):
##      la próxima vez que arranca la TV se lee del disco sin renderizar
##      nada. La firma (Props3D.signature) cambia si cambia una receta o un
##      color, y entonces se vuelve a hornear.
##
## Concepto: *azulejos* (tiles). Una placa de TV barata no siempre acepta
## texturas de render de más de 2048 px, y al 4× un atlas de 2048 px pediría
## una de 8192. Con la cámara ortográfica cada pedazo se renderiza por
## separado y encaja exacto con el vecino (no hay perspectiva que deforme).
## Ejemplo: atlas de 2048 × 1024 con azulejos de 512 -> 4 × 2 = 8 renders
## de 2048 × 2048 (uno por cuadro), en vez de uno de 8192 × 4096.
##
## Uso (TV):
##   Props3DBaker.ensure(self)   # en _ready; con caché en disco queda listo ya
## En --headless no hace nada (los tests usan el dibujo 2D).

const ATLAS_W := 2048
const TILE := 512
const PAD := 4                 ## Px del atlas entre celdas (los mipmaps no se mezclan).
const CACHE_DIR := "user://props3d/"
const CAM_DISTANCE := 100000.0

## Datos del último horneado o lectura de caché (para medir): ms, tamaño, bytes…
static var last_report: Dictionary = {}
static var _running := false
static var _failed := false


## Deja el atlas listo: de la caché en disco (en el acto) o horneándolo
## (unos cuadros; al terminar avisa al grupo Props3D.GROUP y pide redibujar
## todo). host: un nodo en el árbol. Devuelve true si quedó listo.
static func ensure(host: Node) -> bool:
	if Props3D.is_ready() or _running or _failed or not Props3D.enabled:
		return Props3D.is_ready()
	if host == null or not host.is_inside_tree() or DisplayServer.get_name() == "headless":
		return false
	if load_cache():
		return true
	_running = true
	var ok := await bake(host)
	_running = false
	_failed = not ok  # Si falló (driver, memoria), no se reintenta en esta sesión: queda el 2D.
	if ok:
		save_cache()
		if host.is_inside_tree():
			host.get_tree().call_group(Props3D.GROUP, "_on_props3d_ready")
			host.get_tree().root.propagate_call("queue_redraw")
	return ok


## Hornea todo el catálogo e instala el atlas en Props3D. Devuelve false si
## no se pudo (sin pantalla, sin nodo, render vacío).
static func bake(host: Node) -> bool:
	var t0 := Time.get_ticks_usec()
	if host == null or not host.is_inside_tree():
		return false
	var layout := plan(Props3D.catalog())
	var size: Vector2i = layout.size
	var ss := UiTheme.PROP_SUPERSAMPLE
	# Mundo 3D (render grande) dentro del que lo achica.
	var ds := SubViewport.new()
	ds.size = Vector2i(TILE, TILE)
	ds.transparent_bg = true
	ds.disable_3d = true
	ds.render_target_update_mode = SubViewport.UPDATE_DISABLED
	var rvp := SubViewport.new()
	rvp.size = Vector2i(TILE, TILE) * ss
	rvp.own_world_3d = true
	rvp.transparent_bg = true
	rvp.msaa_3d = Viewport.MSAA_DISABLED
	rvp.positional_shadow_atlas_size = 0
	rvp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	ds.add_child(rvp)
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.keep_aspect = Camera3D.KEEP_HEIGHT
	cam.size = TILE
	# Cámara MUY lejos: el shader de plástico calcula la dirección de la vista
	# desde cada punto hacia la cámara (VIEW) aunque la cámara sea ortográfica.
	# A 1000 u, una pieza a 250 u del centro del azulejo veía los brillos
	# corridos ~14° y aparecía un "escalón" de luz donde una pieza cruzaba dos
	# azulejos. A 100 000 u la diferencia es de 0,15°: igual en todo el atlas.
	cam.near = CAM_DISTANCE - 2000.0
	cam.far = CAM_DISTANCE + 2000.0
	rvp.add_child(cam)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_CLEAR_COLOR
	env.environment.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	rvp.add_child(env)
	var world := Node3D.new()
	rvp.add_child(world)
	for item: Dictionary in layout.items:
		var node := Props3D.build(item.def)
		var res: float = item.def.res
		node.scale = Vector3.ONE * res
		node.position = Vector3(item.origin.x, -item.origin.y, 0.0)
		_scale_ink(node, res)
		world.add_child(node)
	var shrink := TextureRect.new()
	shrink.texture = rvp.get_texture()
	shrink.expand_mode = TextureRect.EXPAND_IGNORE_SIZE  # Si no, mide lo que la textura (4× más).
	shrink.size = Vector2(TILE, TILE)
	shrink.stretch_mode = TextureRect.STRETCH_SCALE
	shrink.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://core/art3d/props3d_downsample.gdshader")
	mat.set_shader_parameter("factor", ss)
	mat.set_shader_parameter("fill_color", UiTheme.INK)
	shrink.material = mat
	ds.add_child(shrink)
	host.add_child(ds)
	var t_build := Time.get_ticks_usec()
	var atlas := Image.create_empty(size.x, size.y, false, Image.FORMAT_RGBA8)
	var tiles := 0
	var read_us := 0
	for ty in ceili(float(size.y) / TILE):
		for tx in ceili(float(size.x) / TILE):
			var tile := Rect2i(tx * TILE, ty * TILE, TILE, TILE)
			if not _tile_used(layout.items, tile):
				continue
			cam.position = Vector3(tile.position.x + TILE / 2.0, -(tile.position.y + TILE / 2.0), CAM_DISTANCE)
			rvp.render_target_update_mode = SubViewport.UPDATE_ONCE
			await RenderingServer.frame_post_draw
			ds.render_target_update_mode = SubViewport.UPDATE_ONCE
			await RenderingServer.frame_post_draw
			if not is_instance_valid(ds):
				return false
			var r0 := Time.get_ticks_usec()
			var img := ds.get_texture().get_image()
			read_us += Time.get_ticks_usec() - r0
			if img == null or img.is_empty():
				ds.queue_free()
				return false
			if img.get_format() != Image.FORMAT_RGBA8:
				img.convert(Image.FORMAT_RGBA8)
			atlas.blit_rect(img, Rect2i(Vector2i.ZERO, Vector2i(mini(TILE, size.x - tile.position.x), mini(TILE, size.y - tile.position.y))), tile.position)
			tiles += 1
	var t_render := Time.get_ticks_usec()
	ds.queue_free()
	# Mallas y materiales ya no hacen falta (quedan en el atlas): se sueltan.
	Props3D.release_build_caches()
	if atlas.is_invisible():
		return false
	var regions := {}
	var keep: Array = []
	for item: Dictionary in layout.items:
		regions[item.def.name] = [item.cell, item.body]
		if item.def.get("keep", false):
			keep.append(item.def.name)
	_last_atlas = atlas.duplicate()
	_last_regions = regions
	_last_keep = keep
	Props3D.install(atlas, regions, keep)
	var t_end := Time.get_ticks_usec()
	last_report = {"cache": "miss", "atlas": size, "tiles": tiles, "pieces": layout.items.size(),
		"bytes": atlas.get_data().size(), "build_ms": (t_build - t0) / 1000.0, "render_ms": (t_render - t_build) / 1000.0,
		"readback_ms": read_us / 1000.0, "install_ms": (t_end - t_render) / 1000.0, "total_ms": (t_end - t0) / 1000.0}
	return true


# Lo último horneado (sin mipmaps), para guardarlo en el disco.
static var _last_atlas: Image
static var _last_regions: Dictionary = {}
static var _last_keep: Array = []


## Acomoda las piezas en estantes. Devuelve {size: Vector2i, items: [{def,
## cell: Rect2 (px del atlas), body: Rect2 (relativo a la celda), origin:
## Vector2 (px del atlas donde cae el origen de la pieza)}]}.
static func plan(defs: Array[Dictionary]) -> Dictionary:
	var items: Array[Dictionary] = []
	for def in defs:
		var node := Props3D.build(def)
		var box := projected_box(node)
		node.free()
		var res: float = def.res
		var body: Rect2 = def.body
		if not body.has_area():
			body = box
		var margin := (UiTheme.PROP_INK * 1.5 + 3.0) / res
		var cell_model := box.merge(body).grow(margin)
		var px := Vector2i((cell_model.size * res).ceil())
		items.append({"def": def, "model": cell_model, "px": px, "body_model": body})
	# Estantes: de la más alta a la más baja, de izquierda a derecha.
	var order := range(items.size())
	order.sort_custom(func(a: int, b: int) -> bool:
		return items[a].px.y > items[b].px.y if items[a].px.y != items[b].px.y else a < b)
	var x := 0
	var y := 0
	var shelf_h := 0
	for i: int in order:
		var it: Dictionary = items[i]
		var px: Vector2i = it.px
		if x + px.x > ATLAS_W:
			x = 0
			y += shelf_h + PAD
			shelf_h = 0
		var res: float = it.def.res
		var model: Rect2 = it.model
		var body_model: Rect2 = it.body_model
		it.cell = Rect2(x, y, px.x, px.y)
		it.body = Rect2((body_model.position - model.position) * res, body_model.size * res)
		it.origin = Vector2(x, y) - model.position * res
		x += px.x + PAD
		shelf_h = maxi(shelf_h, px.y)
	var h := y + shelf_h
	return {"size": Vector2i(ATLAS_W, ceili(h / 4.0) * 4), "items": items}


## Caja que ocupa la pieza vista de frente, en px lógicos (x derecha, y abajo).
static func projected_box(root: Node3D) -> Rect2:
	var box := Rect2()
	var first := true
	var stack: Array = [[root, root.transform]]
	while not stack.is_empty():
		var top: Array = stack.pop_back()
		var node: Node3D = top[0]
		var xf: Transform3D = top[1]
		if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
			var aabb := (node as MeshInstance3D).mesh.get_aabb()
			for k in 8:
				var p := xf * aabb.get_endpoint(k)
				var q := Vector2(p.x, -p.y)
				if first:
					box = Rect2(q, Vector2.ZERO)
					first = false
				else:
					box = box.expand(q)
		for c in node.get_children():
			if c is Node3D:
				stack.append([c, xf * (c as Node3D).transform])
	return box


## El contorno del shader de tinta se mide en unidades del mundo: con la
## pieza escalada por `res`, el ancho también.
static func _scale_ink(node: Node, res: float) -> void:
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		if mi.material_override != null:
			mi.material_override = Props3D.material_for_res(mi.material_override, res)
	for c in node.get_children():
		_scale_ink(c, res)


static func _tile_used(items: Array, tile: Rect2i) -> bool:
	for it: Dictionary in items:
		if Rect2(tile).intersects((it.cell as Rect2).grow(2.0)):
			return true
	return false


# --- Caché en disco ------------------------------------------------------------------

static func _cache_paths() -> Array[String]:
	var sig := Props3D.signature()
	return [CACHE_DIR + "atlas_%s.png" % sig, CACHE_DIR + "atlas_%s.json" % sig]


## Lee el atlas del disco si existe con la firma de hoy. true si quedó listo.
static func load_cache() -> bool:
	var t0 := Time.get_ticks_usec()
	var paths := _cache_paths()
	if not FileAccess.file_exists(paths[0]) or not FileAccess.file_exists(paths[1]):
		return false
	var meta: Variant = JSON.parse_string(FileAccess.get_file_as_string(paths[1]))
	if not meta is Dictionary or not (meta as Dictionary).has("regions"):
		return false
	var img := Image.load_from_file(ProjectSettings.globalize_path(paths[0]))
	if img == null or img.is_empty():
		return false
	if img.get_format() != Image.FORMAT_RGBA8:
		img.convert(Image.FORMAT_RGBA8)
	var regions := {}
	var raw: Dictionary = meta.regions
	for n: String in raw:
		var a: Array = raw[n]
		if a.size() != 8:
			return false
		regions[n] = [Rect2(a[0], a[1], a[2], a[3]), Rect2(a[4], a[5], a[6], a[7])]
	var keep: Array = meta.get("keep", [])
	Props3D.install(img, regions, keep)
	last_report = {"cache": "hit", "atlas": Vector2i(img.get_width(), img.get_height()), "pieces": regions.size(),
		"bytes": img.get_data().size(), "total_ms": (Time.get_ticks_usec() - t0) / 1000.0}
	return true


## Guarda el último horneado (y borra atlas viejos con otra firma).
static func save_cache() -> void:
	if _last_atlas == null:
		return
	DirAccess.make_dir_recursive_absolute(CACHE_DIR)
	var dir := DirAccess.open(CACHE_DIR)
	if dir != null:
		for f in dir.get_files():
			if f.begins_with("atlas_"):
				dir.remove(f)
	var paths := _cache_paths()
	var raw := {}
	for n: String in _last_regions:
		var cell: Rect2 = _last_regions[n][0]
		var body: Rect2 = _last_regions[n][1]
		raw[n] = [cell.position.x, cell.position.y, cell.size.x, cell.size.y, body.position.x, body.position.y, body.size.x, body.size.y]
	if _last_atlas.save_png(paths[0]) != OK:
		return
	var f := FileAccess.open(paths[1], FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify({"signature": Props3D.signature(), "regions": raw, "keep": _last_keep}))
	_last_atlas = null
