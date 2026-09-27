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
```

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
- El temblor no mueve las capas: cuando tiembla, las capas de la isla se redibujan con el desplazamiento (≈ 13 frames por golpe), así el resultado es idéntico.

**Pintar el piso** (`host/minigames/paint/paint.gd`, `_draw_tiles`): las baldosas quietas van en **una capa por fila** (11), que se redibuja solo cuando cambia alguna baldosa de esa fila; las que están "saltando" (recién pintadas, 0,18 s) se dibujan en `_draw` como antes. Con 4 jugadores se pintan decenas de baldosas por segundo: con una sola capa para todo el piso se redibujaba casi en cada frame; por fila, cada cambio redibuja 20 baldosas y no 220. Los puntos del patrón de 3P van en un lote por fila (antes eran 5 draw calls por baldosa).

Comparación visual: escenas deterministas de los dos juegos (estado fijo: cuenta regresiva; isla achicándose con temblor, efectos, uno cayendo y otro en la tribuna; final con la isla chica; piso con 140 baldosas, algunas saltando, power-up, brocha y velocidad; "¡Tiempo!"): **Pintar el piso 0 píxeles distintos**; **Empujones ≤ 3 píxeles de 2 millones con diferencia de 1/255** (redondeo de seno/coseno en el borde suavizado de los arcos). Las capturas de `capture_screens.gd` antes y después se ven iguales.

## Qué se cambió y por qué

### 1. Capas estáticas que se dibujan una sola vez

Godot conserva los comandos de dibujo de cada `CanvasItem` hasta el próximo `queue_redraw()` **de ese nodo**. Si un nodo se redibuja en cada frame, todo lo que dibuja se recalcula en cada frame, aunque no cambie. Entonces lo que no cambia va en un nodo hijo que no se redibuja:

- **`PartyBackground`** (`core/ui/widgets/party_background.gd`): solo las nubes se mueven. El nodo dibuja cielo + nubes en cada frame; torres, piso a cuadros y bordes de bloques (≈ 160 rectángulos redondeados + 40 círculos + 100 rectángulos) van en el hijo `_front`, que se redibuja solo al cambiar de tamaño o de capas. El orden no cambia (cielo, nubes, torres, piso, bordes) porque los hijos se dibujan después que el padre.
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

- Lo que no cambia durante la pantalla va en un nodo aparte que no se redibuja (ver `PartyBackground._front` y las capas de `MiniGame`).
- En los juegos, `draw_sky()` y `draw_play_field()` al principio de `_draw()` y `draw_hud()` una vez por `_draw()`: ya están cacheados.
- Varias figuras seguidas → `UiTheme.ShapeBatch` (y `flush` antes de texto, líneas o rectángulos redondeados).
- Nada de crear objetos (`StyleBox`, `Theme`, arreglos grandes) dentro de `_draw()` o `_process()`.
- `_process` apagado mientras el nodo no se ve.

## Próximos pasos posibles

- **Empujones mientras se achica la isla**: el anillo recortado y el borde se redibujan en cada frame. Se podría redibujar por saltos (cada pocos px de radio), pero se vería distinto: se dejó exacto.
- **Fondo de la TV como una sola textura**: las torres y bordes siguen siendo ~160 rectángulos redondeados (≈ 160 draw calls fijos en lobby, resumen y podio). Renderizarlos una vez a una textura bajaría a 1 draw call, pero con el estiramiento `canvas_items` hay que generarla a la resolución real de la pantalla (hasta 4K) y componerla con alfa premultiplicado para que se vea igual; se dejó afuera para no arriesgar diferencias visuales.
- **Redibujar en `_process` en vez de `_physics_process`**: si la TV no llega a 60 fps, hay dos pasos de física por frame y los juegos se dibujan dos veces. Mover el `queue_redraw()` a `_process` evita ese trabajo extra justo cuando más falta hace.
- **Mascotas como nodos**: en los juegos las mascotas se redibujan en cada frame aunque solo cambie su posición. Como nodos hijos con `position` no haría falta redibujarlas (cuando llegue arte con sprites, ver ADR 0004).
- Medir en el aparato real (Google TV) con el profiler remoto de Godot y el monitor de `Performance`, y ajustar estos presupuestos con esos números.
