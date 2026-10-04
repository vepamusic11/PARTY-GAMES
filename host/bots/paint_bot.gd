extends Bot
## Pintar el piso: ir a la baldosa sin pintar (o ajena) que más conviene.
##
## Cada vez que piensa recorre la grilla (20×11) y elige la baldosa con menor
## "costo": distancia, un poco menos si es de otro jugador (robar le resta a
## él), menos si queda en la dirección en la que ya va (no zigzaguear), más
## si hay otra mascota al lado (la volvería a pintar: pelearse por las mismas
## baldosas no suma) y las propias no cuentan. Si hay un power-up cerca, va
## a buscarlo.

const NEAR_CELLS := 4         ## Radio (en baldosas) de la primera búsqueda.
const CROWD_CELLS := 2.5      ## Baldosas a menos de esto de otra mascota valen menos.

var _target := Vector2i(-1, -1)
var _heading := Vector2.ZERO


func decide(view: Dictionary, delta: float) -> Dictionary:
	var positions: Dictionary = view.get("pos", {})
	if not positions.has(player_id) or not view.get("playing", false):
		return idle()
	var me := predict(positions[player_id], float(view.get("speed", 0.0)))
	var owner: PackedInt32Array = view.owner
	var cols: int = view.cols
	var reached := _target.x < 0 or owner[_target.y * cols + _target.x] == player_id
	if reached or think_due(delta):
		_target = _choose(view, me)
	if _target.x < 0:
		return idle()
	var field: Rect2 = view.field
	var cell: float = view.cell
	var goal := field.position + (Vector2(_target) + Vector2(0.5, 0.5)) * cell
	var axis := steer(me, aim_at(goal, me, 160.0), 20.0)
	# Nunca frena del todo al llegar: la baldosa se pinta al pisarla.
	if axis.length() < 0.35 * speed and axis != Vector2.ZERO:
		axis = axis.normalized() * 0.35 * speed
	if axis != Vector2.ZERO:
		_heading = axis.normalized()
	return {"axis": axis, "btn": 0}


func _choose(view: Dictionary, me: Vector2) -> Vector2i:
	var owner: PackedInt32Array = view.owner
	var cols: int = view.cols
	var rows: int = view.rows
	var cell: float = view.cell
	var field: Rect2 = view.field
	var empty: int = view.empty
	var here := (me - field.position) / cell - Vector2(0.5, 0.5)  # en celdas
	var power: Dictionary = view.get("powerup", {})
	if not power.is_empty():
		var pc: Vector2i = power.cell
		if here.distance_to(Vector2(pc)) < lerpf(2.0, 7.0, skill):
			return pc
	var others: Array[Vector2] = []
	var positions: Dictionary = view.pos
	for pid: int in positions:
		if pid != player_id:
			others.append(((positions[pid] as Vector2) - field.position) / cell - Vector2(0.5, 0.5))
	# Primero mira alrededor (barato); si ahí ya está todo pintado, toda la grilla.
	var best := _scan(owner, cols, rows, empty, here, others, NEAR_CELLS)
	if best.x < 0:
		best = _scan(owner, cols, rows, empty, here, others, maxi(cols, rows))
	return best


## Mejor baldosa dentro de `radius` celdas de `here` (-1, -1 si no hay).
func _scan(owner: PackedInt32Array, cols: int, rows: int, empty: int, here: Vector2, others: Array[Vector2],
		radius: int) -> Vector2i:
	var best := Vector2i(-1, -1)
	var best_cost := INF
	var steal := 0.6 * skill
	var jitter := 1.5 * (1.0 - skill)
	var cx := roundi(here.x)
	var cy := roundi(here.y)
	for y in range(maxi(0, cy - radius), mini(rows, cy + radius + 1)):
		for x in range(maxi(0, cx - radius), mini(cols, cx + radius + 1)):
			var o := owner[y * cols + x]
			if o == player_id:
				continue
			var d := Vector2(x, y) - here
			var dist := d.length()
			var cost := dist
			if o != empty:
				cost -= steal
			for q in others:
				var near := CROWD_CELLS - q.distance_to(Vector2(x, y))
				if near > 0.0:
					cost += near * 2.0 * skill
			if dist > 0.01 and _heading != Vector2.ZERO:
				cost -= 0.8 * skill * _heading.dot(d / dist)
			if jitter > 0.0:
				cost += rng.randf() * jitter
			if cost < best_cost:
				best_cost = cost
				best = Vector2i(x, y)
	return best
