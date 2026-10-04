class_name HelpSession
extends Node
## Ayuda de los eliminados en la TV (docs/MODOS.md §11, ADR 0020): junta al
## juego (que valida y aplica la ayuda) con la competencia (que cobra).
##
##   1. Alguien queda afuera en un juego con "help" → pasa a "ayudante": su
##      celular recibe el layout joystick_ab con el hint "Elegí a quién
##      ayudar: 2P · 3P" (A = Ayudar, B = Cambiar). Sin cambios de protocolo.
##   2. Con el joystick elige: empujarlo hacia la mascota de un jugador vivo
##      (desde donde está la suya) lo elige; si no apunta a nadie, izquierda
##      y derecha rotan. B también rota. En la TV se ve la ficha con su 1P–4P
##      arriba del elegido (TvHelpOverlay).
##   3. Con A ayuda: la TV mira si el juego la acepta (MiniGame.help_denial),
##      si le alcanzan los puntos (Tournament.can_afford, costo doble si el
##      elegido va primero), aplica (MiniGame.apply_help) y cobra
##      (Tournament.spend). Si no alcanza, vibra "lose" y avisa en la TV.
##
## El celular solo manda `axis` y `btn`: todo lo decide la TV. Los bots
## eliminados usan lo mismo (BotDriver les pasa bot_view() y su entrada
## vuelve por on_input), así en modo solo pasa igual.
##
## Ejemplo: en Esquivar, Tomi (3P, 40 puntos) queda aplastado. Su celular
## muestra "Elegí a quién ayudar: 1P · 2P". Empuja el joystick hacia Sofi
## (2P), aprieta A: Sofi tiene burbuja 3 s, Tomi queda con 30 y la TV
## muestra "Tomi ayudó a Sofi · −10".

## Se aplicó una ayuda (ya cobrada). helper/target: jugadores del juego.
signal help_given(helper: Dictionary, target: Dictionary, cost: int)
## No se pudo ayudar. reason: el de MiniGame.help_denial, o "no_points".
signal help_denied(helper: Dictionary, reason: String, cost: int)
## Hay que mandarle a este jugador su control (layout_for).
signal layout_needed(player_id: int)
## Vibración/sonido en el celular (como MiniGame.feedback).
signal feedback(player_id: int, kind: String)

const SETTINGS_SECTION := "help"
const HINT := "Elegí a quién ayudar"
const BUTTON_A := "Ayudar"
const BUTTON_B := "Cambiar"
## Eje: se "arma" al soltarlo (≤ AXIS_ARM) y elige al empujarlo (≥ AXIS_FIRE):
## un empujón = una elección, aunque el celular mande 30 entradas por segundo.
const AXIS_ARM := 0.35
const AXIS_FIRE := 0.7
## Cono para elegir por dirección: coseno mínimo entre el joystick y la
## dirección hacia la mascota (0,5 = ±60°).
const DIRECTION_CONE := 0.5

## Opción del lobby "Ayudas: Sí/No" (se guarda en los ajustes de la TV).
static var enabled := true

var game: MiniGame
var tournament: Tournament
## helper_id -> {sel: target_id o -1, armed: bool, btn: int}
var helpers: Dictionary = {}
## Si es false, no mira solo en _physics_process (lo hace quien llama a poll()).
var auto_poll := true


func _init() -> void:
	name = "HelpSession"


static func load_prefs(path: String) -> void:
	var cfg := ConfigFile.new()
	if cfg.load(path) == OK:
		enabled = bool(cfg.get_value(SETTINGS_SECTION, "enabled", true))


static func save_prefs(path: String) -> void:
	var cfg := ConfigFile.new()
	cfg.load(path)  # Conserva el resto de las secciones.
	cfg.set_value(SETTINGS_SECTION, "enabled", enabled)
	cfg.save(path)


## Arranca para un juego. Solo se activa si las ayudas están prendidas, el
## juego ofrece una ("help" en get_info) y hay competencia que cobre.
func start(p_game: MiniGame, p_tournament: Tournament) -> void:
	stop()
	if not enabled or not is_instance_valid(p_game) or p_tournament == null or p_game.help_info().is_empty():
		return
	game = p_game
	tournament = p_tournament


func stop() -> void:
	game = null
	tournament = null
	helpers.clear()


func is_active() -> bool:
	return is_instance_valid(game) and tournament != null


## ¿La entrada de este jugador es para ayudar (y no para el juego)?
func handles(player_id: int) -> bool:
	return is_active() and helpers.has(player_id)


func _physics_process(_delta: float) -> void:
	if auto_poll and is_active() and game.is_inside_tree() and game.can_process():
		poll()


## Mira quién quedó afuera (nuevo ayudante: layout_needed) y corrige las
## elecciones de candidatos que también quedaron afuera.
func poll() -> void:
	if not is_active():
		return
	for p in game.players:
		var pid := int(p.id)
		if not helpers.has(pid) and game.help_is_out(pid) and not game.is_finished():
			helpers[pid] = {"sel": _default_target(pid), "armed": true, "btn": 0}
			if not bool(p.get("bot", false)):
				layout_needed.emit(pid)
	for pid: int in helpers:
		var h: Dictionary = helpers[pid]
		if int(h.sel) == -1 or not int(h.sel) in game.help_candidates(pid):
			h.sel = _default_target(pid)


## Control del ayudante: [layout, data]. Con ayudas: joystick_ab con el hint
## y los 1P–4P de los candidatos; sin ayudas por dar: "Mirá la TV".
func layout_for(player_id: int) -> Array:
	if not handles(player_id) or game.help_remaining(player_id) <= 0:
		return [Protocol.LAYOUT_WAIT, {}]
	var tags: Array[String] = []
	for pid in game.help_candidates(player_id):
		tags.append(UiTheme.player_tag(int(game.player_by_id(pid).get("slot", 0))))
	var hint := HINT if tags.is_empty() else "%s: %s" % [HINT, " · ".join(tags)]
	return [Protocol.LAYOUT_JOYSTICK_AB, {"hint": hint, "a": BUTTON_A, "b": BUTTON_B}]


## Entrada ya validada (Protocol.parse_input) de un ayudante.
func on_input(player_id: int, input: Dictionary) -> void:
	if not handles(player_id):
		return
	var h: Dictionary = helpers[player_id]
	var axis: Variant = input.get("axis", Vector2.ZERO)
	var a: Vector2 = (axis as Vector2).limit_length(1.0) if axis is Vector2 else Vector2.ZERO
	if not (is_finite(a.x) and is_finite(a.y)):
		a = Vector2.ZERO
	if a.length() <= AXIS_ARM:
		h.armed = true
	elif h.armed and a.length() >= AXIS_FIRE:
		h.armed = false
		select_toward(player_id, a)
	var btn := int(input.get("btn", 0)) & Protocol.BTN_MASK
	var down := btn & ~int(h.btn)
	h.btn = btn
	if down & Protocol.BTN_B:
		rotate_selection(player_id, 1)
	if down & Protocol.BTN_A:
		try_help(player_id)


## Elige al candidato hacia el que apunta `axis` (desde la mascota del
## ayudante). Si no apunta a nadie, izquierda/derecha rotan.
func select_toward(player_id: int, axis: Vector2) -> void:
	if not handles(player_id) or axis.length() < 0.01:
		return
	var h: Dictionary = helpers[player_id]
	var from := game.help_anchor(player_id)
	var dir := axis.normalized()
	var best := -1
	var best_dot := DIRECTION_CONE
	for pid in game.help_candidates(player_id):
		if pid == int(h.sel):
			continue  # Empujar hacia el que ya está elegido busca otro.
		var to := game.help_anchor(pid) - from
		if to.length() < 1.0:
			continue
		var d := dir.dot(to.normalized())
		if d > best_dot:
			best_dot = d
			best = pid
	if best != -1:
		_select(player_id, best)
	elif absf(axis.x) >= absf(axis.y) * 0.5:
		rotate_selection(player_id, 1 if axis.x > 0.0 else -1)


## Pasa al candidato siguiente (step 1) o anterior (-1), en orden de lugar.
func rotate_selection(player_id: int, step: int) -> void:
	if not handles(player_id):
		return
	var list := game.help_candidates(player_id)
	if list.is_empty():
		return
	var i := list.find(int(helpers[player_id].sel))
	_select(player_id, list[posmod(i + step, list.size())] if i != -1 else list[0])


func _select(player_id: int, target_id: int) -> void:
	if int(helpers[player_id].sel) != target_id:
		helpers[player_id].sel = target_id
		feedback.emit(player_id, "tap")


## Candidato elegido por este ayudante (-1 si ninguno).
func selected(player_id: int) -> int:
	return int((helpers.get(player_id, {}) as Dictionary).get("sel", -1))


## Cuánto le costaría ayudar a `target_id` (doble si va primero).
func cost_for(target_id: int) -> int:
	if not is_active():
		return 0
	return tournament.help_cost(target_id, int(game.help_info().get("cost", Tournament.HELP_BASE_COST)))


## Intenta ayudar al elegido. Devuelve "" si se aplicó o el motivo si no.
func try_help(player_id: int) -> String:
	if not handles(player_id):
		return "not_helper"
	var target := selected(player_id)
	var helper := game.player_by_id(player_id)
	var cost := cost_for(target) if target != -1 else 0
	# Primero los puntos: "te faltan puntos" le sirve más que "esperá".
	var reason := "no_points" if target != -1 and not tournament.can_afford(player_id, cost) else ""
	if reason.is_empty():
		reason = game.help_denial(player_id, target)
	if reason.is_empty() and not game.apply_help(player_id, target):
		reason = "rejected"
	if not reason.is_empty():
		help_denied.emit(helper, reason, cost)
		feedback.emit(player_id, "lose" if reason == "no_points" else "tap")
		return reason
	var target_p := game.player_by_id(target)
	var paid := tournament.spend(player_id, cost, "ayudó a %s" % str(target_p.get("name", "")), target)
	help_given.emit(helper, target_p, paid)
	feedback.emit(player_id, "point")
	if game.help_remaining(player_id) <= 0 and not bool(helper.get("bot", false)):
		layout_needed.emit(player_id)  # Ya no le quedan: "Mirá la TV".
	return ""


## Estado público para el bot de un ayudante (lo que se ve en la TV):
## candidatos y dónde está cada mascota, a quién eligió, quién va último en
## la competencia y si le alcanzan los puntos para ayudarlo.
func bot_view(player_id: int) -> Dictionary:
	if not handles(player_id):
		return {}
	var anchors := {}
	for pid in game.help_candidates(player_id):
		anchors[pid] = game.help_anchor(pid)
	var last := _default_target(player_id)
	return {
		"from": game.help_anchor(player_id), "candidates": anchors, "selected": selected(player_id),
		"last": last, "can_afford": last != -1 and tournament.can_afford(player_id, cost_for(last)),
		"remaining": game.help_remaining(player_id), "used": MiniGame.HELP_MAX_PER_HELPER - game.help_remaining(player_id),
		"wait": game.help_wait_left(player_id), "busy": last != -1 and game.help_active.has(last),
	}


## El que va último en la competencia entre los candidatos (a igualdad, el
## de lugar más bajo): la primera elección y a quien ayudan los bots.
func _default_target(player_id: int) -> int:
	var best := -1
	var best_total := 0
	for pid in game.help_candidates(player_id):
		var total := int(tournament.totals.get(pid, 0))
		if best == -1 or total < best_total:
			best = pid
			best_total = total
	return best

