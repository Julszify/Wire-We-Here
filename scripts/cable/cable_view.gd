class_name CableView
extends MeshInstance3D
## Darstellung eines Kabels. Liest nur aus CableData, verändert sie nie.

var data: CableData
var _mesh := ArrayMesh.new()
var _mat: StandardMaterial3D


func setup(cable: CableData) -> void:
	data = cable
	mesh = _mesh
	_mat = StandardMaterial3D.new()
	_mat.albedo_color = cable.color()
	_mat.roughness = 0.35
	_mat.metallic = 0.05
	_mat.clearcoat_enabled = true
	_mat.clearcoat = 0.4
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
	_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA if alpha < 1.0 else BaseMaterial3D.TRANSPARENCY_DISABLED
	_mat.albedo_color.a = alpha


func _build(pts: PackedVector3Array) -> void:
	var c: Dictionary = Balancing.cable
	TubeMesh.build(pts, c["radius_m"], int(c["tube_sides"]), _mesh)
