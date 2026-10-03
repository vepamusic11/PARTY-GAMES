class_name PhoneSettings
extends RefCounted
## Ajustes del celular que no son de sonido (esos los guarda Sfx en la
## sección [audio]). Viven en el mismo archivo local que el apodo
## (`user://settings.cfg`), sección [controller]:
##
##   lefty         zurdo: joystick a la derecha y botón a la izquierda
##   control_size  tamaño del control: 0 chico · 1 normal · 2 grande
##   dev_mode      modo desarrollador: muestra la latencia en milisegundos
##
## Lo que se lee del archivo se valida y recorta: un archivo editado a mano
## (o de una versión vieja) nunca rompe la app, cae en el valor por defecto.

const SECTION := "controller"
const SIZE_SMALL := 0
const SIZE_NORMAL := 1
const SIZE_LARGE := 2

var lefty := false
var control_size := SIZE_NORMAL
var dev_mode := false


## Escala del control según `control_size` (ver UiTheme.PHONE_CONTROL_SCALES).
func control_scale() -> float:
	return UiTheme.PHONE_CONTROL_SCALES[clampi(control_size, 0, UiTheme.PHONE_CONTROL_SCALES.size() - 1)]


func load_from(path: String) -> void:
	var cfg := ConfigFile.new()
	if cfg.load(path) != OK:
		return
	lefty = _as_bool(cfg.get_value(SECTION, "lefty", false))
	dev_mode = _as_bool(cfg.get_value(SECTION, "dev_mode", false))
	var s: Variant = cfg.get_value(SECTION, "control_size", SIZE_NORMAL)
	control_size = clampi(int(s), SIZE_SMALL, SIZE_LARGE) if typeof(s) in [TYPE_INT, TYPE_FLOAT] else SIZE_NORMAL


## Guarda sin pisar las otras secciones (apodo, apariencia, sonido).
func save_to(path: String) -> void:
	var cfg := ConfigFile.new()
	cfg.load(path)
	cfg.set_value(SECTION, "lefty", lefty)
	cfg.set_value(SECTION, "control_size", control_size)
	cfg.set_value(SECTION, "dev_mode", dev_mode)
	cfg.save(path)


static func _as_bool(v: Variant) -> bool:
	return v if typeof(v) == TYPE_BOOL else false
