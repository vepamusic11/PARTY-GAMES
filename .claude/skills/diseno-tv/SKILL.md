---
name: diseno-tv
description: Sistema visual y reglas de UI de Party Games (TV y celular). Usar antes de crear o cambiar cualquier pantalla, componente, color, tipografía o navegación con D-pad (host/ui/, core/ui/, controller/).
---

# Diseño de la TV y el celular

## Dónde está cada cosa

| Archivo | Qué tiene |
|---|---|
| `core/ui/ui_theme.gd` | Tokens (colores, medidas), tema de Godot, fábricas (`label`, `headline`) y funciones de dibujo (`draw_hex_chip`, `draw_round_rect`, `draw_star`…) |
| `core/ui/widgets/` | Compartidos: `PartyBackground` (escenario desenfocado detrás de la UI, se prepara una vez; tokens `BG_*`, ADR 0008), `PlayerAvatar` (mascotas), `HexChip` |
| `host/ui/widgets/` | Solo TV: `GameCard`, `Stepper`, `SeatCard`, `ScorePedestal`, `ScoreBar` (marcador del resumen con el arte de los juegos), `NamePlate` (chapita [1P | nombre]), `PointsBadge` (placa "+70"), `Confetti`, `KeyHint`, `Transition` (barrido de bloques entre pantallas) |
| `host/ui/*_screen.gd` | Pantallas: lobby, intro "¿Cómo se juega?", resumen de ronda, podio, pausa |

## Reglas

1. **Sin valores sueltos**: colores y tamaños salen de `UiTheme`. Si falta un token, agregarlo ahí.
2. **UI por código** (sin `.tscn`), con el tema aplicado en la raíz: `theme = UiTheme.build()`.
3. **D-pad primero**: todo lo accionable es focusable y el foco se ve (`UiTheme.focus_ring()` o anillo dibujado a mano en controles propios). Cada pantalla deja el foco en un elemento al mostrarse. Si un control usa ◀ ▶ para cambiar su valor (como `Stepper`), ▲ ▼ deben seguir navegando.
4. **Atrás** del control remoto abre el menú de pausa; nunca corta una partida sin preguntar.
5. **Legibilidad a 3 m**: textos ≥ 24 px en la TV; títulos con `UiTheme.headline` (contorno + sombra).
6. **Overscan**: `UiTheme.SAFE_MARGIN` (64 px) libre en los bordes.
7. **No solo color**: cada jugador lleva etiqueta `1P`–`4P` y un accesorio propio en la mascota.
8. **Nombres de jugador**: solo `Label` o `draw_string`. Nunca `RichTextLabel` con BBCode.
9. **Animaciones cortas** (≤ 1 s) con `Tween`, sin bloquear la navegación.
10. **Mascotas vivas:** en los juegos, dibujarlas con `PlayerAvatar.draw_mascot(..., mascot_anim(pid, dirección))` y llamar `advance_walk(pid, velocidad01, delta)` al moverlas: caminan, miran hacia donde van y parpadean. Ánimos: `NORMAL`, `HAPPY` (festeja con los brazos), `SAD` (lágrima) y `SURPRISED` (peligro cerca). Revisar cambios con la hoja de personajes: `tools/character_sheet.gd` (genera `docs/img/mascotas.png`).
11. Los íconos que la tipografía no trae (◀ ▶ ✓ ★) se dibujan: `draw_arrow`, `draw_check`, `draw_star`.

## Después de cambiar algo

Tests + skill `verificar-visual`. Si el cambio es de identidad visual, actualizar `docs/adr/0004-sistema-visual.md`.
