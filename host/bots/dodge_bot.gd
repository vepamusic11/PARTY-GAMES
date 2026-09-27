extends Bot
## Esquivar: mirar las sombras y salirse de donde va a caer un bloque.
##
## Cada tanto (más seguido cuanto más difícil) prueba 9 movidas: quedarse
## quieto o ir en una de 8 direcciones. Para cada una calcula dónde estaría
## cuando cae cada bloque y suma "peligro" si queda dentro de su sombra
## (más peligro cuanto menos falta para que caiga). Elige la de menor
## peligro, prefiriendo quedarse cerca del centro y no cambiar de idea por
## nada. Los bloques recién aparecidos no los "ve" hasta pasado su tiempo de
## reacción, y los fáciles dejan menos margen alrededor de la sombra.

const DIRS := 8
const HORIZON := 1.1          ## Segundos hacia adelante que mira.
const LANDED_CHECK := 0.12    ## Bloque ya apoyado: ¿lo piso en este instante?

var _move := Vector2.ZERO     # movida elegida (dirección unitaria o cero)


func decide(view: Dictionary, delta: float) -> Dictionary:
	var positions: Dictionary = view.get("pos", {})
	if not positions.has(player_id) or (view.get("out", {}) as Dictionary).has(player_id):
		return idle()
	if think_due(delta):
		_move = _choose(view, predict(positions[player_id], float(view.speed)))
	return {"axis": _move * speed, "btn": 0}


func _choose(view: Dictionary, me: Vector2) -> Vector2:
	var area: Rect2 = view.move_rect
	var spd: float = float(view.speed) * speed
	var margin: float = float(view.hit_radius) + lerpf(4.0, 26.0, skill)
	var linger: float = view.linger
	var blocks: Array = view.blocks
	var best := Vector2.ZERO
	var best_cost := INF
	for i in DIRS + 1:
		var dir := Vector2.ZERO if i == DIRS else Vector2.from_angle(TAU * i / DIRS)
		var cost := _cost(me, dir, spd, area, margin, linger, blocks)
		# Pereza: cambiar de plan (o moverse sin necesidad) cuesta un poco.
		if dir != _move:
			cost += 1.5
		if cost < best_cost:
			best_cost = cost
			best = dir
	return best


func _cost(me: Vector2, dir: Vector2, spd: float, area: Rect2, margin: float, linger: float, blocks: Array) -> float:
	var cost := 0.0
	for b: Dictionary in blocks:
		var t: float = b.t
		var fall: float = b.fall
		if t >= fall + linger or t < reaction:
			continue  # Ya no lastima, o todavía no lo "vio".
		var ttl := fall - t
		var when := clampf(ttl, LANDED_CHECK, HORIZON)
		var p := _clamp(me + dir * spd * when, area)
		var half: float = float(b.size) / 2.0 + margin
		var g: Vector2 = b.ground
		var dx := absf(p.x - g.x) - half
		var dy := absf(p.y - g.y) - half
		var urgency := 1.0 / (0.15 + maxf(ttl, 0.0))
		if dx < 0.0 and dy < 0.0:
			cost += 100.0 * urgency
		else:
			var gap := maxf(dx, dy)
			if gap < 60.0:
				cost += (60.0 - gap) * 0.15 * urgency
	# Mejor lejos de las paredes (hay más lugar para escapar).
	var p1 := _clamp(me + dir * spd * 0.4, area)
	cost += p1.distance_to(area.get_center()) * 0.01 * skill
	return cost


static func _clamp(p: Vector2, r: Rect2) -> Vector2:
	return Vector2(clampf(p.x, r.position.x, r.end.x), clampf(p.y, r.position.y, r.end.y))
