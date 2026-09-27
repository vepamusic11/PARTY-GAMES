class_name TvToasts
extends Control
## Avisos de la TV sobre los jugadores, arriba al centro y debajo del
## marcador de los juegos (UiTheme.TOAST_TOP), con la mascota y el color de
## cada uno:
##
##   ╭──────────────────────────────────────────────────────────╮
##   │ (mascota) [2P] Sofi se desconectó — esperando que vuelva (30 s) │
##   ╰──────────────────────────────────────────────────────────╯
##
##   Se sumó Tomi · Juli volvió · Sofi se fue
##
## Concepto: *aviso no bloqueante* (toast). Informa sin pedir nada ni frenar
## el juego, y se va solo. Ejemplo: si Pablo se queda sin Wi-Fi en medio de
## Empujones, los demás ven por qué su mascota no se mueve y cuánto falta
## para que se libere su lugar.
##
## "Se desconectó" queda mientras el jugador no vuelva, pero a los
## TOAST_EXPAND_SEC se achica a una pastilla chica ([mascota 2P · 25 s])
## para no tapar el juego. Si vuelve, se reemplaza por "volvió"; si se
## vence la espera, por "se fue".
##
## Se conecta a las señales de HostServer con `watch(server)`. Los nombres
## se dibujan con draw_string (texto plano, nunca BBCode).
##
## Rendimiento: sin avisos no hay nodos ni _process. Cada aviso se dibuja al
## aparecer y la cuenta regresiva lo redibuja una vez por segundo.

enum Kind { JOINED, LOST, BACK, LEFT }

const PORTRAIT := 76.0          ## Círculo de la mascota.
const MAX_WIDTH := 1180.0

var _server: HostServer
var _known := {}                ## player_id -> último diccionario conocido del jugador.
var _toasts: Array[_Toast] = []


func _init() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_index = 15  # Encima de pantallas y juegos; debajo de la pausa (20) y el barrido (30).


func _ready() -> void:
	set_process(false)


## Escucha a HostServer: se unió, se desconectó, volvió y se fue.
func watch(server: HostServer) -> void:
	_server = server
	server.player_joined.connect(func(p: Dictionary) -> void: show_toast(p, Kind.JOINED))
	server.player_reconnected.connect(func(p: Dictionary) -> void: show_toast(p, Kind.BACK))
	server.player_updated.connect(_on_player_updated)
	server.player_disconnected.connect(func(pid: int) -> void: show_toast(_lookup(pid), Kind.LOST))
	server.player_left.connect(func(pid: int) -> void: show_toast(_lookup(pid), Kind.LEFT))


## Muestra un aviso. `player`: diccionario de HostServer.get_players().
func show_toast(player: Dictionary, kind: int) -> void:
	if player.is_empty():
		return
	var pid := int(player.get("id", 0))
	_known[pid] = player
	# Un aviso por jugador: el nuevo reemplaza al anterior ("volvió" tapa a
	# "se desconectó").
	for t: _Toast in _toasts.duplicate():
		if t.player_id == pid:
			_remove(t, false)
	var toast := _Toast.new(player, kind)
	add_child(toast)
	_toasts.push_front(toast)
	while _toasts.size() > UiTheme.TOAST_MAX:
		_remove(_toasts.back(), false)
	_layout(true)
	set_process(true)


## Textos visibles (para tests y capturas).
func texts() -> Array[String]:
	var out: Array[String] = []
	for t in _toasts:
		out.append(t.message())
	return out


func active_count() -> int:
	return _toasts.size()


## Avanza el tiempo a mano (tests): como si pasaran `seconds`.
func advance(seconds: float) -> void:
	_process(seconds)


## Cambió su color o estilo (lobby): el aviso a la vista se actualiza (ej.
## "Se sumó Juli" aparece antes de que el celular pida su apariencia).
func _on_player_updated(p: Dictionary) -> void:
	var pid := int(p.get("id", 0))
	_known[pid] = p
	for t in _toasts:
		if t.player_id == pid:
			t.color = p.get("color", t.color)
			t.style = PlayerAvatar.style_of(p)
			t.queue_redraw()


func _lookup(pid: int) -> Dictionary:
	if _server != null:
		for p in _server.get_players():
			if int(p.id) == pid:
				_known[pid] = p
				return p
	return _known.get(pid, {})


func _process(delta: float) -> void:
	var relayout := false
	for t: _Toast in _toasts.duplicate():
		var was_compact := t.compact
		t.tick(delta)
		if t.expired():
			_remove(t, true)
			relayout = true
		elif t.compact != was_compact:
			relayout = true
	if relayout:
		_layout(false)
	if _toasts.is_empty():
		set_process(false)


func _remove(t: _Toast, animate: bool) -> void:
	_toasts.erase(t)
	if not animate or UiTheme.reduce_motion or not is_inside_tree():
		t.queue_free()
		return
	var tw := t.create_tween()
	tw.tween_property(t, "modulate:a", 0.0, 0.2)
	tw.tween_callback(t.queue_free)


## Apila los avisos desde TOAST_TOP hacia abajo, centrados.
func _layout(entering: bool) -> void:
	var y := UiTheme.TOAST_TOP
	for t in _toasts:
		var w := t.wanted_width()
		var target := Vector2((size.x - w) / 2.0, y)
		t.size = Vector2(w, UiTheme.TOAST_HEIGHT)
		t.queue_redraw()
		if t.fresh and entering:
			t.fresh = false
			t.position = target
			if not UiTheme.reduce_motion and is_inside_tree():
				t.modulate.a = 0.0
				var tw := t.create_tween().set_parallel()
				tw.tween_property(t, "position", target, 0.28).from(target - Vector2(0, 46)) \
					.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
				tw.tween_property(t, "modulate:a", 1.0, 0.18)
		elif is_inside_tree() and not UiTheme.reduce_motion:
			t.create_tween().tween_property(t, "position", target, 0.2).set_trans(Tween.TRANS_CUBIC)
		else:
			t.position = target
		y += UiTheme.TOAST_HEIGHT + UiTheme.TOAST_GAP


## Un aviso: pastilla blanca con bisel, mascota en un círculo de su color,
## etiqueta 1P–4P y el texto.
class _Toast:
	extends Control
	var player_id := 0
	var kind := 0
	var name_text := ""
	var slot := 0
	var color := Color.WHITE
	var style := 0
	var age := 0.0
	var compact := false
	var fresh := true
	var _grace := float(HostServer.RECONNECT_GRACE_MS) / 1000.0
	var _shown_seconds := -1

	func _init(p: Dictionary, p_kind: int) -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		player_id = int(p.get("id", 0))
		kind = p_kind
		name_text = str(p.get("name", ""))
		slot = int(p.get("slot", 0))
		color = p.get("color", Protocol.player_color(slot))
		style = PlayerAvatar.style_of(p)
		_shown_seconds = seconds_left()

	func tick(delta: float) -> void:
		age += delta
		if kind == TvToasts.Kind.LOST:
			if not compact and age >= UiTheme.TOAST_EXPAND_SEC:
				compact = true
			var s := seconds_left()
			if s != _shown_seconds:
				_shown_seconds = s
				queue_redraw()

	func expired() -> bool:
		if kind == TvToasts.Kind.LOST:
			return age >= _grace + 1.0  # Por si "se fue" no llega (no debería pasar).
		return age >= UiTheme.TOAST_SHOW_SEC

	func seconds_left() -> int:
		return maxi(0, ceili(_grace - age))

	func message() -> String:
		match kind:
			TvToasts.Kind.JOINED:
				return "Se sumó %s" % name_text
			TvToasts.Kind.LOST:
				if compact:
					return "%d s" % seconds_left()
				return "%s se desconectó — esperando que vuelva (%d s)" % [name_text, seconds_left()]
			TvToasts.Kind.BACK:
				return "%s volvió" % name_text
		return "%s se fue" % name_text

	func _font_px() -> int:
		return UiTheme.TOAST_COMPACT_FONT if compact else UiTheme.TOAST_FONT

	func wanted_width() -> float:
		var text_w := UiTheme.FONT_BOLD.get_string_size(message(), HORIZONTAL_ALIGNMENT_LEFT, -1, _font_px()).x
		return minf(TvToasts.MAX_WIDTH, 16.0 + TvToasts.PORTRAIT + 14.0 + UiTheme.TAG_BUBBLE.x + 14.0 + text_w + 34.0)

	func _draw() -> void:
		var h := size.y - UiTheme.BEVEL_DEPTH
		var r := Rect2(Vector2.ZERO, Vector2(size.x, h))
		var lost := kind == TvToasts.Kind.LOST or kind == TvToasts.Kind.LEFT
		var rim := UiTheme.TOAST_ALERT if kind == TvToasts.Kind.LOST else UiTheme.INK
		UiTheme.draw_bevel(self, r, UiTheme.TOAST_BG, h / 2.0, false, rim)
		# Mascota en un círculo de su color (se "sale" un poco por arriba).
		var pc := Vector2(16.0 + TvToasts.PORTRAIT / 2.0, h / 2.0)
		UiTheme.draw_bevel_circle(self, pc, TvToasts.PORTRAIT / 2.0, color.lerp(UiTheme.PAPER, 0.35))
		var mood := PlayerAvatar.Mood.SAD if lost else PlayerAvatar.Mood.HAPPY
		PlayerAvatar.draw_mascot(self, pc + Vector2(0, TvToasts.PORTRAIT * 0.46), 0.76, color, style, mood, 0.0, 0.0,
			false, {"t": 0.0})
		# Etiqueta 1P–4P.
		var tag := Rect2(Vector2(pc.x + TvToasts.PORTRAIT / 2.0 + 14.0, (h - UiTheme.TAG_BUBBLE.y) / 2.0), UiTheme.TAG_BUBBLE)
		UiTheme.draw_round_rect(self, tag, color, tag.size.y / 2.0, 3, UiTheme.INK)
		var tag_text := UiTheme.text_on(color)
		UiTheme.draw_text(self, UiTheme.player_tag(slot), tag.get_center(), 24, tag_text, 5,
			UiTheme.INK if tag_text == UiTheme.PAPER else UiTheme.PAPER)
		var left := tag.end.x + 14.0
		var avail := size.x - left - 30.0
		var col := UiTheme.INK
		UiTheme.draw_text_left(self, message(), Vector2(left, h / 2.0), _font_px(), col, avail)
