# Arquitectura

## Visión general

```
┌──────────────┐   WebSocket (Wi-Fi local)   ┌───────────────────────────────┐
│ Celular 1..4 │ ──── input (30/seg) ──────► │ TV · HostMain                  │
│ ControllerMain│ ◄─── layout / fase ──────── │  ├─ HostServer  (red, validación)│
└──────────────┘                              │  ├─ DiscoveryBeacon (anuncio UDP)│
       ▲                                      │  └─ MiniGame activo (lógica)     │
       └──────── anuncio UDP broadcast ────── └───────────────────────────────┘
```

**Un solo proyecto, dos modos.** `app/boot.gd` decide al arrancar si el dispositivo es la TV (`HostMain`) o un control (`ControllerMain`). Esto evita mantener dos apps y garantiza que ambas usen exactamente el mismo `Protocol`.

## Conceptos clave

### Host autoritativo
La TV es la única que decide qué pasa en el juego. Los celulares **no calculan nada**: solo mandan "el dedo está acá" y la TV decide si la paleta tocó la pelota.

*Ejemplo:* si un celular modificado mandara "gané 100 puntos", no tendría efecto, porque el protocolo ni siquiera tiene un mensaje para eso. Lo único que puede mandar es un eje entre -1 y 1 y botones, y el host los recorta y valida (`Protocol.parse_input`).

### Control "tonto" y layouts
El celular no sabe qué juego se está jugando. La TV le dice **qué control mostrar** (`layout`): joystick, slider o botón. Así un mismo control sirve para 3 o para 80 juegos, y agregar un juego no requiere actualizar la app del celular (siempre que use un layout existente).

*Ejemplo:* al arrancar Ping Pong, la TV envía `{"type":"layout","layout":"slider_h"}` y todos los celulares cambian a un slider.

### Sesión con fases
`HostMain` es una máquina de estados simple:

```
LOBBY ──elegir juego──► PLAYING ──juego termina──► RESULTS ──5 seg──► LOBBY
  ▲                        │
  └──── botón Atrás ───────┘
```

Durante `PLAYING` no entran jugadores nuevos, pero **sí** se reconectan los que ya estaban.

### Reconexión con token
Al unirse, cada jugador recibe un token aleatorio de 128 bits. Si el celular se bloquea o se corta el Wi-Fi, el cliente reintenta con backoff exponencial (0,5 s, 1 s, 2 s… hasta 5 s) presentando el token, y recupera **el mismo lugar, color e id**. El host reserva el lugar 30 segundos.

*Ejemplo:* Sofi está jugando, le entra una llamada y la app pasa a segundo plano. Su paleta queda quieta (input neutro), y cuando vuelve a la app sigue siendo la jugadora 2 sin tocar nada.

### Minijuegos como plugins
Cada juego hereda de `MiniGame` y se registra en `MiniGameRegistry.GAMES`. El lobby, la red y los demás juegos no se modifican. Ver [ADDING_A_MINIGAME.md](ADDING_A_MINIGAME.md).

## Flujo de un input (de punta a punta)

1. `VirtualJoystick` actualiza `value` al mover el dedo.
2. `ControllerMain._process` lo lee a 30 Hz y lo manda **solo si cambió** (o cada 250 ms como keepalive).
3. `ControllerClient.send_input` lo serializa con número de secuencia.
4. `HostServer` lo recibe, aplica límite de frecuencia (90/seg), valida con `Protocol.parse_input` y emite `input_received`.
5. `HostMain` lo pasa al `MiniGame` activo en `on_input`.
6. El juego guarda el último valor y lo aplica en `_physics_process`.

## Decisiones de diseño

Registradas en [adr/](adr/):
- [0001 · Motor: Godot 4](adr/0001-motor-godot.md)
- [0002 · Red local con WebSocket y host autoritativo](adr/0002-red-local-websocket.md)

## Límites conocidos (v0.1)

- WebSocket va sobre TCP: si se pierde un paquete, los siguientes esperan. En Wi-Fi doméstico normal es imperceptible (la latencia se ve en pantalla del control). Si hiciera falta, la capa de red está aislada para migrar a UDP/ENet sin tocar los juegos.
- Sin QR todavía (Godot no genera QR nativamente): está en el roadmap.
- Sin relay en la nube: TV y celulares deben estar en la misma red.
