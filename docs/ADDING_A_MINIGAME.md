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
	# Globito 1P–4P sobre cada mascota y nombre abajo (todos juntos: menos draw calls).
	draw_player_tags(players.map(func(p: Dictionary) -> Array: return [p, _pos[p.id], 0.8]))
	draw_hud(_survived, clock_text(_time_left))     # marcador: [1P mascota 12] [reloj 0:28] ...
```

Todo el dibujo sale del sistema visual (`UiTheme`): sin colores sueltos. Ver `.claude/skills/diseno-tv/`.
El arte común de los juegos (escenario desenfocado, tablero con volumen, marcador con mascotas, globito
1P–4P, brillo de premios) está en `host/minigames/game_art.gd` (`GameArt`, ver [ADR 0009](adr/0009-arte-de-los-juegos.md)): usá
`GameArt.TriBatch` para tus figuras (un draw call por lote) y `GameArt.add_glow` para lo que brilla.

Rendimiento (ver `docs/PERFORMANCE.md`): `draw_sky()`, `draw_play_field()` y `draw_hud()` están cacheados en capas propias y no cuestan nada si no cambian. Llamá `draw_sky()`/`draw_play_field()` al **principio** de `_draw()` (quedan siempre detrás de todo) y `draw_hud()` una vez por `_draw()` (queda siempre delante). Lo que no cambia en toda la partida (una mesa, paneles, carteles) va en `draw_static(_draw_mesa)`, con `func _draw_mesa(ci: CanvasItem)` dibujando en `ci`: se dibuja una sola vez, detrás de lo demás (pasale un método, no una `func` anónima: una nueva en cada frame no se cachea). Para varias figuras seguidas usá `GameArt.TriBatch` (o `UiTheme.ShapeBatch`). Medí el juego nuevo con `tools/benchmark.gd -- --only=<id>`.

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

### Diorama de la tarjeta (ADR 0018)

La tarjeta del lobby muestra, antes que la captura, un **diorama 3D** del juego (`assets/thumbs/diorama/<id>.webp`, 648×240): una escena chica de juguete como la de la maqueta. Un juego sin receta propia sale con la **genérica** (escenario redondo con baldosas de su `accent` y su control —joystick, botón o deslizador— como pieza grande), así que alcanza con correr:

```bash
xvfb-run -a -s "-screen 0 1920x1080x24" godot --path . --rendering-driver opengl3 \
  --audio-driver Dummy -s res://tools/make_dioramas.gd -- --only=dodge
godot --headless --path . --import
```

Para una escena propia, sumá una receta en `core/art3d/game_diorama.gd` (`RECIPES` y el `match` de `build`) con las piezas de ahí (`_round_stage`, `_tile_floor`, `_toy_block`, `_star`, `_mascot`, `_joystick`…). `test_games_have_dioramas` falla si falta el archivo y dice el comando.

## Tablero 2.5D horneado (ADR 0019)

Opcional, para juegos con tablero (hoy lo usa Pintar el piso). El tablero, su marco de bloques y los juguetes de alrededor son una escena 3D que se **hornea una vez** a una textura con una **cámara en perspectiva** (el tablero "se aleja", como en la maqueta); el juego se dibuja encima en 2D **proyectado con la misma cámara**. Las reglas no cambian: posiciones, choques y celdas siguen en las coordenadas planas de siempre (tu `FIELD`). Cuesta menos por cuadro que el tablero plano (ver [PERFORMANCE.md](PERFORMANCE.md#tablero-25d-horneado-adr-0019)).

Conceptos, con Pintar el piso:
- **Cámara en perspectiva**: lo lejano se ve más chico. La fila de atrás mide ~1360 px en pantalla y la de adelante ~1590.
- **Homografía** (`view.project(p)`): la fórmula que lleva un punto del plano del juego a la pantalla. *Ejemplo:* el centro de la baldosa (0, 0), que en el juego está en (257, 209), se dibuja en (309, 227).
- **Transformación del piso** (`view.floor_xform(p)`): cerca de un punto, la homografía es casi una transformación 2D común. Con ella se dibuja cualquier figura "acostada" en el piso (baldosa, sombra, marco) con las funciones de siempre.
- **Horneado**: renderizar una vez y guardar la imagen (en `user://board25d/`, se lee en ~45 ms las veces siguientes).

Pasos (ver `host/minigames/paint/paint.gd`):

```gdscript
static var _board_view: BoardView25D
var _v25 := false  # ¿Este cuadro se dibuja en 2.5D?

static func board_view() -> BoardView25D:  # La usa también tools/benchmark.gd (--board=both).
	if _board_view == null:
		_board_view = BoardView25D.make(FIELD, CELL, "mi_juego")  # "mi_juego": nombre de la receta/caché.
	return _board_view

static func prewarm_art(host: Node) -> void:  # El host la llama durante la intro.
	Board25DBaker.request(host, board_view())

func _draw() -> void:
	_v25 = draw_board_25d(board_view())  # false: sin render, horneando o falló -> plano
	if not _v25:
		draw_sky()
		draw_play_field(FIELD, CELL)
	# Lo acostado en el piso: con floor_xform (o cell_xform para una celda).
	# Lo parado (mascotas, premios): en _screen(p) y escalado por _depth(p),
	# de atrás hacia adelante; globitos con draw_player_tags([[p, _screen(pos), u * _depth(pos)]]).

func _screen(p: Vector2) -> Vector2:
	return board_view().project(p) if _v25 else p

func _depth(p: Vector2) -> float:
	return clampf(board_view().scale_at(p), UiTheme.BOARD25D_SCALE_MIN, UiTheme.BOARD25D_SCALE_MAX) if _v25 else 1.0
```

- **Todo lo que se dibuje sobre el piso se proyecta**: también los efectos (`juice().sparkles(_screen(p))`, `float_text`, confeti de `celebrate`). Las capas cacheadas propias (ej. filas de baldosas) se redibujan cuando cambia `_v25`.
- **Obstáculos**: si no se mueven en toda la partida podrían ir en la escena horneada (una receta propia en `Board25DScene`); si cambian (se rompen, aparecen), dibujalos en 2D: acostados con `floor_xform`, o parados como las mascotas.
- **Otro escenario** (arena redonda, mesa): sumá una receta en `core/art3d/board_scene_25d.gd` (`build` elige por `view.recipe`) y subí `Board25DBaker.VERSION` al cambiarla. Los colores y medidas van en `UiTheme` (`BOARD25D_*`).
- **Verificar**: `tools/board25d_preview.gd` (Pintar el piso en un estado fijo, con `--flat` para el antes y `--compare` para la comparación con la maqueta), `tools/capture_screens.gd` y `tools/benchmark.gd -- --only=<id> --board=both`. Sin pantalla (tests) el juego se dibuja plano: los tests de reglas no cambian.

## Sonido y vibración

Una línea por evento, sin archivos de audio (ver `core/audio/sfx.gd`):

```gdscript
play_sfx("point")                 # suena en la TV
notify_player(pid, "point")       # vibra y suena en el celular de ese jugador
notify_all("go")                  # en todos los celulares
tick_countdown(antes, despues)    # "3, 2, 1, ¡YA!" con sonido y vibración
```

*Ejemplo:* en Arena, al juntar una estrella: `play_sfx("point")` y `notify_player(pid, "point")`. Tipos válidos para el celular: `Protocol.FEEDBACK_KINDS`.

## Efectos ("juice")

Que cada acción se *sienta*: partículas, números que saltan, un temblor leve. Sin tocar reglas ni puntajes (ver [ADR 0011](adr/0011-efectos.md)):

```gdscript
juice().sparkles(pos)                           # estrellitas (también shine, dust, sparks, confetti, splash)
juice().float_text("+1", cabeza, p.color)       # número flotante del color del jugador
juice().stop_dust(pid, axis.length(), pies)     # polvo al frenar de golpe (llamar en cada paso)
juice().shake(0.8)                              # sacudida leve en golpes grandes
juice().zoom_punch(pos)                         # zoom sutil hacia un punto
hit_stop()                                      # pausa de impacto (50–80 ms) en el golpe…
if hit_stopped(delta): return                   # …y esto al principio de _physics_process
draw_countdown(_countdown)                      # "3, 2, 1, ¡YA!" con golpe de escala
finish_after(result, "¡Tiempo!", {pid: pies})   # cartel, confeti y festejo; después finished
```

*Ejemplo:* en Arena, al juntar una estrella: `juice().sparkles(estrella)`, `juice().shine(estrella)` y `juice().float_text("+1", pos + Vector2(0, -130), p.color)`; al llegar a 0:00, `finish_after(resultado, "¡Tiempo!", ganadores)` y, mientras `in_finale()`, nadie se mueve y los ganadores festejan (`is_celebrating(pid)`, `celebrate_hop(pid)`).

Todo respeta **"Reducir movimiento"** (`UiTheme.reduce_motion`, menú de pausa): sin sacudida ni zoom y menos partículas. Todas las partículas van en un draw call y la cámara no redibuja nada.

## Cómo entra en la competencia

El juego **solo reporta su puntaje propio** en `finish(...)`. El modo competencia lo convierte en puestos y puntos (1° 100 · 2° 70 · 3° 50 · 4° 30) y arma el resumen de ronda.

*Ejemplo:* `finish(result_from_scores({1: 12, 2: 9, 3: 9}))` → Pablo 1° (+100), Sofi y Tomi 2° (+70). Si el juego es "gana el primero en llegar", pasar `winners` explícitos: ese jugador queda 1° aunque otro tenga más puntaje.

## Bots (opcional)

Con bots, una persona sola puede jugar tu juego (ADR 0010). Sin hacer nada, el juego ya funciona con bots: el `Bot` base manda entradas suaves al azar según el control. Para que jueguen **bien**:

1. En el juego, `bot_view()`: el estado público que se ve en la TV (posiciones, pelota…), de solo lectura. Nada que una persona no pueda ver.
2. `host/bots/<id>_bot.gd` que `extends Bot` y sobrescribe `decide(view, delta) -> {axis, btn}`: qué haría una persona. Usá `aim_at`, `steer`, `predict`, `think_due` y `skill` de la base; la reacción, el error y el temblor ya los pone `Bot`.
3. Registrarlo en `BotDriver.GAME_BOTS`.

*Ejemplo:* el bot de Arena elige la estrella más cercana que nadie le va a ganar y hace `steer(yo, aim_at(estrella, yo))`. Nunca suma puntos: solo mueve el joystick.

Para ver si el juego está balanceado: `godot --headless --path . -s res://tools/simulate.gd -- --n=50 --games=<id>` (duración, puntajes y ventaja por lugar de salida).

## 4. Correr los tests

```bash
godot --headless --path . -s res://tests/run_tests.gd
```
`test_registry_games_are_valid` y `test_games_run_headless` verifican automáticamente que el juego nuevo tenga metadatos válidos y que corra 30 frames con inputs aleatorios sin romperse; `test_games_have_thumbnails`, que tenga su miniatura; `test_bots_play_every_game`, que 4 bots lo jueguen hasta el final (en las 3 dificultades) sin mandar nada fuera de rango. Si tu juego no termina solo (ej. espera que alguien haga algo concreto), ese test lo marca.

## Reglas

- **Nunca confiar en el control:** usar solo `input.axis` y `input.btn`. Si el juego necesita límites propios (ej. toques por segundo), aplicarlos en el juego (ver `tap_race.gd`).
- **Desconexiones:** `on_player_disconnected` por defecto manda input neutro. No pausar el juego.
- **Nombres:** mostrarlos con `draw_string` o `Label`, nunca en `RichTextLabel` con BBCode.
- **Resolución lógica:** 1920×1080 (`SCREEN`). Dejar márgenes: algunas TVs recortan los bordes (*overscan*).
- **Un layout nuevo** (ej. dos botones) requiere: constante en `Protocol`, control en `controller/layouts/`, caso en `ControllerMain._on_layout_changed`, y actualizar `PROTOCOL.md`. Eso sí obliga a actualizar la app del celular.
  Checklist completo: skill `nuevo-layout`. Ejemplo: `joystick_ab` ([ADR 0014](adr/0014-layout-joystick-ab.md)), que subió `VERSION` a 2.
- **Joystick + botones A y B** (`Protocol.LAYOUT_JOYSTICK_AB`): moverse y hacer una acción a la vez (patear, saltar). `layout_data` opcional `{"a": "Patear", "b": "Saltar"}` pone un texto debajo de cada botón. Para los botones, `track_buttons` devuelve lo que se acaba de apretar (un toque = una acción) y `pressed_a`/`pressed_b` dicen qué está apretado:
  ```gdscript
  func on_input(player_id: int, input: Dictionary) -> void:
  	_dir[player_id] = input.axis
  	var down := track_buttons(player_id, input)
  	if down & Protocol.BTN_A:
  		_kick(player_id)
  	_blocking[player_id] = pressed_b(player_id)  # B sostenido = cubrirse
  ```
