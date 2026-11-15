class_name Zipline
extends Node3D
## Seilbahn zur Basis: Strecke aus world.json (ziplines), Masten, Stationen und Seil.
## Die Fahrt selbst steuert die Hauptszene; hier stehen Bahn (gleichmäßig abgetastet) und Darstellung.
## Erste Station = äußeres Ende, letzte = Basis-Seite. Freigeschaltet durch einen Dienst (`unlock`).

var id := ""
var line_name := ""
var unlock := ""
var continues := ""
## Seil-Punkte in Szenen-Koordinaten, ca. alle 2 m, vom äußeren Ende zur Basis
var path := PackedVector3Array()
## Stationen am Boden (Szenen-Koordinaten): [äußeres Ende, Basis-Seite]
var stations: Array[Vector3] = []
var length := 0.0
var _signs: Array[Label3D] = []
var _cable_mat: StandardMaterial3D


func build(cfg: Dictionary, city: CityWorld) -> void:
	id = String(cfg["id"])
	line_name = String(cfg.get("name", id))
	unlock = String(cfg.get("unlock", ""))
	continues = String(cfg.get("continues", ""))
	var tops: Array[Vector3] = []
	var feet: Array[Vector3] = []
	for p: Array in cfg["points"]:
		var ground := city.to_scene(Vector2(float(p[0]), float(p[1])))
		feet.append(ground)
		tops.append(ground + Vector3(0, float(p[2]), 0))
	stations = [city.to_scene(Vector2(float(cfg["points"][0][0]), float(cfg["points"][0][1]))),
		city.to_scene(Vector2(float(cfg["points"][-1][0]), float(cfg["points"][-1][1])))]
	path = sample_path(tops, func(x: float, z: float) -> float: return city.ground_height(x, z))
	length = CablePath.polyline_length(path)
	_build_view(tops, feet)


## Bahn zwischen den Mastspitzen mit leichtem Durchhang, nie näher als min_clearance_m am Boden
static func sample_path(tops: Array[Vector3], ground: Callable) -> PackedVector3Array:
	var z: Dictionary = Balancing.zipline
	var sag := float(z.get("sag_per_m", 0.025))
	var clear := float(z.get("min_clearance_m", 3.0)) + float(z.get("hang_m", 2.3))
	var out := PackedVector3Array()
	for i in tops.size() - 1:
		var a := tops[i]
		var b := tops[i + 1]
		var span := Vector2(b.x - a.x, b.z - a.z).length()
		var steps := maxi(2, ceili(span / 2.0))
		for k in steps:
			var t := float(k) / steps
			var p := a.lerp(b, t)
			p.y -= sag * span * 4.0 * t * (1.0 - t)
			p.y = maxf(p.y, float(ground.call(p.x, p.z)) + clear)
			out.append(p)
	out.append(tops[-1])
	return out


## Punkt auf dem Seil nach `s` Metern vom äußeren Ende
func point_at(s: float) -> Vector3:
	var left := clampf(s, 0.0, length)
	for i in path.size() - 1:
		var seg := path[i].distance_to(path[i + 1])
		if left <= seg:
			return path[i].lerp(path[i + 1], left / maxf(seg, 0.001))
		left -= seg
	return path[path.size() - 1]


func set_unlocked(on: bool, service_hint: String) -> void:
	for i in _signs.size():
		var dest := "zur Basis" if i == 0 else "hinaus"
		_signs[i].text = "%s\n%s" % [line_name, ("E: fahren " + dest) if on else "außer Betrieb\n" + service_hint]
		_signs[i].modulate = Color(0.75, 1.0, 0.8) if on else Color(1.0, 0.7, 0.6)
	_cable_mat.albedo_color = Color(0.2, 0.22, 0.26) if on else Color(0.45, 0.45, 0.48)


func _build_view(tops: Array[Vector3], feet: Array[Vector3]) -> void:
	_cable_mat = StandardMaterial3D.new()
	_cable_mat.roughness = 0.4
	var cable := MeshInstance3D.new()
	cable.mesh = TubeMesh.build(path, 0.04, 6)
	cable.material_override = _cable_mat
	cable.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(cable)
	var steel := StandardMaterial3D.new()
	steel.albedo_color = Color(0.3, 0.33, 0.38)
	steel.roughness = 0.5
	var yellow := StandardMaterial3D.new()
	yellow.albedo_color = Color(0.97, 0.8, 0.3)
	for i in tops.size():
		var top := tops[i]
		var foot := feet[i]
		var h := top.y - foot.y
		_box(Vector3(0.35, h + 0.4, 0.35), foot + Vector3(0, (h + 0.4) * 0.5, 0), steel)
		_box(Vector3(1.6, 0.18, 0.25), top + Vector3(0, 0.2, 0), yellow)
		if i == 0 or i == tops.size() - 1:
			# Station: Plattform mit Geländer und Schild
			_box(Vector3(3.2, 0.3, 3.2), foot + Vector3(0, 0.15, 0), steel)
			_box(Vector3(3.2, 0.9, 0.1), foot + Vector3(0, 0.75, 1.55), yellow)
			var sign := Label3D.new()
			sign.font_size = 52
			sign.outline_size = 12
			sign.pixel_size = 0.005
			sign.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			sign.position = foot + Vector3(0, 3.0, 0)
			sign.visibility_range_end = 60.0
			add_child(sign)
			_signs.append(sign)


func _box(size: Vector3, pos: Vector3, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = size
	mi.mesh = b
	mi.material_override = mat
	mi.position = pos
	add_child(mi)
