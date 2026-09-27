# Lobby de la TV · referencia de diseño

Maqueta aprobada (26/09/2026) y cómo se tradujo al lobby dibujado por código.

![Lobby actual](../img/lobby_full.png)

| Zona de la maqueta | Implementación |
|---|---|
| Logo PARTY-GAME arriba a la izquierda | `UiTheme.logo_rect()` con `assets/brand/party_game_logo.png` |
| "¡Sumate desde tu celular!" con ícono de celular | `GlyphBadge("phone")` + tres pasos numerados en píldoras (`_step_row`) |
| Código de sala en fichas de colores | Fichas de `BRICKS`, 90×112 px |
| "¿No aparece la TV?" + dirección | Ícono Wi-Fi y la dirección en una píldora clara |
| Fila de jugadores 1P–4P con mascota grande | `SeatCard` alta: fondo teñido con el color del jugador, halo, etiqueta 1P |
| "Esperando jugadores…" | Lugar libre: tarjeta translúcida, borde punteado y "+" |
| Cantidad de jugadores | Quinta tarjeta: `Stepper` alto ("¿Cuántos juegan?"), ◀ ▶ |
| "¿A qué jugamos?" + "6 de 7 elegidos" | Ícono de joystick y píldora oscura con el contador |
| Tarjetas de juego con ilustración y ✓ | `GameCard`: cielo en degradé, piso en perspectiva, ícono del control; candado si no se puede jugar |
| Orden y "¡A jugar!" | Botones con ícono dibujado (`order`, `play`) |
| Mascota que saluda abajo a la izquierda | `PlayerAvatar` feliz, detrás de los paneles |

**Qué no se copió:** la barra superior de la maqueta (Tests, Juegos, Fase, PR, CI, Licencia) es información de desarrollo; vive en el tablero de avances, no en la TV de los jugadores.

Al abrir la app en la TV se muestra antes "IO-GAMES presenta" (`host/ui/splash_screen.gd`, se saltea con cualquier tecla).

![Presentación](../img/splash.png)
