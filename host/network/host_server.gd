class_name HostServer
extends Node
## Servidor WebSocket que corre en la TV. Es la única fuente de verdad:
## acepta controles, valida cada mensaje y reenvía inputs ya limpios.
##
## Ciclo de vida de una conexión:
##   TCP aceptado -> WebSocket abierto -> "join" válido -> jugador
##   Si un jugador se desconecta, su lugar queda reservado RECONNECT_GRACE_MS
##   y puede volver presentando su token (ver docs/PROTOCOL.md).

signal player_joined(player: Dictionary)
signal player_reconnected(player: Dictionary)
signal player_disconnected(player_id: int)  ## Temporal: lugar reservado.
signal player_left(player_id: int)          ## Definitivo: lugar liberado.
signal input_received(player_id: int, input: Dictionary)
## Cambió la apariencia (color/estilo) de un jugador desde el lobby.
signal player_updated(player: Dictionary)

const JOIN_TIMEOUT_MS := 5000
const CLOSING_TIMEOUT_MS := 2000
const MAX_PENDING_CONNECTIONS := 8
const INPUT_RATE_LIMIT_PER_SEC := 90
## "look" dispara un aviso a todos los celulares: tope propio, más bajo.
const LOOK_RATE_LIMIT_PER_SEC := 8
const RECONNECT_GRACE_MS := 30000
const INBOUND_BUFFER_BYTES := 4096

var room_code := ""
var port := 0
## Durante una partida no entran jugadores nuevos (sí reconexiones).
var accepting_new_players := true
## Capacidad de la sala (1..MAX_PLAYERS): la elige quien maneja la TV
## ("¿Cuántos juegan?"). Bajarla no expulsa a nadie: solo frena a los nuevos.
var max_players := Protocol.MAX_PLAYERS:
	set(value):
		max_players = clampi(value, 1, Protocol.MAX_PLAYERS)
var current_layout := Protocol.LAYOUT_WAIT
var current_layout_data: Dictionary = {}
var current_phase := Protocol.PHASE_LOBBY

var _tcp := TCPServer.new()
var _peers: Dictionary = {}    # peer_key -> _Peer
var _players: Dictionary = {}  # player_id -> Dictionary
var _next_peer_key := 1


class _Peer:
	var ws: WebSocketPeer
	var player_id := 0          # 0 = todavía no se unió
	var opened_at := 0
	var closing_since := -1
	var window_start := 0
	var window_count := 0
	var look_window_start := 0
	var look_window_count := 0


func start(p_port: int = Protocol.WS_PORT, bind_address: String = "*") -> Error:
	room_code = Protocol.generate_room_code()
	var err := _tcp.listen(p_port, bind_address)
	if err == OK:
		port = _tcp.get_local_port()
	return err


func stop() -> void:
	for key in _peers.keys():
		(_peers[key] as _Peer).ws.close(1001, "host_stopped")
	_peers.clear()
	_players.clear()
	_tcp.stop()


func is_listening() -> bool:
	return _tcp.is_listening()


func _process(_delta: float) -> void:
	poll()


func poll() -> void:
	if not _tcp.is_listening():
		return
	_accept_new_connections()
	var now := Time.get_ticks_msec()
	for key: int in _peers.keys():
		if _peers.has(key):
			_poll_peer(key, now)
	_expire_disconnected_players(now)


# --- API pública para el juego ------------------------------------------------

func get_players() -> Array[Dictionary]:
	var list: Array[Dictionary] = []
	for p: Dictionary in _players.values():
		list.append(_public_player(p))
	list.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.slot < b.slot)
	return list


func get_connected_count() -> int:
	var n := 0
	for p: Dictionary in _players.values():
		if p.connected:
			n += 1
	return n


func set_phase(phase: String) -> void:
	current_phase = phase
	broadcast(Protocol.T_PHASE, {"phase": phase})
	if phase == Protocol.PHASE_LOBBY:
		_send_appearance_all()  # De vuelta al lobby: el selector del celular se pone al día.


## ¿Se puede cambiar la apariencia ahora? Solo en el lobby y antes de que
## arranque la competencia (el torneo copia color y estilo al empezar).
func can_change_look() -> bool:
	return current_phase == Protocol.PHASE_LOBBY and accepting_new_players


## Cambia el control que ven todos los celulares. data es opcional (ej. etiquetas).
func set_layout(layout: String, data: Dictionary = {}) -> void:
	assert(layout in Protocol.LAYOUTS, "Layout desconocido: %s" % layout)
	current_layout = layout
	current_layout_data = data
	broadcast(Protocol.T_LAYOUT, {"layout": layout, "data": data})


func broadcast(type: String, payload: Dictionary = {}) -> void:
	var text := Protocol.encode(type, payload)
	for peer: _Peer in _peers.values():
		if peer.player_id != 0 and peer.closing_since < 0:
			peer.ws.send_text(text)


func send_to(player_id: int, type: String, payload: Dictionary = {}) -> void:
	var peer := _peer_for_player(player_id)
	if peer:
		peer.ws.send_text(Protocol.encode(type, payload))


## Expulsa a un jugador y libera su lugar (ej. desde el menú de la TV).
func kick(player_id: int) -> void:
	var key := _peer_key_for_player(player_id)
	if key != 0:
		_close_peer(key, 4000, "kicked")
	if _players.has(player_id):
		_players.erase(player_id)
		player_left.emit(player_id)
		_send_appearance_all()


# --- Conexiones ---------------------------------------------------------------

func _accept_new_connections() -> void:
	while _tcp.is_connection_available():
		var stream := _tcp.take_connection()
		if _pending_count() >= MAX_PENDING_CONNECTIONS:
			stream.disconnect_from_host()
			continue
		var ws := WebSocketPeer.new()
		ws.inbound_buffer_size = INBOUND_BUFFER_BYTES
		ws.max_queued_packets = 64
		if ws.accept_stream(stream) != OK:
			stream.disconnect_from_host()
			continue
		var peer := _Peer.new()
		peer.ws = ws
		peer.opened_at = Time.get_ticks_msec()
		_peers[_next_peer_key] = peer
		_next_peer_key += 1


func _poll_peer(key: int, now: int) -> void:
	var peer: _Peer = _peers[key]
	peer.ws.poll()
	var state := peer.ws.get_ready_state()

	if state == WebSocketPeer.STATE_CLOSED:
		_on_peer_closed(key)
		return
	if peer.closing_since >= 0:
		if now - peer.closing_since > CLOSING_TIMEOUT_MS:
			_on_peer_closed(key)
		return
	if peer.player_id == 0 and now - peer.opened_at > JOIN_TIMEOUT_MS:
		_reject(key, Protocol.R_TIMEOUT)
		return
	if state != WebSocketPeer.STATE_OPEN:
		return

	while peer.ws.get_available_packet_count() > 0:
		var packet := peer.ws.get_packet()
		if not peer.ws.was_string_packet():
			_reject(key, Protocol.R_MALFORMED)
			return
		_handle_message(key, packet.get_string_from_utf8(), now)
		if not _peers.has(key) or peer.closing_since >= 0:
			return


func _handle_message(key: int, raw: String, now: int) -> void:
	var peer: _Peer = _peers[key]
	var msg := Protocol.decode(raw)
	if msg.is_empty():
		# Un control ya unido que manda basura se ignora; uno sin unirse, se corta.
		if peer.player_id == 0:
			_reject(key, Protocol.R_MALFORMED)
		return

	if peer.player_id == 0:
		if msg.type == Protocol.T_JOIN:
			_handle_join(key, msg)
		else:
			_reject(key, Protocol.R_MALFORMED)
		return

	match msg.type:
		Protocol.T_INPUT:
			if _rate_limited(peer, now):
				return
			var input := Protocol.parse_input(msg)
			if not input.is_empty():
				input_received.emit(peer.player_id, input)
		Protocol.T_PING:
			var t: Variant = msg.get("t", 0)
			peer.ws.send_text(Protocol.encode(Protocol.T_PONG, {"t": t if typeof(t) in [TYPE_INT, TYPE_FLOAT] else 0}))
		Protocol.T_LOOK:
			if _look_rate_limited(peer, now):
				return
			_handle_look(peer.player_id, Protocol.parse_look(msg))
		Protocol.T_LEAVE:
			var pid := peer.player_id
			_close_peer(key, 1000, "bye")
			if _players.erase(pid):
				player_left.emit(pid)
				_send_appearance_all()
		_:
			pass # Tipos desconocidos se ignoran: permite extender el protocolo.


func _handle_join(key: int, msg: Dictionary) -> void:
	if not Protocol.is_supported_version(msg):
		_reject(key, Protocol.R_BAD_VERSION)
		return
	if not Protocol.is_valid_room_code(msg.get("room")) or msg.room != room_code:
		_reject(key, Protocol.R_BAD_ROOM)
		return

	# ¿Es una reconexión?
	var token: Variant = msg.get("token", "")
	if Protocol.is_valid_token(token):
		for p: Dictionary in _players.values():
			if p.token == token:
				_attach(key, p)
				player_reconnected.emit(_public_player(p))
				_send_appearance(p)  # Se reconecta con su apariencia de antes.
				return

	if not accepting_new_players:
		_reject(key, Protocol.R_GAME_IN_PROGRESS)
		return
	var player_name := Protocol.sanitize_name(msg.get("name"))
	if player_name.is_empty():
		_reject(key, Protocol.R_BAD_NAME)
		return
	var slot := _free_slot()
	if slot < 0 or _players.size() >= max_players:
		_reject(key, Protocol.R_ROOM_FULL)
		return

	# Apariencia pedida (opcional): lo inválido se ignora y se usa la del lugar.
	var look := Protocol.parse_look(msg)
	var color_index := _free_color(int(look.get("color", slot)), 0, slot)
	var player := {
		"id": slot + 1,
		"slot": slot,
		"name": player_name,
		"color": Protocol.mascot_color(color_index),
		"color_index": color_index,
		"style": int(look.get("style", slot)),
		"token": Protocol.generate_token(),
		"connected": false,
		"disconnected_at": -1,
	}
	_players[player.id] = player
	_attach(key, player)
	player_joined.emit(_public_player(player))
	_send_appearance_all()


## Aplica un "look" ya validado (Protocol.parse_look). Fuera del lobby se
## ignora. Si el color pedido lo usa otro jugador, conserva el propio. Se
## confirma siempre al celular (así corrige lo que mostró de antemano).
func _handle_look(player_id: int, look: Dictionary) -> void:
	if not _players.has(player_id) or look.is_empty() or not can_change_look():
		return
	var p: Dictionary = _players[player_id]
	var changed := false
	if look.has("color") and look.color != p.color_index and not _color_taken(look.color, player_id):
		p.color_index = look.color
		p.color = Protocol.mascot_color(look.color)
		changed = true
	if look.has("style") and look.style != p.style:
		p.style = look.style
		changed = true
	if changed:
		player_updated.emit(_public_player(p))
		_send_appearance_all()
	else:
		_send_appearance(p)


func _attach(key: int, player: Dictionary) -> void:
	# Si el jugador tenía otra conexión abierta (ej. dos pestañas), se cierra la vieja.
	var old_key := _peer_key_for_player(player.id)
	if old_key != 0 and old_key != key:
		_close_peer(old_key, 4001, "replaced")
	var peer: _Peer = _peers[key]
	peer.player_id = player.id
	player.connected = true
	player.disconnected_at = -1
	peer.ws.send_text(Protocol.encode(Protocol.T_WELCOME, {
		"playerId": player.id,
		"name": player.name,
		"color": (player.color as Color).to_html(false),
		"colorIndex": player.color_index,
		"style": player.style,
		"token": player.token,
		"phase": current_phase,
	}))
	peer.ws.send_text(Protocol.encode(Protocol.T_LAYOUT, {"layout": current_layout, "data": current_layout_data}))


func _reject(key: int, reason: String) -> void:
	var peer: _Peer = _peers[key]
	if peer.ws.get_ready_state() == WebSocketPeer.STATE_OPEN:
		peer.ws.send_text(Protocol.encode(Protocol.T_REJECT, {"reason": reason}))
	_close_peer(key, 4000, reason)


func _close_peer(key: int, code: int, reason: String) -> void:
	var peer: _Peer = _peers.get(key)
	if peer == null or peer.closing_since >= 0:
		return
	peer.closing_since = Time.get_ticks_msec()
	peer.ws.close(code, reason)


func _on_peer_closed(key: int) -> void:
	var peer: _Peer = _peers[key]
	_peers.erase(key)
	var pid := peer.player_id
	# Cierre prolijo del control (1000 "bye"): se fue a propósito, liberar el lugar.
	if pid != 0 and _players.has(pid) and peer.ws.get_close_code() == 1000 and peer.ws.get_close_reason() == "bye":
		_players.erase(pid)
		player_left.emit(pid)
		_send_appearance_all()
		return
	if pid != 0 and _players.has(pid) and _peer_key_for_player(pid) == 0:
		var p: Dictionary = _players[pid]
		p.connected = false
		p.disconnected_at = Time.get_ticks_msec()
		player_disconnected.emit(pid)


func _expire_disconnected_players(now: int) -> void:
	for pid: int in _players.keys():
		var p: Dictionary = _players[pid]
		if not p.connected and p.disconnected_at >= 0 and now - p.disconnected_at > RECONNECT_GRACE_MS:
			_players.erase(pid)
			player_left.emit(pid)
			_send_appearance_all()


# --- Utilidades ---------------------------------------------------------------

func _rate_limited(peer: _Peer, now: int) -> bool:
	if now - peer.window_start >= 1000:
		peer.window_start = now
		peer.window_count = 0
	peer.window_count += 1
	return peer.window_count > INPUT_RATE_LIMIT_PER_SEC


func _look_rate_limited(peer: _Peer, now: int) -> bool:
	if now - peer.look_window_start >= 1000:
		peer.look_window_start = now
		peer.look_window_count = 0
	peer.look_window_count += 1
	return peer.look_window_count > LOOK_RATE_LIMIT_PER_SEC


## ¿Otro jugador (distinto de except_id) ya usa ese color?
func _color_taken(index: int, except_id: int) -> bool:
	for p: Dictionary in _players.values():
		if p.id != except_id and p.color_index == index:
			return true
	return false


## Colores únicos: el pedido si está libre; si no, el del lugar (1P rojo…);
## si tampoco, el primero libre de la paleta. Siempre hay uno (10 > 4).
func _free_color(requested: int, except_id: int, slot: int) -> int:
	for candidate in [requested, slot]:
		if Protocol.parse_color_index(candidate) >= 0 and not _color_taken(candidate, except_id):
			return candidate
	for i in Protocol.MASCOT_COLORS.size():
		if not _color_taken(i, except_id):
			return i
	return 0


## Colores de los demás jugadores (para que el celular los muestre ocupados).
func _taken_colors(except_id: int) -> Array[int]:
	var out: Array[int] = []
	for p: Dictionary in _players.values():
		if p.id != except_id:
			out.append(p.color_index)
	out.sort()
	return out


## Confirma a un celular su apariencia y los colores ocupados.
func _send_appearance(p: Dictionary) -> void:
	send_to(p.id, Protocol.T_APPEARANCE, {
		"color": p.color_index, "style": p.style, "taken": _taken_colors(p.id),
	})


## Avisa a todos: cambió quién usa qué color (alguien entró, salió o cambió).
func _send_appearance_all() -> void:
	for p: Dictionary in _players.values():
		if p.connected:
			_send_appearance(p)


func _free_slot() -> int:
	var used := {}
	for p: Dictionary in _players.values():
		used[p.slot] = true
	for slot in Protocol.MAX_PLAYERS:
		if not used.has(slot):
			return slot
	return -1


func _pending_count() -> int:
	var n := 0
	for peer: _Peer in _peers.values():
		if peer.player_id == 0:
			n += 1
	return n


func _peer_for_player(player_id: int) -> _Peer:
	var key := _peer_key_for_player(player_id)
	return _peers[key] if key != 0 else null


func _peer_key_for_player(player_id: int) -> int:
	for key: int in _peers.keys():
		var peer: _Peer = _peers[key]
		if peer.player_id == player_id and peer.closing_since < 0:
			return key
	return 0


## Copia sin el token: el token nunca sale del servidor salvo al propio jugador.
func _public_player(p: Dictionary) -> Dictionary:
	return {
		"id": p.id,
		"slot": p.slot,
		"name": p.name,
		"color": p.color,
		"color_index": p.color_index,
		"style": p.style,
		"connected": p.connected,
	}
