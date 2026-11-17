class_name ToonLook
extends RefCounted
## Spielzeug-Look für die ganze Szene: alle StandardMaterial3D bekommen Toon-Schattierung (weich
## abgestuftes Licht, kleine harte Glanzpunkte wie auf Plastik), dazu Umrisslinien als Nachbearbeitung
## vor der Kamera. Eigene Shader (Blockout, Meer, Bausatz) setzen den Toon-Modus selbst per render_mode.
## Aufruf einmal pro Szene: ToonLook.install(root, camera); neue Nodes werden automatisch erfasst.

const OUTLINE_SHADER := "res://assets/shaders/outline.gdshader"

static var _done: Dictionary = {}  # Instanz-IDs bereits umgestellter Materialien


static var _hooked := false


static func install(root: Node, camera: Camera3D) -> void:
	_done.clear()
	_apply_tree(root)
	# Einmal pro Programmlauf verbinden (Menü und Welt rufen install beide auf); verzögert, und nur, wenn der
	# Node bis dahin noch lebt
	if not _hooked:
		_hooked = true
		root.get_tree().node_added.connect(func(n: Node) -> void:
			var id := n.get_instance_id()
			(func() -> void:
				var obj := instance_from_id(id)
				if obj != null and is_instance_valid(obj):
					_apply_node(obj as Node)).call_deferred())
	if camera:
		add_outline(camera)


## Bildschirmfüllendes Rechteck mit dem Umriss-Shader an die Kamera hängen
static func add_outline(camera: Camera3D) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = "Outline"
	var q := QuadMesh.new()
	q.size = Vector2(2, 2)
	q.flip_faces = true
	mi.mesh = q
	var mat := ShaderMaterial.new()
	mat.shader = load(OUTLINE_SHADER)
	mi.material_override = mat
	mi.extra_cull_margin = 16384.0
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position = Vector3(0, 0, -1)
	camera.add_child(mi)
	return mi


static func toonify(m: Material) -> void:
	if m == null or _done.has(m.get_instance_id()):
		return
	_done[m.get_instance_id()] = true
	if m is BaseMaterial3D:
		var b := m as BaseMaterial3D
		if b.shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED:
			return
		b.diffuse_mode = BaseMaterial3D.DIFFUSE_TOON
		b.specular_mode = BaseMaterial3D.SPECULAR_TOON
		# Toon-Rampe: Rauheit bestimmt, wie weich die Licht-Kante ist
		b.roughness = clampf(b.roughness, 0.3, 0.75)


static func _on_node_added(n: Node) -> void:
	if is_instance_valid(n):
		_apply_node(n)


static func _apply_tree(n: Node) -> void:
	_apply_node(n)
	for c in n.get_children():
		_apply_tree(c)


static func _apply_node(n: Node) -> void:
	if n is MeshInstance3D:
		var mi := n as MeshInstance3D
		if mi.name == "Outline":
			return
		toonify(mi.material_override)
		if mi.mesh:
			for i in mi.mesh.get_surface_count():
				toonify(mi.mesh.surface_get_material(i))
				toonify(mi.get_surface_override_material(i))
	elif n is MultiMeshInstance3D:
		var mm := n as MultiMeshInstance3D
		toonify(mm.material_override)
		if mm.multimesh and mm.multimesh.mesh:
			for i in mm.multimesh.mesh.get_surface_count():
				toonify(mm.multimesh.mesh.surface_get_material(i))
