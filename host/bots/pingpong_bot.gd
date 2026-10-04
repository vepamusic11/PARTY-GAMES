extends Bot
## Ping Pong: mover la paleta (slider absoluto) a donde va a llegar la pelota.
##
## Cuando la pelota viene hacia su lado, calcula dónde cruza su línea
## (con los rebotes en los costados de la mesa) y va ahí. Cada pelota elige
## con qué parte de la paleta pegarle: los buenos le pegan con el borde para
## desviarla. Error de puntería por pelota, mayor cuanto más rápida viene:
## los fáciles a veces no llegan y los difíciles fallan en los peloteos largos.
## Cuando la pelota se aleja, vuelve (sin apuro) al centro.

const MISS_K := 1.3        ## Error por pelota = puntería × esto…
const MISS_BASE := 10.0    ## …más esto (px), escalado por la velocidad de la pelota.
const BASE_SPEED := 620.0  ## Velocidad del saque en pingpong.gd.

var _plan_x := NAN        # x donde piensa recibir la pelota que viene
var _coming := false      # ¿la pelota venía hacia él en el paso anterior?
var _hit_offset := 0.0    # dónde de la paleta le quiere pegar (px)
var _miss := 0.0          # error de esta pelota (px)
var _naive := false       # en esta pelota se olvida de los rebotes en los costados


func decide(view: Dictionary, delta: float) -> Dictionary:
	if view.is_empty() or not (view.get("paddle_x", {}) as Dictionary).has(player_id):
		return idle()
	var table: Rect2 = view.table
	var half: float = float(view.paddle_w) / 2.0
	var r: float = view.ball_radius
	var top: bool = view.top_id == player_id
	var my_y: float = table.position.y + view.margin if top else table.end.y - view.margin
	var ball: Vector2 = view.ball
	var vel: Vector2 = view.vel
	var coming: bool = not view.serving and (vel.y < 0.0 if top else vel.y > 0.0)
	if coming and not _coming:
		# Nueva pelota hacia mí: elijo con qué parte pegarle y cuánto le erro.
		_hit_offset = rng.randf_range(-0.55, 0.55) * half * skill
		# Cuanto más rápida viene, más difícil acertarle (como a una persona).
		_miss = gauss((aim_error * MISS_K + MISS_BASE) * vel.length() / BASE_SPEED)
		_naive = rng.randf() > skill + 0.25
	_coming = coming
	var target := table.get_center().x
	if coming:
		if is_nan(_plan_x) or think_due(delta):
			_plan_x = _predict_x(ball, vel, my_y, table, r)
		target = _plan_x - _hit_offset + _miss
	else:
		_plan_x = NAN
		# Mientras tanto, se acomoda más o menos al centro (los fáciles, a medias).
		target = lerpf(float(view.paddle_x[player_id]), table.get_center().x, 0.5 + 0.5 * skill)
	var t := inverse_lerp(table.position.x + half, table.end.x - half, target)
	return {"axis": Vector2(clampf(t * 2.0 - 1.0, -1.0, 1.0), 0.0), "btn": 0}


## Dónde cruza la pelota la línea y = my_y, con rebotes en los costados.
## Los menos hábiles a veces se olvidan del rebote.
func _predict_x(ball: Vector2, vel: Vector2, my_y: float, table: Rect2, r: float) -> float:
	if absf(vel.y) < 1.0:
		return ball.x
	var t := (my_y - ball.y) / vel.y
	var x := ball.x + vel.x * t
	if _naive:
		return clampf(x, table.position.x + r, table.end.x - r)
	var lo := table.position.x + r
	var width := table.size.x - 2.0 * r
	var u := fposmod(x - lo, 2.0 * width)  # Plegar: ida y vuelta entre las paredes.
	return lo + (u if u <= width else 2.0 * width - u)
