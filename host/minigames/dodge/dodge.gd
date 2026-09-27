extends MiniGame
## Esquivar: caen bloques del cielo y hay que moverse para que no te aplasten.
## La sombra en el piso avisa dónde va a caer cada bloque y crece a medida
## que baja. Cada vez caen más rápido y más seguido.
##
## Puntaje: segundos que sobreviviste (con un decimal). Gana el último en
## pie; si llegan varios al final del tiempo, ganan todos los que siguen en pie.
##
## Vista "desde arriba con altura": cada bloque tiene un punto de impacto en
## el piso (`ground`) y baja desde el borde de arriba del campo hasta ahí,
## acelerando. Solo lastima cuando ya está en el piso.
##
## Capas de dibujo (de atrás hacia adelante):
##   1. este nodo: cielo, campo, sombras, bloques apoyados, mascotas en pie, HUD
##   2. _ghosts (CanvasGroup semitransparente): mascotas eliminadas
##   3. _air (Control recortado al campo): bloques en el aire

const DURATION_SEC := 45.0
const COUNTDOWN_SEC := 3.0
const GO_SEC := 0.8               ## Cuánto se ve "¡YA!" después del 1.
const FIELD := Rect2(160, 140, 1600, 860)
const SPEED := 620.0              ## Igual que Arena.
const MASCOT_SCALE := 0.8
const HIT_RADIUS := 28.0          ## Radio del "pie" de la mascota para choques.
const NAME_OFFSET := 26.0         ## Nombre debajo de los pies.
## Márgenes para que la mascota (hacia arriba) y el nombre (hacia abajo)
## no se salgan del campo.
const MOVE_MARGIN_X := 44.0
const MOVE_MARGIN_TOP := 96.0
const MOVE_MARGIN_BOTTOM := 46.0

const BLOCK_MIN := 84.0
const BLOCK_MAX := 132.0
const BLOCK_RADIUS := 16.0
const BLOCK_DEPTH := 14.0         ## Cara inferior más oscura (relieve).
const LINGER_SEC := 0.45          ## Tiempo apoyado en el piso: sigue lastimando.
const FADE_SEC := 0.3             ## Después se desvanece sin lastimar.

## Dificultad: todo interpola de "fácil" a "difícil" en RAMP_SEC segundos.
const RAMP_SEC := 35.0
const FIRST_SPAWN_SEC := 0.5
const SPAWN_EVERY_START := 0.7
const SPAWN_EVERY_END := 0.22
const FALL_TIME_START := 1.5
const FALL_TIME_END := 0.65
const AIM_CHANCE := 0.35          ## Algunos bloques apuntan (con error) a un jugador.
const AIM_JITTER := 90.0

const OUT_ALPHA := 0.45           ## Transparencia de los eliminados.

var _pos: Dictionary = {}         # player_id -> Vector2 (pies, en el piso)
var _axis: Dictionary = {}        # player_id -> Vector2
var _out_time: Dictionary = {}    # player_id -> segundos sobrevividos (solo eliminados)
## Bloques: {ground: Vector2, size: float, color: Color, fall: float, t: float}
## t = segundos desde que apareció; toca el piso cuando t >= fall.
var _blocks: Array = []
var _countdown := COUNTDOWN_SEC
var _elapsed := 0.0               # segundos de juego (sin la cuenta regresiva)
var _spawn_timer := FIRST_SPAWN_SEC
var _anim := 0.0                  # reloj solo para animaciones
var _rng := RandomNumberGenerator.new()

# Capas: se crean al entrar al árbol (instanciar el juego sin usarlo no deja nodos sueltos).
var _ghosts: CanvasGroup
var _ghost_drawer: Node2D
var _air: Control


static func get_info() -> Dictionary:
	return {
		"id": "dodge",
		"title": "Esquivar",
		"description": "Esquivá los bloques que caen del cielo. Mirá las sombras: el último en pie gana.",
		"min_players": 1,
		"max_players": 4,
		"layout": Protocol.LAYOUT_JOYSTICK,
		"layout_data": {},
		"accent": UiTheme.BRICKS[0],
		"score_label": "segundos",
	}


func _ready() -> void:
	_ghosts = CanvasGroup.new()
	_ghost_drawer = Node2D.new()
	_air = Control.new()
	# CanvasGroup aplica la transparencia a la mascota entera (sin que se
	# vean los contornos superpuestos a través del relleno).
	_ghosts.self_modulate = Color(1, 1, 1, OUT_ALPHA)
	_ghosts.add_child(_ghost_drawer)
	_ghost_drawer.draw.connect(_draw_ghosts)
	add_child(_ghosts)
	# Los bloques en el aire se recortan al campo: "entran" por debajo del
	# marco y nunca tapan el HUD.
	_air.position = FIELD.position
	_air.size = FIELD.size
	_air.clip_contents = true
	_air.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_air.draw.connect(_draw_air)
	add_child(_air)


func setup(p_players: Array[Dictionary]) -> void:
	super.setup(p_players)
	_rng.randomize()
	var n := players.size()
	for i in n:
		var p: Dictionary = players[i]
		_pos[p.id] = Vector2(FIELD.position.x + FIELD.size.x * (i + 1) / (n + 1), FIELD.get_center().y + 80.0)
		_axis[p.id] = Vector2.ZERO


func on_input(player_id: int, input: Dictionary) -> void:
	if not _axis.has(player_id) or _out_time.has(player_id):
		return
	var axis: Variant = input.get("axis", Vector2.ZERO)
	_axis[player_id] = (axis as Vector2).limit_length(1.0) if axis is Vector2 else Vector2.ZERO


## Para los bots (ver MiniGame.bot_view): mascotas, bloques (con su sombra
## en el piso: dónde y cuándo caen, como se ve en la TV) y el campo. Solo lectura.
func bot_view() -> Dictionary:
	return {
		"pos": _pos, "out": _out_time, "blocks": _blocks, "countdown": _countdown,
		"move_rect": Rect2(FIELD.position + Vector2(MOVE_MARGIN_X, MOVE_MARGIN_TOP),
			FIELD.size - Vector2(MOVE_MARGIN_X * 2.0, MOVE_MARGIN_TOP + MOVE_MARGIN_BOTTOM)),
		"speed": SPEED, "hit_radius": HIT_RADIUS, "linger": LINGER_SEC,
	}


func _physics_process(delta: float) -> void:
	if is_finished() or hit_stopped(delta):
		return
	if in_finale():  # Festejo final: todo quieto, los que quedaron en pie saltan.
		for pid: int in _pos:
			advance_walk(pid, 0.0, delta)
		_redraw()
		return
	_anim += delta
	if _countdown > -GO_SEC:
		var before := _countdown
		_countdown -= delta
		tick_countdown(before, _countdown)
	_move_players(delta)
	if _countdown <= 0.0:
		_elapsed = minf(_elapsed + delta, DURATION_SEC)
		_spawn_timer -= delta
		while _spawn_timer <= 0.0:
			_spawn_random_block()
			_spawn_timer += lerpf(SPAWN_EVERY_START, SPAWN_EVERY_END, _difficulty())
	_update_blocks(delta)
	_check_hits()
	_check_end()
	_redraw()


func _move_players(delta: float) -> void:
	for pid: int in _pos:
		if _out_time.has(pid):
			continue
		var p: Vector2 = _pos[pid] + (_axis[pid] as Vector2) * SPEED * delta
		advance_walk(pid, (_axis[pid] as Vector2).length(), delta, 3.0)
		p.x = clampf(p.x, FIELD.position.x + MOVE_MARGIN_X, FIELD.end.x - MOVE_MARGIN_X)
		p.y = clampf(p.y, FIELD.position.y + MOVE_MARGIN_TOP, FIELD.end.y - MOVE_MARGIN_BOTTOM)
		_pos[pid] = p
		juice().stop_dust(pid, (_axis[pid] as Vector2).length(), p)


## 0 al empezar, 1 a los RAMP_SEC segundos.
func _difficulty() -> float:
	return clampf(_elapsed / RAMP_SEC, 0.0, 1.0)


func _spawn_random_block() -> void:
	var size := _rng.randf_range(BLOCK_MIN, BLOCK_MAX)
	var alive := _alive_ids()
	var target: Vector2
	if not alive.is_empty() and _rng.randf() < AIM_CHANCE:
		var pid: int = alive[_rng.randi() % alive.size()]
		target = (_pos[pid] as Vector2) + Vector2(_rng.randf_range(-AIM_JITTER, AIM_JITTER), _rng.randf_range(-AIM_JITTER, AIM_JITTER))
	else:
		target = Vector2(_rng.randf_range(FIELD.position.x, FIELD.end.x), _rng.randf_range(FIELD.position.y, FIELD.end.y))
	_spawn_block(target, size, lerpf(FALL_TIME_START, FALL_TIME_END, _difficulty()))


## Agrega un bloque que cae en `ground` (recortado al campo) en `fall_time`
## segundos. Con fall_time = 0 cae en el próximo paso (lo usan los tests).
func _spawn_block(ground: Vector2, size: float, fall_time: float) -> void:
	var half := size / 2.0
	ground.x = clampf(ground.x, FIELD.position.x + half, FIELD.end.x - half)
	ground.y = clampf(ground.y, FIELD.position.y + half, FIELD.end.y - half)
	_blocks.append({
		"ground": ground, "size": size, "fall": maxf(fall_time, 0.0), "t": 0.0,
		"color": UiTheme.BRICKS[_rng.randi() % UiTheme.BRICKS.size()],
	})


func _update_blocks(delta: float) -> void:
	for b in _blocks:
		var landed: bool = b.t < b.fall and b.t + delta >= b.fall
		b.t += delta
		if landed:
			_land_fx(b)
	_blocks = _blocks.filter(func(b: Dictionary) -> bool: return b.t < b.fall + LINGER_SEC + FADE_SEC)


func _check_hits() -> void:
	for b in _blocks:
		if b.t < b.fall or b.t >= b.fall + LINGER_SEC:
			continue
		var r := _ground_rect(b)
		for pid: int in _pos:
			if _out_time.has(pid):
				continue
			var feet: Vector2 = _pos[pid]
			var closest := Vector2(clampf(feet.x, r.position.x, r.end.x), clampf(feet.y, r.position.y, r.end.y))
			if feet.distance_to(closest) < HIT_RADIUS:
				_out_time[pid] = snappedf(_elapsed, 0.1)
				_axis[pid] = Vector2.ZERO
				play_sfx("hit")
				notify_player(pid, "hit")
				# Alcanzado: pausa de impacto, sacudida leve y estrellitas.
				hit_stop(0.08)
				juice().shake(0.8)
				juice().sparkles(feet + Vector2(0, -50), UiTheme.GOLD, 10, 420.0)


func _check_end() -> void:
	var alive := _alive_ids()
	var last_standing := players.size() >= 2 and alive.size() <= 1
	if alive.is_empty() or last_standing or _elapsed >= DURATION_SEC:
		_end(alive)


func _end(alive: Array[int]) -> void:
	var scores := {}
	for p in players:
		scores[p.id] = float(_out_time.get(p.id, snappedf(_elapsed, 0.1)))
	var result := {"winners": alive, "scores": scores, "summary": "Último en pie gana"}
	if alive.is_empty():
		result = result_from_scores(scores, "Más segundos en pie gana")
	# Festejo antes del resumen: "¡Tiempo!" o "¡Último en pie!" y confeti.
	var party := {}
	for pid in alive:
		party[pid] = _pos[pid]
	finish_after(result, "¡Tiempo!" if _elapsed >= DURATION_SEC else ("¡Último en pie!" if not alive.is_empty() else "¡Fin!"), party)
	_redraw()


## Un bloque toca el piso: polvo a los costados y un golpe sordo.
func _land_fx(b: Dictionary) -> void:
	var r := _ground_rect(b)
	var y := r.end.y - 6.0
	juice().dust(Vector2(r.position.x + 8.0, y), 2, Vector2(-1, -0.3), 12.0)
	juice().dust(Vector2(r.end.x - 8.0, y), 2, Vector2(1, -0.3), 12.0)
	play_sfx("thud", _rng.randf_range(0.85, 1.15))


func _alive_ids() -> Array[int]:
	var out: Array[int] = []
	for p in players:
		if not _out_time.has(p.id):
			out.append(p.id)
	return out


## Segundos para el HUD: los eliminados quedan fijos, los demás siguen sumando.
func _live_scores() -> Dictionary:
	var out := {}
	for p in players:
		out[p.id] = _out_time.get(p.id, _elapsed)
	return out


func _ground_rect(b: Dictionary) -> Rect2:
	var s: float = b.size
	return Rect2(b.ground - Vector2(s, s) / 2.0, Vector2(s, s))


# --- Dibujo ------------------------------------------------------------------

func _redraw() -> void:
	queue_redraw()
	if _air == null:
		return
	_ghost_drawer.queue_redraw()
	_air.queue_redraw()


func _draw() -> void:
	draw_sky()
	draw_play_field(FIELD)
	# Sombras de los bloques en el aire: crecen y se oscurecen al bajar.
	for b in _blocks:
		if b.t < b.fall:
			var k: float = clampf(b.t / b.fall, 0.0, 1.0) if b.fall > 0.0 else 1.0
			var r := _ground_rect(b)
			var shadow := Rect2(r.get_center() - r.size * lerpf(0.5, 1.0, k) / 2.0, r.size * lerpf(0.5, 1.0, k))
			UiTheme.draw_round_rect(self, shadow, Color(UiTheme.SHADOW, lerpf(0.12, 0.42, k)), BLOCK_RADIUS)
			if k > 0.4:  # Aviso final: marco punteado que titila cada vez más rápido.
				var blink := 0.75 + 0.25 * sin(_anim * lerpf(10.0, 36.0, k))
				UiTheme.draw_dashed_rect(self, r, Color(UiTheme.DANGER, (k - 0.4) / 0.6 * blink), 4.0, BLOCK_RADIUS, 12.0, 8.0)
	# Bloques apoyados (al final se desvanecen).
	for b in _blocks:
		if b.t >= b.fall:
			var fade := clampf(1.0 - (b.t - b.fall - LINGER_SEC) / FADE_SEC, 0.0, 1.0)
			_draw_block(self, _ground_rect(b), b.color, fade)
	# Mascotas en pie: de arriba hacia abajo (la de más abajo queda adelante).
	var order := players.filter(func(p: Dictionary) -> bool: return not _out_time.has(p.id))
	order.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return (_pos[a.id] as Vector2).y < (_pos[b.id] as Vector2).y)
	for p in order:
		var feet: Vector2 = _pos[p.id]
		var party := is_finished() or is_celebrating(p.id)
		var mood := PlayerAvatar.Mood.HAPPY if party else PlayerAvatar.Mood.NORMAL
		# Si un bloque está por caer muy cerca, pone cara de susto.
		if mood == PlayerAvatar.Mood.NORMAL and not in_finale() and _danger_near(feet):
			mood = PlayerAvatar.Mood.SURPRISED
		var anim := mascot_anim(p.id, _axis[p.id])
		anim["wave"] = party
		PlayerAvatar.draw_mascot(self, feet, MASCOT_SCALE, p.color, PlayerAvatar.style_of(p), mood, 0.0, celebrate_hop(p.id), false, anim)
	# Globitos y nombres de todos, también de los eliminados y a opacidad
	# completa: la mascota va translúcida (capa _ghosts), pero quién es tiene
	# que seguir leyéndose.
	draw_player_tags(players.map(func(p: Dictionary) -> Array: return [p, _pos[p.id], MASCOT_SCALE, NAME_OFFSET]))
	draw_hud(_live_scores(), clock_text(DURATION_SEC - _elapsed), "clock")
	draw_countdown(_countdown, GO_SEC)


## ¿Hay un bloque a punto de caer (último 40 % de la caída) cerca de estos pies?
func _danger_near(feet: Vector2) -> bool:
	for b in _blocks:
		if b.t < b.fall and b.fall > 0.0 and b.t / b.fall > 0.6:
			if _ground_rect(b).grow(HIT_RADIUS * 2.0).has_point(feet):
				return true
	return false


## Eliminados: mascota triste, quieta y semitransparente (ver _ghosts).
func _draw_ghosts() -> void:
	for p in players:
		if not _out_time.has(p.id):
			continue
		var feet: Vector2 = _pos[p.id]
		PlayerAvatar.draw_mascot(_ghost_drawer, feet, MASCOT_SCALE, p.color, PlayerAvatar.style_of(p), PlayerAvatar.Mood.SAD)


## Bloques en el aire, en coordenadas de pantalla (la capa está corrida).
func _draw_air() -> void:
	_air.draw_set_transform(-_air.position)
	var falling := _blocks.filter(func(b: Dictionary) -> bool: return b.t < b.fall)
	# Los más altos (más lejos del piso) primero.
	falling.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.t / a.fall < b.t / b.fall)
	for b in falling:
		var k: float = clampf(b.t / b.fall, 0.0, 1.0)
		var r := _ground_rect(b)
		var s := r.size * lerpf(1.15, 1.0, k)       # más grande cuanto más alto
		# Arranca justo arriba del recorte (fuera de vista) y cae acelerando.
		var start_height := r.get_center().y - _air.position.y + s.y
		var height := start_height * (1.0 - k * k)
		_draw_block(_air, Rect2(r.get_center() - s / 2.0 - Vector2(0, height), s), b.color, 1.0)


## Bloque de juguete: contorno INK, cara inferior oscura y brillo arriba.
static func _draw_block(ci: CanvasItem, r: Rect2, col: Color, alpha: float) -> void:
	var body := Rect2(r.position, r.size - Vector2(0, BLOCK_DEPTH))
	UiTheme.draw_round_rect(ci, r.grow(4.0), Color(UiTheme.INK, alpha), BLOCK_RADIUS + 4.0)
	UiTheme.draw_round_rect(ci, r, Color(col.darkened(0.3), alpha), BLOCK_RADIUS)
	UiTheme.draw_round_rect(ci, body, Color(col, alpha), BLOCK_RADIUS)
	var shine := Rect2(body.position + Vector2(10, 8), Vector2(body.size.x - 20, body.size.y * 0.22))
	UiTheme.draw_round_rect(ci, shine, Color(col.lightened(0.35), alpha), shine.size.y / 2.0)
