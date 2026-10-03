class_name HoldButton
extends ToyButton
## Botón que hay que MANTENER apretado (UiTheme.PHONE_HOLD_SEC, 1 s) para que
## haga algo: el "Salir" del celular. Mientras se mantiene, un anillo de
## progreso se llena alrededor del ícono y al completarse emite `held`. Si
## se suelta antes, el anillo vuelve a cero y emite `released_early` (para
## avisar "Mantené apretado para salir"). Así un toque sin querer con el
## pulgar no corta la partida.
##
## El aro gris (vacío) se ve siempre: anticipa que no es un toque común.
## Batería: _process corre solo mientras el dedo está apoyado.

signal held
signal released_early

var hold_sec := UiTheme.PHONE_HOLD_SEC
## 0..1: cuánto se mantuvo.
var progress := 0.0:
	set(v):
		progress = v
		queue_redraw()
var _holding := false
var _back: Tween


func _init(p_text: String = "", p_glyph: String = "", p_color: Color = UiTheme.PAPER, p_font_size: int = 34) -> void:
	super(p_text, p_glyph, p_color, p_font_size)
	button_down.connect(begin_hold)
	button_up.connect(end_hold)


func _ready() -> void:
	set_process(false)


func _notification(what: int) -> void:
	# Oculto o la app en segundo plano: se cancela sin contar como toque.
	if (what == NOTIFICATION_VISIBILITY_CHANGED or what == NOTIFICATION_APPLICATION_FOCUS_OUT) and _holding:
		_holding = false
		set_process(false)
		progress = 0.0


func is_holding() -> bool:
	return _holding


func begin_hold() -> void:
	if _back:
		_back.kill()
	_holding = true
	progress = 0.0
	set_process(true)
	Haptics.buzz("tap")


func end_hold() -> void:
	if not _holding:
		return
	_holding = false
	set_process(false)
	released_early.emit()
	if is_inside_tree():
		_back = create_tween()
		_back.tween_property(self, "progress", 0.0, 0.2).set_ease(Tween.EASE_OUT)
	else:
		progress = 0.0


## Suma tiempo mantenido (lo llama _process; los tests lo usan directo).
func advance(delta: float) -> void:
	if not _holding:
		return
	progress = minf(1.0, progress + delta / maxf(hold_sec, 0.01))
	if progress >= 1.0:
		_holding = false
		set_process(false)
		progress = 0.0
		Haptics.buzz("go")
		held.emit()


func _process(delta: float) -> void:
	advance(delta)


func _draw() -> void:
	super._draw()
	var r := icon_size * 0.78
	var w := maxf(5.0, icon_size * 0.14)
	draw_arc(icon_center, r, 0.0, TAU, 40, UiTheme.PHONE_SIGNAL_OFF, w, true)
	if progress > 0.0:
		draw_arc(icon_center, r, -PI / 2.0, -PI / 2.0 + TAU * progress, maxi(8, int(40 * progress)),
			UiTheme.PHONE_HOLD_RING, w * 1.3, true)
