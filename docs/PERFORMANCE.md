# Rendimiento

Objetivo del producto: **60 fps estables en una Google TV / Chromecast de gama baja** (CPU tipo Cortex-A55, GPU Mali-G31) y **poco consumo de batería en el celular**. Este documento explica cómo medir, qué se optimizó y qué presupuestos respetar al agregar pantallas o juegos.

La decisión de arquitectura está en [ADR 0006](adr/0006-rendimiento-capas-cacheadas.md).

## Cómo medir

`tools/benchmark.gd` arma cada pantalla con render real, la deja correr N frames con jugadores e inputs simulados y mide cada frame:

```bash
# Tabla en la terminal (necesita pantalla: con --headless Godot no dibuja)
xvfb-run -a -s "-screen 0 1920x1080x24" godot --path . --rendering-driver opengl3 \
  --audio-driver Dummy -s res://tools/benchmark.gd

# Opciones (después de --):
#   --frames=600            frames medidos por escena (default 300, más 45 de calentamiento)
#   --only=lobby,dodge      solo algunas escenas
#   --json=/tmp/bench.json  además guarda los resultados en JSON (para comparar)
#   --no-audio              sin música ni efectos (por defecto suenan, como en la TV)
#   --mascots=both          cada escena con mascotas 2D y 3D horneadas, intercaladas (también 2d o 3d; default 3d)
```

Por defecto el benchmark agrega `Sfx` y `Music` como la TV: cada escena cambia de pista (fundido cruzado durante el calentamiento) y un `go` por segundo dispara el *ducking*. El presupuesto del audio es **≤ 0,3 ms de p95 de Scripts** frente a `--no-audio` ([ADR 0015](adr/0015-musica-y-mezcla.md)); el OGG se decodifica en el hilo de audio y no cuenta en Scripts.

Escenas: `lobby` (4 jugadores), `game_intro` ("¿Cómo se juega?"), `round_summary`, `final` (podio con confeti), **cada juego del registry** con su máximo de jugadores (hasta 4) e inputs que cambian todo el tiempo (si un juego termina antes de juntar los frames, se reinicia), y el celular a 2340×1080: `ctrl_join`, `ctrl_wait` y `ctrl_joy`. Un juego nuevo en el registry entra solo. Los juegos que cambian mucho con el tiempo se miden además adelantados (`LATE_SCENES` en el script): `sumo_tarde` es Empujones a los 20 s, con la isla achicándose (con `--only=sumo` se miden las dos).

El benchmark corre con tope de 60 fps y sin vsync (como la TV): cada frame tiene un paso de física, igual que en el aparato. Usa los puertos de red solo el celular (descubrimiento UDP); si corrés varias instancias de Godot en paralelo, serializalas (ej. `flock /tmp/party-games-godot.lock …`).

### Qué significa cada columna

| Columna | Qué mide |
|---|---|
| **Scripts** (prom. y p95) | CPU de la escena sin el render: desde que empieza el frame (física) hasta `frame_pre_draw`. Incluye `_physics_process`, `_process`, los `_draw()` de GDScript, el layout de los Controls y los tweens. **Es el número a vigilar**: es lo que más se parece a lo que gasta la CPU de la TV. |
| Proceso | `Performance.TIME_PROCESS`. En Godot 4 incluye además el envío del render (`RenderingServer.draw`), así que en xvfb lo domina la GPU por software (llvmpipe) y casi no cambia con las optimizaciones de scripts. |
| Física | `Performance.TIME_PHYSICS_PROCESS`. Ojo: los juegos piden `queue_redraw()` en `_physics_process`, y Godot vacía la cola de llamadas diferidas al final de cada paso de física, así que el `_draw()` de los juegos cae acá. |
| Render | `frame_pre_draw` → `frame_post_draw`: render de Godot + driver. En xvfb es rasterización por software (lenta, depende del área pintada): sirve para comparar, no como valor absoluto. |
| Frame | Tiempo entre frames (lo que ve el jugador; tope 16,7 ms). |
| Draw calls | `Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME`. En una GPU móvil cada draw call cuesta CPU del driver. |
| Objetos | `Performance.OBJECT_COUNT` (sirve para detectar fugas: no debería crecer). |
| Dibujos/s | Frames que realmente se dibujaron por segundo. Con el modo de bajo consumo del celular, lo que no cambia no se redibuja. |

Los tiempos absolutos dependen de la máquina: compará **siempre antes y después en la misma máquina** (guardá la línea base con `--json`).

## Antes y después

Medido en el contenedor de desarrollo (x86, Godot 4.4.1, `opengl3` sobre llvmpipe en xvfb), 300 frames por escena, el mismo benchmark sobre la punta sin este cambio (`f321a10`) y con este cambio:

| Escena | Scripts prom. (ms) | Scripts p95 (ms) | Draw calls | TIME_PROCESS prom. (ms) | Dibujos/s |
|---|---:|---:|---:|---:|---:|
| lobby | 3,92 → **1,75** (−55 %) | 5,08 → 2,30 | 790 → **520** (−34 %) | 63,3 → 67,0 | 19 → 18 |
| game_intro | 3,92 → **1,79** (−54 %) | 4,67 → 2,20 | 623 → **457** (−27 %) | 56,6 → 61,4 | 20 → 21 |
| round_summary | 4,00 → **1,65** (−59 %) | 5,42 → 2,39 | 633 → **452** (−29 %) | 57,6 → 56,4 | 21 → 21 |
| final | 3,81 → **1,68** (−56 %) | 5,23 → 2,23 | 526 → **370** (−30 %) | 47,0 → 50,2 | 26 → 24 |
| arena | 2,87 → **2,00** (−30 %) | 4,27 → 2,80 | 160 → **70** (−56 %) | 41,9 → 36,9 | 32 → 33 |
| pingpong | 1,47 → **1,06** (−28 %) | 2,23 → 1,57 | 91 → **51** (−44 %) | 28,8 → 27,9 | 40 → 42 |
| tap_race | 2,72 → **1,94** (−29 %) | 4,09 → 2,96 | 153 → **74** (−52 %) | 32,9 → 33,4 | 33 → 35 |
| stop_clock | 3,45 → **2,38** (−31 %) | 4,74 → 3,70 | 170 → **91** (−47 %) | 36,5 → 34,7 | 32 → 33 |
| dodge | 3,03 → **2,05** (−32 %) | 3,97 → 2,92 | 159 → **84** (−47 %) | 37,3 → 36,8 | 31 → 33 |
| paint | 4,45 → **3,53** (−21 %) | 7,44 → 6,22 | 312 → **232** (−25 %) | 38,4 → 36,4 | 28 → 29 |
| sumo | 9,72 → **8,09** (−17 %) | 14,50 → 11,39 | 663 → **587** (−11 %) | 44,3 → 45,9 | 21 → 22 |
| ctrl_join | 0,57 → 0,62 | 0,75 → 0,83 | 77 → **49** (−36 %) | 39,1 → 41,2 | 34 → **30** |
| ctrl_wait | 1,08 → 1,08 | 1,47 → 1,33 | 140 → **86** (−39 %) | 34,7 → 33,5 | 44 → **30** |
| ctrl_joy | 0,87 → 0,78 | 1,20 → 0,99 | 95 → **53** (−44 %) | 31,7 → 29,8 | 46 → 47 |

Cómo leerla:

- **TV**: la CPU por frame bajó a menos de la mitad en las pantallas de menú (lobby, intro, resumen, podio) y ~30 % en los juegos que usan el campo y el marcador comunes; los draw calls, entre 25 % y 56 %. En xvfb los fps casi no cambian porque el cuello de botella es la GPU por software (TIME_PROCESS y Render); en la TV el render lo hace la GPU real y lo que limita es la CPU.
- **Juegos a menos de 60 fps**: en xvfb van a ~33 fps, así que hay 2 pasos de física por frame y el juego se dibuja dos veces. Por eso "Scripts" de los juegos está inflado acá; a 60 fps es más o menos la mitad.
- **Pintar el piso y Empujones** mejoraban menos porque la mayor parte de su dibujo es propio (baldosas pintadas, isla de bloques, agua con olas). Ver la sección siguiente: ahora también tienen capas propias.
- **Celular**: esperando (unirse, "¡Mirá la TV!", resultado) dibuja **30 veces por segundo en vez de 44–60**. El costo por frame dibujado es parecido, pero la CPU total por segundo baja ~30 % (1,08 ms × 44 ≈ 48 ms/s → 1,08 ms × 30 ≈ 32 ms/s) y la GPU trabaja un tercio menos. Con un control en pantalla (`ctrl_joy`) todo sigue a 60 fps: la latencia del input no cambia.

### Empujones y Pintar el piso

Medido después, con el mismo benchmark sobre `530a33d` (ya con todo lo de arriba) y con las capas propias de cada juego, corridas una detrás de la otra:

| Escena | Scripts prom. (ms) | Scripts p95 (ms) | Draw calls |
|---|---:|---:|---:|
| sumo | 8,75 → **3,13** (−64 %) | 12,18 → **4,31** | 585 → **133** (−77 %) |
| sumo_tarde (isla achicándose) | 7,93 → **3,60** (−55 %) | 11,68 → **4,89** | 571 → **130** (−77 %) |
| paint | 4,18 → **2,71** (−35 %) | 6,48 → **4,07** | 255 → **165** (−35 %) |

Los dos quedan dentro de lo pedido para la TV (p95 ≤ 8 ms en el benchmark y ≤ 150 draw calls en Empujones; Pintar el piso queda en ~165 porque cada fila de baldosas es un lote). Recordá que en xvfb los juegos corren a ~25–30 fps y se dibujan dos veces por frame: a 60 fps el costo por frame es más o menos la mitad.

**Empujones** (`host/minigames/sumo/sumo.gd`, sección "Capas"): seis nodos hijos con `show_behind_parent`, en el mismo orden en que se dibujaba todo antes:

| Capa | Qué dibuja | Cuándo se redibuja |
|---|---|---|
| `_water` | degradé del agua | nunca |
| `_waves` | ≈ 120 olas en **un** lote | nunca: la capa se mueve con `position.x` (el patrón se repite cada 180 px) |
| `_back` | los que caen por el lado de atrás (quedan detrás de la isla) | solo mientras alguien cae |
| `_island` | espuma, costado y tapa (4 círculos en un lote) | cada frame (la espuma late) |
| `_rings` | círculo blanco, anillos enteros y círculo de sumo | al perder un anillo o al temblar |
| `_edge` | anillo recortado por el borde y el borde | mientras la isla se achica o tiembla |

- Cada `draw_arc` con antialiasing son **3 draw calls**; `UiTheme.ShapeBatch.arc/polyline` arma la misma línea (tira central + bordes que se desvanecen, mismo algoritmo que el motor) dentro del lote. Se usa en lo que se redibuja poco (olas, anillos enteros). En lo que cambia en cada frame (borde que se achica, anillos de los jugadores) se deja `draw_arc` del motor: en C++ cuesta menos CPU que armarlo en GDScript.
- Los bloques de cada anillo van en lote como tiras de cuadriláteros (cubren los mismos píxeles que el polígono). Para respetar el orden bloque → costura → bloque…, el único bloque que tapa una costura ajena (el último, sobre la primera) se vuelve a dibujar después de ella: es opaco, así que queda igual.
- ~~El temblor no mueve las capas: cuando tiembla, las capas de la isla se redibujan con el desplazamiento (≈ 13 frames por golpe).~~ Desde [ADR 0011](adr/0011-efectos.md) el temblor es de cámara (`Juice.shake`: se mueve el nodo del juego entero) y las capas ya no se redibujan por un golpe.

**Pintar el piso** (`host/minigames/paint/paint.gd`, `_draw_tiles`): las baldosas quietas van en **una capa por fila** (11), que se redibuja solo cuando cambia alguna baldosa de esa fila; las que están "saltando" (recién pintadas, 0,18 s) se dibujan en `_draw` como antes. Con 4 jugadores se pintan decenas de baldosas por segundo: con una sola capa para todo el piso se redibujaba casi en cada frame; por fila, cada cambio redibuja 20 baldosas y no 220. Los puntos del patrón de 3P van en un lote por fila (antes eran 5 draw calls por baldosa).

Comparación visual: escenas deterministas de los dos juegos (estado fijo: cuenta regresiva; isla achicándose con temblor, efectos, uno cayendo y otro en la tribuna; final con la isla chica; piso con 140 baldosas, algunas saltando, power-up, brocha y velocidad; "¡Tiempo!"): **Pintar el piso 0 píxeles distintos**; **Empujones ≤ 3 píxeles de 2 millones con diferencia de 1/255** (redondeo de seno/coseno en el borde suavizado de los arcos). Las capturas de `capture_screens.gd` antes y después se ven iguales.

### Fondo de escenario, transición y confeti

Medido después, sobre `4d4997f`, antes y después del escenario desenfocado ([ADR 0008](adr/0008-fondo-escenario-desenfocado.md)), 300 frames por escena, corridas una detrás de la otra (la máquina tenía otras corridas en paralelo: diferencias de ±10 % son ruido):

| Escena | Scripts prom. (ms) | Scripts p95 (ms) | Draw calls | Render prom. (ms) |
|---|---:|---:|---:|---:|
| lobby | 2,12 → **1,64** | 2,68 → 2,08 | 599 → **418** | 65,2 → 42,2 |
| game_intro | 1,71 → **1,42** | 2,05 → 1,83 | 465 → **284** | 46,6 → 33,5 |
| round_summary | 1,70 → **1,58** | 2,23 → 2,32 | 460 → **279** | 44,7 → 34,2 |
| final (con confeti) | 1,74 → **1,39** | 2,29 → 1,84 | 376 → **195** | 42,5 → 28,9 |
| ctrl_join | 0,67 → **0,23** | 0,93 → 0,41 | 29 → 16 | 29,8 → 27,9 |
| ctrl_wait | 1,28 → **0,97** | 1,67 → 1,31 | 90 → 77 | 23,6 → 21,8 |
| ctrl_joy | 0,84 → **0,54** | 1,04 → 0,68 | 55 → 42 | 20,8 → 19,0 |

Los juegos no cambian (el fondo está oculto mientras se juega). El celular esperando sigue en 30 dibujos/s.

- **`PartyBackground`**: el escenario se pinta una vez en un `SubViewport` a media resolución, otro lo desenfoca una vez (`core/ui/shaders/soft_blur.gdshader`) y los dos quedan en `UPDATE_ONCE`. En pantalla: 1 `TextureRect` + 6 nubes y 9 brillos como `Sprite2D` (texturas hechas por código una vez por proceso). En cada frame solo cambian posición, escala y transparencia de esos nodos: no hay `_draw()` por frame (antes, cielo + 7 nubes en GDScript y ≈ 160 draw calls fijos de torres y bordes). También baja el render: un cuadro con textura en vez de cientos de figuras con mezcla alfa.
- **Celular**: sin escenario (ni SubViewport ni brillos): cielo liso que se dibuja una vez y nubes `Sprite2D` que se mueven a `anim_fps`.
- **`Transition`**: cada fila de bloques es un nodo que se dibuja una vez (un lote, 1 draw call) y durante el barrido solo se mueve; antes eran ≈ 290 comandos redibujados en cada frame.
- **`Confetti`**: todas las piezas (papelitos, estrellas, serpentinas, puntos, destellos) en **un** triangle array por frame; antes, un draw call por papelito. Cada tipo tiene una plantilla de puntos (las serpentinas, una por cuadro de su ondeo) que se transforma en C++; índices y colores se arman una vez en `burst()`.

### Arte de los juegos (ADR 0009)

Escenario desenfocado, tablero con volumen, marcador con mascotas, globito 1P–4P y brillo de premios (`host/minigames/game_art.gd`). Medido intercalando la punta sin el cambio (`c4f8755`) y con el cambio, dos corridas de cada uno una detrás de la otra (promedio de las dos); `lobby` no cambia y sirve de control del ruido de la máquina:

| Escena | Scripts prom. (ms) | Scripts p95 (ms) | Draw calls | Render (ms) |
|---|---:|---:|---:|---:|
| lobby (control) | 2,19 → 2,33 | 2,95 → 3,18 | 599 → 599 | 66,2 → 66,9 |
| arena | 2,73 → 2,92 | 3,83 → 4,28 | 78 → **66** | 29,0 → 28,3 |
| pingpong | 1,34 → 1,49 | 1,96 → 2,17 | 55 → 58 | 23,9 → 27,8 |
| tap_race | 2,61 → 2,71 | 3,69 → 3,89 | 82 → **68** | 28,1 → 28,9 |
| stop_clock | 3,11 → 3,08 | 4,22 → 4,56 | 99 → 97 | 28,8 → 34,7 |
| dodge | 3,04 → 3,24 | 4,40 → 4,62 | 88 → **80** | 30,4 → 29,4 |
| paint | 3,30 → 3,23 | 4,93 → 4,71 | 172 → **81** | 32,1 → 30,7 |
| sumo | 3,87 → 4,17 | 5,37 → 6,12 | 140 → 136 | 35,2 → 38,5 |
| sumo_tarde | 4,55 → 4,65 | 6,50 → 6,51 | 138 → 132 | 34,0 → 36,4 |

- Todo dentro del presupuesto (p95 ≤ 8 ms, ≤ 150 draw calls). Las diferencias de Scripts (−5 % a +14 % en p95) son del orden del ruido (el control varió +8 %).
- **Qué cuesta por frame**: los globitos 1P–4P y los nombres (≈ 75 µs para 4 jugadores; el globito se arma una vez por color y en cada frame solo se ubica) y el brillo de los premios (más barato que las estrellas de antes: formas y colores cacheados). Todo lo demás es fijo y va en capas cacheadas: escenario, tablero, píldoras del marcador (los números van en una capa hija, `_hud_text`), mesa de Ping Pong, paneles de Reloj exacto y tribunas de Empujones (`MiniGame.draw_static`).
- **Render en xvfb**: sube en los juegos sin tablero (Ping Pong, Reloj exacto: el escenario es una textura estirada a pantalla completa y llvmpipe paga cada muestra). Con tablero, el escenario se pinta solo alrededor y el piso no tiene capas que se tapen (cada baldosa es cara + labio + brillo sin superponerse; la junta va solo en las rendijas): queda igual o menos que antes. Una primera versión con baldosas y bloques redondeados (~36 triángulos cada uno) y una sombra `StyleBoxFlat` del tamaño del tablero duplicaba el render: ver [ADR 0009](adr/0009-arte-de-los-juegos.md).
- **Pintar el piso**: cada fila de baldosas es un lote de triángulos armado con la baldosa precalculada de cada jugador (`GameArt.tile_template`): 172 → 81 draw calls.

### Karts de mascotas

Medido con Empujones en la misma corrida como control (la máquina tenía varias corridas en paralelo: los tiempos absolutos salieron ~3× los de las tablas de arriba, con el juego a ~11 fps y varios pasos de física por frame). `karts_tarde` es la carrera a los 14 s (se midió con `LATE_SCENES` agregado en una copia local del benchmark):

| Escena | Scripts prom. (ms) | Scripts p95 (ms) | Draw calls |
|---|---:|---:|---:|
| sumo (control) | 12,05 | 18,64 | 94 |
| karts | 13,19 | 18,08 | **41** |
| karts_tarde | 15,15 | 20,84 | **39** |

- **CPU parecida a Empujones** (que en condiciones normales da p95 ≈ 6 ms): Karts debería quedar en el mismo rango, dentro de los 8 ms. La física son pasos fijos de 1/60 s (búsqueda local del tramo más cercano, ±8 puntos) y los centros de charcos y turbos se calculan una vez.
- **Draw calls: ~40.** Pasto, pista (bordes de bloques, asfalto, líneas, largada a cuadros), turbos, charcos, árboles y el marco van en **un** lote en la capa fija (`draw_static`); el escenario se pinta solo alrededor del tablero. Por frame: un lote por kart (sombra, ruedas, chasis de plantilla por color, llamas), la mascota y el asiento, los globitos 1P–4P y las flechas que se prenden en los turbos. Las pestañas de vuelta debajo del marcador son una capa propia que se redibuja solo cuando cambia alguna vuelta.

### Memoria de colores

`host/minigames/memory/memory.gd`, medido con `--only=memory,dodge,stop_clock` en la misma corrida (máquina cargada por otros procesos: sirve para comparar entre juegos, no como valor absoluto):

| Escena | Scripts prom. (ms) | Scripts p95 (ms) | Draw calls |
|---|---:|---:|---:|
| stop_clock (referencia) | 8,58 | 14,57 | 62 |
| dodge (referencia) | 9,01 | 13,70 | 42 |
| memory | 10,14 | 15,81 | **35** |

- Tablero, botones apagados, tarjetas y ayuda van en `draw_static` (un lote). Por frame: un lote con el botón encendido, el halo, el arco del tiempo y las fichas de todos; los botones de cada estado se arman una vez (`_pad_mesh`).
- Scripts ≈ +10 % sobre Esquivar por las cuatro mascotas más grandes (escala 1,5); dentro del ruido de la máquina.

### Efectos (ADR 0011)

Partículas en lote con pool fijo (`FxParticles`, un draw call), números flotantes, cartel del final y cámara (sacudida/zoom moviendo el nodo del juego, sin redibujar). Medido intercalando la punta sin el cambio (`8576fbb`) y con el cambio, 4 corridas de cada uno (promedio; la máquina tenía otras corridas en paralelo y el control `lobby`, que no cambia, varió +7 %):

| Escena | Scripts prom. (ms) | Scripts p95 (ms) | Draw calls |
|---|---:|---:|---:|
| lobby (control) | 1,79 → 1,84 | 2,41 → 2,59 | 355 → 355 |
| arena | 2,26 → 2,59 | 3,38 → 3,81 (+13 %) | 30 → 31 |
| pingpong | 1,32 → 1,47 | 1,87 → 2,14 (+14 %) | 35 → 37 |
| tap_race | 2,16 → 2,25 | 3,23 → 3,40 (+5 %) | 32 → 32 |
| stop_clock | 2,70 → 2,75 | 4,16 → 4,09 | 61 → 61 |
| dodge | 2,76 → 2,85 | 4,43 → 4,36 | 42 → 42 |
| paint | 2,73 → 2,76 | 4,01 → 4,15 | 45 → 45 |
| sumo | 3,65 → 3,72 | 5,30 → 5,61 (+6 %) | 93 → 91 |
| sumo_tarde | 4,35 → 4,62 | 6,41 → 7,23 (+13 %) | 95 → 95 |

- Todo dentro del presupuesto (p95 ≤ 8 ms en el benchmark, ≤ 150 draw calls) y ninguno sube más de 15 %. `sumo_tarde` es el más ruidoso (p95 de 5,4 a 7,5 ms en la línea base y de 5,4 a 9,5 en una corrida con el cambio).
- **Qué cuesta**: en Arena y Ping Pong los efectos se disparan todo el tiempo en el benchmark (estrellas y rebotes cada pocos frames): ≈ 0,15–0,3 ms por frame con partículas vivas. El pool recorre solo los lugares ocupados (`_hi`), reusa los arreglos de colores por forma y ubica cada forma con `Transform2D * PackedVector2Array`; 200 partículas ≈ 0,1 ms de armado.
- **Empujones**: la sacudida ya no redibuja las capas de la isla (antes ≈ 13 frames por golpe) y los efectos a mano (varios `draw_arc`/`draw_star` por golpe) pasaron al lote: 93 → 91 draw calls.
- Sin efectos activos, `Juice` y `FxParticles` apagan su `_process` y no se redibujan.

### Pool loco

`host/minigames/pool/`: la mesa (paño, bandas, troneras) va en `draw_static` sobre `draw_play_field` con una sola baldosa (el marco de bloques del tablero); en cada frame, sombras, brillo de las doradas, guías de tiro y bolas van en **un** `TriBatch` (las bolas, la sombra y la guía de puntitos se arman una vez como plantillas locales y solo se ubican), más las 4 mascotas y los globitos. La física (`pool_physics.gd`, pasos fijos de 1/120 s, hasta 11 bolas) saltea los pares de bolas quietas. Medido en la misma corrida que Arena y Pintar el piso (600 frames, máquina compartida):

| Escena | Scripts prom. (ms) | Scripts p95 (ms) | Draw calls |
|---|---:|---:|---:|
| arena (control) | 2,65 | 4,17 | 30 |
| paint | 3,28 | 5,29 | 48 |
| pool | 4,07 | 5,53 | 32 |

Los inputs del benchmark casi nunca vuelven a 0, así que en `pool` todos apuntan todo el tiempo (flechas y guías en cada frame) y casi no tiran. Con una variante que suelta el joystick cada 1,6 s (tiros, choques y troneras todo el tiempo), `pool` quedó ≈ 1,6× Arena en Scripts (p95 6,84 contra 4,19 ms en una corrida con la máquina menos cargada).

### Mascotas 3D horneadas (ADR 0012)

Todas las mascotas se dibujan como un sprite del atlas horneado (`MascotAtlas`, ver [ARTE.md](ARTE.md#integración-27092026)); la 2D por código queda de respaldo. Medido con `--mascots=both`: **en la misma corrida**, cada escena con 2D y con 3D, alternando cuál va primero (27/09/2026, la máquina estaba cargada por otros procesos: los valores absolutos están inflados; comparar las columnas entre sí):

| Escena | Scripts prom. 2D → 3D (ms) | Scripts p95 2D → 3D (ms) | Draw calls 2D → 3D | Atlas (MB) |
|---|---:|---:|---:|---:|
| lobby | 3,53 → **1,13** (−68 %) | 4,69 → **1,57** | 467 → 467 | 15,9 |
| arena | 9,09 → **3,92** (−57 %) | 13,09 → **5,80** | 31 → 31 | 24,5 |
| sumo | 13,00 → **7,07** (−46 %) | 19,48 → **10,70** | 90 → 91 | 25,8 |
| sumo_tarde | 14,83 → **9,35** (−37 %) | 22,05 → **14,03** | 93 → 92 | 25,8 |
| pool | 14,96 → **8,06** (−46 %) | 22,39 → **11,66** | 32 → 31 | 29,7 |
| karts | 17,61 → **10,63** (−40 %) | 26,58 → **15,94** | 40 → 42 | 29,7 |

- **CPU:** dibujar un sprite (elegir el cuadro + sombra + una transformación) cuesta mucho menos que armar ~40 figuras por mascota: los Scripts bajan entre 37 % y 68 %. Es el mismo hallazgo del prototipo (ARTE.md), ahora en el juego completo.
- **Draw calls:** iguales (una mascota eran 2 lotes; ahora son la sombra y el sprite). Juegos ≤ 150 y lobby ≤ 500.
- **p95 ≤ 8 ms:** en esta corrida (máquina cargada, juegos a ~15 fps en xvfb, o sea 3–4 pasos de física y dibujos por frame) la 3D lo cumple en lobby y arena y la 2D en ninguna escena de juego; en una máquina sin carga los valores de la 2D eran ~2–3× más chicos (tabla de arriba) y la 3D los baja a la mitad.
- "Atlas" es la memoria de texturas horneadas en ese momento (acumula las escenas anteriores de la corrida: no se sueltan porque el presupuesto no se llena).

**Horneado** (`tools/mascot_atlas_check.gd`: 4 jugadores, poses de juego a u = 0,8 + avisos + pantallas, como en el lobby y la intro; llvmpipe):

| Qué | Valor |
|---|---|
| Poses / trabajos | 188 poses en 28 trabajos (≤ 17 poses por trabajo en juego, 3 en pantalla) |
| Tiempo total | 5,5 s en llvmpipe (render por software; en una GPU real el render es decenas de veces más rápido). Se tapa con el lobby y la intro |
| CPU del horneado | 277 ms en total; **3–5 ms por cuadro** (armar 1 mascota ≈ 2–3 ms, leer la imagen ≈ 1–4 ms, achicar ≈ 1–3 ms, subir < 1 ms); peor cuadro 15,6 ms (el primer trabajo: crea el viewport y compila los shaders) |
| Cuadro de la escena mientras hornea | prom. 26,7 ms (base 14,9 ms), p95 51 ms, máx. 149 ms (el primero, con la compilación de shaders); casi todo es el render por software de 3 mascotas por cuadro |
| Memoria | **21,5 MB** para 4 jugadores (≈ 5,4 MB por jugador); en una partida completa (lobby + varios juegos) 25–30 MB |

**Presupuesto de memoria** (`MascotAtlas.BUDGET_BYTES` = 40 MB; RGBA8, sin mipmaps):

| Tamaño (u) | Celda (px) | Por pose | Uso | Poses precalentadas por jugador | Por jugador |
|---|---|---:|---|---:|---:|
| 0,62 | 74 × 87 | 25 KB | karts, tribuna (u 0,56–0,67) | según el juego | ≤ 1 MB |
| 0,95 | 114 × 133 | 60 KB | la mayoría de los juegos (u 0,7–0,85), avisos | 13 + 24 de caminata + 3 de avisos | ≈ 2,4 MB |
| 1,45 | 174 × 203 | 141 KB | juegos con mascotas grandes (u 1,3–1,5) | 13 (sin caminata) | ≈ 1,8 MB |
| 2,25 | 270 × 315 | 340 KB | lobby, intro, resumen, podio, marcador, celular | 10 | ≈ 3,3 MB |
| 3,4 | 408 × 476 | 777 KB | mascota anfitriona del lobby, selector | lo que se dibuje | ≈ 3 MB en total |

- Lo que se usa se queda; si la memoria pasa de 40 MB se sueltan las hojas que hace más de 3 s no se dibujan.
- Al irse un jugador (o cambiar de color o estilo en el lobby) su apariencia se suelta a los ~3 s (`MascotAtlas.keep_only`, lo llama el host en cada cambio de jugadores y el celular con la suya).
- Durante el horneado se reserva además un viewport temporal (≤ 1 MP con supersampling, ≈ 8 MB con profundidad) que se suelta al terminar.

**Precalentado por juego** (29/09/2026, `tools/mascot_prewarm_check.gd`: hace lo mismo que la intro, espera a que termine el horneado y juega la partida entera con 4 bots; cuenta las poses pedidas recién al dibujar, cada una un tirón chico y unos cuadros con la pose parecida). Cada juego declara en `MASCOT_PREWARM` las poses que dibuja además de las típicas (cara de susto caminando, festejo caminando al final, la tribuna) y `MASCOT_SCALE` si no dibuja a 0,8:

| Juego | Tarde antes | Tarde después | Precalentado (llvmpipe) | Atlas tras la intro |
|---|---:|---:|---:|---:|
| Empujones (sumo) | 16 | 0 | 4,4 s | 32,6 MB |
| Karts | 4 | 0 | 3,0 s | 17,7 MB |
| ¡Que no te deje la cámara! | 17 | 0 | 5,3 s | 33,4 MB |
| Esquivar | 25 | 0 | 4,1 s | 32,6 MB |
| Carrera de obstáculos | 13 | 0 | 3,3 s | 25,5 MB |
| Carrera de toques (dibujaba a u 1,3 y se precalentaba a 0,8) | 5 | 0 | 3,3 s | 29,3 MB |
| Ping Pong (u 1,6; ídem) | 5 | 0 | 1,0 s | 11,4 MB |
| Arena de estrellas · Pintar el piso | 1 · 1 | 1 · 1 | 3,0 s | 21,5 MB |
| Reloj exacto, Memoria de colores, Desenfunde, Pool loco | 0 | 0 | — | — |
| **Total** | **87** | **2** | | |

- Lo que queda: un cuadro de festejo caminando al final de Arena y de Pintar el piso (una pose; no justifica 24 poses más por jugador).
- El atlas llega a ~33 MB con 4 jugadores en los juegos con más poses (incluye ~13,6 MB de poses de pantalla a 2,25): entra en el presupuesto de 40 MB y al pasar al juego siguiente se sueltan las hojas que ya no se dibujan.

Cómo repetirlo:

```bash
xvfb-run -a -s "-screen 0 1920x1080x24" godot --path . --rendering-driver opengl3 --audio-driver Dummy \
  -s res://tools/benchmark.gd -- --only=lobby,arena,sumo,pool,karts --mascots=both
xvfb-run -a -s "-screen 0 1920x1080x24" godot --path . --rendering-driver opengl3 --audio-driver Dummy \
  -s res://tools/mascot_atlas_check.gd -- --out=/tmp/atlas.png --log   # tiempos por trabajo y hoja 2D vs 3D
```
### Piezas 3D horneadas (ADR 0016)

Estrellas, bloques del marco y de los fondos, medallas, corona, trofeo, ficha de Pintar y pelota de Ping Pong como sprites de un atlas horneado en 3D (`core/art3d/`, [ADR 0016](adr/0016-piezas-3d-horneadas.md)). Medido con el mismo código y el interruptor nuevo del benchmark (`--no-props3d` = dibujo 2D de antes), dos corridas de cada uno intercaladas en la misma sesión (promedio de las dos):

```bash
… -s res://tools/benchmark.gd -- --only=lobby,round_summary,final,arena,pingpong,paint,sumo --no-props3d --json=/tmp/off.json
… -s res://tools/benchmark.gd -- --only=lobby,round_summary,final,arena,pingpong,paint,sumo --json=/tmp/on.json
```

| Escena | Scripts prom. (ms) 2D → 3D | Scripts p95 (ms) | Draw calls | Render (ms) |
|---|---:|---:|---:|---:|
| lobby | 3,41 → 3,20 | 4,62 → 4,30 | 467 → 467 | 103,4 → 102,1 |
| round_summary | 3,21 → 2,88 | 4,27 → 3,88 | 187 → 181 | 70,5 → 67,5 |
| final | 2,93 → 2,95 | 4,07 → 3,94 | 115 → 109 | 53,4 → 53,4 |
| arena | 8,66 → 8,13 | 12,65 → 11,63 | 31 → 35 | 54,5 → 50,8 |
| pingpong | 4,65 → 4,68 | 6,75 → 6,45 | 37 → 37 | 55,3 → 53,8 |
| paint | 11,69 → 10,98 | 18,10 → 16,84 | 49 → 52 | 66,2 → 63,2 |
| sumo | 12,77 → 12,46 | 18,19 → 19,01 | 90 → 90 | 75,6 → 74,3 |
| sumo_tarde | 14,79 → 13,90 | 22,03 → 20,80 | 93 → 93 | 68,5 → 66,3 |

- **La máquina estaba muy cargada** (otras corridas de Godot en paralelo): los juegos iban a ~12–15 fps con 4–5 pasos de física por frame, así que los tiempos absolutos salen 2–4× los de las tablas de arriba (paint p95 ≈ 17 ms contra 4,7 ms en la tabla del ADR 0009) **con y sin** piezas 3D. Lo que vale es la comparación: Scripts igual o menor en todas las escenas (±5 %, del orden del ruido: el 2D armaba ~5 figuras con bisel por bloque en las capas cacheadas; el 3D, un rectángulo de textura) y render igual o un poco menor.
- **Draw calls**: el tablero pasa de 1 a 4 comandos (lote, bloques, lote, esquinas; todos los bloques del mismo atlas van juntos en uno); Arena suma las estrellas como sprites (+4 en total). Resumen y podio bajan (la medalla 3D es un sprite en vez de 3 círculos). Todo muy por debajo de 150 en juegos y 500 en menús.
- **Objetos**: +11 con el atlas instalado (textura, regiones e imágenes chicas); las mallas y materiales del armado se sueltan después de hornear (`Props3D.release_build_caches`). Estable entre escenas.
- **Horneado** (primer arranque, sin caché; xvfb + llvmpipe): 0,9–1,1 s en total = armado de las 53 piezas ~0,13 s + 8 azulejos de 512 px renderizados a 2048×2048 (2 cuadros cada uno) ~0,8 s + lectura de píxeles ~6 ms. Se hace al abrir la TV, tapado por la presentación.
- **Con caché** (`user://props3d/atlas_<firma>.png`): leer el PNG, mipmaps y textura ≈ 36 ms, en `_ready` de la TV antes de armar el lobby.
- **Memoria**: atlas 2048×644 RGBA8 con mipmaps = 7,0 MB en la GPU (5,3 MB sin mipmaps) + 0,6 MB de imágenes chicas en RAM (estrella y bloques, para componer el escenario de los juegos). Transitorio al hornear: render de 2048×2048 color + profundidad (~32 MB) y otro de 512×512, que se liberan al terminar.

### Lobby como la maqueta (dioramas, tarjetas y piezas de juguete, ADR 0018)

`tools/benchmark.gd -- --only=lobby`, intercalando la punta sin el cambio (`8a7ae11`, copiada aparte) y con el cambio, dos corridas de cada uno una detrás de la otra con el candado de Godot tomado (xvfb + llvmpipe):

| Escena | Scripts prom. (ms) | Scripts p95 (ms) | Draw calls | Objetos | Render (ms) |
|---|---:|---:|---:|---:|---:|
| lobby | 0,75 → 0,76 | 1,01 → 1,04 | **467 → 405** | 2212 → 2211 | 50,9 → 50,7 |

- **Draw calls −13 %** aunque se sumaron el selector de música y los destellos fijos del botón: cada tarjeta de jugador, ficha del código y botón es ahora **un lote** (`UiTheme.draw_seat_card`/`draw_toy_block`: sombra, borde, canto, degradé, brillo y el borde suavizado en un solo triangle array) en vez de 4–6 StyleBox y polígonos sueltos.
- **Scripts igual** (±3 %, ruido): lo que cambia se sigue redibujando solo cuando cambia (foco, texto, jugador); los destellos se dibujan una vez y solo laten (escala) con el foco.
- **Dioramas**: una textura por tarjeta, igual que la captura (648×240 WebP, ~20 KB; en la GPU ≈ 0,8 MB con mipmaps para los 13). No hay 3D en la TV: se renderizan con `tools/make_dioramas.gd` (~0,3 s por juego en llvmpipe).
- **Fondo más lleno** (fila de torres del medio): se pinta una vez al preparar el escenario desenfocado, cero costo por frame.

### Tablero 2.5D horneado (ADR 0019)

Pintar el piso con el escenario 3D horneado (tablero en perspectiva, marco con volumen, juguetes desenfocados) y el juego en 2D proyectado encima. `tools/benchmark.gd -- --only=paint,arena --board=both`: el mismo juego plano y en 2.5D **en la misma corrida**, con Arena como control del ruido; tres corridas con el candado de Godot tomado (xvfb + llvmpipe, 300 frames, 4 jugadores):

| Escena | Scripts prom. (ms) | Scripts p95 (ms) | Draw calls | Render (ms) |
|---|---:|---:|---:|---:|
| arena (control) | 1,26 · 1,86 · 1,56 | 1,94 · 2,52 · 2,31 | 35–36 | 24,8 · 28,6 · 25,9 |
| paint plano (antes) | 1,70 · 2,01 · 1,95 | 2,62 · 3,04 · 2,89 | 52–53 | 29,0 · 30,7 · 30,3 |
| **paint 2.5D** | **1,05 · 1,71 · 1,66** | **1,70 · 2,70 · 2,71** | **44–47** | **18,5 · 23,7 · 23,7** |

- **Más barato que el plano**: el fondo es **una** textura de pantalla completa (1 draw call, capa cacheada) en vez del escenario en franjas + el tablero en lotes con bisel y bloques del atlas; y cada píxel se pinta una vez (el render de llvmpipe baja ~20–35 %). Muy lejos del presupuesto (p95 ≤ 8 ms, ≤ 150 draw calls).
- **Qué se hace por cuadro además del plano**: proyectar 4 mascotas y el premio (`project` + `scale_at`: una multiplicación de matriz 3×3 cada una) y, cuando cambia una fila de baldosas, ubicar cada baldosa con su transformación ya calculada (`cell_xform`, en caché: igual costo que antes).
- **Horneado** (la primera vez en el aparato, durante la intro "¿Cómo se juega?"): 0,9–1,2 s en llvmpipe (armar la escena ~85 ms, entorno ~190 ms, desenfoque ~170 ms, tablero 2 × 2 azulejos con supermuestreo ~400 ms, componer ~50 ms). En una GPU real el render es mucho menor; el armado (GDScript, ~600 piezas) es lo que más pesa en la CPU de la TV: pendiente medirlo en el aparato.
- **Después, del disco**: `user://board25d/board_paint_<firma>.png` se lee en un hilo en **~37–45 ms** (32 ms leer + 4–8 ms subir a la placa): no traba la intro.
- **Memoria**: la textura es de 1920 × 1080 RGB = **6,2 MB** (8,3 MB si el driver la guarda como RGBA), mientras se juega a Pintar el piso y 2 s después (`Board25DBaker.retain`). Transitorio del horneado ≈ 35 MB (render de 1920 × 1080 con profundidad, el achicado y las imágenes intermedias), que se suelta al terminar.

## Qué se cambió y por qué

### 1. Capas estáticas que se dibujan una sola vez

Godot conserva los comandos de dibujo de cada `CanvasItem` hasta el próximo `queue_redraw()` **de ese nodo**. Si un nodo se redibuja en cada frame, todo lo que dibuja se recalcula en cada frame, aunque no cambie. Entonces lo que no cambia va en un nodo hijo que no se redibuja:

- **`PartyBackground`** (`core/ui/widgets/party_background.gd`): el escenario (cielo, torres, piso, luces) se pinta **una vez** en un `SubViewport` a media resolución y se desenfoca una vez (ver [Fondo de escenario](#fondo-de-escenario-transición-y-confeti) y [ADR 0008](adr/0008-fondo-escenario-desenfocado.md)); en pantalla es un solo `TextureRect`. Solo nubes y brillos se mueven, como `Sprite2D`: sin `_draw()` por frame.
- **`MiniGame.draw_sky()` / `draw_play_field()`** (`host/minigames/minigame.gd`): ahora *registran* la capa y la dibuja una vez un hijo interno `_backdrop` con `show_behind_parent` (queda detrás de todo lo del juego). Solo se redibuja si cambian los argumentos. La API no cambió: los juegos las siguen llamando al principio de `_draw()`.
- **`MiniGame.draw_hud()`**: el marcador va en un hijo interno `_hud`, delante del juego, que se redibuja solo cuando cambia un número o el texto del centro (≈ 1 vez por segundo en vez de 60).
- Si en un `_draw()` el juego deja de pedir una capa, se borra al terminar ese `_draw()` (el juego se entera por la señal `draw`, que Godot emite justo antes de `_draw()`).

### 2. Menos comandos de dibujo: figuras en lote

Cada `draw_circle` / `draw_colored_polygon` / rectángulo redondeado es un comando aparte: arma su propio buffer de vértices en la GPU y cuesta un draw call. `UiTheme.ShapeBatch` junta círculos, elipses y polígonos consecutivos en **un solo** `canvas_item_add_triangle_array`, respetando el orden (lo agregado después queda encima). Los círculos usan la misma geometría que `draw_circle` (64 segmentos desde el centro) y los polígonos convexos cubren los mismos píxeles, así que se ve igual. Se usa en:

- `PlayerAvatar.draw_mascot`: pies, manos, orejas, cabeza, cara, ojos, boca y accesorios se juntan en tramos; se hace `flush` antes de cada rectángulo redondeado, línea, arco y cambio de transform, así el orden es exactamente el de siempre y cada tramo queda bajo el transform de *squash & stretch* que le corresponde (la sombra, fuera de él).
- Para que los círculos del lote den **los mismos vértices** que `draw_circle`, se calculan con el mismo redondeo a float de 32 bits que usa el motor.
- `UiTheme.draw_star` (3 → 1), `UiTheme.draw_hex_chip` (fondos 3–4 → 1), nubes del fondo (5 círculos → 1 por nube), botones de los bloques del borde (40 → 2) y lunares de las tarjetas del lobby (~20 → 1 por tarjeta).

### 3. Sin reservas ni trigonometría por frame en los helpers

`UiTheme.ellipse_points` usa senos y cosenos precalculados por cantidad de pasos, y `ellipse_points`/`star_points` reservan el arreglo de una vez (`resize`) en vez de hacerlo crecer punto a punto. Las cuentas son exactamente las mismas que antes, así que los puntos salen idénticos bit a bit (con `Transform2D * PackedVector2Array` era más rápido, pero redondeaba distinto y cambiaba algún píxel del borde).

### 4. No animar lo que no se ve

`PartyBackground`, `PlayerAvatar` y `Confetti` apagan su `_process` cuando no son visibles (`NOTIFICATION_VISIBILITY_CHANGED` + `is_visible_in_tree()`). Antes el fondo de la TV seguía redibujándose oculto durante todos los minijuegos, y las mascotas del resumen/podio seguían animándose con la pantalla oculta.

### 5. Celular: bajo consumo mientras espera

`ControllerMain._update_power_mode()`: si no hay un control en pantalla (unirse, esperar, ver el resultado):

- Nubes y mascotas se animan a `IDLE_ANIM_FPS` (30) con `anim_fps` (usa un reloj común, así se redibujan en el mismo frame). Son 30 y no menos porque la mascota de espera saluda con los brazos: a 30 fps el saludo sigue fluido y las nubes avanzan < 1 px por paso.
- `OS.low_processor_usage_mode = true`: Godot no dibuja los frames en los que nada cambió.
- `PlayerAvatar.hop()` (salto y *squash*) pide redibujo en cada paso, así el festejo se ve fluido aunque el idle vaya a 30 fps.

Apenas la TV manda un control (`layout`), vuelve todo a 60 fps y se apaga el bajo consumo: **la latencia del input durante el juego no cambia**. El modo de bajo consumo es global del proceso, así que solo se activa si el control es la app (raíz de la ventana); en las capturas y los tests la TV corre en el mismo proceso y no se frena.

### Verificación visual

- **Hoja de personajes** (`tools/character_sheet.gd`, determinista: 4 mascotas × ánimos, parpadeo, mirada, caminata, salto y aterrizaje con *squash*): **0 píxeles distintos** antes y después.
- Una hoja determinista extra (fondo con las nubes quietas, mascotas con caminata, mirada, saludo y *squash*, vacías, estrellas rotadas, elipses, chips del marcador, medalla, tarjetas del lobby y Carrera y Pintar el piso escalados): **0 píxeles distintos**.
- `tools/capture_screens.gd` antes y después: solo cambia lo que depende del tiempo o del azar (nubes, respiración, parpadeo y saludo, estrellas y bloques al azar, código de sala, confeti). Dos corridas de la punta *sin* el cambio difieren entre sí en la misma medida.

### Bots (ADR 0010)

Los bots corren en la TV en cada paso de física: tienen que costar poco. **Presupuesto: ≤ 0,5 ms por juego sobre el p95 de Scripts** (todos los bots juntos). Dos formas de medirlo:

- `tools/benchmark.gd -- --bots`: los jugadores de cada juego son bots "Normal" en vez de entradas inventadas. Comparar con la corrida sin `--bots` en la misma máquina.
- `tools/simulate.gd` (sin pantalla): la columna "Bots p95 / máx" mide solo `BotDriver.step` (todos los bots de un paso).

Medido con 4 bots (2 en Ping Pong), 50 competencias, en el contenedor de desarrollo:

| Juego | Bots p95 (ms) |
|---|---:|
| arena | 0,09 |
| pingpong | 0,04 |
| tap_race | 0,06 |
| stop_clock | 0,06 |
| dodge | 0,10–0,16 |
| paint | 0,13–0,16 |
| sumo | 0,07 |

Con `tools/benchmark.gd -- --bots` (xvfb, contenedor cargado: los valores absolutos varían ±30 % entre corridas) la diferencia en Scripts p95 queda dentro del ruido en Arena, Ping Pong, Reloj, Esquivar y Pintar (−1,7 a +2 ms entre corridas, en ambos sentidos). En **Empujones** sube bastante (p95 23 → 38 ms en xvfb), pero no por los bots: con bots hay choques de verdad, y el juego dibuja estrellitas, sacudón y "+5" que con las entradas inventadas del benchmark casi no aparecen. Es el costo del juego con acción real y conviene mirarlo aparte. La placa "BOT" del marcador suma ~9 draw calls por juego (un lote para las figuras y un texto por bot).

Cómo se mantiene bajo: `bot_view()` devuelve referencias (no copia nada), se llama una vez por paso para todos los bots, y los bots caros no piensan en cada frame: Esquivar prueba 9 movidas cada 0,07–0,3 s (según la dificultad) y Pintar busca primero en un radio de 4 baldosas. Hay máximos aislados de 1–14 ms (uno cada varios miles de pasos, incluso en Carrera, cuyo bot no calcula casi nada): parecen pausas del contenedor y no afectan el p95, pero conviene mirarlos en la TV real con el profiler.

## En la CI

El job `capturas` de `.github/workflows/ci.yml` (que ya tiene pantalla virtual) corre además el benchmark con `--frames=150`:

- imprime la tabla en el log y en el resumen del job (*Summary* del run de GitHub Actions);
- sube `benchmark.json` y `benchmark.txt` como artefacto `benchmark`;
- es **informativo**: `continue-on-error`, nunca hace fallar el job. Un runner de GitHub (CPU compartida, GPU por software) no se parece a una TV y varía entre corridas; sirve para ver tendencias entre PRs (ej. un juego nuevo que duplica los draw calls), no para aprobar o rechazar. Para comparar en serio, correr antes y después en la misma máquina con `--json`.

## Presupuestos recomendados

Para 60 fps el frame dura 16,7 ms. En la TV de gama baja (CPU ~4–5× más lenta que la máquina de desarrollo):

| Qué | Presupuesto en la TV | Equivalente aproximado en el benchmark (x86) |
|---|---|---|
| CPU de scripts por frame (juegos y menús) | **≤ 8 ms** (deja la otra mitad para el render y el sistema) | Scripts p95 ≤ 2 ms a 60 fps (≤ 3 ms en xvfb, donde los juegos se dibujan dos veces por frame) |
| Draw calls por frame en un juego | ≤ 150 | igual |
| Draw calls por frame en menús | ≤ 500 | igual |
| Objetos | estable entre escenas (sin crecer al repetir) | igual |
| Celular esperando | ≤ 30 dibujos/s | `ctrl_wait` ≤ 30 |
| Celular con control | 60 fps, sin bajo consumo | `ctrl_joy` sin cambios |

Reglas prácticas al dibujar:

- Lo que no cambia durante la pantalla va en un nodo aparte que no se redibuja (ver las capas de `MiniGame`), o se prepara una vez en una textura si además se desenfoca (`PartyBackground`).
- En los juegos, `draw_sky()` y `draw_play_field()` al principio de `_draw()` y `draw_hud()` una vez por `_draw()`: ya están cacheados.
- Varias figuras seguidas → `UiTheme.ShapeBatch` (y `flush` antes de texto, líneas o rectángulos redondeados).
- Nada de crear objetos (`StyleBox`, `Theme`, arreglos grandes) dentro de `_draw()` o `_process()`.
- `_process` apagado mientras el nodo no se ve.
- Tablero en perspectiva o escenario 3D: **horneado** una vez a una textura (`Board25DBaker`, ADR 0019) y el juego en 2D proyectado; nunca 3D en vivo por cuadro.

## Próximos pasos posibles

- **Empujones mientras se achica la isla**: el anillo recortado y el borde se redibujan en cada frame. Se podría redibujar por saltos (cada pocos px de radio), pero se vería distinto: se dejó exacto.
- **Redibujar en `_process` en vez de `_physics_process`**: si la TV no llega a 60 fps, hay dos pasos de física por frame y los juegos se dibujan dos veces. Mover el `queue_redraw()` a `_process` evita ese trabajo extra justo cuando más falta hace.
- **Mascotas como nodos**: en los juegos las mascotas se redibujan en cada frame aunque solo cambie su posición. Ahora que son sprites horneados (ADR 0012) cada una cuesta poco, pero como nodos hijos con `position` no haría falta ni eso.
- **Horneado en la TV real:** medir en una Google TV cuánto tarda el render de 3 mascotas por cuadro (`Mascot3DBaker.POSES_PER_FRAME`) y ajustar ese número (1 si traba, más si sobra).
- Medir en el aparato real (Google TV) con el profiler remoto de Godot y el monitor de `Performance`, y ajustar estos presupuestos con esos números.
