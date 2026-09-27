# Créditos y licencias de terceros

Todo lo que el juego usa y **no** escribimos nosotros va anotado acá: código, addons, fuentes, sonidos, música e imágenes. Qué licencias se aceptan y cómo se eligió cada recurso: [docs/RECURSOS.md](docs/RECURSOS.md).

**Regla:** nada de terceros entra al repositorio sin su fila en esta tabla y su archivo de licencia al lado (en la carpeta del recurso). Una licencia MIT, BSD u OFL exige que el aviso de copyright viaje **con el juego**: antes de publicar (Fase D) esta lista tiene que verse también dentro de la app (pantalla "Créditos" en la pausa o en ajustes).

*Ejemplo:* si sumamos "click.ogg" del pack Interface Sounds de Kenney (CC0), agregamos una fila con el archivo, el autor, la licencia y el enlace. CC0 no obliga a dar crédito, pero lo anotamos igual para saber de dónde salió cada archivo.

## Motor

| Qué | Autor | Licencia | Dónde |
|---|---|---|---|
| Godot Engine 4.4.1 (y sus bibliotecas: FreeType, ENet, mbedTLS, etc.) | Juan Linietsky, Ariel Manzur y colaboradores de Godot | MIT (+ las de cada biblioteca) | [godotengine.org/license](https://godotengine.org/license) · el texto completo sale de `Engine.get_license_text()` y `Engine.get_copyright_info()` para la pantalla de créditos |

## Código y addons

| Qué | Versión | Autor | Licencia | Dónde está | Origen |
|---|---|---|---|---|---|
| Codificador QR `PMCQr` (`qr.gd`, `qr_matrix.gd`, copiados sin cambios de `addons/phone_mass_controllers/qr/`) | commit `8c87cb6` (14/09/2026) | splatterfacegames | MIT | `addons/pmc_qr/` ([LICENSE](addons/pmc_qr/LICENSE)) | [splatterfacegames/godot-phone-mass-controllers](https://github.com/splatterfacegames/godot-phone-mass-controllers) |

## Fuentes

| Qué | Autor | Licencia | Dónde está | Origen |
|---|---|---|---|---|
| Fredoka (SemiBold y Bold) | The Fredoka Project Authors (Milena Brandão, Hafontia) | SIL Open Font License 1.1 | `assets/fonts/` ([OFL.txt](assets/fonts/OFL.txt)) | [google/fonts · ofl/fredoka](https://github.com/google/fonts/tree/main/ofl/fredoka) |

## Música

### Retro (ADR 0015)

Juhani Junkala · <https://juhanijunkala.com/> · **CC0 1.0** (dominio público; el crédito es opcional y lo damos igual). Texto original de la licencia en `assets/audio/music/LICENSE-Juhani-Junkala-*.txt`.

| Archivo | Tema original | Pack | Dónde suena |
|---|---|---|---|
| `assets/audio/music/lobby.ogg` | Stage Select | Chiptune Adventures | Lobby |
| `assets/audio/music/game_calm.ogg` | Stage 1 | Chiptune Adventures | Reloj exacto, Ping Pong |
| `assets/audio/music/game_play.ogg` | Stage 2 | Chiptune Adventures | Arena, Pintar el piso (y juegos nuevos sin grupo) |
| `assets/audio/music/game_action.ogg` | Level 1 | Retro Game Music Pack (5 Action Chiptunes) | Esquivar, Empujones, Carrera de toques |
| `assets/audio/music/summary.ogg` | Title Screen | Retro Game Music Pack (5 Action Chiptunes) | Resumen de la ronda |
| `assets/audio/music/podium.ogg` | Ending | Retro Game Music Pack (5 Action Chiptunes) | Podio |

Origen verificado (26/09/2026), con el `INFO.txt` del autor dentro de cada carpeta ("These music tracks have been released under CC0 creative commons license"):

- Chiptune Adventures (OGG): repositorio [PacktPublishing/Game-Development-Patterns-with-Godot-4](https://github.com/PacktPublishing/Game-Development-Patterns-with-Godot-4), commit `1b68c8c`, carpeta `12.cross-fading-with-service-locator/01.start/Assets/Juhani Junkala [Chiptune Adventures] OGG/`.
- Retro Game Music Pack (WAV): repositorio [excaliburjs/sample-tactics](https://github.com/excaliburjs/sample-tactics), commit `bfe18ba`, carpeta `res/5 Action Chiptunes By Juhani Junkala/`. Publicado originalmente en [OpenGameArt](https://opengameart.org/content/5-chiptunes-action).

Cambios: nivel de sonoridad común, rampa de 6 ms en la costura del bucle y recodificado a OGG Vorbis (`tools/audio/prepare_audio.py`).

### Estilos de música (ADR 0017)

La TV elige el estilo en la pausa ("Estilo: …"). Retro es la tabla de arriba; **Fiesta** y **Latino** los compone y sintetiza el juego por código (`core/audio/music_gen.gd`): son propios, no usan archivos de nadie.

#### Relajado · Abstraction (Benjamin Burnes / Tallbeard Studios) · **CC0 1.0**

Del *Music Loop Bundle* de Abstraction · <https://abstractionmusic.com/> · <https://tallbeard.itch.io/music-loop-bundle>. Texto original de la licencia, copiado sin cambios (solo los finales de línea pasan a LF), en `assets/audio/music/relajado/LICENSE-Abstraction-Music-Loop-Bundle.txt` ("This asset bundle is licensed as Public Domain (CC-0 …)"). El autor aclara que, aunque la licencia lo permite, no avala su uso en proyectos de NFT, IA/aprendizaje automático o reventa de los archivos sin cambios: no es una restricción de CC0 y un juego no entra en esos casos.

| Archivo | Tema original (etiquetas del autor) | Dónde suena |
|---|---|---|
| `assets/audio/music/relajado/lobby.ogg` | Sketchbook 2024-09-25 (Jazz / lo-fi) | Lobby |
| `assets/audio/music/relajado/calm.ogg` | Sketchbook 2024-12-04 (Chillout) | Juegos tranquilos y resumen de la ronda |
| `assets/audio/music/relajado/groove.ogg` | Sketchbook 2024-11-30 (New Age) | Juegos movidos y podio |
| `assets/audio/music/relajado/action.ogg` | Sketchbook 2024-07-03 (Chillout) | Juegos de acción |

Origen verificado (27/09/2026): release `music-v1` del repositorio [jfpx/cc0-media-library](https://github.com/jfpx/cc0-media-library) (commit `1494e02`), archivo `music-cc0.zip` (sha256 `f76258c8…172cc`, igual al de su `SHA256SUMS.txt`). El ZIP trae los OGG originales sin recodificar —con las etiquetas del autor adentro: ARTIST "Abstraction", COMPOSER "Benjamin Burnes"— y los avisos de licencia del autor byte a byte. Ids en el catálogo: `abstraction-4e6836606331898f144502c1`, `-d20307161d504210a0dd287e`, `-9ccab202734d1e91a94d3042`, `-f23d9e696a256a1881c5d216`. La web del autor (itch.io) está bloqueada desde el entorno de desarrollo; el CC0 del pack figura también en su página según buscadores. Cambios: sonoridad igualada (−14,5 LUFS), rampa de 6 ms en la costura y recodificado a OGG Vorbis de ~62 kbps (`tools/audio/prepare_audio.py`).

#### PARTY-GAME · temas del dueño del proyecto (hechos con Suno)

No son de terceros ni CC0. Aviso con autoría y condiciones en `assets/audio/music/original/NOTICE-PARTY-GAME-temas-del-dueno.txt`.

| Archivo | Tema | Autor | Origen | Dónde suena |
|---|---|---|---|---|
| `assets/audio/music/original/breakpoint_rush.ogg` | Breakpoint Rush | 666monko6666 (el dueño) | Hecho con Suno · id `53a987a6-6cf1-477a-b3e2-264545df30ad` · <https://suno.com/song/53a987a6-6cf1-477a-b3e2-264545df30ad> | Juegos de acción (Esquivar, Empujones, Carrera de toques) |
| `assets/audio/music/original/lobby.ogg` *(pendiente)* | Tema del lobby | 666monko6666 | Suno (anotar id y enlace al sumarlo) | Lobby; mientras falte, suena el de Fiesta |

**Condición:** requiere que el tema se haya creado con plan pago de Suno para uso comercial (Pro o Premier: la canción es del usuario y se puede usar comercialmente). Con el plan gratis, Suno solo permite uso no comercial. Confirmar el plan de cada tema antes de vender el juego. Cambios: recorte desde 12,94 s, bucle de 80 compases que vuelve a los 33,08 s del original con fundido de 0,25 s, sonoridad −14,5 LUFS y OGG Vorbis de ~120 kbps (`tools/audio/prepare_audio.py`).

## Efectos de sonido

Kenney (<https://www.kenney.nl>) · pack **Interface Sounds** · **CC0 1.0**. Texto original en `assets/audio/sfx/LICENSE-Kenney-Interface-Sounds.txt`.

| Archivo | Original | Reemplaza la receta |
|---|---|---|
| `assets/audio/sfx/ui_tick.ogg` | `tick_004.ogg` | `tick` (mover el foco) |
| `assets/audio/sfx/ui_select.ogg` | `select_002.ogg` | `select` (confirmar) |
| `assets/audio/sfx/ui_back.ogg` | `back_004.ogg` | `back` (volver) |

Origen verificado (26/09/2026): repositorio [lavenderdotpet/CC0-Public-Domain-Sounds](https://github.com/lavenderdotpet/CC0-Public-Domain-Sounds), commit `f2b6264`, carpeta `kenney_interfacesounds/` con el `License.txt` de Kenney ("License: (Creative Commons Zero, CC0)"). Cambios: mono y volumen ajustado a los efectos sintetizados.

El resto de los efectos y los jingles de marca (IO-GAMES, PARTY-GAME) están sintetizados por código en el proyecto (`core/audio/sfx.gd`, `core/audio/jingles.gd`).

## Imágenes e íconos

*Todavía nada de terceros: mascotas, fondos e íconos se dibujan por código. Los logos de `assets/brand/` son propios (ver [TRADEMARKS.md](TRADEMARKS.md)).*

| Archivo | Pack | Autor | Licencia | Origen |
|---|---|---|---|---|
