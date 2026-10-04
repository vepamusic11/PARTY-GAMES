@tool
extends EditorPlugin
## Plugin solo del editor: registra `android_tv_export.gd`, que deja el APK
## listo para aparecer en el launcher de Google TV / Android TV. No agrega
## nada al juego en sí (el script no se exporta: ver `exclude_filter`).

var _export_plugin: EditorExportPlugin


func _enter_tree() -> void:
	_export_plugin = preload("res://addons/android_tv/android_tv_export.gd").new()
	add_export_plugin(_export_plugin)


func _exit_tree() -> void:
	if _export_plugin != null:
		remove_export_plugin(_export_plugin)
		_export_plugin = null
