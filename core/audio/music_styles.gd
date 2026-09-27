class_name MusicStyles
extends RefCounted
## Estilos de música de la TV (ADR 0017): qué suena en cada pantalla según el
## estilo que se elige en la pausa ("◀ Estilo: Fiesta ▶"). Se guarda en el
## archivo de ajustes de la TV (`[audio] music_style`).
##
## Cada estilo cubre las mismas seis *pistas* (una por pantalla o energía de
## juego, ver Music.GAME_TRACKS): lobby, game_calm, game_play, game_action,
## summary y podium. Una pista sale de una de tres fuentes:
##   - archivo  -> un .ogg de assets/audio/music/ (con su licencia al lado);
##   - generada -> la compone y sintetiza MusicGen al arrancar, en un hilo:
##                 música 100 % propia, sin archivo ni licencia;
##   - respaldo -> si el estilo no tiene esa pista (o falta el archivo),
##                 usa la del estilo `fallback`.
## Ejemplo: "PARTY-GAME" (los temas del dueño) tiene Breakpoint Rush para los
## juegos de acción y un lugar para el tema del lobby; el resto de las
## pantallas suenan con "Fiesta" hasta que haya más temas propios.
##
## "Sin música" no tiene pistas ni respaldo: la TV queda en silencio (los
## efectos siguen sonando).

const ORIGINAL := "original"
const FIESTA := "fiesta"
const RETRO := "retro"
const RELAJADO := "relajado"
const LATINO := "latino"
const NONE := "none"

## Orden del selector (◀ ▶). El primero es el estilo por defecto.
const ORDER: Array[String] = [ORIGINAL, FIESTA, LATINO, RELAJADO, RETRO, NONE]
const DEFAULT := ORIGINAL

## Las pistas que tiene que cubrir cada estilo (mismos nombres que Music).
const TRACK_NAMES: Array[String] = ["lobby", "game_calm", "game_play", "game_action", "summary", "podium"]

const MUSIC_DIR := "res://assets/audio/music/"

## name: lo que se ve en la TV. files: pista -> archivo. generated: MusicGen
## compone todas las pistas. fallback: estilo que cubre lo que falta.
const STYLES := {
	ORIGINAL: {
		"name": "PARTY-GAME",
		"files": {
			# Tema del dueño para el lobby: todavía no está. Al copiar el .ogg
			# (preparado con tools/audio/prepare_audio.py) suena solo.
			"lobby": MUSIC_DIR + "original/lobby.ogg",
			"game_action": MUSIC_DIR + "original/breakpoint_rush.ogg",
		},
		"fallback": FIESTA,
	},
	FIESTA: {"name": "Fiesta", "generated": true},
	LATINO: {"name": "Latino", "generated": true},
	# Cuatro temas para seis pantallas: el resumen repite el de juegos
	# tranquilos y el podio el de juegos movidos (presupuesto del APK).
	RELAJADO: {
		"name": "Relajado",
		"files": {
			"lobby": MUSIC_DIR + "relajado/lobby.ogg",
			"game_calm": MUSIC_DIR + "relajado/calm.ogg",
			"game_play": MUSIC_DIR + "relajado/groove.ogg",
			"game_action": MUSIC_DIR + "relajado/action.ogg",
			"summary": MUSIC_DIR + "relajado/calm.ogg",
			"podium": MUSIC_DIR + "relajado/groove.ogg",
		},
	},
	RETRO: {
		"name": "Retro",
		"files": {
			"lobby": MUSIC_DIR + "lobby.ogg",
			"game_calm": MUSIC_DIR + "game_calm.ogg",
			"game_play": MUSIC_DIR + "game_play.ogg",
			"game_action": MUSIC_DIR + "game_action.ogg",
			"summary": MUSIC_DIR + "summary.ogg",
			"podium": MUSIC_DIR + "podium.ogg",
		},
	},
	NONE: {"name": "Sin música"},
}

## Estilo elegido. Cambiarlo con Music.set_style (aplica y guarda).
static var style := DEFAULT
## Archivo de ajustes que usó load_prefs: save_prefs escribe ahí.
static var prefs_path := ""


static func is_valid(id: Variant) -> bool:
	return id is String and STYLES.has(id)


## Nombre para la TV ("Fiesta", "Sin música"…).
static func display_name(id: String) -> String:
	return str(STYLES.get(id, {}).get("name", id))


static func index_of(id: String) -> int:
	return maxi(0, ORDER.find(id))


## De dónde sale `track` en el estilo `id`, siguiendo los respaldos:
##   {"file": "res://…ogg"}                       archivo que existe
##   {"generated": "fiesta"}                      pista compuesta por MusicGen
##   {}                                           silencio ("Sin música")
## `exists` permite a los tests simular archivos que faltan.
static func resolve(id: String, track: String, exists: Callable = Callable()) -> Dictionary:
	var seen := {}
	var current := id if STYLES.has(id) else DEFAULT
	while not current.is_empty() and not seen.has(current):
		seen[current] = true
		var st: Dictionary = STYLES[current]
		var path: String = st.get("files", {}).get(track, "")
		if not path.is_empty():
			var found: bool = exists.call(path) if exists.is_valid() else ResourceLoader.exists(path)
			if found:
				return {"file": path}
		if st.get("generated", false) and MusicGen.has_track(current, track):
			return {"generated": current}
		current = str(st.get("fallback", ""))
	return {}


## Estilos que MusicGen tiene que componer para cubrir `id` (su propio y el
## de respaldo, si alguna pista cae ahí).
static func generated_needs(id: String) -> Array[String]:
	var out: Array[String] = []
	for track in TRACK_NAMES:
		var src := resolve(id, track)
		if src.has("generated") and not out.has(str(src.generated)):
			out.append(str(src.generated))
	return out


## Lee el estilo guardado; un valor desconocido o de otro tipo se ignora.
static func load_prefs(path: String) -> void:
	prefs_path = path
	var cfg := ConfigFile.new()
	if cfg.load(path) != OK:
		return
	var v: Variant = cfg.get_value("audio", "music_style", DEFAULT)
	if is_valid(v):
		style = v


## Guarda el estilo sin pisar el resto del archivo (volúmenes, apodo…).
static func save_prefs(path: String = prefs_path) -> void:
	if path.is_empty():
		return
	var cfg := ConfigFile.new()
	cfg.load(path)
	cfg.set_value("audio", "music_style", style)
	cfg.save(path)
