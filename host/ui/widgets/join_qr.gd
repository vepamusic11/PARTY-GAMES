class_name JoinQr
extends Control
## QR grande del lobby con el enlace del control web (ADR 0022): el invitado
## lo escanea con la cámara del celular y se abre el navegador con el control.
##
## El QR se codifica UNA vez por texto (addons/pmc_qr, ~1 ms) como una
## textura de un píxel por módulo y se dibuja escalada con filtro "nearest",
## a un entero de píxeles por módulo: módulos nítidos, sin borrosidad, y el
## costo por cuadro es un draw_texture_rect (docs/PERFORMANCE.md). Se
## regenera solo si cambia el texto (otro código de sala u otra IP).
##
## Tinta sobre papel (UiTheme.INK / PAPER, contraste ~15:1) con un margen
## claro: QUIET_ZONE módulos en la textura más el marco blanco y el panel
## blanco del lobby alrededor (los lectores piden ≥ 4 módulos claros).
## Corrección de errores M (se pierde hasta ~15 % de los módulos, ej. un
## reflejo, y sigue leyéndose).

const QUIET_ZONE := 3
const ECC := PMCQr.ECC_M
const FRAME_RADIUS := 22.0

var text := ""
var _tex: ImageTexture
var _modules := 0  # Lado del QR en módulos (sin margen).


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST


## Cambia el enlace. Un texto vacío o que no entra en un QR deja el marco vacío.
func set_text(p_text: String) -> void:
	if p_text == text and (_tex != null or p_text.is_empty()):
		return
	text = p_text
	_tex = null
	_modules = 0
	if not text.is_empty():
		var m := PMCQr.encode(text, ECC)
		if m != null:
			_modules = m.size
			_tex = ImageTexture.create_from_image(to_image(m))
	queue_redraw()


func has_code() -> bool:
	return _tex != null


## Versión del QR (1..40) o 0 si no hay. La típica del enlace del lobby es 2 o 3.
func version() -> int:
	return (_modules - 17) / 4 if _modules > 0 else 0


## Imagen de un píxel por módulo, con el margen claro incluido.
static func to_image(m: PMCQrMatrix) -> Image:
	var side := m.size + QUIET_ZONE * 2
	var img := Image.create(side, side, false, Image.FORMAT_RGB8)
	img.fill(UiTheme.PAPER)
	for y in m.size:
		for x in m.size:
			if m.get_module(x, y):
				img.set_pixel(x + QUIET_ZONE, y + QUIET_ZONE, UiTheme.INK)
	return img


## Píxeles por módulo con los que se dibuja (entero: módulos nítidos).
func module_px() -> int:
	if _tex == null:
		return 0
	return maxi(1, int(minf(size.x, size.y)) / (_modules + QUIET_ZONE * 2))


func _draw() -> void:
	var frame := Rect2(Vector2.ZERO, size)
	UiTheme.draw_round_rect(self, frame, UiTheme.PAPER, FRAME_RADIUS, 3.0, Color(UiTheme.INK_SOFT, 0.25))
	if _tex == null:
		return
	var px := module_px()
	var side := float(px * (_modules + QUIET_ZONE * 2))
	var at := (size - Vector2(side, side)) / 2.0
	draw_texture_rect(_tex, Rect2(at.round(), Vector2(side, side)), false)
