# ADR 0019 · Tablero "2.5D horneado": escenario 3D con cámara en perspectiva, juego en 2D proyectado

- **Estado:** Aceptada (integrada en Pintar el piso)
- **Fecha:** 2026-09-29
- **Relacionados:** [ADR 0009](0009-arte-de-los-juegos.md) (arte de los juegos: descartaba la perspectiva por costo), [ADR 0012](0012-mascotas-3d.md) (mascotas 3D horneadas), [ADR 0016](0016-piezas-3d-horneadas.md) (piezas 3D horneadas), [ADR 0018](0018-dioramas-de-los-juegos.md) (dioramas del lobby: misma idea de fondo desenfocado y frente nítido), [ADR 0006](0006-rendimiento-capas-cacheadas.md) (capas cacheadas).

## Contexto
El dueño siente que Pintar el piso está "muy alejado" de su maqueta (`docs/design/referencia_juego_pintar.webp`). La diferencia principal no es de detalle sino de **técnica**: la maqueta es una escena 3D vista con una **cámara en perspectiva** (el tablero se aleja: la fila de atrás es ~13 % más angosta que la de adelante), con un marco grueso de bloques de plástico con volumen, sombra debajo del tablero y un mundo de juguetes alrededor, desenfocado. El juego era un tablero plano visto desde arriba (`GameArt.paint_board`) con volumen pintado. El ADR 0009 había descartado la perspectiva porque "obliga a transformar posiciones, choques y dibujo de todos los juegos".

Restricción: 60 fps en una Google TV de gama baja (p95 de Scripts ≤ 8 ms y ≤ 150 draw calls en el benchmark, [PERFORMANCE.md](../PERFORMANCE.md)).

## Decisión
**"2.5D horneado"**: el escenario es 3D, se renderiza **una vez** a una textura; la jugabilidad sigue en 2D y se **proyecta** con la misma cámara.

1. **Escena 3D por código** (`core/art3d/board_scene_25d.gd`, `Board25DScene`): base del tablero, 220 baldosas a cuadros con cantos redondeados, marco de bloques arcoíris que sobresale del piso, esquinas más altas con estrella dorada, sombra del marco sobre el piso y un entorno de juguetes (bloques con botones, estrellas, bandera, piso de la sala). Mismo plástico y contorno de tinta que las mascotas (`toy_plastic.gdshader` + `ink_outline.gdshader`, sin editarlos); los parámetros los elige la escena.
2. **Cámara en perspectiva** (`core/art3d/board_view_25d.gd`, `BoardView25D`): 65° sobre el piso, 28° de campo de visión, a 2182 unidades (tokens `UiTheme.BOARD25D_*`), ajustada para que el tablero ocupe lo mismo que en la maqueta. Da la **homografía** plano → pantalla (exacta: el piso es un plano) y, para cada punto, su aproximación lineal (`floor_xform`: error < 0,5 px en las esquinas de una baldosa).
3. **Horneado** (`core/art3d/board_baker_25d.gd`, `Board25DBaker`): el entorno se renderiza a media resolución y se desenfoca en la placa (profundidad de campo); el tablero se renderiza nítido con supermuestreo 2× en 2 × 2 azulejos (frustum corrido: la textura de render más grande es de 1920 × 1080). Se compone en una imagen RGB de 1920 × 1080 y se guarda en `user://board25d/` con una firma (cámara, tokens, receta, código de los shaders): después se lee del disco en un hilo aparte. Se pide durante la intro "¿Cómo se juega?" (`MiniGame.prewarm_art`) y se suelta cuando sale el último juego que la usa.
4. **Dibujo por cuadro** (Pintar el piso): la textura es el fondo (`MiniGame.draw_board_25d`, 1 draw call, en la capa cacheada). Encima, en 2D: baldosas pintadas acostadas en el piso (la plantilla de siempre con `cell_xform`, un lote por fila como antes), sombra del premio acostada, mascotas y premios parados en `project(p)` escalados por profundidad (`scale_at`, con tope para no cambiar el tamaño de horneado de la mascota), ordenados de atrás hacia adelante, y globitos 1P–4P y nombres encima. Reglas, choques, celdas, tests y bots siguen en las coordenadas planas de `FIELD`.
5. **Respaldo plano**: sin render (`--headless`, tests), mientras se hornea o lee, si el horneado falla o con `Board25DBaker.enabled = false`, el juego se dibuja exactamente como antes.

## Números (contenedor de desarrollo, xvfb + llvmpipe: render por software)
- **Horneado** (primera vez en el aparato): 0,9–1,0 s en total (armar la escena ~85 ms, entorno ~190 ms, desenfoque ~180 ms, tablero ~400–430 ms, componer ~50–70 ms). Después, **lectura del disco: ~45 ms** (38 ms leer el PNG en un hilo + 7 ms subirlo).
- **Memoria**: textura de 1920 × 1080 RGB = 6,2 MB (8,3 MB si el driver la guarda como RGBA), solo mientras se juega (y 2 s después). Transitorio del horneado ≈ 35 MB (render de 1920 × 1080 con profundidad, imágenes intermedias).
- **Por cuadro** (`tools/benchmark.gd -- --only=paint,arena --board=both`, misma corrida): Pintar el piso plano → 2.5D: Scripts p95 2,62 → **1,70 ms**, draw calls 53 → **44**, render 29,0 → **18,5 ms**; Arena (control) 1,94 ms / 35 draw calls. El 2.5D es **más barato** que el plano: el fondo es un rectángulo con textura en vez de cielo + escenario + tablero en lotes. Tabla completa en [PERFORMANCE.md](../PERFORMANCE.md#tablero-25d-horneado-adr-0019).

## Alternativas
- **3D en vivo** (la escena 3D renderizada en cada cuadro, las mascotas como sprites o modelos): lo más fiel y con luz dinámica, pero ~600 piezas con contorno son ~1200 draw calls por cuadro, más el costo del driver GLES3 de la TV. No entra en 150 draw calls; ni con MultiMesh (el contorno de casco invertido duplica todo y cada material es un lote).
- **2D plano mejorado** (lo que había, ADR 0009): barato y probado, pero no tiene perspectiva ni profundidad; es justamente la diferencia que marcó el dueño.
- **Arte pintado** (un ilustrador dibuja el tablero y el entorno en perspectiva): puede quedar igual a la maqueta, pero cuesta dinero y tiempo por cada juego, no sigue los tokens de color (cambiar el marco pide redibujar) y hay que calzar la grilla del juego a mano sobre la ilustración. El horneado da lo mismo desde el código, con la cámara exacta.
- **Renderizar el tablero plano a una textura y deformarla con un shader en cada cuadro**: reutiliza todo el dibujo 2D, pero agrega un pase de pantalla completa por cuadro (costoso en una GPU Mali-G31) y deja borroso lo que se agranda.

## Consecuencias
- **Reutilizable**: otro juego con tablero (Arena, Esquivar, Pool…) define `static func board_view()` y `prewarm_art()`, llama `draw_board_25d(board_view())` en `_draw()` y pasa sus posiciones por `project`/`scale_at`/`floor_xform`. Guía: [ADDING_A_MINIGAME.md](../ADDING_A_MINIGAME.md#tablero-25d-horneado-adr-0019). Una receta de escenario distinta (ej. arena redonda) se suma en `Board25DScene` con otro `recipe`.
- La textura se genera en el aparato (el APK no crece) y se lee de `user://` después de la primera vez; cambiar la cámara, un token `BOARD25D_*`, los shaders o `Board25DBaker.VERSION` invalida la caché.
- Las mascotas se dibujan de frente (como billboards), no giradas por la cámara; en perspectiva real se inclinarían apenas. Con la escala por profundidad entre 0,93 y 1,07 siguen usando el mismo tamaño de horneado del atlas (ADR 0012).
- Los efectos (partículas, textos flotantes, confeti) usan posiciones proyectadas; los juegos que pasen al 2.5D tienen que proyectar todo lo que dibujen en el piso.
- Lo que cambia con el juego no puede ir en la textura (se hornea una vez): obstáculos móviles o destructibles se dibujan en 2D proyectado.
- El celular no cambia (no hornea).
