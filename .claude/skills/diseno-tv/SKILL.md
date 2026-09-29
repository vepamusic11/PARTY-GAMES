---
name: diseno-tv
description: Sistema visual y reglas de UI de Party Games (TV y celular). Usar antes de crear o cambiar cualquier pantalla, componente, color, tipografía o navegación con D-pad (host/ui/, core/ui/, controller/).
---

# Diseño de la TV y el celular

## Dónde está cada cosa

| Archivo | Qué tiene |
|---|---|
| `core/ui/ui_theme.gd` | Tokens (colores, medidas), tema de Godot, fábricas (`label`, `headline`) y funciones de dibujo (`draw_hex_chip`, `draw_round_rect`, `draw_star`…) |
| `core/art3d/` | Piezas 3D horneadas a un atlas (`Props3D`: estrellas, bloques, medallas, corona, trofeo, ficha, pelota; ADR 0016). `Props3D.draw(ci, pieza, rect)` devuelve false sin atlas: siempre dejar el dibujo 2D de respaldo. Hoja: `tools/props3d_sheet.gd` |
| `core/art3d/board_*_25d.gd` | Tablero 2.5D (ADR 0019): `Board25DScene` arma el tablero y el entorno en 3D, `Board25DBaker` lo hornea una vez a una textura (caché en `user://board25d/`), `BoardView25D` proyecta el juego 2D con la misma cámara (`project`, `scale_at`, `floor_xform`). Uso en juegos: `MiniGame.draw_board_25d(view)` (false = dibujar plano). Vista previa: `tools/board25d_preview.gd` |
| `core/art3d/game_diorama.gd` | Dioramas 3D de los juegos para las tarjetas del lobby (`GameDiorama`, ADR 0018): receta por juego + genérica; se renderizan con `tools/make_dioramas.gd` a `assets/thumbs/diorama/` (`GameCard.card_art`: diorama → captura → dibujo) |
| `core/ui/widgets/` | Compartidos: `PartyBackground` (escenario desenfocado detrás de la UI, se prepara una vez; tokens `BG_*`, ADR 0008), `PlayerAvatar` (mascotas), `HexChip` |
| `core/mascot3d/` | Mascotas 3D (ADR 0012): `Mascot3D` (modelo y material), `Mascot3DBaker` (horneado a atlas en cuotas), `MascotAtlas` (caché de cuadros por apariencia y tamaño, con presupuesto de memoria; lo usa `PlayerAvatar` solo) |
| `host/ui/widgets/` | Solo TV: `GameCard`, `Stepper`, `SeatCard`, `ScorePedestal`, `ScoreBar` (marcador del resumen con el arte de los juegos), `NamePlate` (chapita [1P | nombre]), `PointsBadge` (placa "+70"), `Confetti`, `KeyHint`, `Transition` (barrido de bloques entre pantallas) |
| `host/ui/widgets/tv_*.gd` | Pantallas: `TvButton` (botón de juguete con bisel e ícono), `TvLogoTitle` (título "de logo"), `TvReadyCard` ("¡Listo!" de la intro), `TvToasts` (avisos se sumó/se desconectó/volvió), `TvDeviceCard` (selector TV/celular) |
| `host/ui/*_screen.gd` | Pantallas: lobby, intro "¿Cómo se juega?", resumen de ronda, podio, pausa |

## Reglas

1. **Sin valores sueltos**: colores y tamaños salen de `UiTheme`. Si falta un token, agregarlo ahí.
2. **UI por código** (sin `.tscn`), con el tema aplicado en la raíz: `theme = UiTheme.build()`.
3. **D-pad primero**: todo lo accionable es focusable y el foco se ve (`UiTheme.focus_ring()` o anillo dibujado a mano en controles propios). Cada pantalla deja el foco en un elemento al mostrarse. Si un control usa ◀ ▶ para cambiar su valor (como `Stepper`), ▲ ▼ deben seguir navegando.
4. **Atrás** del control remoto abre el menú de pausa; nunca corta una partida sin preguntar.
5. **Legibilidad a 3 m**: textos ≥ 24 px en la TV; títulos con `UiTheme.headline` (contorno + sombra).
6. **Overscan**: `UiTheme.SAFE_MARGIN` (64 px) libre en los bordes.
7. **No solo color**: cada jugador lleva etiqueta `1P`–`4P` y un accesorio propio en la mascota. Si el juego no muestra la mascota entera (tanque, víbora, paleta del color del jugador), la etiqueta 1P–4P va sobre lo que controla y suma una forma o patrón propio; el marcador sigue mostrando la cabeza de cada mascota. Niveles y ejemplos: "Cómo se ve cada jugador" en `docs/JUEGOS.md`.
8. **Nombres de jugador**: solo `Label` o `draw_string`. Nunca `RichTextLabel` con BBCode.
9. **Animaciones cortas** (≤ 1 s) con `Tween`, sin bloquear la navegación. Respetar `UiTheme.reduce_motion` ("Movimiento: Reducido" en la pausa): sin rebotes, deslizamientos, brillos ni partículas; solo fundidos.
10. **Mascotas vivas:** en los juegos, dibujarlas con `PlayerAvatar.draw_mascot(..., mascot_anim(pid, dirección))` y llamar `advance_walk(pid, velocidad01, delta)` al moverlas: caminan, miran hacia donde van y parpadean. Ánimos: `NORMAL`, `HAPPY` (festeja con los brazos), `SAD` (lágrima), `SURPRISED` (peligro cerca), `ANGRY` (enojada/concentrada), `DIZZY` (mareada: ojos en espiral y estrellitas, ej. al caer en Empujones), `SLEEPY` (dormida), `WINNER` (ojos de estrella) y `LAUGHING` (llorando de risa). En los juegos, las animaciones son claves opcionales del dict `anim`: `dance` (0..1) + `dance_kind` (`PlayerAvatar.DANCE_HOPS/SPIN/ARMS`; sin clave, el del estilo), `defeat` (0..1), `greet` (0..1). En las pantallas, usar los métodos del nodo `PlayerAvatar`: `celebrate(kind, segundos)` / `stop_celebrating()`, `lose(true/false)`, `say_hello()` (al entrar al lobby) y `sleep_after` + `wake()` (se duerme en esperas largas). Revisar cambios con la hoja de personajes: `tools/character_sheet.gd` (`docs/img/mascotas.png`; `--expressions` → `docs/img/mascotas_expresiones.png`).
11. Los íconos que la tipografía no trae (◀ ▶ ✓ ★) se dibujan: `draw_arrow`, `draw_check`, `draw_star`. `draw_star` (dorada o blanca) y `draw_medal` usan la pieza 3D horneada si hay atlas; los íconos planos de `draw_glyph` siguen en 2D.
12. **Mascotas 3D horneadas (ADR 0012):** `PlayerAvatar.draw_mascot` y el nodo `PlayerAvatar` dibujan solos el cuadro 3D horneado de `MascotAtlas` (`core/mascot3d/mascot_atlas.gd`) cuando existe y la 2D por código si no (headless, tests, todavía horneando, horneado fallido o ánimo que la 3D todavía no tiene). No dibujar mascotas de otra forma ni tocar `Mascot3D` desde pantallas o juegos. El salto (`lift`), el *squash*, la inclinación y los efectos que se mueven (estrellitas, Z, destellos) se aplican en 2D encima del sprite: siguen funcionando igual. Si una pantalla o juego nuevo usa un tamaño de mascota distinto, declarar `MASCOT_SCALE` en el juego (el host precalienta ese tamaño durante la intro); si dibuja poses fuera de las típicas (susto o festejo caminando, otro tamaño en una tribuna), declararlas en `MASCOT_PREWARM` y confirmar con `tools/mascot_prewarm_check.gd --only=<id>` que no quedan poses horneadas tarde. Una pose nueva: agregarla en `MascotAtlas.pose_for`/`pose_def` (y el test `test_mascot_atlas_pose_keys`). Poses de pantalla: `wave` (festeja con los dos brazos), `greet` (saluda agitando una mano) y `hello` (una mano bien arriba, quieta: `PlayerAvatar.hello = 1.0`, la de las tarjetas del lobby). Revisar con capturas reales (`verificar-visual`) y `tools/mascot_atlas_check.gd` (hoja 2D vs 3D y tiempos de horneado); comparar con `--mascots-2d`.
13. **Piezas de juguete** (estrellas, bloques, premios): usar `Props3D` con el 2D de respaldo; una pieza nueva se agrega al catálogo (`Props3D.catalog()` + receta en `Props3D.build`) y se revisa en la hoja de piezas.
14. **Look de la maqueta del lobby** (sección "Lobby maqueta" de `UiTheme`): tarjetas de jugador con `draw_seat_card` (degradé pastel del color del jugador, marco claro y resplandor; base celeste si el color es muy claro), lugar libre con `draw_glass_card`, fichas y botones con `draw_toy_block`/`draw_toy_tile` (sin contorno de tinta, canto oscuro abajo, un solo lote). La mascota va con la cabeza adentro de la tarjeta y el cuerpo detrás de la base del nombre (`SeatCard.MASCOT_TOP/MASCOT_SINK`). Colores del fondo, fichas y botones medidos contra la maqueta (`docs/ARTE.md`, "Revisión de dirección de arte"): antes de cambiar un token, medir. Referencia: `docs/img/lobby_comparacion.png`.

## Después de cambiar algo

Tests + skill `verificar-visual`. Si el cambio es de identidad visual, actualizar `docs/adr/0004-sistema-visual.md`.
