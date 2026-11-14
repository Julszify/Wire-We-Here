class_name ReelView
extends Node3D
## Platzhalter-Darstellung einer Rolle: Trommel, zwei Flansche, bei der Handkurbel ein Griff.
## Die Drehung kommt von außen (passend zur Kabel-Spirale), nicht aus eigener Zeitmessung.

var data: ReelData
var _spin: Node3D


func setup(reel: ReelData) -> void:
	data = reel
	position = reel.position
	var r: Dictionary = Balancing.reel
	var drum_r: float = r["drum_radius_m"]
	var drum_h: float = r["drum_height_m"]
	var flange_r: float = r["flange_radius_m"]

	var metal := _material(Color(0.6, 0.65, 0.7), 0.5, 0.4)
	var flange_color := Color(0.54, 0.35, 0.23) if reel.kind == ReelData.Kind.HAND else Color(0.95, 0.76, 0.19)
	var flange_mat := _material(flange_color, 0.7, 0.0)

	_spin = Node3D.new()
	add_child(_spin)
	_add_cylinder(_spin, drum_r, drum_h, Vector3(0, 0.15 + drum_h * 0.5, 0), metal)
	_add_cylinder(_spin, flange_r, 0.06, Vector3(0, 0.12, 0), flange_mat)
	_add_cylinder(_spin, flange_r, 0.06, Vector3(0, 0.18 + drum_h, 0), flange_mat)

	if reel.kind == ReelData.Kind.HAND:
		# Kurbelarm mit Griff oben auf dem Flansch
		var top := 0.21 + drum_h
		var arm := MeshInstance3D.new()
		var arm_mesh := BoxMesh.new()
		arm_mesh.size = Vector3(0.7, 0.06, 0.12)
		arm.mesh = arm_mesh
		arm.material_override = flange_mat
		arm.position = Vector3(0.35, top, 0)
		_spin.add_child(arm)
		_add_cylinder(_spin, 0.06, 0.32, Vector3(0.66, top + 0.16, 0), metal)
	else:
		# Motorgehäuse (dreht sich nicht mit)
		var motor := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(0.5, 0.4, 0.5)
		motor.mesh = box
		motor.material_override = _material(Color(0.23, 0.26, 0.31), 0.6, 0.0)
		motor.position = Vector3(flange_r + 0.2, 0.2, 0)
		add_child(motor)


## Drehwinkel aus der Spirale (Bogenmaß, gleiche Konvention wie CableShape).
func set_phase(phase: float) -> void:
	# CableShape legt Punkte bei (cos a, sin a) in X/Z ab; in Godot entspricht das -a um Y
	_spin.rotation.y = -phase


func _add_cylinder(parent: Node3D, radius: float, height: float, pos: Vector3, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = radius
	cyl.bottom_radius = radius
	cyl.height = height
	cyl.radial_segments = 32
	mi.mesh = cyl
	mi.material_override = mat
	mi.position = pos
	parent.add_child(mi)


static func _material(color: Color, roughness: float, metallic: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = roughness
	m.metallic = metallic
	return m
