class_name SeatCard
extends Control
## Lugar de un jugador en el lobby (1P–4P). Estados:
##   READY        conectado            -> mascota + nombre + "¡Listo!"
##   RECONNECTING perdió la conexión   -> lugar reservado 30 s
##   OPEN         lugar libre          -> "+" + "Esperando jugadores…"
##   LOCKED       fuera de la cantidad elegida -> atenuado, "No juega"
##
## Dos formatos: tarjeta alta o fila compacta (`compact`):
## [1P] (mascota) Pablo ········ ¡Listo!
##
## Tarjeta alta (la del lobby): la mascota es grande y *sobresale* por arriba
## de la tarjeta (OVERHANG px libres arriba para la cabeza), sobre un fondo
## en degradé del color del jugador con un resplandor detrás. La etiqueta 1P
## es una píldora con contorno que va encima de todo (capa `_tag_layer`).
##
##        ( o o )        <- la cabeza asoma por arriba
##   ╭(1P)─┤     ├──╮
##   │    ╰─────╯   │
##   │    Pablo     │
##   │   ¡Listo!    │
##   ╰──────────────╯
##
## Bots (ADR 0010): un lugar libre o con bot se puede elegir con el D-pad
## (`selectable`); OK emite `activated` y el lobby abre el menú del bot. Un
## bot se ve como un jugador más, con la placa "BOT" arriba a la derecha y
## su dificultad donde las personas dicen "¡Listo!".

signal activated(slot: int)

enum State { READY, RECONNECTING, OPEN, LOCKED }

const OVERHANG := 44.0        ## Alto libre arriba de la tarjeta para la cabeza de la mascota.
const TALL_HEIGHT := 268.0
const LABELS_HEIGHT := 72.0   ## Nombre + estado, abajo de la tarjeta.
const MASCOT_RISE := 22.0     ## Cuánto sube la mascota por encima del control.
const MASCOT_GAP := 6.0       ## Aire entre los pies de la mascota y el nombre.
const CARD_RADIUS := 30.0
const NAME_FONT := 34
const STATUS_FONT := 26
const TAG_SIZE := UiTheme.SEAT_TAG_SIZE

var slot := 0
var state := State.OPEN
var compact := false
## Se puede elegir con el D-pad (lugar libre o con bot). Lo decide el lobby.
var selectable := false:
	set(value):
		selectable = value
		focus_mode = Control.FOCUS_ALL if value else Control.FOCUS_NONE
var is_bot := false
var _player: Dictionary = {}
var _locked := false
var _avatar: PlayerAvatar
var _name: Label
var _status: Label
var _tag_layer: Control


func _init(p_slot: int, p_compact: bool = false) -> void:
	slot = p_slot
	compact = p_compact
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if compact:
		_build_row()
		return
	custom_minimum_size = Vector2(200, TALL_HEIGHT)
	_avatar = PlayerAvatar.new()
	_avatar.slot = slot
	_avatar.color = Protocol.player_color(slot)
	_avatar.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_avatar.offset_top = -MASCOT_RISE
	_avatar.offset_bottom = -LABELS_HEIGHT - MASCOT_GAP
	add_child(_avatar)
	var box := VBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	box.offset_top = -LABELS_HEIGHT - 8.0
	box.offset_bottom = -10
	box.offset_left = 12
	box.offset_right = -12
	box.alignment = BoxContainer.ALIGNMENT_END
	box.add_theme_constant_override("separation", -4)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(box)
	_name = UiTheme.label("", NAME_FONT, UiTheme.INK, true)
	_name.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_name.clip_text = true
	_name.custom_minimum_size = Vector2(0, 42)
	box.add_child(_name)
	_status = UiTheme.label("", STATUS_FONT, UiTheme.INK_SOFT, true)
	box.add_child(_status)
	# La etiqueta 1P va encima de la mascota (un brazo puede pasar por ahí).
	_tag_layer = Control.new()
	_tag_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_tag_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tag_layer.draw.connect(_draw_tag)
	add_child(_tag_layer)


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
## Usa el color y el estilo de mascota del jugador si los trae (los elige
## desde el celular); si no, los de su lugar.
func show_player(player: Dictionary, locked: bool) -> void:
	_player = player
	_locked = locked
	is_bot = bool(player.get("bot", false))
	_avatar.color = player.get("color", Protocol.player_color(slot))
	_avatar.style = PlayerAvatar.style_of(player) if not player.is_empty() else -1
	var present := not player.is_empty()
	if present:
		state = State.READY if player.connected else State.RECONNECTING
		_name.text = player.name  # Label: el nombre se muestra como texto plano.
	else:
		state = State.LOCKED if locked else State.OPEN
		if compact:
			_name.text = "—" if locked else "Libre"
		else:
			_name.text = "—" if locked else "Esperando"
	_avatar.empty = not present
	# En la tarjeta alta el lugar libre muestra un "+" (dibujado en _draw) y
	# la mascota no se dibuja ni se anima (no gasta CPU en algo invisible).
	var avatar_visible := compact or present
	_avatar.modulate.a = (0.55 if state == State.RECONNECTING else 1.0) if avatar_visible else 0.0
	_avatar.animate = avatar_visible
	_avatar.mood = PlayerAvatar.Mood.HAPPY if state == State.READY else PlayerAvatar.Mood.NORMAL
	_name.add_theme_color_override("font_color", UiTheme.INK if present else UiTheme.INK_SOFT)
	if not compact:
		_name.add_theme_font_size_override("font_size", NAME_FONT if present else STATUS_FONT + 2)
	match state:
		State.READY when is_bot:
			_status.text = "Bot · %s" % Bot.difficulty_name(int(player.get("difficulty", Bot.Difficulty.NORMAL)))
			_status.add_theme_color_override("font_color", UiTheme.INK_SOFT)
		State.READY:
			_status.text = "¡Listo!"
			_status.add_theme_color_override("font_color", UiTheme.SUCCESS)
		State.RECONNECTING:
			_status.text = "Reconectando…"
			_status.add_theme_color_override("font_color", UiTheme.WARNING)
		State.OPEN when has_focus():
			# Con el foco encima, el lugar libre dice qué hace OK.
			_name.text = "Sumar bot"
			_status.text = "con OK"
			_status.add_theme_color_override("font_color", UiTheme.INK)
		State.OPEN:
			_status.text = "Esperando…" if compact else "jugadores…"
			_status.add_theme_color_override("font_color", UiTheme.INK_SOFT)
		State.LOCKED:
			_status.text = "No juega"
			_status.add_theme_color_override("font_color", UiTheme.INK_SOFT)
	modulate.a = 0.45 if state == State.LOCKED else 1.0
	queue_redraw()
	if _tag_layer != null:
		_tag_layer.queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if selectable and event.is_action_pressed("ui_accept"):
		activated.emit(slot)
		accept_event()


func _notification(what: int) -> void:
	if what == NOTIFICATION_FOCUS_ENTER or what == NOTIFICATION_FOCUS_EXIT:
		show_player(_player, _locked)


## Rectángulo de la tarjeta alta (debajo del espacio libre para la cabeza).
func _card_rect() -> Rect2:
	return Rect2(Vector2(4, OVERHANG), Vector2(size.x - 8, size.y - OVERHANG - 4))


func _draw() -> void:
	if compact:
		_draw_row()
		return
	var r := _card_rect()
	var col := _avatar.color
	var filled := state == State.READY or state == State.RECONNECTING
	if has_focus():
		# Anillo de foco del D-pad (como el del Stepper), detrás de la tarjeta.
		UiTheme.draw_round_rect(self, r.grow(12), Color(UiTheme.INK, 0.5), CARD_RADIUS + 12)
		UiTheme.draw_round_rect(self, r.grow(9), UiTheme.ACCENT, CARD_RADIUS + 9)
	if not filled:
		# Lugar libre: tarjeta de vidrio con un "+" grande en un disco claro.
		UiTheme.draw_glass_card(self, r, CARD_RADIUS)
		if state == State.OPEN:
			var plus := Vector2(r.get_center().x, r.position.y + (r.size.y - LABELS_HEIGHT) * 0.5 + 6.0)
			var batch := UiTheme.ShapeBatch.new()
			batch.circle(plus, 46, UiTheme.SEAT_PLUS_DISC)
			batch.flush(self)
			UiTheme.draw_glyph(self, "plus", plus, 58, UiTheme.on_light(col))
		return
	# Tarjeta en degradé pastel del color del jugador, con marco claro y un
	# resplandor detrás de la mascota (ver UiTheme.draw_seat_card).
	var glow := Vector2(r.get_center().x, r.position.y + (r.size.y - LABELS_HEIGHT) * 0.42)
	UiTheme.draw_seat_card(self, r, col, CARD_RADIUS, glow)
	# Base clara para el nombre: se lee bien sobre cualquier color de jugador.
	var inner := r.grow(-UiTheme.SEAT_RIM_W)
	var base := Rect2(Vector2(inner.position.x, inner.end.y - LABELS_HEIGHT - 6), Vector2(inner.size.x, LABELS_HEIGHT + 6))
	UiTheme.draw_gradient_round_rect(self, base, Color(UiTheme.PAPER, 0.0), Color(UiTheme.PAPER, 0.85), CARD_RADIUS - 6)


## Etiqueta 1P–4P: píldora del color del jugador con contorno, encima de la
## mascota y un poco afuera de la tarjeta, como en las consolas.
func _draw_tag() -> void:
	var r := _card_rect()
	var tag := Rect2(r.position + Vector2(-2, -12), TAG_SIZE)
	var present := state == State.READY or state == State.RECONNECTING
	var fill := _avatar.color if present else UiTheme.PAPER
	var text_col := UiTheme.PAPER if present else UiTheme.INK_SOFT
	UiTheme.draw_round_rect(_tag_layer, Rect2(tag.position + Vector2(0, 4), tag.size).grow(3), UiTheme.INK, TAG_SIZE.y / 2.0 + 3)
	UiTheme.draw_round_rect(_tag_layer, tag, fill, TAG_SIZE.y / 2.0, 3, UiTheme.INK)
	UiTheme.draw_gradient_round_rect(_tag_layer, Rect2(tag.position + Vector2(8, 5), Vector2(tag.size.x - 16, tag.size.y * 0.4)),
		UiTheme.GLOSS_TOP, UiTheme.GLOSS_BOTTOM, 8)
	UiTheme.draw_text(_tag_layer, UiTheme.player_tag(slot), tag.get_center(), UiTheme.SEAT_TAG_FONT, text_col, 6 if present else 0, UiTheme.INK)
	if is_bot and present:
		UiTheme.draw_bot_badge(_tag_layer, Vector2(r.end.x - UiTheme.BOT_BADGE_SIZE.x / 2.0 - 2.0, tag.get_center().y + 2.0))


func _draw_row() -> void:
	var r := Rect2(Vector2(4, 4), size - Vector2(8, 8))
	var radius := r.size.y / 2.0
	var filled := state == State.READY or state == State.RECONNECTING
	var col := _avatar.color
	UiTheme.draw_round_rect(self, r, UiTheme.PAPER if filled else UiTheme.GLASS, radius, 0, UiTheme.INK, filled)
	if state == State.OPEN:
		UiTheme.draw_dashed_rect(self, r.grow(-4), Color(UiTheme.INK_SOFT, 0.55), 4.0, radius)
	var tag := Rect2(Vector2(r.position.x + 14, r.get_center().y - 20), Vector2(74, 40))
	UiTheme.draw_round_rect(self, tag, col, 19, 3, UiTheme.INK)
	UiTheme.draw_text(self, UiTheme.player_tag(slot), tag.get_center(), 24, UiTheme.PAPER, 4, UiTheme.INK)
	if has_focus():
		UiTheme.draw_round_rect(self, r.grow(4), Color(UiTheme.ACCENT, 0.0), radius + 4, UiTheme.FOCUS_WIDTH, UiTheme.ACCENT)
