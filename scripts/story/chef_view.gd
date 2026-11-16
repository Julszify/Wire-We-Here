class_name ChefView
extends Node3D
## Einer der drei Chefs der Wolkig AG. Lädt das Tripo-Modell `assets/models/chefs/tripo/chef_<id>.glb`, wenn es
## da ist (ca. 1 m hoch, schaut nach +Z, wird auf `height` skaliert); sonst eine rundliche Platzhalter-Figur aus
## Grundformen: zu enger Anzug, Krawatte. Kann reden (wippt) und lachen (hüpft).
##   grossspurig: dunkelblauer Anzug, rote Krawatte, am größten
##   jasager:     grauer Anzug, gelbe Krawatte, schmal
##   zahlen:      brauner Anzug, grüne Krawatte, Brille

const LOOKS := {
	"grossspurig": { "suit": Color(0.16, 0.2, 0.38), "tie": Color(0.85, 0.15, 0.15), "height": 1.75, "width": 1.25, "glasses": false },
	"jasager": { "suit": Color(0.5, 0.52, 0.56), "tie": Color(0.95, 0.8, 0.2), "height": 1.65, "width": 0.95, "glasses": false },
	"zahlen": { "suit": Color(0.42, 0.3, 0.2), "tie": Color(0.2, 0.6, 0.3), "height": 1.6, "width": 1.1, "glasses": true },
}

var chef_id := "grossspurig"
var talking := false
var _body: Node3D
var _t := 0.0
var _laugh_t := -1.0
var _anim: PlayerAnimator          # nur beim Tripo-Modell mit Skelett
var _was_talking := false


func setup(id: String) -> void:
	chef_id = id
	_body = Node3D.new()
	add_child(_body)
	if not _load_tripo():
		_build_placeholder()


## Kurz lachen (hüpfen und zurücklehnen)
func laugh() -> void:
	_laugh_t = 0.0
	if _anim:
		_anim.trigger("tug")  # lehnt sich lachend zurück


func _process(delta: float) -> void:
	_t += delta
	var y := 0.0
	var tilt := 0.0
	if talking:
		y = absf(sin(_t * 9.0)) * 0.03
		tilt = sin(_t * 4.0) * 0.05
	if _laugh_t >= 0.0:
		_laugh_t += delta
		y += absf(sin(_laugh_t * 14.0)) * 0.08 * maxf(0.0, 1.0 - _laugh_t)
		tilt -= 0.15 * maxf(0.0, 1.0 - _laugh_t)
		if _laugh_t > 1.0:
			_laugh_t = -1.0
	_body.position.y = y
	_body.rotation.x = tilt
	if _anim:
		if talking and not _was_talking:
			_anim.trigger("reach")  # Geste zum Satzanfang
		_was_talking = talking
		_anim.speed = 0.0
		_anim.update(delta)


func _load_tripo() -> bool:
	var path := "res://assets/models/chefs/tripo/chef_%s.glb" % chef_id
	if not ResourceLoader.exists(path):
		return false
	var scene := load(path) as PackedScene
	if scene == null:
		return false
	var model := scene.instantiate() as Node3D
	_body.add_child(model)
	# Größe aus den Meshes in Weltlage (das Skelett kann im Modell skaliert sein)
	var aabb := _world_aabb(model)
	var h := float(LOOKS[chef_id]["height"])
	var k := h / maxf(aabb.size.y, 0.01)
	model.scale = Vector3.ONE * k
	aabb = _world_aabb(model)
	model.global_position -= Vector3(aabb.get_center().x - global_position.x, aabb.position.y - global_position.y,
		aabb.get_center().z - global_position.z)
	# Mixamo-Skelett: Arme aus der T-Pose holen, atmen, schauen (derselbe Animator wie beim Admin)
	var skels := model.find_children("*", "Skeleton3D", true, false)
	if not skels.is_empty():
		var skel := skels[0] as Skeleton3D
		var chain := Basis()
		var n: Node = skel
		while n != model and n != null:
			if n is Node3D:
				chain = (n as Node3D).transform.basis * chain
			n = n.get_parent()
		var anim := PlayerAnimator.new()
		if anim.setup(skel, model, chain.orthonormalized().inverse()):
			_anim = anim
			_anim.update(0.0)
	return true


static func _world_aabb(root: Node3D) -> AABB:
	var out := AABB()
	var first := true
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		var box := m.global_transform * m.get_aabb()
		if first:
			out = box
			first = false
		else:
			out = out.merge(box)
	return out


func _build_placeholder() -> void:
	var look: Dictionary = LOOKS[chef_id]
	var h := float(look["height"])
	var w := float(look["width"])
	var suit := _mat(look["suit"])
	var skin := _mat(Color(0.96, 0.78, 0.66))
	var shirt := _mat(Color(0.95, 0.95, 0.95))
	var dark := _mat(Color(0.08, 0.08, 0.1))
	# Beine
	for side in [-1.0, 1.0]:
		_add(_capsule(0.13, h * 0.42), suit, Vector3(side * 0.16 * w, h * 0.2, 0))
		_add(_box(Vector3(0.2, 0.1, 0.34)), dark, Vector3(side * 0.16 * w, 0.05, 0.06))
	# Bauch im zu engen Anzug
	var belly := _add(_sphere(0.42 * w, 0.62 * h * 0.85), suit, Vector3(0, h * 0.55, 0))
	belly.scale = Vector3(1.0, 1.0, 0.9)
	# Hemd und Krawatte vorn
	_add(_box(Vector3(0.22 * w, 0.32, 0.05)), shirt, Vector3(0, h * 0.68, 0.36 * w))
	_add(_box(Vector3(0.09, 0.36, 0.04)), _mat(look["tie"]), Vector3(0, h * 0.62, 0.39 * w))
	# Arme
	for side in [-1.0, 1.0]:
		var arm := _add(_capsule(0.1, h * 0.36), suit, Vector3(side * 0.44 * w, h * 0.55, 0.05))
		arm.rotation.z = side * 0.25
		_add(_sphere(0.09, 0.18), skin, Vector3(side * 0.52 * w, h * 0.38, 0.1))
	# Kopf
	var head_y := h * 0.86
	_add(_sphere(0.24, 0.46), skin, Vector3(0, head_y, 0.02))
	for side in [-1.0, 1.0]:
		_add(_sphere(0.035, 0.07), dark, Vector3(side * 0.08, head_y + 0.04, 0.22))
	_add(_box(Vector3(0.14, 0.025, 0.02)), _mat(Color(0.55, 0.25, 0.22)), Vector3(0, head_y - 0.09, 0.22))
	_add(_sphere(0.22, 0.2), _mat(Color(0.35, 0.25, 0.2)), Vector3(0, head_y + 0.15, -0.02))  # Haare
	if bool(look["glasses"]):
		for side in [-1.0, 1.0]:
			var lens := _add(_cylinder(0.06, 0.02), _mat(Color(0.75, 0.9, 1.0)), Vector3(side * 0.08, head_y + 0.04, 0.24))
			lens.rotation.x = PI * 0.5


func _add(mesh: Mesh, mat: Material, pos: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	_body.add_child(mi)
	return mi


static func _capsule(r: float, h: float) -> CapsuleMesh:
	var m := CapsuleMesh.new()
	m.radius = r
	m.height = h
	return m


static func _sphere(r: float, h: float) -> SphereMesh:
	var m := SphereMesh.new()
	m.radius = r
	m.height = h
	return m


static func _box(size: Vector3) -> BoxMesh:
	var m := BoxMesh.new()
	m.size = size
	return m


static func _cylinder(r: float, h: float) -> CylinderMesh:
	var m := CylinderMesh.new()
	m.top_radius = r
	m.bottom_radius = r
	m.height = h
	return m


static func _mat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.6
	return m
