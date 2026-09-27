class_name RoundSummaryScreen
extends Control
## Resumen al terminar cada minijuego de la competencia:
##
##   [1P 130] [2P 180] [ Ronda 2/3 ] [3P 170] [4P 120]   <- totales (cuentan hacia arriba)
##               ARENA DE ESTRELLAS
##      +100        +70        +50        +30           <- puntos ganados esta ronda
##      (mascota)   (mascota)  (mascota)  (mascota)
##      [1° | 12]   [2° | 9]   [3° | 7]   [4° | 3]       <- puesto y puntaje del juego
##        Pablo       Sofi       Tomi       Juli
##   Siguiente: Ping Pong                  [Continuar · 12]
##
## Revelado en orden inverso (del último al primero) para generar
## suspenso; al final salta el ganador y los totales se actualizan.
## Avanza con OK o solo, a los AUTO_CONTINUE_SEC segundos.

signal continue_requested

const AUTO_CONTINUE_SEC := 15.0
const REVEAL_GAP := 0.45

var paused := false  ## Con el menú de pausa abierto no corre la cuenta regresiva.

var _bar: ScoreBar
var _title: Label
var _subtitle: Label
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
		bar_rows.append({"id": s.id, "slot": s.slot, "color": s.color, "total": s.total - int(gained.get(s.id, 0))})
		totals[s.id] = s.total
	_bar.setup(bar_rows, "Ronda %d/%d" % [summary.round, summary.total_rounds])

	_title.text = str(summary.get("title", ""))
	_subtitle.text = "Resultados de la ronda %d" % summary.round
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
		var delta_label: Label = col.delta
		var pedestal: ScorePedestal = col.pedestal
		delta_label.pivot_offset = delta_label.size / 2.0
		tw.parallel().tween_property(delta_label, "modulate:a", 1.0, 0.15).set_delay(delay)
		tw.parallel().tween_property(delta_label, "scale", Vector2.ONE, 0.35) \
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
	var delta := UiTheme.headline("+%d" % row.points, 96, color, UiTheme.PAPER)
	delta.add_theme_color_override("font_shadow_color", UiTheme.INK)
	delta.add_theme_constant_override("shadow_offset_y", 6)
	delta.modulate.a = 0.0
	col.add_child(delta)

	var avatar := PlayerAvatar.new()
	avatar.slot = row.slot
	avatar.style = PlayerAvatar.style_of(row)
	avatar.color = color
	avatar.custom_minimum_size = Vector2(250, 250)
	if count > 1 and row.place == 1:
		avatar.mood = PlayerAvatar.Mood.HAPPY
	elif count > 1 and row.place == last_place:
		avatar.mood = PlayerAvatar.Mood.SAD
	col.add_child(avatar)

	var pedestal := ScorePedestal.new()
	pedestal.color = color
	pedestal.score_text = _format_score(row.score)
	pedestal.unit = unit
	pedestal.place = row.place
	pedestal.custom_minimum_size = Vector2(280, 200)
	col.add_child(pedestal)

	var name_label := UiTheme.headline(row.name, 40)  # Label: texto plano, sin BBCode.
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name_label.custom_minimum_size = Vector2(320, 64)
	col.add_child(name_label)
	return {"place": row.place, "delta": delta, "avatar": avatar, "pedestal": pedestal}


static func _format_score(score: Variant) -> String:
	var f := float(score)
	return str(int(f)) if is_equal_approx(f, roundf(f)) else "%.1f" % f


# --- UI -------------------------------------------------------------------------

func _build() -> void:
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right"]:
		margin.add_theme_constant_override("margin_" + side, UiTheme.SAFE_MARGIN)
	margin.add_theme_constant_override("margin_top", 52)
	margin.add_theme_constant_override("margin_bottom", 58)
	add_child(margin)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	margin.add_child(col)

	_bar = ScoreBar.new()
	col.add_child(_bar)
	_title = UiTheme.headline("", 76)
	col.add_child(_title)
	_subtitle = UiTheme.label("", 30, UiTheme.INK, true)
	_subtitle.add_theme_constant_override("outline_size", 8)
	_subtitle.add_theme_color_override("font_outline_color", UiTheme.PAPER)
	col.add_child(_subtitle)

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
