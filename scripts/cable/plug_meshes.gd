class_name PlugMeshes
extends RefCounted
## Stecker-Geometrie für die Kabelenden (aus assets/models/cable/plugs.glb, erzeugt mit
## tools/blender/plug_designs.py). Die Stecker werden nicht als eigene Nodes gesetzt, sondern als
## zweite Fläche in das Kabel-Mesh geschrieben: so kosten 1000 Stecker keine 1000 Draw Calls.
## Im Modell liegt der Ursprung am Kabelende, der Stecker zeigt nach -Z. Farben = Vertex-Farben.

const MODEL_PATH := "res://assets/models/cable/plugs.glb"
## Vereinfachte Stecker (ca. 120 Dreiecke) für die Blöcke ruhender Kabel (tools/blender/plug_lod.py)
const LOD_PATH := "res://assets/models/cable/plugs_lod.glb"

static var _arrays: Dictionary = {}  # Steckertyp -> [Vertices, Normalen, Farben, Indizes]
static var _lod_arrays: Dictionary = {}
static var _loaded := false
static var _material: StandardMaterial3D


static func has_plug(plug_id: String) -> bool:
	_load()
	return _arrays.has(plug_id)


## Gemeinsames Material aller Stecker (Farbe aus den Vertex-Farben)
static func material() -> StandardMaterial3D:
	if _material == null:
		_material = StandardMaterial3D.new()
		_material.vertex_color_use_as_albedo = true
		_material.roughness = 0.3
		_material.metallic = 0.1
		_material.clearcoat_enabled = true
		_material.clearcoat = 0.4
	return _material


## Hängt eine Fläche mit zwei Steckern an `mesh`: einen an jedem Ende von `pts`.
## Gibt den Index der neuen Fläche zurück (-1, wenn es diesen Steckertyp nicht gibt).
static func add_to_mesh(mesh: ArrayMesh, plug_id: String, pts: PackedVector3Array, roll: float) -> int:
	_load()
	var n := pts.size()
	if n < 2 or not _arrays.has(plug_id):
		return -1
	var src: Array = _arrays[plug_id]
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()
	_append(src, _end_transform(pts[0], pts[0] - pts[1], roll), verts, normals, colors, indices)
	_append(src, _end_transform(pts[n - 1], pts[n - 1] - pts[n - 2], roll + 1.3), verts, normals, colors, indices)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh.get_surface_count() - 1


## Stecker an beiden Enden von `pts` an fremde Arrays anhängen (für die Blöcke ruhender Kabel, CableBatch).
## Positionen relativ zu `origin`; UV.x trägt `index` (Nummer des Kabels im Block). Läuft auch in Threads,
## sofern das Modell vorher auf dem Hauptthread geladen wurde (preload()).
static func append_ends(plug_id: String, pts: PackedVector3Array, roll: float, origin: Vector3, index: int,
		verts: PackedVector3Array, normals: PackedVector3Array, colors: PackedColorArray, uvs: PackedVector2Array,
		indices: PackedInt32Array, simple := true) -> void:
	var n := pts.size()
	var table := _lod_arrays if simple and _lod_arrays.has(plug_id) else _arrays
	if n < 2 or not table.has(plug_id):
		return
	var src: Array = table[plug_id]
	var before := verts.size()
	var shift := Transform3D(Basis.IDENTITY, -origin)
	_append(src, shift * _end_transform(pts[0], pts[0] - pts[1], roll), verts, normals, colors, indices)
	_append(src, shift * _end_transform(pts[n - 1], pts[n - 1] - pts[n - 2], roll + 1.3), verts, normals, colors, indices)
	var uv := Vector2(float(index), 0.0)
	for i in verts.size() - before:
		uvs.append(uv)


## Modell auf dem Hauptthread laden (vor append_ends in Threads)
static func preload_model() -> void:
	_load()


## Lage eines Steckers: Ursprung am Kabelende, -Z zeigt vom Kabel weg, um die Achse gedreht.
static func _end_transform(pos: Vector3, outward: Vector3, roll: float) -> Transform3D:
	if outward.length_squared() < 1e-10:
		outward = Vector3.FORWARD
	outward = outward.normalized()
	var up := Vector3.UP if absf(outward.dot(Vector3.UP)) < 0.95 else Vector3.RIGHT
	var basis := Basis.looking_at(outward, up).rotated(outward, roll)
	return Transform3D(basis, pos)


static func _append(src: Array, xf: Transform3D, verts: PackedVector3Array, normals: PackedVector3Array,
		colors: PackedColorArray, indices: PackedInt32Array) -> void:
	var offset := verts.size()
	var sv: PackedVector3Array = src[0]
	var sn: PackedVector3Array = src[1]
	for i in sv.size():
		verts.append(xf * sv[i])
		normals.append(xf.basis * sn[i])
	colors.append_array(src[2])
	for idx in (src[3] as PackedInt32Array):
		indices.append(idx + offset)


static func _load() -> void:
	if _loaded:
		return
	_loaded = true
	_arrays = _read(MODEL_PATH)
	_lod_arrays = _read(LOD_PATH)


static func _read(path: String) -> Dictionary:
	var out := {}
	if not ResourceLoader.exists(path):
		return out
	var scene := load(path) as PackedScene
	if scene == null:
		return out
	var root := scene.instantiate()
	for node in root.find_children("plug_*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		var a := mi.mesh.surface_get_arrays(0)
		var colors: PackedColorArray = a[Mesh.ARRAY_COLOR] if a[Mesh.ARRAY_COLOR] != null else PackedColorArray()
		if colors.is_empty():
			colors.resize((a[Mesh.ARRAY_VERTEX] as PackedVector3Array).size())
			colors.fill(Color(0.2, 0.2, 0.22))
		out[String(mi.name).trim_prefix("plug_")] = [a[Mesh.ARRAY_VERTEX], a[Mesh.ARRAY_NORMAL], colors,
			a[Mesh.ARRAY_INDEX]]
	root.free()
	return out
