# ADR 0008 · Fondo de la TV: escenario prerenderizado y desenfocado

- **Estado:** Aceptada
- **Fecha:** 2026-09-27

## Contexto
El fondo de las pantallas de la TV (lobby, intro, resumen, podio) era plano: cielo en degradé, torres de cuadrados, piso a cuadros sin perspectiva y una fila de bloques nítidos arriba y abajo. La maqueta aprobada (`docs/design/referencia_lobby.webp`) muestra un escenario de fiesta con profundidad, **desenfocado detrás de la UI**, como en los party games de consola. Además, las torres y bordes seguían costando ≈ 160 draw calls fijos por frame (ADR 0006 dejó "renderizar el fondo a una textura" como próximo paso, descartado entonces por la resolución: hasta 4K y alfa premultiplicado).

## Decisión
- `PartyBackground` pinta el escenario **una vez** en un `SubViewport` a **media resolución lógica** (960 × 540 para 1080p) y otro `SubViewport` lo desenfoca una vez con `core/ui/shaders/soft_blur.gdshader` (gaussiano 7 × 7). Los dos quedan en `UPDATE_ONCE` y no vuelven a dibujar salvo que cambie el tamaño o las capas. En pantalla es un solo `TextureRect`.
- Como está desenfocado, la media resolución no se nota (ni en 4K) y la textura es **opaca** (el cielo va adentro): no hay problema de alfa premultiplicado. Memoria: dos texturas de ≈ 2 MB.
- El escenario: cielo en tres paradas, luz ambiente y haces de luz, nubes lejanas, estrellas, torres de bloques con volumen (frente, tapa y costado que mira al centro, brillo y botón arriba) en dos planos, luces de colores (bokeh), piso a cuadros en perspectiva que se funde con la bruma y viñeta. Colores mezclados con la bruma (`UiTheme.BG_HAZE_*`) para no competir con la UI.
- Lo que se mueve (nubes que cruzan y brillos que titilan) son `Sprite2D` con texturas **generadas por código** una vez por proceso (sin archivos que importar). En cada frame solo cambian posición, escala y transparencia: no hay `_draw()` por frame.
- Se sacan de la TV las filas de bloques nítidos de arriba y abajo (la maqueta no las tiene); `bricks` sigue existiendo, apagado por defecto.
- El celular sigue con **solo el cielo** (sin escenario, sin SubViewport, sin brillos) y las nubes a `anim_fps`.
- Tokens nuevos en `UiTheme`, sección "Fondo (agente)".

## Motivos
- Profundidad y "ambiente de consola" como en la maqueta, con la UI destacando por contraste de nitidez y de saturación.
- Menos CPU y draw calls en los menús: el fondo pasa de ≈ 175 draw calls por frame a ≈ 10, y de redibujar las nubes en GDScript en cada frame a mover nodos (ver `docs/PERFORMANCE.md`).
- También baja el render: el fondo es un solo cuadro con textura en vez de cientos de figuras con mezcla alfa.

## Alternativas descartadas
- **Desenfoque en cada frame** (shader sobre el fondo en vivo): en una GPU Mali-G31 un desenfoque de pantalla completa por frame es caro; hacerlo una vez es gratis.
- **Desenfoque en CPU** (`Image`): segundos en GDScript para una imagen de 960 × 540; la GPU lo hace en un frame.
- **Leer la textura a la CPU (`get_image`) y guardar un `ImageTexture`**: obliga a sincronizar con la GPU y no aporta nada: la `ViewportTexture` queda fija mientras el viewport no se actualice.
- **Arte en PNG**: no hay ilustrador todavía (ADR 0004); el escenario sigue saliendo de tokens y se puede reemplazar por una imagen sin tocar pantallas.

## Consecuencias
- Durante el primer par de frames (mientras se prepara) se ve el cielo liso de siempre; nunca un cuadro negro.
- Al cambiar el tamaño de la ventana se vuelve a preparar (3 frames).
- Si en el futuro llega un fondo ilustrado, se reemplaza `_paint_scene` por dibujar esa imagen y se conserva el desenfoque.
