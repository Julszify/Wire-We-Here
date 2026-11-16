class_name IntroScene
extends Node3D
## Intro beim neuen Spiel: Stammtisch im „Goldenen Router“ (die drei Chefs bauen C.O.R.D. per Bierdeckel-Prompt),
## „Drei Monate später“ über der Stadt voller Kabelberge, dann der Anruf beim Admin im Hinterhof.
## Eigene Kamera, Untertitel, schwarze Balken; Leertaste, Enter oder Esc überspringen.
## Die Kneipe ist ein kleines Set unter der Karte (PUB_ORIGIN), damit sie die Stadt nicht stört.

signal finished

const PUB_ORIGIN := Vector3(0, -300, 0)
const SPEAKER_COLORS := {
	"Der Großspurige": Color(0.55, 0.7, 1.0),
	"Der Ja-Sager": Color(1.0, 0.85, 0.35),
	"Der Zahlenmensch": Color(0.5, 0.95, 0.55),
	"C.O.R.D.": Color(0.4, 0.95, 1.0),
	"Du": Color(1.0, 0.6, 0.85),
}

var player: Player
var _cam: Camera3D
var _chefs: Dictionary = {}       # id -> ChefView
var _cord: CordView
var _shots: Array[Dictionary] = []
var _shot := -1
var _shot_t := 0.0
var _ui: CanvasLayer
var _fade: ColorRect
var _speaker: Label
var _line: Label
var _title: Label
var _done := false


func start(p: Player) -> void:
	player = p
	_build_pub()
	_build_ui()
	_cam = Camera3D.new()
	_cam.fov = 55.0
	add_child(_cam)
	ToonLook.add_outline(_cam)
	_cam.make_current()
	_define_shots()
	_next_shot()


## Nur für Tests: direkt zu Einstellung `n` springen
func jump_to(n: int) -> void:
	_shot = n - 1
	_next_shot()
	# alle vorherigen Aktionen nachholen (z. B. C.O.R.D. erscheint)
	for k in n:
		if _shots[k].has("call") and k != n:
			(_shots[k]["call"] as Callable).call()


func _unhandled_input(event: InputEvent) -> void:
	if _done:
		return
	if event.is_action_pressed("ui_cancel") or event.is_action_pressed("jump") or event.is_action_pressed("ui_accept"):
		get_viewport().set_input_as_handled()
		_finish()


func _process(delta: float) -> void:
	if _done or _shot < 0:
		return
	var s: Dictionary = _shots[_shot]
	_shot_t += delta
	var dur := float(s["dur"])
	var k := clampf(_shot_t / dur, 0.0, 1.0)
	var e := k * k * (3.0 - 2.0 * k)
	var from: Array = s["from"]
	var to: Array = s.get("to", from)
	var pos := (from[0] as Vector3).lerp(to[0], e)
	var look := (from[1] as Vector3).lerp(to[1], e)
	_cam.global_position = pos
	if not pos.is_equal_approx(look):
		_cam.look_at(look, Vector3.UP)
	# Ein- und Ausblenden am Anfang und Ende einer Einstellung mit „fade“
	var fade := 0.0
	if bool(s.get("fade_in", false)):
		fade = maxf(fade, 1.0 - clampf(_shot_t / 0.6, 0.0, 1.0))
	if bool(s.get("fade_out", false)):
		fade = maxf(fade, clampf((_shot_t - dur + 0.6) / 0.6, 0.0, 1.0))
	if bool(s.get("black", false)):
		fade = 1.0
	_fade.color.a = fade
	if _shot_t >= dur:
		_next_shot()


func _next_shot() -> void:
	if _shot >= 0:
		var old: Dictionary = _shots[_shot]
		if old.has("speaker") and _chefs.has(String(old.get("chef", ""))):
			(_chefs[old["chef"]] as ChefView).talking = false
	_shot += 1
	_shot_t = 0.0
	if _shot >= _shots.size():
		_finish()
		return
	var s: Dictionary = _shots[_shot]
	var speaker := String(s.get("speaker", ""))
	_speaker.text = speaker
	var col: Color = SPEAKER_COLORS.get(speaker, Color.WHITE)
	if speaker.begins_with("Der Großspurige"):
		col = SPEAKER_COLORS["Der Großspurige"]
	_speaker.add_theme_color_override("font_color", col)
	_line.text = String(s.get("text", "")) if speaker != "" else ""
	_title.text = String(s.get("text", "")) if speaker == "" else ""
	_line.get_parent().visible = speaker != ""
	if _chefs.has(String(s.get("chef", ""))):
		(_chefs[s["chef"]] as ChefView).talking = true
	if s.has("call"):
		(s["call"] as Callable).call()


func _finish() -> void:
	if _done:
		return
	_done = true
	if player:
		player.set_phone(false)
		player.camera.make_current()
	_ui.queue_free()
	finished.emit()
	queue_free()


# ---------------------------------------------------------------- Ablauf

func _define_shots() -> void:
	var p := PUB_ORIGIN
	var table := p + Vector3(0, 1.1, -0.3)
	var g := p + Vector3(-0.85, 1.45, -1.35)  # Köpfe der Chefs (ungefähr)
	var j := p + Vector3(0.0, 1.4, -1.5)
	var z := p + Vector3(0.85, 1.35, -1.35)
	var yard_player := player.global_position + Vector3(0, 1.45, 0)
	var face := player.facing()
	var side := face.cross(Vector3.UP)
	var phone_cam := player.global_position + face * 2.2 + side * 0.9 + Vector3(0, 1.7, 0)
	_shots = [
		{ "dur": 4.5, "fade_in": true, "text": "Zum Goldenen Router\nDonnerstagabend, drittes Bier",
			"from": [p + Vector3(0, 2.6, 5.2), table], "to": [p + Vector3(0, 2.1, 3.6), table] },
		{ "dur": 4.6, "speaker": "Der Großspurige", "chef": "grossspurig",
			"text": "Wozu brauchen wir eigentlich noch eine IT-Abteilung? Das kann doch die KI!",
			"from": [g + Vector3(0.7, 0.35, 2.8), g], "to": [g + Vector3(0.5, 0.3, 2.3), g] },
		{ "dur": 3.0, "speaker": "Der Ja-Sager", "chef": "jasager", "text": "Genau! Das kann doch die KI.",
			"from": [j + Vector3(0.2, 0.3, 2.4), j], "call": func() -> void: (_chefs["grossspurig"] as ChefView).laugh() },
		{ "dur": 3.6, "speaker": "Der Zahlenmensch", "chef": "zahlen", "text": "Und eine KI will kein Gehalt. Kein Urlaub. Kein Weihnachtsgeld.",
			"from": [z + Vector3(-0.6, 0.3, 2.5), z], "to": [z + Vector3(-0.4, 0.3, 2.1), z] },
		{ "dur": 3.4, "speaker": "Der Großspurige", "chef": "grossspurig", "text": "Ich bau sie uns gleich hier. Vibe Coding! Hat wer einen Stift?",
			"from": [p + Vector3(-0.2, 2.0, 2.4), table], "to": [p + Vector3(0.2, 1.9, 2.0), table] },
		{ "dur": 4.5, "speaker": "Der Großspurige", "chef": "grossspurig", "text": "„Kümmer dich um die Kabel. Wenn was kaputt ist, bestell neu.“ … Fertig.",
			"from": [table + Vector3(0.05, 0.7, 0.45), table + Vector3(0.05, 0.0, 0.15)],
			"to": [table + Vector3(0.05, 0.45, 0.35), table + Vector3(0.05, 0.0, 0.15)] },
		{ "dur": 4.6, "speaker": "C.O.R.D.", "text": "C.O.R.D. online. Defektes Kabel erkannt. Ersatz bestellt. Alles im grünen Bereich.",
			"from": [table + Vector3(0.6, 0.5, 1.5), table + Vector3(-0.2, 0.4, 0)], "call": _cord_appears },
		{ "dur": 2.4, "speaker": "Alle drei", "text": "Prost!", "fade_out": true,
			"from": [p + Vector3(0, 2.4, 3.8), table], "call": _all_laugh },
		{ "dur": 2.6, "black": true, "text": "Drei Monate später.", "from": [p + Vector3(0, 2.4, 3.8), table] },
		{ "dur": 6.5, "fade_in": true, "text": "C.O.R.D. bestellt und bestellt. Eingesteckt wird nie etwas.\nDie Cloud ist ausgefallen – weltweit.",
			"from": [Vector3(40, 60, 40), Vector3(-60, 0, -115)], "to": [Vector3(-20, 22, -50), Vector3(-60, 6, -115)] },
		{ "dur": 5.2, "speaker": "Der Großspurige (am Telefon)", "text": "Hallo? Sie waren doch mal unsere IT … Können Sie das mal eben reparieren?",
			"from": [phone_cam + Vector3(0, 0.3, 0.8), yard_player], "to": [phone_cam, yard_player],
			"call": func() -> void: player.set_phone(true) },
		{ "dur": 2.6, "speaker": "Du", "text": "Knot my problem.", "from": [phone_cam, yard_player] },
		{ "dur": 2.8, "speaker": "Der Großspurige (am Telefon)", "text": "Wir zahlen pro Meter!", "from": [phone_cam, yard_player] },
		{ "dur": 2.4, "speaker": "Du", "text": "… Na gut.", "fade_out": true, "from": [phone_cam, yard_player],
			"to": [player.camera.global_position, yard_player] },
	]


func _cord_appears() -> void:
	_cord.visible = true
	_cord.scale = Vector3.ONE * 0.01
	var tw := create_tween()
	tw.tween_property(_cord, "scale", Vector3.ONE * 0.6, 0.5).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_cord.set_asking(true, "")


func _all_laugh() -> void:
	_cord.set_asking(false)
	for c: ChefView in _chefs.values():
		c.laugh()


# ---------------------------------------------------------------- Kneipe

func _build_pub() -> void:
	var p := PUB_ORIGIN
	var wood := _mat(Color(0.42, 0.26, 0.15))
	var dark_wood := _mat(Color(0.28, 0.17, 0.1))
	var wall := _mat(Color(0.62, 0.45, 0.3))
	# Raum: Kiste mit nach innen gedrehten Flächen
	var room := MeshInstance3D.new()
	var rb := BoxMesh.new()
	rb.size = Vector3(10, 4, 9)
	rb.flip_faces = true
	room.mesh = rb
	room.material_override = wall
	room.position = p + Vector3(0, 2, 0)
	add_child(room)
	_box(p + Vector3(0, 0.02, 0), Vector3(9.9, 0.04, 8.9), _mat(Color(0.3, 0.2, 0.14)))  # Dielen
	# Theke mit Flaschen
	_box(p + Vector3(0, 0.55, -3.6), Vector3(6.0, 1.1, 0.8), dark_wood)
	_box(p + Vector3(0, 1.13, -3.6), Vector3(6.2, 0.06, 1.0), wood)
	_box(p + Vector3(0, 2.0, -4.35), Vector3(6.0, 0.06, 0.3), wood)
	for k in 14:
		var bottle := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.035
		cm.bottom_radius = 0.06
		cm.height = 0.32
		bottle.mesh = cm
		var hue := float(k) / 14.0
		bottle.material_override = _mat(Color.from_hsv(hue, 0.6, 0.7))
		bottle.position = p + Vector3(-2.6 + k * 0.4, 2.2, -4.35)
		add_child(bottle)
	# Leuchtschild über der Theke
	var sign := Label3D.new()
	sign.text = "Zum Goldenen Router"
	sign.font_size = 96
	sign.outline_size = 16
	sign.pixel_size = 0.006
	sign.modulate = Color(1.0, 0.82, 0.3)
	sign.outline_modulate = Color(0.4, 0.15, 0.0)
	sign.position = p + Vector3(0, 3.1, -4.45)
	add_child(sign)
	# Stehtisch mit drei Bieren und dem Bierdeckel
	var top := p + Vector3(0, 1.1, -0.3)
	_cyl(top - Vector3(0, 0.55, 0), 0.06, 1.1, dark_wood)
	_cyl(top, 0.75, 0.06, wood)
	for k in 3:
		var at := top + Vector3(-0.45 + k * 0.45, 0.14, -0.3)
		if not _prop("bierkrug", 0.2, at - Vector3(0, 0.11, 0), 0.4 + k * 1.3):
			_cyl(at, 0.06, 0.22, _mat(Color(0.95, 0.65, 0.15, 1.0)))
			_cyl(at + Vector3(0, 0.12, 0), 0.062, 0.04, _mat(Color(0.98, 0.97, 0.92)))
	# Ausstattung aus Tripo3D (fehlt eine Datei, bleibt die Stelle leer)
	_prop("zapfanlage", 0.6, p + Vector3(0.4, 1.16, -3.6), 0.0)
	_prop("zapfhahn", 0.4, p + Vector3(-1.6, 1.16, -3.6), 0.0)
	_prop("bierkrug", 0.2, p + Vector3(1.6, 1.16, -3.5), 2.0)
	for k in 4:
		_prop("barhocker", 0.78, p + Vector3(-2.2 + k * 1.45, 0.0, -2.75), k * 0.7)
	_prop("jukebox", 1.5, p + Vector3(4.3, 0.0, -2.6), -PI * 0.5)
	_prop("garderobe", 1.8, p + Vector3(-4.3, 0.0, -3.4), PI * 0.25)
	_prop("dartscheibe", 0.55, p + Vector3(-4.9, 1.45, 0.6), PI * 0.5)
	_coaster(top + Vector3(0.05, 0.035, 0.15), 0.2)
	# Die drei Chefs hinter dem Tisch, Blick zur Kamera
	var ids := ["grossspurig", "jasager", "zahlen"]
	for k in 3:
		var chef := ChefView.new()
		add_child(chef)
		chef.setup(ids[k])
		chef.position = p + Vector3(-0.85 + k * 0.85, 0, -1.4 - (0.1 if k == 1 else 0.0))
		chef.rotation.y = (0.25 if k == 0 else (-0.25 if k == 2 else 0.0))
		_chefs[ids[k]] = chef
	# C.O.R.D. erscheint auf dem Tisch
	_cord = CordView.new()
	add_child(_cord)
	_cord.position = top + Vector3(-0.2, 0.45, 0.05)
	_cord.rotation.y = PI
	_cord.visible = false
	# Warmes Licht
	for at in [Vector3(0, 3.3, 0.5), Vector3(-3, 3.0, -3), Vector3(3, 3.0, 2)]:
		var light := OmniLight3D.new()
		light.light_color = Color(1.0, 0.78, 0.5)
		light.light_energy = 2.2
		light.omni_range = 9.0
		light.position = p + at
		add_child(light)


func _build_ui() -> void:
	_ui = CanvasLayer.new()
	_ui.layer = 20
	add_child(_ui)
	for top in [true, false]:
		var bar := ColorRect.new()
		bar.color = Color.BLACK
		bar.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE if top else Control.PRESET_BOTTOM_WIDE)
		if top:
			bar.offset_bottom = 70
		else:
			bar.offset_top = -70
		_ui.add_child(bar)
	_fade = ColorRect.new()
	_fade.color = Color(0, 0, 0, 1)
	_fade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.add_child(_fade)
	_title = Label.new()
	_title.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_title.add_theme_font_size_override("font_size", 38)
	_title.add_theme_constant_override("outline_size", 10)
	_title.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	_ui.add_child(_title)
	var panel := VBoxContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	panel.offset_top = -190
	panel.offset_bottom = -85
	panel.offset_left = 140
	panel.offset_right = -140
	_ui.add_child(panel)
	_speaker = Label.new()
	_speaker.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_speaker.add_theme_font_size_override("font_size", 22)
	_speaker.add_theme_constant_override("outline_size", 8)
	_speaker.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	panel.add_child(_speaker)
	_line = Label.new()
	_line.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_line.add_theme_font_size_override("font_size", 28)
	_line.add_theme_constant_override("outline_size", 10)
	_line.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	panel.add_child(_line)
	var skip := Label.new()
	skip.text = "Leertaste oder Esc: überspringen"
	skip.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	skip.offset_left = -330
	skip.offset_top = -52
	skip.offset_right = -20
	skip.offset_bottom = -20
	skip.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	skip.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	_ui.add_child(skip)


## Tripo-Modell aus assets/models/props/pub/tripo/ auf `height` skalieren und mit der Unterkante auf `base`
## stellen (Blick +Z, um `turn` gedreht). false, wenn die Datei fehlt.
func _prop(file: String, height: float, base: Vector3, turn: float) -> bool:
	var path := "res://assets/models/props/pub/tripo/%s.glb" % file
	if not ResourceLoader.exists(path):
		return false
	var model := (load(path) as PackedScene).instantiate() as Node3D
	add_child(model)
	var box := ChefView._world_aabb(model)
	var k := height / maxf(box.size.y, 0.001)
	model.scale = Vector3.ONE * k
	model.rotation.y = turn
	box = ChefView._world_aabb(model)
	model.global_position += base - Vector3(box.get_center().x, box.position.y, box.get_center().z)
	return true


func _box(center: Vector3, size: Vector3, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = size
	mi.mesh = b
	mi.material_override = mat
	mi.position = center
	add_child(mi)


## Bierdeckel mit dem Prompt: Pappscheibe, obenauf das Midjourney-Bild (assets/textures/story/bierdeckel.png,
## quadratisch auf die Scheibe zugeschnitten); fehlt es, bleibt die Scheibe leer.
func _coaster(center: Vector3, r: float) -> void:
	_cyl(center, r, 0.01, _mat(Color(0.86, 0.74, 0.56)))
	var path := "res://assets/textures/story/bierdeckel.png"
	if not ResourceLoader.exists(path):
		return
	var shader := Shader.new()
	shader.code = """
shader_type spatial;
render_mode unshaded;  // beleuchtet würde das Bild im warmen Kneipenlicht überstrahlen
uniform sampler2D tex : source_color, filter_linear_mipmap;
void fragment() {
	if (distance(UV, vec2(0.5)) > 0.49) { discard; }
	ALBEDO = texture(tex, UV).rgb * vec3(0.95, 0.88, 0.78);
}
"""
	var mat := ShaderMaterial.new()
	mat.shader = shader
	mat.set_shader_parameter("tex", load(path))
	var quad := QuadMesh.new()
	quad.size = Vector2(r * 2.0, r * 2.0)
	var mi := MeshInstance3D.new()
	mi.mesh = quad
	mi.material_override = mat
	mi.rotation = Vector3(-PI * 0.5, 0, 0)  # flach, Oberkante des Bildes zu den Chefs
	mi.position = center + Vector3(0, 0.0055, 0)
	add_child(mi)


func _cyl(center: Vector3, r: float, h: float, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	var c := CylinderMesh.new()
	c.top_radius = r
	c.bottom_radius = r
	c.height = h
	mi.mesh = c
	mi.material_override = mat
	mi.position = center
	add_child(mi)


static func _mat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.7
	return m
