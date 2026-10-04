# ADR 0016 · Piezas del escenario y de la UI en 3D, horneadas a un atlas

- **Estado:** Aceptada
- **Fecha:** 2026-09-27
- **Relacionados:** [ADR 0012](0012-mascotas-3d.md) (mascotas 3D horneadas; este ADR es el punto 3 de su "Plan de adopción"), [ADR 0009](0009-arte-de-los-juegos.md) (arte de los juegos), [ADR 0008](0008-fondo-escenario-desenfocado.md) (fondo), [ADR 0006](0006-rendimiento-capas-cacheadas.md) (capas cacheadas).

## Contexto
El dueño pidió "las mascotas y el diseño en 3D como en las maquetas o mejor". Las mascotas ya tienen su pipeline 3D (ADR 0012), pero el resto del arte seguía en 2D con bisel pintado: estrellas de las esquinas del tablero y de Arena, bloques del marco, medallas del resumen y del podio, corona del ganador, ficha de premio de Pintar el piso, pelota de Ping Pong y los bloques de juguete de los fondos. Al lado de mascotas con brillo de barniz y contorno de tinta, esas piezas planas desentonan con las maquetas (`docs/design/referencia_juego_pintar.webp`, `referencia_lobby.webp`).

## Decisión
1. **Piezas armadas por código** en `core/art3d/` (`Props3D` + `Props3DMeshes`): estrella "almohadón" (contorno de estrella con puntas redondeadas inflado con perfil de elipse), ladrillo con cantos redondeados (normales exactas), bloque de juguete con cuatro botones, disco con aro (medallas oro/plata/bronce, moneda, ficha de premio), gema tallada (caras planas), corona, trofeo y pelota. Catálogo de datos puros (`Props3D.catalog()`), 53 piezas.
2. **El mismo material que las mascotas**: los shaders `core/mascot3d/toy_plastic.gdshader` y `ink_outline.gdshader` se reutilizan tal cual (sin editarlos); `Props3D` solo elige los parámetros (plástico, metal, estrella con sombra naranja, gema).
3. **Horneado una vez a un atlas** (`Props3DBaker`): todas las piezas en un mundo 3D, una cámara ortográfica que lo recorre de a azulejos de 512 px renderizados al 4× y achicados con un shader que promedia el alfa bien (`props3d_downsample.gdshader`: bordes limpios, sin halo oscuro). Resultado: un atlas de 2048×644 con mipmaps, dibujado con `CanvasTexture` (filtro lineal con mipmaps: una estrella de 80 px dibujada a 11 px no titila).
4. **Caché en disco** (`user://props3d/atlas_<firma>.png` + `.json`): la TV hornea la primera vez (~0,9 s en xvfb/llvmpipe) y después lee el PNG al arrancar (≈ 36 ms, antes de armar el lobby). La firma cambia si cambia una receta o un color (`Props3D.signature()`).
5. **Integración con respaldo 2D**: `Props3D.draw(ci, pieza, rect)` devuelve false si no hay atlas y el que llama dibuja su 2D de siempre. Así en `--headless` (tests), en un aparato donde el horneado falle o con `Props3D.enabled = false`, todo se ve como antes. Usan el atlas: `UiTheme.draw_star`/`draw_medal`, `GameArt.paint_board` (bloques y esquinas), el ícono estrella del marcador, el escenario de los juegos (`GameArt.stage_texture`: bloques y estrellas pegados en la imagen), `PartyBackground` (torres y estrellas del fondo), las estrellas de Arena, la ficha de Pintar el piso, la pelota de Ping Pong, las medallas de `ScorePedestal` y del podio, la corona y dos trofeos junto al título del podio.
6. **Lo fijo se sigue cacheando** (ADR 0006): el tablero, el escenario y el fondo se dibujan una vez; cuando el atlas queda listo (primer arranque) se avisa al grupo `props3d` y se pide redibujar todo una vez.

## Motivos
- Mismo acabado de juguete que las mascotas (brillo nítido, barniz, contraluz, contorno de tinta) con un solo lugar para el look.
- En cada cuadro cuesta lo mismo que un sprite: los bloques del marco pasan de ~5 figuras con bisel cada uno a un rectángulo de textura, todos del mismo atlas (el motor los junta en un draw call).
- Sin archivos de arte ni licencias: todo es código; el APK no crece (el atlas se genera en el aparato).

## Consecuencias
- **Memoria**: atlas 2048×644 RGBA con mipmaps ≈ 7,0 MB en la GPU (5,3 MB sin mipmaps) + ≈ 0,6 MB de imágenes chicas en RAM (bloques y estrella para componer el escenario). Transitorio al hornear: un render de 2048×2048 (color + profundidad ≈ 32 MB) y uno de 512×512.
- **Tiempo**: primer arranque ~0,9 s de horneado (8 azulejos, 2 cuadros cada uno) tapado por la presentación; después, lectura del PNG. Detalle en `docs/PERFORMANCE.md`.
- Draw calls: el tablero pasa de 1 a 4 comandos (lote, bloques, lote, esquinas); los juegos siguen muy por debajo de 150.
- La cámara del horneado va muy lejos (100 000 u): el shader de plástico calcula la vista desde cada punto aunque la cámara sea ortográfica, y con la cámara cerca una pieza que cruzaba dos azulejos mostraba un escalón de luz.
- El celular sigue en 2D (no hornea): su pantalla de resultado usa `draw_medal`/`draw_star` y cae en el respaldo. Se puede sumar con `Props3DBaker.ensure()` en `ControllerMain` si se quiere.
- Si cambian los parámetros o uniforms del shader de las mascotas, las piezas los siguen (mismo shader), pero los parámetros que setea `Props3D` tienen que coincidir con los uniforms.

## Alternativas descartadas
- **Render 3D en vivo** de las piezas: un viewport 3D más por pantalla y draw calls por pieza en cada cuadro; no entra en el presupuesto de la TV de gama baja.
- **Hornear cada pieza en su propia textura**: cada textura corta el lote (un draw call por bloque del marco).
- **Un solo render grande sin azulejos**: al 4× el atlas pediría una textura de 8192 px; muchas GPU de TV aceptan 2048–4096.
- **Supermuestreo con `Image.resize`**: más lento (CPU) y deja un borde oscuro (el promedio con el vacío transparente); el shader promedia con el alfa y deja la tinta en lo vacío para los mipmaps.
