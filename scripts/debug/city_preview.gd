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
	_build_environment()
	_player = (load("res://scenes/player.tscn") as PackedScene).instantiate()
	add_child(_player)
	var city := CityWorld.new()
	city.name = "City"
	add_child(city)
	city.build(Vector3.ZERO, _player)
	ToonLook.install(self, _player.camera)
	layout = city.layout
	terrain = city.terrain
	print("STADT erzeugt in %d ms (%d Gebäude)" % [Time.get_ticks_msec() - t0, city.blockout.building_count])
	_build_district_signs()
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
			"cam":
				# Freie Kamera: --cam=<x>,<z>,<Höhe über Boden>,<Ziel-x>,<Ziel-z> (Koordinaten wie world.json)
				var v := String(kv[1]).split(",")
				var cam := Camera3D.new()
				add_child(cam)
				cam.far = 3000.0
				cam.fov = 60.0
				var layout := WorldLayout.load_default()
				var gx := float(v[0])
				var gz := float(v[1])
				cam.global_position = Vector3(gx, layout.height(gx, gz) + float(v[2]), gz)
				var tx := float(v[3])
				var tz := float(v[4])
				cam.look_at(Vector3(tx, layout.height(tx, tz), tz))
				cam.current = true
				ToonLook.add_outline(cam)
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


func _build_environment() -> void:
	var env := WorldEnvironment.new()
	env.environment = CityLook.environment()
	add_child(env)
	var sun := DirectionalLight3D.new()
	CityLook.setup_sun(sun)
	add_child(sun)
