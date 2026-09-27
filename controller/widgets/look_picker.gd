class_name LookPicker
extends PanelContainer
## Selector de apariencia del celular: estilo de mascota (◀ Robot ▶) y una
## grilla con los colores de Protocol.MASCOT_COLORS. Se muestra mientras se
## espera en el lobby, al lado de la mascota grande, que hace de vista previa
## en vivo (ControllerMain la actualiza con cada toque).
##
## Solo elige la apariencia: la TV confirma con "appearance" y es la que
## decide si un color está libre (ver docs/adr/0007-apariencia-del-jugador.md).
## Los colores que usan otros se ven tachados y no se pueden tocar.

## El jugador tocó una flecha o un color (ya validado y distinto del actual).
signal look_changed(color_index: int, style: int)

const COLUMNS := 5

var color_index := 0
var style := 0
var taken: Array[int] = []

var _style_label: Label
var _color_label: Label
var _swatches: Array[_Swatch] = []


func _init() -> void:
	add_theme_stylebox_override("panel", UiTheme.panel_style(UiTheme.PAPER, UiTheme.RADIUS + 8, 36))
	size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 22)
	add_child(col)
	col.add_child(UiTheme.label("Tu mascota", 44, UiTheme.INK_SOFT, true))

	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 20)
	col.add_child(row)
	row.add_child(_arrow(Vector2.LEFT, -1))
	_style_label = UiTheme.label("", 60, UiTheme.INK, true)
	_style_label.custom_minimum_size = Vector2(UiTheme.TOUCH_TARGET * 3.4, 0)
	row.add_child(_style_label)
	row.add_child(_arrow(Vector2.RIGHT, 1))

	var grid := GridContainer.new()
	grid.columns = COLUMNS
	grid.add_theme_constant_override("h_separation", 22)
	grid.add_theme_constant_override("v_separation", 22)
	grid.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	col.add_child(grid)
	for i in Protocol.MASCOT_COLORS.size():
		var sw := _Swatch.new()
		sw.index = i
		sw.custom_minimum_size = Vector2.ONE * UiTheme.TOUCH_TARGET
		sw.pressed.connect(_on_color_pressed.bind(i))
		grid.add_child(sw)
		_swatches.append(sw)
	_color_label = UiTheme.label("", 38, UiTheme.INK_SOFT, true)
	col.add_child(_color_label)
	_refresh()


## Muestra la apariencia que confirmó la TV (no emite look_changed).
## Los índices inválidos se recortan: nunca falla por datos de la red.
func set_look(p_color_index: int, p_style: int, p_taken: Array = []) -> void:
	color_index = clampi(p_color_index, 0, Protocol.MASCOT_COLORS.size() - 1)
	style = posmod(p_style, Protocol.MASCOT_STYLES)
	taken.clear()
	for i: Variant in p_taken:
		if Protocol.parse_color_index(i) >= 0:
			taken.append(int(i))
	_refresh()


## Paso de estilo con las flechas (da la vuelta: después de Conejo, Antena).
func step_style(direction: int) -> void:
	style = posmod(style + direction, Protocol.MASCOT_STYLES)
	_refresh()
	look_changed.emit(color_index, style)


func _on_color_pressed(i: int) -> void:
	if i == color_index or i in taken:
		return
	color_index = i
	_refresh()
	look_changed.emit(color_index, style)


func _refresh() -> void:
	_style_label.text = PlayerAvatar.STYLE_NAMES[posmod(style, PlayerAvatar.STYLE_NAMES.size())]
	_color_label.text = Protocol.MASCOT_COLOR_NAMES[color_index]
	for sw in _swatches:
		sw.selected = sw.index == color_index
		sw.disabled = sw.index in taken and not sw.selected
		sw.queue_redraw()


func _arrow(dir: Vector2, step: int) -> _Arrow:
	var b := _Arrow.new()
	b.dir = dir
	b.custom_minimum_size = Vector2.ONE * UiTheme.TOUCH_TARGET
	b.pressed.connect(step_style.bind(step))
	return b


## Flecha "de juguete" grande (≥ 88 px) para cambiar de estilo.
class _Arrow:
	extends BaseButton
	var dir := Vector2.RIGHT

	func _init() -> void:
		focus_mode = Control.FOCUS_NONE
		button_down.connect(queue_redraw)
		button_up.connect(queue_redraw)

	func _draw() -> void:
		var down := get_draw_mode() in [DRAW_PRESSED, DRAW_HOVER_PRESSED]
		var depth := 3.0 if down else 9.0
		var r := Rect2(Vector2(0, 9.0 - depth), size - Vector2(0, 9.0))
		UiTheme.draw_round_rect(self, Rect2(Vector2(0, 9.0), size - Vector2(0, 9.0)), UiTheme.ACCENT.darkened(0.25), UiTheme.RADIUS)
		UiTheme.draw_round_rect(self, r, UiTheme.ACCENT, UiTheme.RADIUS, 4, UiTheme.INK)
		UiTheme.draw_arrow(self, r.get_center(), r.size.y * 0.5, dir, UiTheme.INK)


## Círculo de color tocable. Seleccionado: anillo de foco y tilde.
## Ocupado por otro jugador: apagado y tachado.
class _Swatch:
	extends BaseButton
	var index := 0
	var selected := false

	func _init() -> void:
		focus_mode = Control.FOCUS_NONE

	func _draw() -> void:
		var c := size / 2.0
		var r := minf(size.x, size.y) / 2.0 - UiTheme.FOCUS_WIDTH - 2.0
		var col := Protocol.mascot_color(index)
		var a := 0.35 if disabled else 1.0
		if selected:
			draw_circle(c, r + UiTheme.FOCUS_WIDTH + 2.0, UiTheme.ACCENT)
		draw_circle(c, r, Color(UiTheme.INK, a))
		draw_circle(c, r - 4.0, Color(col, a))
		draw_circle(c + Vector2(-r, -r) * 0.32, r * 0.22, Color(1, 1, 1, 0.35 * a))
		# Tilde con contraste: tinta sobre colores claros, papel sobre oscuros.
		var mark := UiTheme.INK if col.get_luminance() > 0.5 else UiTheme.PAPER
		if selected:
			UiTheme.draw_check(self, c, r * 0.9, mark, 8.0)
		elif disabled:
			draw_line(c + Vector2(-r, r) * 0.6, c + Vector2(r, -r) * 0.6, UiTheme.INK, 6.0, true)
