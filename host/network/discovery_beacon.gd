class_name DiscoveryBeacon
extends Node
## Anuncia la TV en la red local por UDP broadcast, una vez por segundo.
##
## Decisión de seguridad: el anuncio NO incluye el código de sala.
## El celular descubre "hay una TV en 192.168.0.20", pero para unirse necesita
## el código que se ve en pantalla. Así, estar en la misma Wi-Fi no alcanza:
## hay que estar físicamente frente a la TV.
##
## Destinos: además del broadcast general (255.255.255.255) se manda a la
## dirección de broadcast de cada red privada de la TV, suponiendo máscara /24
## (la de casi todos los routers hogareños): con IP 192.168.1.34 también va a
## 192.168.1.255. Motivo: en una PC con Windows y varios adaptadores
## (VirtualBox, Hyper-V, WSL, VPN) el broadcast general sale por UNO solo, a
## veces el equivocado, y el celular nunca ve la TV. El dirigido sale siempre
## por el adaptador de esa red. Si la red no es /24 no se pierde nada: el
## general sigue saliendo igual.

const LIMITED_BROADCAST := "255.255.255.255"

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
	var err := _udp.set_dest_address(LIMITED_BROADCAST, Protocol.DISCOVERY_PORT)
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
	var packet := msg.to_utf8_buffer()
	# Se recalcula en cada anuncio (1 por segundo, barato): si la PC cambia de
	# Wi-Fi, el anuncio sigue a la red nueva sin reiniciar la TV.
	for target in broadcast_targets(IP.get_local_addresses()):
		if _udp.set_dest_address(target, Protocol.DISCOVERY_PORT) == OK:
			_udp.put_packet(packet)


## Direcciones a las que va el anuncio: el broadcast general y el /24 de cada
## IPv4 privada (10.x, 172.16–31.x, 192.168.x), sin repetir. Función pura
## (recibe las IP locales) para poder probarla.
static func broadcast_targets(local_addresses: Array) -> Array[String]:
	var out: Array[String] = [LIMITED_BROADCAST]
	for addr: Variant in local_addresses:
		if typeof(addr) != TYPE_STRING:
			continue
		var parts := (addr as String).split(".")
		if parts.size() != 4:
			continue  # IPv6 u otra cosa.
		var octets: Array[int] = []
		for p in parts:
			if not p.is_valid_int() or int(p) < 0 or int(p) > 255:
				break
			octets.append(int(p))
		if octets.size() != 4:
			continue
		var is_private := octets[0] == 10 \
				or (octets[0] == 172 and octets[1] >= 16 and octets[1] <= 31) \
				or (octets[0] == 192 and octets[1] == 168)
		if not is_private:
			continue
		var target := "%d.%d.%d.255" % [octets[0], octets[1], octets[2]]
		if target not in out:
			out.append(target)
	return out
