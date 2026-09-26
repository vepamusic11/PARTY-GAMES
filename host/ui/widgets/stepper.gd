class_name Stepper
extends Control
## Selector numérico pensado para el control remoto: con el foco encima,
## ◀ y ▶ cambian el valor; ▲ y ▼ siguen navegando como siempre.
## Con mouse (desarrollo) se puede hacer clic en las flechas.

signal value_changed(value: int)

var value := 2
var min_value := 1
var max_value := 4
var unit_one := "jugador"
var unit_many := "jugadores"


func _init() -> void:
	focus_mode = Control.FOCUS_ALL
	custom_minimum_size = Vector2(440, 92)


func set_range(lo: int, hi: int) -> void:
	min_value = lo
	max_value = maxi(lo, hi)
	set_value(value)


func set_value(v: int) -> void:
	var clamped := clampi(v, min_value, max_value)
	var changed := clamped != value
	value = clamped
	queue_redraw()
	if changed:
		value_changed.emit(value)


func _gui_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_left", true):
		set_value(value - 1)
		accept_event()
	elif event.is_action_pressed("ui_right", true):
		set_value(value + 1)
		accept_event()
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var x := (event as InputEventMouseButton).position.x
		if x < size.x * 0.3:
			set_value(value - 1)
		elif x > size.x * 0.7:
			set_value(value + 1)
		grab_focus()
		accept_event()


func _notification(what: int) -> void:
	if what == NOTIFICATION_FOCUS_ENTER or what == NOTIFICATION_FOCUS_EXIT:
		queue_redraw()


func _draw() -> void:
	var r := Rect2(Vector2(6, 6), size - Vector2(12, 12))
	var radius := r.size.y / 2.0
	if has_focus():
		UiTheme.draw_round_rect(self, r.grow(12), Color(UiTheme.INK, 0.5), radius + 12)
		UiTheme.draw_round_rect(self, r.grow(9), UiTheme.ACCENT, radius + 9)
	UiTheme.draw_round_rect(self, r, UiTheme.PAPER, radius, 0, UiTheme.INK, true)
	var h := r.size.y
	for side in [-1, 1]:
		var enabled: bool = value > min_value if side < 0 else value < max_value
		var c := Vector2(r.position.x + h / 2.0 + 6, r.get_center().y) if side < 0 \
			else Vector2(r.end.x - h / 2.0 - 6, r.get_center().y)
		draw_circle(c, h * 0.38, UiTheme.ACCENT if enabled else UiTheme.PAPER_DIM)
		UiTheme.draw_arrow(self, c, h * 0.34, Vector2(side, 0), UiTheme.INK if enabled else UiTheme.MUTED)
	var txt := "%d %s" % [value, unit_one if value == 1 else unit_many]
	UiTheme.draw_text(self, txt, r.get_center(), int(h * 0.46), UiTheme.INK)
