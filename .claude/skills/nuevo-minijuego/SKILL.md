---
name: nuevo-minijuego
description: Crear o modificar un minijuego de Party Games (host/minigames/). Usar cuando se pida "agregar un juego", "nuevo minijuego", cambiar reglas, puntaje o dibujo de un juego existente.
---

# Nuevo minijuego

Guía completa con ejemplo: `docs/ADDING_A_MINIGAME.md`. Esta skill es el checklist para no olvidar nada.

## Pasos

1. **Carpeta y script** `host/minigames/<id>/<id>.gd` que `extends MiniGame`.
2. **`get_info()`** con: `id` (único, minúsculas), `title`, `description` (se lee en la intro "¿Cómo se juega?": una o dos frases), `min_players`, `max_players`, `layout` (uno de `Protocol.LAYOUTS`), `layout_data`, y los opcionales recomendados:
   - `accent`: color de la tarjeta en el lobby (tomar uno de `UiTheme.BRICKS`).
   - `score_label`: unidad del puntaje en el resumen de ronda ("estrellas", "goles"…).
3. **Registrar** el script en `MiniGameRegistry.GAMES` (`host/minigames/registry.gd`).
4. **Terminar una sola vez** con `finish(result_from_scores(puntajes, "resumen"))` o con `winners` explícitos si "gana el primero en llegar". El modo competencia convierte puestos en puntos (100/70/50/30): el juego solo reporta su puntaje propio.
5. **Dibujar con el sistema visual**, no con colores sueltos:
   - `draw_sky()` y `draw_play_field(rect)` para el fondo.
   - `PlayerAvatar.draw_mascot(self, pies, escala, p.color, p.slot)` para los jugadores.
   - `draw_hud(puntajes, texto_central)` arriba (reloj con `clock_text(seg)`).
   - `draw_text_centered(texto, pos, tamaño, color, contorno)` para textos.
6. **Sonido y vibración**: `play_sfx(nombre)` en la TV, `notify_player(pid, tipo)` en el celular del jugador y `tick_countdown(antes, después)` para la cuenta regresiva. Eventos importantes (sumar, eliminar, ganar) siempre con las dos cosas.
7. **Seguridad**: usar solo `input.axis` / `input.btn`; límites propios si hace falta (ver `tap_race.gd`). Nombres solo con `draw_string`/`Label`.
8. **Márgenes**: resolución lógica 1920×1080; dejar ~64 px libres en los bordes (overscan) y los 90 px de arriba para el HUD.

## Verificar

- `godot --headless --path . -s res://tests/run_tests.gd` (los tests genéricos cubren el juego nuevo automáticamente).
- Skill `verificar-visual` para ver cómo se ve en la TV.
- Si el juego necesita un control nuevo (ej. dos botones): es un cambio de protocolo → ver reglas en `CLAUDE.md` y `docs/PROTOCOL.md`.
