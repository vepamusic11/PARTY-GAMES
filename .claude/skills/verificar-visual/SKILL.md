---
name: verificar-visual
description: Ver cómo se ven de verdad la TV y el celular de Party Games generando capturas con una pantalla virtual. Usar después de tocar UI, pantallas, minijuegos o el sistema visual, o cuando se pida "capturas", "screenshots", "cómo se ve" o actualizar docs/img.
---

# Verificación visual

`tools/capture_screens.gd` levanta la TV y controles reales conectados por WebSocket, recorre una competencia completa y guarda PNGs:

`lobby`, `lobby_full`, `ctrl_join`, `ctrl_wait`, una captura por cada minijuego de la competencia (`arena`, `tap_race`, `stop_clock`…, con el nombre de su id), `ctrl_joy`, `round_summary`, `ctrl_standing`, `final` y `pingpong`. Un juego nuevo en el registry aparece solo.

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

## Qué revisar en cada captura

- Nada cortado en los bordes; márgenes de 64 px (overscan de TVs).
- El foco del D-pad se ve (anillo amarillo) y hay un elemento enfocado.
- Textos legibles a 3 metros: ≥ 24 px en la TV.
- Jugadores distinguibles por algo más que el color (etiqueta 1P–4P + accesorio de la mascota).
- Colores y medidas salen de `UiTheme` (ver skill `diseno-tv`).
