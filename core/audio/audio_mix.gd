class_name AudioMix
extends RefCounted
## Mezcla de la TV: buses de audio, volúmenes y silencio (ADR 0015).
##
## Concepto: *bus*. Es un canal por el que pasa un grupo de sonidos antes de
## llegar al parlante, con su propio volumen. Así se puede bajar la música
## sin tocar los efectos:
##   Master  -> todo (lo apaga el ajuste "Sonido: No")
##     Music -> la música (core/audio/music.gd)
##     SFX   -> los efectos (core/audio/sfx.gd)
## Se crean por código la primera vez que alguien los pide: no hay
## default_bus_layout.tres que mantener a mano.
##
## Volúmenes en escala lineal 0..1 (lo que ve la persona: 0 %–100 %); el bus
## usa decibeles. Se guardan en la sección [audio] del archivo de ajustes,
## junto a lo que guarda Sfx (muted, vibration).

const BUS_MASTER := "Master"
const BUS_MUSIC := "Music"
const BUS_SFX := "SFX"

## Volumen inicial. La música va por debajo de los efectos: acompaña.
const DEFAULT_VOLUMES := {BUS_MUSIC: 0.7, BUS_SFX: 1.0}
## Pasos del ajuste en la pausa (◀ ▶): 0 %, 10 % … 100 %.
const STEPS := 10

## Archivo de ajustes que usó load_prefs: save_prefs escribe ahí.
static var prefs_path := ""


## Crea los buses Music y SFX si no existen. Idempotente y barato.
static func ensure_buses() -> void:
	for bus_name: String in [BUS_MUSIC, BUS_SFX]:
		if AudioServer.get_bus_index(bus_name) != -1:
			continue
		var idx := AudioServer.bus_count
		AudioServer.add_bus(idx)
		AudioServer.set_bus_name(idx, bus_name)
		AudioServer.set_bus_send(idx, BUS_MASTER)
		_apply_volume(bus_name, float(DEFAULT_VOLUMES[bus_name]))


## Nombre del bus de efectos, creando los buses si hace falta (lo usa Sfx).
static func sfx_bus() -> StringName:
	ensure_buses()
	return BUS_SFX


static func music_bus() -> StringName:
	ensure_buses()
	return BUS_MUSIC


## Volumen lineal 0..1 de un bus (Music o SFX).
static func get_volume(bus_name: String) -> float:
	ensure_buses()
	var idx := AudioServer.get_bus_index(bus_name)
	if idx == -1:
		return 0.0
	if AudioServer.is_bus_mute(idx):
		return 0.0
	return clampf(db_to_linear(AudioServer.get_bus_volume_db(idx)), 0.0, 1.0)


static func set_volume(bus_name: String, linear: float) -> void:
	ensure_buses()
	if not DEFAULT_VOLUMES.has(bus_name):
		return
	_apply_volume(bus_name, clampf(linear, 0.0, 1.0))


## "Sonido: No" de la TV: silencia todo (música y efectos) sin perder los
## volúmenes elegidos. La música además se pausa (ver Music.sync_mute).
static func set_muted(muted: bool) -> void:
	AudioServer.set_bus_mute(AudioServer.get_bus_index(BUS_MASTER), muted)


static func is_muted() -> bool:
	return AudioServer.is_bus_mute(AudioServer.get_bus_index(BUS_MASTER))


## Lee los volúmenes guardados (valores fuera de rango se recortan).
static func load_prefs(path: String) -> void:
	prefs_path = path
	ensure_buses()
	var cfg := ConfigFile.new()
	if cfg.load(path) != OK:
		return
	for bus_name: String in DEFAULT_VOLUMES:
		var v: Variant = cfg.get_value("audio", _key(bus_name), DEFAULT_VOLUMES[bus_name])
		if v is float or v is int:
			set_volume(bus_name, float(v))


## Guarda los volúmenes sin pisar el resto del archivo (apodo, muted…).
static func save_prefs(path: String = prefs_path) -> void:
	if path.is_empty():
		return
	var cfg := ConfigFile.new()
	cfg.load(path)
	for bus_name: String in DEFAULT_VOLUMES:
		cfg.set_value("audio", _key(bus_name), snappedf(get_volume(bus_name), 0.01))
	cfg.save(path)


static func _key(bus_name: String) -> String:
	return "%s_volume" % bus_name.to_lower()


## 0 = bus en silencio (mute), no -80 dB: el mezclador ni lo procesa.
static func _apply_volume(bus_name: String, linear: float) -> void:
	var idx := AudioServer.get_bus_index(bus_name)
	AudioServer.set_bus_mute(idx, linear <= 0.001)
	AudioServer.set_bus_volume_db(idx, linear_to_db(maxf(linear, 0.001)))
