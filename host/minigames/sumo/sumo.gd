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
## Poses extra que se hornean en la intro (MascotAtlas.prewarm_game): cara de
## susto caminando cerca del borde y festejo caminando al final.
const MASCOT_PREWARM := [[MASCOT_SCALE, ["walk@3", "walk@1"]]]
const FEET_OFFSET := 32.0         ## Los pies se dibujan un poco abajo del centro físico.
const NAME_OFFSET := 26.0
const NAME_SIZE := 26
const FALL_SEC := 0.6
const FALL_DRAG := 3.0

# --- Efectos (ver MiniGame.juice) -----------------------------------------------
const HIT_FX_MIN_SPEED := 150.0   ## Choques más suaves no muestran estrellitas.
const HIT_FX_COOLDOWN := 0.3     ## Entre dos efectos del mismo par (empujarse sin parar no satura).
const BIG_HIT := 0.6              ## Desde esta fuerza (0..1) el choque sacude y congela un instante.
const ANNOUNCE_SEC := 2.5
const WARN_SEC := 1.5             ## Antes de achicarse, el borde de la isla titila y suena un aviso.

# --- Tribuna --------------------------------------------------------------------
const STAND_W := 320.0
const STAND_TOP := 300.0
const STAND_H := 600.0
const STAND_SCALE := 0.8

# --- Ayuda de los eliminados (MODOS.md §11, ADR 0020) ------------------------
## Salvavidas: si el ayudado se cae en los próximos `duration` segundos,
## rebota de vuelta a la isla (una vez).
const HELP := {"name": "Salvavidas", "cost": 10, "duration": 3.0}
## Adónde vuelve el salvado (fracción del radio de la isla) y con qué
## velocidad hacia el centro (fracción de MAX_SPEED).
const HELP_RETURN_RING := 0.6
const HELP_RETURN_SPEED := 0.6

var _pos: Dictionary = {}         # player_id -> Vector2 (centro físico)
var _vel: Dictionary = {}         # player_id -> Vector2
var _axis: Dictionary = {}        # player_id -> Vector2
var _out_time: Dictionary = {}    # player_id -> segundos sobrevividos (solo los que cayeron)
var _fall_t: Dictionary = {}      # player_id -> segundos desde que se cayó
var _kos: Dictionary = {}         # player_id -> rivales que tiró
var _last_hit: Dictionary = {}    # player_id -> {by: id, t: segundos de juego}
var _pair_fx: Dictionary = {}     # Vector2i(a, b) -> segundos de juego del último efecto
var _radius := RADIUS_START
var _countdown := COUNTDOWN_SEC
var _elapsed := 0.0
var _anim := 0.0
var _ending := false
var _end_timer := 0.0
var _result: Dictionary = {}
var _rng := RandomNumberGenerator.new()


static func get_info() -> Dictionary:
	return {
		"id": "sumo",
		"title": "Empujones",
		"description": "Mové tu mascota y embestí a los demás para tirarlos de la isla. La isla se achica: el último en pie gana.",
		"min_players": 2,
		"max_players": 4,
		"layout": Protocol.LAYOUT_JOYSTICK,
		"layout_data": {"hint": "Embestí para tirarlos de la isla"},
		"accent": UiTheme.BRICKS[3],   # Verde: cada juego tiene su color (ver test_registry_optional_defaults).
		"score_label": "puntos",
		"help": HELP,
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


## Para los bots (ver MiniGame.bot_view): mascotas (posición y velocidad),
## quiénes cayeron y el tamaño de la isla. Solo lectura.
func bot_view() -> Dictionary:
	return {
		"pos": _pos, "vel": _vel, "out": _out_time, "center": CENTER, "radius": _radius,
		"countdown": _countdown, "body_radius": BODY_RADIUS, "max_speed": MAX_SPEED,
	}


func _physics_process(delta: float) -> void:
	if is_finished() or hit_stopped(delta):
		return
	step(delta)
	queue_redraw()


## Un paso de juego. Separado de _physics_process para que los tests lo
## puedan avanzar a mano.
func step(delta: float) -> void:
	_anim += delta
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
	help_tick(delta)
	_warn_beeps(_elapsed, minf(_elapsed + delta, DURATION_SEC))
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
				_hit_fx(((r.pa as Vector2) + (r.pb as Vector2)) / 2.0, (r.pb as Vector2) - (r.pa as Vector2), power)


func _check_falls() -> void:
	for pid in _alive_ids():
		if not is_off_platform(_pos[pid], CENTER, _radius):
			continue
		if _lifebuoy_saves(pid):
			continue
		_out_time[pid] = snappedf(_elapsed, 0.1)
		_fall_t[pid] = 0.0
		_axis[pid] = Vector2.ZERO
		var by := credited_pusher(_last_hit.get(pid, {}), _elapsed)
		if by != -1 and by != pid and _kos.has(by):
			_kos[by] += 1
			if is_inside_tree():
				juice().float_text("+%d" % int(KO_BONUS), (_pos[by] as Vector2) + Vector2(0, -140),
					player_by_id(by).get("color", UiTheme.GOLD))


func _update_falls(delta: float) -> void:
	for pid: int in _fall_t.keys():
		var t: float = _fall_t[pid]
		if t >= FALL_SEC:
			continue
		_vel[pid] = (_vel[pid] as Vector2) * exp(-FALL_DRAG * delta)
		_pos[pid] += (_vel[pid] as Vector2) * delta
		_fall_t[pid] = t + delta
		if t + delta >= FALL_SEC and is_inside_tree():
			# Chapuzón: gotas, onda y una sacudida leve.
			juice().splash(_pos[pid])
			juice().shake(0.7)
			play_sfx("splash")


## Choque: estrellitas y chispas en el punto de contacto; los fuertes además
## sacuden la pantalla y la congelan un instante (hit-stop).
func _hit_fx(at: Vector2, dir: Vector2, power: float) -> void:
	if not is_inside_tree():
		return
	juice().sparkles(at, UiTheme.GOLD, roundi(3 + 5 * power), 200.0 + 220.0 * power)
	juice().sparks(at, dir.orthogonal(), UiTheme.FX_SPARK, 2)
	juice().sparks(at, -dir.orthogonal(), UiTheme.FX_SPARK, 2)
	if power >= BIG_HIT:
		juice().shake(power * 0.8)
		hit_stop(0.06)


## Anticipación: WARN_SEC antes de que la isla empiece a achicarse suena un
## aviso por cada titileo del borde (ver _draw).
func _warn_beeps(before: float, after: float) -> void:
	var b := SHRINK_START_SEC - before
	var a := SHRINK_START_SEC - after
	if b > 0.0 and b <= WARN_SEC + 0.001 and ceili(a * 2.0) < ceili(b * 2.0):
		play_sfx("warn", 1.0 if a > 0.0 else 0.7)


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
	var party := {}
	for pid in alive:
		_vel[pid] = Vector2.ZERO
		_axis[pid] = Vector2.ZERO
		party[pid] = (_pos[pid] as Vector2) + Vector2(0, FEET_OFFSET)
	_ending = true
	_end_timer = END_DELAY_SEC
	if is_inside_tree():
		celebrate("¡Tiempo!" if _elapsed >= DURATION_SEC else ("¡Último en pie!" if not alive.is_empty() else "¡Fin!"), party)


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
	# La sacudida ahora es de cámara (MiniGame.juice().shake): mueve el juego
	# entero sin redibujar las capas. `shake` queda en cero.
	var shake := Vector2.ZERO
	# Agua, los que caen por el lado de atrás e isla: capas propias (ver
	# "Capas" más abajo), que quedan detrás de todo lo que se dibuja acá.
	_update_layers(shake)
	draw_static(_draw_stand_panels)  # Paneles y bancos de las tribunas: fijos.
	# Mientras se achica, el borde titila en rojo. Anticipación: WARN_SEC antes
	# ya titila (más fuerte y a saltos, con un aviso sonoro en cada uno).
	var warn := SHRINK_START_SEC - _elapsed
	if warn > 0.0 and warn <= WARN_SEC and _countdown <= 0.0 and not _ending:
		if fmod(warn, 0.5) > 0.2:
			draw_arc(CENTER + shake, _radius - 12.0, 0, TAU, 96, Color(UiTheme.DANGER, 0.9), 18.0, true)
	elif _elapsed >= SHRINK_START_SEC and _radius > RADIUS_END and not _ending:
		var blink := 0.35 + 0.35 * sin(_anim * 8.0)
		draw_arc(CENTER + shake, _radius - 10.0, 0, TAU, 96, Color(UiTheme.DANGER, blink), 8.0, true)
	var order := players.filter(func(p: Dictionary) -> bool:
		return not _out_time.has(p.id) or (_is_falling(p.id) and (_pos[p.id] as Vector2).y >= CENTER.y))
	order.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return (_pos[a.id] as Vector2).y < (_pos[b.id] as Vector2).y)
	for p in order:
		if not _out_time.has(p.id):
			_draw_base_ring(p, shake)
	for p in order:
		if _out_time.has(p.id):
			_draw_falling(self, p, shake)
		else:
			_draw_player(p, shake)
	# Globitos 1P–4P y nombres de los que siguen en la isla, todos juntos.
	var tags: Array = []
	for p in order:
		if not _out_time.has(p.id):
			tags.append([p, (_pos[p.id] as Vector2) + shake + Vector2(0, FEET_OFFSET), MASCOT_SCALE, NAME_OFFSET])
	draw_player_tags(tags)
	draw_start_markers(tags)
	for p in order:
		if not _out_time.has(p.id):
			_draw_kos(self, p, (_pos[p.id] as Vector2) + shake + Vector2(0, FEET_OFFSET + NAME_OFFSET), p.name)
	_draw_help_fx()
	_draw_stands()
	draw_hud(_live_scores(), clock_text(DURATION_SEC - _elapsed))
	draw_countdown(_countdown, GO_SEC)
	var since_shrink := _elapsed - SHRINK_START_SEC
	if since_shrink >= 0.0 and since_shrink < ANNOUNCE_SEC and not _ending:
		draw_text_centered("¡La isla se achica!", Vector2(CENTER.x, 140), 52, UiTheme.ACCENT, 12)


func _is_falling(pid: int) -> bool:
	return _fall_t.has(pid) and float(_fall_t[pid]) < FALL_SEC


# --- Capas ----------------------------------------------------------------------
#
# Rendimiento: el agua y la isla son cientos de figuras (≈ 120 olas y ≈ 50
# bloques con sus costuras). Redibujarlas en cada frame costaba más que todo
# el resto del juego. Van en nodos hijos (show_behind_parent: detrás de lo
# que dibuja _draw, en este orden) que se redibujan solo cuando cambia lo
# que muestran:
#   _water   degradé del agua                     nunca
#   _waves   olas (un solo lote)                  nunca: se mueven con position.x
#   _back    los que caen por el lado de atrás    solo mientras alguien cae
#   _island  espuma, costado y tapa               cada frame (la espuma late)
#   _rings   anillos completos y centro           al perder un anillo o temblar
#   _edge    anillo recortado y borde             al achicarse o temblar
# Lo que se redibuja poco va en lotes (UiTheme.ShapeBatch: menos draw calls);
# lo que cambia en cada frame usa las funciones del motor (menos CPU).
# Mismo orden de dibujo que antes, así que se ve igual.

var _water: Node2D
var _waves: Node2D
var _back: Node2D
var _island: Node2D
var _rings: Node2D
var _edge: Node2D
var _layer_keys: Dictionary = {}  # capa -> lo que mostraba la última vez
var _shake_now := Vector2.ZERO


func _make_layer(draw_fn: Callable) -> Node2D:
	var layer := Node2D.new()
	layer.show_behind_parent = true
	layer.draw.connect(draw_fn)
	add_child(layer, false, Node.INTERNAL_MODE_FRONT)
	return layer


## Pide redibujar `layer` solo si cambió `key`.
func _refresh(layer: Node2D, key: Array) -> void:
	if _layer_keys.get(layer, []) != key:
		_layer_keys[layer] = key
		layer.queue_redraw()


func _update_layers(shake: Vector2) -> void:
	if _water == null:
		_water = _make_layer(_draw_water_layer)
		_waves = _make_layer(_draw_waves_layer)
		_back = _make_layer(_draw_back_layer)
		_island = _make_layer(_draw_island_layer)
		_rings = _make_layer(_draw_rings_layer)
		_edge = _make_layer(_draw_edge_layer)
	_shake_now = shake
	# Las olas se desplazan con la capa entera (el patrón se repite cada 180 px).
	_waves.position.x = fmod(_anim * 24.0, 180.0)
	var back_key: Array = [shake]
	for p in players:
		if _is_falling(p.id) and (_pos[p.id] as Vector2).y < CENTER.y:
			back_key.append_array([p.id, _pos[p.id], _fall_t[p.id]])
	_refresh(_back, back_key)
	_refresh(_island, [_radius, _anim, shake])
	_refresh(_rings, [_complete_rings(), minf(_radius, RING_EDGES[0]), shake])
	_refresh(_edge, [_radius, shake])


## Cuántos anillos de bloques entran enteros en la isla.
func _complete_rings() -> int:
	var k := 0
	while k < RING_EDGES.size() - 1 and RING_EDGES[k + 1] <= _radius:
		k += 1
	return k


## Agua: degradé de dos bloques de la paleta.
func _draw_water_layer() -> void:
	var top: Color = UiTheme.BRICKS[4]
	var bottom: Color = UiTheme.BRICKS[5]
	_water.draw_polygon(PackedVector2Array([Vector2.ZERO, Vector2(SCREEN.x, 0), SCREEN, Vector2(0, SCREEN.y)]),
		PackedColorArray([top, top, bottom, bottom]))


## Olitas en un solo lote (cada draw_arc con antialiasing son 3 draw calls).
## Se dibujan sin desplazamiento; la capa se mueve con position.x.
func _draw_waves_layer() -> void:
	var batch := UiTheme.ShapeBatch.new()
	var wave := Color(UiTheme.PAPER, 0.28)
	var row := 0
	var y := 130.0
	while y < SCREEN.y:
		var x := -180.0 + (90.0 if row % 2 == 1 else 0.0)
		while x < SCREEN.x + 60.0:
			batch.arc(Vector2(x, y), 24.0, PI * 1.15, PI * 1.85, 10, wave, 5.0)
			x += 180.0
		y += 96.0
		row += 1
	batch.flush(_waves)


## Los que caen por el lado de atrás quedan detrás de la isla.
func _draw_back_layer() -> void:
	for p in players:
		if _is_falling(p.id) and (_pos[p.id] as Vector2).y < CENTER.y:
			_draw_falling(_back, p, _shake_now)


## Isla vista desde arriba: espuma alrededor, costado oscuro (relieve) y tapa.
func _draw_island_layer() -> void:
	var c := CENTER + _shake_now
	var r := _radius
	var side := c + Vector2(0, ISLAND_DEPTH)
	var foam := 16.0 + sin(_anim * 3.0) * 4.0
	var batch := UiTheme.ShapeBatch.new()
	batch.circle(side, r + foam, Color(UiTheme.PAPER, 0.45))
	batch.circle(side, r + 6.0, UiTheme.INK)
	batch.circle(side, r, UiTheme.INK_SOFT)
	batch.circle(c, r + 6.0, UiTheme.INK)
	batch.flush(_island)


## Círculo blanco del centro, anillos de bloques completos y círculo de sumo.
func _draw_rings_layer() -> void:
	var c := CENTER + _shake_now
	var batch := UiTheme.ShapeBatch.new()
	batch.circle(c, minf(_radius, RING_EDGES[0]), UiTheme.PAPER)
	for ring in _complete_rings():
		_add_ring(_rings, batch, c, ring, RING_EDGES[ring + 1], false)
	# Círculo de sumo del centro (no toca ningún anillo: puede ir antes del recortado).
	batch.arc(c, 58.0, 0, TAU, 48, Color(UiTheme.INK, 0.25), 5.0)
	batch.flush(_rings)


## Anillo recortado por el borde (si hay) y el borde de la isla. Mientras la
## isla se achica se redibuja en cada frame: los arcos van con draw_arc del
## motor (en C++), que acá conviene más que armarlos en el lote en GDScript.
func _draw_edge_layer() -> void:
	var c := CENTER + _shake_now
	var batch := UiTheme.ShapeBatch.new()
	var ring := _complete_rings()
	if ring < RING_EDGES.size() - 1 and _radius > RING_EDGES[ring]:
		_add_ring(_edge, batch, c, ring, _radius, true)
	_edge.draw_arc(c, _radius, 0, TAU, 96, UiTheme.INK, 6.0, true)


## Un anillo de bloques entre RING_EDGES[ring] y r_out, con el mismo
## resultado que dibujando bloque, costura, bloque, costura… y al final la
## línea del borde interior. Los bloques van en lote y las costuras (líneas,
## que el motor ya agrupa en un draw call) aparte. Ningún bloque toca la
## costura de otro salvo el último con la primera: alcanza con repetir ese
## bloque después de la primera costura (es opaco, queda igual).
## `engine_arc`: la línea del borde interior con draw_arc (más rápido de
## armar) en vez de sumarla al lote (un draw call menos).
func _add_ring(ci: CanvasItem, batch: UiTheme.ShapeBatch, c: Vector2, ring: int, r_out: float, engine_arc: bool) -> void:
	var r_in: float = RING_EDGES[ring]
	var seam := Color(UiTheme.INK, 0.35)
	var segs := maxi(8, int(TAU * (r_in + r_out) / 2.0 / BRICK_LEN))
	var turn := ring * 0.37
	var last := PackedVector2Array()
	var last_col := Color.WHITE
	for s in segs:
		var a0 := turn + TAU * s / segs
		var a1 := turn + TAU * (s + 1) / segs
		var col: Color = UiTheme.BRICKS[(s + ring * 3) % UiTheme.BRICKS.size()]
		last = _sector(c, r_in, r_out, a0, a1)
		last_col = col.lightened(0.4)
		_add_sector(batch, last, last_col)
	batch.flush(ci)
	for s in segs:
		var a0 := turn + TAU * s / segs
		ci.draw_line(c + Vector2.from_angle(a0) * r_in, c + Vector2.from_angle(a0) * r_out, seam, 3.0, true)
		if s == 0:
			_add_sector(batch, last, last_col)
			batch.flush(ci)
	if engine_arc:
		ci.draw_arc(c, r_in, 0, TAU, 72, seam, 3.0, true)
	else:
		batch.arc(c, r_in, 0, TAU, 72, seam, 3.0)


## Sector de anillo como tira de cuadriláteros entre el arco de afuera y el
## de adentro: cubre los mismos píxeles que el polígono de _sector().
static func _add_sector(batch: UiTheme.ShapeBatch, sector: PackedVector2Array, col: Color) -> void:
	var n := sector.size() >> 1  # puntos por arco
	var pts := PackedVector2Array()
	for i in n:
		pts.append(sector[i])                        # afuera, de a0 a a1
		pts.append(sector[sector.size() - 1 - i])    # adentro, en el mismo ángulo
	var cols := PackedColorArray()
	cols.resize(pts.size())
	cols.fill(col)
	batch.strip(pts, cols)


static func _sector(c: Vector2, r_in: float, r_out: float, a0: float, a1: float) -> PackedVector2Array:
	const STEPS := 6
	var pts := PackedVector2Array()
	for i in STEPS + 1:
		pts.append(c + Vector2.from_angle(lerpf(a0, a1, float(i) / STEPS)) * r_out)
	for i in range(STEPS, -1, -1):
		pts.append(c + Vector2.from_angle(lerpf(a0, a1, float(i) / STEPS)) * r_in)
	return pts


## Anillo en el piso con el color del jugador: marca el cuerpo para choques.
## (Se dibuja en cada frame con draw_arc del motor: armarlo en un lote con
## ShapeBatch.arc ahorra draw calls pero cuesta más CPU en GDScript.)
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
	PlayerAvatar.draw_mascot(self, feet, MASCOT_SCALE, p.color, PlayerAvatar.style_of(p), mood, 0.0, celebrate_hop(p.id), false, anim)


## Caída: la mascota gira y se achica hasta desaparecer en el agua.
func _draw_falling(ci: CanvasItem, p: Dictionary, off: Vector2) -> void:
	var k := clampf(float(_fall_t[p.id]) / FALL_SEC, 0.0, 1.0)
	var s := 1.0 - k * k
	if s <= 0.01:
		return
	var spin := k * PI * 1.5 * (1.0 if p.slot % 2 == 0 else -1.0)
	var xform := Transform2D(spin, Vector2(s, s), 0.0, _pos[p.id] + off)
	ci.draw_set_transform_matrix(xform)
	PlayerAvatar.draw_mascot(ci, Vector2(0, FEET_OFFSET), MASCOT_SCALE, p.color, PlayerAvatar.style_of(p), PlayerAvatar.Mood.SAD,
		0.0, 0.0, false, {"xform": xform})
	ci.draw_set_transform(Vector2.ZERO)


## En el panel claro de la tribuna: "1P Pablo" en tinta y una estrellita
## por cada rival tirado. (Sobre la isla van el globito 1P–4P y el nombre,
## como en los demás juegos: ver _draw.)
func _draw_name(ci: CanvasItem, p: Dictionary, center: Vector2) -> void:
	var text := "%s %s" % [UiTheme.player_tag(p.slot), p.name]
	UiTheme.draw_text(ci, text, center, NAME_SIZE, UiTheme.INK)
	_draw_kos(ci, p, center, text)


## Una estrellita por cada rival tirado, a la derecha de `text` (centrado en `center`).
func _draw_kos(ci: CanvasItem, p: Dictionary, center: Vector2, text: String) -> void:
	var kos := int(_kos.get(p.id, 0))
	if kos <= 0:
		return
	var w := UiTheme.FONT_BOLD.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, NAME_SIZE).x
	for i in kos:
		UiTheme.draw_star(ci, center + Vector2(w / 2.0 + 20.0 + i * 28.0, -1.0), 11.0, UiTheme.GOLD)


## Tribunas a los costados: los que se cayeron miran tristes desde ahí.
## Lugar fijo por slot (1P y 3P a la izquierda, 2P y 4P a la derecha).
## Los paneles y bancos son fijos (_draw_stand_panels, capa cacheada); acá
## solo los que ya están sentados.
func _draw_stands() -> void:
	for side in 2:
		for row in 2:
			var p := _player_in_seat(side + row * 2)
			if p.is_empty():
				continue
			var feet := _seat_feet(side, row)
			PlayerAvatar.draw_mascot(self, feet, STAND_SCALE, p.color, PlayerAvatar.style_of(p), PlayerAvatar.Mood.SAD)
			_draw_name(self, p, feet + Vector2(0, 58.0))


func _stand_panel(side: int) -> Rect2:
	var x := float(UiTheme.SAFE_MARGIN) if side == 0 else SCREEN.x - UiTheme.SAFE_MARGIN - STAND_W
	return Rect2(x, STAND_TOP, STAND_W, STAND_H)


func _seat_feet(side: int, row: int) -> Vector2:
	var panel := _stand_panel(side)
	return Vector2(panel.get_center().x, panel.position.y + 230.0 + row * 250.0)


## Lo fijo de las tribunas (se dibuja una vez, ver MiniGame.draw_static).
func _draw_stand_panels(ci: CanvasItem) -> void:
	for side in 2:
		var panel := _stand_panel(side)
		UiTheme.draw_round_rect(ci, panel, Color(UiTheme.PAPER, 0.85), UiTheme.RADIUS, 5.0, UiTheme.INK, true)
		UiTheme.draw_text(ci, "Tribuna", Vector2(panel.get_center().x, panel.position.y + 42.0), 30, UiTheme.INK)
		for row in 2:
			var feet := _seat_feet(side, row)
			var bench := Rect2(panel.position.x + 30.0, feet.y - 8.0, STAND_W - 60.0, 30.0)
			var bench_col: Color = UiTheme.BRICKS[(side * 2 + row * 5 + 1) % UiTheme.BRICKS.size()]
			UiTheme.draw_round_rect(ci, bench.grow(4.0), UiTheme.INK, 14.0)
			UiTheme.draw_round_rect(ci, bench, bench_col, 12.0)


## Jugador sentado en ese lugar de la tribuna (ya terminó de caer), o {}.
func _player_in_seat(seat: int) -> Dictionary:
	for p in players:
		if p.slot % 4 == seat and _fall_t.has(p.id) and float(_fall_t[p.id]) >= FALL_SEC:
			return p
	return {}


# --- Ayuda de los eliminados (MODOS.md §11, ADR 0020) ------------------------
#
# Salvavidas: el eliminado (desde la tribuna) le tira un salvavidas a otro.
# Si ese jugador se cae en los próximos HELP.duration segundos, en vez de
# caer al agua rebota de vuelta a la isla, una sola vez. Las reglas comunes
# (tope, espera, una a la vez) están en MiniGame; el cobro, en la TV.

func help_is_out(player_id: int) -> bool:
	return _out_time.has(player_id)


func help_is_running() -> bool:
	return _countdown <= 0.0 and not _ending and super.help_is_running()


## Pies de la mascota: en la isla, o en su asiento de la tribuna si ya cayó.
func help_anchor(player_id: int) -> Vector2:
	var p := player_by_id(player_id)
	if not p.is_empty() and _fall_t.has(player_id) and float(_fall_t[player_id]) >= FALL_SEC:
		var seat := int(p.slot) % 4
		return _seat_feet(seat % 2, seat / 2)
	return (_pos.get(player_id, CENTER) as Vector2) + Vector2(0, FEET_OFFSET)


func help_scale(player_id: int) -> float:
	return STAND_SCALE if _fall_t.has(player_id) else MASCOT_SCALE


func _start_help(_helper_id: int, target_id: int, _duration: float) -> bool:
	play_sfx("power")
	notify_player(target_id, "point")
	if is_inside_tree():
		juice().sparkles(help_anchor(target_id) + Vector2(0, -50), UiTheme.HELP_BUOY_RED, 8, 260.0)
	return true


## ¿El salvavidas lo salva de esta caída? Lo gasta y lo devuelve a la isla
## (HELP_RETURN_RING del radio, yendo hacia el centro).
func _lifebuoy_saves(player_id: int) -> bool:
	if help_for(player_id).is_empty():
		return false
	consume_help(player_id)
	var out := (_pos[player_id] as Vector2) - CENTER
	var dir := out / out.length() if out.length() > 0.001 else Vector2.UP
	if is_inside_tree():
		juice().splash(_pos[player_id])
		play_sfx("splash")
		play_sfx("power", 1.3)
	_pos[player_id] = CENTER + dir * _radius * HELP_RETURN_RING
	_vel[player_id] = -dir * MAX_SPEED * HELP_RETURN_SPEED
	_last_hit.erase(player_id)
	if is_inside_tree():
		juice().sparkles(help_anchor(player_id) + Vector2(0, -50), UiTheme.HELP_BUOY_RED, 12, 380.0)
	return true


## Salvavidas puesto sobre cada jugador con ayuda (titila al vencerse). Una
## línea desde _draw: dibujo aislado para no tocar el del juego.
func _draw_help_fx() -> void:
	for target: int in help_active:
		if _out_time.has(target):
			continue
		var h: Dictionary = help_active[target]
		HelpFx.draw_lifebuoy(self, help_anchor(target), help_scale(target), float(h.left) / maxf(float(h.total), 0.01), anim_time)
