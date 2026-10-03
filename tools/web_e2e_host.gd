extends SceneTree
## TV de prueba para el control web (ADR 0022): levanta HostMain con el
## servidor WebSocket y el HTTP en puertos fijos, imprime el código de sala
## y obedece órdenes de un archivo de texto (una por línea, se agregan al
## final) para que un script externo —tools/web_e2e.mjs con Playwright—
## maneje la competencia y saque capturas de la TV mientras los navegadores
## juegan.
##
##   xvfb-run -a -s "-screen 0 1920x1080x24" godot --path . --rendering-driver opengl3 --audio-driver Dummy \
##     -s res://tools/web_e2e_host.gd -- --cmd=/tmp/e2e/cmd.txt --out=/tmp/e2e --ws=47990 --http=47980
##
## Órdenes: `shot NOMBRE` (captura de la TV), `start id1,id2` (competencia),
## `skip` (saltar la intro), `finish` (terminar el juego actual con un
## resultado inventado), `continue` (seguir desde el resumen), `lobby`,
## `layout NOMBRE {json}` (manda ese control a los celulares, para probar
## cada layout sin un juego), `players` (imprime los jugadores) y `quit`.
## Cada línea que informa empieza con `E2E ` y va a la consola y a
## `events.log` en --out (la salida estándar de un proceso hijo puede quedar
## retenida en el buffer; el archivo se vacía línea por línea); las entradas
## que llegan se informan cuando cambian (`E2E input …`).

var host: HostMain
var _cmd_path := ""
var _out_dir := ""
var _consumed := 0
var _round := 0
var _events: FileAccess


func _initialize() -> void:
	var ws_port := Protocol.WS_PORT
	var http_port := Protocol.HTTP_PORT
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--cmd="):
			_cmd_path = arg.trim_prefix("--cmd=")
		elif arg.begins_with("--out="):
			_out_dir = arg.trim_prefix("--out=").trim_suffix("/") + "/"
			DirAccess.make_dir_recursive_absolute(_out_dir)
		elif arg.begins_with("--ws="):
			ws_port = int(arg.trim_prefix("--ws="))
		elif arg.begins_with("--http="):
			http_port = int(arg.trim_prefix("--http="))
	if not _out_dir.is_empty():
		_events = FileAccess.open(_out_dir + "events.log", FileAccess.WRITE)
	host = HostMain.new()
	host.server_port = ws_port
	host.web_port = http_port
	host.announce = false
	root.add_child(host)
	host.server.player_joined.connect(func(_p: Dictionary) -> void: _print_players("joined"))
	host.server.player_reconnected.connect(func(_p: Dictionary) -> void: _print_players("reconnected"))
	host.server.player_disconnected.connect(func(_id: int) -> void: _print_players("disconnected"))
	host.server.player_left.connect(func(_id: int) -> void: _print_players("left"))
	host.server.input_received.connect(_on_input)
	_loop.call_deferred()


func _loop() -> void:
	# Un nodo agregado desde _initialize recibe _ready recién en el primer cuadro.
	await process_frame
	await process_frame
	host._lobby._stepper.set_value(Protocol.MAX_PLAYERS)  # Que entren los 3 celulares de la prueba.
	_say("E2E code=%s http=%d ws=%d url=%s" % [host.server.room_code, host.web.port, host.server.port, host._lobby.join_url()])
	while true:
		await create_timer(0.2).timeout
		if _cmd_path.is_empty() or not FileAccess.file_exists(_cmd_path):
			continue
		# Solo las líneas terminadas en "\n": la última puede estar a medio escribir.
		var lines := FileAccess.get_file_as_string(_cmd_path).split("\n")
		while _consumed < lines.size() - 1:
			var line := lines[_consumed].strip_edges()
			_consumed += 1
			if line.is_empty():
				continue
			await _run(line)
			_say("E2E done %s" % line)


func _run(line: String) -> void:
	var parts := line.split(" ", false, 1)
	var cmd := parts[0]
	var arg := parts[1] if parts.size() > 1 else ""
	match cmd:
		"shot":
			await _shot(arg)
		"start":
			var ids: Array[String] = []
			for id in arg.split(","):
				ids.append(id.strip_edges())
			var ok := host.start_tournament(ids)
			await _settle()
			_say("E2E started=%s game=%s" % [ok, host.tournament.current_game_id if host.tournament else ""])
		"skip":
			await _until(func() -> bool: return MascotAtlas.is_idle() and Board25DBaker.is_idle(), 30000)
			host.skip_intro()
			await _settle()
			_say("E2E playing=%s" % [is_instance_valid(host._game)])
		"finish":
			if is_instance_valid(host._game):
				host._game.finish(_fake_result())
				_round += 1
			await create_timer(0.5).timeout
			await _settle()
		"continue":
			if host._summary.visible:
				host._summary._on_continue()
			await _settle()
		"lobby":
			host._back_to_lobby()
			await _settle()
		"layout":
			var lp := arg.split(" ", false, 1)
			var data: Dictionary = {}
			if lp.size() > 1:
				var parsed: Variant = JSON.parse_string(lp[1])
				if typeof(parsed) == TYPE_DICTIONARY:
					data = parsed
			if lp.size() > 0 and lp[0] in Protocol.LAYOUTS:
				host.server.set_layout(lp[0], data)
		"players":
			_print_players("asked")
		"quit":
			quit(0)
		_:
			_say("E2E unknown %s" % line)


func _say(line: String) -> void:
	print(line)
	if _events != null:
		_events.store_line(line)
		_events.flush()


## Entrada de un celular, solo cuando cambia (los keepalive repiten el estado).
var _last_input: Dictionary = {}
func _on_input(player_id: int, input: Dictionary) -> void:
	var key := "%d %.2f %.2f %d" % [player_id, input.axis.x, input.axis.y, input.btn]
	if _last_input.get(player_id, "") == key:
		return
	_last_input[player_id] = key
	_say("E2E input %s" % key)


func _print_players(why: String) -> void:
	var list: Array = []
	for p in host.server.get_players():
		list.append({"id": p.id, "slot": p.slot, "name": p.name, "connected": p.connected, "color": p.color_index, "style": p.style})
	_say("E2E players %s %s" % [why, JSON.stringify(list)])


func _fake_result() -> Dictionary:
	var scores := {}
	var ids: Array = []
	for p in host.server.get_players():
		ids.append(p.id)
	for i in ids.size():
		scores[ids[i]] = 10 + ((i + _round) % ids.size()) * 7
	var best := -1
	var winner := 0
	for pid: int in scores:
		if scores[pid] > best:
			best = scores[pid]
			winner = pid
	return {"winners": [winner], "scores": scores, "summary": ""}


func _shot(name: String) -> void:
	if not MascotAtlas.is_idle():
		await _until(func() -> bool: return MascotAtlas.is_idle(), 2500)
	for i in 3:
		await process_frame
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	var path := _out_dir + name + ".png"
	img.save_png(path)
	_say("E2E shot=%s" % path)


func _settle() -> void:
	await _until(func() -> bool: return not host._transition.is_running(), 3000)
	for i in 2:
		await process_frame


func _until(cond: Callable, timeout_ms: int = 5000) -> void:
	var start := Time.get_ticks_msec()
	while not cond.call() and Time.get_ticks_msec() - start < timeout_ms:
		await process_frame
