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
var _material: StandardMaterial3D


func build(world_layout: WorldLayout) -> void:
	layout = world_layout
	_material = StandardMaterial3D.new()
	_material.vertex_color_use_as_albedo = true
	_material.vertex_color_is_srgb = true  # Farben oben sind sRGB-Werte, sonst wirken sie fast weiß
	_material.roughness = 0.8
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
	st.set_color(color)
	st.set_normal(Vector3.UP)
	for i in steps:
		var q0 := a.lerp(b, float(i) / steps)
		var q1 := a.lerp(b, float(i + 1) / steps)
		var l0 := _ground(q0 + side)
		var r0 := _ground(q0 - side)
		var l1 := _ground(q1 + side)
		var r1 := _ground(q1 - side)
		st.add_vertex(l0); st.add_vertex(r1); st.add_vertex(r0)
		st.add_vertex(l0); st.add_vertex(l1); st.add_vertex(r1)


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
	for x in xs:
		_box(ctx, Vector3(x, y + STREET_TOP - 0.1, c.y), Vector3(street, 0.2, half.y * 2.0), STREET_COLOR, false)
	for z in zs:
		_box(ctx, Vector3(c.x, y + STREET_TOP - 0.1, z), Vector3(half.x * 2.0, 0.2, street), STREET_COLOR, false)

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
				_lot(ctx, r, h)
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


## Ein Gebäude auf einem Grundstück (überspringt Grundstücke auf Hauptstraßen)
func _lot(ctx: Dictionary, r: Rect2, height: float) -> void:
	if r.size.x < 3.0 or r.size.y < 3.0:
		return
	var center := r.get_center()
	if _near_main_road(center, r.size.length() * 0.5):
		return
	var y: float = ctx["y"]
	var shade := ctx["rng"].randf_range(0.66, 0.82) as float
	var color := Color(shade, shade, shade + 0.02)
	_box(ctx, Vector3(center.x, y + (height - BASE_DEPTH) * 0.5, center.y),
		Vector3(r.size.x, height + BASE_DEPTH, r.size.y), color, true)
	building_count += 1


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
	var stand := 28.0
	var grey := Color(0.7, 0.7, 0.73)
	# Spielfeld (grün, ohne Kollision)
	_box(ctx, Vector3(c.x, y + 0.05, c.y), Vector3(field.x, 0.2, field.y), Color(0.3, 0.55, 0.3), false)
	# Tribünen als gestufte Kisten (zwei Stufen je Seite, außen höher)
	for step in 2:
		var off := stand * (0.25 + 0.5 * step)
		var sh := h * (0.55 + 0.45 * step)
		for side in [-1.0, 1.0]:
			_solid(ctx, Vector3(c.x, y + sh * 0.5, c.y + side * (field.y * 0.5 + off)),
				Vector3(field.x + stand * 2.0, sh, stand * 0.5), grey)
			_solid(ctx, Vector3(c.x + side * (field.x * 0.5 + off), y + sh * 0.5, c.y),
				Vector3(stand * 0.5, sh, field.y), grey)


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
			Color(0.35, 0.6, 0.9), true)
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = _material
	body.add_child(mi)
	add_child(body)


# ---------------------------------------------------------------- Kisten

func _solid(ctx: Dictionary, center: Vector3, size: Vector3, color: Color) -> void:
	_box(ctx, center, size, color, true)
	building_count += 1


## Kiste ins Mesh des Viertels; mit Kollision als BoxShape am StaticBody des Viertels
func _box(ctx: Dictionary, center: Vector3, size: Vector3, color: Color, collide: bool) -> void:
	var st: SurfaceTool = ctx["st"]
	st.set_color(color)
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
		var col := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = size
		col.shape = shape
		col.position = center
		(ctx["body"] as StaticBody3D).add_child(col)
