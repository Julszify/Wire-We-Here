class_name CityBlockout
extends Node3D
## Grobe Stadt aus grauen Blöcken (Blockout), erzeugt aus data/world.json:
##   - Hauptstraßen zwischen den Vierteln (Band, das dem Gelände folgt)
##   - Straßenraster je Viertel (Mittelachsen sind immer Straßen, dort kommen die Hauptstraßen an)
##   - Gebäude als Kisten auf den Grundstücken zwischen den Straßen, Stil je Viertel
## Deterministisch (Seed je Viertel). Pro Viertel ein Mesh und ein StaticBody mit Kisten-Kollision.

const ROAD_LIFT := 0.12        # Hauptstraßen knapp über dem Boden
const STREET_TOP := 0.03       # Straßen in den Vierteln (flach, damit Kabel darauf sichtbar bleiben)
const BASE_DEPTH := 3.0        # Gebäude reichen so tief in den Boden (keine Lücken an Rampen)
const STREET_COLOR := Color(0.32, 0.33, 0.36)
const ROAD_COLOR := Color(0.27, 0.28, 0.31)

var layout: WorldLayout
var building_count := 0
var _roads: Array[PackedVector2Array] = []  # Hauptstraßen als 2D-Linien (für Abstandstests)
var _road_w := 12.0
var _material: ShaderMaterial
const BLOCKOUT_SHADER := "res://assets/shaders/blockout.gdshader"
## Farben der Gebäude, wenn ein Viertel keine eigene `palette` hat
const DEFAULT_PALETTE := ["#d9dde3", "#c9d3df", "#e6e1d6", "#cfd8d2"]
## Hausmodelle aus Blender (tools/blender/building_designs.py): Einheitsmodelle 1 x 1 x 1 m, Vorderseite +Z
const HOUSES_PATH := "res://assets/models/buildings/houses.glb"
var _house_meshes: Array[Mesh] = []
var _house_material: StandardMaterial3D
## Gebäude-Bausatz aus Blender (tools/blender/building_kit.py): Dächer, Aufbauten, Markisen, Schilder
const KIT_PATH := "res://assets/models/buildings/kit.glb"
const KIT_SHADER := "res://assets/shaders/kit.gdshader"
## Fassadenstil (blockout.gdshader, UV2.x) je Name aus world.json → blockout.kit.facade
const FACADES := { "grid": 0, "office": 1, "altstadt": 2, "shop": 3, "warehouse": 4, "datacenter": 5, "tower": 6 }
var _kit_meshes: Dictionary = {}  # Teilname -> Mesh
var _kit_material: ShaderMaterial
var kit_count := 0


func build(world_layout: WorldLayout) -> void:
	layout = world_layout
	# Ein Shader für alles: Fenster auf Gebäuden, Linien auf Straßen (siehe blockout.gdshader)
	_material = ShaderMaterial.new()
	_material.shader = load(BLOCKOUT_SHADER)
	_build_main_roads()
	for d in layout.districts:
		_build_district(d)
	_build_landmarks()


# ---------------------------------------------------------------- Hauptstraßen

func _build_main_roads() -> void:
	var roads: Dictionary = layout.raw().get("roads", {})
	_road_w = float(roads.get("width_m", 12.0))
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for link: Array in roads.get("links", []):
		var a := layout.district(String(link[0]))
		var b := layout.district(String(link[1]))
		if a.is_empty() or b.is_empty():
			continue
		var p0 := layout.exit_point(a, b)
		var p1 := layout.exit_point(b, a)
		var line := PackedVector2Array([p0, p1])
		_roads.append(line)
		_add_ribbon(st, p0, p1, _road_w, ROAD_COLOR)
	var mi := MeshInstance3D.new()
	mi.name = "MainRoads"
	mi.mesh = st.commit()
	mi.material_override = _material
	add_child(mi)


## Straßenband von a nach b, alle 2 m (= Rasterweite des Geländes) an die Geländehöhe angepasst
func _add_ribbon(st: SurfaceTool, a: Vector2, b: Vector2, width: float, color: Color) -> void:
	var length := a.distance_to(b)
	var steps := maxi(1, ceili(length / 2.0))
	var side := (b - a).normalized().orthogonal() * width * 0.5
	st.set_color(Color(color, 0.1))
	st.set_normal(Vector3.UP)
	for i in steps:
		var q0 := a.lerp(b, float(i) / steps)
		var q1 := a.lerp(b, float(i + 1) / steps)
		var l0 := _ground(q0 + side)
		var r0 := _ground(q0 - side)
		var l1 := _ground(q1 + side)
		var r1 := _ground(q1 - side)
		var m0 := length * float(i) / steps
		var m1 := length * float(i + 1) / steps
		# UV: Lage quer (-1 … 1) und längs in Metern, für Mittel- und Randlinien
		for v: Array in [[l0, 1.0, m0], [r1, -1.0, m1], [r0, -1.0, m0], [l0, 1.0, m0], [l1, 1.0, m1], [r1, -1.0, m1]]:
			st.set_uv(Vector2(v[1], v[2]))
			st.add_vertex(v[0])


## Punkt knapp über dem Gelände; an Hängen etwas höher, damit das Band nicht im Boden verschwindet
func _ground(p: Vector2) -> Vector3:
	var h := layout.height(p.x, p.y)
	var slope := absf(layout.height(p.x + 2.0, p.y) - h) + absf(layout.height(p.x, p.y + 2.0) - h)
	return Vector3(p.x, maxf(h, 0.0) + ROAD_LIFT + slope * 0.5, p.y)


func _near_main_road(center: Vector2, radius: float) -> bool:
	for line in _roads:
		if Geometry2D.get_closest_point_to_segment(center, line[0], line[1]).distance_to(center) < radius + _road_w * 0.5 + 2.0:
			return true
	return false


# ---------------------------------------------------------------- Viertel

func _build_district(d: Dictionary) -> void:
	var bo: Dictionary = d.get("blockout", {})
	if bo.is_empty():
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([d["id"], "blockout"])
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var body := StaticBody3D.new()
	body.name = "Blockout_%s" % d["id"]
	var ctx := { "d": d, "bo": bo, "rng": rng, "st": st, "body": body, "y": float(d["height_m"]) }
	# Viertel mit "models": "houses" bekommen Hausmodelle statt grauer Kisten (Kollision bleibt die Kiste)
	if String(bo.get("models", "")) == "houses" and _load_houses():
		ctx["houses"] = []
	elif bo.has("kit") and _load_kit():
		ctx["kit"] = {}
	if d.has("wall"):
		_build_wall(ctx)
	match String(bo.get("style", "grid")):
		"grid", "towers", "warehouse":
			_style_grid(ctx)
		"stadium":
			_style_stadium(ctx)
		"harbor":
			_style_harbor(ctx)
		"crater":
			_style_crater(ctx)
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = _material
	body.add_child(mi)
	add_child(body)
	if ctx.has("houses"):
		_build_houses(body, ctx["houses"])
	if ctx.has("kit"):
		_build_kit(body, ctx["kit"])


## Hausmodelle laden (einmal); false, wenn die Datei fehlt
func _load_houses() -> bool:
	if not _house_meshes.is_empty():
		return true
	if not ResourceLoader.exists(HOUSES_PATH):
		return false
	var scene := load(HOUSES_PATH) as PackedScene
	if scene == null:
		return false
	var root := scene.instantiate()
	for child in root.find_children("House*", "MeshInstance3D", true, false):
		_house_meshes.append((child as MeshInstance3D).mesh)
	root.free()
	_house_material = StandardMaterial3D.new()
	_house_material.vertex_color_use_as_albedo = true
	_house_material.vertex_color_is_srgb = true  # Farben aus Blender sind sRGB-Werte
	_house_material.roughness = 0.75
	return not _house_meshes.is_empty()


## Ein MultiMesh je Hausmodell: [Modell-Index, Transform, Farbton] je Haus
func _build_houses(parent: Node3D, houses: Array) -> void:
	for v in _house_meshes.size():
		var list := houses.filter(func(h: Array) -> bool: return int(h[0]) == v)
		if list.is_empty():
			continue
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.mesh = _house_meshes[v]
		mm.instance_count = list.size()
		for i in list.size():
			mm.set_instance_transform(i, list[i][1])
			mm.set_instance_color(i, list[i][2])
		var mmi := MultiMeshInstance3D.new()
		mmi.name = "Houses%d" % (v + 1)
		mmi.multimesh = mm
		mmi.material_override = _house_material
		parent.add_child(mmi)


## Straßenraster: Straßen auf den Mittelachsen und im Abstand block_m; dazwischen Grundstücke
func _style_grid(ctx: Dictionary) -> void:
	var d: Dictionary = ctx["d"]
	var bo: Dictionary = ctx["bo"]
	var rng: RandomNumberGenerator = ctx["rng"]
	var c := WorldLayout._v2(d["center"])
	var half := WorldLayout._v2(d["size"]) * 0.5
	var block := float(bo["block_m"])
	var street := float(bo["street_m"])
	var y: float = ctx["y"]
	var style := String(bo["style"])

	# Straßen (Linien in x und z durch die Mitte, dann im Raster nach außen)
	var xs := WorldLayout.grid_lines(c.x, half.x, block)
	var zs := WorldLayout.grid_lines(c.y, half.y, block)
	# Alpha 0.2 / 0.3 = Straße entlang z / x; UV = Mittelachse und Breite (für die Mittellinie),
	# UV2 = Lage der Kreuzungen längs (Ursprung, Abstand): dort setzen Linie und Gehweg aus
	for x in xs:
		_box(ctx, Vector3(x, y + STREET_TOP - 0.1, c.y), Vector3(street, 0.2, half.y * 2.0), Color(STREET_COLOR, 0.2),
			false, Vector2(x, street), Vector2(c.y, block))
	for z in zs:
		_box(ctx, Vector3(c.x, y + STREET_TOP - 0.09, z), Vector3(half.x * 2.0, 0.2, street), Color(STREET_COLOR, 0.3),
			false, Vector2(z, street), Vector2(c.x, block))

	# Grundstücke zwischen den Straßen
	var bounds_x := [c.x - half.x] + xs + [c.x + half.x]
	var bounds_z := [c.y - half.y] + zs + [c.y + half.y]
	for i in bounds_x.size() - 1:
		for j in bounds_z.size() - 1:
			var x0: float = bounds_x[i] + street * 0.5 + 3.0
			var x1: float = bounds_x[i + 1] - street * 0.5 - 3.0
			var z0: float = bounds_z[j] + street * 0.5 + 3.0
			var z1: float = bounds_z[j + 1] - street * 0.5 - 3.0
			if x1 - x0 < 8.0 or z1 - z0 < 8.0:
				continue
			var cell := Rect2(x0, z0, x1 - x0, z1 - z0)
			if _is_kept_free(bo, cell):
				continue
			match style:
				"towers":
					_tower_block(ctx, cell)
				"warehouse":
					_lot(ctx, cell.grow(-4.0), rng.randf_range(float(bo["h_min"]), float(bo["h_max"])))
				_:
					_fill_block(ctx, cell)


## Block mit mehreren Häusern am Rand entlang (Hof in der Mitte), Lücken nach fill
func _fill_block(ctx: Dictionary, cell: Rect2) -> void:
	var bo: Dictionary = ctx["bo"]
	var rng: RandomNumberGenerator = ctx["rng"]
	var lot_min := float(bo["lot_min"])
	var lot_max := float(bo["lot_max"])
	var depth := minf(lot_max, minf(cell.size.x, cell.size.y) * 0.5)
	# Reihen an Nord- und Südseite, dann an West- und Ostseite (zwischen den Ecken)
	for edge in 4:
		var horizontal := edge < 2
		var along := cell.size.x if horizontal else cell.size.y - 2.0 * depth
		var t := 0.0
		while t < along - lot_min * 0.6:
			var w := minf(rng.randf_range(lot_min, lot_max), along - t)
			if rng.randf() < float(bo["fill"]):
				var h := rng.randf_range(float(bo["h_min"]), float(bo["h_max"]))
				var r: Rect2
				match edge:
					0: r = Rect2(cell.position.x + t, cell.position.y, w - 1.0, depth)
					1: r = Rect2(cell.position.x + t, cell.end.y - depth, w - 1.0, depth)
					2: r = Rect2(cell.position.x, cell.position.y + depth + t, depth, w - 1.0)
					_: r = Rect2(cell.end.x - depth, cell.position.y + depth + t, depth, w - 1.0)
				_lot(ctx, r, h, edge)
			t += w


## Hochhaus-Block: ein Turm in der Mitte, Sockel drumherum
func _tower_block(ctx: Dictionary, cell: Rect2) -> void:
	var bo: Dictionary = ctx["bo"]
	var rng: RandomNumberGenerator = ctx["rng"]
	if rng.randf() > float(bo["fill"]):
		return
	var size := rng.randf_range(float(bo["lot_min"]), float(bo["lot_max"]))
	var tower := Rect2(cell.get_center() - Vector2(size, size) * 0.5, Vector2(size, size))
	_lot(ctx, tower, rng.randf_range(float(bo["h_min"]), float(bo["h_max"])))
	_lot(ctx, cell.grow(-6.0), 8.0)  # Sockelgeschoss


## Ein Gebäude auf einem Grundstück (überspringt Grundstücke auf Hauptstraßen).
## `edge` = Seite des Blocks, an der es steht (0 Nord, 1 Süd, 2 West, 3 Ost); die Haustür zeigt zur Straße.
func _lot(ctx: Dictionary, r: Rect2, height: float, edge: int = 1) -> void:
	if r.size.x < 3.0 or r.size.y < 3.0:
		return
	var center := r.get_center()
	if _near_main_road(center, r.size.length() * 0.5):
		return
	var y: float = ctx["y"]
	var shade := ctx["rng"].randf_range(0.66, 0.82) as float
	# Farbe aus der Palette des Viertels (per Lage gewählt), leicht abgedunkelt; Alpha 0.5 = Gebäude
	var palette: Array = ctx["bo"].get("palette", DEFAULT_PALETTE) if ctx.has("bo") else DEFAULT_PALETTE
	var pick := Color.html(String(palette[posmod(hash([roundi(center.x), roundi(center.y), "farbe"]), palette.size())]))
	var color := Color(pick.darkened((0.82 - shade) * 0.9), 0.5)
	var box_center := Vector3(center.x, y + (height - BASE_DEPTH) * 0.5, center.y)
	var box_size := Vector3(r.size.x, height + BASE_DEPTH, r.size.y)
	building_count += 1
	if not ctx.has("houses"):
		var kit: Dictionary = ctx["bo"].get("kit", {}) if ctx.has("bo") else {}
		var facade := float(FACADES.get(String(kit.get("facade", "grid")), 0))
		_box(ctx, box_center, box_size, color, true, Vector2(y, height), Vector2(facade, 0.0))
		if ctx.has("kit"):
			_decorate(ctx, r, y, height, edge)
		return
	# Hausmodell: Kollision als Kiste, Darstellung als Instanz im MultiMesh
	_collider(ctx, box_center, box_size)
	var angle: float = [PI, 0.0, -PI * 0.5, PI * 0.5][edge]
	var along := r.size.x if edge < 2 else r.size.y
	var deep := r.size.y if edge < 2 else r.size.x
	var basis := Basis(Vector3.UP, angle) * Basis.from_scale(Vector3(along, height, deep))
	var variant := posmod(hash([roundi(center.x), roundi(center.y)]), _house_meshes.size())
	var tint := 0.82 + (shade - 0.66) / 0.16 * 0.18
	(ctx["houses"] as Array).append([variant, Transform3D(basis, Vector3(center.x, y, center.y)), Color(tint, tint, tint)])


# ---------------------------------------------------------------- Bausatz

func _load_kit() -> bool:
	if not _kit_meshes.is_empty():
		return true
	if not ResourceLoader.exists(KIT_PATH):
		return false
	var scene := load(KIT_PATH) as PackedScene
	if scene == null:
		return false
	var root := scene.instantiate()
	for child in root.find_children("*", "MeshInstance3D", true, false):
		_kit_meshes[String(child.name)] = (child as MeshInstance3D).mesh
	root.free()
	_kit_material = ShaderMaterial.new()
	_kit_material.shader = load(KIT_SHADER)
	return not _kit_meshes.is_empty()


func _kit_add(ctx: Dictionary, part: String, xf: Transform3D, color := Color.WHITE) -> void:
	if not _kit_meshes.has(part):
		return
	var kit: Dictionary = ctx["kit"]
	if not kit.has(part):
		kit[part] = []
	(kit[part] as Array).append([xf, color])
	kit_count += 1


## Gewichtete Auswahl aus [[Name, Gewicht], …] mit einer Zufallszahl 0..1
static func _pick(list: Array, x: float) -> String:
	var total := 0.0
	for e: Array in list:
		total += float(e[1])
	x *= total
	for e: Array in list:
		x -= float(e[1])
		if x <= 0.0:
			return String(e[0])
	return String(list[-1][0])


static func _pick_color(list: Array, x: float, fallback: Color) -> Color:
	if list.is_empty():
		return fallback
	return Color.html(String(list[clampi(int(x * list.size()), 0, list.size() - 1)]))


## Dach, Dachaufbauten und Fassadenschmuck für ein Gebäude (Regeln aus blockout.kit in world.json).
## `edge` = Blockseite, an der das Gebäude steht; die Vorderseite zeigt zur Straße.
func _decorate(ctx: Dictionary, r: Rect2, y: float, height: float, edge: int) -> void:
	var kit: Dictionary = ctx["bo"]["kit"]
	var rng := RandomNumberGenerator.new()
	var c2 := r.get_center()
	rng.seed = hash([roundi(c2.x * 10.0), roundi(c2.y * 10.0), "kit"])
	var angle: float = [PI, 0.0, -PI * 0.5, PI * 0.5][edge]
	var rot := Basis(Vector3.UP, angle)
	var along := r.size.x if edge < 2 else r.size.y
	var deep := r.size.y if edge < 2 else r.size.x
	var top := y + height
	var center := Vector3(c2.x, top, c2.y)
	var front := rot * Vector3(0, 0, 1)
	var side := rot * Vector3(1, 0, 0)

	# Dach
	var roof := _pick(kit.get("roofs", [["RoofParapet", 1]]), rng.randf())
	var roof_col := _pick_color(kit.get("roof_palette", []), rng.randf(), Color(0.85, 0.86, 0.88))
	var roof_h := 1.0
	match roof:
		"RoofGable", "RoofHip", "RoofMansard":
			roof_h = clampf(minf(along, deep) * 0.38, 2.5, 7.0)
		"RoofSawtooth":
			roof_h = 2.4
	_kit_add(ctx, roof, Transform3D(rot * Basis.from_scale(Vector3(along, roof_h, deep)), center), roof_col)
	var flat := roof == "RoofParapet"

	# Aufbauten auf Flachdächern (Anzahl nach Fläche), Schornsteine auf geneigten Dächern
	var props: Array = kit.get("props", [])
	if flat and not props.is_empty() and along > 6.0 and deep > 6.0:
		var n := clampi(int(along * deep / 140.0 * float(kit.get("prop_density", 1.0))), 1, 7)
		for i in n:
			var part := _pick(props, rng.randf())
			var p := center + side * rng.randf_range(-along * 0.5 + 2.5, along * 0.5 - 2.5) \
				+ front * rng.randf_range(-deep * 0.5 + 2.5, deep * 0.5 - 2.5) + Vector3(0, 0.08, 0)
			var turn := Basis(Vector3.UP, angle + PI * 0.5 * rng.randi_range(0, 3))
			if part == "Billboard":
				# Werbetafel an der Straßenseite, Bild zur Straße
				p = center + front * (deep * 0.5 - 1.5) + side * rng.randf_range(-along * 0.25, along * 0.25)
				turn = Basis(Vector3.UP, angle + PI)
			_kit_add(ctx, part, Transform3D(turn, p), _pick_color(kit.get("neon_palette", []), rng.randf(), Color.WHITE))
	elif not flat and rng.randf() < float(kit.get("chimney_chance", 0.0)):
		var cp := center + side * rng.randf_range(-along * 0.3, along * 0.3) + front * deep * 0.12
		cp.y += roof_h * 0.55
		_kit_add(ctx, "Chimney", Transform3D(rot, cp))
	if flat and height > float(kit.get("helipad_min_h", 9999.0)) and rng.randf() < float(kit.get("helipad_chance", 0.0)) \
			and minf(along, deep) > 14.0:
		_kit_add(ctx, "Helipad", Transform3D(rot, center + Vector3(0, 0.1, 0)))

	# Erdgeschoss zur Straße: Markise und Ladenschild, Leuchtschild an der Ecke
	var facade := center - Vector3(0, height, 0) + front * deep * 0.5
	if rng.randf() < float(kit.get("awning_chance", 0.0)):
		var w := along * rng.randf_range(0.5, 0.8)
		_kit_add(ctx, "Awning", Transform3D(rot * Basis.from_scale(Vector3(w, 0.9, 1.4)), facade + Vector3(0, 2.7, 0)),
			_pick_color(kit.get("awning_palette", []), rng.randf(), Color(0.8, 0.3, 0.25)))
	if rng.randf() < float(kit.get("shop_sign_chance", 0.0)):
		_kit_add(ctx, "ShopSign", Transform3D(rot * Basis.from_scale(Vector3(along * 0.6, 0.9, 1.0)),
			facade + Vector3(0, 3.5, 0)), _pick_color(kit.get("neon_palette", []), rng.randf(), Color.WHITE))
	if height > 8.0 and rng.randf() < float(kit.get("neon_chance", 0.0)):
		var corner := facade + side * along * 0.5 * (1.0 if rng.randf() < 0.5 else -1.0) * 0.85
		_kit_add(ctx, "NeonSign", Transform3D(rot, corner + Vector3(0, rng.randf_range(4.5, minf(height - 4.0, 9.0)), 0)),
			_pick_color(kit.get("neon_palette", []), rng.randf(), Color.WHITE))


## Ein MultiMesh je Bausatz-Teil
func _build_kit(parent: Node3D, kit: Dictionary) -> void:
	for part: String in kit:
		var list: Array = kit[part]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_custom_data = true
		mm.mesh = _kit_meshes[part]
		mm.instance_count = list.size()
		for i in list.size():
			mm.set_instance_transform(i, list[i][0])
			mm.set_instance_custom_data(i, list[i][1])  # Farbe je Gebäude (kit.gdshader)
		var mmi := MultiMeshInstance3D.new()
		mmi.name = "Kit_%s" % part
		mmi.multimesh = mm
		mmi.material_override = _kit_material
		parent.add_child(mmi)


func _is_kept_free(bo: Dictionary, cell: Rect2) -> bool:
	for k: Array in bo.get("keep_free", []):
		var free := Rect2(float(k[0]) - float(k[2]) * 0.5, float(k[1]) - float(k[3]) * 0.5, float(k[2]), float(k[3]))
		if free.intersects(cell):
			return true
	return false


## Zaun am Rand des Viertels mit Lücken zu den Vierteln in wall.exits (dort liegen die Sperren)
func _build_wall(ctx: Dictionary) -> void:
	var d: Dictionary = ctx["d"]
	var w: Dictionary = d["wall"]
	var c := WorldLayout._v2(d["center"])
	var half := WorldLayout._v2(d["size"]) * 0.5
	var y: float = ctx["y"]
	var h := float(w["height_m"])
	var t := float(w["thickness_m"])
	var gap := float(w["gap_m"])
	var gaps: Array[Vector2] = []
	for exit_id: String in w.get("exits", []):
		gaps.append(layout.exit_point(d, layout.district(exit_id)))
	var color := Color(0.55, 0.57, 0.6)
	var corners := [c + Vector2(-half.x, -half.y), c + Vector2(half.x, -half.y), c + Vector2(half.x, half.y),
		c + Vector2(-half.x, half.y)]
	for i in 4:
		var a: Vector2 = corners[i]
		var b: Vector2 = corners[(i + 1) % 4]
		# Abschnitte zwischen den Lücken auf dieser Seite
		var cuts: Array[float] = [0.0]
		var length := a.distance_to(b)
		for g in gaps:
			if Geometry2D.get_closest_point_to_segment(g, a, b).distance_to(g) < 0.5:
				var tg := a.distance_to(g)
				cuts.append(tg - gap * 0.5)
				cuts.append(tg + gap * 0.5)
		cuts.append(length)
		var dir := (b - a) / length
		for k in range(0, cuts.size(), 2):
			var s0: float = cuts[k]
			var s1: float = cuts[k + 1]
			if s1 - s0 < 0.5:
				continue
			var mid := a + dir * (s0 + s1) * 0.5
			var size := Vector3(absf(dir.x) * (s1 - s0) + absf(dir.y) * t, h, absf(dir.y) * (s1 - s0) + absf(dir.x) * t)
			_box(ctx, Vector3(mid.x, y + h * 0.5 - 0.3, mid.y), size + Vector3(0, 0.6, 0), color, true)


# ---------------------------------------------------------------- Sonderformen

## Stadion: vier Tribünen um ein Spielfeld, dazu Nebengebäude
func _style_stadium(ctx: Dictionary) -> void:
	var d: Dictionary = ctx["d"]
	var c := WorldLayout._v2(d["center"])
	var y: float = ctx["y"]
	var h := float(ctx["bo"]["h_max"])
	var field := Vector2(110, 75)
	if _load_kit():
		ctx["kit"] = {}
		for sx in [-1.0, 1.0]:
			for sz in [-1.0, 1.0]:
				var corner := Vector3(c.x + sx * (field.x * 0.5 + 34.0), y, c.y + sz * (field.y * 0.5 + 34.0))
				_kit_add(ctx, "Floodlight", Transform3D(Basis(Vector3.UP, atan2(sx, sz) + PI), corner))
	var stand := 28.0
	var grey := Color(0.88, 0.88, 0.9)
	var seats := Color(0.85, 0.27, 0.22)
	# Spielfeld (grün, ohne Kollision)
	_box(ctx, Vector3(c.x, y + 0.05, c.y), Vector3(field.x, 0.2, field.y), Color(0.3, 0.55, 0.3), false)
	# Tribünen als gestufte Kisten (zwei Stufen je Seite, außen höher)
	for step in 2:
		var off := stand * (0.25 + 0.5 * step)
		var sh := h * (0.55 + 0.45 * step)
		for side in [-1.0, 1.0]:
			var col := seats if step == 0 else grey
			_solid(ctx, Vector3(c.x, y + sh * 0.5, c.y + side * (field.y * 0.5 + off)),
				Vector3(field.x + stand * 2.0, sh, stand * 0.5), col)
			_solid(ctx, Vector3(c.x + side * (field.x * 0.5 + off), y + sh * 0.5, c.y),
				Vector3(stand * 0.5, sh, field.y), col)


## Hafen: Lagerhallen in einer Reihe, Kräne an der Kaimauer
func _style_harbor(ctx: Dictionary) -> void:
	var d: Dictionary = ctx["d"]
	var rng: RandomNumberGenerator = ctx["rng"]
	var c := WorldLayout._v2(d["center"])
	var half := WorldLayout._v2(d["size"]) * 0.5
	var y: float = ctx["y"]
	var basin: Dictionary = layout.raw()["harbor_basin"]
	var quay_z := float(basin["center"][1]) - float(basin["size"][1]) * 0.5
	var bc := float(basin["center"][0])
	var bw := float(basin["size"][0])
	# Lagerhallen im nördlichen Teil
	var x := c.x - half.x + 20.0
	while x < c.x + half.x - 40.0:
		var w := rng.randf_range(40.0, 60.0)
		_lot(ctx, Rect2(x, c.y - half.y + 15.0, w, 45.0), rng.randf_range(float(ctx["bo"]["h_min"]), float(ctx["bo"]["h_max"])))
		x += w + 14.0
	# Kräne an der Kaimauer: Turm + Ausleger über das Becken
	var crane := Color(0.85, 0.55, 0.15)
	for i in 4:
		var cx := bc - bw * 0.5 + bw * (i + 0.5) / 4.0
		var cz := quay_z - 10.0
		_solid(ctx, Vector3(cx, y + 20.0, cz), Vector3(5, 40, 5), crane)
		_box(ctx, Vector3(cx, y + 40.0, cz + 18.0), Vector3(3, 3, 50), crane, true)


## Krater: Rechenzentrums-Hallen auf dem Kraterboden
func _style_crater(ctx: Dictionary) -> void:
	var cr: Dictionary = layout.raw()["crater"]
	var c := WorldLayout._v2(cr["center"])
	var y := float(cr["floor_m"])
	ctx["y"] = y
	var rng: RandomNumberGenerator = ctx["rng"]
	for i in 3:
		for j in 2:
			var p := c + Vector2((i - 1) * 42.0, (j - 0.5) * 40.0)
			_lot(ctx, Rect2(p - Vector2(15, 12), Vector2(30, 24)), rng.randf_range(float(ctx["bo"]["h_min"]), float(ctx["bo"]["h_max"])))


# ---------------------------------------------------------------- Landmarken

## Landmarken aus world.json als Kisten (vorerst nur der Wolkig-Turm)
func _build_landmarks() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var body := StaticBody3D.new()
	body.name = "Landmarks"
	var ctx := { "st": st, "body": body }
	for l in layout.landmarks:
		var pos := WorldLayout._v2(l["pos"])
		var s: Array = l["size"]
		var size := Vector3(float(s[0]), float(s[1]), float(s[2]))
		var y := layout.height(pos.x, pos.y)
		_box(ctx, Vector3(pos.x, y + (size.y - BASE_DEPTH) * 0.5, pos.y), size + Vector3(0, BASE_DEPTH, 0),
			Color(0.35, 0.6, 0.9, 0.5), true, Vector2(y, size.y), Vector2(FACADES["tower"], 0.0))
		if _load_kit():
			if not ctx.has("kit"):
				ctx["kit"] = {}
			var roof_y := y + size.y
			_kit_add(ctx, "RoofParapet", Transform3D(Basis.from_scale(Vector3(size.x, 1.2, size.z)), Vector3(pos.x, roof_y, pos.y)),
				Color(0.85, 0.9, 0.95))
			_kit_add(ctx, "Antenna", Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * 2.5), Vector3(pos.x + 6.0, roof_y, pos.y - 6.0)))
			_kit_add(ctx, "Helipad", Transform3D(Basis.IDENTITY, Vector3(pos.x - 4.0, roof_y + 0.1, pos.y + 4.0)))
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = _material
	body.add_child(mi)
	add_child(body)
	if ctx.has("kit"):
		_build_kit(body, ctx["kit"])


# ---------------------------------------------------------------- Kisten

func _solid(ctx: Dictionary, center: Vector3, size: Vector3, color: Color) -> void:
	_box(ctx, center, size, color, true)
	building_count += 1


## Kiste ins Mesh des Viertels; mit Kollision als BoxShape am StaticBody des Viertels
func _box(ctx: Dictionary, center: Vector3, size: Vector3, color: Color, collide: bool, uv := Vector2.ZERO,
		uv2 := Vector2.ZERO) -> void:
	var st: SurfaceTool = ctx["st"]
	st.set_color(color)
	st.set_uv(uv)
	st.set_uv2(uv2)
	var h := size * 0.5
	var faces := [
		[Vector3.UP, Vector3(-h.x, h.y, -h.z), Vector3(h.x, h.y, -h.z), Vector3(h.x, h.y, h.z), Vector3(-h.x, h.y, h.z)],
		[Vector3.DOWN, Vector3(-h.x, -h.y, h.z), Vector3(h.x, -h.y, h.z), Vector3(h.x, -h.y, -h.z), Vector3(-h.x, -h.y, -h.z)],
		[Vector3.FORWARD, Vector3(h.x, -h.y, -h.z), Vector3(h.x, h.y, -h.z), Vector3(-h.x, h.y, -h.z), Vector3(-h.x, -h.y, -h.z)],
		[Vector3.BACK, Vector3(-h.x, -h.y, h.z), Vector3(-h.x, h.y, h.z), Vector3(h.x, h.y, h.z), Vector3(h.x, -h.y, h.z)],
		[Vector3.LEFT, Vector3(-h.x, -h.y, -h.z), Vector3(-h.x, h.y, -h.z), Vector3(-h.x, h.y, h.z), Vector3(-h.x, -h.y, h.z)],
		[Vector3.RIGHT, Vector3(h.x, -h.y, h.z), Vector3(h.x, h.y, h.z), Vector3(h.x, h.y, -h.z), Vector3(h.x, -h.y, -h.z)],
	]
	for f in faces:
		st.set_normal(f[0])
		var a: Vector3 = center + f[1]
		var b: Vector3 = center + f[2]
		var cc: Vector3 = center + f[3]
		var dd: Vector3 = center + f[4]
		# Godot: Vorderseite im Uhrzeigersinn
		st.add_vertex(a); st.add_vertex(b); st.add_vertex(cc)
		st.add_vertex(a); st.add_vertex(cc); st.add_vertex(dd)
	if collide:
		_collider(ctx, center, size)


func _collider(ctx: Dictionary, center: Vector3, size: Vector3) -> void:
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	col.shape = shape
	col.position = center
	(ctx["body"] as StaticBody3D).add_child(col)
