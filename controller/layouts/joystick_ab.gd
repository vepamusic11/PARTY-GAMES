class_name JoystickAB
extends Control
## Joystick + botones A y B, como un control de consola (layout
## "joystick_ab"). Diestro: joystick a la izquierda y botones a la derecha;
## con `left_handed` (modo zurdo) se invierte todo en espejo.
##
## Reusa las piezas de los otros layouts para que se vea igual: un
## VirtualJoystick (flotante dentro de su mitad) y dos BigButton (aro de
## arcade, bisel, brillo, squash y onda al tocar). A lleva el color del
## jugador y es el más grande (acción principal); B es neutro.
##
## Multitouch real: cada dedo se asigna al tocar (joystick, A o B según la
## zona) y sigue yendo al mismo lugar hasta que se levanta, igual que el
## "touch focus" de Godot. Así se puede caminar con un pulgar y apretar A,
## B o los dos con el otro. Toda la zona de botones cuenta: el dedo va al
## botón más cercano, para no tener que mirar el celular.
##
## `value` y `buttons` cambian en el mismo evento táctil (sin latencia); lo
## que manda el celular lo arma ControllerMain: axis = value, btn = buttons.

## Fracción del ancho que ocupa el joystick; el resto es de los botones.
const STICK_SHARE := 0.54
## Radio de la cara de A y B respecto del alto (se recorta a MIN/MAX).
const A_SHARE := 0.19
const B_SHARE := 0.16
## Diámetro mínimo de cada botón: ≥ 128 px (se acierta sin mirar).
const MIN_BUTTON_RADIUS := 64.0
const MAX_BUTTON_RADIUS := 230.0
## BigButton dibuja la cara con radio = lado × 0,36 y el aro hasta × 1,24.
const _BIG_BUTTON_FACE := 0.36
const _HOUSING := 1.24
const CAPTION_SIZE := 34
const CAPTION_MAX_CHARS := 12

@export var color := Color.WHITE:
	set(v):
		color = v
		if _stick:
			_stick.color = v
			_a.color = v
			_stick.queue_redraw()
			_a.queue_redraw()
## Modo zurdo: joystick a la derecha y botones a la izquierda. Lo decide el
## ajuste del celular (ControllerMain); cambiarlo suelta los dedos.
@export var left_handed := false:
	set(v):
		if v == left_handed:
			return
		release_all()
		left_handed = v
		_layout()
## Texto opcional debajo de cada botón (ej. "Patear"), lo manda la TV en
## `data` del layout. Vacío = solo la letra.
@export var label_a := "":
	set(v):
		label_a = v.left(CAPTION_MAX_CHARS)
		queue_redraw()
@export var label_b := "":
	set(v):
		label_b = v.left(CAPTION_MAX_CHARS)
		queue_redraw()

## Dirección del joystick, -1..1 en cada eje. Vector2.ZERO si no hay dedo.
var value: Vector2:
	get:
		return _stick.value if _stick else Vector2.ZERO
## Máscara de botones apretados (Protocol.BTN_A | Protocol.BTN_B).
var buttons: int:
	get:
		if _a == null:
			return 0
		return (Protocol.BTN_A if _a.pressed else 0) | (Protocol.BTN_B if _b.pressed else 0)

var _stick: VirtualJoystick
var _a: BigButton
var _b: BigButton
## índice del dedo -> pieza que lo recibe (_stick, _a o _b).
var _routes: Dictionary = {}


func _init() -> void:
	_stick = VirtualJoystick.new()
	_stick.hint = "Arrastrá para moverte"
	_a = BigButton.new()
	_a.label = "A"
	_b = BigButton.new()
	_b.label = "B"
	_b.color = UiTheme.PHONE_KEY_NEUTRAL
	for part: Control in [_stick, _a, _b]:
		# Los toques los reparte este control (ver _gui_input): las piezas no
		# los reciben directo del viewport.
		part.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(part, false, Node.INTERNAL_MODE_FRONT)
	_stick.color = color
	_a.color = color


func _notification(what: int) -> void:
	match what:
		NOTIFICATION_RESIZED:
			_layout()
		NOTIFICATION_APPLICATION_FOCUS_OUT, NOTIFICATION_VISIBILITY_CHANGED:
			# Las piezas se sueltan solas; acá solo se olvidan los dedos.
			_routes.clear()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		var t := event as InputEventScreenTouch
		if t.pressed:
			if _routes.has(t.index):
				return
			var part := part_at(t.position)
			if part == _stick and _routes.values().has(_stick):
				accept_event()  # Ya hay un dedo en el joystick: este no hace nada.
				return
			_routes[t.index] = part
			_forward(part, t)
		elif _routes.has(t.index):
			var part: Control = _routes[t.index]
			_routes.erase(t.index)
			_forward(part, t)
		accept_event()
	elif event is InputEventScreenDrag:
		var d := event as InputEventScreenDrag
		if _routes.get(d.index) == _stick:
			_forward(_stick, d)
		accept_event()


## Qué pieza recibe un dedo que apoya en `pos` (coordenadas de este
## control): el joystick en su mitad; en la otra, el botón más cercano
## (relativo a su tamaño, así A, que es más grande, gana en el medio).
func part_at(pos: Vector2) -> Control:
	if stick_rect().has_point(pos):
		return _stick
	var da := pos.distance_to(button_center(Protocol.BTN_A)) / button_radius(Protocol.BTN_A)
	var db := pos.distance_to(button_center(Protocol.BTN_B)) / button_radius(Protocol.BTN_B)
	return _a if da <= db else _b


## Suelta todos los dedos (ej. al cambiar a zurdo en medio del juego).
func release_all() -> void:
	for index: int in _routes.keys():
		var up := InputEventScreenTouch.new()
		up.index = index
		up.pressed = false
		_forward(_routes[index], up)
	_routes.clear()


# --- Geometría (diestro; zurdo = espejo horizontal) -----------------------------

## Zona del joystick.
func stick_rect() -> Rect2:
	var w := size.x * STICK_SHARE
	return Rect2(size.x - w if left_handed else 0.0, 0.0, w, size.y)


## Radio de la cara del botón (BTN_A o BTN_B).
func button_radius(button: int) -> float:
	var share := A_SHARE if button == Protocol.BTN_A else B_SHARE
	var fit := size.x * (1.0 - STICK_SHARE) * 0.2  # Celulares angostos: que entren los dos.
	return clampf(minf(size.y * share, fit), MIN_BUTTON_RADIUS, MAX_BUTTON_RADIUS)


## Centro del botón. Como en un control de consola: A abajo, del lado de
## afuera; B arriba y hacia adentro, en diagonal, a un pulgar de distancia.
func button_center(button: int) -> Vector2:
	var ra := button_radius(Protocol.BTN_A)
	var rb := button_radius(Protocol.BTN_B)
	var margin := size.x * 0.04
	var a := Vector2(size.x - margin - ra * _HOUSING, size.y * 0.62)
	var p := a
	if button == Protocol.BTN_B:
		var dy := size.y * 0.26
		var gap := (ra + rb) * _HOUSING + UiTheme.PHONE_MARGIN
		p = a - Vector2(sqrt(maxf(gap * gap - dy * dy, 0.0)) + rb * 0.1, dy)
	if left_handed:
		p.x = size.x - p.x
	return p


func _layout() -> void:
	if _stick == null:
		return
	var zone := stick_rect()
	_stick.position = zone.position
	_stick.size = zone.size
	_stick.radius = minf(140.0, minf(zone.size.x, zone.size.y) * 0.16)
	for pair: Array in [[_a, Protocol.BTN_A], [_b, Protocol.BTN_B]]:
		var side := button_radius(pair[1]) / _BIG_BUTTON_FACE
		var part: BigButton = pair[0]
		# BigButton sube la cara un 6 % del radio: se compensa para que el
		# centro de la cara quede en button_center (donde se hace el hit test).
		var c := button_center(pair[1]) + Vector2(0, button_radius(pair[1]) * 0.06)
		part.size = Vector2(side, side)
		part.position = c - part.size / 2.0
	queue_redraw()


func _forward(part: Control, event: InputEvent) -> void:
	part._gui_input(event.xformed_by(Transform2D(0.0, -part.position)))


## Textos opcionales debajo de cada botón (los botones van encima).
func _draw() -> void:
	for pair: Array in [[label_a, Protocol.BTN_A], [label_b, Protocol.BTN_B]]:
		var text: String = pair[0]
		if text.is_empty():
			continue
		var r := button_radius(pair[1])
		var pos := button_center(pair[1]) + Vector2(0, r * (_HOUSING + 0.2) + CAPTION_SIZE)
		UiTheme.draw_text(self, text, pos, CAPTION_SIZE, UiTheme.PAPER, 8, UiTheme.INK)
