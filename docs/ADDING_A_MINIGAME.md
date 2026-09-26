# Cómo agregar un minijuego

Ejemplo completo: **"Esquivar"**, 1–4 jugadores, joystick, caen bloques y pierde el que toca uno.

## 1. Crear la carpeta y el script

`host/minigames/dodge/dodge.gd`:

```gdscript
extends MiniGame

var _pos: Dictionary = {}
var _axis: Dictionary = {}
var _survived: Dictionary = {}   # player_id -> segundos en pie
var _time_left := 30.0

static func get_info() -> Dictionary:
	return {
		"id": "dodge",                    # único, en minúsculas
		"title": "Esquivar",
		"description": "Esquivá los bloques que caen.",
		"min_players": 1,
		"max_players": 4,
		"layout": Protocol.LAYOUT_JOYSTICK,   # uno de Protocol.LAYOUTS
		"layout_data": {},
		"accent": Color("#9B5DE5"),       # opcional: color de la tarjeta en el lobby
		"score_label": "segundos",        # opcional: "12 segundos" en el resumen
	}

func setup(p_players: Array[Dictionary]) -> void:
	super.setup(p_players)                # guarda self.players
	for p in players:
		_pos[p.id] = Vector2(300 + p.slot * 400, 900)
		_axis[p.id] = Vector2.ZERO

func on_input(player_id: int, input: Dictionary) -> void:
	if _axis.has(player_id):
		_axis[player_id] = input.axis     # ya validado y recortado

func _physics_process(delta: float) -> void:
	if is_finished():
		return
	# ... mover, detectar choques ...
	# Al terminar, UNA sola vez:
	# finish(result_from_scores(_survived, "Último en pie gana"))
	queue_redraw()

func _draw() -> void:
	draw_sky()                                        # fondo común
	draw_play_field(Rect2(160, 140, 1600, 860))       # piso con marco de bloques
	for p in players:
		PlayerAvatar.draw_mascot(self, _pos[p.id], 0.8, p.color, p.slot)
	draw_hud(_survived, clock_text(_time_left))     # marcador superior [1P 12] [0:28]
```

Todo el dibujo sale del sistema visual (`UiTheme`): sin colores sueltos. Ver `.claude/skills/diseno-tv/`.

## 2. Registrarlo

En `host/minigames/registry.gd`:

```gdscript
const GAMES: Array[Script] = [
	...,
	preload("res://host/minigames/dodge/dodge.gd"),
]
```

Listo: aparece como tarjeta en el lobby, se puede elegir para la competencia y se habilita cuando la cantidad de jugadores elegida está en su rango.

## Cómo entra en la competencia

El juego **solo reporta su puntaje propio** en `finish(...)`. El modo competencia lo convierte en puestos y puntos (1° 100 · 2° 70 · 3° 50 · 4° 30) y arma el resumen de ronda.

*Ejemplo:* `finish(result_from_scores({1: 12, 2: 9, 3: 9}))` → Pablo 1° (+100), Sofi y Tomi 2° (+70). Si el juego es "gana el primero en llegar", pasar `winners` explícitos: ese jugador queda 1° aunque otro tenga más puntaje.

## 3. Correr los tests

```bash
godot --headless --path . -s res://tests/run_tests.gd
```
`test_registry_games_are_valid` y `test_games_run_headless` verifican automáticamente que el juego nuevo tenga metadatos válidos y que corra 30 frames con inputs aleatorios sin romperse.

## Reglas

- **Nunca confiar en el control:** usar solo `input.axis` y `input.btn`. Si el juego necesita límites propios (ej. toques por segundo), aplicarlos en el juego (ver `tap_race.gd`).
- **Desconexiones:** `on_player_disconnected` por defecto manda input neutro. No pausar el juego.
- **Nombres:** mostrarlos con `draw_string` o `Label`, nunca en `RichTextLabel` con BBCode.
- **Resolución lógica:** 1920×1080 (`SCREEN`). Dejar márgenes: algunas TVs recortan los bordes (*overscan*).
- **Un layout nuevo** (ej. dos botones) requiere: constante en `Protocol`, control en `controller/layouts/`, caso en `ControllerMain._on_layout_changed`, y actualizar `PROTOCOL.md`. Eso sí obliga a actualizar la app del celular.
