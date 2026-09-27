extends SceneTree
## Genera las capturas de docs/img/ desde el propio proyecto: una TV real y
## controles reales conectados por WebSocket, recorriendo una competencia
## completa (lobby -> intro -> juego -> resumen de ronda -> podio).
##
##   xvfb-run -a -s "-screen 0 1920x1080x24" godot --path . -s res://tools/capture_screens.gd
##   … -- --out=/tmp/capturas/      (otra carpeta, para revisar sin pisar docs/)
##   … -- --width=1920              (ancho de las capturas; default 960, el de docs/img)
##   … -- --out=/tmp/estilos/pixel --style=pixel
##        (exploración de estilos: post-proceso sobre la TV y el celular; ver
##        docs/ESTILOS.md. Sin --style las capturas quedan como siempre.)
##   … -- --mascots-2d            (mascotas 2D por código en vez de las 3D
##                                  horneadas, para comparar; ADR 0012)
##
## Necesita una pantalla (real o virtual con xvfb): con --headless Godot no
## dibuja nada. También sirve como prueba de humo visual: si una pantalla
## rompe, falla acá antes que en la TV de alguien.

const PORT := 47995
const OUT_DIR := "res://docs/img/"
const OUT_WIDTH := 960
const PHONE := Vector2i(2340, 1080)  ## Celular apaisado típico (19.5:9).
const StyleLayer := preload("res://tools/styles/style_layer.gd")

## Segundos de juego antes de capturar (default 2,5): algunos juegos se ven
## mejor más avanzados (ej. el reloj ya corriendo o bloques cayendo).
const SHOT_DELAY := {"stop_clock": 5.0, "dodge": 6.0, "paint": 8.0, "sumo": 4.5, "karts": 7.0, "scroller": 8.0, "memory": 4.2, "pool": 5.0, "hurdles": 6.0}
## Juegos en los que los controles de prueba mueven el joystick en círculos
## mientras esperan la captura (ej. para que se vea el piso pintado).
const WANDER := ["paint", "sumo"]
## Apariencia que piden los controles de prueba al unirse (ver Protocol.parse_look).
const LOOKS := {
	"Pablo": {},
	"Sofi": {"color": 5, "style": 6},   # Rosa, conejo.
	"Tomi": {"color": 7, "style": 4},   # Blanco, robot.
}
## Nombre de la captura del celular según el control que muestra.
const CONTROL_SHOTS := {
	Protocol.LAYOUT_JOYSTICK: "ctrl_joy", Protocol.LAYOUT_ONE_BUTTON: "ctrl_button", Protocol.LAYOUT_SLIDER_H: "ctrl_slider",
	Protocol.LAYOUT_JOYSTICK_AB: "ctrl_joy_ab",  # Todavía sin juego: vista previa con tools/preview_joystick_ab.gd.
}

var host: HostMain
var _out_dir := OUT_DIR
var _out_width := OUT_WIDTH  ## `--width=1920`: resolución completa (para revisar detalle).
var _lobby_only := false  ## `--lobby-only`: corta tras el lobby (iterar diseño rápido).
var _style := ""  ## Post-proceso de estilo (--style=pixel|neon|paper|flat); vacío = el actual.
var _style_params := {}
var _clients: Array[ControllerClient] = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			_out_dir = arg.trim_prefix("--out=").trim_suffix("/") + "/"
			DirAccess.make_dir_recursive_absolute(_out_dir)
		elif arg.begins_with("--width="):
			_out_width = clampi(int(arg.trim_prefix("--width=")), 320, 3840)
		elif arg == "--lobby-only":
			_lobby_only = true
		elif arg.begins_with("--style="):
			_style = arg.trim_prefix("--style=")
		elif arg == "--mascots-2d":
			MascotAtlas.enabled = false  # Capturas con la mascota 2D (para comparar).
	_style_params = StyleLayer.params_from_args(OS.get_cmdline_user_args())
	if _style != "" and _out_dir == OUT_DIR:
		printerr("--style necesita --out=<carpeta>: las capturas con estilo no van a docs/img.")
		quit(1)
		return
	if _style != "" and StyleLayer.attach(root, _style, _style_params) == null:
		quit(1)
		return
	# Piezas 3D horneadas (ADR 0016) listas antes de la primera captura: la TV
	# las lee de la caché en disco al arrancar; acá, si no hay caché, se hornean.
	await Props3DBaker.ensure(root)
	# Presentación de la marca (sola, antes de la TV).
	var splash := SplashScreen.new()
	root.add_child(splash)
	await _seconds(0.8)
	await _shot(root, "splash")
	splash.queue_free()
	host = HostMain.new()
	host.server_port = PORT
	host.announce = false
	root.add_child(host)
	await _frames(5)
	host._lobby._stepper.set_value(4)
	# Cada uno con su apariencia (Pablo, la de su lugar): así los juegos
	# muestran estilos y colores elegidos, blanco incluido.
	for n in LOOKS:
		var c := ControllerClient.new()
		root.add_child(c)
		c.join("127.0.0.1", PORT, host.server.room_code, n, LOOKS[n])
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
	if _style != "":
		StyleLayer.attach(phone, _style, _style_params)
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
	# Selector de mascota: el celular pide negro + diablito (por la red, como
	# al tocar el selector, pero sin guardar la preferencia en este equipo).
	ctrl.client.send_look(9, PlayerAvatar.STYLE_HORNS)
	await _until(func() -> bool: return int(ctrl.client.player_info.get("color_index", -1)) == 9)
	_expect(ctrl._look_picker.visible and ctrl._look_picker.color_index == 9, "el celular muestra el selector con el color elegido")
	await _seconds(0.8)
	await _shot(phone, "ctrl_look")
	await _shot(root, "lobby_full")
	if _lobby_only:
		quit(0)
		return

	# Competencia con todos los juegos que admiten 4: se recorre sin importar
	# cuántos haya (un juego nuevo en el registry aparece solo en las capturas).
	_expect(host.start_tournament(host._lobby.selected_game_ids()), "arranca la competencia")
	await _settle()
	var round_index := 0
	while host.phase == Protocol.PHASE_PLAYING:
		var game_id := host.tournament.current_game_id
		# Antes de cada juego, la intro "¿Cómo se juega?" (se captura la primera).
		_expect(host._intro.visible and host._game == null, "se muestra la intro de %s" % game_id)
		if round_index == 0:
			# Dos tocan su celular: sus tarjetas muestran "¡Listo!" (ready check).
			_clients[0].send_input(Vector2.ZERO, Protocol.BTN_A)
			_clients[2].send_input(Vector2.ZERO, Protocol.BTN_A)
			await _seconds(1.2)
			await _shot(root, "game_intro")
		# Como en la TV: las mascotas del juego se hornean mientras se lee la intro.
		await _until(func() -> bool: return MascotAtlas.is_idle(), 30000)
		host.skip_intro()
		await _settle()
		_expect(host._game != null, "arranca %s después de la intro" % game_id)
		if game_id in WANDER:
			await _wander(SHOT_DELAY.get(game_id, 2.5))
		else:
			await _seconds(SHOT_DELAY.get(game_id, 2.5))
		await _shot(root, game_id)
		if round_index == 0:
			await _shot(phone, CONTROL_SHOTS.get(MiniGameRegistry.info(game_id).layout, "ctrl_play"))
		# El juego puede haber terminado solo (ej. en Empujones se tiran entre ellos).
		if is_instance_valid(host._game):
			host._game.finish(_fake_result(round_index))
		await _seconds(4.5 if round_index == 0 else 1.0)
		_expect(host._summary.visible, "se muestra el resumen de la ronda %d" % (round_index + 1))
		if round_index == 0:
			await _shot(root, "round_summary")
			# El celular muestra su propio resultado mientras la TV muestra el resumen.
			_expect(ctrl._standing_panel.visible, "el celular muestra su resultado de la ronda")
			await _shot(phone, "ctrl_standing")
		host._summary._on_continue()
		round_index += 1
		await _settle()
	await _seconds(2.0)
	_expect(host._final.visible, "se muestra el podio")
	await _shot(root, "final")

	# Ping Pong necesita exactamente 2: se juega en otra competencia.
	host._back_to_lobby()
	_clients[2].leave()
	ctrl._on_leave_pressed()
	await _until(func() -> bool: return host.server.get_players().size() == 2)
	host._lobby._stepper.set_value(2)
	_expect(host.start_tournament(["pingpong"] as Array[String]), "arranca Ping Pong con 2")
	await _settle()
	await _until(func() -> bool: return MascotAtlas.is_idle(), 30000)
	host.skip_intro()
	await _settle()
	await _seconds(2.0)
	await _shot(root, "pingpong")

	# Aviso de desconexión (con el marcador de Ping Pong detrás): Sofi pierde
	# la conexión; su control se congela hasta la captura para que no vuelva antes.
	_clients[1]._ws.close()
	await _until(func() -> bool: return host._toasts.active_count() > 0 and host._toasts.texts()[0].contains("desconectó"))
	_clients[1].process_mode = Node.PROCESS_MODE_DISABLED
	await _seconds(0.5)
	_expect(host._toasts.active_count() > 0, "la TV avisa que Sofi se desconectó")
	await _shot(root, "toast")
	_clients[1].process_mode = Node.PROCESS_MODE_INHERIT
	# Menú de pausa y la confirmación de "Salir de la competencia".
	var cancel := InputEventAction.new()
	cancel.action = "ui_cancel"
	cancel.pressed = true
	host._unhandled_input(cancel)
	await _seconds(0.5)
	_expect(host._pause.visible, "Atrás abre la pausa")
	await _shot(root, "pause")
	host._pause._quit.pressed.emit()
	await _seconds(0.5)
	_expect(host._pause.is_confirming(), "Salir pide confirmación")
	await _shot(root, "pause_confirm")
	# Cierra la confirmación y la pausa; Sofi vuelve a conectarse sola.
	host._pause._confirm_no.pressed.emit()
	host._unhandled_input(cancel)
	await _until(func() -> bool:
		return host.server.get_players().all(func(p: Dictionary) -> bool: return bool(p.get("connected", true))))
	_expect(not host._pause.visible, "Atrás cierra la pausa")

	# Bots (ADR 0010): Pablo solo + 3 bots (fácil, normal, difícil). Lobby
	# con bots, su menú, un juego con la placa BOT en el marcador y el resumen.
	host._back_to_lobby()
	_clients[1].leave()
	await _until(func() -> bool: return host.server.get_players().size() == 1)
	host._lobby._stepper.set_value(4)
	for d in [Bot.Difficulty.EASY, Bot.Difficulty.NORMAL, Bot.Difficulty.HARD]:
		_expect(host.add_bot(d), "se suma un bot %s" % Bot.difficulty_name(d))
	host._lobby._seats[3].grab_focus()
	await _seconds(1.0)
	await _shot(root, "lobby_bots")
	host._lobby.open_bot_menu(3)
	await _seconds(0.6)
	await _shot(root, "lobby_bot_menu")
	host._lobby._bot_menu._cancel.pressed.emit()
	_expect(host.start_tournament(["arena", "tap_race"] as Array[String]), "arranca la competencia con bots")
	await _settle()
	await _until(func() -> bool: return MascotAtlas.is_idle(), 30000)
	host.skip_intro()
	await _settle()
	await _seconds(4.0)
	await _shot(root, "arena_bots")
	if is_instance_valid(host._game):
		host._game.finish(_fake_result(1))
	await _seconds(4.5)
	_expect(host._summary.visible, "resumen con bots")
	await _shot(root, "round_summary_bots")

	# Selector TV / celular (app/boot.gd, sin argumentos).
	host.queue_free()
	await _frames(2)
	var boot: Control = load("res://app/boot.gd").new()
	root.add_child(boot)
	await _seconds(1.0)
	await _shot(root, "selector")

	print("Capturas guardadas en ", ProjectSettings.globalize_path(_out_dir))
	quit(0)


## Resultado inventado pero variado: el ganador rota en cada ronda para que
## el podio muestre puntos distintos.
func _fake_result(round_index: int) -> Dictionary:
	var scores := {}
	var ids: Array = []
	for p in host.server.get_players():
		ids.append(p.id)
	for i in ids.size():
		scores[ids[i]] = 10 + ((i + round_index) % ids.size()) * 7
	var best := -1
	var winner := 0
	for pid: int in scores:
		if scores[pid] > best:
			best = scores[pid]
			winner = pid
	return {"winners": [winner], "scores": scores, "summary": ""}


## Si algo del recorrido no pasa, sale con error (útil en CI).
func _expect(cond: bool, what: String) -> void:
	if not cond:
		printerr("FALLA: ", what)
		quit(1)


func _shot(vp: Viewport, name: String) -> void:
	# Mascotas 3D (ADR 0012): si todavía se están horneando poses que se
	# pidieron recién, espera un poco (acá el render es por software).
	if not MascotAtlas.is_idle():
		await _until(func() -> bool: return MascotAtlas.is_idle(), 2500)
		await _frames(3)
	await RenderingServer.frame_post_draw
	var img := vp.get_texture().get_image()
	if img.get_width() != _out_width:
		img.resize(_out_width, int(img.get_height() * float(_out_width) / img.get_width()), Image.INTERPOLATE_LANCZOS)
	img.save_png(_out_dir + name + ".png")
	print("  ", name, ".png")


## Los controles de prueba mueven el joystick en círculos distintos (por
## la red, como un celular) durante `s` segundos y después lo sueltan.
func _wander(s: float) -> void:
	var start := Time.get_ticks_msec()
	while Time.get_ticks_msec() - start < s * 1000.0:
		var t := (Time.get_ticks_msec() - start) / 1000.0
		for i in _clients.size():
			_clients[i].send_input(Vector2.from_angle(t * (1.1 + i * 0.35) + i * 2.1), 0)
		await _seconds(0.05)
	for c in _clients:
		c.send_input(Vector2.ZERO, 0)


## Espera a que termine el barrido entre pantallas (Transition).
func _settle() -> void:
	await _until(func() -> bool: return not host._transition.is_running(), 2000)
	await _frames(2)


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _seconds(s: float) -> void:
	await create_timer(s).timeout


func _until(cond: Callable, timeout_ms: int = 5000) -> void:
	var start := Time.get_ticks_msec()
	while not cond.call() and Time.get_ticks_msec() - start < timeout_ms:
		await process_frame
