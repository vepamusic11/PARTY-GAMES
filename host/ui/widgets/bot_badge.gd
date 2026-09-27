class_name BotBadge
extends Control
## Placa "BOT" como nodo (para pantallas armadas con Controls, ej. el
## resumen de ronda): se ancla arriba a la derecha de su padre. Dibuja
## UiTheme.draw_bot_badge una sola vez (no se anima).


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	offset_left = -UiTheme.BOT_BADGE_SIZE.x - 8.0
	offset_right = 0.0
	offset_top = 4.0
	offset_bottom = UiTheme.BOT_BADGE_SIZE.y + 12.0


func _draw() -> void:
	UiTheme.draw_bot_badge(self, size / 2.0)
