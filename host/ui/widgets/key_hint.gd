class_name KeyHint
extends HBoxContainer
## Guía de controles al pie de la pantalla: [◀ ▶] Cambiar  [OK] Elegir
## Le dice a quien tiene el control remoto qué puede hacer en cada pantalla.

const ARROWS := {
	"left": Vector2.LEFT, "right": Vector2.RIGHT, "up": Vector2.UP, "down": Vector2.DOWN,
}


func _init() -> void:
	add_theme_constant_override("separation", 12)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


## keys: nombres de flechas ("left", "right"…) o un texto ("OK", "Atrás").
func add_hint(keys: Array[String], text: String) -> KeyHint:
	var cap := _KeyCap.new()
	cap.keys = keys
	add_child(cap)
	var l := UiTheme.label(text, 26, UiTheme.INK, true)
	l.add_theme_constant_override("outline_size", 8)
	l.add_theme_color_override("font_outline_color", UiTheme.PAPER)
	add_child(l)
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(26, 0)
	add_child(gap)
	return self


class _KeyCap:
	extends Control
	var keys: Array[String] = []

	func _ready() -> void:
		var w := 20.0
		for k in keys:
			w += 40.0 if KeyHint.ARROWS.has(k) else UiTheme.FONT_BOLD.get_string_size(k, HORIZONTAL_ALIGNMENT_LEFT, -1, 24).x + 24.0
		custom_minimum_size = Vector2(w, 48)

	func _draw() -> void:
		var r := Rect2(Vector2(0, 2), size - Vector2(0, 4))
		UiTheme.draw_round_rect(self, r, UiTheme.CHIP_DARK, r.size.y / 2.0, 3, UiTheme.PAPER)
		var x := 10.0
		for k in keys:
			if KeyHint.ARROWS.has(k):
				UiTheme.draw_arrow(self, Vector2(x + 20, r.get_center().y), 20, KeyHint.ARROWS[k], UiTheme.PAPER)
				x += 40.0
			else:
				var w := UiTheme.FONT_BOLD.get_string_size(k, HORIZONTAL_ALIGNMENT_LEFT, -1, 24).x + 24.0
				UiTheme.draw_text(self, k, Vector2(x + w / 2.0, r.get_center().y), 24, UiTheme.PAPER)
				x += w
