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


## Texto centrado con la tipografía del juego. outline > 0 le pone contorno.
func draw_text_centered(text: String, pos: Vector2, size: int, color: Color = Color.WHITE,
		outline: int = 0) -> void:
	UiTheme.draw_text(self, text, pos, size, color, outline, UiTheme.INK)


## Marcador superior común a todos los juegos, como en las consolas:
##   [1P 12] [2P 9] [ 0:28 ] [3P 7] [4P 3]
## scores: {player_id: número}. center: tiempo, ronda o lo que el juego quiera.
func draw_hud(scores: Dictionary, center: String) -> void:
	const CHIP := Vector2(230, 58)
	const CENTER_W := 250.0
	const GAP := 16.0
	var n := players.size()
	var x := (SCREEN.x - (n * CHIP.x + CENTER_W + n * GAP)) / 2.0
	var half := ceili(n / 2.0)
	for i in n + 1:
		if i == half:
			UiTheme.draw_hex_chip(self, Rect2(x, 24, CENTER_W, CHIP.y), "", Color.WHITE, center, true)
			x += CENTER_W + GAP
		if i < n:
			var p: Dictionary = players[i]
			var value := float(scores.get(p.id, 0))
			UiTheme.draw_hex_chip(self, Rect2(Vector2(x, 24), CHIP), UiTheme.player_tag(p.slot), p.color, str(roundi(value)))
			x += CHIP.x + GAP


## "0:28": segundos restantes en formato reloj.
static func clock_text(seconds: float) -> String:
	var s := ceili(maxf(seconds, 0.0))
	return "%d:%02d" % [s / 60, s % 60]


## Fondo de cielo que usan todos los juegos (coherente con el lobby).
func draw_sky() -> void:
	draw_polygon(PackedVector2Array([Vector2.ZERO, Vector2(SCREEN.x, 0), SCREEN, Vector2(0, SCREEN.y)]),
		PackedColorArray([UiTheme.SKY_TOP, UiTheme.SKY_TOP, UiTheme.SKY_BOTTOM, UiTheme.SKY_BOTTOM]))


## Campo de juego: piso a cuadros dentro de un marco de bloques de colores.
func draw_play_field(rect: Rect2, cell: float = 80.0) -> void:
	const FRAME := 26.0
	var frame := rect.grow(FRAME)
	UiTheme.draw_round_rect(self, frame.grow(4), UiTheme.INK, 30)
	# Bloques de colores alrededor: filas arriba/abajo y columnas a los lados.
	var i := 0
	var x := frame.position.x
	while x < frame.end.x:
		var w := minf(96.0, frame.end.x - x)
		var c: Color = UiTheme.BRICKS[i % UiTheme.BRICKS.size()]
		draw_rect(Rect2(x, frame.position.y, w, FRAME), c)
		draw_rect(Rect2(x, rect.end.y, w, FRAME), UiTheme.BRICKS[(i + 4) % UiTheme.BRICKS.size()])
		x += 96.0
		i += 1
	var y0 := rect.position.y
	while y0 < rect.end.y:
		var h := minf(96.0, rect.end.y - y0)
		draw_rect(Rect2(frame.position.x, y0, FRAME, h), UiTheme.BRICKS[i % UiTheme.BRICKS.size()])
		draw_rect(Rect2(rect.end.x, y0, FRAME, h), UiTheme.BRICKS[(i + 3) % UiTheme.BRICKS.size()])
		y0 += 96.0
		i += 1
	draw_rect(rect, Color("#F4F6FB"))
	var row := 0
	var y := rect.position.y
	while y < rect.end.y:
		var cx := rect.position.x + (0.0 if row % 2 == 0 else cell)
		while cx < rect.end.x:
			draw_rect(Rect2(cx, y, minf(cell, rect.end.x - cx), minf(cell, rect.end.y - y)), Color("#E3E8F2"))
			cx += cell * 2.0
		y += cell
		row += 1
	draw_rect(rect, UiTheme.INK, false, 4.0)
