---
name: verificar-visual
description: Ver cómo se ven de verdad la TV y el celular de Party Games generando capturas con una pantalla virtual. Usar después de tocar UI, pantallas, minijuegos o el sistema visual, o cuando se pida "capturas", "screenshots", "cómo se ve" o actualizar docs/img.
---

# Verificación visual

`tools/capture_screens.gd` levanta la TV y controles reales conectados por WebSocket, recorre una competencia completa y guarda PNGs:

`lobby`, `lobby_full` (con el cuarteto de la maqueta: 1P rojo antena, 2P azul oso, 3P amarillo gato, 4P verde brote), `ctrl_join`, `ctrl_wait`, `ctrl_look` (selector de mascota del celular), `lobby_colores` (variedad: rosa conejo, blanco robot y negro diablito), `game_intro` (intro del primer juego), una captura por cada minijuego de la competencia (`arena`, `tap_race`, `stop_clock`…, con el nombre de su id), `ctrl_joy`, `round_summary`, `ctrl_standing`, `final`, `pingpong`, `toast` (aviso de desconexión sobre Ping Pong), `pause`, `pause_confirm` (¿Salir de la competencia?), con bots (ADR 0010) `lobby_bots` (1 persona + 3 bots, foco en un lugar con bot), `lobby_bot_menu` (menú del bot), `arena_bots` (placa BOT en el marcador) y `round_summary_bots`, y al final `selector` (TV/celular). Un juego nuevo en el registry aparece solo.

## Comandos

```bash
# Revisar sin pisar la documentación
xvfb-run -a -s "-screen 0 1920x1080x24" godot --path . --rendering-driver opengl3 --audio-driver Dummy \
  -s res://tools/capture_screens.gd -- --out=/ruta/temporal/capturas

# Actualizar docs/img (solo cuando el cambio visual es intencional)
xvfb-run -a -s "-screen 0 1920x1080x24" godot --path . --rendering-driver opengl3 --audio-driver Dummy \
  -s res://tools/capture_screens.gd
```

- Con `--headless` Godot **no dibuja**: hace falta `xvfb-run` (pantalla virtual).
- Sale con código 1 si algún paso del recorrido falla (ej. el resumen no aparece).
- En CI el job `capturas` hace lo mismo y sube las imágenes como artefacto del PR.
- Las capturas se guardan a 960 px de ancho (livianas para el repo). Para revisar detalle o compararlas con una maqueta, usar `--width=1920` (resolución real de la TV) en una carpeta temporal.
- `--lobby-only` corta después del lobby y el celular: sirve para iterar rápido en el diseño del lobby.
- `--style=pixel|neon|paper|flat` aplica un post-proceso de exploración de estilo (TV y celular); ver `docs/ESTILOS.md`. Nunca usarlo para actualizar `docs/img`.

## Qué revisar en cada captura

- Nada cortado en los bordes; márgenes de 64 px (overscan de TVs).
- El foco del D-pad se ve (anillo amarillo) y hay un elemento enfocado.
- Textos legibles a 3 metros: ≥ 24 px en la TV.
- Jugadores distinguibles por algo más que el color (etiqueta 1P–4P + accesorio de la mascota).
- Colores y medidas salen de `UiTheme` (ver skill `diseno-tv`).
