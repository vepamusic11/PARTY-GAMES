class_name BotMatch
extends RefCounted
## Juega un minijuego completo sin pantalla ni red, a toda velocidad: pasos
## de física fijos de 1/60 s llamados a mano (60 s de juego tardan una
## fracción de segundo). Lo usan los tests y tools/simulate.gd.
##
## Los jugadores con `bot: true` los maneja un BotDriver; para los demás,
## `feed` (opcional) hace de celular: recibe (juego, player_id, segundos) y
## devuelve la entrada cruda {axis, btn}, que pasa por Protocol.parse_input
## igual que la de la red.
##
## Ejemplo:
##   var r := BotMatch.run(root, "arena", [bot_robi, bot_chispa])
##   r.result.scores   -> {1: 14, 2: 11}
##   r.seconds         -> 30.0

const STEP := 1.0 / 60.0


## Devuelve {finished, seconds, result, invalid_outputs, raw_log, bot_ms}.
## `max_sec` corta juegos que no terminan (ej. un bot que no hace nada en
## Ping Pong). bot_ms: cuánto tardó cada paso de los bots (todos juntos), en
## ms: lo que suman a "Scripts" en la TV (ver docs/PERFORMANCE.md).
static func run(parent: Node, game_id: String, players: Array[Dictionary], max_sec: float = 180.0,
		seed_value: int = 0, feed: Callable = Callable(), record: bool = false) -> Dictionary:
	var game := MiniGameRegistry.create(game_id)
	if game == null:
		return {}
	# Sin proceso propio: el motor no lo avanza, solo estos pasos a mano.
	game.process_mode = Node.PROCESS_MODE_DISABLED
	parent.add_child(game)
	game.setup(players)
	var driver := BotDriver.new()
	driver.auto_step = false
	driver.seed_value = seed_value
	driver.record = record
	driver.start(game, players)
	var result := {}
	game.finished.connect(func(r: Dictionary) -> void: result.merge(r, true))
	var t := 0.0
	var seq := 0
	var bot_ms := PackedFloat32Array()
	while not game.is_finished() and t < max_sec:
		if feed.is_valid():
			for p in players:
				if not bool(p.get("bot", false)):
					var raw: Dictionary = feed.call(game, int(p.id), t)
					var axis: Vector2 = raw.get("axis", Vector2.ZERO)
					seq += 1
					var input := Protocol.parse_input({"seq": seq, "axis": [axis.x, axis.y], "btn": raw.get("btn", 0)})
					if not input.is_empty():
						game.on_input(int(p.id), input)
		var t0 := Time.get_ticks_usec()
		driver.step(STEP)
		bot_ms.append((Time.get_ticks_usec() - t0) / 1000.0)
		game._physics_process(STEP)
		t += STEP
	var out := {
		"finished": game.is_finished(), "seconds": t, "result": result,
		"invalid_outputs": driver.invalid_outputs, "raw_log": driver.raw_log, "bot_ms": bot_ms,
	}
	driver.stop()
	driver.free()
	game.free()
	return out


## Jugadores bot inventados (como los arma HostServer.add_bot).
static func bot_players(n: int, difficulty: int = Bot.Difficulty.NORMAL) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for i in n:
		out.append({
			"id": i + 1, "slot": i, "name": HostServer.BOT_NAMES[i % HostServer.BOT_NAMES.size()],
			"color": Protocol.player_color(i), "color_index": i, "style": PlayerAvatar.STYLE_ROBOT,
			"connected": true, "bot": true, "difficulty": difficulty,
		})
	return out
