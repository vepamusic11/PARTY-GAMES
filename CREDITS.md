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
