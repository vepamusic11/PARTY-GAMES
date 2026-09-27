class_name ScorePedestal
extends Control
## "Consola" en la que se para cada mascota en el resumen de ronda:
## caja del color del jugador, luces arriba, pantalla con el puntaje del
## minijuego y medalla con el puesto.

var color := Color.WHITE
var score_text := ""
var unit := ""
var place := 0
var _lights_on := 0.0  ## 0..1: las luces se encienden en la animación.


func _init() -> void:
	custom_minimum_size = Vector2(250, 190)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func light_up(duration: float = 0.6) -> void:
	create_tween().tween_method(func(v: float) -> void:
		_lights_on = v
		queue_redraw(), 0.0, 1.0, duration)


func _draw() -> void:
	var r := Rect2(Vector2(14, 10), size - Vector2(28, 16))
	UiTheme.draw_round_rect(self, r.grow(4), UiTheme.INK, 26)
	UiTheme.draw_round_rect(self, r, color.darkened(0.25), 22)
	UiTheme.draw_round_rect(self, Rect2(r.position, r.size - Vector2(0, 12)), color, 22)
	# Luces
	for i in 5:
		var p := Vector2(r.position.x + r.size.x * (0.22 + 0.14 * i), r.position.y + 22)
		var on := _lights_on * 5.0 > i
		draw_circle(p, 9, UiTheme.INK)
		draw_circle(p, 7, UiTheme.ACCENT if on else color.darkened(0.45))
	# Pantalla
	var screen := Rect2(r.position.x + 20, r.position.y + 44, r.size.x - 40, r.size.y - 76)
	UiTheme.draw_round_rect(self, screen.grow(3), UiTheme.INK, 16)
	UiTheme.draw_round_rect(self, screen, UiTheme.CHIP_DARK, 14)
	UiTheme.draw_text(self, score_text, screen.get_center() - Vector2(0, 12), 56, UiTheme.ACCENT)
	UiTheme.draw_text(self, unit, Vector2(screen.get_center().x, screen.end.y - 17), 24, Color(UiTheme.ACCENT, 0.75), 0, UiTheme.INK, false)
	# Medalla con el puesto
	if place > 0:
		var m := Vector2(r.position.x + 6, r.position.y + 4)
		if place <= 3 and Props3D.is_ready():
			UiTheme.draw_medal(self, m, 30.0, place)  # Medalla de metal 3D (ADR 0016).
		else:
			draw_circle(m, 34, UiTheme.INK)
			draw_circle(m, 30, UiTheme.place_color(place))
			draw_circle(m + Vector2(-8, -8), 10, Color(1, 1, 1, 0.4))
			UiTheme.draw_text(self, UiTheme.place_text(place), m + Vector2(2, 1), 30, UiTheme.INK)
