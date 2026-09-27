class_name MiniGame
extends Node2D
## Contrato que cumple todo minijuego. El host no conoce los detalles de
## cada juego: solo llama a estos métodos. Así agregar el juego número 20
## no toca el lobby, la red ni los otros juegos.
##
## Ciclo: setup(players) -> on_input(...) muchas veces -> finished.emit(result)
## Ver docs/ADDING_A_MINIGAME.md para una guía paso a paso.

## Emitir una sola vez al terminar. result = { "winners": Array[int], "scores": {player_id: int}, "summary": String }
signal finished(result: Dictionary)
## Pedido de vibración/sonido en el celular de un jugador (la TV lo reenvía
## como mensaje "feedback"). kind: uno de Protocol.FEEDBACK_KINDS.
signal feedback(player_id: int, kind: String)

## Tamaño lógico de la pantalla de la TV (ver project.godot).
const SCREEN := Vector2(1920, 1080)

var players: Array[Dictionary] = []
## Reloj solo para animaciones (parpadeo, brazos); lo avanza _process.
var anim_time := 0.0
var _finished := false
var _walk: Dictionary = {}   # player_id -> fase de caminata (vueltas)

# Capas cacheadas (ver "Capas cacheadas" más abajo): fondo y marcador.
var _backdrop: Node2D          # detrás del juego: cielo y campo
var _backdrop_ops: Array = []  # capas pedidas, en orden: ["sky"], ["field", rect, cell], ["static", fn]
var _backdrop_used := 0        # cuántas se pidieron en el _draw en curso
var _hud: Node2D               # delante del juego: marcador superior (píldoras, mascotas, reloj)
var _hud_text: Node2D          # hijo de _hud: solo los números y el texto del reloj
var _hud_state: Array = []     # lo que muestra el marcador (vacío = nada)
var _hud_shape: Array = []     # lo que dibuja _hud (sin números): cambia casi nunca
var _hud_requested := false    # se llamó a draw_hud() en el _draw en curso
var _portraits: Dictionary = {}  # [color, estilo] -> textura de la mascota del marcador


## Metadatos del juego. Sobrescribir en cada juego.
static func get_info() -> Dictionary:
	return {
		"id": "base",
		"title": "Sin título",
		"description": "",
		"min_players": 1,
		"max_players": Protocol.MAX_PLAYERS,
		"layout": Protocol.LAYOUT_WAIT,
		"layout_data": {},
	}


## Recibe los jugadores conectados (ver HostServer.get_players()).
func setup(p_players: Array[Dictionary]) -> void:
	players = p_players


## Input ya validado por HostServer: { seq, axis: Vector2, btn: int }.
func on_input(_player_id: int, _input: Dictionary) -> void:
	pass


## El control se desconectó: tratar como input neutro (no pausar el juego).
func on_player_disconnected(player_id: int) -> void:
	on_input(player_id, {"seq": -1, "axis": Vector2.ZERO, "btn": 0})


func finish(result: Dictionary) -> void:
	if _finished:
		return
	_finished = true
	finished.emit(result)


func is_finished() -> bool:
	return _finished


# --- Utilidades comunes para juegos -------------------------------------------

func player_by_id(player_id: int) -> Dictionary:
	for p in players:
		if p.id == player_id:
			return p
	return {}


## Arma el resultado a partir de un diccionario de puntajes.
static func result_from_scores(scores: Dictionary, summary: String = "") -> Dictionary:
	var best := -INF
	var winners: Array[int] = []
	for pid: int in scores:
		var s := float(scores[pid])
		if s > best:
			best = s
			winners = [pid]
		elif s == best:
			winners.append(pid)
	return {"winners": winners, "scores": scores.duplicate(), "summary": summary}


func _process(delta: float) -> void:
	anim_time += delta


# --- Animación de mascotas -------------------------------------------------------

## Avanza la caminata de un jugador según cuánto se movió (0..1 de su
## velocidad máxima). Llamar en cada frame donde se mueve a los jugadores.
func advance_walk(player_id: int, speed01: float, delta: float, steps_per_sec: float = 2.4) -> void:
	if speed01 < 0.08:
		_walk.erase(player_id)
		return
	_walk[player_id] = float(_walk.get(player_id, 0.0)) + speed01 * steps_per_sec * delta


## Parámetros de animación para PlayerAvatar.draw_mascot: camina si se está
## moviendo, mira en la dirección dada y parpadea con el reloj del juego.
func mascot_anim(player_id: int, look: Vector2 = Vector2.ZERO) -> Dictionary:
	return {"t": anim_time + player_id * 0.9, "walk": float(_walk.get(player_id, -1.0)), "look": look}


# --- Sonido y vibración ------------------------------------------------------

## Sonido en la TV (ver Sfx.RECIPES). Sin nodo Sfx (tests) no hace nada.
func play_sfx(sound_name: String, pitch: float = 1.0) -> void:
	Sfx.play(sound_name, 0.0, pitch)


## Vibración/sonido en el celular de un jugador.
func notify_player(player_id: int, kind: String) -> void:
	feedback.emit(player_id, kind)


func notify_all(kind: String) -> void:
	for p in players:
		feedback.emit(p.id, kind)


## Cuenta regresiva con sonido: llamar en cada frame con los segundos que
## faltaban antes y después del delta. Suena "3, 2, 1" y al llegar a 0 "¡YA!"
## en la TV y vibra en todos los celulares.
func tick_countdown(left_before: float, left_after: float) -> void:
	if left_before <= 0.0:
		return
	if left_after <= 0.0:
		play_sfx("go")
		notify_all("go")
	elif ceili(left_after) < ceili(left_before):
		play_sfx("count")


## Texto centrado con la tipografía del juego. outline > 0 le pone contorno.
func draw_text_centered(text: String, pos: Vector2, size: int, color: Color = Color.WHITE,
		outline: int = 0) -> void:
	UiTheme.draw_text(self, text, pos, size, color, outline, UiTheme.INK)


## Globito con la etiqueta 1P–4P (del color del jugador) sobre la cabeza de
## su mascota y el nombre debajo de los pies, con contorno. `u`: escala con la
## que se dibujó la mascota. Llamarlo después de dibujar las mascotas (queda
## encima). Ver GameArt.draw_player_tag.
func draw_player_tag(p: Dictionary, feet: Vector2, u: float = 0.8, name_offset: float = 26.0, alpha: float = 1.0) -> void:
	draw_player_tags([[p, feet, u, name_offset, alpha]])


## Como draw_player_tag para varios jugadores a la vez (menos draw calls):
## entries = [[jugador, pies, u, name_offset, alpha], ...] (u, name_offset y
## alpha opcionales).
func draw_player_tags(entries: Array) -> void:
	var tags: Array = []
	for e: Array in entries:
		var p: Dictionary = e[0]
		tags.append([int(p.get("slot", 0)), p.get("color", UiTheme.PAPER), str(p.get("name", "")), e[1],
			e[2] if e.size() > 2 else 0.8, e[3] if e.size() > 3 else 26.0, e[4] if e.size() > 4 else 1.0])
	GameArt.draw_player_tags(self, tags)


## Marcador superior común a todos los juegos, como en la maqueta:
##   [1P mascota 12] [2P mascota 9] [reloj 0:28] [3P mascota 7] [4P mascota 3]
## Una píldora del color de cada jugador con su etiqueta, su mascota y el
## puntaje, y en el medio el reloj (píldora oscura con borde arcoíris).
## scores: {player_id: número}. center: tiempo, ronda o lo que el juego quiera.
## icon: "clock" (cronómetro), "flag" (meta), "star" o "" (sin ícono). Por
## defecto "clock" si center tiene forma de reloj ("0:28") y si no "star".
##
## Se cachea (ver "Capas cacheadas"): lo dibuja una capa propia, delante de
## todo lo del juego. Las píldoras, las mascotas y el reloj casi nunca
## cambian; los números y el texto del centro van en una capa hija que se
## redibuja solo cuando cambia alguno (≈ 1 vez por segundo en vez de 60).
func draw_hud(scores: Dictionary, center: String, icon: String = "auto") -> void:
	if icon == "auto":
		icon = "clock" if _looks_like_clock(center) else "star"
	var state: Array = [[center, icon]]
	for p in players:
		state.append_array([p.slot, p.color, str(roundi(float(scores.get(p.id, 0))))])
	_layers_ready()
	_hud_requested = true
	if state != _hud_state:
		_hud_state = state
		_hud_text.queue_redraw()
		var shape: Array = [icon, GameArt.hud_center_width(center, icon)]
		for i in range(1, state.size(), 3):
			shape.append_array([state[i], state[i + 1]])
		if shape != _hud_shape:
			_hud_shape = shape
			_hud.queue_redraw()


static func _looks_like_clock(text: String) -> bool:
	var parts := text.split(":")
	return parts.size() == 2 and parts[0].is_valid_int() and parts[1].length() == 2 and parts[1].is_valid_int()


func _draw_hud_layer() -> void:
	if _hud_state.is_empty():
		return
	var head: Array = _hud_state[0]
	var n := floori((_hud_state.size() - 1) / 3.0)
	var entries: Array = []
	for i in n:
		var k := 1 + i * 3
		var p: Dictionary = players[i] if i < players.size() else {}
		entries.append({
			"tag": UiTheme.player_tag(_hud_state[k]), "color": _hud_state[k + 1],
			"portrait": _portrait(_hud_state[k + 1], PlayerAvatar.style_of(p)) if not p.is_empty() else null,
		})
	var pills := GameArt.paint_hud(_hud, entries, head[0], head[1])
	for i in mini(n, players.size()):
		_draw_hud_extra(_hud, players[i], pills[i])


func _draw_hud_text_layer() -> void:
	if _hud_state.is_empty():
		return
	var head: Array = _hud_state[0]
	var scores: Array[String] = []
	for i in range(1, _hud_state.size(), 3):
		scores.append(_hud_state[i + 2])
	GameArt.paint_hud_text(_hud_text, scores, head[0], head[1])


## Para que un juego agregue algo a la píldora de un jugador (se dibuja en la
## capa cacheada del marcador). Ej. Pintar el piso muestra su patrón debajo.
func _draw_hud_extra(_ci: CanvasItem, _player: Dictionary, _pill: Rect2) -> void:
	pass


## Mascota de la píldora del marcador: una textura por color y estilo que se
## dibuja una sola vez (GameArt.make_portrait).
func _portrait(col: Color, style: int) -> Texture2D:
	var key := [col, style]
	if not _portraits.has(key):
		_portraits[key] = GameArt.make_portrait(_hud, col, style)
	return _portraits[key]


## "0:28": segundos restantes en formato reloj.
static func clock_text(seconds: float) -> String:
	var s := ceili(maxf(seconds, 0.0))
	return "%d:%02d" % [s / 60, s % 60]


## Fondo que usan todos los juegos: cielo con un escenario de bloques y
## juguetes desenfocado alrededor (coherente con el lobby).
## Se cachea (ver "Capas cacheadas"): llamarla al principio de _draw().
func draw_sky() -> void:
	_backdrop_request(["sky"])


## Campo de juego: tablero con volumen (sombra proyectada, marco de bloques
## con bisel y estrellas en las esquinas) y baldosas con relieve de lado
## `cell`. Se cachea igual que draw_sky().
func draw_play_field(rect: Rect2, cell: float = 80.0) -> void:
	_backdrop_request(["field", rect, cell])


## Dibujo fijo del juego que no cambia en toda la partida (la mesa de Ping
## Pong, paneles, tribunas, carteles…): se cachea igual que draw_sky() (va en
## la capa de fondo, detrás de todo lo que dibuja _draw) y se dibuja una sola
## vez. `fn` recibe el CanvasItem donde dibujar. Llamarla al principio de
## _draw(), después de draw_sky()/draw_play_field(). Ojo: lo que cambie con
## el juego no puede ir acá (no se volvería a dibujar), y `fn` tiene que ser
## un método (una func anónima nueva en cada frame no se reconoce como la
## misma y se redibujaría siempre).
func draw_static(fn: Callable) -> void:
	_backdrop_request(["static", fn])


# --- Capas cacheadas ----------------------------------------------------------
#
# Los juegos se redibujan en cada frame (queue_redraw en _physics_process),
# pero el cielo, el campo (cientos de rectángulos) y el marcador casi nunca
# cambian. Godot conserva lo que dibujó un CanvasItem hasta el próximo
# queue_redraw() de ESE nodo, así que esas partes van en nodos hijos
# internos que se redibujan solo cuando cambian sus datos:
#   _backdrop  show_behind_parent: queda detrás de todo lo que dibuja el juego.
#   _hud       último hijo interno: queda delante de todo el juego.
# Para el juego no cambia nada: sigue llamando draw_sky(), draw_play_field()
# y draw_hud() desde su _draw(); estas funciones solo registran qué pedir.
# Si en un _draw se deja de pedir una capa, se borra al terminar ese _draw.

func _layers_ready() -> void:
	if _backdrop != null:
		return
	_backdrop = Node2D.new()
	_backdrop.name = "Backdrop"
	_backdrop.show_behind_parent = true
	_backdrop.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR  # Escenario estirado: suave.
	_backdrop.draw.connect(_draw_backdrop)
	add_child(_backdrop, false, Node.INTERNAL_MODE_FRONT)
	_hud = Node2D.new()
	_hud.name = "Hud"
	_hud.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR  # Mascotas del marcador (al doble): suaves.
	_hud.draw.connect(_draw_hud_layer)
	add_child(_hud, false, Node.INTERNAL_MODE_BACK)
	_hud_text = Node2D.new()
	_hud_text.name = "HudText"
	_hud_text.draw.connect(_draw_hud_text_layer)
	_hud.add_child(_hud_text)
	# `draw` se emite justo antes de cada _draw() del juego. Este primer
	# _draw ya empezó, así que se abre a mano.
	draw.connect(_layers_begin_draw)
	_layers_begin_draw()


func _layers_begin_draw() -> void:
	_backdrop_used = 0
	_hud_requested = false
	_layers_end_draw.call_deferred()  # Corre cuando termina este _draw().


func _layers_end_draw() -> void:
	if _backdrop_used < _backdrop_ops.size():
		_backdrop_ops.resize(_backdrop_used)
		_backdrop.queue_redraw()
	if not _hud_requested and not _hud_state.is_empty():
		_hud_state = []
		_hud_shape = []
		_hud.queue_redraw()
		_hud_text.queue_redraw()


## Compara la capa pedida con la que ya está dibujada en esa posición y
## redibuja el fondo solo si cambió.
func _backdrop_request(op: Array) -> void:
	_layers_ready()
	if _backdrop_used < _backdrop_ops.size() and _backdrop_ops[_backdrop_used] == op:
		_backdrop_used += 1
		return
	_backdrop_ops.resize(_backdrop_used)
	_backdrop_ops.append(op)
	_backdrop_used += 1
	_backdrop.queue_redraw()


func _draw_backdrop() -> void:
	# Lo que tapa el tablero (si hay) no hace falta pintarlo en el escenario.
	var cover := Rect2()
	for op: Array in _backdrop_ops:
		if op[0] == "field":
			cover = GameArt.board_cover(op[1])
	for op: Array in _backdrop_ops:
		match op[0]:
			"sky":
				GameArt.paint_stage(_backdrop, cover)
			"field":
				_paint_play_field(_backdrop, op[1], op[2])
			"static":
				(op[1] as Callable).call(_backdrop)


## Tablero con volumen: ver GameArt.paint_board.
static func _paint_play_field(ci: CanvasItem, rect: Rect2, cell: float) -> void:
	GameArt.paint_board(ci, rect, cell)
