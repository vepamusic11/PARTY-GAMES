class_name Mascot3DLive
extends Sprite2D
## Mascota 3D renderizada EN VIVO dentro de un juego 2D (camino "a" del
## prototipo, ver docs/ARTE.md): cada jugador tiene su propio SubViewport
## con su mascota 3D, que se renderiza en cada cuadro, y este Sprite2D
## muestra el resultado como una textura más.
##
## Ventaja: animación continua (cualquier ángulo, cualquier mezcla de poses).
## Costo: por cada jugador, un render 3D por cuadro (≈ 40 piezas × 2 pasadas
## con el contorno) y la memoria de su viewport. Se mide con
## tools/mascot3d_benchmark.gd.
##
## `position` es el punto donde apoyan los pies (igual que PlayerAvatar.draw_mascot).

var mood := PlayerAvatar.Mood.NORMAL
var walk := -1.0             ## Fase de caminata (≥ 0 camina).
var look := Vector2.ZERO
var wave := false
var squash := 0.0
var animate := true          ## Respira y parpadea sola.

var _mascot: Mascot3D
var _viewport: SubViewport
var _t := 0.0


## look_info: {"color", "style"} como en Mascot3DBaker.bake. cell_px: lado
## del viewport (ver Mascot3DBaker.cell_for_u). msaa: suavizado de bordes.
func setup(look_info: Dictionary, cell_px: int, msaa := Viewport.MSAA_4X) -> Mascot3DLive:
	_viewport = Mascot3DBaker.make_viewport(Vector2i(cell_px, cell_px))
	_viewport.msaa_3d = msaa
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_mascot = Mascot3D.new().setup(Mascot3DBaker._look_color(look_info), int(look_info.get("style", 0)))
	_mascot.position = Mascot3DBaker.cell_origin(0, 0, 1, 1)
	_viewport.add_child(_mascot)
	add_child(_viewport)
	texture = _viewport.get_texture()
	centered = false
	offset = -Mascot3DBaker.feet_offset(cell_px)
	return self


func _process(delta: float) -> void:
	if _mascot == null:
		return
	_t += delta
	var anim := {"t": _t, "walk": walk, "look": look, "wave": wave, "squash": squash}
	if animate:
		anim["bob"] = sin(_t * 2.4) * 1.3
	_mascot.apply(mood, anim)
