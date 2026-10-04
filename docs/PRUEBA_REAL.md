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
| chaos | 3 + 0 y 2 + 1 | con los arreglos | sin problemas |
| **Después de integrar Google TV y el control web (85dfbe5)** | | | |
| chaos | 3 + 0 | Wi-Fi cargada | sin problemas |
| room | 3 + 0 | TV lenta | sin problemas |
| room | 2 + 1 | Wi-Fi cargada | sin problemas |
| `node tools/web_e2e.mjs` | 3 navegadores (iPhone apaisado y vertical, Pixel) | Chromium real contra la TV | todo OK (QR, layouts multitáctiles, reconexión, cerrar y reabrir la página, podio, "Salir") |
| `node tools/web_chaos.mjs` (04/10) | 3–5 navegadores, cada uno detrás de una "Wi-Fi fea" | 3G lento, demora + retransmisiones, cortes de 5/12/20 s, bloqueo 20/30/40 s, girar, recargar, dos pestañas, Atrás, sala llena, partida en curso, la TV que se cierra y se reinicia | ver §6 y [ADR 0022](adr/0022-control-web.md#celulares-reales-y-condiciones-feas-2026-10-04) |
| room, xvfb (render real) | 3 + 0 | `user://` vacío (primer arranque) y después con caché | ver §4 |
| long, xvfb | 2 + 2 | 36 min seguidos: 4 competencias, 48 rondas | sin problemas; memoria plana (§5) |

Ayudas de los eliminados activadas en todas. Con 3–4 jugadores Ping Pong se saltea solo (es de a 2), como corresponde.

## 3. Qué se encontró y se arregló

Cada arreglo tiene su test en `tests/run_tests.gd`.

1. **Celular bloqueado con la conexión abierta = jugador "fantasma" con el joystick a fondo.** Al bloquear la pantalla o pasar a otra app, Android suele dejar el socket abierto: la app deja de correr y no manda nada, pero la TV no se enteraba. Seguía mostrándolo conectado y **usando su última entrada** (en Karts el auto seguía acelerando, en Empujones la mascota seguía empujando). Ahora, con **4 s sin ningún mensaje** (el celular manda un `ping` por segundo), la TV lo da por desconectado: el juego recibe entrada neutra y se ve el aviso. Mientras el socket siga abierto **no** le corre la reserva de 30 s, y vuelve solo apenas manda algo. Test: `test_silent_phone_counts_as_disconnected`. Medido en la prueba: vuelve en ~1 s; si además se cortó la conexión, en ~2 s. **Con el control web:** su `setInterval` de `ping` (1 s) corre siempre que está unido, también en el lobby y en "Mirá la TV". Un navegador que lo espacia hasta ~2 s (pestaña en segundo plano, ahorro de batería) sigue conectado (`test_web_like_client_pinging_slowly_stays_connected`). Con la pantalla bloqueada (JS suspendido) se marca desconectado a los 4 s y vuelve solo al desbloquear. Cualquier control nuevo tiene que mandar algo al menos cada 1 s ([PROTOCOL.md](PROTOCOL.md#ping)).
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

| Corrida | Cuadros (p50 / p95) | Arena | Carrera de toques | Reloj exacto | Pintar | Pool | Carrera de obstáculos |
|---|---|---|---|---|---|---|---|
| Normal (headless, 145 fps) | 6,9 / 9–10 ms | 31,6 s | 9,4–9,7 s | 15,2–15,5 s | 49,8 s | 54,8 s | 40–43 s |
| TV lenta (tope 30 fps + 22 ms por cuadro) | 33,3 / 35–45 ms | 31,6 s | 9,5–9,7 s | 15,2–15,4 s | 49,7–49,8 s | 54,7–54,8 s | 42–43 s |
| Render por software (xvfb, 10–25 fps reales) | 35–90 / 45–135 ms | 31,6 s | 12,4 s* | 15,9 s | 49,8 s | 54,9 s | 41,7 s |

Las duraciones no cambian con la velocidad de la TV: los juegos con tiempo fijo duran lo mismo al centésimo, y los que dependen de lo que hacen los jugadores (Carrera de toques, Empujones, Esquivar, Karts) varían igual que entre dos partidas normales. *Carrera de toques en xvfb dura más porque los celulares de prueba tocan más lento con la máquina cargada, no por la TV. **Ningún juego se volvió injugable a 30 fps.** Lo que se pierde es suavidad: la pelota de Ping Pong y los autos de Karts avanzan dos pasos por cuadro. Para mirar en el Xiaomi: Pintar el piso, Reloj exacto, Empujones y ¡Que no te deje la cámara! son los más pesados de dibujar (con render por software, p50 de 60–90 ms contra 35–45 ms de Pool o Esquivar).

**Horneado.** Mascotas 3D (en memoria: se hornean **cada vez que se abre la app**), tablero 2.5D de cada juego y piezas 3D (en disco, `user://board25d/`, `user://props3d/`) y música generada (`user://music_cache/`). Mientras algo no está, se dibuja la versión 2D: **no se congela**, como mucho un tirón de una fracción de segundo.

Medido con render por software (xvfb + llvmpipe: en este contenedor la TV corre a 10–25 fps, más lento que el Xiaomi en CPU), 2–3 celulares por la red:

| | `user://` vacío (primer arranque) | Con caché en disco (segunda vez) |
|---|---|---|
| Abrir la app → lobby con todo horneado | 10,5 s (lo que se ve: el lobby al instante, las mascotas pasan de 2D a 3D) | — |
| Juegos que arrancan antes de terminar de hornear (intro de ~6,5 s) | 6 de 12: Arena, Carrera de toques, Esquivar, Pintar, Karts y ¡Que no te deje la cámara! | 4 de 12: Arena, Carrera de toques, Esquivar y ¡Que no te deje la cámara! |
| Los demás terminan de hornear en | 0,5–3,2 s de intro | 0–4,8 s de intro |
| Disco usado | tableros 5 MB, música 15 MB, piezas 0,4 MB, *shaders* 3,7 MB | igual |

Con la app **1 minuto en el lobby** antes de arrancar (`--lobby=60`, `user://` vacío, 2 celulares, ya con Google TV y el control web integrados), solo el **primer juego** (Arena) arrancó sin terminar de hornear; los otros 12 terminaron en 0–4,7 s de intro. Por eso la guía pide dejar la app abierta en el lobby mientras se unen. En el podio: atlas de mascotas 38,6 MB (presupuesto 40 MB), tableros 2.5D 7,9 MB.

Con caché seguían arrancando en 2D los que estrenan **poses de mascota** (hasta el 04/10 vivían en memoria y se horneaban de nuevo en cada arranque; ahora quedan en disco con el resto de la mascota: riesgo 5). Ninguno se congela: la intro sigue su cuenta y el juego arranca a tiempo; durante unos segundos se ven algunas mascotas 2D y alguna pose aparece un cuadro tarde. En el Xiaomi (GPU real, CPU más lenta que esta) hay que medirlo: es la tarea del jueves (§7.1).

## 5. Sesión larga

`--scenario=long`, xvfb (render real), 2 celulares + 2 bots, **36 min seguidos: 4 competencias, 48 rondas**, con "Jugar otra vez" y vuelta al lobby. Sin problemas ni errores del motor.

| Momento | RAM estática | Objetos | Nodos | Huérfanos | Texturas |
|---|---|---|---|---|---|
| Inicio (lobby) | 107 MB | 2 827 | 592 | 0 | 62 MB |
| 6 min (primera competencia, juegos nuevos) | 193 MB | 3 270 | 365 | 0 | 242 MB |
| Podio 1 (9,5 min) | 219 MB | 3 356 | 385 | 0 | 268 MB |
| Podio 3 (27 min) | 219 MB | 3 363 | 385 | 0 | 267 MB |
| Podio 4 (36 min) | 219 MB | 3 419 | 385 | 0 | 267 MB |

Crece durante la primera competencia (cada juego nuevo hornea su tablero y sus poses) y después **queda plano**: sin fugas de nodos ni de objetos. Las texturas incluyen el atlas de mascotas (presupuesto 40 MB), el tablero 2.5D del juego en curso, la sala 3D y el render. ~270 MB de texturas y ~220 MB de RAM era mucho para un aparato de 2 GB; con el perfil "TV de poca memoria" (04/10, automático en el stick) baja a ~80 MB de texturas y ~105 MB de RAM (riesgo 6). Igual conviene mirarlo en el Xiaomi.

## 6. Riesgos conocidos (no se arreglaron)

1. **Instalación en la Google TV.** Sin PC ni celular: con la app **Downloader** y el código **`1669675`** (o la dirección fija `https://github.com/vepamusic11/PARTY-GAMES/releases/download/prueba/party-game.apk`); alternativa: *Send Files to TV* desde un celular ([BUILD.md](BUILD.md#jugar-en-una-google-tv-sin-pc)). El APK de la CI ya sale con Gradle (aparece en la fila de apps con su banner, verificado con `aapt2`), pero no se probó en un aparato real: si no apareciera, se abre desde **Configuración → Apps → Ver todas las apps → PARTY-GAME → Abrir**. Probarlo el jueves, no el viernes.
2. **Control web (QR) con iPhone: nunca se probó en Safari real.** No hay WebKit en el contenedor: lo de iOS se revisó a mano contra comportamientos conocidos de Safari 15–18 y se arregló lo encontrado ([ADR 0022](adr/0022-control-web.md#celulares-reales-y-condiciones-feas-2026-10-04): pellizco/zoom, audio que queda "interrupted", Wake Lock, girar, zonas seguras, sockets muertos al desbloquear, dos pestañas). **Probarlo el jueves con un iPhone** (§7.1). Lo que queda: Safari anterior a 16.4 no tiene Wake Lock, así que la pantalla se apaga si no se toca (en el lobby, con el bloqueo automático en 30 s); al desbloquear vuelve solo en ~1 s. En iPhone no vibra, y con el interruptor de silencio puesto no suena.
   - ~~**La pantalla del celular se apagaba sola.**~~ **Arreglado (04/10):** Wake Lock solo existe con https/localhost y el QR abre `http://<IP>`, así que en la casa nunca estaba: un iPhone con bloqueo a los 30 s se apagaba en el resumen o en la intro (nadie toca nada) y se desconectaba. Ahora el control reproduce en bucle un video mudo e invisible desde el toque de "Unirme" (truco de NoSleep.js, [ADR 0022](adr/0022-control-web.md)). **A mirar el viernes:** que ningún celular se apague solo en el lobby ni en el resumen; en iPhone puede pausar la música que el invitado tenía puesta.
   - **iPhone bloqueado más de 30 s.** Si iOS corta la conexión al bloquear (no se sabe si lo hace siempre ni cuándo), en la TV corre la reserva de 30 s. Bloqueado más tiempo, pierde el lugar: en el lobby vuelve a entrar solo al desbloquear (como alguien nuevo, con su apodo y su mascota); en medio de una competencia ve "Estuviste afuera un rato y se liberó tu lugar…" y entra solo cuando la TV vuelve al lobby. Si iOS deja la conexión abierta, el lugar lo espera sin límite. Alargar la reserva (`RECONNECT_GRACE_MS`) es un cambio de una línea si en la prueba molesta.
3. **Reabrir la app o la página: 30 s.** Quien se queda sin conexión (app cerrada, página cerrada) recupera su lugar dentro de los 30 s de reserva: el control web solo (token guardado) y la app con el **mismo apodo** (§3.2). Después de 30 s queda afuera de esa competencia y entra en la siguiente. No se alargó la reserva: el aviso de la TV muestra una cuenta de 30 s y cambiarlo era tocar diseño.
4. ~~**Aviso "se desconectó · N s" de un celular bloqueado.**~~ **Arreglado (04/10):** con la conexión abierta la TV dice "Sofi no responde — su lugar lo espera" (chico: "sin señal"), sin cuenta ni vencimiento; si la conexión se cierra, cuenta la reserva real (`test_silent_phone_toast_has_no_countdown`).
5. **Horneado de las mascotas 3D.** ~~Se horneaban en memoria en cada arranque~~: desde el 04/10 quedan en disco (`user://mascot_cache/`, [ADR 0023](adr/0023-tv-de-poca-memoria.md)); con la caché llena el lobby tiene todas las mascotas 3D en 0,8 s (antes 10,5 s, llvmpipe) y los juegos quedan listos en la intro. La **primera vez** igual se hornea: por eso la competencia del jueves (§7.1) también deja las mascotas en el disco. Si alguien elige un color o mascota nuevos el viernes, esa se hornea en el momento (unos segundos en 2D, no se traba).
6. **Memoria.** En la sesión larga (render por software) se estabilizaba en ~220 MB de RAM y ~270 MB de texturas (§5): ~120 MB eran cachés de letras. Desde el 04/10, en Android con ≤ 3 GB se prende solo el perfil "TV de poca memoria" ([ADR 0023](adr/0023-tv-de-poca-memoria.md)): dos competencias seguidas quedan en ~105 MB de RAM y ~80 MB de texturas (forzado en la PC con `-- --low-memory`), sin cambiar cómo se ve. Igual mirar si la TV cierra la app sola (vuelve al inicio de Google TV) después de varias competencias: con OpenGL ES en la Mali puede ser distinto.
7. **Pestaña en segundo plano más de 5 min** (control web): Chrome espacia los timers a 1 por minuto, la TV lo marca "no responde" y al abrir la pestaña reconecta enseguida (si la TV no habló en 2,5 s, no espera al socket viejo). Es lo esperado: nadie juega con la pestaña escondida.
8. **Juegos que con jugadores perdidos terminan enseguida.** En ¡Que no te deje la cámara! quien no avanzaba hacia la derecha quedaba afuera en ~2 s, y con 2 jugadores el juego terminaba en ~5 s. **Arreglado el 04/10** (§8): la cámara arranca despacito 3–5 s (más con menos jugadores), las mascotas salen más adentro, la TV dice "¡Corré a la derecha!" y el celular también; quien no se mueve dura ~5–6 s. Además había otra causa: **no tenía bot** (el bot base movía el joystick en círculos y lo dejaba la cámara a los 2 s): con 1 persona + 1 bot el juego duraba 5 s. Ahora tiene bot. Empujones de a 2 sigue pudiendo durar 5 s o 65 s: es el juego.
9. **Mismo apodo.** Dos personas pueden llamarse igual; se distinguen por 1P–4P y el color. Si uno de los dos se desconecta y un tercero entra con ese apodo desde la **app** (sin token), se queda con su lugar (§3.2). En una fiesta no debería pasar.
10. **Control web: lo que ve el invitado cuando algo falla.** Probado con `tools/web_chaos.mjs`: Wi-Fi cortada (aviso "Se cortó la conexión · Reconectando…" a los ~6 s; vuelve sola a su lugar en < 1 s al volver la Wi-Fi), sin Wi-Fi ("Tu celular se quedó sin Wi-Fi"), la TV que cierra el juego o se corta ("No encontramos el juego en la TV…"), la TV reiniciada ("Ese código ya no sirve: la TV se reinició. Escaneá otra vez el QR"), sala llena y partida en curso (entra solo cuando se puede), dos pestañas ("Abriste el control en otra pestaña…"). Encontró y se arregló un error de la TV: con Wi-Fi floja el tope de entrada tiraba las ráfagas que TCP entrega después de un tirón y el joystick quedaba trabado (`test_input_rate_limit_tolerates_wifi_bursts`). Si la Wi-Fi no vuelve en 90 s, el celular deja de intentar y pide tocar ¡Unirme!. Riesgos de navegador no probados: el modo "Siempre usar conexiones seguras" de Chrome y el aviso de Safari para sitios `http` podrían mostrar una advertencia antes de la página (la TV sirve `http://` en la red local; las IP privadas suelen quedar exentas); el router con "aislamiento de clientes" impide todo (§7.4).
11. **No probado con aparatos reales:** Wi-Fi real (2,4 GHz, router con "aislamiento de clientes"), multitáctil en celulares reales, sonido y vibración, 60 fps reales en la GPU Mali, tiempo real de horneado en el Xiaomi.

## 7. Guía para el viernes (Google TV, sin PC, 2–3 personas)

TV: **Xiaomi TV Stick 4K (2.ª gen.) con Google TV** (CPU ARM chica de 4 núcleos, GPU Mali de gama baja, ~2 GB de RAM). Corre la app como TV y abre directo en el lobby. Se maneja con el control remoto: flechas, OK y Atrás (pausa). **Invitados: escanean el QR del lobby con la cámara** y juegan desde el navegador (Android o iPhone, sin instalar nada). Si alguien ya tiene la app Android, también sirve.

### 7.1 El día antes (jueves), 30–40 minutos

- [ ] **Instalar el APK en la TV** con **Downloader** y el código **`1669675`** ([BUILD.md → Lo más fácil: instalar con la app Downloader](BUILD.md#lo-más-fácil-instalar-con-la-app-downloader-sin-celular)). Confirmar que abre en el lobby y que se ve el **QR**.
- [ ] **Jugar una competencia completa** con tu celular (escaneando el QR) + 2 bots (lobby: OK sobre un lugar libre → "Sumar bot"). Deja en el disco de la TV las mascotas 3D, los tableros, las piezas y la música, así el viernes el primer ingreso a cada juego es más rápido. Anotar cuánto tarda en abrir, si algún juego da tirones o se ve con la mascota 2D, y si la TV cerró la app sola.
- [ ] Probar el QR con **un iPhone y un Android** si los hay: escanear, unirse, bloquear la pantalla 10 s en medio de un juego y volver (tiene que volver solo).
- [ ] Ver si aparece el **protector de pantalla** de Google TV con la app abierta 15 minutos sin tocar el control remoto. Si aparece: Configuración → Sistema → Energía y luz (o *Protector de pantalla*) → más largo o apagado.

### 7.2 Antes de empezar (viernes, 10 minutos)

- [ ] **Misma Wi-Fi** en la TV y en todos los celulares, la **principal** (no la de invitados: suele tener "aislamiento de clientes" y el QR no abre). Si el router separa 2,4 y 5 GHz con nombres distintos, todos en la misma. Pasarles la clave de la Wi-Fi antes del QR.
- [ ] **Firewall:** sin PC no hay nada que abrir. Solo el router: sin "aislamiento AP/de clientes".
- [ ] **Abrir la app en la TV y dejarla en el lobby** mientras se unen: si el jueves se jugó la competencia de prueba, las mascotas ya están en el disco y en ~1 s están todas en 3D; las que sean nuevas (otro color o mascota) se hornean ahí.
- [ ] **Sonido:** volumen de la TV a mitad; música y efectos se ajustan desde la pausa (Atrás → "Sonido" y los volúmenes). En los celulares, el sonido del control web se prende en su pantalla; en iPhone no vibra.
- [ ] **Batería:** celulares con más del 50 % (el control deja la pantalla prendida) y un cargador a mano.
- [ ] **Tener a mano la dirección corta** que muestra el lobby debajo del QR (ej. `192.168.1.34:47770`) por si a alguien no le lee el QR: se escribe en el navegador.
- [ ] Contarles **tres cosas**: se escanea el QR y se pone un apodo; para irse se **mantiene** apretado "Salir"; si se cierra la página sin querer, volver a escanear el QR (vuelve a su lugar con sus puntos si pasaron menos de 30 s).

### 7.3 Orden sugerido (~20 minutos, 2–3 personas)

En el lobby, cada juego se marca o desmarca con OK. Con "Orden: lista" se juegan en el orden de la lista. Cada juego suma ~6 s de intro (1,5 s si todos tocaron "¡Listo!") y ~12 s de resumen (se puede pasar con OK). Una competencia de 8 juegos con 2–3 personas dura **8–10 min** (§8.3).

**Competencia 1, para aprender (~9 min), Ayudas: No:** Arena de estrellas → *Ping Pong (solo si son 2)* → Carrera de toques → Reloj exacto → Esquivar → Pintar el piso → Empujones → Karts de mascotas → Desenfunde. Arranca con joystick libre (Arena) y un botón (Carrera de toques), y deja un juego largo (Karts) cerca del final. Termina con un duelo corto.

**Competencia 2, la revancha (~10 min), Ayudas: Sí:** Esquivar → Empujones → ¡Que no te deje la cámara! → Memoria de colores → Pool loco → Carrera de obstáculos. Las ayudas de los eliminados están en Esquivar (escudo) y Empujones (salvavidas): el que queda afuera elige con el joystick a quién ayudar y paga 10 puntos.

Con 2 personas, en la competencia 2 se puede sumar **1 bot Normal** (lobby: OK sobre un lugar libre); Ping Pong se saltea solo con 3 o más. Con 3 personas, sin bots.

### 7.4 Si algo sale mal

| Pasa | Qué hacer |
|---|---|
| El QR no abre la página | Misma Wi-Fi (no la de invitados); escribir la dirección corta del lobby en el navegador |
| "¡La sala está llena!" | En la TV, subir "¿Cuántos juegan?" (si hay bots, la persona reemplaza a uno sola). Con la página abierta, el celular entra solo apenas hay lugar |
| "Están en medio de una partida" | Dejar la página abierta: entra solo al volver la TV al lobby (después del podio) |
| Se le cerró la página o la app | Volver a escanear el QR (o abrir la app y entrar con el **mismo apodo**) **antes de 30 s**: vuelve a su lugar con sus puntos |
| Un celular se bloqueó | La TV muestra "no responde — su lugar lo espera" a los 4 s y su mascota queda quieta; al desbloquear vuelve solo |
| El celular dice "Abriste el control en otra pestaña" | Escaneó el QR dos veces: seguir en la pestaña nueva, o tocar ¡Unirme! en esta |
| Un juego no se entiende o se traba | Atrás (pausa) → "Saltar este juego"; anotarlo |
| Hay que cortar | Atrás → "Salir de la competencia" → "Sí, salir" → podio con lo jugado |
| La app de la TV se cerró | Abrirla de nuevo (Configuración → Apps si no está en la fila); la competencia se pierde. Los celulares dicen "No encontramos el juego en la TV" y, cuando vuelve, "la TV se reinició: escaneá otra vez el QR" (el apodo queda guardado) |

### 7.5 Qué observar y anotar

- **Unirse:** cuánto tardan desde que ven el QR, si la cámara lo leyó a la primera, quién tuvo que escribir la dirección, iPhone o Android.
- **Intro de cada juego:** ¿la leen? ¿alcanza con el texto, el dibujo del control y la línea del celular? ¿Quién pregunta "¿qué hago?"?
- **Durante el juego:** demoras ("apreté y no respondió"), tirones de imagen, mascotas que se ven planas (2D), cortes de conexión.
- **Quién gana:** ¿siempre el mismo? ¿algún juego que nadie gana o que se decide por azar?
- **Ganas:** risas, quejas, "¡otra!", aburrimiento; si 20 min fue poco o mucho.
- **Técnico:** ¿se calienta el stick? batería de los celulares al final; ¿la TV cerró la app sola?

### 7.6 Planilla (ver también §8.4, qué mirar de la claridad)

Fecha: ____  Personas: ____  Celulares (marca/modelo, ¿web o app?): ________________  Wi-Fi: ________

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


## 8. Claridad por juego (revisión del 04/10 para primerizos)

Pregunta: ¿alguien que nunca vio el juego entiende **en 5 segundos** qué hacer y cuál es su mascota, y es divertido de a 2–3? Se revisó cada juego con capturas reales (`tools/capture_screens.gd` con xvfb: la intro de la TV, el celular y el primer segundo de juego), con bots (`tools/simulate.gd --players=2`) y con celulares por la red (`tools/playtest.gd --scenario=room --humans=2` y `--humans=3`).

**Lo que ve un primerizo, en orden:** (1) la intro "¿Cómo se juega?": título, hasta 3 pasos sacados de la descripción (uno por oración), la foto del juego con el celular y el control dibujado, y su tarjeta que pasa a "¡Listo!" al tocar el celular; (2) en el celular, el control del juego con **una instrucción arriba** (`hint`); (3) al arrancar, la cuenta "3, 2, 1, ¡YA!" y, nuevo, una **flecha grande de su color con su nombre** que rebota sobre su mascota los primeros 3,6 s (`MiniGame.draw_start_markers`).

### 8.1 Qué se cambió en general

- **Instrucción propia por juego en el celular.** Todos los juegos con joystick mostraban la misma frase ("Mové tu mascota con el joystick"), que en Karts, Pool loco o Memoria no dice nada. Ahora cada juego manda su `hint` (≤ 48 caracteres, ya previsto en [PROTOCOL.md](PROTOCOL.md): sin cambio de protocolo ni de `web/`). Test: `test_game_texts_for_first_timers`.
- **Flecha "¿cuál soy yo?"** al empezar, en los 8 juegos de cancha compartida (Arena, Esquivar, Pintar, Empujones, Pool, Desenfunde, Memoria y la cámara). Si la mascota está pegada al marcador, la flecha va debajo de los pies apuntando hacia arriba. No va en los de carriles apilados (Carrera de toques, Carrera de obstáculos: ya tienen el cartel [1P | nombre] en el carril), en Karts (salen pegados y los nombres se pisarían), en Reloj exacto (panel con nombre) ni en Ping Pong (cada uno su lado). Barata: dos textos por jugador durante 3,6 s, nada después.
- **Arena de estrellas tiene cuenta regresiva** (3, 2, 1, ¡YA!) como los demás: era el único que arrancaba moviéndose y es el primer juego sugerido; sin la cuenta nadie encontraba su mascota antes de perder 3 segundos de juego.
- **Descripciones**: la primera oración es siempre el verbo de lo que hay que hacer; máximo 3 oraciones (la intro no muestra más: en Carrera de obstáculos "¡Primero en la meta gana!" era la 4.ª y no se veía).
- **Resumen de ronda: 12 s** en vez de 15 (el revelado con 2–3 personas dura ~2 s; OK siempre adelanta).
- **Lobby**: el botón grande decía "Esperando 1 jugador…" si "¿Cuántos juegan?" quedaba más alto que la gente que vino; ahora dice "Falta 1 jugador · o bajá la cantidad".

### 8.2 Tabla

| Juego | Objetivo en una frase | Control | Problema detectado | Cambio hecho |
|---|---|---|---|---|
| Arena de estrellas | Juntar más estrellas que los demás en 30 s | Joystick | Arrancaba moviéndose, sin "3, 2, 1"; mascotas chicas en las esquinas: primeros segundos para encontrarse | Cuenta regresiva de 3 s; flecha con el nombre; celular: "Movete y juntá las estrellas" |
| Ping Pong | Primero a 5 puntos | Deslizar | Claro (la paleta sigue el dedo). Nombres a un costado de la mesa, no sobre la paleta | Celular: "Deslizá el dedo: tu paleta lo sigue" |
| Carrera de toques | Llegar primero a 40 toques | Un botón "¡TOCÁ!" | Claro (cartel [1P | nombre] en cada carril). Lo único que confunde: tocar antes del ¡YA! no cuenta | Intro: "Después del ¡YA!, tocá…"; celular igual |
| Reloj exacto | Frenar en 10.00 contando de memoria | Un botón "¡STOP!" | Claro (panel con nombre por jugador). La intro no decía que se frena tocando | Intro: "Tocá para frenar tu reloj…"; celular: "Tocá cuando tu reloj llegue a 10.00" |
| Esquivar | Último en pie bajo los bloques | Joystick | Claro; las sombras avisan | Celular: "Movete: salí de las sombras"; flecha con el nombre |
| Pintar el piso | Pintar más baldosas | Joystick | Claro | Celular: "Caminá para pintar las baldosas"; flecha |
| Empujones | Último arriba de la isla | Joystick | Claro. De a 2 puede durar 5 s o 65 s (es el juego: se anota) | Celular: "Embestí para tirarlos de la isla"; flecha |
| Karts de mascotas | Primero en 3 vueltas | Joystick (solo dobla) | "El kart acelera solo, vos doblás" se entiende, pero el celular decía "Mové tu mascota". Los karts salen pegados: con la cuenta regresiva encima, 1P y 3P quedan medio tapados 3 s | Intro: "Tu kart acelera solo: con el joystick doblás…"; celular: "Solo doblá: izquierda y derecha" (sin flecha: se pisarían los nombres) |
| ¡Que no te deje la cámara! | Correr a la derecha sin que la cámara te deje ni chocar nada | Joystick | **La intro empezaba por la cámara, no por "corré"; quien no se movía quedaba afuera a los ~2 s (salía a 300 px del borde), y de a 2 el juego terminaba en 5 s. Sin bot: el bot base no corría** | Intro empieza "Corré hacia la derecha…"; celular: "¡Corré a la derecha! La cámara no espera"; salida 260 px más adentro; **gracia** de 3 s (4 jug.), 4 s (3) y 5 s (2) con la cámara desde 45 px/s; crucero inicial 112/126/140 px/s según sean 2/3/4; cartel "¡Corré a la derecha!" con flechas durante la gracia; **bot nuevo** (`host/bots/scroller_bot.gd`). Tests: `test_scroller_start_grace`, `test_bot_skill` |
| Memoria de colores | Repetir la secuencia; gana quien llega más lejos | Joystick (4 direcciones) | La intro listaba las 4 figuras (largo); el tablero ya las muestra con flechas | Intro más corta ("cada dirección es una figura"); celular: "Mirá la TV y repetí: una dirección por figura"; flecha |
| Desenfunde | Tocar primero después del ¡YA! | Un botón "¡PUM!" | Claro ("Preparados…" en el cartel); el engaño es parte de la gracia | Celular: "Tocá solo cuando la TV diga ¡YA!"; flecha |
| Pool loco | Meter doradas (3) o la de otro (2) | Joystick: estirar y soltar | Claro; la TV ya muestra la instrucción arriba de la mesa | Celular: "Estirá para apuntar, soltá para tirar"; flecha |
| Carrera de obstáculos | Primero en la meta saltando | Un botón "¡SALTÁ!" | La 4.ª oración ("¡Primero en la meta gana!") no se veía en la intro | Descripción en 3 oraciones; celular: "Tocá para saltar; mantené: más alto" (cartel [1P | nombre] en el carril, sin flecha) |

### 8.3 Duración y ritmo con 2–3 personas

Medido con `tools/playtest.gd --scenario=room` (celulares por la red; el resumen se deja correr solo): ver las duraciones por juego en §4. Con los tiempos nuevos, una competencia de 8 juegos suma ~5–6 min de juego + 8 × (~6 s de intro + ~1 s de barrido + ~12 s de resumen) ≈ **8–10 min**; las dos competencias sugeridas en §7.3 entran en ~20 min. Con 2 personas el bot ya corre en ¡Que no te deje la cámara! (antes: 2 bots, 5 s y 0 m; ahora 2 bots "Normal" duran 11–50 s, media ~25 s, y 60 m; 3 bots, media 35 s). Con celulares por la red (`--scenario=room --games=scroller,arena`): 2 personas, cámara 11,2 s y Arena 34,6 s; 3 personas, cámara 17,3 s; sin problemas ni errores del motor.

### 8.4 Qué mirar el viernes sobre la claridad

- ¿Alguien preguntó "¿cuál soy yo?" después de la flecha con el nombre? ¿La vieron?
- ¿Leen la instrucción del celular o solo miran la TV? (si nadie la lee, la próxima vez va más grande o se saca).
- En ¡Que no te deje la cámara!: ¿a los 5 s de gracia todos corren? ¿Alguien quedó afuera por no entender igual?
- ¿El resumen de 12 s se hace largo o corto? ¿Quién aprieta OK?
