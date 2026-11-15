class_name CoilItemView
extends Node3D
## Darstellung eines Knäuels: dieselben Schlaufen wie am Arm, mit Etikett.
## In der Tasche hängt es am Rücken der Figur, am Boden liegt es flach.

var data: CoilItem
var _label: Label3D


func setup(item: CoilItem) -> void:
	data = item
	var mi := MeshInstance3D.new()
	var c: Dictionary = Balancing.cable
	var pts := CableShape.ring_coil_points(item.visual_length)
	mi.mesh = TubeMesh.build(pts, c["radius_m"], int(c["tube_sides"]))
	var mat := StandardMaterial3D.new()
	mat.albedo_color = item.color()
	mat.roughness = 0.35
	mat.emission_enabled = true
	mat.emission = item.color().lightened(0.3)
	mat.emission_energy_multiplier = 0.6
	mi.material_override = mat
	add_child(mi)

	_label = Label3D.new()
	_label.text = RackPlan.port_label(item.port_id)
	_label.font_size = 40
	_label.outline_size = 10
	_label.pixel_size = 0.004
	_label.modulate = Color(0.75, 1.0, 1.0)
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.no_depth_test = true
	_label.top_level = true
	add_child(_label)


## Getragen: Lage des Unterarms übernehmen.
func follow_arm(arm: Transform3D) -> void:
	global_transform = arm
	_label.global_position = arm.origin + Vector3(0, 0.95, 0)


## In der Tasche: hängt verkleinert am Rücken, ohne Etikett.
func set_carried(carried: bool) -> void:
	_label.visible = not carried


func carry_at(xf: Transform3D) -> void:
	global_transform = xf


## Am Boden: flach hinlegen (Schlaufen waagerecht).
func lie_at(pos: Vector3) -> void:
	global_transform = Transform3D(Basis.IDENTITY, pos + Vector3(0, 0.1, 0))
	_label.global_position = pos + Vector3(0, 0.6, 0)
	_label.visibility_range_end = 25.0
