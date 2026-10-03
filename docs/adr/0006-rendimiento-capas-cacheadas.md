# ADR 0006 · Rendimiento: capas cacheadas, figuras en lote y bajo consumo en el celular

- **Estado:** Aceptada
- **Fecha:** 2026-09-26

## Contexto
Todo se dibuja por código (ADR 0004). El fondo de la TV y los juegos se redibujaban completos en cada frame: cientos de rectángulos, círculos y polígonos que no cambian, cada uno con su propio buffer y draw call. El objetivo es 60 fps estables en una Google TV de gama baja y poco consumo de batería en el celular. `tools/benchmark.gd` mostró que la CPU de scripts del lobby era ~3,9 ms por frame en una máquina x86 (varias veces más en la TV) y que había hasta 790 draw calls por frame.

## Decisión
- **Lo que no cambia va en un nodo hijo que no se redibuja**: `PartyBackground._front` (torres, piso, bordes); en `MiniGame`, `draw_sky()`/`draw_play_field()` registran la capa en un hijo interno `_backdrop` (detrás del juego) y `draw_hud()` en `_hud` (delante), que se redibujan solo si cambian sus datos. La API de los juegos no cambia.
- **`UiTheme.ShapeBatch`**: junta figuras rellenas consecutivas en un solo `canvas_item_add_triangle_array` con la misma geometría que `draw_circle`/`draw_colored_polygon`. Se usa en mascotas (respetando el transform de *squash & stretch*), estrellas, chips, nubes y lunares. Los círculos se calculan con el mismo redondeo a float de 32 bits que el motor para dar los mismos vértices.
- **Juegos con fondo propio** (Empujones, Pintar el piso): el mismo criterio dentro del juego, con capas que se redibujan solo cuando cambia lo que muestran (ver `docs/PERFORMANCE.md`).
- **Nodos ocultos no animan** (`_process` apagado según `is_visible_in_tree()`).
- **Celular**: sin control en pantalla, animaciones a 30 fps (la mascota de espera saluda: a menos se vería a saltos) y `OS.low_processor_usage_mode`; con un control activo, 60 fps normales.
- Medir siempre con `tools/benchmark.gd` antes y después (ver `docs/PERFORMANCE.md`).

## Motivos
- Mismo resultado visual (hoja de personajes: 0 píxeles distintos), con menos de la mitad de CPU por frame en menús, ~30 % menos en los juegos con campo y marcador comunes y entre 25 % y 56 % menos draw calls.
- Sin cambiar la API de `MiniGame` ni de `UiTheme`: los juegos existentes y nuevos se benefician solos.

## Alternativas descartadas
- **Renderizar el fondo a una textura (SubViewport)**: 1 draw call en vez de ~160, pero con el estiramiento `canvas_items` hay que generarla a la resolución real (hasta 4K, ~33 MB) y componerla con alfa premultiplicado; riesgo de diferencias visuales. Queda como próximo paso si hace falta. *(Hecho después, desenfocado y a media resolución: ver [ADR 0008](0008-fondo-escenario-desenfocado.md).)*
- **Mascotas y marcador como nodos con sprites**: cambia la estructura de todos los juegos; mejor cuando llegue arte definitivo.
- **Bajar los fps del celular también durante el juego**: aumentaría la latencia del input.

## Consecuencias
- `draw_sky()`/`draw_play_field()` quedan siempre detrás de todo lo que dibuja el juego y `draw_hud()` delante (antes dependía del orden de las llamadas; todos los juegos ya las usaban así).
- Los juegos tienen dos hijos internos (`INTERNAL_MODE`): no aparecen en `get_children()`.
- El modo de bajo consumo es global del proceso: el control solo lo activa si es la raíz de la ventana (no en capturas ni tests, donde la TV corre en el mismo proceso).
