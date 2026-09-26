class_name FinalScreen
extends Control
## Podio al terminar la competencia: 2° – 1° – 3° (el 1° más alto, en el
## centro), el 4° abajo, confeti y dos opciones:
##   "Jugar otra vez"   -> misma selección de juegos y jugadores
##   "Cambiar juegos"   -> vuelve al lobby

signal play_again_requested
signal lobby_requested

const PODIUM_HEIGHTS: Array[float] = [190.0, 140.0, 105.0]

var _confetti: Confetti
var _title: Label
var _podium: HBoxContainer
var _others: HBoxContainer
var _games: Label
var _again: Button


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	visible = false
	_build()


## standings: Tournament.standings(). game_titles: juegos que se jugaron.
func show_final(standings: Array[Dictionary], game_titles: Array[String]) -> void:
	visible = true
	for c in _podium.get_children() + _others.get_children():
		c.queue_free()
	var champions: Array[String] = []
	for s in standings:
		if s.place == 1:
			champions.append(s.name)
	if champions.size() == 1:
		_title.text = "¡%s gana la competencia!" % champions[0]
	elif champions.size() > 1:
		_title.text = "¡Empate! %s" % " y ".join(champions)
	else:
		_title.text = "Fin de la competencia"

	# Orden visual del podio: 2°, 1°, 3° (índices 1, 0, 2 de la tabla).
	for idx in [1, 0, 2]:
		if idx < standings.size():
			_podium.add_child(_podium_column(standings[idx], idx))
	for i in range(3, standings.size()):
		var s: Dictionary = standings[i]
		var chip := PanelContainer.new()
		chip.add_theme_stylebox_override("panel", UiTheme.panel_style(UiTheme.PAPER, 28, 16))
		chip.add_child(UiTheme.label("%s  %s · %d pts" % [UiTheme.place_text(s.place), s.name, s.total], 30, UiTheme.INK, true))
		_others.add_child(chip)
	_games.text = "Se jugó: " + " · ".join(game_titles) if not game_titles.is_empty() else ""
	_confetti.burst()
	Sfx.play("fanfare")
	_again.grab_focus()


func hide_final() -> void:
	visible = false


func _podium_column(s: Dictionary, index: int) -> Control:
	var col := VBoxContainer.new()
	col.alignment = BoxContainer.ALIGNMENT_END
	col.add_theme_constant_override("separation", 0)
	col.custom_minimum_size = Vector2(360, 0)
	if index == 0:
		var crown := _Crown.new()
		crown.custom_minimum_size = Vector2(0, 70)
		col.add_child(crown)
	var avatar := PlayerAvatar.new()
	avatar.slot = s.slot
	avatar.color = s.color
	avatar.mood = PlayerAvatar.Mood.HAPPY if s.place == 1 else PlayerAvatar.Mood.NORMAL
	avatar.custom_minimum_size = Vector2(260, 250 if index == 0 else 210)
	col.add_child(avatar)
	if s.place == 1:
		avatar.ready.connect(func() -> void: avatar.hop(4))
	var name_label := UiTheme.headline(s.name, 44)
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name_label.custom_minimum_size = Vector2(340, 64)
	col.add_child(name_label)
	var points := UiTheme.headline("%d pts" % s.total, 34, UiTheme.ACCENT)
	col.add_child(points)
	var block := _Block.new()
	block.color = s.color
	block.place = s.place
	block.custom_minimum_size = Vector2(340, PODIUM_HEIGHTS[index])
	col.add_child(block)
	return col


func _build() -> void:
	_confetti = Confetti.new()
	add_child(_confetti)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right"]:
		margin.add_theme_constant_override("margin_" + side, UiTheme.SAFE_MARGIN)
	margin.add_theme_constant_override("margin_top", 56)
	margin.add_theme_constant_override("margin_bottom", 66)
	add_child(margin)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 14)
	margin.add_child(col)
	_title = UiTheme.headline("", 72, UiTheme.ACCENT)
	_title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	col.add_child(_title)
	_podium = HBoxContainer.new()
	_podium.alignment = BoxContainer.ALIGNMENT_CENTER
	_podium.add_theme_constant_override("separation", 10)
	_podium.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(_podium)
	_others = HBoxContainer.new()
	_others.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_child(_others)
	_games = UiTheme.label("", 28, UiTheme.INK, true)
	_games.add_theme_constant_override("outline_size", 8)
	_games.add_theme_color_override("font_outline_color", UiTheme.PAPER)
	col.add_child(_games)
	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 40)
	col.add_child(buttons)
	_again = Button.new()
	_again.text = "Jugar otra vez"
	_again.custom_minimum_size = Vector2(440, 88)
	_again.add_theme_stylebox_override("normal", UiTheme.button_style(UiTheme.ACCENT))
	_again.add_theme_stylebox_override("hover", UiTheme.button_style(UiTheme.ACCENT.lightened(0.1)))
	_again.add_theme_stylebox_override("pressed", UiTheme.button_style(UiTheme.ACCENT, true))
	_again.pressed.connect(func() -> void: play_again_requested.emit())
	buttons.add_child(_again)
	var lobby := Button.new()
	lobby.text = "Cambiar juegos"
	lobby.custom_minimum_size = Vector2(440, 88)
	lobby.pressed.connect(func() -> void: lobby_requested.emit())
	buttons.add_child(lobby)


## Bloque del podio con el puesto y los puntos totales.
class _Block:
	extends Control
	var color := Color.WHITE
	var place := 1

	func _draw() -> void:
		var r := Rect2(Vector2(10, 0), size - Vector2(20, 0))
		UiTheme.draw_round_rect(self, r.grow(4), UiTheme.INK, 22)
		UiTheme.draw_round_rect(self, r, color.darkened(0.2), 18)
		UiTheme.draw_round_rect(self, Rect2(r.position, Vector2(r.size.x, r.size.y - 14)), color, 18)
		UiTheme.draw_round_rect(self, Rect2(r.position + Vector2(0, 0), Vector2(r.size.x, 18)), color.lightened(0.25), 18)
		var c := Vector2(r.get_center().x, r.position.y + (r.size.y - 14.0) / 2.0 + 4.0)
		draw_circle(c, 44, UiTheme.INK)
		draw_circle(c, 40, UiTheme.place_color(place))
		UiTheme.draw_text(self, UiTheme.place_text(place), c + Vector2(2, 1), 40, UiTheme.INK)


## Corona dibujada sobre el ganador.
class _Crown:
	extends Control

	func _draw() -> void:
		var c := Vector2(size.x / 2.0, size.y - 8)
		var w := 110.0
		var pts := PackedVector2Array([
			c + Vector2(-w / 2, 0), c + Vector2(-w / 2, -44), c + Vector2(-w / 4, -20), c + Vector2(0, -58),
			c + Vector2(w / 4, -20), c + Vector2(w / 2, -44), c + Vector2(w / 2, 0)])
		var big := PackedVector2Array()
		for p in pts:
			big.append(c + Vector2(0, -26) + (p - c - Vector2(0, -26)) * 1.12)
		draw_colored_polygon(big, UiTheme.INK)
		draw_colored_polygon(pts, UiTheme.GOLD)
		for x in [-w / 2, 0.0, w / 2]:
			draw_circle(c + Vector2(x, -48 if x != 0.0 else -62), 8, UiTheme.DANGER)
