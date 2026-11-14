extends Node3D
## Schubladen-Ebene: verbindet Spielfigur, Kabel-Logik und Darstellung.
## Die Logik steckt in CableSystem (Daten), hier wird nur verdrahtet und angezeigt.

@export var heap_seed: int = 1234
@export var heap_center := Vector3.ZERO

@onready var _player: Player = $Player
@onready var _crosshair: Crosshair = $HUD/Crosshair
@onready var _hint: Label = $HUD/Hint
@onready var _status: Label = $HUD/Status

var _system: CableSystem
var _heap: HeapData
var _arm_reel: ReelData
var _views: Dictionary = {}  # Kabel-ID -> CableView
var _fading: Array[CableView] = []
var _target: CableData
var _marker: MeshInstance3D
var _next_cable_id := 0
var _done_count := 0
var _message := ""
var _message_t := 0.0


func _ready() -> void:
	_system = CableSystem.new()
	add_child(_system)
	_system.cable_completed.connect(_on_cable_completed)
	_system.cable_released.connect(_on_cable_released)

	_arm_reel = ReelData.new(0, ReelData.Kind.ARM)
	_arm_reel.owner_id = 0
	_system.add_reel(_arm_reel)

	_player.interact_pressed.connect(_on_interact)
	_player.pull_pressed.connect(func() -> void: _system.press(_arm_reel))
	_player.release_pressed.connect(func() -> void: _system.release(_arm_reel))

	_marker = _make_marker()
	add_child(_marker)
	_spawn_heap(heap_seed)
	_player.look_toward(heap_center)

	# Nur zum automatischen Testen: godot -- --grab --pull=8
	_apply_test_args()


func _process(delta: float) -> void:
	_arm_reel.position = _player.arm_transform().origin

	# Anvisieren nur mit freier Hand
	_target = null
	if _arm_reel.is_free():
		var ray := _player.aim_ray()
		_target = CableTargeting.find_end(_system.cables.values(), ray[0], ray[1], _player.global_position)
	_crosshair.targeting = _target != null
	_marker.visible = _target != null
	if _target:
		_marker.global_position = _target.path.points[0]

	# Aktives Kabel jeden Frame neu formen (Figur bewegt sich)
	var held := _system.cable_on(_arm_reel)
	if held:
		_views[held.id].show_on_arm(_player.arm_transform())

	for v in _fading.duplicate():
		v.set_meta("t", float(v.get_meta("t", 0.0)) + delta / float(Balancing.reel["done_fade_s"]))
		v.set_fade(1.0 - float(v.get_meta("t")))
		if float(v.get_meta("t")) >= 1.0:
			_fading.erase(v)
			v.queue_free()

	_message_t -= delta
	_update_hud(held)


func _on_interact() -> void:
	if _target == null:
		return
	var cable := _target
	if _system.hook(cable, _arm_reel):
		_player.holding = true
		_player.tether_anchor = cable.path.points[0]
		_show_message("Kabel gegriffen – jetzt wickeln!")


func _on_cable_released(cable: CableData, reel: ReelData) -> void:
	if reel != _arm_reel:
		return
	_player.holding = false
	_views[cable.id].show_in_heap()
	_show_message("Losgelassen – das Kabel rutscht zurück in den Haufen.")


func _on_cable_completed(cable: CableData, reel: ReelData) -> void:
	if reel != _arm_reel:
		return
	_player.holding = false
	var view: CableView = _views[cable.id]
	view.show_on_arm(_player.arm_transform())
	_views.erase(cable.id)
	_system.remove_cable(cable.id)
	_fading.append(view)
	_done_count += 1
	_show_message("Knäuel abgelegt: %.1f m" % cable.length_m)
	if _system.cables.is_empty():
		_spawn_heap(_heap.rng_seed + 1)
		_show_message("Haufen leer – Nachschub ist da.")


func _spawn_heap(seed_value: int) -> void:
	_heap = HeapData.new(0, seed_value, heap_center, int(Balancing.heap["cable_count"]))
	for cable in _heap.create_cables(_next_cable_id):
		_system.add_cable(cable)
		var view := CableView.new()
		add_child(view)
		view.setup(cable)
		_views[cable.id] = view
	_next_cable_id += _heap.cable_count


func _update_hud(held: CableData) -> void:
	if held:
		_hint.text = "Leertaste / Linksklick: wickeln   ·   Q: loslassen"
	elif _target:
		_hint.text = "E: Kabelende greifen"
	else:
		_hint.text = "Ein Kabelende am Rand des Haufens anvisieren"
	var line := "Kabel im Haufen: %d   ·   Aufgerollt: %d" % [_system.cables.size() - (1 if held else 0), _done_count]
	if held:
		line += "\nAm Arm: %.1f von %.1f m" % [held.pulled_m, held.length_m]
	if _message_t > 0.0:
		line += "\n" + _message
	_status.text = line


func _show_message(text: String) -> void:
	_message = text
	_message_t = 3.0


func _make_marker() -> MeshInstance3D:
	var m := MeshInstance3D.new()
	var s := SphereMesh.new()
	s.radius = 0.1
	s.height = 0.2
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.85, 0.3)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.75, 0.2)
	mat.emission_energy_multiplier = 2.0
	s.material = mat
	m.mesh = s
	m.visible = false
	return m


func _apply_test_args() -> void:
	var args := OS.get_cmdline_user_args()
	for arg in args:
		if arg.begins_with("--orbit=") and not args.has("--grab"):
			_player.orbit_camera(float(arg.trim_prefix("--orbit=")))
	if not args.has("--grab"):
		return
	# Nächstes Kabelende greifen und optional vorwickeln
	var best: CableData = null
	for c: CableData in _system.cables.values():
		if best == null or c.path.points[0].distance_to(_player.global_position) < best.path.points[0].distance_to(_player.global_position):
			best = c
	var end := best.path.points[0]
	var away := (end - heap_center)
	away.y = 0.0
	_player.global_position = end + away.normalized() * 1.5
	_player.look_toward(heap_center)
	_target = best
	_on_interact()
	for arg in args:
		if arg.begins_with("--orbit="):
			_player.orbit_camera(float(arg.trim_prefix("--orbit=")))
		if arg.begins_with("--pull="):
			_system.pull(_arm_reel, float(arg.trim_prefix("--pull=")))
