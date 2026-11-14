class_name TubeMesh
extends RefCounted
## Baut ein Röhren-Mesh entlang einer Punktliste (mit geschlossenen Enden).
## Rahmen per Projektion des vorherigen Normalenvektors (Parallel Transport light),
## damit sich die Röhre nicht verdreht.


static func build(pts: PackedVector3Array, radius: float, sides: int, mesh: ArrayMesh = null) -> ArrayMesh:
	if mesh == null:
		mesh = ArrayMesh.new()
	mesh.clear_surfaces()
	var n := pts.size()
	if n < 2:
		return mesh

	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	var ring := sides + 1  # ein Vertex doppelt für die UV-Naht
	verts.resize(n * ring + 2 * (sides + 2))
	normals.resize(verts.size())
	uvs.resize(verts.size())

	# Startnormale: irgendein Vektor senkrecht zur ersten Tangente
	var tangent := (pts[1] - pts[0]).normalized()
	var helper := Vector3.UP if absf(tangent.dot(Vector3.UP)) < 0.9 else Vector3.RIGHT
	var normal := (helper - tangent * tangent.dot(helper)).normalized()

	var v_len := 0.0
	var vi := 0
	var first_t := tangent
	for i in n:
		if i > 0:
			v_len += pts[i].distance_to(pts[i - 1])
		var prev := pts[maxi(i - 1, 0)]
		var next := pts[mini(i + 1, n - 1)]
		var t := next - prev
		if t.length_squared() > 1e-12:
			tangent = t.normalized()
		# Vorherige Normale auf die neue Tangente projizieren
		var projected := normal - tangent * tangent.dot(normal)
		if projected.length_squared() > 1e-8:
			normal = projected.normalized()
		var binormal := tangent.cross(normal)
		if i == 0:
			first_t = tangent
		for s in ring:
			var ang := TAU * float(s) / sides
			var dir := normal * cos(ang) + binormal * sin(ang)
			verts[vi] = pts[i] + dir * radius
			normals[vi] = dir
			uvs[vi] = Vector2(float(s) / sides, v_len / (TAU * radius))
			vi += 1

	# Mantel (Godot: Vorderseiten im Uhrzeigersinn)
	for i in n - 1:
		var a := i * ring
		var b := (i + 1) * ring
		for s in sides:
			indices.append_array([a + s, b + s, a + s + 1, a + s + 1, b + s, b + s + 1])

	# Endkappen
	vi = _add_cap(verts, normals, uvs, indices, vi, 0, ring, sides, pts[0], -first_t, true)
	vi = _add_cap(verts, normals, uvs, indices, vi, (n - 1) * ring, ring, sides, pts[n - 1], tangent, false)

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


static func _add_cap(verts: PackedVector3Array, normals: PackedVector3Array, uvs: PackedVector2Array,
		indices: PackedInt32Array, vi: int, ring_start: int, ring: int, sides: int,
		center: Vector3, outward: Vector3, is_start: bool) -> int:
	var c := vi
	verts[c] = center
	normals[c] = outward
	uvs[c] = Vector2(0.5, 0.5)
	vi += 1
	var first := vi
	for s in sides + 1:
		verts[vi] = verts[ring_start + s]
		normals[vi] = outward
		uvs[vi] = Vector2(0.5, 0.5)
		vi += 1
	for s in sides:
		if is_start:
			indices.append_array([c, first + s, first + s + 1])
		else:
			indices.append_array([c, first + s + 1, first + s])
	return vi
