class_name Haptics
extends RefCounted
## Vibración del celular por tipo de evento. Cada tipo tiene una duración
## distinta para que se "sienta" diferente sin mirar la pantalla:
##   tap 15 ms (toque) · point 35 ms · go 60 ms · win 120 ms · hit 220 ms
##
## En Android requiere el permiso VIBRATE en el preset de exportación (ver
## docs/BUILD.md). En iOS la duración la decide el sistema. En PC no hace nada.

const PATTERNS := {
	"tap": 15,
	"count": 20,
	"point": 35,
	"go": 60,
	"win": 120,
	"lose": 160,
	"hit": 220,
}

static var enabled := true


static func buzz(kind: String) -> void:
	if not enabled or not PATTERNS.has(kind):
		return
	if OS.has_feature("mobile"):
		Input.vibrate_handheld(int(PATTERNS[kind]))


static func duration_ms(kind: String) -> int:
	return int(PATTERNS.get(kind, 0))
