# Cómo agregar un minijuego

Ejemplo: **"Esquivar"**, 1–4 jugadores, joystick, caen bloques y pierde el que toca uno.
El juego ya existe completo en `host/minigames/dodge/dodge.gd`; abajo va una versión
resumida para ver la forma de un minijuego.

## 1. Crear la carpeta y el script

`host/minigames/dodge/dodge.gd` (resumido):

```gdscript
extends MiniGame

var _pos: Dictionary = {}
var _axis: Dictionary = {}
var _survived: Dictionary = {}   # player_id -> segundos en pie
var _time_left := 45.0

static func get_info() -> Dictionary:
	return {
		"id": "dodge",                    # único, en minúsculas
		"title": "Esquivar",
		"description": "Esquivá los bloques que caen.",
		"min_players": 1,
		"max_players": 4,
		"layout": Protocol.LAYOUT_JOYSTICK,   # uno de Protocol.LAYOUTS
		"layout_data": {},
		"accent": UiTheme.BRICKS[0],      # opcional: color de la tarjeta en el lobby
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
	# ... mover, hacer caer bloques, detectar choques ...
	# Al terminar, UNA sola vez (los que siguen en pie ganan):
	# finish({"winners": en_pie, "scores": _survived, "summary": "Último en pie gana"})
	queue_redraw()

func _draw() -> void:
	draw_sky()                                        # fondo común
	draw_play_field(Rect2(160, 140, 1600, 860))       # piso con marco de bloques
	for p in players:
		PlayerAvatar.draw_mascot(self, _pos[p.id], 0.8, p.color, p.slot)
	draw_hud(_survived, clock_text(_time_left))     # marcador superior [1P 12] [0:28]
```

Todo el dibujo sale del sistema visual (`UiTheme`): sin colores sueltos. Ver `.claude/skills/diseno-tv/`.

Rendimiento (ver `docs/PERFORMANCE.md`): `draw_sky()`, `draw_play_field()` y `draw_hud()` están cacheados en capas propias y no cuestan nada si no cambian. Llamá `draw_sky()`/`draw_play_field()` al **principio** de `_draw()` (quedan siempre detrás de todo) y `draw_hud()` una vez por `_draw()` (queda siempre delante). Para varias figuras seguidas usá `UiTheme.ShapeBatch`. Medí el juego nuevo con `tools/benchmark.gd -- --only=<id>`.

## 2. Registrarlo

En `host/minigames/registry.gd`:

```gdscript
const GAMES: Array[Script] = [
	...,
	preload("res://host/minigames/dodge/dodge.gd"),
]
```

Listo: aparece como tarjeta en el lobby, se puede elegir para la competencia y se habilita cuando la cantidad de jugadores elegida está en su rango.

## 3. Generar su miniatura

La tarjeta del lobby y la intro "¿Cómo se juega?" muestran una foto real del juego: `assets/thumbs/<id>.webp` (640×360). La genera una herramienta que corre el juego con jugadores de prueba y guarda un recorte sin el marcador:

```bash
xvfb-run -a -s "-screen 0 1920x1080x24" godot --path . --rendering-driver opengl3 \
  --audio-driver Dummy -s res://tools/make_thumbnails.gd -- --only=dodge
godot --headless --path . --import      # para que Godot tome el archivo nuevo
```

Sin `--only` regenera todas (hacelo si cambiás el dibujo de un juego). Mirá el resultado: la tarjeta muestra solo la franja del medio (≈ 2,8:1) y chica, así que conviene un primer plano con los jugadores en acción. Para elegir el encuadre, `-- --only=<id> --full --out=/tmp/thumbs` guarda también la TV entera; después agregá una entrada en `SHOTS` de `tools/make_thumbnails.gd` (segundos de juego, recorte y cómo juegan los jugadores de prueba). Sin entrada usa un recorte del centro del campo estándar.

Mientras no tenga miniatura, la tarjeta usa un dibujo genérico con el ícono del control, pero `test_games_have_thumbnails` falla y dice el comando para generarla.

## Sonido y vibración

Una línea por evento, sin archivos de audio (ver `core/audio/sfx.gd`):

```gdscript
play_sfx("point")                 # suena en la TV
notify_player(pid, "point")       # vibra y suena en el celular de ese jugador
notify_all("go")                  # en todos los celulares
tick_countdown(antes, despues)    # "3, 2, 1, ¡YA!" con sonido y vibración
```

*Ejemplo:* en Arena, al juntar una estrella: `play_sfx("point")` y `notify_player(pid, "point")`. Tipos válidos para el celular: `Protocol.FEEDBACK_KINDS`.

## Cómo entra en la competencia

El juego **solo reporta su puntaje propio** en `finish(...)`. El modo competencia lo convierte en puestos y puntos (1° 100 · 2° 70 · 3° 50 · 4° 30) y arma el resumen de ronda.

*Ejemplo:* `finish(result_from_scores({1: 12, 2: 9, 3: 9}))` → Pablo 1° (+100), Sofi y Tomi 2° (+70). Si el juego es "gana el primero en llegar", pasar `winners` explícitos: ese jugador queda 1° aunque otro tenga más puntaje.

## 4. Correr los tests

```bash
godot --headless --path . -s res://tests/run_tests.gd
```
`test_registry_games_are_valid` y `test_games_run_headless` verifican automáticamente que el juego nuevo tenga metadatos válidos y que corra 30 frames con inputs aleatorios sin romperse; `test_games_have_thumbnails`, que tenga su miniatura.

## Reglas

- **Nunca confiar en el control:** usar solo `input.axis` y `input.btn`. Si el juego necesita límites propios (ej. toques por segundo), aplicarlos en el juego (ver `tap_race.gd`).
- **Desconexiones:** `on_player_disconnected` por defecto manda input neutro. No pausar el juego.
- **Nombres:** mostrarlos con `draw_string` o `Label`, nunca en `RichTextLabel` con BBCode.
- **Resolución lógica:** 1920×1080 (`SCREEN`). Dejar márgenes: algunas TVs recortan los bordes (*overscan*).
- **Un layout nuevo** (ej. dos botones) requiere: constante en `Protocol`, control en `controller/layouts/`, caso en `ControllerMain._on_layout_changed`, y actualizar `PROTOCOL.md`. Eso sí obliga a actualizar la app del celular.
