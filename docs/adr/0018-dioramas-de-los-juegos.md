# ADR 0018 · Dioramas 3D de los juegos en las tarjetas del lobby

- **Estado:** Aceptada
- **Fecha:** 2026-09-29
- **Relacionados:** [ADR 0016](0016-piezas-3d-horneadas.md) (piezas 3D horneadas), [ADR 0012](0012-mascotas-3d.md) (mascotas 3D), [ADR 0009](0009-arte-de-los-juegos.md) (arte de los juegos), [ADR 0004](0004-sistema-visual.md) (sistema visual).

## Contexto
El dueño siente el lobby "muy alejado" de la maqueta (`docs/design/referencia_lobby.webp`). Una de las diferencias más visibles son las miniaturas de los juegos: en la maqueta cada tarjeta muestra una **ilustración 3D tipo diorama** (una escena chica y colorida del juego: el escenario redondo de Arena con estrellas y un joystick gigante, la mesa de ping pong, el reloj…), mientras que el juego mostraba **capturas** (`tools/make_thumbnails.gd`): fotos del juego, planas y con mucho blanco, que a 270 px de ancho se leen poco.

## Decisión
1. **Una receta 3D por juego** en `core/art3d/game_diorama.gd` (`GameDiorama.build(info)`): piezas de juguete armadas por código con las recetas de `Props3DMeshes` (cajas redondeadas, tornos, almohadones), el mismo plástico de las mascotas (`toy_plastic.gdshader` + `ink_outline.gdshader`, sin editarlos) y mascotas `Mascot3D` del cuarteto de siempre (1P rojo antena, 2P azul oso, 3P amarillo gato, 4P verde brote). Ejemplos: Arena = escenario redondo de baldosas hexagonales, aro de bloques, estrellas doradas y un joystick de arcade gigante; Pool loco = mesa de juguete con troneras y las bolas en triángulo.
2. **Receta genérica** para un juego sin receta propia (juego nuevo): el escenario redondo con baldosas del color del juego (`accent`) y el control que usa (joystick, botón o deslizador) como pieza grande, igual que en la maqueta. Así un juego nuevo tiene diorama con solo correr la herramienta.
3. **Se renderiza una vez, fuera del juego** (`tools/make_dioramas.gd` → `assets/thumbs/diorama/<id>.webp`, 660×260 ≈ 2,5:1, la franja que muestra la tarjeta; desde la vuelta 2 de dirección de arte la cámara de cada receta se acerca y baja con `UiTheme.DIORAMA_ZOOM`/`DIORAMA_CAM_DROP` para que el escenario llene la tarjeta como en la maqueta): el fondo (torres de bloques y estrellas) se renderiza aparte y se desenfoca (como una foto con poca profundidad de campo), el frente va nítido; todo al doble y achicado al final. Cámara con perspectiva (a diferencia del horneado de piezas, que es ortográfico).
4. **La tarjeta prefiere el diorama** (`GameCard.card_art`): diorama → captura (`assets/thumbs/<id>.webp`) → dibujo de respaldo. La intro "¿Cómo se juega?" sigue mostrando la captura: ahí sirve ver el juego de verdad.
5. **Test genérico** (`test_games_have_dioramas`): un juego del registry sin diorama falla con el comando para generarlo, como las capturas.

## Motivos
- Se ve como la maqueta: color saturado, volumen de juguete y una pieza que dice de qué se trata el juego, legible a 3 m y en 270 px.
- **Costo cero en la TV**: es una textura más por tarjeta (igual que la captura); nada de 3D ni horneado en el aparato. Peso: ~15–25 KB por juego en WebP.
- Mismo acabado que las mascotas y las piezas (ADR 0012/0016): un solo lugar para el look.

## Consecuencias
- Cambiar una receta, un color de la paleta o el plástico pide volver a correr `tools/make_dioramas.gd` (y `godot --headless --path . --import`). Los dioramas no se regeneran solos.
- Si cambian los uniforms del shader de plástico, `GameDiorama.plastic()` tiene que seguirlos (igual que `Props3D`).
- El APK suma ~250 KB (13 imágenes).
- La guía de juegos nuevos (`docs/ADDING_A_MINIGAME.md`) suma el paso de la herramienta; una receta propia es opcional (la genérica ya cumple).

## Alternativas descartadas
- **Mejorar el encuadre y la saturación de las capturas**: más barato, pero siguen siendo fotos planas del juego con mucho blanco; no se acercan a la maqueta.
- **Hornear los dioramas en la TV** (como las piezas de ADR 0016, con caché en disco): no hace falta que cambien por aparato, cuestan ~0,3 s cada uno en llvmpipe y sumarían trabajo al primer arranque.
- **Ilustraciones hechas a mano o con IA**: más lindas en una imagen suelta, pero sin receta para juegos nuevos y con licencias que revisar.
