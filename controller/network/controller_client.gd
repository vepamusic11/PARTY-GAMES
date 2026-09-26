class_name ControllerClient
extends Node
## Cliente WebSocket del celular. Se une a la sala, manda inputs y mide
## latencia. Si se corta la conexión (Wi-Fi, pantalla bloqueada) reintenta
## solo, usando el token de sesión para recuperar su lugar.

signal joined(info: Dictionary)
signal rejected(reason: String)
signal connection_lost()        ## Se cortó, intentando reconectar.
signal reconnected()
signal gave_up()                ## No se pudo reconectar: volver a la pantalla inicial.
signal layout_changed(layout: String, data: Dictionary)
signal phase_changed(phase: String)

enum State { IDLE, CONNECTING, JOINED, RECONNECTING, LEAVING }

const PING_INTERVAL_MS := 1000
const MAX_RECONNECT_ATTEMPTS := 8
const CONNECT_TIMEOUT_MS := 4000

var state := State.IDLE
var player_info: Dictionary = {}
## Latencia ida y vuelta en ms (promedio móvil). -1 = sin datos todavía.
var rtt_ms := -1.0

var _ws := WebSocketPeer.new()
var _url := ""
var _room := ""
var _name := ""
var _token := ""
var _seq := 0
var _last_ping_ms := 0
var _attempt := 0
var _next_attempt_ms := 0
var _connect_started_ms := 0
var _join_sent := false


func join(ip: String, port: int, room: String, player_name: String) -> Error:
	_url = "ws://%s:%d" % [ip, port]
	_room = Protocol.normalize_room_code(room)
	_name = Protocol.sanitize_name(player_name)
	_token = ""
	_attempt = 0
	return _open(State.CONNECTING)


func leave() -> void:
	if _ws.get_ready_state() == WebSocketPeer.STATE_OPEN:
		_ws.send_text(Protocol.encode(Protocol.T_LEAVE))
		_ws.close(1000, "bye")
		# Se sigue haciendo poll hasta que el cierre se envíe de verdad.
		state = State.LEAVING
		_connect_started_ms = Time.get_ticks_msec()
	else:
		state = State.IDLE
	_token = ""


func send_input(axis: Vector2, buttons: int) -> void:
	if state != State.JOINED:
		return
	_seq += 1
	_ws.send_text(Protocol.encode(Protocol.T_INPUT, {
		"seq": _seq,
		"axis": [snappedf(axis.x, 0.001), snappedf(axis.y, 0.001)],
		"btn": buttons,
	}))


func _process(_delta: float) -> void:
	poll()


func poll() -> void:
	if state == State.IDLE:
		return
	var now := Time.get_ticks_msec()
	if state == State.LEAVING:
		_ws.poll()
		if _ws.get_ready_state() == WebSocketPeer.STATE_CLOSED or now - _connect_started_ms > CONNECT_TIMEOUT_MS:
			state = State.IDLE
		return
	if state == State.RECONNECTING and _ws.get_ready_state() == WebSocketPeer.STATE_CLOSED:
		if now >= _next_attempt_ms:
			_open(State.RECONNECTING)
		return

	_ws.poll()
	# Leer primero lo que haya llegado: un "reject" puede venir justo antes del cierre.
	if _ws.get_ready_state() != WebSocketPeer.STATE_CONNECTING:
		while _ws.get_available_packet_count() > 0:
			_handle(_ws.get_packet().get_string_from_utf8())
			if state == State.IDLE:
				return
	match _ws.get_ready_state():
		WebSocketPeer.STATE_CONNECTING:
			if now - _connect_started_ms > CONNECT_TIMEOUT_MS:
				_ws.close()
				_on_closed()
		WebSocketPeer.STATE_OPEN:
			if not _join_sent:
				_send_join()
			if state == State.JOINED and now - _last_ping_ms >= PING_INTERVAL_MS:
				_last_ping_ms = now
				_ws.send_text(Protocol.encode(Protocol.T_PING, {"t": now}))
		WebSocketPeer.STATE_CLOSED:
			_on_closed()


func _open(new_state: State) -> Error:
	_ws = WebSocketPeer.new()
	_ws.inbound_buffer_size = 8192
	_join_sent = false
	_connect_started_ms = Time.get_ticks_msec()
	var err := _ws.connect_to_url(_url)
	state = new_state
	if err != OK:
		_on_closed()
	return err


func _send_join() -> void:
	_join_sent = true
	var payload := {"room": _room, "name": _name}
	if not _token.is_empty():
		payload["token"] = _token
	_ws.send_text(Protocol.encode(Protocol.T_JOIN, payload))


func _handle(raw: String) -> void:
	var msg := Protocol.decode(raw)
	if msg.is_empty():
		return
	match msg.type:
		Protocol.T_WELCOME:
			var was_reconnecting := state == State.RECONNECTING
			_token = str(msg.get("token", ""))
			player_info = {
				"id": int(msg.get("playerId", 0)),
				"name": str(msg.get("name", _name)),
				"color": Color.from_string(str(msg.get("color", "")), Color.WHITE),
			}
			state = State.JOINED
			_attempt = 0
			if was_reconnecting:
				reconnected.emit()
			else:
				joined.emit(player_info)
			phase_changed.emit(str(msg.get("phase", Protocol.PHASE_LOBBY)))
		Protocol.T_REJECT:
			state = State.IDLE
			_token = ""
			rejected.emit(str(msg.get("reason", "unknown")))
		Protocol.T_LAYOUT:
			var layout := str(msg.get("layout", Protocol.LAYOUT_WAIT))
			var data: Variant = msg.get("data", {})
			layout_changed.emit(layout, data if typeof(data) == TYPE_DICTIONARY else {})
		Protocol.T_PHASE:
			phase_changed.emit(str(msg.get("phase", "")))
		Protocol.T_PONG:
			var sent: Variant = msg.get("t")
			if typeof(sent) in [TYPE_INT, TYPE_FLOAT]:
				var sample := float(Time.get_ticks_msec() - int(sent))
				rtt_ms = sample if rtt_ms < 0 else lerpf(rtt_ms, sample, 0.2)


func _on_closed() -> void:
	# El host cierra con código 4000 y el motivo cuando rechaza o expulsa.
	# Se lee del cierre porque el mensaje "reject" puede descartarse al cerrar.
	if state != State.IDLE and _ws.get_close_code() == 4000:
		state = State.IDLE
		_token = ""
		rejected.emit(_ws.get_close_reason() if not _ws.get_close_reason().is_empty() else "unknown")
		return
	match state:
		State.CONNECTING:
			state = State.IDLE
			rejected.emit("unreachable")
		State.JOINED, State.RECONNECTING:
			if _token.is_empty():
				state = State.IDLE
				gave_up.emit()
				return
			if state == State.JOINED:
				connection_lost.emit()
			_attempt += 1
			if _attempt > MAX_RECONNECT_ATTEMPTS:
				state = State.IDLE
				gave_up.emit()
				return
			state = State.RECONNECTING
			# Backoff exponencial: 0.5s, 1s, 2s, 4s... tope 5s.
			_next_attempt_ms = Time.get_ticks_msec() + mini(500 * (1 << (_attempt - 1)), 5000)
