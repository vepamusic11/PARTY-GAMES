extends Bot
## Empujones: no caerse y embestir a los demás hacia afuera.
##
## Prioridad 1: si está cerca del borde (o yendo rápido hacia afuera), volver
## hacia el centro. Prioridad 2: elegir a un rival (el más cercano, y con
## habilidad, el que está más cerca del borde). Si embistiéndolo desde donde
## está lo tiraría al agua, embestir; si no, rodearlo hasta quedar entre él
## y el centro. Como las mascotas
## tienen inercia, el joystick corrige la velocidad actual en vez de
## apuntar directo (así no se pasa de largo).

var _victim := -1
var _dir := Vector2.ZERO


func decide(view: Dictionary, delta: float) -> Dictionary:
	var positions: Dictionary = view.get("pos", {})
	var out: Dictionary = view.get("out", {})
	if not positions.has(player_id) or out.has(player_id) or float(view.get("countdown", 0.0)) > 0.0:
		return idle()
	if think_due(delta):
		_dir = _plan(view, positions, out)
	return {"axis": _dir * speed, "btn": 0}


func _plan(view: Dictionary, positions: Dictionary, out: Dictionary) -> Vector2:
	var center: Vector2 = view.center
	var radius: float = view.radius
	var body: float = view.body_radius
	var max_speed: float = view.max_speed
	var vels: Dictionary = view.vel
	var me: Vector2 = positions[player_id]
	var v: Vector2 = vels.get(player_id, Vector2.ZERO)
	var from_center := me - center
	var r := from_center.length()
	var outward := from_center / r if r > 1.0 else Vector2.ZERO
	# Muy cerca del borde, o yendo derecho al agua: volver al centro.
	var ahead := (me + v * lerpf(0.2, 0.5, skill) - center).length()
	var safe := radius * lerpf(0.9, 0.72, skill) - body * 0.5
	if r > safe or ahead > radius * lerpf(1.05, 0.92, skill):
		return _toward(-outward * max_speed, v)
	var victim := _pick_victim(positions, out, center, radius, me)
	if victim < 0:
		return _toward(-from_center.limit_length(max_speed), v)
	var opp: Vector2 = positions[victim]
	var opp_v: Vector2 = vels.get(victim, Vector2.ZERO)
	var push := opp - me
	var gap := push.length()
	push = push / gap if gap > 1.0 else -outward
	# Si lo embisto desde acá, ¿cuánto le falta para caerse en esa dirección?
	# Un empujón a toda velocidad lo lanza ~300 px: si el agua está más
	# cerca, embestir. Si no, rodearlo hasta quedar entre él y el centro.
	var edge := _to_edge(opp - center, push, radius)
	if edge < lerpf(140.0, 320.0, skill) or (opp - center).length() < body:
		var goal := aim_at(opp + opp_v * 0.25 * skill, me, 200.0)
		return _toward((goal - me).normalized() * max_speed, v)
	var opp_out := (opp - center).normalized()
	var behind := opp - opp_out * (body * 2.6)
	# Rodearlo sin pasar por encima: si está en el camino, abrirse de costado.
	var goal := behind
	if (behind - me).dot(push) > 0.0 and gap < body * 4.0:
		goal = me + push.orthogonal() * signf(push.orthogonal().dot(behind - opp) + 0.01) * body * 3.0 - outward * body
	return _toward((goal - me).normalized() * max_speed, v)


## Distancia desde `rel` (posición relativa al centro) hasta el borde de la
## isla yendo en la dirección `dir` (unitaria).
static func _to_edge(rel: Vector2, dir: Vector2, radius: float) -> float:
	var b := rel.dot(dir)
	var c := rel.length_squared() - radius * radius
	return -b + sqrt(maxf(b * b - c, 0.0))


## Joystick que lleva la velocidad actual hacia la deseada (inercia).
func _toward(desired: Vector2, v: Vector2) -> Vector2:
	var k := lerpf(0.3, 0.9, skill)  # Cuánto corrige la velocidad que ya trae.
	var steer_v := desired - v * k
	return steer_v.normalized() if steer_v.length() > 1.0 else Vector2.ZERO


func _pick_victim(positions: Dictionary, out: Dictionary, center: Vector2, radius: float, me: Vector2) -> int:
	var best := -1
	var best_cost := INF
	for pid: int in positions:
		if pid == player_id or out.has(pid):
			continue
		var p: Vector2 = positions[pid]
		var cost := me.distance_to(p) - skill * 300.0 * (p.distance_to(center) / maxf(radius, 1.0))
		if pid == _victim:
			cost -= 60.0  # Constancia: no cambia de víctima por poco.
		if cost < best_cost:
			best_cost = cost
			best = pid
	_victim = best
	return best
