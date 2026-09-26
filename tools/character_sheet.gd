extends SceneTree
## Hoja de personajes (*model sheet*): las 4 mascotas en todos sus ánimos y
## en fases de caminata, salto y aplastado, en una sola imagen. Sirve para
## revisar cambios de personaje o animación de un vistazo.
##
##   xvfb-run -a -s "-screen 0 1920x1080x24" godot --path . --rendering-driver opengl3 \
##     -s res://tools/character_sheet.gd -- --out=docs/img/mascotas.png

const SIZE := Vector2i(1920, 1080)
const OUT_WIDTH := 1280


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
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			out = arg.trim_prefix("--out=")
	root.size = SIZE
	var sheet := _Sheet.new()
	sheet.size = Vector2(SIZE)
	root.add_child(sheet)
	for i in 3:
		await process_frame
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	img.resize(OUT_WIDTH, int(img.get_height() * float(OUT_WIDTH) / img.get_width()), Image.INTERPOLATE_LANCZOS)
	img.save_png(out)
	print("Hoja de personajes: ", out)
	quit(0)
