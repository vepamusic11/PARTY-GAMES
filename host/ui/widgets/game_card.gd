class_name GameCard
extends Button
## Tarjeta de minijuego en el lobby. OK del control remoto la marca o
## desmarca para la competencia. Si no se puede jugar con la cantidad de
## jugadores elegida queda deshabilitada, pero sigue siendo navegable para
## que se pueda leer el motivo ("Solo para 2 jugadores").

const CONTROL_NAMES := {
	Protocol.LAYOUT_JOYSTICK: "Joystick",
	Protocol.LAYOUT_SLIDER_H: "Deslizar",
	Protocol.LAYOUT_ONE_BUTTON: "Un botón",
}

var info: Dictionary
var unavailable_reason := ""


func _init(p_info: Dictionary) -> void:
	info = p_info
	toggle_mode = true
	focus_mode = Control.FOCUS_ALL
	custom_minimum_size = Vector2(372, 262)
	for style in ["normal", "hover", "pressed", "disabled", "focus", "hover_pressed"]:
		add_theme_stylebox_override(style, StyleBoxEmpty.new())
	toggled.connect(func(_on: bool) -> void: queue_redraw())
	focus_entered.connect(_on_focus.bind(true))
	focus_exited.connect(_on_focus.bind(false))
	resized.connect(func() -> void: pivot_offset = size / 2.0)


func set_unavailable(reason: String) -> void:
	unavailable_reason = reason
	disabled = not reason.is_empty()
	queue_redraw()


func is_selected() -> bool:
	return button_pressed and not disabled


static func players_text(p_info: Dictionary) -> String:
	var lo := int(p_info.min_players)
	var hi := int(p_info.max_players)
	if lo == hi:
		return "%d jugador%s" % [lo, "" if lo == 1 else "es"]
	return "%d–%d jugadores" % [lo, hi]


func _on_focus(focused: bool) -> void:
	create_tween().tween_property(self, "scale", Vector2.ONE * (1.05 if focused else 1.0), 0.12)
	queue_redraw()


func _draw() -> void:
	var r := Rect2(Vector2(10, 10), size - Vector2(20, 20))
	var a := 0.55 if disabled else 1.0
	var accent: Color = info.get("accent", UiTheme.ACCENT)
	if disabled:
		accent = accent.lerp(UiTheme.MUTED, 0.6)
	if has_focus():
		UiTheme.draw_round_rect(self, r.grow(12), Color(UiTheme.INK, 0.5), 40)
		UiTheme.draw_round_rect(self, r.grow(9), UiTheme.ACCENT, 38)
	UiTheme.draw_round_rect(self, r, Color(UiTheme.PAPER, a), 30, 6.0 if is_selected() else 0.0, UiTheme.SUCCESS, true)

	# Ilustración: fondo de color con lunares y el ícono del tipo de control.
	var art := Rect2(r.position + Vector2(12, 12), Vector2(r.size.x - 24, r.size.y * 0.52))
	UiTheme.draw_round_rect(self, art, Color(accent, a), 22)
	var dot := Color(1, 1, 1, 0.16 * a)
	var y := art.position.y + 22.0
	var row := 0
	while y < art.end.y - 12.0:
		var x := art.position.x + (24.0 if row % 2 == 0 else 46.0)
		while x < art.end.x - 16.0:
			draw_circle(Vector2(x, y), 6.0, dot)
			x += 44.0
		y += 26.0
		row += 1
	_draw_control_icon(art.get_center() + Vector2(0, 4), art.size.y * 0.34, str(info.get("layout", "")), a)

	# Marca de selección
	var badge := Vector2(art.end.x - 30, art.position.y + 30)
	if is_selected():
		draw_circle(badge, 24, UiTheme.PAPER)
		draw_circle(badge, 20, UiTheme.SUCCESS)
		UiTheme.draw_check(self, badge, 24, UiTheme.PAPER, 5.0)
	else:
		draw_circle(badge, 22, Color(UiTheme.PAPER, 0.9 * a))
		draw_arc(badge, 16, 0, TAU, 24, Color(UiTheme.INK_SOFT, 0.5 * a), 3.0, true)

	var text_x := r.position.x + 24
	UiTheme.draw_text_left(self, str(info.get("title", "")), Vector2(text_x, art.end.y + 38), 34,
		Color(UiTheme.INK, a), r.size.x - 48)
	var meta := unavailable_reason if disabled else "%s · %s" % [players_text(info), CONTROL_NAMES.get(info.get("layout"), "Control")]
	UiTheme.draw_text_left(self, meta, Vector2(text_x, art.end.y + 80), 25,
		UiTheme.DANGER if disabled else UiTheme.INK_SOFT, r.size.x - 48, false)


func _draw_control_icon(c: Vector2, s: float, layout: String, a: float) -> void:
	var white := Color(1, 1, 1, a)
	var ink := Color(UiTheme.INK, a)
	match layout:
		Protocol.LAYOUT_JOYSTICK:
			draw_circle(c, s + 4, ink)
			draw_circle(c, s, Color(1, 1, 1, 0.35 * a))
			var knob := c + Vector2(s * 0.35, -s * 0.3)
			draw_circle(knob, s * 0.5 + 4, ink)
			draw_circle(knob, s * 0.5, white)
		Protocol.LAYOUT_SLIDER_H:
			var bar := Rect2(c.x - s * 1.5, c.y - s * 0.2, s * 3.0, s * 0.4)
			UiTheme.draw_round_rect(self, bar.grow(4), ink, s * 0.24)
			UiTheme.draw_round_rect(self, bar, Color(1, 1, 1, 0.45 * a), s * 0.2)
			var knob := Vector2(c.x + s * 0.5, c.y)
			draw_circle(knob, s * 0.5 + 4, ink)
			draw_circle(knob, s * 0.5, white)
		Protocol.LAYOUT_ONE_BUTTON:
			draw_circle(c + Vector2(0, 6), s + 4, ink)
			draw_circle(c + Vector2(0, 6), s, white.darkened(0.2))
			draw_circle(c, s + 4, ink)
			draw_circle(c, s, white)
			UiTheme.draw_text(self, "A", c, int(s), ink)
		_:
			UiTheme.draw_star(self, c, s, white)
