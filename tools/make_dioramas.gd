extends SceneTree
## Renderiza los dioramas 3D de los juegos (GameDiorama, ADR 0018) para las
## tarjetas del lobby: assets/thumbs/diorama/<id>.webp. Un juego sin receta
## propia sale con la genérica (escenario de su color y su control), así que
## un juego nuevo tiene diorama con solo correr esto.
##
##   xvfb-run -a -s "-screen 0 1920x1080x24" godot --path . --rendering-driver opengl3 \
##     --audio-driver Dummy -s res://tools/make_dioramas.gd
##   … -- --only=arena,pool        (algunos juegos)
##   … -- --out=/tmp/dioramas       (otra carpeta, para revisar sin pisar assets/)
##   … -- --generic                 (además, <id>_generic con la receta genérica)
##
## Después, `godot --headless --path . --import` para que Godot importe los
## archivos nuevos (sin eso la tarjeta usa la captura de make_thumbnails).
##
## Cómo se arma cada imagen: el fondo (torres de bloques, estrellas) se
## renderiza aparte y se desenfoca (como una foto con poca profundidad de
## campo); encima va el frente (escenario, piezas y mascotas), nítido. Todo
## se renderiza al doble y se achica al final (bordes suaves sin MSAA).
## Necesita pantalla (real o xvfb): con --headless Godot no dibuja.

const OUT_DIR := "res://assets/thumbs/diorama/"
const EXT := ".webp"
const SIZE := Vector2i(648, 240)   ## ≈ 2,7:1, la franja de la tarjeta del lobby.
const SUPERSAMPLE := 2
const WEBP_QUALITY := 0.9
const BLUR_DOWN := 7               ## El fondo se achica tantas veces y se vuelve a agrandar (desenfoque).

var _out_dir := OUT_DIR
var _only: Array[String] = []
var _generic := false


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			_out_dir = arg.trim_prefix("--out=").trim_suffix("/") + "/"
		elif arg.begins_with("--only="):
			_only.assign(arg.trim_prefix("--only=").split(",", false))
		elif arg == "--generic":
			_generic = true
	DirAccess.make_dir_recursive_absolute(_out_dir)
	var jobs: Array[Dictionary] = []
	for info in MiniGameRegistry.all_info():
		if not _only.is_empty() and not info.id in _only:
			continue
		jobs.append({"info": info, "name": info.id})
		if _generic:
			var g := info.duplicate()
			g.id = "_generic_" + info.id  # Sin receta: sale la genérica.
			jobs.append({"info": g, "name": info.id + "_generic"})
	var t0 := Time.get_ticks_msec()
	for job: Dictionary in jobs:
		var img := await render(root, job.info)
		if img == null:
			printerr("FALLA: no se pudo renderizar ", job.name)
			quit(1)
			return
		var path: String = _out_dir + job.name + EXT
		img.save_webp(path, false, WEBP_QUALITY)
		print("  ", job.name, EXT)
	print("Dioramas: %d en %.1f s -> %s" % [jobs.size(), (Time.get_ticks_msec() - t0) / 1000.0,
		ProjectSettings.globalize_path(_out_dir)])
	quit(0)


## Imagen final (SIZE) del diorama del juego `info`, o null si falló.
static func render(host: Node, info: Dictionary) -> Image:
	var scene := GameDiorama.build(info)
	var px := SIZE * SUPERSAMPLE
	var bg := await _render_layer(host, scene.bg, scene.camera, px)
	var fg := await _render_layer(host, scene.fg, scene.camera, px)
	GameDiorama.release()
	if bg == null or fg == null:
		return null
	# Cielo en degradé, fondo desenfocado y frente nítido.
	var sky: Array[Color] = scene.sky
	var out := Image.create_empty(px.x, px.y, false, Image.FORMAT_RGBA8)
	for y in px.y:
		var col := sky[0].lerp(sky[1], float(y) / (px.y - 1))
		out.fill_rect(Rect2i(0, y, px.x, 1), col)
	var blur := bg.duplicate() as Image
	blur.resize(px.x / BLUR_DOWN, px.y / BLUR_DOWN, Image.INTERPOLATE_BILINEAR)
	blur.resize(px.x / BLUR_DOWN / 2, px.y / BLUR_DOWN / 2, Image.INTERPOLATE_BILINEAR)
	blur.resize(px.x, px.y, Image.INTERPOLATE_CUBIC)
	# Bruma: lo de atrás se mezcla un poco con el cielo claro (profundidad).
	var haze := Image.create_empty(px.x, px.y, false, Image.FORMAT_RGBA8)
	haze.fill(Color(sky[1], UiTheme.DIORAMA_HAZE))
	out.blend_rect(blur, Rect2i(Vector2i.ZERO, px), Vector2i.ZERO)
	out.blend_rect(haze, Rect2i(Vector2i.ZERO, px), Vector2i.ZERO)
	out.blend_rect(fg, Rect2i(Vector2i.ZERO, px), Vector2i.ZERO)
	out.convert(Image.FORMAT_RGB8)
	out.resize(SIZE.x, SIZE.y, Image.INTERPOLATE_LANCZOS)
	return out


## Renderiza `world` (se libera al terminar) con fondo transparente.
static func _render_layer(host: Node, world: Node3D, cam_def: Dictionary, px: Vector2i) -> Image:
	var vp := SubViewport.new()
	vp.size = px
	vp.own_world_3d = true
	vp.transparent_bg = true
	vp.msaa_3d = Viewport.MSAA_DISABLED
	vp.positional_shadow_atlas_size = 0
	vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	var cam := Camera3D.new()
	cam.fov = cam_def.fov
	cam.near = 1.0
	cam.far = 1000.0
	vp.add_child(cam)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_CLEAR_COLOR
	env.environment.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	vp.add_child(env)
	vp.add_child(world)
	host.add_child(vp)
	cam.look_at_from_position(cam_def.pos, cam_def.target, Vector3.UP)
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	await RenderingServer.frame_post_draw
	var img := vp.get_texture().get_image()
	vp.queue_free()
	if img == null or img.is_empty():
		return null
	img.convert(Image.FORMAT_RGBA8)
	return img
