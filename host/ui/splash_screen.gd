class_name SplashScreen
extends Control
## Presentación de la marca paraguas al abrir la TV: "IO-GAMES presenta".
## Dura UiTheme.SPLASH_TOTAL (≤ 2,5 s) y cualquier tecla del control remoto
## (o un toque) la saltea.
##
## Concepto: *marca paraguas* (endorsed brand). IO-GAMES es el estudio que
## va a publicar varios juegos; PARTY-GAME es el primero. Ejemplo: así como
## una película muestra el logo del estudio antes del título, la TV muestra
## IO-GAMES un instante y después el lobby con el logo de PARTY-GAME.
##
## Entrada "de cine", en tres tiempos:
##   0,0–0,5 s  el logo aparece creciendo desde un resplandor azul
##   0,2–1,4 s  chispas de neón (cian y violeta) salen del logo
##   0,45–1,3 s un brillo recorre el logo en diagonal (shader: solo aclara
##              las partes luminosas, el fondo oscuro del logo no cambia)
##   … y a los ~1,95 s se funde al lobby.
## Con UiTheme.reduce_motion: solo fundidos (sin escala, brillo ni chispas).
##
## Rendimiento: el brillo es un parámetro del shader (no se redibuja nada) y
## las chispas son un CPUParticles2D de 40 partículas que existe 2 segundos.

signal finished

const FADE_IN := 0.5
const SWEEP_AT := 0.45
const SWEEP_DUR := 0.85
const FADE_OUT := 0.3
const HOLD := UiTheme.SPLASH_TOTAL - FADE_IN - FADE_OUT  ## Quieto, antes de fundirse.

## Brillo que recorre el logo: una franja diagonal que suma luz solo donde
## el logo ya es luminoso (el neón), así el fondo oscuro no se "lava".
const SHINE_SHADER := """
shader_type canvas_item;
uniform float sweep = -0.4;
uniform float width = 0.11;
uniform vec4 shine : source_color = vec4(1.0, 1.0, 1.0, 0.9);
void fragment() {
	vec4 c = texture(TEXTURE, UV);
	float d = abs((UV.x + UV.y * 0.4) - sweep);
	float band = smoothstep(width, 0.0, d);
	float lum = max(c.r, max(c.g, c.b));
	c.rgb += shine.rgb * shine.a * band * smoothstep(0.3, 0.85, lum);
	COLOR = c * COLOR;
}
"""

var _done := false
var _logo: TextureRect
var _glow: Control
var _presents: Label
var _sparks: CPUParticles2D
var _shine: ShaderMaterial


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = UiTheme.build()
	mouse_filter = Control.MOUSE_FILTER_STOP
	var bg := ColorRect.new()
	bg.color = UiTheme.STUDIO_BG
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var box := VBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 24)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(box)
	_logo = UiTheme.logo_rect(UiTheme.STUDIO_LOGO_PATH)
	_logo.custom_minimum_size = Vector2(0, 620)
	_shine = ShaderMaterial.new()
	_shine.shader = Shader.new()
	_shine.shader.code = SHINE_SHADER
	_logo.material = _shine
	_logo.resized.connect(func() -> void: _logo.pivot_offset = _logo.size / 2.0)
	box.add_child(_logo)
	var feather := _Feather.new()
	feather.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_logo.add_child(feather)
	_presents = UiTheme.label("presenta", 34, Color(UiTheme.PAPER, 0.8))
	box.add_child(_presents)
	# Resplandor y chispas van encima y suman luz (mezcla aditiva): así
	# cubren también el fondo propio del logo sin que se vea su rectángulo.
	var add := CanvasItemMaterial.new()
	add.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_glow = Control.new()
	_glow.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_glow.material = add
	_glow.draw.connect(_draw_glow)
	_glow.resized.connect(func() -> void: _glow.pivot_offset = _glow.size * Vector2(0.5, 0.45))
	add_child(_glow)
	_sparks = _make_sparks()
	_sparks.material = add
	add_child(_sparks)
	resized.connect(_place_sparks)
	_play()


func _play() -> void:
	_logo.modulate.a = 0.0
	_presents.modulate.a = 0.0
	_glow.modulate.a = 0.0
	var tw := create_tween().set_parallel()
	tw.tween_property(_logo, "modulate:a", 1.0, FADE_IN * 0.7)
	tw.tween_property(_glow, "modulate:a", 1.0, FADE_IN)
	tw.tween_property(_presents, "modulate:a", 1.0, 0.3).set_delay(FADE_IN + 0.1)
	if not UiTheme.reduce_motion:
		tw.tween_property(_logo, "scale", Vector2.ONE, FADE_IN).from(Vector2.ONE * 0.86) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tw.tween_property(_glow, "scale", Vector2.ONE, FADE_IN + 0.3).from(Vector2.ONE * 0.5) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tw.tween_method(_set_sweep, -0.4, 1.8, SWEEP_DUR).set_delay(SWEEP_AT) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		tw.tween_callback(_start_sparks).set_delay(0.2)
	var seq := create_tween()
	seq.tween_interval(FADE_IN + HOLD)
	seq.tween_callback(_finish)


func _set_sweep(v: float) -> void:
	_shine.set_shader_parameter("sweep", v)


func _input(event: InputEvent) -> void:
	if _done or not event.is_pressed():
		return
	if event is InputEventKey or event is InputEventJoypadButton or event is InputEventMouseButton \
			or event is InputEventScreenTouch:
		get_viewport().set_input_as_handled()
		_finish()


func _finish() -> void:
	if _done:
		return
	_done = true
	_sparks.emitting = false
	var tw := create_tween()
	tw.tween_property(self, "modulate:a", 0.0, FADE_OUT)
	tw.tween_callback(func() -> void:
		finished.emit()
		queue_free())


# --- Chispas y resplandor ------------------------------------------------------------

func _make_sparks() -> CPUParticles2D:
	var p := CPUParticles2D.new()
	p.emitting = false
	p.one_shot = true
	p.amount = 40
	p.lifetime = 1.2
	p.explosiveness = 0.75
	p.texture = PartyBackground.sparkle_texture()
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	p.direction = Vector2(0, -1)
	p.spread = 80.0
	p.initial_velocity_min = 90.0
	p.initial_velocity_max = 260.0
	p.gravity = Vector2(0, 60)
	p.damping_min = 40.0
	p.damping_max = 80.0
	p.scale_amount_min = 0.35
	p.scale_amount_max = 1.0
	var ramp := Gradient.new()
	ramp.set_color(0, UiTheme.STUDIO_CYAN)
	ramp.set_color(1, Color(UiTheme.STUDIO_MAGENTA, 0.0))
	ramp.add_point(0.55, UiTheme.STUDIO_MAGENTA)
	p.color_ramp = ramp
	return p


func _place_sparks() -> void:
	_sparks.position = size * Vector2(0.5, 0.46)
	_sparks.emission_rect_extents = Vector2(size.x * 0.2, size.y * 0.12)


func _start_sparks() -> void:
	if _done:
		return
	_place_sparks()
	_sparks.restart()
	_sparks.emitting = true


## Resplandor azul sobre el logo (degradé radial aditivo, se dibuja una vez).
func _draw_glow() -> void:
	var c := _glow.size * Vector2(0.5, 0.45)
	UiTheme.draw_radial(_glow, c, _glow.size.x * 0.42, UiTheme.STUDIO_GLOW, Color(UiTheme.STUDIO_GLOW, 0.0),
		_glow.size.y * 0.42, 48)


## Funde los bordes del logo (que trae su propio fondo) con el fondo de la
## pantalla, para que no se vea el rectángulo de la imagen.
class _Feather:
	extends Control

	const WIDTH := 0.16  ## Proporción del alto del logo que se funde.

	func _draw() -> void:
		var tex := (get_parent() as TextureRect).texture
		if tex == null:
			return
		var aspect := float(tex.get_width()) / tex.get_height()
		var h := minf(size.y, size.x / aspect)
		var r := Rect2((size - Vector2(h * aspect, h)) / 2.0, Vector2(h * aspect, h))
		var w := h * WIDTH
		var solid := UiTheme.STUDIO_BG
		var clear := Color(solid, 0.0)
		var tl := r.position
		var br := r.end
		# Cuatro bandas en degradé: opaco en el borde, transparente hacia adentro.
		_band([tl, Vector2(br.x, tl.y), Vector2(br.x, tl.y + w), Vector2(tl.x, tl.y + w)], solid, clear)
		_band([Vector2(tl.x, br.y), br, Vector2(br.x, br.y - w), Vector2(tl.x, br.y - w)], solid, clear)
		_band([tl, Vector2(tl.x, br.y), Vector2(tl.x + w, br.y), Vector2(tl.x + w, tl.y)], solid, clear)
		_band([Vector2(br.x, tl.y), br, Vector2(br.x - w, br.y), Vector2(br.x - w, tl.y)], solid, clear)

	func _band(pts: Array, edge: Color, inner: Color) -> void:
		draw_polygon(PackedVector2Array(pts), PackedColorArray([edge, edge, inner, inner]))
