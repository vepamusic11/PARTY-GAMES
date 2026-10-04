extends SceneTree
## Hoja de personajes de las mascotas 3D (prototipo, ver docs/ARTE.md): las
## mismas columnas que tools/character_sheet.gd para comparar lado a lado
## con la versión 2D. Las mascotas se hornean con Mascot3DBaker (un render
## por jugador) y se dibujan como sprites 2D, igual que las usaría un juego.
##
##   xvfb-run -a -s "-screen 0 1920x1080x24" godot --path . --rendering-driver opengl3 \
##     --audio-driver Dummy -s res://tools/mascot3d_sheet.gd -- --out=docs/img/mascotas_3d.png
##
## Opciones (después de --):
##   --styles      todos los estilos en una paleta amplia (como character_sheet --styles)
##   --closeup     grandes (lobby, podio) arriba y chicas (juegos) abajo
##   --compare     maqueta vs. 2D actual vs. 3D, las 4 mascotas en dos poses
##   --expressions todos los ánimos (enojada, mareada, dormida, ganadora, riendo…)
##                 y, en fases, los tres bailes, la derrota y el saludo
##   --ref=N       revisión de detalle de la mascota N (0–3) contra la maqueta:
##                 grandes y a la misma escala, y abajo a tamaño de juego (116 px)
##   --moods=N     los 9 ánimos grandes con el color N de la paleta (estilo N % 7)
##   --standard    material estándar de Godot (PBR + clearcoat) con luces reales
##   --width=1920  ancho de la imagen (default 1280, como la hoja 2D)
##   --all=DIR     todas las hojas en DIR con los nombres de docs/img
##                 (mascotas_3d.png, _estilos, _cerca, _comparacion, _expresiones, _detalle)
##
## Necesita pantalla (xvfb): con --headless no se renderiza nada.

const SIZE := Vector2i(1920, 1080)
const OUT_WIDTH := 1280
const PALETTE: Array[Color] = Protocol.MASCOT_COLORS
const REFERENCE := "res://docs/design/referencia_mascotas.webp"

## Columnas de la hoja (mismas que tools/character_sheet.gd).
const COLUMNS := [["Normal", "normal"], ["Parpadeo", "blink"], ["Mira", "look"], ["Feliz", "happy"],
	["Triste", "sad"], ["Sorpresa", "surprised"], ["Paso 1", "walk1"], ["Paso 2", "walk2"],
	["Salto", "jump"], ["Aterriza", "land"]]

var _shading := Mascot3D.Shading.TOON
var _ref_slot := 0


## Lienzo que dibuja una lista de sprites (textura, pies, sombra) y textos.
class _Canvas:
	extends Control

	var title := ""
	var sprites: Array = []   # [Texture2D, feet: Vector2, cell_px: float, lift: float, shadow: bool]
	var labels: Array = []    # [texto, pos, tamaño, color, contorno]
	var calls: Array[Callable] = []  # Dibujos extra (mascotas 2D para comparar).
	var floor_y := -1.0
	var shadow_tex: Texture2D

	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), UiTheme.SKY_BOTTOM)
		if floor_y > 0.0:
			draw_rect(Rect2(0, floor_y, size.x, size.y - floor_y), UiTheme.FLOOR)
		UiTheme.draw_text(self, title, Vector2(size.x / 2.0, 60), 56, UiTheme.PAPER, 10)
		for l in labels:
			UiTheme.draw_text(self, l[0], l[1], l[2], l[3], l[4])
		for c in calls:
			c.call(self)
		for s in sprites:
			var tex: Texture2D = s[0]
			var feet: Vector2 = s[1]
			var cell: float = s[2]
			var lift: float = s[3]
			if s[4]:  # Sombra difusa en el piso (se achica si está en el aire), como en 2D.
				var k := clampf(1.0 - lift / (80.0 * cell / 144.0), 0.3, 1.0)
				var sh := Vector2(86.0, 17.0) * cell / 144.0 * k
				draw_texture_rect(shadow_tex, Rect2(feet - sh / 2.0 + Vector2(0, cell * 0.004), sh), false,
					PlayerAvatar.SHADOW)
			if tex:
				draw_texture(tex, feet - Mascot3DBaker.feet_offset(cell) - Vector2(0, lift))


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var out := "res://docs/img/mascotas_3d.png"
	var mode := "sheet"
	var all_dir := ""
	var out_width := OUT_WIDTH
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			out = arg.trim_prefix("--out=")
		elif arg == "--styles":
			mode = "styles"
		elif arg == "--closeup":
			mode = "closeup"
		elif arg == "--compare":
			mode = "compare"
		elif arg == "--expressions":
			mode = "expressions"
		elif arg.begins_with("--moods="):
			mode = "moods"
			_ref_slot = clampi(arg.trim_prefix("--moods=").to_int(), 0, Protocol.MASCOT_COLORS.size() - 1)
		elif arg.begins_with("--ref="):
			mode = "ref"
			_ref_slot = clampi(arg.trim_prefix("--ref=").to_int(), 0, 3)
		elif arg == "--standard":
			_shading = Mascot3D.Shading.STANDARD
		elif arg.begins_with("--all="):  # Todas las hojas en una carpeta (una sola corrida).
			all_dir = arg.trim_prefix("--all=")
		elif arg.begins_with("--width="):
			out_width = clampi(arg.trim_prefix("--width=").to_int(), 320, SIZE.x)
	if DisplayServer.get_name() == "headless":
		printerr("La hoja 3D necesita pantalla: correla con xvfb-run (ver el comentario del script).")
		quit(1)
		return
	root.size = SIZE
	if all_dir.is_empty():
		await _render(mode, out, out_width)
	else:
		var names := {"sheet": "mascotas_3d.png", "styles": "mascotas_3d_estilos.png", "closeup": "mascotas_3d_cerca.png",
			"compare": "mascotas_3d_comparacion.png", "expressions": "mascotas_3d_expresiones.png",
			"ref": "mascotas_3d_detalle.png"}
		_ref_slot = 1  # Detalle: el oso (2P), el recorte más limpio de la maqueta.
		for m: String in names:
			await _render(m, all_dir.path_join(names[m]), out_width)
	quit(0)


func _render(mode: String, out: String, out_width: int) -> void:
	var canvas := _Canvas.new()
	canvas.size = Vector2(SIZE)
	canvas.shadow_tex = _shadow_texture()
	root.add_child(canvas)
	var t0 := Time.get_ticks_msec()
	match mode:
		"styles":
			await _styles(canvas)
		"closeup":
			await _closeup(canvas)
		"compare":
			await _compare(canvas)
		"ref":
			await _ref(canvas, _ref_slot)
		"expressions":
			await _expressions(canvas)
		"moods":
			await _moods(canvas, _ref_slot)
		_:
			await _sheet(canvas)
	var bake_ms := Time.get_ticks_msec() - t0
	canvas.queue_redraw()
	for i in 3:
		await process_frame
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	if out_width < img.get_width():
		img.resize(out_width, int(img.get_height() * float(out_width) / img.get_width()), Image.INTERPOLATE_LANCZOS)
	img.save_png(out)
	print("Hoja 3D (%s): %s · horneado %d ms" % [mode, out, bake_ms])
	canvas.queue_free()
	await process_frame


func _sheet(c: _Canvas) -> void:
	c.title = "Mascotas 3D · hoja de personajes"
	var cell := Vector2((SIZE.x - 120.0) / COLUMNS.size(), (SIZE.y - 200.0) / 4.0)
	var u := 1.45
	var px := Mascot3DBaker.cell_for_u(u)
	var names: Array = []
	for col in COLUMNS:
		names.append(col[1])
	for i in COLUMNS.size():
		c.labels.append([COLUMNS[i][0], Vector2(60.0 + cell.x * (i + 0.5), 140), 26, UiTheme.INK, 0])
	for slot in 4:
		var tex := await Mascot3DBaker.bake(root, {"color": Protocol.player_color(slot), "style": slot}, names, px, _shading)
		for i in COLUMNS.size():
			var feet := Vector2(60.0 + cell.x * (i + 0.5), 170.0 + cell.y * (slot + 1) - 14.0)
			var lift := 18.0 if COLUMNS[i][1] == "jump" else 0.0
			c.sprites.append([tex.get(COLUMNS[i][1]), feet, float(px), lift, true])
		c.labels.append([UiTheme.player_tag(slot), Vector2(30, 170.0 + cell.y * (slot + 0.55)), 28, UiTheme.PAPER, 6])
	print("  horneado de 1P: ", Mascot3DBaker.last_report)


func _styles(c: _Canvas) -> void:
	c.title = "Mascotas 3D · estilos y colores"
	var styles := PlayerAvatar.STYLE_NAMES.size()
	var rows := 3
	var cell := Vector2((SIZE.x - 120.0) / styles, (SIZE.y - 200.0) / rows)
	var px := Mascot3DBaker.cell_for_u(1.75)
	for i in styles:
		c.labels.append([PlayerAvatar.STYLE_NAMES[i], Vector2(60.0 + cell.x * (i + 0.5), 140), 30, UiTheme.INK, 0])
	# Misma combinación de estilo × color × ánimo que character_sheet --styles.
	var moods := ["happy", "normal", "surprised"]
	for r in rows:
		for i in styles:
			var col: Color = PALETTE[(i + r * styles) % PALETTE.size()]
			if r == rows - 1 and i % 2 == 0:
				col = PALETTE[PALETTE.size() - 1 - (i / 2) % 2]  # Negro y grafito.
			var tex := await Mascot3DBaker.bake(root, {"color": col, "style": i}, [moods[r]], px, _shading)
			var feet := Vector2(60.0 + cell.x * (i + 0.5), 170.0 + cell.y * (r + 1) - 14.0)
			c.sprites.append([tex.get(moods[r]), feet, float(px), 0.0, true])


func _closeup(c: _Canvas) -> void:
	c.title = "Mascotas 3D · de cerca y chicas"
	var big := [[0, 0, "normal"], [1, 1, "happy"], [2, 2, "normal"], [3, 3, "surprised"], [PlayerAvatar.STYLE_ROBOT, 4, "normal"]]
	var px := Mascot3DBaker.cell_for_u(3.6)
	for i in big.size():
		var tex := await Mascot3DBaker.bake(root, {"color": PALETTE[big[i][1]], "style": big[i][0]}, [big[i][2]], px, _shading)
		c.sprites.append([tex.get(big[i][2]), Vector2(SIZE.x * (i + 0.5) / big.size(), 560), float(px), 0.0, true])
	c.floor_y = 640.0
	var styles := PlayerAvatar.STYLE_NAMES.size()
	for row in 2:
		var u := 0.6 if row == 0 else 0.8
		var spx := Mascot3DBaker.cell_for_u(u)
		for i in PALETTE.size():
			var pose := "walk1" if i % 2 == 0 else "look"
			var tex := await Mascot3DBaker.bake(root, {"color": PALETTE[i], "style": (i + row * 3) % styles}, [pose], spx, _shading)
			var feet := Vector2(SIZE.x * (i + 0.5) / PALETTE.size(), 780.0 + row * 210.0)
			c.sprites.append([tex.get(pose), feet, float(spx), 0.0, true])


## Maqueta (recortes de la hoja de referencia) vs. mascota 2D actual vs. 3D.
func _compare(c: _Canvas) -> void:
	c.title = "Maqueta · 2D actual · 3D en Godot"
	var ref := Image.load_from_file(ProjectSettings.globalize_path(REFERENCE))
	var ref_tex: Texture2D = ImageTexture.create_from_image(ref) if ref and not ref.is_empty() else null
	var poses := [["normal", PlayerAvatar.Mood.NORMAL, {}, 0], ["happy", PlayerAvatar.Mood.HAPPY, {"wave": true, "t": 0.3}, 3]]
	var u := 1.9
	var px := Mascot3DBaker.cell_for_u(u)
	var col_w := (SIZE.x - 160.0) / 8.0
	var rows_y := [390.0, 690.0, 1000.0]
	var row_names := ["Maqueta", "2D", "3D"]
	for r in 3:
		c.labels.append([row_names[r], Vector2(80, rows_y[r] - 110.0), 30, UiTheme.INK, 0])
	for slot in 4:
		var tex := await Mascot3DBaker.bake(root, {"color": Protocol.player_color(slot), "style": slot}, ["normal", "happy"], px, _shading)
		for k in 2:
			var i := slot * 2 + k
			var x := 160.0 + col_w * (i + 0.5)
			var pose: Array = poses[k]
			if ref_tex:
				# Celdas de la maqueta (1688×932): columnas a ~153 px desde x=92, filas a ~180 px desde y=160.
				var src := Rect2(92.0 + pose[3] * 153.4, 158.0 + slot * 181.0, 145.0, 170.0)
				var dst_h := 290.0
				var dst := Rect2(x - dst_h * 145.0 / 170.0 / 2.0, rows_y[0] - dst_h + 20.0, dst_h * 145.0 / 170.0, dst_h)
				c.calls.append(func(ci: CanvasItem) -> void: ci.draw_texture_rect_region(ref_tex, dst, src))
			var feet2 := Vector2(x, rows_y[1])
			var mood: int = pose[1]
			var anim: Dictionary = pose[2]
			c.calls.append(func(ci: CanvasItem) -> void:
				PlayerAvatar.draw_mascot(ci, feet2, u, Protocol.player_color(slot), slot, mood, 0.0, 0.0, false, anim))
			c.sprites.append([tex.get(pose[0]), Vector2(x, rows_y[2]), float(px), 0.0, true])


## Expresiones (todos los ánimos, en dos filas con estilos y colores
## distintos, blanco y negro incluidos) y animaciones en fases: los tres
## bailes, derrota y saludo. Mismo armado que character_sheet --expressions.
func _expressions(c: _Canvas) -> void:
	var M := PlayerAvatar.Mood
	c.title = "Mascotas 3D · expresiones y bailes"
	var moods := [["Normal", M.NORMAL], ["Feliz", M.HAPPY], ["Triste", M.SAD], ["Sorpresa", M.SURPRISED],
		["Enojada", M.ANGRY], ["Mareada", M.DIZZY], ["Dormida", M.SLEEPY], ["Ganadora", M.WINNER], ["Risa", M.LAUGHING]]
	var left := 210.0
	var cell := (SIZE.x - left - 30.0) / moods.size()
	for k in moods.size():
		c.labels.append([moods[k][0], Vector2(left + cell * (k + 0.5), 116), 26, UiTheme.INK, 0])
	var px := Mascot3DBaker.cell_for_u(1.0)
	var rows := [[0, 0], [4, 7]]  # Primer estilo y color de cada fila.
	for r in rows.size():
		c.labels.append(["Expresión", Vector2(100, 225.0 + r * 160.0), 24, UiTheme.PAPER, 6])
		for k in moods.size():
			var st: int = (rows[r][0] + k) % PlayerAvatar.STYLE_NAMES.size()
			var col: Color = PALETTE[(rows[r][1] + k * 3) % PALETTE.size()]
			var pose := {"name": "p", "mood": moods[k][1], "anim": {"t": 1.3 + k * 0.21}}
			var tex := await Mascot3DBaker.bake(root, {"color": col, "style": st}, [pose], px, _shading)
			c.sprites.append([tex.get("p"), Vector2(left + cell * (k + 0.5), 290.0 + r * 160.0), float(px), 0.0, true])
	# Animaciones en fases: una fila por baile + derrota y saludo.
	var phases := 8
	var pcell := (SIZE.x - left - 30.0) / phases
	var spx := Mascot3DBaker.cell_for_u(0.82)
	var dances := [
		["Saltitos", PlayerAvatar.STYLE_BUNNY, 6, PlayerAvatar.DANCE_HOPS, 0.5],
		["Giro", 1, 1, PlayerAvatar.DANCE_SPIN, 1.0],
		["Brazos arriba", 2, 2, PlayerAvatar.DANCE_ARMS, 1.0],
	]
	for r in dances.size():
		var y := 600.0 + r * 125.0
		c.labels.append([dances[r][0], Vector2(100, y - 40.0), 24, UiTheme.PAPER, 6])
		var poses: Array = []
		for k in phases:
			# La vuelta del giro ocupa la primera mitad de su ciclo.
			var span: float = dances[r][4] * (0.5 if r == 1 else 1.0)
			# Sin el salto horneado: se suma en 2D (como lo haría un juego) y la sombra se achica.
			poses.append({"name": "d%d" % k, "mood": M.WINNER if r == 1 else M.HAPPY,
				"anim": {"t": 10.0 + span * k / phases, "dance": 1.0, "dance_kind": dances[r][3], "lift": false}})
		var tex := await Mascot3DBaker.bake(root, {"color": PALETTE[dances[r][2]], "style": dances[r][1]}, poses, spx, _shading)
		for k in phases:
			var p: Dictionary = poses[k]
			var lift := Mascot3D.pose_lift(p.mood, p.anim, dances[r][1]) * spx / 144.0
			c.sprites.append([tex.get("d%d" % k), Vector2(left + pcell * (k + 0.5), y), float(spx), lift, true])
	var yd := 975.0
	c.labels.append(["Derrota · saludo", Vector2(100, yd - 40.0), 24, UiTheme.PAPER, 6])
	for k in phases:
		var anim := {"t": 20.0 + k * 0.09}
		var mood: int = M.SAD
		if k < 4:
			anim["defeat"] = k / 3.0
		else:
			anim["greet"] = 1.0
			mood = M.HAPPY
		var tex := await Mascot3DBaker.bake(root, {"color": PALETTE[k % 4 + 3 * int(k >= 4)],
			"style": (k + 3) % PlayerAvatar.STYLE_NAMES.size()}, [{"name": "p", "mood": mood, "anim": anim}], spx, _shading)
		c.sprites.append([tex.get("p"), Vector2(left + pcell * (k + 0.5), yd), float(spx), 0.0, true])


## Los 9 ánimos grandes (u = 2,1) de un color y estilo: para revisar caras y efectos de cerca.
func _moods(c: _Canvas, index: int) -> void:
	var names := ["Normal", "Feliz", "Triste", "Sorpresa", "Enojada", "Mareada", "Dormida", "Ganadora", "Risa"]
	var st := index % PlayerAvatar.STYLE_NAMES.size()
	c.title = "Ánimos · %s %s" % [Protocol.MASCOT_COLOR_NAMES[index], PlayerAvatar.STYLE_NAMES[st]]
	var px := Mascot3DBaker.cell_for_u(2.1)
	var poses: Array = []
	for m in names.size():
		poses.append({"name": names[m], "mood": m, "anim": {"t": 1.3 + m * 0.21}})
	var tex := await Mascot3DBaker.bake(root, {"color": PALETTE[index], "style": st}, poses, px, _shading)
	for m in names.size():
		var col := m % 5
		var row := m / 5
		var x := 200.0 + col * 380.0 + row * 190.0
		var feet := Vector2(x, 470.0 + row * 470.0)
		c.labels.append([names[m], feet + Vector2(0, 40), 28, UiTheme.INK, 0])
		c.sprites.append([tex.get(names[m]), feet, float(px), 0.0, true])


## Celda de la maqueta (1688×932): columna col (0 Normal … 9 Aterriza) y fila slot (1P–4P).
static func ref_cell(col: int, slot: int) -> Rect2:
	return Rect2(92.0 + col * 153.4, 158.0 + slot * 181.0, 145.0, 170.0)


## Revisión de detalle de una mascota: arriba, maqueta y 3D grandes y a la
## misma escala (Normal y Feliz); abajo, las 4 a tamaño de juego (celda de 116 px).
## En la maqueta, de la coronilla a la suela hay ~136 px de 170: la 3D se
## escala para medir lo mismo (9,6 unidades del mundo).
func _ref(c: _Canvas, slot: int) -> void:
	c.title = "Maqueta vs. 3D · %s" % UiTheme.player_tag(slot)
	var ref := Image.load_from_file(ProjectSettings.globalize_path(REFERENCE))
	var ref_tex: Texture2D = ImageTexture.create_from_image(ref)
	var k := 3.0                        # Escala de los recortes grandes.
	var feet_y := 120.0 + 157.0 * k     # Suela de la maqueta en el recorte (157 de 170).
	var px := int(round(136.0 * k * Mascot3DBaker.CELL_WORLD / 9.6))
	var tex := await Mascot3DBaker.bake(root, {"color": Protocol.player_color(slot), "style": slot}, ["normal", "happy"], px, _shading)
	var cols := [[0, "normal"], [3, "happy"]]
	for i in 2:
		var src := ref_cell(cols[i][0], slot)
		var x0 := 20.0 + i * 950.0
		var dst := Rect2(x0, 120.0, src.size.x * k, src.size.y * k)
		c.calls.append(func(ci: CanvasItem) -> void: ci.draw_texture_rect_region(ref_tex, dst, src))
		c.sprites.append([tex.get(cols[i][1]), Vector2(x0 + dst.size.x + 240.0, feet_y), float(px), 0.0, true])
	# Tamaño de juego: maqueta achicada a la misma altura que la 3D en una celda de 116 px.
	var small := 116
	var ks := (9.6 * small / Mascot3DBaker.CELL_WORLD) / 136.0
	for s in 4:
		var st := await Mascot3DBaker.bake(root, {"color": Protocol.player_color(s), "style": s}, ["normal", "happy"], small, _shading)
		for i in 2:
			var src := ref_cell(cols[i][0], s)
			var x := 60.0 + (s * 2 + i) * 230.0
			var dst := Rect2(x, 915.0 - 157.0 * ks, src.size.x * ks, src.size.y * ks)
			c.calls.append(func(ci: CanvasItem) -> void: ci.draw_texture_rect_region(ref_tex, dst, src))
			c.sprites.append([st.get(cols[i][1]), Vector2(x + dst.size.x + 50.0, 915.0), float(small), 0.0, true])


## Mancha redonda que se desvanece hacia el borde (sombra en el piso).
func _shadow_texture() -> Texture2D:
	var g := GradientTexture2D.new()
	g.width = 64
	g.height = 64
	g.fill = GradientTexture2D.FILL_RADIAL
	g.fill_from = Vector2(0.5, 0.5)
	g.fill_to = Vector2(1.0, 0.5)
	var grad := Gradient.new()
	grad.set_color(0, Color(1, 1, 1, 1))
	grad.set_color(1, Color(1, 1, 1, 0))
	g.gradient = grad
	return g
