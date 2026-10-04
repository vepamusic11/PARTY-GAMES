extends Bot
## Reloj exacto: frenar en 10.00 contando "en la cabeza".
##
## Mientras el cronómetro se ve, el bot lo lee. Cuando se apaga sigue con
## su reloj mental, que corre un poco más rápido o más lento que el real
## (como el de una persona): el fácil se equivoca ±0,4 s y el difícil ±0,06 s
## (desvío típico). Aprieta un poco antes para compensar su tiempo de reacción.

const DRIFT_EASY := 0.07     ## Desvío del ritmo del reloj mental (fracción).
const DRIFT_HARD := 0.008
const HOLD_SEC := 0.12       ## Cuánto mantiene apretado el botón.

var _mental := -1.0          # lo que cree que marca el reloj (-1 = todavía no corre)
var _rate := 1.0
var _pressed_at := -1.0


func _ready_bot() -> void:
	_rate = 1.0 + gauss(lerpf(DRIFT_EASY, DRIFT_HARD, skill))


func decide(view: Dictionary, delta: float) -> Dictionary:
	if view.is_empty():
		return idle()
	if _pressed_at >= 0.0:
		return {"axis": Vector2.ZERO, "btn": Protocol.BTN_A if time - _pressed_at < HOLD_SEC else 0}
	if not view.get("running", false):
		return idle()
	var shown: float = view.get("shown", -1.0)
	if shown >= 0.0:
		_mental = shown          # Lo ve: se sincroniza.
	elif _mental >= 0.0:
		_mental += delta * _rate  # Apagado: cuenta a su ritmo.
	else:
		return idle()
	if _mental >= float(view.get("target", 10.0)) - reaction:
		_pressed_at = time
		return {"axis": Vector2.ZERO, "btn": Protocol.BTN_A}
	return idle()
