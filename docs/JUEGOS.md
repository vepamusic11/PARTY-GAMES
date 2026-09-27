# Catálogo de juegos: actuales y propuestos

Qué juegos hay, cuáles conviene sumar y cómo encajan en lo que ya existe. Complementa la Fase C de [PLAN.md](PLAN.md). Para hacer uno: [ADDING_A_MINIGAME.md](ADDING_A_MINIGAME.md) y la skill `nuevo-minijuego`.

Más abajo: qué hace divertidos a los party games de referencia, **modos de juego** (detalle en [MODOS.md](MODOS.md)), **20 ideas nuevas** por emoción, **retención** y el **roadmap de contenido** de las próximas 3 versiones.

**Regla de oro:** cada juego nuevo tiene que sumar algo distinto, ya sea un control, una dinámica o una emoción. Un juego que se parece mucho a otro ocupa lugar en el lobby sin aportar.

## Los de hoy
## Los 8 de hoy

| Juego | Dinámica | Control | Jugadores |
|---|---|---|---|
| Arena de estrellas | Juntar estrellas | Joystick | 1–4 |
| Ping Pong | Devolver la pelota | Deslizar | 2 |
| Carrera de toques | Tocar lo más rápido posible | Un botón | 1–4 |
| Reloj exacto | Frenar el reloj justo a tiempo | Un botón | 1–4 |
| Esquivar | Evitar bloques que caen | Joystick | 1–4 |
| Pintar el piso | Pintar más territorio que los demás | Joystick | 1–4 |
| Empujones | Tirar a los otros de la isla | Joystick | 2–4 |
| Karts de mascotas | Carrera de 3 vueltas vista desde arriba | Joystick | 1–4 |
| ¡Que no te deje la cámara! *(hecho)* | La cámara avanza sola y acelera por un recorrido de bloques, sierras, molinetes, pozos y flechas de impulso; el que se queda atrás o choca algo mortal va a la tribuna. Último en pie gana; a los 75 s ganan los que siguen, por metros. Tramos prediseñados combinados con semilla (el mismo recorrido para todos) | Joystick | 2–4 |
| Memoria de colores | Repetir la secuencia del tablero de Simón; quien se equivoca queda afuera | Joystick (cada dirección es un botón) | 1–4 |

Los 7 tienen **bot** (Fácil / Normal / Difícil) para jugar solo o completar la mesa: ver [ADR 0010](adr/0010-bots.md).

## Balance con bots

**Concepto: *simulación de balance*.** Se juegan cientos de competencias bot contra bot sin pantalla y se mira si algún juego dura demasiado, si los puntajes tienen sentido o si un lugar de salida gana más que los otros. Con bots iguales, cada lugar debería ganar ≈ 100 % / jugadores.

```bash
godot --headless --path . -s res://tools/simulate.gd -- --n=50 --difficulty=normal   # 4 bots iguales
godot --headless --path . -s res://tools/simulate.gd -- --n=50 --players=2           # con Ping Pong
godot --headless --path . -s res://tools/simulate.gd -- --n=50 --difficulty=mixed    # fácil/normal/difícil/normal
```

Resultados (50 competencias de 4 bots "Normal"; Ping Pong con 2):

| Juego | Duración media (p95) | Puntaje medio (mín–máx) | % victorias 1P / 2P / 3P / 4P |
|---|---|---|---|
| Arena de estrellas | 30 s (30) | 32 estrellas (21–48) | 34 / 21 / 21 / 24 |
| Ping Pong (2 bots) | 60 s (77) | 3,9 puntos (1–5) | 50 / 50 |
| Carrera de toques | 7,7 s (8,0) | 38 toques (33–40) | 24 / 28 / 30 / 18 |
| Reloj exacto | 15,3 s (15,6) | 825 de precisión (283–1000) | 28 / 24 / 23 / 25 |
| Esquivar | 36 s (45) | 27 segundos (4–45) | 30 / 25 / 30 / 15 |
| Pintar el piso | 49,5 s (49,5) | 52 baldosas (11–149) | 21 / 18 / 34 / 27 |
| Empujones | 54 s (64) | 32 puntos (2–70) | 21 / 27 / 28 / 24 |

Lo que dicen los números:
- **Arena daba ventaja a 1P** (encontrado con esta simulación): si dos mascotas tocaban la misma estrella en el mismo paso, siempre se la llevaba el primero de la lista. Entre bots "Difícil", 1P ganaba ~50 % y 4P ~8 %. Ahora el orden es al azar en cada paso y quedó parejo (25 / 21 / 33 / 22 con 4 difíciles).
- **Ningún lugar de salida da ventaja clara** en los demás juegos: las diferencias (ej. 3P en Pintar) cambian de una corrida a otra y con 80 partidas de Pintar quedan 21 / 14 / 21 / 24.
- **La dificultad se nota**: con fácil / normal / difícil / normal, el difícil gana las 50 competencias y el fácil sale último en 47. El juego con más azar es Reloj exacto (el difícil gana el 51 %).
- **Empujones 1 contra 1** entre bots parejos casi siempre termina por tiempo con los dos arriba (empate): a vigilar con personas, quizás la isla tendría que achicarse más al final.
- **Carrera de toques es el más corto** (≈ 8 s con la cuenta regresiva): con bots dura lo mismo que con gente rápida.
| Pool loco | Meter bolas doradas (o la de otro) en las troneras, todos a la vez | Joystick: apuntar y soltar | 2–4 |

## Propuestos

### Carreras

**Concepto: *carrera con vista desde arriba* (top-down).** La cámara mira la pista desde arriba y cada mascota va en su autito. Así se ven los cuatro jugadores a la vez en una sola pantalla, sin dividirla.

*Ejemplo:* Pablo dobla con el joystick, agarra un turbo en la curva y le gana a Sofi en la última vuelta.

| Juego | Cómo se juega | Control | Qué suma | Dificultad |
|---|---|---|---|---|
| **Karts de mascotas** ✅ *hecho* (`host/minigames/karts/`) | Circuito de 3 vueltas con curvas, turbos y charcos resbalosos. El kart acelera solo: el jugador solo dobla. | Joystick (usa el eje X; abajo frena, arriba turbo suave) | La primera carrera de verdad: adelantar, cerrar al rival, la tensión de la última vuelta | Media: pista suavizada (Catmull-Rom, polilínea), vueltas y puestos |
| **Carrera de obstáculos** ✅ *hecho* (`host/minigames/hurdles/`) | Vista de costado, 4 carriles. Se salta con el botón para esquivar vallas y pozos, y tropezar frena un segundo. | Un botón | Timing puro; se aprende en 5 segundos | Baja |
| **Derrape** | Mini circuito ovalado. Mantener apretado derrapa: más derrape da más turbo, pero con riesgo de salirse. | Un botón | Riesgo contra recompensa con un solo botón | Media |

**Cuidados en las carreras:**
- **Nadie debe quedar "fuera de carrera".** Técnica de *rubber banding* (goma elástica): el que viene último recibe un turbo un poco más fuerte. *Ejemplo:* si Tomi va 2 vueltas atrás, sus turbos duran 20 % más. Tiene que ser sutil, que no se note como trampa.
- **Cámara:** la pista entra entera en la pantalla. No hay pantalla dividida, porque en una TV a 3 metros cuatro pantallas chicas no se leen.
- **Latencia:** doblar con 60 ms de demora se siente bien si el auto tiene algo de inercia. Con giros bruscos se sentiría "pesado".

**Cómo quedó Karts de mascotas** (`host/minigames/karts/karts.gd`):
- **Pista:** 16 puntos de control suavizados (Catmull-Rom) en una polilínea con un punto cada 12 px; el punto 0 es la línea de largada. Cada kart busca su tramo más cercano cerca del anterior (no se teletransporta) y suma lo que avanzó: cruzar la línea marcha atrás resta, no cuenta vuelta. Los bordes de bloques son paredes blanditas: frenan (×0,6), rebotan poco y enderezan el kart, así nadie queda trabado.
- **Manejo:** acelera solo hasta 380 px/s; el eje X dobla con inercia de volante (τ ≈ 90 ms); abajo frena (hasta 40 %) y dobla más cerrado; arriba da +8 % pero en diagonal se dobla menos. Derrape: la velocidad de costado se la come el agarre (9/s; en un charco, 1/s durante 1 s).
- **Turbos** ×1,55 durante 1,1 s; **goma elástica:** el último, 1,32 s (20 % más). **Choques** suaves entre karts (rebote 0,45).
- **Fin:** cuando llegan todos, a los 90 s o 15 s después del primero. Puntaje "vueltas": los que llegaron, 3 + centésimas por orden de llegada; los demás, las vueltas recorridas.
- **Física determinista:** pasos fijos de 1/60 s (`advance` acumula el delta real); mismo control, mismo resultado a 30, 60 o 144 fps (lo verifica `test_karts_deterministic`).

### Estilo pool

**Concepto: *física de choques entre círculos*.** Cada bola es un círculo con velocidad. Cuando dos bolas se tocan, rebotan e intercambian velocidad según el ángulo del golpe. Conviene programarla a mano con pasos fijos (*física determinista*), en lugar de usar el motor de física de Godot. Así la misma jugada da siempre el mismo resultado y se puede testear.

*Ejemplo:* la bola de Juli pega de costado en una bola dorada, la dorada sale en diagonal y cae en la tronera: Juli suma 3 puntos.

| Juego | Cómo se juega | Control | Qué suma | Dificultad |
|---|---|---|---|---|
| **Pool loco** *(hecho: `host/minigames/pool/`)* | Todos tiran **al mismo tiempo**, sin turnos. Cada mascota va arriba de su bola y la mesa tiene bolas doradas: meter una suma 3 puntos, y meter la bola de otro suma 2. Si tu bola cae, vuelve a los 1,5 s. Una ronda de 50 s. | Joystick para apuntar; al soltarlo se tira, y cuanto más lejos del centro, más fuerza | Puntería y caos. Sin turnos no hay espera, lo que es clave con 4 jugadores | Media: física de círculos, troneras, rondas |
| **Mini golf** | Hoyos cortos con rampas y molinos. Todos juegan a la vez con bolas que se atraviesan entre sí; gana el de menos golpes. | Joystick para apuntar y soltar para tirar (igual que Pool loco) | Planificar el tiro; comparte el código de física con Pool loco | Media |
| **Bochas / curling** | Dejar la bola lo más cerca posible del blanco, y también se puede sacar a las de los rivales. | Joystick + soltar | Estrategia tranquila, buen contraste con los juegos de reflejos | Baja-media |

**Por qué tirar a la vez y no por turnos:** en un pool clásico con 4 jugadores, cada uno espera 3 turnos sin hacer nada. En un party game, esperar es aburrirse. Si un modo por turnos resulta divertido, puede sumarse más adelante como variante para 2 jugadores.

**Control "apuntar y soltar":** se puede hacer con el joystick que ya existe, sin cambiar el protocolo.
- La TV recibe la dirección y el largo del joystick en cada `axis`.
- Cuando el valor vuelve a cero después de haber estado estirado, lo interpreta como "soltó".

Toda la lógica vive en la TV, que sigue siendo autoritativa: el celular solo manda el eje. Si más adelante se quiere una flecha de fuerza dibujada en el celular, eso sí sería un layout nuevo (ver la skill `nuevo-layout`).

### Otros que suman algo distinto

| Juego | Dinámica | Control | Qué suma |
|---|---|---|---|
| Papa caliente | Pasar la bomba antes de que explote | Un botón | Tensión y risas |
| Luz roja, luz verde | Avanzar solo con luz verde | Joystick | Autocontrol |
| Motos de luz | Estela que no se puede tocar, como el clásico "Tron" | Joystick | Encerrar al rival |
| Hockey de mesa | 1 contra 1 o 2 contra 2 | Deslizar | Primer juego por equipos con el control que ya existe |
| ~~Memoria de colores~~ **(hecho)** | Repetir la secuencia | Joystick: arriba, derecha, abajo e izquierda son los cuatro botones (sin layout nuevo) | Juego de cabeza |
| Equilibrio | Mantener la bandeja nivelada | Inclinación (layout nuevo) | Usa el celular como objeto físico |

### Clásicos arcade para 4 (Bomberman, Battle City y parecidos)

Juegos de sala de juegos y consolas que la gente ya conoce: se explican solos ("es como el Bomberman") y funcionan muy bien con 4 personas en un sillón. Varios usan el nuevo **joystick + A/B** ([ADR 0014](adr/0014-layout-joystick-ab.md)), que todavía no tiene juego. Son ideas propias *inspiradas* en el género: nombres, arte y niveles nuestros (nunca copiar nombres, sprites ni músicas de los originales).

| Juego | Inspirado en | Dinámica | Control | Cómo se ve cada jugador | Qué suma | Dificultad |
|---|---|---|---|---|---|---|
| **Bombas de mascotas** | Bomberman | Laberinto en grilla con bloques rompibles; A pone una bomba que explota en cruz; los bloques sueltan mejoras (más alcance, más bombas, patear con B). Último en pie o más puntos a los 90 s. *Ej.:* Juli encierra a Tomi entre dos bombas; Tomi patea una con B y se salva | Joystick + A/B (**primer uso**) | Mascota entera (se ve chica en la grilla) | Estrategia de encierro; el clásico más pedido para 4 | Media: grilla, explosiones en cruz, mejoras |
| **Tanquecitos** | Battle City / Tank | Tanques vistos desde arriba en un mapa con ladrillos que se rompen, acero que no, agua y arbustos que tapan. A dispara. Modo todos contra todos o **2 contra 2 cuidando la base** (la torta de cumpleaños de cada equipo). *Ej.:* Pablo y Sofi defienden su torta mientras Tomi rompe la pared de atrás | Joystick + A | **Tanque del color del jugador** con 1P–4P pintado en la torreta (no hace falta la mascota entera; como mucho, su cabeza asomando) | Primer juego de disparos y de equipos con base | Media |
| **Víboras** | Snake / "Achtung, die Kurve" | Cada víbora crece al comer frutas; chocar con cualquier cuerpo te elimina. Variante "Achtung": se dobla con el joystick y la estela queda con huecos | Joystick | **Solo el color** + patrón propio (rayas, puntos, rombos, lisa) y la etiqueta 1P–4P en la cabeza | Encerrar al rival; partidas de 30 s | Baja |
| **Come-come** | Pac-Man Vs. | Uno es el come-come y los otros tres son fantasmas que **solo ven cerca** (la TV oscurece lejos de ellos); si un fantasma lo atrapa, cambian los roles | Joystick | Come-come y fantasmas del color de cada uno + 1P–4P | 1 contra 3 asimétrico (como Mario Party) | Media |
| **Cruzá la calle** | Frogger / Crossy Road | Cruzar carriles de autos y troncos de un río; gana quien llega más lejos. Los empujones entre jugadores valen | Joystick (pasitos) | Mascota entera | Timing + caos; lo entiende un chico de 5 años | Baja |
| **Justas voladoras** | Joust | Se aletea con A para subir; gana el choque quien está más arriba | Joystick + A | Mascota entera sobre un pájaro de su color | Física de vuelo simple; muy gracioso | Media |
| **Golpe de abajo** | Mario Bros. (arcade 1983) | Plataformas: golpear el piso desde abajo da vuelta a los bichos y después se los empuja; también se puede dar vuelta al rival | Joystick + A (saltar) | Mascota entera | Cooperar y traicionar en la misma pantalla | Media |
| **Nave contra nave** | Spacewar! / Asteroids | Arena con gravedad hacia un sol central; A dispara, B turbo. Rocas que se parten | Joystick + A/B | **Nave del color del jugador** + 1P–4P | Inercia y puntería | Media |
| **Territorio** | Qix / Paper.io | Salir de tu zona dibuja una línea; al volver, lo encerrado es tuyo. Si te tocan la línea, perdés lo que estabas cerrando | Joystick | **Solo el color** + textura propia en el territorio y 1P–4P en el lápiz | Riesgo contra recompensa (parecido a Pintar el piso, pero con encierro) | Media |
| **Ladrillos en equipo** | Breakout / Arkanoid | Cada uno tiene su paleta en un lado de la pantalla y todos rompen el mismo muro; puntos por ladrillo y penalidad si se te escapa la pelota | Deslizar | **Paleta del color del jugador** + 1P–4P | Usa el deslizar de Ping Pong con 4 | Baja |
| **Bloques que caen** | Tetris 99 / Puyo | Cada uno arma su pozo; limpiar líneas le manda basura a otro | Joystick + A (girar) | Pozo con borde del color + mascota chica mirando | Juego de cabeza competitivo | Alta (necesita buen control del giro por red) |
| **Hockey de aire** | Air hockey | 1 contra 1 o 2 contra 2 con disco y arcos | Deslizar o joystick | Mazo del color + 1P–4P | Primer juego por equipos (ya estaba como "Hockey de mesa") | Baja-media |

**Orden sugerido dentro de este grupo:** Bombas de mascotas (estrena el joystick + A/B y es el más pedido), Tanquecitos (equipos 2 contra 2), Víboras (barata, 1 día) y Come-come (asimétrico).

### Cómo se ve cada jugador: no siempre hace falta la mascota entera

Según el juego alcanza con **el color del jugador** en lo que controla (un tanque, una víbora, una paleta, un territorio). Dibujar la mascota entera no siempre suma: en una grilla chica no se lee, y cuesta más por cuadro. Hay tres niveles:

| Nivel | Cuándo | Ejemplos |
|---|---|---|
| **Mascota entera** | El personaje camina, salta o se cae y eso es parte de la gracia | Arena, Empujones, Carrera de obstáculos, Bombas de mascotas |
| **Objeto del color + cabeza de la mascota** | El jugador maneja algo (vehículo, bola) y la mascota va arriba o asomando | Karts, Pool loco, Tanquecitos |
| **Solo el color** | El jugador es una estela, una paleta o un territorio | Víboras, Territorio, Ladrillos en equipo, Ping Pong |

**Regla que no cambia (accesibilidad):** el color **solo** nunca alcanza, porque 1 de cada 12 hombres distingue mal algunos colores (por ejemplo, el rojo del verde). Siempre va la etiqueta **1P–4P** sobre lo que controla el jugador, y cuando no hay mascota, una **forma o patrón propio** (rayas, puntos, rombos, lisa). *Ej.:* en Víboras, la víbora roja de Pablo lleva "1P" en la cabeza y rayas; la verde de Sofi lleva "2P" y puntos. Así se distinguen aunque se vean del mismo tono. El marcador de arriba sigue mostrando la cabeza de la mascota de cada uno, así todos saben quién es quién.

## Orden recomendado

1. **Pool loco** *(hecho)*: no necesitó un layout nuevo y su física (`host/minigames/pool/pool_physics.gd`) se puede reutilizar en Mini golf y Bochas.
2. **Karts de mascotas** *(hecho)*: es la carrera que la gente espera en un party game y usa el joystick que ya existe.
3. **Carrera de obstáculos** *(hecho, `host/minigames/hurdles/`)*: barata y muy clara para jugadores nuevos. Cada carril tiene su propio scroll lateral (la mascota queda fija y el recorrido pasa) y un riel con la meta; todos corren la misma secuencia de vallas, pozos, escalones y plataformas, generada con una semilla. Tocar salta, mantener salta un poco más alto (con límite); tropezar frena 1 s. Gana el primero en la meta o, a los 60 s, el que llegó más lejos. Física con pasos fijos de 1/60 s: la misma semilla y las mismas entradas dan la misma carrera (tests `test_hurdles_*`).
4. **Hockey de mesa:** primer juego por equipos.
5. Después, los que necesitan layouts nuevos (Equilibrio), sumados juntos en una sola versión del protocolo. Memoria de colores ya está hecha con el joystick (cada dirección es un botón), sin cambiar el protocolo.

Cada juego nuevo tiene que cumplir la definición de "terminado" de [PLAN.md](PLAN.md): tests, capturas revisadas, rendimiento dentro del presupuesto y su miniatura para el lobby.

---

## Qué hace divertido a un party game

Investigación del 27/09/2026 sobre las referencias que el público ya conoce. Las fuentes se consultaron por buscador; como las páginas no se pudieron abrir directamente, van marcadas *(indirecto)*, igual que en [RECURSOS.md](RECURSOS.md). Lista completa al final, en "Fuentes".

| Referencia | Qué la hace divertida | Qué tomamos | Ejemplo en nuestro juego |
|---|---|---|---|
| **Mario Party** | Tablero con dados y un minijuego por turno; tipos fijos de minijuego (4 jugadores, 1 contra 3, 2 contra 2, duelo); estrellas bonus al final | Economía monedas → estrellas; minijuegos 1 contra 3 y 2 contra 2; duelos | Modo Tablero; con 3 jugadores, un 1 contra 2 donde el que va solo es más rápido |
| **Jackbox** | El celular es el control y **la pantalla privada**: se escribe, dibuja o vota en secreto. Pocos tipos de control, así se aprende uno y se saben todos. Público de hasta 10.000 personas | Juegos con información oculta; votar; público | Tres puertas (cada uno elige en secreto en su celular); modo espectador |
| **Trivia Murder Party** (Jackbox) | Perder una pregunta te manda a un minijuego de vida o muerte; los muertos siguen jugando como fantasmas | Eliminación sin quedarse afuera | Torneo por eliminación con fantasmas |
| **Fall Guys** | Rondas de 2–3 minutos; caerse es gracioso, no frustrante; mezcla carrera, supervivencia, equipos y memoria | Rondas cortas; el fracaso como chiste; variedad de tipos | La mascota que cae en Empujones hace "splash" y sale mojada, no "GAME OVER" |
| **Overcooked** | Cooperativo con roles imprescindibles, presión de tiempo y gritos; la comunicación es el juego | Cooperativo contra la TV | La torta gigante: solo se mueve si los cuatro tiran para el mismo lado |
| **Ultimate Chicken Horse** | Cada uno pone una trampa y después todos corren. **Si todos llegan o nadie llega, no hay puntos**: hay que hacer el nivel difícil, pero no imposible | Construir y competir; puntaje que castiga los extremos | Trampas para todos |
| **Pummel Party** | Tablero con ítems absurdos (un guante, una berenjena a control remoto) y minijuegos de caos | Ítems graciosos en la versión 2 del tablero | Guante que le roba una moneda a quien tengas al lado |
| **WarioWare** | Microjuegos de ~4 segundos que se aceleran con cada acierto; un tablero corto donde el liderazgo cambia de mano | Variantes que aceleran; partidas cortas | Variante "turbo" de cualquier juego; Desenfunde dura 5 segundos por ronda |
| **Kirby Air Riders** | *Top Ride*: carrera vista desde arriba en pistas que entran enteras en la pantalla, sin pantalla dividida. *City Trial*: 5 minutos juntando mejoras y después una prueba en el estadio | Confirma la cámara de Karts de mascotas; "preparación + prueba" | Variante de Arena: las estrellas juntadas dan velocidad para una carrera final de 20 s |
| **BombSquad** | Bombas, física y explosiones que empujan a todos; hockey, capturar la bandera y una variante en cámara lenta ("Epic") | Caos físico con reglas simples; cámara lenta en el momento clave | Bombas saltarinas; la última explosión se ve en cámara lenta |
| **Nintendo Switch Sports** | Colecciones de ropa nueva cada semana, siempre cosméticas; liga con rangos | Progresión solo cosmética | Stickers que desbloquean gorros y patrones para la mascota |

**Cinco lecciones que guían todo lo que sigue:**
1. **Cero espera.** Todos juegan a la vez, siempre. *Ejemplo:* en el Tablero los cuatro tiran el dado juntos; nadie mira tres turnos ajenos.
2. **Se entiende en 5 segundos.** Un verbo por juego ("tocá", "esquivá", "tirá"). *Ejemplo:* Desenfunde se explica con una palabra: "¡Ya!".
3. **Perder es gracioso.** La animación del que pierde tiene que hacer reír. *Ejemplo:* en Sillas musicales, la mascota que se queda sin silla se sienta en el piso con cara de ofendida.
4. **Nadie "ya perdió".** Alcance sutil, rondas que valen más al final, fantasmas que siguen jugando. *Ejemplo:* Gran final ×2 en Partida rápida.
5. **El celular es más que un joystick.** Es una pantalla privada: se puede elegir, votar o dibujar en secreto. *Ejemplo:* en Tres puertas nadie sabe qué puerta eligió Pablo hasta que la TV las abre.

## Modos de juego

Hoy hay un solo modo: **Competencia** (una ronda de N juegos con puntos 100 / 70 / 50 / 30 por puesto, [ADR 0003](adr/0003-modo-competencia.md)). Los modos nuevos cambian *cómo se encadenan y cuentan* los juegos, sin tocar los juegos en sí. Detalle de cada uno (cómo se juega, cambios de arquitectura, riesgo y ejemplo completo): **[MODOS.md](MODOS.md)**.

**Concepto: *modo* vs. *juego*.** El juego es la cancha; el modo es el campeonato. *Ejemplo:* Pintar el piso en Competencia da 100 al que más pinta; en Equipos se pinta con dos patrones y ganan dos; en el Tablero da 10 monedas.

| Modo | Cómo se juega (una línea) | Arquitectura | Protocolo | Esfuerzo | Riesgo |
|---|---|---|---|---|---|
| **Partida rápida + Gran final** | 3 juegos elegidos con variedad; el último vale doble | `QuickMode` sobre `Tournament` | No | S | Bajo |
| **Bots** | "Agregar bot" fácil/normal/difícil; reemplaza a quien se desconecta | Script de bot por juego + `BotDriver` | No | L | Medio |
| **Equipos 2 vs 2** | Sol contra Luna; juegos propios de equipo o de suma | `TeamMode`; `teams` en `get_info()` | Opcional | L | Medio |
| **Cooperativo contra la TV** | 4 desafíos contra la Nube Gruñona con 3 corazones compartidos; medalla | `CoopMode`; `coop_score` en el resultado | No | M-L | Medio |
| **Handicap ("Ayuda")** | La TV le da ayuda visible a un jugador (ej. estrellas desde más lejos) | `assist` en cada jugador | No | M | Bajo-medio |
| **Eliminación con fantasmas** | Sale el último de cada juego y sigue como fantasma; final 1 contra 1 | `EliminationMode`; `ghost` en cada jugador | No | M-L | Medio |
| **Fiesta infinita** | Juegos sin fin, se entra y sale entre juegos, corona de los últimos 5 | `EndlessMode`; cola en `HostServer` | No (cola con `wait`) | M | Medio |
| **Desafío del día** | Un juego con una variante y una meta, igual en todas las TVs por la fecha | Semilla por fecha; `modifiers` | No | M | Bajo |
| **Espectador** | Del 5° en adelante: alentar y votar qué juego sigue | Público separado de `MAX_PLAYERS` | **Sí** (ADR) | M-L | Medio |
| **Tablero de la fiesta** | Dados simultáneos, casillas, monedas y estrellas; 10 turnos | `BoardMode` + `BoardScreen` | No | XL | Alto |

Base común para todos: un contrato `GameMode` del que `Tournament` pasa a ser un caso más (ADR 0013 propuesto en [MODOS.md](MODOS.md#base-común-modos-como-estrategia)).

## Más ideas

Veinte juegos nuevos (distintos de los de arriba), agrupados por la **emoción** que buscan. Cada uno cumple la regla de oro: suma algo que no tiene otro. "Dificultad" es de programación.

**Controles que aparecen en esta sección:**

| Control | ¿Existe? | Qué habilita | Protocolo |
|---|---|---|---|
| Joystick, deslizar, un botón | Sí | La mayoría de las ideas | — |
| **Apuntar y soltar** con el joystick | Sí (interpretación en la TV, ver "Estilo pool") | Catapulta, Topos | — |
| **Cuatro botones** (`four_buttons`) | No (Memoria de colores se resolvió con las 4 direcciones del joystick) | Trivia, ¿Quién es más probable?, respuestas en general | Sí: bits C y D en `btn`, `VERSION` 2 |
| **Joystick + A y B** (`joystick_ab`, reemplaza a la idea `stick_button`) | Sí ([ADR 0014](adr/0014-layout-joystick-ab.md)); todavía sin juego | Globos; también patear en Fútbol, saltar y tirar bombas | Sí: `VERSION` 2 |
| **Dibujar** (`draw`) | No | Dibujá y adiviná | Sí: mensaje de trazos (en tramos, por el límite de 512 bytes) + ADR |
| **Teclado** (`text`) | No | Tutti frutti | Sí: mensaje de texto corto + ADR |

Como dice la Fase C de [PLAN.md](PLAN.md), los layouts nuevos se suman **juntos en una sola versión del protocolo** (skill `nuevo-layout`).

### Reflejos

| Juego | Dinámica (con ejemplo) | Control | Jugadores | Qué suma | Dificultad | Reutiliza |
|---|---|---|---|---|---|---|
| **Desenfunde** *(hecho: `host/minigames/quickdraw/`; la TV mide cada toque con su reloj, ver "Justicia de red" en el script)* | Duelo del Oeste: las mascotas se miran de espaldas y hay que tocar apenas la TV dice "¡YA!". Quien toca antes de tiempo pierde la ronda. La TV engaña: "¡YA… mate!". *Ej.:* Sofi (Conejo) toca en 0,21 s; Pablo se adelantó con "¡YA… mate!" y su Oso se cae sentado | Un botón | 1–4 | Reacción a un momento **desconocido** (Reloj exacto es a un momento conocido); el engaño da risa | Baja | Visor y cronómetro de Reloj exacto |
| **Topos** | Cada jugador tiene 4 pozos en su esquina (arriba, abajo, izquierda, derecha); sale un topo y hay que mover el joystick hacia ese pozo. El topo con casco no se toca. *Ej.:* a Tomi le sale el topo dorado a la izquierda: +3 | Joystick (movimiento corto y soltar) | 1–4 | Reflejos de **dirección**, no de un solo botón | Baja-media | Detección de "soltar" del joystick (Pool loco) |

### Puntería y precisión

| Juego | Dinámica (con ejemplo) | Control | Jugadores | Qué suma | Dificultad | Reutiliza |
|---|---|---|---|---|---|---|
| **Grúa de bloques** | Una grúa va y viene sola sobre la torre de cada uno; se toca para soltar el bloque. Si queda torcido, la torre se tambalea y puede caerse. Gana la más alta a los 60 s. *Ej.:* la torre de Juli llega a 11 bloques pero se inclina; Pablo, más prudente, termina con 9 bien derechos y gana porque la de Juli se cae en el último segundo | Un botón | 1–4 | Precisión + riesgo (apurarse o esperar) | Media (apilado simple sin motor de física: cae si el centro de masa sale de la base) | — |
| **Catapulta** | Cada mascota tiene una catapulta y un castillo de cartón; se apunta y se suelta para tirar una bola en parábola y derribar los castillos ajenos. *Ej.:* Sofi estira el joystick hacia abajo a la izquierda, suelta, y la bola vuela sobre el castillo de Tomi y le baja la torre | Joystick (apuntar y soltar) | 2–4 | Puntería con **curva** (Pool loco es en línea recta) | Media | "Apuntar y soltar" de Pool loco; bloques de Grúa |
| **Globos** | Suben globos; se mueve la mira con el joystick y el botón revienta. Globo con tu patrón +1, dorado +3, nube de tormenta −2. *Ej.:* Pablo revienta el dorado justo antes que Juli | Joystick + botón (**nuevo**) | 1–4 | Primer juego de "mira y disparo" | Baja-media | — |

### Estrategia

| Juego | Dinámica (con ejemplo) | Control | Jugadores | Qué suma | Dificultad | Reutiliza |
|---|---|---|---|---|---|---|
| **Tres puertas** | Cada ronda hay 3 puertas: un tesoro de 6 monedas, uno de 2 y una trampa. Cada uno elige **en secreto en su celular**; si varios eligen el mismo tesoro, se lo reparten. Pistas en la TV ("la trampa no está a la izquierda"). *Ej.:* Pablo y Sofi van al tesoro grande y se llevan 3 cada uno; Tomi apuesta al de 2 y se lo lleva entero | Joystick (izquierda / arriba / derecha, con tiempo límite) | 2–4 | Primer juego de **información oculta**: leer a los demás. Casi no lleva física | Baja | — |
| **Trampas para todos** | Al estilo Ultimate Chicken Horse: (1) cada uno ubica una trampa en una pista de costado; (2) todos corren y saltan. Sumás si llegás y otros no; **si llegan todos o no llega nadie, nadie suma**. *Ej.:* Juli pone un resorte que ayuda a todos… salvo a quien lo pisa tarde | Joystick para ubicar, botón para saltar (**cambia de layout a mitad del juego**) | 2–4 | Construir el nivel y competir en él; el puntaje castiga los extremos | Alta (dos fases; `MiniGame` necesita poder pedir otro layout) | Carrera de obstáculos (vista de costado y salto) |

### Caos

| Juego | Dinámica (con ejemplo) | Control | Jugadores | Qué suma | Dificultad | Reutiliza |
|---|---|---|---|---|---|---|
| **Bombas saltarinas** | Al estilo BombSquad: caen bombas con mecha en una isla; caminar contra una la patea. Al explotar empujan a todos; el que cae al agua pierde una vida. La última explosión va en cámara lenta. *Ej.:* Tomi patea una bomba hacia Pablo, rebota en una piedra y vuelve: salen volando los dos | Joystick | 2–4 | Caos con **proyectiles**: la amenaza la crean los jugadores | Media | Física de empuje, isla y agua de Empujones |
| **Sillas musicales** | Suena música y las mascotas dan vueltas; cuando para, hay que sentarse. Una silla menos por ronda. *Ej.:* la música para de golpe; el Gato de Juli y el Conejo de Sofi llegan a la misma silla y gana la que llegó primero por 3 cm | Joystick | 3–4 | **La música es la mecánica**; todos lo conocen de la vida real | Baja-media | Movimiento de Arena; audio sintetizado ([ADR 0005](adr/0005-sonido-sintetizado.md)) |

### Cooperación

**Concepto: *interdependencia*.** Nadie puede ganar solo (ver Overcooked arriba). Estos juegos son la base del modo Cooperativo contra la TV; en Competencia se puntúan por aporte ("quién tapó más goteras").

| Juego | Dinámica (con ejemplo) | Control | Jugadores | Qué suma | Dificultad | Reutiliza |
|---|---|---|---|---|---|---|
| **La torta gigante** | Los cuatro tiran de una torta con cuerdas; la torta se mueve con **la suma** de los joysticks por un laberinto con charcos. Si tiran para lados opuestos, no se mueve. *Ej.:* Pablo tira para arriba, Sofi para la derecha: la torta va en diagonal y casi cae al charco; Tomi grita "¡todos a la derecha!" | Joystick | 2–4 (cooperativo) | Primer cooperativo; obliga a hablar | Baja | — |
| **Barco con goteras** | Aparecen goteras en la cubierta y se tapan parándose encima. Si todos se amontonan de un lado, el barco se inclina y las mascotas resbalan. *Ej.:* Juli corre a tapar una gotera a la izquierda y el barco se inclina; Pablo se va a la derecha para equilibrar | Joystick | 1–4 (cooperativo) | Equilibrio **entre personas**: cada movimiento afecta a todos | Media | Movimiento de Arena |
| **Pizzería de mascotas** | Estilo Overcooked simplificado: llegan pedidos, hay estaciones de masa, salsa, queso y horno; se agarra y se deja pasando por encima. *Ej.:* Sofi se queda en el horno, Tomi trae la masa y Pablo, el queso: sin repartirse los roles no llegan | Joystick (agarrar y soltar automáticos) | 2–4 (cooperativo) | Roles y organización | Alta | Movimiento de Arena |

### Memoria y atención

| Juego | Dinámica (con ejemplo) | Control | Jugadores | Qué suma | Dificultad | Reutiliza |
|---|---|---|---|---|---|---|
| **Contar ovejas** | Pasan ovejas blancas, ovejas negras y algún lobo disfrazado saltando un cerco. Pregunta: "¿Cuántas ovejas negras pasaron?". Se elige el número en una recta de 0 a 20 con el slider; gana quien más se acerca. *Ej.:* pasaron 7; Juli dice 7, Pablo 8 y Tomi 12 | Deslizar | 1–4 | Juego **tranquilo** de atención; el único uso del slider fuera de Ping Pong | Baja | Slider de Ping Pong |
| **¿Qué cambió?** | Se ve la escena de la fiesta 5 s, se apaga la luz y al volver algo cambió (el gorro del Oso, un globo menos). Se mueve el cursor y se queda quieto 1 s sobre la respuesta. *Ej.:* Sofi señala el globo que faltaba en 2 s | Joystick | 1–4 | Memoria visual (Memoria de colores es de secuencias) | Baja-media | Mascotas y escenario existentes |

### Ritmo y música

| Juego | Dinámica (con ejemplo) | Control | Jugadores | Qué suma | Dificultad | Reutiliza |
|---|---|---|---|---|---|---|
| **Banda de mascotas** | Cada mascota toca un instrumento (Oso bombo, Conejo pandereta, Robot teclado, Gato guitarra) y las notas llegan por su carril: se toca justo cuando pasan por la línea. Cada acierto suma su capa a la canción. *Ej.:* cuando Tomi falla, se deja de oír el teclado y todos se dan cuenta | Un botón | 1–4 | Ritmo; la música **se arma** con los aciertos | Media-alta: hay que **calibrar la latencia** (medir la demora de cada celular con el ping y correr la ventana de acierto) | Sintetizador y "música por capas" de [CALIDAD.md](CALIDAD.md) |

### Dibujo y creatividad

| Juego | Dinámica (con ejemplo) | Control | Jugadores | Qué suma | Dificultad | Reutiliza |
|---|---|---|---|---|---|---|
| **Calcar la figura** | La TV muestra una figura (estrella, casa, pez) y cada uno la traza en su cuadrante con el joystick como lápiz, al estilo de las pizarras mágicas. La TV mide el parecido. *Ej.:* el pez de Pablo parece un zapato, pero cierra bien la cola y saca 71 % | Joystick | 1–4 | Dibujo **sin layout nuevo**; torpe a propósito, y eso da risa | Media (comparar trazos) | — |
| **Dibujá y adiviná** | Al estilo Drawful: uno dibuja en su celular una palabra secreta y los demás eligen qué es entre opciones en su celular. Suma el que adivina y el que dibujó si alguien acertó. *Ej.:* Juli dibuja "jirafa"; Tomi elige "lámpara" y todos se ríen | Dibujar (**nuevo**) + cuatro botones | 3–4 | Creatividad de verdad; el celular como lienzo | Alta (trazos por red, ADR, validar tamaño y cantidad de puntos) | — |

### Trivia y preguntas

| Juego | Dinámica (con ejemplo) | Control | Jugadores | Qué suma | Dificultad | Reutiliza |
|---|---|---|---|---|---|---|
| **Trivia de la fiesta** | Preguntas con 4 respuestas; cuanto más rápido y correcto, más puntos. Incluye preguntas **sobre la partida en curso**, sacadas del historial del torneo. *Ej.:* "¿Quién juntó más estrellas en Arena hace un rato?": todos miran a Sofi | Cuatro botones (**nuevo**) | 1–4 | Juego de **cabeza**; las preguntas sobre la partida son únicas de este juego | Media (banco de preguntas por idioma y apto para chicos) | `Tournament.history` |
| **¿Quién es más probable…?** | "¿Quién es más probable que se duerma en el cine?". Cada uno vota a otro jugador en su celular; suma quien vota con la mayoría. *Ej.:* 3 de 4 votan al Oso de Pablo, que protesta | Cuatro botones con las mascotas de los jugadores | 3–4 | 100 % social, sin habilidad: parejo entre chicos y grandes | Baja de código; media de contenido (200 frases **amables**) | — |
| **Tutti frutti** | Categoría y letra ("un animal con M"). Cada uno escribe en su celular; los demás marcan si vale. *Ej.:* Tomi escribe "murciélago", Pablo "mosquito" y Juli "mono" | Teclado (**nuevo**) | 2–4 | El celular como teclado | Alta: texto libre por red (validar largo y mostrar solo con `Label`, regla de `CLAUDE.md`), idiomas y moderación | — |

> Votar ("¿quién es más probable?", "¿vale esta palabra?") **no rompe** la regla de que el celular no decide resultados: el voto es un `btn` más, y la TV cuenta, valida (un voto por persona, no votarse a sí mismo) y decide.

### Variantes: contenido nuevo sin juegos nuevos

**Concepto: *modificador*.** Una regla que cambia un juego existente sin reescribirlo. Multiplica el contenido y alimenta el Desafío del día y la Fiesta infinita, como la aceleración de WarioWare.

| Variante | Juegos | Ejemplo |
|---|---|---|
| **De noche** | Arena, Pintar el piso | Solo se ve un círculo de luz alrededor de cada mascota; las estrellas brillan un segundo al aparecer |
| **Turbo** | Todos | Todo va 30 % más rápido en los últimos 15 s |
| **Hielo** | Empujones, Arena | Las mascotas resbalan y frenan tarde |
| **Viento** | Esquivar, Ping Pong | Una ráfaga visible (con flechas) corre los bloques o la pelota |
| **Gigantes** | Empujones, Bombas saltarinas | Mascotas el doble de grandes: más choques |

Se declaran en `modifiers` de `get_info()` y el juego los recibe en `setup`. Un test genérico juega cada juego con cada variante.

## Retención

Qué hace que la gente **vuelva a jugar**, sin monetización agresiva.

**Concepto: *las tres necesidades*.** Según la teoría de la autodeterminación (Ryan, Rigby y Przybylski), un juego engancha cuando hace sentir **capaz** (competencia), **libre de elegir** (autonomía) y **conectado con otros** (relación); las tres predicen por separado el disfrute y las ganas de volver a jugar ([Motivation and Emotion, 2006](https://selfdeterminationtheory.org/SDT/documents/2006_RyanRigbyPrzybylski_MandE.pdf)).

*Ejemplo:* Juli vuelve porque (capaz) bajó su récord de Reloj exacto a 0,02 s, (autonomía) quiere desbloquear el gorro de cumpleaños para su Gato y (relación) quiere la revancha con Pablo en Ping Pong.

| Mecanismo | Qué es | Ejemplo | Dónde vive | Fase |
|---|---|---|---|---|
| **Stickers y accesorios** | Cada partida da un sticker; con 5 se desbloquea un accesorio **cosmético** (gorro de cumpleaños, anteojos de sol, bufanda, corona de flores, casco de sumo) | "Jugaste 10 partidas de Empujones: casco de sumo para tu Oso" | Perfil en el celular (`user://`); la TV valida que el accesorio exista, igual que `look` | D |
| **Patrones de pelaje** | Lunares, rayas, manchas y estrellitas sobre el cuerpo de la mascota | Sofi desbloquea "lunares" y su Conejo rosa se distingue del Conejo rosa de su prima **sin depender del color** (suma accesibilidad, ver [CALIDAD.md](CALIDAD.md)) | Ídem | D |
| **Bailes de victoria** | Animación elegible en el podio | El Robot de Tomi hace "el robot" al ganar | Ídem | D |
| **Logros** | Metas curiosas por juego, avisadas en el celular | "Ganar Reloj exacto con 0,00" · "Esquivar sin moverte 10 s" · "Pintar 100 baldosas" · "Tirar a 3 en un solo empujón" · "Ganar la Gran final viniendo último" · "Tapar 20 goteras" · "Jugar todos los juegos" | La TV los detecta y avisa con un mensaje informativo nuevo `achievement` (TV → celular, compatible, como `feedback`) | D |
| **Récords de la casa** | Tabla por juego guardada en la TV | En el lobby rota: "Récord de Esquivar: Juli, 52 s" | `user://` de la TV | C |
| **Estadísticas divertidas** | Datos curiosos al terminar | "Pablo caminó 1,2 km en Arena" · "Sofi tocó 312 veces" | Solo en pantalla | A |
| **Rivalidades** | Historial entre dos jugadores que se repiten | "Pablo vs Sofi en Ping Pong: 7 a 3. ¿Revancha?" | Perfiles en la TV por apodo + mascota | D |
| **Álbum de la fiesta** | Foto del podio de cada noche | "27/09: ganó el Conejo de Sofi" | Captura guardada en la TV, **nunca sale de la casa** | D |
| **Racha amable** | Cuenta **semanas** con al menos una fiesta y nunca se pierde con castigo | "Llevan 4 semanas de fiesta" | Perfil | D |

**Lo que no hacemos** (para público familiar, y porque sale caro): cajas sorpresa pagas, monedas premium, "perdés tu racha si no entrás hoy", notificaciones insistentes, ventajas de juego pagas ni anuncios en medio de una partida. En 2022 la FTC acordó con Epic Games (Fortnite) USD 245 millones en reintegros por *patrones oscuros* que llevaban a compras no deseadas ([FTC](https://www.ftc.gov/business-guidance/blog/2022/12/245-million-ftc-settlement-alleges-fortnite-owner-epic-games-used-digital-dark-patterns-charge)).

**Concepto: *patrón oscuro*.** Un diseño que empuja a hacer algo que la persona no quería. *Ejemplo de lo que no hay que hacer:* un botón "Comprar pack" del mismo color y en el mismo lugar que "Jugar otra vez", para que un chico lo toque sin querer.

**Si se monetiza** (decisión pendiente de [PLAN.md](PLAN.md)): pago único o **packs de juegos** ("Pack Playa: 4 juegos y 2 accesorios"), con precio claro y compra solo desde la TV con confirmación. Los accesorios se ganan jugando; ninguno se vende suelto.

**Por qué alcanza con que el perfil viva en el celular:** si alguien edita su archivo y se pone la corona sin ganarla, no cambia ningún resultado: es cosmético. Lo que la TV sí controla es que el id exista y que no rompa la distinción 1P–4P.

## Roadmap de contenido

### Tabla de prioridades

Impacto: cuánto mejora la experiencia de un grupo nuevo. Esfuerzo: S / M / L / XL (ver [MODOS.md](MODOS.md)). Fase según [PLAN.md](PLAN.md).

| # | Qué | Tipo | Impacto | Esfuerzo | Fase | Versión | Por qué ahí |
|---|---|---|---|---|---|---|---|
| 1 | Partida rápida + Gran final | Modo | Alto | S | A | v0.3 | Lo más pedido en la primera sesión ("tenemos 10 minutos") y casi gratis |
| 2 | Contrato `GameMode` (ADR 0013) | Base | Alto (habilita todo) | M | A | v0.3 | Sin él, cada modo ensucia `HostMain` |
| 3 | Desenfunde *(hecho)* | Juego | Alto | S | C | v0.3 | Un botón, 5 s de explicación, muchas risas |
| 4 | Bombas saltarinas | Juego | Alto | M | C | v0.3 | Caos al estilo BombSquad reutilizando Empujones |
| 5 | Tres puertas | Juego | Medio-alto | S | C | v0.3 | Primer juego de información oculta; barato |
| 6 | Estadísticas divertidas y Récords de la casa | Retención | Medio | S | A/C | v0.3 | El final "cierra" y queda algo para superar |
| 7 | Bots | Modo | Alto | L | C | v0.4 | Jugar solo, reemplazar desconectados, balancear con simulaciones |
| 8 | Cooperativo contra la TV | Modo | Alto (familias) | M-L | C | v0.4 | Nadie pierde contra nadie: ideal con chicos |
| 9 | La torta gigante | Juego | Alto | S | C | v0.4 | Primer cooperativo; es el desafío 1 del modo cooperativo |
| 10 | Equipos 2 vs 2 | Modo | Medio-alto | L | C | v0.4 | Criterio de la Fase C ("1 por equipos"); junto con Hockey de mesa |
| 11 | Layouts `four_buttons` y `joystick_ab` (`VERSION` 2; `joystick_ab` ya está) | Base | Alto | M | C | v0.4 | Se suman juntos, como pide [PLAN.md](PLAN.md) |
| 12 | Trivia de la fiesta | Juego | Alto | M | C | v0.4 | Juego de cabeza; usa el layout de 4 botones |
| 13 | Handicap ("Ayuda") | Modo | Medio | M | C | v0.4 | Se mide con las simulaciones de bots |
| 14 | Tablero de la fiesta | Modo | Muy alto | XL | C/D | v0.5 | Lo que hace "volver el sábado que viene"; necesita 12+ juegos y bots |
| 15 | Stickers, accesorios y logros | Retención | Alto | L | D | v0.5 | Motivo para volver sin tocar la justicia del juego |
| 16 | Fiesta infinita | Modo | Medio | M | C/D | v0.5 | Cumpleaños y reuniones largas |
| 17 | Desafío del día + variantes | Modo | Medio | M | D | v0.5 | Contenido nuevo cada día sin servidor |
| 18 | Sillas musicales, Barco con goteras, Contar ovejas | Juegos | Medio | S-M c/u | C | v0.5 | Música como mecánica, segundo cooperativo, juego tranquilo |
| 19 | Eliminación con fantasmas | Modo | Medio | M-L | D | Después | Divertido, pero pide juegos para 2 y variantes de fantasma |
| 20 | Espectador | Modo | Medio | M-L | E | Después | Cambia el protocolo y la red; tiene sentido con relay y fiestas grandes |
| 21 | Dibujá y adiviná, Tutti frutti | Juegos | Alto | L c/u | E | Después | Layouts de dibujo y texto: más protocolo, moderación y localización |
| 22 | Trampas para todos, Pizzería, Banda de mascotas | Juegos | Alto | L c/u | D/E | Después | Los más caros; conviene tener bots y variantes antes |

### Próximas 3 versiones

**v0.3 · "Más fiesta, mismo protocolo"** (cierra la Fase A y abre la C; se puede hacer en paralelo con la Fase B de dispositivos reales)
- **Modos:** Partida rápida + Gran final; contrato `GameMode` con `Tournament` adentro.
- **Juegos:** Desenfunde, Bombas saltarinas y Tres puertas, más los que ya están en curso del "Orden recomendado" (Pool loco, Karts de mascotas, Carrera de obstáculos). Con eso se llega a los **10–12 juegos** de la Fase C.
- **Retención:** estadísticas divertidas en el podio y Récords de la casa.
- **Por qué:** nada de esto cambia el protocolo, así que no obliga a actualizar la app del celular mientras se valida en dispositivos reales. Suma lo que un grupo nuevo nota en la primera noche: empezar rápido, juegos variados y un final con tensión.
- *Ejemplo:* un grupo que prueba la app por primera vez toca "Partida rápida", le salen Desenfunde, Pintar el piso y Bombas saltarinas, y la Gran final se define por una bomba que vuelve.

**v0.4 · "Solos, en equipo o todos juntos"** (Fase C, protocolo `VERSION` 2)
- **Modos:** Bots (con test obligatorio para todo juego), Cooperativo contra la TV, Equipos 2 vs 2 y Handicap.
- **Protocolo:** paquete de layouts `four_buttons` y `joystick_ab` (este ya está, [ADR 0014](adr/0014-layout-joystick-ab.md); junto con dos botones e inclinación, si ya están listos según [PLAN.md](PLAN.md)).
- **Juegos:** La torta gigante (cooperativo), Trivia de la fiesta (cuatro botones), Globos (joystick + botón), Hockey de mesa (equipos); Memoria de colores ya está hecha (joystick).
- **Por qué:** los bots son la base de tres cosas: jugar solo, reemplazar desconectados y **balancear con miles de partidas simuladas**, que a su vez sirven para medir el handicap. Cooperativo y equipos abren el juego a familias con chicos. Los layouts van todos juntos para actualizar la app una sola vez.
- *Ejemplo:* Juli juega sola con 3 bots un martes; el sábado la familia juega Cooperativo contra la Nube Gruñona y saca medalla de oro.

**v0.5 · "Para volver el sábado que viene"** (fin de la Fase C, entrada a la D)
- **Modos:** Tablero de la fiesta (versión 1, sin ítems, con "Tablero justo"), Fiesta infinita y Desafío del día con variantes.
- **Retención:** stickers, accesorios, patrones de pelaje, bailes y logros (mensaje `achievement`).
- **Juegos:** Sillas musicales, Barco con goteras y Contar ovejas, pensados para darle variedad al tablero.
- **Por qué:** el tablero necesita muchos juegos y bots para completar lugares, así que va después de v0.3 y v0.4. Junto con la progresión cosmética es lo que convierte "una noche divertida" en "la juntada de todos los sábados", que es el criterio de "listo" de la Fase D ("la mayoría quiere volver a jugar").
- *Ejemplo:* la familia guarda el tablero en el turno 6 y lo termina el domingo; Tomi desbloquea el casco de sumo para su Robot y Sofi supera el Desafío del día.

**Cómo saber si se acertó:** con la analítica anónima de la Fase D (Aptabase, [PRODUCCION.md](PRODUCCION.md)) medir qué modos se eligen, cuántos juegos se juegan por sesión y si el grupo vuelve en 7 días; y en las pruebas cerradas preguntar "¿qué juego sacarían?". Un juego que casi nadie elige no se arregla con más contenido, sino rediseñándolo o sacándolo del lobby.

## Fuentes

Consultadas el 27/09/2026. *(indirecto)*: confirmado por buscador, sin abrir la página.

- Mario Party: tipos de minijuego ([Mario Wiki](https://mario.fandom.com/wiki/Minigame_(Mario_Party_series))) y estrellas bonus ([Super Mario Wiki](https://www.mariowiki.com/Bonus_Star)) *(indirecto)*.
- Jackbox: controles del celular y público ([Built In Chicago](https://www.builtinchicago.org/articles/jackbox-games-design-party-pack), [Jackbox Wiki](https://jackboxgames.fandom.com/wiki/The_Jackbox_Party_Pack_(series))); fantasmas en Trivia Murder Party ([Jackbox Wiki](https://jackboxgames.fandom.com/wiki/Trivia_Murder_Party)) *(indirecto)*.
- Fall Guys: diseño y rondas ([GamesRadar](https://www.gamesradar.com/fall-guys-interview/), [NPR](https://www.npr.org/2020/08/13/901735175/fall-guys-is-candy-colored-party-battle-fun)) *(indirecto)*.
- Overcooked: cooperación y roles ([Push Square](https://www.pushsquare.com/news/2018/08/interview_chewing_the_fat_with_overcooked_2_developer_ghost_town_games), [Game Developer](https://www.gamedeveloper.com/design/game-design-deep-dive-building-truly-cooperative-play-in-i-overcooked-i-)) *(indirecto)*.
- Ultimate Chicken Horse: reglas y puntaje ([UCH Wiki](https://ultimate-chicken-horse.fandom.com/wiki/Rules), [Clever Endeavour](https://cleverendeavourgames.freshdesk.com/support/solutions/articles/32000028991-custom-rules-and-presets)) *(indirecto)*.
- Pummel Party ([Steam](https://store.steampowered.com/app/880940/Pummel_Party/)) *(indirecto)*.
- WarioWare: microjuegos y tablero de Move It! ([Super Mario Wiki](https://www.mariowiki.com/Microgame), [Biff Bam Pop](https://biffbampop.com/2023/11/16/in-the-game-warioware-move-it-unleashes-an-onslaught-of-microgames/)) *(indirecto)*.
- Kirby Air Riders: Top Ride y City Trial ([WiKirby Top Ride](https://wikirby.com/wiki/Top_Ride), [WiKirby City Trial](https://wikirby.com/wiki/City_Trial)) *(indirecto)*.
- BombSquad ([App Store](https://apps.apple.com/us/app/bombsquad/id416482767)) *(indirecto)*.
- Nintendo Switch Sports: liga y colecciones cosméticas ([Switch Sports Wiki](https://switchsports.fandom.com/wiki/Pro_League), [Game8](https://game8.co/games/Nintendo-Switch-Sports/archives/376755)) *(indirecto)*.
- Mecánicas de alcance ([Board Game Design Course](https://boardgamedesigncourse.com/making-a-comeback/)) *(indirecto)*.
- Motivación: Ryan, Rigby y Przybylski, *The Motivational Pull of Video Games* (2006) ([PDF](https://selfdeterminationtheory.org/SDT/documents/2006_RyanRigbyPrzybylski_MandE.pdf)) *(indirecto)*.
- Patrones oscuros: acuerdo de la FTC con Epic Games, 2022 ([FTC](https://www.ftc.gov/business-guidance/blog/2022/12/245-million-ftc-settlement-alleges-fortnite-owner-epic-games-used-digital-dark-patterns-charge)) *(indirecto)*.
