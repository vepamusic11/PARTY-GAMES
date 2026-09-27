# Arte de las mascotas: cómo llegar a la calidad de la maqueta

La maqueta de mascotas (`docs/design/referencia_mascotas.webp`) muestra personajes con acabado de **juguete de plástico 3D**: volumen real, reflejo chico y nítido, brillo ancho de barniz, luz de contorno, zapatos lustrados y un contorno de tinta grueso. Este documento compara cuatro caminos para llegar ahí (o superarla), con un **prototipo 3D real** hecho en Godot para medir en vez de suponer. La decisión queda en [ADR 0012](adr/0012-mascotas-3d.md) (estado: propuesta).

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
| `mascot_3d.gd` (`Mascot3D`) | Arma la mascota con primitivas: cabeza (esfera achatada), cara blanca (almohadilla que sigue la superficie de la cabeza), ojos ovalados con dos reflejos, cuerpo (superficie de revolución más ancha abajo) con gema, brazos cápsula, piernas y zapatos, y los 7 accesorios (antena, oso, gato, brote, robot, cuernos, conejo). `apply(mood, anim)` recibe las mismas claves que `PlayerAvatar.draw_mascot` (`t`, `walk`, `look`, `squash`, `wave`) más `blink` y `bob`. Ojos y bocas de cada ánimo son mallas que se prenden y apagan. |
| `mascot3d_meshes.gd` | Recetas de mallas por código: esfera, torno (`lathe`), tubo con radio variable (antena, cuernos que se afinan, arcos de los ojos felices, cejas), figura plana con espesor (bocas) y la almohadilla de la cara. En caché: todas las mascotas comparten buffers. |
| `toy_plastic.gdshader` | Plástico de juguete: rampa sombra→color→luz (mismos colores que la 2D), relleno, rebote del piso, contraluz, brillo nítido y brillo de barniz. Sin luces reales. |
| `ink_outline.gdshader` | Contorno por casco invertido, inflado en el plano de la pantalla y medido en unidades del mundo: 3 u como en 2D, a cualquier resolución. |
| `mascot3d_baker.gd` (`Mascot3DBaker`) | `bake(host, look, poses, cell_px) -> Dictionary[String, Texture2D]`: hornea las poses en un atlas (una grilla, un render, supersampling 2×). `POSES` y `GAME_POSES` traen las poses con nombre; `feet_offset()` dice dónde quedan los pies en la celda. |
| `mascot3d_live.gd` (`Mascot3DLive`) | Camino "en vivo": `Sprite2D` con su propio `SubViewport` 3D que se renderiza en cada cuadro. |
| `tools/mascot3d_sheet.gd` | Hojas: mismas columnas que `tools/character_sheet.gd` (y `--styles`, `--closeup`, `--compare`, `--standard`, `--all=DIR`). |
| `tools/mascot3d_benchmark.gd` | Mide 2D vs 3D en vivo vs horneado, y el horneado. |

Nada de esto lo usa el juego todavía (ni `PlayerAvatar` ni los minijuegos). El test `test_mascot3d_prototype` arma todas las combinaciones de estilo y ánimo y ejerce el horneado (sin pantalla solo verifica que arma la escena).

### Qué se ganó frente a la 2D

- **Volumen de verdad:** cada pieza tiene su luz según su orientación (la oreja de oso inclinada, el brazo que se levanta, el zapato que se adelanta al caminar).
- **Poses que en 2D no existen:** en "Mira" y "Paso 1/2" la mascota gira la cabeza o el cuerpo hacia donde va (vista 3/4): se ve el costado de la cara y la antena de perfil. En 2D solo se corrían los ojos.
- **Contornos que siguen la pose:** los brazos por delante del cuerpo, la oreja por detrás de la cabeza, sin reordenar nada a mano.
- **Consistencia:** los 7 estilos × 10 colores salen del mismo material; blanco y negro se leen gracias al contraluz y al borde de la cara.

### Lo que todavía no alcanza a la maqueta

- La maqueta tiene reflejos "pintados" (bandas de luz, reflejo del cielo) y una textura de plástico que un shader simple no copia del todo.
- Los ojos y la boca felices son tubos: se ven bien, pero un ilustrador los dibujaría con más intención (grosor variable).
- Sin sombras propias (la cabeza no oscurece el cuerpo): se aproxima con el rebote y la rampa. Se podría hornear oclusión ambiental más adelante.

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

Próximos pasos (fuera de este prototipo): medir en la TV real; integrar en `PlayerAvatar.draw_mascot` con el atlas del jugador (el *squash* y el salto siguen siendo transformaciones 2D sobre el sprite); hornear en la intro; y, si se quiere más identidad, encargar a un ilustrador la cara y los reflejos (camino 4) reutilizando el mismo horneado.
