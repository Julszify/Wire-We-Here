extends Node3D
## Vorschau: Modelle nebeneinander (je auf 1 m Höhe gebracht), Kamera von vorn leicht oben.
## Aufruf: godot res://scenes/debug/model_lineup.tscn -- --dir=res://assets/models/props/room/tripo [--yaw=<grad>]

func _ready() -> void:
	var dir := "res://assets/models/props/room/tripo"
	var yaw := 0.0
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--dir="):
			dir = a.get_slice("=", 1)
		elif a.begins_with("--yaw="):
			yaw = deg_to_rad(float(a.get_slice("=", 1)))
	var env := WorldEnvironment.new()
	env.environment = CityLook.environment()
	add_child(env)
	var sun := DirectionalLight3D.new()
	add_child(sun)
	CityLook.setup_sun(sun)
	var files := Array(DirAccess.get_files_at(dir)).filter(func(f: String) -> bool: return f.ends_with(".glb"))
	files.sort()
	var x := 0.0
	for f: String in files:
		var m := (load(dir + "/" + f) as PackedScene).instantiate() as Node3D
		add_child(m)
		var box := ChefView._world_aabb(m)
		var k := 1.0 / maxf(box.size.y, 0.01)
		m.scale = Vector3.ONE * k
		m.rotation.y = yaw
		box = ChefView._world_aabb(m)
		m.position += Vector3(x - box.get_center().x, -box.position.y, -box.get_center().z)
		var l := Label3D.new()
		l.text = f.get_basename()
		l.font_size = 36
		l.outline_size = 8
		l.pixel_size = 0.004
		l.position = Vector3(x, 1.25, 0)
		add_child(l)
		x += 1.6
	var cam := Camera3D.new()
	add_child(cam)
	cam.position = Vector3(x * 0.5 - 0.8, 1.6, 4.6 + files.size() * 0.35)
	cam.look_at(Vector3(x * 0.5 - 0.8, 0.5, 0))
	var floor := MeshInstance3D.new()
	var p := PlaneMesh.new()
	p.size = Vector2(40, 20)
	floor.mesh = p
	add_child(floor)
