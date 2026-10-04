class_name GameIntroScreen
extends Control
## "¿Cómo se juega?": aparece antes de cada minijuego de la competencia.
##
##                        [ Ronda 2/4 ]
##                   CARRERA DE TOQUES          <- héroe: título "de logo"
##                    (?) ¿Cómo se juega?
##   ┌──────────────────────┐  ┌──────────────────────────────────┐
##   │ [Un botón]  (foto del│  │ (A) Tocá el botón lo más rápido… │
##   │   juego)    ╱celular╲│  │ (🏆) Primero en llegar gana.     │
##   │            ╱  (A)   ╱│  │ ─────────────────────────────────│
##   │ Tu celular ya muestra│  │ 2 jugadores · Tocá tu celular    │
##   │ este control         │  │ [1P ✓][2P …]                     │
##   └──────────────────────┘  └──────────────────────────────────┘
##   [OK] Empezar ya  [Atrás] Menú                 (5) [ ¡A jugar! ]
##
## Pasos: la descripción del juego se parte en oraciones y cada una lleva un
## ícono (el primero, el control del juego; "gana" lleva trofeo; tiempo,
## reloj…). Si el juego trae una sola oración, se suma "Buscá tu mascota".
##
## *Ready check*: mientras se ve la intro, cada celular ya muestra el control
## del juego. Si alguien lo toca (botón o joystick), su tarjeta pasa a
## "¡Listo!". Cuando están todos, la cuenta regresiva se acorta a
## ALL_READY_SEC. Lo decide la TV con el input de siempre (axis/btn): el
## celular no manda nada nuevo ni decide nada. El input se sigue ignorando
## para el juego: eso lo decide HostMain, que todavía no creó el minijuego.
##
## Avanza con OK o sola a los AUTO_CONTINUE_SEC segundos (anillo de cuenta
## regresiva al lado del botón).
##
## Entrada orquestada (≤ 1 s): la ronda cae, el título hace "pop", los
## paneles se deslizan desde los costados y las tarjetas saltan en cadena.
## Con UiTheme.reduce_motion es un fundido corto, sin rebotes.

signal continue_requested

const AUTO_CONTINUE_SEC := 6.0
const ALL_READY_SEC := 1.5    ## Con todos listos, arranca a lo sumo en este tiempo.
const READY_AXIS := 0.35      ## Cuánto hay que mover el joystick/slider para "¡Listo!".
const ART_WIDTH := 740.0

var paused := false  ## Con el menú de pausa abierto no corre la cuenta regresiva.

var _round: HexChip
var _title: TvLogoTitle
var _how: Control
var _art: _ControlArt
var _info_panel: PanelContainer
var _steps: VBoxContainer
var _players_label: Label
var _ready_hint: Label
var _players_row: HBoxContainer
var _footer: HBoxContainer
var _ring: _CountdownRing
var _continue: TvButton
var _description := ""
var _time_left := 0.0
var _active := false
var _enter_gen := 0  ## Cambia en cada show/hide: corta una entrada vieja a medio camino.
var _enter_tweens: Array[Tween] = []
var _enter_rest: Array = []  ## [nodo, posición final] de lo que se desliza (para cortar limpio).


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
	_description = str(info.get("description", ""))
	var layout := str(info.get("layout", ""))
	_art.layout = layout
	_art.accent = info.get("accent", UiTheme.ACCENT)
	_art.thumb = GameCard.thumbnail(str(info.get("id", "")))
	_art.queue_redraw()
	_fill_steps(_description, layout)
	var n := players.size()
	_players_label.text = "%d jugador%s" % [n, "" if n == 1 else "es"]
	_ready_hint.text = "Tocá tu celular para decir ¡Listo!"
	_ready_hint.add_theme_color_override("font_color", UiTheme.INK_SOFT)
	for c in _players_row.get_children():
		_players_row.remove_child(c)
		c.queue_free()
	for p in players:
		_players_row.add_child(TvReadyCard.new(p))
	_time_left = AUTO_CONTINUE_SEC
	_ring.fraction = 1.0
	_ring.seconds = ceili(AUTO_CONTINUE_SEC)
	_active = true
	_continue.grab_focus()
	Sfx.play("join")
	_animate_in()


func hide_intro() -> void:
	_active = false
	_enter_gen += 1
	_stop_entrance()
	visible = false


func focus_continue() -> void:
	_continue.grab_focus()


## Como apretar OK: termina la intro (tests, capturas y el botón).
func skip() -> void:
	_on_continue()


func is_active() -> bool:
	return _active


## Textos de los pasos, en orden (tests y capturas).
func steps_text() -> Array[String]:
	var out: Array[String] = []
	for row in _steps.get_children():
		out.append((row.get_child(1) as Label).text)
	return out


## Input de un celular durante la intro (ya validado por HostServer). Tocar
## el botón o mover el joystick marca al jugador como listo; nada más.
func on_player_input(player_id: int, input: Dictionary) -> void:
	if not _active or paused:
		return
	var raw: Variant = input.get("axis", Vector2.ZERO)
	var axis: Vector2 = raw if typeof(raw) == TYPE_VECTOR2 else Vector2.ZERO
	if int(input.get("btn", 0)) == 0 and axis.length() < READY_AXIS:
		return
	mark_ready(player_id)


func mark_ready(player_id: int) -> void:
	var all := true
	var changed := false
	for card: TvReadyCard in _players_row.get_children():
		if card.player_id == player_id and not card.is_ready():
			card.set_ready(true)
			changed = true
		all = all and card.is_ready()
	if changed and all and _players_row.get_child_count() > 0:
		_time_left = minf(_time_left, ALL_READY_SEC)
		_ready_hint.text = "¡Todos listos!"
		_ready_hint.add_theme_color_override("font_color", UiTheme.INTRO_READY_TEXT)


func ready_count() -> int:
	var n := 0
	for card: TvReadyCard in _players_row.get_children():
		n += 1 if card.is_ready() else 0
	return n


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


# --- Pasos -----------------------------------------------------------------------

## Parte la descripción en oraciones y arma un paso con ícono por cada una.
func _fill_steps(description: String, layout: String) -> void:
	for c in _steps.get_children():
		_steps.remove_child(c)
		c.queue_free()
	var sentences := split_sentences(description)
	if sentences.size() < 2:
		sentences.append("Buscá tu mascota: lleva tu etiqueta 1P–4P.")
	for i in mini(sentences.size(), 3):
		_steps.add_child(_step_row(i, sentences[i], layout))


## "Tocá el botón. ¡Primero gana!" -> ["Tocá el botón.", "¡Primero gana!"]
static func split_sentences(text: String) -> Array[String]:
	var out: Array[String] = []
	var current := ""
	for i in text.length():
		var ch := text[i]
		current += ch
		var next := text[i + 1] if i + 1 < text.length() else " "
		if ch in [".", "!", "?"] and next == " ":
			if not current.strip_edges().is_empty():
				out.append(current.strip_edges())
			current = ""
	if not current.strip_edges().is_empty():
		out.append(current.strip_edges())
	return out


## Ícono de un paso según lo que dice (el primero es siempre el control).
static func step_glyph(index: int, sentence: String) -> String:
	var s := sentence.to_lower()
	if index == 0:
		return "control"
	if s.contains("gana"):
		return "trophy"
	if s.contains("1p"):
		return "tag"
	if s.contains("segundo") or s.contains(" s ") or s.contains("reloj") or s.contains("cronómetro"):
		return "clock"
	if s.contains("mirá") or s.contains("sombra"):
		return "eye"
	return "star"


func _step_row(index: int, sentence: String, layout: String) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 18)
	var icon := _StepIcon.new()
	icon.glyph = step_glyph(index, sentence)
	icon.layout = layout
	icon.color = UiTheme.BRICKS[[5, 2, 7][index % 3]] if icon.glyph != "control" else _art.accent
	icon.custom_minimum_size = Vector2(UiTheme.INTRO_STEP_ICON, UiTheme.INTRO_STEP_ICON)
	icon.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	row.add_child(icon)
	var l := UiTheme.label(sentence, UiTheme.INTRO_STEP_FONT, UiTheme.INK, true, HORIZONTAL_ALIGNMENT_LEFT)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.custom_minimum_size = Vector2(0, UiTheme.INTRO_STEP_ICON)
	row.add_child(l)
	return row


# --- Entrada ---------------------------------------------------------------------

## Entrada en cadena. Todo arranca invisible para que no "salte" y, cuando
## el layout ya está calculado (un frame), cada pieza entra con su retraso.
func _animate_in() -> void:
	_enter_gen += 1
	_stop_entrance()
	var gen := _enter_gen
	var pieces := _enter_pieces()
	for p in pieces:
		(p[0] as Control).modulate.a = 0.0
	if not is_inside_tree():
		for p in pieces:
			(p[0] as Control).modulate.a = 1.0
		return
	await get_tree().process_frame
	if gen != _enter_gen or not is_inside_tree():
		return
	var delay := UiTheme.INTRO_ENTER_DELAY
	if UiTheme.reduce_motion:
		for p in pieces:
			create_tween().tween_property(p[0], "modulate:a", 1.0, 0.2).set_delay(delay)
		return
	var dur := UiTheme.INTRO_ENTER_DUR
	for p in pieces:
		var node: Control = p[0]
		var kind: String = p[1]
		var at: float = delay + float(p[2])
		var tw := create_tween().set_parallel()
		_enter_tweens.append(tw)
		tw.tween_property(node, "modulate:a", 1.0, dur * 0.6).set_delay(at)
		match kind:
			"drop", "rise", "left", "right":
				var off: Vector2 = {"drop": Vector2(0, -40), "rise": Vector2(0, 40),
					"left": Vector2(-UiTheme.INTRO_SLIDE, 0), "right": Vector2(UiTheme.INTRO_SLIDE, 0)}[kind]
				_enter_rest.append([node, node.position])
				tw.tween_property(node, "position", node.position, dur).from(node.position + off).set_delay(at) \
					.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
			"pop":
				node.pivot_offset = node.size / 2.0 if not node is TvReadyCard else Vector2(node.size.x / 2.0, node.size.y)
				tw.tween_property(node, "scale", Vector2.ONE, dur * 1.2).from(Vector2.ONE * 0.6).set_delay(at) \
					.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## Corta una entrada a medio camino y deja todo en su lugar final.
func _stop_entrance() -> void:
	for tw in _enter_tweens:
		if tw.is_valid():
			tw.kill()
	_enter_tweens.clear()
	for rest in _enter_rest:
		if is_instance_valid(rest[0]):
			(rest[0] as Control).position = rest[1]
	_enter_rest.clear()
	for p in _enter_pieces():
		if is_instance_valid(p[0]):
			(p[0] as Control).scale = Vector2.ONE
			(p[0] as Control).modulate.a = 1.0


## [nodo, tipo de entrada, retraso].
func _enter_pieces() -> Array:
	var out: Array = [
		[_round, "drop", 0.0], [_title, "pop", 0.06], [_how, "rise", 0.18],
		[_art, "left", 0.22], [_info_panel, "right", 0.26],
	]
	var t := 0.36
	for row in _steps.get_children():
		out.append([row, "right", t])
		t += UiTheme.INTRO_ENTER_STAGGER
	for card in _players_row.get_children():
		out.append([card, "pop", t])
		t += UiTheme.INTRO_ENTER_STAGGER
	out.append([_footer, "rise", minf(t, 0.6)])
	return out


# --- UI -------------------------------------------------------------------------

func _build() -> void:
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right"]:
		margin.add_theme_constant_override("margin_" + side, UiTheme.SAFE_MARGIN)
	margin.add_theme_constant_override("margin_top", 30)
	margin.add_theme_constant_override("margin_bottom", 34)
	add_child(margin)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 4)
	margin.add_child(col)

	var top := CenterContainer.new()
	col.add_child(top)
	_round = HexChip.new("", Color.WHITE, "")
	_round.rainbow = true
	_round.custom_minimum_size = Vector2(340, 72)
	top.add_child(_round)

	_title = TvLogoTitle.new("", UiTheme.INTRO_TITLE_SIZE)
	_title.custom_minimum_size.y = UiTheme.INTRO_TITLE_SIZE * 1.42
	col.add_child(_title)

	var how_center := CenterContainer.new()
	col.add_child(how_center)
	_how = _HowPill.new()
	how_center.add_child(_how)

	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 10)
	col.add_child(gap)

	var content := HBoxContainer.new()
	content.add_theme_constant_override("separation", 36)
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(content)
	_art = _ControlArt.new()
	_art.custom_minimum_size = Vector2(ART_WIDTH, 0)
	content.add_child(_art)

	_info_panel = PanelContainer.new()
	_info_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var style := UiTheme.panel_style(UiTheme.PAPER, UiTheme.RADIUS + 8, 28)
	style.content_margin_left = 30
	style.content_margin_right = 30
	_info_panel.add_theme_stylebox_override("panel", style)
	content.add_child(_info_panel)
	var info_box := VBoxContainer.new()
	info_box.add_theme_constant_override("separation", 10)
	_info_panel.add_child(info_box)
	_steps = VBoxContainer.new()
	_steps.add_theme_constant_override("separation", 12)
	_steps.size_flags_vertical = Control.SIZE_EXPAND_FILL
	info_box.add_child(_steps)
	var divider := _Divider.new()
	divider.custom_minimum_size = Vector2(0, 14)
	info_box.add_child(divider)
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 14)
	info_box.add_child(header)
	header.add_child(GlyphBadge.new("people", UiTheme.BRICKS[5], UiTheme.PAPER, 44))
	_players_label = UiTheme.label("", 30, UiTheme.INK, true, HORIZONTAL_ALIGNMENT_LEFT)
	header.add_child(_players_label)
	_ready_hint = UiTheme.label("", 26, UiTheme.INK_SOFT, true, HORIZONTAL_ALIGNMENT_LEFT)
	_ready_hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(_ready_hint)
	var head_room := Control.new()  # Las cabezas de las mascotas asoman por arriba de las tarjetas.
	head_room.custom_minimum_size = Vector2(0, 14)
	info_box.add_child(head_room)
	_players_row = HBoxContainer.new()
	_players_row.add_theme_constant_override("separation", 18)
	info_box.add_child(_players_row)

	_footer = HBoxContainer.new()
	_footer.add_theme_constant_override("separation", 22)
	col.add_child(_footer)
	var hints := KeyHint.new()
	hints.add_hint(["OK"], "Empezar ya").add_hint(["Atrás"], "Menú")
	hints.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_footer.add_child(hints)
	_ring = _CountdownRing.new()
	_ring.custom_minimum_size = Vector2(104, 104)
	_ring.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_footer.add_child(_ring)
	var sparkle_room := Control.new()  # Lugar para los destellos de "¡A jugar!".
	sparkle_room.custom_minimum_size = Vector2(56, 0)
	_footer.add_child(sparkle_room)
	_continue = TvButton.new("¡A jugar!", UiTheme.ACCENT, "play")
	_continue.hero = true
	_continue.font_px = 44
	_continue.custom_minimum_size = Vector2(470, 124)
	_continue.pressed.connect(_on_continue)
	_footer.add_child(_continue)


## "(?) ¿Cómo se juega?": pastilla blanca con el signo en un círculo.
class _HowPill:
	extends Control
	const TEXT := "¿Cómo se juega?"
	const FONT := 34

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		var w := UiTheme.FONT_BOLD.get_string_size(TEXT, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT).x
		custom_minimum_size = Vector2(w + 110, 62)

	func _draw() -> void:
		var r := Rect2(Vector2(4, 4), size - Vector2(8, 12))
		UiTheme.draw_bevel(self, r, UiTheme.PAPER, r.size.y / 2.0, false, UiTheme.INK, 6.0, 3.0)
		var c := Vector2(r.position.x + r.size.y / 2.0 + 2.0, r.get_center().y)
		UiTheme.draw_bevel_circle(self, c, r.size.y / 2.0 - 8.0, UiTheme.BRICKS[5])
		UiTheme.draw_screen_glyph(self, "question", c - Vector2(0, 2), r.size.y * 0.5, UiTheme.PAPER)
		var left := c.x + r.size.y / 2.0
		UiTheme.draw_text(self, TEXT, Vector2((left + r.end.x - 14.0) / 2.0, r.get_center().y), FONT, UiTheme.INK)


## Ícono de un paso: círculo con bisel y el dibujo encima. "control" es el
## ícono del control del juego (joystick, botón, slider).
class _StepIcon:
	extends Control
	var glyph := ""
	var layout := ""
	var color := UiTheme.ACCENT

	func _draw() -> void:
		var c := size / 2.0
		var r := minf(size.x, size.y) / 2.0 - UiTheme.BEVEL_OUTLINE - 2.0
		UiTheme.draw_bevel_circle(self, c, r, color)
		c.y -= 3.0
		match glyph:
			"control":
				UiTheme.draw_control_icon(self, c, r * (0.42 if layout == Protocol.LAYOUT_SLIDER_H else 0.5), layout)
			"tag":
				UiTheme.draw_text(self, "1P", c, int(r * 0.9), UiTheme.PAPER, 5, UiTheme.INK)
			_:
				UiTheme.draw_screen_glyph(self, glyph, c, r * 1.1, UiTheme.PAPER)


## Línea punteada que separa los pasos de los jugadores.
class _Divider:
	extends Control

	func _draw() -> void:
		var y := size.y / 2.0
		UiTheme.draw_dashed_line(self, Vector2(0, y), Vector2(size.x, y), UiTheme.PAPER_DIM.darkened(0.08), 4.0, 16.0, 12.0)


## Ilustración grande: la foto del juego con un celular apaisado encima,
## un poco inclinado, que muestra el control del juego "de juguete" con
## flechas que indican cómo se mueve. Sin foto, el celular va grande en el
## centro. Un aro que late sobre el control dice "tocá acá" (con reducir
## movimiento queda quieto).
class _ControlArt:
	extends Control
	const TILT := -0.07
	var layout := ""
	var accent := UiTheme.ACCENT
	var thumb: Texture2D
	var _pulse: Node2D
	var _t := 0.0
	var _since := 0.0

	func _init() -> void:
		texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		_pulse = Node2D.new()
		_pulse.draw.connect(_draw_pulse)
		add_child(_pulse)
		resized.connect(queue_redraw)

	func _notification(what: int) -> void:
		if what == NOTIFICATION_VISIBILITY_CHANGED and is_inside_tree():
			set_process(is_visible_in_tree())

	func _process(delta: float) -> void:
		if UiTheme.reduce_motion:
			_pulse.scale = Vector2.ONE
			_pulse.modulate.a = 0.8
			return
		_t += delta
		_since += delta
		if _since < 1.0 / 30.0:  # Solo cambia escala y opacidad, a 30 cuadros por segundo.
			return
		_since = 0.0
		var k := fmod(_t, 1.2) / 1.2
		_pulse.scale = Vector2.ONE * (0.85 + 0.55 * k)
		_pulse.modulate.a = 1.0 - k

	func _card() -> Rect2:
		return Rect2(Vector2(6, 6), size - Vector2(12, 16))

	func _draw() -> void:
		var r := _card()
		UiTheme.draw_round_rect(self, r.grow(4), UiTheme.INK, UiTheme.RADIUS + 12, 0, UiTheme.INK, true)
		UiTheme.draw_round_rect(self, r, UiTheme.PAPER, UiTheme.RADIUS + 8)
		var hint_y := r.end.y - 38.0
		var caption := "Tu celular ya muestra este control"
		var cw := UiTheme.FONT_BOLD.get_string_size(caption, HORIZONTAL_ALIGNMENT_LEFT, -1, 28).x
		var cx := r.get_center().x + 22.0
		UiTheme.draw_phone_glyph(self, "phone", Vector2(cx - cw / 2.0 - 30.0, hint_y), 38, UiTheme.INK_SOFT)
		UiTheme.draw_text(self, caption, Vector2(cx, hint_y), 28, UiTheme.INK_SOFT)
		var chip_pos := r.position + Vector2(28, 24)
		var phone: Rect2
		if thumb != null:
			# Foto arriba (hasta el texto) y el celular abajo a la derecha, encima.
			var photo := Rect2(r.position + Vector2(14, 14), Vector2(r.size.x - 28, hint_y - 34 - r.position.y - 14))
			GameCard.draw_thumbnail(self, thumb, photo, UiTheme.RADIUS, Color.WHITE, UiTheme.PAPER)
			var h := photo.size.y * 0.44
			phone = Rect2(photo.end - Vector2(h * 2.05, h) - Vector2(22, 10), Vector2(h * 2.05, h))
			chip_pos = photo.position + Vector2(18, 18)
		else:
			var top := chip_pos.y + 74.0
			var avail := Rect2(r.position.x + 40, top, r.size.x - 80, hint_y - 40 - top)
			var h := minf(avail.size.y, avail.size.x / 2.05)
			phone = Rect2(avail.get_center() - Vector2(h * 2.05, h) / 2.0, Vector2(h * 2.05, h))
		_draw_phone(phone)
		var name: String = GameCard.CONTROL_NAMES.get(layout, "Control")
		var fs := 30
		var chip_w := UiTheme.FONT_BOLD.get_string_size(name, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x + 90.0
		var chip := Rect2(chip_pos, Vector2(chip_w, 56))
		UiTheme.draw_bevel(self, chip, accent, 28.0, false, UiTheme.INK, 6.0, 3.0)
		UiTheme.draw_control_icon(self, chip.position + Vector2(30, 28), 14.0, layout)
		UiTheme.draw_text(self, name, chip.position + Vector2(chip_w / 2.0 + 22.0, 27), fs, UiTheme.PAPER, 6, UiTheme.INK)

	## Celular apaisado (inclinado) con el control del juego en la pantalla.
	func _draw_phone(phone: Rect2) -> void:
		var h := phone.size.y
		var pivot := phone.get_center()
		var xf := Transform2D(TILT, pivot)
		var local := Rect2(phone.position - pivot, phone.size)
		# Sombra difusa en el piso, sin rotar.
		UiTheme.draw_round_rect(self, Rect2(phone.position + Vector2(10, 14), phone.size), UiTheme.SHADOW, h * 0.2)
		draw_set_transform_matrix(xf)
		UiTheme.draw_round_rect(self, local.grow(5), UiTheme.INK, h * 0.2)
		UiTheme.draw_round_rect(self, local, UiTheme.KEY_CAP, h * 0.18)
		UiTheme.draw_gradient_round_rect(self, Rect2(local.position + Vector2(h * 0.1, 4), Vector2(local.size.x - h * 0.2, h * 0.2)),
			Color(UiTheme.PAPER, 0.28), Color(UiTheme.PAPER, 0.0), h * 0.08)
		var screen := local.grow(-h * 0.07)
		screen.position.x += h * 0.06
		screen.size.x -= h * 0.12
		UiTheme.draw_gradient_round_rect(self, screen, accent.lightened(0.12), accent.darkened(0.12), h * 0.1)
		var dot := Color(UiTheme.PAPER, 0.16)
		var step := clampf(h * 0.16, 26.0, 48.0)
		var batch := UiTheme.ShapeBatch.new()
		var y := screen.position.y + step * 0.5
		var row := 0
		while y < screen.end.y - 12.0:
			var x := screen.position.x + (step * 0.5 if row % 2 == 0 else step)
			while x < screen.end.x - 14.0:
				batch.circle(Vector2(x, y), step * 0.12, dot)
				x += step
			y += step * 0.58
			row += 1
		batch.flush(self)
		draw_circle(Vector2(local.position.x + h * 0.035, 0), h * 0.02, UiTheme.INK_SOFT)
		var c := screen.get_center()
		var s := screen.size.y * (0.2 if layout == Protocol.LAYOUT_JOYSTICK else 0.26)
		_draw_control(c, s)
		_draw_motion_hints(c, s)
		draw_set_transform_matrix(Transform2D.IDENTITY)
		# El aro que late va centrado sobre el control (en coordenadas sin rotar).
		_pulse.position = xf * c
		_pulse.set_meta("r", s * 1.25)
		_pulse.queue_redraw()

	## Control "de juguete" (bisel y brillo), como el que ve el celular.
	func _draw_control(c: Vector2, s: float) -> void:
		match layout:
			Protocol.LAYOUT_JOYSTICK:
				draw_circle(c, s * 1.28 + 5.0, UiTheme.INK)
				draw_circle(c, s * 1.28, UiTheme.PHONE_DISH)
				draw_arc(c, s * 1.1, 0.0, TAU, 40, UiTheme.PHONE_DISH_RIM, 4.0, true)
				UiTheme.draw_toy_disc(self, c + Vector2(s * 0.3, -s * 0.26), s * 0.62, UiTheme.PAPER)
			Protocol.LAYOUT_SLIDER_H:
				var track := Rect2(c.x - s * 1.7, c.y - s * 0.2, s * 3.4, s * 0.4)
				UiTheme.draw_round_rect(self, track.grow(5), UiTheme.INK, s * 0.26)
				UiTheme.draw_round_rect(self, track, UiTheme.PHONE_DISH, s * 0.2)
				UiTheme.draw_toy_disc(self, Vector2(c.x + s * 0.5, c.y - s * 0.08), s * 0.5, UiTheme.PAPER)
			Protocol.LAYOUT_ONE_BUTTON:
				var face := UiTheme.draw_toy_disc(self, c - Vector2(0, s * 0.1), s, UiTheme.DANGER)
				UiTheme.draw_text(self, "A", face, int(s * 0.9), UiTheme.PAPER, 6, UiTheme.INK)
			_:
				UiTheme.draw_star(self, c, s, UiTheme.PAPER)

	## Flechas que dicen cómo se usa el control.
	func _draw_motion_hints(c: Vector2, s: float) -> void:
		var arrow := s * 0.42
		match layout:
			Protocol.LAYOUT_JOYSTICK:
				for d in [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]:
					UiTheme.draw_arrow(self, c + d * s * 1.75, arrow + 7.0, d, UiTheme.INK)
					UiTheme.draw_arrow(self, c + d * s * 1.75, arrow, d, UiTheme.PAPER)
			Protocol.LAYOUT_SLIDER_H:
				for d in [Vector2.LEFT, Vector2.RIGHT]:
					UiTheme.draw_arrow(self, c + d * s * 2.25, arrow + 7.0, d, UiTheme.INK)
					UiTheme.draw_arrow(self, c + d * s * 2.25, arrow, d, UiTheme.PAPER)

	func _draw_pulse() -> void:
		var r := float(_pulse.get_meta("r", 40.0))
		_pulse.draw_arc(Vector2.ZERO, r, 0.0, TAU, 40, UiTheme.PAPER, 6.0, true)


## Cuenta regresiva: disco con bisel, un aro que se vacía y los segundos.
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
		var r := minf(size.x, size.y) / 2.0 - UiTheme.BEVEL_OUTLINE - 4.0
		UiTheme.draw_bevel_circle(self, c, r, UiTheme.PAPER)
		c.y -= 3.0
		var width := 12.0
		var ring_r := r - 12.0
		draw_arc(c, ring_r, 0.0, TAU, 48, UiTheme.PAPER_DIM.darkened(0.06), width, true)
		if fraction > 0.0:
			draw_arc(c, ring_r, -PI / 2.0, -PI / 2.0 + TAU * fraction, 48, UiTheme.WARNING, width, true)
		UiTheme.draw_text(self, str(seconds), c, int(r * 0.95), UiTheme.INK)
