extends Node3D
## Schubladen-Ebene: verbindet Spielfigur, Kabel-Logik, Wirtschaft und Darstellung.
## Die Logik steckt in CableSystem und Economy (Daten), hier wird nur verdrahtet und angezeigt.

@export var heap_seed: int = 1234
@export var heap_center := Vector3.ZERO

## Vorläufiger Laden (bis zum Tablet-Menü in M6): Taste -> Upgrade-ID
const SHOP_KEYS := { KEY_1: "crank", KEY_2: "extra_reel" }

@onready var _player: Player = $Player
@onready var _crosshair: Crosshair = $HUD/Crosshair
@onready var _hint: Label = $HUD/Hint
@onready var _status: Label = $HUD/Status
@onready var _money: Label = $HUD/Money
@onready var _shop: Label = $HUD/Shop

var _system: CableSystem
var _economy: Economy
var _heap: HeapData
var _arm_reel: ReelData
var _views: Dictionary = {}       # Kabel-ID -> CableView
var _reel_views: Dictionary = {}  # Rollen-ID -> ReelView
var _knot_markers: Dictionary = {}  # Kabel-ID -> MeshInstance3D
var _fading: Array[CableView] = []
var _next_cable_id := 0
var _next_reel_id := 1
var _done_count := 0
var _message := ""
var _message_t := 0.0
var _time := 0.0

# Was gerade anvisiert ist (höchstens eins davon)
var _target_end: CableData
var _target_knot: CableData
var _target_reel: ReelData
var _end_marker: MeshInstance3D


func _ready() -> void:
	_system = CableSystem.new()
	add_child(_system)
	_system.cable_completed.connect(_on_cable_completed)
	_system.cable_released.connect(_on_cable_released)
	_system.knot_hit.connect(_on_knot_hit)
	_system.knot_progress.connect(_on_knot_progress)
	_system.knot_solved.connect(_on_knot_solved)

	_economy = Economy.new()
	add_child(_economy)
	_economy.upgrade_bought.connect(_on_upgrade_bought)

	_arm_reel = ReelData.new(0, ReelData.Kind.ARM)
	_arm_reel.owner_id = 0
	_system.add_reel(_arm_reel)

	_player.interact_pressed.connect(_on_interact)
	_player.pull_pressed.connect(_on_pull)
	_player.release_pressed.connect(func() -> void: _system.release(_arm_reel))

	_end_marker = _make_sphere(0.1, Color(1.0, 0.85, 0.3), 2.0)
	add_child(_end_marker)
	_spawn_heap(heap_seed)
	_player.look_toward(heap_center)

	# Nur zum automatischen Testen, siehe _apply_test_args
	_apply_test_args()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and SHOP_KEYS.has(event.physical_keycode):
		var id: String = SHOP_KEYS[event.physical_keycode]
		if _economy.is_maxed(id):
			_show_message("%s: schon gekauft." % _economy.upgrade_name(id))
		elif not _economy.buy(id):
			_show_message("Zu wenig Geld für %s (%s)." % [_economy.upgrade_name(id), Economy.format_money(_economy.cost(id))])


func _process(delta: float) -> void:
	_time += delta
	_arm_reel.position = _player.arm_transform().origin
	_update_targets()

	# Eingehängte Kabel jeden Frame neu formen (Figur bewegt sich, Rollen drehen)
	for reel: ReelData in _system.reels.values():
		var cable := _system.cable_on(reel)
		if cable == null:
			continue
		var view: CableView = _views[cable.id]
		if reel.kind == ReelData.Kind.ARM:
			view.show_on_arm(_player.arm_transform())
		else:
			_reel_views[reel.id].set_phase(view.show_on_reel(reel.position))

	# Knoten-Markierungen pulsieren
	for m: MeshInstance3D in _knot_markers.values():
		m.scale = Vector3.ONE * (1.0 + 0.18 * sin(_time * 8.0))

	for v in _fading.duplicate():
		v.set_meta("t", float(v.get_meta("t", 0.0)) + delta / float(Balancing.reel["done_fade_s"]))
		v.set_fade(1.0 - float(v.get_meta("t")))
		if float(v.get_meta("t")) >= 1.0:
			_fading.erase(v)
			v.queue_free()

	_message_t -= delta
	_update_hud()


# --- Eingaben -------------------------------------------------------------

func _on_interact() -> void:
	var held := _system.cable_on(_arm_reel)
	# 1. Knoten am eigenen Kabel lösen geht immer, ohne zu zielen
	if held and held.is_stuck():
		_system.untie(held)
	# 2. Anvisierter Knoten (an Rolle)
	elif _target_knot:
		_system.untie(_target_knot)
	# 3. Kabel vom Arm an eine freie Rolle hängen
	elif held and _target_reel and _target_reel.is_free():
		_system.transfer(_arm_reel, _target_reel)
		_player.holding = false
		_show_message("Eingehängt!" + (" Die Rolle zieht jetzt von selbst." if _target_reel.kind == ReelData.Kind.MOTOR else " Jetzt kurbeln."))
	# 4. Kabelende greifen
	elif _target_end and _arm_reel.is_free():
		if _system.hook(_target_end, _arm_reel):
			_player.holding = true
			_player.tether_anchor = _target_end.path.points[0]
			_show_message("Kabel gegriffen – jetzt wickeln!")


func _on_pull() -> void:
	if not _arm_reel.is_free():
		_system.press(_arm_reel)
		return
	# Ohne Kabel in der Hand: an der Handkurbel in der Nähe drehen
	var crank := CableTargeting.nearest_reel(_system.reels.values(), _player.global_position, ReelData.Kind.HAND)
	if crank and not crank.is_free():
		_system.press(crank)


# --- Signale aus der Logik --------------------------------------------------

func _on_cable_released(cable: CableData, reel: ReelData) -> void:
	_remove_knot_marker(cable.id)
	if reel == _arm_reel:
		_player.holding = false
	_views[cable.id].show_in_heap()
	_show_message("Losgelassen – das Kabel rutscht zurück in den Haufen.")


func _on_cable_completed(cable: CableData, reel: ReelData) -> void:
	var view: CableView = _views[cable.id]
	var pay_pos: Vector3
	if reel == _arm_reel:
		_player.holding = false
		view.show_on_arm(_player.arm_transform())
		pay_pos = _player.global_position + Vector3(0, 2.1, 0)
	else:
		_reel_views[reel.id].set_phase(view.show_on_reel(reel.position))
		pay_pos = reel.position + Vector3(0, 1.6, 0)
	var amount := _economy.pay_for_cable(cable.length_m)
	FloatText.spawn(self, pay_pos, "+" + Economy.format_money(amount))

	_remove_knot_marker(cable.id)
	_views.erase(cable.id)
	_system.remove_cable(cable.id)
	_fading.append(view)
	_done_count += 1
	if _system.cables.is_empty():
		_spawn_heap(_heap.rng_seed + 1)
		_show_message("Haufen leer – Nachschub ist da.")


func _on_knot_hit(cable: CableData, reel: ReelData) -> void:
	var m := _make_sphere(float(Balancing.knot["marker_radius_m"]), Color(0.85, 0.15, 0.1), 1.5)
	add_child(m)
	m.global_position = cable.path.points[0]
	_knot_markers[cable.id] = m
	if reel == _arm_reel:
		_show_message("Knoten! E drücken, um ihn zu lösen.")
	else:
		_show_message("Knoten an einer Rolle! Hingehen, Knoten anvisieren und E drücken.")


func _on_knot_progress(_cable: CableData, presses: int, needed: int) -> void:
	if presses < needed:
		_show_message("Knoten lösen … %d/%d" % [presses, needed])


func _on_knot_solved(cable: CableData) -> void:
	_remove_knot_marker(cable.id)
	_show_message("Knoten gelöst!")


func _on_upgrade_bought(upgrade_id: String, _level: int) -> void:
	match upgrade_id:
		"crank":
			_place_reel(ReelData.Kind.HAND)
			_show_message("Handkurbel aufgestellt. Kabel greifen, zur Kurbel bringen und mit E einhängen.")
		"extra_reel":
			_place_reel(ReelData.Kind.MOTOR)
			_show_message("Motorrolle aufgestellt. Sie zieht eingehängte Kabel von selbst.")


# --- Hilfen ---------------------------------------------------------------

func _update_targets() -> void:
	var ray := _player.aim_ray()
	var pos := _player.global_position
	_target_knot = CableTargeting.find_knot(_system.cables.values(), ray[0], ray[1], pos)
	_target_reel = null
	_target_end = null
	if _target_knot == null:
		_target_reel = CableTargeting.find_reel(_system.reels.values(), ray[0], ray[1], pos)
	if _target_knot == null and _target_reel == null and _arm_reel.is_free():
		_target_end = CableTargeting.find_end(_system.cables.values(), ray[0], ray[1], pos)
	var holding := not _arm_reel.is_free()
	_crosshair.targeting = _target_knot != null or _target_end != null \
		or (holding and _target_reel != null and _target_reel.is_free())
	_end_marker.visible = _target_end != null
	if _target_end:
		_end_marker.global_position = _target_end.path.points[0]


func _place_reel(kind: ReelData.Kind) -> void:
	var pl: Dictionary = Balancing.placement
	var pos := _player.global_position + _player.facing() * float(pl["distance_ahead_m"])
	pos.y = 0.0
	# Nicht in den Haufen stellen
	var away := pos - heap_center
	away.y = 0.0
	var min_d: float = float(Balancing.heap["radius_m"]) + float(pl["min_heap_clearance_m"])
	if away.length() < min_d:
		pos = heap_center + (away.normalized() if away.length() > 0.01 else Vector3.BACK) * min_d
	var reel := ReelData.new(_next_reel_id, kind, pos)
	_next_reel_id += 1
	_system.add_reel(reel)
	var view := ReelView.new()
	add_child(view)
	view.setup(reel)
	_reel_views[reel.id] = view


func _spawn_heap(seed_value: int) -> void:
	_heap = HeapData.new(0, seed_value, heap_center, int(Balancing.heap["cable_count"]))
	for cable in _heap.create_cables(_next_cable_id):
		_system.add_cable(cable)
		var view := CableView.new()
		add_child(view)
		view.setup(cable)
		_views[cable.id] = view
	_next_cable_id += _heap.cable_count


func _remove_knot_marker(cable_id: int) -> void:
	if _knot_markers.has(cable_id):
		_knot_markers[cable_id].queue_free()
		_knot_markers.erase(cable_id)


func _update_hud() -> void:
	var held := _system.cable_on(_arm_reel)
	if held and held.is_stuck():
		_hint.text = "Knoten! E: lösen (%d/%d)" % [held.knot_presses, int(Balancing.knot["untie_presses"])]
	elif _target_knot:
		_hint.text = "E: Knoten lösen (%d/%d)" % [_target_knot.knot_presses, int(Balancing.knot["untie_presses"])]
	elif held and _target_reel and _target_reel.is_free():
		_hint.text = "E: Kabel an %s einhängen" % ("Motorrolle" if _target_reel.kind == ReelData.Kind.MOTOR else "Handkurbel")
	elif held:
		_hint.text = "Leertaste / Linksklick: wickeln   ·   Q: loslassen"
	elif _target_end:
		_hint.text = "E: Kabelende greifen"
	else:
		var crank := CableTargeting.nearest_reel(_system.reels.values(), _player.global_position, ReelData.Kind.HAND)
		if crank and not crank.is_free():
			_hint.text = "Leertaste / Linksklick: kurbeln"
		else:
			_hint.text = "Ein Kabelende am Rand des Haufens anvisieren"

	var line := "Kabel im Haufen: %d   ·   Aufgerollt: %d" % [_heap_count(), _done_count]
	for reel: ReelData in _system.reels.values():
		var c := _system.cable_on(reel)
		if c:
			var who := "Am Arm" if reel.kind == ReelData.Kind.ARM else ("Handkurbel" if reel.kind == ReelData.Kind.HAND else "Motorrolle %d" % reel.id)
			line += "\n%s: %.1f von %.1f m%s" % [who, c.pulled_m, c.length_m, "  – KNOTEN!" if c.is_stuck() else ""]
	if _message_t > 0.0:
		line += "\n" + _message
	_status.text = line

	_money.text = Economy.format_money(_economy.state.money)
	var shop := ""
	for key in SHOP_KEYS:
		var id: String = SHOP_KEYS[key]
		var price := "gekauft" if _economy.is_maxed(id) else Economy.format_money(_economy.cost(id))
		shop += "%s: %s – %s\n" % [OS.get_keycode_string(key), _economy.upgrade_name(id), price]
	_shop.text = shop.strip_edges()


func _heap_count() -> int:
	var n := 0
	for c: CableData in _system.cables.values():
		if c.state == CableData.State.HEAP:
			n += 1
	return n


func _show_message(text: String) -> void:
	_message = text
	_message_t = 3.5


func _make_sphere(radius: float, color: Color, glow: float) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	var s := SphereMesh.new()
	s.radius = radius
	s.height = radius * 2.0
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = glow
	s.material = mat
	m.mesh = s
	m.visible = true
	return m


## Testoptionen: godot -- --money=50 --buy=crank,extra_reel --grab --pull=8 --hang --orbit=-120
func _apply_test_args() -> void:
	var args := OS.get_cmdline_user_args()
	var opts := {}
	for arg in args:
		var parts := arg.trim_prefix("--").split("=")
		opts[parts[0]] = parts[1] if parts.size() > 1 else ""
	if opts.has("money"):
		_economy.state.money = float(opts["money"])
	if opts.has("noknots"):
		for c: CableData in _system.cables.values():
			c.knots_m = PackedFloat32Array()
	if opts.has("orbit") and not opts.has("grab"):
		_player.orbit_camera(float(opts["orbit"]))
	if opts.has("grab"):
		var best: CableData = null
		for c: CableData in _system.cables.values():
			if best == null or c.path.points[0].distance_to(_player.global_position) < best.path.points[0].distance_to(_player.global_position):
				best = c
		var end := best.path.points[0]
		var away := end - heap_center
		away.y = 0.0
		_player.global_position = end + away.normalized() * 1.5
		_player.look_toward(heap_center)
		if opts.has("orbit"):
			_player.orbit_camera(float(opts["orbit"]))
		_target_end = best
		_on_interact()
	if opts.has("buy"):
		for id in String(opts["buy"]).split(","):
			_economy.state.money += _economy.cost(id)
			_economy.buy(id)
	if opts.has("hang"):
		for reel: ReelData in _system.reels.values():
			if reel.kind != ReelData.Kind.ARM and reel.is_free():
				_system.transfer(_arm_reel, reel)
				_player.holding = false
				break
	if opts.has("pull"):
		for reel: ReelData in _system.reels.values():
			if not reel.is_free():
				_system.pull(reel, float(opts["pull"]))
