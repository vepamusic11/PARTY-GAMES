extends SceneTree
## Genera las capturas de docs/img/ desde el propio proyecto: una TV real y
## controles reales conectados por WebSocket, recorriendo una competencia
## completa (lobby -> juego -> resumen de ronda -> podio).
##
##   xvfb-run -a -s "-screen 0 1920x1080x24" godot --path . -s res://tools/capture_screens.gd
##   … -- --out=/tmp/capturas/      (otra carpeta, para revisar sin pisar docs/)
##
## Necesita una pantalla (real o virtual con xvfb): con --headless Godot no
## dibuja nada. También sirve como prueba de humo visual: si una pantalla
## rompe, falla acá antes que en la TV de alguien.

const PORT := 47995
const OUT_DIR := "res://docs/img/"
const OUT_WIDTH := 960
const PHONE := Vector2i(2340, 1080)  ## Celular apaisado típico (19.5:9).

var host: HostMain
var _out_dir := OUT_DIR
var _clients: Array[ControllerClient] = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			_out_dir = arg.trim_prefix("--out=").trim_suffix("/") + "/"
			DirAccess.make_dir_recursive_absolute(_out_dir)
	host = HostMain.new()
	host.server_port = PORT
	host.announce = false
	root.add_child(host)
	await _frames(5)
	host._lobby._stepper.set_value(4)
	for n in ["Pablo", "Sofi", "Tomi"]:
		var c := ControllerClient.new()
		root.add_child(c)
		c.join("127.0.0.1", PORT, host.server.room_code, n)
		_clients.append(c)
	await _until(func() -> bool: return host.server.get_players().size() == 3)
	_expect(host.server.get_players().size() == 3, "se unen 3 controles")
	await _seconds(1.0)
	await _shot(root, "lobby")

	# Cuarto jugador desde la app real del celular (en un viewport aparte).
	var phone := SubViewport.new()
	phone.size = PHONE
	phone.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(phone)
	var ctrl := ControllerMain.new()
	phone.add_child(ctrl)
	await _frames(5)
	ctrl._selected_host = {"ip": "127.0.0.1", "port": PORT}  # Como si la eligiera de la lista.
	ctrl._ip_edit.text = "127.0.0.1"
	ctrl._name_edit.text = "Juli"
	ctrl._code_edit.text = host.server.room_code
	await _seconds(0.5)
	await _shot(phone, "ctrl_join")
	ctrl._on_join_pressed()
	await _until(func() -> bool: return host.server.get_players().size() == 4)
	_expect(host.server.get_players().size() == 4, "el celular se une desde su pantalla")
	await _seconds(0.8)
	await _shot(phone, "ctrl_wait")
	await _shot(root, "lobby_full")

	_expect(host.start_tournament(host._lobby.selected_game_ids()), "arranca la competencia")
	await _seconds(2.5)
	await _shot(root, "arena")
	await _shot(phone, "ctrl_joy")
	host._game.finish({"winners": [1], "scores": {1: 12, 2: 9, 3: 9, 4: 4}, "summary": ""})
	await _seconds(4.5)
	_expect(host._summary.visible, "se muestra el resumen de ronda")
	await _shot(root, "round_summary")
	# El celular muestra su propio resultado mientras la TV muestra el resumen.
	_expect(ctrl._standing_panel.visible, "el celular muestra su resultado de la ronda")
	await _shot(phone, "ctrl_standing")

	host._summary._on_continue()  # Ping Pong se saltea (es para 2): sigue Carrera.
	await _seconds(3.0)
	await _shot(root, "tap_race")
	host._game.finish({"winners": [3], "scores": {1: 31, 2: 36, 3: 40, 4: 22}, "summary": ""})
	await _seconds(1.0)
	host._summary._on_continue()
	await _seconds(2.5)
	_expect(host._final.visible, "se muestra el podio")
	await _shot(root, "final")

	# Ping Pong necesita exactamente 2: se juega en otra competencia.
	host._back_to_lobby()
	_clients[2].leave()
	ctrl._on_leave_pressed()
	await _until(func() -> bool: return host.server.get_players().size() == 2)
	host._lobby._stepper.set_value(2)
	_expect(host.start_tournament(["pingpong"] as Array[String]), "arranca Ping Pong con 2")
	await _seconds(2.0)
	await _shot(root, "pingpong")

	print("Capturas guardadas en ", ProjectSettings.globalize_path(_out_dir))
	quit(0)


## Si algo del recorrido no pasa, sale con error (útil en CI).
func _expect(cond: bool, what: String) -> void:
	if not cond:
		printerr("FALLA: ", what)
		quit(1)


func _shot(vp: Viewport, name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := vp.get_texture().get_image()
	img.resize(OUT_WIDTH, int(img.get_height() * float(OUT_WIDTH) / img.get_width()), Image.INTERPOLATE_LANCZOS)
	img.save_png(_out_dir + name + ".png")
	print("  ", name, ".png")


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _seconds(s: float) -> void:
	await create_timer(s).timeout


func _until(cond: Callable, timeout_ms: int = 5000) -> void:
	var start := Time.get_ticks_msec()
	while not cond.call() and Time.get_ticks_msec() - start < timeout_ms:
		await process_frame
