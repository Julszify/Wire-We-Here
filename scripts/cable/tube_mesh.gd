class_name TubeMesh
extends RefCounted
## Baut ein Röhren-Mesh entlang einer Punktliste (mit geschlossenen Enden).
## Rahmen per Projektion des vorherigen Normalenvektors (Parallel Transport light),
## damit sich die Röhre nicht verdreht.
## Schnell genug für Dutzende aktive Kabel pro Bild: Indizes und Winkel-Tabellen werden je Punktzahl bzw.
## Seitenzahl einmal berechnet und wiederverwendet.

static var _index_cache: Dictionary = {}  # (Punkte, Seiten) -> PackedInt32Array
static var _angle_cache: Dictionary = {}  # Seiten -> [cos, sin] je Ring-Vertex


static func build(pts: PackedVector3Array, radius: float, sides: int, mesh: ArrayMesh = null) -> ArrayMesh:
	if mesh == null:
		mesh = ArrayMesh.new()
	mesh.clear_surfaces()
	var n := pts.size()
	if n < 2:
		return mesh

	var ring := sides + 1  # ein Vertex doppelt für die UV-Naht
	var total := n * ring + 2 * (sides + 2)
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	verts.resize(total)
	normals.resize(total)
	uvs.resize(total)
	var angles := _angles(sides)
	var cs: PackedFloat32Array = angles[0]
	var sn: PackedFloat32Array = angles[1]

	# Startnormale: irgendein Vektor senkrecht zur ersten Tangente
	var tangent := (pts[1] - pts[0]).normalized()
	var helper := Vector3.UP if absf(tangent.dot(Vector3.UP)) < 0.9 else Vector3.RIGHT
	var normal := (helper - tangent * tangent.dot(helper)).normalized()

	var v_len := 0.0
	var vi := 0
	var first_t := tangent
	var uv_k := 1.0 / (TAU * radius)
	for i in n:
		var p := pts[i]
		if i > 0:
			v_len += p.distance_to(pts[i - 1])
		var t := pts[mini(i + 1, n - 1)] - pts[maxi(i - 1, 0)]
		if t.length_squared() > 1e-12:
			tangent = t.normalized()
		# Vorherige Normale auf die neue Tangente projizieren
		var projected := normal - tangent * tangent.dot(normal)
		if projected.length_squared() > 1e-8:
			normal = projected.normalized()
		var binormal := tangent.cross(normal)
		if i == 0:
			first_t = tangent
		var v := v_len * uv_k
		for s in ring:
			var dir := normal * cs[s] + binormal * sn[s]
			verts[vi] = p + dir * radius
			normals[vi] = dir
			uvs[vi] = Vector2(float(s) / sides, v)
			vi += 1

	# Endkappen (Vertices; Indizes kommen aus dem Zwischenspeicher)
	vi = _cap_verts(verts, normals, uvs, vi, 0, sides, pts[0], -first_t)
	_cap_verts(verts, normals, uvs, vi, (n - 1) * ring, sides, pts[n - 1], tangent)

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = _indices(n, sides)
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


static func _angles(sides: int) -> Array:
	if not _angle_cache.has(sides):
		var cs := PackedFloat32Array()
		var sn := PackedFloat32Array()
		for s in sides + 1:
			var a := TAU * float(s) / sides
			cs.append(cos(a))
			sn.append(sin(a))
		_angle_cache[sides] = [cs, sn]
	return _angle_cache[sides]


## Indizes für Mantel und beide Kappen; hängen nur von Punktzahl und Seitenzahl ab
static func _indices(n: int, sides: int) -> PackedInt32Array:
	var key := n * 64 + sides
	if _index_cache.has(key):
		return _index_cache[key]
	var ring := sides + 1
	var idx := PackedInt32Array()
	idx.resize((n - 1) * sides * 6 + sides * 6)
	var k := 0
	# Mantel (Godot: Vorderseiten im Uhrzeigersinn)
	for i in n - 1:
		var a := i * ring
		var b := (i + 1) * ring
		for s in sides:
			idx[k] = a + s
			idx[k + 1] = b + s
			idx[k + 2] = a + s + 1
			idx[k + 3] = a + s + 1
			idx[k + 4] = b + s
			idx[k + 5] = b + s + 1
			k += 6
	# Kappen: Mitte, dann Ring
	var c0 := n * ring
	for s in sides:
		idx[k] = c0
		idx[k + 1] = c0 + 1 + s
		idx[k + 2] = c0 + 2 + s
		k += 3
	var c1 := c0 + sides + 2
	for s in sides:
		idx[k] = c1
		idx[k + 1] = c1 + 2 + s
		idx[k + 2] = c1 + 1 + s
		k += 3
	if _index_cache.size() > 400:
		_index_cache.clear()
	_index_cache[key] = idx
	return idx


static func _cap_verts(verts: PackedVector3Array, normals: PackedVector3Array, uvs: PackedVector2Array,
		vi: int, ring_start: int, sides: int, center: Vector3, outward: Vector3) -> int:
	verts[vi] = center
	normals[vi] = outward
	uvs[vi] = Vector2(0.5, 0.5)
	vi += 1
	for s in sides + 1:
		verts[vi] = verts[ring_start + s]
		normals[vi] = outward
		uvs[vi] = Vector2(0.5, 0.5)
		vi += 1
	return vi
