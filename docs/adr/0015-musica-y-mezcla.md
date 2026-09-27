# ADR 0015 · Música CC0, buses de mezcla y logos sonoros sintetizados

- **Estado:** Aceptada
- **Fecha:** 2026-09-27
- **Amplía:** [ADR 0005](0005-sonido-sintetizado.md) (efectos sintetizados)

## Contexto
La TV no tenía música: en el lobby, el silencio se siente como "esto no arrancó" ([CALIDAD.md §3](../CALIDAD.md#3-audio)). Tampoco había canales separados: efectos y (futura) música salían por el mismo bus, sin forma de bajar uno sin el otro ni de que el "¡YA!" se oiga claro por encima de un tema. Faltaba además una identidad sonora para el estudio (IO-GAMES) y el juego (PARTY-GAME).

Se evaluaron dos caminos: **Plan A**, música real con licencia libre verificada; **Plan B**, un secuenciador chiptune propio que compone por código. Desde el entorno de desarrollo, las webs de los autores (OpenGameArt, kenney.nl, archive.org) están bloqueadas, pero sí se pueden clonar repositorios públicos de GitHub.

## Decisión
**Plan A para la música y los efectos de menú; síntesis propia solo para los logos sonoros.**

- **Música:** 6 bucles chiptune de **Juhani Junkala, CC0**, tomados de dos repositorios públicos que incluyen el `INFO.txt` original del autor con la licencia ("released under CC0"). Van en `assets/audio/music/` como OGG Vorbis con nombre de *función*, no de tema (`lobby.ogg`, `game_action.ogg`…): cambiar un tema no toca código. Cada carpeta lleva el texto de licencia original y cada archivo figura en `CREDITS.md`.
  - Una pista por pantalla: lobby, resumen, podio, y los juegos **agrupados por energía** (`Music.GAME_TRACKS`): *calma/precisión* (Reloj exacto, Ping Pong), *movido* (Arena, Pintar el piso) y *acción* (Esquivar, Empujones, Carrera de toques). Un juego nuevo sin grupo usa "movido".
  - Preparación reproducible con `tools/audio/prepare_audio.py`: misma sonoridad (−16 dB RMS, pico ≤ −1,4 dBFS), rampa de 6 ms en la costura del bucle para que no haga clic, OGG a calidad media. Total de `assets/audio/`: **3,3 MB** (4 min 9 s de música).
- **Efectos:** los tres de navegación (`tick`, `select`, `back`), que son los que más suenan y donde la onda cuadrada cansaba, pasan a clics de **Kenney Interface Sounds (CC0)**. `core/audio/sfx_files.gd` mapea nombre → archivo; `Sfx` los carga al iniciar y, si falta el archivo, queda la receta. Las llamadas `Sfx.play(...)` no cambian.
- **Logos sonoros compuestos para el juego** (`core/audio/jingles.gd`): IO-GAMES (1,75 s) en la presentación y PARTY-GAME (1,85 s) al llegar al lobby. Son partituras cortas (melodía, acorde, bajo y percusión) sintetizadas una vez y guardadas en memoria. Un jingle de banco no sirve como marca: cualquiera lo puede usar.
- **Buses por código** (`core/audio/audio_mix.gd`, `AudioMix`): `Master` → `Music` y `SFX`. Volumen de cada uno en la pausa de la TV (`VolumeStepper`, ◀ ▶ de a 10 %), guardado en `[audio] music_volume / sfx_volume` del archivo de ajustes. "Sonido: No" silencia `Master` y pausa la música.
- **`Music`** (`core/audio/music.gd`), nodo en `HostMain` con API estática como `Sfx`: `Music.play(pista, jingle_de_entrada)`, `Music.jingle(nombre)`, `Music.duck()`.
  - **Fundido cruzado** lineal de 0,8 s con dos reproductores: la suma de los volúmenes nunca pasa de 1.
  - **Bucle sin cortes:** `AudioStreamOggVorbis.loop` (precisión de muestra).
  - **Ducking:** `Sfx.play` avisa a `Music.on_sfx`; `go`, `win`, `fanfare`, `hit` y `lose` bajan la música 6 dB durante 0,3 s y vuelve en 0,4 s. Un jingle la baja 12 dB mientras suena.
- **Celular sin música:** `ControllerMain` no crea `Music` (batería, y la música ya suena en la TV). Sigue respetando su ajuste "Sonido" (`Sfx.muted`).

## Motivos
- Calidad: temas compuestos por un músico profesional suenan mejor que cualquier secuenciador que podamos escribir en días, y el estilo chiptune combina con los efectos sintetizados (ADR 0005).
- Licencia sin dudas: CC0 verificado en el texto del autor que viaja con los archivos; no hay atribución obligatoria ni restricción comercial. Si un tema no convence, se reemplaza el `.ogg` y su fila en `CREDITS.md`.
- Rendimiento: el OGG se decodifica en el hilo de audio, no en Scripts. `Music` solo corre `_process` durante un fundido o ducking; el resto del tiempo está apagado. Los jingles se sintetizan una vez en un hilo aparte (~70–100 ms cada uno en PC) y quedan en caché.

## Alternativas descartadas
- **Plan B completo (música generada por código):** cero riesgo de licencia, pero bucles de 30–60 s de un secuenciador simple suenan repetitivos y "de prueba". Se usa solo para los logos sonoros, donde la brevedad y la exclusividad importan más.
- **Kenney Music Jingles para los logos:** CC0 y de buena calidad, pero no son exclusivos: no identifican a la marca.
- **Packs JRPG de Juhani Junkala (orquestales):** CC0 también, pero rompen la estética chiptune.
- **`default_bus_layout.tres`:** otro archivo que mantener a mano; los buses por código son 10 líneas y los tests los verifican.
- **Música en el celular:** gasta batería y compite con la TV.

## Consecuencias
- El APK crece ~3,3 MB (presupuesto de música ≤ 8 MB en [CALIDAD.md §3.3](../CALIDAD.md#33-fuentes-cc0-ver-recursosmd)).
- Cada archivo nuevo en `assets/audio/` necesita su licencia al lado y su fila en `CREDITS.md`; lo verifica `test_audio_licenses`.
- Un juego nuevo puede sumarse a un grupo en `Music.GAME_TRACKS`; si no, suena "movido".
- `tools/render_music.gd` exporta los jingles a WAV y copia las pistas para escucharlas fuera del juego.
- Pendiente: *stinger* en la intro de cada juego, capa extra en los últimos 10 s y normalización en LUFS (hoy RMS).
