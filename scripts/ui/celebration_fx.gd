class_name CelebrationFx
extends CPUParticles3D
## Kosmetik „Effekt“: kurzer Partikel-Ausbruch, wenn ein Kabel fertig wird oder Knäuel eingesteckt werden.
## Arten: sparks (gelbe Funken), confetti (bunte Schnipsel), stars (goldene Sterne), rainbow (Regenbogen-Ring).
## Löscht sich nach dem Ausbruch selbst.

const LIFETIME := 1.4


static func spawn(parent: Node, at: Vector3, kind: String, amount_scale := 1.0) -> void:
	if kind == "" or parent == null:
		return
	var fx := CelebrationFx.new()
	parent.add_child(fx)
	fx.global_position = at
	fx._setup(kind, amount_scale)


func _setup(kind: String, amount_scale: float) -> void:
	one_shot = true
	explosiveness = 0.9
	lifetime = LIFETIME
	local_coords = false
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var quad := QuadMesh.new()
	quad.size = Vector2(0.09, 0.09)
	quad.material = mat
	mesh = quad
	direction = Vector3.UP
	spread = 60.0
	gravity = Vector3(0, -6.0, 0)
	initial_velocity_min = 2.5
	initial_velocity_max = 5.0
	scale_amount_min = 0.6
	scale_amount_max = 1.4
	var fade := Gradient.new()
	match kind:
		"sparks":
			amount = int(40 * amount_scale)
			quad.size = Vector2(0.05, 0.05)
			color = Color(1.0, 0.85, 0.3)
			mat.emission_enabled = true
			fade.set_color(0, Color(1.0, 0.95, 0.6))
			fade.set_color(1, Color(1.0, 0.4, 0.1, 0.0))
			initial_velocity_max = 6.0
		"confetti":
			amount = int(50 * amount_scale)
			quad.size = Vector2(0.08, 0.05)
			color_initial_ramp = _rainbow(0.85)
			fade.set_color(0, Color.WHITE)
			fade.set_color(1, Color(1, 1, 1, 0.0))
			gravity = Vector3(0, -3.0, 0)
			angular_velocity_min = -540.0
			angular_velocity_max = 540.0
			mat.billboard_mode = BaseMaterial3D.BILLBOARD_DISABLED
			mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		"stars":
			amount = int(24 * amount_scale)
			mesh = _star_mesh(mat)
			color = Color(1.0, 0.85, 0.25)
			fade.set_color(0, Color(1.0, 0.95, 0.5))
			fade.set_color(1, Color(1.0, 0.8, 0.2, 0.0))
			gravity = Vector3(0, -1.5, 0)
			initial_velocity_min = 1.5
			initial_velocity_max = 3.0
		"rainbow":
			amount = int(70 * amount_scale)
			color_initial_ramp = _rainbow(1.0)
			fade.set_color(0, Color.WHITE)
			fade.set_color(1, Color(1, 1, 1, 0.0))
			direction = Vector3.UP
			spread = 180.0
			flatness = 0.85  # Ring statt Kugel
			gravity = Vector3(0, 0.5, 0)
			initial_velocity_min = 3.0
			initial_velocity_max = 3.5
		_:
			queue_free()
			return
	color_ramp = fade
	emitting = true
	get_tree().create_timer(LIFETIME + 0.3).timeout.connect(queue_free)


static func _rainbow(sat: float) -> Gradient:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.2, 0.4, 0.6, 0.8, 1.0])
	var cols := PackedColorArray()
	for k in 6:
		cols.append(Color.from_hsv(k / 6.0, sat, 1.0))
	g.colors = cols
	return g


## Fünfzackiger Stern als flaches Mesh
static func _star_mesh(mat: Material) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_material(mat)
	var outer := 0.09
	var inner := 0.04
	for i in 10:
		var a0 := PI * 0.5 + i * TAU / 10.0
		var a1 := PI * 0.5 + (i + 1) * TAU / 10.0
		var r0 := outer if i % 2 == 0 else inner
		var r1 := outer if (i + 1) % 2 == 0 else inner
		st.add_vertex(Vector3.ZERO)
		st.add_vertex(Vector3(cos(a1) * r1, sin(a1) * r1, 0))
		st.add_vertex(Vector3(cos(a0) * r0, sin(a0) * r0, 0))
	return st.commit()
