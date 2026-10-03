class_name HelpFx
extends RefCounted
## Dibujo de la ayuda de los eliminados (docs/MODOS.md §11, ADR 0020): lo que
## se ve sobre el jugador ayudado. Funciones estáticas y aisladas: cada juego
## las llama desde su `_draw_help_fx()` (una línea en su _draw), así el
## dibujo del juego no cambia.
##
##   draw_bubble    Esquivar: burbuja celeste que envuelve a la mascota.
##   draw_lifebuoy  Empujones: salvavidas rojo y blanco a la altura de la panza.
##
## `feet`: pies de la mascota en pantalla (en 2.5D, ya proyectados); `u`: la
## escala con la que el juego dibuja esa mascota; `left01`: cuánto le queda
## a la ayuda (1 → 0; en los últimos segundos titila); `t`: reloj de
## animación del juego. Colores y medidas: tokens HELP_* de UiTheme.


## Opacidad del titileo del final (1 mientras falta mucho).
static func blink(left01: float, t: float) -> float:
	if left01 > UiTheme.HELP_BLINK_FROM or UiTheme.reduce_motion:
		return 1.0
	return 0.45 + 0.55 * absf(sin(t * 14.0))


## Todo en un lote (UiTheme.ShapeBatch): cada draw_arc con antialiasing son
## tres draw calls; así la burbuja o el salvavidas son uno.
static func draw_bubble(ci: CanvasItem, feet: Vector2, u: float, left01: float, t: float) -> void:
	var a := blink(left01, t)
	var wobble := 0.0 if UiTheme.reduce_motion else sin(t * 5.0) * 0.03
	var r := UiTheme.HELP_BUBBLE_R * u * (1.0 + wobble)
	var c := feet + Vector2(0, -UiTheme.HELP_BUBBLE_LIFT * u)
	var b := UiTheme.ShapeBatch.new()
	b.circle(c, r, Color(UiTheme.HELP_BUBBLE_FILL, UiTheme.HELP_BUBBLE_FILL.a * a))
	# Borde: fino entero y grueso en la parte que le queda (como un reloj).
	b.arc(c, r, 0.0, TAU, 48, Color(UiTheme.HELP_BUBBLE_RIM, 0.8 * a), 4.0 * u + 2.0)
	var left := clampf(left01, 0.0, 1.0)
	if left > 0.0:
		b.arc(c, r, -PI / 2.0, -PI / 2.0 + TAU * left, maxi(4, int(48 * left)), Color(UiTheme.HELP_BUBBLE_RIM, 0.95 * a), 7.0 * u + 1.0)
	# Brillos: un arco arriba a la izquierda y un puntito.
	var shine := Color(UiTheme.HELP_BUBBLE_SHINE, UiTheme.HELP_BUBBLE_SHINE.a * a)
	b.arc(c, r * 0.78, PI * 1.12, PI * 1.42, 12, shine, 6.0 * u + 1.0)
	b.circle(c + Vector2(r * 0.42, -r * 0.55), 5.0 * u + 1.0, shine)
	b.flush(ci)


static func draw_lifebuoy(ci: CanvasItem, feet: Vector2, u: float, left01: float, t: float) -> void:
	var a := blink(left01, t)
	var c := feet + Vector2(0, -UiTheme.HELP_BUOY_LIFT * u)
	var r := UiTheme.HELP_BUOY_R * u
	var w := UiTheme.HELP_BUOY_W * u
	# Anillo achatado: se dibuja como círculo con la escala vertical reducida.
	var b := UiTheme.ShapeBatch.new()
	b.arc(Vector2.ZERO, r, 0.0, TAU, 48, Color(UiTheme.INK, a), w + 8.0)
	const SEGMENTS := 8
	var spin := 0.0 if UiTheme.reduce_motion else t * 0.8
	for i in SEGMENTS:
		var col := UiTheme.HELP_BUOY_RED if i % 2 == 0 else UiTheme.HELP_BUOY_WHITE
		var a0 := spin + TAU * i / SEGMENTS
		b.arc(Vector2.ZERO, r, a0, a0 + TAU / SEGMENTS, 8, Color(col, a), w)
	b.arc(Vector2.ZERO, r + w * 0.18, PI * 1.15, PI * 1.6, 10, Color(UiTheme.HELP_BUBBLE_SHINE, 0.6 * a), w * 0.25)
	ci.draw_set_transform(c, 0.0, Vector2(1.0, UiTheme.HELP_BUOY_FLAT))
	b.flush(ci)
	ci.draw_set_transform(Vector2.ZERO)
	# Cuánto le queda: puntitos debajo (de 3 a 0).
	var dots := ceili(clampf(left01, 0.0, 1.0) * 3.0)
	var d := UiTheme.ShapeBatch.new()
	for i in dots:
		var p := c + Vector2((i - (dots - 1) / 2.0) * 16.0 * u, r * UiTheme.HELP_BUOY_FLAT + w * 0.5 + 12.0 * u)
		d.circle(p, 5.0 * u + 1.0, Color(UiTheme.HELP_BUOY_RED, a))
	d.flush(ci)
