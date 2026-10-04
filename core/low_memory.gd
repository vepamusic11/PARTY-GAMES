class_name LowMemory
extends RefCounted
## Perfil "TV de poca memoria" (ADR 0023): en una Google TV con ~2 GB de RAM
## (ej. Xiaomi TV Stick 4K) la app gasta menos memoria sin cambiar cómo se
## ve. Se prende solo en Android con ≤ RAM_LIMIT_BYTES de RAM (o si no se
## sabe cuánta tiene), o a mano con
## `-- --low-memory` (para medirlo en la PC); `-- --no-low-memory` lo apaga.
## En la PC (sin la bandera) no cambia nada.
##
## Qué hace (medido en docs/PERFORMANCE.md → "TV de poca memoria"):
## - **Letras**: cada tamaño de letra (y cada contorno) que se dibuja deja un
##   caché de glifos con su textura (≥ 65 px: 1024×1024, 2 MB en la placa y
##   otros 2 MB en la RAM). Una competencia junta ~60 combinaciones (títulos,
##   cuentas regresivas, carteles de cada juego): ~120 MB. Al cambiar de
##   pantalla (con el barrido tapando todo) se sueltan los tamaños grandes
##   (> FONT_KEEP_PX); la pantalla nueva vuelve a armar solo los que usa.
##   Los textos que se agrandan con una animación se dibujan a un tamaño fijo
##   y se escalan con la transformación (draw_text_sized): un caché, no 24.
## - **Mascotas**: presupuesto del atlas MASCOT_BUDGET en vez de 40 MB. Lo
##   que se suelta vuelve del disco en unos ms (MascotDiskCache), no se
##   vuelve a hornear.
## - **Lobby**: al irse del lobby se sueltan los dioramas de las tarjetas y el
##   logo (≈ 11 MB); al volver se leen otra vez (unos ms).
## - **Tableros 2.5D**: fuera de los juegos se sueltan los que nadie dibuja.

const ARG_ON := "--low-memory"
const ARG_OFF := "--no-low-memory"
## RAM total hasta la que se considera "poca" (un aparato de 3 GB informa un
## poco menos: se deja margen).
const RAM_LIMIT_BYTES := 3 * 1024 * 1024 * 1024 + 256 * 1024 * 1024
## Presupuesto del atlas de mascotas con el perfil (MascotAtlas.BUDGET_BYTES = 40 MB).
const MASCOT_BUDGET := 24 * 1024 * 1024
## Tamaños de letra que se conservan al cambiar de pantalla (los chicos son
## baratos, 128–512 KB, y los usa casi toda pantalla).
const FONT_KEEP_PX := 32

## Perfil activo (lo decide HostMain al arrancar: ver apply).
static var active := false
## Estadística: tamaños de letra soltados (para medir).
static var fonts_released := 0


## ¿Va el perfil? Datos puros para poder probarlo: argumentos de la línea de
## comandos, nombre del sistema (OS.get_name()) y RAM física en bytes (-1 si
## no se sabe).
static func should_enable(args: PackedStringArray, os_name: String, physical_ram: int) -> bool:
	if ARG_OFF in args:
		return false
	if ARG_ON in args:
		return true
	# RAM desconocida en Android (-1): se prende igual. La TV es Android y el
	# perfil no cambia cómo se ve; mejor de más que quedarse sin memoria.
	return os_name == "Android" and physical_ram <= RAM_LIMIT_BYTES


## Lo mismo con los datos de este aparato.
static func detect() -> bool:
	var args := OS.get_cmdline_args()
	args.append_array(OS.get_cmdline_user_args())
	return should_enable(args, OS.get_name(), int(OS.get_memory_info().get("physical", -1)))


## Prende o apaga el perfil (presupuestos de los cachés).
static func apply(on: bool) -> void:
	active = on
	MascotAtlas.budget_bytes = MASCOT_BUDGET if on else MascotAtlas.BUDGET_BYTES


## La TV cambió de pantalla (lo llama HostMain con el barrido tapando todo).
## `in_game`: hay un juego en curso o por empezar (su tablero no se suelta).
static func on_screen_changed(in_game: bool) -> void:
	if not active:
		return
	purge_fonts()
	if not in_game:
		Board25DBaker.release_unused()


## Suelta los cachés de glifos de más de `keep_px` de las letras del juego.
## Lo que se vuelva a dibujar se arma de nuevo solo. Devuelve cuántos soltó.
static func purge_fonts(keep_px: int = FONT_KEEP_PX) -> int:
	var n := 0
	for f: Font in [UiTheme.FONT_BOLD, UiTheme.FONT_SEMI]:
		var ff := f as FontFile
		if ff == null:
			continue
		for c in ff.get_cache_count():
			for sz: Vector2i in ff.get_size_cache_list(c):
				if sz.x > keep_px:
					ff.remove_size_cache(c, sz)
					n += 1
	fonts_released += n
	return n


## Texto centrado de tamaño animado (ej. un cartel que "late" de 76 a 87 px).
## Sin el perfil se dibuja a `px`, como siempre. Con el perfil se dibuja a
## `base` px y se escala a px/base con la transformación: un solo caché de
## glifos en vez de uno por tamaño. Deja la transformación de dibujo en la
## identidad (usarlo donde no hay otra puesta).
static func draw_text_sized(ci: CanvasItem, text: String, center: Vector2, px: int, base: int,
		color: Color, outline: int = 0, outline_color: Color = UiTheme.INK) -> void:
	if not active or base <= 0 or px == base:
		UiTheme.draw_text(ci, text, center, px, color, outline, outline_color)
		return
	var k := float(px) / base
	ci.draw_set_transform(center, 0.0, Vector2(k, k))
	UiTheme.draw_text(ci, text, Vector2.ZERO, base, color, outline, outline_color)
	ci.draw_set_transform(Vector2.ZERO)
