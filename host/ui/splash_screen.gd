class_name SplashScreen
extends Control
## Presentación de la marca paraguas al abrir la TV: "IO-GAMES presenta".
## Dura menos de 2,5 s y cualquier tecla del control remoto la saltea.
##
## Concepto: *marca paraguas* (endorsed brand). IO-GAMES es el estudio que
## va a publicar varios juegos; PARTY-GAME es el primero. Ejemplo: así como
## una película muestra el logo del estudio antes del título, la TV muestra
## IO-GAMES un instante y después el lobby con el logo de PARTY-GAME.

signal finished

const HOLD := 1.4

var _done := false


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
	add_child(box)
	var logo := UiTheme.logo_rect(UiTheme.STUDIO_LOGO_PATH)
	logo.custom_minimum_size = Vector2(0, 300)
	box.add_child(logo)
	var feather := _Feather.new()
	feather.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	logo.add_child(feather)
	var presents := UiTheme.label("presenta", 34, Color(UiTheme.PAPER, 0.8))
	box.add_child(presents)
	modulate.a = 0.0
	var tw := create_tween()
	tw.tween_property(self, "modulate:a", 1.0, 0.35)
	tw.tween_interval(HOLD)
	tw.tween_callback(_finish)


func _input(event: InputEvent) -> void:
	if not _done and (event is InputEventKey or event is InputEventJoypadButton) and event.is_pressed():
		get_viewport().set_input_as_handled()
		_finish()


func _finish() -> void:
	if _done:
		return
	_done = true
	var tw := create_tween()
	tw.tween_property(self, "modulate:a", 0.0, 0.3)
	tw.tween_callback(func() -> void:
		finished.emit()
		queue_free())


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
