class_name YardProps
extends Node3D
## Ausstattung des Hinterhofs: Bäume, Büsche, Bänke, Laternen, Paletten, Lieferwagen … (zone.json → props).
## Modelle aus Blender (tools/blender/prop_designs.py), ein MultiMesh je Modell, Kollision als Kisten.
## Einzelne Stücke stehen fest in `items`; Bäume und Büsche am Hofrand verteilt `ring` per Seed.

const MODEL_PATH := "res://assets/models/props/yard_props.glb"
## Kollisions-Kiste je Modell: Breite (x), Höhe, Tiefe (z); fehlt ein Modell, kann man hindurchlaufen
const COLLIDERS := {
	"TreeRound": Vector3(0.6, 3.0, 0.6), "TreePine": Vector3(0.5, 3.0, 0.5), "Planter": Vector3(1.2, 0.9, 1.2),
	"Bench": Vector3(1.9, 0.9, 0.6), "Lamp": Vector3(0.25, 3.7, 0.25), "PalletStack": Vector3(1.2, 1.1, 1.2),
	"Dumpster": Vector3(1.9, 1.2, 1.2), "CableDrum": Vector3(0.95, 1.5, 1.5), "Van": Vector3(2.1, 2.4, 5.3),
	"Fence": Vector3(3.0, 1.5, 0.12),
}

## [Modell, Position, Drehung in Grad, Größe]
var placed: Array[Array] = []


func build(city: CityWorld) -> void:
	var cfg: Dictionary = Balancing.zone.get("props", {})
	if cfg.is_empty() or not ResourceLoader.exists(MODEL_PATH):
		return
	for it: Dictionary in cfg.get("items", []):
		var p: Array = it["pos"]
		placed.append([String(it["model"]), Vector3(float(p[0]), 0.0, float(p[1])), float(it.get("rot", 0.0)), float(it.get("scale", 1.0))])
	_ring(cfg.get("ring", {}), city)

	var scene := load(MODEL_PATH) as PackedScene
	var root := scene.instantiate()
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.vertex_color_is_srgb = true  # Farben aus Blender sind sRGB-Werte
	mat.roughness = 0.7
	var body := StaticBody3D.new()
	body.name = "PropsBody"
	add_child(body)
	var by_model := {}
	for pr in placed:
		pr[1].y = city.ground_height(pr[1].x, pr[1].z)
		if not by_model.has(pr[0]):
			by_model[pr[0]] = []
		by_model[pr[0]].append(pr)
		if COLLIDERS.has(pr[0]):
			var size: Vector3 = COLLIDERS[pr[0]] * float(pr[3])
			var col := CollisionShape3D.new()
			var shape := BoxShape3D.new()
			shape.size = size
			col.shape = shape
			col.position = pr[1] + Vector3(0, size.y * 0.5, 0)
			col.rotation.y = deg_to_rad(pr[2])
			body.add_child(col)
	for model: String in by_model:
		var src := root.find_child(model, true, false) as MeshInstance3D
		if src == null:
			push_warning("Hof-Ausstattung: Modell %s fehlt" % model)
			continue
		var list: Array = by_model[model]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = src.mesh
		mm.instance_count = list.size()
		for i in list.size():
			var basis := Basis(Vector3.UP, deg_to_rad(list[i][2])).scaled(Vector3.ONE * float(list[i][3]))
			mm.set_instance_transform(i, Transform3D(basis, list[i][1]))
		var mmi := MultiMeshInstance3D.new()
		mmi.name = model
		mmi.multimesh = mm
		mmi.material_override = mat
		add_child(mmi)
	root.free()


## Steht hier schon etwas (mit Abstand `radius`)? Lieferungen sollen nicht auf der Ausstattung landen.
func blocked(pos: Vector3, radius: float) -> bool:
	for pr in placed:
		var p: Vector3 = pr[1]
		if Vector2(p.x - pos.x, p.z - pos.z).length() < radius + 1.5:
			return true
	return false


## Bäume und Büsche in einem Band um den Hof, nicht auf Straßen und nicht im Serverraum
func _ring(cfg: Dictionary, city: CityWorld) -> void:
	if cfg.is_empty():
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = int(cfg.get("seed", 1))
	var inner := float(cfg.get("inner_m", 48.0))
	var outer := float(cfg.get("outer_m", 62.0))
	var models: Array = cfg.get("models", ["TreeRound"])
	# Straßen des Viertels in Szenen-Koordinaten (dort bleibt es frei)
	var streets_x: Array = []
	var streets_z: Array = []
	var street_w := 14.0
	var d := city.district_at(0.0, 0.0)
	if not d.is_empty():
		var bo: Dictionary = d.get("blockout", {})
		var c := WorldLayout._v2(d["center"])
		var half := WorldLayout._v2(d["size"]) * 0.5
		street_w = float(bo.get("street_m", 14.0))
		for x: float in WorldLayout.grid_lines(c.x, half.x, float(bo.get("block_m", 90.0))):
			streets_x.append(x + city.offset.x)
		for z: float in WorldLayout.grid_lines(c.y, half.y, float(bo.get("block_m", 90.0))):
			streets_z.append(z + city.offset.z)
	var room := ServerRoomView.rect().grow(5.0)
	var tries := 0
	var count := int(cfg.get("count", 40))
	var done := 0
	while done < count and tries < count * 20:
		tries += 1
		# Punkt im quadratischen Band zwischen inner und outer
		var side := rng.randi_range(0, 3)
		var along := rng.randf_range(-outer, outer)
		var dist := rng.randf_range(inner, outer)
		var pos := Vector3(along, 0, -dist)
		match side:
			1: pos = Vector3(along, 0, dist)
			2: pos = Vector3(-dist, 0, along)
			3: pos = Vector3(dist, 0, along)
		var free := not room.has_point(Vector2(pos.x, pos.z)) and not blocked(pos, 2.0)
		for x: float in streets_x:
			free = free and absf(pos.x - x) > street_w * 0.5 + 1.5
		for z: float in streets_z:
			free = free and absf(pos.z - z) > street_w * 0.5 + 1.5
		if not free:
			continue
		placed.append([String(models[rng.randi_range(0, models.size() - 1)]), pos, rng.randf_range(0.0, 360.0),
			rng.randf_range(0.8, 1.25)])
		done += 1
