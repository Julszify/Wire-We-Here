class_name ServerRoomView
extends Node3D
## Begehbarer Serverraum im Hinterhof: eine Halle mit Tür, darin ein Schrank je Viertel.
## Jeder Port ist ein Lämpchen (rot = leer, grün = Knäuel steckt, hell = Dienst läuft); Reihen à 10 Ports.
## Maße aus balancing.json (server_room). Die Hülle kommt aus Blender (server_room.glb, gleiche Maße);
## fehlt die Datei, stehen graue Wände da. Kollision entsteht immer hier aus Kisten.

const MODEL_PATH := "res://assets/models/buildings/server_room.glb"
const LAMP_OFF := Color(0.1, 0.016, 0.016)
const LAMP_ON := Color(0.03, 0.55, 0.1)
const LAMP_SERVICE := Color(0.35, 1.0, 0.5)
const COLS := 10

var size := Vector3(20, 4.6, 12)
var _lamps: MultiMesh
var _port_xf: Array[Transform3D] = []    # Port -> Lage des Lämpchens (lokal)
var _rack_xf: Array[Transform3D] = []    # Schrank -> Lage (lokal, Vorderseite = +Z)
var _titles: Array[Label3D] = []
var _body: StaticBody3D
var _lights: Array[OmniLight3D] = []
## Serverraum-Ausbau (room_* in balancing.json): Teile je Stufe, neu gebaut, wenn sich Stufen ändern
var _extras: Node3D
var _extras_body: StaticBody3D
var _extras_key := ""
var _neon: Array[StandardMaterial3D] = []
var _neon_cycle := false
var _screen_label: Label3D
var _t := 0.0


func setup() -> void:
	var cfg: Dictionary = Balancing.server_room
	var s: Array = cfg.get("size", [20, 4.6, 12])
	size = Vector3(float(s[0]), float(s[1]), float(s[2]))
	_body = StaticBody3D.new()
	_body.name = "ServerRoomBody"
	add_child(_body)
	_build_shell(cfg)
	_build_racks(cfg)
	for x in [-size.x * 0.25, size.x * 0.25]:
		var light := OmniLight3D.new()
		light.position = Vector3(x, size.y - 0.8, 0.0)
		light.omni_range = 12.0
		light.light_energy = 1.6
		light.light_color = Color(0.8, 0.9, 1.0)
		add_child(light)
		_lights.append(light)


## Mitte des Raums am Boden (Szenen-Koordinaten)
static func center() -> Vector3:
	var c: Array = Balancing.server_room.get("center", [0, 0, 34])
	return Vector3(float(c[0]), float(c[1]), float(c[2]))


## Grundfläche in der Szene (x, z)
static func rect() -> Rect2:
	var c := center()
	var s: Array = Balancing.server_room.get("size", [20, 4.6, 12])
	return Rect2(c.x - float(s[0]) * 0.5, c.z - float(s[2]) * 0.5, float(s[0]), float(s[2]))


## Punkt vor der Tür (draußen), z. B. für Wegweiser und Tests
static func door_point() -> Vector3:
	var r := rect()
	return Vector3(r.get_center().x, center().y, r.position.y - 1.5)


## Zielpunkte der Schränke in der Szene (Mitte der Vorderseite)
func rack_points() -> Array[Vector3]:
	var out: Array[Vector3] = []
	var h := float(Balancing.server_room.get("rack_height_m", 2.7))
	for xf in _rack_xf:
		out.append(global_transform * (xf * Vector3(0, h * 0.5, 0.35)))
	return out


## Stelle vor dem Schrank eines Ports (für schwebenden Text)
func port_position(port: int) -> Vector3:
	if port < 0 or port >= _port_xf.size():
		return global_position + Vector3(0, 2, 0)
	return global_transform * (_port_xf[port].origin)


## Alle Lämpchen und Titel aus dem Zustand neu setzen
func refresh(state: GameState) -> void:
	var sections := RackPlan.sections()
	for i in sections.size():
		var sec: Dictionary = sections[i]
		var plugged := 0
		var services := 0
		var first := int(sec["first_port"])
		var service_on := {}
		for p in range(first, first + int(sec["count"])):
			var on := state.has_port(p)
			if on:
				plugged += 1
			var service := RackPlan.service_of(p)
			if not service_on.has(service):
				service_on[service] = RackPlan.service_active(state, service)
				if service_on[service]:
					services += 1
			_lamps.set_instance_color(p, LAMP_SERVICE if service_on[service] else (LAMP_ON if on else LAMP_OFF))
		_titles[i].text = "%s\n%d / %d Ports\n%d / %d Dienste" % [sec["name"], plugged, int(sec["count"]),
			services, int(sec["tutorial"]) + int(sec["rows"])]
		_titles[i].modulate = Color(0.6, 1.0, 0.7) if plugged > 0 else Color(0.8, 0.82, 0.86)
	_refresh_extras(state)


# ---------------------------------------------------------------- Ausbau

## Ausbau-Stufen aus dem Zustand übernehmen; baut die Teile nur neu, wenn sich eine Stufe geändert hat
func _refresh_extras(state: GameState) -> void:
	var lv := {}
	var key := ""
	for id in Balancing.room_order:
		lv[String(id)] = state.level(String(id))
		key += "%s=%d;" % [id, lv[String(id)]]
	if key != _extras_key:
		_extras_key = key
		if _extras:
			_extras.queue_free()
		_extras = Node3D.new()
		_extras.name = "Ausbau"
		add_child(_extras)
		_extras_body = StaticBody3D.new()
		_extras.add_child(_extras_body)
		_neon.clear()
		_screen_label = null
		_build_light(int(lv.get("room_light", 0)))
		_build_cooling(int(lv.get("room_cooling", 0)))
		_build_cable_trays(int(lv.get("room_cables", 0)))
		_build_monitors(int(lv.get("room_monitors", 0)))
		_build_coffee(int(lv.get("room_coffee", 0)))
	if _screen_label:
		_screen_label.text = "WOLKIG-LEITSTAND\nDienste online: %d / %d\nPorts belegt: %d / %d\nC.O.R.D.: %s" % [
			RackPlan.active_services(state), RackPlan.total_services(), state.active_ports.size(),
			RackPlan.total_ports(), "schläft" if state.finale_done else "bestellt fleißig"]


func _process(delta: float) -> void:
	# Höchste Lichtstufe: Leuchtleisten wechseln langsam die Farbe
	if _neon_cycle and not _neon.is_empty():
		_t += delta
		for i in _neon.size():
			var c := Color.from_hsv(fmod(_t * 0.06 + i * 0.13, 1.0), 0.75, 1.0)
			_neon[i].albedo_color = c
			_neon[i].emission = c


func _neon_mat(c: Color, energy := 2.4) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.emission_enabled = true
	m.emission = c
	m.emission_energy_multiplier = energy
	_neon.append(m)
	return m


func _part(center_pos: Vector3, box_size: Vector3, mat: Material, collide := false) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = box_size
	mi.mesh = box
	mi.material_override = mat
	mi.position = center_pos
	_extras.add_child(mi)
	if collide:
		var col := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = box_size
		col.shape = shape
		col.position = center_pos
		_extras_body.add_child(col)
	return mi


static func _flat(c: Color, rough := 0.6) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	return m


## Neonbeleuchtung: 1 Leisten unter der Decke, 2 Leuchtsockel an den Schränken, 3 Farbwechsel
func _build_light(level: int) -> void:
	var cool := Color(0.8, 0.9, 1.0)
	for l in _lights:
		l.light_color = cool if level == 0 else Color(0.75, 0.85, 1.0).lerp(Color(0.8, 0.6, 1.0), level / 3.0)
		l.light_energy = 1.6 + 0.3 * level
	if level < 1:
		return
	var wall := float(Balancing.server_room.get("wall_m", 0.4))
	var y := size.y - 0.12
	for z in [-size.z * 0.25, size.z * 0.25]:
		_part(Vector3(0, y, z), Vector3(size.x - 2.0 * wall - 1.0, 0.08, 0.14), _neon_mat(Color(0.3, 0.95, 1.0)))
	for x in [-size.x * 0.5 + wall + 0.1, size.x * 0.5 - wall - 0.1]:
		_part(Vector3(x, y - 0.3, 0), Vector3(0.06, 0.08, size.z - 2.0 * wall - 0.6), _neon_mat(Color(1.0, 0.35, 0.85)))
	if level >= 2:
		var rd := float(Balancing.server_room.get("rack_depth_m", 0.6))
		var rw := float(Balancing.server_room.get("rack_width_m", 1.5))
		for xf in _rack_xf:
			var glow := _part(Vector3.ZERO, Vector3(rw + 0.2, 0.05, 0.08), _neon_mat(Color(0.55, 0.3, 1.0), 3.0))
			glow.transform = xf * Transform3D(Basis.IDENTITY, Vector3(0, 0.04, rd * 0.5 + 0.12))
	_neon_cycle = level >= 3


## Kühlung: je Stufe zwei Klimageräte aufs Dach und eins an die Wand; ab Stufe 4 Kaltluft-Gitter am Boden
func _build_cooling(level: int) -> void:
	if level < 1:
		return
	var ac := _kit_mesh("AcUnit")
	var white := _flat(Color(0.92, 0.94, 0.96), 0.4)
	for i in level * 2:
		var x := lerpf(-size.x * 0.38, size.x * 0.38, (i + 0.5) / 8.0)
		var z := size.z * (0.22 if i % 2 == 0 else -0.05)
		var at := Vector3(x, size.y + 0.3, z)
		if ac:
			var mi := MeshInstance3D.new()
			mi.mesh = ac
			mi.material_override = _vertex_color_mat()
			mi.position = at
			_extras.add_child(mi)
		else:
			_part(at + Vector3(0, 0.45, 0), Vector3(1.4, 0.9, 0.9), white)
	# Wandgeräte innen an der Vorderwand über Kaffeeecke und Leitstand
	var wall := float(Balancing.server_room.get("wall_m", 0.4))
	var front := -size.z * 0.5 + wall
	for i in level:
		var x: float = [-7.5, 0.0, -4.5, 8.7][i]  # nicht vor dem großen Lagebildschirm
		_part(Vector3(x, 3.7, front + 0.16), Vector3(1.6, 0.42, 0.28), white)
		_part(Vector3(x, 3.52, front + 0.31), Vector3(1.4, 0.04, 0.02), _neon_mat(Color(0.5, 0.85, 1.0), 1.2))
	if level >= 4:
		var grate := _flat(Color(0.35, 0.4, 0.48), 0.4)
		for x in [-5.0, 0.0, 5.0]:
			_part(Vector3(x, 0.03, 0.6), Vector3(1.2, 0.02, 0.6), grate)
			for k in 5:
				var slot := _part(Vector3(x - 0.48 + k * 0.24, 0.045, 0.6), Vector3(0.1, 0.01, 0.5),
					_neon_mat(Color(0.35, 0.65, 1.0), 0.6))
				_neon.erase(slot.material_override)


## Kabelmanagement: 1 Pritschen über den Schränken, 2 gebündelte Kabel darin, 3 Kabel von der Pritsche in jeden Schrank
func _build_cable_trays(level: int) -> void:
	if level < 1:
		return
	var tray := _flat(Color(0.55, 0.58, 0.62), 0.35)
	var rh := float(Balancing.server_room.get("rack_height_m", 2.7))
	var rd := float(Balancing.server_room.get("rack_depth_m", 0.6))
	var colors := [Color(0.95, 0.3, 0.25), Color(0.25, 0.6, 1.0), Color(0.3, 0.85, 0.4), Color(1.0, 0.8, 0.2), Color(0.7, 0.4, 0.95)]
	for xf in _rack_xf:
		var y := rh + 0.95
		var base := xf * Transform3D(Basis.IDENTITY, Vector3(0, y, 0))
		var t := _part(Vector3.ZERO, Vector3(2.6, 0.06, 0.5), tray)
		t.transform = base
		for side in [-1.0, 1.0]:
			var lip := _part(Vector3.ZERO, Vector3(2.6, 0.14, 0.04), tray)
			lip.transform = base * Transform3D(Basis.IDENTITY, Vector3(0, 0.07, side * 0.25))
		if level >= 2:
			for k in colors.size():
				var bundle := _part(Vector3.ZERO, Vector3(2.55, 0.05, 0.07), _flat(colors[k], 0.3))
				bundle.transform = base * Transform3D(Basis.IDENTITY, Vector3(0, 0.06, -0.18 + k * 0.09))
		if level >= 3:
			for k in 3:
				var drop := _part(Vector3.ZERO, Vector3(0.06, y - rh, 0.06), _flat(colors[k], 0.3))
				drop.transform = xf * Transform3D(Basis.IDENTITY, Vector3(-0.4 + k * 0.4, rh + (y - rh) * 0.5, -rd * 0.2))


## Leitstand an der Vorderwand rechts der Tür: 1 Pult mit zwei Bildschirmen, 2 Monitorwand, 3 großer Lagebildschirm
func _build_monitors(level: int) -> void:
	if level < 1:
		return
	var wall := float(Balancing.server_room.get("wall_m", 0.4))
	var front := -size.z * 0.5 + wall
	var dark := _flat(Color(0.12, 0.13, 0.16), 0.4)
	var cx := 5.8
	# Pult
	_part(Vector3(cx, 0.45, front + 0.9), Vector3(3.2, 0.9, 0.8), _flat(Color(0.3, 0.33, 0.38)), true)
	for i in 2:
		_screen(Vector3(cx - 0.75 + i * 1.5, 1.35, front + 0.75), Vector2(1.2, 0.7), ["Kabel-Monitor", "Knoten-Alarm"][i])
	if level >= 2:
		for r in 2:
			for c in 3:
				_screen(Vector3(cx - 1.4 + c * 1.4, 2.0 + r * 0.8, front + 0.06), Vector2(1.25, 0.7),
					["Viertel", "Drohnen", "Winden", "C.O.R.D.", "Lieferzentrum", "Wetter"][r * 3 + c])
	if level >= 3:
		_part(Vector3(cx, 3.75, front + 0.05), Vector3(3.6, 1.2, 0.06), dark)
		var screen := _part(Vector3(cx, 3.75, front + 0.09), Vector3(3.4, 1.05, 0.02), _neon_mat(Color(0.05, 0.2, 0.35), 1.0))
		screen.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_neon.erase(screen.material_override)  # großer Bildschirm wechselt nicht die Farbe
		_screen_label = Label3D.new()
		_screen_label.font_size = 44
		_screen_label.pixel_size = 0.0045
		_screen_label.outline_size = 0
		_screen_label.modulate = Color(0.6, 1.0, 0.85)
		_screen_label.position = Vector3(cx, 3.75, front + 0.11)
		_screen_label.rotation = Vector3(0, 0, 0)
		_extras.add_child(_screen_label)


func _screen(at: Vector3, sz: Vector2, title: String) -> void:
	_part(at, Vector3(sz.x + 0.08, sz.y + 0.08, 0.05), _flat(Color(0.12, 0.13, 0.16), 0.4))
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.08, 0.25, 0.4)
	m.emission_enabled = true
	m.emission = Color(0.1, 0.35, 0.55)
	m.emission_energy_multiplier = 1.2
	_part(at + Vector3(0, 0, 0.03), Vector3(sz.x, sz.y, 0.01), m)
	var label := Label3D.new()
	label.text = title + "\n▮▮▮▮▮▯▯ OK"
	label.font_size = 32
	label.pixel_size = 0.0035
	label.outline_size = 0
	label.modulate = Color(0.55, 1.0, 0.75)
	label.position = at + Vector3(0, 0, 0.04)
	_extras.add_child(label)


## Kaffeeecke an der Vorderwand links der Tür: 1 Bank und Pflanzen, 2 Kaffeemaschine auf Tresen, 3 Sofa und Teppich
func _build_coffee(level: int) -> void:
	if level < 1:
		return
	var wall := float(Balancing.server_room.get("wall_m", 0.4))
	var front := -size.z * 0.5 + wall
	var items: Array = [["Bench", Vector3(-5.8, 0, front + 0.6), 0.0, 1.0], ["Planter", Vector3(-3.1, 0, front + 0.8), 0.0, 0.8]]
	if level < 2:
		items.append(["Planter", Vector3(-8.6, 0, front + 0.8), 0.0, 0.8])
	else:
		_part(Vector3(-8.2, 0.5, front + 0.45), Vector3(1.6, 1.0, 0.7), _flat(Color(0.55, 0.36, 0.22)), true)
		_part(Vector3(-8.4, 1.25, front + 0.4), Vector3(0.45, 0.5, 0.4), _flat(Color(0.75, 0.15, 0.12), 0.3))
		_part(Vector3(-8.4, 1.32, front + 0.61), Vector3(0.06, 0.06, 0.02), _neon_mat(Color(0.3, 1.0, 0.4), 2.0))
		var sign := Label3D.new()
		sign.text = "KAFFEE"
		sign.font_size = 40
		sign.pixel_size = 0.004
		sign.outline_size = 8
		sign.modulate = Color(1.0, 0.85, 0.5)
		sign.position = Vector3(-8.2, 1.8, front + 0.5)
		sign.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		_extras.add_child(sign)
	if level >= 3:
		var sofa := _flat(Color(0.3, 0.55, 0.85), 0.8)
		_part(Vector3(-5.6, 0.25, front + 2.9), Vector3(2.4, 0.5, 0.9), sofa, true)
		_part(Vector3(-5.6, 0.7, front + 3.25), Vector3(2.4, 0.5, 0.2), sofa)
		for side in [-1.0, 1.0]:
			_part(Vector3(-5.6 + side * 1.15, 0.45, front + 2.9), Vector3(0.2, 0.5, 0.9), sofa)
		_part(Vector3(-5.6, 0.015, front + 2.0), Vector3(3.2, 0.03, 2.2), _flat(Color(0.8, 0.45, 0.3), 0.9))
		items.append(["Bush", Vector3(-3.2, 0, front + 3.0), 30.0, 0.9])
	YardProps.add_items(_extras, _extras_body, items)


static var _kit_cache: Dictionary = {}
static func _kit_mesh(part: String) -> Mesh:
	if _kit_cache.has(part):
		return _kit_cache[part]
	var mesh: Mesh = null
	if ResourceLoader.exists(CityBlockout.KIT_PATH):
		var root := (load(CityBlockout.KIT_PATH) as PackedScene).instantiate()
		var mi := root.find_child(part, true, false) as MeshInstance3D
		if mi:
			mesh = mi.mesh
		root.free()
	_kit_cache[part] = mesh
	return mesh


static var _vc_mat: StandardMaterial3D
static func _vertex_color_mat() -> StandardMaterial3D:
	if _vc_mat == null:
		_vc_mat = StandardMaterial3D.new()
		_vc_mat.vertex_color_use_as_albedo = true
		_vc_mat.vertex_color_is_srgb = true
		_vc_mat.roughness = 0.6
	return _vc_mat


# ---------------------------------------------------------------- Aufbau

func _build_shell(cfg: Dictionary) -> void:
	var wall := float(cfg.get("wall_m", 0.4))
	var door_w := float(cfg.get("door_width_m", 3.6))
	var door_h := float(cfg.get("door_height_m", 3.0))
	var hx := size.x * 0.5
	var hz := size.z * 0.5
	var side := (size.x - door_w) * 0.5
	# [Mitte, Größe]: Rückwand, Seitenwände, Vorderwand links/rechts der Tür, Sturz, Dach
	var boxes := [
		[Vector3(0, size.y * 0.5, hz - wall * 0.5), Vector3(size.x, size.y, wall)],
		[Vector3(-hx + wall * 0.5, size.y * 0.5, 0), Vector3(wall, size.y, size.z)],
		[Vector3(hx - wall * 0.5, size.y * 0.5, 0), Vector3(wall, size.y, size.z)],
		[Vector3(-hx + side * 0.5, size.y * 0.5, -hz + wall * 0.5), Vector3(side, size.y, wall)],
		[Vector3(hx - side * 0.5, size.y * 0.5, -hz + wall * 0.5), Vector3(side, size.y, wall)],
		[Vector3(0, (size.y + door_h) * 0.5, -hz + wall * 0.5), Vector3(door_w, size.y - door_h, wall)],
		[Vector3(0, size.y + 0.15, 0), Vector3(size.x + 0.6, 0.3, size.z + 0.6)],
	]
	for b: Array in boxes:
		_collider(b[0], b[1])

	var model := _load_model()
	if model:
		add_child(model)
	else:
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.62, 0.64, 0.68)
		mat.roughness = 0.85
		for b: Array in boxes:
			_mesh_box(b[0], b[1], mat)
	# Boden (liegt knapp über dem Gelände, ohne Kollision)
	var floor_mat := StandardMaterial3D.new()
	floor_mat.albedo_color = Color(0.24, 0.26, 0.3)
	floor_mat.roughness = 0.6
	_mesh_box(Vector3(0, 0.02, 0), Vector3(size.x - 0.1, 0.04, size.z - 0.1), floor_mat)

	var sign := Label3D.new()
	sign.text = "SERVERRAUM"
	sign.font_size = 96
	sign.outline_size = 16
	sign.pixel_size = 0.008
	sign.modulate = Color(0.75, 0.95, 1.0)
	sign.position = Vector3(0, door_h + 0.75, -hz - 0.06)
	sign.rotation = Vector3(0, PI, 0)
	add_child(sign)


func _load_model() -> Node3D:
	if not ResourceLoader.exists(MODEL_PATH):
		return null
	var scene := load(MODEL_PATH) as PackedScene
	if scene == null:
		return null
	var model := scene.instantiate() as Node3D
	# Farben stecken als Vertex-Farben im Mesh
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.vertex_color_is_srgb = true  # Farben aus Blender sind sRGB-Werte
	mat.roughness = 0.8
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).material_override = mat
	return model


func _build_racks(cfg: Dictionary) -> void:
	var rw := float(cfg.get("rack_width_m", 1.5))
	var rh := float(cfg.get("rack_height_m", 2.7))
	var rd := float(cfg.get("rack_depth_m", 0.6))
	var wall := float(cfg.get("wall_m", 0.4))
	var hx := size.x * 0.5 - wall - rd * 0.5 - 0.05
	var hz := size.z * 0.5 - wall - rd * 0.5 - 0.05
	var sections := RackPlan.sections()
	var n := sections.size()
	# Verteilung in Spielreihenfolge, von der Tür aus gesehen im Uhrzeigersinn:
	# zwei an der linken Wand (+x), dann die Rückwand von links nach rechts, zuletzt zwei an der rechten Wand
	var side_n := 2 if n >= 6 else 0
	var back_n := n - side_n * 2
	for i in n:
		var xf: Transform3D
		if i < side_n:
			var z := lerpf(-size.z * 0.5 + 3.2, hz - 2.6, float(i) / maxf(side_n - 1, 1))
			xf = Transform3D(Basis(Vector3.UP, -PI * 0.5), Vector3(hx, 0, z))
		elif i < side_n + back_n:
			var k := i - side_n
			var span := size.x - 2.0 * (wall + rd + 1.6)
			var x := lerpf(span * 0.5, -span * 0.5, float(k) / maxf(back_n - 1, 1))
			xf = Transform3D(Basis(Vector3.UP, PI), Vector3(x, 0, hz))
		else:
			var k := i - side_n - back_n
			var z := lerpf(hz - 2.6, -size.z * 0.5 + 3.2, float(k) / maxf(side_n - 1, 1))
			xf = Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(-hx, 0, z))
		_rack_xf.append(xf)

	var rack_mat := StandardMaterial3D.new()
	rack_mat.albedo_color = Color(0.13, 0.15, 0.19)
	rack_mat.roughness = 0.45
	rack_mat.metallic = 0.4
	_port_xf.resize(RackPlan.total_ports())
	for i in n:
		var sec: Dictionary = sections[i]
		var xf := _rack_xf[i]
		var mi := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(rw, rh, rd)
		mi.mesh = box
		mi.material_override = rack_mat
		mi.transform = xf * Transform3D(Basis.IDENTITY, Vector3(0, rh * 0.5, 0))
		add_child(mi)
		var size_rot := Vector3(absf((xf.basis * Vector3(rw, 0, 0)).x) + absf((xf.basis * Vector3(0, 0, rd)).x), rh,
			absf((xf.basis * Vector3(rw, 0, 0)).z) + absf((xf.basis * Vector3(0, 0, rd)).z))
		_collider(xf.origin + Vector3(0, rh * 0.5, 0), size_rot)

		# Lämpchen: 10 je Reihe, von oben nach unten
		var count := int(sec["count"])
		var rows := ceili(float(count) / COLS)
		var area := rh - 0.5
		var pitch_y := minf(0.16, area / rows)
		var pitch_x := (rw - 0.2) / COLS
		for k in count:
			var col := k % COLS
			var row := floori(float(k) / COLS)
			var local := Vector3((col - (COLS - 1) * 0.5) * pitch_x, rh - 0.25 - row * pitch_y, rd * 0.5 + 0.012)
			_port_xf[int(sec["first_port"]) + k] = xf * Transform3D(Basis.IDENTITY.scaled(Vector3(pitch_x * 0.72, minf(pitch_y * 0.6, 0.07), 0.02)), local)

		var title := Label3D.new()
		title.font_size = 48
		title.outline_size = 12
		title.pixel_size = 0.0046
		title.transform = xf * Transform3D(Basis.IDENTITY, Vector3(0, rh + 0.55, rd * 0.5))
		add_child(title)
		_titles.append(title)

	_lamps = MultiMesh.new()
	_lamps.transform_format = MultiMesh.TRANSFORM_3D
	_lamps.use_colors = true
	var lamp := BoxMesh.new()
	lamp.size = Vector3.ONE
	var lamp_mat := StandardMaterial3D.new()
	lamp_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	lamp_mat.vertex_color_use_as_albedo = true
	lamp.material = lamp_mat
	_lamps.mesh = lamp
	_lamps.instance_count = _port_xf.size()
	for p in _port_xf.size():
		_lamps.set_instance_transform(p, _port_xf[p])
		_lamps.set_instance_color(p, LAMP_OFF)
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = _lamps
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)


func _collider(center_pos: Vector3, box_size: Vector3) -> void:
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = box_size
	col.shape = shape
	col.position = center_pos
	_body.add_child(col)


func _mesh_box(center_pos: Vector3, box_size: Vector3, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = box_size
	mi.mesh = box
	mi.material_override = mat
	mi.position = center_pos
	add_child(mi)
