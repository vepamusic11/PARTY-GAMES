class_name TvDeviceCard
extends Button
## Tarjeta grande del selector "¿Qué es este dispositivo?" (app/boot.gd):
## una ilustración (la TV con las mascotas en pantalla, o el celular con el
## joystick), el nombre y una línea que explica para qué sirve.
##
##   ╭────────────────────────╮
##   │  ┌──────────────────┐  │   <- ilustración sobre cielo
##   │  │  (o o) (o o)     │  │
##   │  └──────────────────┘  │
##   │     Pantalla (TV)      │
##   │  Muestra el juego y…   │
##   ╰════════════════════════╯   <- labio (bisel)
##
## Se elige con el D-pad (◀ ▶ y OK) o tocándola. Con foco: anillo amarillo
## y un "pop". Todo se dibuja al cambiar el foco, no por frame.

enum Kind { TV, PHONE }

const RADIUS := 40.0
const LIP := 14.0

var kind := Kind.TV
var title := ""
var subtitle := ""


func _init(p_kind: int, p_title: String, p_subtitle: String) -> void:
	kind = p_kind
	title = p_title
	subtitle = p_subtitle
	text = ""  # Todo se dibuja en _draw.
	tooltip_text = p_title
	focus_mode = Control.FOCUS_ALL
	custom_minimum_size = UiTheme.DEVICE_CARD_SIZE
	size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	for st in ["normal", "hover", "pressed", "disabled", "focus", "hover_pressed"]:
		add_theme_stylebox_override(st, StyleBoxEmpty.new())
	focus_entered.connect(_on_focus.bind(true))
	focus_exited.connect(_on_focus.bind(false))
	button_down.connect(queue_redraw)
	button_up.connect(queue_redraw)
	resized.connect(func() -> void: pivot_offset = size / 2.0)


func _on_focus(focused: bool) -> void:
	queue_redraw()
	if not is_inside_tree() or UiTheme.reduce_motion:
		return
	var tw := create_tween()
	tw.tween_property(self, "scale", Vector2.ONE * (1.04 if focused else 1.0), 0.16) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _draw() -> void:
	var pad := UiTheme.FOCUS_WIDTH + 10.0
	var body := Rect2(Vector2(pad, pad), size - Vector2(pad * 2.0, pad * 2.0 + LIP))
	var pressed := get_draw_mode() == DRAW_PRESSED or get_draw_mode() == DRAW_HOVER_PRESSED
	if pressed:
		body.position.y += LIP * 0.6
	if has_focus():
		var ring := Rect2(Vector2(pad, pad), size - Vector2(pad * 2.0, pad * 2.0)).grow(UiTheme.FOCUS_WIDTH + 2.0)
		UiTheme.draw_round_rect(self, ring.grow(3), Color(UiTheme.INK, 0.55), RADIUS + UiTheme.FOCUS_WIDTH + 5.0)
		UiTheme.draw_round_rect(self, ring, UiTheme.ACCENT, RADIUS + UiTheme.FOCUS_WIDTH + 2.0)
	var o := UiTheme.BEVEL_OUTLINE
	var whole := Rect2(Vector2(pad, pad), size - Vector2(pad * 2.0, pad * 2.0))
	UiTheme.draw_round_rect(self, whole.grow(o), UiTheme.INK, RADIUS + o, 0, UiTheme.INK, not pressed)
	UiTheme.draw_round_rect(self, Rect2(whole.position + Vector2(0, LIP), whole.size - Vector2(0, LIP)),
		UiTheme.PAPER_DIM.darkened(0.16), RADIUS)
	UiTheme.draw_round_rect(self, body, UiTheme.PAPER, RADIUS)
	# Ilustración arriba, sobre un cielo en degradé.
	var art := Rect2(body.position + Vector2(20, 20), Vector2(body.size.x - 40, body.size.y * 0.62))
	UiTheme.draw_gradient_round_rect(self, art, UiTheme.BG_SKY_TOP, UiTheme.BG_SKY_MID, RADIUS - 14.0)
	var floor_rect := Rect2(Vector2(art.position.x, art.end.y - art.size.y * 0.22), Vector2(art.size.x, art.size.y * 0.22))
	UiTheme.draw_gradient_round_rect(self, floor_rect, UiTheme.BG_FLOOR_A, UiTheme.BG_FLOOR_B, RADIUS - 14.0)
	UiTheme.draw_gradient_round_rect(self, Rect2(art.position + Vector2(14, 8), Vector2(art.size.x - 28, 40)),
		Color(UiTheme.PAPER, 0.35), Color(UiTheme.PAPER, 0.0), 20)
	if kind == Kind.TV:
		_draw_tv(art)
	else:
		_draw_phone(art)
	var text_top := art.end.y + 14.0
	UiTheme.draw_text(self, title, Vector2(body.get_center().x, text_top + 40.0), 50, UiTheme.PAPER,
		12, UiTheme.INK)
	var px := 28
	while px > 24 and UiTheme.FONT_SEMI.get_string_size(subtitle, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x > body.size.x - 48.0:
		px -= 2
	UiTheme.draw_text(self, subtitle, Vector2(body.get_center().x, text_top + 104.0), px, UiTheme.INK_SOFT, 0,
		UiTheme.INK, false)


## TV con patas y, en pantalla, tres mascotas festejando y un marcador.
func _draw_tv(art: Rect2) -> void:
	var w := art.size.x * 0.74
	var h := w * 0.56
	var tv := Rect2(Vector2(art.get_center().x - w / 2.0, art.position.y + art.size.y * 0.1), Vector2(w, h))
	for k: int in [-1, 1]:
		var leg := PackedVector2Array([tv.get_center() + Vector2(k * w * 0.26, h * 0.4),
			tv.get_center() + Vector2(k * w * 0.32, h * 0.62), tv.get_center() + Vector2(k * w * 0.28, h * 0.62)])
		draw_polyline(leg, UiTheme.INK, 10.0, true)
	UiTheme.draw_round_rect(self, tv.grow(6), UiTheme.INK, 26.0, 0, UiTheme.INK, true)
	UiTheme.draw_round_rect(self, tv, UiTheme.KEY_CAP, 22.0)
	var screen := tv.grow(-14)
	UiTheme.draw_gradient_round_rect(self, screen, UiTheme.SKY_TOP, UiTheme.SKY_BOTTOM, 12.0)
	var ground := Rect2(Vector2(screen.position.x, screen.end.y - screen.size.y * 0.28), Vector2(screen.size.x, screen.size.y * 0.28))
	UiTheme.draw_gradient_round_rect(self, ground, UiTheme.FLOOR, UiTheme.FLOOR_TILE, 12.0)
	# Marcador arriba: tres pastillas de color.
	for i in 3:
		var pill := Rect2(Vector2(screen.position.x + 16.0 + i * (screen.size.x - 32.0) / 3.0, screen.position.y + 12.0),
			Vector2((screen.size.x - 32.0) / 3.0 - 12.0, 24.0))
		UiTheme.draw_round_rect(self, pill, Protocol.player_color(i), 12.0, 2, UiTheme.INK)
	var u := screen.size.y / 150.0
	for i in 3:
		var feet := Vector2(screen.position.x + screen.size.x * (0.24 + 0.26 * i), screen.end.y - 8.0)
		PlayerAvatar.draw_mascot(self, feet, u, Protocol.player_color(i), i, PlayerAvatar.Mood.HAPPY, 0.0,
			(8.0 if i == 1 else 0.0), false, {"t": 0.4 * i, "wave": i == 1})
	UiTheme.draw_gradient_round_rect(self, Rect2(tv.position + Vector2(18, 6), Vector2(tv.size.x * 0.4, 14)),
		Color(UiTheme.PAPER, 0.35), Color(UiTheme.PAPER, 0.0), 7.0)


## Celular parado, un poco inclinado, con el joystick en pantalla y una
## mascota al lado que saluda.
func _draw_phone(art: Rect2) -> void:
	var h := art.size.y * 0.86
	var w := h * 0.5
	var c := Vector2(art.get_center().x + art.size.x * 0.1, art.position.y + art.size.y * 0.5)
	draw_set_transform(c, 0.14)
	var body := Rect2(-Vector2(w, h) / 2.0, Vector2(w, h))
	UiTheme.draw_round_rect(self, Rect2(body.position + Vector2(12, 14), body.size), UiTheme.SHADOW, w * 0.2)
	UiTheme.draw_round_rect(self, body.grow(5), UiTheme.INK, w * 0.2)
	UiTheme.draw_round_rect(self, body, UiTheme.KEY_CAP, w * 0.18)
	var screen := body.grow(-w * 0.07)
	screen.position.y += w * 0.08
	screen.size.y -= w * 0.16
	var blue := UiTheme.BRICKS[5]
	UiTheme.draw_gradient_round_rect(self, screen, blue.lightened(0.15), blue.darkened(0.1), w * 0.1)
	var tag := Rect2(screen.position + Vector2(screen.size.x / 2.0 - 30.0, 16.0), Vector2(60, 34))
	UiTheme.draw_round_rect(self, tag, Protocol.player_color(0), 17.0, 3, UiTheme.INK)
	UiTheme.draw_text(self, "1P", tag.get_center(), 24, UiTheme.PAPER, 5, UiTheme.INK)
	var jc := screen.get_center() + Vector2(0, screen.size.y * 0.12)
	var jr := screen.size.x * 0.34
	draw_circle(jc, jr + 5.0, UiTheme.INK)
	draw_circle(jc, jr, UiTheme.PHONE_DISH)
	draw_arc(jc, jr * 0.84, 0.0, TAU, 36, UiTheme.PHONE_DISH_RIM, 4.0, true)
	UiTheme.draw_toy_disc(self, jc + Vector2(jr * 0.22, -jr * 0.2), jr * 0.5, UiTheme.PAPER)
	draw_set_transform(Vector2.ZERO)
	var feet := Vector2(art.position.x + art.size.x * 0.22, art.end.y - 12.0)
	PlayerAvatar.draw_mascot(self, feet, art.size.y / 150.0, Protocol.player_color(1), 1, PlayerAvatar.Mood.HAPPY, 0.0,
		0.0, false, {"t": 0.6, "wave": true})
