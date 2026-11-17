class_name DroneView
extends Node3D
## Abräum-Drohne: gelber Körper, vier Arme mit Rotoren, Leuchte unten. Platzhalter im Spielzeug-Look,
## alles aus Grundformen. Die Lage setzt die Hauptszene; die Rotoren drehen sich hier.

## Lack (Kosmetik): gilt für neue Drohnen; laufende stellt set_paint um
static var paint := Color(0.98, 0.78, 0.15)
var _body_mat: StandardMaterial3D
var _rotors: Array[Node3D] = []
var _lamp: StandardMaterial3D
var _t := 0.0


func _ready() -> void:
	var body_mat := _mat(paint)
	_body_mat = body_mat
	var dark := _mat(Color(0.18, 0.2, 0.24))
	var body := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.55, 0.22, 0.55)
	body.mesh = box
	body.material_override = body_mat
	add_child(body)
	var dome := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.2
	sphere.height = 0.22
	dome.mesh = sphere
	dome.material_override = dark
	dome.position = Vector3(0, 0.12, 0)
	add_child(dome)
	for i in 4:
		var a := PI * 0.25 + i * PI * 0.5
		var dir := Vector3(cos(a), 0, sin(a))
		var arm := MeshInstance3D.new()
		var arm_mesh := BoxMesh.new()
		arm_mesh.size = Vector3(0.5, 0.05, 0.07)
		arm.mesh = arm_mesh
		arm.material_override = dark
		arm.position = dir * 0.35
		arm.rotation.y = -a
		add_child(arm)
		var rotor := Node3D.new()
		rotor.position = dir * 0.6 + Vector3(0, 0.07, 0)
		add_child(rotor)
		var blade := MeshInstance3D.new()
		var blade_mesh := BoxMesh.new()
		blade_mesh.size = Vector3(0.42, 0.015, 0.06)
		blade.mesh = blade_mesh
		blade.material_override = dark
		rotor.add_child(blade)
		var ring := MeshInstance3D.new()
		var ring_mesh := CylinderMesh.new()
		ring_mesh.top_radius = 0.24
		ring_mesh.bottom_radius = 0.24
		ring_mesh.height = 0.02
		ring.mesh = ring_mesh
		var glass := _mat(Color(0.9, 0.95, 1.0, 0.18))
		glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		ring.material_override = glass
		rotor.add_child(ring)
		_rotors.append(rotor)
	var lamp := MeshInstance3D.new()
	var lamp_mesh := SphereMesh.new()
	lamp_mesh.radius = 0.07
	lamp_mesh.height = 0.1
	lamp.mesh = lamp_mesh
	_lamp = _mat(Color(0.3, 1.0, 0.5))
	_lamp.emission_enabled = true
	_lamp.emission = Color(0.3, 1.0, 0.5)
	_lamp.emission_energy_multiplier = 3.0
	lamp.material_override = _lamp
	lamp.position = Vector3(0, -0.13, 0)
	add_child(lamp)


## Leuchte: grün = arbeitet, gelb = fliegt, blau = bringt Knäuel zur Basis
func set_mode(mode: String) -> void:
	var c := Color(0.3, 1.0, 0.5)
	if mode == "fly":
		c = Color(1.0, 0.85, 0.2)
	elif mode == "deliver":
		c = Color(0.3, 0.7, 1.0)
	_lamp.albedo_color = c
	_lamp.emission = c


func _process(delta: float) -> void:
	_t += delta
	for i in _rotors.size():
		_rotors[i].rotation.y += delta * (38.0 if i % 2 == 0 else -38.0)
	# leichtes Schaukeln in der Luft
	rotation.z = sin(_t * 2.3) * 0.04
	rotation.x = cos(_t * 1.9) * 0.04


static func _mat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.45
	return m


func set_paint(color: Color) -> void:
	if _body_mat:
		_body_mat.albedo_color = color
