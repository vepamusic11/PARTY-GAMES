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
var _backdrop_ops: Array = []  # capas pedidas, en orden: ["sky"], ["field", rect, cell]
var _backdrop_used := 0        # cuántas se pidieron en el _draw en curso
var _hud: Node2D               # delante del juego: marcador superior
var _hud_state: Array = []     # lo que muestra el marcador (vacío = nada)
var _hud_requested := false    # se llamó a draw_hud() en el _draw en curso


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


## Marcador superior común a todos los juegos, como en las consolas:
##   [1P 12] [2P 9] [ 0:28 ] [3P 7] [4P 3]
## scores: {player_id: número}. center: tiempo, ronda o lo que el juego quiera.
##
## Se cachea (ver "Capas cacheadas"): lo dibuja una capa propia, delante de
## todo lo del juego, y solo se redibuja cuando cambia algún número o el
## texto del centro (≈ 1 vez por segundo en vez de 60).
func draw_hud(scores: Dictionary, center: String) -> void:
	var state: Array = [center]
	for p in players:
		state.append_array([p.slot, p.color, str(roundi(float(scores.get(p.id, 0))))])
	_layers_ready()
	_hud_requested = true
	if state != _hud_state:
		_hud_state = state
		_hud.queue_redraw()


func _draw_hud_layer() -> void:
	if _hud_state.is_empty():
		return
	const CHIP := Vector2(230, 58)
	const CENTER_W := 250.0
	const GAP := 16.0
	var n := floori((_hud_state.size() - 1) / 3.0)
	var x := (SCREEN.x - (n * CHIP.x + CENTER_W + n * GAP)) / 2.0
	var half := ceili(n / 2.0)
	for i in n + 1:
		if i == half:
			UiTheme.draw_hex_chip(_hud, Rect2(x, 24, CENTER_W, CHIP.y), "", Color.WHITE, _hud_state[0], true)
			x += CENTER_W + GAP
		if i < n:
			var k := 1 + i * 3
			UiTheme.draw_hex_chip(_hud, Rect2(Vector2(x, 24), CHIP), UiTheme.player_tag(_hud_state[k]), _hud_state[k + 1], _hud_state[k + 2])
			x += CHIP.x + GAP


## "0:28": segundos restantes en formato reloj.
static func clock_text(seconds: float) -> String:
	var s := ceili(maxf(seconds, 0.0))
	return "%d:%02d" % [s / 60, s % 60]


## Fondo de cielo que usan todos los juegos (coherente con el lobby).
## Se cachea (ver "Capas cacheadas"): llamarla al principio de _draw().
func draw_sky() -> void:
	_backdrop_request(["sky"])


## Campo de juego: piso a cuadros dentro de un marco de bloques de colores.
## Se cachea igual que draw_sky().
func draw_play_field(rect: Rect2, cell: float = 80.0) -> void:
	_backdrop_request(["field", rect, cell])


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
	_backdrop.draw.connect(_draw_backdrop)
	add_child(_backdrop, false, Node.INTERNAL_MODE_FRONT)
	_hud = Node2D.new()
	_hud.name = "Hud"
	_hud.draw.connect(_draw_hud_layer)
	add_child(_hud, false, Node.INTERNAL_MODE_BACK)
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
		_hud.queue_redraw()


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
	for op: Array in _backdrop_ops:
		match op[0]:
			"sky":
				_paint_sky(_backdrop)
			"field":
				_paint_play_field(_backdrop, op[1], op[2])


static func _paint_sky(ci: CanvasItem) -> void:
	ci.draw_polygon(PackedVector2Array([Vector2.ZERO, Vector2(SCREEN.x, 0), SCREEN, Vector2(0, SCREEN.y)]),
		PackedColorArray([UiTheme.SKY_TOP, UiTheme.SKY_TOP, UiTheme.SKY_BOTTOM, UiTheme.SKY_BOTTOM]))


static func _paint_play_field(ci: CanvasItem, rect: Rect2, cell: float) -> void:
	const FRAME := 26.0
	var frame := rect.grow(FRAME)
	UiTheme.draw_round_rect(ci, frame.grow(4), UiTheme.INK, 30)
	# Bloques de colores alrededor: filas arriba/abajo y columnas a los lados.
	var i := 0
	var x := frame.position.x
	while x < frame.end.x:
		var w := minf(96.0, frame.end.x - x)
		var c: Color = UiTheme.BRICKS[i % UiTheme.BRICKS.size()]
		ci.draw_rect(Rect2(x, frame.position.y, w, FRAME), c)
		ci.draw_rect(Rect2(x, rect.end.y, w, FRAME), UiTheme.BRICKS[(i + 4) % UiTheme.BRICKS.size()])
		x += 96.0
		i += 1
	var y0 := rect.position.y
	while y0 < rect.end.y:
		var h := minf(96.0, rect.end.y - y0)
		ci.draw_rect(Rect2(frame.position.x, y0, FRAME, h), UiTheme.BRICKS[i % UiTheme.BRICKS.size()])
		ci.draw_rect(Rect2(rect.end.x, y0, FRAME, h), UiTheme.BRICKS[(i + 3) % UiTheme.BRICKS.size()])
		y0 += 96.0
		i += 1
	ci.draw_rect(rect, UiTheme.FLOOR)
	var row := 0
	var y := rect.position.y
	while y < rect.end.y:
		var cx := rect.position.x + (0.0 if row % 2 == 0 else cell)
		while cx < rect.end.x:
			ci.draw_rect(Rect2(cx, y, minf(cell, rect.end.x - cx), minf(cell, rect.end.y - y)), UiTheme.FIELD_TILE)
			cx += cell * 2.0
		y += cell
		row += 1
	ci.draw_rect(rect, UiTheme.INK, false, 4.0)
