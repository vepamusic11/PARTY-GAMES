extends Bot
## Carrera de toques: tocar el botón a un ritmo humano.
##
## Cada toque es apretar y soltar (el juego cuenta flancos de subida). El
## ritmo depende de la dificultad (≈ 5,5 toques/s el fácil, 10 el difícil;
## el juego corta en 14) y varía un poco, como un dedo que se cansa y se
## recupera. Arranca con la cuenta regresiva: su tiempo de reacción hace el resto.

const RATE_EASY := 5.5
const RATE_HARD := 10.0

var _phase := 0.0
var _rate := 7.0


func _ready_bot() -> void:
	_rate = lerpf(RATE_EASY, RATE_HARD, skill) * rng.randf_range(0.92, 1.08)


func decide(view: Dictionary, delta: float) -> Dictionary:
	if view.is_empty() or float(view.get("countdown", 0.0)) > 0.0:
		return idle()
	# Ritmo con un vaivén suave (±10 %) y algo de azar en cada toque.
	var rate := _rate * (1.0 + 0.1 * sin(time * 1.3 + slot)) * (1.0 + gauss(noise * 0.5))
	_phase += delta * maxf(rate, 1.0)
	return {"axis": Vector2.ZERO, "btn": Protocol.BTN_A if fposmod(_phase, 1.0) < 0.5 else 0}
