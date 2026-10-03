extends SceneTree
## Simulación de competencias bot contra bot, sin pantalla y a toda
## velocidad, para balancear juegos (ver ADR 0010 y docs/PRODUCCION.md).
##
##   godot --headless --path . -s res://tools/simulate.gd
##   … -- --n=50                  competencias (default 20)
##   … -- --players=4             bots por competencia (1..4; default 4)
##   … -- --difficulty=normal     easy | normal | hard | mixed (1P fácil, 2P normal, 3P difícil, 4P normal)
##   … -- --games=arena,dodge     solo esos juegos (default: todos los del registry)
##   … -- --seed=7                semilla de los bots (los juegos siguen al azar: sirve para
##                                comparar cambios de un bot con menos ruido)
##   … -- --json=/tmp/sim.json    además guarda las estadísticas en JSON
##
## Cada competencia juega todos los juegos elegidos que admiten esa cantidad
## (con 4 bots, Ping Pong se saltea: se prueba aparte con --players=2).
##
## Qué imprime, por juego:
##   duración   segundos de juego (media, p50, p95, máx) y cuántos no terminaron
##   puntaje    del juego (estrellas, toques…): media, mínimo, máximo
##   ventaja    % de rondas ganadas según el lugar de salida (1P..4P): con
##              bots iguales debería rondar 100/jugadores; si un lugar gana
##              mucho más, el juego da ventaja por dónde arrancás
##   ptos/lugar puntos de competencia promedio de cada lugar
##   bots p95   ms que tardan TODOS los bots en un paso de física (p95 y
##              máximo). Es lo que suman a "Scripts" en la TV; presupuesto:
##              0,5 ms por juego (docs/PERFORMANCE.md). Medido en esta PC:
##              en la TV de gama baja, multiplicar por ~3.
## Y al final, en qué puesto terminó cada lugar (o cada dificultad) en la tabla.

const MAX_GAME_SEC := 180.0
const DIFF_BY_NAME := {"easy": Bot.Difficulty.EASY, "normal": Bot.Difficulty.NORMAL, "hard": Bot.Difficulty.HARD}
const MIXED: Array[int] = [Bot.Difficulty.EASY, Bot.Difficulty.NORMAL, Bot.Difficulty.HARD, Bot.Difficulty.NORMAL]

var _n := 20
var _players := 4
var _difficulty := "normal"
var _games: Array[String] = []
var _seed := 0
var _json_path := ""


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--n="):
			_n = maxi(1, int(arg.trim_prefix("--n=")))
		elif arg.begins_with("--players="):
			_players = clampi(int(arg.trim_prefix("--players=")), 1, Protocol.MAX_PLAYERS)
		elif arg.begins_with("--difficulty="):
			_difficulty = arg.trim_prefix("--difficulty=")
		elif arg.begins_with("--games="):
			for id in arg.trim_prefix("--games=").split(",", false):
				_games.append(id.strip_edges())
		elif arg.begins_with("--seed="):
			_seed = int(arg.trim_prefix("--seed="))
		elif arg.begins_with("--json="):
			_json_path = arg.trim_prefix("--json=")
	if _difficulty != "mixed" and not DIFF_BY_NAME.has(_difficulty):
		printerr("--difficulty tiene que ser easy, normal, hard o mixed")
		quit(1)
		return
	if _games.is_empty():
		for info in MiniGameRegistry.all_info():
			_games.append(str(info.id))
	var players := _make_players()
	var playable: Array[String] = []
	for id in _games:
		var info := MiniGameRegistry.info(id)
		if not info.is_empty() and MiniGameRegistry.can_play(info, players.size()):
			playable.append(id)
	print("\n=== Party Games · simulación: %d competencias, %d bots (%s), %d juegos ===\n" % [
		_n, players.size(), _difficulty, playable.size()])
	if playable.is_empty():
		printerr("Ningún juego admite %d jugadores." % players.size())
		quit(1)
		return

	var stats := {}  # game_id -> {durations, unfinished, scores, wins_by_slot, points_by_slot, rounds}
	for id in playable:
		stats[id] = {"durations": [], "unfinished": 0, "scores": [], "wins": _zeros(players.size()),
			"points": _zeros(players.size()), "rounds": 0, "invalid": 0, "bot_ms": PackedFloat32Array()}
	var final_places := {}  # slot -> [veces 1°, 2°, 3°, 4°]
	for p in players:
		final_places[p.slot] = _zeros(Protocol.MAX_PLAYERS)
	var started := Time.get_ticks_msec()
	for c in _n:
		var t := Tournament.new(playable, players)
		while true:
			var id := t.advance(players.size())
			if id.is_empty():
				break
			var match_seed := 0 if _seed == 0 else _seed * 1000 + c * 37 + playable.find(id)
			var r := BotMatch.run(root, id, players, MAX_GAME_SEC, match_seed)
			var st: Dictionary = stats[id]
			st.rounds += 1
			st.durations.append(float(r.seconds))
			st.invalid += int(r.invalid_outputs)
			st.bot_ms.append_array(r.bot_ms)
			if not r.finished:
				st.unfinished += 1
			var result: Dictionary = r.result
			for p in players:
				st.scores.append(float((result.get("scores", {}) as Dictionary).get(p.id, 0.0)))
			var summary := t.record(result, players)
			var firsts := 0
			for row: Dictionary in summary.rows:
				if row.place == 1:
					firsts += 1
			for row: Dictionary in summary.rows:
				st.points[row.slot] += float(row.points)
				if row.place == 1:
					st.wins[row.slot] += 1.0 / firsts  # Empates: se reparte la victoria.
		for s in t.standings():
			final_places[s.slot][int(s.place) - 1] += 1
	var wall := (Time.get_ticks_msec() - started) / 1000.0
	_print(stats, final_places, players, wall)
	if not _json_path.is_empty():
		_save_json(stats, final_places, players, wall)
	quit(0)


func _make_players() -> Array[Dictionary]:
	var out := BotMatch.bot_players(_players)
	for p in out:
		p.difficulty = MIXED[p.slot] if _difficulty == "mixed" else DIFF_BY_NAME[_difficulty]
	return out


func _print(stats: Dictionary, final_places: Dictionary, players: Array[Dictionary], wall: float) -> void:
	var tags: Array[String] = []
	for p in players:
		tags.append(UiTheme.player_tag(p.slot) + ("" if _difficulty != "mixed" else " " + Bot.difficulty_name(p.difficulty)))
	print("| Juego | Rondas | Duración media (s) | p50 | p95 | Máx | Sin terminar | Puntaje medio | Mín | Máx | Ventaja (%% victorias) %s | Puntos medios por lugar | Bots p95 / máx (ms) |" % " / ".join(tags))
	print("|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---|---|---|")
	for id: String in stats:
		var st: Dictionary = stats[id]
		if st.rounds == 0:
			continue
		var d: Array = st.durations
		var sc: Array = st.scores
		var wins: Array[String] = []
		var pts: Array[String] = []
		for i in players.size():
			wins.append("%.0f" % (100.0 * st.wins[i] / st.rounds))
			pts.append("%.0f" % (st.points[i] / st.rounds))
		var label := str(MiniGameRegistry.info(id).get("score_label", "puntos"))
		var ms := Array(st.bot_ms)
		print("| %s | %d | %.1f | %.1f | %.1f | %.1f | %d | %.1f %s | %.1f | %.1f | %s | %s | %.3f / %.2f |" % [
			id, st.rounds, _mean(d), _pct(d, 0.5), _pct(d, 0.95), _pct(d, 1.0), st.unfinished,
			_mean(sc), label, _pct(sc, 0.0), _pct(sc, 1.0), " / ".join(wins), " / ".join(pts),
			_pct(ms, 0.95), _pct(ms, 1.0)])
		if st.invalid > 0:
			printerr("  ¡%s: %d entradas de bot fuera de rango!" % [id, st.invalid])
	print("\nPuesto final en la competencia (veces 1° / 2° / 3° / 4°):")
	for i in players.size():
		var row: Array = final_places[players[i].slot]
		print("  %-14s %s" % [tags[i], " / ".join(row.slice(0, players.size()).map(func(v: float) -> String: return "%d" % v))])
	print("\n(%.1f s de simulación)\n" % wall)


func _save_json(stats: Dictionary, final_places: Dictionary, players: Array[Dictionary], wall: float) -> void:
	var games := {}
	for id: String in stats:
		var st: Dictionary = stats[id]
		if st.rounds == 0:
			continue
		var win_pct: Array = []
		var pts: Array = []
		for i in players.size():
			win_pct.append(snappedf(100.0 * st.wins[i] / st.rounds, 0.1))
			pts.append(snappedf(st.points[i] / st.rounds, 0.1))
		games[id] = {
			"rounds": st.rounds, "unfinished": st.unfinished, "invalid_outputs": st.invalid,
			"duration": {"mean": _mean(st.durations), "p50": _pct(st.durations, 0.5), "p95": _pct(st.durations, 0.95), "max": _pct(st.durations, 1.0)},
			"score": {"mean": _mean(st.scores), "min": _pct(st.scores, 0.0), "max": _pct(st.scores, 1.0),
				"label": MiniGameRegistry.info(id).get("score_label", "puntos")},
			"win_pct_by_slot": win_pct, "points_by_slot": pts,
			"bot_step_ms": {"p95": _pct(Array(st.bot_ms), 0.95), "max": _pct(Array(st.bot_ms), 1.0)},
		}
	var data := {
		"competitions": _n, "players": players.size(), "difficulty": _difficulty, "seed": _seed,
		"wall_seconds": wall, "games": games, "final_places_by_slot": final_places,
	}
	var f := FileAccess.open(_json_path, FileAccess.WRITE)
	if f == null:
		printerr("No se pudo escribir ", _json_path)
		return
	f.store_string(JSON.stringify(data, "  "))
	print("JSON guardado en ", _json_path)


static func _zeros(n: int) -> Array:
	var out: Array = []
	out.resize(n)
	out.fill(0.0)
	return out


static func _mean(values: Array) -> float:
	if values.is_empty():
		return 0.0
	var total := 0.0
	for v: float in values:
		total += v
	return total / values.size()


## Percentil (0 = mínimo, 1 = máximo).
static func _pct(values: Array, q: float) -> float:
	if values.is_empty():
		return 0.0
	var sorted := values.duplicate()
	sorted.sort()
	return float(sorted[clampi(int(ceil(q * sorted.size())) - 1, 0, sorted.size() - 1)])
