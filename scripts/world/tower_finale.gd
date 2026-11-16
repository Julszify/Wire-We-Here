class_name TowerFinale
extends Node3D
## Finale im Wolkig-Turm (world.json → tower_finale): umlaufende Plattform auf Etage 40, Geländer am Dachrand,
## Aufzug mit drei Halten (Erdgeschoss, Etage 40, Dach) und C.O.R.D.s Kern auf dem Dach.
## Nur Darstellung und Kollision; ob der Aufzug fährt und was der Kern tut, entscheidet die Hauptszene.

## Halte: [{ "name", "pos" }] in Szenen-Koordinaten (Standpunkt vor der Aufzugtür)
var stops: Array[Dictionary] = []
var core_pos := Vector3.ZERO
var _doors: Array[StandardMaterial3D] = []
var _core_mat: StandardMaterial3D
var _core_label: Label3D
var _t := 0.0
var _unlocked := false
var _core_on := true


func build(city: CityWorld) -> void:
	var cfg: Dictionary = city.layout.raw().get("tower_finale", {})
	if cfg.is_empty():
		return
	var tower: Dictionary = {}
	for l: Dictionary in city.layout.landmarks:
		if String(l["id"]) == String(cfg.get("landmark", "turm")):
			tower = l
	if tower.is_empty():
		return
	var base := city.to_scene(WorldLayout._v2(tower["pos"]))
	var size: Array = tower["size"]
	var half := Vector2(float(size[0]), float(size[2])) * 0.5
	var top := base.y + float(size[1])
	var body := StaticBody3D.new()
	body.name = "TowerFinale"
	add_child(body)
	var deck_y := base.y + float(cfg.get("deck_height_m", 120.0))
	var w := float(cfg.get("deck_width_m", 10.0))
	var rail := float(cfg.get("railing_m", 1.2))
	var deck_mat := _mat(Color(0.52, 0.55, 0.6))
	var rail_mat := _mat(Color(0.35, 0.6, 0.9))
	# Plattform auf Etage 40: vier Platten rund um den Turm, außen ein Geländer
	var outer := half + Vector2(w, w)
	for side in [-1.0, 1.0]:
		_slab(body, Vector3(base.x, deck_y - 0.3, base.z + side * (half.y + w * 0.5)), Vector3(outer.x * 2.0, 0.6, w), deck_mat)
		_slab(body, Vector3(base.x + side * (half.x + w * 0.5), deck_y - 0.3, base.z), Vector3(w, 0.6, half.y * 2.0), deck_mat)
		_slab(body, Vector3(base.x, deck_y + rail * 0.5, base.z + side * outer.y), Vector3(outer.x * 2.0, rail, 0.25), rail_mat)
		_slab(body, Vector3(base.x + side * outer.x, deck_y + rail * 0.5, base.z), Vector3(0.25, rail, outer.y * 2.0), rail_mat)
		# Dachrand: unsichtbare Wand über der Brüstung, damit niemand hinunterfällt
		_wall(body, Vector3(base.x, top + 1.0, base.z + side * (half.y - 0.3)), Vector3(half.x * 2.0, 2.0, 0.4))
		_wall(body, Vector3(base.x + side * (half.x - 0.3), top + 1.0, base.z), Vector3(0.4, 2.0, half.y * 2.0))
	# Aufzug: Häuschen mit leuchtender Tür an jedem Halt
	for st: Dictionary in cfg.get("stops", []):
		var at := city.to_scene(WorldLayout._v2(st["at"]))
		var lift := float(st.get("lift_m", 0.0))
		var y := base.y + lift if lift > 0.0 else at.y
		var pos := Vector3(at.x, y, at.z)
		stops.append({ "name": String(st["name"]), "pos": pos })
		_elevator_door(body, pos, base)
	# C.O.R.D.s Kern auf dem Dach
	var core: Dictionary = cfg.get("core", {})
	if not core.is_empty():
		var at := city.to_scene(WorldLayout._v2(core["at"]))
		core_pos = Vector3(at.x, base.y + float(core.get("lift_m", 200.0)), at.z)
		_build_core(body)


## Halt in Reichweite (Index) oder -1
func stop_near(pos: Vector3, reach: float) -> int:
	for i in stops.size():
		if (stops[i]["pos"] as Vector3).distance_to(pos) < reach:
			return i
	return -1


func near_core(pos: Vector3, reach: float) -> bool:
	return core_pos != Vector3.ZERO and Vector2(pos.x - core_pos.x, pos.z - core_pos.z).length() < reach \
		and absf(pos.y - core_pos.y) < 4.0


## Aufzug fährt (Türen grün) oder nicht (rot)
func set_unlocked(on: bool) -> void:
	_unlocked = on
	for m in _doors:
		var c := Color(0.3, 1.0, 0.5) if on else Color(1.0, 0.3, 0.25)
		m.albedo_color = c
		m.emission = c


## Kern läuft (rot pulsierend) oder ist abgeschaltet (dunkel)
func set_core_on(on: bool) -> void:
	_core_on = on
	if _core_label:
		_core_label.text = "C.O.R.D.-KERN" if on else "C.O.R.D.-Kern (aus)"


func _process(delta: float) -> void:
	_t += delta
	if _core_mat:
		var k := (0.6 + 0.4 * sin(_t * 3.0)) if _core_on else 0.05
		_core_mat.emission_energy_multiplier = 3.0 * k


func _elevator_door(body: StaticBody3D, stand: Vector3, tower_base: Vector3) -> void:
	# Tür zeigt vom Turm weg; das Häuschen steht zwischen Standpunkt und Turmmitte
	var out := Vector3(stand.x - tower_base.x, 0, stand.z - tower_base.z)
	out = Vector3(signf(out.x), 0, 0) if absf(out.x) > absf(out.z) else Vector3(0, 0, signf(out.z))
	var housing := stand - out * 1.6 + Vector3(0, 1.4, 0)
	var size := Vector3(3.2, 2.8, 3.2) if out.z == 0.0 else Vector3(3.2, 2.8, 1.2)
	if out.x != 0.0:
		size = Vector3(1.2, 2.8, 3.2)
	var mi := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mi.mesh = box
	mi.material_override = _mat(Color(0.25, 0.28, 0.34))
	mi.position = housing
	add_child(mi)
	var door := MeshInstance3D.new()
	var door_mesh := BoxMesh.new()
	door_mesh.size = Vector3(1.6, 2.2, 0.06) if out.x == 0.0 else Vector3(0.06, 2.2, 1.6)
	door.mesh = door_mesh
	var m := _mat(Color(1.0, 0.3, 0.25))
	m.emission_enabled = true
	m.emission = m.albedo_color
	m.emission_energy_multiplier = 1.6
	door.material_override = m
	door.position = housing + out * (size.z * 0.5 if out.x == 0.0 else size.x * 0.5) + Vector3(0, -0.2, 0)
	add_child(door)
	_doors.append(m)
	var sign := Label3D.new()
	sign.text = "AUFZUG"
	sign.font_size = 48
	sign.outline_size = 10
	sign.pixel_size = 0.006
	sign.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	sign.position = housing + Vector3(0, 2.0, 0)
	add_child(sign)


func _build_core(body: StaticBody3D) -> void:
	var base_mat := _mat(Color(0.2, 0.22, 0.27))
	_slab(body, core_pos + Vector3(0, 1.6, 0), Vector3(3.0, 3.2, 3.0), base_mat)
	# Leuchtende Streifen rundherum (pulsieren rot, solange C.O.R.D. läuft)
	_core_mat = _mat(Color(1.0, 0.25, 0.2))
	_core_mat.emission_enabled = true
	_core_mat.emission = Color(1.0, 0.25, 0.2)
	_core_mat.emission_energy_multiplier = 3.0
	for i in 4:
		var band := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(3.1, 0.18, 3.1)
		band.mesh = bm
		band.material_override = _core_mat
		band.position = core_pos + Vector3(0, 0.6 + i * 0.7, 0)
		add_child(band)
	var dome := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 1.0
	sphere.height = 1.2
	dome.mesh = sphere
	dome.material_override = _core_mat
	dome.position = core_pos + Vector3(0, 3.5, 0)
	add_child(dome)
	_core_label = Label3D.new()
	_core_label.text = "C.O.R.D.-KERN"
	_core_label.font_size = 56
	_core_label.outline_size = 12
	_core_label.pixel_size = 0.008
	_core_label.modulate = Color(1.0, 0.75, 0.7)
	_core_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_core_label.position = core_pos + Vector3(0, 5.0, 0)
	add_child(_core_label)


func _slab(body: StaticBody3D, center: Vector3, size: Vector3, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mi.mesh = box
	mi.material_override = mat
	mi.position = center
	add_child(mi)
	_wall(body, center, size)


func _wall(body: StaticBody3D, center: Vector3, size: Vector3) -> void:
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	col.shape = shape
	col.position = center
	body.add_child(col)


static func _mat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.6
	return m
