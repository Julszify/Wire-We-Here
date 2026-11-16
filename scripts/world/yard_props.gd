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
	"Fence": Vector3(3.0, 1.5, 0.12), "TreeAutumn": Vector3(0.6, 3.0, 0.6), "Rock": Vector3(1.1, 1.1, 1.1),
	"LampOld": Vector3(0.25, 3.4, 0.25),
}

## Modelle aus Tripo3D (assets/models/props/tripo/, übernommen mit tools/blender/import_tripo_props.py).
## Gibt es sie, ersetzen sie das Blender-Teil gleichen Namens; mehrere Varianten werden je Standort gewählt.
## Höhe in Metern (die Modelle kommen ca. 1 m groß an), Drehung in Grad, damit die Vorderseite stimmt.
const TRIPO_DIR := "res://assets/models/props/tripo/"
const TRIPO := {
	"TreeRound": { "files": ["baum_gruen_1", "baum_gruen_2", "baum_gruen_3", "baum_gruen_4"], "height": 6.0 },
	"TreePine": { "files": ["nadelbaum_1", "nadelbaum_2"], "height": 7.0 },
	"TreeAutumn": { "files": ["herbstbaum"], "height": 6.0 },
	"Bush": { "files": ["busch_1", "busch_2"], "height": 1.4 },
	"Planter": { "files": ["blumenkuebel_1", "blumenkuebel_2"], "height": 1.6 },
	"Rock": { "files": ["felsen"], "height": 1.3 },
	"Lamp": { "files": ["laterne_modern"], "height": 4.0, "turn": -90.0, "glow": [0.36, 0.86] },
	"LampOld": { "files": ["laterne_alt"], "height": 3.6, "glow": [0.0, 0.84] },
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

	for pr in placed:
		pr[1].y = city.ground_height(pr[1].x, pr[1].z)
	var body := StaticBody3D.new()
	body.name = "PropsBody"
	add_child(body)
	add_items(self, body, placed)


## Stücke aufstellen: [Modell, Position (mit Bodenhöhe), Drehung in Grad, Größe] je Stück; ein MultiMesh je Modell
## bzw. Tripo-Variante, Kollision als Kisten in `body` (null = keine). Mit `chunk_m` > 0 wird nach Kacheln
## getrennt und ab `range_m` ausgeblendet (für weit verteilte Stücke wie im Umland).
static func add_items(parent: Node3D, body: StaticBody3D, items: Array, chunk_m := 0.0, range_m := 0.0) -> void:
	if items.is_empty():
		return
	var tripo := _tripo_variants()
	var by_model := {}
	for pr in items:
		var key := String(pr[0])
		if chunk_m > 0.0:
			var p: Vector3 = pr[1]
			key += "@%d,%d" % [floori(p.x / chunk_m), floori(p.z / chunk_m)]
		if not by_model.has(key):
			by_model[key] = []
		by_model[key].append(pr)
		if body and COLLIDERS.has(pr[0]):
			var size: Vector3 = COLLIDERS[pr[0]] * float(pr[3])
			var col := CollisionShape3D.new()
			var shape := BoxShape3D.new()
			shape.size = size
			col.shape = shape
			col.position = pr[1] + Vector3(0, size.y * 0.5, 0)
			col.rotation.y = deg_to_rad(pr[2])
			body.add_child(col)
	var root: Node = null
	for key: String in by_model:
		var model := key.get_slice("@", 0)
		var list: Array = by_model[key]
		var nodes: Array[GeometryInstance3D] = []
		if tripo.has(model):
			nodes = _add_tripo(parent, model, tripo[model], list)
		else:
			if root == null:
				if not ResourceLoader.exists(MODEL_PATH):
					continue
				root = (load(MODEL_PATH) as PackedScene).instantiate()
			var src := root.find_child(model, true, false) as MeshInstance3D
			if src == null:
				push_warning("Ausstattung: Modell %s fehlt" % model)
				continue
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.mesh = src.mesh
			mm.instance_count = list.size()
			for i in list.size():
				mm.set_instance_transform(i, _place_xf(list[i]))
			var mmi := MultiMeshInstance3D.new()
			mmi.name = model
			mmi.multimesh = mm
			mmi.material_override = _blender_material()
			parent.add_child(mmi)
			nodes.append(mmi)
		if range_m > 0.0:
			for n in nodes:
				n.visibility_range_end = range_m
				n.visibility_range_end_margin = range_m * 0.1
				n.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	if root:
		root.free()


static var _blender_mat: StandardMaterial3D
static func _blender_material() -> StandardMaterial3D:
	if _blender_mat == null:
		_blender_mat = StandardMaterial3D.new()
		_blender_mat.vertex_color_use_as_albedo = true
		_blender_mat.vertex_color_is_srgb = true  # Farben aus Blender sind sRGB-Werte
		_blender_mat.roughness = 0.7
	return _blender_mat


static var _tripo_cache: Dictionary = {}
static var _tripo_loaded := false
static func _tripo_variants() -> Dictionary:
	if not _tripo_loaded:
		_tripo_cache = _load_tripo()
		_tripo_loaded = true
	return _tripo_cache


## Tripo-Varianten laden: Teilname -> [[Mesh, Normalisierung (auf Höhe, Fuß bei 0, zentriert)], …]
static func _load_tripo() -> Dictionary:
	var out := {}
	for model: String in TRIPO:
		var cfg: Dictionary = TRIPO[model]
		var variants := []
		for f: String in cfg["files"]:
			var path := TRIPO_DIR + f + ".glb"
			if not ResourceLoader.exists(path):
				continue
			var root := (load(path) as PackedScene).instantiate()
			var mis := root.find_children("*", "MeshInstance3D", true, false)
			if mis.is_empty():
				root.free()
				continue
			var mi := mis[0] as MeshInstance3D
			# Lage des Meshes im Modell (Knoten können verschoben oder gedreht sein)
			var node_xf := Transform3D.IDENTITY
			var n: Node = mi
			while n != root and n != null:
				if n is Node3D:
					node_xf = (n as Node3D).transform * node_xf
				n = n.get_parent()
			var box := node_xf * mi.mesh.get_aabb()
			var k := float(cfg["height"]) / maxf(box.size.y, 0.001)
			var base := Vector3(box.get_center().x, box.position.y, box.get_center().z)
			var norm := Transform3D(Basis(Vector3.UP, deg_to_rad(float(cfg.get("turn", 0.0)))).scaled(Vector3.ONE * k), Vector3.ZERO) \
				* Transform3D(Basis.IDENTITY, -base) * node_xf
			variants.append([mi.mesh, norm, box.size * k])
			root.free()
		if not variants.is_empty():
			out[model] = variants
	return out


## Ein MultiMesh je Tripo-Variante; Laternen bekommen ein kleines Leuchtteil am Lampenkopf
static func _add_tripo(parent: Node3D, model: String, variants: Array, list: Array) -> Array[GeometryInstance3D]:
	var out: Array[GeometryInstance3D] = []
	var cfg: Dictionary = TRIPO[model]
	var per := []
	for v in variants:
		per.append([])
	for pr in list:
		var pos: Vector3 = pr[1]
		per[posmod(hash([roundi(pos.x * 10.0), roundi(pos.z * 10.0)]), variants.size())].append(pr)
	var glow_mat: StandardMaterial3D = null
	if cfg.has("glow"):
		glow_mat = StandardMaterial3D.new()
		glow_mat.albedo_color = Color(1.0, 0.9, 0.6)
		glow_mat.emission_enabled = true
		glow_mat.emission = Color(1.0, 0.85, 0.5)
		glow_mat.emission_energy_multiplier = 2.5
	for vi in variants.size():
		var items: Array = per[vi]
		if items.is_empty():
			continue
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = variants[vi][0]
		mm.instance_count = items.size()
		for i in items.size():
			mm.set_instance_transform(i, _place_xf(items[i]) * (variants[vi][1] as Transform3D))
		var mmi := MultiMeshInstance3D.new()
		mmi.name = "%s_%d" % [model, vi + 1]
		mmi.multimesh = mm
		parent.add_child(mmi)
		out.append(mmi)
		if glow_mat:
			# Leuchtkugel am Lampenkopf: Lage als Anteil der Breite (seitlich) und Höhe
			var size: Vector3 = variants[vi][2]
			var g: Array = cfg["glow"]
			var bulb := SphereMesh.new()
			bulb.radius = 0.13
			bulb.height = 0.26
			bulb.material = glow_mat
			for it in items:
				var mi := MeshInstance3D.new()
				mi.mesh = bulb
				mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				parent.add_child(mi)
				out.append(mi)
				mi.transform = _place_xf(it) * Transform3D(Basis.IDENTITY,
					Vector3(0, float(g[1]) * size.y, float(g[0]) * maxf(size.x, size.z)))
	return out


static func _place_xf(pr: Array) -> Transform3D:
	var basis := Basis(Vector3.UP, deg_to_rad(float(pr[2]))).scaled(Vector3.ONE * float(pr[3]))
	return Transform3D(basis, pr[1])


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
