class_name NamePlate
extends Control
## Chapita del jugador fuera de los juegos (resumen de ronda y podio):
##   ( 1P | Pablo   4° · 330 pts )
## Píldora de papel con contorno grueso de tinta y la etiqueta 1P–4P en el
## color del jugador. Se lee sobre cualquier fondo (cielo claro, piso,
## mascota) y no depende del color: la etiqueta dice quién es.
## El nombre se dibuja con draw_string (texto plano, nunca BBCode) y se
## recorta con "…" si no entra.

var slot := 0
var color := Color.WHITE
var player_name := ""
var extra := ""  ## Texto secundario a la derecha (ej. "4° · 330 pts"); vacío = nada.


static func make(p_slot: int, p_color: Color, p_name: String, p_extra: String = "") -> NamePlate:
	var plate := NamePlate.new()
	plate.slot = p_slot
	plate.color = p_color
	plate.player_name = p_name
	plate.extra = p_extra
	plate.custom_minimum_size = Vector2(minf(plate.natural_width(), UiTheme.PLATE_MAX_W), UiTheme.PLATE_H + UiTheme.PLATE_OUTLINE * 2.0)
	return plate


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


## Ancho que ocupa con el nombre entero.
func natural_width() -> float:
	return _tag_width() + _text_width(player_name, UiTheme.PLATE_NAME_SIZE) + _extra_width() + 44.0 + UiTheme.PLATE_OUTLINE * 2.0


func _draw() -> void:
	var h := UiTheme.PLATE_H
	var ol := UiTheme.PLATE_OUTLINE
	var tag_w := _tag_width()
	var extra_w := _extra_width()
	var shown := _fit(player_name, size.x - ol * 2.0 - tag_w - extra_w - 44.0)
	var w := tag_w + _text_width(shown, UiTheme.PLATE_NAME_SIZE) + extra_w + 44.0
	var r := Rect2(Vector2((size.x - w) / 2.0, (size.y - h) / 2.0), Vector2(w, h))
	var tag := Rect2(r.position + Vector2(7, 7), Vector2(tag_w, h - 14.0 - UiTheme.PLATE_LIP / 2.0))

	var b := GameArt.TriBatch.new()
	var outer := r.grow(ol)
	b.feather_capsule(outer, UiTheme.INK)
	b.capsule(outer, UiTheme.INK)
	b.capsule(r, UiTheme.PAPER_DIM.darkened(0.12))
	b.capsule(Rect2(r.position, r.size - Vector2(0, UiTheme.PLATE_LIP)), UiTheme.PAPER)
	b.capsule(tag.grow(3.0), UiTheme.INK)
	b.capsule(tag, color.darkened(0.3))
	b.capsule(Rect2(tag.position, tag.size - Vector2(0, 4.0)), color)
	b.capsule(Rect2(tag.position + Vector2(8, 3), Vector2(tag.size.x - 16.0, tag.size.y * 0.3)), UiTheme.PLATE_GLOSS)
	b.flush(self)

	var fg := UiTheme.text_on(color)
	UiTheme.draw_text(self, UiTheme.player_tag(slot), tag.get_center() + Vector2(0, -1), UiTheme.PLATE_TAG_SIZE, fg)
	var cy := r.position.y + (h - UiTheme.PLATE_LIP) / 2.0
	var x := tag.end.x + 14.0
	UiTheme.draw_text_left(self, shown, Vector2(x, cy), UiTheme.PLATE_NAME_SIZE, UiTheme.INK)
	if not extra.is_empty():
		x += _text_width(shown, UiTheme.PLATE_NAME_SIZE) + 16.0
		UiTheme.draw_text_left(self, extra, Vector2(x, cy + 1.0), UiTheme.PLATE_EXTRA_SIZE, UiTheme.INK_SOFT)


func _tag_width() -> float:
	return _text_width(UiTheme.player_tag(slot), UiTheme.PLATE_TAG_SIZE) + 26.0


func _extra_width() -> float:
	return 0.0 if extra.is_empty() else _text_width(extra, UiTheme.PLATE_EXTRA_SIZE) + 16.0


static func _text_width(text: String, font_size: int) -> float:
	return UiTheme.FONT_BOLD.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x


## El nombre recortado con "…" para que entre en `max_w`.
static func _fit(text: String, max_w: float) -> String:
	if _text_width(text, UiTheme.PLATE_NAME_SIZE) <= max_w:
		return text
	var cut := text
	while cut.length() > 1 and _text_width(cut + "…", UiTheme.PLATE_NAME_SIZE) > max_w:
		cut = cut.left(cut.length() - 1)
	return cut + "…"
