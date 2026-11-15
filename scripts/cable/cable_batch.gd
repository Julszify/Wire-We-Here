class_name CableBatch
extends Node3D
## Bis zu 256 ruhende Kabel als ein gemeinsames Mesh (statt eines Meshes je Kabel).
## Drei Detailstufen (nah, mittel, fern) nach Entfernung zur Kamera; die Röhren formt der Shader
## (assets/shaders/cable_batch.gdshader), die CPU legt nur die Mittellinien ab. Die ferne Stufe ist immer da,
## nah und mittel baut CableBatcher bei Bedarf in Hintergrund-Threads.
## Gegriffene und fertige Kabel werden über eine kleine Textur ausgeblendet (ein Pixel je Kabel);
## ein Neubau ist dafür nicht nötig. Liest CableData nur, verändert sie nie.

enum Lod { NEAR, MID, FAR }
const MAX_CABLES := 256

var key: String = ""                  # Besitzer (Einheit oder "zone"), zum gemeinsamen Entfernen
var cables: Array[CableData] = []
var extent := 0.0                     # Ausdehnung um den Ursprung (für die Entfernungsstufen)
var lod_ready: Array[bool] = [false, false, false]
var lod_pending: Array[bool] = [false, false, false]

var _local: Dictionary = {}           # Kabel-ID -> Nummer im Block
var _hidden: Image
var _tex: ImageTexture
var _tube_mat: ShaderMaterial
var _plug_mat: ShaderMaterial
var _lods: Array[MeshInstance3D] = [null, null, null]
var _shadow: MeshInstance3D           # wirft in der Nähe den Schatten (gröbere mittlere Stufe, spart Dreiecke)

static var _tube_shader: Shader
static var _plug_shader: Shader


func setup(owner_key: String, list: Array[CableData], origin: Vector3, size: float) -> void:
	key = owner_key
	cables = list
	extent = size
	position = origin
	for i in list.size():
		_local[list[i].id] = i
	_hidden = Image.create(MAX_CABLES, 1, false, Image.FORMAT_R8)
	_tex = ImageTexture.create_from_image(_hidden)
	if _tube_shader == null:
		_tube_shader = load("res://assets/shaders/cable_batch.gdshader")
		_plug_shader = load("res://assets/shaders/cable_batch_plug.gdshader")
	_tube_mat = ShaderMaterial.new()
	_tube_mat.shader = _tube_shader
	_tube_mat.set_shader_parameter("hidden_tex", _tex)
	_plug_mat = ShaderMaterial.new()
	_plug_mat.shader = _plug_shader
	_plug_mat.set_shader_parameter("hidden_tex", _tex)


func has_cable(cable_id: int) -> bool:
	return _local.has(cable_id)


## Kabel aus- oder wieder einblenden (gegriffen, losgelassen, fertig)
func set_hidden(cable_id: int, hidden: bool) -> void:
	var i: int = _local.get(cable_id, -1)
	if i < 0:
		return
	_hidden.set_pixel(i, 0, Color(1, 0, 0) if hidden else Color(0, 0, 0))
	_tex.update(_hidden)


func is_hidden(cable_id: int) -> bool:
	var i: int = _local.get(cable_id, -1)
	return i >= 0 and _hidden.get_pixel(i, 0).r > 0.5


## Gebaute Arrays einer Stufe übernehmen (Hauptthread)
func apply_lod(lod: int, arrays: Dictionary) -> void:
	lod_pending[lod] = false
	drop_lod(lod)
	var mesh := ArrayMesh.new()
	var tube: Array = arrays["tube"]
	if (tube[Mesh.ARRAY_VERTEX] as PackedVector3Array).is_empty():
		lod_ready[lod] = true
		return
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, tube)
	mesh.surface_set_material(0, _tube_mat)
	if arrays.has("plugs"):
		var plugs: Array = arrays["plugs"]
		if not (plugs[Mesh.ARRAY_VERTEX] as PackedVector3Array).is_empty():
			mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, plugs)
			mesh.surface_set_material(1, _plug_mat)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.extra_cull_margin = 0.3  # Röhre ist dicker als die Mittellinie im Mesh
	# Schatten wirft nur die Schatten-Kopie der mittleren Stufe (siehe update_ranges)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	_lods[lod] = mi
	lod_ready[lod] = true
	update_ranges()


func drop_lod(lod: int) -> void:
	if _lods[lod]:
		_lods[lod].queue_free()
		_lods[lod] = null
	lod_ready[lod] = false


## Sichtbereiche der Stufen; fehlt eine feinere Stufe, springt die gröbere ein
func update_ranges() -> void:
	var cfg: Array = Balancing.cable_batch["lods"]
	var near_end := float(cfg[0]["show_m"]) + extent * 0.6
	var mid_end := float(cfg[1]["show_m"]) + extent
	var far_end := float(cfg[2]["show_m"]) + extent * 6.0
	var begin := 0.0
	var ends := [near_end, mid_end, far_end]
	for lod in 3:
		var mi := _lods[lod]
		if mi == null:
			continue
		mi.visibility_range_begin = begin
		mi.visibility_range_end = ends[lod]
		mi.visibility_range_begin_margin = 2.0 if begin > 0.0 else 0.0
		mi.visibility_range_end_margin = 2.0
		begin = ends[lod]
	# Schatten der nahen Kabel: die mittlere Stufe als reiner Schattenwerfer im Nahbereich
	var want_shadow := _lods[Lod.NEAR] != null and _lods[Lod.MID] != null \
		and bool(cfg[0].get("shadows", false))
	if want_shadow:
		if _shadow == null:
			_shadow = MeshInstance3D.new()
			_shadow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
			_shadow.extra_cull_margin = 0.3
			add_child(_shadow)
		_shadow.mesh = _lods[Lod.MID].mesh
		_shadow.visibility_range_end = near_end
		_shadow.visibility_range_end_margin = 2.0
	elif _shadow:
		_shadow.queue_free()
		_shadow = null


# ------------------------------------------------------------ Aufbau (auch in Threads)

## Nur die Werte, die das Mesh braucht. Packed-Arrays werden nicht kopiert, nur geteilt (Copy on Write):
## dreht der Hauptthread später eine Bahn um, behält der Thread seine Fassung.
static func snapshot(list: Array) -> Dictionary:
	var pts: Array[PackedVector3Array] = []
	var colors := PackedColorArray()
	var radii := PackedFloat32Array()
	var plugs := PackedStringArray()
	var rolls := PackedFloat32Array()
	for c: CableData in list:
		pts.append(c.path.points)
		var col := c.color().srgb_to_linear()
		colors.append(col)
		radii.append(c.radius())
		plugs.append(c.plug_id())
		rolls.append(float(posmod(c.rng_seed, 628)) / 100.0)
	return { "points": pts, "colors": colors, "radii": radii, "plugs": plugs, "rolls": rolls }


## Mesh-Arrays einer Stufe aus einem snapshot(). Reine Rechnung, threadsicher.
static func build_arrays(src: Dictionary, origin: Vector3, lod: int) -> Dictionary:
	var cfg: Dictionary = Balancing.cable_batch["lods"][lod]
	var step := maxi(1, int(cfg["step"]))
	var sides := maxi(3, int(cfg["sides"]))
	var with_plugs := bool(cfg.get("plugs", false))
	# Ferne Stufen etwas dicker: dünne Kabel flimmern sonst, wenn sie schmaler als ein Pixel werden
	var thick := float(cfg.get("radius_scale", 1.0))
	var all_pts: Array = src["points"]
	var colors: PackedColorArray = src["colors"]
	var radii: PackedFloat32Array = src["radii"]

	# Größe vorab bestimmen, dann ohne append füllen (deutlich schneller)
	var total_v := 0
	var total_i := 0
	for p: PackedVector3Array in all_pts:
		var m := _sample_count(p.size(), step)
		total_v += m * sides
		total_i += (m - 1) * sides * 6
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var cols := PackedColorArray()
	var idx := PackedInt32Array()
	verts.resize(total_v)
	normals.resize(total_v)
	uvs.resize(total_v)
	cols.resize(total_v)
	idx.resize(total_i)

	var vi := 0
	var ii := 0
	for li in all_pts.size():
		var pts: PackedVector3Array = all_pts[li]
		var n := pts.size()
		if n < 2:
			continue
		var col := colors[li]
		col.a = float(li) / 255.0
		var r := radii[li] * thick
		var m := _sample_count(n, step)
		var base := vi
		for j in m:
			var i0 := mini(j * step, n - 1)
			var t := pts[mini(i0 + 1, n - 1)] - pts[maxi(i0 - 1, 0)]
			t = t.normalized() if t.length_squared() > 1e-12 else Vector3.FORWARD
			var p := pts[i0] - origin
			for s in sides:
				verts[vi] = p
				normals[vi] = t
				uvs[vi] = Vector2(float(s) / sides, r)
				cols[vi] = col
				vi += 1
		for j in m - 1:
			var a := base + j * sides
			var b := a + sides
			for s in sides:
				var s1 := (s + 1) % sides
				idx[ii] = a + s
				idx[ii + 1] = b + s
				idx[ii + 2] = a + s1
				idx[ii + 3] = a + s1
				idx[ii + 4] = b + s
				idx[ii + 5] = b + s1
				ii += 6
	var tube := []
	tube.resize(Mesh.ARRAY_MAX)
	tube[Mesh.ARRAY_VERTEX] = verts
	tube[Mesh.ARRAY_NORMAL] = normals
	tube[Mesh.ARRAY_TEX_UV] = uvs
	tube[Mesh.ARRAY_COLOR] = cols
	tube[Mesh.ARRAY_INDEX] = idx
	var out := { "tube": tube }
	if with_plugs:
		var pv := PackedVector3Array()
		var pn := PackedVector3Array()
		var pc := PackedColorArray()
		var pu := PackedVector2Array()
		var pi := PackedInt32Array()
		var plugs: PackedStringArray = src["plugs"]
		var rolls: PackedFloat32Array = src["rolls"]
		for li in all_pts.size():
			if plugs[li] != "":
				PlugMeshes.append_ends(plugs[li], all_pts[li], rolls[li], origin, li, pv, pn, pc, pu, pi)
		var plug_arrays := []
		plug_arrays.resize(Mesh.ARRAY_MAX)
		plug_arrays[Mesh.ARRAY_VERTEX] = pv
		plug_arrays[Mesh.ARRAY_NORMAL] = pn
		plug_arrays[Mesh.ARRAY_COLOR] = pc
		plug_arrays[Mesh.ARRAY_TEX_UV] = pu
		plug_arrays[Mesh.ARRAY_INDEX] = pi
		out["plugs"] = plug_arrays
	return out


## Anzahl der Stützpunkte bei jedem `step`-ten Punkt (letzter Punkt immer dabei)
static func _sample_count(n: int, step: int) -> int:
	if n < 2:
		return 0
	return int(ceil(float(n - 1) / step)) + 1


## Teilt Gruppen ruhender Kabel in Blöcke: große Gruppen (Haufen) werden geteilt, kleine (Straßenkabel,
## kleine Haufen) nach Lage in Zellen zusammengefasst. groups: [{ "indices": PackedInt32Array,
## "center": Vector3, "radius": float }]. Ergebnis: [{ "indices", "origin", "extent" }]
static func plan(groups: Array, cell_m: float = -1.0) -> Array:
	if cell_m <= 0.0:
		cell_m = float(Balancing.cable_batch.get("cell_m", 25.0))
	var out: Array = []
	var buckets: Dictionary = {}  # Zelle -> [indices, Summe der Mitten, Anzahl Gruppen, Mitten+Radien]
	for g: Dictionary in groups:
		var ids: PackedInt32Array = g["indices"]
		var center: Vector3 = g["center"]
		var radius := float(g["radius"])
		if ids.size() >= 64:
			var k := 0
			while k < ids.size():
				out.append({ "indices": ids.slice(k, mini(k + MAX_CABLES, ids.size())), "origin": center,
					"extent": radius * 1.6 })
				k += MAX_CABLES
			continue
		var cell := Vector2i(floori(center.x / cell_m), floori(center.z / cell_m))
		if not buckets.has(cell):
			buckets[cell] = [PackedInt32Array(), Vector3.ZERO, 0, []]
		var bk: Array = buckets[cell]
		var merged: PackedInt32Array = bk[0]
		merged.append_array(ids)
		bk[0] = merged  # Packed-Arrays sind Werte: zurückschreiben
		bk[1] += center
		bk[2] += 1
		(bk[3] as Array).append([center, radius])
		if merged.size() >= MAX_CABLES - 64:
			out.append(_flush(bk))
			buckets.erase(cell)
	for bk: Array in buckets.values():
		out.append(_flush(bk))
	return out


static func _flush(bk: Array) -> Dictionary:
	var origin: Vector3 = bk[1] / float(bk[2])
	var ext := 0.0
	for cr: Array in bk[3]:
		ext = maxf(ext, origin.distance_to(cr[0]) + float(cr[1]) * 1.3)
	return { "indices": bk[0], "origin": origin, "extent": ext }
