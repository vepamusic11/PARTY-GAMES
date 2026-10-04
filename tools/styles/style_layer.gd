extends CanvasLayer
## Post-proceso de pantalla completa para explorar estilos visuales
## (docs/ESTILOS.md). Solo lo usan las herramientas de `tools/`: el juego
## no lo carga nunca, así que el aspecto por defecto no cambia.
##
## Es una capa bien alta con un `ColorRect` que cubre el viewport y un shader
## `canvas_item` que lee la pantalla ya dibujada (`hint_screen_texture`) y
## la redibuja con otro estilo. Sirve igual para la TV (root) y para el
## `SubViewport` del celular: cada viewport tiene su propia textura de pantalla.

const STYLES := ["pixel", "neon", "paper", "flat"]
const STYLE_DIR := "res://tools/styles/"


## Agrega el post-proceso `style` dentro de `parent` (un Viewport o un nodo
## de él). `params` pisa uniforms del shader (ej. {"pixel_height": 360}).
## Devuelve null (y avisa) si el estilo no existe.
static func attach(parent: Node, style: String, params: Dictionary = {}) -> CanvasLayer:
	var path := STYLE_DIR + style + ".gdshader"
	if not style in STYLES or not ResourceLoader.exists(path):
		push_error("Estilo desconocido: %s (hay: %s)" % [style, ", ".join(STYLES)])
		return null
	var layer: CanvasLayer = load("res://tools/styles/style_layer.gd").new()
	layer.name = "StyleLayer_" + style
	layer.layer = 128  # Máximo permitido: queda encima de todo, incluso de la pausa.
	var rect := ColorRect.new()
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat := ShaderMaterial.new()
	mat.shader = load(path)
	for key: String in params:
		mat.set_shader_parameter(key, params[key])
	rect.material = mat
	layer.add_child(rect)
	parent.add_child(layer)
	return layer


## Lee `--style-param=nombre=valor` (se puede repetir) de los argumentos.
static func params_from_args(args: PackedStringArray) -> Dictionary:
	var out := {}
	for arg in args:
		if arg.begins_with("--style-param="):
			var kv := arg.trim_prefix("--style-param=").split("=", false, 1)
			if kv.size() == 2:
				out[kv[0]] = str_to_var(kv[1]) if kv[1].is_valid_float() or kv[1] in ["true", "false"] else kv[1]
	return out
