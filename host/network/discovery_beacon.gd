class_name DiscoveryBeacon
extends Node
## Anuncia la TV en la red local por UDP broadcast, una vez por segundo.
##
## Decisión de seguridad: el anuncio NO incluye el código de sala.
## El celular descubre "hay una TV en 192.168.0.20", pero para unirse necesita
## el código que se ve en pantalla. Así, estar en la misma Wi-Fi no alcanza:
## hay que estar físicamente frente a la TV.

@export var host_name := "PARTY-GAME TV"
@export var ws_port := Protocol.WS_PORT
@export var interval_sec := 1.0

var _udp := PacketPeerUDP.new()
var _elapsed := 0.0
var _running := false


func start(p_ws_port: int, p_host_name: String = host_name) -> Error:
	ws_port = p_ws_port
	host_name = p_host_name
	_udp.set_broadcast_enabled(true)
	var err := _udp.set_dest_address("255.255.255.255", Protocol.DISCOVERY_PORT)
	_running = err == OK
	if _running:
		announce()
	return err


func stop() -> void:
	_running = false
	_udp.close()


func _process(delta: float) -> void:
	if not _running:
		return
	_elapsed += delta
	if _elapsed >= interval_sec:
		_elapsed = 0.0
		announce()


func announce() -> void:
	var msg := Protocol.encode(Protocol.T_ANNOUNCE, {
		"game": Protocol.GAME_ID,
		"name": host_name,
		"port": ws_port,
	})
	_udp.put_packet(msg.to_utf8_buffer())
