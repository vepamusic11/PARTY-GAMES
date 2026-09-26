class_name MiniGameRegistry
extends RefCounted
## Catálogo de minijuegos. Para sumar uno nuevo alcanza con agregar su
## script a GAMES (ver docs/ADDING_A_MINIGAME.md).

const GAMES: Array[Script] = [
	preload("res://host/minigames/arena/arena.gd"),
	preload("res://host/minigames/pingpong/pingpong.gd"),
	preload("res://host/minigames/tap_race/tap_race.gd"),
]


static func all_info() -> Array[Dictionary]:
	var list: Array[Dictionary] = []
	for script in GAMES:
		list.append(script.call("get_info"))
	return list


static func info(game_id: String) -> Dictionary:
	for script in GAMES:
		var i: Dictionary = script.call("get_info")
		if i.id == game_id:
			return i
	return {}


static func create(game_id: String) -> MiniGame:
	for script in GAMES:
		if script.call("get_info").id == game_id:
			return script.new() as MiniGame
	return null


static func can_play(info: Dictionary, player_count: int) -> bool:
	return player_count >= int(info.min_players) and player_count <= int(info.max_players)
