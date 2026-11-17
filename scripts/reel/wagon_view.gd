class_name WagonView
extends Node3D
## Darstellung des Kabeltrommel-Wagens: Ladefläche, vier Räder, Deichsel. Die Trommeln sind eigene
## ReelViews (Kind.WAGON), die die Hauptszene auf die Plätze setzt.

## Lack (Kosmetik): gilt für den nächsten Wagen; den vorhandenen stellt set_paint um
static var paint := Color(0.96, 0.55, 0.15)
var _body_mat: StandardMaterial3D
var data: WagonData
var _wheels: Array[Node3D] = []
var _roll := 0.0
var _last := Vector3.ZERO
var _sign: Label3D


func setup(wagon: WagonData) -> void:
	data = wagon
	var w: Dictionary = Balancing.wagon
	var n := int(w.get("slots", 3))
	var length := n * float(w.get("slot_spacing_m", 1.2)) + 0.4
	var bed := float(w.get("bed_height_m", 0.62))
	var body := _mat(paint)
	_body_mat = body
	var dark := _mat(Color(0.18, 0.2, 0.24))
	_box(Vector3(1.25, 0.18, length), Vector3(0, bed - 0.09, 0), body)
	for sgn in [-1.0, 1.0]:
		_box(Vector3(0.08, 0.22, length), Vector3(sgn * 0.6, bed + 0.05, 0), _mat(Color(0.2, 0.5, 0.9)))
		for end in [-1.0, 1.0]:
			var wheel := Node3D.new()
			wheel.position = Vector3(sgn * 0.7, 0.3, end * (length * 0.5 - 0.35))
			add_child(wheel)
			var mi := MeshInstance3D.new()
			var cyl := CylinderMesh.new()
			cyl.top_radius = 0.3
			cyl.bottom_radius = 0.3
			cyl.height = 0.16
			cyl.radial_segments = 16
			mi.mesh = cyl
			mi.material_override = dark
			mi.rotation = Vector3(0, 0, PI * 0.5)
			wheel.add_child(mi)
			_box(Vector3(0.18, 0.12, 0.12), Vector3.ZERO, _mat(Color(0.85, 0.85, 0.82)), wheel)
			_wheels.append(wheel)
	# Deichsel nach vorn (-Z) mit Griff
	_box(Vector3(0.08, 0.08, 1.1), Vector3(0, bed - 0.05, -length * 0.5 - 0.5), dark)
	_box(Vector3(0.6, 0.08, 0.08), Vector3(0, bed - 0.05, -length * 0.5 - 1.05), dark)
	_sign = Label3D.new()
	_sign.font_size = 40
	_sign.outline_size = 10
	_sign.pixel_size = 0.004
	_sign.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_sign.position = Vector3(0, bed + 1.2, 0)
	_sign.visibility_range_end = 14.0
	add_child(_sign)
	_last = wagon.position
	refresh()


## Lage aus den Daten übernehmen; Räder drehen sich mit der gefahrenen Strecke
func refresh() -> void:
	global_position = data.position
	rotation.y = data.yaw
	var moved := Vector2(data.position.x - _last.x, data.position.z - _last.z).length()
	_last = data.position
	_roll += moved / 0.3
	for wheel in _wheels:
		wheel.rotation.x = _roll
	_sign.text = "Wagen · geparkt (%d/%d frei)" % [data.free_slots(), data.slots.size()] if data.parked else "Wagen · folgt dir"


func _box(size: Vector3, pos: Vector3, mat: Material, parent: Node3D = null) -> void:
	var mi := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = size
	mi.mesh = b
	mi.material_override = mat
	mi.position = pos
	(parent if parent else self).add_child(mi)


static func _mat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.5
	return m


func set_paint(color: Color) -> void:
	if _body_mat:
		_body_mat.albedo_color = color
