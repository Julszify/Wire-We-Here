class_name Tablet
extends Control
## Tablet-Menü für Upgrades. Tab öffnet/schließt; das Spiel läuft weiter.
## Liest nur aus Economy und ruft Economy.buy auf – keine eigene Spiellogik.

signal closed
signal new_game_requested

var economy: Economy
var rack: ServiceRack

var _list: VBoxContainer
var _money: Label
var _services: Label
var _rows: Dictionary = {}  # Upgrade-ID -> { level, button, desc }
var _new_game: Button
var _confirm := false


func setup(eco: Economy, service_rack: ServiceRack) -> void:
	economy = eco
	rack = service_rack
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP

	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0, 0.35)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(shade)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var frame := PanelContainer.new()
	frame.custom_minimum_size = Vector2(720, 0)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.11, 0.14, 0.19)
	style.border_color = Color(0.32, 0.36, 0.42)
	style.set_border_width_all(10)
	style.set_corner_radius_all(26)
	style.set_content_margin_all(26)
	frame.add_theme_stylebox_override("panel", style)
	center.add_child(frame)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	frame.add_child(box)

	var head := HBoxContainer.new()
	box.add_child(head)
	var title := Label.new()
	title.text = "Wolkig-Tablet · Werkzeug-Shop"
	title.add_theme_font_size_override("font_size", 26)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	_money = Label.new()
	_money.add_theme_font_size_override("font_size", 26)
	_money.add_theme_color_override("font_color", Color(1, 0.9, 0.3))
	head.add_child(_money)

	box.add_child(HSeparator.new())
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 10)
	box.add_child(_list)
	for id in Balancing.tablet_order:
		_add_row(String(id))

	box.add_child(HSeparator.new())
	_services = Label.new()
	_services.add_theme_color_override("font_color", Color(0.7, 0.75, 0.8))
	box.add_child(_services)
	var foot := HBoxContainer.new()
	box.add_child(foot)
	var hint := Label.new()
	hint.text = "Tab oder Esc: schließen   ·   F5 speichern, F9 laden (speichert auch automatisch)"
	hint.add_theme_color_override("font_color", Color(0.55, 0.6, 0.65))
	hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	foot.add_child(hint)
	_new_game = Button.new()
	_new_game.text = "Neues Spiel"
	_new_game.pressed.connect(_on_new_game_pressed)
	foot.add_child(_new_game)

	economy.money_changed.connect(func(_m: float) -> void: refresh())
	economy.upgrade_bought.connect(func(_id: String, _l: int) -> void: refresh())
	rack.service_activated.connect(func(_p: int, _n: String, _u: String) -> void: refresh())
	refresh()


func _add_row(id: String) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	_list.add_child(row)
	var text := VBoxContainer.new()
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(text)
	var name_label := Label.new()
	name_label.text = economy.upgrade_name(id)
	name_label.add_theme_font_size_override("font_size", 20)
	text.add_child(name_label)
	var desc := Label.new()
	desc.add_theme_font_size_override("font_size", 15)
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.add_child(desc)
	var level := Label.new()
	level.custom_minimum_size = Vector2(70, 0)
	level.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	level.add_theme_font_size_override("font_size", 18)
	row.add_child(level)
	var button := Button.new()
	button.custom_minimum_size = Vector2(150, 44)
	button.add_theme_font_size_override("font_size", 18)
	button.pressed.connect(func() -> void: economy.buy(id))
	row.add_child(button)
	_rows[id] = { "level": level, "button": button, "desc": desc }


func refresh() -> void:
	if economy == null:
		return
	_money.text = Economy.format_money(economy.state.money)
	for id: String in _rows:
		var r: Dictionary = _rows[id]
		var lvl := economy.state.level(id)
		var u: Dictionary = Balancing.upgrades[id]
		r["level"].text = ("%d/%d" % [lvl, int(u["max_count"])]) if u.has("max_count") else ("Stufe %d" % lvl)
		var button: Button = r["button"]
		var desc: Label = r["desc"]
		var blocker := economy.locked_by(id)
		if blocker >= 0:
			button.text = "Gesperrt"
			button.disabled = true
			desc.text = "Benötigt Dienst „%s“ (Port %d)." % [ServiceRack.service_name(blocker), blocker + 1]
			desc.add_theme_color_override("font_color", Color(0.9, 0.5, 0.4))
		else:
			desc.text = economy.upgrade_description(id)
			desc.add_theme_color_override("font_color", Color(0.75, 0.8, 0.85))
			if economy.is_maxed(id):
				button.text = "Gekauft"
				button.disabled = true
			else:
				button.text = Economy.format_money(economy.cost(id))
				button.disabled = not economy.can_buy(id)
	_services.text = "Dienste online: %d / %d" % [rack.active_count(), ServiceRack.port_count()]
	if not visible:
		_confirm = false
		_new_game.text = "Neues Spiel"


## Zweimal klicken, damit niemand aus Versehen alles löscht
func _on_new_game_pressed() -> void:
	if not _confirm:
		_confirm = true
		_new_game.text = "Wirklich alles löschen?"
		return
	new_game_requested.emit()


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("tablet") or (event is InputEventKey and event.pressed and event.physical_keycode == KEY_ESCAPE):
		get_viewport().set_input_as_handled()
		closed.emit()
