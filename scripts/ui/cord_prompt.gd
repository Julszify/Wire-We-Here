class_name CordPrompt
extends PanelContainer
## Bildschirm-Anzeige der Bestellfrage mit ablaufendem Balken.

var _text: Label
var _bar: ProgressBar
var _total := 1.0


func _ready() -> void:
	# Spielzeug-Look: helle Karte mit dickem rotem Rand, Balken als rote Pille
	var style := UiTheme.box(UiTheme.PAPER, UiTheme.RED, 26, 6, 10, 18)
	style.border_width_bottom = 12
	add_theme_stylebox_override("panel", style)
	set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	position.y = 110
	custom_minimum_size = Vector2(640, 0)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	add_child(box)
	var who := Label.new()
	who.text = "C.O.R.D. fragt:"
	UiTheme.style_label(who, 18, UiTheme.RED)
	box.add_child(who)
	_text = Label.new()
	_text.text = "Defektes Kabel erkannt. Ersatz bestellen?"
	UiTheme.style_label(_text, 26, UiTheme.INK)
	box.add_child(_text)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	box.add_child(row)
	var key := Label.new()
	key.text = "N"
	UiTheme.style_label(key, 22, Color.WHITE)
	var cap := UiTheme.box(UiTheme.RED, UiTheme.RED.darkened(0.35), 12, 0, 0, 4)
	cap.border_width_bottom = 5
	cap.border_color = UiTheme.RED.darkened(0.35)
	cap.content_margin_left = 14
	cap.content_margin_right = 14
	key.add_theme_stylebox_override("normal", cap)
	row.add_child(key)
	var keys := Label.new()
	keys.text = "Nein!   (nichts tun = bestellen)"
	UiTheme.style_label(keys, 20, UiTheme.INK_SOFT)
	row.add_child(keys)
	_bar = ProgressBar.new()
	_bar.show_percentage = false
	_bar.custom_minimum_size = Vector2(0, 16)
	_bar.add_theme_stylebox_override("background", UiTheme.box(UiTheme.PAPER_DIM.darkened(0.06), Color(0, 0, 0, 0), 8, 0, 0, 0))
	_bar.add_theme_stylebox_override("fill", UiTheme.box(UiTheme.RED, Color(0, 0, 0, 0), 8, 0, 0, 0))
	box.add_child(_bar)
	visible = false


func show_question(total_time: float) -> void:
	_total = maxf(total_time, 0.01)
	_bar.max_value = 1.0
	_bar.value = 1.0
	visible = true
	# Zentrieren, nachdem die Größe feststeht
	await get_tree().process_frame
	if is_inside_tree():
		position.x = (get_viewport_rect().size.x - size.x) * 0.5


func update_time(left: float) -> void:
	_bar.value = clampf(left / _total, 0.0, 1.0)
