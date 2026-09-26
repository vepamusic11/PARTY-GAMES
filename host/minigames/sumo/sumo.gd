extends MiniGame
## Empujones: todos arriba de una isla redonda de bloques y hay que tirar a
## los demás al agua. Cada mascota tiene inercia (el joystick acelera, el
## piso frena) y los choques rebotan: embestir con velocidad empuja mucho
## más que quedarse quieto.
##
## A partir de los 15 s la isla se achica de a poco. Termina cuando queda
## uno en pie o a los 60 s; los que siguen arriba ganan.
##
## Puntaje: segundos sobrevividos (con un decimal) + 5 por cada rival que
## tiraste. Cuenta como tuyo si fuiste el último en tocarlo en los 1,5 s
## previos a su caída.
##
## La física vive en funciones estáticas puras (`resolve_collision`,
## `step_velocity`, `platform_radius`…) para poder testearla sin escena.

const DURATION_SEC := 60.0
const COUNTDOWN_SEC := 3.0
const GO_SEC := 0.8               ## Cuánto se ve "¡YA!" después del 1.
const END_DELAY_SEC := 1.2        ## Pausa final: se ve la última caída y el festejo.

# --- Isla ---------------------------------------------------------------------
const CENTER := Vector2(960, 572)
const RADIUS_START := 390.0
const RADIUS_END := 170.0
const SHRINK_START_SEC := 15.0
const SHRINK_END_SEC := DURATION_SEC
const ISLAND_DEPTH := 26.0        ## Alto del costado de la isla (relieve).
## Anillos de bloques: radios fijos en el mundo. Al achicarse la isla, el
## anillo de afuera queda recortado, como si se desmoronara.
const RING_EDGES: Array[float] = [90.0, 165.0, 240.0, 315.0, 400.0]
const BRICK_LEN := 118.0          ## Largo aproximado de cada bloque del anillo.

# --- Jugadores ------------------------------------------------------------------
const ACCEL := 1500.0             ## px/s² con el joystick a fondo.
const FRICTION := 2.4             ## Frenado del piso (proporcional a la velocidad).
const MAX_SPEED := 540.0          ## Tope con el joystick (los empujones lo superan).
const BODY_RADIUS := 40.0         ## Radio del cuerpo para choques.
const RAM_BONUS := 0.55           ## Empujón extra: fracción de la velocidad con la que embestís.
const KO_WINDOW_SEC := 1.5        ## Ventana para que la caída cuente como tuya.
const KO_BONUS := 5.0
const START_RING := 0.55          ## Posición inicial: fracción del radio de la isla.
const MASCOT_SCALE := 0.85
const FEET_OFFSET := 32.0         ## Los pies se dibujan un poco abajo del centro físico.
const NAME_OFFSET := 26.0
const NAME_SIZE := 26
const FALL_SEC := 0.6
const FALL_DRAG := 3.0

# --- Efectos --------------------------------------------------------------------
const HIT_FX_MIN_SPEED := 150.0   ## Choques más suaves no muestran estrellitas.
const HIT_FX_SEC := 0.4
const HIT_FX_COOLDOWN := 0.3     ## Entre dos efectos del mismo par (empujarse sin parar no satura).
const SPLASH_SEC := 0.55
const POPUP_SEC := 1.0
const SHAKE_SEC := 0.22
const SHAKE_MAX := 9.0
const ANNOUNCE_SEC := 2.5

# --- Tribuna --------------------------------------------------------------------
const STAND_W := 320.0
const STAND_TOP := 300.0
const STAND_H := 600.0
const STAND_SCALE := 0.8

var _pos: Dictionary = {}         # player_id -> Vector2 (centro físico)
var _vel: Dictionary = {}         # player_id -> Vector2
var _axis: Dictionary = {}        # player_id -> Vector2
var _out_time: Dictionary = {}    # player_id -> segundos sobrevividos (solo los que cayeron)
var _fall_t: Dictionary = {}      # player_id -> segundos desde que se cayó
var _kos: Dictionary = {}         # player_id -> rivales que tiró
var _last_hit: Dictionary = {}    # player_id -> {by: id, t: segundos de juego}
var _effects: Array = []          # {kind: "hit"|"splash", pos, t, power}
var _pair_fx: Dictionary = {}     # Vector2i(a, b) -> segundos de juego del último efecto
var _popups: Array = []           # {text, pos, t}
var _radius := RADIUS_START
var _countdown := COUNTDOWN_SEC
var _elapsed := 0.0
var _anim := 0.0
var _shake_t := 0.0
var _shake_power := 0.0
var _ending := false
var _end_timer := 0.0
var _result: Dictionary = {}
var _rng := RandomNumberGenerator.new()


static func get_info() -> Dictionary:
	return {
		"id": "sumo",
		"title": "Empujones",
		"description": "Embestí a los demás para tirarlos de la isla. La isla se achica: el último en pie gana.",
		"min_players": 2,
		"max_players": 4,
		"layout": Protocol.LAYOUT_JOYSTICK,
		"layout_data": {},
		"accent": UiTheme.BRICKS[3],   # Verde: cada juego tiene su color (ver test_registry_optional_defaults).
		"score_label": "puntos",
	}


func setup(p_players: Array[Dictionary]) -> void:
	super.setup(p_players)
	_rng.randomize()
	var n := players.size()
	# Lugares repartidos en círculo; qué lugar le toca a cada uno rota al azar.
	var start_angle: float = {2: PI, 3: -PI / 2.0}.get(n, PI / 4.0)
	var shift := _rng.randi() % maxi(n, 1)
	for i in n:
		var p: Dictionary = players[i]
		var a := start_angle + TAU * float((i + shift) % n) / n
		_pos[p.id] = CENTER + Vector2.from_angle(a) * RADIUS_START * START_RING
		_vel[p.id] = Vector2.ZERO
		_axis[p.id] = Vector2.ZERO
		_kos[p.id] = 0


func on_input(player_id: int, input: Dictionary) -> void:
	if not _axis.has(player_id) or _out_time.has(player_id):
		return
	var axis: Variant = input.get("axis", Vector2.ZERO)
	_axis[player_id] = (axis as Vector2).limit_length(1.0) if axis is Vector2 else Vector2.ZERO


func _physics_process(delta: float) -> void:
	if is_finished():
		return
	step(delta)
	queue_redraw()


## Un paso de juego. Separado de _physics_process para que los tests lo
## puedan avanzar a mano.
func step(delta: float) -> void:
	_anim += delta
	_shake_t = maxf(_shake_t - delta, 0.0)
	_update_effects(delta)
	_update_falls(delta)
	if _ending:
		_end_timer -= delta
		if _end_timer <= 0.0:
			finish(_result)
		return
	if _countdown > -GO_SEC:
		_countdown -= delta
	if _countdown > 0.0:
		return  # Nadie se mueve hasta el "¡YA!".
	_elapsed = minf(_elapsed + delta, DURATION_SEC)
	_radius = platform_radius(_elapsed)
	_move_players(delta)
	_collide_players()
	_check_falls()
	_check_end()


# --- Física pura (testeable) ----------------------------------------------------

## Nueva velocidad: fricción, aceleración del joystick y tope. El joystick
## no te hace pasar MAX_SPEED, pero si un empujón te lanzó más rápido, esa
## velocidad se conserva (y se va frenando por la fricción).
static func step_velocity(v: Vector2, axis: Vector2, delta: float) -> Vector2:
	var drifted := v * exp(-FRICTION * delta)
	var out := drifted + axis.limit_length(1.0) * ACCEL * delta
	var cap := maxf(MAX_SPEED, drifted.length())
	return out.limit_length(cap)


## Choque entre dos círculos del mismo peso. Devuelve
## {pa, va, pb, vb, hit: bool, impact: float}:
##   - separa los cuerpos si se superponen;
##   - rebote elástico: intercambian la componente de velocidad sobre la
##     línea que los une;
##   - empujón extra: cada uno recibe RAM_BONUS × la velocidad con la que
##     el OTRO venía hacia él. El que embiste lanza lejos al que estaba quieto.
## impact = velocidad de acercamiento (0 si ya se estaban separando).
static func resolve_collision(pa: Vector2, va: Vector2, pb: Vector2, vb: Vector2,
		min_dist: float = BODY_RADIUS * 2.0) -> Dictionary:
	var out := {"pa": pa, "va": va, "pb": pb, "vb": vb, "hit": false, "impact": 0.0}
	var d := pb - pa
	var dist := d.length()
	if dist >= min_dist:
		return out
	var n := d / dist if dist > 0.001 else Vector2.RIGHT
	var overlap := (min_dist - dist) / 2.0
	out.pa = pa - n * overlap
	out.pb = pb + n * overlap
	out.hit = true
	var a_in := va.dot(n)        # A yendo hacia B
	var b_in := -vb.dot(n)       # B yendo hacia A
	var closing := a_in + b_in
	if closing <= 0.0:
		return out
	out.va = va - n * (closing + RAM_BONUS * maxf(b_in, 0.0))
	out.vb = vb + n * (closing + RAM_BONUS * maxf(a_in, 0.0))
	out.impact = closing
	return out


## Se cae si el centro sale de la isla.
static func is_off_platform(pos: Vector2, center: Vector2, radius: float) -> bool:
	return pos.distance_to(center) > radius


## Radio de la isla según los segundos de juego: fijo hasta SHRINK_START_SEC
## y después se achica de a poco hasta RADIUS_END.
static func platform_radius(elapsed: float) -> float:
	var k := clampf((elapsed - SHRINK_START_SEC) / (SHRINK_END_SEC - SHRINK_START_SEC), 0.0, 1.0)
	return lerpf(RADIUS_START, RADIUS_END, k)


## Quién se lleva el crédito por una caída: el último que lo tocó, si fue
## hace KO_WINDOW_SEC o menos. -1 si nadie.
static func credited_pusher(last_hit: Dictionary, now: float) -> int:
	if last_hit.is_empty() or now - float(last_hit.get("t", -INF)) > KO_WINDOW_SEC:
		return -1
	return int(last_hit.get("by", -1))


static func final_score(survived: float, knockouts: int) -> float:
	return snappedf(survived + KO_BONUS * knockouts, 0.1)


# --- Lógica del juego -------------------------------------------------------------

func _move_players(delta: float) -> void:
	for pid: int in _pos:
		if _out_time.has(pid):
			continue
		_vel[pid] = step_velocity(_vel[pid], _axis[pid], delta)
		advance_walk(pid, minf((_vel[pid] as Vector2).length() / MAX_SPEED, 1.0), delta, 3.2)
		_pos[pid] += (_vel[pid] as Vector2) * delta


func _collide_players() -> void:
	var alive := _alive_ids()
	for i in alive.size():
		for j in range(i + 1, alive.size()):
			var a: int = alive[i]
			var b: int = alive[j]
			var r := resolve_collision(_pos[a], _vel[a], _pos[b], _vel[b])
			if not r.hit:
				continue
			_pos[a] = r.pa
			_vel[a] = r.va
			_pos[b] = r.pb
			_vel[b] = r.vb
			_last_hit[a] = {"by": b, "t": _elapsed}
			_last_hit[b] = {"by": a, "t": _elapsed}
			var impact: float = r.impact
			var pair := Vector2i(a, b)
			if impact >= HIT_FX_MIN_SPEED and _elapsed - float(_pair_fx.get(pair, -INF)) >= HIT_FX_COOLDOWN:
				_pair_fx[pair] = _elapsed
				var power := clampf(impact / (MAX_SPEED * 1.5), 0.3, 1.0)
				_effects.append({"kind": "hit", "pos": ((r.pa as Vector2) + (r.pb as Vector2)) / 2.0, "t": 0.0, "power": power})
				if power >= _shake_power or _shake_t <= 0.0:
					_shake_power = power
					_shake_t = SHAKE_SEC


func _check_falls() -> void:
	for pid in _alive_ids():
		if not is_off_platform(_pos[pid], CENTER, _radius):
			continue
		_out_time[pid] = snappedf(_elapsed, 0.1)
		_fall_t[pid] = 0.0
		_axis[pid] = Vector2.ZERO
		var by := credited_pusher(_last_hit.get(pid, {}), _elapsed)
		if by != -1 and by != pid and _kos.has(by):
			_kos[by] += 1
			_popups.append({"text": "+%d" % int(KO_BONUS), "pos": _pos[by], "t": 0.0})


func _update_falls(delta: float) -> void:
	for pid: int in _fall_t.keys():
		var t: float = _fall_t[pid]
		if t >= FALL_SEC:
			continue
		_vel[pid] = (_vel[pid] as Vector2) * exp(-FALL_DRAG * delta)
		_pos[pid] += (_vel[pid] as Vector2) * delta
		_fall_t[pid] = t + delta
		if t + delta >= FALL_SEC:
			_effects.append({"kind": "splash", "pos": _pos[pid], "t": 0.0, "power": 1.0})


func _update_effects(delta: float) -> void:
	for e in _effects:
		e.t += delta
	_effects = _effects.filter(func(e: Dictionary) -> bool:
		return e.t < (HIT_FX_SEC if e.kind == "hit" else SPLASH_SEC))
	for p in _popups:
		p.t += delta
	_popups = _popups.filter(func(p: Dictionary) -> bool: return p.t < POPUP_SEC)


func _check_end() -> void:
	var alive := _alive_ids()
	if alive.is_empty() or (players.size() >= 2 and alive.size() <= 1) or _elapsed >= DURATION_SEC:
		_start_end(alive)


## Decide el resultado ya, pero lo emite después de END_DELAY_SEC para que
## se vea la última caída.
func _start_end(alive: Array[int]) -> void:
	var scores := {}
	for p in players:
		scores[p.id] = final_score(float(_out_time.get(p.id, snappedf(_elapsed, 0.1))), int(_kos.get(p.id, 0)))
	if alive.is_empty():
		_result = result_from_scores(scores, "Más puntos gana")
	else:
		_result = {"winners": alive, "scores": scores, "summary": "Último en pie gana"}
	for pid in alive:
		_vel[pid] = Vector2.ZERO
		_axis[pid] = Vector2.ZERO
	_ending = true
	_end_timer = END_DELAY_SEC


func _alive_ids() -> Array[int]:
	var out: Array[int] = []
	for p in players:
		if not _out_time.has(p.id):
			out.append(p.id)
	return out


## Puntaje en vivo para el HUD.
func _live_scores() -> Dictionary:
	var out := {}
	for p in players:
		out[p.id] = float(_out_time.get(p.id, _elapsed)) + KO_BONUS * int(_kos.get(p.id, 0))
	return out


# --- Dibujo ------------------------------------------------------------------

func _draw() -> void:
	_draw_water()
	var shake := Vector2.ZERO
	if _shake_t > 0.0:
		shake = Vector2(sin(_anim * 93.0), cos(_anim * 71.0)) * SHAKE_MAX * _shake_power * (_shake_t / SHAKE_SEC)
	# Los que caen por el lado de atrás quedan detrás de la isla.
	for p in players:
		if _is_falling(p.id) and (_pos[p.id] as Vector2).y < CENTER.y:
			_draw_falling(p, shake)
	_draw_island(shake)
	var order := players.filter(func(p: Dictionary) -> bool:
		return not _out_time.has(p.id) or (_is_falling(p.id) and (_pos[p.id] as Vector2).y >= CENTER.y))
	order.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return (_pos[a.id] as Vector2).y < (_pos[b.id] as Vector2).y)
	for p in order:
		if not _out_time.has(p.id):
			_draw_base_ring(p, shake)
	for p in order:
		if _out_time.has(p.id):
			_draw_falling(p, shake)
		else:
			_draw_player(p, shake)
	_draw_effects(shake)
	_draw_stands()
	draw_hud(_live_scores(), clock_text(DURATION_SEC - _elapsed))
	if _countdown > 0.0:
		draw_text_centered("%d" % ceili(_countdown), SCREEN / 2.0, 260, UiTheme.PAPER, 22)
	elif _countdown > -GO_SEC:
		draw_text_centered("¡YA!", SCREEN / 2.0, 260, UiTheme.ACCENT, 22)
	var since_shrink := _elapsed - SHRINK_START_SEC
	if since_shrink >= 0.0 and since_shrink < ANNOUNCE_SEC and not _ending:
		draw_text_centered("¡La isla se achica!", Vector2(CENTER.x, 140), 52, UiTheme.ACCENT, 12)


func _is_falling(pid: int) -> bool:
	return _fall_t.has(pid) and float(_fall_t[pid]) < FALL_SEC


## Agua: degradé de dos bloques de la paleta con olitas que se mueven.
func _draw_water() -> void:
	var top: Color = UiTheme.BRICKS[4]
	var bottom: Color = UiTheme.BRICKS[5]
	draw_polygon(PackedVector2Array([Vector2.ZERO, Vector2(SCREEN.x, 0), SCREEN, Vector2(0, SCREEN.y)]),
		PackedColorArray([top, top, bottom, bottom]))
	var wave := Color(UiTheme.PAPER, 0.28)
	var drift := fmod(_anim * 24.0, 180.0)
	var row := 0
	var y := 130.0
	while y < SCREEN.y:
		var x := -180.0 + drift + (90.0 if row % 2 == 1 else 0.0)
		while x < SCREEN.x + 60.0:
			draw_arc(Vector2(x, y), 24.0, PI * 1.15, PI * 1.85, 10, wave, 5.0, true)
			x += 180.0
		y += 96.0
		row += 1


## Isla vista desde arriba: costado oscuro, espuma y anillos de bloques.
func _draw_island(off: Vector2) -> void:
	var c := CENTER + off
	var r := _radius
	var side := c + Vector2(0, ISLAND_DEPTH)
	# Espuma alrededor.
	var foam := 16.0 + sin(_anim * 3.0) * 4.0
	draw_circle(side, r + foam, Color(UiTheme.PAPER, 0.45))
	# Costado (relieve).
	draw_circle(side, r + 6.0, UiTheme.INK)
	draw_circle(side, r, UiTheme.INK_SOFT)
	# Tapa.
	draw_circle(c, r + 6.0, UiTheme.INK)
	draw_circle(c, minf(r, RING_EDGES[0]), UiTheme.PAPER)
	var seam := Color(UiTheme.INK, 0.35)
	for ring in range(RING_EDGES.size() - 1):
		var r_in: float = RING_EDGES[ring]
		var r_out := minf(RING_EDGES[ring + 1], r)
		if r_out <= r_in:
			break
		var segs := maxi(8, int(TAU * (r_in + r_out) / 2.0 / BRICK_LEN))
		var turn := ring * 0.37
		for s in segs:
			var a0 := turn + TAU * s / segs
			var a1 := turn + TAU * (s + 1) / segs
			var col: Color = UiTheme.BRICKS[(s + ring * 3) % UiTheme.BRICKS.size()]
			draw_colored_polygon(_sector(c, r_in, r_out, a0, a1), col.lightened(0.4))
			draw_line(c + Vector2.from_angle(a0) * r_in, c + Vector2.from_angle(a0) * r_out, seam, 3.0, true)
		draw_arc(c, r_in, 0, TAU, 72, seam, 3.0, true)
	# Centro: círculo de sumo.
	draw_arc(c, 58.0, 0, TAU, 48, Color(UiTheme.INK, 0.25), 5.0, true)
	draw_arc(c, r, 0, TAU, 96, UiTheme.INK, 6.0, true)
	# Mientras se achica, el borde titila en rojo.
	if _elapsed >= SHRINK_START_SEC and r > RADIUS_END and not _ending:
		var blink := 0.35 + 0.35 * sin(_anim * 8.0)
		draw_arc(c, r - 10.0, 0, TAU, 96, Color(UiTheme.DANGER, blink), 8.0, true)


static func _sector(c: Vector2, r_in: float, r_out: float, a0: float, a1: float) -> PackedVector2Array:
	const STEPS := 6
	var pts := PackedVector2Array()
	for i in STEPS + 1:
		pts.append(c + Vector2.from_angle(lerpf(a0, a1, float(i) / STEPS)) * r_out)
	for i in range(STEPS, -1, -1):
		pts.append(c + Vector2.from_angle(lerpf(a0, a1, float(i) / STEPS)) * r_in)
	return pts


## Anillo en el piso con el color del jugador: marca el cuerpo para choques.
func _draw_base_ring(p: Dictionary, off: Vector2) -> void:
	var pos: Vector2 = _pos[p.id] + off
	draw_circle(pos, BODY_RADIUS, UiTheme.SHADOW)
	draw_arc(pos, BODY_RADIUS, 0, TAU, 32, UiTheme.INK, 9.0, true)
	draw_arc(pos, BODY_RADIUS, 0, TAU, 32, p.color, 5.0, true)


func _draw_player(p: Dictionary, off: Vector2) -> void:
	var feet: Vector2 = _pos[p.id] + off + Vector2(0, FEET_OFFSET)
	var mood := PlayerAvatar.Mood.HAPPY if _ending else PlayerAvatar.Mood.NORMAL
	# Cerca del borde de la isla: cara de susto.
	if not _ending and (_pos[p.id] as Vector2).distance_to(CENTER) > _radius - BODY_RADIUS * 1.2:
		mood = PlayerAvatar.Mood.SURPRISED
	var anim := mascot_anim(p.id, (_vel[p.id] as Vector2) / MAX_SPEED)
	anim["wave"] = mood == PlayerAvatar.Mood.HAPPY
	PlayerAvatar.draw_mascot(self, feet, MASCOT_SCALE, p.color, p.slot, mood, 0.0, 0.0, false, anim)
	_draw_name(self, p, feet + Vector2(0, NAME_OFFSET))


## Caída: la mascota gira y se achica hasta desaparecer en el agua.
func _draw_falling(p: Dictionary, off: Vector2) -> void:
	var k := clampf(float(_fall_t[p.id]) / FALL_SEC, 0.0, 1.0)
	var s := 1.0 - k * k
	if s <= 0.01:
		return
	var spin := k * PI * 1.5 * (1.0 if p.slot % 2 == 0 else -1.0)
	draw_set_transform(_pos[p.id] + off, spin, Vector2(s, s))
	PlayerAvatar.draw_mascot(self, Vector2(0, FEET_OFFSET), MASCOT_SCALE, p.color, p.slot, PlayerAvatar.Mood.SAD)
	draw_set_transform(Vector2.ZERO)


## "1P Pablo" y una estrellita por cada rival tirado. Sobre la isla va en
## blanco con contorno; sobre el panel claro de la tribuna, en tinta.
func _draw_name(ci: CanvasItem, p: Dictionary, center: Vector2, on_paper: bool = false) -> void:
	var text := "%s %s" % [UiTheme.player_tag(p.slot), p.name]
	if on_paper:
		UiTheme.draw_text(ci, text, center, NAME_SIZE, UiTheme.INK)
	else:
		UiTheme.draw_text(ci, text, center, NAME_SIZE, UiTheme.PAPER, 6, UiTheme.INK)
	var kos := int(_kos.get(p.id, 0))
	if kos <= 0:
		return
	var w := UiTheme.FONT_BOLD.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, NAME_SIZE).x
	for i in kos:
		UiTheme.draw_star(ci, center + Vector2(w / 2.0 + 20.0 + i * 28.0, -1.0), 11.0, UiTheme.GOLD)


func _draw_effects(off: Vector2) -> void:
	for e in _effects:
		var pos: Vector2 = e.pos + off
		if e.kind == "hit":
			var k: float = e.t / HIT_FX_SEC
			var power: float = e.power
			draw_arc(pos, lerpf(12.0, 70.0 * power + 20.0, k), 0, TAU, 32, Color(UiTheme.PAPER, 1.0 - k), lerpf(10.0, 2.0, k), true)
			for i in 5:
				var a := TAU * i / 5.0 + pos.x * 0.01
				var star_pos := pos + Vector2.from_angle(a) * lerpf(14.0, 50.0 + 50.0 * power, k)
				UiTheme.draw_star(self, star_pos, (8.0 + 8.0 * power) * (1.0 - k * 0.8), UiTheme.GOLD, k * 2.0)
		else:
			var k: float = e.t / SPLASH_SEC
			var ring := Color(UiTheme.PAPER, 1.0 - k)
			draw_arc(pos, lerpf(10.0, 80.0, k), 0, TAU, 32, ring, 8.0 * (1.0 - k) + 2.0, true)
			draw_arc(pos, lerpf(4.0, 46.0, k), 0, TAU, 24, ring, 5.0 * (1.0 - k) + 1.0, true)
			for i in 6:
				var a := -PI + PI * (i + 0.5) / 6.0
				var drop := pos + Vector2(cos(a) * 60.0 * k, sin(a) * 70.0 * k + 120.0 * k * k)
				draw_circle(drop, 7.0 * (1.0 - k) + 2.0, ring)
	for p in _popups:
		var k: float = p.t / POPUP_SEC
		UiTheme.draw_text(self, p.text, (p.pos as Vector2) + off - Vector2(0, 110.0 + 60.0 * k), 48,
			Color(UiTheme.GOLD, 1.0 - k * k), 10, Color(UiTheme.INK, 1.0 - k * k))


## Tribunas a los costados: los que se cayeron miran tristes desde ahí.
## Lugar fijo por slot (1P y 3P a la izquierda, 2P y 4P a la derecha).
func _draw_stands() -> void:
	for side in 2:
		var x := float(UiTheme.SAFE_MARGIN) if side == 0 else SCREEN.x - UiTheme.SAFE_MARGIN - STAND_W
		var panel := Rect2(x, STAND_TOP, STAND_W, STAND_H)
		UiTheme.draw_round_rect(self, panel, Color(UiTheme.PAPER, 0.85), UiTheme.RADIUS, 5.0, UiTheme.INK, true)
		draw_text_centered("Tribuna", Vector2(panel.get_center().x, panel.position.y + 42.0), 30, UiTheme.INK)
		for row in 2:
			var feet := Vector2(panel.get_center().x, panel.position.y + 230.0 + row * 250.0)
			var bench := Rect2(panel.position.x + 30.0, feet.y - 8.0, STAND_W - 60.0, 30.0)
			var bench_col: Color = UiTheme.BRICKS[(side * 2 + row * 5 + 1) % UiTheme.BRICKS.size()]
			UiTheme.draw_round_rect(self, bench.grow(4.0), UiTheme.INK, 14.0)
			UiTheme.draw_round_rect(self, bench, bench_col, 12.0)
			var p := _player_in_seat(side + row * 2)
			if p.is_empty():
				continue
			PlayerAvatar.draw_mascot(self, feet, STAND_SCALE, p.color, p.slot, PlayerAvatar.Mood.SAD)
			_draw_name(self, p, feet + Vector2(0, 58.0), true)


## Jugador sentado en ese lugar de la tribuna (ya terminó de caer), o {}.
func _player_in_seat(seat: int) -> Dictionary:
	for p in players:
		if p.slot % 4 == seat and _fall_t.has(p.id) and float(_fall_t[p.id]) >= FALL_SEC:
			return p
	return {}
