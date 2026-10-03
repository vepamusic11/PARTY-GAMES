@tool
extends EditorExportPlugin
## Deja el APK de Android listo para Google TV / Android TV, además de
## celulares (un solo APK para los dos: `app/boot.gd` decide el modo).
##
## Godot 4.4 ya agrega la categoría LEANBACK_LAUNCHER (opción del preset
## `package/show_in_android_tv`, que exige *Use Gradle Build*), pero no tiene
## opción para el resto. Este plugin completa lo que falta:
##
##   1. Manifiesto (por la API de plugins, en el manifiesto que genera Godot):
##      - `android.hardware.touchscreen` no requerido: una TV no tiene
##        pantalla táctil y sin esto Google Play/la TV la considera no apta.
##      - `android.software.leanback` no requerido: la misma app sirve en
##        celulares (que no tienen leanback).
##      - `android.hardware.wifi` no requerido: hay TVs solo con cable de red.
##   2. Banner de 320×180 (`android:banner`): es la tarjeta de la app en la
##      fila de apps de la TV. Se copia `assets/brand/android/banner_320x180.png`
##      (lo genera `tools/make_android_icons.gd`) a `res/drawable-xhdpi/` del
##      proyecto Gradle y se agrega el atributo al `<application>` del
##      manifiesto de la plantilla (`android/build/AndroidManifest.xml`).
##      El atributo no se puede pedir por la API de plugins (solo agrega
##      elementos, no atributos), por eso se edita ese archivo.
##
## Cuándo corre: al exportar con Gradle, después de que Godot instala la
## plantilla (`--install-android-build-template` o Proyecto → Instalar
## plantilla de compilación de Android) y antes de que arranque Gradle. Es
## idempotente: se puede exportar mil veces. La carpeta `android/` no se
## versiona (.gitignore): se regenera en cada máquina y en la CI.
##
## Sin Gradle (APK armado desde la plantilla precompilada) no hace nada: en
## ese modo Godot no permite cambiar el manifiesto.

const BANNER_SRC := "res://assets/brand/android/banner_320x180.png"
const BANNER_RES_DIR := "res/drawable-xhdpi"
const BANNER_ATTR := "android:banner=\"@drawable/banner\""
const DEFAULT_BUILD_DIR := "res://android/build"

const MANIFEST_FEATURES := """
    <uses-feature android:name="android.hardware.touchscreen" android:required="false" />
    <uses-feature android:name="android.software.leanback" android:required="false" />
    <uses-feature android:name="android.hardware.wifi" android:required="false" />
"""


func _get_name() -> String:
	return "PartyGameAndroidTv"


func _supports_platform(platform: EditorExportPlatform) -> bool:
	return platform != null and platform.get_os_name() == "Android"


func _get_android_manifest_element_contents(_platform: EditorExportPlatform, _debug: bool) -> String:
	return MANIFEST_FEATURES


func _export_begin(features: PackedStringArray, _is_debug: bool, _path: String, _flags: int) -> void:
	if not features.has("android") or not bool(get_option("gradle_build/use_gradle_build")):
		return
	var build_dir := _build_dir()
	if not FileAccess.file_exists(build_dir.path_join("AndroidManifest.xml")):
		# Exportar un .pck/.zip suelto no instala la plantilla: no hay nada que tocar.
		return
	var ok := _copy_banner(build_dir) and _patch_manifest(build_dir.path_join("AndroidManifest.xml"))
	if ok:
		print("Android TV: banner y manifiesto listos en ", build_dir)
	else:
		push_error("Android TV: no se pudo preparar el banner; el APK no va a tener banner en la TV.")


## Misma regla que Godot: `gradle_build/gradle_build_directory` + "/build".
func _build_dir() -> String:
	var custom := str(get_option("gradle_build/gradle_build_directory")).strip_edges()
	return DEFAULT_BUILD_DIR if custom.is_empty() else custom.path_join("build")


func _copy_banner(build_dir: String) -> bool:
	var bytes := FileAccess.get_file_as_bytes(BANNER_SRC)
	if bytes.is_empty():
		push_error("Android TV: falta %s (generalo con tools/make_android_icons.gd)." % BANNER_SRC)
		return false
	var dir := build_dir.path_join(BANNER_RES_DIR)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	var f := FileAccess.open(dir.path_join("banner.png"), FileAccess.WRITE)
	if f == null:
		push_error("Android TV: no se pudo escribir el banner en %s." % dir)
		return false
	f.store_buffer(bytes)
	return true


## Agrega `android:banner` al `<application>` de la plantilla (una sola vez).
func _patch_manifest(manifest_path: String) -> bool:
	var text := FileAccess.get_file_as_string(manifest_path)
	if text.is_empty():
		return false
	if text.contains(BANNER_ATTR):
		return true
	var at := text.find("<application")
	if at < 0:
		push_error("Android TV: %s no tiene <application>." % manifest_path)
		return false
	var cut := at + "<application".length()
	text = text.substr(0, cut) + "\n        " + BANNER_ATTR + text.substr(cut)
	var f := FileAccess.open(manifest_path, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(text)
	return true
