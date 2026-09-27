class_name SignalIcon
extends Control
## Señal de la conexión con la TV, para todos: el ícono de Wi-Fi con 3
## barras (arcos). Buena: 3 barras verdes · lenta: 2 naranjas · mala: 1 roja
## · cortada: solo el punto, rojo y tachado. No depende solo del color: la
## cantidad de barras encendidas dice lo mismo.
##
## Se redibuja solo cuando cambia de nivel (no en cada frame).

const UNKNOWN := -1  ## Todavía no hay medición: 3 barras grises.
const LOST := 0
const BAD := 1
const SLOW := 2
const GOOD := 3

var level := UNKNOWN:
	set(v):
		if v != level:
			level = v
			queue_redraw()


func _init(p_size: float = 56.0) -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(p_size, p_size)
	size_flags_vertical = Control.SIZE_SHRINK_CENTER


## Nivel según la latencia (ida y vuelta, en ms).
static func level_for_ms(ms: float) -> int:
	if ms < 0.0:
		return UNKNOWN
	if ms <= ControllerMain.LATENCY_OK_MS:
		return GOOD
	return SLOW if ms <= ControllerMain.LATENCY_SLOW_MS else BAD


static func color_for(p_level: int) -> Color:
	match p_level:
		GOOD: return UiTheme.SUCCESS
		SLOW: return UiTheme.WARNING
		BAD, LOST: return UiTheme.DANGER
	return UiTheme.INK_SOFT


func _draw() -> void:
	var s := minf(size.x, size.y)
	var c := size / 2.0
	var lit := color_for(level)
	var w := maxf(4.0, s * 0.13)
	var base := c + Vector2(0, s * 0.36)
	draw_circle(base, s * 0.1, lit)
	var bars := 3 if level == UNKNOWN else level
	for i in 3:
		var r := s * (0.28 + 0.22 * i)
		draw_arc(base, r, -PI * 0.78, -PI * 0.22, 16, lit if i < bars else UiTheme.PHONE_SIGNAL_OFF, w, true)
	if level == LOST:
		draw_line(c + Vector2(-s, -s) * 0.42, c + Vector2(s, s) * 0.42, UiTheme.DANGER, w, true)
