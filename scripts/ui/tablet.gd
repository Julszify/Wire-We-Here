class_name Tablet
extends Control
## Wolkig-Tablet im Spielzeug-Look. Tab öffnet/schließt; das Spiel läuft weiter.
## Vier Reiter: Werkzeuge (Upgrades), Serverraum (Ausbau), Kosmetik, Auftrag (Ruf, neuer Auftrag, Fortschritt).
## Liest nur aus Economy und ruft deren Kauf-Funktionen auf – keine eigene Spiellogik.

signal closed
signal new_game_requested
## Neuer Auftrag (Prestige) bestätigt
signal new_job_requested
## Abschaltknopf für C.O.R.D. gedrückt (Dienst mit special "cord_snooze")
signal snooze_requested
## Alle Abräum-Drohnen arbeiten ab jetzt dort, wo der Spieler steht
signal drones_recall_requested
## Kaufen bzw. Kosmetik anlegen (die Welt entscheidet: selbst ausführen oder beim Host anfragen)
signal buy_requested(upgrade_id: String)
signal wear_requested(item_id: String)
## Zurück ins Hauptmenü
signal menu_requested

const TABS := ["Werkzeuge", "Serverraum", "Kosmetik", "Auftrag"]
## Farbe der Grundausstattung je Kosmetik-Platz (für das Farbfeld im Tablet)
const STANDARD_PREVIEW := {
	"hoodie": "#3b8fe0", "pants": "#5a606b", "headphones": "#c9ced6", "shoes": "#f08a24", "cord_band": "#4ce6ff",
	"cord_paint": "#f2f4f7", "drone_paint": "#fac726", "wagon_paint": "#f58c26",
}

var economy: Economy
var rack: ServiceRack
## Mehrspieler: nur der Host darf neu anfangen
var host_only_locked := false
## Angelegtes Stück je Platz für die eigene Figur (Mehrspieler: Figur-Teile gehören jedem selbst)
var own_look: Callable

var _money: Label
var _tab_buttons: Array[Button] = []
var _pages: Array[Control] = []
var _tab := 0
var _rows: Dictionary = {}  # Upgrade-ID -> { level, button, desc }
var _swatches: Dictionary = {}  # Kosmetik-ID -> { button, price, color }
var _services: Label
var _effects: Label
var _snooze: Button
var _recall: Button
var _job_title: Label
var _job_info: Label
var _job_gain: Label
var _job_button: Button
var _new_game: Button
var _bars: Dictionary = {}  # Viertel-ID -> [ProgressBar, Label]
var _confirm := false
var _confirm_job := false


func setup(eco: Economy, service_rack: ServiceRack) -> void:
	economy = eco
	rack = service_rack
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP

	var shade := ColorRect.new()
	shade.color = Color(0.05, 0.08, 0.16, 0.45)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(shade)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	# Gehäuse: dicker, runder Rahmen in Wolkig-Blau
	var device := PanelContainer.new()
	device.custom_minimum_size = Vector2(940, 0)
	var bezel := UiTheme.box(UiTheme.BLUE, UiTheme.BLUE_DARK, 44, 0, 18, 22)
	bezel.border_color = UiTheme.BLUE_DARK
	bezel.border_width_bottom = 12
	device.add_theme_stylebox_override("panel", bezel)
	center.add_child(device)
	var screen := PanelContainer.new()
	screen.add_theme_stylebox_override("panel", UiTheme.box(UiTheme.PAPER, Color(0, 0, 0, 0), 26, 0, 0, 20))
	device.add_child(screen)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	screen.add_child(box)

	var head := HBoxContainer.new()
	box.add_child(head)
	var title := Label.new()
	title.text = "Wolkig-Tablet"
	UiTheme.style_label(title, 30, UiTheme.BLUE_DARK)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	_money = Label.new()
	UiTheme.style_label(_money, 26, UiTheme.INK)
	var pill := UiTheme.box(UiTheme.YELLOW, UiTheme.YELLOW_DARK, 22, 0, 0, 8)
	pill.border_width_bottom = 5
	pill.border_color = UiTheme.YELLOW_DARK
	pill.content_margin_left = 18
	pill.content_margin_right = 18
	_money.add_theme_stylebox_override("normal", pill)
	head.add_child(_money)

	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 10)
	box.add_child(tabs)
	for i in TABS.size():
		var b := Button.new()
		b.text = TABS[i]
		b.custom_minimum_size = Vector2(150, 46)
		b.pressed.connect(_show_tab.bind(i))
		tabs.add_child(b)
		_tab_buttons.append(b)

	var stack := Control.new()
	stack.custom_minimum_size = Vector2(0, 430)
	box.add_child(stack)
	_pages.append(_build_upgrade_page(stack, Balancing.tablet_order, ""))
	_pages.append(_build_upgrade_page(stack, Balancing.room_order,
		"Der Serverraum wächst mit: Jede Stufe ist im Raum zu sehen und wirkt dauerhaft wie ein weiterer Dienst."))
	_pages.append(_build_cosmetics_page(stack))
	_pages.append(_build_job_page(stack))

	_services = Label.new()
	UiTheme.style_label(_services, 15, UiTheme.INK_SOFT, false)
	box.add_child(_services)
	_effects = Label.new()
	UiTheme.style_label(_effects, 14, UiTheme.GREEN_DARK, false)
	_effects.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_effects)
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 10)
	box.add_child(actions)
	_snooze = Button.new()
	_snooze.custom_minimum_size = Vector2(0, 44)
	UiTheme.style_button(_snooze, UiTheme.RED, UiTheme.RED.darkened(0.3), Color.WHITE, 16)
	_snooze.pressed.connect(func() -> void: snooze_requested.emit())
	actions.add_child(_snooze)
	_recall = Button.new()
	_recall.custom_minimum_size = Vector2(0, 44)
	_recall.text = "Drohnen zu mir rufen"
	UiTheme.style_button(_recall, UiTheme.YELLOW, UiTheme.YELLOW_DARK, UiTheme.INK, 16)
	_recall.pressed.connect(func() -> void: drones_recall_requested.emit())
	actions.add_child(_recall)
	var menu := Button.new()
	menu.text = "Hauptmenü"
	menu.custom_minimum_size = Vector2(0, 44)
	UiTheme.style_button(menu, UiTheme.PAPER_DIM, UiTheme.GREY, UiTheme.INK, 16)
	menu.pressed.connect(func() -> void: menu_requested.emit())
	actions.add_child(menu)
	var hint := Label.new()
	hint.text = "Tab oder Esc: schließen  ·  F5 speichern, F9 laden"
	UiTheme.style_label(hint, 14, UiTheme.INK_SOFT, false)
	hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	actions.add_child(hint)

	economy.money_changed.connect(func(_m: float) -> void: refresh())
	economy.upgrade_bought.connect(func(_id: String, _l: int) -> void: refresh())
	economy.look_changed.connect(func(_s: String, _i: String) -> void: refresh())
	rack.port_plugged.connect(func(_p: int) -> void: refresh())
	_show_tab(0)


func show_tab(i: int) -> void:
	_show_tab(clampi(i, 0, TABS.size() - 1))


func _show_tab(i: int) -> void:
	_tab = i
	for k in _pages.size():
		_pages[k].visible = k == i
		UiTheme.style_tab(_tab_buttons[k], k == i)
	refresh()


func _page(parent: Control) -> ScrollContainer:
	var scroll := ScrollContainer.new()
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	parent.add_child(scroll)
	return scroll


func _list_box(scroll: ScrollContainer) -> VBoxContainer:
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 10)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)
	return list


# ---------------------------------------------------------------- Werkzeuge und Serverraum

func _build_upgrade_page(parent: Control, ids: Array, intro: String) -> Control:
	var scroll := _page(parent)
	var list := _list_box(scroll)
	if intro != "":
		var l := Label.new()
		l.text = intro
		UiTheme.style_label(l, 16, UiTheme.INK_SOFT, false)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		list.add_child(l)
	for id in ids:
		_add_row(list, String(id))
	return scroll


func _add_row(list: VBoxContainer, id: String) -> void:
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", UiTheme.box(UiTheme.PAPER_DIM, Color(0, 0, 0, 0), 18, 0, 0, 12))
	list.add_child(card)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	card.add_child(row)
	var text := VBoxContainer.new()
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.add_theme_constant_override("separation", 2)
	row.add_child(text)
	var name_label := Label.new()
	name_label.text = economy.upgrade_name(id)
	UiTheme.style_label(name_label, 20, UiTheme.INK)
	text.add_child(name_label)
	var desc := Label.new()
	UiTheme.style_label(desc, 15, UiTheme.INK_SOFT, false)
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.add_child(desc)
	var level := Label.new()
	level.custom_minimum_size = Vector2(110, 0)
	level.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	level.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	UiTheme.style_label(level, 24, UiTheme.BLUE)
	row.add_child(level)
	var button := Button.new()
	button.custom_minimum_size = Vector2(170, 50)
	button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	UiTheme.style_button(button, UiTheme.GREEN, UiTheme.GREEN_DARK)
	button.pressed.connect(func() -> void: buy_requested.emit(id))
	row.add_child(button)
	_rows[id] = { "level": level, "button": button, "desc": desc }


func _refresh_rows() -> void:
	for id: String in _rows:
		var r: Dictionary = _rows[id]
		var lvl := economy.state.level(id)
		var u: Dictionary = Balancing.upgrades[id]
		var level: Label = r["level"]
		if u.has("max_count") and int(u["max_count"]) == 1:
			level.text = ""  # Einmal-Kauf: der Knopf sagt alles
		elif u.has("max_count") and int(u["max_count"]) <= 8:
			# Stufen als Punkte: ● gekauft, ○ offen
			level.text = "●".repeat(lvl) + "○".repeat(int(u["max_count"]) - lvl)
		elif u.has("max_count"):
			level.text = "%d / %d" % [lvl, int(u["max_count"])]
		else:
			level.text = "Stufe %d" % lvl
		var button: Button = r["button"]
		var desc: Label = r["desc"]
		var blocker := economy.locked_by(id)
		if blocker >= 0:
			button.text = "Gesperrt"
			button.disabled = true
			desc.text = "Benötigt Dienst „%s“ (%s)." % [RackPlan.service_name(blocker), RackPlan.service_place(blocker)]
			desc.add_theme_color_override("font_color", UiTheme.RED)
		else:
			desc.text = economy.upgrade_description(id)
			desc.add_theme_color_override("font_color", UiTheme.INK_SOFT)
			if economy.is_maxed(id):
				button.text = "Fertig ✓"
				button.disabled = true
			else:
				button.text = Economy.format_short(economy.cost(id))
				button.disabled = not economy.can_buy(id)


# ---------------------------------------------------------------- Kosmetik

func _build_cosmetics_page(parent: Control) -> Control:
	var scroll := _page(parent)
	var list := _list_box(scroll)
	var intro := Label.new()
	intro.text = "Einmal gekauft, gehört es dir – auch im nächsten Auftrag. Klick auf ein Feld: kaufen bzw. anlegen."
	UiTheme.style_label(intro, 16, UiTheme.INK_SOFT, false)
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	list.add_child(intro)
	for slot: Dictionary in Balancing.cosmetics.get("slots", []):
		var card := PanelContainer.new()
		card.add_theme_stylebox_override("panel", UiTheme.box(UiTheme.PAPER_DIM, Color(0, 0, 0, 0), 18, 0, 0, 12))
		list.add_child(card)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 14)
		card.add_child(row)
		var name_label := Label.new()
		name_label.text = String(slot["name"])
		name_label.custom_minimum_size = Vector2(170, 0)
		UiTheme.style_label(name_label, 19, UiTheme.INK)
		row.add_child(name_label)
		var flow := HFlowContainer.new()
		flow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		flow.add_theme_constant_override("h_separation", 10)
		flow.add_theme_constant_override("v_separation", 8)
		row.add_child(flow)
		for it: Dictionary in Economy.cosmetic_items(String(slot["id"])):
			_add_swatch(flow, it)
	return scroll


func _add_swatch(flow: HFlowContainer, it: Dictionary) -> void:
	var id := String(it["id"])
	var cell := VBoxContainer.new()
	cell.add_theme_constant_override("separation", 2)
	flow.add_child(cell)
	var b := Button.new()
	var has_color := it.has("color") or STANDARD_PREVIEW.has(String(it["slot"]))
	var color := Color.html(String(it.get("color", STANDARD_PREVIEW.get(String(it["slot"]), "#ffffff"))))
	b.custom_minimum_size = Vector2(62, 44) if has_color else Vector2(112, 44)
	b.tooltip_text = "%s – %s" % [it["name"], "gratis" if float(it.get("cost", 0)) <= 0.0 else Economy.format_money(float(it["cost"]))]
	if not has_color:
		b.text = String(it["name"])
	b.pressed.connect(func() -> void: wear_requested.emit(id))
	cell.add_child(b)
	var price := Label.new()
	price.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UiTheme.style_label(price, 12, UiTheme.INK_SOFT, false)
	cell.add_child(price)
	_swatches[id] = { "button": b, "price": price, "color": color, "plain": not has_color, "name": String(it["name"]) }


func _refresh_swatches() -> void:
	for id: String in _swatches:
		var sw: Dictionary = _swatches[id]
		var def := Economy.cosmetic_def(id)
		var b: Button = sw["button"]
		var slot := String(def["slot"])
		var current := String(own_look.call(slot)) if own_look.is_valid() else economy.look(slot)
		var worn := current == id or (current == "" and float(def.get("cost", 0)) <= 0.0)
		var owned := economy.owns_cosmetic(id)
		var price: Label = sw["price"]
		if worn:
			price.text = "angelegt"
		elif owned:
			price.text = String(sw["name"])
		else:
			price.text = Economy.format_short(float(def.get("cost", 0)))
		b.disabled = not owned and economy.state.money < float(def.get("cost", 0)) - 1e-6
		var c: Color = sw["color"]
		if bool(sw["plain"]):
			UiTheme.style_button(b, UiTheme.PURPLE if worn else UiTheme.PAPER, UiTheme.PURPLE.darkened(0.3) if worn else UiTheme.GREY,
				Color.WHITE if worn else UiTheme.INK, 15)
		else:
			var dark := c.darkened(0.3)
			UiTheme.style_button(b, c, UiTheme.INK if worn else dark, UiTheme.INK if c.get_luminance() > 0.55 else Color.WHITE, 18)
			b.text = "✓" if worn else ("" if owned else "€")
			if worn:
				for k in ["normal", "hover", "pressed"]:
					var sb := b.get_theme_stylebox(k) as StyleBoxFlat
					sb.set_border_width_all(4)
					sb.border_width_bottom = 6


# ---------------------------------------------------------------- Auftrag

func _build_job_page(parent: Control) -> Control:
	var scroll := _page(parent)
	var list := _list_box(scroll)
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", UiTheme.box(UiTheme.PURPLE, UiTheme.PURPLE.darkened(0.3), 20, 0, 0, 16))
	list.add_child(card)
	var inner := VBoxContainer.new()
	card.add_child(inner)
	_job_title = Label.new()
	UiTheme.style_label(_job_title, 24, Color.WHITE)
	inner.add_child(_job_title)
	_job_info = Label.new()
	UiTheme.style_label(_job_info, 16, Color(1, 1, 1, 0.92), false)
	_job_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	inner.add_child(_job_info)

	var explain := Label.new()
	explain.text = "Nach dem Finale kannst du einen neuen Auftrag annehmen: Die Chefs starten C.O.R.D. aus einer Sicherung neu, " \
		+ "die Stadt füllt sich wieder mit Kabeln, Geld, Werkzeuge, Ausbau und Ports gehen zurück auf Anfang. " \
		+ "Dafür bekommst du Ruf – je mehr du in diesem Auftrag verdient hast, desto mehr. Ruf und Kosmetik bleiben dir."
	UiTheme.style_label(explain, 15, UiTheme.INK_SOFT, false)
	explain.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	list.add_child(explain)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	list.add_child(row)
	_job_gain = Label.new()
	UiTheme.style_label(_job_gain, 17, UiTheme.INK)
	_job_gain.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_job_gain.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	row.add_child(_job_gain)
	_job_button = Button.new()
	_job_button.custom_minimum_size = Vector2(260, 54)
	_job_button.pressed.connect(_on_new_job_pressed)
	row.add_child(_job_button)

	var head := Label.new()
	head.text = "Wichtige Kabel je Viertel"
	UiTheme.style_label(head, 19, UiTheme.INK)
	list.add_child(head)
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 6)
	list.add_child(grid)
	for sec in RackPlan.sections():
		var name_label := Label.new()
		name_label.text = String(sec["name"])
		name_label.custom_minimum_size = Vector2(250, 0)
		UiTheme.style_label(name_label, 15, UiTheme.INK, false)
		grid.add_child(name_label)
		var bar := ProgressBar.new()
		bar.custom_minimum_size = Vector2(380, 18)
		bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		bar.show_percentage = false
		bar.max_value = float(sec["count"])
		bar.add_theme_stylebox_override("background", UiTheme.box(UiTheme.PAPER_DIM.darkened(0.08), Color(0, 0, 0, 0), 9, 0, 0, 0))
		bar.add_theme_stylebox_override("fill", UiTheme.box(UiTheme.GREEN, Color(0, 0, 0, 0), 9, 0, 0, 0))
		grid.add_child(bar)
		var count := Label.new()
		UiTheme.style_label(count, 15, UiTheme.INK_SOFT)
		grid.add_child(count)
		_bars[String(sec["id"])] = [bar, count, sec]

	_new_game = Button.new()
	_new_game.custom_minimum_size = Vector2(0, 42)
	_new_game.size_flags_horizontal = Control.SIZE_SHRINK_END
	UiTheme.style_button(_new_game, UiTheme.PAPER_DIM, UiTheme.GREY, UiTheme.RED, 15)
	_new_game.pressed.connect(_on_new_game_pressed)
	list.add_child(_new_game)
	return scroll


func _refresh_job() -> void:
	var st := economy.state
	var pr: Dictionary = Balancing.prestige
	_job_title.text = "Auftrag Nr. %d   ·   Ruf %d" % [st.prestige_count + 1, st.reputation]
	if st.reputation > 0 or st.prestige_count > 0:
		_job_info.text = "Ruf wirkt dauerhaft: +%d %% Geld, +%d %% schneller ziehen. C.O.R.D. bestellt in diesem Auftrag %s-mal so viel und fragt öfter." % [
			roundi(float(pr.get("money_per_point", 0.1)) * st.reputation * 100.0),
			roundi(float(pr.get("speed_per_point", 0.05)) * st.reputation * 100.0),
			("%.2f" % pow(float(pr.get("cord_order_growth", 1.15)), st.prestige_count)).replace(".", ",")]
	else:
		_job_info.text = "Dein erster Auftrag. Ruf gibt es, wenn du nach dem Finale einen neuen Auftrag annimmst."
	var gain := economy.reputation_gain()
	_job_gain.text = "In diesem Auftrag verdient: %s  →  +%d Ruf" % [Economy.format_short(st.total_earned), gain]
	if host_only_locked:
		UiTheme.style_button(_job_button, UiTheme.PURPLE, UiTheme.PURPLE.darkened(0.3), Color.WHITE, 16)
		_job_button.disabled = true
		_job_button.text = "Nur der Host kann neu anfangen"
	elif economy.can_prestige():
		UiTheme.style_button(_job_button, UiTheme.PURPLE, UiTheme.PURPLE.darkened(0.3), Color.WHITE, 18)
		_job_button.disabled = false
		_job_button.text = "Wirklich neu anfangen?" if _confirm_job else "Neuer Auftrag (+%d Ruf)" % gain
	else:
		UiTheme.style_button(_job_button, UiTheme.PURPLE, UiTheme.PURPLE.darkened(0.3), Color.WHITE, 16)
		_job_button.disabled = true
		_job_button.text = "Erst C.O.R.D.s Kern abschalten" if not st.finale_done else "Noch kein Ruf verdient"
	for id: String in _bars:
		var e: Array = _bars[id]
		var sec: Dictionary = e[2]
		var n := RackPlan.section_plugged(st, String(sec["id"]))
		(e[0] as ProgressBar).value = n
		(e[1] as Label).text = "%d / %d" % [n, int(sec["count"])]
	_new_game.text = "Wirklich alles löschen (auch Ruf und Kosmetik)?" if _confirm else "Neues Spiel"
	_new_game.visible = not host_only_locked


func _on_new_job_pressed() -> void:
	if not _confirm_job:
		_confirm_job = true
		refresh()
		return
	new_job_requested.emit()


## Zweimal klicken, damit niemand aus Versehen alles löscht
func _on_new_game_pressed() -> void:
	if not _confirm:
		_confirm = true
		refresh()
		return
	new_game_requested.emit()


# ---------------------------------------------------------------- Allgemein

func refresh() -> void:
	if economy == null:
		return
	_money.text = Economy.format_money(economy.state.money)
	match _tab:
		0, 1:
			_refresh_rows()
		2:
			_refresh_swatches()
		3:
			_refresh_job()
	_services.text = "Dienste online: %d / %d   ·   Ports belegt: %d / %d   ·   Tasche: %d Knäuel" % [
		rack.active_services(), RackPlan.total_services(), rack.active_count(), RackPlan.total_ports(), economy.bag_capacity()]
	_effects.text = _effects_text()
	_effects.visible = _effects.text != ""
	_recall.visible = economy.state.level("drone") > 0
	_snooze.visible = RackPlan.has_special(economy.state, "cord_snooze")
	var wait := economy.state.snooze_cooldown
	_snooze.disabled = wait > 0.0
	_snooze.text = "C.O.R.D. abschalten (5 Min. Ruhe)" if wait <= 0.0 else "Abschaltknopf lädt … %d:%02d" % [int(wait / 60.0), int(wait) % 60]
	if not visible:
		_confirm = false
		_confirm_job = false


## Kurze Liste, was die laufenden Dienste (und Ausbau, Ruf) gerade bewirken
func _effects_text() -> String:
	var names := { "money": "Geld", "press": "Handzug", "motor": "Motoren", "walk": "Lauftempo",
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
	return "" if parts.is_empty() else "Wirkung: " + "  ·  ".join(parts)


func _process(_delta: float) -> void:
	# Wartezeit des Abschaltknopfs läuft sichtbar herunter
	if visible and _snooze and _snooze.visible and _snooze.disabled:
		refresh()


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("tablet") or (event is InputEventKey and event.pressed and event.physical_keycode == KEY_ESCAPE):
		get_viewport().set_input_as_handled()
		closed.emit()
