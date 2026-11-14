class_name RackView
extends Node3D
## Platzhalter-Server-Schrank: dunkler Kasten mit 20 Port-Lämpchen (4 × 5)
## und einer Anzeige der laufenden Dienste. Rot = aus, Grün = Dienst läuft.

const COLS := 4
const WIDTH := 0.9
const HEIGHT := 2.0
const DEPTH := 0.6

var _lamps: Array[MeshInstance3D] = []
var _off := _lamp_material(Color(0.7, 0.12, 0.1), 0.6)
var _on := _lamp_material(Color(0.2, 1.0, 0.35), 2.5)
var _title: Label3D


func setup(port_count: int) -> void:
	var body := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(WIDTH, HEIGHT, DEPTH)
	body.mesh = box
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.16, 0.18, 0.22)
	mat.roughness = 0.5
	mat.metallic = 0.3
	body.material_override = mat
	body.position = Vector3(0, HEIGHT * 0.5, 0)
	add_child(body)

	# Port-Lämpchen auf der Vorderseite (+Z)
	var rows := ceili(float(port_count) / COLS)
	var lamp_mesh := BoxMesh.new()
	lamp_mesh.size = Vector3(0.12, 0.08, 0.04)
	for i in port_count:
		var lamp := MeshInstance3D.new()
		lamp.mesh = lamp_mesh
		lamp.material_override = _off
		var col := i % COLS
		var row := floori(i / float(COLS))
		lamp.position = Vector3((col - (COLS - 1) * 0.5) * 0.19, 1.75 - row * (1.3 / maxf(rows - 1, 1)), DEPTH * 0.5 + 0.01)
		add_child(lamp)
		_lamps.append(lamp)

	_title = Label3D.new()
	_title.font_size = 48
	_title.outline_size = 12
	_title.pixel_size = 0.004
	_title.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_title.position = Vector3(0, HEIGHT + 0.35, 0)
	add_child(_title)
	set_active_count(0, port_count)


func set_port_active(port_id: int, active: bool) -> void:
	if port_id >= 0 and port_id < _lamps.size():
		_lamps[port_id].material_override = _on if active else _off


func set_active_count(active: int, total: int) -> void:
	_title.text = "Server-Schrank\n%d / %d Dienste online" % [active, total]


static func _lamp_material(color: Color, glow: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = glow
	return m
