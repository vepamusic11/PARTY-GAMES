class_name Tournament
extends RefCounted
## Modo competencia: una lista de minijuegos que se juegan en orden y una
## tabla de puntos acumulados. Es lógica pura (sin nodos ni UI): se testea
## aislada y la TV solo la consulta.
##
## Concepto: *puntos por posición*. Cada minijuego mide cosas distintas
## (estrellas, toques, goles) en escalas distintas. Sumar esos números
## crudos no sería justo: 40 toques no "valen" más que 5 goles. Por eso
## cada ronda se traduce a posiciones, y la posición da puntos fijos:
##   1° = 100 · 2° = 70 · 3° = 50 · 4° = 30
## Ejemplo: en Arena, Pablo junta 12 estrellas y Sofi y Tomi 9 cada uno.
##   Pablo 1° (+100); Sofi y Tomi empatan en 2° (+70 cada uno).
## Los empates comparten puesto y el siguiente se saltea ("1-2-2-4").

const PLACE_POINTS: Array[int] = [100, 70, 50, 30]

var game_ids: Array[String] = []
var totals: Dictionary = {}           # player_id -> int
var history: Array[Dictionary] = []   # resumen de cada ronda jugada
var skipped: Array[String] = []       # juegos salteados (sin puntos)
var current_game_id := ""
## Ayudas de los eliminados de la ronda en curso (ver "Ayuda de los
## eliminados" más abajo). record() las pasa al resumen de la ronda
## (`history[i].helps`); saltear el juego las devuelve.
var pending_helps: Array[Dictionary] = []

var _roster: Dictionary = {}          # player_id -> {id, slot, name, color}
var _cursor := 0


## game_ids desconocidos o repetidos se descartan.
func _init(p_game_ids: Array[String], players: Array[Dictionary], shuffle: bool = false) -> void:
	for id in p_game_ids:
		if not MiniGameRegistry.info(id).is_empty() and not id in game_ids:
			game_ids.append(id)
	if shuffle:
		game_ids.shuffle()
	for p in players:
		_remember(p)
		totals[p.id] = 0


# --- Avance ---------------------------------------------------------------------

## Pasa al siguiente juego jugable con `player_count` jugadores y lo
## devuelve. Los que no se pueden jugar (ej. alguien se fue y Ping Pong
## necesita 2) se saltean. Devuelve "" si no quedan juegos.
func advance(player_count: int) -> String:
	current_game_id = ""
	while _cursor < game_ids.size():
		var id := game_ids[_cursor]
		_cursor += 1
		if _playable(id, player_count):
			current_game_id = id
			return id
		skipped.append(id)
	return ""


## Qué juego vendría después, sin avanzar (para mostrar "Siguiente: …").
func peek_next(player_count: int) -> String:
	for i in range(_cursor, game_ids.size()):
		if _playable(game_ids[i], player_count):
			return game_ids[i]
	return ""


## El juego en curso se abandona sin dar puntos (desde el menú de pausa).
func skip_current() -> void:
	if not current_game_id.is_empty():
		skipped.append(current_game_id)
		current_game_id = ""
	_refund_pending_helps()


func is_over() -> bool:
	return current_game_id.is_empty() and _cursor >= game_ids.size()


## Rondas totales descontando las salteadas (el denominador de "2/3").
func total_rounds() -> int:
	return game_ids.size() - skipped.size()


## Número de la ronda en curso (o la última jugada), empezando en 1.
func round_number() -> int:
	return history.size() + (0 if current_game_id.is_empty() else 1)


# --- Resultados -----------------------------------------------------------------

## Registra el resultado de un minijuego (ver MiniGame.finished) y devuelve
## el resumen de la ronda:
##   { round, total_rounds, game_id, title, score_label,
##     rows: [{id, slot, name, color, style, bot, score, place, points, spent, total_before, total}],
##     helps: [{helper, target, points, reason, helper_name, target_name, …}] }
## `players` son los que jugaron esa ronda (MiniGame.players). `spent`: lo
## que ese jugador gastó ayudando en esta ronda (ya descontado de
## total_before, así la tabla sube desde lo que le quedó).
func record(result: Dictionary, players: Array[Dictionary]) -> Dictionary:
	var scores: Variant = result.get("scores", {})
	var winners: Variant = result.get("winners", [])
	if typeof(scores) != TYPE_DICTIONARY:
		scores = {}
	if typeof(winners) != TYPE_ARRAY:
		winners = []
	var entries: Array[Dictionary] = []
	for p in players:
		_remember(p)
		var raw: Variant = (scores as Dictionary).get(p.id, 0)
		var score := float(raw) if typeof(raw) == TYPE_INT or typeof(raw) == TYPE_FLOAT else 0.0
		entries.append({"id": p.id, "score": score if is_finite(score) else 0.0, "winner": p.id in (winners as Array)})
	var places := rank(entries)

	var rows: Array[Dictionary] = []
	for e in entries:
		var pid: int = e.id
		var place: int = places[pid]
		var before: int = totals.get(pid, 0)
		var points := points_for_place(place)
		totals[pid] = before + points
		var row := (_roster[pid] as Dictionary).duplicate()
		row.merge({"score": e.score, "place": place, "points": points, "spent": _spent_this_round(pid),
			"total_before": before, "total": before + points})
		rows.append(row)
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.slot < b.slot)

	var info := MiniGameRegistry.info(current_game_id)
	var summary := {
		"round": history.size() + 1,
		"total_rounds": total_rounds(),
		"game_id": current_game_id,
		"title": info.get("title", ""),
		"score_label": info.get("score_label", "puntos"),
		"rows": rows,
		"helps": pending_helps.duplicate(),
	}
	pending_helps.clear()
	history.append(summary)
	current_game_id = ""
	return summary


## Tabla general ordenada: más puntos primero; a igualdad, por lugar (1P, 2P…).
## Cada fila: {id, slot, name, color, style, bot, total, place}.
func standings() -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	for pid: int in _roster:
		var row := (_roster[pid] as Dictionary).duplicate()
		row["total"] = int(totals.get(pid, 0))
		rows.append(row)
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return a.total > b.total or (a.total == b.total and a.slot < b.slot))
	for i in rows.size():
		rows[i]["place"] = 1 if i == 0 else (rows[i - 1].place if rows[i].total == rows[i - 1].total else i + 1)
	return rows


## Posiciones con empates compartidos. Ganadores declarados por el juego
## primero (ej. en Carrera gana quien cruza la meta), después más puntaje.
## entries: [{id, score, winner}] -> {id: puesto}
static func rank(entries: Array[Dictionary]) -> Dictionary:
	var sorted := entries.duplicate()
	sorted.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if a.winner != b.winner:
			return a.winner
		return a.score > b.score)
	var places := {}
	for i in sorted.size():
		var e: Dictionary = sorted[i]
		if i > 0 and e.winner == sorted[i - 1].winner and e.score == sorted[i - 1].score:
			places[e.id] = places[sorted[i - 1].id]
		else:
			places[e.id] = i + 1
	return places


static func points_for_place(place: int) -> int:
	return PLACE_POINTS[clampi(place - 1, 0, PLACE_POINTS.size() - 1)]


# --- Ayuda de los eliminados (docs/MODOS.md §11, ADR 0020) ---------------------
#
# El que ya quedó afuera en un juego puede ayudar a otro que sigue, pero le
# cuesta puntos de su total. Acá solo vive la cuenta (lógica pura): quién
# puede pagar, cuánto cuesta y el registro. El juego decide si la ayuda
# vale (MiniGame.apply_help) y la TV (HelpSession) junta las dos cosas.
#
# Ejemplo: Tomi (40 puntos) ayuda a Sofi (70) → cuesta 10, le quedan 30.
# Si ayudara a Pablo, que va primero con 170, costaría 20 (contra el
# "hacedor de reyes": ayudar sirve más para emparejar que para decidir).

## Costo base de una ayuda (≈ ⅓ de un 4.° puesto). Cada juego puede pedir
## otro en su HELP.cost.
const HELP_BASE_COST := 10
## Ayudar al que va primero cuesta este múltiplo.
const HELP_LEADER_FACTOR := 2


## ¿Va primero en la competencia? Primero (solo o empatado) y con más puntos
## que alguien: al empezar, con todos en 0, nadie "va primero".
func is_leader(player_id: int) -> bool:
	if not totals.has(player_id) or totals.size() < 2:
		return false
	var top := -1
	var low := -1
	for pid: int in totals:
		var v := int(totals[pid])
		top = v if top < 0 else maxi(top, v)
		low = v if low < 0 else mini(low, v)
	return int(totals[player_id]) == top and top > low


## Cuánto cuesta ayudar a `target_id`: `base` (HELP.cost del juego), el doble
## si va primero. Nunca negativo.
func help_cost(target_id: int, base: int = HELP_BASE_COST) -> int:
	return maxi(base, 0) * (HELP_LEADER_FACTOR if is_leader(target_id) else 1)


## ¿Le alcanzan los puntos? (si el total no alcanza, no se puede ayudar).
func can_afford(player_id: int, points: int) -> bool:
	return totals.has(player_id) and points >= 0 and int(totals[player_id]) >= points


## Descuenta `points` del total de `helper_id` (nunca por debajo de 0) y lo
## registra en la ronda en curso (pasa a history con record()). Devuelve lo
## que se descontó de verdad. `reason`: texto para el resumen ("ayudó a
## Sofi"); `target_id`: a quién ayudó (-1 si no aplica).
func spend(helper_id: int, points: int, reason: String, target_id: int = -1) -> int:
	if not totals.has(helper_id) or points <= 0:
		return 0
	var paid := mini(points, int(totals[helper_id]))
	if paid <= 0:
		return 0
	totals[helper_id] = int(totals[helper_id]) - paid
	pending_helps.append({
		"helper": helper_id, "target": target_id, "points": paid, "reason": reason,
		"game_id": current_game_id, "round": round_number(),
		"helper_name": str((_roster.get(helper_id, {}) as Dictionary).get("name", "")),
		"target_name": str((_roster.get(target_id, {}) as Dictionary).get("name", "")),
	})
	return paid


## Juego salteado desde la pausa: sus resultados no cuentan, y las ayudas
## que se pagaron en él tampoco (se devuelven los puntos).
func _refund_pending_helps() -> void:
	for h in pending_helps:
		var pid: int = h.helper
		if totals.has(pid):
			totals[pid] = int(totals[pid]) + int(h.points)
	pending_helps.clear()


func _spent_this_round(player_id: int) -> int:
	var sum := 0
	for h in pending_helps:
		if int(h.helper) == player_id:
			sum += int(h.points)
	return sum


func _playable(id: String, player_count: int) -> bool:
	var info := MiniGameRegistry.info(id)
	return not info.is_empty() and MiniGameRegistry.can_play(info, player_count)


func _remember(p: Dictionary) -> void:
	# El estilo de mascota viaja con el jugador (resumen y podio lo dibujan),
	# y también si es un bot (placa "BOT" en el resumen).
	_roster[p.id] = {"id": p.id, "slot": p.slot, "name": p.name, "color": p.color, "style": PlayerAvatar.style_of(p),
		"bot": bool(p.get("bot", false))}
