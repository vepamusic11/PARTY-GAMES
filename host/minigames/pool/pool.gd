extends MiniGame
## Pool loco: todos tiran a la vez, sin turnos. Cada mascota va arriba de su
## bola; en la mesa hay bolas doradas y seis troneras.
##
## Cómo se tira (con el joystick de siempre, sin cambiar el protocolo):
##   - estirar el joystick apunta: la flecha sale hacia donde apunta y es
##     más larga cuanto más se estira (más fuerza);
##   - soltarlo tira: cuando el eje vuelve a ~0 después de haber estado
##     estirado (ver `track_aim`). Entre tiro y tiro hay SHOT_COOLDOWN.
##
## Puntos:
##   - meter una bola dorada: GOLD_POINTS para el último que la tocó (con su
##     bola o con otra dorada que venía de su tiro), si fue hace CREDIT_SEC
##     o menos;
##   - meter la bola de otro: RIVAL_POINTS con la misma regla;
##   - si tu bola cae, reaparece en tu lugar de salida a los RESPAWN_SEC
##     (sin restar puntos). Las doradas vuelven a aparecer al azar.
## Gana quien tenga más puntos a los DURATION_SEC.
##
## La física es propia y determinista (pool_physics.gd: pasos fijos, choques
## elásticos, fricción); las reglas de tiro y de crédito son funciones
## estáticas (`track_aim`, `shot_speed`, `credited`) para testearlas.
##
## Escenario 2.5D (ADR 0019, como Pintar el piso): si hay render, la mesa
## (paño, bandas, troneras con aro, miras) y los juguetes de alrededor son
## una escena 3D horneada (receta "pool" de Board25DScene) con cámara en
## perspectiva, y el juego se dibuja encima proyectado: sombras, guía de
## tiro, flecha y anillos acostados en el paño (cada vértice por la
## homografía: la guía larga queda derecha y exacta), bolas a su altura
## sobre el paño y mascotas arriba de su bola, más chicas atrás. La física,
## las reglas y los bots siguen en las coordenadas planas de PLAY. Sin render
## (--headless) o mientras se hornea, se dibuja plano como siempre.

const Physics := preload("res://host/minigames/pool/pool_physics.gd")

enum State { COUNTDOWN, PLAYING, TIME_UP }

const DURATION_SEC := 50.0
const COUNTDOWN_SEC := 3.0
const GO_SEC := 0.8               ## Cuánto se ve "¡YA!" después del 1.
const END_WAIT_SEC := 1.5         ## Cuánto se ve "¡Tiempo!" antes de terminar.
const HINT_SEC := 8.0             ## Segundos de juego con el cartel de cómo se tira.

# --- Mesa -----------------------------------------------------------------------
## Paño (adentro del marco de bloques del tablero).
const FELT := Rect2(250, 196, 1420, 764)
const CUSHION := 36.0             ## Ancho de las bandas.
## Donde ruedan las bolas: el paño sin las bandas (FELT achicado CUSHION).
const PLAY := Rect2(286, 232, 1348, 692)
const POCKET_R := 36.0            ## Radio del agujero que se ve.
const POCKET_CAPTURE := 44.0      ## Una bola cae si su centro queda a menos de esto.
## draw_play_field con una sola baldosa: el paño la tapa entera.
const BOARD_CELL := 4096.0

# --- Bolas ----------------------------------------------------------------------
const BALL_R := 28.0
const BALL_MASS := 1.0
const GOLD_R := 21.0
const GOLD_MASS := 0.8            ## Más livianas: salen más rápido al pegarles.
const GOLD_COUNT := 7
const GOLD_RESPAWN_SEC := 1.2
const RESPAWN_SEC := 1.5
const FALL_SEC := 0.35            ## Animación de caer en la tronera.
const MAX_STEPS_PER_FRAME := 8    ## Tope de pasos fijos por frame (si la TV se traba).

# --- Tiro -----------------------------------------------------------------------
const RELEASE_ZONE := 0.15        ## Debajo de esto el joystick está "suelto".
const ARM_MIN := 0.3              ## Estirado menos que esto no tira (roces sin querer).
## Se tira con lo más estirado de este último tramo: al soltar, el celular
## puede mandar algún valor intermedio mientras la perilla vuelve al centro.
const AIM_HOLD_SEC := 0.15
const SHOT_MIN_SPEED := 380.0
const SHOT_MAX_SPEED := 1900.0
const SHOT_COOLDOWN := 0.8

# --- Puntos ---------------------------------------------------------------------
const GOLD_POINTS := 3
const RIVAL_POINTS := 2
const CREDIT_SEC := 5.0

# --- Dibujo ---------------------------------------------------------------------
const MASCOT_SCALE := 0.7
const FEET_UP := 0.72             ## Pies de la mascota: arriba de la bola (fracción del radio).
const NAME_OFFSET := 62.0         ## Nombre debajo de la bola (desde los pies).
const AIM_MIN_LEN := 70.0
const AIM_MAX_LEN := 290.0
const AIM_GUIDE := 520.0          ## Largo de la guía de puntitos (desde la bola).
const POPUP_SEC := 1.0
const HIT_FX_SEC := 0.35
const HIT_FX_MIN := 520.0         ## Choques más suaves no muestran estrellitas.
const HIT_SFX_MIN := 160.0
const HIT_SFX_GAP := 0.06
const POCKET_FX_SEC := 0.5
const SPAWN_FX_SEC := 0.35
const SURPRISE_SPEED := 950.0
const HAPPY_SEC := 1.2

var _state := State.COUNTDOWN
var _countdown := COUNTDOWN_SEC
var _time_left := DURATION_SEC
var _end_wait := END_WAIT_SEC
var _time := 0.0                  ## Segundos desde el setup (aim, crédito y efectos).
var _acc := 0.0                   ## Tiempo acumulado para los pasos fijos.

var _phys: Physics
var _ball: Dictionary = {}        # player_id -> índice de su bola
var _owner: Dictionary = {}       # índice de bola -> player_id (las doradas no están)
var _golds: Array[int] = []       # índices de las bolas doradas
var _spawn: Dictionary = {}       # player_id -> lugar de salida
var _pos: Dictionary = {}         # player_id -> centro de su bola (lo usan las herramientas)
var _axis: Dictionary = {}        # player_id -> último eje recibido
var _aim: Dictionary = {}         # player_id -> {dir, power, t} (ver track_aim)
var _cooldown: Dictionary = {}    # player_id -> segundos hasta poder tirar
var _respawn: Dictionary = {}     # player_id -> segundos para reaparecer (solo si cayó)
var _gold_wait: Dictionary = {}   # índice de dorada -> segundos para reaparecer
var _touch: Dictionary = {}       # índice de bola -> {by: player_id, t: _time}
var _score: Dictionary = {}       # player_id -> puntos
var _happy: Dictionary = {}       # player_id -> segundos de festejo
var _roll: Dictionary = {}        # índice de bola -> [fase, dirección] (bola que rueda)
var _falls: Array = []            # {i, from, to, t}
var _effects: Array = []          # {kind: "hit"|"pocket"|"spawn", pos, t, power}
var _popups: Array = []           # {text, pid, t}
var _last_hit_sfx := -1.0
var _rng := RandomNumberGenerator.new()
static var _ring_unit := PackedVector2Array()  # anillo de radio 1 (ver _add_ring)
static var _tpl: Dictionary = {}  # clave -> [puntos, colores] (ver "Formas armadas una vez")

## Vista 2.5D de la mesa (una por proceso) y si este cuadro se dibuja con ella.
static var _board_view: BoardView25D
var _v25 := false


static func get_info() -> Dictionary:
	return {
		"id": "pool",
		"title": "Pool loco",
		"description": "Estirá el joystick para apuntar y soltalo para tirar. Meté las bolas doradas (o la de otro) en las troneras. ¡Todos tiran a la vez!",
		"min_players": 2,
		"max_players": 4,
		"layout": Protocol.LAYOUT_JOYSTICK,
		"layout_data": {},
		"accent": UiTheme.BRICKS[2],
		"score_label": "puntos",
	}


## Cámara y proyección del escenario 2.5D (ADR 0019): el paño encuadrado
## como el tablero de Pintar el piso, con la mesa de la receta "pool" (bandas
## y troneras en los lugares de la física).
static func board_view() -> BoardView25D:
	if _board_view == null:
		var v := BoardView25D.make_fit(FELT, FELT.size.x / 20.0, Board25DScene.RECIPE_POOL)
		v.extras = {"cushion": CUSHION, "pocket_r": POCKET_R, "pockets": pockets()}
		_board_view = v
	return _board_view


## Durante la intro: el escenario 2.5D se lee del disco o se hornea.
static func prewarm_art(host: Node) -> void:
	Board25DBaker.request(host, board_view())


# --- Reglas puras (testeadas) ---------------------------------------------------

## Estado de puntería vacío (ver track_aim).
static func new_aim() -> Dictionary:
	return {"dir": Vector2.RIGHT, "power": 0.0, "t": -INF}


## Sigue el joystick de un jugador y detecta el tiro. `aim` se modifica:
##   dir    última dirección estirada (unitaria);
##   power  lo más estirado (0..1) del último tramo de AIM_HOLD_SEC;
##   t      cuándo se tomó ese máximo.
## Mientras está estirado devuelve Vector2.ZERO; al soltarlo (largo menor a
## RELEASE_ZONE) devuelve el tiro: dirección × estirado (0 si no llegaba a
## ARM_MIN) y deja `aim` vacío.
static func track_aim(aim: Dictionary, axis: Vector2, now: float) -> Vector2:
	var stretch := axis.length()
	if stretch >= RELEASE_ZONE:
		if stretch >= float(aim.power) or now - float(aim.t) > AIM_HOLD_SEC:
			aim.power = minf(stretch, 1.0)
			aim.t = now
		aim.dir = axis / stretch
		return Vector2.ZERO
	var shot := Vector2.ZERO
	if float(aim.power) >= ARM_MIN:
		shot = (aim.dir as Vector2) * float(aim.power)
	aim.power = 0.0
	aim.t = -INF
	return shot


## Velocidad de la bola según lo estirado (ARM_MIN..1 -> mínima..máxima).
static func shot_speed(stretch: float) -> float:
	return lerpf(SHOT_MIN_SPEED, SHOT_MAX_SPEED, clampf(inverse_lerp(ARM_MIN, 1.0, stretch), 0.0, 1.0))


## Quién se lleva los puntos de una bola que cae: el último que la tocó, si
## fue hace CREDIT_SEC o menos. -1 si nadie.
static func credited(touch: Dictionary, now: float) -> int:
	if touch.is_empty() or now - float(touch.get("t", -INF)) > CREDIT_SEC:
		return -1
	return int(touch.get("by", -1))


## Troneras: las cuatro esquinas y el medio de las bandas largas.
static func pockets() -> PackedVector2Array:
	var c := PLAY.get_center()
	return PackedVector2Array([PLAY.position, Vector2(c.x, PLAY.position.y), Vector2(PLAY.end.x, PLAY.position.y),
		Vector2(PLAY.position.x, PLAY.end.y), Vector2(c.x, PLAY.end.y), PLAY.end])


## Lugar de salida de cada jugador: 1P arriba a la izquierda, 2P abajo a la
## derecha, 3P arriba a la derecha y 4P abajo a la izquierda (como Arena).
static func start_spot(slot: int) -> Vector2:
	var c := PLAY.get_center()
	var dx := PLAY.size.x / 2.0 - 190.0
	var dy := 175.0
	var spots: Array[Vector2] = [c + Vector2(-dx, -dy), c + Vector2(dx, dy), c + Vector2(dx, -dy), c + Vector2(-dx, dy)]
	return spots[posmod(slot, spots.size())]


## Doradas al empezar: una en el centro y seis alrededor (hexágono).
static func rack_spot(k: int) -> Vector2:
	if k == 0:
		return PLAY.get_center()
	return PLAY.get_center() + Vector2.from_angle(TAU * (k - 1) / 6.0 + PI / 6.0) * (GOLD_R * 2.0 + 5.0)


# --- Ciclo del juego --------------------------------------------------------------

func setup(p_players: Array[Dictionary]) -> void:
	super.setup(p_players)
	_rng.randomize()
	_phys = Physics.new(PLAY, pockets(), POCKET_CAPTURE)
	for p in players:
		var pid: int = p.id
		var at := start_spot(int(p.get("slot", 0)))
		var i := _phys.add_ball(at, BALL_R, BALL_MASS)
		_ball[pid] = i
		_owner[i] = pid
		_spawn[pid] = at
		_pos[pid] = at
		_axis[pid] = Vector2.ZERO
		_aim[pid] = new_aim()
		_cooldown[pid] = 0.0
		_score[pid] = 0
		_happy[pid] = 0.0
		# Al empezar miran hacia el centro de la mesa.
		(_aim[pid] as Dictionary).dir = (PLAY.get_center() - at).normalized()
	for k in GOLD_COUNT:
		_golds.append(_phys.add_ball(rack_spot(k), GOLD_R, GOLD_MASS))


func on_input(player_id: int, input: Dictionary) -> void:
	if not _axis.has(player_id):
		return
	var axis: Variant = input.get("axis", Vector2.ZERO)
	var v := (axis as Vector2) if axis is Vector2 else Vector2.ZERO
	_axis[player_id] = v.limit_length(1.0) if v.is_finite() else Vector2.ZERO


func _physics_process(delta: float) -> void:
	if is_finished():
		return
	step(delta)
	queue_redraw()


## Un paso de juego. Separado de _physics_process para que los tests lo
## puedan avanzar a mano.
func step(delta: float) -> void:
	if is_finished():
		return
	_time += delta
	_update_effects(delta)
	match _state:
		State.COUNTDOWN:
			var before := _countdown
			_countdown -= delta
			tick_countdown(before, _countdown)
			_track_all(false)  # Se puede apuntar, pero no tirar.
			if _countdown <= 0.0:
				_state = State.PLAYING
		State.PLAYING:
			if _countdown > -GO_SEC:
				_countdown -= delta
			_time_left = maxf(_time_left - delta, 0.0)
			_track_all(true)
			_tick_timers(delta)
			_simulate(delta)
			if _time_left <= 0.0:
				_state = State.TIME_UP
				_end_wait = END_WAIT_SEC
				for pid: int in _aim:
					_aim[pid] = new_aim()
				play_sfx("whoosh")
		State.TIME_UP:
			_end_wait -= delta
			if _end_wait <= 0.0:
				finish(result_from_scores(_score, "Más puntos gana"))


func _track_all(can_fire: bool) -> void:
	for pid: int in _aim:
		var shot := track_aim(_aim[pid], _axis[pid], _time)
		if shot != Vector2.ZERO and can_fire:
			_shoot(pid, shot)


## Tira la bola del jugador: la velocidad nueva reemplaza a la que tenía.
## Devuelve si pudo (no puede si su bola cayó o si todavía no pasó el cooldown).
func _shoot(pid: int, shot: Vector2) -> bool:
	if _respawn.has(pid) or float(_cooldown[pid]) > 0.0:
		return false
	var stretch := shot.length()
	var i: int = _ball[pid]
	_phys.vel[i] = shot / stretch * shot_speed(stretch)
	_cooldown[pid] = SHOT_COOLDOWN
	play_sfx("pong", lerpf(0.8, 1.25, clampf(stretch, 0.0, 1.0)))
	notify_player(pid, "tap")
	return true


func _tick_timers(delta: float) -> void:
	for pid: int in _cooldown:
		_cooldown[pid] = maxf(float(_cooldown[pid]) - delta, 0.0)
		_happy[pid] = maxf(float(_happy[pid]) - delta, 0.0)
	for pid: int in _respawn.keys():
		_respawn[pid] = float(_respawn[pid]) - delta
		if float(_respawn[pid]) > 0.0:
			continue
		var i: int = _ball[pid]
		var at := _free_spot_near(_spawn[pid], BALL_R, i)
		if at == Vector2.INF:
			continue  # Ocupado: prueba en el próximo frame.
		_phys.place(i, at)
		_pos[pid] = at
		_respawn.erase(pid)
		_cooldown[pid] = 0.0
		_effects.append({"kind": "spawn", "pos": at, "t": 0.0, "power": 1.0})
		play_sfx("pop")
	for i: int in _gold_wait.keys():
		_gold_wait[i] = float(_gold_wait[i]) - delta
		if float(_gold_wait[i]) > 0.0:
			continue
		var at := _random_gold_spot()
		if at == Vector2.INF:
			continue
		_phys.place(i, at)
		_gold_wait.erase(i)
		_effects.append({"kind": "spawn", "pos": at, "t": 0.0, "power": 0.75})


## Avanza la física en pasos fijos de Physics.DT con el tiempo acumulado.
func _simulate(delta: float) -> void:
	_acc += delta
	var steps := 0
	while _acc >= Physics.DT and steps < MAX_STEPS_PER_FRAME:
		_acc -= Physics.DT
		_apply(_phys.step())
		steps += 1
	if steps == MAX_STEPS_PER_FRAME:
		_acc = 0.0  # La TV se trabó: se pierde tiempo antes que acumular atraso.
	for i in _phys.pos.size():
		var s := _phys.speed(i)
		if s > 0.0:
			var r: Array = _roll.get(i, [0.0, Vector2.RIGHT])
			_roll[i] = [float(r[0]) + s * delta / _phys.radius[i], _phys.vel[i] / s]
	for pid: int in _ball:
		var i: int = _ball[pid]
		if _phys.is_on_table(i):
			_pos[pid] = _phys.pos[i]
			advance_walk(pid, minf(_phys.speed(i) / 700.0, 1.0), delta, 4.0)


## Aplica lo que pasó en un paso de física: crédito de los toques, sonido,
## efectos y puntos de lo que cayó.
func _apply(events: Dictionary) -> void:
	for h: Array in events.hits:
		var a: int = h[0]
		var b: int = h[1]
		var impact: float = h[2]
		_credit(a, b)
		_credit(b, a)
		if impact >= HIT_SFX_MIN and _time - _last_hit_sfx >= HIT_SFX_GAP:
			_last_hit_sfx = _time
			play_sfx("pong", clampf(0.7 + impact / 2400.0, 0.7, 1.4))
		if impact >= HIT_FX_MIN:
			_effects.append({"kind": "hit", "pos": h[3], "t": 0.0, "power": clampf(impact / 1600.0, 0.35, 1.0)})
	for e: Array in events.pocketed:
		_pocket(e[0], e[1])


## La bola `target` fue tocada por la bola `source`: el crédito es del dueño
## de `source` (o, si es dorada, de quien la tiró). Tocar tu propia bola no cuenta.
func _credit(target: int, source: int) -> void:
	var by := _credit_of(source)
	if by == -1 or by == int(_owner.get(target, -1)):
		return
	_touch[target] = {"by": by, "t": _time}


func _credit_of(i: int) -> int:
	if _owner.has(i):
		return _owner[i]
	return credited(_touch.get(i, {}), _time)


func _pocket(i: int, k: int) -> void:
	var at: Vector2 = _phys.pockets[k]
	var by := credited(_touch.get(i, {}), _time)
	_touch.erase(i)
	_effects.append({"kind": "pocket", "pos": at, "t": 0.0, "power": 1.0})
	_falls.append({"i": i, "from": _phys.pos[i], "to": at, "t": 0.0})
	_phys.vel[i] = Vector2.ZERO
	if _owner.has(i):
		var owner: int = _owner[i]
		_respawn[owner] = RESPAWN_SEC
		_aim[owner] = new_aim()
		notify_player(owner, "lose")
		if by != -1 and by != owner:
			_add_points(by, RIVAL_POINTS)
		else:
			play_sfx("lose")
	else:
		_gold_wait[i] = GOLD_RESPAWN_SEC
		if by != -1:
			_add_points(by, GOLD_POINTS)
		else:
			play_sfx("pop")


func _add_points(pid: int, points: int) -> void:
	if not _score.has(pid):
		return
	_score[pid] = int(_score[pid]) + points
	_happy[pid] = HAPPY_SEC
	_popups.append({"text": "+%d" % points, "pid": pid, "t": 0.0})
	play_sfx("point")
	notify_player(pid, "point")


## Lugar libre cerca de `center` para una bola de radio `r`: el mismo lugar o
## alrededor, en un orden fijo (determinista). Vector2.INF si no hay.
func _free_spot_near(center: Vector2, r: float, ignore: int) -> Vector2:
	if _phys.is_free(center, r, ignore):
		return center
	for ring in range(1, 4):
		for a in 8:
			var p := center + Vector2.from_angle(TAU * a / 8.0) * ring * r * 2.4
			if _phys.is_free(p, r, ignore):
				return p
	return Vector2.INF


## Lugar al azar para una dorada que vuelve: en la mesa, lejos de las
## troneras y de las bolas de los jugadores.
func _random_gold_spot() -> Vector2:
	var area := PLAY.grow(-110.0)
	for attempt in 24:
		var p := Vector2(_rng.randf_range(area.position.x, area.end.x), _rng.randf_range(area.position.y, area.end.y))
		if not _phys.is_free(p, GOLD_R, -1, 14.0):
			continue
		var near := false
		for pid: int in _ball:
			var i: int = _ball[pid]
			if _phys.is_on_table(i) and p.distance_to(_phys.pos[i]) < BALL_R + GOLD_R + 90.0:
				near = true
				break
		if not near:
			return p
	return Vector2.INF


func _update_effects(delta: float) -> void:
	for f in _falls:
		f.t += delta
	_falls = _falls.filter(func(f: Dictionary) -> bool: return f.t < FALL_SEC)
	for e in _effects:
		e.t += delta
	_effects = _effects.filter(func(e: Dictionary) -> bool: return e.t < _effect_life(e.kind))
	for p in _popups:
		p.t += delta
	_popups = _popups.filter(func(p: Dictionary) -> bool: return p.t < POPUP_SEC)


static func _effect_life(kind: String) -> float:
	match kind:
		"hit":
			return HIT_FX_SEC
		"pocket":
			return POCKET_FX_SEC
	return SPAWN_FX_SEC


# --- Dibujo ---------------------------------------------------------------------

func _draw() -> void:
	if _phys == null:
		return  # Todavía sin setup().
	_v25 = draw_board_25d(board_view())
	if not _v25:
		draw_sky()
		draw_play_field(FELT, BOARD_CELL)  # Marco de bloques con volumen (el paño va encima).
		draw_static(_draw_table)
	# Lo acostado en el paño (sombras, guía de tiro): en 2.5D se arma en
	# coordenadas de la mesa y se proyecta vértice por vértice.
	# Halos de las doradas: plano, debajo de la flecha (como siempre); en
	# 2.5D, alrededor de la bola levantada (encima de lo acostado).
	var floor := GameArt.TriBatch.new()
	_add_shadows(floor)
	if not _v25:
		_add_glows(floor)
	for p in players:
		_add_aim(floor, p)
	var batch := _to_screen(floor)
	if _v25:
		_add_glows(batch)
	_add_falling_golds(batch)
	for i in _golds:
		if _phys.is_on_table(i):
			_add_gold(batch, _ball_at(_phys.pos[i], GOLD_R), GOLD_R * _depth(_phys.pos[i]), i)
	for p in players:
		var i: int = _ball[p.id]
		if _phys.is_on_table(i):
			_add_ball(batch, _ball_at(_phys.pos[i], BALL_R), BALL_R, p.color, i, _depth(_phys.pos[i]))
	batch.flush(self)
	# Mascotas arriba de su bola, de arriba hacia abajo (la de más abajo queda adelante).
	var order := players.filter(func(p: Dictionary) -> bool: return _phys.is_on_table(_ball[p.id]))
	order.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return (_pos[a.id] as Vector2).y < (_pos[b.id] as Vector2).y)
	var best := _best_score()
	for p in order:
		_draw_player(p, best)
	# Globitos 1P–4P y nombres; los que esperan reaparecer, transparentes en su lugar.
	var tags: Array = []
	for p in order:
		var d := _depth(_pos[p.id])
		tags.append([p, _feet_at(_pos[p.id]), MASCOT_SCALE * d, NAME_OFFSET * d])
	for p in players:
		if _respawn.has(p.id):
			tags.append([p, _feet_at(_spawn[p.id]), MASCOT_SCALE * _depth(_spawn[p.id]), -1.0, 0.55])
	draw_player_tags(tags)
	_draw_falling_players()
	_draw_respawns()
	_draw_effects()
	draw_hud(_score, clock_text(_time_left), "clock")
	_draw_messages()


func _add_glows(b: GameArt.TriBatch) -> void:
	for gi in _golds.size():
		var i := _golds[gi]
		if _phys.is_on_table(i):
			GameArt.add_glow(b, _ball_at(_phys.pos[i], GOLD_R), (GOLD_R + 20.0) * _depth(_phys.pos[i]), UiTheme.GLOW,
				anim_time + gi * 0.7, 8)


## Triángulos armados en coordenadas de la mesa -> pantalla: en 2.5D, cada
## vértice por la homografía (exacto: las rectas siguen rectas); plano, igual.
func _to_screen(b: GameArt.TriBatch) -> GameArt.TriBatch:
	if _v25:
		b.points = board_view().project_points(b.points)
	return b


## Centro en pantalla de una bola de radio `r` apoyada en `p`: en 2.5D, a
## su altura sobre el paño; plano, en su lugar.
func _ball_at(p: Vector2, r: float) -> Vector2:
	return board_view().project_up(p, r) if _v25 else p


## Escala de lo que está parado en `p` (bolas, mascotas, efectos): más chico
## atrás en 2.5D (con tope, UiTheme.BOARD25D_SCALE_*); 1 en plano.
func _depth(p: Vector2) -> float:
	if not _v25:
		return 1.0
	return clampf(board_view().scale_at(p), UiTheme.BOARD25D_SCALE_MIN, UiTheme.BOARD25D_SCALE_MAX)


## Pies de la mascota que va arriba de la bola apoyada en `p` (pantalla).
func _feet_at(p: Vector2) -> Vector2:
	return _ball_at(p, BALL_R) + Vector2(0, -BALL_R * FEET_UP) * _depth(p)


static func _feet(ball: Vector2) -> Vector2:
	return ball + Vector2(0, -BALL_R * FEET_UP)


## Lo fijo (se dibuja una vez, ver MiniGame.draw_static): paño con luz en el
## centro, bandas con filo de luz y puntitos, troneras y la marca del centro.
func _draw_table(ci: CanvasItem) -> void:
	var b := GameArt.TriBatch.new()
	b.rect(FELT, UiTheme.POOL_FELT)
	# Luz de lámpara: óvalo que va del centro (más claro) a transparente.
	var center := PLAY.get_center()
	var clear := Color(UiTheme.POOL_FELT_LIGHT, 0.0)
	b.points.append_array(Transform2D(0.0, PLAY.size * Vector2(0.5, 0.62), 0.0, center) * GameArt.circle_tris(40))
	b.colors.append_array(GameArt.pattern_colors(PackedColorArray([UiTheme.POOL_FELT_LIGHT, clear, clear]), 40))
	# Bandas: trapecios entre el borde del paño y el área de juego.
	var o := FELT
	var n := PLAY
	var cushion := UiTheme.POOL_CUSHION
	b.quad(o.position, Vector2(o.end.x, o.position.y), Vector2(n.end.x, n.position.y), n.position, cushion)
	b.quad(Vector2(o.position.x, o.end.y), Vector2(n.position.x, n.end.y), n.end, o.end, cushion)
	b.quad(o.position, n.position, Vector2(n.position.x, n.end.y), Vector2(o.position.x, o.end.y), cushion)
	b.quad(Vector2(o.end.x, o.position.y), Vector2(o.end.x, o.end.y), n.end, Vector2(n.end.x, n.position.y), cushion)
	# Filo de luz de las bandas y sombra que hacen sobre el paño (arriba e izquierda).
	var edge := UiTheme.POOL_CUSHION_EDGE
	b.rect(Rect2(n.position.x, n.position.y - 4.0, n.size.x, 4.0), edge)
	b.rect(Rect2(n.position.x, n.end.y, n.size.x, 4.0), edge)
	b.rect(Rect2(n.position.x - 4.0, n.position.y, 4.0, n.size.y), edge)
	b.rect(Rect2(n.end.x, n.position.y, 4.0, n.size.y), edge)
	var shade := Color(UiTheme.INK, 0.22)
	var none := Color(UiTheme.INK, 0.0)
	b.quad_colors(n.position, Vector2(n.end.x, n.position.y), Vector2(n.end.x, n.position.y + 18.0),
		n.position + Vector2(0, 18.0), shade, shade, none, none)
	b.quad_colors(n.position, n.position + Vector2(14.0, 0), Vector2(n.position.x + 14.0, n.end.y),
		Vector2(n.position.x, n.end.y), shade, none, none, shade)
	# Sombra del marco sobre las bandas (como en el tablero).
	b.quad_colors(o.position, Vector2(o.end.x, o.position.y), Vector2(o.end.x, o.position.y + 12.0),
		o.position + Vector2(0, 12.0), shade, shade, none, none)
	# Puntitos (miras) en las bandas, entre las troneras.
	for k: int in [1, 2, 3, 5, 6, 7]:
		var x := n.position.x + n.size.x * k / 8.0
		b.circle(Vector2(x, o.position.y + CUSHION / 2.0), 5.0, UiTheme.POOL_SIGHT, 10)
		b.circle(Vector2(x, o.end.y - CUSHION / 2.0), 5.0, UiTheme.POOL_SIGHT, 10)
	for k: int in [1, 2, 3]:
		var y := n.position.y + n.size.y * k / 4.0
		b.circle(Vector2(o.position.x + CUSHION / 2.0, y), 5.0, UiTheme.POOL_SIGHT, 10)
		b.circle(Vector2(o.end.x - CUSHION / 2.0, y), 5.0, UiTheme.POOL_SIGHT, 10)
	# Marcas del paño: punto del centro y anillo de las doradas.
	b.circle(center, 7.0, UiTheme.POOL_MARK, 14)
	var ring_in := PackedVector2Array()
	var ring_out := PackedVector2Array()
	for a in 48:
		var d := Vector2.from_angle(TAU * a / 48.0)
		ring_in.append(d * 138.0)
		ring_out.append(d * 144.0)
	b.shape(GameArt.ring_tris(ring_in, ring_out), Transform2D(0.0, center), UiTheme.POOL_MARK)
	# Troneras: aro de tinta, borde y agujero con la sombra del borde arriba.
	for pk: Vector2 in pockets():
		b.feather_circle(pk, POCKET_R + 5.0, UiTheme.INK)
		b.circle(pk, POCKET_R + 5.0, UiTheme.INK, 32)
		b.circle(pk, POCKET_R, UiTheme.POOL_POCKET_RIM, 32)
		b.circle(pk + Vector2(0, 3.0), POCKET_R - 5.0, UiTheme.POOL_POCKET, 32)
		b.ellipse(pk + Vector2(0, -POCKET_R * 0.35), POCKET_R * 0.6, POCKET_R * 0.22, Color(UiTheme.PAPER, 0.12))
	b.flush(ci)


## Sombras de las bolas sobre el paño (luz arriba a la izquierda).
func _add_shadows(b: GameArt.TriBatch) -> void:
	var pos := _phys.pos
	for i in pos.size():
		if _phys.on_table[i] == 1:
			var tpl := _shadow_tpl(_phys.radius[i])
			b.template(tpl[0], tpl[1], Transform2D(0.0, pos[i]))


## Guía de tiro mientras el jugador estira el joystick: puntitos hacia donde
## va a salir y una flecha más larga cuanto más fuerza. Gris si todavía no
## puede tirar (cuenta regresiva o recién tiró).
func _add_aim(b: GameArt.TriBatch, p: Dictionary) -> void:
	var pid: int = p.id
	var aim: Dictionary = _aim[pid]
	var power := float(aim.power)
	if power < RELEASE_ZONE or _respawn.has(pid) or _state == State.TIME_UP:
		return
	var i: int = _ball[pid]
	var dir: Vector2 = aim.dir
	var from: Vector2 = _phys.pos[i]
	var ready := _state == State.PLAYING and float(_cooldown[pid]) <= 0.0 and power >= ARM_MIN
	var col: Color = p.color if ready else UiTheme.MUTED
	var k := clampf(inverse_lerp(ARM_MIN, 1.0, power), 0.0, 1.0)
	var length := lerpf(AIM_MIN_LEN, AIM_MAX_LEN, k)
	var start := from + dir * (BALL_R + 8.0)
	var tip := start + dir * length
	# Guía de puntitos que se apaga de a poco (la flecha tapa los de abajo).
	var dots := _dots_tpl()
	b.template(dots[0], dots[1], Transform2D(dir.angle(), start))
	var side := dir.orthogonal()
	var head := 30.0 + 8.0 * k
	var neck := tip - dir * head
	# Contorno de tinta y después el color (cuerpo y punta).
	b.line(start - dir * 3.0, neck, UiTheme.INK, 22.0)
	b.tri(tip + dir * 7.0, neck + side * (head * 0.85 + 7.0) - dir * 5.0, neck - side * (head * 0.85 + 7.0) - dir * 5.0, UiTheme.INK)
	b.line(start, neck + dir * 2.0, col, 12.0)
	b.tri(tip, neck + side * head * 0.85, neck - side * head * 0.85, col)
	b.line(start + side * 2.5, neck - side * 1.0, Color(UiTheme.PAPER, 0.35), 3.0)


## Doradas que caen en una tronera: se achican hacia el agujero.
func _add_falling_golds(b: GameArt.TriBatch) -> void:
	for f in _falls:
		if _owner.has(f.i):
			continue
		var k: float = f.t / FALL_SEC
		var c: Vector2 = (f.from as Vector2).lerp(f.to, minf(k * 1.6, 1.0))
		var r := GOLD_R * (1.0 - k * 0.85)
		_add_gold(b, _ball_at(c, r), r * _depth(c), f.i)


## Bola dorada: aro de tinta, cuerpo con sombra, estrella (se distingue sin
## depender del color) y reflejo.
func _add_gold(b: GameArt.TriBatch, c: Vector2, r: float, i: int) -> void:
	var tpl := _gold_tpl()
	var s := r / GOLD_R
	b.template(tpl[0], tpl[1], Transform2D(0.0, Vector2(s, s), 0.0, c))
	var roll: Array = _roll.get(i, [0.0, Vector2.RIGHT])
	b.star(c + (roll[1] as Vector2) * sin(float(roll[0])) * r * 0.3, r * 0.52, UiTheme.GOLD.lightened(0.5), float(roll[0]) * 0.4, 0.0)


## Bola de un jugador, de su color, con un círculo blanco que rueda (se ve
## que se mueve y hacia dónde) y reflejo.
func _add_ball(b: GameArt.TriBatch, c: Vector2, r: float, col: Color, i: int, u: float = 1.0) -> void:
	var tpl := _ball_tpl(col)
	b.template(tpl[0], tpl[1], Transform2D(0.0, Vector2(u, u), 0.0, c))
	r *= u
	var roll: Array = _roll.get(i, [0.0, Vector2.DOWN])
	var phase := float(roll[0])
	var dir: Vector2 = roll[1]
	var front := cos(phase)
	if front > 0.0:
		var disc := c + dir * sin(phase) * r * 0.55
		b.ellipse(disc, r * 0.4 * lerpf(0.35, 1.0, front), r * 0.4, UiTheme.INK, dir.angle())
		b.ellipse(disc, r * 0.4 * lerpf(0.35, 1.0, front) - 2.5, r * 0.4 - 2.5, UiTheme.PAPER, dir.angle())


# --- Formas armadas una vez ------------------------------------------------------
#
# Rendimiento: las bolas se dibujan en cada frame (hasta 11) y cada una son
# varias figuras. Se arman una sola vez en coordenadas locales (puntos y
# colores, como GameArt.tile_template) y en cada frame solo se ubican: dos
# append_array por bola en vez de armar cada círculo.

## Sombra de una bola de radio `r` (centrada en la bola).
static func _shadow_tpl(r: float) -> Array:
	var key := ["shadow", r]
	if not _tpl.has(key):
		var b := GameArt.TriBatch.new()
		b.ellipse(Vector2(r * 0.22, r * 0.4), r * 1.02, r * 0.82, UiTheme.POOL_BALL_SHADOW)
		_tpl[key] = [b.points, b.colors]
	return _tpl[key]


## Dorada sin la estrella (que rueda): aro de tinta, cuerpo con sombra y reflejo.
static func _gold_tpl() -> Array:
	var key := ["gold"]
	if not _tpl.has(key):
		var b := GameArt.TriBatch.new()
		var r := GOLD_R
		b.feather_circle(Vector2.ZERO, r + 3.0, UiTheme.INK, 24)
		b.circle(Vector2.ZERO, r + 3.0, UiTheme.INK, 24)
		b.circle(Vector2.ZERO, r, UiTheme.GOLD.darkened(0.28), 24)
		b.circle(Vector2(-r * 0.1, -r * 0.12), r * 0.86, UiTheme.GOLD, 24)
		b.ellipse(Vector2(-r * 0.42, -r * 0.42), r * 0.28, r * 0.15, UiTheme.POOL_SHINE, -0.7)
		_tpl[key] = [b.points, b.colors]
	return _tpl[key]


## Bola de un jugador sin el círculo que rueda: aro de tinta, cuerpo de su
## color con sombra y reflejo.
static func _ball_tpl(col: Color) -> Array:
	var key := ["ball", col]
	if not _tpl.has(key):
		if _tpl.size() > 64:  # Tope (colores elegidos en muchas partidas).
			_tpl.clear()
		var b := GameArt.TriBatch.new()
		var r := BALL_R
		b.feather_circle(Vector2.ZERO, r + 4.0, UiTheme.INK, 28)
		b.circle(Vector2.ZERO, r + 4.0, UiTheme.INK, 28)
		b.circle(Vector2.ZERO, r, col.darkened(0.32), 28)
		b.circle(Vector2(-r * 0.1, -r * 0.12), r * 0.86, col, 28)
		b.ellipse(Vector2(-r * 0.5, -r * 0.12), r * 0.16, r * 0.26, UiTheme.POOL_SHINE, 0.3)
		_tpl[key] = [b.points, b.colors]
	return _tpl[key]


## Guía de tiro: puntitos sobre el eje +x desde 0 hasta AIM_GUIDE, cada vez
## más transparentes (se ubica rotada hacia donde apunta).
static func _dots_tpl() -> Array:
	var key := ["dots"]
	if not _tpl.has(key):
		var b := GameArt.TriBatch.new()
		var d := 26.0
		while d < AIM_GUIDE:
			var fade := 1.0 - d / AIM_GUIDE
			b.circle(Vector2(d, 0), 4.5, Color(UiTheme.POOL_AIM_DOT, UiTheme.POOL_AIM_DOT.a * fade), 8)
			d += 24.0
		_tpl[key] = [b.points, b.colors]
	return _tpl[key]


func _draw_player(p: Dictionary, best: int) -> void:
	var pid: int = p.id
	var i: int = _ball[pid]
	var mood := PlayerAvatar.Mood.NORMAL
	if float(_happy[pid]) > 0.0 or (_state == State.TIME_UP and int(_score[pid]) == best and best > 0):
		mood = PlayerAvatar.Mood.HAPPY
	elif _phys.speed(i) > SURPRISE_SPEED:
		mood = PlayerAvatar.Mood.SURPRISED
	var aim: Dictionary = _aim[pid]
	var look: Vector2 = (aim.dir as Vector2) if float(aim.power) >= RELEASE_ZONE else _phys.vel[i] / 1200.0
	var anim := mascot_anim(pid, look.limit_length(1.0))
	anim["wave"] = mood == PlayerAvatar.Mood.HAPPY
	var at: Vector2 = _phys.pos[i]
	PlayerAvatar.draw_mascot(self, _feet_at(at), MASCOT_SCALE * _depth(at), p.color, PlayerAvatar.style_of(p), mood, 0.0, 0.0, false, anim)


## Bola y mascota de un jugador que cae en una tronera: giran y se achican.
func _draw_falling_players() -> void:
	for f in _falls:
		if not _owner.has(f.i):
			continue
		var p := player_by_id(_owner[f.i])
		if p.is_empty():
			continue
		var k: float = f.t / FALL_SEC
		var s := 1.0 - k * 0.9
		var c: Vector2 = (f.from as Vector2).lerp(f.to, minf(k * 1.6, 1.0))
		s *= _depth(c)
		var xform := Transform2D(k * PI * (1.0 if int(p.slot) % 2 == 0 else -1.0), Vector2(s, s), 0.0, _ball_at(c, BALL_R * s))
		draw_set_transform_matrix(xform)
		var b := GameArt.TriBatch.new()
		_add_ball(b, Vector2.ZERO, BALL_R, p.color, f.i)
		b.flush(self)
		PlayerAvatar.draw_mascot(self, _feet(Vector2.ZERO), MASCOT_SCALE, p.color, PlayerAvatar.style_of(p), PlayerAvatar.Mood.SAD,
			0.0, 0.0, false, {"xform": xform})
		draw_set_transform(Vector2.ZERO)


## Mientras una bola espera para volver: su lugar marcado con un círculo
## transparente que se va llenando (el globito del jugador arriba).
func _draw_respawns() -> void:
	for p in players:
		if not _respawn.has(p.id):
			continue
		var at: Vector2 = _spawn[p.id]
		var k := 1.0 - clampf(float(_respawn[p.id]) / RESPAWN_SEC, 0.0, 1.0)
		if _v25:  # Acostado en el paño.
			draw_set_transform_matrix(board_view().floor_xform(at))
		draw_circle(at, BALL_R, Color(p.color, 0.3))
		draw_arc(at, BALL_R + 2.0, 0, TAU, 32, Color(UiTheme.INK, 0.5), 6.0, true)
		draw_arc(at, BALL_R + 2.0, -PI / 2.0, -PI / 2.0 + TAU * k, 32, p.color, 6.0, true)
	draw_set_transform(Vector2.ZERO)


func _draw_effects() -> void:
	# Anillos (tronera, bola que vuelve): acostados en el paño. Estrellitas
	# de los choques: paradas, a la altura de las bolas.
	var rings := GameArt.TriBatch.new()
	var b := GameArt.TriBatch.new()
	for e in _effects:
		var pos: Vector2 = e.pos
		match e.kind:
			"hit":
				var k: float = e.t / HIT_FX_SEC
				var power: float = e.power
				var c := _ball_at(pos, BALL_R)
				var u := _depth(pos)
				for s in 5:
					var a := TAU * s / 5.0 + pos.x * 0.01
					var at := c + Vector2.from_angle(a) * lerpf(10.0, 30.0 + 40.0 * power, k) * u
					b.star(at, (7.0 + 7.0 * power) * (1.0 - k * 0.8) * u, UiTheme.GOLD, k * 2.0, 3.0)
			"pocket":
				var k: float = e.t / POCKET_FX_SEC
				_add_ring(rings, pos, lerpf(POCKET_R * 0.8, POCKET_R * 2.0, k), Color(UiTheme.PAPER, 0.85 * (1.0 - k)))
			_:
				var k: float = e.t / SPAWN_FX_SEC
				_add_ring(rings, pos, lerpf(BALL_R * 2.4, BALL_R * 1.1, k), Color(UiTheme.PAPER, 0.9 * (1.0 - k)))
	_to_screen(rings).flush(self)
	b.flush(self)
	for p in _popups:
		var k: float = p.t / POPUP_SEC
		var at: Vector2 = _pos.get(p.pid, Vector2.ZERO)
		UiTheme.draw_text(self, p.text, _feet_at(at) - Vector2(0, 120.0 + 50.0 * k) * _depth(at), 48,
			Color(UiTheme.GOLD, 1.0 - k * k), 10, Color(UiTheme.INK, 1.0 - k * k))


## Anillo de efecto (tronera, bola que vuelve): un anillo unitario
## precalculado, escalado. Así no se cachea una forma nueva por cada radio.
static func _add_ring(b: GameArt.TriBatch, c: Vector2, r: float, col: Color) -> void:
	if _ring_unit.is_empty():
		var inner := PackedVector2Array()
		var outer := PackedVector2Array()
		for a in 32:
			var d := Vector2.from_angle(TAU * a / 32.0)
			inner.append(d * 0.8)
			outer.append(d)
		_ring_unit = GameArt.ring_tris(inner, outer)
	b.shape(_ring_unit, Transform2D(0.0, Vector2(r, r), 0.0, c), col)


## Cuenta regresiva, "¡YA!", "¡Tiempo!" y el cartel de cómo se tira (arriba
## de la mesa, entre el marcador y el tablero).
func _draw_messages() -> void:
	if _state != State.TIME_UP and _time < COUNTDOWN_SEC + HINT_SEC:
		var alpha := clampf((COUNTDOWN_SEC + HINT_SEC - _time) / 0.6, 0.0, 1.0)
		var text := "Estirá el joystick para apuntar y soltalo para tirar"
		var w := UiTheme.FONT_BOLD.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 30).x + 64.0
		var r := Rect2(SCREEN.x / 2.0 - w / 2.0, 100.0, w, 46.0)
		var b := GameArt.TriBatch.new()
		b.capsule(r, Color(UiTheme.POOL_HINT_BG, UiTheme.POOL_HINT_BG.a * alpha))
		b.flush(self)
		UiTheme.draw_text(self, text, r.get_center(), 30, Color(UiTheme.PAPER, alpha))
	if _state == State.COUNTDOWN:
		draw_text_centered("%d" % ceili(_countdown), SCREEN / 2.0, 260, UiTheme.PAPER, 22)
	elif _state == State.PLAYING and _countdown > -GO_SEC:
		draw_text_centered("¡YA!", SCREEN / 2.0, 260, UiTheme.ACCENT, 22)
	elif _state == State.TIME_UP or is_finished():
		draw_text_centered("¡Tiempo!", SCREEN / 2.0, 200, UiTheme.ACCENT, 22)


func _best_score() -> int:
	var best := 0
	for pid: int in _score:
		best = maxi(best, int(_score[pid]))
	return best
