# Modos de juego: detalle y arquitectura

Detalle de los modos propuestos en [JUEGOS.md](JUEGOS.md#modos-de-juego) (allí está la tabla resumen, las lecciones de las referencias y el roadmap). Acá va, modo por modo: cómo se juega, qué cambia en el código, esfuerzo, riesgo y un ejemplo con las mascotas.

**Concepto: *modo de juego*.** Los minijuegos son las "canchas"; el modo es el "campeonato": decide qué juego viene, qué vale ganar cada uno y cuándo termina la noche.

*Ejemplo:* Empujones es el mismo juego en todos los modos. En **Competencia** el ganador suma 100 puntos; en **Equipos** el Oso y el Conejo suman juntos; en **Tablero** el ganador se lleva 10 monedas para comprar una estrella; en **Cooperativo** Empujones ni siquiera entra, porque no tiene sentido empujarse entre compañeros.

Esfuerzo: **S** (1–2 días), **M** (3–5 días), **L** (1–2 semanas), **XL** (más de 2 semanas), siempre con tests y capturas según la definición de "terminado" de [PLAN.md](PLAN.md).

## Base común: modos como "estrategia"

Hoy `HostMain` usa directamente `Tournament` (puntos 100/70/50/30, [ADR 0003](adr/0003-modo-competencia.md)). Para sumar modos sin llenar `HostMain` de `if`, se propone un contrato común.

**Concepto: *patrón estrategia*.** Varias clases cumplen el mismo contrato y el que las usa no sabe cuál tiene. `HostMain` pregunta "¿qué juego sigue?" y "¿cómo quedó?", y cada modo responde a su manera.

```
HostMain ── pregunta ──► GameMode (lógica pura, RefCounted, testeable sin red ni pantalla)
                           ├─ Tournament        (hoy: competencia; pasa a ser un GameMode más)
                           ├─ QuickMode         (Tournament con 3 juegos elegidos con criterio)
                           ├─ TeamMode          (2 vs 2: puntos por equipo)
                           ├─ CoopMode          (todos contra la TV: vidas y medallas)
                           ├─ EliminationMode   (el último de cada juego pasa a fantasma)
                           ├─ EndlessMode       (fiesta infinita: rotación sin final)
                           ├─ DailyMode         (desafío del día: un juego, una variante, una meta)
                           └─ BoardMode         (tablero: dados, casillas, monedas, estrellas)
MiniGame ◄── setup(players) — cada jugador puede traer: team, assist, bot, ghost
         ◄── modifiers      — variantes del juego ("bloques dobles", "de noche")
```

| Pieza | Cambio | Protocolo |
|---|---|---|
| `host/modes/game_mode.gd` (nuevo) | `next_game(players) -> String`, `record(result, players) -> Dictionary`, `is_over()`, `final_standings()`, `summary_kind()` (qué pantalla mostrar) | No |
| `Tournament` | Pasa a extender `GameMode` sin cambiar su lógica (sus tests siguen igual) | No |
| `MiniGame.get_info()` | Metadatos opcionales nuevos con valor por defecto en `OPTIONAL_DEFAULTS`: `teams` (`"none"`, `"sum"`, `"native"`), `coop` (bool), `bot` (script del bot o `null`), `modifiers` (lista de variantes) | No |
| `MiniGame.result` | Opcionales: `team_scores`, `coop_score` (0–1). Los modos que no los usan los ignoran | No |
| Lobby | Selector de modo navegable con D-pad antes de elegir juegos | No |
| ADR | **0013 · Modos de juego como estrategia** | — |

*Ejemplo:* un test genérico recorre `MiniGameRegistry.GAMES` × todos los modos con jugadores simulados y verifica que ningún modo se cuelga ni da puntos negativos. Igual que hoy "los tests genéricos cubren solos" a cada juego nuevo.

---

## 1. Partida rápida *(+ Gran final)*

**Cómo se juega.** Un botón grande en el lobby: "Partida rápida · 3 juegos". La TV elige tres juegos con criterio y arranca. Opcional para cualquier modo: **Gran final**, el último juego vale el doble.

**Concepto: *selección con variedad*.** Elegir al azar puro puede dar tres juegos de joystick seguidos. La selección evita repetir tipo de control o emoción entre juegos consecutivos y prefiere los menos jugados en esta TV.

*Ejemplo:* Pablo (Oso rojo), Sofi (Conejo rosa) y Tomi (Robot celeste) tienen 10 minutos antes de cenar. Tocan "Partida rápida" y salen Reloj exacto (botón, precisión), Pintar el piso (joystick, territorio) y Ping Pong (deslizar, duelo). Tomi va último por 60 puntos al llegar a Ping Pong, pero como es Gran final vale 200 / 140 / 100: si gana, da vuelta la partida. Nadie "ya perdió" en el último juego.

| Arquitectura | Detalle |
|---|---|
| Tournament | Ya soporta `shuffle`; falta `pick_varied(n, played_counts)` y un `multiplier` para la última ronda |
| Protocolo | Ninguno (`standing` ya manda los puntos de la ronda) |
| UI | Botón en el lobby; en la intro del último juego, un sello "×2 GRAN FINAL" |

**Esfuerzo:** S. **Riesgo:** bajo. El doble puntaje puede sentirse injusto para el que venía primero: mostrarlo **desde el principio** ("el último juego vale doble") para que sea regla y no sorpresa, que es la queja clásica de las estrellas bonus de Mario Party ([Super Mario Wiki](https://www.mariowiki.com/Bonus_Star) *(indirecto)*).

## 2. Bots para completar lugares

**Cómo se juega.** En el lobby, "Agregar bot" (fácil, normal, difícil). Sirve para jugar solo, para completar un 2 vs 2 y para reemplazar a quien se desconecta (con el cartel "1P Pablo se desconectó · lo reemplaza un bot" que propone [CALIDAD.md](CALIDAD.md)).

**Concepto: *bot con reglas*.** Un programa chico que "mira" el estado del juego y genera el mismo input que mandaría un celular: `{axis, btn}`. No hace trampa: tiene demora de reacción y errores a propósito.

*Ejemplo:* Juli juega sola contra 3 bots en Arena. El bot fácil camina hacia la estrella más cercana con 400 ms de demora y a veces se distrae; el difícil elige la estrella que nadie más tiene cerca. Los bots usan la mascota **Robot** con la chapita "BOT" en lugar de 1P–4P, así nadie los confunde con una persona.

| Arquitectura | Detalle |
|---|---|
| Registry | `bot` en `get_info()`: script por juego (`host/minigames/arena/arena_bot.gd`) con `think(game, player_id, dt) -> {axis, btn}` |
| HostMain | Un `BotDriver` llama a `think` cada cuadro y entrega el resultado a `game.on_input()`, igual que `HostServer` |
| Jugadores | `players` suma `bot: true` e ids que no chocan con los de red |
| Tests / CI | Test genérico: cada juego con bot termina una partida de 4 bots sin errores. Con eso se simulan miles de partidas para balancear (ver "¿Una red neuronal…?" en [PRODUCCION.md](PRODUCCION.md)) |
| Protocolo | Ninguno |

**Esfuerzo:** L (M la infraestructura + S por juego). **Riesgo:** medio. Un bot demasiado bueno frustra y uno tonto aburre; mantener un bot por juego cuesta. Mitigación: 3 niveles con los mismos números (demora y error) y el test que obliga a que todo juego nuevo traiga su bot. Árboles de comportamiento ([Beehave / LimboAI](RECURSOS.md)) solo si algún juego lo necesita.

## 3. Equipos 2 vs 2

**Cómo se juega.** En el lobby se activa "Equipos". Por defecto 1P+3P contra 2P+4P; la TV puede reordenar con el D-pad. Cada juego se juega de una de tres formas:

| Tipo (`teams`) | Qué pasa | Ejemplo |
|---|---|---|
| `native` | El juego está hecho para equipos | Hockey de mesa, Fútbol 2 vs 2 |
| `sum` | Juego de todos contra todos donde se suma lo de los dos | Arena: estrellas del Oso + estrellas del Gato |
| `none` | No se juega en equipos | Ping Pong (es 1 contra 1) |

**Concepto: *identidad de equipo sin color*.** Como los colores los elige cada jugador ([ADR 0007](adr/0007-apariencia-del-jugador.md)), el equipo no puede ser "rojo contra azul". Cada equipo lleva **forma y patrón**: equipo Sol (bandana lisa, chapita redonda) y equipo Luna (bandana rayada, chapita triangular).

*Ejemplo:* Pablo (Oso rojo) y Juli (Gato amarillo) son equipo Sol; Sofi (Conejo rosa) y Tomi (Robot celeste) son Luna. En Pintar el piso el piso tiene solo dos patrones, lunares y rayas. Sol pinta el 58 %: Pablo y Juli suman 100 cada uno; Sofi y Tomi, 50.

| Arquitectura | Detalle |
|---|---|
| Modo | `TeamMode`: puntos por puesto del equipo (100 / 50) a cada integrante; juegos `none` se saltean |
| MiniGame | `team` en cada jugador; los `native` lo usan para ubicar y resolver; los `sum` no cambian: suma el modo |
| Con 3 jugadores | **1 contra 2**: el que va solo tiene ventaja de juego (más vida, más velocidad), como los 1-vs-3 de Mario Party ([Mario Wiki](https://mario.fandom.com/wiki/Minigame_(Mario_Party_series)) *(indirecto)*) |
| Protocolo | Opcional: `team` en `standing` para que el celular muestre "Ganó tu equipo" (compatible) |
| UI | Lobby con dos columnas, chapita con forma, resumen por equipo |

**Esfuerzo:** L. **Riesgo:** medio. Los juegos `sum` pueden sentirse "individuales con otra cuenta"; el valor real está en los `native` (Hockey, Fútbol, La torta gigante). Equipos desparejos (papá + nene contra mamá + nena) funcionan si se combinan con handicap (modo 5).

## 4. Cooperativo contra la TV

**Cómo se juega.** Todos juntos contra un rival de la TV: la **Nube Gruñona**, que tira bloques, apaga luces y hace llover. Se juegan 4 desafíos seguidos con **3 corazones compartidos**. Al final, medalla de bronce, plata u oro según cuánto se logró.

**Concepto: *interdependencia*.** En un buen cooperativo nadie puede ganar solo: los roles se reparten y hay que hablar. Es la base de Overcooked, donde cada jugador tiene un papel imprescindible y la presión del tiempo termina en gritos y risas ([Push Square](https://www.pushsquare.com/news/2018/08/interview_chewing_the_fat_with_overcooked_2_developer_ghost_town_games), [Game Developer](https://www.gamedeveloper.com/design/game-design-deep-dive-building-truly-cooperative-play-in-i-overcooked-i-) *(indirecto)*).

*Ejemplo:* la Nube se lleva la torta de cumpleaños. Desafío 1, **La torta gigante**: los cuatro tiran de la torta con su joystick y solo se mueve si tiran para el mismo lado; Tomi grita "¡a la derecha!". Desafío 2, **Esquivar cooperativo**: si a Sofi la aplasta un bloque queda como fantasma y Pablo la revive tocándola. Desafío 3, **Barco con goteras**. Terminan con 2 corazones: medalla de plata, y la Nube se va llorando.

| Arquitectura | Detalle |
|---|---|
| Modo | `CoopMode`: corazones, desafíos y medalla; sin ranking individual (solo "estadísticas divertidas": "Juli tapó 14 goteras") |
| MiniGame | `coop: true` y `coop_score` (0–1) en el resultado. Juegos existentes adaptables con una variante: Esquivar (revivir), Arena (meta común de 60 estrellas), Pintar el piso (pintar el 80 % antes de que llueva) |
| Rival | La Nube es un personaje de `core/ui/widgets/` dibujado por código, igual que las mascotas |
| Protocolo | Ninguno |

**Esfuerzo:** M con juegos adaptados; L con juegos cooperativos propios. **Riesgo:** medio. El problema del "jugador que manda a todos" (uno decide y los demás obedecen) se reduce con presión de tiempo y tareas en paralelo. Es el modo ideal para familias con chicos: nadie pierde contra nadie.

## 5. Handicap para chicos ("Ayuda")

**Cómo se juega.** En el lobby, la TV pone a cada jugador un nivel de ayuda: sin ayuda, ayuda o mucha ayuda. Cada juego decide qué significa, y se ve en pantalla con un ícono de estrellita junto al nombre: no es trampa escondida.

**Concepto: *mecánica de alcance* (catch-up).** Ayudar a quien va atrás mantiene a todos metidos, pero si se nota demasiado castiga al que juega bien. La recomendación del diseño de juegos de mesa es dar **oportunidades** y no regalos ([Board Game Design Course](https://boardgamedesigncourse.com/making-a-comeback/) *(indirecto)*).

*Ejemplo:* Juli (7 años, Conejo blanco) juega con "mucha ayuda":

| Juego | Qué cambia para Juli |
|---|---|
| Arena de estrellas | Agarra estrellas desde un 40 % más lejos |
| Reloj exacto | Frenar a ±0,3 s del objetivo cuenta como perfecto |
| Carrera de toques | Cada toque vale 1,3 |
| Esquivar | Arranca con un escudo que aguanta un golpe |
| Ping Pong | Su paleta es un 30 % más ancha |

| Arquitectura | Detalle |
|---|---|
| Jugadores | `assist: 0..2` en `players`; el juego que no lo implementa lo ignora |
| Balance | Las simulaciones con bots (modo 2) miden que "mucha ayuda" iguale a un bot normal con uno fácil, sin pasarse |
| Protocolo | Ninguno: lo decide la TV, nunca el celular |
| UI | Ciclo de ayuda en la tarjeta del jugador en el lobby (D-pad) |

**Esfuerzo:** M (S por juego). **Riesgo:** bajo-medio: un adulto podría ponerse ayuda a sí mismo. Como el ícono se ve, lo resuelve la mesa ("¡Pablo, sacate la ayuda!").

## 6. Torneo por eliminación (con fantasmas)

**Cómo se juega.** Al estilo Fall Guys: después de cada juego, el último queda eliminado. Con 4 jugadores: ronda de 4, ronda de 3 y **final 1 contra 1**. Los eliminados **no se van**: pasan a ser fantasmas que siguen jugando con reglas propias.

**Concepto: *eliminación sin aburrimiento*.** Quedar afuera y mirar 10 minutos es lo peor en una fiesta. En Trivia Murder Party de Jackbox los muertos siguen jugando como fantasmas en la ronda final ([Jackbox Wiki](https://jackboxgames.fandom.com/wiki/Trivia_Murder_Party) *(indirecto)*), y en Fall Guys caerse es gracioso, no frustrante ([GamesRadar](https://www.gamesradar.com/fall-guys-interview/) *(indirecto)*).

*Ejemplo:* Tomi (Robot) sale último en Esquivar y queda eliminado. En el siguiente juego, Arena, su mascota aparece traslúcida con una sábana de fantasma: no puede ganar, pero cada estrella que junta le da un "susto" (un segundo de lentitud) al rival que elija. En la final, Pablo contra Sofi en Ping Pong, los dos fantasmas pueden soplar la pelota un poco hacia el lado de uno de ellos. La TV valida todo: el fantasma solo manda `axis` y `btn`, como siempre.

| Arquitectura | Detalle |
|---|---|
| Modo | `EliminationMode`: quién sigue vivo, orden de eliminación como puesto final |
| MiniGame | `ghost: true` en `players`; variante opcional por juego ("qué hace un fantasma acá"); sin variante, el fantasma mira con layout `wait` y un emote de alentar |
| Protocolo | Ninguno (los fantasmas reciben el layout del juego o `wait`) |
| UI | Resumen con "¡Eliminado!" divertido (la mascota se va flotando), llave visual de la final |

**Esfuerzo:** M (sin variantes de fantasma) a L (con variantes). **Riesgo:** medio: con 2 jugadores no tiene sentido (se desactiva) y la final 1 contra 1 necesita juegos para 2 (Ping Pong, Hockey, Reloj exacto).

## 7. Fiesta infinita

**Cómo se juega.** Para cumpleaños o reuniones largas: los juegos se suceden sin podio final. La gente entra y sale **entre juegos**. En pantalla, una **corona** sobre la mascota de quien ganó más de los últimos 5 juegos, así quien llega tarde también puede ser "rey de la fiesta".

**Concepto: *ventana móvil*.** El ranking cuenta solo los últimos N juegos, no toda la noche. Quien jugó 2 horas no tiene ventaja eterna sobre quien llegó hace 10 minutos.

*Ejemplo:* en el cumpleaños de Sofi, Pablo (Oso) se va a comer torta y deja su lugar. Juli (Gato) escanea el QR en la mitad de Empujones: su celular dice "Entrás en el próximo juego" y la TV muestra su mascota esperando en el borde. Dos juegos después, Juli tiene la corona.

| Arquitectura | Detalle |
|---|---|
| Modo | `EndlessMode`: selección con variedad (modo 1) sin fin y ranking de los últimos 5 juegos |
| HostServer | Aceptar `join` durante una partida y dejar al jugador **en cola** (hoy rechaza con `game_in_progress`); entra al próximo `setup` |
| Protocolo | Sin mensajes nuevos: al que está en cola se le manda `layout: wait` con `data.label` "Entrás en el próximo juego". Revisar que los controles viejos lo muestren bien |
| UI | Fila de "esperando" en el borde, corona sobre la mascota, "Terminar fiesta" en la pausa |

**Esfuerzo:** M. **Riesgo:** medio. Tocar el ciclo de vida de la sala (entrar a mitad) es delicado para la red y la reconexión; necesita tests de integración como los de [SECURITY.md](SECURITY.md).

## 8. Desafío del día

**Cómo se juega.** Cada día hay un desafío para jugar solo o de a varios: un juego existente con una variante y una meta. "Hoy: Esquivar con bloques dobles; aguantá 40 segundos."

**Concepto: *semilla por fecha*.** La TV calcula el desafío a partir de la fecha (por ejemplo `hash("2026-09-27")`) con un generador de números al azar. Todas las TVs del mundo tienen el mismo desafío el mismo día **sin ningún servidor**, como el Wordle.

*Ejemplo:* el sábado el desafío es "Arena de noche: 15 estrellas en 45 s". Pablo llega a 13; el domingo a la mañana Sofi, con su Conejo, hace 16 y queda en la tabla "Récord de la casa". Si nadie juega el martes, no pasa nada: no hay castigo.

| Arquitectura | Detalle |
|---|---|
| Juegos | `modifiers` en `get_info()` (variantes: "de noche", "bloques dobles", "más rápido") y una meta medible |
| TV | Récords guardados en `user://` de la TV (sin datos personales: apodo y mascota) |
| Protocolo | Ninguno |
| UI | Tarjeta "Desafío de hoy" en el lobby |

**Esfuerzo:** M. **Riesgo:** bajo. Cuidado con los patrones oscuros: nada de "¡perdés tu racha si no jugás hoy!" (ver "Retención" en [JUEGOS.md](JUEGOS.md#retención)).

## 9. Modo espectador (público)

**Cómo se juega.** Si hay más de 4 personas, las que sobran entran como **público**. Su celular muestra botones de alentar (aplauso, risa, "¡uh!") que aparecen como burbujas sobre el borde de la TV, y en Partida rápida o Tablero votan **qué juego sigue** entre tres opciones.

**Concepto: *modo audiencia*.** Jackbox deja sumar hasta 10.000 espectadores que votan desde el celular ([Jackbox Wiki](https://jackboxgames.fandom.com/wiki/The_Jackbox_Party_Pack_(series)) *(indirecto)*). En una casa alcanza con pocos, pero la idea es la misma: nadie queda sin participar.

*Ejemplo:* en el cumpleaños hay 7 personas. Pablo, Sofi, Tomi y Juli juegan; la abuela, Nico y Lu son público. Cuando Tomi gana Ping Pong en el último punto, la TV se llena de burbujas de aplauso. Después votan "¿Qué sigue?": gana Pintar el piso por 2 a 1.

| Arquitectura | Detalle |
|---|---|
| Protocolo | **Cambio con ADR**: `join` suma `role: "audience"` (si falta, es jugador: compatible) y un mensaje nuevo control → TV `cheer` con un índice de una lista cerrada. La TV valida, **limita la frecuencia** (1 cada 2 s por persona) y tope de 8 espectadores. Votar el próximo juego no decide ningún resultado; aun así lo cuenta la TV |
| HostServer | Conexiones de público separadas de `MAX_PLAYERS`; no reciben `standing` |
| UI | Burbujas en el borde (capa cacheada, presupuesto de [PERFORMANCE.md](PERFORMANCE.md)); pantalla de voto |

**Esfuerzo:** M-L. **Riesgo:** medio: es superficie de red nueva (spam, límites) y sube `VERSION` si los controles viejos no lo toleran. Conviene sumarlo junto con los layouts nuevos.

## 10. Tablero de la fiesta (tipo Mario Party)

**Cómo se juega.** Un tablero circular de ~30 casillas en un parque. Cada **turno** todos tiran el dado **a la vez** y avanzan juntos (sin esperar a los demás), después se juega un minijuego y su resultado da monedas. Con 20 monedas se compra la **estrella** cuando se pasa por su casilla. Gana quien tenga más estrellas después de 10 turnos (~35 minutos).

**Conceptos:**
- **Economía de dos monedas.** Las monedas se ganan seguido y en cantidades chicas; las estrellas son pocas y deciden. Así cada minijuego importa, pero ninguno solo define la noche.
- **Casillas.** Azul (+3 monedas), roja (−3), evento (le pasa algo a todos), duelo (el que cae desafía a otro a un minijuego 1 contra 1).
- **Estrellas bonus.** Premios al final por estadísticas ("el que más casillas caminó"). Son la sorpresa típica de Mario Party, pero muchas veces premian al que ya iba ganando ([Super Mario Wiki](https://www.mariowiki.com/Bonus_Star) *(indirecto)*): acá se anuncian **al principio** y favorecen a quien va atrás.

*Ejemplo:* turno 6. Pablo (Oso rojo) toca su celular y la TV saca un 4; Sofi (Conejo rosa), un 6. Sofi pasa por la estrella con 22 monedas y la compra (queda con 2). Tomi (Robot) cae en una casilla de evento: "¡Viento!", y todos retroceden 2. Juli cae en duelo y elige a Sofi para jugar Reloj exacto: gana Juli y le saca 5 monedas. Minijuego del turno: Pintar el piso; Pablo sale primero y suma 10 monedas. Al final, la estrella bonus anunciada era "Estrella del caminante lento" (el que menos avanzó): se la lleva Tomi y empata el segundo puesto.

| Arquitectura | Detalle |
|---|---|
| Modo | `BoardMode`: tablero como datos (lista de casillas y vecinos), dados con el RNG de la TV, economía y bonus. Lógica pura y testeada: "con esta semilla, después de 10 turnos, Sofi tiene 3 estrellas" |
| Dado | El celular solo manda "tocó" (`one_button`, `data.label` "¡Tirá!"); **el número lo decide la TV**. En los cruces, `joystick`: la TV lee la dirección con un tiempo límite y, si no hay respuesta, elige sola |
| Minijuegos | Monedas por puesto: 10 / 6 / 4 / 2. Los duelos usan juegos para 2 |
| Protocolo | Ninguno: `layout` con `data.label` alcanza |
| UI | Pantalla `BoardScreen` con el tablero en una capa estática cacheada y solo las mascotas y el dado animados ([ADR 0006](adr/0006-rendimiento-capas-cacheadas.md)); marcador de monedas y estrellas con 1P–4P |
| Guardado | Guardar la partida en `user://` para seguir otro día (una sesión de 35 min se corta seguido) |
| ADR | **0011 · Modo tablero** |

**Esfuerzo:** XL. **Riesgo:** alto. Es una pantalla y una lógica grandes; demasiada suerte frustra ("perdí por un dado"). Mitigaciones: movimiento simultáneo (cero espera), partida corta (10 turnos) y opción **"Tablero justo"** sin casillas rojas ni eventos de robo, solo minijuegos y estrellas. Referencias: el modo tablero de Pummel Party con ítems absurdos ([Steam](https://store.steampowered.com/app/880940/Pummel_Party/) *(indirecto)*) y el tablero corto de WarioWare: Move It!, donde casi todas las casillas son malas y el liderazgo cambia de mano todo el tiempo ([Biff Bam Pop](https://biffbampop.com/2023/11/16/in-the-game-warioware-move-it-unleashes-an-onslaught-of-microgames/) *(indirecto)*).

**Versión 2 del tablero:** ítems (dado doble, "cambio de lugar", guante para robar una moneda), varios tableros temáticos y "Tablero rápido" de 5 turnos.

---

## Resumen de impacto en la arquitectura

| Modo | `GameMode` | MiniGame | Protocolo | Pantallas nuevas | Esfuerzo | Riesgo |
|---|---|---|---|---|---|---|
| Partida rápida + Gran final | QuickMode | — | No | Botón y sello ×2 | S | Bajo |
| Bots | (todos) | `bot` + script por juego | No | Chapita BOT | L | Medio |
| Equipos 2 vs 2 | TeamMode | `teams`, `team` | Opcional (`team` en `standing`) | Lobby por equipos | L | Medio |
| Cooperativo contra la TV | CoopMode | `coop`, `coop_score` | No | Corazones, medalla, la Nube | M-L | Medio |
| Handicap | (todos) | `assist` | No | Ícono de ayuda | M | Bajo-medio |
| Eliminación con fantasmas | EliminationMode | `ghost` | No | Llave y eliminado | M-L | Medio |
| Fiesta infinita | EndlessMode | — | No (cola con `wait`) | Fila y corona | M | Medio |
| Desafío del día | DailyMode | `modifiers` | No | Tarjeta y récords | M | Bajo |
| Espectador | (todos) | — | **Sí** (`role`, `cheer`) | Burbujas y voto | M-L | Medio |
| Tablero | BoardMode | Monedas por puesto | No | `BoardScreen` | XL | Alto |

Regla que se mantiene en todos: **la TV decide**. Los celulares siguen mandando solo `axis` y `btn` (más `cheer` del público, que no afecta resultados). Dados, votos, ayudas y bots los resuelve la TV.
