class_name Juice
extends Node2D
## Efectos de respuesta ("juice") de los minijuegos: lo que hace que cada
## acción se SIENTA sin cambiar ninguna regla.
##
## Concepto — *juice*: responder a cada acción con más de lo estrictamente
## necesario (partículas, un número que salta, un temblor, un sonido), para
## que el jugador sienta que lo que hizo "pegó". Ejemplos en los juegos:
##   - Arena: al juntar una estrella, estrellitas + anillo de brillo + "+1"
##     del color del jugador.
##   - Esquivar: al ser alcanzado, pausa de impacto (hit-stop), sacudida leve
##     y estrellitas; los bloques levantan polvo al caer.
##   - Reloj exacto: al frenar, zoom sutil hacia tu cajita y chispas.
##   - Al terminar: "¡Tiempo!" con golpe de escala y confeti sobre los ganadores.
## Ver docs/adr/0011-efectos.md.
##
## Lo crea MiniGame la primera vez que un juego lo pide (`juice()`): un nodo
## hijo interno que queda delante de todo lo del juego. Tiene:
##   - `particles` (FxParticles): pool fijo, un draw call.
##   - números flotantes y cartel del final (se dibujan acá, solo mientras
##     se animan);
##   - la "cámara": sacudida y zoom se aplican al transform del juego entero
##     (no redibuja nada: mover un nodo es gratis).
## Con UiTheme.reduce_motion: sin sacudida, sin zoom, sin golpes de escala y
## con menos partículas. Sin nada que animar, apaga su _process.

const SCREEN := Vector2(1920, 1080)
const FLOAT_PILL_H := 50.0     ## Alto de la ficha de un texto flotante.
const MAX_POPUPS := 12         ## Tope de números flotantes a la vez (el más viejo se va).

var particles: FxParticles

var _game: Node2D                   # Nodo al que se le aplica la cámara (el juego).
var _shake_t := 0.0
var _shake_power := 0.0
var _zoom_t := -1.0                 # < 0: sin zoom
var _zoom_amount := 0.0
var _zoom_focus := SCREEN / 2.0
var _cam_active := false
var _popups: Array = []             # {text, pos, col, t}
var _banner: Dictionary = {}        # {text, pos, size, t}
var _speed: Dictionary = {}         # id -> velocidad 0..1 del frame anterior (polvo al frenar)
var _had_popups := false            # Había números en el frame anterior (hay que borrarlos).
var _pill := GameArt.TriBatch.new()
var _widths: Dictionary = {}        # texto -> ancho de su píldora


func _init(game: Node2D = null) -> void:
	_game = game
	name = "Juice"
	particles = FxParticles.new()
	particles.name = "Particles"
	add_child(particles)
	set_process(false)


# --- Cámara ---------------------------------------------------------------------

## Sacudida breve y leve (power 0..1; 1 = UiTheme.FX_SHAKE_MAX px). Una más
## fuerte reemplaza a la que está en curso; una más débil no la corta.
func shake(power: float = 1.0) -> void:
	if UiTheme.reduce_motion:
		return
	power = clampf(power, 0.0, 1.0)
	if power >= _shake_power * (_shake_t / UiTheme.DUR_SHAKE):
		_shake_power = power
		_shake_t = UiTheme.DUR_SHAKE
	_wake()


## Zoom sutil hacia `focus` que entra y sale (UiTheme.DUR_ZOOM).
func zoom_punch(focus: Vector2, amount: float = UiTheme.FX_ZOOM) -> void:
	if UiTheme.reduce_motion:
		return
	_zoom_focus = focus
	_zoom_amount = amount
	_zoom_t = 0.0
	_wake()


## Desplazamiento de la sacudida ahora (px). Cero sin sacudida o con
## "Reducir movimiento".
func shake_offset() -> Vector2:
	if _shake_t <= 0.0:
		return Vector2.ZERO
	var amp := UiTheme.FX_SHAKE_MAX * _shake_power * (_shake_t / UiTheme.DUR_SHAKE)
	# Dos senos de frecuencias distintas: tiembla sin repetirse ni quedar corrido.
	var t := UiTheme.DUR_SHAKE - _shake_t
	return Vector2(sin(t * 93.0), cos(t * 71.0)) * amp


## Transform que la cámara le pone al juego (identidad si no hay efecto).
func camera_transform() -> Transform2D:
	var off := shake_offset()
	var z := 1.0
	var focus := _zoom_focus
	if _zoom_t >= 0.0:
		# Entra rápido y sale suave: sube el primer 30 % y baja el resto.
		var k := _zoom_t / UiTheme.DUR_ZOOM
		var bump := k / 0.3 if k < 0.3 else 1.0 - (k - 0.3) / 0.7
		z += _zoom_amount * (1.0 - (1.0 - bump) * (1.0 - bump))
	if off != Vector2.ZERO:
		# Un poco de zoom tapa los bordes que la sacudida dejaría al descubierto.
		var cover := 1.0 + 2.2 * off.length() / SCREEN.y
		if cover > z:
			z = cover
			focus = SCREEN / 2.0
	if z == 1.0 and off == Vector2.ZERO:
		return Transform2D.IDENTITY
	return Transform2D(0.0, Vector2(z, z), 0.0, focus * (1.0 - z) + off)


# --- Textos ---------------------------------------------------------------------

## Número flotante ("+1", "+5"): píldora del color del jugador con el texto en
## su color legible (UiTheme.text_on), que salta, sube y se desvanece.
## `scale`: tamaño relativo (ej. la profundidad en un tablero 2.5D).
func float_text(text: String, pos: Vector2, col: Color, scale: float = 1.0) -> void:
	if _popups.size() >= MAX_POPUPS:
		_popups.pop_front()
	_popups.append({"text": text, "pos": pos, "col": col, "t": 0.0, "s": clampf(scale, 0.5, 1.5)})
	_wake()


## Cartel grande del final ("¡Tiempo!", "¡Meta!") con golpe de escala. Queda
## hasta que el juego termina (o hasta `clear_banner`).
func banner(text: String, pos: Vector2 = SCREEN / 2.0, size: int = UiTheme.FX_BANNER_SIZE) -> void:
	_banner = {"text": text, "pos": pos, "size": size, "t": 0.0}
	_wake()


func clear_banner() -> void:
	_banner = {}
	queue_redraw()


func has_banner() -> bool:
	return not _banner.is_empty()


# --- Recetas de partículas ----------------------------------------------------------

## Estrellitas que saltan para todos lados (juntar un premio, golpe).
func sparkles(pos: Vector2, col: Color = UiTheme.GOLD, count: int = 8, speed: float = 380.0) -> void:
	particles.burst(FxParticles.Kind.STAR, pos, count, col, speed, 13.0, 0.55, Vector2.ZERO, TAU, 0.0, 4.0)


## Anillo de brillo que se expande (brillo al juntar un premio).
func shine(pos: Vector2, radius: float = 70.0, col: Color = UiTheme.FX_SHINE) -> void:
	particles.emit(FxParticles.Kind.RING, pos, Vector2.ZERO, radius, 0.35, col)


## Polvo a los pies (frenar, aterrizar). `dir`: hacia dónde sale (ZERO = a los costados).
func dust(pos: Vector2, count: int = 4, dir: Vector2 = Vector2.ZERO, size: float = 13.0) -> void:
	if dir == Vector2.ZERO:
		particles.burst(FxParticles.Kind.PUFF, pos, count, UiTheme.FX_DUST, 140.0, size, 0.45, Vector2.RIGHT, TAU, -60.0, 6.0)
	else:
		particles.burst(FxParticles.Kind.PUFF, pos, count, UiTheme.FX_DUST, 160.0, size, 0.45, dir, 1.6, -60.0, 6.0)


## Chispas en una dirección (paleta, choque).
func sparks(pos: Vector2, dir: Vector2, col: Color = UiTheme.FX_SPARK, count: int = 8) -> void:
	particles.burst(FxParticles.Kind.SPARK, pos, count, col, 700.0, 10.0, 0.32, dir, 1.8, 0.0, 5.0)


## Confeti chico que salta hacia arriba y cae (festejo de un ganador).
func confetti(pos: Vector2, count: int = 26) -> void:
	var n := count
	if UiTheme.reduce_motion:
		n = maxi(1, roundi(count * UiTheme.FX_REDUCED))
	for i in n:
		var v := Vector2.from_angle(-PI / 2.0 + particles.rng.randf_range(-0.9, 0.9)) * particles.rng.randf_range(260.0, 620.0)
		particles.emit(FxParticles.Kind.CONFETTI, pos, v, particles.rng.randf_range(8.0, 12.0), particles.rng.randf_range(1.0, 1.4),
			UiTheme.BRICKS[i % UiTheme.BRICKS.size()], 900.0, 1.6, particles.rng.randf_range(-9.0, 9.0), particles.rng.randf() * TAU)


## Chapuzón: gotas que saltan y caen y una onda en el agua.
func splash(pos: Vector2) -> void:
	particles.burst(FxParticles.Kind.DOT, pos, 10, UiTheme.FX_WATER, 420.0, 9.0, 0.6, Vector2.UP, 2.4, 1100.0, 0.5)
	particles.emit(FxParticles.Kind.RING, pos, Vector2.ZERO, 90.0, 0.5, UiTheme.FX_WATER)


## Polvo al frenar de golpe: llamar en cada paso con la velocidad del jugador
## (0..1). Si venía rápido y casi se detuvo, levanta polvo a sus pies.
func stop_dust(id: int, speed01: float, feet: Vector2) -> void:
	var before := float(_speed.get(id, 0.0))
	_speed[id] = speed01
	if before > 0.7 and speed01 < 0.15:
		dust(feet, 4)


# --- Ciclo ------------------------------------------------------------------------

func _wake() -> void:
	if not is_processing():
		set_process(true)


func _process(delta: float) -> void:
	_shake_t = maxf(_shake_t - delta, 0.0)
	if _zoom_t >= 0.0:
		_zoom_t += delta
		if _zoom_t >= UiTheme.DUR_ZOOM:
			_zoom_t = -1.0
	_apply_camera()
	var redraw := false
	for p in _popups:
		p.t += delta
		redraw = true
	if not _popups.is_empty() and float(_popups[0].t) >= UiTheme.DUR_FLOAT:
		_popups = _popups.filter(func(p: Dictionary) -> bool: return float(p.t) < UiTheme.DUR_FLOAT)
	if not _banner.is_empty():
		var before := float(_banner.t)
		_banner.t = before + delta
		redraw = redraw or before < UiTheme.DUR_POP  # Después del golpe queda quieto.
	if redraw or (_popups.is_empty() and _had_popups):
		queue_redraw()
	_had_popups = not _popups.is_empty()
	if not redraw and not _cam_active and _shake_t <= 0.0 and _zoom_t < 0.0:
		set_process(false)


func _apply_camera() -> void:
	if _game == null:
		return
	var xf := camera_transform()
	if xf != Transform2D.IDENTITY or _cam_active:
		_game.transform = xf
		# El marcador no tiembla ni se agranda: se lee siempre en el mismo lugar.
		var hud: Node2D = _game._hud if _game is MiniGame else null
		if hud != null:
			hud.transform = xf.affine_inverse()
	_cam_active = xf != Transform2D.IDENTITY


func _draw() -> void:
	if not _popups.is_empty():
		_draw_popups()
	if not _banner.is_empty():
		var s := UiTheme.pop_scale(float(_banner.t))
		var pos: Vector2 = _banner.pos
		draw_set_transform(pos, 0.0, Vector2(s, s))
		UiTheme.draw_text(self, str(_banner.text), Vector2.ZERO, int(_banner.size), UiTheme.ACCENT, 22, UiTheme.INK)
		draw_set_transform(Vector2.ZERO)


## Fichas de todos los textos en un lote (un draw call) y después los textos.
## La ficha de cada texto se arma una vez (tamaño fijo, GameArt la guarda) y
## el golpe de escala va en el Transform2D: nada se recalcula por frame.
## Es una ficha de juguete como las del código del lobby (color pleno, canto
## oscuro abajo, contorno de tinta y un reflejo chico), no una píldora
## brillante: chica, no tapa el juego y es de la misma familia que el lobby.
func _draw_popups() -> void:
	var boxes: Array = []
	for p in _popups:
		var t: float = p.t
		var k := t / UiTheme.DUR_FLOAT
		var s := UiTheme.pop_scale(t, 0.25) * float(p.get("s", 1.0))
		var a := clampf((1.0 - k) / 0.35, 0.0, 1.0)  # Se desvanece en el último tercio.
		var rise := UiTheme.FX_FLOAT_RISE * (1.0 - (1.0 - k) * (1.0 - k))
		var c: Vector2 = (p.pos as Vector2) - Vector2(0, rise)
		var size := Vector2(_text_width(str(p.text)), FLOAT_PILL_H)
		var xf := Transform2D(0.0, Vector2(s, s), 0.0, c)
		var col: Color = p.col
		var r := size.y * 0.3
		var lip := UiTheme.TOY_DEPTH * 0.6
		var ink := size + Vector2(8.0, 8.0 + lip)
		_pill.shape(GameArt.round_rect_tris(ink, r + 4.0), xf * Transform2D(0.0, Vector2(0, lip / 2.0)), Color(UiTheme.INK, a))
		_pill.shape(GameArt.round_rect_tris(size, r), xf * Transform2D(0.0, Vector2(0, lip)), Color(col.darkened(UiTheme.TOY_LIP_SHADE), a))
		_pill.shape(GameArt.round_rect_tris(size, r), xf, Color(col, a))
		var spec := Vector2(minf(size.x * 0.2, 40.0), size.y * 0.12)
		_pill.shape(GameArt.round_rect_tris(spec, spec.y / 2.0),
			xf * Transform2D(0.0, Vector2(-size.x / 2.0 + r * 0.6 + spec.x / 2.0, -size.y * 0.32)), Color(UiTheme.TOY_SPEC, UiTheme.TOY_SPEC.a * a))
		boxes.append([c, s, a, col, str(p.text)])
	_pill.flush(self)
	for b: Array in boxes:
		draw_set_transform(b[0], 0.0, Vector2(b[1], b[1]))
		var fg := UiTheme.text_on(b[3])
		var edge := UiTheme.INK if fg == UiTheme.PAPER else UiTheme.PAPER
		UiTheme.draw_text(self, b[4], Vector2(0, -1), UiTheme.FX_FLOAT_SIZE, Color(fg, b[2]), 5, Color(edge, b[2]))
	draw_set_transform(Vector2.ZERO)


## Ancho de la píldora de un texto (se mide una vez por texto).
func _text_width(text: String) -> float:
	if not _widths.has(text):
		_widths[text] = UiTheme.FONT_BOLD.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, UiTheme.FX_FLOAT_SIZE).x + 30.0
	return _widths[text]
