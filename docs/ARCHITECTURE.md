# Arquitectura

## Visión general

```
┌──────────────┐   WebSocket (Wi-Fi local)   ┌───────────────────────────────┐
│ Celular 1..4 │ ──── input (30/seg) ──────► │ TV · HostMain                  │
│ ControllerMain│ ◄─── layout / fase ──────── │  ├─ HostServer  (red, validación)│
└──────────────┘                              │  ├─ DiscoveryBeacon (anuncio UDP)│
       ▲                                      │  ├─ Tournament (puntos, rondas)  │
       │                                      │  ├─ BotDriver (bots en la TV)    │
       │                                      │  ├─ Pantallas (host/ui/)         │
       │                                      │  └─ MiniGame activo (lógica)     │
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

### Sesión con fases (modo competencia)
`HostMain` es una máquina de estados simple que recorre la lista de juegos elegida:

```
LOBBY ──¡A jugar!──► PLAYING: intro ──OK o 6 s──► PLAYING: juego ──termina──► RESULTS (resumen de ronda)
  ▲                    ▲                                                          │
  │                    └──────────────── quedan juegos ◄──────────────────────────┤ OK o 15 s
  │                                                                               ▼
  └──── Cambiar juegos ◄──── RESULTS (podio) ◄──────────────────────────── no quedan juegos
                               │
                               └── Jugar otra vez ──► PLAYING: intro
```

- La **intro "¿Cómo se juega?"** es parte de `PLAYING`: la TV ya manda el `layout` (los celulares muestran el control para que cada uno se ubique), pero el minijuego todavía no existe y el input se descarta.
- Cada flecha del diagrama pasa por un **barrido de bloques** (`Transition`, ≤ 0,45 s): el cambio de pantalla ocurre cuando la pantalla está tapada y los cambios pedidos se ejecutan en el orden en que llegaron. Mientras dura, se ignoran las teclas del control remoto.

- En el **lobby** se elige cuántos juegan (esa es la capacidad de la sala) y qué minijuegos entran.
- **Atrás** del control remoto abre un menú de pausa: seguir, saltar el juego (sin puntos) o terminar (ir al podio).
- Desde el lobby hasta el podio no entran jugadores nuevos, pero **sí** se reconectan los que ya estaban.

### Puntos por posición
Cada minijuego reporta su puntaje propio y `Tournament` lo traduce a puestos: 1° 100 · 2° 70 · 3° 50 · 4° 30.

*Ejemplo:* en Arena, Pablo junta 12 estrellas y Sofi y Tomi 9. Pablo suma +100 y Sofi y Tomi empatan en 2° (+70 cada uno). Así 40 toques en Carrera no "pesan" más que 5 goles en Ping Pong. Detalle y alternativas en [ADR 0003](adr/0003-modo-competencia.md).

### Capas de la TV
```
HostMain (orquesta fases)
├─ PartyBackground           escenario desenfocado (prerenderizado) + nubes y brillos
├─ capa de juego             MiniGame activo (Node2D, dibuja su propio fondo)
├─ LobbyScreen               unirse · cuántos juegan · qué juegos
├─ GameIntroScreen           "¿Cómo se juega?" antes de cada juego
├─ RoundSummaryScreen        resumen por jugador tras cada juego
├─ FinalScreen               podio
├─ PauseMenu                 encima de las pantallas
└─ Transition                barrido entre pantallas, encima de todo
```
Cada pantalla es un componente independiente que **emite señales** (`start_requested`, `continue_requested`…) y no conoce a las demás. La lógica de puntos no vive en ninguna pantalla: está en `Tournament`, que se testea sola.

### Sistema visual
Colores, tipografía y funciones de dibujo están en `core/ui/ui_theme.gd` (*design tokens*). Las mascotas, chips y fondos se dibujan por código. Ver [ADR 0004](adr/0004-sistema-visual.md) y la skill `.claude/skills/diseno-tv/`.

### Sonido y vibración
Los efectos se sintetizan al iniciar (`core/audio/sfx.gd`, sin archivos de audio). Un juego llama `play_sfx("point")` para la TV y `notify_player(pid, "point")` para el celular de ese jugador; la TV lo reenvía como mensaje `feedback` con límite de frecuencia y el celular vibra (`Haptics`) y suena.

*Ejemplo:* en Esquivar, cuando un bloque te toca, la TV hace "¡pum!" y solo tu celular vibra fuerte (220 ms). Así sabés que quedaste afuera sin buscar tu mascota. Ver [ADR 0005](adr/0005-sonido-sintetizado.md).

### Rendimiento
Lo que no cambia no se redibuja en cada frame: el fondo y el campo de los juegos van en capas propias que se dibujan una vez, y las figuras se dibujan en lote. El celular baja a 30 fps y modo de bajo consumo mientras espera. Medición, presupuestos y detalles en [PERFORMANCE.md](PERFORMANCE.md) y [ADR 0006](adr/0006-rendimiento-capas-cacheadas.md).

### Reconexión con token
Al unirse, cada jugador recibe un token aleatorio de 128 bits. Si el celular se bloquea o se corta el Wi-Fi, el cliente reintenta con backoff exponencial (0,5 s, 1 s, 2 s… hasta 5 s) presentando el token, y recupera **el mismo lugar, color e id**. El host reserva el lugar 30 segundos.

*Ejemplo:* Sofi está jugando, le entra una llamada y la app pasa a segundo plano. Su paleta queda quieta (input neutro), y cuando vuelve a la app sigue siendo la jugadora 2 sin tocar nada.

### Bots: jugadores virtuales
Para jugar solo o completar la mesa (1 persona + 3 bots, 2 + 2), la TV puede ocupar lugares libres con **bots** (Fácil / Normal / Difícil). Un bot genera **las mismas entradas que un celular** (`axis`/`btn`) en cada paso de física, sin red: mira el estado público del juego (`MiniGame.bot_view()`), decide con reglas simples y tiempo de reacción, y `BotDriver` le pasa la entrada al juego por `on_input` después de validarla con `Protocol.parse_input`. Nunca decide resultados.

*Ejemplo:* en Ping Pong, el bot calcula dónde va a cruzar la pelota su línea (con los rebotes) y mueve el slider ahí, 0,13–0,34 s tarde según la dificultad. Si no llega, el punto es del otro: lo decide Ping Pong, igual que con una persona.

Se suman desde el lobby con el D-pad (OK en un lugar libre → elegir dificultad) y llevan la placa **BOT** en el lobby, el marcador y el resumen. Las personas tienen prioridad: si entra un celular y la sala está llena, reemplaza a un bot. `tools/simulate.gd` usa los mismos bots para jugar cientos de competencias sin pantalla y medir el balance. Ver [ADR 0010](adr/0010-bots.md).

```
host/bots/
├─ bot.gd            Bot: dificultad (reacción, puntería, temblor), predicción y entrada por defecto
├─ <id>_bot.gd       un bot por juego (arena, pingpong, tap_race, stop_clock, dodge, paint, sumo)
├─ bot_driver.gd     BotDriver: cada paso, bot_view() -> bots -> parse_input -> on_input
└─ bot_match.gd      BotMatch: un juego entero sin pantalla (tests y simulate.gd)
```

### Minijuegos como plugins
Cada juego hereda de `MiniGame` y se registra en `MiniGameRegistry.GAMES`. El lobby, la red y los demás juegos no se modifican. Ver [ADDING_A_MINIGAME.md](ADDING_A_MINIGAME.md).

## Flujo de un input (de punta a punta)

1. `VirtualJoystick` actualiza `value` al mover el dedo.
2. `ControllerMain._process` lo lee a 30 Hz y lo manda **solo si cambió** (o cada 250 ms como keepalive).
3. `ControllerClient.send_input` lo serializa con número de secuencia.
4. `HostServer` lo recibe, aplica límite de frecuencia (90/seg), valida con `Protocol.parse_input` y emite `input_received`.
5. `HostMain` lo pasa al `MiniGame` activo en `on_input`. (Los bots entran acá también: `BotDriver` arma la misma entrada, la valida con `Protocol.parse_input` y llama a `on_input`.)
6. El juego guarda el último valor y lo aplica en `_physics_process`.

## Decisiones de diseño

Registradas en [adr/](adr/):
- [0001 · Motor: Godot 4](adr/0001-motor-godot.md)
- [0002 · Red local con WebSocket y host autoritativo](adr/0002-red-local-websocket.md)
- [0003 · Modo competencia con puntos por posición](adr/0003-modo-competencia.md)
- [0004 · Sistema visual dibujado por código](adr/0004-sistema-visual.md)
- [0005 · Sonido sintetizado por código y vibración por eventos](adr/0005-sonido-sintetizado.md)
- [0006 · Rendimiento: capas cacheadas, figuras en lote y bajo consumo](adr/0006-rendimiento-capas-cacheadas.md)
- [0010 · Bots con reglas: jugadores virtuales que aprietan botones](adr/0010-bots.md)

## Límites conocidos (v0.1)

- WebSocket va sobre TCP: si se pierde un paquete, los siguientes esperan. En Wi-Fi doméstico normal es imperceptible (la latencia se ve en pantalla del control). Si hiciera falta, la capa de red está aislada para migrar a UDP/ENet sin tocar los juegos.
- Sin QR todavía (Godot no genera QR nativamente): está en el roadmap.
- Sin relay en la nube: TV y celulares deben estar en la misma red.
