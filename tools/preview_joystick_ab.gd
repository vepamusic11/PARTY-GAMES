extends SceneTree
## Vista previa del layout "joystick_ab" (joystick + A y B, ver ADR 0014).
## Todavía no hay un juego que lo use, así que tools/capture_screens.gd no
## pasa por él: este script arma la app real del celular (ControllerMain)
## como si la TV le hubiera pedido ese control y guarda capturas.
##
##   xvfb-run -a -s "-screen 0 1920x1080x24" godot --path . --rendering-driver opengl3 \
##     --audio-driver Dummy -s res://tools/preview_joystick_ab.gd
##       -> docs/img/ctrl_joy_ab.png (960 px de ancho, como el resto de docs/img)
##   … -- --out=/tmp/joy_ab/ --width=2340
##       -> además ctrl_joy_ab_play.png (dedos apoyados: joystick movido, A
##          apretado), ctrl_joy_ab_zurdo.png, ctrl_joy_ab_16x9.png (celular
##          1920×1080) y tv_intro_joy_ab.png (la intro
##          "¿Cómo se juega?" de la TV con el ícono del control, 1920×1080).
##
## Cuando un juego use joystick_ab, capture_screens.gd ya lo captura como
## ctrl_joy_ab (CONTROL_SHOTS) y este script deja de hacer falta.

const OUT_DIR := "res://docs/img/"
const OUT_WIDTH := 960
const PHONE := Vector2i(2340, 1080)

var _out_dir := OUT_DIR
var _out_width := OUT_WIDTH
var _extra := false  ## Con --out: también las capturas de revisión.


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			_out_dir = arg.trim_prefix("--out=").trim_suffix("/") + "/"
			DirAccess.make_dir_recursive_absolute(_out_dir)
			_extra = true
		elif arg.begins_with("--width="):
			_out_width = clampi(int(arg.trim_prefix("--width=")), 320, 3840)

	var phone := SubViewport.new()
	phone.size = PHONE
	phone.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(phone)
	var ctrl := ControllerMain.new()
	phone.add_child(ctrl)
	await _frames(5)
	# Como si la TV lo hubiera aceptado (Juli, 2P, rosa con conejo).
	ctrl.client.player_info = {
		"id": 2, "name": "Juli", "color": Protocol.mascot_color(5), "color_index": 5, "style": 6, "taken": [] as Array[int],
	}
	ctrl._on_joined(ctrl.client.player_info)
	ctrl._on_phase_changed(Protocol.PHASE_PLAYING)
	ctrl._on_layout_changed(Protocol.LAYOUT_JOYSTICK_AB, {"a": "Patear", "b": "Saltar"})
	await _seconds(0.8)
	var pad := ctrl._active_layout as JoystickAB
	if pad == null:
		printerr("El celular no armó el JoystickAB.")
		quit(1)
		return
	print("  layout ", pad.size, " · A ", pad.button_radius(Protocol.BTN_A) * 2.0, " px · B ",
		pad.button_radius(Protocol.BTN_B) * 2.0, " px")
	await _shot(phone, "ctrl_joy_ab")
	if not _extra:
		quit(0)
		return

	# Dos dedos: el joystick hacia arriba a la derecha y A apretado.
	var stick := pad.stick_rect().get_center() + Vector2(-60, 40)
	pad._gui_input(_touch(0, stick, true))
	pad._gui_input(_drag(0, stick + Vector2(90, -80)))
	pad._gui_input(_touch(1, pad.button_center(Protocol.BTN_A), true))
	await _seconds(0.1)
	print("  jugando: axis ", pad.value, " btn ", pad.buttons)
	await _shot(phone, "ctrl_joy_ab_play")
	pad.release_all()

	pad.left_handed = true
	await _seconds(0.4)
	await _shot(phone, "ctrl_joy_ab_zurdo")
	# Celular 16:9 (más angosto): los botones tienen que seguir entrando.
	pad.left_handed = false
	phone.size = Vector2i(1920, 1080)
	await _seconds(0.4)
	var keep_width := _out_width
	_out_width = 1920
	await _shot(phone, "ctrl_joy_ab_16x9")
	_out_width = keep_width
	phone.queue_free()

	# TV: la intro "¿Cómo se juega?" de un juego que pidiera este control.
	var intro := GameIntroScreen.new()
	intro.theme = UiTheme.build()  # En la app lo hereda de HostMain.
	root.add_child(intro)
	await _frames(2)
	var players: Array[Dictionary] = []
	for i in 2:
		players.append({"id": i + 1, "slot": i, "name": ["Pablo", "Juli"][i], "color": Protocol.player_color(i), "connected": true})
	intro.show_intro({"id": "vista_previa", "title": "Fútbol de mascotas", "description": "Movete con el joystick, A patea y B salta.",
		"layout": Protocol.LAYOUT_JOYSTICK_AB, "accent": UiTheme.ACCENT}, 1, 3, players)
	await _seconds(0.8)
	var keep := _out_width
	_out_width = 1920
	await _shot(root, "tv_intro_joy_ab")
	_out_width = keep
	quit(0)


func _touch(index: int, pos: Vector2, pressed: bool) -> InputEventScreenTouch:
	var t := InputEventScreenTouch.new()
	t.index = index
	t.position = pos
	t.pressed = pressed
	return t


func _drag(index: int, pos: Vector2) -> InputEventScreenDrag:
	var d := InputEventScreenDrag.new()
	d.index = index
	d.position = pos
	return d


func _shot(vp: Viewport, shot_name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := vp.get_texture().get_image()
	if img.get_width() != _out_width:
		img.resize(_out_width, int(img.get_height() * float(_out_width) / img.get_width()), Image.INTERPOLATE_LANCZOS)
	img.save_png(_out_dir + shot_name + ".png")
	print("  ", shot_name, ".png")


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _seconds(s: float) -> void:
	await create_timer(s).timeout
