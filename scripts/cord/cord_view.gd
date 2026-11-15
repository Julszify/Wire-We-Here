class_name CordView
extends Node3D
## C.O.R.D.: schwebende Figur mit Leuchtteilen, folgt dem Spieler.
## Verwendet das Tripo-Modell (TRIPO_PATH), sonst den Blender-Entwurf „Server-Box“ (MODEL_PATH), sonst einen Platzhalter.
## Alle Teile mit dem Material „CordRing“ leuchten cyan; während der Bestellfrage blinken sie rot.

var _ring_mat: StandardMaterial3D
var _body: Node3D
var _speech: Label3D
var _asking := false
var _t := 0.0

const CALM := Color(0.3, 0.9, 1.0)
const ALARM := Color(1.0, 0.2, 0.15)
const MODEL_PATH := "res://assets/models/cord/cord_server.glb"
## In Tripo3D erzeugtes Modell (eine Textur, ca. 1 m hoch). Hat Vorrang; der Leuchtring liegt dort in der
## Textur, deshalb kommt ein eigenes Leuchtband darüber, das blinken kann.
const TRIPO_PATH := "res://assets/models/cord/tripo/cord_tripo.glb"
const TRIPO_HEIGHT := 0.8
## Lage des Bands im Modell (Anteil der Höhe von unten) und seine Höhe (Anteil der Höhe)
const TRIPO_BAND_Y := 0.43
const TRIPO_BAND_H := 0.11
const RING_MATERIAL := "CordRing"


func _ready() -> void:
	_body = Node3D.new()
	add_child(_body)

	_ring_mat = StandardMaterial3D.new()
	_ring_mat.albedo_color = CALM
	_ring_mat.emission_enabled = true
	_ring_mat.emission = CALM
	_ring_mat.emission_energy_multiplier = 3.0

	if not _build_tripo() and not _build_model():
		_build_placeholder()

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


## Lädt das Modell (Maße in Metern) und zentriert es um den Ursprung.
## glTF-Modelle schauen nach +Z, C.O.R.D. schaut nach -Z, daher um 180° gedreht.
## Leuchtmaterialien werden durch _ring_mat ersetzt, damit sie die Farbe wechseln können.
func _build_model() -> bool:
	if not ResourceLoader.exists(MODEL_PATH):
		return false
	var scene := load(MODEL_PATH) as PackedScene
	if scene == null:
		return false
	var model: Node3D = scene.instantiate()
	var holder := Node3D.new()
	holder.rotation = Vector3(0, PI, 0)
	holder.add_child(model)
	_body.add_child(holder)
	model.position = -_mesh_aabb(model, Transform3D.IDENTITY).get_center()
	_swap_ring_materials(model)
	return true


## Tripo-Modell laden, auf TRIPO_HEIGHT verkleinern, zentrieren, Leuchtband darüberlegen
func _build_tripo() -> bool:
	if not ResourceLoader.exists(TRIPO_PATH):
		return false
	var scene := load(TRIPO_PATH) as PackedScene
	if scene == null:
		return false
	var model: Node3D = scene.instantiate()
	var box := _mesh_aabb(model, Transform3D.IDENTITY)
	if box.size.y <= 0.0:
		model.free()
		return false
	var k := TRIPO_HEIGHT / box.size.y
	var holder := Node3D.new()
	holder.rotation = Vector3(0, PI, 0)
	holder.scale = Vector3.ONE * k
	holder.add_child(model)
	_body.add_child(holder)
	model.position = -box.get_center()
	# Leuchtband: vier flache Leisten knapp außerhalb des Gehäuses (im Modell-Raum, vor dem Verkleinern)
	var y := box.position.y + box.size.y * TRIPO_BAND_Y - box.get_center().y
	var h := box.size.y * TRIPO_BAND_H
	var hx := box.size.x * 0.5 * 0.955
	var hz := box.size.z * 0.5 * 0.955
	var t := 0.012
	for spec in [[Vector3(0, y, hz), Vector3(hx * 2.0, h, t)], [Vector3(0, y, -hz), Vector3(hx * 2.0, h, t)],
			[Vector3(hx, y, 0), Vector3(t, h, hz * 2.0)], [Vector3(-hx, y, 0), Vector3(t, h, hz * 2.0)]]:
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = spec[1]
		bm.material = _ring_mat
		mi.mesh = bm
		mi.position = spec[0]
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		holder.add_child(mi)
	return true


func _swap_ring_materials(node: Node) -> void:
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		for i in mi.mesh.get_surface_count():
			var m := mi.mesh.surface_get_material(i)
			if m and m.resource_name == RING_MATERIAL:
				mi.set_surface_override_material(i, _ring_mat)
	for child in node.get_children():
		_swap_ring_materials(child)


## Begrenzungsbox aller Meshes unter node, im Koordinatensystem von node.
func _mesh_aabb(node: Node, xform: Transform3D) -> AABB:
	var result := AABB()
	var has := false
	for child in node.get_children():
		var t := xform
		if child is Node3D:
			t = xform * (child as Node3D).transform
		var boxes: Array[AABB] = []
		if child is MeshInstance3D and (child as MeshInstance3D).mesh:
			boxes.append(t * (child as MeshInstance3D).mesh.get_aabb())
		var sub := _mesh_aabb(child, t)
		if sub.size != Vector3.ZERO:
			boxes.append(sub)
		for b in boxes:
			result = b if not has else result.merge(b)
			has = true
	return result


## Platzhalter aus Grundformen, falls das Modell fehlt.
func _build_placeholder() -> void:
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
