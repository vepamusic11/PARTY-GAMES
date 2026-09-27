extends RefCounted
## Física de círculos propia y determinista para Pool loco (y reutilizable en
## Mini golf o Bochas, ver docs/JUEGOS.md "Estilo pool").
##
## Concepto: *física determinista*. Todo avanza en pasos fijos de DT (no con
## el delta del frame) y en un orden fijo (bolas por índice, pares (i, j) con
## i < j), sin el motor de física de Godot. Así la misma jugada da siempre el
## mismo resultado y se puede testear sin escena.
##
## Cada paso:
##   1. fricción: la velocidad baja un porcentaje (paño) y además una cantidad
##      fija (rodadura); debajo de STOP_SPEED la bola se frena del todo;
##   2. mover;
##   3. troneras: si el centro de una bola entra al radio de captura de una
##      tronera, cae (sale de la mesa) y no choca más;
##   4. bandas: rebote contra los bordes de `bounds` con pérdida de energía;
##   5. choques entre bolas: se separan y rebotan (choque elástico con masas;
##      RESTITUTION < 1 le saca un poco de energía).
##
## Sin dependencias de nodos: la usa pool.gd y los tests la llaman directo.

const DT := 1.0 / 120.0          ## Paso fijo (s). A 60 fps son 2 pasos por frame.
const DRAG := 0.9                ## Fricción del paño: fracción de velocidad por segundo (exponencial).
const ROLL_DECEL := 150.0        ## Frenado fijo (px/s²): las bolas terminan de frenar.
const STOP_SPEED := 14.0         ## Debajo de esto la bola queda quieta (px/s).
const RESTITUTION := 0.94        ## Choque entre bolas (1 = perfectamente elástico).
const CUSHION_BOUNCE := 0.78     ## Rebote en las bandas.

## Mesa: las bolas rebotan contra los bordes de este rectángulo.
var bounds := Rect2(0, 0, 1000, 500)
## Troneras (centros) y radio de captura (distancia al centro de la bola).
var pockets := PackedVector2Array()
var pocket_capture := 44.0

var pos := PackedVector2Array()
var vel := PackedVector2Array()
var radius := PackedFloat32Array()
var mass := PackedFloat32Array()
## 1 = en la mesa; 0 = cayó en una tronera (no se mueve ni choca).
var on_table := PackedByteArray()


func _init(p_bounds: Rect2 = Rect2(0, 0, 1000, 500), p_pockets: PackedVector2Array = PackedVector2Array(),
		p_capture: float = 44.0) -> void:
	bounds = p_bounds
	pockets = p_pockets
	pocket_capture = p_capture


## Agrega una bola y devuelve su índice.
func add_ball(p: Vector2, r: float, m: float = 1.0) -> int:
	pos.append(p)
	vel.append(Vector2.ZERO)
	radius.append(r)
	mass.append(maxf(m, 0.001))
	on_table.append(1)
	return pos.size() - 1


## Vuelve a poner una bola en la mesa, quieta, en `p`.
func place(i: int, p: Vector2) -> void:
	pos[i] = p
	vel[i] = Vector2.ZERO
	on_table[i] = 1


func is_on_table(i: int) -> bool:
	return on_table[i] == 1


func speed(i: int) -> float:
	return vel[i].length()


## ¿Hay lugar para una bola de radio `r` en `p`? (adentro de la mesa, lejos
## de las troneras y sin tocar otra bola; `ignore`: índice a no contar).
func is_free(p: Vector2, r: float, ignore: int = -1, gap: float = 6.0) -> bool:
	if not bounds.grow(-r).has_point(p):
		return false
	for k in pockets.size():
		if p.distance_to(pockets[k]) < pocket_capture + r + gap:
			return false
	for j in pos.size():
		if j != ignore and on_table[j] == 1 and p.distance_to(pos[j]) < r + radius[j] + gap:
			return false
	return true


## Un paso fijo de DT. Devuelve lo que pasó, para puntos, sonido y efectos:
##   hits:     [[i, j, impacto (velocidad de acercamiento), punto], ...]
##   pocketed: [[i, índice de tronera], ...]
##   cushions: [[i, impacto], ...]
func step() -> Dictionary:
	var hits: Array = []
	var pocketed: Array = []
	var cushions: Array = []
	var n := pos.size()
	var keep := exp(-DRAG * DT)
	for i in n:
		if on_table[i] == 0:
			continue
		var v := vel[i] * keep
		var s := v.length()
		s = maxf(s - ROLL_DECEL * DT, 0.0)
		if s < STOP_SPEED:
			vel[i] = Vector2.ZERO
			continue
		vel[i] = v.normalized() * s
		pos[i] += vel[i] * DT
	# Troneras antes que las bandas: una bola que llega a la esquina cae, no rebota.
	for i in n:
		if on_table[i] == 0:
			continue
		for k in pockets.size():
			if pos[i].distance_to(pockets[k]) < pocket_capture:
				on_table[i] = 0
				pocketed.append([i, k])
				break
	for i in n:
		if on_table[i] == 0:
			continue
		var r := radius[i]
		var p := pos[i]
		var v := vel[i]
		var impact := 0.0
		if p.x < bounds.position.x + r:
			p.x = bounds.position.x + r
			impact = maxf(impact, -v.x)
			v.x = absf(v.x) * CUSHION_BOUNCE
		elif p.x > bounds.end.x - r:
			p.x = bounds.end.x - r
			impact = maxf(impact, v.x)
			v.x = -absf(v.x) * CUSHION_BOUNCE
		if p.y < bounds.position.y + r:
			p.y = bounds.position.y + r
			impact = maxf(impact, -v.y)
			v.y = absf(v.y) * CUSHION_BOUNCE
		elif p.y > bounds.end.y - r:
			p.y = bounds.end.y - r
			impact = maxf(impact, v.y)
			v.y = -absf(v.y) * CUSHION_BOUNCE
		pos[i] = p
		vel[i] = v
		if impact > 0.0:
			cushions.append([i, impact])
	for i in n:
		if on_table[i] == 0:
			continue
		var still := vel[i] == Vector2.ZERO
		for j in range(i + 1, n):
			# Dos bolas quietas no se pueden chocar (nunca se ponen superpuestas).
			if on_table[j] == 0 or (still and vel[j] == Vector2.ZERO):
				continue
			var hit := _collide(i, j)
			if hit >= 0.0:
				hits.append([i, j, hit, (pos[i] * radius[j] + pos[j] * radius[i]) / (radius[i] + radius[j])])
	return {"hits": hits, "pocketed": pocketed, "cushions": cushions}


## Choque entre dos bolas: si se superponen, las separa (en proporción
## inversa a la masa) y, si se acercaban, les aplica el impulso de un choque
## elástico sobre la línea que une los centros. Devuelve la velocidad de
## acercamiento (0 si ya se separaban) o -1 si no se tocan.
func _collide(i: int, j: int) -> float:
	var d := pos[j] - pos[i]
	var min_dist := radius[i] + radius[j]
	var dist := d.length()
	if dist >= min_dist:
		return -1.0
	var nrm := d / dist if dist > 0.0001 else Vector2.RIGHT
	var inv_i := 1.0 / mass[i]
	var inv_j := 1.0 / mass[j]
	var overlap := min_dist - dist
	pos[i] -= nrm * overlap * inv_i / (inv_i + inv_j)
	pos[j] += nrm * overlap * inv_j / (inv_i + inv_j)
	var closing := (vel[i] - vel[j]).dot(nrm)
	if closing <= 0.0:
		return 0.0
	var impulse := (1.0 + RESTITUTION) * closing / (inv_i + inv_j)
	vel[i] -= nrm * impulse * inv_i
	vel[j] += nrm * impulse * inv_j
	return closing

