class_name CableView
extends MeshInstance3D
## Darstellung eines Kabels. Liest nur aus CableData, verändert sie nie.

var data: CableData
var _mesh := ArrayMesh.new()
var _mat: StandardMaterial3D
var _plug_mat: StandardMaterial3D
var _label: Label3D
## Drehung der Stecker um die Kabelachse (aus dem Seed, damit nicht alle gleich liegen)
var _plug_roll := 0.0
## Spannung des Verbindungsstücks (0 locker … 1 straff) und Zittern am Knoten; nur Darstellung
var tension := 0.0
var jitter := 0.0
var _time := 0.0
var _delta := 0.016
var _was_stuck := false
## Verbindungsstück als weiches Seil (schwingt nach, ruckt am Knoten)
var _rope := CableRope.new()


## Aussehen fürs Verbindungsstück, inklusive Seil-Zustand
func _look(ground_y: float) -> Dictionary:
	var lk := CableShape.look(tension, jitter, _time, ground_y)
	lk["rope"] = _rope
	lk["delta"] = _delta
	return lk


func setup(cable: CableData) -> void:
	data = cable
	mesh = _mesh
	if cable.is_important():
		# Wichtige Kabel leuchten schwach und tragen ein Etikett (eigenes Material)
		_mat = _new_material(cable.color())
		_mat.emission_enabled = true
		_mat.emission = cable.color().lightened(0.3)
		_mat.emission_energy_multiplier = 0.6
		_label = Label3D.new()
		_label.text = RackPlan.port_label(cable.port_id)
		_label.font_size = 40
		_label.outline_size = 10
		_label.pixel_size = 0.004
		_label.modulate = Color(0.75, 1.0, 1.0)
		_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		_label.no_depth_test = true
		_label.visibility_range_end = 9.0
		add_child(_label)
		_label.position = cable.path.points[0] + Vector3(0, 0.35, 0)
	else:
		# Gewöhnliche Kabel teilen sich ein Material pro Farbe (viel schneller bei hunderten Kabeln)
		_mat = _shared_material(cable.color_index, cable.color())
	_plug_mat = PlugMeshes.material()
	_plug_roll = float(posmod(cable.rng_seed, 628)) / 100.0
	show_in_heap()


## Ruhende Form im Haufen (wird nur einmal gebaut).
func show_in_heap() -> void:
	_build(data.path.points)


## Form an einer Rolle. Nur für aktive Kabel pro Frame aufrufen.
## Gibt den Drehwinkel der Rolle zurück.
func show_on_reel(reel_pos: Vector3, scale: float = 1.0, ground_y: float = NAN) -> float:
	var t0 := Time.get_ticks_usec()
	var shape := CableShape.build_on_reel(data, reel_pos, scale, _look(ground_y))
	stat_us[0] += Time.get_ticks_usec() - t0
	_build(shape["points"])
	return shape["phase"]


## Form um den Arm der Spielfigur gewickelt.
func show_on_arm(arm: Transform3D, ground_y: float = NAN) -> void:
	_build(CableShape.build_on_arm(data, arm, _look(ground_y)))


## Spannung nachführen: `target` 1 = wird gerade gezogen, 0 = locker; `stuck` = hängt am Knoten
func update_tension(target: float, stuck: bool, delta: float) -> void:
	var c: Dictionary = Balancing.connector
	_time += delta
	_delta = delta
	# Ruck am Knoten (Kabel bleibt schlagartig hängen) und beim Lösen
	if stuck != _was_stuck:
		_rope.kick(Vector3(0, float(c.get("knot_kick", 5.0)) * (1.0 if stuck else 0.6), 0))
		_was_stuck = stuck
	if stuck:
		target = 1.0
	var rate := 1.0 / maxf(float(c.get("tension_up_s" if target > tension else "tension_down_s", 0.3)), 0.01)
	tension = move_toward(tension, target, rate * delta)
	jitter = move_toward(jitter, 1.0 if stuck else 0.0, 4.0 * delta)


## Ausblenden nach dem Fertigstellen (0 = unsichtbar, 1 = voll sichtbar).
func set_fade(alpha: float) -> void:
	if _label:
		_label.visible = alpha >= 1.0
	if _SHARED.values().has(_mat):
		# Geteiltes Material nicht für alle Kabel ausblenden: vorher kopieren
		_mat = _mat.duplicate()
	if _plug_mat == PlugMeshes.material():
		_plug_mat = _plug_mat.duplicate()
	for m in [_mat, _plug_mat]:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA if alpha < 1.0 else BaseMaterial3D.TRANSPARENCY_DISABLED
		m.albedo_color.a = alpha
	_apply_materials()


static var _SHARED: Dictionary = {}  # Farbindex -> StandardMaterial3D


static func _shared_material(index: int, color: Color) -> StandardMaterial3D:
	if not _SHARED.has(index):
		_SHARED[index] = _new_material(color)
	return _SHARED[index]


static func _new_material(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 0.35
	m.metallic = 0.05
	m.clearcoat_enabled = true
	m.clearcoat = 0.4
	return m


## Messung (--perf): gebaute Kabel und Punkte seit der letzten Ausgabe
static var stat_builds := 0
static var stat_points := 0
static var stat_us := [0, 0, 0, 0]  # Form, Ausdünnen, Röhre, Stecker


## Kamera für die Detailstufe aktiver Kabel (von der Welt gesetzt)
static var camera: Camera3D


func _build(pts: PackedVector3Array) -> void:
	# Detail nach Abstand: nah fein und rund, weiter weg weniger Punkte und Seiten
	var sides := int(Balancing.cable["tube_sides"])
	var step := 0.05
	if camera and is_instance_valid(camera) and pts.size() > 0:
		var d := camera.global_position.distance_to(pts[pts.size() / 2])
		if d > 30.0:
			step = 0.35
			sides = maxi(5, sides - 4)
		elif d > 12.0:
			step = 0.14
			sides = maxi(6, sides - 2)
	var t0 := Time.get_ticks_usec()
	pts = simplify(pts, step)
	var t1 := Time.get_ticks_usec()
	stat_builds += 1
	stat_points += pts.size()
	TubeMesh.build(pts, data.radius(), sides, _mesh)
	var t2 := Time.get_ticks_usec()
	_place_plugs(pts)
	stat_us[1] += t1 - t0
	stat_us[2] += t2 - t1
	stat_us[3] += Time.get_ticks_usec() - t2
	_apply_materials()


## Fläche 0 = Kabel (wird bei jedem Neubau gesetzt, weil das Mesh neu entsteht); Stecker sind eigene Nodes
func _apply_materials() -> void:
	if _mesh.get_surface_count() > 0:
		_mesh.surface_set_material(0, _mat)
	for p in _plugs:
		p.material_override = _plug_mat


## Zwei Stecker als eigene kleine Meshes an den Enden: nur ihre Lage ändert sich pro Bild
var _plugs: Array[MeshInstance3D] = []


func _place_plugs(pts: PackedVector3Array) -> void:
	if pts.size() < 2:
		return
	if _plugs.is_empty():
		var m := PlugMeshes.mesh_of(data.plug_id())
		if m == null:
			return
		for i in 2:
			var mi := MeshInstance3D.new()
			mi.mesh = m
			mi.material_override = _plug_mat
			add_child(mi)
			_plugs.append(mi)
	var xf := PlugMeshes.end_transforms(pts, _plug_roll)
	_plugs[0].transform = xf[0]
	_plugs[1].transform = xf[1]


## Punkte ausdünnen: sehr dicht liegende fallen weg, Knicke bleiben (Wicklung, Bögen)
static func simplify(pts: PackedVector3Array, step: float) -> PackedVector3Array:
	var n := pts.size()
	if n < 4:
		return pts
	var out := PackedVector3Array()
	out.resize(n)
	out[0] = pts[0]
	var m := 1
	var last := pts[0]
	var last_dir := Vector3.ZERO
	var min_step := step * 0.3
	for i in range(1, n - 1):
		var d := pts[i] - last
		var len := d.length()
		if len < min_step:
			continue
		var dir := d / len
		if len >= step or (last_dir != Vector3.ZERO and last_dir.dot(dir) < 0.985):
			out[m] = pts[i]
			m += 1
			last_dir = dir
			last = pts[i]
	out[m] = pts[n - 1]
	m += 1
	out.resize(m)
	return out
