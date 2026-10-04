class_name MascotDiskCache
extends RefCounted
## Caché en disco de las hojas de mascotas horneadas (ADR 0012, ADR 0023):
## cada trabajo de Mascot3DBaker deja una hoja (una textura con varias poses
## de una apariencia a un tamaño); MascotAtlas la guarda en
## `user://mascot_cache/` y, la próxima vez que se abre la app, la lee del
## disco (en un hilo, unos ms) en vez de volver a hornearla (render 3D).
## Ejemplo: el lobby con 4 jugadores pasa de ~10 s de horneado en una TV
## lenta a leer ~12 archivos chicos.
##
## Conceptos (los mismos de MusicCache y Board25DBaker):
## - *Firma*: un hash de todo lo que decide cómo sale una mascota (el código
##   de Mascot3D, sus mallas, el baker y MascotAtlas, los dos shaders, los
##   colores MASCOT_* de UiTheme, las constantes de PlayerAvatar que usa,
##   Props3D.VERSION, VERSION de acá y la versión del motor). Un archivo con
##   otra firma es de una versión vieja: se borra.
## - *Tope*: todos los archivos juntos no pasan de max_bytes; al guardar se
##   borran los más viejos (por fecha de escritura).
## - *Nunca rompe*: un archivo corto, con otro formato, con tamaños imposibles
##   o con una imagen que no se puede leer se descarta (y se borra) sin
##   errores; la mascota se hornea como siempre.
##
## Formato (little endian): "PGMA", versión del formato (u32), firma (u32 de
## largo + ASCII), color RGBA32 (u32), estilo (u32), tamaño (u32, índice de
## MascotAtlas.TIERS_U), celda ancho/alto (u32), cantidad de poses (u32) y
## por cada una: nombre (u32 de largo + ASCII) y su rectángulo x, y, ancho,
## alto (u32); al final la imagen en PNG (u32 de largo + bytes).
##
## save_sheet/load_sheet/scan corren en hilos (WorkerThreadPool): solo usan
## FileAccess, DirAccess e Image. signature() se calcula en el hilo principal.

const DEFAULT_DIR := "user://mascot_cache/"
const MAGIC := "PGMA"
const FORMAT_VERSION := 1
const EXT := ".mpose"
## Subirla a mano si cambia algo del horneado que la firma no ve.
const VERSION := 1
## Tope de todos los archivos (bytes). Una competencia con 4 jugadores deja
## ~20–30 MB (PNG); el tope deja lugar para cambiar de mascota sin borrar.
const MAX_BYTES := 64 * 1024 * 1024
## Límites de cordura al leer (un archivo fuera de esto no es nuestro).
const MAX_POSES := 64
const MAX_NAME := 48
const MAX_SIDE := 4096

## Código que define cómo sale una mascota (se hashea el archivo; en el APK
## los scripts van como .gdc y se hashea ese).
const SOURCES: Array[String] = [
	"res://core/mascot3d/mascot_3d.gd",
	"res://core/mascot3d/mascot3d_meshes.gd",
	"res://core/mascot3d/mascot3d_baker.gd",
	"res://core/mascot3d/mascot_atlas.gd",
	"res://core/ui/widgets/player_avatar.gd",
]
const SHADERS: Array[String] = [
	"res://core/mascot3d/toy_plastic.gdshader",
	"res://core/mascot3d/ink_outline.gdshader",
]

## Carpeta (los tests usan otra para no tocar la de la TV).
static var dir := DEFAULT_DIR
static var max_bytes := MAX_BYTES
## false: ni lee ni escribe (para comparar o si el disco falla).
static var enabled := true
static var _signature := ""


## Firma de hoy (se calcula una vez por proceso).
static func signature() -> String:
	if _signature.is_empty():
		_signature = compute_signature(signature_parts())
	return _signature


## Lo que entra en la firma (separado para poder probarlo).
static func signature_parts() -> Array:
	var files := []
	for path in SOURCES:
		files.append(_file_md5(path))
	for path in SHADERS:
		var sh := load(path) as Shader
		files.append(sh.code.md5_text() if sh != null else "")
	var theme := {}
	var theme_consts: Dictionary = (load("res://core/ui/ui_theme.gd") as Script).get_script_constant_map()
	for k: String in theme_consts:
		if k.begins_with("MASCOT_") or k in ["ACCENT", "DANGER", "INK", "LEAF", "PAPER", "SKY_BOTTOM"]:
			theme[k] = theme_consts[k]
	return [VERSION, FORMAT_VERSION, Props3D.VERSION, Engine.get_version_info().get("hash", ""),
		files, theme, MascotAtlas.TIERS_U, Mascot3DBaker.ATLAS_CELL, Mascot3DBaker.ATLAS_FEET,
		Mascot3DBaker.SUPERSAMPLE, Mascot3DBaker.PITCH_DEG, Mascot3DBaker.CAM_DISTANCE]


static func compute_signature(parts: Array) -> String:
	return var_to_str(parts).md5_text()


## Olvida la firma calculada (tests).
static func reset_signature() -> void:
	_signature = ""


## md5 del archivo, o del .gdc del APK (scripts exportados como tokens).
static func _file_md5(path: String) -> String:
	for p in [path, path + "c", path.get_basename() + ".gdc"]:
		if FileAccess.file_exists(p):
			return FileAccess.get_md5(p)
	return ""


## Nombre del archivo de una hoja: apariencia, tamaño y las poses que trae.
static func path_for(col_rgba32: int, style: int, tier: int, poses: Array) -> String:
	var names := []
	for p: Variant in poses:
		names.append(str(p))
	names.sort()
	return dir.path_join("m%08x_%d_%d_%s%s" % [col_rgba32 & 0xffffffff, style, tier,
		"|".join(names).md5_text().substr(0, 12), EXT])


## Guarda una hoja. `regions`: pose -> Rect2 (px) dentro de `img` (RGBA8).
## Escribe a un temporal y lo renombra (un corte a mitad no deja un archivo
## roto con el nombre bueno) y después recorta la carpeta a max_bytes.
## Devuelve la ruta o "" si no se guardó.
static func save_sheet(sig: String, col_rgba32: int, style: int, tier: int, cell: Vector2i,
		regions: Dictionary, img: Image) -> String:
	if not enabled or sig.is_empty() or img == null or img.is_empty() or regions.is_empty() \
			or regions.size() > MAX_POSES or img.get_format() != Image.FORMAT_RGBA8:
		return ""
	var png := img.save_png_to_buffer()
	if png.is_empty():
		return ""
	var names: Array = regions.keys()
	var size := _header_size(sig, names) + 4 + png.size()
	if size > max_bytes:
		return ""
	if not DirAccess.dir_exists_absolute(dir):
		DirAccess.make_dir_recursive_absolute(dir)
	var path := path_for(col_rgba32, style, tier, names)
	var tmp := path + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		return ""
	f.store_buffer(MAGIC.to_ascii_buffer())
	f.store_32(FORMAT_VERSION)
	_store_str(f, sig)
	f.store_32(col_rgba32 & 0xffffffff)
	f.store_32(style)
	f.store_32(tier)
	f.store_32(cell.x)
	f.store_32(cell.y)
	f.store_32(names.size())
	for n: Variant in names:
		var r: Rect2 = regions[n]
		_store_str(f, str(n))
		f.store_32(int(r.position.x))
		f.store_32(int(r.position.y))
		f.store_32(int(r.size.x))
		f.store_32(int(r.size.y))
	f.store_32(png.size())
	f.store_buffer(png)
	var ok := f.get_error() == OK
	f.close()
	if not ok or DirAccess.rename_absolute(tmp, path) != OK:
		DirAccess.remove_absolute(tmp)
		return ""
	trim(path)
	return path


## Encabezado de una hoja (sin la imagen): {"path", "color", "style",
## "tier", "cell", "regions"} o {} si no es válida con esta firma (en ese
## caso se borra).
static func read_header(path: String, sig: String) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var h := _read_header(f, sig)
	var ok := not h.is_empty() and f.get_length() == f.get_position() + int(h.png_size)
	f.close()
	if not ok:
		DirAccess.remove_absolute(path)
		return {}
	h.erase("png_size")
	h["path"] = path
	return h


## Hoja completa: el encabezado más "image" (RGBA8). {} si falta, es de otra
## firma o está rota (se borra).
static func load_sheet(path: String, sig: String) -> Dictionary:
	if not enabled or not FileAccess.file_exists(path):
		return {}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var h := _read_header(f, sig)
	var img: Image = null
	if not h.is_empty() and f.get_length() == f.get_position() + int(h.png_size):
		var png := f.get_buffer(int(h.png_size))
		if png.size() == int(h.png_size):
			img = Image.new()
			if img.load_png_from_buffer(png) != OK or img.is_empty():
				img = null
	f.close()
	if img != null and img.get_format() != Image.FORMAT_RGBA8:
		img.convert(Image.FORMAT_RGBA8)
	if img != null:
		var bounds := Rect2(Vector2.ZERO, Vector2(img.get_size()))
		for r: Rect2 in (h.regions as Dictionary).values():
			if not bounds.encloses(r):
				img = null
				break
	if img == null:
		DirAccess.remove_absolute(path)
		return {}
	h.erase("png_size")
	h["path"] = path
	h["image"] = img
	return h


## Encabezados de todas las hojas válidas (las rotas o viejas se borran, y
## los temporales que dejó una escritura cortada también).
static func scan(sig: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if not enabled:
		return out
	var d := DirAccess.open(dir)
	if d == null:
		return out
	for name in d.get_files():
		var path := dir.path_join(name)
		if name.ends_with(EXT + ".tmp"):
			DirAccess.remove_absolute(path)
		elif name.ends_with(EXT):
			var h := read_header(path, sig)
			if not h.is_empty():
				out.append(h)
	return out


## Borra los archivos más viejos hasta que todo entre en max_bytes (nunca
## `keep`, el que se acaba de guardar).
static func trim(keep: String = "") -> void:
	var files := list_files()
	var total := 0
	for info: Dictionary in files:
		total += int(info.size)
	if total <= max_bytes:
		return
	files.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.time) < int(b.time))
	for info: Dictionary in files:
		if total <= max_bytes:
			break
		if str(info.path) == keep:
			continue
		DirAccess.remove_absolute(str(info.path))
		total -= int(info.size)


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
	var d := DirAccess.open(dir)
	if d == null:
		return
	for name in d.get_files():
		if name.ends_with(EXT) or name.ends_with(EXT + ".tmp"):
			DirAccess.remove_absolute(dir.path_join(name))


# --- Interno ------------------------------------------------------------------------

static func _store_str(f: FileAccess, s: String) -> void:
	var b := s.to_ascii_buffer()
	f.store_32(b.size())
	f.store_buffer(b)


static func _read_str(f: FileAccess, max_len: int) -> Variant:
	if f.get_position() + 4 > f.get_length():
		return null
	var n := f.get_32()
	if n > max_len or f.get_position() + n > f.get_length():
		return null
	var b := f.get_buffer(n)
	return b.get_string_from_ascii() if b.size() == n else null


static func _header_size(sig: String, names: Array) -> int:
	var n := 4 + 4 + 4 + sig.length() + 4 * 6
	for p: Variant in names:
		n += 4 + str(p).length() + 16
	return n


## Lee y valida el encabezado; deja el archivo justo antes del PNG. {} si
## algo no cierra. "png_size": bytes del PNG.
static func _read_header(f: FileAccess, sig: String) -> Dictionary:
	var length := f.get_length()
	if length < 4 + 4 + 4 + sig.length() + 4 * 7:
		return {}
	if f.get_buffer(4).get_string_from_ascii() != MAGIC or f.get_32() != FORMAT_VERSION:
		return {}
	var s: Variant = _read_str(f, 128)
	if s == null or s != sig:
		return {}
	if f.get_position() + 4 * 6 > length:
		return {}
	var col := f.get_32()
	var style := f.get_32()
	var tier := f.get_32()
	var cell := Vector2i(f.get_32(), f.get_32())
	var count := f.get_32()
	if style > 7 or tier >= MascotAtlas.TIERS_U.size() or cell.x < 1 or cell.y < 1 \
			or cell.x > MAX_SIDE or cell.y > MAX_SIDE or count < 1 or count > MAX_POSES:
		return {}
	var regions := {}
	for i in count:
		var name: Variant = _read_str(f, MAX_NAME)
		if name == null or f.get_position() + 16 > length:
			return {}
		var r := Rect2(f.get_32(), f.get_32(), f.get_32(), f.get_32())
		if Vector2i(r.size) != cell or r.end.x > MAX_SIDE or r.end.y > MAX_SIDE:
			return {}
		regions[name] = r
	if f.get_position() + 4 > length:
		return {}
	var png_size := f.get_32()
	if png_size < 8:
		return {}
	return {"color": col, "style": style, "tier": tier, "cell": cell, "regions": regions, "png_size": png_size}
