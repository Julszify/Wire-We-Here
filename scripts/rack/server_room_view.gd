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
