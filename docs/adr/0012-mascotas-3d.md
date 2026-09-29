# ADR 0012 · Mascotas 3D renderizadas por Godot y horneadas a sprites

- **Estado:** Aceptada (27/09/2026, decisión del dueño: "las mascotas y el diseño en 3D como en las maquetas o mejor")
- **Fecha:** 2026-09-27
- **Relacionados:** [ADR 0004](0004-sistema-visual.md) (sistema visual dibujado por código), [ADR 0006](0006-rendimiento-capas-cacheadas.md) (rendimiento), [ADR 0007](0007-apariencia-del-jugador.md) (color y estilo), `docs/PLAN.md` ("¿Conviene usar heightfields?": recomienda 2.5D), análisis completo en [docs/ARTE.md](../ARTE.md).

## Contexto
La maqueta de mascotas (`docs/design/referencia_mascotas.webp`) tiene acabado de **juguete 3D brillante**: volumen real, reflejos nítidos, brillo de barniz, luz de contorno y un contorno de tinta que se adapta a la pose. Las mascotas de hoy son 2D por código con degradé por vértice (`PlayerAvatar` + `MascotShading`): se ven bien de frente, pero el volumen es una ilusión (un círculo sombreado) y no pueden girar, mirar de costado ni mostrar las piezas encimadas con su propia luz.

Hay que elegir cómo llegar a la calidad de la maqueta. Opciones evaluadas (detalle, costos y licencias en `docs/ARTE.md`): (1) seguir mejorando el 2D por código, (2) 3D en Godot con primitivas (este prototipo), (3) modelos generados por IA, (4) ilustrador/modelador contratado.

## Decisión
**Camino 2 con horneado**, manteniendo el 2D actual como respaldo mientras tanto:

1. **Mascotas 3D armadas por código** en `core/mascot3d/` (`Mascot3D`): esferas, tubos y superficies de revolución; mismas proporciones, 7 accesorios, 10 colores, ánimos y parámetros de animación que `PlayerAvatar`.
2. **Material propio** (`toy_plastic.gdshader`, sin luces reales): rampa de color como la 2D + brillo especular nítido + brillo ancho tipo barniz (*clearcoat*) + contraluz (*rim light*) + rebote del piso. **Contorno** por casco invertido (`ink_outline.gdshader`). Funciona igual en Compatibility y Mobile.
3. **Horneado a atlas** (`Mascot3DBaker.bake(host, look, poses, cell_px)`): al empezar la partida (o al cambiar la apariencia en el lobby) cada jugador se renderiza una vez en todas sus poses, en una grilla con cámara ortográfica (un solo cuadro de render por jugador). Los juegos dibujan sprites 2D del atlas: en la TV no hay 3D por cuadro.
4. **Render en vivo** (`Mascot3DLive`) solo donde la pose no se puede precalcular y hay pocas mascotas grandes (ej. podio, vista previa en el celular), y solo si la medición en el aparato lo permite.
5. Integración posterior (otro PR): `PlayerAvatar.draw_mascot` elige el cuadro del atlas según ánimo/caminata/salto y lo dibuja con `draw_texture`; el *squash & stretch* y el salto siguen siendo transformaciones 2D encima del sprite. Pantallas y juegos no cambian (ADR 0004 ya preveía este reemplazo).

## Evidencia (ver docs/ARTE.md)
- Hojas lado a lado: `docs/img/mascotas.png` (2D) vs `docs/img/mascotas_3d.png` (3D) y `docs/img/mascotas_estilos.png` vs `docs/img/mascotas_3d_estilos.png`; comparación con la maqueta en `docs/img/mascotas_3d_comparacion.png`.
- Números de `tools/mascot3d_benchmark.gd` (xvfb, llvmpipe, 4 mascotas caminando; tabla completa en `docs/ARTE.md`):
  - CPU de scripts por cuadro: 2D por código 2,22 ms (p95 3,37) · 3D en vivo 0,83 ms (p95 1,20) pero 142 draw calls y render ~3× · **3D horneado 0,35 ms (p95 0,56)**, 5 draw calls (escena vacía: 0,28 ms).
  - Horneado de 4 jugadores: 21 poses a 116 px en ~0,9 s y 7 MB; 10 poses a 519 px (lobby) en ~2,2 s y 49 MB (demasiado: usar menos poses y ~360 px).

## Consecuencias
- **A favor:** volumen, brillos y contornos "de verdad"; poses nuevas (girar, mirar de costado, 3/4) sin redibujar a mano; un solo lugar para el look (shader) y todo sigue siendo código (sin archivos binarios de arte ni licencias de terceros). Con el horneado, el costo por cuadro en la TV es el de un sprite (menos CPU que la 2D actual, que arma ~40 figuras por mascota en cada cuadro).
- **En contra:** memoria de los atlas (unos MB por jugador, ver números); un tiempo de horneado al empezar cada partida (se tapa con la transición o la intro); la animación queda cuantizada a los cuadros horneados (8 de caminata, 4 de saludo…); pipeline 3D nuevo para mantener (shaders, cámara, encuadre). En `--headless` no hay render: los tests solo verifican que la escena se arma.
- **Riesgo principal:** drivers GLES3 de TVs baratas (compilación de shaders la primera vez, lectura de la textura del viewport). Mitigación: hornear durante la intro, medir en una Google TV real antes de integrar y mantener la 2D como respaldo si el horneado falla (`bake()` devuelve vacío).

## Alternativas
- **Seguir con 2D por código:** costo cero de integración, pero el techo de calidad está cerca (ver `docs/ARTE.md`).
- **Render 3D en vivo para todo:** animación perfecta, pero multiplica draw calls y CPU del driver por jugador en cada cuadro; no entra con holgura en el presupuesto de una TV de gama baja.
- **Modelos generados por IA / modelador contratado:** mejor acabado posible, pero con costo, licencias y consistencia de estilo a resolver; se pueden sumar después usando el mismo horneado (el pipeline del atlas no cambia si la malla viene de un `.glb`).

## Plan de adopción (27/09/2026)
1. **Calidad de la maqueta o mejor:** material, ojos, proporciones y brillos del `Mascot3D` comparados lado a lado con `docs/design/referencia_mascotas.webp`; horneado con supermuestreo para bordes limpios. Todos los ánimos y animaciones de `PlayerAvatar` (bailes, derrota, saludo, dormir) con su pose 3D.
2. **Integración:** `PlayerAvatar.draw_mascot` dibuja el cuadro del atlas horneado cuando existe y cae en la 2D si no (tests en `--headless`, TV sin render). Horneado al sumarse o cambiar apariencia en el lobby y al empezar la partida, con presupuesto de memoria.
3. **El resto del diseño en 3D:** piezas del escenario (estrellas, trofeo, premios, bloques) modeladas con el mismo material y horneadas a texturas, para que todo tenga el mismo acabado de juguete. Hecho en [ADR 0016](0016-piezas-3d-horneadas.md) (`core/art3d/`).
4. Medir en una Google TV real antes de publicar; si el horneado falla en el aparato, queda la 2D.

## Integración (27/09/2026)
Hecho el punto 2 del plan: **todo el juego** (lobby, intro, juegos, resumen, podio, pausa, avisos, selector TV/celular y el celular: encabezado, espera, selector de mascota y marca de agua) muestra las mascotas 3D horneadas. Pantallas y juegos no cambiaron: `PlayerAvatar.draw_mascot` elige el cuadro.

- **`MascotAtlas`** (`core/mascot3d/mascot_atlas.gd`): caché estático de cuadros por apariencia (color + estilo) y tamaño (`TIERS_U`: 0,62 · 0,95 · 1,45 · 2,25 · 3,4). Clave de pose `"<base>@<ánimo>"` (`pose_for` / `pose_def`): quieta, parpadeo, mirar a 4 lados, caminata de 8 cuadros hacia la derecha, la izquierda y de frente, festejo (4), saludo (2), derrota y bailes (4 por baile). Presupuesto de **40 MB** con liberación de lo que no se usa (LRU) y de los jugadores que se van (`keep_only`).
- **Horneado repartido** (`Mascot3DBaker.Job`): 3 mascotas armadas por trabajo que se reutilizan con `apply()`, 3 poses renderizadas por cuadro en un viewport que no se borra (render acumulado), una sola lectura de la imagen, supersampling 2× y celdas rectangulares. CPU por cuadro 3–5 ms (peor 15,6 ms, el primero).
- **Cuándo:** poses de pantalla al sumarse o cambiar de look en el lobby; poses del juego (a su `MASCOT_SCALE`) durante la intro "¿Cómo se juega?"; lo demás, perezoso (al dibujar), mostrando mientras tanto la pose más parecida.
- **Respaldo 2D automático:** sin render (headless, tests), mientras se hornea una apariencia nueva, si el horneado falla dos veces, con la silueta vacía y con los ánimos que la cara 3D todavía no tiene (se detecta comparando las piezas visibles de `Mascot3D`).
- **Rendimiento** (misma corrida, 2D vs 3D intercalados): Scripts −37 % a −68 % (lobby p95 4,69 → 1,57 ms; arena 13,1 → 5,8 ms), mismos draw calls. Memoria 21,5 MB para 4 jugadores (lobby + intro), 25–30 MB en una partida completa. Detalle en `docs/PERFORMANCE.md`.
- **Convención con el modelo:** el baker pasa `"in_place": true` y `"fx": false` en `anim`; saltos, squash, inclinación y efectos que se mueven (estrellitas, Z, destellos) los agrega `PlayerAvatar` en 2D encima del sprite. `test_mascot_atlas_framing` avisa si una pose de algún estilo se sale de la celda.
- **Precalentado por juego** (29/09/2026): cada juego puede declarar `MASCOT_PREWARM` (lista de `[u, poses]`, con atajos como `"walk@3"` = los 24 cuadros de caminata con cara de susto) además de `MASCOT_SCALE`; la intro los hornea. Poses horneadas tarde en una partida con 4 bots: 87 → 2 en los 13 juegos (detalle en `docs/PERFORMANCE.md`, `tools/mascot_prewarm_check.gd`).
- **Luz pareja en todo el atlas** (29/09/2026): la cámara del horneado está a `CAM_DISTANCE` = 10 000 u (antes 80 u). El shader de plástico calcula la vista desde cada punto aunque la cámara sea ortográfica: con la cámara cerca, la misma pose en la celda del borde de un trabajo de 24 celdas se veía con los brillos corridos (brillo medio 143 → 157 de 255). Ahora la diferencia es 0,2/255; `tools/mascot_atlas_check.gd` la mide y falla si pasa de 1,5, y `test_mascot_atlas_uniform_light` controla la geometría (< 1° entre celdas) sin render.
- **Pendiente:** medir el horneado en una Google TV real (ajustar `POSES_PER_FRAME`); punto 3 del plan (piezas del escenario en 3D).
