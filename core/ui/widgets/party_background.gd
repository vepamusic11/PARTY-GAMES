class_name PartyBackground
extends Control
## Fondo "de fiesta": un escenario desenfocado detrás de la UI, como en las
## consolas. Cielo con luz ambiente y haces de luz, nubes suaves, estrellas,
## torres de bloques con volumen (frente, tapa y costado que mira al centro),
## luces de colores (bokeh), piso a cuadros en perspectiva que se aleja
## hacia la bruma y viñeta en los bordes. Los colores van mezclados con la
## bruma del horizonte y desenfocados: la UI de adelante sigue destacando.
##
## Cada capa se puede apagar. El celular usa solo el cielo (`towers`,
## `checker_floor` y `bricks` en false): ahí no se arma el escenario y solo
## se mueven las nubes, a `anim_fps` (ahorro de batería).
##
## Rendimiento (ver docs/PERFORMANCE.md):
##   - El escenario se pinta UNA vez en un SubViewport a media resolución
##     (`_scene_vp`) y otro SubViewport (`_blur_vp`) lo desenfoca una vez con
##     `soft_blur.gdshader`. Los dos quedan en UPDATE_ONCE: después no
##     vuelven a dibujar. En pantalla es un solo TextureRect (1 draw call).
##     Se vuelve a preparar solo si cambia el tamaño o las capas.
##   - Lo que se mueve (nubes y brillos) son Sprite2D con texturas hechas
##     por código una sola vez (compartidas entre instancias): en cada frame
##     solo cambian posición, escala y transparencia; nada de _draw().
##   - Mientras el escenario no está listo (primer par de frames) se ve el
##     cielo liso de siempre, así nunca hay un cuadro negro.
##   - Los bordes de bloques (`bricks`) quedan nítidos en la capa `_front`,
##     que se dibuja una sola vez.

@export var bricks := false:
	set(v):
		bricks = v
		_refresh_layers()
@export var towers := true:
	set(v):
		towers = v
		_refresh_layers()
@export var checker_floor := true:
	set(v):
		checker_floor = v
		_refresh_layers()
## Cuadros por segundo de la animación de nubes y brillos. 0 = en cada frame
## (TV). El celular lo baja mientras espera para gastar menos batería (ver
## ControllerMain): con el modo de bajo consumo de Godot, si nada cambia, no
## se dibuja el frame.
var anim_fps := 0.0

const BRICK_H := 34.0
const BRICK_W := 96.0
## El escenario se prepara a esta escala: está desenfocado, así que no hace
## falta más resolución (y ocupa la cuarta parte de memoria).
const BAKE_SCALE := 0.5
## Altura (fracción de la pantalla) donde empieza el piso.
const FLOOR_AT := 0.8
const CLOUD_TEX := Vector2i(160, 80)
const SPARKLE_TEX := 48
const BLUR_SHADER := preload("res://core/ui/shaders/soft_blur.gdshader")

## Estados de la preparación del escenario (uno por frame).
enum Bake { IDLE, PAINT, BLUR, SHOW }

static var _cloud_tex: Texture2D
static var _sparkle_tex: Texture2D

var _t := 0.0
var _anim_slot := -1
var _clouds: Array[Vector3] = []          # x (0..1), y (0..1), escala
var _cloud_sprites: Array[Sprite2D] = []
var _glints: Array[Vector4] = []          # x, y (0..1), fase, período (s)
var _glint_sprites: Array[Sprite2D] = []
var _back_towers: Array[Vector3] = []     # x (0..1), bloques, color
var _front_towers: Array[Vector3] = []
var _stars: Array[Vector3] = []           # x, y (0..1), tamaño
var _bokeh: Array[Vector4] = []           # x, y (0..1), radio, color
var _far_clouds: Array[Vector3] = []      # x, y (0..1), escala

var _scene_vp: SubViewport                # escenario nítido, a media resolución
var _painter: Node2D                      # dibuja el escenario dentro de _scene_vp
var _blur_vp: SubViewport                 # el mismo, desenfocado
var _backdrop: TextureRect                # lo que se ve: la textura de _blur_vp
var _anim_layer: Control                  # nubes y brillos (Sprite2D)
var _front: Control                       # capa estática y nítida: bordes de bloques
var _bake := Bake.IDLE


func _ready() -> void:
	add_to_group(Props3D.GROUP)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build_layout()
	_build_nodes()
	resized.connect(_on_resized)
	_refresh_layers()
	_update_anim()
	set_process(is_visible_in_tree())


## Siempre el mismo paisaje (semilla fija): la TV no "parpadea" entre pantallas.
func _build_layout() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for i in 6:
		_clouds.append(Vector3(i / 6.0 + rng.randf_range(0.0, 0.08), rng.randf_range(0.02, 0.3), rng.randf_range(0.75, 1.35)))
	var x := rng.randf_range(0.0, 0.03)
	while x < 1.02:
		var center := x > 0.3 and x < 0.7
		_back_towers.append(Vector3(x, rng.randi_range(2, 4) if center else rng.randi_range(3, 8), rng.randi_range(0, 7)))
		x += rng.randf_range(0.035, 0.065)
	for side in 2:
		x = rng.randf_range(-0.03, 0.0) if side == 0 else rng.randf_range(0.76, 0.79)
		var stop := 0.24 if side == 0 else 1.02
		while x < stop:
			_front_towers.append(Vector3(x, rng.randi_range(2, 5), rng.randi_range(0, 7)))
			x += rng.randf_range(0.06, 0.1)
	for i in 11:
		_stars.append(Vector3(rng.randf(), rng.randf_range(0.06, 0.55), rng.randf_range(12.0, 30.0)))
	for i in 16:
		var bx := rng.randf_range(0.0, 0.3) if i % 2 == 0 else rng.randf_range(0.7, 1.0)
		_bokeh.append(Vector4(bx, rng.randf_range(0.25, 0.85), rng.randf_range(30.0, 90.0), rng.randi_range(0, 7)))
	for i in 5:
		_far_clouds.append(Vector3(i / 5.0 + rng.randf_range(0.0, 0.1), rng.randf_range(0.5, 0.6), rng.randf_range(1.4, 2.0)))
	for i in 9:
		var gx := rng.randf_range(0.02, 0.3) if i % 2 == 0 else rng.randf_range(0.7, 0.98)
		_glints.append(Vector4(gx, rng.randf_range(0.12, 0.7), rng.randf_range(0.0, TAU), rng.randf_range(1.8, 3.4)))


func _build_nodes() -> void:
	# Escenario: _blur_vp desenfoca la textura de _scene_vp. _scene_vp es hijo
	# de _blur_vp, así Godot lo dibuja antes (igual se piden en frames distintos).
	_blur_vp = _make_viewport()
	add_child(_blur_vp)
	_scene_vp = _make_viewport()
	_blur_vp.add_child(_scene_vp)
	_painter = Node2D.new()
	_painter.scale = Vector2(BAKE_SCALE, BAKE_SCALE)
	_painter.draw.connect(_paint_scene)
	_scene_vp.add_child(_painter)
	var blur := TextureRect.new()
	blur.texture = _scene_vp.get_texture()
	blur.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	blur.stretch_mode = TextureRect.STRETCH_SCALE
	blur.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var mat := ShaderMaterial.new()
	mat.shader = BLUR_SHADER
	mat.set_shader_parameter("step_px", UiTheme.BG_BLUR_STEP)
	blur.material = mat
	_blur_vp.add_child(blur)

	_backdrop = TextureRect.new()
	_backdrop.texture = _blur_vp.get_texture()
	_backdrop.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_backdrop.stretch_mode = TextureRect.STRETCH_SCALE
	_backdrop.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_backdrop.visible = false
	add_child(_backdrop)

	_anim_layer = Control.new()
	_anim_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_anim_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_anim_layer)
	for c in _clouds:
		var s := Sprite2D.new()
		s.texture = cloud_texture()
		s.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		s.scale = Vector2.ONE * 2.2 * c.z
		s.flip_h = _cloud_sprites.size() % 2 == 1
		s.modulate = Color(1, 1, 1, 0.9)
		_anim_layer.add_child(s)
		_cloud_sprites.append(s)
	for g in _glints:
		var s := Sprite2D.new()
		s.texture = sparkle_texture()
		s.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		s.modulate = UiTheme.BG_SPARKLE
		_anim_layer.add_child(s)
		_glint_sprites.append(s)

	_front = Control.new()
	_front.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_front.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_front.draw.connect(_draw_front)
	add_child(_front)


func _make_viewport() -> SubViewport:
	var vp := SubViewport.new()
	vp.disable_3d = true
	vp.transparent_bg = false
	vp.gui_disable_input = true
	vp.size = Vector2i(2, 2)
	vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	return vp


func _notification(what: int) -> void:
	# Oculto (ej. durante un minijuego) no anima: no gasta CPU en cada frame.
	if what == NOTIFICATION_VISIBILITY_CHANGED and is_inside_tree():
		set_process(is_visible_in_tree())


func _process(delta: float) -> void:
	_t += delta
	if _bake != Bake.IDLE:
		_advance_bake()
	if anim_fps <= 0.0:
		_update_anim()
		return
	# Reloj común (no _t): varios nodos con el mismo anim_fps cambian en el
	# mismo frame, así el celular dibuja pocas veces por segundo.
	var slot := int(Time.get_ticks_msec() * anim_fps / 1000.0)
	if slot != _anim_slot:
		_anim_slot = slot
		_update_anim()


## Nubes que cruzan despacio y brillos que titilan: solo propiedades de
## nodos (Godot reutiliza lo dibujado; no hay _draw por frame).
func _update_anim() -> void:
	var s := size
	var span := s.x + 700.0
	for i in _cloud_sprites.size():
		var c := _clouds[i]
		var x := fposmod(c.x * span + _t * 14.0 * c.z, span) - 350.0
		_cloud_sprites[i].position = Vector2(x, c.y * s.y + 60.0 * c.z)
	if not _glint_sprites[0].visible:
		return
	for i in _glint_sprites.size():
		var g := _glints[i]
		var k := maxf(0.0, sin(_t * TAU / g.w + g.z))
		k = k * k * k
		var sp := _glint_sprites[i]
		sp.position = Vector2(g.x * s.x, g.y * s.y)
		sp.scale = Vector2.ONE * (0.5 + 0.9 * k)
		sp.rotation = _t * 0.6 + g.z
		sp.modulate.a = k


func _on_resized() -> void:
	_refresh_layers()


## Las piezas 3D quedaron horneadas (Props3DBaker): se vuelve a preparar el
## escenario con los bloques y estrellas 3D.
func _on_props3d_ready() -> void:
	_refresh_layers()


## Capas o tamaño distintos: pide rearmar el escenario y la capa nítida.
func _refresh_layers() -> void:
	if _front == null:
		return
	_front.visible = bricks
	_front.queue_redraw()
	var scenery := _has_scenery()
	for sp in _glint_sprites:
		sp.visible = scenery
	queue_redraw()
	if not scenery:
		_backdrop.visible = false
		_bake = Bake.IDLE
		return
	_bake = Bake.PAINT


func _has_scenery() -> bool:
	return towers or checker_floor


## Un paso por frame: pintar (SubViewport nítido), desenfocar y mostrar.
func _advance_bake() -> void:
	match _bake:
		Bake.PAINT:
			if size.x < 2.0 or size.y < 2.0:
				return
			var px := Vector2i(ceili(size.x * BAKE_SCALE), ceili(size.y * BAKE_SCALE))
			_scene_vp.size = px
			_blur_vp.size = px
			_painter.queue_redraw()
			_scene_vp.render_target_update_mode = SubViewport.UPDATE_ONCE
			_bake = Bake.BLUR
		Bake.BLUR:
			_blur_vp.render_target_update_mode = SubViewport.UPDATE_ONCE
			_bake = Bake.SHOW
		Bake.SHOW:
			_backdrop.visible = true
			_bake = Bake.IDLE
			queue_redraw()  # Ya no hace falta el cielo liso de abajo.


## Cielo liso (celular, o mientras se prepara el escenario de la TV).
func _draw() -> void:
	if _backdrop != null and _backdrop.visible:
		return
	var s := size
	draw_polygon(PackedVector2Array([Vector2.ZERO, Vector2(s.x, 0), s, Vector2(0, s.y)]),
		PackedColorArray([UiTheme.SKY_TOP, UiTheme.SKY_TOP, UiTheme.SKY_BOTTOM, UiTheme.SKY_BOTTOM]))


# --- Escenario (se pinta una vez en _scene_vp, en coordenadas de la pantalla) ----

func _paint_scene() -> void:
	var ci := _painter
	var w := size.x
	var h := size.y
	var floor_y := h * FLOOR_AT
	# Cielo: tres paradas hasta la bruma del horizonte.
	var mid := floor_y * 0.5
	ci.draw_polygon(PackedVector2Array([Vector2.ZERO, Vector2(w, 0), Vector2(w, mid), Vector2(0, mid)]),
		PackedColorArray([UiTheme.BG_SKY_TOP, UiTheme.BG_SKY_TOP, UiTheme.BG_SKY_MID, UiTheme.BG_SKY_MID]))
	ci.draw_polygon(PackedVector2Array([Vector2(0, mid), Vector2(w, mid), Vector2(w, floor_y), Vector2(0, floor_y)]),
		PackedColorArray([UiTheme.BG_SKY_MID, UiTheme.BG_SKY_MID, UiTheme.BG_HAZE, UiTheme.BG_HAZE]))
	# Luz ambiente y haces de luz desde arriba, como en un escenario.
	var clear := Color(UiTheme.BG_GLOW, 0.0)
	UiTheme.draw_radial(ci, Vector2(w * 0.5, h * 0.18), w * 0.55, UiTheme.BG_GLOW, clear, h * 0.62)
	for a in [-0.62, -0.3, 0.3, 0.62]:
		_beam(ci, Vector2(w * 0.5 + a * w * 0.25, -20.0), a, floor_y)
	# Nubes lejanas detrás de las torres (quietas).
	for c in _far_clouds:
		var sz := Vector2(CLOUD_TEX) * 2.4 * c.z
		var p := Vector2(c.x * w, c.y * h)
		ci.draw_texture_rect(cloud_texture(), Rect2(p - sz / 2.0, sz), false, Color(1, 1, 1, 0.75))
	# Estrellas y polvo brillante en el cielo.
	var batch := UiTheme.ShapeBatch.new()
	var stars_3d := Props3D.is_ready()
	for st in _stars:
		var p := Vector2(st.x * w, st.y * h)
		if stars_3d:  # Estrella de juguete 3D (Props3D), un poco transparente como la 2D.
			ci.draw_set_transform(p, st.x * 3.0)
			Props3D.draw(ci, "star", Rect2(-st.z, -st.z, st.z * 2.0, st.z * 2.0), Color(1, 1, 1, 0.85))
			continue
		var col := UiTheme.GOLD.lerp(UiTheme.PAPER, 0.35)
		batch.star(UiTheme.star_points(p, st.z, 0.5, st.x * 3.0), p, Color(col, 0.85))
	ci.draw_set_transform(Vector2.ZERO)
	batch.flush(ci)
	# Torres de atrás (más chicas y más mezcladas con la bruma).
	for t in _back_towers:
		_tower(ci, t, 40.0, floor_y + 4.0, UiTheme.BG_HAZE_FAR)
	# Piso a cuadros en perspectiva.
	if checker_floor:
		_floor(ci, floor_y)
	# Luces de colores (bokeh) entre las torres.
	batch = UiTheme.ShapeBatch.new()
	for b in _bokeh:
		var col: Color = UiTheme.BRICKS[int(b.w) % UiTheme.BRICKS.size()].lerp(UiTheme.PAPER, 0.45)
		batch.circle(Vector2(b.x * w, b.y * h), b.z, Color(col, 0.2))
		batch.circle(Vector2(b.x * w, b.y * h), b.z * 0.62, Color(col, 0.14))
	batch.flush(ci)
	# Torres de adelante: más grandes, a los costados (el centro queda para la UI).
	for t in _front_towers:
		_tower(ci, t, 64.0, floor_y + 40.0, UiTheme.BG_HAZE_NEAR)
	# Viñeta: bordes más oscuros, centro intacto.
	_vignette(ci, w, h)


## Haz de luz: angosto arriba, ancho abajo, se desvanece al bajar.
func _beam(ci: CanvasItem, top: Vector2, angle: float, floor_y: float) -> void:
	var bottom := Vector2(top.x + angle * floor_y * 0.9, floor_y)
	var clear := Color(UiTheme.BG_BEAM, 0.0)
	ci.draw_polygon(PackedVector2Array([top - Vector2(30, 0), top + Vector2(30, 0),
		bottom + Vector2(170, 0), bottom - Vector2(170, 0)]),
		PackedColorArray([UiTheme.BG_BEAM, UiTheme.BG_BEAM, clear, clear]))


## Torre de bloques con volumen. `t`: x (0..1), bloques, color inicial.
func _tower(ci: CanvasItem, t: Vector3, block: float, base_y: float, haze: float) -> void:
	if not towers:
		return
	var x := t.x * size.x
	# El costado mira al centro de la pantalla (punto de fuga en el medio).
	var dir := 1.0 if x + block / 2.0 < size.x / 2.0 else -1.0
	var batch := UiTheme.ShapeBatch.new()
	var n := int(t.y)
	for j in n:
		var idx := (int(t.z) + j * 3) % UiTheme.BRICKS.size()
		if Props3D.is_ready():
			# Bloque de juguete 3D con botones (Props3D): ocupa el frente, la tapa
			# (arriba) y el costado que mira al centro; los de la derecha, espejados.
			var d := (block - 2.0) * 0.26
			var r3 := Rect2(x - (d if dir < 0.0 else 0.0), base_y - (j + 1) * block - d, block - 2.0 + d, block - 2.0 + d)
			Props3D.draw(ci, ("block_far_%d" if haze > 0.3 else "block_near_%d") % idx, r3, Color.WHITE, dir < 0.0)
			continue
		var c: Color = UiTheme.BRICKS[idx]
		c = c.lerp(UiTheme.BG_HAZE, haze * (1.0 - 0.08 * j))  # Lo más alto, un poco más vivo.
		var r := Rect2(x, base_y - (j + 1) * block, block - 2.0, block - 2.0)
		_block(batch, r, c, dir, j == n - 1)
	batch.flush(ci)


func _block(batch: UiTheme.ShapeBatch, r: Rect2, c: Color, dir: float, top: bool) -> void:
	var d := r.size.x * 0.26
	var off := Vector2(d * dir, -d)
	var edge_x := r.end.x if dir > 0.0 else r.position.x
	var tr := Vector2(edge_x, r.position.y)
	var br := Vector2(edge_x, r.end.y)
	batch.polygon(PackedVector2Array([tr, tr + off, br + off, br]), c.darkened(0.22))
	var tl := r.position
	var tr2 := Vector2(r.end.x, r.position.y)
	batch.polygon(PackedVector2Array([tl, tr2, tr2 + off, tl + off]), c.lightened(0.25))
	batch.polygon(UiTheme.round_rect_points(r, r.size.x * 0.12, 3), c)
	# Brillo arriba a la izquierda del frente.
	var gloss := Rect2(r.position + r.size * 0.12, r.size * Vector2(0.45, 0.16))
	batch.polygon(UiTheme.round_rect_points(gloss, gloss.size.y / 2.0, 2), Color(1, 1, 1, 0.28))
	if top:
		var stud := r.position + Vector2(r.size.x / 2.0, 0) + off / 2.0
		batch.ellipse(stud + Vector2(0, 2), r.size.x * 0.24, d * 0.3, c.darkened(0.15))
		batch.ellipse(stud - Vector2(0, 3), r.size.x * 0.24, d * 0.3, c.lightened(0.35))


## Piso a cuadros que se aleja: filas más finas y columnas que convergen
## hacia un punto de fuga en el centro; se funde con la bruma al fondo.
func _floor(ci: CanvasItem, floor_y: float) -> void:
	var w := size.x
	var h := size.y
	var horizon := floor_y - h * 0.25  # Horizonte (oculto): de él sale la perspectiva.
	var cell := 170.0                   # Ancho de una baldosa en el borde de abajo.
	var depth_max := (h - horizon) / (floor_y - horizon)
	ci.draw_rect(Rect2(0, floor_y, w, h - floor_y), UiTheme.BG_FLOOR_A)
	var batch := UiTheme.ShapeBatch.new()
	var row := 0
	var depth := 1.0
	while depth < depth_max:
		var d2 := minf(depth + 0.13 * depth, depth_max)
		var y0 := horizon + (h - horizon) / d2   # borde de arriba (más lejos)
		var y1 := horizon + (h - horizon) / depth
		var k0 := (y0 - horizon) / (h - horizon)
		var k1 := (y1 - horizon) / (h - horizon)
		var fog := pow(1.0 - (y1 - floor_y) / (h - floor_y), 2.0) * 0.7
		var col := UiTheme.BG_FLOOR_B.lerp(UiTheme.BG_HAZE, fog)
		var half := int(ceil(w / 2.0 / (cell * k0))) + 1
		for i in range(-half, half):
			if (i + row) % 2 == 0:
				continue
			var xa := i * cell
			var xb := xa + cell
			batch.polygon(PackedVector2Array([
				Vector2(w / 2.0 + xa * k0, y0), Vector2(w / 2.0 + xb * k0, y0),
				Vector2(w / 2.0 + xb * k1, y1), Vector2(w / 2.0 + xa * k1, y1)]), col)
		depth = d2
		row += 1
	batch.flush(ci)
	# Brillo del piso cerca del horizonte y borde del escenario.
	var shine := Color(1, 1, 1, 0.45)
	ci.draw_polygon(PackedVector2Array([Vector2(0, floor_y), Vector2(w, floor_y), Vector2(w, floor_y + 90), Vector2(0, floor_y + 90)]),
		PackedColorArray([shine, shine, Color(shine, 0.0), Color(shine, 0.0)]))


## Viñeta: anillo entre una elipse interior (transparente) y otra más
## grande que la pantalla (oscura): bordes y esquinas se oscurecen de a poco.
func _vignette(ci: CanvasItem, w: float, h: float) -> void:
	var steps := 48
	var c := Vector2(w / 2.0, h / 2.0)
	var pts := UiTheme.ellipse_points(c, w * 0.36, h * 0.36, 0.0, steps)
	pts.append_array(UiTheme.ellipse_points(c, w * 0.75, h * 0.78, 0.0, steps))
	var cols := PackedColorArray()
	cols.resize(steps * 2)
	cols.fill(UiTheme.BG_VIGNETTE)
	for i in steps:
		cols[i] = Color(UiTheme.BG_VIGNETTE, 0.0)
	var idx := PackedInt32Array()
	for i in steps:
		var j := (i + 1) % steps
		idx.append_array([i, j, steps + i, j, steps + j, steps + i])
	RenderingServer.canvas_item_add_triangle_array(ci.get_canvas_item(), idx, pts, cols)


# --- Capa nítida -----------------------------------------------------------------

func _draw_front() -> void:
	if bricks:
		_draw_brick_row(_front, 0.0)
		_draw_brick_row(_front, size.y - BRICK_H)


## Los botones de los bloques van todos en un lote al final de la fila: no
## se tocan con los bloques vecinos, así que el orden no cambia nada.
func _draw_brick_row(ci: CanvasItem, y: float) -> void:
	var studs := UiTheme.ShapeBatch.new()
	var i := 0
	var x := 0.0
	while x < size.x:
		var c: Color = UiTheme.BRICKS[i % UiTheme.BRICKS.size()]
		var r := Rect2(x + 1.0, y + 1.0, BRICK_W - 2.0, BRICK_H - 2.0)
		UiTheme.draw_round_rect(ci, r, c.darkened(0.2), 7)
		UiTheme.draw_round_rect(ci, Rect2(r.position, r.size - Vector2(0, 5)), c, 7)
		for k in 2:
			var stud := Vector2(r.position.x + r.size.x * (0.3 + 0.4 * k), r.position.y + r.size.y * 0.42)
			studs.circle(stud, 7.0, c.lightened(0.28))
		x += BRICK_W
		i += 1
	studs.flush(ci)


# --- Texturas hechas por código (una vez por proceso) -----------------------------

## Nube suave: unión de círculos con base plana, borde difuso y panza
## azulada. Sin archivos que importar.
static func cloud_texture() -> Texture2D:
	if _cloud_tex != null:
		return _cloud_tex
	var w := CLOUD_TEX.x
	var h := CLOUD_TEX.y
	var blobs: Array[Vector3] = [Vector3(40, 50, 21), Vector3(66, 35, 27), Vector3(98, 36, 25),
		Vector3(124, 50, 19), Vector3(82, 52, 26)]
	var bottom := 63.0
	var data := PackedByteArray()
	data.resize(w * h * 4)
	var i := 0
	for y in h:
		var fy := y + 0.5
		var shade := clampf((fy - 22.0) / (bottom - 22.0), 0.0, 1.0)
		var col := UiTheme.PAPER.lerp(UiTheme.BG_CLOUD_SHADE, shade * shade)
		var r8 := col.r8
		var g8 := col.g8
		var b8 := col.b8
		for x in w:
			var p := Vector2(x + 0.5, fy)
			var d := fy - bottom
			var dmin := 1e9
			for b in blobs:
				dmin = minf(dmin, p.distance_to(Vector2(b.x, b.y)) - b.z)
			# Base: cápsula horizontal (sin muescas entre los círculos).
			dmin = minf(dmin, p.distance_to(Vector2(clampf(p.x, 36.0, 124.0), 50.0)) - 15.0)
			d = maxf(d, dmin)
			data[i] = r8
			data[i + 1] = g8
			data[i + 2] = b8
			data[i + 3] = int(clampf(0.5 - d / 5.0, 0.0, 1.0) * 255.0)
			i += 4
	_cloud_tex = ImageTexture.create_from_image(Image.create_from_data(w, h, false, Image.FORMAT_RGBA8, data))
	return _cloud_tex


## Destello de cuatro puntas con halo (blanco: se tiñe con `modulate`).
static func sparkle_texture() -> Texture2D:
	if _sparkle_tex != null:
		return _sparkle_tex
	var n := SPARKLE_TEX
	var data := PackedByteArray()
	data.resize(n * n * 4)
	data.fill(255)
	var half := n / 2.0
	for y in n:
		for x in n:
			var p := Vector2(x + 0.5 - half, y + 0.5 - half)
			var glow := exp(-p.length_squared() / 40.0) * 0.7
			var arm_h := exp(-absf(p.y) / 1.2) * maxf(0.0, 1.0 - absf(p.x) / half)
			var arm_v := exp(-absf(p.x) / 1.2) * maxf(0.0, 1.0 - absf(p.y) / half)
			data[(y * n + x) * 4 + 3] = int(clampf(glow + arm_h + arm_v, 0.0, 1.0) * 255.0)
	_sparkle_tex = ImageTexture.create_from_image(Image.create_from_data(n, n, false, Image.FORMAT_RGBA8, data))
	return _sparkle_tex
