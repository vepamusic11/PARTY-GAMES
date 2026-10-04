class_name TvButton
extends Button
## Botón "de juguete" de la TV: píldora con bisel (contorno de tinta, labio
## oscuro abajo, luz arriba), ícono opcional en un círculo de color y texto.
## Lo usan la intro ("¡A jugar!"), la pausa y el selector TV/celular.
##
##   ╭──────────────────────────────╮
##   │ (▶)  Seguir jugando          │   <- cara con brillo
##   ╰══════════════════════════════╯   <- labio (relieve)
##
## Con foco: anillo amarillo por fuera y un "pop" de escala. `hero` suma los
## destellos que laten alrededor (como "¡A jugar!" del lobby).
##
## Rendimiento: el botón se redibuja solo cuando cambia (texto, foco,
## apretado). Los destellos van en nodos aparte que solo cambian su escala
## y corren únicamente mientras el botón tiene el foco.

var base := UiTheme.PAPER        ## Color de la cara.
var glyph := ""                  ## Ícono (UiTheme.draw_screen_glyph); vacío = sin ícono.
var glyph_bg := Color.TRANSPARENT  ## Círculo detrás del ícono; transparente = ícono suelto.
var glyph_off := false           ## Tacha el ícono (ej. sonido apagado).
var font_px := 34
var align_left := false          ## Texto a la izquierda (listas del menú) o centrado.
var hero := false:               ## Destellos alrededor con foco (acción principal).
	set(v):
		hero = v
		if hero and _sparkles == null:
			_sparkles = _Sparkles.new()
			_sparkles.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			add_child(_sparkles)
var _sparkles: _Sparkles


func _init(p_text: String = "", p_base: Color = UiTheme.PAPER, p_glyph: String = "",
		p_glyph_bg: Color = Color.TRANSPARENT) -> void:
	text = p_text
	base = p_base
	glyph = p_glyph
	glyph_bg = p_glyph_bg
	focus_mode = Control.FOCUS_ALL
	custom_minimum_size = Vector2(0, UiTheme.PAUSE_BUTTON_H)
	# El texto lo dibuja _draw encima del bisel: el del tema queda invisible.
	add_theme_font_override("font", UiTheme.FONT_BOLD)
	for st in ["normal", "hover", "pressed", "disabled", "focus", "hover_pressed"]:
		add_theme_stylebox_override(st, StyleBoxEmpty.new())
	for key in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color",
			"font_hover_pressed_color", "font_disabled_color"]:
		add_theme_color_override(key, Color(UiTheme.INK, 0.0))
	focus_entered.connect(_on_focus.bind(true))
	focus_exited.connect(_on_focus.bind(false))
	button_down.connect(queue_redraw)
	button_up.connect(queue_redraw)
	resized.connect(func() -> void: pivot_offset = size / 2.0)


func set_label(value: String) -> void:
	text = value
	queue_redraw()


func _on_focus(focused: bool) -> void:
	queue_redraw()
	if _sparkles != null:
		_sparkles.set_running(focused and not disabled)
	if not is_inside_tree():
		return
	if UiTheme.reduce_motion:
		scale = Vector2.ONE
		return
	var tw := create_tween()
	if focused:
		tw.tween_property(self, "scale", Vector2.ONE * 1.04, 0.14).from(Vector2.ONE * 0.97) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	else:
		tw.tween_property(self, "scale", Vector2.ONE, 0.12)


## Cuerpo del botón (sin labio ni anillo de foco).
func body_rect() -> Rect2:
	var o := UiTheme.BEVEL_OUTLINE
	var pad := o + UiTheme.FOCUS_WIDTH + 4.0
	return Rect2(Vector2(pad, pad), size - Vector2(pad * 2.0, pad * 2.0 + UiTheme.BEVEL_DEPTH))


func _draw() -> void:
	var depth := UiTheme.BEVEL_DEPTH
	var o := UiTheme.BEVEL_OUTLINE
	var r := body_rect()
	var radius := minf(r.size.y / 2.0, UiTheme.RADIUS + 6.0)
	var pressed := get_draw_mode() == DRAW_PRESSED or get_draw_mode() == DRAW_HOVER_PRESSED
	if has_focus():
		var ring := Rect2(r.position, r.size + Vector2(0, depth)).grow(o + UiTheme.FOCUS_WIDTH - 2.0)
		var ring_col := UiTheme.PAPER if base == UiTheme.ACCENT else UiTheme.ACCENT
		UiTheme.draw_round_rect(self, ring.grow(3), Color(UiTheme.INK, 0.55), radius + o + UiTheme.FOCUS_WIDTH + 1.0)
		UiTheme.draw_round_rect(self, ring, ring_col, radius + o + UiTheme.FOCUS_WIDTH - 2.0)
	var fill := base
	var ink := UiTheme.text_on(base)
	if disabled:
		fill = UiTheme.PAPER_DIM
		ink = UiTheme.MUTED
	UiTheme.draw_bevel(self, r, fill, radius, pressed, UiTheme.INK if not disabled else Color(UiTheme.INK, 0.35))
	var body := Rect2(r.position + Vector2(0, depth * 0.7 if pressed else 0.0), r.size)
	var left := body.position.x + radius * 0.6
	if not glyph.is_empty():
		var icon_r := body.size.y * 0.34
		var icon_c := Vector2(body.position.x + maxf(radius, icon_r + 14.0), body.get_center().y)
		if glyph_bg.a > 0.0:
			UiTheme.draw_bevel_circle(self, icon_c, icon_r, glyph_bg)
			UiTheme.draw_screen_glyph(self, glyph, icon_c - Vector2(0, 2), icon_r * 1.15, UiTheme.PAPER)
		else:
			UiTheme.draw_screen_glyph(self, glyph, icon_c, icon_r * 1.5, ink)
		if glyph_off:
			var k := icon_r * 0.7
			draw_line(icon_c + Vector2(-k, -k), icon_c + Vector2(k, k), UiTheme.INK, 9.0, true)
			draw_line(icon_c + Vector2(-k, -k), icon_c + Vector2(k, k), UiTheme.DANGER, 5.0, true)
		left = icon_c.x + icon_r + 18.0
	var right := body.end.x - radius * 0.6
	# Si no entra, el texto se achica (nunca por debajo de 24 px).
	var px := font_px
	while px > 24 and UiTheme.FONT_BOLD.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x > right - left:
		px -= 2
	var outline := 6 if ink == UiTheme.PAPER else 0
	if align_left:
		var w := UiTheme.FONT_BOLD.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x
		UiTheme.draw_text(self, text, Vector2(left + w / 2.0, body.get_center().y), px, ink, outline)
	else:
		UiTheme.draw_text(self, text, Vector2((left + right) / 2.0, body.get_center().y), px, ink, outline)


## Destellos del botón principal: dos abanicos de rayitas que "laten"
## (solo cambia su escala, a 30 cuadros por segundo; no se redibujan).
## Con "reducir movimiento" quedan quietos.
class _Sparkles:
	extends Control
	const PULSE_SPEED := 6.0
	const PULSE_FPS := 30.0
	var _t := 0.0
	var _since := 0.0
	var _fans: Array[Node2D] = []

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		visible = false
		for i in 2:
			var fan := Node2D.new()
			fan.draw.connect(_draw_fan.bind(fan, i))
			add_child(fan)
			_fans.append(fan)
		resized.connect(_refresh)

	func _ready() -> void:
		set_process(false)

	func set_running(on: bool) -> void:
		visible = on
		set_process(on and not UiTheme.reduce_motion)
		if on:
			_refresh()

	func _refresh() -> void:
		for i in _fans.size():
			_fans[i].position = _fan_data(i)[0]
			_fans[i].scale = Vector2.ONE
			_fans[i].queue_redraw()

	func _fan_data(i: int) -> Array:
		var button := get_parent() as TvButton
		var r := button.body_rect()
		var whole := Rect2(r.position, r.size + Vector2(0, UiTheme.BEVEL_DEPTH))
		return UiTheme.sparkle_fans(whole.grow(UiTheme.BEVEL_OUTLINE + 6.0))[i]

	func _draw_fan(fan: Node2D, i: int) -> void:
		var data := _fan_data(i)
		UiTheme.draw_sparkle_fan(fan, Vector2.ZERO, data[1], data[2] - data[0])

	func _process(delta: float) -> void:
		_t += delta
		_since += delta
		if _since < 1.0 / PULSE_FPS:
			return
		_since = 0.0
		for i in _fans.size():
			_fans[i].scale = Vector2.ONE * (0.92 + 0.14 * sin(_t * PULSE_SPEED + i * PI))
