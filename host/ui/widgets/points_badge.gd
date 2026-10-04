class_name PointsBadge
extends Control
## Placa con los puntos que ganó un jugador en la ronda ("+70") en el
## resumen: píldora del color del jugador con contorno grueso de tinta,
## canto y brillo (como las píldoras del marcador) y el número en tinta o
## blanco según el color (UiTheme.text_on). Así se lee sobre el cielo claro y
## no se confunde con una mascota del mismo color (ej. "+50" rosa sobre la
## oreja rosa del conejo): la placa tapa lo de atrás y el contorno la separa.

var color := Color.WHITE
var text := ""


static func make(p_text: String, p_color: Color) -> PointsBadge:
	var badge := PointsBadge.new()
	badge.text = p_text
	badge.color = p_color
	var tw := UiTheme.FONT_BOLD.get_string_size(p_text, HORIZONTAL_ALIGNMENT_LEFT, -1, UiTheme.POINTS_BADGE_SIZE).x
	badge.custom_minimum_size = Vector2(tw + UiTheme.POINTS_BADGE_PAD * 2.0, UiTheme.POINTS_BADGE_H) \
		+ Vector2.ONE * UiTheme.PLATE_OUTLINE * 2.0
	return badge


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	var tw := UiTheme.FONT_BOLD.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, UiTheme.POINTS_BADGE_SIZE).x
	var w := tw + UiTheme.POINTS_BADGE_PAD * 2.0
	var h := UiTheme.POINTS_BADGE_H
	var r := Rect2(Vector2((size.x - w) / 2.0, (size.y - h) / 2.0), Vector2(w, h))
	var b := GameArt.TriBatch.new()
	var outer := r.grow(UiTheme.PLATE_OUTLINE).grow_side(SIDE_BOTTOM, 2.0)
	b.feather_capsule(outer, UiTheme.INK)
	b.capsule(outer, UiTheme.INK)
	b.capsule(r, color.darkened(0.3))
	b.capsule(Rect2(r.position, r.size - Vector2(0, UiTheme.PLATE_LIP)), color)
	b.capsule(Rect2(r.position + Vector2(h * 0.3, 5.0), Vector2(r.size.x - h * 0.6, h * 0.26)), UiTheme.PLATE_GLOSS)
	b.flush(self)
	var fg := UiTheme.text_on(color)
	var edge := UiTheme.INK if fg == UiTheme.PAPER else UiTheme.PAPER
	UiTheme.draw_text(self, text, r.get_center() - Vector2(0, UiTheme.PLATE_LIP / 2.0 + 1.0), UiTheme.POINTS_BADGE_SIZE,
		fg, UiTheme.TAG_OUTLINE, edge)
