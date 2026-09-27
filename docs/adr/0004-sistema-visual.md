# ADR 0004 · Sistema visual dibujado por código

- **Estado:** Aceptada
- **Fecha:** 2026-09-26

## Contexto
El prototipo usaba el tema por defecto de Godot sobre fondo oscuro. La referencia de producto son los party games de consola (marcadores hexagonales "1P | 345", personajes simpáticos, colores vivos, cielo celeste, bloques de colores). Todavía no hay arte encargado a un ilustrador.

## Decisión
- **Tokens de diseño** en `core/ui/ui_theme.gd`: paleta, medidas, tema de Godot y funciones de dibujo. Ninguna pantalla ni juego define colores sueltos.
- **Todo dibujado por código** (`_draw`): fondo, mascotas, chips, tarjetas, íconos. Sin texturas.
- **Tipografía Fredoka** (SIL Open Font License 1.1, en `assets/fonts/` con su licencia).
- **Mascotas por lugar**, con un accesorio distinto además del color: 1P antena · 2P orejas redondas · 3P orejas puntiagudas · 4P brote. Personajes propios (no copiados de otros juegos).
- Los minijuegos comparten fondo, marco, marcador superior (`MiniGame.draw_hud`) y mascotas.
- **Animación de mascotas por parámetros** (sin sprites): caminata, mirada, parpadeo, brazos, boca por ánimo y *squash & stretch* en los saltos. La hoja de personajes (`tools/character_sheet.gd` → `docs/img/mascotas.png`) muestra todas las poses para revisarlas de un vistazo.
- **Transiciones**: entre pantallas de la TV, un barrido corto (≤ 0,45 s) de bloques con los colores de `UiTheme.BRICKS`, con volumen, estrellas en la punta y una estrella en el centro mientras todo está tapado (`host/ui/widgets/transition.gd`).
- **Fondo de la TV**: escenario de fiesta con profundidad, desenfocado y más suave que la UI (ver [ADR 0008](0008-fondo-escenario-desenfocado.md)). El ícono de cada tipo de control se dibuja con `UiTheme.draw_control_icon` (tarjetas del lobby e intro de cada juego).

## Actualización (27/09/2026): calidad de maqueta

Las maquetas de referencia están en `docs/design/` (lobby, un juego y hoja de mascotas). Para acercarse a su acabado de "juguete 3D" sin sprites:
- **Mascotas con sombreado por vértice** (`core/ui/widgets/mascot_shading.gd`): cada parte es una malla de anillos cuyos vértices llevan el color de una esfera iluminada (luz arriba a la izquierda, rebote abajo, luz de borde en colores oscuros). La GPU interpola y da el degradé suave; el contorno grueso es un anillo más de la misma malla. Mallas y colores se cachean: una mascota sigue siendo 1–2 draw calls.
  *Ejemplo:* la cabeza roja de 1P ya no es "círculo rojo + círculo más claro": es una esfera con brillo arriba y sombra abajo, como la hoja de referencia.
- **Marca y apariencia**: logo PARTY-GAME, presentación IO-GAMES, 7 estilos y 10 colores elegibles ([ADR 0007](0007-apariencia-del-jugador.md)). Los textos sobre el color de un jugador usan `UiTheme.text_on(bg)` (contraste ≥ 3:1 comprobado por test).
- **Fondo de menús**: escenario desenfocado ([ADR 0008](0008-fondo-escenario-desenfocado.md)).
- **Arte de los juegos**: tablero con volumen, marcador con la cabeza de cada mascota y globito 1P–4P ([ADR 0009](0009-arte-de-los-juegos.md)).
- **Celular**: botones "de juguete" con bisel que se aplastan al tocarlos (`controller/widgets/toy_button.gd`).
- **Miniaturas reales** de cada juego en el lobby, generadas con `tools/make_thumbnails.gd`.

## Motivos
- Nítido en 720p, 1080p y 4K sin exportar imágenes en varios tamaños; el APK queda liviano (~100 KB de fuentes, nada de sprites).
- Un único lugar para cambiar la identidad cuando llegue el arte definitivo.
- Accesibilidad: jugadores distinguibles aunque no se perciban los colores (daltonismo), y textos grandes con contorno legibles a 3 metros.

## Alternativas descartadas
- **Sprites/PNG ahora:** requieren arte que todavía no existe y un pipeline de importación por resolución.
- **Escenas `.tscn` para la UI:** el proyecto construye la UI por código (ver `CLAUDE.md`); mezclar estilos complica el mantenimiento.

## Consecuencias
- Cuando haya arte definitivo, `PlayerAvatar.draw_mascot` y `PartyBackground` se reemplazan por sprites sin tocar pantallas ni juegos.
- `tools/capture_screens.gd` + el job `capturas` de CI permiten revisar cada cambio visual en el PR.
