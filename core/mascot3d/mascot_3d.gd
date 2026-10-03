class_name Mascot3D
extends Node3D
## Mascota 3D de verdad, armada con primitivas (esferas, tubos, superficies
## de revolución) y renderizada por Godot. Se hornea a sprites con
## Mascot3DBaker (ver docs/ARTE.md y docs/adr/0012-mascotas-3d.md).
##
## Mismos accesorios, ánimos y parámetros de animación que
## `PlayerAvatar.draw_mascot`: `apply(mood, anim)` recibe el mismo dict
## `anim` (t, walk, look, squash, wave, dance, dance_kind, defeat, greet,
## flop) más `blink` (bool) y `bob` (u, respiración de la cabeza).
## Unidades: 1 unidad del mundo = 10 u de PlayerAvatar (la mascota mide
## ~9,6 de la coronilla a la suela, con los pies en el origen, mirando a +Z).
## Proporciones de la maqueta (docs/design/referencia_mascotas.webp): la
## cabeza es ~3/4 del alto y casi el doble de ancha que el cuerpo.
##
## Conceptos (explicados con más detalle en docs/ARTE.md):
## - *Plástico brillante*: material propio (toy_plastic.gdshader) con rampa
##   de color, reflejo nítido "pintado", brillo ancho de barniz (clearcoat),
##   contraluz y reflejo del cielo. La luz de estudio va dentro del shader.
## - *Contorno de tinta*: casco invertido (ink_outline.gdshader), una
##   segunda pasada de cada pieza inflada y dada vuelta; más fino del lado
##   de la luz y más grueso del lado de la sombra.
## - *Cara pintada*: la cara blanca es una zona del material de la cabeza
##   (no otra malla): borde limpio a cualquier tamaño.
## - *Cara intercambiable*: ojos y bocas de cada ánimo son mallas propias
##   que se prenden y apagan (no hay texturas). Las de los ánimos menos
##   comunes (enojada, mareada, dormida, ganadora, riendo) se arman recién
##   la primera vez que se piden: el horneado de un juego no las paga.
## - *Pose por capas* (como en 2D): cada animación suma su parte a unos
##   pocos números (inclinación, ángulo de cada brazo, salto, giro…) y
##   después se aplican una sola vez. Ejemplo: bailar y estar derrotada a
##   la vez baja la cabeza Y mueve los brazos.
## - *Squash & stretch*: se escala el nodo `_squash` alrededor de los pies
##   (ancho × alto ≈ constante), igual que en 2D.

enum Shading { TOON, STANDARD }
enum Kind { PLASTIC, FACE, EYE, SHOE, METAL, FLAT, GLOW, HEAD, BLUSH, MOUTH, GEM, HALO, LEAF, GLASS, BODY }

const STYLE_ROBOT := PlayerAvatar.STYLE_ROBOT
const STYLE_HORNS := PlayerAvatar.STYLE_HORNS
const STYLE_BUNNY := PlayerAvatar.STYLE_BUNNY
const Mood := PlayerAvatar.Mood

const U := 0.1                             ## 1 u de PlayerAvatar en unidades del mundo.
const HEAD_C := Vector3(0, 6.0, 0)         ## Centro de la cabeza.
const HEAD_R := Vector3(4.2, 3.6, 3.45)    ## Semiejes de la cabeza.
const FACE_C := Vector2(0, -1.0)           ## Centro de la cara (relativo a la cabeza).
## Semiejes de la cara vista de frente. Medido en la maqueta (vuelta 2, por
## zonas): la cara ocupa ~68 % del ancho de la cabeza (la capucha se ve
## gruesa a los costados) y mide ~0,72 de alto por ancho; llega casi hasta
## el mentón (borde fino).
const FACE_R := Vector2(2.95, 2.3)
const BODY_C := Vector3(0, 1.88, 0)
const BODY_R := Vector3(1.72, 1.3, 1.48)  ## Semiejes aproximados del cuerpo (para no meter las manos adentro).
## Hombro derecho, relativo al cuerpo. En la maqueta los brazos cuelgan bien
## visibles a los costados (la silueta del cuerpo con brazos mide ~65 % de
## la cabeza; antes ~55 %): más afuera, más abajo y más gordos.
const SHOULDER := Vector3(1.6, 0.42, 0.28)
const ARM_LEN := 1.35                      ## Del hombro al centro de la mano.
const ARM_R := 0.7                         ## Radio del brazo (la manga; vuelta 3: más gorda, como la maqueta).
const ARM_REST := 0.36                     ## Ángulo del brazo colgando (rad desde la vertical).
## Saludo con una mano bien arriba (lobby, como la maqueta): el brazo se
## estira como en los dibujos animados y la mano queda al costado de la
## cabeza, a la altura de la frente. En unidades de ARM_LEN.
const HELLO_REACH := 4.4
const HELLO_ANGLE := 2.35                  ## Radianes desde "colgando" (PI = derecho hacia arriba).
const HELLO_PERIOD := 0.9                  ## Segundos de un vaivén de la mano (2 cuadros horneados).
const HAND_R := 0.76
const INK_W := 0.19                        ## Contorno de piezas grandes (~2 u).
const INK_W_SMALL := 0.15                  ## Contorno de piezas chicas.
const EYE_X := 1.28
const EYE_Y := -0.78
## Ojo normal: semiejes (ancho, alto, profundidad). La maqueta: óvalo alto
## (alto ≈ 1,7 × ancho) que mide ~0,4 del alto de la cara.
const EYE_R := Vector3(0.66, 1.2, 0.42)
const MOUTH_Y := -2.12

## Colores propios de la cara 3D (la 2D usa los de PlayerAvatar).
const BLUSH := Color(1.0, 0.52, 0.62)     ## Cachetes (en el centro; se funden con la cara).
const MOUTH_IN := Color(0.55, 0.1, 0.2)    ## Interior de la boca abierta.
const SKY_RIM := Color(0.78, 0.9, 1.0)     ## Contraluz celeste (el cielo detrás de la mascota).
const GOLD := Color(1.0, 0.78, 0.2)        ## Ojos de estrella y estrellitas.
const VEIN := Color(0.93, 0.25, 0.3)       ## Venita de enojo.

const SHADER_TOY := preload("res://core/mascot3d/toy_plastic.gdshader")
const SHADER_INK := preload("res://core/mascot3d/ink_outline.gdshader")

var color := Color.WHITE
var style := 0
var shading := Shading.TOON

var _squash: Node3D
var _lift: Node3D
var _turn: Node3D
var _body: Node3D
var _body_mesh: Node3D
var _head: Node3D
var _acc: Node3D
var _eyes: Node3D
var _cheeks: Node3D
var _legs: Array[Node3D] = []
var _shoes: Array[Node3D] = []
var _arms: Array[Node3D] = []
var _arm_tubes: Array[Node3D] = []
var _hands: Array[Node3D] = []
var _features: Dictionary = {}   # nombre -> Node3D (se prenden según el ánimo)
var _moving: Dictionary = {}     # nombre -> Array[Node3D] (piezas que se animan con t)
## Piezas de los accesorios que se doblan con la inercia: [nodo, giro base,
## giro por flop, giro por swing, giro por sway, acortado por flop].
var _pivots: Array = []
var _built_moods: Dictionary = {}
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
	_moving.clear()
	_pivots.clear()
	_built_moods.clear()
	_bulb = null
	_build()
	apply(Mood.NORMAL, {})
	return self


## Cantidad de piezas (MeshInstance3D) de la mascota: cada una es 1 draw
## call, más otro por el contorno si lo tiene.
func mesh_count() -> int:
	return find_children("*", "MeshInstance3D", true, false).size()


## Ojos, boca y efectos que se ven ahora (ej. ["eyes_happy", "mouth_happy"]); para los tests.
func visible_features() -> Array[String]:
	var out: Array[String] = []
	for key: String in _features:
		if (_features[key] as Node3D).visible:
			out.append(key)
	out.sort()
	return out


## Color vivo del plástico: la maqueta es un juguete de colores saturados.
## Sube un poco saturación y brillo (sin cambiar el tono: el jugador sigue
## siendo "el rojo"). Blanco, negro y grafito quedan igual.
## Ejemplo: el rojo #E24B4A se ve #FF3230 en la parte iluminada (la maqueta: #F53047).
static func vivid(col: Color) -> Color:
	if col.s < 0.25 or col.v < 0.3:
		return col
	return Color.from_hsv(col.h, minf(1.0, col.s * 1.18 + 0.1), minf(1.0, col.v * 1.08 + 0.05))


## Gema de la panza: brillante y de un tono vecino al del jugador (como en
## la maqueta: rojo -> dorada, azul -> celeste, amarillo -> naranja,
## verde -> lima). Blanco, negro y grafito: dorada.
static func gem_color(col: Color) -> Color:
	if col.s < 0.25:
		return GOLD
	var h := col.h
	if h < 0.05 or h > 0.95:
		h = 0.14
	else:
		h = fposmod(h - 0.07, 1.0)
	return Color.from_hsv(h, 0.72, 1.0)


# --- Construcción -------------------------------------------------------------------

func _build() -> void:
	var col := color
	_squash = _node(self, Vector3.ZERO)
	_lift = _node(_squash, Vector3.ZERO)
	_turn = _node(_lift, Vector3.ZERO)
	var sph := Mascot3DMeshes.sphere()
	var sph_s := Mascot3DMeshes.sphere(10, 16)

	# Piernas cortitas (casi escondidas bajo el cuerpo) y zapatos oscuros
	# brillantes, chicos: en la maqueta apenas asoman debajo del cuerpo.
	for side in [-1.0, 1.0]:
		var leg := _node(_turn, Vector3(side * 0.66, 0.95, 0.0))
		_part(leg, sph_s, Kind.PLASTIC, col, Vector3(0, -0.25, 0), Vector3(0.52, 0.55, 0.52), INK_W_SMALL)
		_legs.append(leg)
		var shoe := _node(_turn, Vector3(side * 0.8, 0.3, 0.22))
		_part(shoe, sph_s, Kind.SHOE, UiTheme.MASCOT_SHOE, Vector3.ZERO, Vector3(0.6, 0.34, 0.72), INK_W_SMALL)
		_shoes.append(shoe)

	# Cuerpo: superelipse de revolución, más ancha abajo, con la gema que brilla.
	_body = _node(_turn, BODY_C)
	_body_mesh = _node(_body, Vector3.ZERO)
	var body_mesh := Mascot3DMeshes.lathe("body2", Mascot3DMeshes.blob_profile(BODY_R.x, BODY_R.y, 0.0, 2.6, 0.16), 32,
		BODY_R.z / BODY_R.x)
	_part(_body_mesh, body_mesh, Kind.BODY, col, Vector3.ZERO, Vector3.ONE, INK_W)
	var robot := style == STYLE_ROBOT
	var gem_col := UiTheme.MASCOT_METAL if robot else gem_color(col)
	var gem_at := Vector3(0, -0.05, BODY_R.z - 0.06)
	if not robot:  # Halo: el brillo de la gema tiñe el plástico alrededor.
		var body_mid: Color = plastic_ramp(col)[1]
		_part(_body_mesh, sph_s, Kind.HALO, gem_col.lerp(body_mid, 0.35), gem_at + Vector3(0, 0, -0.34),
			Vector3(0.68, 0.68, 0.4), 0.0, Vector3.ZERO, body_mid)
	_part(_body_mesh, Mascot3DMeshes.torus(0.16), Kind.EYE, UiTheme.INK, gem_at + Vector3(0, 0, 0.02),
		Vector3(0.38, 0.38, 0.38), 0.0, Vector3(PI / 2.0 - 0.2, 0, 0))
	_part(_body_mesh, sph_s, Kind.METAL if robot else Kind.GEM, gem_col, gem_at + Vector3(0, 0, 0.03),
		Vector3(0.33, 0.33, 0.18), 0.0)

	# Brazos: tubo + mano redonda, con el pivote en el hombro.
	for side in [-1.0, 1.0]:
		var shoulder := _node(_body, SHOULDER * Vector3(side, 1, 1))
		var arm := Mascot3DMeshes.tube("arm3", PackedVector3Array([Vector3(0, 0, 0), Vector3(0, -ARM_LEN * 0.85, 0)]),
			PackedFloat32Array([ARM_R, ARM_R * 1.04]), 12)
		_arm_tubes.append(_part(shoulder, arm, Kind.PLASTIC, col, Vector3.ZERO, Vector3.ONE, INK_W_SMALL))
		_hands.append(_part(shoulder, sph_s, Kind.PLASTIC, col, Vector3(0, -ARM_LEN, 0), Vector3.ONE * HAND_R, INK_W_SMALL))
		_arms.append(shoulder)

	# Cabeza: esfera un poco más ancha que alta; la cara está pintada en su material.
	_head = _node(_turn, HEAD_C)
	_part(_head, Mascot3DMeshes.sphere(32, 64), Kind.HEAD, col, Vector3.ZERO, HEAD_R, INK_W)
	if shading == Shading.STANDARD:  # El material estándar no pinta la cara: va la almohadilla.
		var pad := Mascot3DMeshes.face_pad("face", HEAD_R, FACE_C, FACE_R, 0.05)
		_part(_head, pad, Kind.FACE, UiTheme.PAPER, Vector3.ZERO, Vector3.ONE, 0.0)
	_acc = _node(_head, Vector3.ZERO)
	_eyes = _node(_head, Vector3.ZERO)
	_build_face()
	_build_accessory()


func _build_face() -> void:
	var eye_ink := UiTheme.MASCOT_EYE
	var sph_s := Mascot3DMeshes.sphere(12, 20)
	var normal_eyes := _feature("eyes_open", _eyes)
	var sad_eyes := _feature("eyes_sad", _eyes)
	var surprised_eyes := _feature("eyes_surprised", _eyes)
	var happy_eyes := _feature("eyes_happy", _eyes)
	var blink_eyes := _feature("eyes_blink", _eyes)
	_cheeks = _node(_head, Vector3.ZERO)
	for sx in [-1.0, 1.0]:
		var e := Vector2(sx * EYE_X, EYE_Y)
		# Normal: óvalo negro brillante (su propio reflejo sale del shader) y dos reflejos pintados.
		var eye := _on_face(normal_eyes, e, -0.12)
		_eye_dome(eye, EYE_R)
		# Triste: ojo más chico y bajo, con la ceja caída hacia afuera.
		var sad := _on_face(sad_eyes, e + Vector2(0, -0.22), -0.1)
		_eye_dome(sad, Vector3(0.4, 0.58, 0.26))
		_face_tube(sad_eyes, "brow%d" % sx, [e + Vector2(-sx * 0.58, 0.95), e + Vector2(sx * 0.42, 0.62)], 0.12, eye_ink)
		# Sorpresa: ojo blanco con aro de tinta, pupila chica y cejas bien arriba.
		var sur := _on_face(surprised_eyes, e, -0.02)
		_part(sur, sph_s, Kind.FACE, UiTheme.PAPER, Vector3.ZERO, Vector3(0.44, 0.44, 0.12), 0.0)
		_part(sur, Mascot3DMeshes.torus(0.2), Kind.EYE, eye_ink, Vector3(0, 0, 0.04), Vector3(0.47, 0.47, 0.47),
			0.0, Vector3(PI / 2.0, 0, 0))
		_part(sur, sph_s, Kind.EYE, eye_ink, Vector3(0, 0, 0.1), Vector3(0.24, 0.24, 0.1), 0.0)
		_part(sur, sph_s, Kind.FLAT, Color.WHITE, Vector3(-0.07, 0.09, 0.19), Vector3(0.08, 0.08, 0.03), 0.0)
		_face_tube(surprised_eyes, "sbrow%d" % sx, _arc(e + Vector2(0, 0.35), 0.42, 1.2, 1.8, 7), 0.1, eye_ink)
		# Feliz: arco grueso (^), más abierto y alto como en la maqueta.
		_face_tube(happy_eyes, "happy%d" % sx, _arc(e + Vector2(0, -0.38), 0.62, 1.1, 1.9, 11), 0.2, eye_ink)
		# Cachetes rosados que se funden con la cara (feliz, ganadora, riendo):
		# en la maqueta son dos discos bien visibles, pegados a los ojos.
		var blush := _on_face(_cheeks, Vector2(sx * (EYE_X + 0.55), EYE_Y - 0.95), -0.3)
		_part(blush, sph_s, Kind.BLUSH, BLUSH, Vector3.ZERO, Vector3(0.98, 0.66, 0.4), 0.0)
		# Parpadeo: una rayita.
		_face_tube(blink_eyes, "blink%d" % sx, [e + Vector2(-0.44, 0), e + Vector2(0.44, 0)], 0.12, eye_ink)

	# Bocas.
	var m := Vector2(0, MOUTH_Y)
	var happy := _feature("mouth_happy", _head)
	_open_mouth(happy, m + Vector2(0, 0.3), Vector2(0.86, 0.7), "smile2")
	# Sonrisa cerrada (saludo con ánimo normal, como 1P en la maqueta del lobby).
	var smile := _feature("mouth_smile", _head)
	_face_tube(smile, "smile", _arc(m + Vector2(0, 0.42), 0.5, 1.2, 1.8, 9, true), 0.11, eye_ink)
	var sad_mouth := _feature("mouth_sad", _head)
	_face_tube(sad_mouth, "frown", _arc(m + Vector2(0, -0.45), 0.46, 1.2, 1.8, 9, true), 0.11, eye_ink)
	_tear = _node(sad_mouth, Vector3.ZERO)
	_part(_tear, sph_s, Kind.GLASS, PlayerAvatar.TEAR, Vector3.ZERO, Vector3(0.24, 0.3, 0.16), 0.0)
	var sur_mouth := _feature("mouth_surprised", _head)
	var o := _on_face(sur_mouth, m + Vector2(0, 0.08), -0.04)
	_part(o, sph_s, Kind.EYE, eye_ink, Vector3.ZERO, Vector3(0.36, 0.42, 0.1), 0.0)
	_part(o, sph_s, Kind.MOUTH, MOUTH_IN, Vector3(0, 0, 0.05), Vector3(0.26, 0.32, 0.06), 0.0)
	_part(o, sph_s, Kind.FLAT, PlayerAvatar.TONGUE, Vector3(0, -0.15, 0.08), Vector3(0.18, 0.12, 0.05), 0.0)
	if style == STYLE_ROBOT:
		var grille := _feature("mouth_robot", _head)
		var g := _on_face(grille, m + Vector2(0, 0.2), -0.03)
		_part(g, Mascot3DMeshes.extrude("grille", Mascot3DMeshes.rounded_rect_outline(0.72, 0.28), 0.08),
			Kind.EYE, eye_ink, Vector3.ZERO, Vector3.ONE, 0.0)
		for k in 3:
			_part(g, sph_s, Kind.METAL, UiTheme.MASCOT_METAL, Vector3((k - 1) * 0.36, 0, 0.08),
				Vector3(0.07, 0.15, 0.04), 0.0)


## Ojo negro brillante: domo con el reflejo del shader, un reflejo blanco
## grande arriba a la izquierda y uno chico abajo a la derecha.
func _eye_dome(parent: Node3D, scl: Vector3) -> void:
	var sph_s := Mascot3DMeshes.sphere(12, 20)
	_part(parent, sph_s, Kind.EYE, UiTheme.MASCOT_EYE, Vector3.ZERO, scl, 0.0)
	# Reflejos: una gota arriba a la izquierda (chica: el ojo se lee negro y
	# profundo) y un reflejo celeste abajo a la derecha que lo hace brillar
	# como en la maqueta.
	var k := scl.x / 0.56
	_part(parent, sph_s, Kind.FLAT, Color.WHITE, Vector3(-0.3, 0.5, 0.8) * scl, Vector3(0.17, 0.22, 0.06) * k, 0.0)
	_part(parent, sph_s, Kind.FLAT, Color(0.8, 0.9, 1.0), Vector3(0.34, -0.52, 0.76) * scl, Vector3(0.1, 0.09, 0.04) * k, 0.0)


## Boca abierta en D: borde de tinta, interior rojo oscuro y lengua.
func _open_mouth(parent: Node3D, at: Vector2, r: Vector2, key: String) -> void:
	var n := _on_face(parent, at, -0.02)
	_part(n, Mascot3DMeshes.extrude(key, Mascot3DMeshes.ellipse_outline(r.x, r.y, 20, true), 0.08),
		Kind.EYE, UiTheme.MASCOT_EYE, Vector3.ZERO, Vector3.ONE, 0.0)
	_part(n, Mascot3DMeshes.extrude(key + "_in", Mascot3DMeshes.ellipse_outline(r.x - 0.11, r.y - 0.11, 20, true), 0.08),
		Kind.MOUTH, MOUTH_IN, Vector3(0, -0.06, 0.03), Vector3.ONE, 0.0)
	_part(n, Mascot3DMeshes.sphere(12, 20), Kind.FLAT, PlayerAvatar.TONGUE, Vector3(0, -r.y * 0.62, 0.1),
		Vector3(r.x * 0.46, r.y * 0.3, 0.05), 0.0)


## Caras y efectos de los ánimos nuevos: se arman la primera vez que se piden.
func _build_mood(p_mood: int) -> void:
	if _built_moods.has(p_mood):
		return
	_built_moods[p_mood] = true
	var eye_ink := UiTheme.MASCOT_EYE
	var sph_s := Mascot3DMeshes.sphere(12, 20)
	match p_mood:
		Mood.ANGRY:
			var eyes := _feature("eyes_angry", _eyes)
			var brows := _feature("brows_angry", _eyes)
			for sx in [-1.0, 1.0]:
				var e := Vector2(sx * EYE_X, EYE_Y)
				_eye_dome(_on_face(eyes, e + Vector2(0, -0.12), -0.1), Vector3(0.5, 0.66, 0.3))
				# Cejas fruncidas: bajas hacia el centro.
				_face_tube(brows, "abrow%d" % sx, [e + Vector2(-sx * 0.65, 0.6), e + Vector2(sx * 0.55, 1.05)], 0.16, eye_ink)
			var mouth := _feature("mouth_angry", _head)
			var n := _on_face(mouth, Vector2(0, MOUTH_Y + 0.1), -0.02)
			_part(n, Mascot3DMeshes.extrude("teeth_ink", Mascot3DMeshes.rounded_rect_outline(0.62, 0.3), 0.07),
				Kind.EYE, eye_ink, Vector3.ZERO, Vector3.ONE, 0.0)
			_part(n, Mascot3DMeshes.extrude("teeth", Mascot3DMeshes.rounded_rect_outline(0.5, 0.18), 0.07),
				Kind.FACE, UiTheme.PAPER, Vector3(0, 0, 0.03), Vector3.ONE, 0.0)
			_part(n, sph_s, Kind.EYE, eye_ink, Vector3(0, 0, 0.1), Vector3(0.46, 0.03, 0.03), 0.0)
			# Venita de enojo en la frente (cuatro arquitos rojos).
			var fx := _feature("fx_angry", _head)
			var v := _on_face(fx, Vector2(HEAD_R.x * 0.5, HEAD_R.y * 0.52), 0.0)
			for k in 4:
				var a := PI * 0.25 + k * PI * 0.5
				var pts := _arc(Vector2.ZERO, 0.3, a / PI + 0.35, a / PI + 0.65, 5)
				var p3 := PackedVector3Array()
				for p: Vector2 in pts:
					p3.append(Vector3(p.x + cos(a) * 0.5, p.y + sin(a) * 0.5, 0.05))
				_part(v, Mascot3DMeshes.tube("vein%d" % k, p3, PackedFloat32Array([0.09, 0.09, 0.09, 0.09, 0.09]), 6),
					Kind.PLASTIC, VEIN, Vector3.ZERO, Vector3.ONE, 0.0)
		Mood.DIZZY:
			var eyes := _feature("eyes_dizzy", _eyes)
			var spirals: Array[Node3D] = []
			for sx in [-1.0, 1.0]:
				var n := _on_face(eyes, Vector2(sx * EYE_X, EYE_Y), 0.04)
				var spin := _node(n, Vector3.ZERO)
				spin.set_meta("dir", sx)
				var pts := PackedVector3Array()
				var radii := PackedFloat32Array()
				for i in 23:
					var k := i / 22.0
					pts.append(Vector3(cos(k * 1.75 * TAU), sin(k * 1.75 * TAU), 0.0) * (0.08 + 0.62 * k))
					radii.append(0.1)
				_part(spin, Mascot3DMeshes.tube("spiral", pts, radii, 6), Kind.EYE, eye_ink, Vector3.ZERO, Vector3.ONE, 0.0)
				spirals.append(spin)
			_moving["spirals"] = spirals
			var mouth := _feature("mouth_dizzy", _head)
			var wave: Array = []
			for i in 13:
				var x := -1.0 + 2.0 * i / 12.0
				wave.append(Vector2(x * 0.6, MOUTH_Y + 0.1 + sin(x * TAU) * 0.13))
			_face_tube(mouth, "wavy", wave, 0.1, eye_ink)
			# Estrellitas que dan vueltas sobre la cabeza.
			var fx := _feature("fx_dizzy", _head)
			var stars: Array[Node3D] = []
			for k in 3:
				var s := _node(fx, Vector3.ZERO)
				_part(s, Mascot3DMeshes.extrude("star5", Mascot3DMeshes.star_outline(5, 0.5), 0.3), Kind.PLASTIC, GOLD,
					Vector3.ZERO, Vector3.ONE * 0.66, INK_W_SMALL)
				stars.append(s)
			_moving["dizzy_stars"] = stars
		Mood.SLEEPY:
			var eyes := _feature("eyes_sleepy", _eyes)
			for sx in [-1.0, 1.0]:
				var e := Vector2(sx * EYE_X, EYE_Y)
				_face_tube(eyes, "sleep%d" % sx, _arc(e + Vector2(0, 0.24), 0.5, 1.15, 1.85, 11, true), 0.13, eye_ink)
			var mouth := _feature("mouth_sleepy", _head)
			var o := _on_face(mouth, Vector2(0, MOUTH_Y + 0.05), -0.04)
			_part(o, sph_s, Kind.EYE, eye_ink, Vector3.ZERO, Vector3(0.2, 0.25, 0.08), 0.0)
			_moving["sleepy_mouth"] = [o]
			var fx := _feature("fx_sleepy", _head)
			var zs: Array[Node3D] = []
			for k in 2:
				var z := _node(fx, Vector3.ZERO)
				var zp := PackedVector3Array([Vector3(-0.8, 0.8, 0), Vector3(0.8, 0.8, 0), Vector3(-0.8, -0.8, 0),
					Vector3(0.8, -0.8, 0)])
				_part(z, Mascot3DMeshes.tube("zee", zp, PackedFloat32Array([0.2, 0.2, 0.2, 0.2]), 6, true),
					Kind.EYE, UiTheme.INK, Vector3.ZERO, Vector3.ONE * 0.6, 0.0)
				zs.append(z)
			_moving["zees"] = zs
			# Globito en la nariz, que se infla y desinfla.
			var bub := _on_face(fx, Vector2(0.9, MOUTH_Y + 0.55), 0.1)
			_part(bub, Mascot3DMeshes.sphere(), Kind.GLASS, Color(0.8, 0.92, 1.0), Vector3.ZERO, Vector3.ONE, INK_W_SMALL * 0.6)
			_moving["bubble"] = [bub]
		Mood.WINNER, Mood.LAUGHING:
			if not _features.has("mouth_big"):
				_open_mouth(_feature("mouth_big", _head), Vector2(0, MOUTH_Y + 0.22), Vector2(0.76, 0.7), "big_smile")
			if p_mood == Mood.WINNER:
				var eyes := _feature("eyes_winner", _eyes)
				var stars: Array[Node3D] = []
				for sx in [-1.0, 1.0]:
					var n := _on_face(eyes, Vector2(sx * EYE_X, EYE_Y), 0.02)
					var s := _node(n, Vector3.ZERO)
					s.set_meta("dir", sx)
					_part(s, Mascot3DMeshes.extrude("star5", Mascot3DMeshes.star_outline(5, 0.5), 0.3), Kind.PLASTIC, GOLD,
						Vector3.ZERO, Vector3(0.72, 0.72, 0.4), INK_W_SMALL * 0.8)
					_part(s, sph_s, Kind.FLAT, Color.WHITE, Vector3(-0.16, 0.22, 0.15), Vector3(0.13, 0.11, 0.04), 0.0)
					stars.append(s)
				_moving["star_eyes"] = stars
				var fx := _feature("fx_winner", _head)
				var sparks: Array[Node3D] = []
				for k in 2:
					var s := _node(fx, Vector3((-1.0 if k == 0 else 1.0) * (HEAD_R.x + 0.7), -HEAD_R.y * 0.3 + k * 1.0, 0.8))
					_part(s, Mascot3DMeshes.extrude("spark4", Mascot3DMeshes.star_outline(4, 0.28), 0.12), Kind.GLOW,
						Color(1.0, 0.97, 0.8), Vector3.ZERO, Vector3.ONE * 0.8, INK_W_SMALL * 0.6)
					sparks.append(s)
				_moving["sparks"] = sparks
			else:
				var eyes := _feature("eyes_laugh", _eyes)
				for sx in [-1.0, 1.0]:
					var e := Vector2(sx * EYE_X, EYE_Y)
					var pts := [e + Vector2(sx * 0.32, 0.37), e + Vector2(-sx * 0.28, 0.0), e + Vector2(sx * 0.32, -0.37)]
					_face_tube(eyes, "chev%d" % sx, pts, 0.15, eye_ink)
				var fx := _feature("tears_laugh", _head)
				var drops: Array[Node3D] = []
				for k in 2:
					var d := _node(fx, Vector3.ZERO)
					_part(d, sph_s, Kind.GLASS, PlayerAvatar.TEAR, Vector3.ZERO, Vector3(0.28, 0.34, 0.18), INK_W_SMALL * 0.6)
					drops.append(d)
				_moving["laugh_tears"] = drops


func _build_accessory() -> void:
	var col := color
	var sph := Mascot3DMeshes.sphere(16, 28)
	var sph_s := Mascot3DMeshes.sphere(10, 16)
	var ink := UiTheme.INK
	var top := HEAD_R.y
	match style:
		0:  # Antena: palito de tinta con una bola brillante; se dobla con la inercia.
			var piv := _pivot(Vector3(0, top - 0.2, 0.05), 0.0, 0.25, 1.6, 2.0, 0.15)
			var stem := Mascot3DMeshes.tube("antenna3", PackedVector3Array([
				Vector3(0, 0, 0), Vector3(0.02, 0.6, 0), Vector3(0.07, 1.2, 0)]),
				PackedFloat32Array([0.15, 0.14, 0.13]), 8)
			_part(piv, stem, Kind.EYE, ink, Vector3.ZERO, Vector3.ONE, 0.0)
			_part(_acc, sph_s, Kind.SHOE, UiTheme.MASCOT_SHOE, Vector3(0, top + 0.02, 0.05), Vector3(0.5, 0.4, 0.5), INK_W_SMALL)
			_part(piv, sph, Kind.PLASTIC, col, Vector3(0.1, 1.72, 0.0), Vector3(0.72, 0.72, 0.72), INK_W_SMALL)
		1:  # Oso: orejas redondas, un poco hundidas en la cabeza.
			for sx in [-1.0, 1.0]:
				var piv := _pivot(Vector3.ZERO, 0.0, sx * 0.1, 1.0, 1.0, 0.0)
				var ear := _node(piv, Vector3(sx * 2.95, 2.9, -0.45))
				ear.rotation.z = -sx * 0.4
				_part(ear, sph, Kind.PLASTIC, col, Vector3.ZERO, Vector3(1.3, 1.3, 0.9), INK_W)
				_part(ear, sph_s, Kind.PLASTIC, vivid(col).darkened(0.12), Vector3(0, -0.05, 0.56), Vector3(0.66, 0.66, 0.36), 0.0)
		2:  # Gato: orejas puntiagudas con el interior naranja.
			for sx in [-1.0, 1.0]:
				var piv := _pivot(Vector3(sx * 2.3, 2.15, -0.2), -sx * 0.4, sx * 0.28, 1.0, 1.0, 0.0)
				_part(piv, _cone("cat", 1.45, 3.2), Kind.PLASTIC, col, Vector3.ZERO, Vector3(1, 1, 0.62), INK_W)
				_part(piv, _cone("cat_in", 0.85, 2.3), Kind.PLASTIC, UiTheme.MASCOT_EAR_INNER.lerp(col, 0.1),
					Vector3(0, 0.5, 0.6), Vector3(1, 1, 0.3), 0.0)
		3:  # Brote: tallito y dos hojas que se doblan con la inercia.
			var stem := Mascot3DMeshes.tube("sprout2", PackedVector3Array([
				Vector3(0, top - 0.25, 0), Vector3(0, top + 0.3, 0), Vector3(0.05, top + 0.75, 0)]),
				PackedFloat32Array([0.2, 0.18, 0.16]), 8)
			_part(_acc, stem, Kind.LEAF, UiTheme.LEAF.darkened(0.25), Vector3.ZERO, Vector3.ONE, INK_W_SMALL)
			for sx in [-1.0, 1.0]:
				var piv := _pivot(Vector3(0.05, top + 0.8, 0.0), 0.0, sx * 0.4, 1.0, 1.0, 0.0)
				var leaf := _node(piv, Vector3(sx * 0.95, 0.12, 0.0))
				leaf.rotation = Vector3(0.0, -sx * 0.25, sx * 0.42)
				_part(leaf, sph, Kind.LEAF, UiTheme.LEAF, Vector3.ZERO, Vector3(1.08, 0.56, 0.3), INK_W_SMALL)
				var vein := Mascot3DMeshes.tube("leafvein", PackedVector3Array([Vector3(-0.75, 0, 0.3), Vector3(0.6, 0.04, 0.3)]),
					PackedFloat32Array([0.05, 0.03]), 5)
				_part(leaf, vein, Kind.FLAT, UiTheme.LEAF.darkened(0.3), Vector3.ZERO, Vector3(sx, 1, 1), 0.0)
		STYLE_ROBOT:  # Auriculares de metal, antena con foco y tornillos.
			for sx in [-1.0, 1.0]:
				# Auricular: copa de metal redondeada con la tapa de goma oscura.
				_part(_acc, sph, Kind.METAL, UiTheme.MASCOT_METAL, Vector3(sx * (HEAD_R.x - 0.12), -0.1, 0),
					Vector3(0.5, 1.02, 1.02), INK_W_SMALL)
				_part(_acc, sph_s, Kind.SHOE, UiTheme.MASCOT_SOCKET, Vector3(sx * (HEAD_R.x + 0.3), -0.1, 0),
					Vector3(0.14, 0.62, 0.62), 0.0)
				var bolt := Mascot3DMeshes.ellipsoid_point(HEAD_R, Vector2(sx * 2.1, 2.3))
				_part(_acc, sph_s, Kind.METAL, UiTheme.MASCOT_BOLT, bolt, Vector3(0.22, 0.22, 0.14), INK_W_SMALL * 0.6)
			var piv := _pivot(Vector3(0, top - 0.1, 0), 0.0, 0.15, 1.3, 1.0, 0.12)
			_part(piv, sph_s, Kind.SHOE, UiTheme.MASCOT_SOCKET, Vector3(0, 0.05, 0), Vector3(0.66, 0.4, 0.66), INK_W_SMALL)
			var mast := Mascot3DMeshes.tube("mast", PackedVector3Array([Vector3(0, 0.2, 0), Vector3(0, 1.4, 0)]),
				PackedFloat32Array([0.11, 0.11]), 8)
			_part(piv, mast, Kind.METAL, UiTheme.MASCOT_METAL, Vector3.ZERO, Vector3.ONE, 0.08)
			_bulb = _part(piv, sph, Kind.GLOW, UiTheme.DANGER.lerp(UiTheme.ACCENT, 0.3), Vector3(0, 1.72, 0),
				Vector3(0.52, 0.52, 0.52), INK_W_SMALL)
		STYLE_HORNS:  # Diablito: cuernos curvos que se afinan (rígidos: solo se mecen).
			var horn_col := col.darkened(0.4) if col.get_luminance() > 0.25 else col.lightened(0.45)
			for sx in [-1.0, 1.0]:
				var pts := PackedVector3Array()
				var radii := PackedFloat32Array()
				for i in 7:
					var k := i / 6.0
					pts.append(Vector3(sx * (0.9 * sin(k * 1.9) * 0.9), k * 1.8, 0.15 * k))
					radii.append(lerpf(0.64, 0.1, pow(k, 0.9)))
				var horn := Mascot3DMeshes.tube("horn%d" % sx, pts, radii, 12)
				var piv := _pivot(Vector3(sx * 1.7, 2.75, 0.25), -sx * 0.3, 0.0, 0.0, 1.0, 0.0)
				_part(piv, horn, Kind.PLASTIC, horn_col, Vector3.ZERO, Vector3.ONE, INK_W_SMALL)
		STYLE_BUNNY:  # Conejo: orejas largas con el interior rosa; giran desde la base.
			for sx in [-1.0, 1.0]:
				# Base bien metida en la cabeza: la punta tiene que entrar en la celda
				# del horneado también estirada en el salto (squash -0,22).
				var piv := _pivot(Vector3(sx * 1.4, 2.9, -0.25), -sx * 0.18, sx * 0.5, 1.0, 1.0, 0.0)
				_part(piv, sph, Kind.PLASTIC, col, Vector3(0, 0.95, 0), Vector3(0.9, 2.05, 0.62), INK_W)
				_part(piv, sph_s, Kind.PLASTIC, UiTheme.MASCOT_BUNNY_INNER, Vector3(0, 0.9, 0.44),
					Vector3(0.44, 1.35, 0.22), 0.0)


## Oreja de gato: cono de base redonda y punta apenas redondeada.
func _cone(key: String, r: float, h: float) -> Mesh:
	var prof := PackedVector2Array([Vector2(0, 0), Vector2(r * 0.85, 0.0), Vector2(r, 0.18), Vector2(r * 0.55, h * 0.5),
		Vector2(r * 0.16, h * 0.9), Vector2(0.06, h), Vector2(0, h)])
	return Mascot3DMeshes.lathe(key, prof, 20)


## Pivote de un accesorio que se dobla con la inercia (ver `_pivots`).
func _pivot(pos: Vector3, base_rot: float, flop_k: float, swing_k: float, sway_k: float, shrink_k: float) -> Node3D:
	var n := _node(_acc, pos)
	n.rotation.z = base_rot
	_pivots.append([n, base_rot, flop_k, swing_k, sway_k, shrink_k])
	return n


# --- Poses ---------------------------------------------------------------------------

## Aplica un ánimo y una pose. anim: mismas claves que PlayerAvatar.draw_mascot
## (t, walk, look, squash, wave, dance, dance_kind, defeat, greet, flop) más
## `blink` (bool), `bob` (u, respiración de la cabeza), `hello` (0..1: una
## mano bien arriba, quieta, como en las tarjetas del lobby de la maqueta;
## con ánimo normal sonríe), `lift` (false: sin
## el salto propio de la pose, ver pose_lift), `in_place` (true: sin nada que
## mueva la mascota entera: salto, squash & stretch, inclinación,
## respiración ni rebote del paso; los suma la 2D sobre el sprite) y `fx`
## (false: sin los efectos alrededor de la cabeza, `fx_*`: estrellitas del
## mareo, Z y globito, destellos, venita). `xform` se ignora (es del lienzo
## 2D). Todo es opcional: {} es la pose quieta de frente.
## Ejemplo: apply(Mood.HAPPY, {"t": 0.4, "dance": 1.0, "dance_kind": PlayerAvatar.DANCE_SPIN})
## da una vuelta de verdad sobre sí misma (en 2D solo se angosta la cara).
func apply(p_mood: int, anim: Dictionary) -> void:
	p_mood = clampi(p_mood, 0, Mood.size() - 1)
	_build_mood(p_mood)
	var has_t := anim.has("t")
	var t := float(anim.get("t", 0.0))
	var walk := float(anim.get("walk", -1.0))
	var walking := walk >= 0.0
	var bob := float(anim.get("bob", 0.0)) * U
	var q := pose(p_mood, anim, style)
	var lean: float = q.lean
	var tilt: float = q.tilt
	var head_dy: float = q.head_dy
	var spin: float = q.spin
	var swing: float = q.swing
	var tuck: float = q.tuck
	var shoulder_dy: float = q.shoulder_dy
	var arm_l: float = q.arm_l
	var arm_r: float = q.arm_r
	var sway: float = q.sway
	var breathing: float = q.breathing
	var sq: float = q.squash
	var lift: float = q.lift if bool(anim.get("lift", true)) else 0.0
	# En el lugar: lo que mueve la mascota entera (salto, squash & stretch,
	# inclinación, respiración, rebote del paso) lo pone quien dibuja el sprite.
	var in_place := bool(anim.get("in_place", false))
	if in_place:
		lift = 0.0
		sq = 0.0
		lean = 0.0
		breathing = 0.0
		shoulder_dy = 0.0
	var flop: float = q.flop
	var look: Vector2 = q.look
	var hello: float = q.hello
	var hello_side: float = q.hello_side

	# --- Aplicar la pose a los nodos ---
	# Squash & stretch alrededor de los pies; la inclinación (lean) gira sobre los pies.
	_squash.basis = Basis(Vector3.BACK, lean) * Basis.from_scale(Vector3(1.0 + sq * 0.6, 1.0 - sq * 0.6, 1.0 + sq * 0.6))
	var step_bob := absf(sin(walk * TAU)) * 0.3 if walking and not in_place else 0.0
	_lift.position.y = step_bob + lift * U
	# En 3D la mascota gira hacia donde camina o mira (en 2D solo se corren los ojos).
	_turn.rotation.y = look.x * (0.45 if walking else 0.2) + spin
	_head.position = HEAD_C + Vector3(0, -bob - head_dy * U, 0)
	_head.rotation = Vector3(look.y * 0.25, look.x * 0.2, -tilt)
	_body.position = BODY_C + Vector3(0, -bob * 0.4, 0)
	_body_mesh.scale = Vector3(1.0 - 0.012 * breathing, 1.0 + 0.03 * breathing, 1.0 - 0.012 * breathing)
	_eyes.position = Vector3(look.x * 0.18, -look.y * 0.14, 0)
	for p: Array in _pivots:
		var n: Node3D = p[0]
		n.rotation.z = p[1] - (flop * p[2] + swing * p[3] + sway * p[4])
		n.scale = Vector3(1.0, 1.0 - flop * p[5], 1.0)

	# Piernas y zapatos que se alternan al caminar (y se recogen en el aire).
	for i in 2:
		var side := -1.0 if i == 0 else 1.0
		var phase := sin(walk * TAU) * side if walking else 0.0
		var up := maxf(0.0, phase) + tuck
		_shoes[i].position = Vector3(side * 0.8, 0.34 + up * 0.42, 0.24 + phase * 0.45)
		_shoes[i].rotation.x = -maxf(0.0, phase) * 0.35
		_legs[i].position = Vector3(side * 0.62, 0.95 + up * 0.2, phase * 0.2)

	# Brazos: cada uno apunta según su ángulo; si la mano quedaría dentro de
	# la cabeza o del cuerpo, se adelanta (en 2D se dibujaba "delante").
	for i in 2:
		var side := -1.0 if i == 0 else 1.0
		var angle := arm_l if i == 0 else arm_r
		var fwd := sin(walk * TAU) * side * 0.7 if walking else 0.0
		_aim_arm(i, side, angle, fwd, shoulder_dy * U, hello if side == hello_side else 0.0)

	# --- Cara según el ánimo ---
	_mood = p_mood
	var blinking := bool(anim.get("blink", false))
	if not blinking and (p_mood == Mood.NORMAL or p_mood == Mood.ANGRY) and t > 0.0 and has_t:
		# Cada ~3,3 s, desfasado por estilo; una de cada tres veces, doble (como en 2D).
		var bt := t + style * 1.37
		var cycle := floorf(bt / 3.3)
		var ph := bt - cycle * 3.3
		blinking = ph < 0.12 or (posmod(int(cycle), 3) == 1 and ph > 0.24 and ph < 0.36)
	var show: Array[String] = []
	match p_mood:
		Mood.HAPPY:
			show = ["eyes_happy", "mouth_happy"]
		Mood.SAD:
			show = ["eyes_sad", "mouth_sad"]
		Mood.SURPRISED:
			show = ["eyes_surprised", "mouth_surprised"]
		Mood.ANGRY:
			show = ["eyes_blink" if blinking else "eyes_angry", "brows_angry", "mouth_angry", "fx_angry"]
		Mood.DIZZY:
			show = ["eyes_dizzy", "mouth_dizzy", "fx_dizzy"]
		Mood.SLEEPY:
			show = ["eyes_sleepy", "mouth_sleepy", "fx_sleepy"]
		Mood.WINNER:
			show = ["eyes_winner", "mouth_big", "fx_winner"]
		Mood.LAUGHING:
			show = ["eyes_laugh", "mouth_big", "tears_laugh"]
		_:
			show = ["eyes_blink" if blinking else "eyes_open"]
			if style == STYLE_ROBOT:
				show.append("mouth_robot")
			elif hello > 0.35:  # Saludando con ánimo normal: sonrisa cerrada.
				show.append("mouth_smile")
	# fx = false: los efectos alrededor de la cabeza (estrellitas, Z y globito,
	# destellos, venita) los dibuja la 2D encima del sprite.
	if not bool(anim.get("fx", true)):
		show = show.filter(func(k: String) -> bool: return not k.begins_with("fx_"))
	for key: String in _features:
		(_features[key] as Node3D).visible = key in show
	_cheeks.visible = p_mood == Mood.HAPPY or p_mood == Mood.WINNER or p_mood == Mood.LAUGHING
	_animate_features(p_mood, t, has_t)
	if _bulb:
		var glow := 0.55 + 0.45 * absf(sin(t * 3.0 + style))
		_bulb.scale = Vector3.ONE * 0.52 * (0.94 + 0.06 * glow)


## Números de la pose (*pose por capas*), los mismos que calcula
## PlayerAvatar.draw_mascot, en u: inclinaciones, ángulo de cada brazo,
## salto, aplastado, giro… Estática: sirve sin armar la mascota.
## Ejemplo: pose(Mood.HAPPY, {"t": 10.25, "dance": 1.0, "dance_kind": PlayerAvatar.DANCE_HOPS}, 6).lift
## da 12 (u): el conejo está en lo más alto de un saltito.
static func pose(p_mood: int, anim: Dictionary, p_style: int) -> Dictionary:
	var st := posmod(p_style, PlayerAvatar.STYLE_NAMES.size())
	var t := float(anim.get("t", 0.0))
	var walk := float(anim.get("walk", -1.0))
	var look: Vector2 = anim.get("look", Vector2.ZERO)
	var sq := float(anim.get("squash", 0.0))
	var wave := bool(anim.get("wave", false))
	var dance := clampf(float(anim.get("dance", 0.0)), 0.0, 1.0)
	var defeat := clampf(float(anim.get("defeat", 0.0)), 0.0, 1.0)
	var greet := clampf(float(anim.get("greet", 0.0)), 0.0, 1.0)
	var hello := clampf(float(anim.get("hello", 0.0)), 0.0, 1.0)
	var flop := float(anim.get("flop", absf(sq) * 1.6))
	var walking := walk >= 0.0

	# --- Pose por capas (mismos números que PlayerAvatar.draw_mascot, en u) ---
	var lean := 0.0        # Inclinación de todo el cuerpo (sobre los pies).
	var tilt := 0.0        # Inclinación de la cabeza.
	var head_dy := 0.0     # La cabeza baja (derrota, dormida), en u.
	var spin := 0.0        # Giro sobre sí misma (baile), en radianes.
	var swing := 0.0       # Retraso lateral de orejas/antena (inercia).
	var tuck := 0.0        # Pies recogidos en el aire (0..1).
	var shoulder_dy := 0.0 # Hombros que bajan, en u.
	# Ángulo de cada brazo: 0 colgando, PI/2 de costado, PI arriba. Quietos
	# cuelgan casi derechos a los costados del cuerpo, como en la maqueta.
	var arm_l := ARM_REST
	var arm_r := ARM_REST
	var sway := 0.0
	var breathing := 0.0
	var lift := 0.0        # Salto propio de la pose (baile, risa), en u.
	if walking:
		var s := sin(walk * TAU)
		arm_l = ARM_REST - s * 0.55
		arm_r = ARM_REST + s * 0.55
		sway = s * 0.08
		swing = sin(walk * TAU - 1.1) * 0.1
		flop += absf(sin(walk * TAU - 0.9)) * 0.35
	else:
		sway = sin(t * 1.6 + st) * 0.03
		if t > 0.0:
			breathing = PlayerAvatar.breath(t, st)
			shoulder_dy = -0.5 * breathing
			arm_l += 0.04 * breathing
			arm_r += 0.04 * breathing
	if wave:
		arm_l = 2.2 + sin(t * 12.0 - 1.0) * 0.3
		arm_r = 2.2 + sin(t * 12.0 + 1.0) * 0.3
	match p_mood:
		Mood.DIZZY:
			tilt += sin(t * 2.8) * 0.13
			lean += sin(t * 2.8 - 0.6) * 0.045
			swing += sin(t * 2.8 - 1.4) * 0.25
		Mood.SLEEPY:
			tilt += 0.1 + sin(t * 0.9) * 0.03
			head_dy += 2.0
			arm_l = 0.3
			arm_r = 0.3
		Mood.LAUGHING:  # Se sacude de risa, agarrándose la panza.
			var shake := sin(t * 17.0)
			lift += absf(sin(t * 8.5)) * 2.2
			tilt += shake * 0.035
			swing += shake * 0.12
			arm_l = -0.3 + shake * 0.08
			arm_r = -0.3 - shake * 0.08
		Mood.ANGRY:  # Puños apretados, tiembla un poquito.
			arm_l = 0.3
			arm_r = 0.3
			tilt += sin(t * 31.0) * 0.012
	if dance > 0.0:
		var kind := int(anim.get("dance_kind", -1))
		if kind < 0 or kind >= PlayerAvatar.DANCE_KINDS:
			kind = posmod(st, PlayerAvatar.DANCE_KINDS)
		var beat := t * 2.0  # 2 pasos por segundo (120 bpm).
		var da_l := arm_l
		var da_r := arm_r
		match kind:
			PlayerAvatar.DANCE_HOPS:  # Un saltito por paso, brazos en V que se abren en el aire.
				var h := absf(sin(beat * PI))
				var land := pow(1.0 - h, 6.0)
				lift += dance * h * 12.0
				sq += dance * (0.24 * land - 0.1 * h)
				tuck = dance * smoothstep(0.4, 1.0, h)
				flop += dance * (1.0 - absf(sin(beat * PI - 0.6))) * 1.1
				tilt += dance * sin(beat * PI) * 0.05
				da_l = 0.35 + h * 0.85
				da_r = da_l
			PlayerAvatar.DANCE_SPIN:  # Cada 2 pasos, una vuelta completa (en 3D, de verdad).
				var p := fposmod(beat / 2.0, 1.0)
				if p < 0.5:
					var k := p / 0.5
					var open := sin(k * PI)
					spin = smoothstep(0.0, 1.0, k) * TAU
					lift += dance * open * 9.0
					flop += dance * open * 1.3
					swing -= dance * open * 0.2
					da_l = lerpf(0.4, 1.55, open)
					da_r = da_l
				else:
					var k := (p - 0.5) / 0.5
					lean += dance * sin(k * TAU) * 0.09
					swing -= dance * sin(k * TAU - 0.8) * 0.2
					da_l = 0.5 + sin(k * TAU) * 0.3
					da_r = 0.5 - sin(k * TAU) * 0.3
			_:  # DANCE_ARMS: brazos arriba, balanceándose de lado a lado.
				var h := absf(sin(beat * PI))
				lean += dance * sin(beat * PI) * 0.12
				tilt += dance * sin(beat * PI - 0.3) * 0.08
				swing -= dance * sin(beat * PI - 0.9) * 0.3
				lift += dance * h * 3.5
				sq += dance * 0.12 * pow(1.0 - h, 4.0)
				da_l = 2.1 + sin(beat * TAU) * 0.4
				da_r = 2.1 - sin(beat * TAU) * 0.4
		arm_l = lerpf(arm_l, da_l, dance)
		arm_r = lerpf(arm_r, da_r, dance)
		spin *= dance
	if defeat > 0.0:  # Hombros caídos, cabeza gacha, orejas caídas.
		head_dy += 4.0 * defeat
		shoulder_dy += 2.2 * defeat
		sq += 0.05 * defeat
		flop += 1.3 * defeat
		tilt += 0.05 * defeat
		look = look.lerp(Vector2(0.0, 0.8), defeat)
		arm_l = lerpf(arm_l, 0.1, defeat)
		arm_r = lerpf(arm_r, 0.1, defeat)
	if greet > 0.0:  # Una mano arriba, agitándose; la cabeza se ladea.
		arm_r = lerpf(arm_r, 2.0 + sin(t * 11.0) * 0.35, greet)
		tilt -= 0.08 * greet
		swing += sin(t * 11.0 - 1.0) * 0.06 * greet
	var hside := hello_side(st)
	if hello > 0.0:  # "¡Hola!" del lobby: una mano bien arriba (la del lado del estilo), la otra colgando.
		var up := HELLO_ANGLE + sin(t * TAU / HELLO_PERIOD) * 0.09
		if hside > 0.0:
			arm_r = lerpf(arm_r, up, hello)
			arm_l = lerpf(arm_l, 0.42, hello)
		else:
			arm_l = lerpf(arm_l, up, hello)
			arm_r = lerpf(arm_r, 0.42, hello)
		tilt += hside * 0.06 * hello
		swing -= hside * 0.05 * hello
	sq = clampf(sq, -0.5, 0.5)
	flop = clampf(flop, -0.8, 2.0)
	return {"lean": lean, "tilt": tilt, "head_dy": head_dy, "spin": spin, "swing": swing, "tuck": tuck,
		"shoulder_dy": shoulder_dy, "arm_l": arm_l, "arm_r": arm_r, "sway": sway, "breathing": breathing,
		"lift": lift, "squash": sq, "flop": flop, "look": look, "hello": hello, "hello_side": hside}


## Qué mano levanta cada estilo al saludar (`hello`): -1 la del lado
## izquierdo de la pantalla, +1 la del derecho. Alternado, como en la maqueta
## del lobby (1P y 3P la izquierda, 2P y 4P la derecha).
static func hello_side(p_style: int) -> float:
	return -1.0 if posmod(p_style, 2) == 0 else 1.0


## Salto propio de la pose en u (bailes, risa): lo que apply() sube la
## mascota. Con anim["lift"] = false, apply() no lo aplica y quien dibuja el
## sprite lo puede sumar en 2D (y achicar la sombra).
static func pose_lift(p_mood: int, anim: Dictionary, p_style: int) -> float:
	return float(pose(p_mood, anim, p_style).lift)


## Orienta el brazo i. angle: como en 2D (0 colgando, PI arriba); fwd: giro
## hacia adelante al caminar; dy: los hombros bajan (derrota, respiración).
func _aim_arm(i: int, side: float, angle: float, fwd: float, dy: float, hello := 0.0) -> void:
	var shoulder := _arms[i]
	# Saludando, el hombro se adelanta: el brazo pasa por delante del cuerpo y
	# del borde de la cabeza (si no, la cabeza ancha lo tapa).
	shoulder.position = SHOULDER * Vector3(side, 1, 1) + Vector3(0, -dy, 1.1 * hello)
	var sh := _body.position + shoulder.position
	# Brazos levantados: en 3D la cabeza es ancha y los taparía. Como en la
	# maqueta, van hacia afuera (a la altura del mentón) y se estiran un poco
	# (en dibujos animados se vale). Ejemplo: saludo 2,2 rad -> ~1,85 rad y 1,7× de largo.
	# Con `hello` el brazo sí sube de verdad (HELLO_ANGLE) y se estira
	# HELLO_REACH veces: la mano queda al costado de la cabeza, bien arriba.
	var raise := smoothstep(1.2, 2.0, angle) * (1.0 - hello)
	var a3 := lerpf(angle, 1.72 + (angle - 1.3) * 0.25, raise)
	var reach := ARM_LEN * (1.0 + 0.7 * raise + (HELLO_REACH - 1.0) * hello)
	var target := sh + Vector3(side * sin(a3) * cos(fwd), -cos(a3) * cos(fwd), sin(fwd)) * reach
	if hello > 0.0:
		# La mano queda pegada al borde de la cabeza, a la altura de los ojos y
		# por delante, como en la maqueta (la manopla tapa un poco el borde).
		var hy := HEAD_C.y - 0.6
		var half := HEAD_R.x * sqrt(maxf(0.0, 1.0 - pow((hy - HEAD_C.y) / HEAD_R.y, 2.0)))
		# La manopla (más grande desde la vuelta 2, y más desde la vuelta 3) pisa
		# un poco más el borde de la cabeza: así entra en la celda del atlas
		# (test_mascot_atlas_framing).
		target = target.lerp(Vector3(side * (half + HAND_R * 0.2), hy, HEAD_R.z * 0.92), hello)
	# Si la mano cae dentro de la cabeza o del cuerpo (vistos de frente), va por delante.
	var need := _front_z(Vector2(target.x, target.y)) + HAND_R * 0.8
	if target.z < need:
		target.z = need
	var d := target - sh
	var stretch := clampf(d.length() / ARM_LEN, 0.8, 1.8 + (HELLO_REACH - 1.8) * hello)
	shoulder.basis = Basis(Quaternion(Vector3.DOWN, d.normalized()))
	# Saludando, el brazo estirado es más gordo (una manga, no un palito) y la manopla más grande.
	_arm_tubes[i].scale = Vector3(1.0 + 0.55 * hello, stretch, 1.0 + 0.55 * hello)
	_hands[i].position = Vector3(0, -ARM_LEN * stretch, 0)
	_hands[i].scale = Vector3.ONE * HAND_R * (1.0 + 0.45 * hello)


## Frente (z) de la cabeza o del cuerpo en (x, y) vistos de frente; -INF si
## la mano (radio HAND_R) no se toca con ninguno.
func _front_z(p: Vector2) -> float:
	return maxf(_front_z_of(p - Vector2(_head.position.x, _head.position.y), HEAD_R),
		_front_z_of(p - Vector2(_body.position.x, _body.position.y), BODY_R))


static func _front_z_of(p: Vector2, r: Vector3) -> float:
	var reach := Vector2(r.x, r.y) + Vector2.ONE * HAND_R * 1.2
	if (p / reach).length() >= 1.0:
		return -INF
	var inner := (p / Vector2(r.x, r.y)).length()
	var q := p if inner < 0.97 else p * (0.97 / inner)  # Afuera del borde: la z del borde.
	return Mascot3DMeshes.ellipsoid_point(r, q).z


## Piezas de la cara y efectos que se mueven con el reloj t.
func _animate_features(p_mood: int, t: float, has_t: bool) -> void:
	match p_mood:
		Mood.SAD:
			var drop := fposmod(t * 0.9, 1.0) if has_t else 0.35
			_tear.position = _face_pos(Vector2(-EYE_X - 0.02, EYE_Y - 0.6 - drop * 1.2), 0.14)
			_tear.scale = Vector3.ONE * (1.0 - drop * 0.4)
		Mood.DIZZY:
			for s: Node3D in _moving["spirals"]:
				s.rotation.z = t * 5.0 * float(s.get_meta("dir"))
			var stars: Array = _moving["dizzy_stars"]
			for k in stars.size():
				var a := t * 3.2 + k * TAU / 3.0
				var s: Node3D = stars[k]
				s.position = Vector3(cos(a) * HEAD_R.x * 0.8, HEAD_R.y * 1.1 + sin(a) * 0.4, sin(a) * HEAD_R.z * 0.8)
				s.rotation = Vector3(0, 0, a * 0.5)
				s.scale = Vector3.ONE * (0.85 + 0.15 * sin(a))
		Mood.SLEEPY:
			var zs: Array = _moving["zees"]
			for k in zs.size():
				var ph := fposmod(t * 0.45 + k * 0.5, 1.0)
				var z: Node3D = zs[k]
				z.position = Vector3(HEAD_R.x * 0.72 + ph * 1.6, HEAD_R.y * 0.3 + ph * 2.6, 2.6)
				z.rotation.z = 0.15
				z.scale = Vector3.ONE * maxf(0.05, sin(ph * PI)) * (0.6 + ph * 0.7)
			var r := 0.2 + 0.26 * (0.5 + 0.5 * sin(t * 1.9))
			(_moving["bubble"][0] as Node3D).scale = Vector3.ONE * r
			(_moving["sleepy_mouth"][0] as Node3D).scale = Vector3(1.0, 0.8 + 0.2 * sin(t * 1.9), 1.0)
		Mood.WINNER:
			for s: Node3D in _moving["star_eyes"]:
				s.rotation.z = sin(t * 3.0 + float(s.get_meta("dir"))) * 0.12
			var sparks: Array = _moving["sparks"]
			for k in sparks.size():
				var pulse := 0.5 + 0.5 * sin(t * 5.0 + k * 2.0)
				(sparks[k] as Node3D).scale = Vector3.ONE * (0.5 + 0.6 * pulse)
		Mood.LAUGHING:
			var drops: Array = _moving["laugh_tears"]
			for k in drops.size():
				var sx := -1.0 if k == 0 else 1.0
				var ph := fposmod(t * 1.7 + (0.5 if sx > 0.0 else 0.0), 1.0)
				var d: Node3D = drops[k]
				var p := Vector2(sx * (2.05 + ph * 0.9), EYE_Y + 0.3 + ph * 0.5 - ph * ph * 1.4)
				d.position = Mascot3DMeshes.ellipsoid_point(HEAD_R, p * Vector2(0.98, 1.0)) + Vector3(0, 0, 0.25 + ph * 0.3)
				d.scale = Vector3.ONE * maxf(0.05, (1.0 - ph * 0.3) * (1.0 - ph * ph))


# --- Ayudas de armado ------------------------------------------------------------------

func _node(parent: Node3D, pos: Vector3) -> Node3D:
	var n := Node3D.new()
	n.position = pos
	parent.add_child(n)
	return n


func _feature(key: String, parent: Node3D) -> Node3D:
	var n := _node(parent, Vector3.ZERO)
	n.name = key
	n.visible = false
	_features[key] = n
	return n


func _part(parent: Node3D, mesh: Mesh, kind: int, col: Color, pos: Vector3, scl: Vector3, ink_w: float,
		rot := Vector3.ZERO, base := Color.BLACK) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = pos
	mi.rotation = rot
	mi.scale = scl
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.material_override = material(kind, col, ink_w, shading, base)
	parent.add_child(mi)
	return mi


## Nodo apoyado sobre la cara en (x, y) de frente, mirando hacia afuera de la cabeza.
func _on_face(parent: Node3D, p: Vector2, lift: float) -> Node3D:
	var n := _node(parent, _face_pos(p, lift))
	var nrm := Mascot3DMeshes.ellipsoid_normal(HEAD_R, p)
	n.basis = Basis.looking_at(-nrm, Vector3.UP)
	return n


func _face_pos(p: Vector2, lift: float) -> Vector3:
	return Mascot3DMeshes.ellipsoid_point(HEAD_R, p) + Mascot3DMeshes.ellipsoid_normal(HEAD_R, p) * lift


## Tubo pegado a la cara que pasa por los puntos `pts` (vistos de frente).
func _face_tube(parent: Node3D, key: String, pts: Array, r: float, col: Color) -> void:
	var p3 := PackedVector3Array()
	var radii := PackedFloat32Array()
	for p: Vector2 in pts:
		p3.append(_face_pos(p, r * 0.25))
		radii.append(r)
	_part(parent, Mascot3DMeshes.tube("face_" + key, p3, radii, 8), Kind.EYE, col, Vector3.ZERO, Vector3.ONE, 0.0)


## Puntos de un arco de circunferencia (centro c, radio r) entre los ángulos
## a0·PI y a1·PI. down = true: el arco se da vuelta (∪ en vez de ∩).
static func _arc(c: Vector2, r: float, a0: float, a1: float, steps: int, down := false) -> Array:
	var pts: Array = []
	for i in steps:
		var a := PI * lerpf(a0, a1, float(i) / (steps - 1))
		pts.append(c + Vector2(cos(a), (sin(a) if down else -sin(a))) * r)
	return pts


# --- Materiales ------------------------------------------------------------------------

## Material de una pieza (en caché: todas las mascotas del mismo color
## comparten materiales). ink_w > 0: con contorno de ese ancho. base: color
## del plástico de alrededor (halo de la gema).
static func material(kind: int, col: Color, ink_w := 0.0, p_shading := Shading.TOON, base := Color.BLACK) -> Material:
	var key := "%d|%s|%.3f|%d|%s" % [kind, col.to_html(), ink_w, p_shading, base.to_html()]
	if _materials.has(key):
		return _materials[key]
	var mat: Material
	if p_shading == Shading.STANDARD:
		mat = _standard_material(kind, col)
	else:
		mat = _toy_material(kind, col, base)
	if ink_w > 0.0:
		var ink := ShaderMaterial.new()
		ink.shader = SHADER_INK
		ink.set_shader_parameter("ink", UiTheme.INK)
		ink.set_shader_parameter("width", ink_w)
		mat.next_pass = ink
	_materials[key] = mat
	return mat


## Colores de la rampa del plástico para un color de jugador:
## [sombra, color, luz, borde profundo, contraluz, fuerza del contraluz].
## Concepto: *sombras de color*. En la maqueta la sombra del rojo no es
## "rojo más negro" sino un carmín saturado un poco más frío, y la luz es
## un rojo rosado cálido. Eso es lo que hace que se vea juguete y no barro.
static func plastic_ramp(col: Color) -> Array:
	var lum := col.get_luminance()
	if lum < 0.2:  # Negro y grafito: el volumen lo dan la luz clara y el contraluz.
		return [col.darkened(0.25), col.lightened(0.12), col.lightened(0.42), col.darkened(0.1), UiTheme.MASCOT_RIM, 1.0]
	if col.s < 0.2 and lum > 0.8:  # Blanco: sombras azuladas para que no se confunda con la cara.
		var shade := UiTheme.MASCOT_FACE_SHADE
		return [shade.darkened(0.22), col.lerp(shade, 0.3), col.lightened(0.5), shade.darkened(0.08), SKY_RIM, 0.5]
	var mid := vivid(col)
	var cool := fposmod(mid.h + (0.02 if mid.h > 0.2 and mid.h < 0.7 else -0.025), 1.0)
	# Sombra profunda: medida en la maqueta, el 10 % más oscuro del rojo es
	# #67 0C 13 (v ≈ 0,40) y del azul #09 27 65; antes la nuestra quedaba en v ≈ 0,68.
	var low := Color.from_hsv(cool, minf(1.0, mid.s * 1.1 + 0.05), mid.v * 0.4)
	var high := Color.from_hsv(fposmod(mid.h + 0.012, 1.0), mid.s * 0.8, 1.0)
	var edge := Color.from_hsv(cool, minf(1.0, mid.s * 1.1 + 0.04), mid.v * 0.58)
	return [low, mid, high, edge, SKY_RIM, 0.55]


static func _toy_material(kind: int, col: Color, base := Color.BLACK) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = SHADER_TOY
	var low := col
	var mid := col
	var high := col
	var bounce := col
	var bounce_k := 0.3
	var rim := SKY_RIM
	var rim_k := 0.4
	var spec := 1.0
	var spec_size := 0.018
	var spec_soft := 0.012
	var stretch := 1.45
	var coat := 0.2
	var coat_pow := 5.0
	var spread := 0.0
	var edge := col
	var edge_k := 0.0
	var sky := 0.0
	var glow := 0.0
	match kind:
		Kind.PLASTIC, Kind.HEAD, Kind.LEAF, Kind.BODY:
			var r := plastic_ramp(col)
			low = r[0]
			mid = r[1]
			high = r[2]
			edge = r[3]
			rim = r[4]
			rim_k = r[5]
			edge_k = 0.85
			bounce = mid.lerp(high, 0.25)
			bounce_k = 0.14
			sky = 0.5
			# Plástico "jugoso" de la maqueta: volumen de esfera (la sombra sube
			# hasta la mitad), un reflejo grande de borde suave y el barniz ancho.
			spread = 1.0
			spec_size = 0.045
			spec_soft = 0.06
			coat = 0.3
			coat_pow = 3.5
			if kind == Kind.HEAD:
				m.set_shader_parameter("face_on", 1.0)
				m.set_shader_parameter("face_scale", HEAD_R)
				m.set_shader_parameter("face_center", FACE_C)
				m.set_shader_parameter("face_radii", FACE_R)
				m.set_shader_parameter("face_low", UiTheme.MASCOT_FACE_SHADE)
				m.set_shader_parameter("face_mid", UiTheme.PAPER.lerp(UiTheme.MASCOT_FACE_SHADE, 0.1))
				m.set_shader_parameter("face_high", UiTheme.PAPER)
			if kind == Kind.BODY:  # La cabeza le hace sombra al pecho: en la maqueta casi todo el torso queda en sombra.
				m.set_shader_parameter("neck_shadow", 0.6)
				m.set_shader_parameter("neck_y", HEAD_C.y - HEAD_R.y - BODY_C.y - 0.55)
			if kind == Kind.LEAF:  # Hojas: menos barniz, brillo más chico.
				coat = 0.12
				spec_size = 0.025
				spec_soft = 0.02
		Kind.SHOE:  # Zapatos de charol: casi negros, con reflejos nítidos.
			low = col.darkened(0.5)
			mid = col
			high = col.lightened(0.18)
			bounce = col.lightened(0.1)
			bounce_k = 0.2
			edge = col.darkened(0.4)
			edge_k = 0.5
			rim = UiTheme.MASCOT_RIM
			rim_k = 0.6
			sky = 0.35
			spec_size = 0.04
		Kind.FACE:
			low = UiTheme.MASCOT_FACE_SHADE
			mid = UiTheme.PAPER.lerp(UiTheme.MASCOT_FACE_SHADE, 0.1)
			high = UiTheme.PAPER
			bounce = UiTheme.PAPER
			bounce_k = 0.2
			edge = UiTheme.MASCOT_FACE_SHADE.darkened(0.05)
			edge_k = 0.6
			spec = 0.5
			spec_size = 0.02
			coat = 0.05
			rim_k = 0.0
		Kind.EYE:  # Negro brillante: el reflejo del shader es nítido y blanco.
			low = col
			mid = col
			high = col.lerp(UiTheme.MASCOT_EYE_GLOSS, 0.5)
			bounce = UiTheme.MASCOT_EYE_GLOSS
			bounce_k = 0.75
			rim = UiTheme.MASCOT_EYE_GLOSS
			rim_k = 0.5
			spec_size = 0.02
			coat = 0.12
		Kind.MOUTH:
			low = col.darkened(0.3)
			mid = col
			high = col.lightened(0.25)
			bounce_k = 0.0
			rim_k = 0.0
			spec_size = 0.015
			coat = 0.08
		Kind.METAL:
			low = col.darkened(0.5)
			mid = col
			high = UiTheme.PAPER
			bounce = col.lightened(0.3)
			bounce_k = 0.6
			spec_size = 0.05
			coat = 0.35
			sky = 0.6
		Kind.FLAT:
			spec = 0.0
			coat = 0.0
			rim_k = 0.0
			bounce_k = 0.0
		Kind.BLUSH:  # Cachete: rosa en el centro que se funde con la cara hacia el borde.
			spec = 0.0
			coat = 0.0
			rim_k = 0.0
			bounce_k = 0.0
			edge = UiTheme.PAPER.lerp(UiTheme.MASCOT_FACE_SHADE, 0.08)
			edge_k = 1.0
			# El rosa pleno cubre casi todo el disco y se funde recién en el borde
			# (antes se fundía desde el centro y el cachete casi no se veía).
			m.set_shader_parameter("edge_range", Vector2(0.3, 0.62))
		Kind.HALO:  # Brillo de la gema sobre el plástico: se funde con el color de alrededor.
			low = col
			mid = col
			high = col.lightened(0.3)
			spec = 0.0
			coat = 0.0
			rim_k = 0.0
			bounce_k = 0.0
			edge = base
			edge_k = 1.0
			m.set_shader_parameter("edge_range", Vector2(0.05, 0.4))
		Kind.GEM, Kind.GLOW:  # Gema y foco: centro claro y caliente, poca sombra.
			low = col.darkened(0.15)
			mid = col
			high = col.lerp(Color.WHITE, 0.6)
			bounce_k = 0.0
			rim_k = 0.0
			glow = 1.0
			spec_size = 0.03
		Kind.GLASS:  # Lágrimas y globito: celeste claro con reflejo fuerte.
			low = col.darkened(0.2)
			mid = col
			high = col.lightened(0.5)
			bounce = Color.WHITE
			bounce_k = 0.3
			rim = Color.WHITE
			rim_k = 0.6
			spec_size = 0.06
			coat = 0.3
	m.set_shader_parameter("low_color", low)
	m.set_shader_parameter("mid_color", mid)
	m.set_shader_parameter("high_color", high)
	m.set_shader_parameter("bounce_color", bounce)
	m.set_shader_parameter("bounce_strength", bounce_k)
	m.set_shader_parameter("rim_color", rim)
	m.set_shader_parameter("rim_strength", rim_k)
	m.set_shader_parameter("spec_strength", spec)
	m.set_shader_parameter("spec_size", spec_size)
	m.set_shader_parameter("spec_stretch", stretch)
	m.set_shader_parameter("spec_soft", spec_soft)
	m.set_shader_parameter("shade_spread", spread)
	m.set_shader_parameter("coat_strength", coat)
	m.set_shader_parameter("coat_power", coat_pow)
	m.set_shader_parameter("edge_color", edge)
	m.set_shader_parameter("edge_strength", edge_k)
	m.set_shader_parameter("sky_strength", sky)
	m.set_shader_parameter("glow", glow)
	return m


## Variante con el material estándar de Godot (PBR) y luces reales: sirve
## para comparar con el shader propio (ver Mascot3DBaker.add_studio_lights).
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
		Kind.FLAT, Kind.BLUSH, Kind.HALO:
			m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		Kind.GLOW, Kind.GEM:
			m.emission_enabled = true
			m.emission = col
			m.emission_energy_multiplier = 0.6
	return m
