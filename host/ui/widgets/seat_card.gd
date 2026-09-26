class_name SeatCard
extends Control
## Lugar de un jugador en el lobby (1P–4P). Estados:
##   READY        conectado            -> mascota + nombre + "¡Listo!"
##   RECONNECTING perdió la conexión   -> lugar reservado 30 s
##   OPEN         lugar libre          -> silueta + "Esperando…"
##   LOCKED       fuera de la cantidad elegida -> atenuado, "No juega"
##
## Dos formatos: tarjeta alta (mascota arriba) o fila compacta (`compact`):
## [1P] (mascota) Pablo ········ ¡Listo!   — la usa el lobby para dejar
## más lugar a los juegos.

enum State { READY, RECONNECTING, OPEN, LOCKED }

var slot := 0
var state := State.OPEN
var compact := false
var _avatar: PlayerAvatar
var _name: Label
var _status: Label


func _init(p_slot: int, p_compact: bool = false) -> void:
	slot = p_slot
	compact = p_compact
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if compact:
		_build_row()
		return
	custom_minimum_size = Vector2(270, 216)
	var box := VBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	box.offset_top = 40
	box.offset_bottom = -14
	box.add_theme_constant_override("separation", 0)
	add_child(box)
	_avatar = PlayerAvatar.new()
	_avatar.slot = slot
	_avatar.color = Protocol.player_color(slot)
	_avatar.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(_avatar)
	_name = UiTheme.label("", 32, UiTheme.INK, true)
	_name.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_name.clip_text = true
	_name.custom_minimum_size = Vector2(0, 40)
	box.add_child(_name)
	_status = UiTheme.label("", 24, UiTheme.INK_SOFT)
	box.add_child(_status)


func _build_row() -> void:
	custom_minimum_size = Vector2(0, 66)
	var row := HBoxContainer.new()
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row.offset_left = 100  # Deja lugar a la etiqueta 1P dibujada en _draw.
	row.offset_right = -20
	row.add_theme_constant_override("separation", 12)
	add_child(row)
	_avatar = PlayerAvatar.new()
	_avatar.slot = slot
	_avatar.color = Protocol.player_color(slot)
	_avatar.custom_minimum_size = Vector2(52, 0)
	row.add_child(_avatar)
	_name = UiTheme.label("", 28, UiTheme.INK, true, HORIZONTAL_ALIGNMENT_LEFT)
	_name.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_name.clip_text = true
	_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(_name)
	_status = UiTheme.label("", 24, UiTheme.INK_SOFT, true, HORIZONTAL_ALIGNMENT_RIGHT)
	row.add_child(_status)


## player: diccionario de HostServer.get_players() o {} si está libre.
func show_player(player: Dictionary, locked: bool) -> void:
	if not player.is_empty():
		state = State.READY if player.connected else State.RECONNECTING
		_name.text = player.name  # Label: el nombre se muestra como texto plano.
	else:
		state = State.LOCKED if locked else State.OPEN
		_name.text = "—" if locked else "Libre"
	_avatar.empty = player.is_empty()
	_avatar.mood = PlayerAvatar.Mood.HAPPY if state == State.READY else PlayerAvatar.Mood.NORMAL
	_name.add_theme_color_override("font_color", UiTheme.INK if not player.is_empty() else UiTheme.INK_SOFT)
	match state:
		State.READY:
			_status.text = "¡Listo!"
			_status.add_theme_color_override("font_color", UiTheme.SUCCESS)
		State.RECONNECTING:
			_status.text = "Reconectando…"
			_status.add_theme_color_override("font_color", UiTheme.WARNING)
		State.OPEN:
			_status.text = "Esperando…"
			_status.add_theme_color_override("font_color", UiTheme.INK_SOFT)
		State.LOCKED:
			_status.text = "No juega"
			_status.add_theme_color_override("font_color", UiTheme.MUTED)
	modulate.a = 0.45 if state == State.LOCKED else 1.0
	queue_redraw()


func _draw() -> void:
	var r := Rect2(Vector2(4, 4), size - Vector2(8, 8))
	var radius := r.size.y / 2.0 if compact else 30.0
	var filled := state == State.READY or state == State.RECONNECTING
	UiTheme.draw_round_rect(self, r, UiTheme.PAPER if filled else Color(1, 1, 1, 0.55), radius, 0, UiTheme.INK, filled)
	if state == State.OPEN:
		UiTheme.draw_dashed_rect(self, r.grow(-4), Color(UiTheme.INK_SOFT, 0.55), 4.0, radius)
	var tag := Rect2(r.position + Vector2(16, 14), Vector2(74, 40))
	if compact:
		tag.position = Vector2(r.position.x + 14, r.get_center().y - 20)
	UiTheme.draw_round_rect(self, tag, Protocol.player_color(slot), 20, 3, UiTheme.INK)
	UiTheme.draw_text(self, UiTheme.player_tag(slot), tag.get_center(), 26, UiTheme.PAPER, 4, UiTheme.INK)
