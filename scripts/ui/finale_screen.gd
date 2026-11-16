class_name FinaleScreen
extends Control
## Abspann nach dem Abschalten von C.O.R.D.s Kern. Danach geht das Spiel frei weiter.

signal closed


func setup(cables_done: int, earned: float) -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var shade := ColorRect.new()
	shade.color = Color(0.02, 0.04, 0.08, 0.82)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(shade)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(760, 0)
	box.add_theme_constant_override("separation", 18)
	center.add_child(box)
	var title := Label.new()
	title.text = "Die Cloud ist wieder da."
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 44)
	title.add_theme_color_override("font_color", Color(0.6, 0.95, 1.0))
	box.add_child(title)
	var text := Label.new()
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	text.add_theme_font_size_override("font_size", 20)
	text.text = ("Mit einem letzten Klick geht C.O.R.D.s Kern aus. Das rote Leuchten erlischt, irgendwo unten in der Stadt " +
		"verstummt ein Lieferwagen mitten in der Bestellung.\n\n" +
		"Alle 2000 Ports sind belegt, alle 218 Dienste laufen. Die Wolkig AG ist wieder online – und die drei Chefs " +
		"buchen am Stammtisch schon den nächsten Tisch, um über eine neue KI zu reden.\n\n" +
		"C.O.R.D. schläft. Fürs Erste.")
	box.add_child(text)
	var stats := Label.new()
	stats.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stats.add_theme_font_size_override("font_size", 18)
	stats.add_theme_color_override("font_color", Color(1.0, 0.9, 0.4))
	stats.text = "Aufgerollte Kabel: %d   ·   Verdient: %s" % [cables_done, Economy.format_money(earned)]
	box.add_child(stats)
	var hint := Label.new()
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 16)
	hint.add_theme_color_override("font_color", Color(0.7, 0.75, 0.8))
	hint.text = "Danke fürs Spielen! Die Stadt bleibt offen – es liegen noch genug Kabel herum."
	box.add_child(hint)
	var button := Button.new()
	button.text = "Weiterspielen"
	button.custom_minimum_size = Vector2(240, 48)
	button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	button.add_theme_font_size_override("font_size", 20)
	button.pressed.connect(func() -> void: closed.emit())
	box.add_child(button)
