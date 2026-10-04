class_name DiscoveryListener
extends Node
## Escucha los anuncios UDP de las TVs en la red local y mantiene una lista
## actualizada. Si la red bloquea broadcast (Wi-Fi de hoteles, oficinas,
## "aislamiento de clientes"), la lista queda vacía y el usuario puede
## escribir la IP a mano (ver controller_main.gd).
##
## Android: muchos celulares descartan los paquetes broadcast de la Wi-Fi
## (para ahorrar batería) si la app no tiene tomado un *multicast lock*.
## En Godot, `set_broadcast_enabled(true)` lo toma en Android (y lo suelta al
## cerrar); necesita el permiso CHANGE_WIFI_MULTICAST_STATE del preset de
## exportación. En PC no cambia nada. Ver docs/BUILD.md.

signal hosts_changed(hosts: Array[Dictionary])

const HOST_EXPIRY_MS := 3500

var _udp := PacketPeerUDP.new()
var _hosts: Dictionary = {}  # "ip:port" -> {ip, port, name, last_seen}
var _listening := false


func start() -> Error:
	_udp.set_broadcast_enabled(true)  # Android: toma el multicast lock (ver arriba).
	var err := _udp.bind(Protocol.DISCOVERY_PORT, "0.0.0.0")
	_listening = err == OK
	return err


func stop() -> void:
	_listening = false
	_udp.close()
	_hosts.clear()


func get_hosts() -> Array[Dictionary]:
	var list: Array[Dictionary] = []
	for h: Dictionary in _hosts.values():
		list.append(h)
	list.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.name < b.name)
	return list


func _process(_delta: float) -> void:
	if not _listening:
		return
	var changed := false
	while _udp.get_available_packet_count() > 0:
		var raw := _udp.get_packet().get_string_from_utf8()
		var ip := _udp.get_packet_ip()
		changed = _register(ip, raw) or changed
	var now := Time.get_ticks_msec()
	for key: String in _hosts.keys():
		if now - int(_hosts[key].last_seen) > HOST_EXPIRY_MS:
			_hosts.erase(key)
			changed = true
	if changed:
		hosts_changed.emit(get_hosts())


func _register(ip: String, raw: String) -> bool:
	var msg := Protocol.decode(raw)
	if msg.is_empty() or msg.type != Protocol.T_ANNOUNCE or not Protocol.is_supported_version(msg):
		return false
	if msg.get("game") != Protocol.GAME_ID:
		return false
	var port_v: Variant = msg.get("port")
	if typeof(port_v) not in [TYPE_INT, TYPE_FLOAT] or int(port_v) < 1 or int(port_v) > 65535:
		return false
	var host_name := Protocol.sanitize_name(msg.get("name"))
	if host_name.is_empty():
		host_name = ip
	var key := "%s:%d" % [ip, int(port_v)]
	var is_new := not _hosts.has(key)
	_hosts[key] = {"ip": ip, "port": int(port_v), "name": host_name, "last_seen": Time.get_ticks_msec()}
	return is_new
