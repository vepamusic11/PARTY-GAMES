# ADR 0012 · Mascotas 3D renderizadas por Godot y horneadas a sprites

- **Estado:** Propuesta (la decisión final es del dueño del producto)
- **Fecha:** 2026-09-27
- **Relacionados:** [ADR 0004](0004-sistema-visual.md) (sistema visual dibujado por código), [ADR 0006](0006-rendimiento-capas-cacheadas.md) (rendimiento), [ADR 0007](0007-apariencia-del-jugador.md) (color y estilo), `docs/PLAN.md` ("¿Conviene usar heightfields?": recomienda 2.5D), análisis completo en [docs/ARTE.md](../ARTE.md).

## Contexto
La maqueta de mascotas (`docs/design/referencia_mascotas.webp`) tiene acabado de **juguete 3D brillante**: volumen real, reflejos nítidos, brillo de barniz, luz de contorno y un contorno de tinta que se adapta a la pose. Las mascotas de hoy son 2D por código con degradé por vértice (`PlayerAvatar` + `MascotShading`): se ven bien de frente, pero el volumen es una ilusión (un círculo sombreado) y no pueden girar, mirar de costado ni mostrar las piezas encimadas con su propia luz.

Hay que elegir cómo llegar a la calidad de la maqueta. Opciones evaluadas (detalle, costos y licencias en `docs/ARTE.md`): (1) seguir mejorando el 2D por código, (2) 3D en Godot con primitivas (este prototipo), (3) modelos generados por IA, (4) ilustrador/modelador contratado.

## Propuesta
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
