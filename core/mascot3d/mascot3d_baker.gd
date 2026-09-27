class_name Mascot3DBaker
extends RefCounted
## "Horneado" de las mascotas 3D a un atlas de sprites 2D.
##
## Concepto: *horneado a atlas* (bake). En vez de renderizar la mascota 3D
## en cada cuadro, al empezar la partida se la renderiza UNA vez en cada
## pose que el juego va a usar (quieta, parpadeo, pasos de la caminata,
## feliz…) y se guardan todas las fotos en una sola imagen grande (atlas).
## Después el juego dibuja la foto que corresponde como un sprite 2D común:
## en la TV cuesta lo mismo que cualquier textura, sin 3D.
## Ejemplo: 1P rojo con antena -> un atlas de 5×2 celdas; "Paso 1" es la
## celda (0, 1). La animación de caminar es ir cambiando de celda.
##
## Truco: las poses no se renderizan de a una (un cuadro por pose), sino
## todas juntas en una grilla con una cámara ortográfica. Como la cámara
## ortográfica no tiene perspectiva, cada mascota se ve igual en su celda
## que si estuviera sola: un solo cuadro de render da el atlas entero.
##
## Uso (en un nodo que ya está en el árbol):
##   var sprites := await Mascot3DBaker.bake(self, {"color": Color.RED, "style": 0}, ["normal", "walk1"])
##   sprites["walk1"]  # AtlasTexture de 192×192 (los pies en feet_offset(192))
##
## En --headless no hay placa de video: bake() arma igual la escena (así
## los tests verifican que no hay errores) y devuelve un diccionario vacío.


## Encuadre de cada celda en unidades del mundo (1 = 10 u de PlayerAvatar):
## 144 u de lado, los pies 6 u arriba del borde de abajo. Entra la mascota
## estirada en el salto con orejas de conejo y la aplastada al aterrizar.
const CELL_WORLD := 14.4
const FEET_MARGIN := 0.6
## Cámara apenas desde arriba (grados), como la maqueta.
const PITCH_DEG := 8.0
## Supersampling: se renderiza al doble y se achica (bordes suaves sin MSAA).
const SUPERSAMPLE := 2
## Lado máximo del viewport de horneado (GLES3 garantiza 2048; la mayoría 4096+).
const MAX_VIEWPORT := 4096

## Poses con nombre: [ánimo, anim] (mismas claves que PlayerAvatar.draw_mascot).
## Las de la hoja de personajes (tools/character_sheet.gd) más cuadros de animación.
const POSES := {
	"normal": [PlayerAvatar.Mood.NORMAL, {}],
	"blink": [PlayerAvatar.Mood.NORMAL, {"blink": true}],
	"look": [PlayerAvatar.Mood.NORMAL, {"look": Vector2(1, -0.4)}],
	"happy": [PlayerAvatar.Mood.HAPPY, {"wave": true, "t": 0.3}],
	"sad": [PlayerAvatar.Mood.SAD, {"t": 0.4}],
	"surprised": [PlayerAvatar.Mood.SURPRISED, {}],
	"walk1": [PlayerAvatar.Mood.NORMAL, {"walk": 0.25, "look": Vector2(1, 0)}],
	"walk2": [PlayerAvatar.Mood.NORMAL, {"walk": 0.75, "look": Vector2(1, 0)}],
	"jump": [PlayerAvatar.Mood.HAPPY, {"squash": -0.22, "wave": true}],
	"land": [PlayerAvatar.Mood.NORMAL, {"squash": 0.3}],
	# Cuadros de animación para los juegos.
	"idle0": [PlayerAvatar.Mood.NORMAL, {"bob": 0.0}],
	"idle1": [PlayerAvatar.Mood.NORMAL, {"bob": 1.3}],
	"idle2": [PlayerAvatar.Mood.NORMAL, {"bob": 0.0}],
	"idle3": [PlayerAvatar.Mood.NORMAL, {"bob": -1.3}],
	"walk_0": [PlayerAvatar.Mood.NORMAL, {"walk": 0.0, "look": Vector2(1, 0)}],
	"walk_1": [PlayerAvatar.Mood.NORMAL, {"walk": 0.125, "look": Vector2(1, 0)}],
	"walk_2": [PlayerAvatar.Mood.NORMAL, {"walk": 0.25, "look": Vector2(1, 0)}],
	"walk_3": [PlayerAvatar.Mood.NORMAL, {"walk": 0.375, "look": Vector2(1, 0)}],
	"walk_4": [PlayerAvatar.Mood.NORMAL, {"walk": 0.5, "look": Vector2(1, 0)}],
	"walk_5": [PlayerAvatar.Mood.NORMAL, {"walk": 0.625, "look": Vector2(1, 0)}],
	"walk_6": [PlayerAvatar.Mood.NORMAL, {"walk": 0.75, "look": Vector2(1, 0)}],
	"walk_7": [PlayerAvatar.Mood.NORMAL, {"walk": 0.875, "look": Vector2(1, 0)}],
	"wave_0": [PlayerAvatar.Mood.HAPPY, {"wave": true, "t": 0.0}],
	"wave_1": [PlayerAvatar.Mood.HAPPY, {"wave": true, "t": 0.13}],
	"wave_2": [PlayerAvatar.Mood.HAPPY, {"wave": true, "t": 0.26}],
	"wave_3": [PlayerAvatar.Mood.HAPPY, {"wave": true, "t": 0.39}],
}

## Juego típico: respirar, parpadeo, caminar (8 cuadros, se espeja en 2D
## para ir a la izquierda), festejo, triste, sorpresa, salto y aterrizaje.
const GAME_POSES: Array[String] = ["idle0", "idle1", "idle2", "idle3", "blink",
	"walk_0", "walk_1", "walk_2", "walk_3", "walk_4", "walk_5", "walk_6", "walk_7",
	"wave_0", "wave_1", "wave_2", "wave_3", "sad", "surprised", "jump", "land"]

## Datos del último horneado (para medir): ms de armado, render y lectura,
## tamaño del atlas y bytes que ocupa en memoria.
static var last_report: Dictionary = {}


## Hornea las poses del look de un jugador. host: un nodo en el árbol (el
## SubViewport se cuelga ahí mientras dura el horneado). look: {"color":
## Color o índice de Protocol.MASCOT_COLORS, "style": índice de estilo}.
## poses: nombres de POSES o diccionarios {"name", "mood", "anim"}.
## cell_px: lado de cada celda (la mascota mide ~cell_px × 0,73 de alto).
## Devuelve nombre -> AtlasTexture (todas comparten una ImageTexture).
static func bake(host: Node, look: Dictionary, poses: Array, cell_px := 192,
		p_shading := Mascot3D.Shading.TOON) -> Dictionary[String, Texture2D]:
	var out: Dictionary[String, Texture2D] = {}
	var t0 := Time.get_ticks_usec()
	var list := _resolve(poses)
	if list.is_empty() or host == null or not host.is_inside_tree():
		return out
	var ss := SUPERSAMPLE
	var cols := mini(list.size(), maxi(1, MAX_VIEWPORT / (cell_px * ss)))
	var rows := ceili(float(list.size()) / cols)
	var vp := make_viewport(Vector2i(cols, rows) * cell_px * ss, cols, rows, p_shading)
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	var col := _look_color(look)
	var style := int(look.get("style", 0))
	for i in list.size():
		var m := Mascot3D.new().setup(col, style, p_shading)
		m.apply(int(list[i].mood), list[i].anim)
		m.position = cell_origin(i % cols, i / cols, cols, rows)
		vp.add_child(m)
	host.add_child(vp)
	var t_build := Time.get_ticks_usec()
	if DisplayServer.get_name() == "headless":
		last_report = {"build_ms": (t_build - t0) / 1000.0, "headless": true}
		vp.queue_free()
		return out
	await RenderingServer.frame_post_draw
	var t_render := Time.get_ticks_usec()
	var img := vp.get_texture().get_image()
	var t_read := Time.get_ticks_usec()
	vp.queue_free()
	if img == null or img.is_empty():
		return out
	if img.get_format() != Image.FORMAT_RGBA8:
		img.convert(Image.FORMAT_RGBA8)
	if ss > 1:
		img.resize(img.get_width() / ss, img.get_height() / ss, Image.INTERPOLATE_BILINEAR)
	var atlas := ImageTexture.create_from_image(img)
	for i in list.size():
		var tex := AtlasTexture.new()
		tex.atlas = atlas
		tex.region = Rect2(Vector2(i % cols, i / cols) * cell_px, Vector2(cell_px, cell_px))
		out[list[i].name] = tex
	var t_end := Time.get_ticks_usec()
	last_report = {
		"poses": list.size(), "cell_px": cell_px, "atlas": Vector2i(img.get_width(), img.get_height()),
		"bytes": img.get_data().size(),
		"build_ms": (t_build - t0) / 1000.0, "render_ms": (t_render - t_build) / 1000.0,
		"readback_ms": (t_read - t_render) / 1000.0, "pack_ms": (t_end - t_read) / 1000.0,
		"total_ms": (t_end - t0) / 1000.0,
	}
	return out


## Punto de los pies dentro de una celda de cell_px (para ubicar el sprite).
static func feet_offset(cell_px: float) -> Vector2:
	var k := cell_px / CELL_WORLD
	var cy := CELL_WORLD / 2.0 - FEET_MARGIN
	return Vector2(cell_px / 2.0, cell_px / 2.0 + cy * _cam_basis().y.y * k)


## Tamaño de celda para que la mascota mida como PlayerAvatar con unidad u.
static func cell_for_u(u: float) -> int:
	return int(ceil(CELL_WORLD * 10.0 * u))


## SubViewport con mundo propio, fondo transparente y la cámara de las
## mascotas, para una grilla de cols × rows celdas.
static func make_viewport(px: Vector2i, cols := 1, rows := 1, p_shading := Mascot3D.Shading.TOON) -> SubViewport:
	var vp := SubViewport.new()
	vp.size = px
	vp.own_world_3d = true
	vp.transparent_bg = true
	vp.disable_3d = false
	vp.msaa_3d = Viewport.MSAA_DISABLED
	vp.positional_shadow_atlas_size = 0
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.keep_aspect = Camera3D.KEEP_HEIGHT
	cam.size = CELL_WORLD * rows
	cam.near = 1.0
	cam.far = 200.0
	cam.basis = _cam_basis()
	cam.position = cam.basis.z * 80.0
	vp.add_child(cam)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_CLEAR_COLOR
	env.environment.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	if p_shading == Mascot3D.Shading.STANDARD:
		add_studio_lights(vp, env.environment)
	vp.add_child(env)
	vp.set_meta("grid", Vector2i(cols, rows))
	return vp


## Luz de estudio con luces reales (solo para la variante STANDARD): principal
## arriba a la izquierda, relleno suave a la derecha y contraluz desde atrás.
## El shader propio (TOON) tiene estas tres luces "pintadas" adentro.
static func add_studio_lights(vp: Node, env: Environment) -> void:
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = UiTheme.SKY_BOTTOM
	env.ambient_light_energy = 0.55
	var cam := _cam_basis()
	for spec in [[Vector3(-0.5, 0.85, 0.3), 1.25, Color.WHITE], [Vector3(0.75, 0.05, 0.66), 0.35, UiTheme.SKY_BOTTOM],
			[Vector3(0.62, 0.55, -0.56), 0.9, Color.WHITE]]:
		var l := DirectionalLight3D.new()
		var dir: Vector3 = cam * (spec[0] as Vector3).normalized()  # De la cámara al mundo.
		l.basis = Basis.looking_at(-dir, Vector3.UP if absf(dir.y) < 0.99 else Vector3.FORWARD)
		l.light_energy = spec[1]
		l.light_color = spec[2]
		l.shadow_enabled = false
		vp.add_child(l)


## Dónde poner los pies de la mascota de la celda (i, j) para que se vea
## centrada en su celda (con la cámara inclinada, la grilla se arma en el
## plano de la pantalla, no en el piso).
static func cell_origin(i: int, j: int, cols: int, rows: int) -> Vector3:
	var b := _cam_basis()
	var sx := (i - (cols - 1) / 2.0) * CELL_WORLD
	var sy := ((rows - 1) / 2.0 - j) * CELL_WORLD
	# El punto de la mascota que va al centro de la celda: (0, cy, 0).
	var cy := CELL_WORLD / 2.0 - FEET_MARGIN
	return b.x * sx + b.y * (sy - cy * b.y.y)


static func _cam_basis() -> Basis:
	return Basis(Vector3.RIGHT, -deg_to_rad(PITCH_DEG))


static func _look_color(look: Dictionary) -> Color:
	var c: Variant = look.get("color", 0)
	if c is Color:
		return c
	return Protocol.mascot_color(int(c)) if (c is int or c is float) else Protocol.MASCOT_COLORS[0]


static func _resolve(poses: Array) -> Array[Dictionary]:
	var list: Array[Dictionary] = []
	for p: Variant in poses:
		if p is String and POSES.has(p):
			list.append({"name": p, "mood": POSES[p][0], "anim": POSES[p][1]})
		elif p is Dictionary and (p as Dictionary).has("name"):
			list.append({"name": str(p.name), "mood": int(p.get("mood", PlayerAvatar.Mood.NORMAL)), "anim": p.get("anim", {})})
	return list
