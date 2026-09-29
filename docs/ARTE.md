# Arte de las mascotas: cómo llegar a la calidad de la maqueta

La maqueta de mascotas (`docs/design/referencia_mascotas.webp`) muestra personajes con acabado de **juguete de plástico 3D**: volumen real, reflejo chico y nítido, brillo ancho de barniz, luz de contorno, zapatos lustrados y un contorno de tinta grueso. Este documento compara cuatro caminos para llegar ahí (o superarla), con un **prototipo 3D real** hecho en Godot para medir en vez de suponer. La decisión queda en [ADR 0012](adr/0012-mascotas-3d.md) (aceptada el 27/09/2026; integrada en todo el juego: ver "Integración" abajo).

| Maqueta | 2D por código (hoy) | 3D en Godot (prototipo) |
|---|---|---|
| `docs/design/referencia_mascotas.webp` | `docs/img/mascotas.png` | `docs/img/mascotas_3d.png` |

De cerca (lobby/podio) y chicas (juegos): `docs/img/mascotas_3d_cerca.png`.

Comparación directa (mismas 4 mascotas, "Normal" y "Feliz"; arriba recortes de la maqueta, al medio la 2D de hoy, abajo la 3D): `docs/img/mascotas_3d_comparacion.png`. Todos los estilos y colores: `docs/img/mascotas_estilos.png` (2D) vs `docs/img/mascotas_3d_estilos.png` (3D).

## Conceptos nuevos (con ejemplos del juego)

- **Clearcoat (barniz):** muchos objetos brillantes tienen dos capas: el color (plástico, pintura) y encima una capa transparente lustrada. Cada capa refleja la luz distinto: el color da un brillo ancho y suave; el barniz, un reflejo chico y muy nítido. *Ejemplo:* en la cabeza roja de 1P, la mancha clara grande arriba a la izquierda es "el plástico" y el punto blanco bien recortado es "el barniz". En el prototipo son dos términos del shader (`coat_strength` ancho, `spec_strength` nítido); en el material estándar de Godot es la opción `clearcoat`.
- **Rim light (contraluz):** una luz que viene de atrás del personaje y solo ilumina su borde, como el sol detrás de una persona. Despega la silueta del fondo. *Ejemplo:* la mascota **negra** sin contraluz es una mancha oscura con contorno oscuro; con contraluz aparece una línea azulada en el borde derecho de la cabeza y del cuerpo y se lee la forma (ver la fila de abajo de `mascotas_3d_estilos.png`).
- **Inverted hull (casco invertido):** forma clásica de hacer contornos en 3D. Se dibuja cada pieza dos veces: la normal y una copia un poco inflada, de color tinta, de la que solo se muestran las caras de atrás. La copia queda escondida detrás de la pieza salvo en el borde, donde asoma como un contorno. *Ejemplo:* los brazos de 2P tienen su propio contorno también cuando pasan por delante del cuerpo, porque la copia inflada del brazo queda delante del cuerpo. Cuesta un draw call más por pieza con contorno.
- **Horneado a atlas (bake):** renderizar algo caro una vez y guardar el resultado como imagen. *Ejemplo:* al empezar "Pintar el piso", cada jugador se renderiza en 3D una vez en 21 poses (respirar, parpadear, 8 pasos de caminata, saludo, triste, sorpresa, salto…) dentro de una sola imagen grande (atlas). Durante el juego se dibuja la celda que corresponde como un sprite 2D: la TV no hace nada de 3D mientras se juega.
- **Luz de estudio dentro del shader:** en vez de poner tres luces reales en la escena (principal, relleno y contraluz), el shader calcula el color con esas tres direcciones fijas respecto de la cámara. En el renderer Compatibility de Godot cada luz real extra es **otra pasada de dibujo** de cada pieza; así es una sola pasada y la mascota se ve igual en la hoja, en la TV y en el celular.
- **Cámara ortográfica:** sin perspectiva (lo lejano no se achica). Permite renderizar todas las poses juntas en una grilla y que cada una se vea igual que si estuviera sola en su celda: **un solo cuadro de render da el atlas entero**.

## El prototipo 3D (`core/mascot3d/`)

| Archivo | Qué hace |
|---|---|
| `mascot_3d.gd` (`Mascot3D`) | Arma la mascota con primitivas: cabeza (esfera achatada) con la cara blanca pintada en su material, ojos negros brillantes con dos reflejos, cuerpo (superficie de revolución más ancha abajo) con la gema que brilla, brazos, piernas y zapatos, y los 7 accesorios (antena, oso, gato, brote, robot, cuernos, conejo). `apply(mood, anim)` recibe las mismas claves que `PlayerAvatar.draw_mascot` (`t`, `walk`, `look`, `squash`, `wave`, `dance` + `dance_kind`, `defeat`, `greet`, `flop`) más `blink`, `bob` y `lift`, con los 9 ánimos. `pose()` / `pose_lift()` dan los números de la pose sin armar la mascota. Ojos, bocas y efectos de cada ánimo son mallas que se prenden y apagan. |
| `mascot3d_meshes.gd` | Recetas de mallas por código: esfera, torno (`lathe`), tubo con radio variable (antena, cuernos que se afinan, arcos de los ojos felices, cejas, espirales, la Z de dormir), figura plana con espesor (bocas, dientes, estrellas) y puntos/normales del elipsoide de la cabeza para apoyar la cara. En caché: todas las mascotas comparten buffers. |
| `toy_plastic.gdshader` | Plástico de juguete: rampa sombra→color→luz con sombras de color, relleno, rebote del piso, borde profundo, contraluz celeste, reflejo del cielo, reflejo nítido "pintado" y brillo de barniz; la cara pintada en la cabeza y la sombra de la cabeza sobre el pecho. Sin luces reales. |
| `ink_outline.gdshader` | Contorno por casco invertido, inflado en el plano de la pantalla y medido en unidades del mundo (~2 u), más fino del lado de la luz y más grueso del de la sombra, con un mínimo en píxeles para las mascotas chicas. |
| `mascot3d_baker.gd` (`Mascot3DBaker`) | `bake(host, look, poses, cell_px) -> Dictionary[String, Texture2D]`: hornea las poses en un atlas (una grilla, un render, supersampling 2×). `POSES` y `GAME_POSES` traen las poses con nombre; `feet_offset()` dice dónde quedan los pies en la celda. |
| `mascot_atlas.gd` (`MascotAtlas`) | Caché de cuadros horneados por apariencia (color + estilo) y tamaño, con presupuesto de memoria. `PlayerAvatar.draw_mascot` le pide el cuadro de cada pose y, si no está, dibuja la 2D. Ver "Integración". |
| `mascot3d_live.gd` (`Mascot3DLive`) | Camino "en vivo": `Sprite2D` con su propio `SubViewport` 3D que se renderiza en cada cuadro. |
| `tools/mascot3d_sheet.gd` | Hojas: mismas columnas que `tools/character_sheet.gd` (y `--styles`, `--closeup`, `--compare`, `--expressions`, `--moods=N`, `--ref=N`, `--standard`, `--all=DIR`). |
| `tools/mascot3d_benchmark.gd` | Mide 2D vs 3D en vivo vs horneado, y el horneado. |

El juego ya lo usa en todas las pantallas (ver "Integración"). El test `test_mascot3d_prototype` arma todas las combinaciones de estilo y ánimo y ejerce el horneado (sin pantalla solo verifica que arma la escena); los `test_mascot_atlas_*` cubren el caché, las poses, los tamaños y el encuadre.

## Integración (27/09/2026)

Todo el juego (lobby, intro, juegos, resumen, podio, pausa, avisos, selector y el celular) muestra las mascotas 3D horneadas, sin cambios en las pantallas ni en los juegos: `PlayerAvatar.draw_mascot` elige el cuadro y lo dibuja como sprite.

- **Qué cuadro:** `MascotAtlas.pose_for(ánimo, anim)` da un nombre `"<base>@<ánimo>"`: `idle`, `blink` (mismo reloj de parpadeo que la 2D), `look_l/r/u/d`, `walk_{r,l,f}_0..7` (8 cuadros de caminata por dirección; se hornea también la izquierda para que la luz no cambie de lado al espejar), `wave_0..3` (festejo), `greet_0..1`, `defeat`, `danceK_0..3`. *Ejemplo:* caminando hacia la derecha a mitad de paso y feliz → `walk_r_4@1`.
- **Lo que va en 2D encima del sprite:** sombra en el piso, salto (`lift`), *squash & stretch*, inclinación (mareo, baile), respiración (un estirado de 1 %) y los efectos que se mueven solos (estrellitas del mareo, Z al dormir, destellos del ganador). Son las mismas cuentas que la 2D, así que el salto del podio o el aterrizaje en Carrera de obstáculos se ven igual.
- **Tamaños:** se hornea a 5 tamaños fijos (`TIERS_U`: 0,62 · 0,95 · 1,45 · 2,25 · 3,4 en u de `PlayerAvatar`) y se dibuja escalado (nunca más de 1,08× de agrandamiento). Celdas rectangulares de 12 × 14 unidades (más altas que anchas: ~25 % menos memoria que cuadradas); `test_mascot_atlas_framing` verifica que todas las poses de los 7 estilos entran con su contorno.
- **Cuándo se hornea:** al sumarse un jugador o cambiar su look en el lobby (poses de pantalla) y en la intro "¿Cómo se juega?" (poses del juego al tamaño de su `MASCOT_SCALE`, las extra de su `MASCOT_PREWARM` y las de los avisos; `tools/mascot_prewarm_check.gd` mide qué queda sin precalentar). Lo que falte se pide al dibujar (horneado perezoso) y mientras tanto se muestra la pose más parecida ya horneada, o la 2D si esa apariencia no tiene ninguna.
- **Cómo se hornea sin trabar la TV:** `Mascot3DBaker.Job` reparte el trabajo: arma una mascota por cuadro (3 por trabajo, que se reutilizan con `apply()`), renderiza 3 poses por cuadro en un viewport que no se borra (render acumulado), lee la imagen una vez, la achica (supersampling 2× con filtro de caja) en otro cuadro y la sube en otro. El viewport se reutiliza entre trabajos del mismo tamaño.
- **Respaldo 2D:** sin render (`--headless`, tests), si el horneado falla dos veces (se apaga el 3D), mientras se hornea, con la silueta de lugar vacío y con los ánimos que la cara 3D todavía no tiene (se detecta solo: si `Mascot3D` muestra la cara normal para ese ánimo). `--mascots-2d` en `tools/capture_screens.gd` y `--mascots=2d|3d|both` en `tools/benchmark.gd` sirven para comparar.
- **Memoria:** presupuesto de 40 MB (`MascotAtlas.BUDGET_BYTES`); números medidos en [PERFORMANCE.md](PERFORMANCE.md#mascotas-3d-horneadas-adr-0012).

Convención con `Mascot3D` (para quien cambie el modelo): el baker pasa en `anim` las claves de siempre (`t`, `walk`, `look`, `wave`, `blink`, `dance`, `dance_kind`, `defeat`, `greet`) más `"in_place": true` y `"fx": false`. Con `in_place`, lo que mueve el cuerpo entero (saltos del baile, squash) lo pone `PlayerAvatar` en 2D; con `fx: false`, los efectos que giran o suben solos (estrellitas, Z) también. Si la mascota crece (orejas, accesorios), `test_mascot_atlas_framing` avisa y hay que agrandar `Mascot3DBaker.ATLAS_CELL`.

### Qué se ganó frente a la 2D

- **Volumen de verdad:** cada pieza tiene su luz según su orientación (la oreja de oso inclinada, el brazo que se levanta, el zapato que se adelanta al caminar).
- **Poses que en 2D no existen:** en "Mira" y "Paso 1/2" la mascota gira la cabeza o el cuerpo hacia donde va (vista 3/4): se ve el costado de la cara y la antena de perfil. En 2D solo se corrían los ojos.
- **Contornos que siguen la pose:** los brazos por delante del cuerpo, la oreja por detrás de la cabeza, sin reordenar nada a mano.
- **Consistencia:** los 7 estilos × 10 colores salen del mismo material; blanco y negro se leen gracias al contraluz y al borde de la cara.

### Calidad: al nivel de la maqueta (27/09/2026)

Después de aceptar el ADR 0012 ("las mascotas en 3D como en las maquetas o mejor") se comparó la 3D con la maqueta recorte por recorte, grande y a tamaño de juego, y se ajustaron material, contorno, mallas, proporciones, cara y poses.

| Imagen | Qué muestra |
|---|---|
| `docs/img/mascotas_3d_detalle.png` | Maqueta y 3D a la misma escala (2P, Normal y Feliz) y abajo las 4 a tamaño de juego (celda de 116 px) |
| `docs/img/mascotas_3d_comparacion.png` | Maqueta · 2D actual · 3D, las 4 mascotas en Normal y Feliz |
| `docs/img/mascotas_3d.png` | Hoja de personajes (mismas columnas que la maqueta) |
| `docs/img/mascotas_3d_expresiones.png` | Los 9 ánimos y, en fases, los tres bailes, la derrota y el saludo |
| `docs/img/mascotas_3d_estilos.png` | 7 estilos × 10 colores (blanco, negro y grafito incluidos) |
| `docs/img/mascotas_3d_cerca.png` | Grandes (lobby, podio) y chicas (juegos) |

La versión anterior de las imágenes quedó en el historial (commit `6c4e5c2`).

**Qué cambió y por qué** (cada punto, contra algo concreto de la maqueta):

- **Colores vivos y sombras de color** (`Mascot3D.vivid`, `plastic_ramp`). La maqueta es un juguete saturado: su rojo iluminado es ~#F53047 y el nuestro era #E24B4A apagado. Ahora el plástico sube saturación y brillo sin cambiar el tono (el jugador sigue siendo "el rojo"), la sombra es un carmín más saturado y un poco más frío, y la parte iluminada sigue saturada: el blanco queda solo para los reflejos. *Ejemplo:* medido en la hoja, el costado iluminado de la cabeza roja pasó de rosa lavado (#FFBCB7) a rojo vivo.
- **Reflejo "pintado" y barniz.** El reflejo nítido tiene borde recortado (como lo pinta un ilustrador) y se estira siguiendo la curva de la pieza; el barniz es un brillo ancho y suave aparte. Se sumaron el **reflejo del cielo** (una banda clara pegada al borde, abajo a la derecha) y el **borde profundo** (hacia la silueta el plástico se vuelve más oscuro y saturado): eso da la sensación de "barniz grueso" de la maqueta.
- **Cara pintada en la cabeza.** Antes la cara era otra malla apoyada sobre la cabeza y su borde se veía serruchado de cerca (dos superficies facetadas que se cruzan). Ahora es una zona del material de la cabeza: una elipse vista de frente, recortada por píxel. *Ejemplo:* en `mascotas_3d_detalle.png` el borde de la cara es una curva limpia a 600 px. Tiene la sombra de la capucha arriba y un labio de luz afuera, como la maqueta, y es una malla menos por mascota.
- **Proporciones de la maqueta** (medidas sobre el recorte del oso): cabeza de ~3/4 del alto y casi el doble de ancha que el cuerpo; cara más ancha que alta y más baja; ojos más grandes y más separados; cuerpo más bajo, con la sombra de la cabeza en el pecho; zapatos más chicos, casi escondidos.
- **Ojos, cachetes, boca y gema.** Ojos negros con el reflejo del shader más dos reflejos blancos pintados; cachetes rosados que se funden con la cara (el color pasa a blanco hacia el borde del cachete, sin transparencias); boca en D con borde de tinta, interior rojo oscuro y lengua; gema de un tono vecino al del jugador (rojo -> dorada, azul -> celeste, como en la maqueta) con centro claro y un halo que tiñe el plástico de alrededor.
- **Contorno más fino, con intención y que no se pierde de chico.** ~2 u en vez de 3, más fino del lado de la luz y más grueso del de la sombra (lo que hace un ilustrador a mano), con un mínimo en píxeles: a 116 px sigue midiendo ~1,3 px.
- **Brazos que saludan hacia afuera.** En la maqueta, al festejar, las manos quedan afuera de la cabeza a la altura del mentón. Los brazos levantados ahora van hacia afuera y se estiran un poco; si igual quedarían tapados, pasan por delante (`_aim_arm`).
- **Paridad total con `PlayerAvatar`:** los 9 ánimos (enojada con venita, mareada con espirales y estrellitas, dormida con Z y globito, ganadora con ojos de estrella y destellos, riendo con lágrimas) y todas las claves de `anim`. *Pose por capas*: `Mascot3D.pose()` calcula los mismos números que la 2D (inclinación, brazos, salto, giro…) y `apply()` los lleva a los nodos. En 3D el baile "Giro" da una vuelta de verdad (se ve la nuca) y la inercia (`flop`) dobla orejas, antena y hojas desde su base.
- **Caras perezosas:** ojos y bocas de los ánimos nuevos se arman la primera vez que se piden. Un horneado de juego (`GAME_POSES`) no los usa y no los paga.

**Paleta (29/09/2026):** el amarillo y el verde de 3P y 4P pasaron a los de la maqueta: amarillo dorado #F5B82C (antes #EF9F27, más naranja) y verde pasto #45C35A (antes #1D9E75, más turquesa). Cambia el valor, no el índice (compatible con el protocolo). Con daltonismo, Rojo/Verde queda más separado que antes (deuteranopía 0,072 → 0,089 en OKLab) y aparecen Amarillo/Verde en protanopía (0,047) y Verde/Celeste en tritanopía (0,050); el par más cercano de antes (Azul/Verde en tritanopía, 0,035) mejora a 0,099. Sigue siendo aceptable porque el juego no depende del color (1P–4P y accesorio). **Lo que queda distinto:** no hay sombras proyectadas reales (la sombra del pecho está "pintada").

**Para el horneado** (`mascot3d_baker.gd`, lo integra otro PR): el salto propio de algunas poses (saltitos, giro, risa) va dentro del cuadro; con `anim["lift"] = false` se hornea sin él y `Mascot3D.pose_lift()` dice cuánto sumar en 2D (y cuánto achicar la sombra), como hace `--expressions`. Con `anim["in_place"] = true` tampoco se hornea nada que mueva la mascota entera (squash & stretch, inclinación, respiración, rebote del paso) y con `anim["fx"] = false` se apagan los efectos alrededor de la cabeza (`fx_*`: estrellitas, Z y globito, destellos, venita): los dibuja la 2D encima del sprite. Así, la mascota entra en ~11,1 × 12,2 unidades del mundo con contorno (el ancho máximo es el gato derrotado, con las orejas caídas hacia afuera). La sombra en el piso sigue siendo 2D (mancha difusa; en las hojas, un poco más ancha que antes).

**Costo** (`tools/mascot3d_benchmark.gd`, mismo contenedor, antes y después en la misma sesión):

| | Antes | Después |
|---|---:|---:|
| Horneado de juego, 4 jugadores (21 poses × 116 px) | 0,84–0,88 s | 0,97–1,02 s |
| … de eso, armar la escena / render | 0,16–0,18 / 0,62–0,64 s | 0,20–0,22 / 0,71–0,73 s |
| Horneado de lobby, 4 jugadores (10 × 519 px) | 2,07 s | 2,31 s |
| Memoria de los atlas | 7,0 / 49,3 MB | igual |
| Horneado: CPU de scripts por cuadro (4 mascotas) | 0,34 ms | 0,32 ms |
| En vivo: scripts por cuadro / draw calls | 0,81 ms / 142 | 1,06 ms / 145 |

El horneado cuesta ~15 % más (la cabeza tiene más polígonos para que el borde se vea redondo de cerca y el shader hace más cuentas por píxel), y sigue siendo una vez por jugador al empezar la partida. Jugando no cambia nada: se dibuja un sprite. Las mallas siguen compartidas entre todas las mascotas, sin luces reales y con un solo shader de plástico.

## Rendimiento

Medido con `tools/mascot3d_benchmark.gd` en el contenedor de desarrollo (x86, Godot 4.4.1, renderer **Compatibility** sobre llvmpipe en xvfb, 300 cuadros por escena, 4 mascotas caminando). Mismas columnas que [PERFORMANCE.md](PERFORMANCE.md): "Scripts" es la CPU de la escena sin el render (lo que más se parece a la CPU de la TV); "Render" es el render de Godot + driver, en este contenedor **por software**, así que sirve para comparar entre filas, no como valor absoluto.

| Escena (4 mascotas) | Scripts prom. (ms) | Scripts p95 (ms) | Render prom. (ms) | Draw calls* | VRAM (MB) |
|---|---:|---:|---:|---:|---:|
| vacía (control) | 0,28 | 0,43 | 27,7 | 1 | 20,1 |
| **2D por código**, tamaño juego (u = 0,8) | 2,22 | 3,37 | 33,0 | 9 | 20,3 |
| **3D en vivo**, juego, MSAA 4× | 0,83 | 1,20 | 83,0 | 142 | 22,0 |
| 3D en vivo, juego, sin MSAA | 0,78 | 1,08 | 55,0 | 142 | 20,6 |
| **3D horneado**, juego | **0,35** | **0,56** | 27,2 | 5 | 22,4 |
| 2D por código, tamaño lobby (u = 3,6) | 2,69 | 4,03 | 44,8 | 9 | 20,6 |
| 3D en vivo, lobby | 0,85 | 1,19 | 138,3 | 142 | 56,2 |
| 3D horneado, lobby | 0,37 | 0,59 | 36,0 | 5 | 69,6 |

\* `RENDER_TOTAL_DRAW_CALLS_IN_FRAME` de Godot. En vivo cada mascota visible son ~30 piezas, ~20 con contorno (una pasada más cada una).

**Horneado** (4 jugadores, con la escena ya cargada; la primera vez además se compilan los shaders):

| Juego de poses | Poses × celda | Atlas por jugador | Tiempo total (4 jugadores) | Peor jugador | Memoria (4 jugadores) |
|---|---|---|---:|---:|---:|
| Juego (`GAME_POSES`) | 21 × 116 px | 1972 × 232 | 0,87–0,98 s | 0,22–0,27 s | **7,0 MB** |
| Lobby / podio | 10 × 519 px | 1557 × 2076 | 2,2 s | 0,56 s | **49,3 MB** |

Reparto del tiempo de un juego completo: armar la escena ~180 ms (GDScript: ~30 piezas por pose), render ~620 ms (**por software**: en una GPU real es del orden de decenas de ms), leer la textura ~15 ms y empaquetar ~50 ms (achicar 2× el supersampling y subir el atlas).

Cómo leerlo:
- **CPU por cuadro (lo que limita en la TV):** la 2D por código cuesta ~1,9 ms de scripts por encima de la escena vacía para 4 mascotas (p95 3,4 ms); en la TV (CPU 4–5× más lenta) son ~8 ms, **todo el presupuesto** de [PERFORMANCE.md](PERFORMANCE.md). Horneado cuesta ~0,07 ms (elegir la celda y mover 4 sprites): **~25 veces menos**. Este es el hallazgo más importante: el 3D horneado no solo se ve mejor, también es más barato que lo de hoy.
- **3D en vivo:** los scripts son baratos (0,5 ms, mover nodos), pero el render crece mucho: 4 viewports con ~35–50 draw calls cada uno, en cada cuadro. En una Google TV (Mali-G31, driver GLES3) cada draw call cuesta CPU del driver, que en este benchmark cae en "Render": 142 draw calls por cuadro solo en mascotas es casi el presupuesto entero de un juego (≤ 150). **No entra con holgura para 4 jugadores.**
- **Memoria:** el set del juego (7 MB para 4 jugadores) es razonable. El set del lobby a 519 px (49 MB) es demasiado para una TV de 1–2 GB: para pantallas grandes conviene hornear pocas poses (3–4) a ~360 px (≈ 2 MB por jugador) o usar render en vivo solo para 1–2 mascotas grandes (podio).
- **Tiempo de horneado:** menos de 1 s para 4 jugadores en el juego; se esconde en la intro "¿Cómo se juega?" o en la transición, y se puede hacer una vez por partida (el look no cambia durante la competencia, ver [ADR 0007](adr/0007-apariencia-del-jugador.md)).

Pendiente: medir en una Google TV real (Mobile y Compatibility) con el profiler remoto antes de integrar.

Cómo repetir las mediciones:

```bash
xvfb-run -a -s "-screen 0 1920x1080x24" godot --path . --rendering-driver opengl3 --audio-driver Dummy \
  -s res://tools/mascot3d_benchmark.gd -- --json=/tmp/m3d.json
xvfb-run -a -s "-screen 0 1920x1080x24" godot --path . --rendering-driver opengl3 --audio-driver Dummy \
  -s res://tools/mascot3d_sheet.gd -- --all=/tmp/hojas3d      # hoja, estilos, de cerca y comparación
```

## Los cuatro caminos

| | (1) 2D por código (hoy) | (2) 3D en Godot (prototipo) | (3) Modelos generados por IA | (4) Ilustrador / modelador contratado |
|---|---|---|---|---|
| **Calidad posible** | Media-alta de frente; techo cerca (el volumen es una ilusión) | Alta: volumen, brillos y contornos reales; poses 3/4 | Alta en una imagen suelta; irregular entre personajes y poses | La más alta y con identidad propia |
| **Costo** | Ya hecho | Hecho el prototipo; integrar ≈ 2–4 días | Suscripción + horas de limpieza (retopología, rig, repintado) | El más alto (≈ USD 1.500–6.000 según alcance: 1 base + 7 accesorios + expresiones + animaciones) |
| **Riesgo técnico** | Nulo | Medio: drivers GLES3 de TVs baratas, memoria de atlas, tiempo de horneado | Medio-alto: mallas sucias, sin rig, estilos que no combinan | Bajo (entrega en formato acordado) |
| **Riesgo legal / licencias** | Nulo (código propio, Fredoka OFL) | Nulo (todo por código) | **Alto:** revisar los términos de cada servicio (propiedad del resultado, uso comercial según plan, datos de entrenamiento), y en algunos países lo generado solo por IA no tiene derecho de autor (cualquiera podría copiarlo) | Bajo si el contrato cede los derechos patrimoniales y lo dice por escrito |
| **Consistencia** (7 estilos × 10 colores × ánimos) | Total | Total (mismo código y shader) | Difícil: cada generación sale distinta | Total si se pide una base común |
| **Cambios futuros** (nuevo accesorio, nuevo ánimo) | Minutos a horas, por código | Minutos a horas, por código | Volver a generar y limpiar | Volver a encargar |
| **Rendimiento en la TV** | ~40 figuras por mascota por cuadro (CPU de GDScript) | Horneado: un sprite por mascota (menos CPU que hoy); en vivo: caro | Igual que (2) si se hornea | Sprites: lo más barato |
| **Tamaño del APK** | ~0 | ~0 (código); atlas se generan en el aparato | Modelos `.glb` (≈ 0,5–2 MB c/u) | Sprites (≈ 1–5 MB según resolución) |

### (1) 2D por código
Lo que hay hoy (`PlayerAvatar` + `MascotShading`, [ADR 0004](adr/0004-sistema-visual.md)). Barato y consistente, pero cada mejora de volumen es un truco más (manchas de luz, sombras pintadas) y no puede mostrar a la mascota de costado. Sigue siendo el **respaldo** si el horneado falla en algún aparato.

### (2) 3D en Godot (este prototipo)
El mismo personaje hecho con primitivas y un material propio. Da el salto de "dibujo con degradé" a "juguete" y habilita poses nuevas sin redibujar. La clave para la TV es **no renderizar 3D en cada cuadro**: hornear al empezar la partida y dibujar sprites. Riesgos: drivers GLES3 viejos (compilación de shaders la primera vez), memoria de los atlas y el tiempo de horneado (se esconde en la intro "¿Cómo se juega?").

### (3) Modelos generados por IA (solo como opción)
Servicios como **Meshy** (texto/imagen → modelo 3D) o **SpriteCook** (imagen → sprites) pueden dar un personaje muy vistoso en minutos. Cuidados:
- **Licencias:** leer los términos vigentes de cada servicio antes de usar nada: a quién pertenece el resultado, si el plan gratuito permite uso comercial, si el servicio puede reutilizar lo que subimos. Guardar captura de los términos y del plan con la fecha en `CREDITS.md`.
- **Derecho de autor:** en varios países (ej. EE. UU.) lo generado íntegramente por IA no está protegido: no podríamos impedir que otro use nuestras mascotas. Conviene que la IA sea solo un punto de partida que una persona modifica sustancialmente.
- **Consistencia:** lograr 7 accesorios × expresiones con el mismo estilo es difícil; las mallas suelen venir sin rig, con topología sucia y texturas con luz "pintada" que no combina con el resto.
- **Parecidos:** revisar que no se parezcan a personajes de otras marcas (ver `TRADEMARKS.md`).
Si se usa, el resultado entraría por el mismo horneado (una malla `.glb` en vez de primitivas).

### (4) Ilustrador / modelador contratado
Un artista hace la mascota base y los accesorios. Para que el color siga siendo elegible (10 colores, [ADR 0007](adr/0007-apariencia-del-jugador.md)), se pide:
- **Sprites en escala de grises** del cuerpo (luces y sombras sin color) + **máscara de teñido** (qué píxeles toman el color del jugador) + capa de detalles a color fijo (cara, ojos, zapatos, interior de orejas).
- En el juego, un shader multiplica el gris por el color del jugador solo donde marca la máscara. *Ejemplo:* la misma hoja sirve para 1P rojo y para 4P verde; negro y blanco necesitan una curva de tonos especial (el gris multiplicado por negro da negro plano), como la que ya hace `toy_plastic` para los colores oscuros.
- Contrato con **cesión de derechos patrimoniales** para uso comercial, entregables editables (`.psd`/`.blend`) y hojas con las mismas columnas que `tools/character_sheet.gd`.
Es el camino de mejor calidad y más identidad; también el más caro y el más lento para cambios.

## Recomendación

**Camino 2 (3D en Godot) con horneado a atlas**, dejando la 2D por código como respaldo, y el camino 4 (ilustrador) como mejora posterior si el producto lo justifica.

Evidencia:
1. **Calidad:** en `docs/img/mascotas_3d_comparacion.png` la 3D se acerca más a la maqueta que la 2D en lo que la define: volumen, reflejos de plástico, zapatos lustrados, brazos que saludan hacia afuera, y además gira a 3/4 al caminar y mirar (`docs/img/mascotas_3d.png`, columnas "Mira" y "Paso"). Blanco y negro se leen gracias al contraluz (`docs/img/mascotas_3d_estilos.png`). Todavía no la iguala en los reflejos "pintados" y el acabado de los ojos (ver arriba).
2. **Rendimiento:** horneado, 4 mascotas cuestan ~0,07 ms de CPU por cuadro contra ~1,9 ms de la 2D por código (≈ 8 ms en la TV): libera casi todo el presupuesto de p95 ≤ 8 ms para los juegos. En vivo, en cambio, suma ~140 draw calls por cuadro: **no conviene para 4 jugadores en una Google TV de gama baja**, ni en Mobile ni en Compatibility.
3. **Costo y riesgo:** todo es código (sin licencias de terceros, sin archivos binarios de arte), consistente para 7 estilos × 10 colores y fácil de cambiar. El riesgo principal (drivers GLES3 baratos) se acota midiendo en un aparato real y cayendo a la 2D si `bake()` devuelve vacío.

Para la Google TV de gama baja: **hornear** al empezar la partida (21 poses a ~116 px para los juegos, ~7 MB para 4 jugadores) y, para lobby y podio, pocas poses a ~360 px o render en vivo de 1–2 mascotas grandes si el profiler lo permite. Renderer: el material propio (sin luces reales) da lo mismo en Mobile y en Compatibility; el horneado hace que la elección del renderer no afecte a las mascotas.

Próximos pasos: medir en la TV real (la integración en `PlayerAvatar.draw_mascot` y el horneado en el lobby y la intro ya están, ver "Integración"); y, si se quiere más identidad, encargar a un ilustrador la cara y los reflejos (camino 4) reutilizando el mismo horneado.

## El resto del diseño: piezas 3D horneadas ([ADR 0016](adr/0016-piezas-3d-horneadas.md))

Estrellas, bloques del marco del tablero y de los fondos, medallas, corona, trofeo, ficha de premio, moneda, gema y pelota se arman en 3D con **el mismo shader de plástico y el mismo contorno de tinta** que las mascotas (`core/art3d/`) y se hornean **una vez** a un atlas de 2048×644 (caché en `user://props3d/`). Hoja: `docs/img/piezas_3d.png` (arriba cada pieza; abajo, 2D de respaldo al lado de la 3D), con `tools/props3d_sheet.gd`.

- *Almohadón* (`Props3DMeshes.pillow`): un contorno plano inflado como un almohadón (el centro alto, el borde redondeado). *Ejemplo:* la estrella dorada de las esquinas es el contorno de una estrella con las puntas redondeadas, inflado 10 px de cada lado; la luz de arriba a la izquierda deja la punta de arriba clara y la de abajo a la derecha naranja.
- *Supermuestreo con alfa* (`props3d_downsample.gdshader`): se renderiza 4× más grande y cada píxel final promedia 16, pesando el color por su opacidad. *Ejemplo:* en el borde de una medalla, 8 píxeles de tinta y 8 vacíos dan tinta al 50 % (y no un gris oscuro al 50 % que se vería como un halo).
- Sin render (tests, un aparato donde falle el horneado) cada función dibuja su versión 2D de siempre.


## El tablero en 2.5D: perspectiva como la maqueta ([ADR 0019](adr/0019-tablero-25d-horneado.md))

La maqueta de Pintar el piso es una escena 3D con **cámara en perspectiva**: el tablero se aleja, el marco de bloques tiene volumen y alrededor hay juguetes fuera de foco. El juego ahora hace lo mismo sin pagar 3D por cuadro: el tablero, el marco, las esquinas con estrella y el entorno se arman en 3D con el plástico de las mascotas (`core/art3d/board_scene_25d.gd`), se **hornean una vez** a una textura de 1920 × 1080 (`board_baker_25d.gd`, caché en `user://board25d/`) y el juego se dibuja encima en 2D **proyectado con la misma cámara** (`board_view_25d.gd`): baldosas pintadas acostadas en el piso, mascotas y premios parados, más chicos atrás.

| Maqueta | Antes (plano) | Ahora (2.5D) | Lado a lado |
|---|---|---|---|
| `docs/design/referencia_juego_pintar.webp` | `docs/img/pintar_plano.png` | `docs/img/paint.png` | `docs/img/pintar_25d_comparacion.png` |

- *Homografía*: la fórmula exacta que lleva un punto del piso del juego a la pantalla a través de la cámara. *Ejemplo:* el centro de la baldosa de arriba a la izquierda, (257, 209) en el juego, se dibuja en (309, 227).
- *Profundidad de campo barata*: el entorno se renderiza aparte a media resolución y se desenfoca una vez; el tablero va nítido encima. En cada cuadro es una sola textura.
- Para comparar colores se usan las mascotas de la maqueta: rojo robot, azul oso, amarillo gato y verde brote (`tools/board25d_preview.gd -- --flat --compare=…`).

Lo que queda distinto a propósito: las mascotas se dibujan de frente (no se inclinan con la cámara) y el marco usa la paleta `UiTheme.BRICKS`. Para pasar otro juego (Arena, Esquivar, Pool…) ver [ADDING_A_MINIGAME.md](ADDING_A_MINIGAME.md#tablero-25d-horneado-adr-0019).

## Revisión de dirección de arte (29/09/2026)

Pedido del dueño: *"debería mejorar mucho más, la maqueta está mucho mejor, tiene los colores más vivos, los personajes son más lindos, seguir mejorándolo al máximo"*. Objetivo: lobby y mascotas **iguales o mejores que la maqueta**, medido y no opinado.

**Método.** La maqueta (`docs/design/referencia_lobby.webp`, 1814×867) y la captura real del lobby (`tools/capture_screens.gd --width=1920 --lobby-only`) se recortan por zonas equivalentes y se miden con Python/PIL: saturación y brillo medios (HSV), *colorfulness* (Hasler–Süsstrunk: cuánto "color" hay, 0 = gris) y los 4 colores dominantes (k-means). Zonas: cielo, fondo de juguetes, piso, tarjeta de jugador, mascota sola, fichas del código, tarjeta de juego, diorama, botón "¡A jugar!", panel izquierdo y logo.

### Medición antes de tocar nada (commit `699f795`)

| Zona | Maqueta: sat · brillo · colorf | Nuestro: sat · brillo · colorf | Dominantes maqueta → nuestro |
|---|---|---|---|
| Cielo | 0,80 · 0,83 · 99 | 0,67 · 0,81 · **40** | #2398F4 (azul vivo) → #4683CE (azul grisáceo) |
| Fondo de juguetes | 0,54 · 0,89 · 125 | 0,42 · 0,82 · 96 | #4789F0 #A388D7 → #BF7B70 #5A92D0 (lavados) |
| Piso | 0,13 · 0,98 · 19 | 0,15 · 0,88 · 18 | #E1E6FC (casi blanco azulado) → #B7C0DE (gris) |
| Tarjeta 1P | 0,27 · 0,91 · 89 | 0,32 · 0,89 · 95 | parecido; la mascota ocupa más en la maqueta |
| Mascota roja | 0,35 · 0,88 · 100 | 0,40 · 0,86 · 115 | cara blanca 52 % del recorte → 35 % |
| Fichas del código | 0,64 · 0,85 · **143** | 0,43 · 0,83 · **97** | #E69628 #1B9765 #467DD8 #EBA2CB → más pálidas, con brillo "pegatina" |
| Tarjeta de juego | 0,34 · 0,86 · 92 | 0,33 · 0,86 · 90 | igual |
| Diorama Arena | 0,52 · 0,83 · 119 | 0,48 · 0,86 · 114 | parecido |
| Botón "¡A jugar!" | 0,76 · 0,88 · 122 | 0,65 · 0,89 · 113 | #F7B41D → #F1AF2B con más blanco encima |
| Panel izquierdo | 0,24 · 0,92 · 79 | 0,17 · 0,90 · 56 | #F7FAFE + lavanda #A4AAD2 → blanco plano |
| Logo | 0,75 · 0,78 · 165 | 0,70 · 0,75 · 148 | igual (es la misma imagen; difiere el fondo) |

### Diferencias priorizadas (qué, dónde, cuánto)

1. **Cielo y fondo lavados** (`UiTheme.BG_SKY_*`, `BG_HAZE`, `BG_VIGNETTE`, `PartyBackground`): la maqueta tiene un azul saturado (#2398F4, colorfulness 99) y el nuestro es la mitad de colorido (40). Las torres de juguete están mezcladas con bruma (#BF7B70 en vez de #F0524F). Es la diferencia más grande de "colores vivos".
2. **Personajes** (`Mascot3D`): en la maqueta la cabeza es casi toda la tarjeta y la cara blanca cubre ~52 % del recorte (35 % en la nuestra); ojos negros grandes y altos con reflejo chico; cuerpo casi escondido; una mano bien arriba. Las nuestras muestran el cuerpo y los zapatos enteros, saludan con las dos manos y los reflejos son manchas blancas grandes (más "vidrio" que "plástico mate brillante").
3. **Fichas del código** (`draw_toy_tile`, `code_tile_color`): colorfulness 97 contra 143. Están aclaradas arriba (`TOY_TOP_LIGHT` 0,22), con un brillo ancho al 55 % y un reflejo chico "de pegatina". La maqueta: color pleno, degradé suave y letra blanca con contorno gris oscuro.
4. **Botón "¡A jugar!"**: saturación 0,65 contra 0,76 por el mismo brillo blanco encima.
5. **Panel izquierdo**: la maqueta es blanco con un tinte lavanda y filas #E9EDFB; el nuestro es blanco plano (colorfulness 56 contra 79).
6. **Piso**: la maqueta es casi blanco azulado (brillo 0,98); el nuestro gris (0,88).
7. **Tarjetas de jugador**: parecidas; en la maqueta la etiqueta 1P está más adentro de la esquina y la mascota más grande.

### Qué cambió (vueltas 1–4: corregir, capturar, medir, repetir)

- **Fondo y cielo vivos** (`UiTheme.BG_SKY_TOP` #3C8CE6 → #1F8BEF, `BG_SKY_MID` → #43ADF8, `BG_HAZE` #D3E9FF → #B2DBFF celeste en vez de blanco, `BG_GLOW` 0,42 → 0,26, `BG_VIGNETTE` 0,30 → 0,20, bruma de las torres `BG_HAZE_FAR/NEAR` 0,42/0,2 → 0,3/0,1, piso `BG_FLOOR_A/B` más claros y azulados; `SKY_TOP/BOTTOM` del celular y del cielo liso también). La saturación del cielo pasó de 0,67 a 0,79 (maqueta 0,80).
- **Fichas del código y botones** (`TOY_TOP_LIGHT` 0,22 → 0,1, `TOY_GLOSS` 0,55 → 0,26, `TOY_SPEC` 0,85 → 0,5; `CODE_TILE_COLORS` dorado #FFB728, verde, azul y rosa como la maqueta; `START_TOP/BOTTOM` un poco más naranjas). El botón "¡A jugar!" pasó de saturación 0,65 a 0,75 (maqueta 0,76).
- **Panel izquierdo:** `PAPER_DIM` #EEF2FA → #EAEEFB (filas lavanda como la maqueta).
- **Mascotas** (`Mascot3D`): cara más grande y más baja (`FACE_R` 2,98×2,2 → 3,28×2,4; llega casi al mentón, como la maqueta), ojos más altos y angostos (0,6×0,92 → 0,53×1,0) con reflejos más chicos (se leen negros y profundos), sonrisa cerrada nueva (`mouth_smile`) para el ánimo normal cuando saluda, plástico un poco más saturado (`vivid`: s×1,14+0,08) y sombra más profunda (`plastic_ramp`: v×0,46).
- **Pose "¡hola!"** (`anim["hello"]` en `Mascot3D.pose/apply`, `Mascot3DBaker.POSES` "hello"/"hello_happy", `MascotAtlas` "hello@M" (un solo cuadro, quieta como la maqueta: +2 poses de pantalla por jugador, ≈ +0,7 MB), `PlayerAvatar.hello`): una mano bien arriba al costado de la cabeza, a la altura de los ojos y por delante (el hombro se adelanta 1,1 u para que el brazo no quede tapado por la cabeza), brazo estirado ×4,4 y más gordo (una manga, no un palito), manopla ×1,45. Alternado por estilo (`hello_side`): antena y gato la mano izquierda de la pantalla; oso y brote la derecha, como en la maqueta. Está en `SCREEN_POSES` (se precalienta en el lobby). En 2D de respaldo se dibuja como el saludo `greet`.
- **Tarjeta del jugador** (`SeatCard`): la cabeza queda **adentro** de la tarjeta (medido en la maqueta: la cabeza es el 69 % del ancho y empieza ~20 px bajo el borde; antes sobresalía 44 px), el mentón apoya en la base del nombre y el cuerpo queda detrás (`MASCOT_TOP` 16, `MASCOT_SINK` 50, `OVERHANG` 44 → 28). La base del nombre pasó a su propia capa encima de la mascota (`SEAT_NAME_BASE_TOP/BOTTOM`). Listo = "¡hola!"; 1P y 3P con cara normal sonriente, 2P y 4P feliz con cachetes (como la maqueta).

### Medición después (misma captura y zonas; commit final de esta revisión)

| Zona | Maqueta: sat · brillo · colorf | Antes | Después | Dominantes después |
|---|---|---|---|---|
| Cielo | 0,80 · 0,83 · 99* | 0,67 · 0,81 · 40 | **0,79 · 0,87 · 71** | #2984DD #2F89E0 (azul vivo, sin gris) |
| Fondo de juguetes | 0,54 · 0,89 · 125 | 0,42 · 0,82 · 96 | **0,48 · 0,84 · 112** | #CE7E68 #469AE1 (menos bruma) |
| Piso | 0,13 · 0,98 · 19 | 0,15 · 0,88 · 18 | 0,13 · **0,93** · 19 | #C7CFED #D7DCEE |
| Tarjeta 1P | 0,27 · 0,91 · 89 | 0,32 · 0,89 · 95 | 0,38 · 0,89 · 114 | la mascota ocupa más (como la maqueta) |
| Mascota roja | 0,35 · 0,88 · 100 | 0,40 · 0,86 · 115 | 0,45 · 0,89 · 128 | #F05252 rojo vivo, cara blanca 36 % |
| Fichas del código | 0,64 · 0,85 · 143 | 0,43 · 0,83 · 97 | **0,46 · 0,82 · 105**† | #E0AA3D #3D7F68 (color pleno) |
| Tarjeta de juego | 0,34 · 0,86 · 92 | 0,33 · 0,86 · 90 | 0,35 · 0,86 · 95 | igual |
| Diorama Arena | 0,52 · 0,83 · 119 | 0,48 · 0,86 · 114 | **0,51 · 0,86 · 122** | regenerado con el plástico nuevo |
| Botón "¡A jugar!" | 0,76 · 0,88 · 122 | 0,65 · 0,89 · 113 | **0,75 · 0,89 · 123** | #F1A91E #FDD24D |
| Panel izquierdo | 0,24 · 0,92 · 79 | 0,17 · 0,90 · 56 | 0,19 · 0,89 · 60 | filas lavanda |

\* La zona de cielo de la maqueta incluye parte de su barra superior oscura (no existe en la TV), que infla el *colorfulness*. † La zona de las fichas de nuestra captura incluye más panel blanco alrededor que la de la maqueta (fichas más chicas respecto del panel); medidas sobre la ficha sola, las nuestras son color pleno (#FFB728, #3CC46B, #3E7BFA, #F26CB5) como las de la maqueta.

Comparaciones: `docs/img/lobby_comparacion.png` (maqueta · antes · ahora), `docs/img/mascotas_3d_comparacion.png` y `docs/img/mascotas_3d_detalle.png` (2P a la misma escala que la maqueta). Rendimiento en [PERFORMANCE.md](PERFORMANCE.md#revisión-de-dirección-de-arte-2909) (sin cambio de CPU ni draw calls; +2,6 MB de atlas por la pose "¡hola!").

**Qué queda distinto de la maqueta (a propósito o pendiente):** la barra superior de desarrollo no va en la TV; la mascota anfitriona de abajo a la izquierda sigue festejando con los dos brazos; los dioramas usan el cuarteto de mascotas de siempre y no los looks elegidos.
