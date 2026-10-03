# Prueba real: auditoría y guía para el viernes 9/10

Para el dueño y para el próximo que retome. Auditoría del 03/10/2026: ¿se rompe una partida de verdad (TV + celulares por Wi-Fi)? Qué se probó, qué se arregló, qué queda como riesgo y **cómo hacer la prueba del viernes** con una **Google TV (Xiaomi TV Stick 4K, 2.ª gen.) sin PC** y **2–3 personas**.

## 1. Cómo se probó

`tools/playtest.gd` levanta la TV (`HostMain`, la misma de la app) y **celulares simulados que se conectan por WebSocket de verdad** con el `ControllerClient` de la app: se unen con apodo y apariencia, cambian de mascota en el lobby, tocan "¡Listo!" en la intro y mandan entrada 30 veces por segundo con keepalive, como el celular. Unos juegan "dirigidos" (deciden con el cerebro de los bots mirando el juego, como una persona mira la TV) y otros al azar (joystick con vaivén, toques sueltos). Todo viaja por la red; la TV valida y decide como siempre.

```bash
# Una competencia con todos los juegos, 3 personas
godot --headless --path . -s res://tools/playtest.gd -- --scenario=room --humans=3
# 2 personas + 1 bot, Wi-Fi cargada (100–300 ms de demora con jitter, por un proxy TCP)
godot --headless --path . -s res://tools/playtest.gd -- --scenario=room --humans=2 --bots=1 --lag=100-300
# Sucesos de la vida real (ver abajo), 3 personas y Wi-Fi cargada
godot --headless --path . -s res://tools/playtest.gd -- --scenario=chaos --humans=3 --lag=100-300
# TV lenta: tope de 30 fps y 22 ms extra por cuadro (CPU ~3–4× más lenta que el contenedor)
godot --headless --path . -s res://tools/playtest.gd -- --scenario=room --humans=2 --max-fps=30 --slow-ms=22
# Sesión larga con memoria (competencias seguidas)
godot --headless --path . -s res://tools/playtest.gd -- --scenario=long --minutes=25
# Con render real (horneado 3D, tiempos de cuadro): xvfb-run … --rendering-driver opengl3 --audio-driver Dummy -s res://tools/playtest.gd -- …
```

Sale con código 1 si encuentra problemas: pantallas trabadas (intro > 20 s, juego > 200 s, resumen > 25 s), celulares que no recibieron su control o su resultado, reconexiones que no vuelven al mismo lugar, pausa que no pausa. Los errores del motor (`SCRIPT ERROR`, `push_error`) se buscan en el log. `--summary=4` acorta la espera en el resumen; `--json=` guarda los números.

**Sucesos (`--scenario=chaos`):** en cada juego un celular se bloquea 10 s (alternando "socket abierto": la app deja de correr y no manda nada, y "se corta el Wi-Fi": la conexión se cierra), también en el resumen y en el podio; en el 3.er juego el último celular se va con "Salir"; en el 4.º alguien quiere entrar tarde; en el 5.º la TV aprieta Atrás (pausa 4 s y sigue). Después, en el lobby: entra el que llegó tarde, otro con el **mismo apodo** ("Pablo") y alguien **cierra la app** sin "Salir" y la vuelve a abrir.

## 2. Qué se corrió

| Corrida | Personas + bots | Extras | Resultado |
|---|---|---|---|
| room | 2 + 0 | los 13 juegos (con Ping Pong) | sin problemas ni errores del motor |
| room | 3 + 0 | 12 juegos | sin problemas |
| room | 2 + 1 | | sin problemas |
| room | 3 + 1 | | sin problemas |
| room | 1 + 3 | Wi-Fi cargada (100–300 ms) | sin problemas |
| room | 2 + 0 | TV lenta (30 fps + 22 ms/cuadro) | sin problemas; mismas duraciones |
| room | 3 + 1 | TV lenta (30 fps + 22 ms/cuadro) | sin problemas; mismas duraciones |
| chaos | 3 + 0 | Wi-Fi cargada | encontró 2 errores (arreglados, §3) |
| room, xvfb (render real) | 3 + 0 | `user://` vacío (primer arranque) y después con caché | ver §4 |
| long | 2 + 2 | PLACEHOLDER_LONG | ver §5 |

Ayudas de los eliminados activadas en todas. Con 3–4 jugadores Ping Pong se saltea solo (es de a 2), como corresponde.

## 3. Qué se encontró y se arregló

Cada arreglo tiene su test en `tests/run_tests.gd`.

1. **Celular bloqueado con la conexión abierta = jugador "fantasma" con el joystick a fondo.** Al bloquear la pantalla o pasar a otra app, Android suele dejar el socket abierto: la app deja de correr y no manda nada, pero la TV no se enteraba. Seguía mostrándolo conectado y **usando su última entrada** (en Karts el auto seguía acelerando, en Empujones la mascota seguía empujando). Ahora, con **4 s sin ningún mensaje** (el celular manda un `ping` por segundo), la TV lo da por desconectado: el juego recibe entrada neutra y se ve el aviso. Mientras el socket siga abierto **no** le corre la reserva de 30 s, y vuelve solo apenas manda algo. Test: `test_silent_phone_counts_as_disconnected`. Medido en la prueba: vuelve en ~1 s; si además se cortó la conexión, en ~2 s.
2. **Cerrar la app y volver a abrirla = "¡La sala está llena!".** El token de reconexión vive en la app: al cerrarla (o si Android la cierra para liberar memoria) se pierde. Al volver a entrar, su lugar seguía reservado 30 s, así que con la sala llena recibía `room_full`, y en medio de la partida `game_in_progress` (quedaba afuera de la competencia). Ahora, **con el mismo apodo**, recupera **su** lugar desconectado (mismo número, color y puntos). Nunca toma el lugar de alguien conectado: dos "Pablo" conectados son dos jugadores (1P y 4P). Test: `test_reopened_app_reclaims_slot_by_name`. Riesgo aceptado en [SECURITY.md](SECURITY.md).
3. **Errores `ready_state != STATE_OPEN` en el log.** La TV seguía mandando mensajes a un celular que había empezado a cerrar la conexión; además lo veía conectado hasta el cierre del socket. Ahora deja de mandarle y lo da por cerrado a los 2 s. El celular tampoco manda con el socket ya cortado. Test: `test_phone_closing_without_finishing`.
4. **"¡Que no te deje la cámara!" terminaba antes de la foto con todos en 0 m** ([PENDIENTES.md](PENDIENTES.md) §3): era **solo de la herramienta de capturas** y ya estaba resuelto. Con render por software, la cuenta de 6 s de la intro se terminaba mientras se horneaba. El juego arrancaba solo cuando la herramienta todavía no mandaba entrada, y la cámara alcanzaba a todos antes de la línea de salida. `9f05a7e` (pausar la intro mientras se hornea) lo arregló, y las capturas de después muestran el juego. Reproducido con xvfb y 4 controles por la red: la entrada llega y avanzan. Sin cambios en el juego.

Lo que funcionó como dice [PROTOCOL.md](PROTOCOL.md) sin cambios:
- reconexión con token en cada tipo de juego, en el resumen (se le reenvía su resultado) y en el podio;
- el que se va con "Salir" libera su lugar y la competencia sigue con los demás;
- el que llega tarde ve "Están en medio de una partida" (`game_in_progress`) y entra sin problema al volver al lobby;
- la pausa congela el juego (los celulares siguen conectados) y sigue al volver;
- con 100–300 ms de demora todo avanza igual;
- en la TV lenta, juegos y temporizadores usan el tiempo del juego (física a paso fijo): las duraciones no cambian.

## 4. TV lenta y primer arranque

**Justicia con cuadros lentos.** Todos los juegos corren en `_physics_process` con paso fijo (1/60 s). Si la TV dibuja menos cuadros, hace varios pasos por cuadro (hasta 8), así que el juego dura lo mismo y todos reciben la entrada con la misma granularidad. Desenfunde y Reloj exacto miden con el reloj del juego (Desenfunde suma lo que pasó desde el último paso, con tope de 2 cuadros). Medido:

PLACEHOLDER_SLOW

**Horneado.** Mascotas 3D (en memoria: se hornean **cada vez que se abre la app**), tablero 2.5D de cada juego y piezas 3D (en disco, `user://board25d/`, `user://props3d/`) y música generada (`user://music_cache/`). Mientras algo no está, se dibuja la versión 2D: **no se congela**, como mucho un tirón de una fracción de segundo.

PLACEHOLDER_BAKE

## 5. Sesión larga

PLACEHOLDER_LONGTEXT

## 6. Riesgos conocidos (no se arreglaron)

1. **Instalación y arranque en la Google TV.** El APK todavía no aparece en el inicio de Google TV (falta el *Gradle build* para "Show In Android TV", ver [BUILD.md](BUILD.md)). Hay que instalarlo **antes** (con `adb` desde una PC, o con una app tipo *Send files to TV* / *Downloader*) y abrirlo desde **Configuración → Apps → Ver todas las apps → PARTY-GAME → Abrir**. Probarlo el jueves, no el viernes.
2. **Celulares: hace falta instalar el APK en cada uno** (Android, "orígenes desconocidos"). Un invitado con **iPhone no puede jugar** hasta que esté el control web que está haciendo otro agente (con QR). Si llega a estar para el viernes, conviene probarlo antes: tiene que mandar un `ping` por segundo (§3.1; si no, la TV lo marca "desconectado" a los 4 s).
3. **Volver a abrir la app tiene 30 s.** Si alguien cierra la app sin querer en medio de la partida, recupera su lugar entrando con el **mismo apodo** dentro de los 30 s de reserva (la app recuerda el apodo; la TV aparece sola en la lista; falta escribir el código). Después de 30 s queda afuera de esa competencia y entra en la siguiente. No se alargó la reserva: el aviso de la TV muestra una cuenta de 30 s y cambiarlo era tocar diseño.
4. **Aviso "se desconectó · N s" de un celular bloqueado.** Con la conexión abierta (§3.1) la reserva no corre, pero el aviso igual cuenta 30 s y desaparece; el jugador sigue en su lugar y vuelve solo. Solo es un texto engañoso.
5. **Horneado de las mascotas 3D en cada arranque.** Las mascotas se hornean en memoria cada vez que se abre la app (tableros, piezas y música quedan en disco). En la TV lenta, los primeros juegos pueden arrancar con la mascota 2D unos segundos (§4). Se ve distinto pero no se traba. Medir en el Xiaomi: si molesta, dejar la app abierta en el lobby un par de minutos antes de empezar.
6. **Memoria.** En la sesión larga (con render por software) se estabiliza en ~220 MB de RAM y ~270 MB de texturas después de la primera competencia (§5). No crece, pero para un aparato de 2 GB es bastante: mirar si la TV cierra la app (vuelve al inicio de Google TV) después de varias competencias.
7. **Protector de pantalla.** Durante la partida nadie toca el control remoto. La app pide pantalla encendida (`keep_screen_on`, default de Godot), pero no se probó en el Xiaomi: si aparece el protector, desactivarlo en Configuración → Sistema → Energía y luz.
8. **Juegos que con jugadores perdidos terminan enseguida.** En ¡Que no te deje la cámara! quien no avanza hacia la derecha queda afuera en ~2 s, y con 2 jugadores el juego termina en ~5 s. Es la regla, pero si la gente no entiende la intro dura un suspiro: anotarlo. Empujones de a 2 también puede durar 5 s o 65 s.
9. **Mismo apodo.** Dos personas pueden llamarse igual; se distinguen por 1P–4P y el color. Si uno de los dos se desconecta y un tercero entra con ese apodo, se queda con su lugar (§3.2). En una fiesta no debería pasar.
10. **No probado con aparatos reales:** Wi-Fi real (2,4 GHz con microondas, router con "aislamiento de clientes"), descubrimiento UDP en el Xiaomi, multitáctil del joystick A/B, sonido/vibración, 60 fps reales en la GPU Mali.

## 7. Guía para el viernes (Google TV, sin PC, 2–3 personas)

TV: **Xiaomi TV Stick 4K (2.ª gen.) con Google TV**: CPU ARM chica de 4 núcleos, GPU Mali de gama baja, ~2 GB de RAM. Corre la app como TV (host): sin pantalla táctil, `app/boot.gd` arranca sola en modo TV. Se maneja con el control remoto (flechas, OK, Atrás). Celulares: la app instalada en cada uno.

### 7.1 El día antes (jueves), 30 minutos

- [ ] **Instalar el APK en la TV** y confirmar que abre desde **Configuración → Apps → Ver todas las apps → PARTY-GAME → Abrir** (todavía no aparece en el inicio de Google TV, ver riesgo 1). Instalar la **misma versión** en la TV y en todos los celulares: con versiones distintas el celular muestra "Actualizá las dos".
- [ ] **Jugar una competencia completa con bots en la TV** (lobby: OK sobre un lugar libre → "Sumar bot", con un celular propio para arrancar). Deja guardados en el disco los tableros 3D, las piezas y la música (`user://board25d/`, `props3d/`, `music_cache/`): el viernes el primer ingreso a cada juego es más rápido. Anotar cuánto tarda en abrir y si algún juego se ve con la mascota 2D o da tirones.
- [ ] **Instalar la app en los celulares de los invitados** (si se puede, antes): Android → permitir "orígenes desconocidos" ([BUILD.md](BUILD.md)). Con iPhone no se puede hasta que esté el control web.
- [ ] Ver si aparece el **protector de pantalla** con la app abierta 15 minutos sin tocar el control remoto. Si aparece: Configuración → Sistema → Energía y luz → protector de pantalla más largo o apagado.

### 7.2 Antes de empezar (viernes, 10 minutos)

- [ ] **Misma Wi-Fi** en la TV y en todos los celulares, la **principal** (no la de invitados: suele tener "aislamiento de clientes" y los celulares no ven la TV). Si el router tiene 2,4 y 5 GHz con nombres distintos, todos en la misma.
- [ ] **Firewall:** sin PC no hay nada que abrir. Solo el router: sin "aislamiento AP/de clientes".
- [ ] **Abrir la app en la TV y dejarla 1–2 minutos en el lobby** mientras se unen: hornea las mascotas (eso se repite en cada arranque).
- [ ] **Sonido:** volumen de la TV a mitad; la música y los efectos se apagan desde la pausa (Atrás → "Sonido" y los volúmenes de música y efectos). En los celulares, sonido y vibración prendidos (engranaje).
- [ ] **Batería:** celulares con más del 50 % (la app deja la pantalla prendida) y un cargador a mano.
- [ ] **Anotar la IP de la TV** que aparece en el lobby (debajo del código): si un celular no encuentra la TV en la lista, se escribe a mano.
- [ ] Contarles **tres cosas**: el código de 4 fichas está en la TV; "Salir" se mantiene apretado (el Atrás del celular no saca del juego); si se cierra la app sin querer, abrirla y entrar **con el mismo apodo enseguida** (menos de 30 s).

### 7.3 Orden sugerido (~20 minutos, 2–3 personas)

En el lobby, cada juego se marca o desmarca con OK. Con "Orden: lista" se juegan en el orden de la lista. Cada juego suma ~6 s de intro y ~15 s de resumen (se puede pasar con OK).

**Competencia 1, para aprender (~9 min), Ayudas: No:** Arena de estrellas → *Ping Pong (solo si son 2)* → Carrera de toques → Reloj exacto → Esquivar → Pintar el piso → Empujones → Karts de mascotas → Desenfunde. Arranca con joystick libre (Arena) y un botón (Carrera de toques), y deja un juego largo (Karts) cerca del final. Termina con un duelo corto.

**Competencia 2, la revancha (~10 min), Ayudas: Sí:** Esquivar → Empujones → ¡Que no te deje la cámara! → Memoria de colores → Pool loco → Carrera de obstáculos. Las ayudas de los eliminados están en Esquivar (escudo) y Empujones (salvavidas): el que queda afuera elige con el joystick a quién ayudar y paga 10 puntos.

Con 2 personas, en la competencia 2 se puede sumar **1 bot Normal** (lobby: OK sobre un lugar libre); Ping Pong se saltea solo con 3 o más. Con 3 personas, sin bots.

### 7.4 Si algo sale mal

| Pasa | Qué hacer |
|---|---|
| El celular no encuentra la TV | Misma Wi-Fi (no la de invitados) → escribir la IP del lobby a mano |
| "¡La sala está llena!" | En la TV, subir "¿Cuántos juegan?"; si era alguien que cerró la app, que entre **con el mismo apodo** |
| "Están en medio de una partida" | Se une al volver al lobby (después del podio) |
| Se le cerró la app a alguien | Abrirla y entrar con el mismo apodo **antes de 30 s**: vuelve a su lugar con sus puntos |
| Un celular quedó bloqueado | La TV muestra "se desconectó" a los 4 s y su mascota queda quieta; al desbloquear vuelve solo |
| Un juego no se entiende o se traba | Atrás (pausa) → "Saltar este juego"; anotarlo |
| Hay que cortar | Atrás → "Salir de la competencia" → "Sí, salir" → podio con lo jugado |
| La app de la TV se cerró | Abrirla de nuevo; la competencia se pierde (los puntos no se guardan) |

### 7.5 Qué observar y anotar

- **Unirse:** cuánto tardan, si encontraron la TV solos, si entendieron el código de fichas.
- **Intro de cada juego:** ¿la leen? ¿alcanza con el texto, el dibujo del control y la línea del celular? ¿Quién pregunta "¿qué hago?"?
- **Durante el juego:** demoras ("apreté y no respondió"), tirones de imagen, mascotas que se ven planas (2D), cortes de conexión.
- **Quién gana:** ¿siempre el mismo? ¿algún juego que nadie gana o que se decide por azar?
- **Ganas:** risas, quejas, "¡otra!", aburrimiento; si 20 min fue poco o mucho.
- **Técnico:** ¿se calienta el stick? batería de los celulares al final; ¿la TV cerró la app sola?

### 7.6 Planilla

Fecha: ____  Personas: ____  Celulares (marca/modelo): ________________  Wi-Fi: ________

| # | Juego | ¿Se entendió? (sí / más o menos / no) | Demoras o tirones | Ganó | ¿Divertido? (1–5) | Notas (qué dijeron) |
|---|---|---|---|---|---|---|
| 1 | | | | | | |
| 2 | | | | | | |
| 3 | | | | | | |
| 4 | | | | | | |
| 5 | | | | | | |
| 6 | | | | | | |
| 7 | | | | | | |
| 8 | | | | | | |
| 9 | | | | | | |
| 10 | | | | | | |

Unirse (min): ____  Desconexiones (quién, cuándo, ¿volvió solo?): ____________________

Favorito: ________  Para sacar: ________  ¿Jugarían otra vez? ____  Lo que más confundió: ____________________

