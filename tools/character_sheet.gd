extends SceneTree
## Hoja de personajes (*model sheet*): las 4 mascotas en todos sus ánimos y
## en fases de caminata, salto y aplastado, en una sola imagen. Sirve para
## revisar cambios de personaje o animación de un vistazo.
##
##   xvfb-run -a -s "-screen 0 1920x1080x24" godot --path . --rendering-driver opengl3 \
##     -s res://tools/character_sheet.gd -- --out=docs/img/mascotas.png
##
## `--width=1920` guarda la imagen sin achicar (para mirar detalles).
##
## Con `--styles` dibuja la otra hoja: todos los estilos (robot, conejo…) en
## una paleta amplia de colores, negro incluido, para revisar contraste.
## Con `--closeup`, mascotas grandes (como en el lobby y el podio) arriba y
## chicas (como en los juegos) abajo: sirve para revisar el sombreado de
## cerca y que a ~60 px se sigan leyendo.
## Con `--expressions`, todas las expresiones (Mood) y, en fases, los tres
## bailes, la derrota y el saludo (docs/img/mascotas_expresiones.png).

const SIZE := Vector2i(1920, 1080)
const OUT_WIDTH := 1280


## Paleta que se elige desde el celular (negro y blanco son los casos
## difíciles de contraste). Ver Protocol.MASCOT_COLORS y ADR 0007.
const PALETTE: Array[Color] = Protocol.MASCOT_COLORS


class _Styles:
	extends Control

	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), UiTheme.SKY_BOTTOM)
		UiTheme.draw_text(self, "Mascotas · estilos y colores", Vector2(size.x / 2.0, 60), 56, UiTheme.PAPER, 10)
		var styles := PlayerAvatar.STYLE_NAMES.size()
		var rows := 3
		var cell := Vector2((size.x - 120.0) / styles, (size.y - 200.0) / rows)
		for c in styles:
			UiTheme.draw_text(self, PlayerAvatar.STYLE_NAMES[c], Vector2(60.0 + cell.x * (c + 0.5), 140), 30, UiTheme.INK)
		# Cada fila combina estilos con colores distintos: así aparecen los 10
		# colores y cada estilo se ve con uno claro, uno medio y uno oscuro.
		var moods := [PlayerAvatar.Mood.HAPPY, PlayerAvatar.Mood.NORMAL, PlayerAvatar.Mood.SURPRISED]
		for r in rows:
			for c in styles:
				var col: Color = PALETTE[(c + r * styles) % PALETTE.size()]
				if r == rows - 1 and c % 2 == 0:
					col = PALETTE[PALETTE.size() - 1 - (c / 2) % 2]  # Negro y grafito.
				var feet := Vector2(60.0 + cell.x * (c + 0.5), 170.0 + cell.y * (r + 1) - 14.0)
				PlayerAvatar.draw_mascot(self, feet, 1.75, col, c, moods[r], 0.0, 0.0, false, {"t": 1.0 + c * 0.4})


class _Closeup:
	extends Control

	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), UiTheme.SKY_BOTTOM)
		UiTheme.draw_text(self, "Mascotas · de cerca y chicas", Vector2(size.x / 2.0, 60), 56, UiTheme.PAPER, 10)
		# Grandes (~250 px de alto en la hoja final, como en el lobby).
		var big := [[0, 0, PlayerAvatar.Mood.NORMAL], [1, 1, PlayerAvatar.Mood.HAPPY], [2, 2, PlayerAvatar.Mood.NORMAL],
			[3, 3, PlayerAvatar.Mood.SURPRISED], [PlayerAvatar.STYLE_ROBOT, 4, PlayerAvatar.Mood.NORMAL]]
		for i in big.size():
			var feet := Vector2(size.x * (i + 0.5) / big.size(), 560)
			PlayerAvatar.draw_mascot(self, feet, 3.6, PALETTE[big[i][1]], big[i][0], big[i][2], 0.0, 0.0, false,
				{"t": 1.0, "wave": big[i][2] == PlayerAvatar.Mood.HAPPY})
		# Chicas, al tamaño de los juegos (u = 0,6 y 0,8), sobre el piso claro.
		draw_rect(Rect2(0, 640, size.x, size.y - 640), UiTheme.FLOOR)
		var styles := PlayerAvatar.STYLE_NAMES.size()
		for row in 2:
			var u := 0.6 if row == 0 else 0.8
			for i in PALETTE.size():
				var feet := Vector2(size.x * (i + 0.5) / PALETTE.size(), 780.0 + row * 210.0)
				PlayerAvatar.draw_mascot(self, feet, u, PALETTE[i], (i + row * 3) % styles, PlayerAvatar.Mood.NORMAL,
					0.0, 0.0, false, {"t": 1.0, "walk": 0.25 if i % 2 == 0 else -1.0, "look": Vector2(1, 0)})


## Expresiones (todos los ánimos, en dos filas con estilos y colores
## distintos, blanco y negro incluidos) y animaciones del nodo en fases:
## los tres bailes, derrota y saludo.
class _Expressions:
	extends Control

	const MOODS := [
		["Normal", PlayerAvatar.Mood.NORMAL], ["Feliz", PlayerAvatar.Mood.HAPPY], ["Triste", PlayerAvatar.Mood.SAD],
		["Sorpresa", PlayerAvatar.Mood.SURPRISED], ["Enojada", PlayerAvatar.Mood.ANGRY],
		["Mareada", PlayerAvatar.Mood.DIZZY], ["Dormida", PlayerAvatar.Mood.SLEEPY],
		["Ganadora", PlayerAvatar.Mood.WINNER], ["Risa", PlayerAvatar.Mood.LAUGHING],
	]
	const PHASES := 8

	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), UiTheme.SKY_BOTTOM)
		UiTheme.draw_text(self, "Mascotas · expresiones y bailes", Vector2(size.x / 2.0, 52), 50, UiTheme.PAPER, 10)
		var left := 210.0
		var cell := (size.x - left - 30.0) / MOODS.size()
		for c in MOODS.size():
			UiTheme.draw_text(self, MOODS[c][0], Vector2(left + cell * (c + 0.5), 118), 26, UiTheme.INK)
		var rows := [[0, 0], [4, 7]]  # Primer estilo y color de cada fila.
		for r in rows.size():
			UiTheme.draw_text(self, "Expresión", Vector2(100, 250.0 + r * 172.0), 24, UiTheme.PAPER, 6)
			for c in MOODS.size():
				var st: int = (rows[r][0] + c) % PlayerAvatar.STYLE_NAMES.size()
				var col: Color = PALETTE[(rows[r][1] + c * 3) % PALETTE.size()]
				var feet := Vector2(left + cell * (c + 0.5), 305.0 + r * 172.0)
				PlayerAvatar.draw_mascot(self, feet, 1.12, col, st, MOODS[c][1], 0.0, 0.0, false, {"t": 1.3 + c * 0.21})
		# Animaciones en fases: una fila por baile + derrota y saludo.
		var pcell := (size.x - left - 30.0) / PHASES
		var dances := [
			["Saltitos", PlayerAvatar.STYLE_BUNNY, 6, PlayerAvatar.DANCE_HOPS, 0.5],
			["Giro", 1, 1, PlayerAvatar.DANCE_SPIN, 1.0],
			["Brazos arriba", 2, 2, PlayerAvatar.DANCE_ARMS, 1.0],
		]
		for r in dances.size():
			var y := 640.0 + r * 140.0
			UiTheme.draw_text(self, dances[r][0], Vector2(100, y - 45.0), 24, UiTheme.PAPER, 6)
			for k in PHASES:
				# La vuelta del giro ocupa la primera mitad de su ciclo.
				var span: float = dances[r][4] * (0.5 if r == 1 else 1.0)
				var t := 10.0 + span * k / PHASES
				PlayerAvatar.draw_mascot(self, Vector2(left + pcell * (k + 0.5), y), 0.95, PALETTE[dances[r][2]],
					dances[r][1], PlayerAvatar.Mood.WINNER if r == 1 else PlayerAvatar.Mood.HAPPY, 0.0, 0.0, false,
					{"t": t, "dance": 1.0, "dance_kind": dances[r][3]})
		var yd := 1060.0
		UiTheme.draw_text(self, "Derrota · saludo", Vector2(100, yd - 45.0), 24, UiTheme.PAPER, 6)
		for k in PHASES:
			var anim := {"t": 20.0 + k * 0.09}
			var mood := PlayerAvatar.Mood.SAD
			if k < 4:
				anim["defeat"] = k / 3.0
			else:
				anim["greet"] = 1.0
				mood = PlayerAvatar.Mood.HAPPY
			PlayerAvatar.draw_mascot(self, Vector2(left + pcell * (k + 0.5), yd), 0.95, PALETTE[k % 4 + 3 * int(k >= 4)],
				(k + 3) % PlayerAvatar.STYLE_NAMES.size(), mood, 0.0, 0.0, false, anim)


class _Sheet:
	extends Control

	const COLUMNS := [
		["Normal", PlayerAvatar.Mood.NORMAL, {}],
		["Parpadeo", PlayerAvatar.Mood.NORMAL, {"blink": true}],
		["Mira", PlayerAvatar.Mood.NORMAL, {"look": Vector2(1, -0.4), "t": 1.0}],
		["Feliz", PlayerAvatar.Mood.HAPPY, {"wave": true, "t": 0.3}],
		["Triste", PlayerAvatar.Mood.SAD, {"t": 0.4}],
		["Sorpresa", PlayerAvatar.Mood.SURPRISED, {}],
		["Paso 1", PlayerAvatar.Mood.NORMAL, {"walk": 0.25, "look": Vector2(1, 0), "t": 1.0}],
		["Paso 2", PlayerAvatar.Mood.NORMAL, {"walk": 0.75, "look": Vector2(1, 0), "t": 1.0}],
		["Salto", PlayerAvatar.Mood.HAPPY, {"squash": -0.22, "wave": true}],
		["Aterriza", PlayerAvatar.Mood.NORMAL, {"squash": 0.3, "t": 1.0}],
	]

	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), UiTheme.SKY_BOTTOM)
		UiTheme.draw_text(self, "Mascotas · hoja de personajes", Vector2(size.x / 2.0, 60), 56, UiTheme.PAPER, 10)
		var cell := Vector2((size.x - 120.0) / COLUMNS.size(), (size.y - 200.0) / 4.0)
		for c in COLUMNS.size():
			var x := 60.0 + cell.x * (c + 0.5)
			UiTheme.draw_text(self, COLUMNS[c][0], Vector2(x, 140), 26, UiTheme.INK)
		for slot in 4:
			for c in COLUMNS.size():
				var col: Array = COLUMNS[c]
				var feet := Vector2(60.0 + cell.x * (c + 0.5), 170.0 + cell.y * (slot + 1) - 14.0)
				var anim: Dictionary = (col[2] as Dictionary).duplicate()
				if anim.has("blink"):  # Cada lugar parpadea en otro momento (ver draw_mascot).
					anim["t"] = fposmod(-slot * 1.37, 3.3) + 0.05
				var lift := 18.0 if col[0] == "Salto" else 0.0
				PlayerAvatar.draw_mascot(self, feet, 1.45, Protocol.player_color(slot), slot, col[1], 0.0, lift, false, anim)
			UiTheme.draw_text(self, UiTheme.player_tag(slot), Vector2(30, 170.0 + cell.y * (slot + 0.55)), 28, UiTheme.PAPER, 6)


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var out := "res://docs/img/mascotas.png"
	var sheet: Control = null
	var out_width := OUT_WIDTH
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			out = arg.trim_prefix("--out=")
		elif arg == "--styles":
			sheet = _Styles.new()
		elif arg == "--closeup":
			sheet = _Closeup.new()
		elif arg == "--expressions":
			sheet = _Expressions.new()
		elif arg.begins_with("--width="):  # Ancho de la imagen (1920 = sin achicar).
			out_width = clampi(arg.trim_prefix("--width=").to_int(), 320, SIZE.x)
	if sheet == null:
		sheet = _Sheet.new()
	root.size = SIZE
	sheet.size = Vector2(SIZE)
	root.add_child(sheet)
	for i in 3:
		await process_frame
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	if out_width < img.get_width():
		img.resize(out_width, int(img.get_height() * float(out_width) / img.get_width()), Image.INTERPOLATE_LANCZOS)
	img.save_png(out)
	print("Hoja de personajes: ", out)
	quit(0)
