class_name MainMenu
extends Node3D
## Startmenü: im Hintergrund drei Kabelhaufen, Bäume und C.O.R.D. bei langsamer Kamerafahrt, davor Logo und Knöpfe.
## Weiterspielen / Neues Spiel / Mehrspieler (hosten, beitreten) / Einstellungen / Beenden.

const WORLD_SCENE := "res://scenes/world.tscn"
const CENTER := Vector3(0, 0, 0)

var _camera: Camera3D
var _cord: CordView
var _t := 0.0
var _ui: CanvasLayer
var _new_button: Button
var _continue_button: Button
var _confirm_new := false
var _settings_panel: PanelContainer
var _mp_panel: PanelContainer
var _mp_status: Label
var _loading: Label


func _ready() -> void:
	_build_backdrop()
	_build_ui()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if Net.status_changed.is_connected(_on_net_status) == false:
		Net.status_changed.connect(_on_net_status)
	# Test: automatisch beitreten (--autojoin=<Adresse>)
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--runfor="):
			get_tree().create_timer(float(arg.get_slice("=", 1)) + 90.0, true, false, true).timeout.connect(get_tree().quit)
		if arg.begins_with("--autojoin="):
			Settings.last_address = arg.get_slice("=", 1)
			Net.join(Settings.last_address, Settings.port)
	# Zurück aus einer Mehrspieler-Runde: Grund anzeigen
	if Net.last_message != "":
		_show_mp(true)
		_mp_status.text = Net.last_message
		Net.last_message = ""


# ---------------------------------------------------------------- Hintergrund

func _build_backdrop() -> void:
	var env := WorldEnvironment.new()
	env.environment = CityLook.environment()
	add_child(env)
	var sun := DirectionalLight3D.new()
	add_child(sun)
	CityLook.setup_sun(sun)
	_camera = Camera3D.new()
	_camera.fov = 55.0
	add_child(_camera)
	ToonLook.install(self, _camera)

	# Boden: Pflaster in der Mitte, Gras außen
	_ground(Vector2(140, 140), "res://assets/textures/terrain/gras_alb.png", 0.0, 24.0)
	_ground(Vector2(34, 34), "res://assets/textures/terrain/platten_alb.png", 0.02, 6.0)
	# Drei Haufen, wie im Hinterhof
	var id := 0
	for h: Array in [[Vector3(0, 0, 0), 230, 5.0], [Vector3(-9, 0, 6), 90, 3.2], [Vector3(8, 0, -5), 110, 3.6]]:
		var heap := HeapData.new(id, 7000 + id * 31, h[0], int(h[1]), float(h[2]))
		for c in heap.create_cables(id * 1000):
			var v := CableView.new()
			add_child(v)
			v.setup(c)
		id += 1
	# Bäume und Ausstattung rundherum
	var items: Array = []
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	for i in 26:
		var a := rng.randf() * TAU
		var r := rng.randf_range(19.0, 30.0)
		var model: String = ["TreeRound", "TreeRound", "TreeAutumn", "TreePine", "Bush"][rng.randi_range(0, 4)]
		items.append([model, Vector3(cos(a) * r, 0, sin(a) * r), rng.randf_range(0, 360), rng.randf_range(0.85, 1.25)])
	items.append(["Lamp", Vector3(3.5, 0, 7.0), 200.0, 1.0])
	items.append(["Bench", Vector3(5.5, 0, 6.0), 160.0, 1.0])
	items.append(["CableDrum", Vector3(-5, 0, -9), 30.0, 1.0])
	items.append(["PalletStack", Vector3(-7, 0, -8), 10.0, 1.0])
	YardProps.add_items(self, null, items)
	_cord = CordView.new()
	add_child(_cord)
	_cord.position = Vector3(2.5, 3.2, 3.0)


func _ground(size: Vector2, tex_path: String, y: float, tiles: float) -> void:
	var mi := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = size
	mi.mesh = plane
	var m := StandardMaterial3D.new()
	if ResourceLoader.exists(tex_path):
		m.albedo_texture = load(tex_path)
		m.uv1_scale = Vector3(tiles, tiles, 1)
	else:
		m.albedo_color = Color(0.45, 0.7, 0.35)
	m.roughness = 0.9
	mi.material_override = m
	mi.position.y = y
	add_child(mi)


func _process(delta: float) -> void:
	_t += delta
	# Langsame Kreisfahrt um den großen Haufen, leicht schwankende Höhe
	var a := _t * 0.06 + 0.6
	var r := 17.0
	_camera.position = CENTER + Vector3(cos(a) * r, 6.0 + sin(_t * 0.2) * 0.8, sin(a) * r)
	_camera.look_at(CENTER + Vector3(0, 1.6, 0), Vector3.UP)
	# C.O.R.D. schwebt in Achten über dem Haufen
	_cord.position = Vector3(sin(_t * 0.35) * 4.0, 3.4 + sin(_t * 1.3) * 0.25, sin(_t * 0.7) * 2.5)
	_cord.rotation.y = -_t * 0.35 + PI * 0.5


# ---------------------------------------------------------------- Bedienung

func _build_ui() -> void:
	_ui = CanvasLayer.new()
	add_child(_ui)
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.add_child(root)

	var left := VBoxContainer.new()
	left.position = Vector2(70, 70)
	left.add_theme_constant_override("separation", 14)
	root.add_child(left)
	# Logo: zwei Zeilen, dicke Kontur, leicht schräg
	var logo := VBoxContainer.new()
	logo.add_theme_constant_override("separation", -26)
	logo.rotation = deg_to_rad(-3.0)
	left.add_child(logo)
	for line: Array in [["Knot My", UiTheme.YELLOW], ["Problem", Color.WHITE]]:
		var l := Label.new()
		l.text = line[0]
		UiTheme.style_label(l, 92, line[1])
		l.add_theme_color_override("font_outline_color", UiTheme.BLUE_DARK)
		l.add_theme_constant_override("outline_size", 26)
		l.add_theme_color_override("font_shadow_color", Color(0.05, 0.08, 0.15, 0.45))
		l.add_theme_constant_override("shadow_offset_y", 8)
		logo.add_child(l)
	var sub := Label.new()
	sub.text = "Wire We Here?  ·  Die Cloud ist ausgefallen. Du bist die IT."
	UiTheme.style_hud_label(sub, 20)
	left.add_child(sub)
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 24)
	left.add_child(spacer)

	var has_save := SaveGame.exists()
	_continue_button = _menu_button(left, "Weiterspielen", UiTheme.GREEN, UiTheme.GREEN_DARK, _on_continue)
	_continue_button.visible = has_save
	if has_save:
		var when := _save_time()
		if when != "":
			_continue_button.tooltip_text = "Gespeichert: " + when
	_new_button = _menu_button(left, "Neues Spiel", UiTheme.BLUE, UiTheme.BLUE_DARK, _on_new_game)
	_menu_button(left, "Mehrspieler", UiTheme.PURPLE, UiTheme.PURPLE.darkened(0.3), func() -> void: _show_mp(not _mp_panel.visible))
	_menu_button(left, "Einstellungen", UiTheme.PAPER, UiTheme.GREY, func() -> void: _show_settings(not _settings_panel.visible),
		UiTheme.INK)
	_menu_button(left, "Beenden", UiTheme.RED, UiTheme.RED.darkened(0.3), func() -> void: get_tree().quit())

	_settings_panel = _build_settings(root)
	_mp_panel = _build_multiplayer(root)
	_settings_panel.visible = false
	_mp_panel.visible = false

	var version := Label.new()
	version.text = "Vertical Slice · Godot %s" % Engine.get_version_info()["string"]
	UiTheme.style_hud_label(version, 14)
	version.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	version.offset_left = -360
	version.offset_top = -40
	version.offset_right = -20
	version.offset_bottom = -14
	version.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	root.add_child(version)

	_loading = Label.new()
	_loading.text = "Die Stadt wird aufgebaut …"
	UiTheme.style_hud_label(_loading, 34)
	_loading.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_loading.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_loading.visible = false
	root.add_child(_loading)


func _menu_button(parent: Control, text: String, color: Color, dark: Color, cb: Callable, text_color := Color.WHITE) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(340, 60)
	b.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	UiTheme.style_button(b, color, dark, text_color, 24)
	b.pressed.connect(cb)
	parent.add_child(b)
	return b


func _panel(root: Control) -> PanelContainer:
	var p := PanelContainer.new()
	var style := UiTheme.box(UiTheme.PAPER, UiTheme.BLUE, 30, 8, 14, 24)
	style.border_width_bottom = 14
	p.add_theme_stylebox_override("panel", style)
	p.set_anchors_preset(Control.PRESET_CENTER_RIGHT)
	p.offset_left = -640
	p.offset_right = -70
	p.offset_top = -260
	p.custom_minimum_size = Vector2(570, 0)
	root.add_child(p)
	return p


func _title(box: VBoxContainer, text: String) -> void:
	var l := Label.new()
	l.text = text
	UiTheme.style_label(l, 28, UiTheme.BLUE_DARK)
	box.add_child(l)


func _row(box: VBoxContainer, text: String, control: Control) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	box.add_child(row)
	var l := Label.new()
	l.text = text
	l.custom_minimum_size = Vector2(200, 0)
	UiTheme.style_label(l, 18, UiTheme.INK)
	row.add_child(l)
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(control)


func _line_edit(text: String) -> LineEdit:
	var e := LineEdit.new()
	e.text = text
	e.custom_minimum_size = Vector2(0, 42)
	e.add_theme_font_override("font", UiTheme.font(false))
	e.add_theme_font_size_override("font_size", 18)
	e.add_theme_color_override("font_color", UiTheme.INK)
	var sb := UiTheme.box(UiTheme.PAPER_DIM, UiTheme.GREY, 12, 2, 0, 8)
	e.add_theme_stylebox_override("normal", sb)
	var focus := UiTheme.box(Color.WHITE, UiTheme.BLUE, 12, 3, 0, 8)
	e.add_theme_stylebox_override("focus", focus)
	return e


# ---------------------------------------------------------------- Einstellungen

func _build_settings(root: Control) -> PanelContainer:
	var p := _panel(root)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	p.add_child(box)
	_title(box, "Einstellungen")
	var mouse := HSlider.new()
	mouse.min_value = 0.25
	mouse.max_value = 3.0
	mouse.step = 0.05
	mouse.value = Settings.mouse_factor
	mouse.value_changed.connect(func(v: float) -> void: Settings.mouse_factor = v)
	_row(box, "Mausempfindlichkeit", mouse)
	var invert := CheckBox.new()
	invert.button_pressed = Settings.invert_y
	invert.toggled.connect(func(on: bool) -> void: Settings.invert_y = on)
	_row(box, "Maus umkehren", invert)
	var full := CheckBox.new()
	full.button_pressed = Settings.fullscreen
	full.toggled.connect(func(on: bool) -> void:
		Settings.fullscreen = on
		Settings.apply())
	_row(box, "Vollbild", full)
	var quality := OptionButton.new()
	for n in Settings.QUALITY_NAMES:
		quality.add_item(n)
	quality.selected = Settings.quality
	quality.add_theme_font_override("font", UiTheme.font())
	quality.item_selected.connect(func(i: int) -> void:
		Settings.quality = i
		Settings.apply())
	_row(box, "Grafik", quality)
	var vol := HSlider.new()
	vol.min_value = 0.0
	vol.max_value = 1.0
	vol.step = 0.05
	vol.value = Settings.volume
	vol.value_changed.connect(func(v: float) -> void:
		Settings.volume = v
		Settings.apply())
	_row(box, "Lautstärke", vol)
	var note := Label.new()
	note.text = "Grafik wirkt auf Schatten, Bildschärfe und Sichtweite (ab dem nächsten Laden der Stadt)."
	UiTheme.style_label(note, 14, UiTheme.INK_SOFT, false)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(note)
	var done := Button.new()
	done.text = "Fertig"
	done.custom_minimum_size = Vector2(160, 48)
	done.size_flags_horizontal = Control.SIZE_SHRINK_END
	UiTheme.style_button(done, UiTheme.GREEN, UiTheme.GREEN_DARK)
	done.pressed.connect(func() -> void: _show_settings(false))
	box.add_child(done)
	return p


func _show_settings(on: bool) -> void:
	_settings_panel.visible = on
	if on:
		_mp_panel.visible = false
	else:
		Settings.save_settings()


# ---------------------------------------------------------------- Mehrspieler

func _build_multiplayer(root: Control) -> PanelContainer:
	var p := _panel(root)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	p.add_child(box)
	_title(box, "Mehrspieler (bis 4)")
	var name_edit := _line_edit(Settings.player_name)
	name_edit.max_length = 20
	name_edit.text_changed.connect(func(t: String) -> void: Settings.player_name = t.strip_edges())
	_row(box, "Dein Name", name_edit)
	var host := Button.new()
	host.text = "Spiel hosten (Port %d)" % Settings.port
	host.custom_minimum_size = Vector2(0, 52)
	UiTheme.style_button(host, UiTheme.GREEN, UiTheme.GREEN_DARK)
	host.pressed.connect(_on_host)
	box.add_child(host)
	var info := Label.new()
	info.text = "Hosten startet deinen eigenen Spielstand; die anderen spielen darin mit. Fürs Internet muss der Port " \
		+ "am Router freigegeben sein (UDP)."
	UiTheme.style_label(info, 14, UiTheme.INK_SOFT, false)
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(info)
	var addr := _line_edit(Settings.last_address)
	addr.placeholder_text = "IP-Adresse des Hosts"
	addr.text_changed.connect(func(t: String) -> void: Settings.last_address = t.strip_edges())
	_row(box, "Adresse", addr)
	var join := Button.new()
	join.text = "Beitreten"
	join.custom_minimum_size = Vector2(0, 52)
	UiTheme.style_button(join, UiTheme.PURPLE, UiTheme.PURPLE.darkened(0.3))
	join.pressed.connect(_on_join)
	box.add_child(join)
	_mp_status = Label.new()
	UiTheme.style_label(_mp_status, 16, UiTheme.BLUE_DARK)
	_mp_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_mp_status)
	return p


func _show_mp(on: bool) -> void:
	_mp_panel.visible = on
	if on:
		_settings_panel.visible = false


func _on_host() -> void:
	Settings.save_settings()
	var err := Net.host(Settings.port)
	if err != OK:
		_mp_status.text = "Hosten fehlgeschlagen (Port %d belegt?)." % Settings.port
		return
	_start_world(false)


func _on_join() -> void:
	Settings.save_settings()
	var err := Net.join(Settings.last_address, Settings.port)
	if err != OK:
		_mp_status.text = "Adresse ungültig oder Verbindung nicht möglich."
		return
	_mp_status.text = "Verbinde mit %s …" % Settings.last_address


func _on_net_status(text: String) -> void:
	if _mp_status:
		_mp_status.text = text
	# Als Client verbunden und Welt-Daten erhalten: los
	if Net.is_client() and Net.ready_to_enter:
		_start_world(false)


# ---------------------------------------------------------------- Spiel starten

func _on_continue() -> void:
	Net.leave()
	_start_world(false)


func _on_new_game() -> void:
	if SaveGame.exists() and not _confirm_new:
		_confirm_new = true
		_new_button.text = "Wirklich? Alter Stand wird gelöscht"
		return
	Net.leave()
	SaveGame.delete()
	SaveGame.force_new = true
	_start_world(true)


func _start_world(_new: bool) -> void:
	_loading.visible = true
	Settings.save_settings()
	# Ein Bild warten, damit „wird aufgebaut“ zu sehen ist, dann die Stadt laden
	await get_tree().process_frame
	await get_tree().process_frame
	get_tree().change_scene_to_file(WORLD_SCENE)


static func _save_time() -> String:
	var d := SaveGame.read()
	return String(d.get("saved_at", "")).replace("T", " ").substr(0, 16)
