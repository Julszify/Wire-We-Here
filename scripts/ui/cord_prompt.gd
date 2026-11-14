class_name CordPrompt
extends PanelContainer
## Bildschirm-Anzeige der Bestellfrage mit ablaufendem Balken.

var _text: Label
var _bar: ProgressBar
var _total := 1.0


func _ready() -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.12, 0.05, 0.05, 0.92)
	style.border_color = Color(1.0, 0.25, 0.2)
	style.set_border_width_all(4)
	style.set_corner_radius_all(16)
	style.set_content_margin_all(18)
	add_theme_stylebox_override("panel", style)
	set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	position.y = 110
	custom_minimum_size = Vector2(620, 0)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	add_child(box)
	var who := Label.new()
	who.text = "C.O.R.D."
	who.add_theme_color_override("font_color", Color(1.0, 0.45, 0.4))
	who.add_theme_font_size_override("font_size", 18)
	box.add_child(who)
	_text = Label.new()
	_text.text = "Defektes Kabel erkannt. Ersatz bestellen?"
	_text.add_theme_font_size_override("font_size", 26)
	box.add_child(_text)
	var keys := Label.new()
	keys.text = "N: Nein!     (nichts tun = bestellen)"
	keys.add_theme_font_size_override("font_size", 20)
	keys.add_theme_color_override("font_color", Color(1.0, 0.9, 0.3))
	box.add_child(keys)
	_bar = ProgressBar.new()
	_bar.show_percentage = false
	_bar.custom_minimum_size = Vector2(0, 14)
	box.add_child(_bar)
	visible = false


func show_question(total_time: float) -> void:
	_total = maxf(total_time, 0.01)
	_bar.max_value = 1.0
	_bar.value = 1.0
	visible = true
	# Zentrieren, nachdem die Größe feststeht
	await get_tree().process_frame
	position.x = (get_viewport_rect().size.x - size.x) * 0.5


func update_time(left: float) -> void:
	_bar.value = clampf(left / _total, 0.0, 1.0)
