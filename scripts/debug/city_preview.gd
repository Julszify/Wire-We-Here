extends Node3D
## Vorschau der Stadt (grobe Gesamtkarte): Gelände aus data/world.json, Viertel-Schilder,
## Landmarken als Blöcke, Spielfigur mit Absturz-Schutz und Anzeige (Viertel, Position, FPS).
## Testoptionen (nach --):
##   --viertel=<id>   Figur in die Mitte des Viertels setzen (campus, wohnviertel, altstadt, ...)
##   --at=<x>,<z>     Figur an diese Stelle setzen
##   --orbit=<grad>   Kamera drehen
##   --tour           alle Viertel nacheinander besuchen, Höhe und FPS ins Log schreiben

var layout: WorldLayout
var terrain: Terrain3D
var _player: Player
var _label: Label
var _tour: Array[Dictionary] = []
var _tour_t := 0.0
var _fps_log: Array[float] = []


func _ready() -> void:
	var t0 := Time.get_ticks_msec()
	layout = WorldLayout.load_default()
	_build_environment()
	terrain = CityTerrain.build(self, layout)
	CityTerrain.build_sea(self, layout)
	print("STADT-GELAENDE erzeugt in %d ms" % (Time.get_ticks_msec() - t0))
	var t1 := Time.get_ticks_msec()
	var blockout := CityBlockout.new()
	blockout.name = "Blockout"
	add_child(blockout)
	blockout.build(layout)
	print("BLOCKOUT %d Gebäude in %d ms" % [blockout.building_count, Time.get_ticks_msec() - t1])
	_build_district_signs()
	_build_landmarks()

	_player = (load("res://scenes/player.tscn") as PackedScene).instantiate()
	add_child(_player)
	terrain.collision_target = _player
	terrain.clipmap_target = _player
	_place(layout.spawn)

	_label = Label.new()
	_label.add_theme_font_size_override("font_size", 22)
	_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_label.add_theme_constant_override("outline_size", 6)
	_label.position = Vector2(16, 12)
	var layer := CanvasLayer.new()
	layer.add_child(_label)
	add_child(layer)
	_apply_args()


func _physics_process(_delta: float) -> void:
	# Absturz-Schutz: unter das Gelände gerutscht (z. B. in einem Block abgesetzt) -> wieder hochsetzen
	var p := _player.global_position
	var ground := layout.height(p.x, p.z)
	if p.y < ground - 4.0:
		_player.global_position = Vector3(p.x, maxf(ground, 0.0) + 2.0, p.z)
		_player.velocity = Vector3.ZERO


func _process(delta: float) -> void:
	var p := _player.global_position
	var d := layout.district_at(p.x, p.z)
	_label.text = "Stadt-Vorschau   Viertel: %s   FPS: %d\nPosition: %.0f / %.0f m   Höhe: %.1f m" % [
		d.get("name", "–"), Engine.get_frames_per_second(), p.x, p.z, p.y]
	if not _tour.is_empty():
		_tour_t += delta
		_fps_log.append(Engine.get_frames_per_second())
		if _tour_t > 3.0:
			_report()
			_tour.pop_front()
			if _tour.is_empty():
				print("TOUR fertig")
				get_tree().quit()
			else:
				_start_tour_point()


func _apply_args() -> void:
	for arg in OS.get_cmdline_user_args():
		var kv := arg.trim_prefix("--").split("=")
		match kv[0]:
			"viertel":
				var d := layout.district(kv[1])
				if d.is_empty():
					push_warning("Unbekanntes Viertel: %s" % kv[1])
				else:
					_place(WorldLayout._v2(d["center"]))
			"at":
				var xz := kv[1].split(",")
				_place(Vector2(float(xz[0]), float(xz[1])))
			"orbit":
				_player.orbit_camera(float(kv[1]))
			"tour":
				_tour = layout.districts.duplicate()
				_start_tour_point()
			"overview":
				# Luftbild schräg von Süden über die ganze Stadt
				var cam := Camera3D.new()
				add_child(cam)
				cam.far = 6000.0
				cam.fov = 55.0
				cam.global_position = Vector3(0, 1100, 1700)
				cam.look_at(Vector3(0, 0, -150))
				cam.current = true
				_label.visible = false


func _start_tour_point() -> void:
	_tour_t = 0.0
	_fps_log.clear()
	_place(WorldLayout._v2(_tour[0]["center"]))


func _report() -> void:
	var vals := _fps_log.slice(30)
	var avg := 0.0
	var low := 99999.0
	for f in vals:
		avg += f
		low = minf(low, f)
	avg /= maxf(1.0, vals.size())
	var p := _player.global_position
	print("VIERTEL %-24s Höhe %6.1f m  Boden %-5s  FPS Schnitt %4.0f  Minimum %4.0f" % [
		_tour[0]["name"], p.y, _player.is_on_floor(), avg, low])


func _place(xz: Vector2) -> void:
	_player.global_position = Vector3(xz.x, maxf(layout.height(xz.x, xz.y), 0.0) + 1.5, xz.y)
	_player.velocity = Vector3.ZERO


func _build_district_signs() -> void:
	for d in layout.districts:
		var c := WorldLayout._v2(d["center"])
		var sign := Label3D.new()
		sign.text = d["name"]
		sign.font_size = 256
		sign.outline_size = 48
		sign.pixel_size = 0.05
		sign.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		sign.modulate = Color(1.0, 0.85, 0.3)
		add_child(sign)
		sign.global_position = Vector3(c.x, maxf(layout.height(c.x, c.y), 0.0) + 45.0, c.y)


func _build_landmarks() -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.35, 0.6, 0.9)
	for l in layout.landmarks:
		var pos := WorldLayout._v2(l["pos"])
		var s: Array = l["size"]
		var size := Vector3(float(s[0]), float(s[1]), float(s[2]))
		var body := StaticBody3D.new()
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = size
		bm.material = mat
		mi.mesh = bm
		var col := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = size
		col.shape = shape
		body.add_child(mi)
		body.add_child(col)
		add_child(body)
		body.global_position = Vector3(pos.x, layout.height(pos.x, pos.y) + size.y * 0.5 - 0.5, pos.y)


func _build_environment() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	sky.sky_material = ProceduralSkyMaterial.new()
	e.sky = sky
	e.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	e.fog_enabled = true
	e.fog_density = 0.0003
	env.environment = e
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(deg_to_rad(-50), deg_to_rad(35), 0)
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 300.0
	add_child(sun)
