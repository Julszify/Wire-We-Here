extends Node3D
## Schubladen-Ebene: verbindet Spielfigur, Kabel-Logik, Wirtschaft, Server-Schrank und Darstellung.
## Die Logik steckt in CableSystem, Economy und ServiceRack (Daten), hier wird nur verdrahtet und angezeigt.

## Mitte des großen Kabelbergs (Blickrichtung beim Start)
const ZONE_CENTER := Vector3.ZERO

const PLAYER_ID := 0

@onready var _player: Player = $Player
@onready var _hud: CanvasLayer = $HUD
@onready var _crosshair: Crosshair = $HUD/Crosshair
@onready var _hint: Label = $HUD/Hint
@onready var _status: Label = $HUD/Status
@onready var _money: Label = $HUD/Money
@onready var _shop: Label = $HUD/Shop

## Die Stadt (Gelände, Straßen, Gebäude); so verschoben, dass der Wolkig-Hinterhof bei (0, 0, 0) liegt
var _city: CityWorld
var _system: CableSystem
var _economy: Economy
var _rack: ServiceRack
var _rack_view: RackView
var _rack_pos: Vector3
var _tablet: Tablet
var _zone: ZoneData
var _arm_reel: ReelData
var _views: Dictionary = {}       # Kabel-ID -> CableView
var _reel_views: Dictionary = {}  # Rollen-ID -> ReelView
var _knot_markers: Dictionary = {}  # Kabel-ID -> MeshInstance3D
var _items: Dictionary = {}       # Knäuel-ID -> CoilItem
var _item_views: Dictionary = {}  # Knäuel-ID -> CoilItemView
var _carried: CoilItem            # Knäuel, das die Figur gerade trägt
var _fading: Array[CableView] = []
var _next_cable_id := 0
var _next_reel_id := 1
var _next_item_id := 0
var _done_count := 0
var _message := ""
var _message_t := 0.0
var _time := 0.0

# Was gerade anvisiert ist
var _target_end: CableData
var _target_knot: CableData
var _target_reel: ReelData
var _target_item: CoilItem
var _target_rack := false
var _end_marker: MeshInstance3D

# C.O.R.D. und Bestellfalle
var _cord: CordLogic
var _cord_view: CordView
var _cord_prompt: CordPrompt
var _landing: Dictionary = {}  # Kabel-ID -> Sekunden seit Beginn des Falls (negativ = wartet noch)
var _orders := 0

# Spielstand
var _zone_ports: Array[int] = []      # Ports, die bei der Zonen-Erzeugung frei waren
var _zone_first_id := 0               # erste Kabel-ID der Zone
var _order_heaps: Array[Dictionary] = []  # { "heap": HeapData, "first_id": int }
var _removed_ids: Array[int] = []     # fertig aufgerollte Kabel (fehlen beim Neuerzeugen)
var _saving_enabled := true
var _autosave_t := 0.0
var _dump_after := -1  # nur für Tests: Zustand nach so vielen Bildern ausgeben

# Kabel in der Stadt (Viertel und Sperren), die je nach Abstand geladen und entladen werden
var _units: Array[CableUnit] = []
var _unit_loaded: Dictionary = {}     # Einheit-ID -> true, solange geladen (oder in der Warteschlange)
var _load_queue: Array[Array] = []    # [Einheit, Index des nächsten Kabels]
var _stored_states: Dictionary = {}   # Kabel-ID -> Zustand, für Kabel entladener Einheiten
var _blockers: Dictionary = {}        # Einheit-ID -> StaticBody3D (Sperre noch nicht abgetragen)
var _stream_t := 0.0


func _ready() -> void:
	_build_city()
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

	_rack = ServiceRack.new(_economy.state)
	add_child(_rack)
	_rack.service_activated.connect(_on_service_activated)
	_build_rack()

	_tablet = Tablet.new()
	_hud.add_child(_tablet)
	_tablet.setup(_economy, _rack)
	_tablet.visible = false
	_tablet.closed.connect(_close_tablet)

	_arm_reel = ReelData.new(0, ReelData.Kind.ARM)
	_arm_reel.owner_id = PLAYER_ID
	_system.add_reel(_arm_reel)

	_player.interact_pressed.connect(_on_interact)
	_player.pull_pressed.connect(_on_pull)
	_player.release_pressed.connect(_on_release)

	_end_marker = _make_sphere(0.1, Color(1.0, 0.85, 0.3), 2.0)
	add_child(_end_marker)
	# Spielstand laden, falls vorhanden (außer bei "Neues Spiel" oder --nosave)
	_saving_enabled = not OS.get_cmdline_user_args().has("--nosave")
	var save := {}
	if _saving_enabled and not SaveGame.force_new:
		save = SaveGame.read()
	SaveGame.force_new = false
	var zs: Dictionary = save.get("zone", {})

	var start: Array = Balancing.zone.get("player_start", [0, 0, 10])
	_player.global_position = Vector3(start[0], start[1], start[2])
	var ports: Array[int] = []
	for p in zs.get("ports", []):
		ports.append(int(p))
	_spawn_zone(int(zs.get("seed", Balancing.zone.get("seed", 1234))), ports if zs.has("ports") else null, int(zs.get("first_id", 0)))
	_player.look_toward(ZONE_CENTER)
	_apply_upgrades()

	_cord = CordLogic.new()
	add_child(_cord)
	_cord.setup(hash([int(Balancing.zone.get("seed", 1234)), "cord"]))
	_cord.order_requested.connect(_on_order_requested)
	_cord.order_declined.connect(_on_order_declined)
	_cord.order_placed.connect(_on_order_placed)
	_cord_view = CordView.new()
	add_child(_cord_view)
	_cord_view.global_position = _player.global_position + Vector3(1, 1.3, 1)
	_cord_prompt = CordPrompt.new()
	_hud.add_child(_cord_prompt)
	_tablet.new_game_requested.connect(_new_game)

	_units = CableUnit.build_all(_city)
	if not save.is_empty():
		_apply_save(save)
	_update_blockers()
	_stream_update(true)

	# Nur zum automatischen Testen, siehe _apply_test_args
	_apply_test_args()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("decline"):
		_cord.decline()
	elif event.is_action_pressed("quicksave"):
		_save_game(true)
	elif event.is_action_pressed("quickload"):
		if SaveGame.exists():
			get_tree().reload_current_scene()
		else:
			_show_message("Noch kein Spielstand vorhanden.")
	elif event.is_action_pressed("tablet") and not _tablet.visible:
		get_viewport().set_input_as_handled()
		_open_tablet()


## Stadt um die bisherige Zone herum aufbauen: der Hinterhof des Wolkig-Campus liegt auf dem Ursprung.
func _build_city() -> void:
	var layout := WorldLayout.load_default()
	_city = CityWorld.new()
	_city.name = "City"
	add_child(_city)
	_city.build(CityWorld.backyard_offset(layout), _player, layout)


func _physics_process(_delta: float) -> void:
	# Absturz-Schutz: unter das Gelände gerutscht (z. B. in einem Gebäude abgesetzt) -> wieder hochsetzen
	var p := _player.global_position
	var ground := _city.ground_height(p.x, p.z)
	if p.y < ground - 4.0:
		_player.global_position = Vector3(p.x, ground + 2.0, p.z)
		_player.velocity = Vector3.ZERO


func _process(delta: float) -> void:
	_time += delta
	var arm := _player.arm_transform()
	_arm_reel.position = arm.origin
	# Leine nur, solange ein Kabel aus dem Haufen am Arm hängt
	var on_arm := _system.cable_on(_arm_reel)
	_player.tethered = on_arm != null
	if on_arm:
		_player.tether_anchor = on_arm.path.points[0]
	_update_targets()

	# Eingehängte Kabel jeden Frame neu formen (Figur bewegt sich, Rollen drehen)
	for reel: ReelData in _system.reels.values():
		var cable := _system.cable_on(reel)
		if cable == null:
			continue
		var view: CableView = _views[cable.id]
		if reel.kind == ReelData.Kind.ARM:
			view.show_on_arm(arm)
		else:
			_reel_views[reel.id].set_phase(view.show_on_reel(reel.position))

	if _carried:
		_item_views[_carried.id].follow_arm(arm)

	_cord_view.follow(_player.global_position, _player.facing(), delta)
	if _cord.phase == CordLogic.Phase.ASKING:
		_cord_prompt.update_time(_cord.time_left)
	_update_landing(delta)

	# Knoten-Markierungen pulsieren
	for m: MeshInstance3D in _knot_markers.values():
		m.scale = Vector3.ONE * (1.0 + 0.18 * sin(_time * 8.0))

	for v in _fading.duplicate():
		v.set_meta("t", float(v.get_meta("t", 0.0)) + delta / float(Balancing.reel["done_fade_s"]))
		v.set_fade(1.0 - float(v.get_meta("t")))
		if float(v.get_meta("t")) >= 1.0:
			_fading.erase(v)
			v.queue_free()

	_stream_t -= delta
	if _stream_t <= 0.0:
		_stream_t = 0.5
		_stream_update(false)
	_process_load_queue()

	_message_t -= delta
	_update_hud()
	if _dump_after >= 0:
		_dump_after -= 1
		if _dump_after == 0:
			print("ZUSTAND ", _summary())

	_autosave_t += delta
	if _autosave_t >= float(Balancing.save.get("autosave_s", 30.0)):
		_autosave_t = 0.0
		_save_game(false)


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		_save_game(false)


# --- Eingaben -------------------------------------------------------------

func _arm_busy() -> bool:
	return not _arm_reel.is_free() or _carried != null


func _on_interact() -> void:
	var held := _system.cable_on(_arm_reel)
	# 1. Knoten am eigenen Kabel lösen geht immer, ohne zu zielen
	if held and held.is_stuck():
		_system.untie(held)
	# 2. Anvisierter Knoten (an einer Rolle)
	elif _target_knot:
		_system.untie(_target_knot)
	# 3. Getragenes Knäuel in den Server-Schrank stecken
	elif _carried and _target_rack:
		_plug_carried()
	# 4. Kabel vom Arm an eine freie Rolle hängen
	elif held and _target_reel and _target_reel.is_free():
		_system.transfer(_arm_reel, _target_reel)
		_player.holding = false
		_show_message("Eingehängt!" + (" Die Rolle zieht jetzt von selbst." if _target_reel.kind == ReelData.Kind.MOTOR else " Jetzt kurbeln."))
	# 5. Knäuel vom Boden aufheben
	elif _target_item and not _arm_busy():
		_pick_up(_target_item)
	# 6. Kabelende greifen
	elif _target_end and not _arm_busy():
		if _system.hook(_target_end, _arm_reel):
			_player.holding = true
			_player.tether_anchor = _target_end.path.points[0]
			_show_message("Wichtiges Kabel gegriffen – aufrollen und zum Schrank bringen!" if _target_end.is_important() else "Kabel gegriffen – jetzt wickeln!")


func _on_pull() -> void:
	if _carried:
		return
	if not _arm_reel.is_free():
		_system.press(_arm_reel)
		return
	# Ohne Kabel in der Hand: an der Handkurbel in der Nähe drehen
	var crank := CableTargeting.nearest_reel(_system.reels.values(), _player.global_position, ReelData.Kind.HAND)
	if crank and not crank.is_free():
		_system.press(crank)


func _on_release() -> void:
	if _carried:
		_drop_carried()
	else:
		_system.release(_arm_reel)


func _open_tablet() -> void:
	_tablet.refresh()
	_tablet.visible = true
	_player.input_enabled = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _close_tablet() -> void:
	_tablet.visible = false
	_player.input_enabled = true
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


# --- Signale aus der Logik --------------------------------------------------

func _on_cable_released(cable: CableData, reel: ReelData) -> void:
	_remove_knot_marker(cable.id)
	if reel == _arm_reel:
		_player.holding = false
	_views[cable.id].show_in_heap()
	_show_message("Losgelassen – das Kabel rutscht zurück in den Haufen.")


func _on_cable_completed(cable: CableData, reel: ReelData) -> void:
	var view: CableView = _views[cable.id]
	_remove_knot_marker(cable.id)
	_views.erase(cable.id)
	_system.remove_cable(cable.id)
	_removed_ids.append(cable.id)
	_done_count += 1

	if cable.is_important():
		# Wichtiges Kabel: wird zum beschrifteten Knäuel und bringt einen Teil des Meterpreises
		view.queue_free()
		var part := _economy.pay_for_cable(cable.length_m, float(Balancing.economy.get("important_pay_factor", 0.5)))
		var pay_at := (_player.global_position + Vector3(0, 2.1, 0)) if reel == _arm_reel else (reel.position + Vector3(0, 1.6, 0))
		FloatText.spawn(self, pay_at, "+" + Economy.format_money(part))
		var item := CoilItem.from_cable(_next_item_id, cable)
		_next_item_id += 1
		_items[item.id] = item
		var iv := CoilItemView.new()
		add_child(iv)
		iv.setup(item)
		_item_views[item.id] = iv
		if reel == _arm_reel:
			item.carried_by = PLAYER_ID
			_carried = item
			_player.holding = true
		else:
			var out := _player.global_position - reel.position
			out.y = 0.0
			item.position = reel.position + (out.normalized() if out.length() > 0.01 else Vector3.BACK) * 1.4
			iv.lie_at(item.position)
		_show_message("Wichtiges Kabel fertig! Zum Server-Schrank bringen: Port %d · %s" % [item.port_id + 1, ServiceRack.service_name(item.port_id)])
	else:
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
		_fading.append(view)

	var unit := _unit_of(cable.id)
	if unit and unit.barrier:
		_update_blockers()
	if _yard_cable_count() == 0:
		_spawn_zone(_zone.rng_seed + 1, null, _next_cable_id)
		_show_message("Alles aufgeräumt – aber C.O.R.D. hat nachbestellt …")


func _on_knot_hit(cable: CableData, reel: ReelData) -> void:
	_add_knot_marker(cable)
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
		_:
			_show_message("%s gekauft!" % _economy.upgrade_name(upgrade_id))
	_apply_upgrades()


func _on_service_activated(port_id: int, service_name: String, unlocks: String) -> void:
	_rack_view.set_port_active(port_id, true)
	_rack_view.set_active_count(_rack.active_count(), ServiceRack.port_count())
	FloatText.spawn(self, _rack_pos + Vector3(0, 2.3, 0), "%s online!" % service_name, Color(0.4, 1.0, 0.5))
	if unlocks != "":
		_show_message("Dienst „%s“ läuft wieder – neu im Tablet: %s" % [service_name, _economy.upgrade_name(unlocks)])
	else:
		_show_message("Dienst „%s“ läuft wieder." % service_name)


func _on_order_requested(answer_time: float) -> void:
	_cord_view.set_asking(true, "Ersatz bestellen?")
	_cord_prompt.show_question(answer_time)


func _on_order_declined() -> void:
	_cord_view.set_asking(false)
	_cord_prompt.visible = false
	_show_message("C.O.R.D.: „Bestellung storniert. Ich merke mir das.“")


func _on_order_placed(count: int) -> void:
	_cord_view.set_asking(false)
	_cord_prompt.visible = false
	_spawn_order(count)
	_show_message("C.O.R.D.: „Ersatz bestellt: %d Kabel. Gern geschehen!“" % count)


# --- Hilfen ---------------------------------------------------------------

## Neue Lieferung: ein Haufen fällt neben dem Spieler vom Himmel.
func _spawn_order(count: int) -> void:
	var c: Dictionary = Balancing.cord
	var radius: float = c["order_heap_radius_m"]
	var center := _find_free_spot(radius)
	_orders += 1
	var heap := HeapData.new(_zone.heaps.size(), hash([_zone.rng_seed, "order", _orders]), center, count,
		radius, float(c["order_heap_peak_m"]), HeapData.Kind.HEAP)
	heap.name = "Lieferung %d" % _orders
	_add_order_heap(heap, _next_cable_id, true)


## Gelieferten Haufen anlegen (beim Laden ohne Fall-Animation).
func _add_order_heap(heap: HeapData, first_id: int, animate: bool) -> void:
	var c: Dictionary = Balancing.cord
	_zone.heaps.append(heap)
	_order_heaps.append({ "heap": heap, "first_id": first_id })
	var stagger: float = c["drop_stagger_s"]
	var i := 0
	for cable in heap.create_cables(first_id):
		_system.add_cable(cable)
		var view := CableView.new()
		add_child(view)
		view.setup(cable)
		_views[cable.id] = view
		if animate:
			view.position.y = float(c["drop_height_m"])
			_landing[cable.id] = -stagger * float(i) / maxf(heap.cable_count, 1)
		i += 1
	_next_cable_id = maxi(_next_cable_id, first_id + heap.cable_count)


## Fall-Animation der gelieferten Kabel; erst nach der Landung greifbar.
func _update_landing(delta: float) -> void:
	if _landing.is_empty():
		return
	var c: Dictionary = Balancing.cord
	var fall: float = c["drop_time_s"]
	var height: float = c["drop_height_m"]
	for id in _landing.keys():
		var t: float = _landing[id] + delta
		_landing[id] = t
		var view: CableView = _views.get(id)
		if view == null:
			_landing.erase(id)
			continue
		var k := clampf(t / fall, 0.0, 1.0)
		view.position.y = height * (1.0 - k * k)  # beschleunigter Fall
		if k >= 1.0:
			view.position.y = 0.0
			_landing.erase(id)


func _grabbable_cables() -> Array:
	if _landing.is_empty():
		return _system.cables.values()
	return _system.cables.values().filter(func(c: CableData) -> bool: return not _landing.has(c.id))


## Freier Platz für einen neuen Haufen in der Nähe des Spielers.
func _find_free_spot(radius: float) -> Vector3:
	var dist: float = Balancing.cord["order_distance_m"]
	var half := float(Balancing.zone.get("floor_size_m", 90)) * 0.5 - radius - 1.0
	var base := atan2(_player.facing().z, _player.facing().x)
	# Zuerst Plätze in Blickrichtung prüfen, dann abwechselnd weiter links/rechts
	var order: Array[int] = [0]
	for k in range(1, 7):
		order.append(k)
		order.append(-k)
	for ring in 4:
		for step in order:
			var a := base + step * TAU / 12.0
			var pos := _player.global_position + Vector3(cos(a), 0.0, sin(a)) * (dist + ring * 3.0)
			pos.y = 0.0
			if absf(pos.x) > half or absf(pos.z) > half:
				continue
			if _zone.heap_at(pos, radius + 0.5) != null:
				continue
			if Vector2(pos.x - _rack_pos.x, pos.z - _rack_pos.z).length() < radius + 2.0:
				continue
			return pos
	# Kein Platz gefunden (z. B. Spieler unterwegs in der Stadt): Lieferung landet trotzdem im Hinterhof
	var fallback := _player.global_position + _player.facing() * dist
	fallback.x = clampf(fallback.x, -half, half)
	fallback.z = clampf(fallback.z, -half, half)
	fallback.y = 0.0
	return fallback


## Upgrade-Wirkungen an Logik und Spielfigur weitergeben
func _apply_upgrades() -> void:
	_system.press_multiplier = _economy.factor("grip")
	_system.motor_multiplier = _economy.factor("motor")
	var auto: Dictionary = Balancing.upgrades.get("auto_pull", {})
	_player.auto_pull_rate = float(auto.get("presses_per_second", 0.0)) if _economy.state.level("auto_pull") > 0 else 0.0


func _plug_carried() -> void:
	if _rack.plug(_carried.port_id):
		_item_views[_carried.id].queue_free()
		_item_views.erase(_carried.id)
		_items.erase(_carried.id)
		_carried = null
		_player.holding = false
	else:
		_show_message("Port %d ist schon belegt." % (_carried.port_id + 1))


func _pick_up(item: CoilItem) -> void:
	item.carried_by = PLAYER_ID
	_carried = item
	_player.holding = true
	_show_message("Knäuel aufgehoben: Port %d · %s" % [item.port_id + 1, ServiceRack.service_name(item.port_id)])


func _drop_carried() -> void:
	var item := _carried
	item.carried_by = -1
	item.position = _player.global_position + _player.facing() * 0.9
	item.position.y = 0.0
	_item_views[item.id].lie_at(item.position)
	_carried = null
	_player.holding = false


func _update_targets() -> void:
	var ray := _player.aim_ray()
	var origin: Vector3 = ray[0]
	var dir: Vector3 = ray[1]
	var pos := _player.global_position
	_target_knot = CableTargeting.find_knot(_system.cables.values(), origin, dir, pos)
	_target_reel = null
	_target_end = null
	_target_item = null
	_target_rack = false
	if _target_knot == null and _carried:
		var reach: float = Balancing.rack["reach_m"]
		_target_rack = CableTargeting._hit(_rack_pos + Vector3(0, 1.0, 0), origin, dir, pos, reach) < 0.9
	if _target_knot == null and not _target_rack:
		_target_reel = CableTargeting.find_reel(_system.reels.values(), origin, dir, pos)
	if _target_knot == null and _target_reel == null and not _arm_busy():
		_target_item = _find_item(origin, dir, pos)
		if _target_item == null:
			_target_end = CableTargeting.find_end(_grabbable_cables(), origin, dir, pos)
	var holding := not _arm_reel.is_free()
	_crosshair.targeting = _target_knot != null or _target_end != null or _target_item != null or _target_rack \
		or (holding and _target_reel != null and _target_reel.is_free())
	_end_marker.visible = _target_end != null
	if _target_end:
		_end_marker.global_position = _target_end.path.points[0]


func _find_item(origin: Vector3, dir: Vector3, player_pos: Vector3) -> CoilItem:
	var best: CoilItem = null
	var best_d := 0.6
	for item: CoilItem in _items.values():
		if item.carried_by >= 0:
			continue
		var d := CableTargeting._hit(item.position + Vector3(0, 0.15, 0), origin, dir, player_pos, Balancing.player["reach_m"])
		if d < best_d:
			best_d = d
			best = item
	return best


func _build_rack() -> void:
	var p: Array = Balancing.zone.get("rack_position", [0, 0, 10])
	_rack_pos = Vector3(p[0], p[1], p[2])
	_rack_view = RackView.new()
	add_child(_rack_view)
	_rack_view.position = _rack_pos
	# Vorderseite (+Z) zum Haufen drehen
	var to_heap := ZONE_CENTER - _rack_pos
	_rack_view.rotation.y = atan2(to_heap.x, to_heap.z)
	_rack_view.setup(ServiceRack.port_count())


func _place_reel(kind: ReelData.Kind) -> void:
	var pl: Dictionary = Balancing.placement
	var pos := _player.global_position + _player.facing() * float(pl["distance_ahead_m"])
	pos.y = 0.0
	# Nicht in einen Haufen stellen: an den Rand schieben
	var clearance: float = pl["min_heap_clearance_m"]
	var heap := _zone.heap_at(pos, clearance)
	if heap:
		var away := pos - heap.center
		away.y = 0.0
		pos = heap.center + (away.normalized() if away.length() > 0.01 else Vector3.BACK) * (heap.radius + clearance)
	_add_reel(ReelData.new(_next_reel_id, kind, pos))


func _add_reel(reel: ReelData) -> void:
	_next_reel_id = maxi(_next_reel_id, reel.id + 1)
	_system.add_reel(reel)
	var view := ReelView.new()
	add_child(view)
	view.setup(reel)
	_reel_views[reel.id] = view


## Erzeugt die Zone. `ports` = Ports für wichtige Kabel (null = alle gerade freien).
func _spawn_zone(seed_value: int, ports: Variant = null, first_id: int = 0) -> void:
	_zone = ZoneData.from_config(seed_value)
	var free_ports: Array[int] = []
	if ports != null:
		free_ports = ports
	else:
		# Wichtige Kabel nur für Ports, die noch frei sind und für die kein Knäuel unterwegs ist
		for port in ServiceRack.port_count():
			var taken := _rack.is_active(port)
			for item: CoilItem in _items.values():
				taken = taken or item.port_id == port
			for c: CableData in _system.cables.values():
				taken = taken or c.port_id == port
			if not taken:
				free_ports.append(port)
	_zone_ports = free_ports
	_zone_first_id = first_id
	_next_cable_id = maxi(_next_cable_id, first_id)
	_order_heaps.clear()
	_removed_ids.clear()
	var cables := _zone.create_cables(first_id, free_ports)
	for cable in cables:
		_system.add_cable(cable)
		var view := CableView.new()
		add_child(view)
		view.setup(cable)
		_views[cable.id] = view
	_next_cable_id += cables.size()


# --- Kabel in der Stadt: Laden und Entladen -------------------------------

## Lädt Einheiten in der Nähe und entlädt weit entfernte. `now` = sofort vollständig laden (Spielstart).
func _stream_update(now: bool) -> void:
	var cfg: Dictionary = _city.layout.raw().get("streaming", {})
	var load_m := float(cfg.get("load_m", 150.0))
	var unload_m := float(cfg.get("unload_m", 220.0))
	var p := _player.global_position
	for u in _units:
		var dist := u.distance_to(p)
		if dist < load_m and not _unit_loaded.has(u.id):
			_load_unit(u, now)
		elif dist > unload_m and _unit_loaded.has(u.id) and not _unit_busy(u):
			_unload_unit(u)


## Einheit laden: Kabel kommen über die Warteschlange (einige pro Bild), damit nichts ruckelt
func _load_unit(u: CableUnit, now: bool) -> void:
	if _unit_loaded.has(u.id):
		if now:
			for entry in _load_queue:
				if entry[0] == u:
					while entry[1] < u.cable_total():
						_spawn_unit_cable(u, entry[1])
						entry[1] += 1
			_load_queue = _load_queue.filter(func(e: Array) -> bool: return e[0] != u)
		return
	_unit_loaded[u.id] = true
	if now:
		for i in u.cable_total():
			_spawn_unit_cable(u, i)
	else:
		_load_queue.append([u, 0])


func _process_load_queue() -> void:
	var budget := int(_city.layout.raw().get("streaming", {}).get("cables_per_frame", 30))
	while budget > 0 and not _load_queue.is_empty():
		var entry: Array = _load_queue[0]
		var u: CableUnit = entry[0]
		if entry[1] >= u.cable_total():
			_load_queue.pop_front()
			continue
		_spawn_unit_cable(u, entry[1])
		entry[1] += 1
		budget -= 1


func _spawn_unit_cable(u: CableUnit, index: int) -> void:
	var cid := u.first_id + index
	if _removed_ids.has(cid) or _system.cables.has(cid):
		return
	var cable := u.make_cable(index)
	if _stored_states.has(cid):
		var st: Dictionary = _stored_states[cid]
		_stored_states.erase(cid)
		if int(st.get("state", 0)) != CableData.State.HOOKED:
			cable.load_state(st)
	_system.add_cable(cable)
	var view := CableView.new()
	add_child(view)
	view.setup(cable)
	_views[cid] = view


## Einheit entladen: Kabel aus der Szene nehmen, veränderte Zustände für später aufheben
func _unload_unit(u: CableUnit) -> void:
	_unit_loaded.erase(u.id)
	_load_queue = _load_queue.filter(func(e: Array) -> bool: return e[0] != u)
	for cid in range(u.first_id, u.last_id() + 1):
		var c: CableData = _system.cables.get(cid)
		if c == null:
			continue
		if c.pulled_m > 0.0 or c.knots_solved > 0:
			_stored_states[cid] = c.state_dict()
		_remove_knot_marker(cid)
		if _views.has(cid):
			_views[cid].queue_free()
			_views.erase(cid)
		_system.remove_cable(cid)


## Eine Einheit bleibt geladen, solange eins ihrer Kabel an einer Rolle oder am Arm hängt
func _unit_busy(u: CableUnit) -> bool:
	for reel: ReelData in _system.reels.values():
		if reel.cable_id >= 0 and u.owns(reel.cable_id):
			return true
	return false


func _unit_of(cable_id: int) -> CableUnit:
	if cable_id < CableUnit.ID_BASE:
		return null
	for u in _units:
		if u.owns(cable_id):
			return u
	return null


## Kabel der Hinterhof-Zone (inkl. Lieferungen), die noch nicht aufgerollt sind
func _yard_cable_count() -> int:
	var n := 0
	for cid: int in _system.cables.keys():
		if cid < CableUnit.ID_BASE:
			n += 1
	return n


## Sperren: Blockade in der Zaunlücke, bis genug Kabel des Bergs abgetragen sind
func _update_blockers() -> void:
	for u in _units:
		if not u.barrier:
			continue
		var removed := 0
		for cid in _removed_ids:
			if u.owns(cid):
				removed += 1
		var cleared := removed >= int(ceil(u.cable_total() * u.clear_fraction))
		if cleared and _blockers.has(u.id):
			_blockers[u.id].queue_free()
			_blockers.erase(u.id)
			_show_message("%s abgetragen – der Weg ist frei!" % u.name)
		elif not cleared and not _blockers.has(u.id):
			var body := StaticBody3D.new()
			body.name = "Blocker_%s" % u.id
			var col := CollisionShape3D.new()
			var shape := BoxShape3D.new()
			shape.size = u.blocker_size
			col.shape = shape
			body.add_child(col)
			add_child(body)
			body.global_position = u.blocker_center
			_blockers[u.id] = body


func _add_knot_marker(cable: CableData) -> void:
	if _knot_markers.has(cable.id):
		return
	var m := _make_sphere(float(Balancing.knot["marker_radius_m"]), Color(0.85, 0.15, 0.1), 1.5)
	add_child(m)
	m.global_position = cable.path.points[0]
	_knot_markers[cable.id] = m


func _remove_knot_marker(cable_id: int) -> void:
	if _knot_markers.has(cable_id):
		_knot_markers[cable_id].queue_free()
		_knot_markers.erase(cable_id)


func _update_hud() -> void:
	var held := _system.cable_on(_arm_reel)
	var presses := int(Balancing.knot["untie_presses"])
	if held and held.is_stuck():
		_hint.text = "Knoten! E: lösen (%d/%d)" % [held.knot_presses, presses]
	elif _target_knot:
		_hint.text = "E: Knoten lösen (%d/%d)" % [_target_knot.knot_presses, presses]
	elif _carried and _target_rack:
		_hint.text = "E: in Port %d einstecken (%s)" % [_carried.port_id + 1, ServiceRack.service_name(_carried.port_id)]
	elif _carried:
		_hint.text = "Knäuel zum Server-Schrank bringen   ·   Q: ablegen"
	elif held and _target_reel and _target_reel.is_free():
		_hint.text = "E: Kabel an %s einhängen" % ("Motorrolle" if _target_reel.kind == ReelData.Kind.MOTOR else "Handkurbel")
	elif held and _player.at_tether_limit:
		_hint.text = "Das Kabel ist gespannt – erst aufwickeln oder an eine Rolle hängen (Q: loslassen)"
	elif held:
		_hint.text = "Leertaste / Linksklick: wickeln   ·   Q: loslassen"
	elif _target_item:
		_hint.text = "E: Knäuel aufheben (Port %d)" % (_target_item.port_id + 1)
	elif _target_end:
		_hint.text = "E: wichtiges Kabel greifen" if _target_end.is_important() else "E: Kabelende greifen"
	else:
		var crank := CableTargeting.nearest_reel(_system.reels.values(), _player.global_position, ReelData.Kind.HAND)
		if crank and not crank.is_free():
			_hint.text = "Leertaste / Linksklick: kurbeln"
		else:
			_hint.text = "Ein Kabelende am Rand des Haufens anvisieren"

	var line := "Kabel im Haufen: %d   ·   Aufgerollt: %d   ·   Dienste: %d/%d" % [
		_heap_count(), _done_count, _rack.active_count(), ServiceRack.port_count()]
	for reel: ReelData in _system.reels.values():
		var c := _system.cable_on(reel)
		if c:
			var who := "Am Arm" if reel.kind == ReelData.Kind.ARM else ("Handkurbel" if reel.kind == ReelData.Kind.HAND else "Motorrolle %d" % reel.id)
			line += "\n%s: %.1f von %.1f m%s%s" % [who, c.pulled_m, c.length_m,
				"  (wichtig)" if c.is_important() else "", "  – KNOTEN!" if c.is_stuck() else ""]
	if _message_t > 0.0:
		line += "\n" + _message
	_status.text = line

	_money.text = Economy.format_money(_economy.state.money)
	_shop.text = "Tab: Tablet (Upgrades)"


func _heap_count() -> int:
	var n := 0
	for c: CableData in _system.cables.values():
		if c.state == CableData.State.HEAP:
			n += 1
	return n


func _show_message(text: String) -> void:
	_message = text
	_message_t = 4.0


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
	return m


# --- Spielstand -------------------------------------------------------------

func _save_game(announce: bool) -> void:
	if not _saving_enabled:
		return
	if SaveGame.write(_collect_save()) and announce:
		_show_message("Spielstand gespeichert.")


## Alles, was sich nicht aus Seeds neu erzeugen lässt.
func _collect_save() -> Dictionary:
	var cables := []
	for c: CableData in _system.cables.values():
		if c.state != CableData.State.HEAP or c.pulled_m > 0.0 or c.knots_solved > 0:
			cables.append(c.state_dict())
	for st: Dictionary in _stored_states.values():
		cables.append(st)
	var reels := []
	for r: ReelData in _system.reels.values():
		if r.kind != ReelData.Kind.ARM:
			reels.append(r.to_dict())
	var items := []
	for item: CoilItem in _items.values():
		items.append(item.to_dict())
	var orders := []
	for o in _order_heaps:
		orders.append({ "heap": (o["heap"] as HeapData).to_dict(), "first_id": o["first_id"] })
	return {
		"zone": { "seed": _zone.rng_seed, "ports": Array(_zone_ports), "first_id": _zone_first_id },
		"orders": orders,
		"removed_cables": Array(_removed_ids),
		"cables": cables,
		"arm_cable": _arm_reel.cable_id,
		"reels": reels,
		"items": items,
		"economy": _economy.state.to_dict(),
		"cord": _cord.to_dict(),
		"player": _player.view_state(),
		"counters": { "next_cable_id": _next_cable_id, "next_reel_id": _next_reel_id,
			"next_item_id": _next_item_id, "done_count": _done_count, "orders": _orders },
	}


func _apply_save(d: Dictionary) -> void:
	_economy.state.load_dict(d.get("economy", {}))
	for port in _economy.state.active_ports:
		_rack_view.set_port_active(port, true)
	_rack_view.set_active_count(_rack.active_count(), ServiceRack.port_count())

	for o: Dictionary in d.get("orders", []):
		_add_order_heap(HeapData.from_dict(o["heap"]), int(o["first_id"]), false)
	for id in d.get("removed_cables", []):
		var cid := int(id)
		if _views.has(cid):
			_views[cid].queue_free()
			_views.erase(cid)
		_system.remove_cable(cid)
		_removed_ids.append(cid)

	for rd: Dictionary in d.get("reels", []):
		var reel := ReelData.from_dict(rd)
		reel.cable_id = -1
		_add_reel(reel)

	# Stadt-Einheiten in der Nähe sofort laden, ebenso Einheiten mit eingehängten Kabeln
	if d.has("player"):
		_player.set_view_state(d["player"])
	for cs: Dictionary in d.get("cables", []):
		var u := _unit_of(int(cs["id"]))
		if u and int(cs.get("state", 0)) == CableData.State.HOOKED:
			_load_unit(u, true)
	_stream_update(true)

	for cs: Dictionary in d.get("cables", []):
		var cable: CableData = _system.cables.get(int(cs["id"]))
		if cable == null:
			if _unit_of(int(cs["id"])):
				_stored_states[int(cs["id"])] = cs  # Einheit gerade entladen: Zustand aufheben
			continue
		cable.load_state(cs)
		if cable.state == CableData.State.HOOKED:
			var reel: ReelData = _system.reels.get(cable.reel_id)
			if reel == null:
				cable.load_state({})  # Rolle fehlt: zurück in den Haufen
				continue
			reel.cable_id = cable.id
			if reel == _arm_reel:
				_player.holding = true
				_player.tether_anchor = cable.path.points[0]
			if cable.is_stuck():
				_add_knot_marker(cable)

	for idd: Dictionary in d.get("items", []):
		var item := CoilItem.from_dict(idd)
		_items[item.id] = item
		var iv := CoilItemView.new()
		add_child(iv)
		iv.setup(item)
		_item_views[item.id] = iv
		if item.carried_by >= 0 and _arm_reel.is_free() and _carried == null:
			_carried = item
			_player.holding = true
		else:
			item.carried_by = -1
			iv.lie_at(item.position)

	var cnt: Dictionary = d.get("counters", {})
	_next_cable_id = maxi(_next_cable_id, int(cnt.get("next_cable_id", 0)))
	_next_reel_id = maxi(_next_reel_id, int(cnt.get("next_reel_id", 1)))
	_next_item_id = maxi(_next_item_id, int(cnt.get("next_item_id", 0)))
	_done_count = int(cnt.get("done_count", 0))
	_orders = int(cnt.get("orders", 0))

	if d.has("player"):
		_player.set_view_state(d["player"])
	_cord_view.global_position = _player.global_position + Vector3(-1.5, 1.6, 0)
	_cord.load_dict(d.get("cord", {}))
	if _cord.phase == CordLogic.Phase.ASKING:
		_cord_view.set_asking(true, "Ersatz bestellen?")
		_cord_prompt.show_question(_cord.answer_time())
	_apply_upgrades()
	_tablet.refresh()
	_show_message("Spielstand geladen (%s)." % String(d.get("saved_at", "")).replace("T", " "))


func _new_game() -> void:
	SaveGame.delete()
	SaveGame.force_new = true
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	get_tree().reload_current_scene()


## Kurze Zusammenfassung des Zustands (für automatische Tests)
func _summary() -> String:
	var hooked := []
	for r: ReelData in _system.reels.values():
		var c := _system.cable_on(r)
		if c:
			hooked.append("%d@%d:%.2f/k%d" % [c.id, r.id, c.pulled_m, c.knots_solved])
	hooked.sort()
	var loaded := []
	for u in _units:
		if _unit_loaded.has(u.id):
			loaded.append(u.id)
	var gp := _player.global_position
	var hit := get_world_3d().direct_space_state.intersect_ray(
		PhysicsRayQueryParameters3D.create(gp + Vector3(0, 0.5, 0), gp + Vector3(0, -60, 0), 1, [_player.get_rid()]))
	var under := "%s@%.1f" % [hit["collider"].name, hit["position"].y] if hit else "nichts"
	return ("fps=%d boden=%.1f unter=%s " % [Engine.get_frames_per_second(), _city.ground_height(gp.x, gp.z), under]) + "einheiten=%s sperren=%d geld=%.2f ports=%s upgrades=%s kabel=%d rollen=%d haengt=%s knaeuel=%d getragen=%s fertig=%d lieferungen=%d cord=%s/%.2f pos=%s" % [
		str(loaded), _blockers.size(),
		_economy.state.money, str(_economy.state.active_ports), JSON.stringify(_economy.state.upgrades), _system.cables.size(),
		_system.reels.size(), str(hooked), _items.size(), str(_carried != null), _done_count, _orders,
		_cord.phase, _cord.time_left, str(SaveGame.vec_to(_player.global_position))]


## Testoptionen, z. B.:
## godot -- --money=50 --buy=crank,extra_reel --grab --important --noknots --pull=40 --hang --plug --tablet --orbit=-120
func _apply_test_args() -> void:
	var opts := {}
	for arg in OS.get_cmdline_user_args():
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
			if opts.has("important") and not c.is_important():
				continue
			if best == null or c.path.points[0].distance_to(_player.global_position) < best.path.points[0].distance_to(_player.global_position):
				best = c
		var end := best.path.points[0]
		var away := end - best.heap_center
		away.y = 0.0
		_player.global_position = end + away.normalized() * 1.5
		_player.look_toward(best.heap_center)
		if opts.has("orbit"):
			_player.orbit_camera(float(opts["orbit"]))
		_target_end = best
		_on_interact()
	if opts.has("buy"):
		for id in String(opts["buy"]).split(","):
			while _economy.is_locked(id):
				_rack.plug(_economy.locked_by(id))
			_economy.state.money += _economy.cost(id)
			_economy.buy(id)
	if opts.has("hang"):
		for reel: ReelData in _system.reels.values():
			if reel.kind != ReelData.Kind.ARM and reel.is_free():
				_system.transfer(_arm_reel, reel)
				_player.holding = false
				break
	if opts.has("solve"):
		var held := _system.cable_on(_arm_reel)
		if held:
			held.knots_solved = held.knots_m.size()
	if opts.has("pull"):
		for reel: ReelData in _system.reels.values():
			if not reel.is_free():
				_system.pull(reel, float(opts["pull"]))
	if opts.has("plug") and _carried:
		_plug_carried()
	if opts.has("tablet"):
		_open_tablet()
	if opts.has("ask"):
		_cord.ask_now()
	if opts.has("order"):
		_spawn_order(int(Balancing.cord["order_count"]))
		for id in _landing.keys():
			_views[id].position.y = 0.0
		_landing.clear()
	if opts.has("cordtime"):
		_cord.time_left = float(opts["cordtime"])
	if opts.has("teleport"):
		var xz := String(opts["teleport"]).split(",")
		_player.global_position = Vector3(float(xz[0]), 0.05, float(xz[1]))
	if opts.has("clearbarrier"):
		# Sperre zu clear_fraction abtragen, als wären die Kabel aufgerollt
		for u in _units:
			if not u.barrier:
				continue
			var needed := int(ceil(u.cable_total() * u.clear_fraction))
			for cid in range(u.first_id, u.first_id + needed):
				_removed_ids.append(cid)
				if _views.has(cid):
					_views[cid].queue_free()
					_views.erase(cid)
				_system.remove_cable(cid)
		_update_blockers()
	if opts.has("streamtest"):
		# Halb gezogenes Kabel einer Stadt-Einheit: entladen, Spielstand, wieder laden
		var u: CableUnit = _units.filter(func(x: CableUnit) -> bool: return not x.barrier)[0]
		_load_unit(u, true)
		var c: CableData = _system.cables[u.first_id + 3]
		c.pulled_m = 5.5
		c.knots_solved = 1
		_unload_unit(u)
		var stored := _stored_states.has(c.id)
		var in_save: bool = (_collect_save()["cables"] as Array).any(func(st: Dictionary) -> bool: return int(st["id"]) == c.id)
		_load_unit(u, true)
		var back: CableData = _system.cables.get(c.id)
		print("STREAMTEST gespeichert=%s im_spielstand=%s zurueck=%s gezogen=%.1f knoten=%d" % [
			stored, in_save, back != null, back.pulled_m if back else -1.0, back.knots_solved if back else -1])
	if opts.has("dumpafter"):
		_dump_after = int(opts["dumpafter"])
	if opts.has("dump"):
		print("ZUSTAND ", _summary())
	if opts.has("saveexit"):
		_saving_enabled = true
		_save_game(false)
		get_tree().quit()
