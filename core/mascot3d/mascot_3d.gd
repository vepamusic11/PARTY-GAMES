class_name Mascot3D
extends Node3D
## Mascota 3D de verdad, armada con primitivas (esferas, tubos, superficies
## de revolución) y renderizada por Godot. Prototipo para comparar con la
## mascota 2D dibujada por código (PlayerAvatar): ver docs/ARTE.md y
## docs/adr/0012-mascotas-3d.md. NO la usa el juego todavía.
##
## Mismas proporciones, accesorios, ánimos y parámetros de animación que
## `PlayerAvatar.draw_mascot`, para poder comparar lado a lado. Unidades:
## 1 unidad del mundo = 10 u de PlayerAvatar (la mascota mide ~10,5 de alto
## con los pies en el origen, mirando a +Z).
##
## Conceptos (explicados con más detalle en docs/ARTE.md):
## - *Plástico brillante*: material propio (toy_plastic.gdshader) con rampa
##   de color, brillo chico y nítido, brillo ancho tipo barniz (clearcoat) y
##   contraluz (rim light). La luz de estudio va dentro del shader.
## - *Contorno de tinta*: casco invertido (ink_outline.gdshader), una
##   segunda pasada de cada pieza inflada y dada vuelta.
## - *Cara intercambiable*: ojos y bocas de cada ánimo son mallas propias
##   que se prenden y apagan (no hay texturas).
## - *Squash & stretch*: se escala el nodo `_squash` alrededor de los pies
##   (ancho × alto ≈ constante), igual que en 2D.

enum Shading { TOON, STANDARD }
enum Kind { PLASTIC, FACE, EYE, SHOE, METAL, FLAT, GLOW }

const STYLE_ROBOT := PlayerAvatar.STYLE_ROBOT
const STYLE_HORNS := PlayerAvatar.STYLE_HORNS
const STYLE_BUNNY := PlayerAvatar.STYLE_BUNNY

const U := 0.1                             ## 1 u de PlayerAvatar en unidades del mundo.
const HEAD_C := Vector3(0, 5.7, 0)         ## Centro de la cabeza.
const HEAD_R := Vector3(3.9, 3.4, 3.4)     ## Semiejes de la cabeza.
const FACE_C := Vector2(0, -0.85)          ## Centro de la cara (relativo a la cabeza).
const FACE_R := Vector2(2.92, 2.44)        ## Semiejes de la cara vista de frente.
const FACE_BULGE := 0.14                   ## Cuánto sobresale la cara.
const BODY_C := Vector3(0, 2.0, 0)
const INK_W := 0.3                         ## Contorno de piezas grandes (3 u, como en 2D).
const INK_W_SMALL := 0.24                  ## Contorno de piezas chicas.
const EYE_X := 1.08
const EYE_Y := -0.62
const MOUTH_Y := -1.9

const SHADER_TOY := preload("res://core/mascot3d/toy_plastic.gdshader")
const SHADER_INK := preload("res://core/mascot3d/ink_outline.gdshader")

var color := Color.WHITE
var style := 0
var shading := Shading.TOON

var _squash: Node3D
var _lift: Node3D
var _turn: Node3D
var _body: Node3D
var _head: Node3D
var _acc: Node3D
var _eyes: Node3D
var _legs: Array[Node3D] = []
var _shoes: Array[Node3D] = []
var _arms: Array[Node3D] = []
var _arm_tubes: Array[Node3D] = []
var _hands: Array[Node3D] = []
var _features: Dictionary = {}   # nombre -> Node3D (se prenden según el ánimo)
var _tear: Node3D
var _bulb: MeshInstance3D
var _mood := -1

static var _materials: Dictionary = {}


## Arma la mascota. col: color del jugador; p_style: índice de
## PlayerAvatar.STYLE_NAMES (0 antena … 6 conejo).
func setup(col: Color, p_style: int, p_shading := Shading.TOON) -> Mascot3D:
	color = col
	style = posmod(p_style, PlayerAvatar.STYLE_NAMES.size())
	shading = p_shading
	for c in get_children():
		c.free()
	_legs.clear()
	_shoes.clear()
	_arms.clear()
	_arm_tubes.clear()
	_hands.clear()
	_features.clear()
	_build()
	apply(PlayerAvatar.Mood.NORMAL, {})
	return self


## Cantidad de piezas (MeshInstance3D) de la mascota: cada una es 1 draw
## call, más otro por el contorno si lo tiene.
func mesh_count() -> int:
	return find_children("*", "MeshInstance3D", true, false).size()


## Ojos y boca que se ven ahora (ej. ["eyes_happy", "mouth_happy"]); para los tests.
func visible_features() -> Array[String]:
	var out: Array[String] = []
	for key: String in _features:
		if (_features[key] as Node3D).visible:
			out.append(key)
	out.sort()
	return out


# --- Construcción -------------------------------------------------------------------

func _build() -> void:
	var col := color
	_squash = _node(self, Vector3.ZERO)
	_lift = _node(_squash, Vector3.ZERO)
	_turn = _node(_lift, Vector3.ZERO)
	var sph := Mascot3DMeshes.sphere()
	var sph_s := Mascot3DMeshes.sphere(10, 16)

	# Piernas cortas y zapatos oscuros brillantes.
	for side in [-1.0, 1.0]:
		var leg := _node(_turn, Vector3(side * 0.68, 1.3, 0.0))
		_part(leg, sph_s, Kind.PLASTIC, col, Vector3(0, -0.35, 0), Vector3(0.5, 0.62, 0.5), INK_W_SMALL)
		_legs.append(leg)
		var shoe := _node(_turn, Vector3(side * 0.84, 0.44, 0.22))
		_part(shoe, sph_s, Kind.SHOE, UiTheme.MASCOT_SHOE, Vector3.ZERO, Vector3(0.74, 0.46, 0.92), INK_W_SMALL)
		_shoes.append(shoe)

	# Cuerpo: superelipse de revolución, más ancha abajo, con la gema.
	_body = _node(_turn, BODY_C)
	var body_mesh := Mascot3DMeshes.lathe("body", Mascot3DMeshes.blob_profile(1.72, 1.3, 0.0, 2.6, 0.14), 28, 0.88)
	_part(_body, body_mesh, Kind.PLASTIC, col, Vector3.ZERO, Vector3.ONE, INK_W)
	var robot := style == STYLE_ROBOT
	var gem_col := UiTheme.MASCOT_METAL if robot else PlayerAvatar._gem_color(col)
	_part(_body, Mascot3DMeshes.torus(0.22), Kind.METAL, UiTheme.MASCOT_METAL,
		Vector3(0, -0.12, 1.42), Vector3(0.36, 0.36, 0.36), 0.0, Vector3(PI / 2.0 - 0.25, 0, 0))
	_part(_body, sph_s, Kind.METAL if robot else Kind.PLASTIC, gem_col, Vector3(0, -0.12, 1.44),
		Vector3(0.3, 0.3, 0.2), 0.0)

	# Brazos: cápsula + mano redonda, con el pivote en el hombro.
	for side in [-1.0, 1.0]:
		var shoulder := _node(_body, Vector3(side * 1.42, 0.72, 0.3))
		var arm := Mascot3DMeshes.tube("arm", PackedVector3Array([Vector3(0, 0, 0), Vector3(0, -1.15, 0)]),
			PackedFloat32Array([0.44, 0.47]), 12)
		_arm_tubes.append(_part(shoulder, arm, Kind.PLASTIC, col, Vector3.ZERO, Vector3.ONE, INK_W_SMALL))
		_hands.append(_part(shoulder, sph_s, Kind.PLASTIC, col, Vector3(0, -1.3, 0), Vector3(0.58, 0.58, 0.58), INK_W_SMALL))
		_arms.append(shoulder)

	# Cabeza: esfera un poco más ancha que alta, con la cara blanca encima.
	_head = _node(_turn, HEAD_C)
	_part(_head, Mascot3DMeshes.sphere(24, 48), Kind.PLASTIC, col, Vector3.ZERO, HEAD_R, INK_W)
	var pad := Mascot3DMeshes.face_pad("face", HEAD_R, FACE_C, FACE_R, FACE_BULGE)
	_part(_head, pad, Kind.FACE, UiTheme.PAPER, Vector3.ZERO, Vector3.ONE, 0.0)
	_acc = _node(_head, Vector3.ZERO)
	_eyes = _node(_head, Vector3.ZERO)
	_build_face()
	_build_accessory()


func _build_face() -> void:
	var eye_ink := UiTheme.MASCOT_EYE
	var sph_s := Mascot3DMeshes.sphere(10, 16)
	var normal_eyes := _feature("eyes_open", _eyes)
	var sad_eyes := _feature("eyes_sad", _eyes)
	var surprised_eyes := _feature("eyes_surprised", _eyes)
	var happy_eyes := _feature("eyes_happy", _eyes)
	var blink_eyes := _feature("eyes_blink", _eyes)
	for sx in [-1.0, 1.0]:
		var e := Vector2(sx * EYE_X, EYE_Y)
		# Normal: óvalo negro brillante con dos reflejos.
		var eye := _on_face(normal_eyes, e, -0.1)
		_part(eye, sph_s, Kind.EYE, eye_ink, Vector3.ZERO, Vector3(0.54, 0.84, 0.3), 0.0)
		_part(eye, sph_s, Kind.FLAT, Color.WHITE, Vector3(-0.16, 0.37, 0.22), Vector3(0.21, 0.26, 0.08), 0.0)
		_part(eye, sph_s, Kind.FLAT, Color(1, 1, 1, 0.9), Vector3(0.18, -0.38, 0.2), Vector3(0.1, 0.1, 0.05), 0.0)
		# Triste: ojo más chico y bajo, con la ceja caída hacia afuera.
		var sad := _on_face(sad_eyes, e + Vector2(0, -0.2), -0.08)
		_part(sad, sph_s, Kind.EYE, eye_ink, Vector3.ZERO, Vector3(0.36, 0.54, 0.24), 0.0)
		_part(sad, sph_s, Kind.FLAT, Color.WHITE, Vector3(-0.1, 0.16, 0.18), Vector3(0.13, 0.15, 0.06), 0.0)
		_face_tube(sad_eyes, "brow%d" % sx, [e + Vector2(-sx * 0.55, 0.92), e + Vector2(sx * 0.45, 0.6)], 0.11, eye_ink)
		# Sorpresa: ojo blanco con aro de tinta y pupila chica.
		var sur := _on_face(surprised_eyes, e, 0.0)
		_part(sur, sph_s, Kind.FACE, UiTheme.PAPER, Vector3.ZERO, Vector3(0.4, 0.4, 0.12), 0.0)
		_part(sur, Mascot3DMeshes.torus(0.24), Kind.EYE, eye_ink, Vector3(0, 0, 0.04), Vector3(0.44, 0.44, 0.44),
			0.0, Vector3(PI / 2.0, 0, 0))
		_part(sur, sph_s, Kind.EYE, eye_ink, Vector3(0, 0, 0.1), Vector3(0.23, 0.23, 0.1), 0.0)
		# Feliz: arco (^) y cachetes rosados.
		var arc: Array = []
		for i in 9:
			var a := PI * (1.12 + 0.76 * i / 8.0)
			arc.append(e + Vector2(0, -0.3) + Vector2(cos(a), -sin(a)) * 0.52)
		_face_tube(happy_eyes, "happy%d" % sx, arc, 0.14, eye_ink)
		var blush := _on_face(happy_eyes, e + Vector2(sx * 0.78, -0.88), -0.02)
		_part(blush, sph_s, Kind.FLAT, Color(1.0, 0.72, 0.78), Vector3.ZERO, Vector3(0.48, 0.3, 0.06), 0.0)
		# Parpadeo: una rayita.
		_face_tube(blink_eyes, "blink%d" % sx, [e + Vector2(-0.42, 0), e + Vector2(0.42, 0)], 0.12, eye_ink)

	# Bocas.
	var m := Vector2(0, MOUTH_Y)
	var happy := _feature("mouth_happy", _head)
	var smile := _on_face(happy, m + Vector2(0, 0.12), -0.02)
	_part(smile, Mascot3DMeshes.extrude("smile", Mascot3DMeshes.ellipse_outline(0.6, 0.52, 16, true), 0.08),
		Kind.EYE, eye_ink, Vector3.ZERO, Vector3.ONE, 0.0)
	_part(smile, sph_s, Kind.FLAT, PlayerAvatar.TONGUE, Vector3(0, -0.3, 0.06), Vector3(0.24, 0.16, 0.05), 0.0)
	var sad_mouth := _feature("mouth_sad", _head)
	var frown: Array = []
	for i in 7:
		var a := PI * (1.2 + 0.6 * i / 6.0)
		frown.append(m + Vector2(0, -0.45) + Vector2(cos(a), -sin(a)) * 0.45)
	_face_tube(sad_mouth, "frown", frown, 0.1, eye_ink)
	_tear = _node(sad_mouth, Vector3.ZERO)
	_part(_tear, sph_s, Kind.PLASTIC, PlayerAvatar.TEAR, Vector3.ZERO, Vector3(0.24, 0.3, 0.16), 0.0)
	var sur_mouth := _feature("mouth_surprised", _head)
	var o := _on_face(sur_mouth, m + Vector2(0, 0.05), -0.04)
	_part(o, sph_s, Kind.EYE, eye_ink, Vector3.ZERO, Vector3(0.34, 0.4, 0.1), 0.0)
	_part(o, sph_s, Kind.FLAT, PlayerAvatar.TONGUE, Vector3(0, -0.14, 0.06), Vector3(0.2, 0.14, 0.05), 0.0)
	if style == STYLE_ROBOT:
		var grille := _feature("mouth_robot", _head)
		var g := _on_face(grille, m + Vector2(0, 0.2), -0.03)
		_part(g, Mascot3DMeshes.extrude("grille", Mascot3DMeshes.rounded_rect_outline(0.72, 0.28), 0.08),
			Kind.EYE, eye_ink, Vector3.ZERO, Vector3.ONE, 0.0)
		for k in 3:
			_part(g, sph_s, Kind.METAL, UiTheme.MASCOT_METAL, Vector3((k - 1) * 0.36, 0, 0.08),
				Vector3(0.07, 0.15, 0.04), 0.0)


func _build_accessory() -> void:
	var col := color
	var sph := Mascot3DMeshes.sphere(14, 24)
	var sph_s := Mascot3DMeshes.sphere(10, 16)
	var ink := UiTheme.INK
	match style:
		0:  # Antena con bola brillante.
			var stem := Mascot3DMeshes.tube("antenna", PackedVector3Array([
				Vector3(0, 3.25, 0.1), Vector3(0.1, 4.0, 0.1), Vector3(0.35, 4.7, 0.08), Vector3(0.55, 5.1, 0.05)]),
				PackedFloat32Array([0.16, 0.15, 0.14, 0.13]), 8)
			_part(_acc, stem, Kind.EYE, ink, Vector3.ZERO, Vector3.ONE, 0.0)
			_part(_acc, sph_s, Kind.EYE, ink, Vector3(0, 3.3, 0.1), Vector3(0.46, 0.2, 0.46), 0.0)
			_part(_acc, sph, Kind.PLASTIC, col, Vector3(0.6, 5.55, 0.05), Vector3(0.75, 0.75, 0.75), INK_W_SMALL)
		1:  # Oso: orejas redondas con el interior más claro.
			for sx in [-1.0, 1.0]:
				var ear := _node(_acc, Vector3(sx * 2.65, 2.75, -0.35))
				ear.rotation.z = -sx * 0.35
				_part(ear, sph, Kind.PLASTIC, col, Vector3.ZERO, Vector3(1.22, 1.22, 0.8), INK_W)
				_part(ear, sph_s, Kind.PLASTIC, col.lerp(UiTheme.PAPER, 0.35), Vector3(0, -0.05, 0.52),
					Vector3(0.62, 0.62, 0.34), 0.0)
		2:  # Gato: orejas puntiagudas con el interior naranja.
			for sx in [-1.0, 1.0]:
				var ear := _node(_acc, Vector3(sx * 2.15, 2.35, -0.2))
				ear.rotation.z = -sx * 0.36
				_part(ear, _cone("cat", 1.25, 2.7), Kind.PLASTIC, col, Vector3.ZERO, Vector3(1, 1, 0.62), INK_W)
				_part(ear, _cone("cat_in", 0.7, 1.9), Kind.PLASTIC, UiTheme.MASCOT_EAR_INNER.lerp(col, 0.1),
					Vector3(0, 0.1, 0.52), Vector3(1, 1, 0.3), 0.0)
		3:  # Brote: tallito y dos hojas.
			var stem := Mascot3DMeshes.tube("sprout", PackedVector3Array([
				Vector3(0, 3.2, 0), Vector3(0, 3.7, 0), Vector3(0.05, 4.15, 0)]), PackedFloat32Array([0.2, 0.18, 0.16]), 8)
			_part(_acc, stem, Kind.PLASTIC, UiTheme.LEAF.darkened(0.25), Vector3.ZERO, Vector3.ONE, INK_W_SMALL)
			for sx in [-1.0, 1.0]:
				var leaf := _node(_acc, Vector3(sx * 0.95, 4.45, 0.0))
				leaf.rotation = Vector3(0.0, -sx * 0.25, sx * 0.42)
				_part(leaf, sph, Kind.PLASTIC, UiTheme.LEAF, Vector3.ZERO, Vector3(1.05, 0.55, 0.32), INK_W_SMALL)
		STYLE_ROBOT:  # Auriculares de metal, antena con foco y tornillos.
			for sx in [-1.0, 1.0]:
				_part(_acc, Mascot3DMeshes.cylinder(), Kind.METAL, UiTheme.MASCOT_METAL, Vector3(sx * 3.85, -0.1, 0),
					Vector3(0.95, 0.7, 0.95), INK_W_SMALL, Vector3(0, 0, PI / 2.0))
				_part(_acc, sph_s, Kind.PLASTIC, UiTheme.MASCOT_METAL.darkened(0.35), Vector3(sx * 4.2, -0.1, 0),
					Vector3(0.2, 0.55, 0.55), 0.0)
				_part(_acc, sph_s, Kind.METAL, UiTheme.MASCOT_METAL, Vector3(sx * 1.95, 2.15, 1.98),
					Vector3(0.22, 0.22, 0.12), 0.0)
			_part(_acc, Mascot3DMeshes.cylinder(), Kind.METAL, UiTheme.MASCOT_METAL, Vector3(0, 3.35, 0),
				Vector3(0.62, 0.3, 0.62), INK_W_SMALL)
			var mast := Mascot3DMeshes.tube("mast", PackedVector3Array([Vector3(0, 3.4, 0), Vector3(0, 4.7, 0)]),
				PackedFloat32Array([0.11, 0.11]), 8)
			_part(_acc, mast, Kind.METAL, UiTheme.MASCOT_METAL, Vector3.ZERO, Vector3.ONE, 0.1)
			_bulb = _part(_acc, sph, Kind.GLOW, UiTheme.DANGER.lerp(UiTheme.ACCENT, 0.3), Vector3(0, 5.0, 0),
				Vector3(0.52, 0.52, 0.52), INK_W_SMALL)
		STYLE_HORNS:  # Diablito: cuernos curvos que se afinan.
			var horn_col := col.darkened(0.4) if col.get_luminance() > 0.25 else col.lightened(0.45)
			for sx in [-1.0, 1.0]:
				var pts := PackedVector3Array()
				var radii := PackedFloat32Array()
				for i in 7:
					var k := i / 6.0
					pts.append(Vector3(sx * (0.9 * sin(k * 1.9) * 0.9), k * 1.75, 0.15 * k))
					radii.append(lerpf(0.62, 0.1, pow(k, 0.9)))
				var horn := Mascot3DMeshes.tube("horn%d" % sx, pts, radii, 12)
				_part(_acc, horn, Kind.PLASTIC, horn_col, Vector3(sx * 1.55, 2.55, 0.25), Vector3.ONE, INK_W_SMALL,
					Vector3(0, 0, -sx * 0.3))
		STYLE_BUNNY:  # Conejo: orejas largas con el interior rosa.
			for sx in [-1.0, 1.0]:
				var ear := _node(_acc, Vector3(sx * 1.3, 3.2, -0.25))
				ear.rotation.z = -sx * 0.18
				_part(ear, sph, Kind.PLASTIC, col, Vector3(0, 1.0, 0), Vector3(0.88, 2.15, 0.6), INK_W)
				_part(ear, sph_s, Kind.PLASTIC, UiTheme.MASCOT_BUNNY_INNER, Vector3(0, 0.9, 0.42),
					Vector3(0.42, 1.4, 0.22), 0.0)


## Oreja de gato: cono de base redonda y punta apenas redondeada.
func _cone(key: String, r: float, h: float) -> Mesh:
	var prof := PackedVector2Array([Vector2(0, 0), Vector2(r * 0.85, 0.0), Vector2(r, 0.18), Vector2(r * 0.55, h * 0.5),
		Vector2(r * 0.16, h * 0.9), Vector2(0.06, h), Vector2(0, h)])
	return Mascot3DMeshes.lathe(key, prof, 20)


# --- Poses ---------------------------------------------------------------------------

## Aplica un ánimo y una pose. anim: mismas claves que PlayerAvatar.draw_mascot
## (t, walk, look, squash, wave) más `blink` (bool) y `bob` (u, respiración).
func apply(p_mood: int, anim: Dictionary) -> void:
	var t := float(anim.get("t", 0.0))
	var walk := float(anim.get("walk", -1.0))
	var look: Vector2 = anim.get("look", Vector2.ZERO)
	var sq := clampf(float(anim.get("squash", 0.0)), -0.5, 0.5)
	var wave := bool(anim.get("wave", false))
	var bob := float(anim.get("bob", 0.0)) * U
	var walking := walk >= 0.0
	# Parpadeo: explícito o cada ~3,3 s (mismo reloj que la 2D).
	var blinking := bool(anim.get("blink", false))
	if not blinking and p_mood == PlayerAvatar.Mood.NORMAL and t > 0.0 and anim.has("t"):
		blinking = fposmod(t + style * 1.37, 3.3) < 0.12

	_squash.scale = Vector3(1.0 + sq * 0.6, 1.0 - sq * 0.6, 1.0 + sq * 0.6)
	var step_bob := absf(sin(walk * TAU)) * 0.3 if walking else 0.0
	_lift.position.y = step_bob
	# En 3D la mascota puede girar hacia donde camina o mira (en 2D solo se corren los ojos).
	_turn.rotation.y = look.x * (0.45 if walking else 0.2)
	_head.position = HEAD_C + Vector3(0, -bob, 0)
	_head.rotation = Vector3(look.y * 0.25, look.x * 0.2, 0)
	_body.position = BODY_C + Vector3(0, -bob * 0.4, 0)
	_eyes.position = Vector3(look.x * 0.18, -look.y * 0.14, 0)
	var sway := sin(walk * TAU) * 0.08 if walking else sin(t * 1.6 + style) * 0.03
	_acc.rotation.z = -sway

	# Piernas y zapatos que se alternan al caminar.
	for i in 2:
		var side := -1.0 if i == 0 else 1.0
		var phase := sin(walk * TAU) * side if walking else 0.0
		var up := maxf(0.0, phase)
		_shoes[i].position = Vector3(side * 0.84, 0.44 + up * 0.45, 0.22 + phase * 0.45)
		_shoes[i].rotation.x = -up * 0.35
		_legs[i].position = Vector3(side * 0.68, 1.3 + up * 0.2, phase * 0.2)

	# Brazos: colgando, balanceándose o saludando (arriba y hacia adelante).
	for i in 2:
		var side := -1.0 if i == 0 else 1.0
		if wave:
			# En 3D la cabeza taparía los brazos levantados: la mano apunta a
			# un punto delante del costado de la cara, y el brazo se estira
			# un poco para llegar (en dibujos animados se vale).
			var hand := Vector3(side * 3.35, 3.2 + sin(t * 12.0 + side) * 0.35, 1.1) - BODY_C
			var d := hand - _arms[i].position
			var stretch := d.length() / 1.3
			_arms[i].basis = Basis(Quaternion(Vector3.DOWN, d.normalized()))
			_arm_tubes[i].scale = Vector3(1.0, stretch, 1.0)
			_hands[i].position.y = -1.3 * stretch
			continue
		_arm_tubes[i].scale = Vector3.ONE
		_hands[i].position.y = -1.3
		var angle := 0.5
		var fwd := 0.0
		if walking:
			angle = 0.45 + sin(walk * TAU) * side * 0.25
			fwd = sin(walk * TAU) * side * 0.7
		_arms[i].basis = Basis.IDENTITY
		_arms[i].rotation = Vector3(fwd, 0, side * angle)

	# Cara según el ánimo.
	_mood = p_mood
	var eyes := "eyes_open"
	var mouth := ""
	match p_mood:
		PlayerAvatar.Mood.HAPPY:
			eyes = "eyes_happy"
			mouth = "mouth_happy"
		PlayerAvatar.Mood.SAD:
			eyes = "eyes_sad"
			mouth = "mouth_sad"
		PlayerAvatar.Mood.SURPRISED:
			eyes = "eyes_surprised"
			mouth = "mouth_surprised"
		_:
			if blinking:
				eyes = "eyes_blink"
			if style == STYLE_ROBOT:
				mouth = "mouth_robot"
	for key in _features:
		(_features[key] as Node3D).visible = key == eyes or key == mouth
	if p_mood == PlayerAvatar.Mood.SAD:
		var drop := fposmod(t * 0.9, 1.0) if anim.has("t") else 0.35
		var p := Vector2(-1.05, -0.62 - drop * 1.1)
		_tear.position = _face_pos(p, 0.12)
		_tear.scale = Vector3.ONE * (1.0 - drop * 0.4)
	if _bulb:
		var glow := 0.55 + 0.45 * absf(sin(t * 3.0 + style))
		_bulb.scale = Vector3.ONE * 0.52 * (0.94 + 0.06 * glow)


# --- Ayudas de armado ------------------------------------------------------------------

func _node(parent: Node3D, pos: Vector3) -> Node3D:
	var n := Node3D.new()
	n.position = pos
	parent.add_child(n)
	return n


func _feature(key: String, parent: Node3D) -> Node3D:
	var n := _node(parent, Vector3.ZERO)
	n.name = key
	_features[key] = n
	return n


func _part(parent: Node3D, mesh: Mesh, kind: int, col: Color, pos: Vector3, scl: Vector3, ink_w: float,
		rot := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = pos
	mi.rotation = rot
	mi.scale = scl
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.material_override = material(kind, col, ink_w, shading)
	parent.add_child(mi)
	return mi


## Nodo apoyado sobre la cara en (x, y) de frente, mirando hacia afuera de la cara.
func _on_face(parent: Node3D, p: Vector2, lift: float) -> Node3D:
	var n := _node(parent, _face_pos(p, lift))
	var nrm := Mascot3DMeshes.face_normal(HEAD_R, FACE_C, FACE_R, FACE_BULGE, p)
	n.basis = Basis.looking_at(-nrm, Vector3.UP)
	return n


func _face_pos(p: Vector2, lift: float) -> Vector3:
	var nrm := Mascot3DMeshes.face_normal(HEAD_R, FACE_C, FACE_R, FACE_BULGE, p)
	return Mascot3DMeshes.face_point(HEAD_R, FACE_C, FACE_R, FACE_BULGE, p) + nrm * lift


## Tubo pegado a la cara que pasa por los puntos `pts` (vistos de frente).
func _face_tube(parent: Node3D, key: String, pts: Array, r: float, col: Color) -> void:
	var p3 := PackedVector3Array()
	var radii := PackedFloat32Array()
	for p: Vector2 in pts:
		p3.append(_face_pos(p, r * 0.3))
		radii.append(r)
	_part(parent, Mascot3DMeshes.tube("face_" + key, p3, radii, 8), Kind.EYE, col, Vector3.ZERO, Vector3.ONE, 0.0)


# --- Materiales ------------------------------------------------------------------------

## Material de una pieza (en caché: todas las mascotas del mismo color
## comparten materiales). ink_w > 0: con contorno de ese ancho.
static func material(kind: int, col: Color, ink_w := 0.0, p_shading := Shading.TOON) -> Material:
	var key := "%d|%s|%.3f|%d" % [kind, col.to_html(), ink_w, p_shading]
	if _materials.has(key):
		return _materials[key]
	var mat: Material
	if p_shading == Shading.STANDARD:
		mat = _standard_material(kind, col)
	else:
		mat = _toy_material(kind, col)
	if ink_w > 0.0:
		var ink := ShaderMaterial.new()
		ink.shader = SHADER_INK
		ink.set_shader_parameter("ink", UiTheme.INK)
		ink.set_shader_parameter("width", ink_w)
		mat.next_pass = ink
	_materials[key] = mat
	return mat


static func _toy_material(kind: int, col: Color) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = SHADER_TOY
	var low := col
	var mid := col
	var high := col
	var bounce := col
	var bounce_k := 0.35
	var rim := Color.WHITE
	var rim_k := 0.22
	var spec := 0.95
	var spec_pow := 140.0
	var coat := 0.16
	var edge := col
	var edge_k := 0.0
	match kind:
		Kind.PLASTIC, Kind.SHOE:
			var lum := col.get_luminance()
			var dark := lum < 0.2
			low = col.lightened(0.02) if dark else col.darkened(0.55 if lum < 0.8 else 0.3)
			low = low.lerp(UiTheme.MASCOT_SHADE_TINT, 0.12)
			mid = col.lightened(0.12) if dark else col
			high = col.lightened(0.45 if dark else (0.1 if lum > 0.85 else 0.32))
			bounce = mid.lightened(0.18)
			if dark:
				rim = UiTheme.MASCOT_RIM
				rim_k = 0.75
			if kind == Kind.SHOE:
				rim = UiTheme.MASCOT_RIM
				rim_k = 0.5
		Kind.FACE:
			low = UiTheme.MASCOT_FACE_SHADE
			mid = UiTheme.PAPER.lerp(UiTheme.MASCOT_FACE_SHADE, 0.12)
			high = UiTheme.PAPER
			bounce = UiTheme.PAPER
			bounce_k = 0.2
			edge = UiTheme.MASCOT_FACE_SHADE.darkened(0.1)
			edge_k = 0.75
			spec = 0.35
			spec_pow = 60.0
			coat = 0.06
			rim_k = 0.0
		Kind.EYE:
			low = col
			mid = col
			high = col.lerp(UiTheme.MASCOT_EYE_GLOSS, 0.4)
			bounce = UiTheme.MASCOT_EYE_GLOSS
			bounce_k = 0.8
			rim = UiTheme.MASCOT_EYE_GLOSS
			rim_k = 0.4
			spec = 1.0
			spec_pow = 90.0
			coat = 0.1
		Kind.METAL:
			low = col.darkened(0.5)
			mid = col
			high = UiTheme.PAPER
			bounce = col.lightened(0.3)
			bounce_k = 0.6
			spec = 1.0
			spec_pow = 70.0
			coat = 0.35
		Kind.FLAT:
			spec = 0.0
			coat = 0.0
			rim_k = 0.0
			bounce_k = 0.0
		Kind.GLOW:  # Foco que brilla (robot): claro y con poca sombra.
			low = col
			mid = col.lightened(0.2)
			high = col.lightened(0.6)
			bounce_k = 0.0
			rim_k = 0.0
	m.set_shader_parameter("low_color", low)
	m.set_shader_parameter("mid_color", mid)
	m.set_shader_parameter("high_color", high)
	m.set_shader_parameter("bounce_color", bounce)
	m.set_shader_parameter("bounce_strength", bounce_k)
	m.set_shader_parameter("rim_color", rim)
	m.set_shader_parameter("rim_strength", rim_k)
	m.set_shader_parameter("spec_strength", spec)
	m.set_shader_parameter("spec_power", spec_pow)
	m.set_shader_parameter("coat_strength", coat)
	m.set_shader_parameter("edge_color", edge)
	m.set_shader_parameter("edge_strength", edge_k)
	return m


## Variante con el material estándar de Godot (PBR) y luces reales: sirve
## para comparar con el shader propio (ver Mascot3DStage.add_studio_lights).
## Clearcoat = capa de barniz: un segundo reflejo nítido encima del color.
static func _standard_material(kind: int, col: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.roughness = 0.35
	m.clearcoat_enabled = true
	m.clearcoat = 1.0
	m.clearcoat_roughness = 0.08
	m.rim_enabled = true
	m.rim = 0.35
	m.rim_tint = 0.3
	match kind:
		Kind.FACE:
			m.roughness = 0.7
			m.clearcoat_enabled = false
			m.rim_enabled = false
		Kind.METAL:
			m.metallic = 0.85
			m.roughness = 0.25
		Kind.FLAT:
			m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		Kind.GLOW:
			m.emission_enabled = true
			m.emission = col
			m.emission_energy_multiplier = 0.6
	return m
