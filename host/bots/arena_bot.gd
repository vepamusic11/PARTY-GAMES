extends Bot
## Arena de estrellas: ir a la estrella que conviene y juntarla.
##
## Elige la estrella más cercana; con más habilidad descarta las que otro
## jugador tiene más cerca (llegaría tarde) y no cambia de idea a cada rato.
## Apunta con error y corrige al acercarse (Bot.aim_at).

const TIE_PX := 40.0   ## Llegar con menos de esto de diferencia cuenta como empate.
const YIELD_COST := 900.0  ## En un empate, cuánto "cuesta" la estrella para el que cede.

var _target := Vector2.INF


func decide(view: Dictionary, delta: float) -> Dictionary:
	var positions: Dictionary = view.get("pos", {})
	var stars: Array = view.get("stars", [])
	if not positions.has(player_id) or stars.is_empty():
		return idle()
	var me := predict(positions[player_id], float(view.get("speed", 0.0)))
	# Si la estrella que perseguía ya no está (alguien la juntó), vuelve a elegir.
	var gone := not stars.has(_target)
	if gone or think_due(delta):
		_target = _choose(stars, positions, me, gone)
	return {"axis": steer(me, aim_at(_target, me), 30.0), "btn": 0}


func _choose(stars: Array, positions: Dictionary, me: Vector2, must: bool) -> Vector2:
	var best := Vector2.INF
	var best_cost := INF
	for st: Vector2 in stars:
		# Sin habilidad: a veces se tienta con cualquiera.
		var cost := _cost(st, positions, me) * (1.0 + rng.randf() * (1.0 - skill) * 0.8)
		if cost < best_cost:
			best_cost = cost
			best = st
	# Constancia: si la que perseguía sigue ahí y no es mucho peor, no cambia.
	if not must and stars.has(_target) and _cost(_target, positions, me) < best_cost * (1.0 + 0.4 * skill):
		return _target
	return best


## Qué tan mala es la estrella `st`: la distancia y, con habilidad, cuánto
## antes llega otro. En un empate cede uno solo (según _yields), así dos bots
## juntos no persiguen siempre la misma estrella.
func _cost(st: Vector2, positions: Dictionary, me: Vector2) -> float:
	var mine := me.distance_to(st)
	var cost := mine
	for pid: int in positions:
		if pid != player_id:
			var theirs := (positions[pid] as Vector2).distance_to(st)
			if theirs < mine - TIE_PX:
				cost += (mine - theirs) * skill
			elif theirs <= mine + TIE_PX and _yields(pid, st):
				cost += YIELD_COST * skill  # Llegarían juntos: la deja (con habilidad).
	return cost


## En un empate por la estrella `s`, ¿cedo yo ante `other`? Los dos bots
## calculan lo mismo (depende de la estrella, no de quién pregunta primero),
## y cambia de estrella en estrella: ningún lugar tiene prioridad fija.
func _yields(other: int, s: Vector2) -> bool:
	var k := int(s.x) * 31 + int(s.y)
	var mine := (player_id * 7919 + k) % 101
	var theirs := (other * 7919 + k) % 101
	return mine < theirs or (mine == theirs and player_id > other)
