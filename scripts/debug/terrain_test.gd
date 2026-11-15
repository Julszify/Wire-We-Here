extends Node3D
## Gelände-Test mit Terrain3D: 2 × 2 km Testlandschaft nach der Kartenskizze (Tal für die Stadt,
## Campus-Plateau im Nordwesten, Hügel im Osten, Krater im Südosten, Abhang zum Meer im Süden).
## Dazu Spielfigur, Vergleichsblöcke (Häuser 10 m, Hochhaus 80 m, Turm 200 m) und eine Anzeige.
## Testoptionen (nach --): --tour  Figur springt alle 3 s zum nächsten Messpunkt und schreibt FPS ins Log
##                          --at=<x>,<z>  Figur dort absetzen   --orbit=<grad>  Kamera drehen

const SIZE_PX := 1024          # Höhenkarte 1024 × 1024 Pixel
const SPACING := 2.0           # 2 m pro Pixel = 2048 m Kantenlänge
const HALF := SIZE_PX * SPACING * 0.5

var terrain: Terrain3D
var _player: Player
var _label: Label
var _tour: Array[Vector2] = [Vector2(-650, -600), Vector2(40, 80), Vector2(450, -300), Vector2(700, 350),
	Vector2(0, 760), Vector2(-850, 850), Vector2(900, -900)]
var _tour_i := -1
var _tour_t := 0.0
var _touring := false
var _fps_log: Array[float] = []


func _ready() -> void:
	var t0 := Time.get_ticks_msec()
	_build_environment()
	terrain = _build_terrain()
	print("GELAENDE erzeugt in %d ms" % (Time.get_ticks_msec() - t0))
	_build_reference_blocks()
	_build_sea()

	_player = (load("res://scenes/player.tscn") as PackedScene).instantiate()
	add_child(_player)
	terrain.collision_target = _player
	terrain.clipmap_target = _player
	_place_player(Vector2(-650, -560))

	_label = Label.new()
	_label.add_theme_font_size_override("font_size", 22)
	_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_label.add_theme_constant_override("outline_size", 6)
	_label.position = Vector2(16, 12)
	var layer := CanvasLayer.new()
	layer.add_child(_label)
	add_child(layer)
	_apply_args()


func _process(delta: float) -> void:
	var p := _player.global_position
	_label.text = "Gelände-Test (Terrain3D %s)   FPS: %d\nPosition: %.0f / %.0f m   Höhe: %.1f m   Boden: %s" % [
		terrain.version, Engine.get_frames_per_second(), p.x, p.z, p.y, "ja" if _player.is_on_floor() else "nein"]
	if _touring:
		_tour_t += delta
		_fps_log.append(Engine.get_frames_per_second())
		if _tour_t > 3.0:
			_report_point()
			_next_tour_point()


func _apply_args() -> void:
	for arg in OS.get_cmdline_user_args():
		var kv := arg.trim_prefix("--").split("=")
		match kv[0]:
			"tour":
				_touring = true
				_next_tour_point()
			"at":
				var xz := kv[1].split(",")
				_place_player(Vector2(float(xz[0]), float(xz[1])))
			"orbit":
				_player.orbit_camera(float(kv[1]))


func _next_tour_point() -> void:
	_tour_i += 1
	_tour_t = 0.0
	_fps_log.clear()
	if _tour_i >= _tour.size():
		print("TOUR fertig")
		get_tree().quit()
		return
	_place_player(_tour[_tour_i])


func _report_point() -> void:
	var avg := 0.0
	var low := 9999.0
	for f in _fps_log.slice(30):  # erste halbe Sekunde (Nachladen) nicht mitzählen
		avg += f
		low = minf(low, f)
	avg /= maxf(1.0, _fps_log.size() - 30)
	var p := _player.global_position
	print("PUNKT %d (%.0f, %.0f): Höhe %.1f m, Boden %s, FPS Schnitt %.0f, Minimum %.0f" % [
		_tour_i, p.x, p.z, p.y, _player.is_on_floor(), avg, low])


func _place_player(xz: Vector2) -> void:
	var h := _height(xz.x, xz.y)
	_player.global_position = Vector3(xz.x, maxf(h, 0.0) + 1.5, xz.y)
	_player.velocity = Vector3.ZERO


## Testlandschaft in Metern. x nach Osten, z nach Süden (Meer bei großem z).
func _height(x: float, z: float) -> float:
	var h := 8.0
	# Abhang zum Meer
	h -= smoothstep(560.0, 820.0, z) * 16.0
	# Campus-Plateau im Nordwesten, 25 m hoch, mit flacher Rampe nach Südosten
	var d_campus := Vector2(x + 650.0, z + 600.0).length()
	h += (1.0 - smoothstep(240.0, 340.0, d_campus)) * 25.0
	# Hügel im Osten und Norden
	h += smoothstep(450.0, 950.0, x) * 45.0 * (0.6 + 0.4 * sin(z * 0.006))
	h += smoothstep(-600.0, -980.0, z) * 30.0 * (0.5 + 0.5 * cos(x * 0.004))
	# Krater im Südosten: Rand + Mulde
	var d_crater := Vector2(x - 700.0, z - 350.0).length()
	h += exp(-pow((d_crater - 190.0) / 45.0, 2.0)) * 18.0
	h -= (1.0 - smoothstep(60.0, 180.0, d_crater)) * 30.0
	# leichte Unebenheit
	h += sin(x * 0.031) * cos(z * 0.027) * 1.2
	return h


func _build_terrain() -> Terrain3D:
	var t := Terrain3D.new()
	t.name = "Terrain3D"
	add_child(t)
	t.region_size = Terrain3D.SIZE_1024
	t.vertex_spacing = SPACING
	t.material.world_background = Terrain3DMaterial.NONE
	t.show_checkered = true  # Blockout: Schachbrett zeigt Maßstab und Steigung
	var img := Image.create_empty(SIZE_PX, SIZE_PX, false, Image.FORMAT_RF)
	for py in SIZE_PX:
		for px in SIZE_PX:
			var x := px * SPACING - HALF
			var z := py * SPACING - HALF
			img.set_pixel(px, py, Color(_height(x, z), 0.0, 0.0, 1.0))
	# Bei vertex_spacing 2 wird die Position in Pixeln/Raster angegeben, Höhen in Metern (Skalierung 1)
	t.data.import_images([img, null, null], Vector3(-HALF, 0.0, -HALF), 0.0, 1.0)
	return t


func _build_reference_blocks() -> void:
	var grey := StandardMaterial3D.new()
	grey.albedo_color = Color(0.72, 0.72, 0.75)
	# Häuserblock im Tal: 5 × 4 Häuser à 10 m
	for i in 5:
		for j in 4:
			var pos := Vector2(-120.0 + i * 30.0, -60.0 + j * 30.0)
			_box(pos, Vector3(14, 10, 14), grey)
	# Hochhäuser
	for i in 3:
		_box(Vector2(380.0 + i * 45.0, -320.0), Vector3(30, 60 + i * 20, 30), grey)
	# Wolkig-Turm auf dem Plateau
	var tower := StandardMaterial3D.new()
	tower.albedo_color = Color(0.35, 0.6, 0.9)
	_box(Vector2(-700, -650), Vector3(36, 200, 36), tower)


func _box(xz: Vector2, size: Vector3, mat: Material) -> void:
	var y := _height(xz.x, xz.y)
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
	body.global_position = Vector3(xz.x, y + size.y * 0.5 - 0.5, xz.y)


func _build_sea() -> void:
	var sea := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(6000, 6000)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.15, 0.4, 0.65, 0.85)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.roughness = 0.1
	pm.material = mat
	sea.mesh = pm
	add_child(sea)


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
	e.fog_density = 0.0004
	env.environment = e
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(deg_to_rad(-50), deg_to_rad(35), 0)
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 300.0
	add_child(sun)
