class_name VolumeStepper
extends Stepper
## Volumen de un bus (música o efectos) para el menú de pausa de la TV:
## con el foco encima, ◀ y ▶ lo bajan o suben de a 10 %; ▲ ▼ siguen
## navegando. Aplica y guarda el cambio solo (AudioMix), así el menú que lo
## contiene no necesita señales nuevas: alcanza con
##   box.add_child(VolumeStepper.new(AudioMix.BUS_MUSIC, "Música"))
## Al cambiar el volumen de efectos suena un "select" de muestra.

var bus_name := ""
var title := ""


func _init(bus: String = AudioMix.BUS_MUSIC, text: String = "Música") -> void:
	super._init()  # Foco y tamaño mínimo de Stepper.
	bus_name = bus
	title = text
	min_value = 0
	max_value = AudioMix.STEPS
	value = roundi(AudioMix.get_volume(bus_name) * AudioMix.STEPS)
	value_changed.connect(_on_value_changed)


## Relee el volumen actual (por si cambió en otro lado).
func sync() -> void:
	value = roundi(AudioMix.get_volume(bus_name) * AudioMix.STEPS)
	queue_redraw()


func _on_value_changed(v: int) -> void:
	AudioMix.set_volume(bus_name, float(v) / AudioMix.STEPS)
	AudioMix.save_prefs()
	if bus_name == AudioMix.BUS_SFX:
		Sfx.play("select")


func _draw() -> void:
	if size.y < 24.0:  # Todavía sin layout.
		return
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
	var pct := "No" if value == 0 else "%d %%" % (value * 100 / AudioMix.STEPS)
	UiTheme.draw_text(self, "%s: %s" % [title, pct], r.get_center(), int(h * 0.4), UiTheme.INK)
