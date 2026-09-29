class_name MusicCache
extends RefCounted
## Caché en disco de las pistas que compone MusicGen (ADR 0017): la primera
## vez que la TV compone "Fiesta / lobby" la guarda en
## `user://music_cache/fiesta_lobby.pcm`; desde el arranque siguiente la lee
## (~10–30 ms) en vez de componerla (~10–20 s en una TV lenta).
##
## Conceptos:
## - *Firma de la receta*: un hash de todo lo que decide cómo suena la pista
##   (su receta, las tablas compartidas de MusicGen, la frecuencia de
##   muestreo, los compases y MusicGen.GEN_VERSION, que se sube a mano al
##   cambiar el código del sintetizador). Si al leer la firma no coincide,
##   el archivo es de una versión vieja: se borra y se compone de nuevo.
## - *Límite de tamaño*: todos los archivos juntos no pasan de max_bytes;
##   al guardar uno nuevo se borran los más viejos (por fecha de escritura).
##   Ejemplo: con 40 MB entran los dos estilos generados completos (~12
##   pistas de 2,6–3,7 MB).
## - *Nunca rompe*: un archivo corto, con otro formato o con tamaños
##   imposibles se descarta (y se borra) y la pista se compone como siempre.
##
## Formato (little endian): "PGMC", versión del formato (u32), largo de la
## firma (u32) + firma (ASCII), frecuencia (u32), cuadros (u32), y los datos
## PCM de 16 bits estéreo intercalados (cuadros × 4 bytes).
##
## Se llama desde el hilo de Music (WorkerThreadPool): solo usa FileAccess y
## DirAccess, nada del árbol de escena.

const DEFAULT_DIR := "user://music_cache/"
const MAGIC := "PGMC"
const FORMAT_VERSION := 1
const EXT := ".pcm"
## Tope de todos los archivos (bytes). Ver ADR 0017 ("Caché en disco").
const MAX_BYTES := 40 * 1024 * 1024
## Una pista más larga que esto (en segundos) no es nuestra: se descarta.
const MAX_SECONDS := 300.0

## Carpeta de la caché (los tests usan otra para no tocar la de la TV).
static var dir := DEFAULT_DIR
static var max_bytes := MAX_BYTES
## false: ni lee ni escribe (para comparar o si el disco falla).
static var enabled := true


## Firma de lo que define la pista `style/track` con `bars` compases
## (< 1: MusicGen.BARS). Cambia si cambia la receta, una tabla compartida,
## la frecuencia, los compases o MusicGen.GEN_VERSION.
static func signature(style: String, track: String, bars: int = -1) -> String:
	if not MusicGen.has_track(style, track):
		return ""
	var b := MusicGen.BARS if bars < 1 else bars
	var parts := [MusicGen.GEN_VERSION, style, track, b, MusicGen.MIX_RATE, MusicGen.TARGET_RMS_DB,
		MusicGen.PEAK_MAX, MusicGen.LIMIT_KNEE, MusicGen.RECIPES[style][track], MusicGen.CHORDS, MusicGen.KITS,
		MusicGen.DRUM_TRIM, MusicGen.BASS, MusicGen.COMP, MusicGen.CELLS]
	return var_to_str(parts).md5_text()


## Ruta del archivo de una pista (nombres de receta: solo letras y "_").
static func path_for(style: String, track: String) -> String:
	return dir.path_join("%s_%s%s" % [style.validate_filename(), track.validate_filename(), EXT])


## La pista guardada, o null si no está, es de otra versión o está rota
## (en esos dos casos se borra el archivo).
static func load_track(style: String, track: String, bars: int = -1) -> AudioStreamWAV:
	if not enabled:
		return null
	var sig := signature(style, track, bars)
	var path := path_for(style, track)
	if sig.is_empty() or not FileAccess.file_exists(path):
		return null
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return null
	var stream := _read(f, sig)
	f.close()
	if stream == null:
		DirAccess.remove_absolute(path)
	return stream


## Guarda la pista (si la caché está activa y la pista es válida) y después
## recorta la carpeta a max_bytes. Devuelve true si quedó guardada.
static func save_track(style: String, track: String, stream: AudioStreamWAV, bars: int = -1) -> bool:
	var sig := signature(style, track, bars)
	if not enabled or sig.is_empty() or stream == null or not stream.stereo \
			or stream.format != AudioStreamWAV.FORMAT_16_BITS or stream.data.is_empty():
		return false
	var frames := stream.data.size() / 4
	var size := _header_size(sig) + frames * 4
	if size > max_bytes:
		return false
	if not DirAccess.dir_exists_absolute(dir):
		DirAccess.make_dir_recursive_absolute(dir)
	var path := path_for(style, track)
	# Se escribe a un temporal y se renombra: un corte de luz a mitad de la
	# escritura no deja un archivo a medias con el nombre bueno.
	var tmp := path + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		return false
	f.store_buffer(MAGIC.to_ascii_buffer())
	f.store_32(FORMAT_VERSION)
	f.store_32(sig.length())
	f.store_buffer(sig.to_ascii_buffer())
	f.store_32(int(stream.mix_rate))
	f.store_32(frames)
	f.store_buffer(stream.data.slice(0, frames * 4))
	var ok := f.get_error() == OK
	f.close()
	if not ok or DirAccess.rename_absolute(tmp, path) != OK:
		DirAccess.remove_absolute(tmp)
		return false
	trim(path)
	return true


## Borra los archivos más viejos hasta que todo entre en max_bytes (nunca
## `keep`, la que se acaba de guardar) y los temporales huérfanos.
static func trim(keep: String = "") -> void:
	var files := list_files()
	var total := 0
	for info: Dictionary in files:
		total += int(info.size)
	files.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.time) < int(b.time))
	for info: Dictionary in files:
		if total <= max_bytes:
			break
		if str(info.path) == keep:
			continue
		DirAccess.remove_absolute(str(info.path))
		total -= int(info.size)
	# Temporales de una escritura cortada (se escribe de a una pista por vez).
	var d := DirAccess.open(dir)
	if d != null:
		for name in d.get_files():
			if name.ends_with(EXT + ".tmp"):
				DirAccess.remove_absolute(dir.path_join(name))


## Archivos de la caché: [{"path", "size", "time"}].
static func list_files() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var d := DirAccess.open(dir)
	if d == null:
		return out
	for name in d.get_files():
		if not name.ends_with(EXT):
			continue
		var path := dir.path_join(name)
		var f := FileAccess.open(path, FileAccess.READ)
		if f == null:
			continue
		out.append({"path": path, "size": f.get_length(), "time": FileAccess.get_modified_time(path)})
		f.close()
	return out


## Bytes que ocupa la caché.
static func total_bytes() -> int:
	var total := 0
	for info: Dictionary in list_files():
		total += int(info.size)
	return total


## Borra toda la caché.
static func clear() -> void:
	for info: Dictionary in list_files():
		DirAccess.remove_absolute(str(info.path))


# --- Interno ------------------------------------------------------------------------

static func _header_size(sig: String) -> int:
	return 4 + 4 + 4 + sig.length() + 4 + 4


## Lee y valida todo; cualquier cosa rara -> null.
static func _read(f: FileAccess, sig: String) -> AudioStreamWAV:
	var length := f.get_length()
	if length < _header_size(sig):
		return null
	if f.get_buffer(4).get_string_from_ascii() != MAGIC or f.get_32() != FORMAT_VERSION:
		return null
	var sig_len := f.get_32()
	if sig_len != sig.length() or f.get_buffer(sig_len).get_string_from_ascii() != sig:
		return null
	var rate := f.get_32()
	var frames := f.get_32()
	if rate != MusicGen.MIX_RATE or frames <= 0 or frames > int(MAX_SECONDS * rate) \
			or length != _header_size(sig) + frames * 4:
		return null
	var data := f.get_buffer(frames * 4)
	if data.size() != frames * 4:
		return null
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = rate
	stream.stereo = true
	stream.data = data
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.loop_begin = 0
	stream.loop_end = frames
	return stream
