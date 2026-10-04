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
var _buttons: Dictionary = {}  # player_id -> btn del último input (ver track_buttons)

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

# Efectos (ver "Efectos" más abajo y host/minigames/juice.gd).
var _juice: Juice
var _hitstop_left := 0.0
var _finale_left := -1.0         # >= 0: festejando antes de terminar (finish_after)
var _finale_result: Dictionary = {}
var _celebrating: Array = []     # player_id de los que festejan (celebrate)


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


## Estado público del juego para los bots (host/bots/, ADR 0010): lo mismo
## que cualquiera ve en la TV (posiciones, pelota, bloques…), nunca secretos
## ni atajos para decidir resultados. Es de SOLO LECTURA: puede devolver
## referencias a los datos internos para no copiar nada en cada frame.
## Por defecto {}: un juego sin bot propio igual funciona (el bot manda
## entradas suaves al azar). BotDriver lo llama una vez por paso de física.
func bot_view() -> Dictionary:
	return {}


# --- Ayuda de los eliminados (docs/MODOS.md §11, ADR 0020) ----------------------
#
# En los juegos donde se queda afuera a mitad de partida, el eliminado puede
# ayudar a alguien que sigue (a cambio de puntos de la competencia). Un juego
# la ofrece declarando en get_info():
#   "help": {"name": "Escudo burbuja", "cost": 10, "duration": 3.0}
# y sobrescribiendo help_is_out(), help_is_running(), help_anchor() y
# _start_help(). La base valida las reglas comunes (ayudante eliminado,
# objetivo vivo y distinto, tope, espera, una ayuda activa por objetivo) y
# lleva la cuenta del tiempo. La TV (HelpSession) cobra los puntos: el juego
# nunca toca la competencia. Guía: docs/ADDING_A_MINIGAME.md, "Ayuda de los
# eliminados". Los juegos sin "help" no cambian nada.

## Como mucho estas ayudas por eliminado en cada juego.
const HELP_MAX_PER_HELPER := 2
## Segundos de espera entre dos ayudas del mismo eliminado.
const HELP_COOLDOWN_SEC := 3.0

var _help_clock := 0.0         # segundos de juego (lo avanza help_tick)
var _help_used: Dictionary = {}     # helper_id -> ayudas dadas
var _help_ready_at: Dictionary = {} # helper_id -> _help_clock desde el que puede volver a ayudar
## Ayudas en curso: target_id -> {helper, left, total}. Solo lectura afuera.
var help_active: Dictionary = {}


## La ayuda que ofrece el juego ({name, cost, duration}) o {} si no tiene.
func help_info() -> Dictionary:
	var script: Script = get_script()
	var info: Variant = script.call("get_info") if script != null else {}
	var h: Variant = (info as Dictionary).get("help", {}) if info is Dictionary else {}
	return h if h is Dictionary else {}


## ¿Este jugador ya quedó afuera en este juego? Sobrescribir.
func help_is_out(_player_id: int) -> bool:
	return false


## ¿Se puede ayudar ahora? (el juego corre: no en la cuenta regresiva ni en
## el festejo final). Sobrescribir si hace falta.
func help_is_running() -> bool:
	return not is_finished() and not in_finale()


## Dónde está (en pantalla) la mascota de un jugador: para elegir a quién
## ayudar con el joystick y para dibujar la ayuda. Sobrescribir con la misma
## cuenta que usa el juego para dibujarla (en 2.5D, proyectada).
func help_anchor(_player_id: int) -> Vector2:
	return SCREEN / 2.0


## Escala a la que se dibuja la mascota de ese jugador (en 2.5D, con la profundidad).
func help_scale(_player_id: int) -> float:
	return 0.8


## A quién puede ayudar `helper_id` ahora (vivos, sin él), en orden de lugar.
func help_candidates(helper_id: int) -> Array[int]:
	var out: Array[int] = []
	for p in players:
		if int(p.id) != helper_id and not help_is_out(int(p.id)):
			out.append(int(p.id))
	return out


## Ayudas que le quedan a un eliminado en este juego.
func help_remaining(helper_id: int) -> int:
	return maxi(HELP_MAX_PER_HELPER - int(_help_used.get(helper_id, 0)), 0)


## Segundos que le faltan para poder volver a ayudar (0 = ya puede).
func help_wait_left(helper_id: int) -> float:
	return maxf(float(_help_ready_at.get(helper_id, 0.0)) - _help_clock, 0.0)


## Motivo por el que `helper_id` NO puede ayudar a `target_id` ahora, o ""
## si puede. No cobra nada ni cambia el juego (lo usa la TV antes de cobrar).
func help_denial(helper_id: int, target_id: int) -> String:
	if help_info().is_empty():
		return "no_help"
	if not help_is_running():
		return "not_running"
	if player_by_id(helper_id).is_empty() or player_by_id(target_id).is_empty():
		return "unknown_player"
	if not help_is_out(helper_id):
		return "helper_alive"
	if helper_id == target_id or help_is_out(target_id):
		return "bad_target"
	if help_remaining(helper_id) <= 0:
		return "no_helps_left"
	if help_wait_left(helper_id) > 0.0:
		return "cooldown"
	if help_active.has(target_id):
		return "target_busy"
	return ""


## Aplica la ayuda si las reglas lo permiten (ver help_denial). Devuelve
## true si se aplicó. No cobra puntos: eso lo hace la TV con Tournament.
func apply_help(helper_id: int, target_id: int) -> bool:
	if not help_denial(helper_id, target_id).is_empty():
		return false
	var duration := maxf(float(help_info().get("duration", 3.0)), 0.1)
	if not _start_help(helper_id, target_id, duration):
		return false
	_help_used[helper_id] = int(_help_used.get(helper_id, 0)) + 1
	_help_ready_at[helper_id] = _help_clock + HELP_COOLDOWN_SEC
	help_active[target_id] = {"helper": helper_id, "left": duration, "total": duration}
	return true


## La ayuda de este objetivo, si tiene una en curso ({helper, left, total}) o {}.
func help_for(target_id: int) -> Dictionary:
	return help_active.get(target_id, {})


## El juego usó la ayuda (el escudo aguantó el bloque, el salvavidas lo
## salvó): se termina y devuelve cuál era ({} si no tenía).
func consume_help(target_id: int) -> Dictionary:
	var h: Dictionary = help_active.get(target_id, {})
	help_active.erase(target_id)
	return h


## Avanza el reloj de las ayudas: llamarlo en cada paso del juego (después
## de hit_stopped). Las que se vencen sin usarse terminan solas.
func help_tick(delta: float) -> void:
	_help_clock += delta
	for target: int in help_active.keys():
		var h: Dictionary = help_active[target]
		h.left = float(h.left) - delta
		if float(h.left) <= 0.0 or help_is_out(target):
			help_active.erase(target)


## El juego arranca el efecto de la ayuda (sobrescribir). `duration` en
## segundos. Devolver false si no se pudo (no se cuenta ni se cobra).
func _start_help(_helper_id: int, _target_id: int, _duration: float) -> bool:
	return true


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


## Botones A y B (layouts one_button y joystick_ab). Llamar al principio de
## on_input: guarda el estado y devuelve los botones que se ACABAN de apretar
## (flanco de subida), para acciones de un toque (patear, saltar):
##   var down := track_buttons(player_id, input)
##   if down & Protocol.BTN_B: _jump(player_id)
## on_player_disconnected manda btn 0: suelta todo solo.
func track_buttons(player_id: int, input: Dictionary) -> int:
	var now := int(input.get("btn", 0)) & Protocol.BTN_MASK
	var before := int(_buttons.get(player_id, 0))
	_buttons[player_id] = now
	return now & ~before


## ¿Tiene apretado el botón (Protocol.BTN_A o BTN_B)? Según track_buttons.
func is_button_down(player_id: int, button: int = Protocol.BTN_A) -> bool:
	return (int(_buttons.get(player_id, 0)) & button) != 0


func pressed_a(player_id: int) -> bool:
	return is_button_down(player_id, Protocol.BTN_A)


func pressed_b(player_id: int) -> bool:
	return is_button_down(player_id, Protocol.BTN_B)


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


## Un cuadro completo sin depender del reloj del motor: la lógica
## (_physics_process) y lo que avanza con el tiempo de pantalla (_process: la
## cuenta del festejo final, animaciones). Lo usan las simulaciones de bots y
## los tests, que avanzan el juego a mano y más rápido que el tiempo real;
## si solo llamaran a _physics_process, un juego con finish_after() no
## terminaría nunca.
func simulate_frame(delta: float) -> void:
	_physics_process(delta)
	_process(delta)


func _process(delta: float) -> void:
	anim_time += delta
	if _finale_left >= 0.0:
		_finale_left -= delta
		if _finale_left < 0.0:
			finish(_finale_result)


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


# --- Efectos ("juice") --------------------------------------------------------
#
# Respuesta visual a cada acción, sin tocar reglas ni puntajes (ADR 0011):
#   juice().sparkles(pos)            estrellitas (también dust, sparks, confetti, splash, shine)
#   juice().float_text("+1", pos, p.color)   número flotante del color del jugador
#   juice().shake(0.8)               sacudida leve (nada con "Reducir movimiento")
#   juice().zoom_punch(pos)          zoom sutil hacia un punto
#   hit_stop()                       pausa de impacto: el juego se congela 70 ms
#   finish_after(result, "¡Tiempo!", pies_de_los_ganadores)   festejo y después finish

## Efectos del juego (se crea la primera vez que se pide: un juego sin
## efectos no paga nada).
func juice() -> Juice:
	if _juice == null:
		_juice = Juice.new(self)
		add_child(_juice, false, Node.INTERNAL_MODE_BACK)
	return _juice


## Pausa de impacto (*hit-stop*): congela la lógica del juego `sec` segundos
## en el momento del golpe, así se "siente". Los juegos llaman
## `if hit_stopped(delta): return` al principio de _physics_process.
func hit_stop(sec: float = UiTheme.DUR_HITSTOP) -> void:
	_hitstop_left = maxf(_hitstop_left, sec)


## true mientras dura la pausa de impacto (y la va descontando).
func hit_stopped(delta: float) -> bool:
	if _hitstop_left <= 0.0:
		return false
	_hitstop_left -= delta
	return true


## Momento final: muestra `text` con golpe de escala, tira confeti sobre los
## ganadores (`winners`: {player_id: pies}) y emite finished(result) después de
## UiTheme.DUR_FINALE. Mientras tanto el juego debería quedarse quieto
## (in_finale()) y dibujar a los ganadores festejando (is_celebrating(),
## celebrate_hop()). `sound`: "" si el juego ya sonó lo suyo.
func finish_after(result: Dictionary, text: String, winners: Dictionary = {}, sound: String = "time_up",
		delay: float = UiTheme.DUR_FINALE) -> void:
	if _finished or in_finale():
		return
	_finale_result = result
	_finale_left = maxf(delay, 0.0)
	celebrate(text, winners, sound)


## Cartel del final y confeti sobre cada ganador, sin terminar el juego: lo
## usa finish_after y los juegos que ya tienen su propia pausa final (Pintar
## el piso, Empujones).
func celebrate(text: String, winners: Dictionary = {}, sound: String = "time_up") -> void:
	_celebrating = winners.keys()
	juice().banner(text)
	if not sound.is_empty():
		play_sfx(sound)
	for pid: int in winners:
		juice().confetti((winners[pid] as Vector2) + Vector2(0, -110))


func in_finale() -> bool:
	return _finale_left >= 0.0


## ¿Este jugador está festejando (ganó y ya se mostró el cartel del final)?
func is_celebrating(player_id: int) -> bool:
	return player_id in _celebrating


## Saltito de festejo (px, para el parámetro `lift` de PlayerAvatar.draw_mascot).
func celebrate_hop(player_id: int) -> float:
	return absf(sin(anim_time * 7.0 + player_id)) * 18.0 if is_celebrating(player_id) else 0.0


## Cuenta regresiva grande en el centro ("3", "2", "1", "¡YA!"): cada número
## entra con un golpe de escala. `left`: segundos que faltan (negativo después
## del "¡YA!"); `go_sec`: cuánto se ve el "¡YA!".
func draw_countdown(left: float, go_sec: float = 0.8) -> void:
	if left > 0.0:
		_draw_popped("%d" % ceili(left), ceilf(left) - left, UiTheme.PAPER)
	elif left > -go_sec:
		_draw_popped("¡YA!", -left, UiTheme.ACCENT)


func _draw_popped(text: String, t: float, color: Color) -> void:
	var s := UiTheme.pop_scale(t, 0.25)
	draw_set_transform(SCREEN / 2.0, 0.0, Vector2(s, s))
	draw_text_centered(text, Vector2.ZERO, 260, color, 22)
	draw_set_transform(Vector2.ZERO)


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


## Marcador de salida "¿cuál soy yo?": durante los primeros
## UiTheme.START_MARK_SEC segundos del juego (los de la cuenta regresiva),
## sobre el globito de cada mascota rebota una flecha grande del color del
## jugador con su nombre en grande, y después se desvanece. Así un primerizo
## encuentra su mascota antes de que arranque la acción. Mismas entradas que
## draw_player_tags (llamarlo justo después). Barato: solo unos segundos y
## dos textos por jugador.
func draw_start_markers(entries: Array) -> void:
	var left := UiTheme.START_MARK_SEC - anim_time
	if left <= 0.0 or entries.is_empty():
		return
	var alpha := clampf(left / UiTheme.START_MARK_FADE, 0.0, 1.0)
	var bounce := 0.0 if UiTheme.reduce_motion else absf(sin(anim_time * 5.0)) * UiTheme.START_MARK_BOUNCE
	var s := UiTheme.START_MARK_ARROW
	var top := UiTheme.HUD_TOP + UiTheme.HUD_CLOCK_H + s * 2.2 + UiTheme.START_MARK_FONT
	for e: Array in entries:
		var p: Dictionary = e[0]
		var feet: Vector2 = e[1]
		var u: float = e[2] if e.size() > 2 else 0.8
		var col: Color = p.get("color", UiTheme.PAPER)
		# La punta de la flecha, arriba del globito 1P–4P (y nunca sobre el marcador).
		var tip := feet + Vector2(0, -118.0 * u - 14.0 - UiTheme.TAG_BUBBLE.y - bounce)
		tip.y = maxf(tip.y, top)
		var c := tip + Vector2(0, -s * 0.6)
		UiTheme.draw_arrow(self, c, s + 10.0, Vector2.DOWN, Color(UiTheme.INK, alpha))
		UiTheme.draw_arrow(self, c, s, Vector2.DOWN, Color(col, alpha))
		UiTheme.draw_text(self, str(p.get("name", "")), c + Vector2(0, -s * 0.7 - UiTheme.START_MARK_FONT * 0.6),
			UiTheme.START_MARK_FONT, Color(UiTheme.PAPER, alpha), UiTheme.START_MARK_OUTLINE, Color(UiTheme.INK, alpha))


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
	var badges: Array[Vector2] = []
	for i in mini(n, players.size()):
		_draw_hud_extra(_hud, players[i], pills[i])
		if players[i].get("bot", false):
			badges.append(Vector2(pills[i].position.x + 44.0, pills[i].end.y + 12.0))
	_draw_bot_badges(_hud, badges)


## Placas "BOT" debajo de la etiqueta 1P–4P del marcador (ADR 0010): todas
## las figuras en un lote (un draw call) y los textos después. Mismo dibujo
## que UiTheme.draw_bot_badge, que en el marcador costaría ~6 draw calls por bot.
static func _draw_bot_badges(ci: CanvasItem, centers: Array[Vector2], s: float = 0.9) -> void:
	if centers.is_empty():
		return
	var size := UiTheme.BOT_BADGE_SIZE * s
	var b := GameArt.TriBatch.new()
	for c in centers:
		var r := Rect2(c - size / 2.0, size)
		b.capsule(Rect2(r.position + Vector2(0, 3.0 * s), r.size).grow(3.0 * s), UiTheme.INK)
		b.capsule(r, UiTheme.BOT_BADGE_LIGHT)
		b.capsule(r.grow(-2.0 * s), UiTheme.BOT_BADGE.darkened(0.3))
		b.capsule(Rect2(r.position, r.size - Vector2(0, 4.0 * s)).grow(-2.0 * s), UiTheme.BOT_BADGE)
		b.capsule(Rect2(r.position + Vector2(8.0 * s, 3.0 * s), Vector2(size.x * 0.5, size.y * 0.28)), Color(1, 1, 1, 0.3))
	b.flush(ci)
	for c in centers:
		UiTheme.draw_text(ci, UiTheme.BOT_TEXT, c - Vector2(0, 2.0 * s), int(UiTheme.BOT_BADGE_FONT * s), UiTheme.PAPER, int(4 * s), UiTheme.INK)


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
## Con render, el escenario es la sala de juguetes en 3D horneada una vez
## (receta "stage" del tablero 2.5D, ADR 0019: piso en perspectiva y
## bloques de plástico fuera de foco), la misma textura de pantalla completa
## para todos los juegos sin tablero 2.5D; mientras se hornea, sin render o
## si falla, el escenario pintado de siempre (GameArt.stage_texture).
func draw_sky() -> void:
	var tex := Board25DBaker.texture_for(stage_view())
	if tex == null:
		if is_inside_tree():
			Board25DBaker.request(self, stage_view())
		_backdrop_request(["sky"])
		return
	_backdrop_request(["board25d", tex])
	Board25DBaker.retain(stage_view(), self)


static var _stage_view: BoardView25D


## Vista de la sala de juguetes sin tablero (el "cielo" 3D de draw_sky):
## los juguetes rodean un área del tamaño del tablero de Pintar el piso.
static func stage_view() -> BoardView25D:
	if _stage_view == null:
		_stage_view = BoardView25D.make(UiTheme.BOARD25D_STAGE_AREA, UiTheme.BOARD25D_STAGE_AREA.size.x / 20.0, Board25DScene.RECIPE_STAGE)
	return _stage_view


## Campo de juego: tablero con volumen (sombra proyectada, marco de bloques
## con bisel y estrellas en las esquinas) y baldosas con relieve de lado
## `cell`. Se cachea igual que draw_sky().
func draw_play_field(rect: Rect2, cell: float = 80.0) -> void:
	_backdrop_request(["field", rect, cell])


## Escenario 2.5D horneado (ADR 0019): tablero 3D con marco, entorno de
## juguetes y cámara en perspectiva, dibujado como UNA textura en la capa de
## fondo (en lugar de draw_sky() + draw_play_field()). Devuelve false si
## todavía no está (se pide en segundo plano) o no hay render (--headless,
## tests, un aparato donde falló): el juego dibuja plano, como siempre.
## Uso en _draw():
##   _v25 = draw_board_25d(board_view())
##   if not _v25:
##       draw_sky()
##       draw_play_field(FIELD, CELL)
## y el resto del dibujo pasa por la vista (ver BoardView25D y
## docs/ADDING_A_MINIGAME.md, "Tablero 2.5D").
func draw_board_25d(view: BoardView25D) -> bool:
	var tex := Board25DBaker.texture_for(view)
	if tex == null:
		if is_inside_tree():
			Board25DBaker.request(self, view)
		return false
	_backdrop_request(["board25d", tex])
	# Al salir el último juego que la usa, la textura (~6–8 MB) se suelta.
	Board25DBaker.retain(view, self)
	return true


## El host lo llama durante la intro "¿Cómo se juega?" de este juego (como el
## precalentado de mascotas): para preparar arte caro antes de jugar, ej.
## Board25DBaker.request(host, board_view()). `players`: los que van a
## jugar (un tablero que depende de cuántos son, como los carriles, lo
## necesita). Por defecto, la sala de juguetes de draw_sky().
static func prewarm_art(host: Node, _players: Array = []) -> void:
	Board25DBaker.request(host, stage_view())


## Tapa con la textura del escenario 2.5D los polígonos `polys` (en px de
## pantalla): sirve para que lo que se dibuja encima del tablero quede
## "detrás" de una parte del escenario horneado (la banda de adelante de la
## mesa de pool, el marco a los costados de los carriles). La textura es de
## pantalla completa, así que cualquier polígono se pinta con lo mismo que
## hay debajo, en 1 draw call (todos comparten la textura).
func draw_board_25d_cover(view: BoardView25D, polys: Array) -> void:
	var tex := Board25DBaker.texture_for(view)
	if tex == null:
		return
	for poly: PackedVector2Array in polys:
		if poly.size() < 3:
			continue
		var uvs := PackedVector2Array()
		uvs.resize(poly.size())
		for i in poly.size():
			uvs[i] = poly[i] / SCREEN
		draw_polygon(poly, PackedColorArray([Color.WHITE]), uvs, tex)


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
			"board25d":
				_backdrop.draw_texture_rect(op[1], Rect2(Vector2.ZERO, SCREEN), false)


## Tablero con volumen: ver GameArt.paint_board.
static func _paint_play_field(ci: CanvasItem, rect: Rect2, cell: float) -> void:
	GameArt.paint_board(ci, rect, cell)
