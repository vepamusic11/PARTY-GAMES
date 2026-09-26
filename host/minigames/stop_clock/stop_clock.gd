extends MiniGame
## Reloj exacto: después de la cuenta 3-2-1 corre un cronómetro grande. Cada
## jugador tiene que frenar SU reloj lo más cerca posible de 10.00 segundos.
## A los 3 s el cronómetro se apaga y hay que seguir contando mentalmente.
##
## Cada jugador frena una sola vez (flanco de subida del botón, como en
## tap_race: mantener apretado desde la cuenta regresiva no cuenta). Quien no
## frena se detiene solo a los 15 s con el peor resultado. Al frenar todos se
## revelan los tiempos durante 2 s y el juego termina.
##
## El tiempo se mide acumulando el delta de _physics_process (no con el reloj
## del sistema): así, si la TV pausa el juego, el cronómetro también se frena.

const COUNTDOWN := 3.0     ## Segundos de la cuenta regresiva 3-2-1.
const TARGET := 10.0       ## Meta: frenar el reloj en 10.00.
const BLACKOUT_AT := 3.0   ## Desde acá el cronómetro grande se apaga.
const MAX_TIME := 15.0     ## Quien no frenó se detiene solo acá.
const REVEAL_TIME := 2.0   ## Segundos mostrando los tiempos antes de terminar.
const MAX_SCORE := 1000    ## Puntaje de un frenado perfecto (error 0 ms).

const NOT_STOPPED := -1.0

# Medidas del dibujo (resolución lógica 1920×1080).
const LCD_RECT := Rect2(460, 124, 1000, 400)   ## Panel del cronómetro grande.
const LCD_DIGIT_SIZE := 230
const ROW_FEET_Y := 736.0                      ## Donde apoyan las mascotas.
const BOX_SIZE := Vector2(340, 250)            ## Cajita de cada jugador.
const MINI_DIGIT_SIZE := 60
const MASCOT_SCALE := 1.45

var _t := 0.0                    # Segundos desde que empezó el juego (incluye la cuenta).
var _stops: Dictionary = {}      # player_id -> segundos en que frenó, o NOT_STOPPED.
var _was_down: Dictionary = {}   # player_id -> bool (para detectar el flanco de subida).
var _reveal_left := -1.0         # >= 0: mostrando resultados.
var _final_clock := 0.0          # Lo que marca el reloj grande al revelar.


static func get_info() -> Dictionary:
	return {
		"id": "stop_clock",
		"title": "Reloj exacto",
		"description": "Frená tu reloj justo en 10.00 segundos. ¡A los 3 s el cronómetro se apaga y tenés que contar en tu cabeza!",
		"min_players": 1,
		"max_players": 4,
		"layout": Protocol.LAYOUT_ONE_BUTTON,
		"layout_data": {"label": "¡STOP!"},
		"accent": UiTheme.BRICKS[7],   # Rosa: no lo usa ningún otro juego.
		"score_label": "de precisión",
	}


## Puntaje de un frenado (mayor es mejor): 1000 menos el error en milisegundos.
## Pura y estática para poder testearla.
static func score_for(stop_time: float) -> int:
	var error_ms := roundi(absf(stop_time - TARGET) * 1000.0)
	return maxi(0, MAX_SCORE - error_ms)


## "09.87": formato fijo de dos dígitos enteros, como un display.
static func format_time(seconds: float) -> String:
	return "%05.2f" % clampf(seconds, 0.0, 99.99)


func setup(p_players: Array[Dictionary]) -> void:
	super.setup(p_players)
	for p in players:
		_stops[p.id] = NOT_STOPPED
		_was_down[p.id] = false


func on_input(player_id: int, input: Dictionary) -> void:
	if not _stops.has(player_id) or is_finished():
		return
	var down := (int(input.btn) & Protocol.BTN_A) != 0
	if down and not _was_down[player_id] and is_running() and not has_stopped(player_id):
		_stops[player_id] = elapsed()
		play_sfx("stop")
		notify_player(player_id, "tap")
		if _all_stopped():
			_start_reveal()
	_was_down[player_id] = down


## Segundos que marca el cronómetro (0 durante la cuenta regresiva).
func elapsed() -> float:
	return maxf(0.0, _t - COUNTDOWN)


## El cronómetro corre y se puede frenar.
func is_running() -> bool:
	return _t >= COUNTDOWN and _reveal_left < 0.0


func is_revealing() -> bool:
	return _reveal_left >= 0.0


## El cronómetro grande está apagado: hay que contar mentalmente.
func is_blackout() -> bool:
	return is_running() and elapsed() >= BLACKOUT_AT


func has_stopped(player_id: int) -> bool:
	return float(_stops.get(player_id, NOT_STOPPED)) >= 0.0


## Segundos en que frenó el jugador, o NOT_STOPPED.
func stop_time(player_id: int) -> float:
	return float(_stops.get(player_id, NOT_STOPPED))


func scores() -> Dictionary:
	var out := {}
	for pid: int in _stops:
		out[pid] = score_for(stop_time(pid)) if has_stopped(pid) else 0
	return out


func _all_stopped() -> bool:
	for pid: int in _stops:
		if not has_stopped(pid):
			return false
	return true


func _start_reveal() -> void:
	_final_clock = elapsed()
	_reveal_left = REVEAL_TIME
	play_sfx("pop")


func _physics_process(delta: float) -> void:
	if is_finished():
		return
	if is_revealing():
		_reveal_left -= delta
		if _reveal_left <= 0.0:
			finish(result_from_scores(scores(), "Más cerca de 10.00 gana"))
	else:
		tick_countdown(COUNTDOWN - _t, COUNTDOWN - _t - delta)
		_t += delta
		if is_running() and elapsed() >= MAX_TIME:
			# Quien no frenó se detiene solo con el peor resultado.
			_t = COUNTDOWN + MAX_TIME
			for pid: int in _stops:
				if not has_stopped(pid):
					_stops[pid] = MAX_TIME
			_start_reveal()
	queue_redraw()


# --- Dibujo -------------------------------------------------------------------

func _draw() -> void:
	draw_sky()
	_draw_big_clock()
	var n := players.size()
	var slot_w := (SCREEN.x - 2.0 * UiTheme.SAFE_MARGIN) / 4.0
	var left := (SCREEN.x - slot_w * n) / 2.0
	var sc := scores()
	var best := 0
	for pid: int in sc:
		best = maxi(best, int(sc[pid]))
	for i in n:
		var p: Dictionary = players[i]
		_draw_player(p, Vector2(left + slot_w * (i + 0.5), ROW_FEET_Y), int(sc.get(p.id, 0)), best)
	# Durante el juego el marcador muestra ceros: un puntaje parcial delataría
	# cuánto falta para 10.00 a los que todavía no frenaron.
	draw_hud(sc if is_revealing() else {}, "Meta: %s" % format_time(TARGET))


func _draw_big_clock() -> void:
	var r := LCD_RECT
	UiTheme.draw_round_rect(self, r.grow(10), UiTheme.INK, 48, 0, UiTheme.INK, true)
	var screen := r.grow(-18)
	UiTheme.draw_round_rect(self, screen, UiTheme.CHIP_DARK, 30)
	var digits_center := screen.get_center() + Vector2(0, -34)
	var status_center := Vector2(screen.get_center().x, screen.end.y - 52)
	if _t < COUNTDOWN:
		UiTheme.draw_round_rect(self, screen.grow(-10), Color(UiTheme.ACCENT, 0.06), 24)
		UiTheme.draw_text(self, "%d" % ceili(COUNTDOWN - _t), digits_center, LCD_DIGIT_SIZE, UiTheme.ACCENT)
		UiTheme.draw_text(self, "¡Preparados!", status_center, 40, UiTheme.PAPER)
	elif is_blackout():
		# Apagado: pantalla oscura, sin números.
		UiTheme.draw_round_rect(self, screen.grow(-10), Color(UiTheme.INK, 0.6), 24)
		UiTheme.draw_text(self, "¡Contá en tu cabeza!", status_center, 40, UiTheme.MUTED)
	else:
		var shown := _final_clock if is_revealing() else elapsed()
		UiTheme.draw_round_rect(self, screen.grow(-10), Color(UiTheme.ACCENT, 0.06), 24)
		_draw_lcd_text(format_time(shown), digits_center, LCD_DIGIT_SIZE, UiTheme.ACCENT)
		var status := "¡Tiempo!" if is_revealing() else ("¡YA!" if elapsed() < 0.8 else "¡Frená en %s!" % format_time(TARGET))
		UiTheme.draw_text(self, status, status_center, 40, UiTheme.PAPER)


## Dígitos en celdas de ancho fijo: la tipografía no es monoespaciada y el
## número "bailaría" al cambiar cada centésima.
func _draw_lcd_text(text: String, center: Vector2, size: int, color: Color) -> void:
	var digit_w := size * 0.62
	var dot_w := size * 0.3
	var total := 0.0
	for ch in text:
		total += dot_w if ch == "." else digit_w
	var x := center.x - total / 2.0
	for ch in text:
		var w := dot_w if ch == "." else digit_w
		UiTheme.draw_text(self, ch, Vector2(x + w / 2.0, center.y), size, color)
		x += w


func _draw_player(p: Dictionary, feet: Vector2, score: int, best: int) -> void:
	var pid: int = p.id
	var mood: int = PlayerAvatar.Mood.NORMAL
	if is_revealing():
		if score == 0:
			mood = PlayerAvatar.Mood.SAD
		elif score == best:
			mood = PlayerAvatar.Mood.HAPPY
	var hop := 0.0
	if is_revealing() and mood == PlayerAvatar.Mood.HAPPY:
		hop = absf(sin((REVEAL_TIME - _reveal_left) * 7.0)) * 18.0
	# Cajita del color del jugador con una mini pantalla.
	var box := Rect2(feet.x - BOX_SIZE.x / 2.0, feet.y, BOX_SIZE.x, BOX_SIZE.y)
	UiTheme.draw_round_rect(self, box.grow(4), UiTheme.INK, 26, 0, UiTheme.INK, true)
	UiTheme.draw_round_rect(self, box, p.color, 22)
	var mini := Rect2(box.position.x + 26, box.position.y + 22, box.size.x - 52, 92)
	UiTheme.draw_round_rect(self, mini.grow(4), UiTheme.INK, 18)
	UiTheme.draw_round_rect(self, mini, UiTheme.CHIP_DARK, 14)
	var text := "--.--"
	var color := UiTheme.MUTED
	if has_stopped(pid):
		color = UiTheme.ACCENT
		text = "??.??" if is_blackout() else format_time(stop_time(pid))
	_draw_lcd_text(text, mini.get_center(), MINI_DIGIT_SIZE, color)

	# Etiqueta 1P–4P + nombre (no depender solo del color).
	var line_y := mini.end.y + 44
	var tag := UiTheme.player_tag(p.slot)
	var tag_rect := Rect2(box.position.x + 22, line_y - 22, 64, 44)
	UiTheme.draw_round_rect(self, tag_rect, UiTheme.INK, 14)
	UiTheme.draw_text(self, tag, tag_rect.get_center(), 28, UiTheme.PAPER)
	var name_x := tag_rect.end.x + 14
	UiTheme.draw_text_left(self, p.name, Vector2(name_x, line_y), 32, UiTheme.INK, box.end.x - 20 - name_x)

	# Al revelar: cuánto se pasó o le faltó.
	if is_revealing():
		var pill := Rect2(box.get_center().x - 90, box.end.y - 56, 180, 44)
		UiTheme.draw_round_rect(self, pill, UiTheme.INK, 22)
		UiTheme.draw_text(self, "%+.2f s" % (stop_time(pid) - TARGET), pill.get_center(), 30, UiTheme.PAPER)

	# La mascota va parada sobre su cajita (se dibuja después para quedar encima).
	PlayerAvatar.draw_mascot(self, feet, MASCOT_SCALE, p.color, p.slot, mood, 0.0, hop)
	if mood == PlayerAvatar.Mood.HAPPY:
		UiTheme.draw_star(self, feet + Vector2(62, -150), 26)

