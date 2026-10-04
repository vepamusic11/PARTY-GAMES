class_name ScoreBar
extends Control
## Marcador superior del resumen de ronda, con el mismo arte que el de los
## juegos (GameArt.paint_hud, ADR 0009):
##   [1P | mascota | 130] [2P | mascota | 180] (Ronda 2/3) [3P | …] [4P | …]
## Una píldora por jugador (etiqueta, mascota con su accesorio y total) a los
## dos lados de la ronda, en la píldora oscura con borde arcoíris.
##
## Rendimiento: este Control dibuja píldoras, mascotas y ronda (cambia solo
## en setup); su hijo `_numbers` dibuja solo los totales y se redibuja
## mientras cuentan (count_to, ~1 s). Las mascotas son texturas que se
## dibujan una vez (GameArt.make_portrait) y se reusan entre rondas.

const ICON := ""  ## Sin ícono en la píldora del centro: "Ronda 2/3" se lee solo.

var _chips: Dictionary = {}     # player_id -> índice de la píldora
var _entries: Array = []        # [{tag, color, portrait}] en orden 1P, 2P…
var _values: Array[float] = []  # total que se muestra de cada píldora
var _center := ""
var _portraits: Dictionary = {} # [color, estilo] -> Texture2D
var _numbers: Control
var _tween: Tween


func _init() -> void:
	custom_minimum_size = Vector2(0, UiTheme.SUMMARY_BAR_H)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR  # Mascotas al doble: suaves al achicarse.
	_numbers = Control.new()
	_numbers.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_numbers.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_numbers.draw.connect(_draw_numbers)
	add_child(_numbers)
	resized.connect(_numbers.queue_redraw)


## rows: [{id, slot, total, color?, style?}] (se ordenan por lugar 1P, 2P…).
## Sin "color" usa el de siempre del lugar; sin "style", el accesorio clásico.
func setup(rows: Array[Dictionary], center_text: String) -> void:
	if _tween:
		_tween.kill()
	var sorted := rows.duplicate()
	sorted.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.slot < b.slot)
	_chips.clear()
	_entries.clear()
	_values.clear()
	_center = center_text
	for i in sorted.size():
		var row: Dictionary = sorted[i]
		var col: Color = row.get("color", Protocol.player_color(row.slot))
		_entries.append({"tag": UiTheme.player_tag(row.slot), "color": col, "portrait": _portrait(col, PlayerAvatar.style_of(row))})
		_values.append(float(row.total))
		_chips[row.id] = i
	queue_redraw()
	_numbers.queue_redraw()


## Los totales cuentan hasta los valores nuevos ({player_id: total}).
func count_to(totals: Dictionary, duration: float = 1.0) -> void:
	var from := _values.duplicate()
	var to := _values.duplicate()
	for pid: int in totals:
		if _chips.has(pid):
			to[_chips[pid]] = float(totals[pid])
	if _tween:
		_tween.kill()
	if not is_inside_tree():
		_values = to
		return
	_tween = create_tween()
	_tween.tween_method(func(k: float) -> void:
		for i in _values.size():
			_values[i] = lerpf(from[i], to[i], k)
		_numbers.queue_redraw(), 0.0, 1.0, duration).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


## El marcador de los juegos está pensado para la TV entera (1920 px, arriba
## de todo): se centra en este Control.
func _origin() -> Vector2:
	return Vector2((size.x - GameArt.SCREEN.x) / 2.0, UiTheme.SUMMARY_BAR_PAD - UiTheme.HUD_TOP)


func _draw() -> void:
	if _entries.is_empty():
		return
	draw_set_transform(_origin())
	GameArt.paint_hud(self, _entries, _center, ICON)


func _draw_numbers() -> void:
	if _entries.is_empty():
		return
	_numbers.draw_set_transform(_origin())
	var scores: Array[String] = []
	for v in _values:
		scores.append(str(roundi(v)))
	GameArt.paint_hud_text(_numbers, scores, _center, ICON)


func _portrait(col: Color, style: int) -> Texture2D:
	var key := [col, style]
	if not _portraits.has(key):
		_portraits[key] = GameArt.make_portrait(self, col, style)
	return _portraits[key]
