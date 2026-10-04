extends SceneTree
## Genera `host/network/web_bundle.gd` con los archivos del control web
## (`res://web/`) embebidos en base64. Es el respaldo del servidor HTTP
## (WebControllerServer) para los exports: un script siempre viaja en el APK,
## mientras que `web/*` depende del `include_filter` del preset y de que
## Godot no importe ni deje afuera ningún archivo. Ver ADR 0022.
##
##   godot --headless --path . -s res://tools/build_web_bundle.gd
##
## Correrlo después de cada cambio en `web/`. El test `test_web_bundle_in_sync`
## falla si el bundle quedó viejo (y dice este comando).

const WEB_DIR := "res://web/"
const OUT_PATH := "res://host/network/web_bundle.gd"
const CHUNK := 120  ## Caracteres de base64 por línea (líneas cortas: el parser y git contentos).


func _initialize() -> void:
	var names := list_files()
	if names.is_empty():
		printerr("No hay archivos en %s" % WEB_DIR)
		quit(1)
		return
	var out := FileAccess.open(OUT_PATH, FileAccess.WRITE)
	if out == null:
		printerr("No se pudo escribir %s" % OUT_PATH)
		quit(1)
		return
	out.store_string(render(names))
	out.close()
	var total := 0
	for n in names:
		total += FileAccess.get_file_as_bytes(WEB_DIR + n).size()
	print("Bundle: %d archivos, %d bytes -> %s" % [names.size(), total, ProjectSettings.globalize_path(OUT_PATH)])
	quit(0)


## Archivos de WEB_DIR que se sirven (sin los .import/.uid que pudiera crear
## el editor), ordenados para que el bundle sea determinista.
static func list_files() -> PackedStringArray:
	var names := PackedStringArray()
	for n in DirAccess.get_files_at(WEB_DIR):
		if n.ends_with(".import") or n.ends_with(".uid") or n.begins_with("."):
			continue
		names.append(n)
	names.sort()
	return names


static func render(names: PackedStringArray) -> String:
	var lines: PackedStringArray = [
		"class_name WebBundle",
		"extends RefCounted",
		"## GENERADO por tools/build_web_bundle.gd a partir de res://web/ — no editar a mano.",
		"## Copia embebida (base64) de los archivos del control web, para que estén",
		"## en cualquier export aunque el preset no incluya `web/*` (ADR 0022).",
		"## Regenerar: godot --headless --path . -s res://tools/build_web_bundle.gd",
		"",
		"const FILES := {",
	]
	for n in names:
		var b64 := Marshalls.raw_to_base64(FileAccess.get_file_as_bytes(WEB_DIR + n))
		lines.append("\t\"%s\": [" % n)
		var i := 0
		while i < b64.length():
			lines.append("\t\t\"%s\"," % b64.substr(i, CHUNK))
			i += CHUNK
		lines.append("\t],")
	lines.append("}")
	lines.append("")
	lines.append("")
	lines.append("## Contenido del archivo `name` o PackedByteArray vacío si no existe.")
	lines.append("static func get_file(name: String) -> PackedByteArray:")
	lines.append("\tif not FILES.has(name):")
	lines.append("\t\treturn PackedByteArray()")
	lines.append("\treturn Marshalls.base64_to_raw(\"\".join(FILES[name]))")
	lines.append("")
	lines.append("")
	lines.append("static func names() -> Array:")
	lines.append("\treturn FILES.keys()")
	lines.append("")
	return "\n".join(lines)
