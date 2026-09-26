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
```
- `room`: 4 caracteres de `ABCDEFGHJKLMNPQRSTUVWXYZ23456789` (sin I/O/0/1 para no confundir).
- `name`: se limpia (sin caracteres de control) y se recorta a 16.
- `token`: opcional. Si coincide con un jugador existente, se reconecta a su lugar.
- Debe llegar dentro de los **5 segundos** de abierta la conexión, o se corta.

### `input` — estado del control
```json
{"v":1,"type":"input","seq":1042,"axis":[0.73,-0.1],"btn":1}
```
- `seq`: contador creciente (permite detectar pérdidas o desorden en el futuro).
- `axis`: `[x, y]`, se recorta a longitud ≤ 1.
- `btn`: máscara de bits. `1` = A, `2` = B. Otros bits se descartan.
- Límite: **90 por segundo** por jugador; el exceso se descarta.

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
{"v":1,"type":"welcome","playerId":2,"name":"Pablo","color":"378add","token":"9f2c…","phase":"lobby"}
```
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
| `room_full` | La sala alcanzó la capacidad elegida en la TV ("¿Cuántos juegan?", máximo 4) |
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
