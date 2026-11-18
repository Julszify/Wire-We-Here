class_name PneumaticPost
extends Node3D
## Rohrpost-Station in einem Viertel: Knäuel einwerfen, sie landen direkt im Serverraum und werden eingesteckt.
## Steht gleich hinter dem Eingang des Viertels neben der Straße (Lage aus dem Viertel berechnet, world.json →
## pneumatic_post). Geht in Betrieb, sobald jemand zum ersten Mal in der Nähe ist. Nur Darstellung und Lage;
## das Einstecken macht world.gd. Platzhalter aus Grundformen (später ein Tripo-Modell).

var district_id := ""
var district_name := ""
var active := false
var _lamp: StandardMaterial3D
var _sign: Label3D
var _capsules: Array[Dictionary] = []  # { node, t }
var _tube_top := Vector3.ZERO


## Lage im Viertel bestimmen und aufbauen. Gibt false zurück, wenn das Viertel keine Station bekommt.
func setup(city: CityWorld, d: Dictionary) -> bool:
	var cfg: Dictionary = city.layout.raw().get("pneumatic_post", {})
	if (cfg.get("skip", []) as Array).has(String(d["id"])):
		return false
	district_id = String(d["id"])
	district_name = String(d.get("name", district_id))
	var at: Vector2
	if d.has("post"):
		at = WorldLayout._v2(d["post"])
	else:
		# Eingang: Lücke zum ersten Nachbarn im Zaun (ohne Zaun: Richtung Campus); von dort nach innen und zur Seite
		var exits: Array = d.get("wall", {}).get("exits", []) if d.get("wall") else []
		var toward := String(exits[0]) if not exits.is_empty() else String(cfg.get("default_toward", "campus"))
		var other := city.layout.district(toward)
		if other.is_empty():
			return false
		var gate := city.layout.exit_point(d, other)
		var inward := (WorldLayout._v2(d["center"]) - gate).normalized()
		var side := inward.orthogonal()
		# Am Straßenrand (Gehweg) der Einfahrtsstraße, damit sie nicht auf einem Grundstück landet
		var street := float(d.get("blockout", {}).get("street_m", 12.0))
		at = gate + inward * float(cfg.get("inside_m", 22.0)) + side * (street * 0.5 + float(cfg.get("side_m", 1.2)))
	var base := city.to_scene(at)
	global_position = base
	_build()
	set_active(false)
	return true


func set_active(on: bool) -> void:
	active = on
	var c := Color(0.3, 1.0, 0.45) if on else Color(1.0, 0.35, 0.3)
	if _lamp:
		_lamp.albedo_color = c
		_lamp.emission = c
	if _sign:
		_sign.text = "ROHRPOST\n%s" % ("→ Serverraum" if on else "außer Betrieb")


## Kapsel saust das Rohr hoch (beim Einwerfen)
func launch() -> void:
	var m := MeshInstance3D.new()
	var cap := CapsuleMesh.new()
	cap.radius = 0.16
	cap.height = 0.55
	m.mesh = cap
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.8, 0.2)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.7, 0.1)
	mat.emission_energy_multiplier = 2.0
	m.material_override = mat
	add_child(m)
	m.position = Vector3(0, 1.2, 0)
	_capsules.append({ "node": m, "t": 0.0 })


func _process(delta: float) -> void:
	for c in _capsules.duplicate():
		c["t"] = float(c["t"]) + delta
		var t := float(c["t"])
		var node: MeshInstance3D = c["node"]
		# Erst das Rohr hoch, dann oben im Bogen davon
		if t < 0.6:
			node.position = Vector3(0, lerpf(1.2, _tube_top.y, t / 0.6), 0)
		else:
			var u := (t - 0.6) / 0.5
			node.position = _tube_top + Vector3(0, u * 2.5, 0)  # oben aus dem Rohr hinaus
			node.scale = Vector3.ONE * maxf(1.0 - u, 0.01)
		if t > 1.1:
			node.queue_free()
			_capsules.erase(c)


const MODEL_PATH := "res://assets/models/props/room/tripo/rohrpoststation.glb"
const MODEL_HEIGHT := 2.9


## Tripo-Modell (falls vorhanden): auf echte Höhe, Fuß am Boden, schaut zur Straße. Sonst Grundformen.
func _build_model(body: StaticBody3D) -> bool:
	if not ResourceLoader.exists(MODEL_PATH):
		return false
	var m := (load(MODEL_PATH) as PackedScene).instantiate() as Node3D
	add_child(m)
	var box := ChefView._world_aabb(m)
	m.scale = Vector3.ONE * (MODEL_HEIGHT / maxf(box.size.y, 0.01))
	box = ChefView._world_aabb(m)
	m.position -= Vector3(box.get_center().x, box.position.y, box.get_center().z) - global_position
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(box.size.x * 0.7, MODEL_HEIGHT, box.size.z * 0.7)
	col.shape = shape
	col.position = Vector3(0, MODEL_HEIGHT * 0.5, 0)
	body.add_child(col)
	_tube_top = Vector3(0, MODEL_HEIGHT * 0.92, 0)
	return true


func _build() -> void:
	var body := StaticBody3D.new()
	add_child(body)
	var has_model := _build_model(body)
	var metal := _mat(Color(0.35, 0.55, 0.85))
	var dark := _mat(Color(0.2, 0.22, 0.27))
	if has_model:
		_build_signs(MODEL_HEIGHT)
		return
	# Sockel mit Einwurf-Klappe
	_box(Vector3(0, 0.6, 0), Vector3(1.2, 1.2, 1.0), metal, body)
	_box(Vector3(0, 1.0, 0.51), Vector3(0.7, 0.35, 0.04), dark, null)
	# Glasrohr nach oben, oben ein Bogen
	var glass := StandardMaterial3D.new()
	glass.albedo_color = Color(0.75, 0.9, 1.0, 0.35)
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.roughness = 0.1
	var tube := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.22
	cyl.bottom_radius = 0.22
	cyl.height = 4.2
	tube.mesh = cyl
	tube.material_override = glass
	tube.position = Vector3(0, 1.2 + 2.1, 0)
	add_child(tube)
	_tube_top = Vector3(0, 5.4, 0)
	for k in 3:
		_box(Vector3(0, 1.6 + k * 1.3, 0), Vector3(0.55, 0.12, 0.55), metal, null)
	var bend := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.5
	torus.outer_radius = 0.95
	bend.mesh = torus
	bend.material_override = metal
	bend.position = Vector3(0.72, 5.4, 0)
	bend.rotation = Vector3(PI * 0.5, 0, 0)
	add_child(bend)
	_build_signs(2.4)


## Lampe (rot außer Betrieb, grün in Betrieb) und Schild darüber
func _build_signs(top: float) -> void:
	_lamp = _mat(Color(1.0, 0.35, 0.3))
	_lamp.emission_enabled = true
	_lamp.emission_energy_multiplier = 2.0
	var lamp := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.16
	sphere.height = 0.32
	lamp.mesh = sphere
	lamp.material_override = _lamp
	lamp.position = Vector3(0, top * 0.55, 0.42)
	add_child(lamp)
	_sign = Label3D.new()
	_sign.font = UiTheme.font()
	_sign.font_size = 56
	_sign.outline_size = 14
	_sign.pixel_size = 0.006
	_sign.modulate = Color(1.0, 0.95, 0.7)
	_sign.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_sign.position = Vector3(0, top + 0.6, 0)
	add_child(_sign)


func _box(center: Vector3, size: Vector3, mat: Material, body: StaticBody3D) -> void:
	var mi := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = size
	mi.mesh = b
	mi.material_override = mat
	mi.position = center
	add_child(mi)
	if body:
		var col := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = size
		col.shape = shape
		col.position = center
		body.add_child(col)


static func _mat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.4
	return m
