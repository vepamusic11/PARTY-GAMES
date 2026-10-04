extends Bot
## ¡Que no te deje la cámara!: correr a la derecha sin chocar nada.
##
## Sin bot propio, el Bot base movía el joystick en círculos: el bot se
## quedaba quieto, la cámara lo dejaba a los 2 s y con 1 persona + 1 bot el
## juego duraba 5 s (lo encontró tools/simulate.gd, ver docs/PRUEBA_REAL.md).
##
## Cada tanto (más seguido cuanto más difícil) mira el tramo de adelante y
## prueba varias alturas ("carriles"): para cada una simula por dónde pasaría
## en los próximos instantes yendo a la derecha y suma peligro si cruza una
## sierra, un molinete o un pozo (según el momento, porque se mueven), si
## choca un bloque (frena, y la cámara lo alcanza) y resta si pisa una flecha
## de impulso. Elige la altura más segura, prefiriendo la que ya tiene, y
## apunta a quedar en el medio-derecha de la cámara. Como las mascotas
## tienen inercia, el joystick corrige la velocidad actual en vez de apuntar
## directo. Los fáciles miran menos lejos y dejan menos margen.

const SCROLLER := preload("res://host/minigames/scroller/scroller.gd")
const LANES := 9                 ## Alturas que prueba entre el techo y el piso.
const STEPS := 8                 ## Instantes de la trayectoria simulada.
const BLOCK_COST := 2.5          ## Chocar un bloque (frena).
const HAZARD_COST := 60.0        ## Tocar algo mortal.
const BOOST_BONUS := 0.5         ## Pisar una flecha de impulso.
const STEER_PX := 180.0          ## Error de velocidad (px/s) que ya pide el joystick a fondo.

var _goal_y := -1.0


func decide(view: Dictionary, delta: float) -> Dictionary:
	var positions: Dictionary = view.get("pos", {})
	if not positions.has(player_id) or (view.get("out", {}) as Dictionary).has(player_id) \
			or float(view.get("countdown", 0.0)) > 0.0:
		return idle()
	var me: Vector2 = positions[player_id]
	var v: Vector2 = (view.get("vel", {}) as Dictionary).get(player_id, Vector2.ZERO)
	if _goal_y < 0.0 or think_due(delta):
		_goal_y = _choose_lane(view, me)
	var cam := float(view.get("cam", 0.0))
	var cam_speed := float(view.get("cam_speed", 0.0))
	var max_speed := float(view.get("max_speed", 470.0))
	var view_w := float(view.get("view_w", 1712.0))
	# Quedarse en el medio de la cámara (un poco más adelante con habilidad):
	# ni cerca del borde que te deja ni pegado al derecho, donde los
	# obstáculos aparecen sin tiempo para reaccionar.
	var ahead := me.x - cam
	var want := view_w * lerpf(0.42, 0.58, skill)
	var desired := Vector2(cam_speed + clampf((want - ahead) * 1.2, -150.0, 320.0),
		clampf((_goal_y - me.y) * 4.0, -max_speed, max_speed))
	if ahead < 320.0:
		desired.x = max_speed
	return {"axis": _toward(desired, v) * speed, "btn": 0}


## Joystick que lleva la velocidad actual hacia la deseada (inercia):
## proporcional al error, a fondo desde STEER_PX de diferencia.
func _toward(desired: Vector2, v: Vector2) -> Vector2:
	var k := lerpf(0.4, 0.9, skill)  # Cuánto tiene en cuenta la velocidad que ya trae.
	return ((desired - v * k) / STEER_PX).limit_length(1.0)


## La altura más segura del tramo de adelante.
func _choose_lane(view: Dictionary, me: Vector2) -> float:
	var top := float(view.get("top", 72.0)) + 12.0
	var bottom := float(view.get("bottom", 670.0)) - 12.0
	var objs := _objects_ahead(view, me.x)
	# Avanza más o menos con la cámara: mira lo que viene en los próximos
	# 1,6–3 s según habilidad.
	var vx := maxf(float(view.get("cam_speed", 0.0)) + 60.0, 200.0)
	var horizon := vx * lerpf(1.6, 3.0, skill)
	var margin := float(view.get("body_radius", 30.0)) * lerpf(0.9, 1.5, skill)
	var vy := float(view.get("max_speed", 470.0)) * 0.8
	var when0 := float(view.get("elapsed", 0.0))
	var best := me.y
	var best_cost := INF
	for i in LANES:
		var y := lerpf(top, bottom, float(i) / (LANES - 1))
		# Pereza: cerca de donde está y, mejor, la que ya eligió.
		var cost := absf(y - me.y) * 0.004
		if absf(y - _goal_y) < 1.0:
			cost -= 0.3
		var p := me
		var t := 0.0
		var dt := horizon / vx / STEPS
		for _k in STEPS:
			t += dt
			p.x += vx * dt
			p.y = move_toward(p.y, y, vy * dt)
			var urgency := 1.0 / (0.3 + t)
			for o: Dictionary in objs:
				cost += _object_cost(o, p, when0 + t, margin) * urgency
		if cost < best_cost:
			best_cost = cost
			best = y
	return best


## Cuánto "cuesta" estar en `p` en el segundo `when` respecto del obstáculo.
static func _object_cost(o: Dictionary, p: Vector2, when: float, margin: float) -> float:
	match str(o.kind):
		"block":
			return BLOCK_COST if (o.rect as Rect2).grow(margin * 0.6).has_point(p) else 0.0
		"boost":
			return -BOOST_BONUS if (o.rect as Rect2).has_point(p) else 0.0
		"pit":
			return HAZARD_COST if (o.rect as Rect2).grow(margin * 0.5).has_point(p) else 0.0
		"saw":
			return HAZARD_COST if p.distance_to(SCROLLER.saw_center(o, when)) < float(o.r) + margin else 0.0
		"spinner":
			var c: Vector2 = o.c
			var dir := Vector2.from_angle(SCROLLER.spinner_angle(o, when)) * float(o.len)
			var q := Geometry2D.get_closest_point_to_segment(p, c - dir, c + dir)
			return HAZARD_COST if p.distance_to(q) < SCROLLER.ARM_W / 2.0 + margin else 0.0
	return 0.0


## Obstáculos del tramo donde está y de los dos siguientes (ya armados por el juego).
static func _objects_ahead(view: Dictionary, x: float) -> Array:
	var segments: Dictionary = view.get("segments", {})
	var seg_w := float(view.get("seg_w", 1000.0))
	var i := floori(x / seg_w)
	var out: Array = []
	for j in [i, i + 1, i + 2]:
		if segments.has(j):
			out.append_array(segments[j])
	return out
