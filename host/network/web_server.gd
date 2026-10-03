class_name WebControllerServer
extends Node
## Servidor HTTP mínimo que corre en la TV y sirve el control web
## (`res://web/`: una página que habla el mismo protocolo que la app del
## celular, por WebSocket, desde el navegador). Ver ADR 0022.
##
## Qué hace y qué no:
##   - Solo GET y HEAD, solo una lista blanca fija de archivos (ROUTES). La
##     ruta pedida se busca tal cual en el mapa: nunca se arma una ruta de
##     disco con lo que manda el cliente (`..`, `%2e`, etc. dan 404).
##   - Además de los archivos, acepta la ruta del QR (`/K7QX`,
##     Protocol.parse_web_join_path) y sirve la misma página: el JS lee el
##     código de la URL.
##   - Inyecta en la página el puerto real del WebSocket (puede no ser el de
##     siempre si estaba ocupado): `{{WS_PORT}}` en index.html.
##   - Cabeceras de seguridad: Content-Type correcto, nosniff y una CSP que
##     solo permite recursos de la propia TV y el WebSocket a la misma IP
##     (la del encabezado Host, validada) y al puerto real.
##   - Límites: cabecera de hasta MAX_HEADER_BYTES, HEADER_TIMEOUT_MS para
##     mandarla, MAX_CONNECTIONS a la vez; se cierra después de responder.
##     Cualquier cosa rara se responde con 400/404/405/431 o se corta: nunca
##     lanza errores por datos externos (regla del proyecto).
##   - No bloquea el cuadro: poll no bloqueante, lee y escribe de a pedazos.
##     Sin conexiones cuesta un `is_connection_available()` por cuadro.
##
## Los archivos se leen de `res://` una vez (FileAccess: funciona desde el
## proyecto y desde un export, siempre que `web/*` esté en el
## `include_filter` del preset). Los que Godot importaría (fuentes,
## imágenes) viven con extensión `.bin` para que no los importe ni los deje
## afuera del export; acá se sirven con su Content-Type real.

const WEB_DIR := "res://web/"
## Ruta pedida -> [archivo en WEB_DIR, Content-Type, cacheable].
const ROUTES := {
	"/": ["index.html", "text/html; charset=utf-8", false],
	"/index.html": ["index.html", "text/html; charset=utf-8", false],
	"/controller.css": ["controller.css", "text/css; charset=utf-8", false],
	"/controller.js": ["controller.js", "text/javascript; charset=utf-8", false],
	"/fredoka-bold.woff2": ["fredoka-bold.woff2.bin", "font/woff2", true],
	"/fredoka-semibold.woff2": ["fredoka-semibold.woff2.bin", "font/woff2", true],
	"/logo.png": ["logo.png.bin", "image/png", true],
	"/icon.svg": ["icon.svg.bin", "image/svg+xml", true],
}
const INDEX_ROUTE := "/"
const WS_PORT_PLACEHOLDER := "{{WS_PORT}}"
const MAX_CONNECTIONS := 16
const MAX_HEADER_BYTES := 4096
const MAX_PATH_LENGTH := 256
const WRITE_CHUNK_BYTES := 16384
## Lo que queda sin leer al cerrar se descarta (hasta esto) para que el
## cierre no corte la respuesta con un RST antes de que llegue.
const DRAIN_BYTES := 65536

## Tiempo para mandar la cabecera completa; los tests lo acortan.
var header_timeout_ms := 5000
var port := 0
## Puerto real del WebSocket (se inyecta en la página).
var ws_port := Protocol.WS_PORT
## Cantidad de respuestas enviadas (para tests y diagnóstico).
var requests_served := 0

var _tcp := TCPServer.new()
var _conns: Array[_Conn] = []
var _cache: Dictionary = {}  # archivo -> PackedByteArray


class _Conn:
	var tcp: StreamPeerTCP
	var opened_at := 0
	var buf := PackedByteArray()
	var out := PackedByteArray()
	var sent := 0
	var responding := false


## Abre el puerto `p_port` o, si está ocupado, alguno de los `attempts - 1`
## siguientes. `p_ws_port` es el puerto real del WebSocket de la TV.
func start(p_port: int = Protocol.HTTP_PORT, p_ws_port: int = Protocol.WS_PORT, bind_address: String = "*",
		attempts: int = Protocol.HTTP_PORT_ATTEMPTS) -> Error:
	ws_port = p_ws_port
	var err := ERR_CANT_CREATE
	for offset in maxi(1, attempts):
		err = _tcp.listen(p_port + offset, bind_address)
		if err == OK:
			port = _tcp.get_local_port()
			break
	return err


func stop() -> void:
	for c in _conns:
		c.tcp.disconnect_from_host()
	_conns.clear()
	_tcp.stop()
	port = 0


func is_listening() -> bool:
	return _tcp.is_listening()


func active_connections() -> int:
	return _conns.size()


func _exit_tree() -> void:
	stop()


func _process(_delta: float) -> void:
	poll()


func poll() -> void:
	if not _tcp.is_listening():
		return
	while _tcp.is_connection_available():
		var stream := _tcp.take_connection()
		if stream == null:
			break
		if _conns.size() >= MAX_CONNECTIONS:
			stream.disconnect_from_host()
			continue
		stream.set_no_delay(true)
		var c := _Conn.new()
		c.tcp = stream
		c.opened_at = Time.get_ticks_msec()
		_conns.append(c)
	var now := Time.get_ticks_msec()
	var i := 0
	while i < _conns.size():
		if _poll_conn(_conns[i], now):
			i += 1
		else:
			_conns[i].tcp.disconnect_from_host()
			_conns.remove_at(i)


## Devuelve false si la conexión hay que cerrarla.
func _poll_conn(c: _Conn, now: int) -> bool:
	c.tcp.poll()
	var status := c.tcp.get_status()
	if status == StreamPeerTCP.STATUS_ERROR or status == StreamPeerTCP.STATUS_NONE:
		return false
	if status != StreamPeerTCP.STATUS_CONNECTED:
		return now - c.opened_at <= header_timeout_ms
	if not c.responding:
		if not _read_header(c):
			return false
		if not c.responding and now - c.opened_at > header_timeout_ms:
			return false  # No mandó la cabecera a tiempo: se corta sin responder.
	if c.responding:
		return _write_some(c)
	return true


## Lee lo que haya llegado (hasta MAX_HEADER_BYTES) y, si la cabecera está
## completa, arma la respuesta. false = cortar (error de lectura).
func _read_header(c: _Conn) -> bool:
	var avail := c.tcp.get_available_bytes()
	if avail <= 0:
		return true
	var want := mini(avail, MAX_HEADER_BYTES + 1 - c.buf.size())
	if want > 0:
		var r := c.tcp.get_partial_data(want)
		if r[0] != OK:
			return false
		c.buf.append_array(r[1])
	var head := c.buf.get_string_from_ascii()
	var end := head.find("\r\n\r\n")
	if end >= 0:
		_respond(c, _handle_request(head.substr(0, end)))
	elif c.buf.size() > MAX_HEADER_BYTES:
		_respond(c, _error_response(431, "Request Header Fields Too Large"))
	return true


## Manda lo que entre en el buffer de salida. false = terminó (o falló) y
## hay que cerrar.
func _write_some(c: _Conn) -> bool:
	var budget := WRITE_CHUNK_BYTES
	while c.sent < c.out.size() and budget > 0:
		var chunk := c.out.slice(c.sent, mini(c.out.size(), c.sent + budget))
		var r := c.tcp.put_partial_data(chunk)
		if r[0] != OK:
			return false
		var n := int(r[1])
		if n <= 0:
			return true  # Buffer del sistema lleno: se sigue en el próximo cuadro.
		c.sent += n
		budget -= n
	if c.sent >= c.out.size():
		# Descartar lo que quedó sin leer (ej. cuerpo de un POST) y cerrar.
		var pending := mini(c.tcp.get_available_bytes(), DRAIN_BYTES)
		if pending > 0:
			c.tcp.get_partial_data(pending)
		requests_served += 1
		return false
	return true


func _respond(c: _Conn, response: PackedByteArray) -> void:
	c.out = response
	c.sent = 0
	c.responding = true


# --- HTTP -------------------------------------------------------------------------

## Arma la respuesta completa (cabecera + cuerpo) a una cabecera de pedido.
## Cualquier cosa fuera de lo esperado termina en 400/404/405.
func _handle_request(head: String) -> PackedByteArray:
	var lines := head.split("\r\n")
	var request_line := lines[0].split(" ")
	if request_line.size() != 3 or not request_line[2].begins_with("HTTP/1."):
		return _error_response(400, "Bad Request")
	var method := request_line[0]
	var target := request_line[1]
	var host := _host_header(lines)
	if host.is_empty():
		return _error_response(400, "Bad Request")
	if method != "GET" and method != "HEAD":
		return _error_response(405, "Method Not Allowed", ["Allow: GET, HEAD"])
	var path := target.split("?", true, 1)[0]
	if path.is_empty() or path.length() > MAX_PATH_LENGTH or not path.begins_with("/"):
		return _error_response(404, "Not Found")
	var route: Array = ROUTES.get(path, [])
	if route.is_empty() and not Protocol.parse_web_join_path(path).is_empty():  # "/K7QX": la ruta del QR.
		route = ROUTES[INDEX_ROUTE]
	if route.is_empty():
		return _error_response(404, "Not Found")
	var body := _file(route[0])
	if body.is_empty():
		return _error_response(404, "Not Found")
	if route[0] == ROUTES[INDEX_ROUTE][0]:
		body = body.get_string_from_utf8().replace(WS_PORT_PLACEHOLDER, str(ws_port)).to_utf8_buffer()
	var headers: Array[String] = [
		"Content-Type: " + route[1],
		"Cache-Control: " + ("public, max-age=604800, immutable" if route[2] else "no-cache"),
		"Content-Security-Policy: " + _csp(host),
	]
	return _response(200, "OK", headers, body, method == "HEAD")


## Valor del encabezado Host sin el puerto, validado: una IP (v4 o v6 entre
## corchetes) o un nombre con letras, números, puntos y guiones. "" si no
## sirve (sin él no se puede armar la CSP del WebSocket).
func _host_header(lines: PackedStringArray) -> String:
	for i in range(1, lines.size()):
		var line := lines[i]
		var colon := line.find(":")
		if colon <= 0 or line.substr(0, colon).strip_edges().to_lower() != "host":
			continue
		var value := line.substr(colon + 1).strip_edges()
		if value.begins_with("["):
			var close := value.find("]")
			if close < 0:
				return ""
			var v6 := value.substr(1, close - 1)
			return "[%s]" % v6 if v6.is_valid_ip_address() else ""
		var host := value.split(":")[0]
		if host.is_empty() or host.length() > 253:
			return ""
		if host.is_valid_ip_address():
			return host
		for ch in host:
			var code := ch.unicode_at(0)
			var ok := (code >= 48 and code <= 57) or (code >= 65 and code <= 90) or (code >= 97 and code <= 122) \
				or ch == "." or ch == "-"
			if not ok:
				return ""
		return host
	return ""


## Política de contenido: todo de la propia TV; el WebSocket solo a la misma
## dirección que sirvió la página y al puerto real del juego.
func _csp(host: String) -> String:
	return ("default-src 'none'; script-src 'self'; style-src 'self'; font-src 'self'; img-src 'self' data:; "
		+ "connect-src ws://%s:%d; base-uri 'none'; form-action 'none'; frame-ancestors 'none'") % [host, ws_port]


func _error_response(code: int, text: String, extra: Array[String] = []) -> PackedByteArray:
	var headers: Array[String] = ["Content-Type: text/plain; charset=utf-8", "Cache-Control: no-store"]
	headers.append_array(extra)
	return _response(code, text, headers, ("%d %s\n" % [code, text]).to_utf8_buffer(), false)


static func _response(code: int, text: String, headers: Array[String], body: PackedByteArray, head_only: bool) -> PackedByteArray:
	var lines: Array[String] = ["HTTP/1.1 %d %s" % [code, text]]
	lines.append_array(headers)
	lines.append("Content-Length: %d" % body.size())
	lines.append("X-Content-Type-Options: nosniff")
	lines.append("Referrer-Policy: no-referrer")
	lines.append("Connection: close")
	var out := ("\r\n".join(lines) + "\r\n\r\n").to_utf8_buffer()
	if not head_only:
		out.append_array(body)
	return out


## Contenido de un archivo de WEB_DIR (en caché desde la primera vez).
## Si no está en res:// (un export sin `web/*` en el include_filter) sale de
## la copia embebida WebBundle (tools/build_web_bundle.gd). PackedByteArray
## vacío si no existe en ningún lado.
func _file(name: String) -> PackedByteArray:
	if _cache.has(name):
		return _cache[name]
	var bytes := FileAccess.get_file_as_bytes(WEB_DIR + name)
	if bytes.is_empty():
		bytes = WebBundle.get_file(name)
	if not bytes.is_empty():
		_cache[name] = bytes
	return bytes


# --- Utilidades ----------------------------------------------------------------------

## Ordena las IPv4 de la TV de la más probable para los celulares a la menos:
## 192.168.x primero, después 10.x, después 172.16–31.x (suelen ser de WSL,
## Hyper-V o VirtualBox) y al final el resto. Deja afuera loopback y las de
## enlace local (169.254). Función pura, para poder probarla.
static func sort_lan_ips(ips: Array) -> Array[String]:
	var ranked: Array = []
	for v: Variant in ips:
		if typeof(v) != TYPE_STRING:
			continue
		var ip: String = v
		var parts := ip.split(".")
		if parts.size() != 4 or not ip.is_valid_ip_address():
			continue
		var a := int(parts[0])
		var b := int(parts[1])
		if a == 127 or (a == 169 and b == 254):
			continue
		var rank := 3
		if a == 192 and b == 168:
			rank = 0
		elif a == 10:
			rank = 1
		elif a == 172 and b >= 16 and b <= 31:
			rank = 2
		ranked.append([rank, ip])
	ranked.sort_custom(func(x: Array, y: Array) -> bool:
		return x[0] < y[0] if x[0] != y[0] else str(x[1]) < str(y[1]))
	var out: Array[String] = []
	for r: Array in ranked:
		if not r[1] in out:
			out.append(r[1])
	return out
