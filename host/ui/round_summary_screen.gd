class_name RoundSummaryScreen
extends Control
## Resumen al terminar cada minijuego de la competencia:
##
##   [1P|mascota|130] [2P|…|180] (Ronda 2/3) [3P|…|170] [4P|…|120]  <- totales (cuentan)
##               ARENA DE ESTRELLAS
##     (+100)      (+70)      (+50)      (+30)          <- placa con los puntos de esta ronda
##      (mascota)   (mascota)  (mascota)  (mascota)
##      [1° | 12]   [2° | 9]   [3° | 7]   [4° | 3]       <- puesto y puntaje del juego
##     (1P Pablo)  (2P Sofi)  (3P Tomi)  (4P Juli)      <- chapita del jugador
##   Siguiente: Ping Pong                  [Continuar · 12]
##
## El marcador de arriba es el de los juegos (ScoreBar → GameArt.paint_hud).
## La placa de puntos queda siempre arriba de la mascota con un espacio
## (POINTS_BADGE_GAP) que cubre orejas y antena: nunca se pisan.
##
## Revelado en orden inverso (del último al primero) para generar
## suspenso; al final salta el ganador y los totales se actualizan.
## Avanza con OK o solo, a los AUTO_CONTINUE_SEC segundos.

signal continue_requested

const AUTO_CONTINUE_SEC := 15.0
const REVEAL_GAP := 0.45

var paused := false  ## Con el menú de pausa abierto no corre la cuenta regresiva.

var _bar: ScoreBar
var _title: TvLogoTitle
var _subtitle: Label
var _helps: Label  ## "Ayudas: Tomi −10 por ayudar a Sofi" (ADR 0020); oculta si no hubo.
var _columns: HBoxContainer
var _next: Label
var _continue: Button
var _time_left := 0.0
var _active := false
var _continue_text := ""
var _tween: Tween


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	visible = false
	_build()


## summary: Tournament.record(). standings: Tournament.standings().
## next_title: título del próximo juego, o "" si era la última ronda.
func show_summary(summary: Dictionary, standings: Array[Dictionary], next_title: String) -> void:
	visible = true
	paused = false
	var rows: Array = summary.get("rows", [])
	var gained := {}
	for row: Dictionary in rows:
		gained[row.id] = row.points
	var bar_rows: Array[Dictionary] = []
	var totals := {}
	for s in standings:
		bar_rows.append({"id": s.id, "slot": s.slot, "color": s.color, "style": PlayerAvatar.style_of(s),
			"total": s.total - int(gained.get(s.id, 0))})
		totals[s.id] = s.total
	_bar.setup(bar_rows, "Ronda %d/%d" % [summary.round, summary.total_rounds])

	_title.text = str(summary.get("title", ""))
	_subtitle.text = "Resultados de la ronda %d" % summary.round
	_helps.text = helps_line(summary.get("helps", []))
	_helps.visible = not _helps.text.is_empty()
	if next_title.is_empty():
		_next.text = "¡Fue la última ronda!"
		_continue_text = "Ver el podio"
	else:
		_next.text = "Siguiente: %s" % next_title
		_continue_text = "Continuar"

	for c in _columns.get_children():
		c.queue_free()
	var columns: Array[Dictionary] = []
	var last_place := 0
	for row: Dictionary in rows:
		last_place = maxi(last_place, row.place)
	for row: Dictionary in rows:
		columns.append(_make_column(row, str(summary.get("score_label", "")), rows.size(), last_place))

	_time_left = AUTO_CONTINUE_SEC
	_active = true
	_continue.grab_focus()
	_reveal(columns, totals)


func focus_continue() -> void:
	_continue.grab_focus()


func hide_summary() -> void:
	_active = false
	visible = false


func _process(delta: float) -> void:
	if not _active or paused:
		return
	_time_left -= delta
	_continue.text = "%s · %d" % [_continue_text, ceili(maxf(_time_left, 0.0))]
	if _time_left <= 0.0:
		_on_continue()


func _on_continue() -> void:
	if not _active:
		return
	_active = false
	continue_requested.emit()


# --- Animación ------------------------------------------------------------------

func _reveal(columns: Array[Dictionary], totals: Dictionary) -> void:
	# Orden de revelado: del peor puesto al mejor.
	var order := columns.duplicate()
	order.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.place > b.place)
	if _tween:
		_tween.kill()
	await get_tree().process_frame  # Esperar el layout para conocer tamaños (pivotes).
	_tween = create_tween()
	var tw: Tween = _tween
	var delay := 0.3
	for col: Dictionary in order:
		var badge: PointsBadge = col.delta
		var pedestal: ScorePedestal = col.pedestal
		badge.pivot_offset = badge.size / 2.0
		tw.parallel().tween_property(badge, "modulate:a", 1.0, 0.15).set_delay(delay)
		tw.parallel().tween_property(badge, "scale", Vector2.ONE, 0.35) \
			.from(Vector2(0.2, 0.2)).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT).set_delay(delay)
		tw.parallel().tween_callback(pedestal.light_up).set_delay(delay)
		# Cuanto mejor el puesto, más agudo el "pop": se escucha la escalera.
		var pitch := 1.0 + 0.12 * (4 - int(col.place))
		tw.parallel().tween_callback(func() -> void: Sfx.play("pop", 0.0, pitch)).set_delay(delay)
		delay += REVEAL_GAP
	tw.parallel().tween_callback(func() -> void:
		_bar.count_to(totals)
		Sfx.play("win")
		for col: Dictionary in columns:
			if col.place == 1:
				(col.avatar as PlayerAvatar).hop(3)).set_delay(delay)


func _make_column(row: Dictionary, unit: String, count: int, last_place: int) -> Dictionary:
	var col := VBoxContainer.new()
	col.custom_minimum_size = Vector2(330, 0)
	col.add_theme_constant_override("separation", 0)
	col.alignment = BoxContainer.ALIGNMENT_END
	_columns.add_child(col)

	var color: Color = row.color
	# Placa de puntos, y debajo aire para orejas y antena: la mascota nunca
	# queda detrás del número.
	var delta := PointsBadge.make("+%d" % row.points, color)
	delta.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	delta.modulate.a = 0.0
	col.add_child(delta)
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, UiTheme.POINTS_BADGE_GAP)
	gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(gap)

	var avatar := PlayerAvatar.new()
	avatar.slot = row.slot
	avatar.style = PlayerAvatar.style_of(row)
	avatar.color = color
	avatar.custom_minimum_size = Vector2(230, 224)
	if count > 1 and row.place == 1:
		avatar.mood = PlayerAvatar.Mood.HAPPY
	elif count > 1 and row.place == last_place:
		avatar.mood = PlayerAvatar.Mood.SAD
	col.add_child(avatar)
	if row.get("bot", false):
		avatar.add_child(BotBadge.new())  # Placa "BOT" (ADR 0010).

	var pedestal := ScorePedestal.new()
	pedestal.color = color
	pedestal.score_text = _format_score(row.score)
	pedestal.unit = unit
	pedestal.place = row.place
	pedestal.custom_minimum_size = Vector2(280, 184)
	col.add_child(pedestal)

	# Chapita [1P | nombre]: draw_string, texto plano (sin BBCode).
	var plate := NamePlate.make(row.slot, color, str(row.name))
	plate.custom_minimum_size.x = 0.0  # Ocupa el ancho de la columna (recorta con "…").
	col.add_child(plate)
	return {"place": row.place, "delta": delta, "avatar": avatar, "pedestal": pedestal}


## Línea de ayudas del resumen: "Ayudas: Tomi −10 por ayudar a Sofi · …".
## Nada secreto: cada ayuda con quién, a quién y cuánto costó. "" si no hubo.
static func helps_line(helps: Variant) -> String:
	if not helps is Array:
		return ""
	var parts: Array[String] = []
	for h: Variant in helps:
		if h is Dictionary:
			parts.append("%s −%d por ayudar a %s" % [str(h.get("helper_name", "")), int(h.get("points", 0)),
				str(h.get("target_name", ""))])
	return "" if parts.is_empty() else "Ayudas: " + " · ".join(parts)


static func _format_score(score: Variant) -> String:
	var f := float(score)
	return str(int(f)) if is_equal_approx(f, roundf(f)) else "%.1f" % f


# --- UI -------------------------------------------------------------------------

func _build() -> void:
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right"]:
		margin.add_theme_constant_override("margin_" + side, UiTheme.SAFE_MARGIN)
	margin.add_theme_constant_override("margin_top", 40)  # El marcador ya trae su aire.
	margin.add_theme_constant_override("margin_bottom", 58)
	add_child(margin)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	margin.add_child(col)

	_bar = ScoreBar.new()
	col.add_child(_bar)
	# Título "de logo" (letras amarillas con brillo), como en la intro y el lobby.
	_title = TvLogoTitle.new("", UiTheme.SUMMARY_TITLE_SIZE)
	col.add_child(_title)
	_subtitle = UiTheme.label("", 30, UiTheme.INK, true)
	_subtitle.add_theme_constant_override("outline_size", 8)
	_subtitle.add_theme_color_override("font_outline_color", UiTheme.PAPER)
	col.add_child(_subtitle)
	_helps = UiTheme.label("", UiTheme.HELP_SUMMARY_FONT, UiTheme.HELP_BANNER_COST, true)
	_helps.add_theme_constant_override("outline_size", 8)
	_helps.add_theme_color_override("font_outline_color", UiTheme.PAPER)
	_helps.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_helps.visible = false
	col.add_child(_helps)

	_columns = HBoxContainer.new()
	_columns.alignment = BoxContainer.ALIGNMENT_CENTER
	_columns.add_theme_constant_override("separation", 40)
	_columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(_columns)

	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", 24)
	col.add_child(footer)
	var next_panel := PanelContainer.new()
	next_panel.add_theme_stylebox_override("panel", UiTheme.panel_style(UiTheme.PAPER, 28, 18))
	_next = UiTheme.label("", 32, UiTheme.INK, true)
	next_panel.add_child(_next)
	footer.add_child(next_panel)
	var hints := KeyHint.new()
	hints.add_hint(["OK"], "Continuar").add_hint(["Atrás"], "Menú")
	hints.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hints.alignment = BoxContainer.ALIGNMENT_CENTER
	footer.add_child(hints)
	_continue = Button.new()
	_continue.custom_minimum_size = Vector2(420, 92)
	_continue.add_theme_font_size_override("font_size", 36)
	_continue.add_theme_stylebox_override("normal", UiTheme.button_style(UiTheme.ACCENT))
	_continue.add_theme_stylebox_override("hover", UiTheme.button_style(UiTheme.ACCENT.lightened(0.1)))
	_continue.add_theme_stylebox_override("pressed", UiTheme.button_style(UiTheme.ACCENT, true))
	_continue.pressed.connect(_on_continue)
	footer.add_child(_continue)
