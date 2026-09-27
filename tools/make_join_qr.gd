extends SceneTree
## Genera un PNG con el QR para unirse a la TV. Sirve para probar el
## codificador QR de terceros (`addons/pmc_qr/`, MIT, ver CREDITS.md) y elegir
## tamaño y colores ANTES de ponerlo en el lobby (Fase B). No toca el lobby.
##
##   godot --headless --path . -s res://tools/make_join_qr.gd -- --out=/tmp/qr.png
##   … -- --ip=192.168.1.87 --code=AB23   (datos fijos en vez de la IP local y un código al azar)
##   … -- --text="https://ejemplo.com"     (codificar un texto cualquiera)
##   … -- --module=10                      (píxeles por módulo; por defecto 10)
##
## Concepto — *módulo*: cada cuadradito del QR. Un QR "versión 3" tiene
## 29 × 29 módulos y se le suma un margen claro de 4 módulos por lado
## (*quiet zone*), así que con 10 px por módulo mide (29 + 8) × 10 = 370 px.
## Ejemplo: en una TV de 50" a 1080p, 370 px son ~23 cm; Sofi lo escanea
## desde el sillón sin levantarse. Cuanto más corto el texto, menor la
## versión y más grandes los módulos para el mismo tamaño en pantalla.
##
## El QR se genera UNA vez (~1 ms) y se guarda como imagen o capa cacheada:
## no se recalcula en cada cuadro (ver docs/PERFORMANCE.md).
##
## Funciona con --headless: solo arma una Image y la guarda, no dibuja.

## Esquema provisional del enlace para unirse (propuesto en docs/CALIDAD.md).
## Cuando se decida en la Fase B (ADR + Protocol), este helper se mueve a
## `core/protocol/` y el celular aprende a leerlo.
const JOIN_SCHEME := "partygame://join"
const DEFAULT_MODULE_PX := 10
const QUIET_ZONE := 4
## Corrección de errores M: se puede perder ~15 % de los módulos (un reflejo
## de la lámpara en la pantalla) y el QR se sigue leyendo.
const ECC := PMCQr.ECC_M


func _initialize() -> void:
	var args := _parse_args(OS.get_cmdline_user_args())
	var text: String = args.get("text", "")
	if text.is_empty():
		var ip: String = args.get("ip", _first_local_ipv4())
		var code: String = args.get("code", Protocol.generate_room_code())
		text = join_url(ip, Protocol.WS_PORT, code)
	var module_px := clampi(int(args.get("module", DEFAULT_MODULE_PX)), 1, 64)
	var out: String = args.get("out", "user://join_qr.png")

	var t0 := Time.get_ticks_usec()
	var m := encode(text)
	var t1 := Time.get_ticks_usec()
	if m == null:
		printerr("El texto no entra en un QR (máximo versión 40): %d bytes" % text.to_utf8_buffer().size())
		quit(1)
		return
	var img := to_image(m, module_px)
	var t2 := Time.get_ticks_usec()
	var err := img.save_png(out)

	print("Texto:     %s" % text)
	print("Versión:   %d (%d × %d módulos), corrección M, máscara %d, modo %s" % [m.version, m.size, m.size, m.mask, m.mode])
	print("Imagen:    %d × %d px (%d px por módulo + margen de %d módulos)" % [img.get_width(), img.get_height(), module_px, QUIET_ZONE])
	print("Tiempo:    codificar %.2f ms · imagen %.2f ms" % [(t1 - t0) / 1000.0, (t2 - t1) / 1000.0])
	if err != OK:
		printerr("No se pudo guardar %s (error %d)" % [out, err])
		quit(1)
		return
	print("Guardado:  %s" % ProjectSettings.globalize_path(out))
	quit(0)


## Enlace para unirse: IP de la TV y código de sala; el puerto solo si no es
## el de siempre. El celular lo tendrá que validar igual que cualquier dato
## de red (nunca confiar en él).
## Ejemplo: "partygame://join?ip=192.168.1.87&code=AB23" son 42 caracteres y
## entran justo en la versión 3 (29 × 29); con "&port=47777" serían 53 y
## pasaría a la versión 4 (33 × 33): módulos más chicos en la misma pantalla.
static func join_url(ip: String, port: int, code: String) -> String:
	var url := "%s?ip=%s&code=%s" % [JOIN_SCHEME, ip.uri_encode(), code.uri_encode()]
	if port != Protocol.WS_PORT:
		url += "&port=%d" % port
	return url


## Codifica `text` en la versión más chica que alcance. Devuelve null si no
## entra (más de ~2300 bytes con corrección M).
static func encode(text: String) -> PMCQrMatrix:
	return PMCQr.encode(text, ECC)


## Imagen del QR con los colores del sistema visual: tinta sobre papel
## (contraste ~15:1; los lectores de QR necesitan oscuro sobre claro).
static func to_image(m: PMCQrMatrix, module_px: int) -> Image:
	var side := (m.size + QUIET_ZONE * 2) * module_px
	var img := Image.create(side, side, false, Image.FORMAT_RGB8)
	img.fill(UiTheme.PAPER)
	for y in m.size:
		for x in m.size:
			if m.get_module(x, y):
				img.fill_rect(Rect2i((x + QUIET_ZONE) * module_px, (y + QUIET_ZONE) * module_px, module_px, module_px), UiTheme.INK)
	return img


static func _first_local_ipv4() -> String:
	for ip in IP.get_local_addresses():
		if ip.contains(".") and not ip.begins_with("127.") and not ip.begins_with("169.254."):
			return ip
	return "127.0.0.1"


static func _parse_args(raw: PackedStringArray) -> Dictionary:
	var out := {}
	for a in raw:
		if a.begins_with("--") and a.contains("="):
			var kv := a.substr(2).split("=", true, 1)
			out[kv[0]] = kv[1]
	return out
