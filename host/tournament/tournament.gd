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
##     rows: [{id, slot, name, color, score, place, points, total_before, total}] }
## `players` son los que jugaron esa ronda (MiniGame.players).
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
		row.merge({"score": e.score, "place": place, "points": points, "total_before": before, "total": before + points})
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
	}
	history.append(summary)
	current_game_id = ""
	return summary


## Tabla general ordenada: más puntos primero; a igualdad, por lugar (1P, 2P…).
## Cada fila: {id, slot, name, color, total, place}.
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


func _playable(id: String, player_count: int) -> bool:
	var info := MiniGameRegistry.info(id)
	return not info.is_empty() and MiniGameRegistry.can_play(info, player_count)


func _remember(p: Dictionary) -> void:
	_roster[p.id] = {"id": p.id, "slot": p.slot, "name": p.name, "color": p.color}
