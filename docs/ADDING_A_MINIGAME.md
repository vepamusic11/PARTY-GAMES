# Cómo agregar un minijuego

Ejemplo completo: **"Esquivar"**, 1–4 jugadores, joystick, caen bloques y pierde el que toca uno.

## 1. Crear la carpeta y el script

`host/minigames/dodge/dodge.gd`:

```gdscript
extends MiniGame

var _pos: Dictionary = {}
var _axis: Dictionary = {}

static func get_info() -> Dictionary:
	return {
		"id": "dodge",                    # único, en minúsculas
		"title": "Esquivar",
		"description": "Esquivá los bloques que caen.",
		"min_players": 1,
		"max_players": 4,
		"layout": Protocol.LAYOUT_JOYSTICK,   # uno de Protocol.LAYOUTS
		"layout_data": {},
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
	# finish(result_from_scores(puntajes, "Último en pie gana"))
	queue_redraw()

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, SCREEN), Color("#1b1b2f"))
	for p in players:
		draw_circle(_pos[p.id], 30, p.color)
```

## 2. Registrarlo

En `host/minigames/registry.gd`:

```gdscript
const GAMES: Array[Script] = [
	...,
	preload("res://host/minigames/dodge/dodge.gd"),
]
```

Listo: aparece en el lobby y se habilita cuando hay la cantidad de jugadores correcta.

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
