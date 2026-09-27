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

## Sonido y música

*Todavía nada de terceros: los efectos se sintetizan por código ([ADR 0005](docs/adr/0005-sonido-sintetizado.md)).* Formato de fila: archivo · pack · autor · licencia · enlace.

| Archivo | Pack | Autor | Licencia | Origen |
|---|---|---|---|---|

## Imágenes e íconos

*Todavía nada de terceros: mascotas, fondos e íconos se dibujan por código. Los logos de `assets/brand/` son propios (ver [TRADEMARKS.md](TRADEMARKS.md)).*

| Archivo | Pack | Autor | Licencia | Origen |
|---|---|---|---|---|
