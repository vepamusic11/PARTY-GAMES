class_name TvLogoTitle
extends Control
## Título "de logo" (el nombre del juego en la intro): letras amarillas con
## brillo arriba y tono naranja abajo, contorno de tinta, borde blanco por
## fuera y sombra dura, como el logo de PARTY-GAME.
##
## El degradé de las letras se arma sin shaders: el relleno base se dibuja
## una vez y encima dos franjas recortadas (clip_contents) vuelven a dibujar
## el relleno con otro color, solo en la parte de arriba y en la de abajo.
## Todo es estático: se dibuja al cambiar el texto o el tamaño, no por frame.
##
## Si el nombre no entra en el ancho, la letra se achica (nunca < 48 px).

const MIN_SIZE := 48
const BAND_TOP := 0.47     ## Hasta dónde llega el brillo (fracción del alto del control).
const BAND_BOTTOM := 0.6   ## Desde dónde va el tono de abajo.

var text := "":
	set(v):
		text = v
		_refresh()
var font_size := UiTheme.INTRO_TITLE_SIZE:
	set(v):
		font_size = v
		custom_minimum_size.y = v * 1.55
		_refresh()

var _px := UiTheme.INTRO_TITLE_SIZE
var _top: Control
var _bottom: Control


func _init(p_text: String = "", p_size: int = UiTheme.INTRO_TITLE_SIZE) -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_top = _band(UiTheme.TITLE_FILL_TOP)
	_bottom = _band(UiTheme.TITLE_FILL_BOTTOM)
	font_size = p_size
	text = p_text
	resized.connect(_refresh)


func _band(col: Color) -> Control:
	var band := Control.new()
	band.clip_contents = true
	band.mouse_filter = Control.MOUSE_FILTER_IGNORE
	band.draw.connect(func() -> void:
		var font := UiTheme.FONT_BOLD
		var center := size / 2.0 - band.position
		var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, _px).x
		var pos := Vector2(center.x - w / 2.0, center.y + (font.get_ascent(_px) - font.get_descent(_px)) / 2.0)
		band.draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, _px, col))
	add_child(band)
	return band


## Tamaño de letra que entra en el ancho disponible (con el borde blanco).
func fitted_size() -> int:
	var px := font_size
	var avail := size.x
	if avail <= 0.0:
		return px
	while px > MIN_SIZE and UiTheme.FONT_BOLD.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x \
			+ px * UiTheme.TITLE_RIM_RATIO * 2.0 > avail:
		px -= 4
	return px


func _refresh() -> void:
	_px = fitted_size()
	pivot_offset = size / 2.0
	var h := size.y
	_top.position = Vector2.ZERO
	_top.size = Vector2(size.x, h * BAND_TOP)
	_bottom.position = Vector2(0, h * BAND_BOTTOM)
	_bottom.size = Vector2(size.x, h * (1.0 - BAND_BOTTOM))
	queue_redraw()
	_top.queue_redraw()
	_bottom.queue_redraw()


func _draw() -> void:
	UiTheme.draw_logo_text(self, text, size / 2.0, _px)
