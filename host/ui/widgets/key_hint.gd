class_name KeyHint
extends HBoxContainer
## Guía de controles al pie de la pantalla: [◀ ▶] Cambiar  [OK] Elegir
## Le dice a quien tiene el control remoto qué puede hacer en cada pantalla.
## Las teclas son píldoras oscuras con un poco de relieve (labio abajo y
## brillo arriba), como los botones de un control remoto.

const ARROWS := {
	"left": Vector2.LEFT, "right": Vector2.RIGHT, "up": Vector2.UP, "down": Vector2.DOWN,
}
const CAP_HEIGHT := 52.0
const ARROW_SLOT := 38.0
const KEY_FONT := 24
const LABEL_FONT := 28


func _init() -> void:
	add_theme_constant_override("separation", 12)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


## keys: nombres de flechas ("left", "right"…) o un texto ("OK", "Atrás").
func add_hint(keys: Array[String], text: String) -> KeyHint:
	var cap := _KeyCap.new()
	cap.keys = keys
	add_child(cap)
	var l := UiTheme.label(text, LABEL_FONT, UiTheme.INK, true)
	l.add_theme_constant_override("outline_size", 8)
	l.add_theme_color_override("font_outline_color", UiTheme.PAPER)
	add_child(l)
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(30, 0)
	add_child(gap)
	return self


class _KeyCap:
	extends Control
	var keys: Array[String] = []

	func _ready() -> void:
		var w := 24.0
		for k in keys:
			w += _key_width(k)
		custom_minimum_size = Vector2(w, KeyHint.CAP_HEIGHT)
		size_flags_vertical = Control.SIZE_SHRINK_CENTER

	static func _key_width(k: String) -> float:
		if KeyHint.ARROWS.has(k):
			return KeyHint.ARROW_SLOT
		return UiTheme.FONT_BOLD.get_string_size(k, HORIZONTAL_ALIGNMENT_LEFT, -1, KeyHint.KEY_FONT).x + 24.0

	func _draw() -> void:
		var r := Rect2(Vector2(2, 2), size - Vector2(4, 8))
		var radius := r.size.y / 2.0
		# Labio abajo, cuerpo oscuro y brillo arriba: una tecla, no un cartel.
		UiTheme.draw_round_rect(self, Rect2(r.position + Vector2(0, 5), r.size), UiTheme.INK, radius)
		UiTheme.draw_round_rect(self, r, UiTheme.KEY_CAP, radius, 2, Color(UiTheme.PAPER, 0.3))
		UiTheme.draw_gradient_round_rect(self, Rect2(r.position + Vector2(5, 3), Vector2(r.size.x - 10, r.size.y * 0.5)),
			Color(UiTheme.PAPER, 0.22), Color(UiTheme.PAPER, 0.0), radius - 5)
		var x := 12.0
		for k in keys:
			var w := _key_width(k)
			var c := Vector2(x + w / 2.0, r.get_center().y)
			if KeyHint.ARROWS.has(k):
				UiTheme.draw_arrow(self, c, 22, KeyHint.ARROWS[k], UiTheme.PAPER)
			else:
				UiTheme.draw_text(self, k, c, KeyHint.KEY_FONT, UiTheme.PAPER)
			x += w
