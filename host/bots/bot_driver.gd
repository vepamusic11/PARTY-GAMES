class_name BotDriver
extends Node
## Hace jugar a los bots del juego en curso: en cada paso de física lee
## `MiniGame.bot_view()` una vez, le pide a cada bot su entrada, la valida
## con `Protocol.parse_input` (exactamente como HostServer valida la de un
## celular) y se la pasa al juego con `on_input`. Sin red.
##
##   HostMain._start_game  -> driver.start(juego, jugadores)
##   cada paso de física   -> driver.step(delta)   (solo si el juego corre:
##                            en pausa el juego está deshabilitado y los
##                            bots tampoco piensan)
##   HostMain._end_game    -> driver.stop()
##
## tools/simulate.gd y los tests llaman a step() a mano, sin pantalla.

## Bot de cada juego (host/bots/<id>_bot.gd). Un juego que no esté acá juega
## con Bot (entradas suaves al azar): sumar un juego nunca rompe los bots.
const GAME_BOTS := {
	"arena": preload("res://host/bots/arena_bot.gd"),
	"pingpong": preload("res://host/bots/pingpong_bot.gd"),
	"tap_race": preload("res://host/bots/tap_race_bot.gd"),
	"stop_clock": preload("res://host/bots/stop_clock_bot.gd"),
	"dodge": preload("res://host/bots/dodge_bot.gd"),
	"paint": preload("res://host/bots/paint_bot.gd"),
	"sumo": preload("res://host/bots/sumo_bot.gd"),
}

var bots: Array[Bot] = []
var game: MiniGame
## Entradas fuera de rango que generó algún bot (siempre debería ser 0: lo
## miran los tests). Igual nunca llegan al juego: parse_input las recorta.
var invalid_outputs := 0
## Solo tests/simulación: guarda cada entrada cruda [player_id, axis, btn].
var record := false
var raw_log: Array = []
## Semilla de los bots (0 = al azar). Cada bot usa semilla + su id.
var seed_value := 0
## Si es false, no se mueve solo en _physics_process (lo avanza quien llama a step()).
var auto_step := true


func _init() -> void:
	name = "BotDriver"
	# Antes que los juegos: la entrada del bot llega en el mismo paso.
	process_physics_priority = -10


## Crea un bot para cada jugador con `bot: true`. Los demás no se tocan.
func start(p_game: MiniGame, players: Array[Dictionary]) -> void:
	stop()
	if not is_instance_valid(p_game):
		return
	game = p_game
	var info := MiniGameRegistry.info(str(p_game.get_info().get("id", "")))
	if info.is_empty():
		info = p_game.get_info()
	for p in players:
		if bool(p.get("bot", false)):
			bots.append(create_bot(str(info.get("id", "")), p, info, seed_value + int(p.id) if seed_value != 0 else 0))


func stop() -> void:
	bots.clear()
	game = null


## El bot de un juego para un jugador (Bot base si el juego no tiene uno propio).
static func create_bot(game_id: String, player: Dictionary, info: Dictionary, bot_seed: int = 0) -> Bot:
	var script: Script = GAME_BOTS.get(game_id, null)
	var bot: Bot = script.new() if script != null else Bot.new()
	bot.setup(int(player.get("id", 0)), int(player.get("slot", 0)), int(player.get("difficulty", Bot.Difficulty.NORMAL)), info, bot_seed)
	return bot


func has_bots() -> bool:
	return not bots.is_empty()


func _physics_process(delta: float) -> void:
	if auto_step and is_instance_valid(game) and game.is_inside_tree() and game.can_process():
		step(delta)


## Un paso: cada bot decide y su entrada (validada) llega al juego.
func step(delta: float) -> void:
	if bots.is_empty() or not is_instance_valid(game) or game.is_finished():
		return
	var view := game.bot_view()
	for bot in bots:
		var out := bot.tick(view, delta)
		if not Bot.is_valid_output(out):
			invalid_outputs += 1
		if record:
			raw_log.append([bot.player_id, out.get("axis"), out.get("btn")])
		var axis: Vector2 = out.axis if out.get("axis") is Vector2 else Vector2.ZERO
		var input := Protocol.parse_input({"seq": bot.next_seq(), "axis": [axis.x, axis.y], "btn": out.get("btn", 0)})
		if not input.is_empty():
			game.on_input(bot.player_id, input)
