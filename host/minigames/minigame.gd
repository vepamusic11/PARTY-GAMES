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

## Tamaño lógico de la pantalla de la TV (ver project.godot).
const SCREEN := Vector2(1920, 1080)

var players: Array[Dictionary] = []
var _finished := false


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


func draw_text_centered(text: String, pos: Vector2, size: int, color: Color = Color.WHITE) -> void:
	var font := ThemeDB.fallback_font
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	draw_string(font, pos - Vector2(w / 2.0, -size / 3.0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)
