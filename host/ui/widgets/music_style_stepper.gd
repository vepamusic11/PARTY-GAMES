class_name MusicStyleStepper
extends Stepper
## Estilo de música para el menú de pausa de la TV (ADR 0017):
##   [◀  ● Estilo: Fiesta  ▶]
## Con el foco encima, ◀ y ▶ recorren MusicStyles.ORDER (PARTY-GAME, Fiesta,
## Latino, Relajado, Retro, Sin música); ▲ ▼ siguen navegando. Aplica y
## guarda el cambio solo (Music.set_style): la música cambia en el momento,
## así se elige escuchando. El punto de color ayuda a reconocerlo, pero el
## nombre siempre está escrito (no depende del color).
##
## En el lobby (`lobby = true`) es una píldora de juguete más chica, junto al
## título "¿A qué jugamos?":  [◀  ♪ Música: Fiesta  ▶]

var title := "Estilo"
## Forma del lobby: píldora de juguete con nota musical ("Música: …").
var lobby := false


func _init() -> void:
	super._init()  # Foco y tamaño mínimo de Stepper.
	min_value = 0
	max_value = MusicStyles.ORDER.size() - 1
	value = MusicStyles.index_of(MusicStyles.style)
	value_changed.connect(_on_value_changed)


## Id del estilo que muestra.
func style_id() -> String:
	return MusicStyles.ORDER[clampi(value, 0, MusicStyles.ORDER.size() - 1)]


## Relee el estilo actual (por si cambió en otro lado).
func sync() -> void:
	value = MusicStyles.index_of(MusicStyles.style)
	queue_redraw()


func _on_value_changed(_v: int) -> void:
	Music.set_style(style_id())


func _draw() -> void:
	if size.y < 24.0:  # Todavía sin layout.
		return
	if lobby:
		_draw_lobby()
		return
	var r := Rect2(Vector2(6, 6), size - Vector2(12, 12))
	var radius := r.size.y / 2.0
	if has_focus():
		UiTheme.draw_round_rect(self, r.grow(12), Color(UiTheme.INK, 0.5), radius + 12)
		UiTheme.draw_round_rect(self, r.grow(9), UiTheme.ACCENT, radius + 9)
	UiTheme.draw_round_rect(self, r, UiTheme.PAPER, radius, 0, UiTheme.INK, true)
	var h := r.size.y
	for side in [-1, 1]:
		var enabled: bool = value > min_value if side < 0 else value < max_value
		var c := Vector2(r.position.x + h / 2.0 + 6, r.get_center().y) if side < 0 \
			else Vector2(r.end.x - h / 2.0 - 6, r.get_center().y)
		draw_circle(c, h * 0.38, UiTheme.ACCENT if enabled else UiTheme.PAPER_DIM)
		UiTheme.draw_arrow(self, c, h * 0.34, Vector2(side, 0), UiTheme.INK if enabled else UiTheme.MUTED)
	var id := style_id()
	var text := "%s: %s" % [title, MusicStyles.display_name(id)]
	var font_px := int(h * 0.4)
	var text_w := UiTheme.FONT_BOLD.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_px).x
	var dot := UiTheme.MUSIC_STYLE_DOT
	var gap := UiTheme.MUSIC_STYLE_DOT_GAP
	var left := r.get_center().x - (text_w + dot * 2.0 + gap) / 2.0
	var dot_c := Vector2(left + dot, r.get_center().y)
	draw_circle(dot_c, dot + 2.0, UiTheme.INK)
	draw_circle(dot_c, dot, UiTheme.music_style_color(id))
	UiTheme.draw_text(self, text, Vector2(left + dot * 2.0 + gap + text_w / 2.0, r.get_center().y), font_px, UiTheme.INK)


## Píldora del lobby: pieza de juguete blanca, flechas con bisel a los
## costados, nota musical, punto del color del estilo y "Música: <nombre>".
func _draw_lobby() -> void:
	var r := Rect2(Vector2(4, 4), size - Vector2(8, 8))
	var depth := UiTheme.TOY_DEPTH * 0.6
	var radius := (r.size.y - depth) / 2.0
	if has_focus():
		var ring := r.grow(10.0)
		UiTheme.draw_round_rect(self, ring.grow(3), Color(UiTheme.INK, 0.55), ring.size.y / 2.0 + 3.0)
		UiTheme.draw_round_rect(self, ring, UiTheme.ACCENT, ring.size.y / 2.0)
	var body := UiTheme.draw_toy_block(self, r, UiTheme.PAPER, UiTheme.PAPER_DIM, UiTheme.BUTTON_LIGHT_LIP, radius, depth)
	var h := body.size.y
	var arrow_r := h * 0.34
	for side in [-1, 1]:
		var enabled: bool = value > min_value if side < 0 else value < max_value
		var c := Vector2(body.position.x + h / 2.0, body.get_center().y) if side < 0 \
			else Vector2(body.end.x - h / 2.0, body.get_center().y)
		if enabled:
			UiTheme.draw_bevel_circle(self, c, arrow_r, UiTheme.ACCENT)
		else:
			draw_circle(c, arrow_r, UiTheme.PAPER_DIM)
		UiTheme.draw_arrow(self, c - Vector2(0, 1), arrow_r * 0.9, Vector2(side, 0), UiTheme.INK if enabled else UiTheme.MUTED)
	var id := style_id()
	var text := "Música: %s" % MusicStyles.display_name(id)
	var font_px := UiTheme.MUSIC_PILL_FONT
	var avail := body.size.x - h * 2.0 - h * 0.9
	while font_px > 24 and UiTheme.FONT_BOLD.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_px).x > avail:
		font_px -= 2
	var text_w := UiTheme.FONT_BOLD.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_px).x
	var note := h * 0.62
	var left := body.get_center().x - (text_w + note + UiTheme.MUSIC_STYLE_DOT_GAP) / 2.0
	var note_c := Vector2(left + note / 2.0, body.get_center().y)
	# La nota lleva el color del estilo (con contorno): acompaña al nombre.
	UiTheme.draw_music_note(self, note_c + Vector2(1.5, 1.5), note, UiTheme.INK)
	UiTheme.draw_music_note(self, note_c, note, UiTheme.music_style_color(id).darkened(0.15))
	UiTheme.draw_text(self, text, Vector2(left + note + UiTheme.MUSIC_STYLE_DOT_GAP + text_w / 2.0, body.get_center().y),
		font_px, UiTheme.INK)
