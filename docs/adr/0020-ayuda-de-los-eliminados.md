# ADR 0020 · Ayuda de los eliminados, a cambio de puntos

- **Estado:** Aceptada
- **Fecha:** 2026-09-29
- **Especificación:** [MODOS.md §11](../MODOS.md#11-ayuda-de-los-eliminados-a-cambio-de-puntos)

## Contexto
En los juegos con eliminación (Esquivar, Empujones, y después Memoria de colores, ¡Que no te deje la cámara! y Bombas de mascotas) el que pierde primero se queda mirando hasta el resumen. El dueño propuso que pueda **ayudar** a alguien que sigue, pagando con puntos de su total de la competencia: la eliminación pasa a ser una decisión social ("¿ayudo a Sofi para que no gane Pablo?").

Tres restricciones del proyecto mandan: la TV es autoritativa y el celular solo manda `axis` y `btn` (ADR 0002); Tournament es lógica pura y testeada (ADR 0003); y el dibujo de Esquivar y Empujones lo está cambiando en paralelo la dirección de arte (2.5D, ADR 0019).

## Decisión
**Concepto: la ayuda se reparte en tres piezas que no se conocen entre sí más que por un contrato chico.** El juego decide *si* la ayuda vale y *qué hace*; la competencia decide *cuánto cuesta* y la *cobra*; la TV (una sesión nueva) traduce la entrada del eliminado y junta las dos.

```
 celular del eliminado ── axis/btn ──► HelpSession ── help_denial / apply_help ──► MiniGame (valida y aplica)
   (joystick_ab + hint)                 (TV)       ── can_afford / help_cost / spend ─► Tournament (cobra)
                                         │
                                         └─► TvHelpOverlay: ficha "3P" sobre el elegido, mascota traslúcida
                                             del ayudante y cartel "Tomi ayudó a Sofi · −10"
```

- **Tournament** (`spend`, `help_cost`, `is_leader`, `can_afford`): costo base 10 (≈ ⅓ de un 4.° puesto; cada juego puede pedir otro en su `HELP.cost`) y **el doble** si el ayudado va primero ("va primero" = tiene el máximo y alguien tiene menos: con todos en 0 nadie va primero). `spend` nunca baja de 0 y registra la ayuda en `pending_helps`; `record()` la pasa al resumen de la ronda (`history[i].helps`) y cada fila lleva `spent`. Si la ronda se saltea desde la pausa, se devuelven los puntos (sus resultados tampoco cuentan).
- **MiniGame** (`help_info`, `help_denial`, `apply_help`, `help_tick`, `consume_help`, `help_active`): un juego ofrece ayuda con `"help": {name, cost, duration}` en `get_info()` y sobrescribe `help_is_out`, `help_is_running`, `help_anchor`/`help_scale` (dónde está cada mascota en pantalla, con la proyección 2.5D si la hay) y `_start_help`. La base valida lo común: ayudante eliminado, objetivo vivo y distinto, **tope de 2** por eliminado, **3 s de espera** entre ayudas y **una ayuda activa por objetivo**. Los juegos sin `help` no cambian.
- **Esquivar**: escudo burbuja; el primer bloque que lo alcanza en 3 s revienta la burbuja y ese bloque ya no lo lastima (`spared`). **Empujones**: salvavidas; si se cae en 3 s vuelve a la isla (60 % del radio, yendo hacia el centro), una vez. Cada juego suma su dibujo en una función nueva `_draw_help_fx()` llamada con una línea desde su `_draw` (arte común en `HelpFx`): no se reescribe el dibujo existente.
- **HelpSession** (nodo de `HostMain`): detecta a los eliminados, les manda **solo a ellos** `joystick_ab` con `hint` "Elegí a quién ayudar: 2P · 3P" (A = Ayudar, B = Cambiar) y rutea su entrada. Elegir: empujar el joystick hacia la mascota de un jugador vivo (cono de ±60° desde la mascota del ayudante; un empujón = una elección); si no apunta a nadie, izquierda/derecha rotan; B también rota. A: primero los puntos (si no alcanzan, "lose" en el celular y cartel en la TV), después las reglas del juego, `apply_help` y recién ahí `spend`. Al reconectarse, el ayudante recupera su control.
- **Lobby**: "Ayudas: Sí/No" (por defecto Sí), navegable con el D-pad, guardado en `user://tv_settings.cfg` (sección `help`).
- **Resumen de la ronda**: línea "Ayudas: Tomi −10 por ayudar a Sofi · …" (nada secreto).
- **Bots**: un bot eliminado ayuda **una vez por juego** al que va último en la competencia si le alcanzan los puntos. `BotDriver` le pasa `HelpSession.bot_view()` y su entrada vuelve por `input_sink` (el mismo camino que un celular): empuja el joystick hacia esa mascota, aprieta A y la TV valida y cobra.
- **Protocolo: sin cambios** (`VERSION` sigue en 2): `joystick_ab`, `hint` y `a`/`b` ya existían.

## Alternativas descartadas
- **Mandar al celular las mascotas de los candidatos** (color y estilo en los datos del layout) para dibujar un selector propio: es un cambio de protocolo (campos nuevos que un control viejo no entiende) para algo que la TV ya muestra. El celular muestra los 1P–4P de los candidatos en el hint; la mascota se ve en la TV, con la ficha del ayudante encima.
- **Actualizar el hint con el elegido en cada cambio**: cada `layout` rearma el control en el celular (se corta el toque y hay animación de entrada). La elección se ve en la TV.
- **Guardar las ayudas como filas propias de `history`**: rompería `round_number()` y el podio ("Se jugó…"); van dentro del resumen de su ronda.
- **Que el juego cobre**: el juego no conoce la competencia (Tournament) y así seguirá funcionando en otros modos (Equipos, Eliminación con fantasmas).

## Consecuencias
- Sumar la ayuda a otro juego es chico (S): `"help"` en `get_info()`, cuatro métodos y su `_draw_help_fx()` ([ADDING_A_MINIGAME.md](../ADDING_A_MINIGAME.md), "Ayuda de los eliminados").
- El costo (10, doble al primero) y el tope (2) son una primera versión: medir con bots y partidas reales si ayudar conviene demasiado o nunca.
- La mascota traslúcida del ayudante y el cartel se dibujan en una capa encima del juego (`TvHelpOverlay`, z 10): sin ayudantes no dibuja ni procesa nada.
- En Empujones el ayudante mira desde la tribuna: el joystick apunta desde su asiento. Si Empujones pasa a 2.5D, `help_anchor` tiene que usar la misma proyección que el dibujo.
