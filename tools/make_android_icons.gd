extends SceneTree
## Genera los íconos del lanzador de Android a partir del logo de la marca
## (`assets/brand/party_game_logo.png`) y los colores del cielo de `UiTheme`.
## El preset "Android" de `export_presets.cfg` los usa; se regeneran solo si
## cambia el logo o la paleta:
##
##   godot --headless --path . -s res://tools/make_android_icons.gd
##   godot --headless --path . --import   # para que Godot vea los PNG nuevos
##
## Salida (en `assets/brand/android/`):
##   icon_192.png                 ícono clásico (Android 7 y anteriores)
##   icon_foreground_432.png      ícono adaptable: logo sobre transparente
##   icon_background_432.png      ícono adaptable: fondo de cielo
##   icon_monochrome_432.png      ícono temático (Android 13+): solo las letras
##                                claras del logo, en blanco; el sistema lo tiñe.
##                                Sin él, Android mostraría el robot de Godot.
##
## Concepto — *ícono adaptable*: desde Android 8 el lanzador recorta el ícono
## con la forma que elija el fabricante (círculo, gota, cuadrado). Del lienzo
## de 432 px se ve como mucho el centro de 288 (72 dp), y la máscara más chica
## es un círculo de ese diámetro. El logo es apaisado (2,7 : 1): va inscripto
## en ese círculo, de ~270 px de ancho; lo que queda afuera de sus esquinas es
## solo el brillo transparente del logo, no las letras.
##
## Funciona con --headless: solo arma Images y las guarda, no dibuja.

const OUT_DIR := "res://assets/brand/android"
const ADAPTIVE_SIZE := 432
const VISIBLE_DIAMETER := 288.0  ## Círculo visible con la máscara más chica (72 dp de 108).
const LEGACY_SIZE := 192
const LEGACY_RADIUS := 36.0    ## Esquinas redondeadas del ícono clásico.
const LEGACY_LOGO_WIDTH := 176


func _initialize() -> void:
	var logo := Image.load_from_file(ProjectSettings.globalize_path(UiTheme.LOGO_PATH))
	if logo == null or logo.is_empty():
		printerr("No se pudo leer el logo: %s" % UiTheme.LOGO_PATH)
		quit(1)
		return
	logo.convert(Image.FORMAT_RGBA8)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))

	var background := _sky(ADAPTIVE_SIZE)
	# Ancho del rectángulo apaisado inscripto en el círculo visible.
	var aspect := float(logo.get_width()) / float(logo.get_height())
	var fg_width := int(VISIBLE_DIAMETER / sqrt(1.0 + 1.0 / (aspect * aspect)))
	var foreground := Image.create_empty(ADAPTIVE_SIZE, ADAPTIVE_SIZE, false, Image.FORMAT_RGBA8)
	_paste_centered(foreground, logo, fg_width)

	var monochrome := Image.create_empty(ADAPTIVE_SIZE, ADAPTIVE_SIZE, false, Image.FORMAT_RGBA8)
	_paste_centered(monochrome, _silhouette(logo), fg_width)

	var legacy := _sky(LEGACY_SIZE)
	_paste_centered(legacy, logo, LEGACY_LOGO_WIDTH)
	_round_corners(legacy, LEGACY_RADIUS)

	var ok := true
	for item: Array in [
		["icon_192.png", legacy],
		["icon_foreground_432.png", foreground],
		["icon_background_432.png", background],
		["icon_monochrome_432.png", monochrome],
	]:
		var path := OUT_DIR.path_join(item[0])
		var err := (item[1] as Image).save_png(path)
		print(("  ok    " if err == OK else "  FALLA ") + path)
		ok = ok and err == OK
	quit(0 if ok else 1)


## Degradé vertical del cielo del juego (mismos tokens que el fondo de la TV).
static func _sky(size: int) -> Image:
	var img := Image.create_empty(size, size, false, Image.FORMAT_RGBA8)
	for y in size:
		var c := UiTheme.BG_SKY_TOP.lerp(UiTheme.BG_SKY_MID, float(y) / float(size - 1))
		img.fill_rect(Rect2i(0, y, size, 1), c)
	return img


## Pega `logo` escalado a `width` px de ancho, centrado y mezclado con alfa.
static func _paste_centered(dst: Image, logo: Image, width: int) -> void:
	var scaled := logo.duplicate() as Image
	var height := int(round(float(width) * logo.get_height() / logo.get_width()))
	scaled.resize(width, height, Image.INTERPOLATE_LANCZOS)
	var pos := Vector2i((dst.get_width() - width) / 2, (dst.get_height() - height) / 2)
	dst.blend_rect(scaled, Rect2i(Vector2i.ZERO, scaled.get_size()), pos)


## Silueta para el ícono temático: blanco donde el logo es claro (letras,
## corona, destellos) y transparente en el contorno oscuro y el brillo, así
## las letras se separan entre sí en vez de quedar un solo manchón.
static func _silhouette(logo: Image) -> Image:
	var out := Image.create_empty(logo.get_width(), logo.get_height(), false, Image.FORMAT_RGBA8)
	for y in logo.get_height():
		for x in logo.get_width():
			var c := logo.get_pixel(x, y)
			var a := clampf((c.get_luminance() - 0.35) / 0.25, 0.0, 1.0) * c.a
			out.set_pixel(x, y, Color(1, 1, 1, a))
	return out


## Vuelve transparentes las esquinas (con medio píxel de suavizado).
static func _round_corners(img: Image, radius: float) -> void:
	var size := img.get_width()
	for y in size:
		for x in size:
			var cx := clampf(x + 0.5, radius, size - radius)
			var cy := clampf(y + 0.5, radius, size - radius)
			var d := Vector2(x + 0.5 - cx, y + 0.5 - cy).length()
			if d > radius - 0.5:
				var c := img.get_pixel(x, y)
				c.a *= clampf(radius + 0.5 - d, 0.0, 1.0)
				img.set_pixel(x, y, c)
