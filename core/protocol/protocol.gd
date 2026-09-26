class_name Protocol
extends RefCounted
## Contrato de mensajes entre el host (TV) y los controles (celulares).
##
## Toda la comunicación son mensajes JSON de texto sobre WebSocket.
## Cada mensaje lleva "v" (versión del protocolo) y "type".
## La especificación completa está en docs/PROTOCOL.md: si cambiás algo
## acá, actualizá ese documento y subí VERSION si el cambio no es compatible.

# --- Versionado y red -------------------------------------------------------
const VERSION := 1
const GAME_ID := "party-games"
const WS_PORT := 47777
const DISCOVERY_PORT := 47778

# --- Límites de seguridad -----------------------------------------------------
const MAX_MESSAGE_BYTES := 512
const MAX_PLAYERS := 4
const NAME_MAX_LENGTH := 16
const TOKEN_BYTES := 16
const ROOM_CODE_LENGTH := 4
## 32 caracteres sin ambiguos (sin I, O, 0, 1). Al ser 32 = 256/8, elegir con
## un byte aleatorio módulo 32 no introduce sesgo estadístico.
const ROOM_CODE_ALPHABET := "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
## Topes del mensaje informativo "standing" (ver parse_standing).
const MAX_ROUNDS := 99
const MAX_STANDING_POINTS := 100000

# --- Tipos de mensaje: control -> host ---------------------------------------
const T_JOIN := "join"
const T_INPUT := "input"
const T_PING := "ping"
const T_LEAVE := "leave"

# --- Tipos de mensaje: host -> control ---------------------------------------
const T_WELCOME := "welcome"
const T_REJECT := "reject"
const T_LAYOUT := "layout"
const T_PHASE := "phase"
const T_PONG := "pong"
## Resultado propio (puesto y puntos) durante el resumen y el podio. Es solo
## informativo y compatible con controles viejos (ignoran tipos desconocidos).
const T_STANDING := "standing"
## Aviso de vibración/sonido para UN jugador (sumaste, te eliminaron…). Solo
## informativo y compatible: "kind" tiene que ser uno de FEEDBACK_KINDS.
const T_FEEDBACK := "feedback"
const FEEDBACK_KINDS: Array[String] = ["point", "hit", "win", "lose", "go", "count", "tap"]

# --- Descubrimiento en red local (UDP broadcast) ------------------------------
const T_ANNOUNCE := "announce"

# --- Motivos de rechazo -------------------------------------------------------
const R_BAD_VERSION := "bad_version"
const R_BAD_ROOM := "bad_room"
const R_ROOM_FULL := "room_full"
const R_BAD_NAME := "bad_name"
const R_MALFORMED := "malformed"
const R_GAME_IN_PROGRESS := "game_in_progress"
const R_TIMEOUT := "timeout"

# --- Layouts de control (qué dibuja el celular) ------------------------------
const LAYOUT_WAIT := "wait"             ## Sin juego activo: pantalla de espera.
const LAYOUT_JOYSTICK := "joystick"     ## axis = dirección (-1..1, -1..1).
const LAYOUT_SLIDER_H := "slider_h"     ## axis.x = posición absoluta (-1..1).
const LAYOUT_ONE_BUTTON := "one_button" ## btn & BTN_A = botón presionado.
const LAYOUTS: Array[String] = [LAYOUT_WAIT, LAYOUT_JOYSTICK, LAYOUT_SLIDER_H, LAYOUT_ONE_BUTTON]

# --- Fases de la sesión -------------------------------------------------------
const PHASE_LOBBY := "lobby"
const PHASE_PLAYING := "playing"
const PHASE_RESULTS := "results"

# --- Botones (máscara de bits) -----------------------------------------------
const BTN_A := 1
const BTN_B := 2
const BTN_MASK := BTN_A | BTN_B

## Colores de jugador (1..4). Alto contraste sobre fondo oscuro.
const PLAYER_COLORS: Array[Color] = [
	Color("#E24B4A"), # rojo
	Color("#378ADD"), # azul
	Color("#EF9F27"), # amarillo
	Color("#1D9E75"), # verde
]


## Serializa un mensaje agregando versión y tipo.
static func encode(type: String, payload: Dictionary = {}) -> String:
	var msg := payload.duplicate(true)
	msg["v"] = VERSION
	msg["type"] = type
	return JSON.stringify(msg)


## Parsea un mensaje crudo. Devuelve {} si es inválido (nunca lanza error).
## No valida la versión: eso lo decide quien recibe (ver is_supported_version).
static func decode(raw: String) -> Dictionary:
	if raw.is_empty() or raw.to_utf8_buffer().size() > MAX_MESSAGE_BYTES:
		return {}
	var json := JSON.new()  # Instancia (no parse_string) para no ensuciar el log con basura ajena.
	if json.parse(raw) != OK or typeof(json.data) != TYPE_DICTIONARY:
		return {}
	var msg: Dictionary = json.data
	if typeof(msg.get("type")) != TYPE_STRING:
		return {}
	if not _is_number(msg.get("v")):
		return {}
	return msg


static func is_supported_version(msg: Dictionary) -> bool:
	return _is_number(msg.get("v")) and int(msg["v"]) == VERSION


## Genera un código de sala de 4 caracteres con aleatoriedad criptográfica.
static func generate_room_code() -> String:
	var bytes := Crypto.new().generate_random_bytes(ROOM_CODE_LENGTH)
	var code := ""
	for b in bytes:
		code += ROOM_CODE_ALPHABET[b % ROOM_CODE_ALPHABET.length()]
	return code


static func is_valid_room_code(code: Variant) -> bool:
	if typeof(code) != TYPE_STRING or (code as String).length() != ROOM_CODE_LENGTH:
		return false
	for ch in (code as String):
		if not ROOM_CODE_ALPHABET.contains(ch):
			return false
	return true


## Normaliza lo que el usuario tipea como código: mayúsculas y sin espacios.
static func normalize_room_code(raw: String) -> String:
	return raw.strip_edges().to_upper().replace(" ", "")


## Token de sesión: permite reconectarse al mismo lugar sin volver a unirse.
static func generate_token() -> String:
	return Crypto.new().generate_random_bytes(TOKEN_BYTES).hex_encode()


static func is_valid_token(token: Variant) -> bool:
	if typeof(token) != TYPE_STRING or (token as String).length() != TOKEN_BYTES * 2:
		return false
	return (token as String).is_valid_hex_number(false)


## Limpia el apodo: sin caracteres de control, recortado a NAME_MAX_LENGTH.
## Devuelve "" si no queda nada utilizable.
## Importante: mostrar siempre los nombres en Label, nunca en RichTextLabel
## con BBCode activado (un nombre como "[img]..." podría inyectar contenido).
static func sanitize_name(raw: Variant) -> String:
	if typeof(raw) != TYPE_STRING:
		return ""
	var out := ""
	for ch in (raw as String).strip_edges():
		var code := ch.unicode_at(0)
		if code < 32 or (code >= 127 and code < 160):
			continue
		out += ch
		if out.length() >= NAME_MAX_LENGTH:
			break
	return out.strip_edges()


## Valida y normaliza un mensaje de input. Devuelve {} si es inválido.
## Resultado: { "seq": int, "axis": Vector2 (recortado a -1..1), "btn": int }
static func parse_input(msg: Dictionary) -> Dictionary:
	var seq: Variant = msg.get("seq")
	var axis: Variant = msg.get("axis", [0, 0])
	var btn: Variant = msg.get("btn", 0)
	if not _is_number(seq) or not _is_number(btn):
		return {}
	if typeof(axis) != TYPE_ARRAY or (axis as Array).size() != 2:
		return {}
	var ax: Variant = axis[0]
	var ay: Variant = axis[1]
	if not _is_number(ax) or not _is_number(ay):
		return {}
	var x := float(ax)
	var y := float(ay)
	if not (is_finite(x) and is_finite(y)):
		return {}
	var v := Vector2(clampf(x, -1.0, 1.0), clampf(y, -1.0, 1.0))
	return {
		"seq": int(seq),
		"axis": v.limit_length(1.0) if v.length() > 1.0 else v,
		"btn": int(btn) & BTN_MASK,
	}


## Valida y normaliza un mensaje "standing" (host -> control). El control
## tampoco confía a ciegas: tipos incorrectos, NaN o campos faltantes
## devuelven {}; los números fuera de rango se recortan.
## Resultado: { "round", "total_rounds", "place", "points", "total", "rank",
##   "players": int, "final": bool }
## place = puesto en esta ronda (0 = sin puesto: no la jugó o es el podio
## final); rank = puesto en la tabla general.
static func parse_standing(msg: Dictionary) -> Dictionary:
	var limits := {
		"round": [0, MAX_ROUNDS],
		"total_rounds": [0, MAX_ROUNDS],
		"place": [0, MAX_PLAYERS],
		"points": [0, MAX_STANDING_POINTS],
		"total": [0, MAX_STANDING_POINTS],
		"rank": [1, MAX_PLAYERS],
		"players": [1, MAX_PLAYERS],
	}
	var out := {}
	for key: String in limits:
		var value: Variant = msg.get(key)
		if not _is_number(value) or not is_finite(float(value)):
			return {}
		# Se recorta como float antes de convertir: int() de 1e300 no es confiable.
		out[key] = int(clampf(float(value), limits[key][0], limits[key][1]))
	if typeof(msg.get("final")) != TYPE_BOOL:
		return {}
	out["final"] = msg["final"]
	# Coherencia mínima: "Ronda 3/2" o "vas 4° de 2" no tienen sentido.
	out["total_rounds"] = maxi(out.total_rounds, out.round)
	out["players"] = maxi(out.players, maxi(out.rank, out.place))
	return out


## Valida un mensaje "feedback". Devuelve el tipo o "" si es inválido.
static func parse_feedback(msg: Dictionary) -> String:
	var kind: Variant = msg.get("kind")
	if typeof(kind) != TYPE_STRING or not (kind as String) in FEEDBACK_KINDS:
		return ""
	return kind


static func player_color(slot: int) -> Color:
	return PLAYER_COLORS[clampi(slot, 0, PLAYER_COLORS.size() - 1)]


static func _is_number(value: Variant) -> bool:
	return typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT
