class_name TvHelpOverlay
extends Control
## Ayuda de los eliminados en la TV (docs/MODOS.md §11, ADR 0020), encima
## del juego:
##
##   - Ficha "3P" (del color del ayudante) con una flechita sobre el
##     candidato que eligió cada eliminado: así sabe a quién va a ayudar
##     (se oculta en la espera de 3 s después de ayudar).
##   - Mascota traslúcida del ayudante al lado del ayudado mientras dura la
##     ayuda (la burbuja o el salvavidas los dibuja el juego).
##   - Cartel abajo al centro, ficha de juguete que no tapa el juego:
##       [3P] Tomi ayudó a Sofi · −10
##     o, si no le alcanzan los puntos: [3P] Tomi: faltan puntos (10).
##
## Las posiciones salen del juego (MiniGame.help_anchor, que ya usa la
## proyección 2.5D si el juego la tiene). Nombres con draw_string (texto
## plano). Rendimiento: sin ayudantes ni carteles no dibuja ni procesa nada;
## con ayudas en curso se redibuja por cuadro (siguen a las mascotas).

var session: HelpSession
var _banners: Array[Dictionary] = []   # {slot, color, text, cost, t}
var _ghosts: CanvasGroup
var _ghost_drawer: Node2D
var _drawn := false  # el último cuadro mostró algo


func _init() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_index = 10  # Encima del juego; debajo de avisos (15), pausa (20) y barrido (30).


func _ready() -> void:
	_ghosts = CanvasGroup.new()
	_ghosts.self_modulate = Color(1, 1, 1, UiTheme.HELP_GHOST_ALPHA)
	_ghost_drawer = Node2D.new()
	_ghost_drawer.draw.connect(_draw_ghosts)
	_ghosts.add_child(_ghost_drawer)
	add_child(_ghosts)
	set_process(false)


## Escucha a la sesión de ayudas (una vez, al armar la TV).
func watch(p_session: HelpSession) -> void:
	session = p_session
	session.help_given.connect(func(helper: Dictionary, target: Dictionary, cost: int) -> void:
		show_banner(helper, "%s ayudó a %s" % [str(helper.get("name", "")), str(target.get("name", ""))], cost))
	session.help_denied.connect(func(helper: Dictionary, reason: String, cost: int) -> void:
		if reason == "no_points":
			show_banner(helper, "%s: faltan puntos (%d)" % [str(helper.get("name", "")), cost], 0, true))


## Suma un cartel (se va solo a los HELP_BANNER_SEC).
func show_banner(helper: Dictionary, text: String, cost: int, warn: bool = false) -> void:
	_banners.append({"slot": int(helper.get("slot", 0)), "color": helper.get("color", UiTheme.PAPER), "text": text,
		"cost": cost, "warn": warn, "t": 0.0})
	while _banners.size() > 2:
		_banners.pop_front()
	set_process(true)


func clear() -> void:
	_banners.clear()
	queue_redraw()
	if _ghost_drawer != null:
		_ghost_drawer.queue_redraw()


func _has_work() -> bool:
	return not _banners.is_empty() or (session != null and session.is_active() and
		(not session.helpers.is_empty() or not session.game.help_active.is_empty()))


func _process(delta: float) -> void:
	for b in _banners:
		b.t = float(b.t) + delta
	_banners = _banners.filter(func(b: Dictionary) -> bool: return float(b.t) < UiTheme.HELP_BANNER_SEC)
	# Mientras nadie ayuda, no redibuja (solo mira, barato); con algo en
	# pantalla, por cuadro (sigue a las mascotas). Un último cuadro lo borra.
	var work := _has_work()
	if work or _drawn:
		queue_redraw()
		_ghost_drawer.queue_redraw()
	_drawn = work
	if not work and (session == null or not session.is_active()):
		set_process(false)


## La sesión arrancó o paró (HostMain lo avisa al empezar y terminar cada juego).
func refresh() -> void:
	set_process(_has_work() or session != null and session.is_active())
	queue_redraw()
	if _ghost_drawer != null:
		_ghost_drawer.queue_redraw()


func _draw() -> void:
	if session != null and session.is_active():
		_draw_markers()
	_draw_banners()


## Ficha del ayudante sobre el candidato que eligió (varios: uno al lado del otro).
func _draw_markers() -> void:
	var game := session.game
	var by_target := {}
	for pid: int in session.helpers:
		if game.help_remaining(pid) <= 0 or game.help_wait_left(pid) > 0.0:
			continue  # Sin ayudas, o recién ayudó: no ensucia la pantalla.
		var target := session.selected(pid)
		if target == -1:
			continue
		if not by_target.has(target):
			by_target[target] = []
		(by_target[target] as Array).append(game.player_by_id(pid))
	var size := UiTheme.HELP_MARKER_SIZE
	for target: int in by_target:
		var list: Array = by_target[target]
		var u := game.help_scale(target)
		var top := game.help_anchor(target) + Vector2(0, -UiTheme.HELP_MARKER_LIFT * u)
		var bob := 0.0 if UiTheme.reduce_motion else sin(game.anim_time * 6.0) * 4.0
		for i in list.size():
			var p: Dictionary = list[i]
			var c := top + Vector2((i - (list.size() - 1) / 2.0) * (size.x + 10.0), bob)
			var r := Rect2(c - size / 2.0, size)
			var col: Color = p.get("color", UiTheme.PAPER)
			var tip := PackedVector2Array([c + Vector2(-12, size.y / 2.0 - 2.0), c + Vector2(12, size.y / 2.0 - 2.0),
				c + Vector2(0, size.y / 2.0 + 16.0)])
			draw_colored_polygon(Geometry2D.offset_polygon(tip, 4.0)[0], UiTheme.INK)
			draw_colored_polygon(tip, col.darkened(UiTheme.TOY_LIP_SHADE))
			var body := UiTheme.draw_toy_tile(self, r, col, size.y / 2.0, 8.0)
			UiTheme.draw_text(self, UiTheme.player_tag(int(p.get("slot", 0))), body.get_center(), UiTheme.HELP_MARKER_FONT,
				UiTheme.PAPER, 6, UiTheme.INK)


## Mascota del ayudante, traslúcida (capa _ghosts), al lado del ayudado.
func _draw_ghosts() -> void:
	if session == null or not session.is_active():
		return
	var game := session.game
	for target: int in game.help_active:
		var helper := game.player_by_id(int(game.help_active[target].helper))
		if helper.is_empty():
			continue
		var u := game.help_scale(target)
		var feet := game.help_anchor(target)
		var side := -1.0 if feet.x > MiniGame.SCREEN.x / 2.0 else 1.0
		var at := feet + Vector2(side * UiTheme.HELP_GHOST_SIDE * u, -8.0 * u)
		PlayerAvatar.draw_mascot(_ghost_drawer, at, u * UiTheme.HELP_GHOST_SCALE, helper.get("color", UiTheme.PAPER),
			PlayerAvatar.style_of(helper), PlayerAvatar.Mood.HAPPY, 0.0, 0.0, false,
			{"t": game.anim_time, "look": Vector2(-side, 0), "wave": true})


## Carteles abajo al centro: [3P] texto · −10 (el más nuevo abajo).
func _draw_banners() -> void:
	var y := size.y - UiTheme.HELP_BANNER_BOTTOM - UiTheme.HELP_BANNER_H
	for i in range(_banners.size() - 1, -1, -1):
		var b: Dictionary = _banners[i]
		var text := str(b.text)
		var cost_text := " · −%d" % int(b.cost) if int(b.cost) > 0 else ""
		var font := UiTheme.FONT_BOLD
		var tw := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, UiTheme.HELP_BANNER_FONT).x
		var cw := font.get_string_size(cost_text, HORIZONTAL_ALIGNMENT_LEFT, -1, UiTheme.HELP_BANNER_FONT).x
		var tag := UiTheme.HELP_BANNER_TAG
		var w := 20.0 + tag.x + 14.0 + tw + cw + 26.0
		# Entra con un golpe de escala y se va achicándose (sin nada con "Reducir movimiento").
		var out := clampf((UiTheme.HELP_BANNER_SEC - float(b.t)) / 0.2, 0.0, 1.0)
		var s := 1.0 if UiTheme.reduce_motion else UiTheme.pop_scale(float(b.t), 0.25) * out
		var r := Rect2(Vector2((size.x - w) / 2.0, y), Vector2(w, UiTheme.HELP_BANNER_H))
		draw_set_transform(r.get_center(), 0.0, Vector2(s, s))
		r.position -= r.get_center()
		var body := UiTheme.draw_toy_tile(self, r, UiTheme.DANGER.lightened(0.55) if b.warn else UiTheme.PAPER,
			UiTheme.HELP_BANNER_H / 2.0)
		var tr := Rect2(Vector2(body.position.x + 14.0, body.get_center().y - tag.y / 2.0), tag)
		var tb := UiTheme.draw_toy_tile(self, tr, b.color, tag.y / 2.0, 6.0)
		UiTheme.draw_text(self, UiTheme.player_tag(int(b.slot)), tb.get_center(), 24, UiTheme.PAPER, 5, UiTheme.INK)
		var x := tr.end.x + 14.0
		UiTheme.draw_text_left(self, text, Vector2(x, body.get_center().y), UiTheme.HELP_BANNER_FONT, UiTheme.INK)
		if not cost_text.is_empty():
			UiTheme.draw_text_left(self, cost_text, Vector2(x + tw, body.get_center().y), UiTheme.HELP_BANNER_FONT,
				UiTheme.HELP_BANNER_COST)
		draw_set_transform(Vector2.ZERO)
		y -= UiTheme.HELP_BANNER_H + 10.0
