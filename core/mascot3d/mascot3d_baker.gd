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
## Distancia de la cámara del horneado (u del mundo). Concepto: el shader de
## plástico calcula la dirección de la vista (VIEW) desde cada punto hacia la
## cámara aunque la cámara sea ortográfica. Con la cámara cerca (antes, 80 u)
## una mascota en la celda del borde de un trabajo de 24 celdas (a ~140 u del
## centro) se veía desde ~60° de costado: brillos corridos y un "escalón" de
## luz entre celdas (brillo medio 143 → 157 de 255 en la misma pose). A
## 10 000 u la diferencia es < 1°: todas las celdas se ven como la del centro.
## No se aleja más (como las piezas de ADR 0016, a 100 000 u) para no perder
## precisión de profundidad en las piezas chicas (ojos, contorno a 0,18 u).
const CAM_DISTANCE := 10000.0
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


## --- Horneado repartido en cuadros (lo usa MascotAtlas) -------------------------
##
## Concepto: *trabajo en cuotas* (time slicing). Armar ~40 mascotas 3D en
## GDScript lleva decenas de ms: si se hace todo en un cuadro, la TV se traba
## (se nota en las animaciones del lobby). Job arma unas pocas mascotas por
## cuadro (hasta BUILD_BUDGET_USEC), recién después pide el render (un solo
## cuadro de GPU), en el cuadro siguiente lee la imagen y en otro la achica y
## la sube como textura. Ejemplo: 16 poses a 114×133 px → ~6 cuadros de
## trabajo chico en vez de uno de 80 ms.
##
## Celdas rectangulares (ATLAS_CELL, más altas que anchas: la mascota es más
## alta que ancha) en vez de cuadradas: ~25 % menos memoria por pose.

## Celda del atlas en unidades del mundo (ancho, alto): entran las orejas de
## conejo, la antena estirada, los brazos arriba y los ojos de costado. El
## salto, el squash y el baile se aplican después en 2D (no ocupan celda).
const ATLAS_CELL := Vector2(12.0, 14.0)
const ATLAS_FEET := 0.55  ## Pies arriba del borde de abajo (u. del mundo).
## Mascotas que se renderizan por cuadro durante un horneado (ver Job).
const POSES_PER_FRAME := 3
## Tope de píxeles del viewport de un trabajo (con supersampling): limita
## el costo del cuadro de render y la memoria temporal.
const MAX_JOB_PIXELS := 1024 * 1024


## Tamaño en px de una celda del atlas para mascotas de unidad u (PlayerAvatar).
static func atlas_cell_px(u: float) -> Vector2i:
	return Vector2i(maxi(8, roundi(ATLAS_CELL.x * 10.0 * u)), maxi(8, roundi(ATLAS_CELL.y * 10.0 * u)))


## Pies dentro de una celda del atlas de cell px (ver atlas_cell_px).
static func atlas_feet(cell: Vector2i) -> Vector2:
	var k := cell.y / ATLAS_CELL.y
	var cy := ATLAS_CELL.y / 2.0 - ATLAS_FEET
	return Vector2(cell.x / 2.0, cell.y / 2.0 + cy * _cam_basis().y.y * k)


## Cuántas poses entran en un trabajo con celdas de cell px.
static func max_job_poses(cell: Vector2i) -> int:
	var px := cell.x * cell.y * SUPERSAMPLE * SUPERSAMPLE
	return clampi(MAX_JOB_PIXELS / maxi(1, px), 1, 24)


## Grilla (columnas, filas) de los trabajos con celdas de cell px: siempre
## la misma para un tamaño, así el viewport se reutiliza entre trabajos.
static func job_grid(cell: Vector2i) -> Vector2i:
	var n := max_job_poses(cell)
	var cols := clampi(MAX_VIEWPORT / maxi(1, cell.x * SUPERSAMPLE), 1, n)
	return Vector2i(cols, ceili(float(n) / cols))


## Viewport y mascotas del último trabajo, para reutilizarlos en el siguiente
## (crear un viewport grande cuesta ~12 ms por megapíxel en llvmpipe: es
## reservar y limpiar la memoria del render). MascotAtlas lo suelta cuando
## no queda nada por hornear (release_pool).
static var _pool_vp: SubViewport
static var _pool_mascots: Array[Mascot3D] = []
static var _pool_look := ""


## Suelta el viewport y las mascotas guardadas para el próximo horneado.
static func release_pool() -> void:
	if is_instance_valid(_pool_vp):
		_pool_vp.queue_free()
	_pool_vp = null
	_pool_mascots.clear()
	_pool_look = ""


## Un horneado en curso. Uso: job = Job.new(look, poses, cell); en cada
## cuadro job.step(host) hasta que devuelva true; después job.ok, job.texture
## y job.regions (nombre -> Rect2 en px dentro de la textura).
##
## Concepto: *render acumulado*. El viewport no se borra entre cuadros
## (fondo Environment.BG_KEEP): en cada cuadro se ponen POSES_PER_FRAME
## mascotas en las celdas siguientes, se renderiza y en el cuadro siguiente
## se mueven a otras celdas con otra pose. Las celdas ya dibujadas quedan.
## Así un cuadro de la TV nunca renderiza más que unas pocas mascotas, se
## arman solo POSES_PER_FRAME mascotas por trabajo (apply() cambia la pose
## sin volver a armarlas) y se lee la imagen una sola vez al final.
class Job extends RefCounted:
	enum State { NEW, BUILD, RENDER, READBACK, SHRINK, UPLOAD, DONE }
	var look: Dictionary
	var poses: Array[Dictionary]
	var cell := Vector2i(114, 133)
	var state := State.NEW
	var ok := false
	var texture: ImageTexture
	var regions: Dictionary = {}   ## nombre -> Rect2 (px) en texture.
	var bytes := 0
	## Medición: ms de CPU del peor cuadro, total de CPU y cuadros usados.
	var worst_ms := 0.0
	var cpu_ms := 0.0
	var frames := 0
	var started_msec := 0
	## ms por etapa (el peor cuadro de cada una).
	var stage_ms := {"setup": 0.0, "build": 0.0, "pose": 0.0, "readback": 0.0, "shrink": 0.0, "upload": 0.0}
	var _vp: SubViewport
	var _env: Environment
	var _mascots: Array[Mascot3D] = []
	var _next := 0          ## Próxima pose a renderizar.
	var _cols := 1
	var _rows := 1
	var _rendered := true
	var _img: Image

	func _init(p_look: Dictionary, p_poses: Array, p_cell: Vector2i) -> void:
		look = p_look
		cell = Vector2i(maxi(8, p_cell.x), maxi(8, p_cell.y))
		var grid := Mascot3DBaker.job_grid(cell)
		poses = Mascot3DBaker._resolve(p_poses).slice(0, grid.x * grid.y)
		_cols = grid.x
		_rows = grid.y

	## Avanza un paso. Devuelve true cuando terminó (bien o mal: ver ok).
	func step(host: Node) -> bool:
		if state == State.DONE:
			return true
		var t0 := Time.get_ticks_usec()
		var stage := ""
		frames += 1
		match state:
			State.NEW:
				stage = "setup"
				started_msec = Time.get_ticks_msec()
				if poses.is_empty() or host == null or not host.is_inside_tree() \
						or DisplayServer.get_name() == "headless":
					_finish(false)
				else:
					_setup(host)
			State.BUILD:
				# Una mascota por cuadro (armarla es lo más caro en CPU).
				stage = "build"
				var m := Mascot3D.new().setup(Mascot3DBaker._look_color(look), int(look.get("style", 0)))
				m.visible = false
				_vp.add_child(m)
				_mascots.append(m)
				if _mascots.size() >= mini(POSES_PER_FRAME, poses.size()):
					state = State.RENDER
					_render_next()
			State.RENDER:
				if _rendered:
					stage = "pose"
					if _next < poses.size():
						_render_next()
					else:
						state = State.READBACK
			State.READBACK:
				stage = "readback"
				_img = _vp.get_texture().get_image()
				_release()
				if _img == null or _img.is_empty():
					_finish(false)
				else:
					state = State.SHRINK
			State.SHRINK:
				stage = "shrink"
				if _img.get_format() != Image.FORMAT_RGBA8:
					_img.convert(Image.FORMAT_RGBA8)
				# Solo las celdas usadas (el viewport es el de la grilla completa).
				var used := Vector2i(mini(poses.size(), _cols), ceili(float(poses.size()) / _cols))
				var ss := Mascot3DBaker.SUPERSAMPLE
				if used != Vector2i(_cols, _rows):
					_img = _img.get_region(Rect2i(Vector2i.ZERO, used * cell * ss))
				# Supersampling 2×: promedio de 2×2 píxeles (filtro de caja).
				if ss == 2:
					_img.shrink_x2()
				elif ss > 1:
					_img.resize(used.x * cell.x, used.y * cell.y, Image.INTERPOLATE_BILINEAR)
				state = State.UPLOAD
			State.UPLOAD:
				stage = "upload"
				texture = ImageTexture.create_from_image(_img)
				bytes = _img.get_width() * _img.get_height() * 4
				_img = null
				for i in poses.size():
					regions[poses[i].name] = Rect2(Vector2(i % _cols * cell.x, i / _cols * cell.y), Vector2(cell))
				_finish(true)
		var dt := (Time.get_ticks_usec() - t0) / 1000.0
		cpu_ms += dt
		worst_ms = maxf(worst_ms, dt)
		if stage != "":
			stage_ms[stage] = maxf(float(stage_ms[stage]), dt)
		return state == State.DONE

	## Corta el trabajo (ej. el jugador se fue).
	func cancel() -> void:
		_finish(false)

	func _setup(host: Node) -> void:
		var px := Vector2i(_cols * cell.x, _rows * cell.y) * Mascot3DBaker.SUPERSAMPLE
		var look_key := "%s|%d" % [Mascot3DBaker._look_color(look).to_html(), int(look.get("style", 0))]
		var vp := Mascot3DBaker._pool_vp
		if is_instance_valid(vp) and vp.size == px and vp.is_inside_tree():
			_vp = vp
			if Mascot3DBaker._pool_look == look_key:
				_mascots = Mascot3DBaker._pool_mascots.duplicate()
			else:
				for m in Mascot3DBaker._pool_mascots:
					m.queue_free()
		else:
			Mascot3DBaker.release_pool()
			_vp = Mascot3DBaker.make_viewport(px, _cols, _rows, Mascot3D.Shading.TOON, ATLAS_CELL.y)
			host.add_child(_vp)
		Mascot3DBaker._pool_vp = null
		Mascot3DBaker._pool_mascots.clear()
		Mascot3DBaker._pool_look = look_key
		_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
		var env := _vp.find_children("*", "WorldEnvironment", false, false)
		_env = (env[0] as WorldEnvironment).environment if not env.is_empty() else null
		if _env:
			_env.background_mode = Environment.BG_CLEAR_COLOR  # El primer render borra (ver _render_next).
		for m in _mascots:
			m.visible = false
		state = State.BUILD if _mascots.size() < mini(POSES_PER_FRAME, poses.size()) else State.RENDER
		if state == State.RENDER:
			_render_next()

	## Pone las próximas poses en sus celdas y pide un render.
	func _render_next() -> void:
		var cell_w := ATLAS_CELL.y * cell.x / float(cell.y)  # Ancho exacto de la celda en el mundo.
		if _env and _next > 0:
			_env.background_mode = Environment.BG_KEEP  # Desde el segundo render, acumula.
		for m in _mascots:
			m.visible = _next < poses.size()
			if not m.visible:
				continue
			var p := poses[_next]
			m.apply(int(p.mood), p.anim)
			m.position = Mascot3DBaker.cell_origin(_next % _cols, _next / _cols, _cols, _rows,
				Vector2(cell_w, ATLAS_CELL.y), ATLAS_FEET)
			_next += 1
		_rendered = false
		RenderingServer.frame_post_draw.connect(_on_rendered, CONNECT_ONE_SHOT)
		_vp.render_target_update_mode = SubViewport.UPDATE_ONCE

	func _on_rendered() -> void:
		_rendered = true

	## Devuelve el viewport y las mascotas al pozo (para el próximo trabajo).
	func _release() -> void:
		if is_instance_valid(_vp):
			_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
			for m in _mascots:
				m.visible = false
			if is_instance_valid(Mascot3DBaker._pool_vp) and Mascot3DBaker._pool_vp != _vp:
				Mascot3DBaker.release_pool()
			Mascot3DBaker._pool_vp = _vp
			Mascot3DBaker._pool_mascots = _mascots.duplicate()
		_vp = null
		_mascots.clear()

	func _finish(p_ok: bool) -> void:
		if not p_ok and is_instance_valid(_vp):
			_vp.queue_free()  # Algo falló: no se reutiliza.
			if Mascot3DBaker._pool_vp == _vp:
				Mascot3DBaker.release_pool()
		elif is_instance_valid(_vp):
			_release()
		_vp = null
		_mascots.clear()
		_img = null
		ok = p_ok
		state = State.DONE


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
static func make_viewport(px: Vector2i, cols := 1, rows := 1, p_shading := Mascot3D.Shading.TOON,
		cell_h := CELL_WORLD) -> SubViewport:
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
	cam.size = cell_h * rows
	cam.near = CAM_DISTANCE - 500.0
	cam.far = CAM_DISTANCE + 500.0
	cam.basis = _cam_basis()
	cam.position = cam.basis.z * CAM_DISTANCE
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
## cell_world: ancho y alto de la celda (default: cuadrada de CELL_WORLD).
static func cell_origin(i: int, j: int, cols: int, rows: int, cell_world := Vector2(CELL_WORLD, CELL_WORLD),
		feet_margin := FEET_MARGIN) -> Vector3:
	var b := _cam_basis()
	var sx := (i - (cols - 1) / 2.0) * cell_world.x
	var sy := ((rows - 1) / 2.0 - j) * cell_world.y
	# El punto de la mascota que va al centro de la celda: (0, cy, 0).
	var cy := cell_world.y / 2.0 - feet_margin
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
