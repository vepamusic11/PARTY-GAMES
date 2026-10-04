class_name SfxFiles
extends RefCounted
## Efectos grabados que reemplazan a la receta sintetizada del mismo nombre
## (ADR 0015). Sfx los carga al iniciar; las llamadas `Sfx.play("tick")` no
## cambian. Si un archivo falta, queda la receta de Sfx.RECIPES.
##
## Hoy solo la navegación de menús, que es lo que más suena y donde la onda
## cuadrada cansaba: clics suaves de Kenney (CC0, ver CREDITS.md).
## Cada archivo nuevo va con su licencia en assets/audio/sfx/ y en CREDITS.md
## (lo verifica un test).

const FILES := {
	"tick": "res://assets/audio/sfx/ui_tick.ogg",
	"select": "res://assets/audio/sfx/ui_select.ogg",
	"back": "res://assets/audio/sfx/ui_back.ogg",
}


## nombre -> AudioStream de los archivos que existen.
static func load_streams() -> Dictionary:
	var out := {}
	for sound_name: String in FILES:
		var path: String = FILES[sound_name]
		if ResourceLoader.exists(path):
			var stream := load(path) as AudioStream
			if stream != null:
				out[sound_name] = stream
	return out
