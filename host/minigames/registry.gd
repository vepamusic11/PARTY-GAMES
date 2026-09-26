class_name MiniGameRegistry
extends RefCounted
## Catálogo de minijuegos. Para sumar uno nuevo alcanza con agregar su
## script a GAMES (ver docs/ADDING_A_MINIGAME.md).

const GAMES: Array[Script] = [
	preload("res://host/minigames/arena/arena.gd"),
	preload("res://host/minigames/pingpong/pingpong.gd"),
	preload("res://host/minigames/tap_race/tap_race.gd"),
	preload("res://host/minigames/stop_clock/stop_clock.gd"),
	preload("res://host/minigames/dodge/dodge.gd"),
	preload("res://host/minigames/paint/paint.gd"),
]


## Metadatos opcionales y su valor si el juego no los define.
const OPTIONAL_DEFAULTS := {
	"accent": Color("#3E7BFA"),   ## Color de la tarjeta en el lobby.
	"score_label": "puntos",      ## Unidad del puntaje: "12 estrellas".
}


static func all_info() -> Array[Dictionary]:
	var list: Array[Dictionary] = []
	for script in GAMES:
		list.append(_with_defaults(script.call("get_info")))
	return list


static func info(game_id: String) -> Dictionary:
	for script in GAMES:
		var i: Dictionary = script.call("get_info")
		if i.id == game_id:
			return _with_defaults(i)
	return {}


static func create(game_id: String) -> MiniGame:
	for script in GAMES:
		if script.call("get_info").id == game_id:
			return script.new() as MiniGame
	return null


static func can_play(info: Dictionary, player_count: int) -> bool:
	return player_count >= int(info.min_players) and player_count <= int(info.max_players)


static func _with_defaults(i: Dictionary) -> Dictionary:
	var out := i.duplicate()
	out.merge(OPTIONAL_DEFAULTS)  # merge sin overwrite: lo del juego manda.
	return out
