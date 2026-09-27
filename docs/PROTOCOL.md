# Protocolo TV ↔ celular · v1

Fuente de verdad en código: [`core/protocol/protocol.gd`](../core/protocol/protocol.gd). Si cambiás uno, cambiá el otro.

## Transporte

| | Valor |
|---|---|
| Juego | WebSocket, mensajes de **texto** JSON, puerto `47777` |
| Descubrimiento | UDP broadcast a `255.255.255.255:47778`, 1 por segundo |
| Tamaño máximo | 512 bytes por mensaje (más grande = se descarta) |
| Campos obligatorios | `v` (versión, número) y `type` (string) en **todos** los mensajes |

**Compatibilidad:** los tipos desconocidos se ignoran (permite agregar mensajes sin romper versiones viejas). Un cambio incompatible sube `VERSION`, y el host rechaza a los controles con otra versión con `bad_version`, que el celular muestra como "Actualizá ambas apps".

## Control → TV

### `join` — unirse o reconectarse
```json
{"v":1,"type":"join","room":"K7QX","name":"Pablo"}
{"v":1,"type":"join","room":"K7QX","name":"Pablo","token":"9f2c…(32 hex)"}
{"v":1,"type":"join","room":"K7QX","name":"Juli","color":9,"style":5}
```
- `room`: 4 caracteres de `ABCDEFGHJKLMNPQRSTUVWXYZ23456789` (sin I/O/0/1 para no confundir).
- `name`: se limpia (sin caracteres de control) y se recorta a 16.
- `token`: opcional. Si coincide con un jugador existente, se reconecta a su lugar.
- `color` / `style`: **opcionales**. Apariencia pedida (ver [Apariencia](#apariencia-color-y-estilo)). Si faltan o no son válidos, se usan los del lugar (1P rojo con antena…) y el `join` se acepta igual. En una reconexión se ignoran: vuelve con la apariencia que tenía.
- Debe llegar dentro de los **5 segundos** de abierta la conexión, o se corta.

### `input` — estado del control
```json
{"v":1,"type":"input","seq":1042,"axis":[0.73,-0.1],"btn":1}
```
- `seq`: contador creciente (permite detectar pérdidas o desorden en el futuro).
- `axis`: `[x, y]`, se recorta a longitud ≤ 1.
- `btn`: máscara de bits. `1` = A, `2` = B. Otros bits se descartan.
- Límite: **90 por segundo** por jugador; el exceso se descarta.

### `look` — cambiar color y/o estilo (solo en el lobby)
```json
{"v":1,"type":"look","color":4,"style":6}
{"v":1,"type":"look","style":0}
```
- Campos opcionales, mismas reglas que en `join`; lo inválido se descarta en silencio.
- Solo se acepta en la fase `lobby` y antes de que arranque la competencia; si no, se ignora.
- Si el color lo usa otro jugador, se conserva el propio (el estilo sí cambia).
- La TV responde siempre con `appearance` (así el celular corrige lo que mostró de antemano).
- Límite: **8 por segundo** por jugador.

### `ping`
```json
{"v":1,"type":"ping","t":123456}
```
El host responde `pong` con el mismo `t`. El control calcula la latencia ida y vuelta.

### `leave`
```json
{"v":1,"type":"leave"}
```
Salida voluntaria: libera el lugar de inmediato (sin reserva de reconexión).

## TV → control

### `welcome`
```json
{"v":1,"type":"welcome","playerId":2,"name":"Pablo","color":"378add","colorIndex":1,"style":1,"token":"9f2c…","phase":"lobby"}
```
`color` es el color en hex (como siempre); `colorIndex` y `style` son los índices de la apariencia (nuevos y compatibles: un celular sin ellos sabe que la TV no permite elegir apariencia).
El token es secreto de ese control: nunca se envía a otros ni se expone a la lógica de juego.

### `reject`
```json
{"v":1,"type":"reject","reason":"room_full"}
```
Seguido del cierre de la conexión con código **4000** y el motivo como razón de cierre (el cliente usa esto como respaldo).

| Motivo | Cuándo |
|---|---|
| `bad_version` | Versión de protocolo distinta |
| `bad_room` | Código incorrecto |
| `room_full` | La sala alcanzó la capacidad elegida en la TV ("¿Cuántos juegan?", máximo 4) y no hay bots: si hay, un bot le deja su lugar a la persona (ver [Bots](#bots)) |
| `bad_name` | Apodo vacío tras limpiarlo |
| `game_in_progress` | Hay partida en curso (solo reconexiones permitidas) |
| `malformed` | Mensaje inválido antes de unirse |
| `timeout` | No mandó `join` a tiempo |

### `layout`
```json
{"v":1,"type":"layout","layout":"one_button","data":{"label":"¡TOCÁ!"}}
```

| Layout | Qué muestra | Qué manda |
|---|---|---|
| `wait` | "Mirá la TV" | nada |
| `joystick` | Joystick flotante | `axis` = dirección |
| `slider_h` | Slider horizontal | `axis[0]` = posición absoluta -1..1 |
| `one_button` | Botón gigante | `btn & 1` = apretado |

### `phase`
```json
{"v":1,"type":"phase","phase":"playing"}
```
Valores: `lobby`, `playing`, `results`. En modo competencia `results` cubre tanto el resumen de cada ronda como el podio final (el celular muestra "Mirá la TV" en ambos casos, más su resultado si recibe `standing`).

### `pong`
```json
{"v":1,"type":"pong","t":123456}
```

### `feedback` — vibrar/sonar en un celular
```json
{"v":1,"type":"feedback","kind":"point"}
```
La TV avisa a **un** jugador que le pasó algo en el juego para que su celular vibre y suene: `point` (sumó), `hit` (lo eliminaron), `win`, `lose`, `go` (arranca el juego), `count` y `tap`. Cualquier otro valor se descarta (`Protocol.parse_feedback`). La TV limita a un aviso cada 80 ms por jugador. Es informativo y **compatible**: los controles viejos lo ignoran y `VERSION` no cambia.

### `appearance` — apariencia confirmada
```json
{"v":1,"type":"appearance","color":9,"style":5,"taken":[0,5,7]}
```
La TV lo manda **a cada jugador por separado** con su color, su estilo y los colores que usan **los demás** (`taken`), cuando alguien entra, sale, se reconecta o cambia de apariencia, y al volver al lobby. El celular los muestra ocupados en el selector. `Protocol.parse_appearance` descarta el mensaje si `color` o `style` no son válidos y limpia `taken`. Informativo y **compatible**.

### `standing` — resultado propio (resumen y podio)
```json
{"v":1,"type":"standing","round":1,"total_rounds":3,"place":2,"points":70,"total":170,"rank":2,"players":4,"final":false}
{"v":1,"type":"standing","round":3,"total_rounds":3,"place":0,"points":0,"total":170,"rank":1,"players":4,"final":true}
```
La TV lo manda **a cada jugador por separado**, justo después de `phase: results` + `layout: wait`, al mostrar el resumen de una ronda y al mostrar el podio. Si el celular se reconecta durante el resumen o el podio, se le reenvía.

| Campo | Qué es | Rango (el control recorta) |
|---|---|---|
| `round` / `total_rounds` | "Ronda 1/3" (rondas salteadas no cuentan) | 0..99 |
| `place` | Puesto en **esta ronda**. `0` = sin puesto (no la jugó, o es el podio final) | 0..4 |
| `points` | Puntos que sumó en esta ronda | 0..100000 |
| `total` | Total acumulado en la competencia | 0..100000 |
| `rank` | Puesto en la **tabla general** (los empates comparten puesto) | 1..4 |
| `players` | Cantidad de jugadores en la tabla | 1..4 (nunca menor que `rank`) |
| `final` | `true` en el podio final | booleano |

- **Solo datos propios:** ni tokens ni puntajes de otros jugadores (esos se ven en la TV).
- **Solo informativo:** el control lo muestra y no responde nada; los puntos los decide la TV.
- **El control tampoco confía a ciegas:** `Protocol.parse_standing` descarta el mensaje si falta un campo, un tipo no coincide o hay `NaN`/infinito, y recorta los rangos.
- **Compatible:** es un tipo nuevo que los controles viejos ignoran, por eso `VERSION` sigue en 1.
- El celular lo muestra junto a "¡Mirá la TV!" y lo borra al volver al lobby o cuando empieza otro juego.

## Apariencia (color y estilo)

Cada jugador elige desde el celular el color y el estilo de su mascota (ver [ADR 0007](adr/0007-apariencia-del-jugador.md)). Por la red viajan **índices**, nunca colores libres:

| `color` | 0 | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 | 9 |
|---|---|---|---|---|---|---|---|---|---|---|
| Nombre | Rojo | Azul | Amarillo | Verde | Violeta | Rosa | Celeste | Blanco | Grafito | Negro |
| Hex | `e24b4a` | `378add` | `ef9f27` | `1d9e75` | `8b5cf6` | `ff6fb5` | `2ec4d6` | `f5f7fb` | `2b2d3a` | `16171d` |

| `style` | 0 | 1 | 2 | 3 | 4 | 5 | 6 |
|---|---|---|---|---|---|---|---|
| Nombre | Antena | Oso | Gato | Brote | Robot | Diablito | Conejo |

- Por defecto: color = índice del lugar (1P rojo, 2P azul, 3P amarillo, 4P verde) y estilo = lugar.
- **Colores únicos**: en `join`, si el pedido está ocupado se asigna el del lugar y, si tampoco está libre, el primero libre. Los estilos se pueden repetir (la etiqueta 1P–4P distingue).
- **Validación** (`Protocol.parse_color_index`, `parse_style_index`, `parse_look`): número entero (se acepta `3.0`, no `3.5`), finito y en rango. Cualquier otra cosa se descarta sin rechazar la conexión.
- **Solo cosmético**: nunca cambia puntos, puestos, lugar ni nombre.
- **Compatible**: `VERSION` sigue en 1. Un control viejo (sin `color`/`style` ni `look`) juega con la apariencia de su lugar; con una TV vieja el celular no muestra el selector.

## Bots

Los bots ([ADR 0010](adr/0010-bots.md)) **no usan el protocolo**: viven en la TV, no tienen conexión ni token y su entrada (`axis`/`btn`) pasa por la misma validación que la de un celular (`Protocol.parse_input`). Para los celulares casi no existen: cuentan en `standing.players` (son rivales de la tabla), pero su color **no** aparece en `appearance.taken`, porque una persona lo puede elegir.

- Si entra una persona y la sala está llena, reemplaza a un bot en vez de recibir `room_full`.
- Si una persona pide (en `join` o `look`) un color que usa un bot, se lo queda y el bot cambia de color.
- **Sin cambios de mensajes:** `VERSION` sigue en 1.

## Descubrimiento (UDP)

```json
{"v":1,"type":"announce","game":"party-games","name":"TV Living","port":47777}
```
**No incluye el código de sala** a propósito: estar en la misma Wi-Fi permite *ver* la TV, pero para unirse hay que leer el código en la pantalla.

## Códigos de cierre WebSocket

| Código | Significado |
|---|---|
| 1000 `bye` | El control se fue voluntariamente |
| 1001 | El host se apagó |
| 4000 | Rechazado/expulsado (razón = motivo) |
| 4001 `replaced` | El mismo jugador abrió otra conexión |
