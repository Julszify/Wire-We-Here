class_name CableView
extends MeshInstance3D
## Darstellung eines Kabels. Liest nur aus CableData, verändert sie nie.

var data: CableData
var _mesh := ArrayMesh.new()
var _mat: StandardMaterial3D
var _label: Label3D


func setup(cable: CableData) -> void:
	data = cable
	mesh = _mesh
	_mat = StandardMaterial3D.new()
	_mat.albedo_color = cable.color()
	_mat.roughness = 0.35
	_mat.metallic = 0.05
	_mat.clearcoat_enabled = true
	_mat.clearcoat = 0.4
	if cable.is_important():
		# Wichtige Kabel leuchten schwach und tragen ein Etikett
		_mat.emission_enabled = true
		_mat.emission = cable.color().lightened(0.3)
		_mat.emission_energy_multiplier = 0.6
		_label = Label3D.new()
		_label.text = "Port %d · %s" % [cable.port_id + 1, ServiceRack.service_name(cable.port_id)]
		_label.font_size = 40
		_label.outline_size = 10
		_label.pixel_size = 0.004
		_label.modulate = Color(0.75, 1.0, 1.0)
		_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		_label.no_depth_test = true
		_label.visibility_range_end = 9.0
		add_child(_label)
		_label.position = cable.path.points[0] + Vector3(0, 0.35, 0)
	material_override = _mat
	show_in_heap()


## Ruhende Form im Haufen (wird nur einmal gebaut).
func show_in_heap() -> void:
	_build(data.path.points)


## Form an einer Rolle. Nur für aktive Kabel pro Frame aufrufen.
## Gibt den Drehwinkel der Rolle zurück.
func show_on_reel(reel_pos: Vector3) -> float:
	var shape := CableShape.build_on_reel(data, reel_pos)
	_build(shape["points"])
	return shape["phase"]


## Form um den Arm der Spielfigur gewickelt.
func show_on_arm(arm: Transform3D) -> void:
	_build(CableShape.build_on_arm(data, arm))


## Ausblenden nach dem Fertigstellen (0 = unsichtbar, 1 = voll sichtbar).
func set_fade(alpha: float) -> void:
	if _label:
		_label.visible = alpha >= 1.0
	_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA if alpha < 1.0 else BaseMaterial3D.TRANSPARENCY_DISABLED
	_mat.albedo_color.a = alpha


func _build(pts: PackedVector3Array) -> void:
	var c: Dictionary = Balancing.cable
	TubeMesh.build(pts, c["radius_m"], int(c["tube_sides"]), _mesh)
