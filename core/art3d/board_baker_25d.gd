class_name Board25DBaker
extends RefCounted
## Hornea el escenario 3D de un tablero (Board25DScene) UNA vez a una
## textura del tamaño de la pantalla, vista con la cámara en perspectiva de
## BoardView25D. En cada cuadro el juego dibuja esa textura (1 draw call) y
## encima su parte 2D proyectada: no hay 3D por cuadro. Decisión: ADR 0019.
##
## Concepto: *horneado*. Renderizar algo caro una sola vez y guardar el
## resultado como imagen. Ejemplo: el tablero de Pintar el piso con sus 220
## baldosas, 40 bloques del marco con contorno, 4 esquinas con estrella y ~20
## juguetes alrededor son ~600 piezas 3D (≈ 1200 draw calls con los
## contornos). Horneado, es un rectángulo con textura.
##
## Pasos:
##   1. Entorno ("back"): se renderiza a 1/BACK_DIV de la pantalla sobre un
##      cielo pintado y se desenfoca en la placa (soft_blur, BLUR_PASSES
##      pasadas) antes de estirarlo: profundidad de campo barata, una vez.
##   2. Tablero ("board"): nítido, con supermuestreo (SUPERSAMPLE×) y en
##      azulejos (TILES × TILES): cada azulejo es la MISMA cámara con el
##      frustum corrido (`Camera3D.set_frustum` con desplazamiento). Así la
##      textura de render más grande mide lo que la pantalla (1920×1080) y
##      no 3840×2160. Se achica con el shader de las piezas 3D (el alfa se
##      promedia bien: bordes sin halo).
##   3. Se compone (tablero sobre entorno) en una imagen RGB de 1920×1080
##      (≈ 6 MB) y se guarda en `user://board25d/` con una firma: la próxima
##      vez se lee del disco (en un hilo aparte) en vez de renderizar.
##
## Sin pantalla (--headless, tests) o si falla, no hay textura y el juego se
## dibuja plano como antes (`MiniGame.draw_board_25d` devuelve false).

## Versión de la receta del escenario: subirla invalida la caché en disco.
const VERSION := 2
const CACHE_DIR := "user://board25d/"

## Apagado a mano (benchmark A/B, capturas "antes") o si una TV no lo soporta.
static var enabled := true
## Leer y guardar la caché en disco (las herramientas la apagan para iterar).
static var use_disk_cache := true
## Tests: hacer de cuenta que hay render (sin pantalla) para ejercer el
## dibujo 2.5D con una textura inyectada (ver inject).
static var fake_render := false
## Segundos que la textura queda en memoria después de que la deja de usar
## el último juego (si enseguida empieza otro igual, no se vuelve a leer).
static var release_after_sec := 2.0
## Datos del último horneado o lectura: tiempos (ms), tamaño y bytes.
static var last_report: Dictionary = {}

static var _textures: Dictionary = {}   # firma -> Texture2D
static var _running: Dictionary = {}    # firma -> true (horneando o leyendo)
static var _users: Dictionary = {}      # firma -> {id del nodo: true} (juegos que la dibujan)
static var _failed := false


## ¿Se puede usar el 2.5D en este aparato? (hay render y no falló antes).
static func available() -> bool:
	return enabled and not _failed and (fake_render or DisplayServer.get_name() != "headless")


## ¿No hay nada horneándose ni leyéndose? (las herramientas esperan esto).
static func is_idle() -> bool:
	return _running.is_empty()


## Textura ya lista para esta vista, o null (el juego dibuja plano).
static func texture_for(view: BoardView25D) -> Texture2D:
	if not available() or _textures.is_empty():
		return null
	return _textures.get(key_of(view))


## Firma de la vista + receta: cambia si cambia la cámara, el tablero, un
## color o medida del escenario (UiTheme BOARD25D_*), el código de los
## shaders de plástico y contorno, o VERSION (subirla al cambiar la receta).
static func key_of(view: BoardView25D) -> String:
	if view.has_meta("bake_key"):
		return view.get_meta("bake_key")
	var tokens := {}
	var theme_consts: Dictionary = (load("res://core/ui/ui_theme.gd") as Script).get_script_constant_map()
	for k: String in theme_consts:
		if k.begins_with("BOARD25D_"):
			tokens[k] = theme_consts[k]
	var parts := [VERSION, view.signature_parts(), tokens, UiTheme.BRICKS, UiTheme.BG_HAZE, UiTheme.GOLD,
		UiTheme.INK, UiTheme.SKY_TOP, UiTheme.SKY_BOTTOM, UiTheme.STAGE_CLOUD, UiTheme.PROP_STAR_SHADE, UiTheme.MASCOT_SHADE_TINT,
		# El plástico y el contorno (los ajusta la dirección de arte): si cambian, se vuelve a hornear.
		Board25DScene.SHADER_TOY.code.hash(), Board25DScene.SHADER_INK.code.hash()]
	# Colores propios de la receta (ej. los POOL_* de la mesa de pool).
	var own := Board25DScene.recipe_tokens(view.recipe)
	if not own.is_empty():
		parts.append(own)
	var key := "%08x" % (str(parts).hash() & 0xffffffff)
	view.set_meta("bake_key", key)
	return key


## Pide el escenario sin esperar (lo usa el juego si todavía no está): lo
## lee del disco o lo hornea en los cuadros siguientes.
static func request(host: Node, view: BoardView25D) -> void:
	if available() and not _running.has(key_of(view)) and not _textures.has(key_of(view)):
		ensure(host, view)


## Deja lista la textura (de la memoria, del disco o horneándola). Devuelve
## true si quedó. `host`: un nodo en el árbol (para los SubViewport).
static func ensure(host: Node, view: BoardView25D) -> bool:
	var key := key_of(view)
	if _textures.has(key):
		return available()
	if not available() or _running.has(key) or host == null or not host.is_inside_tree():
		return false
	if DisplayServer.get_name() == "headless":
		return false  # Sin render no se hornea ni se lee (tests con fake_render: inject).
	_running[key] = true
	var tree := host.get_tree()
	var tex: Texture2D = null
	if use_disk_cache:
		tex = await _load_cache(tree, view)
	if tex == null:
		var img := await bake(host, view)
		if img == null:
			_failed = true  # No se reintenta en esta sesión: queda el dibujo plano.
		else:
			tex = ImageTexture.create_from_image(img)
			if use_disk_cache:
				await _save_cache(tree, img, view)
	_running.erase(key)
	if tex != null:
		_textures[key] = tex
	return tex != null


## Suelta la textura de esta vista (≈ 6–8 MB de video). Se vuelve a leer del
## disco la próxima vez.
static func release(view: BoardView25D) -> void:
	_textures.erase(key_of(view))


## `node` (un juego) dibuja esta vista. Cuando el último que la usa sale del
## árbol, la textura se suelta a los `release_after_sec` segundos (si en ese
## rato empieza otro juego con la misma vista, se queda). Lo llama
## MiniGame.draw_board_25d; es barato llamarlo en cada cuadro.
static func retain(view: BoardView25D, node: Node) -> void:
	var key := key_of(view)
	var users: Dictionary = _users.get_or_add(key, {})
	var id := node.get_instance_id()
	if users.has(id) or not node.is_inside_tree():
		return
	users[id] = true
	var tree := node.get_tree()
	node.tree_exiting.connect(func() -> void: _on_user_exit(key, id, tree), CONNECT_ONE_SHOT)


static func _on_user_exit(key: String, id: int, tree: SceneTree) -> void:
	var users: Dictionary = _users.get(key, {})
	users.erase(id)
	if not users.is_empty() or tree == null:
		return
	tree.create_timer(release_after_sec).timeout.connect(func() -> void:
		if (_users.get(key, {}) as Dictionary).is_empty():
			_textures.erase(key))


static func release_all() -> void:
	_textures.clear()


## Memoria de las texturas en uso (bytes, estimada como RGBA8).
static func memory_bytes() -> int:
	var total := 0
	for t: Texture2D in _textures.values():
		total += t.get_width() * t.get_height() * 4
	return total


## Para tests y el benchmark: instala una textura como si se hubiera horneado.
static func inject(view: BoardView25D, tex: Texture2D) -> void:
	_textures[key_of(view)] = tex


## Olvida todo (tests): texturas, trabajos y fallas.
static func reset() -> void:
	_textures.clear()
	_running.clear()
	_users.clear()
	_failed = false


# --- Horneado ------------------------------------------------------------------------------

## Renderiza el escenario completo y devuelve la imagen compuesta (RGB, del
## tamaño de la pantalla), o null si no se pudo.
static func bake(host: Node, view: BoardView25D) -> Image:
	if host == null or not host.is_inside_tree() or DisplayServer.get_name() == "headless":
		return null
	var t0 := Time.get_ticks_usec()
	var size := Vector2i(view.screen)
	# 1. Entorno a menos resolución, sobre el cielo, y desenfocado.
	var back_size := size / UiTheme.BOARD25D_BACK_DIV
	var back_root := Board25DScene.build(view, Board25DScene.LAYER_BACK)
	var t_build_back := Time.get_ticks_usec()
	var back := await _render(host, view, back_root, back_size, 1, 1)
	if back == null:
		return null
	var t_back := Time.get_ticks_usec()
	var img := _sky(back_size)
	img.blend_rect(back, Rect2i(Vector2i.ZERO, back_size), Vector2i.ZERO)
	img = await _blur(host, img, UiTheme.BOARD25D_BLUR_STEP, UiTheme.BOARD25D_BLUR_PASSES)
	if img == null:
		return null
	img.resize(size.x, size.y, Image.INTERPOLATE_BILINEAR)
	# 2. Tablero nítido encima.
	var t_blur := Time.get_ticks_usec()
	var board_root := Board25DScene.build(view, Board25DScene.LAYER_BOARD)
	var t_build_board := Time.get_ticks_usec()
	var t_board := t_build_board
	if board_root.get_child_count() == 0:
		board_root.free()  # Receta sin tablero (la sala sola, "stage"): solo el entorno.
	else:
		var board := await _render(host, view, board_root, size, UiTheme.BOARD25D_SUPERSAMPLE, UiTheme.BOARD25D_TILES)
		if board == null:
			return null
		t_board = Time.get_ticks_usec()
		img.blend_rect(board, Rect2i(Vector2i.ZERO, size), Vector2i.ZERO)
	img.convert(Image.FORMAT_RGB8)
	Board25DScene.release_build_caches()
	var t_end := Time.get_ticks_usec()
	last_report = {"cache": "miss", "size": size, "bytes": img.get_data().size(),
		"build_ms": ((t_build_back - t0) + (t_build_board - t_blur)) / 1000.0,
		"render_back_ms": (t_back - t_build_back) / 1000.0, "blur_ms": (t_blur - t_back) / 1000.0,
		"render_board_ms": (t_board - t_build_board) / 1000.0, "compose_ms": (t_end - t_board) / 1000.0,
		"total_ms": (t_end - t0) / 1000.0}
	return img


## Renderiza `root` (se libera al terminar) con la cámara de `view` a una
## imagen de `out_size` px con fondo transparente. `ss`: supermuestreo;
## `tiles`: azulejos por lado (frustum corrido, ver arriba).
static func _render(host: Node, view: BoardView25D, root: Node3D, out_size: Vector2i, ss: int, tiles: int) -> Image:
	var tile_px := out_size / tiles
	var ds := SubViewport.new()
	ds.size = tile_px
	ds.transparent_bg = true
	ds.disable_3d = true
	ds.render_target_update_mode = SubViewport.UPDATE_DISABLED
	var rvp := SubViewport.new()
	rvp.size = tile_px * ss
	rvp.own_world_3d = true
	rvp.transparent_bg = true
	rvp.msaa_3d = Viewport.MSAA_DISABLED
	rvp.positional_shadow_atlas_size = 0
	rvp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	ds.add_child(rvp)
	var cam := Camera3D.new()
	cam.keep_aspect = Camera3D.KEEP_HEIGHT
	cam.transform = view.camera_transform()
	cam.near = view.near()
	cam.far = view.far()
	if tiles == 1:
		cam.projection = Camera3D.PROJECTION_PERSPECTIVE
		cam.fov = view.fov_deg
	else:
		cam.projection = Camera3D.PROJECTION_FRUSTUM
	rvp.add_child(cam)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_CLEAR_COLOR
	env.environment.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	rvp.add_child(env)
	rvp.add_child(root)
	var shrink := TextureRect.new()
	shrink.texture = rvp.get_texture()
	shrink.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	shrink.size = Vector2(tile_px)
	shrink.stretch_mode = TextureRect.STRETCH_SCALE
	shrink.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://core/art3d/props3d_downsample.gdshader")
	mat.set_shader_parameter("factor", ss)
	mat.set_shader_parameter("fill_color", UiTheme.INK)
	shrink.material = mat
	ds.add_child(shrink)
	# Bajo la raíz (no bajo el juego): si el juego se cierra a mitad del
	# horneado, el horneado termina igual y queda en la caché.
	host.get_tree().root.add_child(ds)
	var out := Image.create_empty(out_size.x, out_size.y, false, Image.FORMAT_RGBA8)
	# Frustum completo en el plano cercano: alto y ancho.
	var h_near := 2.0 * view.near() * tan(deg_to_rad(view.fov_deg) / 2.0)
	var w_near := h_near * float(out_size.x) / out_size.y
	for j in tiles:
		for i in tiles:
			if tiles > 1:
				var offset := Vector2((-0.5 + (i + 0.5) / tiles) * w_near, (0.5 - (j + 0.5) / tiles) * h_near)
				cam.set_frustum(h_near / tiles, offset, view.near(), view.far())
			rvp.render_target_update_mode = SubViewport.UPDATE_ONCE
			await RenderingServer.frame_post_draw
			ds.render_target_update_mode = SubViewport.UPDATE_ONCE
			await RenderingServer.frame_post_draw
			if not is_instance_valid(ds):
				return null
			var img := ds.get_texture().get_image()
			if img == null or img.is_empty():
				ds.queue_free()
				return null
			if img.get_format() != Image.FORMAT_RGBA8:
				img.convert(Image.FORMAT_RGBA8)
			out.blit_rect(img, Rect2i(Vector2i.ZERO, tile_px), Vector2i(i, j) * tile_px)
	ds.queue_free()
	if out.is_invisible():
		return null
	return out


## Desenfoque gaussiano en la placa (el shader del fondo de la TV,
## soft_blur), `passes` veces. Una vez por horneado: no corre por cuadro.
static func _blur(host: Node, img: Image, step: float, passes: int) -> Image:
	var vp := SubViewport.new()
	vp.size = img.get_size()
	vp.disable_3d = true
	vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	var rect := TextureRect.new()
	rect.size = Vector2(img.get_size())
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_SCALE
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://core/ui/shaders/soft_blur.gdshader")
	mat.set_shader_parameter("step_px", step)
	rect.material = mat
	vp.add_child(rect)
	host.get_tree().root.add_child(vp)
	var out := img
	for k in passes:
		rect.texture = ImageTexture.create_from_image(out)
		vp.render_target_update_mode = SubViewport.UPDATE_ONCE
		await RenderingServer.frame_post_draw
		if not is_instance_valid(vp):
			return null
		out = vp.get_texture().get_image()
		if out == null or out.is_empty():
			vp.queue_free()
			return null
		out.convert(Image.FORMAT_RGBA8)
	vp.queue_free()
	return out


## Cielo de fondo (lo que se ve donde termina el piso de la sala): degradé y
## nubes. Queda detrás del entorno y se desenfoca con él.
static func _sky(size: Vector2i) -> Image:
	var img := Image.create_empty(size.x, size.y, false, Image.FORMAT_RGBA8)
	for y in size.y:
		img.fill_rect(Rect2i(0, y, size.x, 1), UiTheme.SKY_TOP.lerp(UiTheme.SKY_BOTTOM, clampf(float(y) / (size.y * 0.35), 0.0, 1.0)))
	var k := size.x / 1920.0
	for c: Vector3 in [Vector3(130, 40, 46), Vector3(430, 18, 34), Vector3(1500, 30, 40), Vector3(1790, 70, 52)]:
		for d: Vector3 in [Vector3(-0.9, 0.25, 0.7), Vector3(0.9, 0.3, 0.65), Vector3(0, 0, 1)]:
			_disc(img, Vector2(c.x + d.x * c.z, c.y + d.y * c.z) * k, c.z * d.z * k, UiTheme.STAGE_CLOUD)
	return img


static func _disc(img: Image, c: Vector2, r: float, col: Color) -> void:
	for dy in range(-ceili(r), ceili(r) + 1):
		var half := sqrt(maxf(r * r - dy * dy, 0.0))
		var span := Rect2i(roundi(c.x - half), roundi(c.y) + dy, roundi(half * 2.0), 1).intersection(Rect2i(Vector2i.ZERO, img.get_size()))
		if span.has_area():
			img.fill_rect(span, col)


# --- Caché en disco --------------------------------------------------------------------------

## Un archivo por receta (ej. "paint"): al cambiar la firma se reemplaza el
## de esa receta y no los de otros juegos.
static func _cache_path(view: BoardView25D) -> String:
	return CACHE_DIR + "board_%s_%s.png" % [view.recipe.validate_filename(), key_of(view)]


## Lee la imagen del disco en un hilo aparte (no traba la intro) y la sube a
## la placa en el principal. null si no está.
static func _load_cache(tree: SceneTree, view: BoardView25D) -> Texture2D:
	var path := ProjectSettings.globalize_path(_cache_path(view))
	if not FileAccess.file_exists(_cache_path(view)):
		return null
	var t0 := Time.get_ticks_usec()
	var box := [null]
	var task := WorkerThreadPool.add_task(func() -> void: box[0] = Image.load_from_file(path))
	while not WorkerThreadPool.is_task_completed(task):
		await tree.process_frame
	WorkerThreadPool.wait_for_task_completion(task)
	var img: Image = box[0]
	if img == null or img.is_empty():
		return null
	var t_read := Time.get_ticks_usec()
	var tex := ImageTexture.create_from_image(img)
	last_report = {"cache": "hit", "size": img.get_size(), "bytes": img.get_data().size(),
		"read_ms": (t_read - t0) / 1000.0, "upload_ms": (Time.get_ticks_usec() - t_read) / 1000.0,
		"total_ms": (Time.get_ticks_usec() - t0) / 1000.0}
	return tex


## Guarda en el disco (en un hilo) y borra escenarios viejos de otra firma.
## Espera a que termine (sin trabar los cuadros): así ninguna tarea queda
## suelta si el programa se cierra enseguida.
static func _save_cache(tree: SceneTree, img: Image, view: BoardView25D) -> void:
	DirAccess.make_dir_recursive_absolute(CACHE_DIR)
	var path := _cache_path(view)
	var prefix := "board_%s_" % view.recipe.validate_filename()
	var dir := DirAccess.open(CACHE_DIR)
	if dir != null:
		for f in dir.get_files():
			if f.begins_with(prefix) and f != path.get_file():
				dir.remove(f)
	var task := WorkerThreadPool.add_task(func() -> void: img.save_png(path))
	while not WorkerThreadPool.is_task_completed(task):
		await tree.process_frame
	WorkerThreadPool.wait_for_task_completion(task)
