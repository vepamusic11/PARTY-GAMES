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
## Resultado propio del resumen de ronda o del podio, ya validado con
## Protocol.parse_standing (ver docs/PROTOCOL.md). Solo informativo.
signal standing_received(data: Dictionary)
## Aviso de vibración/sonido para este jugador (ver Protocol.T_FEEDBACK).
signal feedback_received(kind: String)
## La TV confirmó la apariencia de este jugador (ver Protocol.parse_appearance).
## player_info ya tiene "color", "color_index", "style" y "taken" al día.
signal appearance_changed()

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
## Apariencia pedida (Protocol.parse_look): se manda en "join" si hay algo.
var _look: Dictionary = {}


## look (opcional): {"color": índice, "style": índice}. Lo inválido se descarta.
func join(ip: String, port: int, room: String, player_name: String, look: Dictionary = {}) -> Error:
	_url = "ws://%s:%d" % [ip, port]
	_room = Protocol.normalize_room_code(room)
	_name = Protocol.sanitize_name(player_name)
	_look = Protocol.parse_look(look)
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


## Pide cambiar color y/o estilo (solo tiene efecto en el lobby). La TV
## confirma con "appearance"; si el color está ocupado, conserva el anterior.
func send_look(color_index: int, style: int) -> void:
	var look := Protocol.parse_look({"color": color_index, "style": style})
	_look = look  # Si se reconecta a una sala nueva, pide lo último elegido.
	if state != State.JOINED or look.is_empty():
		return
	_ws.send_text(Protocol.encode(Protocol.T_LOOK, look))


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
	payload.merge(_look)  # Campos opcionales "color" y "style".
	_ws.send_text(Protocol.encode(Protocol.T_JOIN, payload))


func _handle(raw: String) -> void:
	var msg := Protocol.decode(raw)
	if msg.is_empty():
		return
	match msg.type:
		Protocol.T_WELCOME:
			var was_reconnecting := state == State.RECONNECTING
			_token = str(msg.get("token", ""))
			var player_id := int(msg.get("playerId", 0)) if typeof(msg.get("playerId")) in [TYPE_INT, TYPE_FLOAT] else 0
			player_info = {
				"id": player_id,
				"name": str(msg.get("name", _name)),
				"color": Color.from_string(str(msg.get("color", "")), Color.WHITE),
				# Una TV vieja no manda estos campos: -1 = "el de mi lugar".
				"color_index": Protocol.parse_color_index(msg.get("colorIndex")),
				"style": Protocol.parse_style_index(msg.get("style")),
				"taken": [] as Array[int],
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
		Protocol.T_FEEDBACK:
			var kind := Protocol.parse_feedback(msg)
			if not kind.is_empty():
				feedback_received.emit(kind)
		Protocol.T_APPEARANCE:
			var look := Protocol.parse_appearance(msg)
			if not look.is_empty() and not player_info.is_empty():
				player_info["color_index"] = look.color
				player_info["color"] = Protocol.mascot_color(look.color)
				player_info["style"] = look.style
				player_info["taken"] = look.taken
				appearance_changed.emit()
		Protocol.T_STANDING:
			var standing := Protocol.parse_standing(msg)
			if not standing.is_empty():
				standing_received.emit(standing)
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
