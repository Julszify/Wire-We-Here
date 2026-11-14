class_name CordView
extends Node3D
## Platzhalter für C.O.R.D.: schwebender Zylinder mit Leuchtring, folgt dem Spieler.
## Der Ring leuchtet cyan; während der Bestellfrage blinkt er rot.

var _ring_mat: StandardMaterial3D
var _body: Node3D
var _speech: Label3D
var _asking := false
var _t := 0.0

const CALM := Color(0.3, 0.9, 1.0)
const ALARM := Color(1.0, 0.2, 0.15)


func _ready() -> void:
	_body = Node3D.new()
	add_child(_body)

	var shell := StandardMaterial3D.new()
	shell.albedo_color = Color(0.88, 0.9, 0.93)
	shell.roughness = 0.25
	shell.metallic = 0.3
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.24
	cyl.bottom_radius = 0.28
	cyl.height = 0.6
	cyl.material = shell
	var body_mesh := MeshInstance3D.new()
	body_mesh.mesh = cyl
	_body.add_child(body_mesh)

	var cap := SphereMesh.new()
	cap.radius = 0.24
	cap.height = 0.24
	cap.is_hemisphere = true
	cap.material = shell
	var cap_mesh := MeshInstance3D.new()
	cap_mesh.mesh = cap
	cap_mesh.position = Vector3(0, 0.3, 0)
	_body.add_child(cap_mesh)

	_ring_mat = StandardMaterial3D.new()
	_ring_mat.albedo_color = CALM
	_ring_mat.emission_enabled = true
	_ring_mat.emission = CALM
	_ring_mat.emission_energy_multiplier = 3.0
	var torus := TorusMesh.new()
	torus.inner_radius = 0.27
	torus.outer_radius = 0.34
	torus.material = _ring_mat
	var ring := MeshInstance3D.new()
	ring.mesh = torus
	ring.position = Vector3(0, 0.08, 0)
	_body.add_child(ring)

	# "Auge": leuchtender Streifen vorne
	var eye := MeshInstance3D.new()
	var eye_box := BoxMesh.new()
	eye_box.size = Vector3(0.26, 0.05, 0.04)
	eye_box.material = _ring_mat
	eye.mesh = eye_box
	eye.position = Vector3(0, 0.2, -0.25)
	_body.add_child(eye)

	_speech = Label3D.new()
	_speech.font_size = 32
	_speech.outline_size = 10
	_speech.pixel_size = 0.0011
	_speech.fixed_size = true
	_speech.modulate = Color(1.0, 0.75, 0.7)
	_speech.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_speech.no_depth_test = true
	_speech.position = Vector3(0, 0.75, 0)
	_speech.visible = false
	add_child(_speech)


## Weich links neben den Spieler schweben (Kamera sitzt rechts hinten) und zu ihm schauen.
## follow_side_m < 0 = links, follow_behind_m < 0 = etwas vor dem Spieler.
func follow(player_pos: Vector3, player_facing: Vector3, delta: float) -> void:
	var c: Dictionary = Balancing.cord
	var right := player_facing.cross(Vector3.UP).normalized()
	var target := player_pos - player_facing * float(c["follow_behind_m"]) \
		+ right * float(c["follow_side_m"]) + Vector3(0, float(c["hover_height_m"]), 0)
	global_position = global_position.lerp(target, 1.0 - exp(-float(c["follow_speed"]) * delta))
	var look := player_pos + Vector3(0, 1.3, 0) - global_position
	look.y = 0.0
	if look.length_squared() > 0.01:
		rotation.y = lerp_angle(rotation.y, atan2(-look.x, -look.z), 1.0 - exp(-6.0 * delta))


func set_asking(asking: bool, text_value: String = "") -> void:
	_asking = asking
	_speech.visible = asking
	_speech.text = text_value
	if not asking:
		_set_ring(CALM)


func _process(delta: float) -> void:
	_t += delta
	_body.position.y = sin(_t * 2.2) * 0.06
	_body.rotation.z = sin(_t * 1.3) * 0.05
	if _asking:
		# Blinken: rot / dunkelrot
		_set_ring(ALARM if fmod(_t, 0.5) < 0.3 else ALARM.darkened(0.6))


func _set_ring(color: Color) -> void:
	_ring_mat.albedo_color = color
	_ring_mat.emission = color
