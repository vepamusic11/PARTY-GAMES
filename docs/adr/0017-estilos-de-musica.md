# ADR 0017 · Estilos de música: temas del dueño, generador propio y Relajado CC0

- **Estado:** Aceptada
- **Fecha:** 2026-09-27
- **Amplía:** [ADR 0015](0015-musica-y-mezcla.md) (música, buses y mezcla)

## Contexto
Con el ADR 0015 la TV tenía un solo estilo: chiptune CC0 de Juhani Junkala. Al dueño no le terminó de convencer y pidió **otra música o poder elegir**: algo tipo *party game* de consola, algo tranquilo y algo latino. Además hizo sus propios temas con Suno y los quiere en el juego, como estilo por defecto.

Restricciones:
- **Licencia sin dudas** (ver [RECURSOS.md](../RECURSOS.md)): CC0 o CC-BY con el texto del autor al lado del archivo. Nada de YouTube ni de "royalty free" sin texto. Las webs de música (OpenGameArt, itch.io, Free Music Archive) están bloqueadas desde el entorno de desarrollo; los clones y releases de GitHub sí andan.
- **Peso:** APK ≤ 40 MB ([PLAN.md](../PLAN.md)); hoy pesa ~35 MB sin 32 bits, y el presupuesto de música es ≤ 8 MB ([CALIDAD.md §3](../CALIDAD.md#3-audio)).
- **Rendimiento:** 60 fps en una TV de gama baja; nada de síntesis por cuadro.

## Decisión
**Un selector "Estilo" en la pausa de la TV, con seis opciones, y tres fuentes de música según el estilo.**

| Estilo | Fuente | Carácter | Peso |
|---|---|---|---|
| **PARTY-GAME** (por defecto) | Temas del dueño hechos con Suno: *Breakpoint Rush* en los juegos de acción; lugar listo para su tema del lobby. Lo que falta, de Fiesta | El del dueño | 2,2 MB |
| **Fiesta** | Generador propio (`MusicGen`) | Pop electrónico de consola: bombo en negras, bajo con octavas, acordes sincopados con "bombeo", melodía de campanita o pulso, 104–132 BPM, tonos mayores | 0 MB |
| **Latino** | Generador propio | Cumbia (güiro, congas, bajo "tum-tum-tum", teclado a contratiempo, acordeón), tropical con marimba y clave, y dembow liviano para la acción; 92–104 BPM | 0 MB |
| **Relajado** | 4 bucles CC0 de Abstraction (Benjamin Burnes) | Chillout / lo-fi / jazz suave | 2,3 MB |
| **Retro** | Los 6 chiptunes CC0 de Juhani Junkala (ADR 0015) | 8 bits | 3,3 MB |
| **Sin música** | — | Solo efectos | 0 MB |

- **`MusicStyles`** (`core/audio/music_styles.gd`): tabla de estilos. Cada estilo cubre las seis pistas de siempre (`lobby`, `game_calm`, `game_play`, `game_action`, `summary`, `podium`) con **archivos**, con **pistas generadas** o con un **respaldo** (`fallback`) a otro estilo. `resolve(estilo, pista)` devuelve `{"file"}`, `{"generated"}` o `{}` (silencio). Se guarda en `[audio] music_style` del archivo de ajustes de la TV; un valor inválido se ignora.
- **`Music`** cambia poco: `Music.play(pista)` resuelve el estilo actual; `Music.set_style(id)` aplica, guarda y pasa **la misma pantalla** al estilo nuevo con el fundido cruzado de siempre. Así se elige escuchando.
- **`MusicGen`** (`core/audio/music_gen.gd`): compositor y sintetizador de bucles de 16 compases por *receta* (tempo, tonalidad, progresión, batería, bajo, acompañamiento, colchón, melodía, arpegio) y *semilla*. La melodía es un motivo de 2 compases que se repite y varía (A A' A cierre | B B' A cierre), con notas del acorde en los tiempos fuertes y de la escala en los débiles. Instrumentos: bombo, caja, palmas, platillos, shaker, güiro, congas, cencerro, timbal, clave, bajo, piano eléctrico FM, celesta FM, marimba, cuerda pulsada (Karplus-Strong), pulso, bronces, colchón de sierras y acordeón (tablas de onda sin aliasing). Eco y reverberación "cebados" con el final para que el bucle no tenga costura; sonoridad pareja y limitador suave.
  - **Se compone al arrancar, en un hilo**: `Music` encola las pistas generadas del estilo elegido (primero la que se pidió, después lobby, juegos, resumen y podio) y lanza **una tarea de WorkerThreadPool por vez** para no quitarle núcleos al juego. Mientras una pista no está, **sigue sonando la anterior** y la nueva entra con fundido apenas termina. Nada se sintetiza en `_process`: ahí solo se pregunta si la tarea terminó.
  - Memoria: ~3 MB por pista (22 050 Hz estéreo, 16 bits). Al cambiar de estilo se sueltan las del estilo anterior.
- **Canciones del dueño** (temas con principio y final, no bucles): `tools/audio/prepare_audio.py` recorta la intro lenta, busca un **punto de vuelta en una frase** (dos pulsos cuya música siguiente se parece, afinado a la muestra por correlación de ataques: Breakpoint Rush vuelve cada 80 compases), funde 0,25 s el final con lo que suena antes de la vuelta y escribe `loop_offset` en el `.import`. Godot vuelve ahí sin clic, sin código extra.
- **Sonoridad común**: los estilos nuevos se igualan a −14,5 LUFS (BS.1770), que es lo que miden los Retro (−16 dB RMS); los generados apuntan a −16 dB RMS (≈ −14,2 LUFS). Diferencia entre estilos medida en las muestras: ≤ 1 dB.
- **Pausa**: una fila nueva, `MusicStyleStepper` ("◀ ● Estilo: Fiesta ▶"), debajo de los volúmenes. ◀ ▶ cambian, ▲ ▼ navegan; el nombre siempre está escrito y el punto de color (`UiTheme.music_style_color`) solo acompaña.

## Motivos
- **Temas del dueño primero:** es su juego y su identidad sonora. El estilo es el de por defecto y crece solo: cada tema nuevo es un `.ogg` más en `assets/audio/music/original/` y una línea en `MusicStyles`.
- **Generador para Fiesta y Latino:** no apareció música CC0/CC-BY de pop de consola ni de cumbia con el texto de licencia del autor al alcance (el "corpus CC0" más grande de GitHub mezcla fuentes sin el aviso de cada autor, y parte es CC-BY). Un generador da música 100 % propia —sin licencia que verificar ni riesgo de reclamos— y **0 MB**, que es lo único que cabe en el APK después de sumar los temas del dueño. Se controla el carácter (tempo, tonalidad mayor, patrones típicos del género) aunque el timbre sea sintetizado.
- **Abstraction para Relajado:** músico profesional, CC0 declarado en el aviso del pack que viaja con los archivos y en las etiquetas de los OGG. Cuatro archivos para seis pantallas (el resumen repite el de juegos tranquilos; el podio, el de movidos) para quedar dentro del presupuesto.
- **Una tarea por vez:** en una TV de cuatro núcleos, componer las seis pistas en paralelo competiría con el juego; en serie tarda más pero no se nota: lo que falta todavía no se necesita.

## Costo medido
- Composición de una pista de 16 compases (29–42 s de audio) en la PC de desarrollo (motor en modo editor): **2,4–3,4 s** (síntesis de notas ~0,4–0,8 s, mezcla ~1,0–1,5 s, efectos ~0,6–0,8 s, nivel final ~0,3 s). Un estilo entero: ~17 s en segundo plano. `tools/render_music.gd` imprime el desglose.
- Estimado en una TV de gama baja: 4–6 veces más lento (~10–20 s por pista). Solo la primera vez que suena un estilo generado: su primera pista puede tardar eso en entrar; mientras tanto sigue lo anterior o el suplente Retro. Después se lee de la caché en disco.
- Espacio en la TV: hasta 40 MB en `user://music_cache/` (tope de `MusicCache`).
- Peso agregado al APK: **4,5 MB** (Breakpoint Rush 2,2 + Relajado 2,3). Música total: **7,7 MB** (≤ 8 MB).

## Alternativas descartadas
- **Bajar audio de YouTube** o usar packs "royalty free" sin texto de licencia: la licencia no se puede verificar y bajar de YouTube viola sus términos.
- **SoundSafari/CC0-1.0-Music** (GitHub, ~9000 archivos): es un rejunte sin el aviso de cada autor; parte viene de sitios donde la licencia real es CC-BY. No cumple "texto del autor con el archivo".
- **Relajado también generado:** posible (piano eléctrico, swing y crujido de vinilo), pero un músico real suena mejor en lo tranquilo, donde el timbre se escucha más. Queda como plan B si el APK aprieta.
- ~~**Pistas generadas guardadas en disco**~~: se descartó al principio por el espacio (~3 MB por pista); se adoptó el 29/09/2026 (ver "Caché en disco y suplente").
- **Sintetizar pistas más cortas (8 compases):** la mitad del costo, pero se repiten el doble. Con 16 compases hay forma A/B y cierre de frase.
- **Tema del dueño para todas las pantallas desde ya:** un solo tema cansaría; mejor sumar temas a medida que los haga.

## Caché en disco y suplente (29/09/2026)
En una TV lenta cada pista generada tarda ~10–20 s: la primera vez que se prendía, el lobby podía quedar en silencio. Dos cambios:

- **`MusicCache`** (`core/audio/music_cache.gd`): cada pista compuesta se guarda en `user://music_cache/<estilo>_<pista>.pcm` (PCM de 16 bits estéreo, sin comprimir: el OGG no se puede codificar en el aparato). Medido en la PC: componer una pista de Fiesta 1,7–1,9 s; guardarla 4 ms; leerla ~1 ms (2,5–2,7 MB). En la TV la lectura depende de la memoria flash, pero es del orden de decenas de ms contra 10–20 s de componer. Desde el segundo arranque, el hilo de `Music` lee el archivo en vez de componer.
  - **Versión de receta**: el archivo lleva una *firma* (MD5 de la receta de la pista, las tablas compartidas de `MusicGen`, la frecuencia, los compases y `MusicGen.GEN_VERSION`). Si no coincide, es de una versión vieja: se borra y se compone de nuevo. `GEN_VERSION` hay que subirlo a mano solo al cambiar el **código** del sintetizador (los cambios de receta ya cambian la firma).
  - **Límite**: 40 MB entre todos los archivos (entran los dos estilos generados completos, ~12 pistas de 2,5–3,7 MB). Al guardar una pista se borran las más viejas hasta entrar.
  - **Nunca rompe**: un archivo vacío, cortado, con otro formato o con tamaños imposibles se descarta y se borra; la pista se compone como siempre. Se escribe a un temporal y se renombra, así un corte de luz no deja un archivo a medias con el nombre bueno. Lectura y escritura corren en el hilo, nunca en un cuadro.
- **Suplente** (`MusicStyles.STAND_IN` = Retro): si la pista pedida se está componiendo y **no suena nada** (TV recién prendida), suena la misma pantalla del estilo Retro, que viene en el APK; al estar lista la generada, entra con el fundido cruzado de siempre. Si ya sonaba otra pista (cambio de estilo en la pausa, cambio de pantalla), sigue esa, como antes. Con el jingle de entrada del lobby: jingle → suplente → generada.
- Tests: `test_music_cache` (caché válida, versión vieja descartada, archivos rotos, límite de tamaño, apagada) y `test_music_stand_in_and_cache` (suplente sin silencio, reemplazo con fundido y lectura desde disco en el "arranque siguiente"). Los tests usan su propia carpeta (`user://test_music_cache/`), nunca la de la TV.

## Consecuencias
- `test_audio_licenses` recorre las subcarpetas de `assets/audio/` y acepta `LICENSE*` CC0/CC-BY (sin NC ni ND) o `NOTICE*` del dueño, que tiene que nombrar a Suno y la condición de **plan pago** para uso comercial (también anotada en CREDITS.md). **Antes de vender el juego hay que confirmar que cada tema de Suno se hizo con plan pago**; si no, regenerarlo o sacarlo.
- Al llegar el tema del lobby del dueño: prepararlo con `prepare_audio.py` (sumarlo a `SONGS` con su punto de vuelta), copiarlo como `assets/audio/music/original/lobby.ogg`, completar su fila en CREDITS.md y el NOTICE. El código ya lo toma. Ojo con el peso: ~2 MB más deja la música en ~10 MB; habría que resignar algo (por ejemplo, Retro o Relajado a menor calidad).
- Un juego nuevo sigue usando `Music.GAME_TRACKS` (calma / movido / acción) y suena en todos los estilos sin cambios.
- Tests nuevos: `test_music_styles_resolve`, `test_music_style_prefs_and_selector`, `test_music_generator`, `test_music_generated_playback`, `test_music_song_loop`.
- Muestras para escuchar fuera del juego: `tools/render_music.gd` (WAV de cada pista generada y copia de los OGG).
