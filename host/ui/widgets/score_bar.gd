class_name ScoreBar
extends HBoxContainer
## Marcador superior: [1P 130] [2P 180] [ Ronda 2/3 ] [3P 170] [4P 120]
## Los jugadores se reparten a los lados del chip central, como en los
## marcadores de consola. Los totales se animan con count_to().

var _chips: Dictionary = {}  # player_id -> HexChip
var _center: HexChip


func _init() -> void:
	alignment = BoxContainer.ALIGNMENT_CENTER
	add_theme_constant_override("separation", 14)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


## rows: [{id, slot, total, color?}] (se ordenan por lugar 1P, 2P…). Sin
## "color" usa el de siempre del lugar.
func setup(rows: Array[Dictionary], center_text: String) -> void:
	for c in get_children():
		c.queue_free()
	_chips.clear()
	var sorted := rows.duplicate()
	sorted.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.slot < b.slot)
	_center = HexChip.new("", Color.WHITE, center_text)
	_center.rainbow = true
	_center.custom_minimum_size = Vector2(300, 66)
	var half := ceili(sorted.size() / 2.0)
	for i in sorted.size():
		if i == half:
			add_child(_center)
		var row: Dictionary = sorted[i]
		var chip := HexChip.new(UiTheme.player_tag(row.slot), row.get("color", Protocol.player_color(row.slot)))
		chip.set_value(int(row.total), false)
		add_child(chip)
		_chips[row.id] = chip
	if _center.get_parent() == null:
		add_child(_center)


func count_to(totals: Dictionary, duration: float = 1.0) -> void:
	for pid: int in totals:
		if _chips.has(pid):
			(_chips[pid] as HexChip).set_value(int(totals[pid]), true, duration)
