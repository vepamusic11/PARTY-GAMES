# Pendientes para retomar

Estado al **29/09/2026** (rama `claude/laughing-ramanujan-tfi3ps`, [PR #1](https://github.com/vepamusic11/PARTY-GAMES/pull/1)). Lo hecho está en el PR y en [PLAN.md](PLAN.md); acá va solo **lo que falta**, ordenado para retomar sin buscar.

## Cómo retomar (5 minutos)

1. Traer lo último: `git pull` en `D:\Claude\PARTY-GAMES` (rama `claude/laughing-ramanujan-tfi3ps`).
2. Importar (arma el índice de clases; hace falta después de cada `git pull` con archivos nuevos):
   `& "D:\Claude\Godot\Godot_v4.4.1-stable_win64_console.exe" --headless --path . --import`
3. Probar en la PC: `... --path . -- --host` (TV, ventana izquierda) y `... --path . -- --controller` (control, ventana derecha). Para jugar solo: en el lobby, Enter sobre un lugar libre → "Sumar bot".
4. Pedirle a Claude: *"retomá los pendientes de docs/PENDIENTES.md"*.

## 1. Lo que depende del dueño

| Qué | Por qué | Cómo |
|---|---|---|
| **Subir como archivo los temas de Suno** del lobby (`suno.com/s/29C9BMlJJeFzj1jz`) y de batallas (`suno.com/s/F9Tq26dAwsYYmFG0`, `suno.com/s/BdjIiimEjU85XsRR`) | El entorno de Claude no puede entrar a suno.com | En Suno: menú **⋯ → Download → MP3 Audio** y adjuntar el `.mp3` en el chat (como se hizo con *Breakpoint Rush*) |
| **Confirmar el plan de Suno** con el que se hicieron los temas | Suno da uso comercial solo a canciones creadas con plan pago (Pro/Premier); con el gratis es uso no comercial | Si fueron con plan gratis, regenerarlos con plan pago antes de publicar |
| **Probar en la PC** y mandar capturas de lo que no guste | Validar diseño y jugabilidad reales | Ver "Cómo retomar" |
| **Instalar el APK de prueba** en un celular Android (el job `apk` de la CI ya lo arma) | Probar con el celular real como control | GitHub → Actions → última corrida → Artifacts → `party-game-debug-apk`; permitir "orígenes desconocidos" ([BUILD.md](BUILD.md)) |
| **Decidir**: enlace definitivo del QR para unirse; pantalla de Créditos antes de publicar | Fase B/D | [RECURSOS.md](RECURSOS.md), [CREDITS.md](../CREDITS.md) |
| **Conseguir un aparato de gama baja** (Chromecast con Google TV o TV box Android, ~30–40 USD) | Es la única forma de medir 60 fps reales y el 3D horneado en el chip de una TV barata | — |

## 2. Trabajo en curso

No quedó ningún agente trabajando: todo lo del 29/09 está integrado en la rama (vuelta 3 de dirección de arte y ayuda de los eliminados).

**Para la próxima sesión (sugerido, en este orden):**
1. **Empujones en 2.5D** (receta `sumo` con sala y agua; la isla proyectada en 2D) y **Desenfunde** con fachadas 3D del pueblo; con eso no queda ningún juego plano ([ADR 0019](adr/0019-tablero-25d-horneado.md)).
2. **Ayuda de los eliminados** en Memoria de colores (pista) y ¡Que no te deje la cámara! (empujón); ajustar el costo con bots ([MODOS.md §11](MODOS.md#11-ayuda-de-los-eliminados-a-cambio-de-puntos), [ADR 0020](adr/0020-ayuda-de-los-eliminados.md)).
3. **Siguiente juego nuevo:** *Bombas de mascotas* (tipo Bomberman, estrena el joystick + A/B, con ayuda de eliminados desde el principio).
4. **Decisiones del dueño pendientes:** texto del botón de orden del lobby ("Orden: lista" vs. el largo) y si vale la pena cambiar el protocolo para mostrar las mascotas en el selector de ayuda del celular.

## 3. Diseño (pedido: "3D como la maqueta o mejor")

- [x] Mascotas 3D horneadas en todo el juego (lobby, intro, 13 juegos, resumen, podio, celular) con respaldo 2D ([ADR 0012](adr/0012-mascotas-3d.md)).
- [x] Podio centrado (la línea "Se jugó…" lo corría a la derecha y cortaba el 3.°).
- [x] Calidad de las mascotas 3D al nivel de la maqueta: plástico, cara, contorno y los 9 ánimos ([comparación](img/mascotas_3d_comparacion.png)). Paleta: amarillo dorado y verde pasto de la maqueta (29/09).
- [x] Piezas del escenario en 3D: estrellas, bloques, medallas, corona y trofeos con el mismo plástico ([ADR 0016](adr/0016-piezas-3d-horneadas.md), hoja `docs/img/piezas_3d.png`). El celular sigue con piezas 2D.
- [x] Lobby más cerca de la maqueta (29/09): tarjetas de jugador en degradé pastel, fichas del código y "¡A jugar!" de juguete, fondo más lleno y **dioramas 3D de los juegos** en las tarjetas ([ADR 0018](adr/0018-dioramas-de-los-juegos.md), [comparación](img/lobby_comparacion.png)). Pose "¡hola!" con una mano bien arriba y revisión de dirección de arte medida contra la maqueta (29/09, `docs/ARTE.md`). Pendiente: dioramas con los looks elegidos no (usan el cuarteto).
- [x] ~~Escalón de luz entre celdas del atlas de mascotas~~: estaba (brillo medio de la misma pose 143 → 157 de 255 entre la primera y la última celda). La cámara del horneado pasó de 80 u a 10 000 u: diferencia 0,2/255. `tools/mascot_atlas_check.gd` lo mide (falla si pasa de 1,5) y `test_mascot_atlas_uniform_light` controla la geometría ([ADR 0012](adr/0012-mascotas-3d.md)).
- [x] Captura de Empujones: ya muestra el juego (con --out a una carpeta temporal; docs/img sin regenerar). La espera en sí no era el problema: la foto esperaba hasta 2,5 s a que se hornearan poses tardías (susto caminando) y en ese tiempo se caían todos; con el precalentado por juego ya no espera.
- [ ] Captura de ¡Que no te deje la cámara!: sigue saliendo el resumen. Los controles de prueba ahora avanzan a la derecha mientras esperan (`RUN_RIGHT` en `tools/capture_screens.gd`); en una simulación sin pantalla con esa misma entrada nadie cae antes de los 8 s (el 4P, quieto, a los 5,5 s), pero en la corrida real con xvfb el juego igual terminó antes de la foto (todos con 0 m). Revisar si la entrada de los controles llega a este juego durante la captura.
- [x] Dirección de arte, **vuelta 2** (29/09, "al máximo"): mascotas con las proporciones medidas de la maqueta (cara 68 % de la cabeza, brazos visibles, ojos y cachetes más grandes) y plástico "jugoso" (`spec_soft`, `shade_spread` en el shader); Pintar el piso con las mascotas al tamaño de la maqueta (`MASCOT_SCALE` 1,3) y el cartel del power-up como ficha chica; dioramas más cerca, saturados y de 660×260; consolas del resumen y bloques del podio como fichas de juguete y título "de logo" en el resumen. Medido en `docs/ARTE.md` ("vuelta 2"). Pendiente: comparar juego por juego con la maqueta de Pintar una vez que Arena, Esquivar y Pool pasen al 2.5D.
- [x] Pintar el piso en **2.5D horneado** como la maqueta: tablero 3D con perspectiva, marco de bloques con volumen y juguetes desenfocados alrededor, con costo de 2D por cuadro ([ADR 0019](adr/0019-tablero-25d-horneado.md), [comparación](img/pintar_25d_comparacion.png)).
- [x] Arena de estrellas, Esquivar y Pool loco en **2.5D horneado** (29/09): encuadre como Pintar el piso (`make_fit`), recetas `arena`, `dodge` (baldosas lila) y `pool` (mesa con bandas, troneras y miras en 3D); reglas, bots y tests de reglas sin cambios ([ADR 0019](adr/0019-tablero-25d-horneado.md); comparaciones [Arena](img/arena_25d_comparacion.png), [Esquivar](img/dodge_25d_comparacion.png), [Pool](img/pool_25d_comparacion.png)). Miniaturas regeneradas.
- [x] Dirección de arte, **vuelta 3** (29/09): Karts, Ping Pong, Carrera de toques y Carrera de obstáculos en **2.5D horneado** (recetas `karts`, `pingpong`, `tap_race`/`hurdles`); la sala de juguetes 3D como cielo de los juegos sin tablero (Memoria, Reloj exacto, ¡Que no te deje la cámara!; receta `stage` en `draw_sky()`); Pool tapa las bolas con la banda de adelante; en Esquivar los bloques caen por delante del marcador; brazos más gordos y ojos más grandes en las mascotas. Medido en `docs/ARTE.md` ("vuelta 3"), comparaciones `docs/img/*_25d_comparacion.png`.
- [ ] **Empujones en 2.5D**: la isla se achica, así que no se hornea. Plan: receta `sumo` con solo la sala y el agua (piso de agua con olas horneadas, tribunas como paneles 3D) y la isla en 2D proyectada (anillos como polígonos por `project_points`, costado como banda entre el borde proyectado y el mismo borde bajado `ISLAND_DEPTH`, espuma acostada, mascotas paradas). Tocar solo `_draw_*_layer` y `_draw_player/_draw_falling` (la lógica la está cambiando otro agente: ayuda de eliminados).
- [ ] **Desenfunde**: tiene su pueblo pintado (saloon, sheriff, cactus). Plan: receta `quickdraw` con las fachadas como cajas de plástico con volumen y el piso de tierra en perspectiva; las mascotas y los carteles siguen en 2D. Bajo impacto: es una pantalla fija y ya se ve bien.
- [ ] Empujones y Karts con máquina libre: confirmar p95 ≤ 8 ms (con carga no lo cumplían).
- [ ] Medir en una Google TV real el horneado del tablero 2.5D (0,8–1,9 s en llvmpipe la primera vez por juego —Karts es el más pesado—; después se lee del disco en ~50 ms), la memoria de la textura (6–8 MB por juego mientras se juega, más la sala `stage` en los juegos sin tablero) y el disco (`user://board25d/`: un PNG por receta y, en carriles, por cantidad de jugadores; ≈ 0,65 MB cada uno).
- [ ] Revisar con la maqueta de Pintar el piso (`docs/design/referencia_juego_pintar.webp`) juego por juego una vez integrado todo.
- [x] ~~Poses que se hornean la primera vez que se dibujan~~: cada juego declara `MASCOT_PREWARM` (y `MASCOT_SCALE` Carrera de toques y Ping Pong, que se precalentaban a otro tamaño). Poses tardías en una partida con 4 bots: 87 → 2 (un cuadro de festejo caminando al final de Arena y de Pintar). Tabla en [PERFORMANCE.md](PERFORMANCE.md); medir con `tools/mascot_prewarm_check.gd`. El atlas llega a ~33 MB en los juegos con más poses (presupuesto 40 MB).

## 4. Juegos nuevos (ver [JUEGOS.md](JUEGOS.md))

- **Siguiente:** *Bombas de mascotas* (tipo Bomberman; estrena el joystick + A/B), *Tanquecitos* (tipo Battle City, 2 contra 2 cuidando la base), *Víboras*, *Come-come*.
- Regla nueva: no todos los juegos necesitan la mascota entera; alcanza el color del jugador **con** etiqueta 1P–4P y patrón propio ("Cómo se ve cada jugador" en JUEGOS.md).
- [x] **Ayuda de los eliminados** (idea del dueño, 29/09) en Esquivar (escudo burbuja) y Empujones (salvavidas): el eliminado elige con el joystick a quién ayudar y paga 10 puntos (20 si ayuda al primero); lobby "Ayudas: Sí/No"; cartel en la TV y línea en el resumen; bots que ayudan al último ([MODOS.md §11](MODOS.md#11-ayuda-de-los-eliminados-a-cambio-de-puntos), [ADR 0020](adr/0020-ayuda-de-los-eliminados.md)).
- [ ] Ayuda de los eliminados en Memoria de colores (pista) y ¡Que no te deje la cámara! (empujón); medir el balance del costo con bots y en partidas reales; si Empujones pasa a 2.5D, que `help_anchor` use la proyección.
- [ ] Ayuda de los eliminados, rendimiento: con una ayuda activa **todo el tiempo** (peor caso, benchmark con el 4P ayudando sin parar) Scripts p95 sube a ~6,7 ms en Esquivar y ~7,9 ms en Empujones (sin ayuda: 2,4 / 3,3 ms; máquina compartida, números ruidosos). Dentro de los 8 ms pero justo en Empujones: medir en la TV real; si hace falta, cachear la mascota traslúcida y la burbuja/salvavidas en una textura.
- [ ] Ayuda de los eliminados, celular: muestra el hint "Elegí a quién ayudar: 1P · 2P" y A/B, pero no la mascota de cada candidato (pediría un campo nuevo en `layout`, cambio de protocolo); la mascota y la ficha del elegido se ven en la TV.
- Máximo de jugadores: **4** (confirmado). Juegos por competencia: **sin límite** (confirmado).

## 4b. Música (ver [ADR 0017](adr/0017-estilos-de-musica.md))

- [ ] **El dueño elige** escuchando las muestras (Fiesta, Latino, Relajado, Retro, PARTY-GAME con *Breakpoint Rush*). Fiesta y Latino salen de un generador propio: aprobar o descartar al oírlos.
- [ ] Tema del lobby del dueño: falta el MP3. Va en `assets/audio/music/original/lobby.ogg` (sumarlo a `SONGS` en `tools/audio/prepare_audio.py` con su punto de bucle). Los dos temas de "batallas" también faltan como archivo.
- [x] Selector de estilo también en el lobby (píldora "♪ Música: …" junto a "¿A qué jugamos?").
- [x] ~~Silencio en una TV lenta mientras se compone Fiesta/Latino~~: las pistas generadas se guardan en `user://music_cache/` (`MusicCache`: firma de la receta, tope 40 MB, archivo roto o viejo se descarta) y, si no suena nada mientras se compone, suena la misma pantalla en Retro y la generada entra con fundido ([ADR 0017](adr/0017-estilos-de-musica.md)). Falta medir en la TV real cuánto tarda en leerse (en la PC ~1 ms).
- [ ] Peso: música ~7,7 MB (presupuesto 8 MB); con el tema del lobby del dueño, ~10 MB.

## 5. Técnico y calidad

- [ ] Medir en un Google TV real: 60 fps, horneado de mascotas (ajustar `Mascot3DBaker.POSES_PER_FRAME`), memoria (~25–30 MB de atlas).
- [ ] Carrera de obstáculos: re-medir p95 con la máquina libre (quedó en el límite de 8 ms con la máquina cargada).
- [ ] Sumo, Pool y Karts: confirmar p95 ≤ 8 ms con la máquina libre (con carga no lo cumplían ni en 2D ni en 3D).
- [ ] Protocolo v2 (joystick + A/B): TV y celulares se actualizan juntos; ningún juego usa todavía A/B.
- [ ] APK: primera corrida real del job `apk` en GitHub (se probó completo en local); pesa ~61 MB (sin 32 bits, ~35 MB). Sin el secreto `ANDROID_DEBUG_KEYSTORE_BASE64`, cada APK nuevo pide desinstalar el anterior ([BUILD.md](BUILD.md)). Google TV: el lanzador de TV y el banner piden build con Gradle.
- [ ] Multitáctil del joystick A/B y "Salir" mantenido: probar en celular real.
- [ ] Música: confirmar en OpenGameArt y kenney.nl las licencias CC0 de los temas actuales (vinieron de repos espejo).
- [ ] Pantalla de Créditos dentro de la app (lo piden las licencias MIT/OFL/CC-BY) antes de publicar.
- [ ] Durante la intro de cada juego el celular no muestra "¡Mirá la TV!" (distinguirlo pide un cambio de protocolo).

## 6. Herramientas para revisar sin TV

- Capturas reales: `tools/capture_screens.gd` (también las sube la CI como artefacto de cada PR).
- Videos cortos: Godot graba cuadro por cuadro con `--write-movie` (probado; ver el lobby animado del 27/09). Pendiente si se quiere: herramienta que grabe 5–8 s de cada juego jugado por bots y los publique en el tablero.
- Tablero de avance: https://claude.ai/artifact/SZTee3B6GCL15wBnSdW795
