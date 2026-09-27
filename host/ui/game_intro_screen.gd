class_name GameIntroScreen
extends Control
## "¿Cómo se juega?": aparece antes de cada minijuego de la competencia.
##
##                     [ Ronda 2/4 ]
##                 CARRERA DE TOQUES
##                   ¿Cómo se juega?
##   ┌──────────────────────┐  ┌──────────────────────────────┐
##   │ [Un botón]           │  │ Tocá el botón lo más rápido  │
##   │     ┌──────────┐     │  │ que puedas…                  │
##   │     │   (A)    │     │  │ 4 jugadores                  │
##   │     └──────────┘     │  │ (mascota) (mascota) …        │
##   └──────────────────────┘  └──────────────────────────────┘
##   [OK] Empezar ya  [Atrás] Menú           (5)  [¡A jugar!]
##
## Mientras se ve, los celulares ya muestran el control del juego (así cada
## uno se ubica), pero su input se ignora hasta que el juego empieza: eso lo
## decide HostMain, que todavía no creó el minijuego.
## Avanza con OK o sola a los AUTO_CONTINUE_SEC segundos (anillo de cuenta
## regresiva al lado del botón).

signal continue_requested

const AUTO_CONTINUE_SEC := 6.0

var paused := false  ## Con el menú de pausa abierto no corre la cuenta regresiva.

var _round: HexChip
var _title: Label
var _art: _ControlArt
var _description: Label
var _players_label: Label
var _players_row: HBoxContainer
var _ring: _CountdownRing
var _continue: Button
var _time_left := 0.0
var _active := false


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	visible = false
	_build()


## info: MiniGameRegistry.info(). players: los que van a jugar
## (HostServer.get_players()).
func show_intro(info: Dictionary, round_no: int, total_rounds: int, players: Array[Dictionary]) -> void:
	visible = true
	paused = false
	_round.set_text("Ronda %d/%d" % [round_no, total_rounds])
	_title.text = str(info.get("title", ""))
	_description.text = str(info.get("description", ""))
	_art.layout = str(info.get("layout", ""))
	_art.accent = info.get("accent", UiTheme.ACCENT)
	_art.queue_redraw()
	var n := players.size()
	_players_label.text = "%d jugador%s" % [n, "" if n == 1 else "es"]
	for c in _players_row.get_children():
		c.queue_free()
	for p in players:
		_players_row.add_child(_player_badge(p))
	_time_left = AUTO_CONTINUE_SEC
	_ring.fraction = 1.0
	_ring.seconds = ceili(AUTO_CONTINUE_SEC)
	_active = true
	_continue.grab_focus()
	_pop_title()


func hide_intro() -> void:
	_active = false
	visible = false


func focus_continue() -> void:
	_continue.grab_focus()


## Como apretar OK: termina la intro (tests, capturas y el botón).
func skip() -> void:
	_on_continue()


func is_active() -> bool:
	return _active


func _process(delta: float) -> void:
	if not _active or paused:
		return
	_time_left -= delta
	_ring.fraction = clampf(_time_left / AUTO_CONTINUE_SEC, 0.0, 1.0)
	_ring.seconds = ceili(maxf(_time_left, 0.0))
	if _time_left <= 0.0:
		_on_continue()


func _on_continue() -> void:
	if not _active:
		return
	_active = false
	continue_requested.emit()


func _pop_title() -> void:
	Sfx.play("join")
	if not is_inside_tree():
		return
	await get_tree().process_frame  # Esperar el layout para conocer el tamaño (pivote).
	_title.pivot_offset = _title.size / 2.0
	create_tween().tween_property(_title, "scale", Vector2.ONE, 0.35) \
		.from(Vector2(0.6, 0.6)).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## Mascota + etiqueta 1P + nombre (Label: texto plano, sin BBCode).
func _player_badge(p: Dictionary) -> Control:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 4)
	col.custom_minimum_size = Vector2(170, 0)
	var avatar := PlayerAvatar.new()
	avatar.slot = int(p.slot)
	avatar.style = PlayerAvatar.style_of(p)
	avatar.color = p.color
	avatar.mood = PlayerAvatar.Mood.HAPPY
	avatar.custom_minimum_size = Vector2(150, 150)
	col.add_child(avatar)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 8)
	var chip := _TagChip.new()
	chip.slot = int(p.slot)
	chip.color = p.color
	chip.custom_minimum_size = Vector2(64, 38)
	row.add_child(chip)
	var name_label := UiTheme.label(str(p.name), 28, UiTheme.INK, true)
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name_label.clip_text = true
	name_label.custom_minimum_size = Vector2(96, 38)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(name_label)
	col.add_child(row)
	return col


# --- UI -------------------------------------------------------------------------

func _build() -> void:
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, UiTheme.SAFE_MARGIN)
	margin.add_theme_constant_override("margin_top", 56)
	add_child(margin)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 14)
	margin.add_child(col)

	var top := CenterContainer.new()
	col.add_child(top)
	_round = HexChip.new("", Color.WHITE, "")
	_round.rainbow = true
	_round.custom_minimum_size = Vector2(320, 70)
	top.add_child(_round)

	_title = UiTheme.headline("", 96)
	_title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	col.add_child(_title)
	var how := UiTheme.label("¿Cómo se juega?", 34, UiTheme.INK, true)
	how.add_theme_constant_override("outline_size", 8)
	how.add_theme_color_override("font_outline_color", UiTheme.PAPER)
	col.add_child(how)

	var content := HBoxContainer.new()
	content.add_theme_constant_override("separation", 40)
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(content)
	_art = _ControlArt.new()
	_art.custom_minimum_size = Vector2(820, 0)
	content.add_child(_art)

	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel", UiTheme.panel_style(UiTheme.PAPER, UiTheme.RADIUS + 8, 36))
	content.add_child(panel)
	var info_box := VBoxContainer.new()
	info_box.add_theme_constant_override("separation", 14)
	panel.add_child(info_box)
	_description = UiTheme.label("", 40, UiTheme.INK, true, HORIZONTAL_ALIGNMENT_LEFT)
	_description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_description.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	_description.size_flags_vertical = Control.SIZE_EXPAND_FILL
	info_box.add_child(_description)
	_players_label = UiTheme.label("", 30, UiTheme.INK_SOFT, true, HORIZONTAL_ALIGNMENT_LEFT)
	info_box.add_child(_players_label)
	_players_row = HBoxContainer.new()
	_players_row.add_theme_constant_override("separation", 12)
	info_box.add_child(_players_row)

	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", 24)
	col.add_child(footer)
	var hints := KeyHint.new()
	hints.add_hint(["OK"], "Empezar ya").add_hint(["Atrás"], "Menú")
	hints.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(hints)
	_ring = _CountdownRing.new()
	_ring.custom_minimum_size = Vector2(96, 96)
	footer.add_child(_ring)
	_continue = Button.new()
	_continue.text = "¡A jugar!"
	_continue.custom_minimum_size = Vector2(420, 96)
	_continue.add_theme_font_size_override("font_size", 38)
	_continue.add_theme_stylebox_override("normal", UiTheme.button_style(UiTheme.ACCENT))
	_continue.add_theme_stylebox_override("hover", UiTheme.button_style(UiTheme.ACCENT.lightened(0.1)))
	_continue.add_theme_stylebox_override("pressed", UiTheme.button_style(UiTheme.ACCENT, true))
	_continue.pressed.connect(_on_continue)
	footer.add_child(_continue)


## Ilustración grande: un celular apaisado con el control del juego en la
## pantalla y flechas que indican cómo se mueve.
class _ControlArt:
	extends Control
	var layout := ""
	var accent := UiTheme.ACCENT

	func _draw() -> void:
		var r := Rect2(Vector2(10, 10), size - Vector2(20, 20))
		UiTheme.draw_round_rect(self, r, UiTheme.PAPER, UiTheme.RADIUS + 8, 0, UiTheme.INK, true)
		var name: String = GameCard.CONTROL_NAMES.get(layout, "Control")
		var fs := 30
		var cw := UiTheme.FONT_BOLD.get_string_size(name, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x + 36.0
		var chip := Rect2(r.position + Vector2(28, 24), Vector2(cw, 50))
		UiTheme.draw_round_rect(self, chip, accent, 25, 3, UiTheme.INK)
		UiTheme.draw_text(self, name, chip.get_center(), fs, UiTheme.PAPER, 5, UiTheme.INK)
		var hint_y := r.end.y - 36.0
		UiTheme.draw_text(self, "Tu celular ya muestra este control", Vector2(r.get_center().x, hint_y), 28,
			UiTheme.INK_SOFT, 0, UiTheme.INK, false)

		# Celular apaisado (19,5:9) centrado entre el chip y el texto de abajo.
		var avail := Rect2(r.position.x + 40, chip.end.y + 24, r.size.x - 80, hint_y - 34 - chip.end.y - 24)
		var h := minf(avail.size.y, avail.size.x / 2.1)
		var w := h * 2.1
		var phone := Rect2(avail.get_center() - Vector2(w, h) / 2.0, Vector2(w, h))
		UiTheme.draw_round_rect(self, phone.grow(6), UiTheme.SHADOW, h * 0.2)
		UiTheme.draw_round_rect(self, phone, UiTheme.INK, h * 0.18)
		var screen := phone.grow(-h * 0.07)
		screen.position.x += h * 0.06
		screen.size.x -= h * 0.12
		UiTheme.draw_round_rect(self, screen, accent, h * 0.1)
		var dot := Color(UiTheme.PAPER, 0.16)
		var y := screen.position.y + 26.0
		var row := 0
		while y < screen.end.y - 14.0:
			var x := screen.position.x + (26.0 if row % 2 == 0 else 52.0)
			while x < screen.end.x - 16.0:
				draw_circle(Vector2(x, y), 7.0, dot)
				x += 52.0
			y += 30.0
			row += 1
		draw_circle(Vector2(phone.position.x + h * 0.035, phone.get_center().y), h * 0.018, UiTheme.INK_SOFT)

		var c := screen.get_center()
		# El joystick lleva flechas en las 4 direcciones: va un poco más chico.
		var s := screen.size.y * (0.22 if layout == Protocol.LAYOUT_JOYSTICK else 0.28)
		UiTheme.draw_control_icon(self, c, s, layout)
		_draw_motion_hints(c, s)

	## Flechas que dicen cómo se usa el control.
	func _draw_motion_hints(c: Vector2, s: float) -> void:
		var arrow := s * 0.45
		match layout:
			Protocol.LAYOUT_JOYSTICK:
				for d in [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]:
					UiTheme.draw_arrow(self, c + d * s * 1.6, arrow + 6.0, d, UiTheme.INK)
					UiTheme.draw_arrow(self, c + d * s * 1.6, arrow, d, UiTheme.PAPER)
			Protocol.LAYOUT_SLIDER_H:
				for d in [Vector2.LEFT, Vector2.RIGHT]:
					UiTheme.draw_arrow(self, c + d * s * 2.0, arrow + 6.0, d, UiTheme.INK)
					UiTheme.draw_arrow(self, c + d * s * 2.0, arrow, d, UiTheme.PAPER)
			Protocol.LAYOUT_ONE_BUTTON:
				# Ondas de "toque" alrededor del botón.
				for k in 2:
					var rad := s * (1.3 + 0.28 * k)
					for side in [-1.0, 1.0]:
						var mid: float = -PI / 2.0 + side * PI * 0.28
						draw_arc(c, rad, mid - 0.32, mid + 0.32, 12, UiTheme.PAPER, maxf(6.0, s * 0.08), true)


## Anillo que se vacía con la cuenta regresiva, con los segundos en el centro.
class _CountdownRing:
	extends Control
	var fraction := 1.0:
		set(v):
			fraction = v
			queue_redraw()
	var seconds := 0:
		set(v):
			if v != seconds:
				seconds = v
				queue_redraw()

	func _draw() -> void:
		var c := size / 2.0
		var r := minf(size.x, size.y) / 2.0 - 4.0
		draw_circle(c, r, UiTheme.INK)
		draw_circle(c, r - 6.0, UiTheme.PAPER)
		var width := 12.0
		draw_arc(c, r - 6.0 - width / 2.0, 0.0, TAU, 48, UiTheme.PAPER_DIM, width, true)
		if fraction > 0.0:
			draw_arc(c, r - 6.0 - width / 2.0, -PI / 2.0, -PI / 2.0 + TAU * fraction, 48, UiTheme.ACCENT, width, true)
		UiTheme.draw_text(self, str(seconds), c, int(r * 0.9), UiTheme.INK)


## Etiqueta "1P" del color del jugador (para distinguirlo sin depender del color).
class _TagChip:
	extends Control
	var slot := 0
	var color := Color.WHITE

	func _draw() -> void:
		var r := Rect2(Vector2(2, 2), size - Vector2(4, 4))
		UiTheme.draw_round_rect(self, r, color, r.size.y / 2.0, 3, UiTheme.INK)
		UiTheme.draw_text(self, UiTheme.player_tag(slot), r.get_center(), 24, UiTheme.PAPER, 4, UiTheme.INK)
