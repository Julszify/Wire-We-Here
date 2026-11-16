class_name Tablet
extends Control
## Tablet-Menü für Upgrades. Tab öffnet/schließt; das Spiel läuft weiter.
## Liest nur aus Economy und ruft Economy.buy auf – keine eigene Spiellogik.

signal closed
signal new_game_requested
## Abschaltknopf für C.O.R.D. gedrückt (Dienst mit special "cord_snooze")
signal snooze_requested
## Alle Abräum-Drohnen arbeiten ab jetzt dort, wo der Spieler steht
signal drones_recall_requested

var economy: Economy
var rack: ServiceRack

var _list: VBoxContainer
var _money: Label
var _services: Label
var _rows: Dictionary = {}  # Upgrade-ID -> { level, button, desc }
var _new_game: Button
var _snooze: Button
var _recall: Button
var _effects: Label
var _progress: Label
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
	# Viele Werkzeuge: Liste scrollt, damit das Tablet auf den Bildschirm passt
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 430)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(scroll)
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 10)
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_list)
	for id in Balancing.tablet_order:
		_add_row(String(id))

	box.add_child(HSeparator.new())
	_services = Label.new()
	_services.add_theme_color_override("font_color", Color(0.7, 0.75, 0.8))
	box.add_child(_services)
	_progress = Label.new()
	_progress.add_theme_font_size_override("font_size", 14)
	_progress.add_theme_color_override("font_color", Color(0.75, 0.82, 0.95))
	_progress.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_progress)
	_effects = Label.new()
	_effects.add_theme_font_size_override("font_size", 14)
	_effects.add_theme_color_override("font_color", Color(0.6, 0.85, 0.7))
	_effects.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_effects)
	_snooze = Button.new()
	_snooze.custom_minimum_size = Vector2(0, 40)
	_snooze.pressed.connect(func() -> void: snooze_requested.emit())
	box.add_child(_snooze)
	_recall = Button.new()
	_recall.custom_minimum_size = Vector2(0, 40)
	_recall.text = "Drohnen zu mir rufen (arbeiten ab jetzt hier)"
	_recall.pressed.connect(func() -> void: drones_recall_requested.emit())
	box.add_child(_recall)
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
	rack.port_plugged.connect(func(_p: int) -> void: refresh())
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
			desc.text = "Benötigt Dienst „%s“ (%s)." % [RackPlan.service_name(blocker), RackPlan.service_place(blocker)]
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
	_services.text = "Dienste online: %d / %d   ·   Ports belegt: %d / %d   ·   Tasche: %d Knäuel" % [
		rack.active_services(), RackPlan.total_services(), rack.active_count(), RackPlan.total_ports(), economy.bag_capacity()]
	_effects.text = _effects_text()
	_effects.visible = _effects.text != ""
	# Fortschritt je Viertel: eingesteckte wichtige Kabel / Ports des Schranks
	var parts: PackedStringArray = []
	for sec in RackPlan.sections():
		parts.append("%s %d/%d" % [sec["name"], RackPlan.section_plugged(economy.state, sec["id"]), int(sec["count"])])
	_progress.text = "Wichtige Kabel je Viertel:  " + "  ·  ".join(parts)
	_recall.visible = economy.state.level("drone") > 0
	_snooze.visible = RackPlan.has_special(economy.state, "cord_snooze")
	var wait := economy.state.snooze_cooldown
	_snooze.disabled = wait > 0.0
	_snooze.text = "C.O.R.D. abschalten (5 Minuten Ruhe)" if wait <= 0.0 else "C.O.R.D.-Abschaltknopf lädt … noch %d:%02d" % [int(wait / 60.0), int(wait) % 60]
	if not visible:
		_confirm = false
		_new_game.text = "Neues Spiel"


## Kurze Liste, was die laufenden Dienste gerade bewirken
func _effects_text() -> String:
	var names := { "money": "Geld", "press": "Handzug", "motor": "Motorrollen", "walk": "Lauftempo",
		"important_pay": "Wichtige Kabel", "order_count": "Bestellmenge", "ask_interval": "Pause zwischen Fragen" }
	var parts := []
	for key: String in names:
		var f := economy.bonus(key)
		if not is_equal_approx(f, 1.0):
			parts.append("%s ×%s" % [names[key], ("%.2f" % f).replace(".", ",")])
	if economy.bonus("answer_time") != 0.0:
		parts.append("Antwortzeit +%d s" % int(economy.bonus("answer_time")))
	if economy.bonus("knot_presses") != 0.0:
		parts.append("Knoten %d Druck" % int(economy.bonus("knot_presses")))
	return "" if parts.is_empty() else "Wirkung der Dienste: " + "  ·  ".join(parts)


func _process(_delta: float) -> void:
	# Wartezeit des Abschaltknopfs läuft sichtbar herunter
	if visible and _snooze and _snooze.visible and _snooze.disabled:
		refresh()


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
