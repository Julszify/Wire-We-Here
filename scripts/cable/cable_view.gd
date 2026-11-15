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
func show_on_reel(reel_pos: Vector3, scale: float = 1.0) -> float:
	var shape := CableShape.build_on_reel(data, reel_pos, scale)
	_build(shape["points"])
	return shape["phase"]


## Form um den Arm der Spielfigur gewickelt.
func show_on_arm(arm: Transform3D) -> void:
	_build(CableShape.build_on_arm(data, arm))


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


func _build(pts: PackedVector3Array) -> void:
	TubeMesh.build(pts, data.radius(), int(Balancing.cable["tube_sides"]), _mesh)
	PlugMeshes.add_to_mesh(_mesh, data.plug_id(), pts, _plug_roll)
	_apply_materials()


## Fläche 0 = Kabel, Fläche 1 = Stecker (wird bei jedem Neubau gesetzt, weil das Mesh neu entsteht)
func _apply_materials() -> void:
	if _mesh.get_surface_count() > 0:
		_mesh.surface_set_material(0, _mat)
	if _mesh.get_surface_count() > 1:
		_mesh.surface_set_material(1, _plug_mat)
