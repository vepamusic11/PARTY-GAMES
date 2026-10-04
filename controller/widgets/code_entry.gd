class_name CodeEntry
extends LineEdit
## Código de sala en fichas grandes de colores, iguales a las de la TV
## (UiTheme.code_tile_color). Es un LineEdit invisible con las fichas
## dibujadas encima: tocarlo abre el teclado del celular como cualquier
## campo. Pasa todo a mayúsculas; la validación sigue en Protocol.
##
## Se redibuja solo cuando cambia (LineEdit redibuja al cambiar el texto o
## el foco): nada corre por frame.

const GAP := 22.0


func _init() -> void:
	max_length = Protocol.ROOM_CODE_LENGTH
	placeholder_text = ""
	context_menu_enabled = false
	selecting_enabled = false
	virtual_keyboard_type = LineEdit.KEYBOARD_TYPE_DEFAULT
	var tiles := Protocol.ROOM_CODE_LENGTH
	custom_minimum_size = Vector2(UiTheme.PHONE_TILE_SIZE.x * tiles + GAP * (tiles - 1) + 40.0, UiTheme.PHONE_TILE_SIZE.y + 24.0)
	size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	for style in ["normal", "focus", "read_only"]:
		add_theme_stylebox_override(style, StyleBoxEmpty.new())
	for key in ["font_color", "font_uneditable_color", "caret_color", "selection_color", "font_selected_color",
			"font_placeholder_color", "clear_button_color"]:
		add_theme_color_override(key, Color.TRANSPARENT)
	text_changed.connect(_on_text_changed)
	focus_entered.connect(func() -> void: caret_column = text.length())


func _on_text_changed(t: String) -> void:
	var upper := t.to_upper()
	if upper != t:
		text = upper
		caret_column = upper.length()


func _draw() -> void:
	var n := Protocol.ROOM_CODE_LENGTH
	var tile := UiTheme.PHONE_TILE_SIZE
	var total := tile.x * n + GAP * (n - 1)
	var x0 := (size.x - total) / 2.0
	var y0 := (size.y - tile.y) / 2.0
	var next := mini(text.length(), n - 1)
	for i in n:
		var letter := text[i] if i < text.length() else ""
		UiTheme.draw_letter_tile(self, Rect2(Vector2(x0 + i * (tile.x + GAP), y0), tile), letter,
			UiTheme.code_tile_color(i), has_focus() and i == next)
