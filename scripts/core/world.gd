extends Node3D
## Hauptszene: verbindet Spielfigur, Kabel-Logik, Wirtschaft, Serverraum, Stadt und Darstellung.
## Die Logik steckt in CableSystem, Economy und ServiceRack (Daten), hier wird nur verdrahtet und angezeigt.

## Mitte des großen Kabelbergs (Blickrichtung beim Start)
const ZONE_CENTER := Vector3.ZERO

const PLAYER_ID := 0

@onready var _local_player: Player = $Player
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
var _room: ServerRoomView
var _props: YardProps
# Werkzeug zum Mitnehmen, Seilbahn, Wegweiser
var _test_anim := ""                   # Testoption --anim: vorgeführte Bewegung
var _wagon: WagonData
var _wagon_view: WagonView
var _wagon_confirm_t := 0.0            # zweites E zum Ankoppeln trotz eingehängter Kabel
var _ziplines: Dictionary = {}         # Strecken-ID -> Zipline
var _target_station: Array = []        # [Zipline, 0 = äußeres Ende / 1 = Basis-Seite] in Reichweite
var _trolley: MeshInstance3D
var _waypoint: Waypoint
var _tablet: Tablet
var _zone: ZoneData
var _views: Dictionary = {}       # Kabel-ID -> CableView
var _reel_views: Dictionary = {}  # Rollen-ID -> ReelView
var _knot_markers: Dictionary = {}  # Kabel-ID -> MeshInstance3D
var _items: Dictionary = {}       # Knäuel-ID -> CoilItem
var _item_views: Dictionary = {}  # Knäuel-ID -> CoilItemView
var _fading: Array[CableView] = []
var _next_cable_id := 0
var _next_reel_id := 1
var _next_item_id := 0
var _done_count := 0
var _message := ""
var _toast: Label  # Meldungen als helle Sprechblase über dem Hinweis
var _message_t := 0.0
static var _test_newjob_done := false  # --newjob nur einmal, nicht nach dem Neuladen
var _time := 0.0

# Was gerade anvisiert ist
var _target_end: CableData
var _target_tail := false  # anvisiert ist das hintere Ende der Bahn
var _target_knot: CableData
var _target_reel: ReelData
var _target_item: CoilItem
var _target_rack := false
var _target_post: PneumaticPost         # Rohrpost-Station in Reichweite (mit Knäueln in der Tasche)
var _posts: Array[PneumaticPost] = []
var _post_t := 0.0
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
var _removed_ids: Dictionary = {}     # Kabel-ID -> true: fertig aufgerollt (fehlen beim Neuerzeugen)
var _batcher: CableBatcher             # zeichnet ruhende Kabel blockweise
var _tools: MassTools                  # Kabelsauger, Haufen-Winden, Abräum-Drohnen
var _heap_count_cache := 0
var _tower: TowerFinale                # Finale: Aufzug, Etage 40, Dach, C.O.R.D.s Kern
var _tower_open := false
var _tower_open_override := false      # Testoption --turmopen
var _target_stop := -1                 # Aufzug-Halt in Reichweite
var _target_core := false
var _finale_screen: Control
var _detector: Detector
var _detector_t := 0.0
var _progress_text := ""                # Fortschritt des Viertels, in dem der Spieler steht
var _progress_t := -1.0
var _heap_count_t := 0.0
var _saving_enabled := true
var _autosave_t := 0.0
var _dump_after := -1  # nur für Tests: Zustand nach so vielen Bildern ausgeben

# Kabel in der Stadt (Viertel und Sperren), die je nach Abstand geladen und entladen werden
var _units: Array[CableUnit] = []
var _unit_loaded: Dictionary = {}     # Einheit-ID -> true, solange geladen (oder in der Warteschlange)
var _stored_states: Dictionary = {}   # Kabel-ID -> Zustand, für Kabel entladener Einheiten
var _blockers: Dictionary = {}        # Einheit-ID -> StaticBody3D (Sperre noch nicht abgetragen)
var _stream_t := 0.0


# --- Mehrspieler: Figuren ----------------------------------------------------
## Eigene Figur und alle Mitspieler; `_actor` ist die Figur, für die gerade gehandelt wird. Der Host führt
## Absichten von Mitspielern aus, indem er `_actor` kurz auf deren Kontext setzt (`_act_as`); der übrige Code
## arbeitet über die Eigenschaften unten (_player, _arm_reel, _bag …) immer mit dem aktuellen `_actor`.
var _me: PlayerCtx
var _actor: PlayerCtx
var _players: Dictionary = {}       # Peer-ID -> PlayerCtx
var _authority := true              # Host oder Einzelspieler: rechnet die Spiellogik
var _net_t := 0.0                   # Takt für Zustands-Nachrichten
var _pstate_t := 0.0
var _econ_dirty := false
var _items_dirty := false
var _missing_since: Dictionary = {} # Client: Kabel-ID -> Zeit, seit der Host es nicht mehr als eingehängt meldet
var _replaying := false             # Client wendet Host-Zustand an: keine eigenen Meldungen
var _remote_arm_next := 950_000     # Host: IDs für die Arme der Mitspieler
var _wagon_driver: PlayerCtx        # wem der Wagen folgt

var _player: Player:
	get:
		return _actor.node if _actor else _local_player
var _arm_reel: ReelData:
	get:
		return _actor.arm_reel if _actor else null
	set(value):
		_actor.arm_reel = value
var _bag: Array[CoilItem]:
	get:
		return _actor.bag
var _carried_reel: ReelData:
	get:
		return _actor.carried_reel
	set(value):
		_actor.carried_reel = value
var _cranking_reel: ReelData:
	get:
		return _actor.cranking_reel
	set(value):
		_actor.cranking_reel = value
var _ride: Dictionary:
	get:
		return _actor.ride
	set(value):
		_actor.ride = value


func _ready() -> void:
	Net.world = self
	_authority = not Net.is_client()
	_me = PlayerCtx.new()
	_me.id = Net.local_id()
	_me.name = Net.player_name(_me.id) if Net.is_online() else String(Settings.player_name)
	_me.node = _local_player
	_actor = _me
	_wagon_driver = _me
	_players[_me.id] = _me
	($WorldEnvironment as WorldEnvironment).environment = CityLook.environment()
	CityLook.setup_sun($Sun)
	_build_city()
	_tower = TowerFinale.new()
	_tower.name = "TowerFinale"
	add_child(_tower)
	_tower.build(_city)
	ToonLook.install(self, _player.camera)
	_system = CableSystem.new()
	_system.authority = _authority
	add_child(_system)
	_system.cable_completed.connect(_on_cable_completed)
	_system.cable_hooked.connect(_on_cable_hooked)
	_batcher = CableBatcher.new()
	_batcher.name = "CableBatches"
	add_child(_batcher)
	_batcher.camera = _player.camera
	CableView.camera = _player.camera
	_tools = MassTools.new()
	_tools.name = "MassTools"
	_tools.world = self
	_tools.authority = _authority
	add_child(_tools)
	_system.cable_released.connect(_on_cable_released)
	_system.knot_hit.connect(_on_knot_hit)
	_system.knot_progress.connect(_on_knot_progress)
	_system.knot_solved.connect(_on_knot_solved)

	_economy = Economy.new()
	add_child(_economy)
	_economy.upgrade_bought.connect(_on_upgrade_bought)
	_economy.look_changed.connect(func(_slot: String, _item: String) -> void: _apply_looks())

	_rack = ServiceRack.new(_economy.state)
	add_child(_rack)
	_rack.service_activated.connect(_on_service_activated)
	_build_server_room()

	_tablet = Tablet.new()
	_style_hud()
	_hud.add_child(_tablet)
	_tablet.setup(_economy, _rack)
	_tablet.visible = false
	_tablet.closed.connect(_close_tablet)
	_tablet.snooze_requested.connect(func() -> void: _request("snooze"))
	_tablet.drones_recall_requested.connect(func() -> void: _request("recall"))
	_tablet.buy_requested.connect(func(id: String) -> void: _request("buy", { "id": id }))
	_tablet.wear_requested.connect(func(id: String) -> void: _request("wear", { "id": id }))
	_tablet.menu_requested.connect(_back_to_menu)
	_tablet.host_only_locked = Net.is_client()
	_tablet.own_look = func(slot: String) -> String: return _look_of(_me, slot)

	# Eigener Arm; als Client ein Platzhalter, bis der Host den echten Arm meldet
	_arm_reel = ReelData.new(PLAYER_ID if _authority else -1, ReelData.Kind.ARM)
	_arm_reel.owner_id = _me.id
	_system.add_reel(_arm_reel)

	_player.interact_pressed.connect(_on_interact)
	_player.pull_pressed.connect(_on_pull)
	_player.release_pressed.connect(_on_release)

	_end_marker = _make_sphere(0.1, Color(1.0, 0.85, 0.3), 2.0)
	add_child(_end_marker)
	_waypoint = Waypoint.new()
	_hud.add_child(_waypoint)
	_waypoint.camera = _player.camera
	_waypoint.label = "Serverraum"
	_waypoint.target = ServerRoomView.door_point()
	_waypoint.visible = false
	_detector = Detector.new()
	_hud.add_child(_detector)
	_detector.camera = _player.camera
	_detector.visible = false
	# Spielstand laden, falls vorhanden (außer bei "Neues Spiel" oder --nosave)
	_saving_enabled = not OS.get_cmdline_user_args().has("--nosave") and _authority
	var save := {}
	if Net.is_client():
		save = Net.join_snapshot  # Spielstand des Hosts
		_me.looks = Settings.looks.duplicate()
	elif _saving_enabled and not SaveGame.force_new:
		save = SaveGame.read()
	SaveGame.force_new = false
	# Neuer Auftrag: Ruf und Kosmetik aus dem letzten Auftrag übernehmen
	var new_job := save.is_empty() and not SaveGame.carry_meta.is_empty()
	if new_job:
		_economy.state.load_meta(SaveGame.carry_meta)
		SaveGame.carry_meta = {}
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
	_tablet.new_job_requested.connect(_start_new_job)

	_build_ziplines()
	_build_posts()
	_units = CableUnit.build_all(_city)
	if not save.is_empty():
		_apply_save(save)
	_update_blockers()
	_stream_update(true)

	_refresh_finale(false)
	_apply_looks()
	_refresh_posts()
	# Intro beim neuen Spiel (erster Start oder „Neues Spiel“); in Testläufen mit --nosave nur mit --intro
	var args := OS.get_cmdline_user_args()
	var intro_arg := ""
	for a in args:
		if a.begins_with("--intro"):
			intro_arg = a
	if save.is_empty() and not new_job and _authority and (_saving_enabled or intro_arg != ""):
		_play_intro(int(intro_arg.get_slice("=", 1)) if intro_arg.contains("=") else 0)
	if new_job:
		var st := _economy.state
		_show_message("Auftrag Nr. %d: Die Chefs haben C.O.R.D. aus einer Sicherung neu gestartet … Ruf %d: +%d %% Geld, +%d %% Tempo." % [
			st.prestige_count + 1, st.reputation, roundi(float(Balancing.prestige.get("money_per_point", 0.1)) * st.reputation * 100.0),
			roundi(float(Balancing.prestige.get("speed_per_point", 0.05)) * st.reputation * 100.0)])
		_message_t = 10.0
		_save_game(false)
	elif save.is_empty():
		_show_message("Der Serverraum steht hinter dir. Wichtige Kabel leuchten – ihre Knäuel gehören dort in die Schränke.")
	if not _authority:
		_cord.enabled = false
		_show_message("Verbunden mit %s. Viel Spaß beim gemeinsamen Aufräumen!" % Net.player_name(1))
	# Nur zum automatischen Testen, siehe _apply_test_args
	_apply_test_args()
	_net_ready()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("decline"):
		_request("decline")
	elif event.is_action_pressed("quicksave") and _authority:
		_save_game(true)
	elif event.is_action_pressed("quickload") and _authority:
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


## Leistungstest (--perf): Rechenzeit einzelner Teile in Mikrosekunden, aufsummiert bis zur Ausgabe
var _prof: Dictionary = {}
var _prof_frames := 0


func _prof_add(key: String, since_us: int) -> int:
	var now := Time.get_ticks_usec()
	_prof[key] = int(_prof.get(key, 0)) + (now - since_us)
	return now


func _process(delta: float) -> void:
	var t_start := Time.get_ticks_usec()
	_prof_frames += 1
	_time += delta
	# Arm, Tasche und getragene Rolle jeder Figur (eigene und Mitspieler)
	for ctx: PlayerCtx in _players.values():
		_actor = ctx
		if _arm_reel:
			_arm_reel.position = _player.arm_transform().origin
		if ctx != _me:
			_player.holding = _arm_reel != null and not _arm_reel.is_free()
			_player.carrying = _carried_reel != null
		for i in _bag.size():
			if _item_views.has(_bag[i].id):
				_item_views[_bag[i].id].carry_at(_player.back_transform(i))
		_update_carried_reel()
	_actor = _me
	var arm := _player.arm_transform()
	# Leine nur, solange ein Kabel aus dem Haufen am Arm hängt
	var on_arm := _system.cable_on(_arm_reel)
	_player.tethered = on_arm != null
	_player.holding = on_arm != null
	if on_arm:
		_player.tether_anchor = on_arm.path.points[0]
	var t_mark := Time.get_ticks_usec()
	_update_targets()
	t_mark = _prof_add("ziele", t_mark)

	# Eingehängte Kabel jeden Frame neu formen (Figur bewegt sich, Rollen drehen)
	t_mark = Time.get_ticks_usec()
	for reel: ReelData in _system.reels.values():
		var cable := _system.cable_on(reel)
		if cable == null:
			continue
		var view: CableView = _views[cable.id]
		# Weit entfernte Kabel nur jedes dritte Bild neu formen (versetzt je Kabel)
		if reel.kind != ReelData.Kind.ARM and reel.position.distance_squared_to(_player.camera.global_position) > 900.0 \
				and (Engine.get_process_frames() + cable.id) % 3 != 0:
			continue
		# Straff, solange gezogen wird (Tastendruck wird abgearbeitet, Motor läuft); locker sonst
		var pulling := 0.0
		if reel.pending_m > 0.0:
			pulling = 1.0
		elif reel.is_motorized():
			pulling = float(Balancing.connector.get("motor_tension", 0.7))
		view.update_tension(pulling, cable.is_stuck(), delta)
		if reel.kind == ReelData.Kind.ARM:
			var owner: PlayerCtx = _players.get(reel.owner_id, _me)
			view.show_on_arm(owner.node.arm_transform(), owner.node.global_position.y)
		else:
			var ground := _wagon.position.y if (_wagon and _wagon.owns(reel)) else reel.position.y
			if not _reel_views.has(reel.id):
				ground = _ground_y(reel.position)  # Sauger und Drohnen: Rolle schwebt, Boden darunter
			var phase := view.show_on_reel(reel.position, ReelView.scale_of(reel), ground)
			if _reel_views.has(reel.id):
				_reel_views[reel.id].set_phase(phase)

	t_mark = _prof_add("kabelformen", t_mark)
	if _authority:
		_economy.state.snooze_cooldown = maxf(_economy.state.snooze_cooldown - delta, 0.0)
	_player.carrying = _carried_reel != null
	if _test_anim != "":
		_run_test_anim()
	if _cranking_reel and _player.is_cranking() and _reel_views.has(_cranking_reel.id):
		_player.crank_point = _reel_views[_cranking_reel.id].handle_point()
	_update_wagon(delta)
	_tools.update(delta, _economy)
	_update_detector(delta)
	_update_ride(delta)
	_net_tick(delta)
	_wagon_confirm_t = maxf(_wagon_confirm_t - delta, 0.0)
	# Wegweiser: zur nächsten Abgabe (Serverraum oder Rohrpost-Station in Betrieb)
	var drop := delivery_point(_player.global_position)
	_waypoint.target = drop["pos"]
	_waypoint.label = "Rohrpost" if drop["post"] != null else "Serverraum"
	var far := _player.global_position.distance_to(drop["pos"]) > 30.0
	_waypoint.visible = not _bag.is_empty() and far and _ride.is_empty()
	_update_posts(delta)

	_cord_view.follow(_player.global_position, _player.facing(), delta)
	if _cord.phase == CordLogic.Phase.ASKING:
		_cord_prompt.update_time(_cord.time_left)
	_update_landing(delta)

	CableView.update_glow(_time)
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

	_message_t -= delta
	t_mark = Time.get_ticks_usec()
	_update_hud()
	_prof_add("hud", t_mark)
	_prof_add("world", t_start)
	if _dump_after >= 0:
		_dump_after -= 1
		if _dump_after == 0:
			print("ZUSTAND ", _summary())

	_autosave_t += delta
	if _authority and _autosave_t >= float(Balancing.save.get("autosave_s", 30.0)):
		_autosave_t = 0.0
		_save_game(false)


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		_save_game(false)


# --- Eingaben -------------------------------------------------------------

func _arm_busy() -> bool:
	return not _arm_reel.is_free() or _carried_reel != null


func _bag_full() -> bool:
	return _bag.size() >= _economy.bag_capacity()


## E gedrückt: Absicht mit allem, was gerade anvisiert ist
func _on_interact() -> void:
	if not _ride.is_empty():
		return
	_request("interact", _target_args())


## Anvisiertes als IDs (für die Absicht an den Host)
func _target_args() -> Dictionary:
	return { "end": _target_end.id if _target_end else -1, "tail": _target_tail,
		"knot": _target_knot.id if _target_knot else -1, "reel": _target_reel.id if _target_reel else -1,
		"item": _target_item.id if _target_item else -1, "rack": _target_rack, "stop": _target_stop,
		"post": _posts.find(_target_post) if _target_post else -1,
		"core": _target_core, "station": [(_target_station[0] as Zipline).id, _target_station[1]] if not _target_station.is_empty() else [] }


## Absicht „E“ der aktuellen Figur (`_actor`) ausführen; Ziele kommen als IDs und werden geprüft
func _interact_with(args: Dictionary) -> void:
	var saved := [_target_end, _target_tail, _target_knot, _target_reel, _target_item, _target_rack, _target_stop,
		_target_core, _target_station, _target_post]
	var pos := _player.global_position
	var reach := float(Balancing.player["reach_m"]) + 3.0
	var c: CableData = _system.cables.get(int(args.get("end", -1)))
	_target_end = c if c and c.state == CableData.State.HEAP and not _landing.has(c.id) \
		and (c.path.points[0].distance_to(pos) < reach or c.path.points[c.path.points.size() - 1].distance_to(pos) < reach) else null
	_target_tail = bool(args.get("tail", false))
	var k: CableData = _system.cables.get(int(args.get("knot", -1)))
	_target_knot = k if k and k.state == CableData.State.HOOKED else null
	_target_reel = _system.reels.get(int(args.get("reel", -1)))
	var it: CoilItem = _items.get(int(args.get("item", -1)))
	_target_item = it if it and it.carried_by == -1 else null
	_target_rack = bool(args.get("rack", false)) and pos.distance_to(ServerRoomView.center()) < 14.0
	var pi := int(args.get("post", -1))
	_target_post = _posts[pi] if pi >= 0 and pi < _posts.size() and _posts[pi].active \
		and _posts[pi].global_position.distance_to(pos) < 5.0 else null
	if _target_post:
		_target_rack = bool(args.get("rack", false))
	_target_stop = int(args.get("stop", -1))
	_target_core = bool(args.get("core", false))
	var st: Array = args.get("station", [])
	_target_station = [_ziplines[st[0]], int(st[1])] if st.size() == 2 and _ziplines.has(st[0]) else []
	_interact_core()
	_target_end = saved[0]
	_target_tail = saved[1]
	_target_knot = saved[2]
	_target_reel = saved[3]
	_target_item = saved[4]
	_target_rack = saved[5]
	_target_stop = saved[6]
	_target_core = saved[7]
	_target_station = saved[8]
	_target_post = saved[9]


func _interact_core() -> void:
	if not _ride.is_empty():
		return
	var held := _system.cable_on(_arm_reel)
	# 0. Getragene Rolle abstellen
	if _carried_reel:
		_put_down_reel()
		return
	# 1. Knoten am eigenen Kabel lösen geht immer, ohne zu zielen
	if held and held.is_stuck():
		_system.untie(held)
		_player.act("tug")
	# 2. Anvisierter Knoten (an einer Rolle)
	elif _target_knot:
		_system.untie(_target_knot)
		_player.act("tug")
	# 3. Knäuel aus der Tasche in die Schränke stecken (alle auf einmal)
	elif not _bag.is_empty() and _target_rack:
		var post := _target_post
		var n := _bag.size()
		_deliver_bag()
		_player.act("reach")
		if post:
			post.launch()
			Net.send_event("post", { "i": _posts.find(post) })
			_show_message("Rohrpost! %d Knäuel sind unterwegs in den Serverraum und stecken schon." % n)
	# 4. Kabel vom Arm an eine freie Rolle hängen
	elif held and _target_reel and _target_reel.is_free():
		_system.transfer(_arm_reel, _target_reel)
		_player.holding = false
		if _wagon and _wagon.owns(_target_reel):
			_wagon.parked = true
			_show_message("Am Wagen eingehängt – er parkt und zieht von selbst (%d/%d Plätze frei)." % [_wagon.free_slots(), _wagon.slots.size()])
		else:
			_show_message("Eingehängt!" + (" Die Rolle zieht jetzt von selbst." if _target_reel.kind == ReelData.Kind.MOTOR else " Jetzt kurbeln."))
	# 4b. Wagen ankoppeln bzw. parken, Rolle aufheben (ohne Kabel in der Hand)
	elif not held and _target_reel and _wagon and _wagon.owns(_target_reel):
		_toggle_wagon()
	elif not held and _target_reel and _target_reel.is_movable() and (_target_reel.is_free() or _target_reel.kind == ReelData.Kind.WINCH):
		if not _target_reel.is_free():
			_system.release(_target_reel)  # Winde: laufendes Kabel rutscht zurück
		_pick_up_reel(_target_reel)
		_player.act("pickup")
	# 4c. Seilbahn
	# 4d. Aufzug im Wolkig-Turm und C.O.R.D.s Kern
	elif _target_stop >= 0:
		if _actor == _me:
			_ride_elevator(_target_stop, held != null)
		else:
			Net.send_event("elevator", { "from": _target_stop, "holding": held != null }, _actor.id)
	elif _target_core:
		_use_core()
	elif not held and not _target_station.is_empty():
		if _actor == _me:
			_start_ride(_target_station[0], _target_station[1])
		else:
			Net.send_event("ride", { "line": (_target_station[0] as Zipline).id, "station": _target_station[1] }, _actor.id)
	# 5. Knäuel vom Boden aufheben
	elif _target_item:
		_pick_up(_target_item)
		_player.act("pickup")
	# 6. Kabelende greifen
	elif _target_end and not _arm_busy():
		if _target_tail:
			_target_end.reverse()  # am anderen Ende gegriffen: von dort aus aufwickeln
			_target_tail = false
		if _system.hook(_target_end, _arm_reel):
			_player.holding = true
			_player.tether_anchor = _target_end.path.points[0]
			_show_message("Wichtiges Kabel gegriffen – aufrollen und in den Serverraum bringen!" if _target_end.is_important() else "Kabel gegriffen – jetzt wickeln!")


func _on_pull() -> void:
	if not _authority and _arm_reel.is_free():
		# Kurbeln sofort zeigen, gezogen wird beim Host
		var near := CableTargeting.nearest_reel(_system.reels.values(), _player.global_position, ReelData.Kind.HAND)
		if near and not near.is_free() and _reel_views.has(near.id):
			_player.crank(_reel_views[near.id].handle_point(), near.position)
	_request("pull")


func _pull_core() -> void:
	if not _arm_reel.is_free():
		_system.press(_arm_reel)
		return
	# Ohne Kabel in der Hand: an der Handkurbel in der Nähe drehen
	var crank := CableTargeting.nearest_reel(_system.reels.values(), _player.global_position, ReelData.Kind.HAND)
	if crank and not crank.is_free():
		_system.press(crank)
		_cranking_reel = crank
		_player.crank(_reel_views[crank.id].handle_point(), crank.position)


func _on_release() -> void:
	_request("release")


func _release_core() -> void:
	if _carried_reel:
		_put_down_reel()
	elif not _arm_reel.is_free():
		_system.release(_arm_reel)
	elif not _bag.is_empty():
		_drop_from_bag()


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
	if _batcher.has(cable.id):
		# Ruhende Kabel zeichnet wieder der Block
		_views[cable.id].queue_free()
		_views.erase(cable.id)
		_batcher.set_hidden(cable.id, false)
	else:
		_views[cable.id].show_in_heap()
	_show_message("Losgelassen – das Kabel rutscht zurück in den Haufen.")


func _on_cable_completed(cable: CableData, reel: ReelData) -> void:
	# Arm und Sauger gehören einer Figur: deren Tasche, deren Meldungen
	var owner: PlayerCtx = _players.get(reel.owner_id, _me) \
		if reel.kind == ReelData.Kind.ARM or reel.kind == ReelData.Kind.VACUUM else _me
	var paid_before := _economy.state.total_earned
	_act_as(owner, func() -> void: _complete_cable(cable, reel))
	if Net.is_host():
		var at := (owner.node.global_position + Vector3(0, 2.1, 0)) \
			if reel.kind == ReelData.Kind.ARM or reel.kind == ReelData.Kind.VACUUM else reel.position + Vector3(0, 1.6, 0)
		Net.send_event("done", { "id": cable.id, "reel": reel.id, "imp": cable.is_important(),
			"pay": _economy.state.total_earned - paid_before, "p": at })
		_items_dirty = _items_dirty or cable.is_important()


func _complete_cable(cable: CableData, reel: ReelData) -> void:
	var view: CableView = _views[cable.id]
	var fx := _look_fx()
	if fx != "" and reel.position.distance_to(_player.global_position) < 40.0:
		var at := (_player.global_position + Vector3(0, 1.4, 0)) if reel == _arm_reel or reel.kind == ReelData.Kind.VACUUM \
			else reel.position + Vector3(0, 1.0, 0)
		CelebrationFx.spawn(self, at, fx, 1.0 if reel == _arm_reel else 0.5)
	_remove_knot_marker(cable.id)
	_views.erase(cable.id)
	_system.remove_cable(cable.id)
	_removed_ids[cable.id] = true
	_done_count += 1

	# Am Arm oder im Kabelsauger: das Knäuel kommt direkt in die Tasche
	var personal := reel == _arm_reel or reel.kind == ReelData.Kind.VACUUM
	if cable.is_important():
		# Wichtiges Kabel: wird zum beschrifteten Knäuel und bringt einen Teil des Meterpreises
		view.queue_free()
		var part := _economy.pay_for_cable(cable.length_m,
			minf(float(Balancing.economy.get("important_pay_factor", 0.5)) * _economy.bonus("important_pay"), 1.0))
		var pay_at := (_player.global_position + Vector3(0, 2.1, 0)) if personal else (reel.position + Vector3(0, 1.6, 0))
		FloatText.spawn(self, pay_at, "+" + Economy.format_money(part))
		var item := CoilItem.from_cable(_next_item_id, cable)
		_next_item_id += 1
		_items[item.id] = item
		var iv := CoilItemView.new()
		add_child(iv)
		iv.setup(item)
		_item_views[item.id] = iv
		if reel == _arm_reel:
			_player.holding = false
		var where := "Port" if RackPlan.row_of_service(RackPlan.service_of(item.port_id)) < 0 else "Reihe"
		if personal and not _bag_full():
			_put_in_bag(item)
			_show_message("Wichtiges Kabel fertig und in der Tasche (%d/%d). %s: %s" % [
				_bag.size(), _economy.bag_capacity(), where, RackPlan.port_label(item.port_id)])
		else:
			# Tasche voll oder an einer Rolle fertig geworden: Knäuel liegt am Boden
			var base := _player.global_position if personal else reel.position
			var out := _player.facing() if personal else _player.global_position - reel.position
			out.y = 0.0
			if reel.kind == ReelData.Kind.DRONE:
				out = Vector3.ZERO  # Drohne: Knäuel fällt genau darunter, sie holt es gleich
			item.position = base + (out.normalized() if out.length() > 0.01 else Vector3.ZERO) * (0.9 if personal else 1.4)
			item.position.y = _ground_y(item.position)
			iv.lie_at(item.position)
			if personal:
				_show_message("Tasche voll – das Knäuel liegt am Boden. Erst im Serverraum abliefern.")
			elif reel.kind != ReelData.Kind.DRONE:
				_show_message("Wichtiges Kabel fertig! Knäuel bei %s aufheben: %s" % [_reel_name(reel), RackPlan.port_label(item.port_id)])
	else:
		var pay_pos: Vector3
		if reel == _arm_reel:
			_player.holding = false
			view.show_on_arm(_player.arm_transform())
			pay_pos = _player.global_position + Vector3(0, 2.1, 0)
		else:
			var phase := view.show_on_reel(reel.position, ReelView.scale_of(reel))
			if _reel_views.has(reel.id):
				_reel_views[reel.id].set_phase(phase)
			pay_pos = (_player.global_position + Vector3(0, 2.1, 0)) if personal else reel.position + Vector3(0, 1.6, 0)
		var amount := _economy.pay_for_cable(cable.length_m)
		FloatText.spawn(self, pay_pos, "+" + Economy.format_money(amount))
		_fading.append(view)

	var unit := _unit_of(cable.id)
	if unit and unit.barrier:
		_update_blockers()
	if _yard_cable_count() == 0:
		_spawn_zone(_zone.rng_seed + 1, null, _next_cable_id)
		Net.send_event("zone", { "seed": _zone.rng_seed, "ports": Array(_zone_ports), "first": _zone_first_id })
		_announce("Alles aufgeräumt – aber C.O.R.D. hat nachbestellt …")


func _on_knot_hit(cable: CableData, reel: ReelData) -> void:
	_add_knot_marker(cable)
	if reel.is_automatic():
		return  # Sauger, Winde und Drohne lösen Knoten selbst
	if reel.kind == ReelData.Kind.ARM:
		_act_as(_players.get(reel.owner_id, _me), func() -> void: _show_message("Knoten! E drücken, um ihn zu lösen."))
	else:
		_announce("Knoten an einer Rolle! Hingehen, Knoten anvisieren und E drücken.")


func _on_knot_progress(_cable: CableData, presses: int, needed: int) -> void:
	if presses < needed:
		_show_message("Knoten lösen … %d/%d" % [presses, needed])


func _on_knot_solved(cable: CableData) -> void:
	_remove_knot_marker(cable.id)
	var reel := _system.reel_of(cable)
	if reel == null or not reel.is_automatic():
		_show_message("Knoten gelöst!")


func _on_upgrade_bought(upgrade_id: String, _level: int) -> void:
	match upgrade_id:
		"crank":
			_place_reel(ReelData.Kind.HAND)
			_show_message("Handkurbel aufgestellt. Kabel greifen, zur Kurbel bringen und mit E einhängen.")
		"extra_reel":
			_place_reel(ReelData.Kind.MOTOR)
			_show_message("Motorrolle aufgestellt. Sie zieht eingehängte Kabel von selbst. Leer kannst du sie mit E aufheben und woanders abstellen.")
		"vacuum":
			_show_message("Kabelsauger gekauft! Mit freiem Arm Linksklick halten: er saugt alle Kabelenden vor dir ein.")
		"winch":
			_place_reel(ReelData.Kind.WINCH)
			_show_message("Haufen-Winde aufgestellt. Sie rollt die Kabel in ihrer Nähe von selbst ab; mit E kannst du sie umstellen.")
		"drone":
			if _economy.state.level("drone") == 1:
				_tools.drone_anchor = _player.global_position
			_show_message("Abräum-Drohne gestartet! Sie arbeitet im Umkreis von %d m. Im Tablet: Drohnen zu mir rufen." % int(Balancing.drone.get("work_radius_m", 45.0)))
		"wagon":
			_wagon_driver = _actor
			_spawn_wagon(null)
			_show_message("Kabeltrommel-Wagen da! Er folgt dir. Kabel daran einhängen: er parkt und zieht drei Kabel gleichzeitig.")
		_:
			if Balancing.room_order.has(upgrade_id):
				_show_message("Serverraum ausgebaut: %s (Stufe %d)." % [_economy.upgrade_name(upgrade_id), _level])
			else:
				_show_message("%s gekauft!" % _economy.upgrade_name(upgrade_id))
	_apply_upgrades()
	_econ_dirty = true
	if Balancing.room_order.has(upgrade_id):
		_room.refresh(_economy.state)


func _on_service_activated(service_id: int, service_name: String, unlocks: String) -> void:
	var def := RackPlan.service_def(service_id)
	var at := _room.port_position(RackPlan.service_ports(service_id)[0]) + Vector3(0, 0.4, 0)
	_float(at, "%s online!" % service_name, Color(0.4, 1.0, 0.5))
	_econ_dirty = true
	var payout := float(def.get("payout", 0.0))
	if payout > 0.0:
		_economy.state.money += payout
		_economy.state.total_earned += payout
		_economy.money_changed.emit(_economy.state.money)
	_apply_upgrades()
	_refresh_ziplines()
	_refresh_finale(true)
	if unlocks != "":
		_announce("Dienst „%s“ läuft wieder – neu im Tablet: %s" % [service_name, _economy.upgrade_name(unlocks)])
	elif def.has("effect"):
		_announce("Dienst „%s“ läuft wieder. %s." % [service_name, String(def["effect"])])
	else:
		_announce("Dienst „%s“ läuft wieder." % service_name)


func _on_snooze_requested() -> void:
	if _economy.state.snooze_cooldown > 0.0 or not RackPlan.has_special(_economy.state, "cord_snooze"):
		return
	_cord.snooze(float(Balancing.cord.get("snooze_s", 300.0)))
	_economy.state.snooze_cooldown = float(Balancing.cord.get("snooze_cooldown_s", 600.0))
	_cord_view.set_asking(false)
	_cord_prompt.visible = false
	_tablet.refresh()
	_econ_dirty = true
	_announce("C.O.R.D.: „Fahre herunter … Updates werden installiert.“ (5 Minuten Ruhe)")


func _on_order_requested(answer_time: float) -> void:
	_cord_view.set_asking(true, "Ersatz bestellen?")
	_cord_prompt.show_question(answer_time)


func _on_order_declined() -> void:
	_cord_view.set_asking(false)
	_cord_view.react("declined")
	_cord_prompt.visible = false
	Net.send_event("cord", { "k": "declined" })
	_announce("C.O.R.D.: „Bestellung storniert. Ich merke mir das.“")


func _on_order_placed(count: int) -> void:
	_cord_view.set_asking(false)
	_cord_view.react("placed")
	_cord_prompt.visible = false
	_spawn_order(count)
	Net.send_event("cord", { "k": "placed" })
	_announce("C.O.R.D.: „Ersatz bestellt: %d Kabel. Gern geschehen!“" % count)


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
	if animate and Net.is_host():
		Net.send_event("order", { "heap": heap.to_dict(), "first": first_id })


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


## Kabel mit Enden in Reichweite (aus dem Raster der Kabelenden); gelieferte erst nach der Landung
func _grabbable_cables() -> Array:
	var near := _system.cables_near(_player.global_position, float(Balancing.player["reach_m"]) + 0.5)
	if _landing.is_empty():
		return near
	return near.filter(func(c: CableData) -> bool: return not _landing.has(c.id))


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
			if ServerRoomView.rect().grow(radius + 2.0).has_point(Vector2(pos.x, pos.z)) or _props.blocked(pos, radius):
				continue
			return pos
	# Kein Platz gefunden (z. B. Spieler unterwegs in der Stadt): Lieferung landet trotzdem im Hinterhof
	var fallback := _player.global_position + _player.facing() * dist
	fallback.x = clampf(fallback.x, -half, half)
	fallback.z = clampf(fallback.z, -half, half)
	fallback.y = 0.0
	return fallback


## Wirkungen von Upgrades und laufenden Diensten an Logik und Spielfigur weitergeben
func _apply_upgrades() -> void:
	_economy.refresh_bonuses()
	_system.press_multiplier = _economy.factor("grip") * _economy.bonus("press")
	_system.motor_multiplier = _economy.factor("motor") * _economy.bonus("motor")
	_system.untie_delta = int(_economy.bonus("knot_presses"))
	# Lauftempo gedeckelt, damit viele kleine Dienst-Boni die Figur nicht unsteuerbar schnell machen
	# Laufschuhe kommen dazu, gedeckelt ist auch die Summe
	_player.speed_factor = minf(minf(_economy.bonus("walk"), float(Balancing.player.get("max_speed_factor", 1.6)))
		* _economy.factor("shoes"), float(Balancing.player.get("max_total_speed_factor", 2.2)))
	var auto: Dictionary = Balancing.upgrades.get("auto_pull", {})
	_player.auto_pull_rate = float(auto.get("presses_per_second", 0.0)) if _economy.state.level("auto_pull") > 0 else 0.0
	if _tools:
		_tools.sync(_economy)
	if _cord:
		_cord.answer_bonus_s = _economy.bonus("answer_time")
		_cord.interval_factor = _economy.bonus("ask_interval")
		_cord.count_factor = _economy.bonus("order_count")


## Kosmetik aus dem Zustand auf Figur, C.O.R.D., Drohnen und Wagen übertragen
func _apply_looks() -> void:
	for ctx: PlayerCtx in _players.values():
		var outfit := {}
		for part: String in PLAYER_SLOTS:
			var def := Economy.cosmetic_def(_look_of(ctx, part))
			if def.has("color"):
				outfit[part] = Color.html(String(def["color"]))
		ctx.node.set_outfit(outfit)
	if _cord_view:
		_cord_view.set_band(_economy.look_color("cord_band", CordView.CALM))
		_cord_view.set_paint(_economy.look_color("cord_paint", Color.WHITE))
	DroneView.paint = _economy.look_color("drone_paint", Color(0.98, 0.78, 0.15))
	for d: Dictionary in _tools.drones:
		(d["view"] as DroneView).set_paint(DroneView.paint)
	WagonView.paint = _economy.look_color("wagon_paint", Color(0.96, 0.55, 0.15))
	if _wagon_view:
		_wagon_view.set_paint(WagonView.paint)


## Effekt aus der Kosmetik (leer = keiner)
func _look_fx() -> String:
	return String(Economy.cosmetic_def(_economy.look("fx")).get("fx", ""))


## Geländehöhe an einer Stelle (Hinterhof = 0)
func _ground_y(pos: Vector3) -> float:
	return _ground_spot(pos).y


func _put_in_bag(item: CoilItem) -> void:
	item.carried_by = _actor.id
	_bag.append(item)
	_items_dirty = true
	_item_views[item.id].set_carried(true)


## Alle Knäuel aus der Tasche in ihre Ports stecken
func _deliver_bag() -> void:
	var items := _bag.duplicate()
	_bag.clear()
	_plug_items(items, _player.global_position + Vector3(0, 2.2, 0))


## Knäuel in ihre Ports stecken (Spieler am Schrank oder Drohne an der Tür)
func _plug_items(items: Array, label_at: Vector3) -> void:
	var online_before := RackPlan.districts_online(_economy.state)
	var plugged := 0
	for item: CoilItem in items:
		if _rack.plug(item.port_id):
			plugged += 1
		# Port schon belegt (kann nur durch alte Spielstände passieren): Knäuel verfällt
		if _item_views.has(item.id):
			_item_views[item.id].queue_free()
			_item_views.erase(item.id)
		_items.erase(item.id)
		_bag.erase(item)
	_room.refresh(_economy.state)
	_tablet.refresh()
	_items_dirty = true
	_econ_dirty = true
	if plugged > 1:
		_float(label_at, "%d Knäuel eingesteckt" % plugged, Color(0.6, 1.0, 0.8))
	if plugged > 0:
		_fx(label_at, _look_fx(), clampf(plugged / 3.0, 1.0, 3.0))
	var online := RackPlan.districts_online(_economy.state)
	if online > online_before:
		var secs := RackPlan.sections()
		_announce("%s ist komplett am Netz! Neue Upgrade-Stufen im Tablet (%d von %d Vierteln)." % [
			String(secs[mini(online, secs.size()) - 1]["name"]), online, secs.size()])


func _pick_up(item: CoilItem) -> void:
	if _bag_full():
		_show_message("Tasche voll (%d/%d) – erst im Serverraum abliefern." % [_bag.size(), _economy.bag_capacity()])
		return
	_put_in_bag(item)
	_show_message("Knäuel eingesteckt (%d/%d): %s" % [_bag.size(), _economy.bag_capacity(), RackPlan.port_label(item.port_id)])


## Zuletzt eingestecktes Knäuel aus der Tasche auf den Boden legen
func _drop_from_bag() -> void:
	var item: CoilItem = _bag.pop_back()
	item.carried_by = -1
	item.position = _player.global_position + _player.facing() * 0.9
	item.position.y = _ground_y(item.position)
	_item_views[item.id].set_carried(false)
	_item_views[item.id].lie_at(item.position)
	_items_dirty = true


func _update_targets() -> void:
	var ray := _player.aim_ray()
	var origin: Vector3 = ray[0]
	var dir: Vector3 = ray[1]
	var pos := _player.global_position
	_target_knot = CableTargeting.find_knot(_system.hooked_cables(), origin, dir, pos)
	_target_reel = null
	_target_end = null
	_target_item = null
	_target_rack = false
	_target_post = null
	if _target_knot == null and not _bag.is_empty():
		var reach: float = Balancing.rack["reach_m"]
		for rp in _room.rack_points():
			if CableTargeting._hit(rp, origin, dir, pos, reach) < 1.3:
				_target_rack = true
				break
		if not _target_rack:
			var post := _post_near(pos, 3.2)
			if post:
				_target_rack = true
				_target_post = post
	if _target_knot == null and not _target_rack:
		_target_reel = CableTargeting.find_reel(_system.reels.values().filter(func(r: ReelData) -> bool: return not r.carried),
			origin, dir, pos)
	if _target_knot == null and _target_reel == null and not _target_rack:
		_target_item = _find_item(origin, dir, pos)
		if _target_item == null and not _arm_busy():
			_target_end = CableTargeting.find_end(_grabbable_cables(), origin, dir, pos)
			_target_tail = _target_end != null and CableTargeting.hit_tail
	_target_station = []
	if _target_knot == null and _target_reel == null and _target_item == null and _target_end == null and not _arm_busy():
		_target_station = _station_near(pos)
	_target_stop = _tower.stop_near(pos, 2.6) if _target_knot == null and _target_end == null else -1
	_target_core = _tower.near_core(pos, 3.5) and _target_end == null
	var holding := not _arm_reel.is_free()
	_crosshair.targeting = _target_knot != null or _target_end != null or _target_item != null or _target_rack \
		or (holding and _target_reel != null and _target_reel.is_free()) \
		or (not holding and _target_reel != null and (_target_reel.kind == ReelData.Kind.WAGON or (_target_reel.is_movable() and _target_reel.is_free())))
	_end_marker.visible = _target_end != null
	if _target_end:
		var ends := _target_end.path.points
		_end_marker.global_position = ends[ends.size() - 1] if _target_tail else ends[0]


func _find_item(origin: Vector3, dir: Vector3, player_pos: Vector3) -> CoilItem:
	var best: CoilItem = null
	var best_d := 0.6
	for item: CoilItem in _items.values():
		if item.carried_by != -1:
			continue  # in der Tasche oder an einer Drohne
		if absf(item.position.y - player_pos.y) > 3.0:
			continue
		var d := CableTargeting._hit(item.position + Vector3(0, 0.15, 0), origin, dir, player_pos, Balancing.player["reach_m"])
		if d < best_d:
			best_d = d
			best = item
	return best


func _build_server_room() -> void:
	_room = ServerRoomView.new()
	_room.name = "ServerRoom"
	add_child(_room)
	_room.position = ServerRoomView.center()
	_room.setup()
	_room.refresh(_economy.state)
	_props = YardProps.new()
	_props.name = "YardProps"
	add_child(_props)
	_props.build(_city)


func _place_reel(kind: ReelData.Kind) -> void:
	var pl: Dictionary = Balancing.placement
	var pos := _ground_spot(_player.global_position + _player.facing() * float(pl["distance_ahead_m"]))
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
		for port in RackPlan.tutorial_count():
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
	for cid: int in _removed_ids.keys():
		if cid < CableUnit.ID_BASE:
			_removed_ids.erase(cid)
	_batcher.remove_owner("zone")
	var cables := _zone.create_cables(first_id, free_ports)
	# Streukabel dürfen nicht durch die Wand des Serverraums laufen: an die Vorderwand schieben
	var room := ServerRoomView.rect().grow(0.6)
	for cable in cables:
		for i in cable.path.points.size():
			var pt := cable.path.points[i]
			if room.has_point(Vector2(pt.x, pt.z)):
				cable.path.points[i].z = room.position.y
		_system.add_cable(cable)
		if cable.is_important():
			_make_view(cable)
	# Gewöhnliche Kabel blockweise je Haufen zeichnen
	var groups: Dictionary = {}  # Haufen-Mitte -> [Kabel]
	for cable in cables:
		if not cable.is_important():
			if not groups.has(cable.heap_center):
				groups[cable.heap_center] = []
			(groups[cable.heap_center] as Array).append(cable)
	var plan_in: Array = []
	var flat: Array[CableData] = []
	for center: Vector3 in groups:
		var list: Array = groups[center]
		var ids := PackedInt32Array()
		var reach := 0.0
		for c: CableData in list:
			ids.append(flat.size())
			flat.append(c)
			for pt in [c.path.points[0], c.path.points[c.path.points.size() - 1]]:
				reach = maxf(reach, Vector2(pt.x - center.x, pt.z - center.z).length())
		plan_in.append({ "indices": ids, "center": center, "radius": reach / 1.3 })
	for pl: Dictionary in CableBatch.plan(plan_in):
		var part: Array[CableData] = []
		for i in (pl["indices"] as PackedInt32Array):
			part.append(flat[i])
		_batcher.add_now("zone", part, pl["origin"], float(pl["extent"]))
	_next_cable_id += cables.size()


# --- Kabel in der Stadt: Laden und Entladen -------------------------------

## Lädt Einheiten in der Nähe und entlädt weit entfernte. `now` = sofort vollständig laden (Spielstart).
func _stream_update(now: bool) -> void:
	var cfg: Dictionary = _city.layout.raw().get("streaming", {})
	var load_m := float(cfg.get("load_m", 150.0))
	var unload_m := float(cfg.get("unload_m", 220.0))
	var points: Array[Vector3] = []
	for ctx: PlayerCtx in _players.values():
		if _authority or ctx == _me:
			points.append(ctx.node.global_position)
	if _tools:
		points.append_array(_tools.stream_points())  # Drohnen-Einsatzort und Winden halten ihre Kabel geladen
	for u in _units:
		var dist := INF
		for p in points:
			dist = minf(dist, u.distance_to(p))
		if dist < load_m and not _unit_loaded.has(u.id):
			_load_unit(u, now)
		elif dist > unload_m and _unit_loaded.has(u.id) and not _unit_busy(u):
			_unload_unit(u)


## Einheit laden: Kabel und Meshes entstehen blockweise in Threads und kommen nach und nach dazu.
## `now` = warten, bis alles da ist (Spielstart, Spielstand mit eingehängten Kabeln).
func _load_unit(u: CableUnit, now: bool) -> void:
	if _unit_loaded.has(u.id):
		if now:
			_batcher.finish_owner(u.id)
		return
	_unit_loaded[u.id] = true
	var skip := {}
	for cid: int in _removed_ids.keys():
		if u.owns(cid):
			skip[cid] = true
	_batcher.load_async(u.id, u.batch_plan(), u.make_cable, skip, _on_unit_batch.bind(u), now)


## Ein Block einer Einheit ist fertig: Kabel in die Logik übernehmen, gemerkte Zustände zurückholen
func _on_unit_batch(batch: CableBatch, normal: Array[CableData], important: Array[CableData], u: CableUnit) -> void:
	if not _unit_loaded.has(u.id):
		return
	for list: Array[CableData] in [normal, important]:
		for cable in list:
			var cid := cable.id
			if _removed_ids.has(cid) or _system.cables.has(cid):
				if batch:
					batch.set_hidden(cid, true)
				continue
			if _stored_states.has(cid):
				var st: Dictionary = _stored_states[cid]
				_stored_states.erase(cid)
				if int(st.get("state", 0)) != CableData.State.HOOKED:
					cable.load_state(st)
			_system.add_cable(cable)
	for cable in important:
		if _system.cables.get(cable.id) == cable:
			_make_view(cable)


## Einzelne Darstellung für ein Kabel (wichtige, gegriffene und gelieferte Kabel)
func _make_view(cable: CableData) -> CableView:
	var view := CableView.new()
	add_child(view)
	view.setup(cable)
	_views[cable.id] = view
	return view


## Gegriffen bzw. umgehängt: Kabel bekommt eine eigene Darstellung, im Block wird es ausgeblendet
func _on_cable_hooked(cable: CableData, _reel: ReelData) -> void:
	if not _views.has(cable.id):
		_make_view(cable)
	_batcher.set_hidden(cable.id, true)


## Kabel ganz aus dem Spiel nehmen (fertig gemeldet, Spielstand, Test): Logik, Darstellung, Block
func _drop_cable(cid: int) -> void:
	_removed_ids[cid] = true
	if _views.has(cid):
		_views[cid].queue_free()
		_views.erase(cid)
	_batcher.set_hidden(cid, true)
	_system.remove_cable(cid)


## Einheit entladen: Kabel aus der Szene nehmen, veränderte Zustände für später aufheben
func _unload_unit(u: CableUnit) -> void:
	_unit_loaded.erase(u.id)
	_batcher.remove_owner(u.id)
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
		for cid: int in _removed_ids.keys():
			if u.owns(cid):
				removed += 1
		var cleared := removed >= int(ceil(u.cable_total() * u.clear_fraction))
		if cleared and _blockers.has(u.id):
			_blockers[u.id].queue_free()
			_blockers.erase(u.id)
			if _authority:
				_announce("%s abgetragen – der Weg ist frei!" % u.name)
		elif not cleared and not _blockers.has(u.id):
			var body := StaticBody3D.new()
			body.name = "Blocker_%s" % u.id
			for box: Array in u.blocker_boxes:
				var col := CollisionShape3D.new()
				var shape := BoxShape3D.new()
				shape.size = box[1]
				col.shape = shape
				col.position = box[0]
				body.add_child(col)
			add_child(body)
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
	var presses := _system.untie_needed()
	if held and held.is_stuck():
		_hint.text = "Knoten! E: lösen (%d/%d)" % [held.knot_presses, presses]
	elif _target_knot:
		_hint.text = "E: Knoten lösen (%d/%d)" % [_target_knot.knot_presses, presses]
	elif not _bag.is_empty() and _target_post:
		_hint.text = "E: %d Knäuel per Rohrpost in den Serverraum" % _bag.size()
	elif not _bag.is_empty() and _target_rack:
		_hint.text = ("E: %d Knäuel einstecken" % _bag.size()) if _bag.size() > 1 else "E: Knäuel einstecken (%s)" % RackPlan.port_label(_bag[0].port_id)
	elif not _ride.is_empty():
		_hint.text = "Seilbahn: %s" % (_ride["line"] as Zipline).line_name
	elif _carried_reel:
		_hint.text = "E oder Q: %s hier abstellen" % _reel_name(_carried_reel)
	elif held and _target_reel and _target_reel.is_free():
		_hint.text = "E: Kabel an %s einhängen" % _reel_name(_target_reel)
	elif not held and _target_reel and _wagon and _wagon.owns(_target_reel):
		if not _wagon.parked:
			_hint.text = "E: Wagen hier parken"
		elif _wagon.any_hooked():
			_hint.text = "E: Wagen ankoppeln (löst die eingehängten Kabel)" + ("  – nochmal E!" if _wagon_confirm_t > 0.0 else "")
		else:
			_hint.text = "E: Wagen ankoppeln (folgt dir)"
	elif not held and _target_reel and _target_reel.is_movable() and (_target_reel.is_free() or _target_reel.kind == ReelData.Kind.WINCH):
		_hint.text = "E: %s aufheben und umstellen" % _reel_name(_target_reel)
	elif _target_stop >= 0:
		var stop_name := String(_tower.stops[(_target_stop + 1) % _tower.stops.size()]["name"])
		if _tower_open or _tower_open_override:
			_hint.text = "E: Aufzug nach oben – %s" % stop_name if _target_stop + 1 < _tower.stops.size() else "E: Aufzug nach unten – Erdgeschoss"
		else:
			_hint.text = "Aufzug außer Betrieb – erst alle anderen Viertel ans Netz bringen (%d von %d Ports)" % [
				mini(_economy.state.active_ports.size(), _tower_gate_ports()), _tower_gate_ports()]
	elif _target_core:
		if _economy.state.finale_done:
			_hint.text = "C.O.R.D.s Kern ist abgeschaltet. Die Cloud läuft wieder."
		elif _economy.state.active_ports.size() >= RackPlan.total_ports():
			_hint.text = "E: C.O.R.D.s Kern abschalten"
		else:
			_hint.text = "C.O.R.D.s Kern – erst alle %d Ports belegen (noch %d)" % [RackPlan.total_ports(),
				RackPlan.total_ports() - _economy.state.active_ports.size()]
	elif not _target_station.is_empty():
		var zl: Zipline = _target_station[0]
		if RackPlan.has_special(_economy.state, zl.unlock):
			_hint.text = "E: Seilbahn %s" % ("zur Basis" if _target_station[1] == 0 else "hinaus")
		else:
			_hint.text = "Seilbahn außer Betrieb – braucht Dienst „%s“" % _zipline_service(zl)
	elif held and _player.at_tether_limit:
		_hint.text = "Das Kabel ist gespannt – erst aufwickeln oder an eine Rolle hängen (Q: loslassen)"
	elif held:
		_hint.text = "Linksklick: wickeln   ·   Q: loslassen"
	elif _target_item:
		_hint.text = "E: Knäuel aufheben (%s)" % RackPlan.port_label(_target_item.port_id)
	elif _target_end:
		_hint.text = "E: wichtiges Kabel greifen" if _target_end.is_important() else "E: Kabelende greifen"
	else:
		var crank := CableTargeting.nearest_reel(_system.reels.values(), _player.global_position, ReelData.Kind.HAND)
		if crank and not crank.is_free():
			_hint.text = "Linksklick: kurbeln"
		else:
			_hint.text = "Knäuel in den Serverraum bringen   ·   Q: eins ablegen" if _bag_full() else ("Linksklick halten: Kabelsauger   ·   E: Kabelende greifen" if not _tools.vacuum_reels.is_empty() else "Ein Kabelende am Rand des Haufens anvisieren")

	var line := "Kabel im Haufen: %d   ·   Aufgerollt: %d   ·   Dienste: %d/%d   ·   Tasche: %d/%d" % [
		_heap_count(), _done_count, _rack.active_services(), RackPlan.total_services(), _bag.size(), _economy.bag_capacity()]
	var progress := _district_progress()
	if progress != "":
		line += "\n" + progress
	var busy := {}  # Werkzeug-Art -> Zahl der Kabel (Sauger, Winden, Drohnen nur zusammengefasst)
	for reel: ReelData in _system.reels.values():
		var c := _system.cable_on(reel)
		if c == null:
			continue
		if reel.is_automatic():
			var key := _reel_name(reel) if reel.kind != ReelData.Kind.WINCH else "Haufen-Winden"
			busy[key] = int(busy.get(key, 0)) + 1
			continue
		var who := "Am Arm" if reel.kind == ReelData.Kind.ARM else _reel_name(reel)
		line += "\n%s: %.1f von %.1f m%s%s" % [who, c.pulled_m, c.length_m,
			"  (wichtig)" if c.is_important() else "", "  – KNOTEN!" if c.is_stuck() else ""]
	for key: String in busy:
		line += "\n%s: %d Kabel" % [key if key != "Drohne" else "Drohnen", busy[key]]
	_status.text = line
	_status.reset_size()  # Hintergrund passt sich dem Text an
	_toast.visible = _message_t > 0.0 and _message != ""
	if _toast.visible:
		_toast.text = _message
		_toast.modulate.a = clampf(_message_t / 0.4, 0.0, 1.0)
		# Kurze Meldung in einer Zeile, lange umbrechen (höchstens 900 px breit)
		var w := UiTheme.font().get_string_size(_message, HORIZONTAL_ALIGNMENT_LEFT, -1, 19).x + 46.0
		_toast.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART if w > 900.0 else TextServer.AUTOWRAP_OFF
		_toast.custom_minimum_size.x = minf(w, 900.0)
		_toast.reset_size()
		_toast.position.x = (_hud_width() - _toast.size.x) * 0.5
	_hint.visible = _hint.text != ""
	_hint.reset_size()
	_hint.position.x = (_hud_width() - _hint.size.x) * 0.5

	_money.text = Economy.format_money(_economy.state.money)
	_shop.text = "Tab  Tablet"
	# Pillen oben rechts so breit wie ihr Text, rechtsbündig
	for l: Label in [_money, _shop]:
		l.reset_size()
		l.position.x = _hud_width() - 20.0 - l.size.x


## Anzeige im Spielzeug-Look (UiTheme): Statuskarte oben links, Geld als gelbe Pille, Hinweis unten,
## Meldungen als helle Sprechblase darüber
func _style_hud() -> void:
	UiTheme.style_hud_label(_status, 18)
	_status.add_theme_stylebox_override("normal", UiTheme.hud_box())
	_status.add_theme_constant_override("line_spacing", 2)
	_status.size = Vector2.ZERO
	UiTheme.style_label(_money, 30, UiTheme.INK)
	var pill := UiTheme.box(UiTheme.YELLOW, UiTheme.YELLOW_DARK, 26, 0, 6, 8)
	pill.border_width_bottom = 6
	pill.border_color = UiTheme.YELLOW_DARK
	pill.content_margin_left = 22
	pill.content_margin_right = 22
	_money.add_theme_stylebox_override("normal", pill)
	_money.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	UiTheme.style_label(_shop, 16, Color.WHITE)
	var key := UiTheme.box(UiTheme.BLUE, UiTheme.BLUE_DARK, 14, 0, 4, 6)
	key.border_width_bottom = 4
	key.border_color = UiTheme.BLUE_DARK
	key.content_margin_left = 14
	key.content_margin_right = 14
	_shop.add_theme_stylebox_override("normal", key)
	_shop.offset_top = 78
	UiTheme.style_label(_hint, 20, Color.WHITE)
	_hint.add_theme_stylebox_override("normal", UiTheme.hud_box(Color(0.1, 0.13, 0.22, 0.72), 22))
	_hint.anchor_left = 0.0
	_hint.anchor_right = 0.0
	_hint.grow_horizontal = Control.GROW_DIRECTION_END
	_toast = Label.new()
	UiTheme.style_label(_toast, 19, UiTheme.INK)
	var bubble := UiTheme.box(UiTheme.PAPER, UiTheme.BLUE, 20, 3, 6, 12)
	bubble.content_margin_left = 20
	bubble.content_margin_right = 20
	_toast.add_theme_stylebox_override("normal", bubble)
	_toast.autowrap_mode = TextServer.AUTOWRAP_OFF
	_toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toast.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_toast.offset_top = -150
	_toast.offset_bottom = -110
	_toast.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_toast.visible = false
	_hud.add_child(_toast)


func _hud_width() -> float:
	return get_viewport().get_visible_rect().size.x if is_inside_tree() else 1600.0


## Kabel-Detektor: nächstes wichtiges Kabelende im Haufen suchen (einige Male pro Sekunde)
func _update_detector(delta: float) -> void:
	_detector.visible = _economy.state.level("detector") > 0
	_detector.show_arrow = _economy.state.level("detector_arrow") > 0
	if not _detector.visible:
		return
	_detector_t -= delta
	if _detector_t > 0.0:
		return
	_detector_t = float(Balancing.detector.get("scan_interval_s", 0.25))
	var p := _player.global_position
	var best := INF
	var best_point := Vector3.ZERO
	for c: CableData in _system.important.values():
		if c.state != CableData.State.HEAP:
			continue
		var pts := c.path.points
		for q in [pts[0], pts[pts.size() - 1]]:
			var d := p.distance_to(q)
			if d < best:
				best = d
				best_point = q
	_detector.has_target = best < INF
	_detector.distance = best
	_detector.target = best_point


## „Gamer-Viertel: 37 von 200 …“ für das Viertel, in dem der Spieler steht (zweimal pro Sekunde neu)
func _district_progress() -> String:
	var now := Time.get_ticks_msec() / 1000.0
	if now - _progress_t < 0.5:
		return _progress_text
	_progress_t = now
	var p := _player.global_position
	var sec_id := String(_city.district_at(p.x, p.z).get("id", ""))
	# Rund um den Wolkig-Turm zählt der Turm-Schrank
	for l: Dictionary in _city.layout.landmarks:
		if String(l["id"]) == "turm":
			var t := _city.to_scene(WorldLayout._v2(l["pos"]))
			if Vector2(p.x - t.x, p.z - t.z).length() < 70.0:
				sec_id = "turm"
	var sec := RackPlan.section(sec_id)
	if sec.is_empty():
		_progress_text = ""
	else:
		_progress_text = "%s: %d von %d wichtigen Kabeln eingesteckt" % [sec["name"],
			RackPlan.section_plugged(_economy.state, sec_id), int(sec["count"])]
	return _progress_text


## Kabel im Haufen (nur einmal pro Sekunde gezählt; bei zehntausenden Kabeln zu teuer für jedes Bild)
func _heap_count() -> int:
	var now := Time.get_ticks_msec() / 1000.0
	if now - _heap_count_t < 1.0:
		return _heap_count_cache
	_heap_count_t = now
	var n := 0
	for c: CableData in _system.cables.values():
		if c.state == CableData.State.HEAP:
			n += 1
	_heap_count_cache = n
	return n


## Meldung an die Figur, für die gerade gehandelt wird (Mitspieler bekommen sie übers Netz)
func _show_message(text: String) -> void:
	if _replaying:
		return
	if _actor != null and _actor != _me:
		Net.send_event("msg", { "t": text }, _actor.id)
		return
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


# --- Werkzeug zum Mitnehmen ---------------------------------------------------

func _reel_name(reel: ReelData) -> String:
	match reel.kind:
		ReelData.Kind.HAND:
			return "Handkurbel"
		ReelData.Kind.WAGON:
			return "Wagen, Platz %d" % (_wagon.slots.find(reel) + 1) if _wagon else "Wagen"
		ReelData.Kind.WINCH:
			return "Haufen-Winde"
		ReelData.Kind.VACUUM:
			return "Kabelsauger"
		ReelData.Kind.DRONE:
			return "Drohne"
		_:
			return "Motorrolle %d" % reel.id


# --- Story ------------------------------------------------------------------------

## Intro abspielen: Spiel läuft im Hintergrund, Spieler und C.O.R.D. warten, Anzeige aus
func _play_intro(jump: int = 0) -> void:
	var intro := IntroScene.new()
	intro.name = "Intro"
	add_child(intro)
	_player.input_enabled = false
	_hud.visible = false
	_cord.enabled = false
	intro.finished.connect(func() -> void:
		_player.input_enabled = true
		_hud.visible = true
		_cord.enabled = not _economy.state.finale_done
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		_show_message("Der Serverraum steht hinter dir. Wichtige Kabel leuchten – ihre Knäuel gehören dort in die Schränke."))
	intro.start(_player)
	if jump > 0:
		intro.jump_to(jump)


# --- Finale im Wolkig-Turm ---------------------------------------------------

## Ports, die vor dem Aufzug belegt sein müssen (alle Schränke außer dem Turm)
func _tower_gate_ports() -> int:
	return int(RackPlan.sections()[-1]["first_port"])


## Aufzug freigeben, sobald alle anderen Schränke voll sind; Kern-Zustand setzen. announce = Meldung zeigen
func _refresh_finale(announce: bool) -> void:
	var was := _tower_open
	_tower_open = RackPlan.all_but_last_plugged(_economy.state)
	_tower.set_unlocked(_tower_open or _tower_open_override)
	_tower.set_core_on(not _economy.state.finale_done)
	if _economy.state.finale_done and _cord:
		_cord.enabled = false
		_cord_view.sleeping = true
	if announce and _tower_open and not was:
		_show_message("Alle Viertel laufen wieder! Der Aufzug im Wolkig-Turm fährt jetzt – oben warten die letzten Kabel.")
	if announce and _economy.state.active_ports.size() >= RackPlan.total_ports() and not _economy.state.finale_done:
		_show_message("Alle 2000 Ports belegt! Auf dem Dach des Wolkig-Turms wartet C.O.R.D.s Kern.")


## Mit dem Aufzug zum nächsten Halt (unten → Etage 40 → Dach → unten)
func _ride_elevator(from: int, holding_cable: bool) -> void:
	if not (_tower_open or _tower_open_override):
		_show_message("Der Aufzug fährt erst, wenn alle anderen Viertel wieder am Netz sind.")
		return
	if holding_cable:
		_show_message("Mit Kabel am Arm passt du nicht in den Aufzug – erst aufrollen oder loslassen (Q).")
		return
	var to := (from + 1) % _tower.stops.size()
	var stop: Dictionary = _tower.stops[to]
	_player.global_position = (stop["pos"] as Vector3) + Vector3(0, 0.1, 0)
	_player.velocity = Vector3.ZERO
	_show_message("Ding! %s." % String(stop["name"]))


## C.O.R.D.s Kern abschalten: das Finale
func _use_core() -> void:
	if _economy.state.finale_done:
		return
	if _economy.state.active_ports.size() < RackPlan.total_ports():
		_show_message("C.O.R.D.: „Zugriff verweigert. Es fehlen noch %d Ports.“" % (RackPlan.total_ports() - _economy.state.active_ports.size()))
		return
	_economy.state.finale_done = true
	_refresh_finale(false)
	_econ_dirty = true
	Net.send_event("finale")
	_show_finale_screen()


func _show_finale_screen() -> void:
	if _finale_screen:
		return
	_finale_screen = FinaleScreen.new()
	_hud.add_child(_finale_screen)
	_finale_screen.setup(_done_count, _economy.state.total_earned)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_player.input_enabled = false
	_finale_screen.closed.connect(func() -> void:
		_finale_screen.queue_free()
		_finale_screen = null
		_player.input_enabled = true
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED)


## Steht eine belegte Handkurbel in Reichweite? (Linksklick kurbelt dann statt zu saugen)
func _crank_in_reach() -> bool:
	var crank := CableTargeting.nearest_reel(_system.reels.values(), _player.global_position, ReelData.Kind.HAND)
	return crank != null and not crank.is_free()


## Punkt am Boden (Gelände) unter `p`
func _ground_spot(p: Vector3) -> Vector3:
	var terrain := _city.ground_height(p.x, p.z)
	# Hoch oben (Plattform, Dach): die Fläche darunter per Strahl suchen, sonst das Gelände
	if p.y > terrain + 3.0 and is_inside_tree():
		var hit := get_world_3d().direct_space_state.intersect_ray(
			PhysicsRayQueryParameters3D.create(p + Vector3(0, 1.5, 0), p - Vector3(0, 8.0, 0)))
		if not hit.is_empty():
			return Vector3(p.x, (hit["position"] as Vector3).y, p.z)
	return Vector3(p.x, terrain, p.z)


func _pick_up_reel(reel: ReelData) -> void:
	reel.carried = true
	reel.carrier_id = _actor.id
	_carried_reel = reel
	_reel_views[reel.id].set_carried(true)
	_show_message("%s aufgehoben – E oder Q stellt sie wieder ab." % _reel_name(reel))


func _put_down_reel() -> void:
	var reel := _carried_reel
	var pos := _ground_spot(_player.global_position + _player.facing() * float(Balancing.placement["distance_ahead_m"]))
	reel.position = pos
	reel.carried = false
	_carried_reel = null
	var view: ReelView = _reel_views[reel.id]
	view.set_carried(false)
	view.global_position = pos
	_show_message("%s abgestellt." % _reel_name(reel))


## Getragene Rolle schwebt verkleinert neben der Figur
func _update_carried_reel() -> void:
	if _carried_reel == null:
		return
	var side := _player.facing().cross(Vector3.UP)
	var p := _player.global_position + side * 0.55 + _player.facing() * 0.2 + Vector3(0, 0.55, 0)
	_carried_reel.position = p
	_reel_views[_carried_reel.id].global_position = p


## Wagen anlegen (neu hinter dem Spieler oder aus dem Spielstand)
func _spawn_wagon(saved: Variant) -> void:
	_wagon = WagonData.new()
	var w: Dictionary = Balancing.wagon
	var ids: Array = (saved as Dictionary).get("slots", []) if saved != null else []
	for i in int(w.get("slots", 3)):
		var reel: ReelData = null
		if i < ids.size():
			reel = _system.reels.get(int(ids[i]))
		if reel == null:
			reel = ReelData.new(_next_reel_id, ReelData.Kind.WAGON)
			_add_reel(reel)
		_wagon.slots.append(reel)
	if saved != null:
		_wagon.position = SaveGame.vec_from(saved.get("position", [0, 0, 0]))
		_wagon.yaw = float(saved.get("yaw", 0.0))
		_wagon.parked = bool(saved.get("parked", false))
	else:
		_wagon.position = _ground_spot(_player.global_position - _player.facing() * float(w.get("follow_distance_m", 3.2)))
		_wagon.yaw = atan2(-_player.facing().x, -_player.facing().z)
	_wagon_view = WagonView.new()
	add_child(_wagon_view)
	_wagon_view.setup(_wagon)
	_update_wagon(0.0)


## Wagen folgt dem Spieler, solange er nicht parkt; Plätze und Trommeln wandern mit
func _update_wagon(delta: float) -> void:
	if _wagon == null:
		return
	if not _authority:
		# Client: Lage kommt vom Host, hier nur Plätze und Trommeln nachziehen
		_wagon.update_slots()
		for slot in _wagon.slots:
			if _reel_views.has(slot.id):
				_reel_views[slot.id].global_position = slot.position
				_reel_views[slot.id].rotation.y = _wagon.yaw
		_wagon_view.refresh()
		return
	# Der Wagen folgt der Figur, die ihn zuletzt angekoppelt hat
	var driver: PlayerCtx = _wagon_driver if _wagon_driver and _players.has(_wagon_driver.id) else _me
	var before := _actor
	_actor = driver
	_update_wagon_core(delta)
	_actor = before


func _update_wagon_core(delta: float) -> void:
	var w: Dictionary = Balancing.wagon
	var me := _player.global_position
	var dist := Vector2(me.x - _wagon.position.x, me.z - _wagon.position.z).length()
	# Geparkt wegen Kabeln und alle fertig: koppelt sich wieder an, sobald der Spieler in der Nähe ist
	if _wagon.parked and _wagon.get_meta("auto", false) and not _wagon.any_hooked() and dist < float(w.get("recouple_range_m", 8.0)):
		_wagon.parked = false
		_wagon.set_meta("auto", false)
		_show_message("Wagen fertig – er folgt dir wieder.")
	if _wagon.any_hooked() and _wagon.parked:
		_wagon.set_meta("auto", true)
	if not _wagon.parked and _ride.is_empty():
		var keep := float(w.get("follow_distance_m", 3.2))
		if dist > keep:
			var to := Vector3(me.x - _wagon.position.x, 0, me.z - _wagon.position.z).normalized()
			var step := minf(dist - keep, maxf(dist - keep, 1.0) * float(w.get("follow_speed", 5.0)) * delta)
			var p := _wagon.position + to * step
			_wagon.position = _ground_spot(p)
			_wagon.yaw = lerp_angle(_wagon.yaw, atan2(-to.x, -to.z), 1.0 - exp(-6.0 * delta))
	_wagon.update_slots()
	for slot in _wagon.slots:
		_reel_views[slot.id].global_position = slot.position
		_reel_views[slot.id].rotation.y = _wagon.yaw
	_wagon_view.refresh()


func _toggle_wagon() -> void:
	if not _wagon.parked:
		_wagon.parked = true
		_wagon.set_meta("auto", false)
		_show_message("Wagen geparkt. Kabel daran einhängen oder mit E wieder ankoppeln.")
		return
	if _wagon.any_hooked() and _wagon_confirm_t <= 0.0:
		_wagon_confirm_t = 3.0
		_show_message("Ankoppeln lässt die eingehängten Kabel los (Fortschritt geht verloren). Nochmal E zum Bestätigen.")
		return
	for slot in _wagon.slots:
		if not slot.is_free():
			_system.release(slot)
	_wagon_confirm_t = 0.0
	_wagon.parked = false
	_wagon.set_meta("auto", false)
	_wagon_driver = _actor
	_show_message("Wagen angekoppelt – er folgt dir.")


# --- Seilbahn -------------------------------------------------------------------

# --- Rohrpost ---------------------------------------------------------------------

## Je Viertel eine Rohrpost-Station (Lage aus dem Viertel, world.json → pneumatic_post)
func _build_posts() -> void:
	for d in _city.layout.districts:
		var post := PneumaticPost.new()
		post.name = "Rohrpost_%s" % d["id"]
		add_child(post)
		if post.setup(_city, d):
			_posts.append(post)
		else:
			post.queue_free()


func _refresh_posts() -> void:
	for post in _posts:
		post.set_active(_economy.state.posts.has(post.district_id))


## Station in Betrieb, die näher als `reach` ist (oder null)
func _post_near(pos: Vector3, reach: float) -> PneumaticPost:
	for post in _posts:
		if post.active and post.global_position.distance_to(pos) < reach:
			return post
	return null


## Nächste Abgabe für Knäuel: { "pos", "post" } – Serverraum oder eine Rohrpost-Station in Betrieb
func delivery_point(from: Vector3) -> Dictionary:
	var best := { "pos": ServerRoomView.door_point(), "post": null }
	var best_d := from.distance_to(best["pos"])
	for post in _posts:
		if post.active and from.distance_to(post.global_position) < best_d:
			best_d = from.distance_to(post.global_position)
			best = { "pos": post.global_position, "post": post }
	return best


## Host: Stationen gehen in Betrieb, sobald jemand zum ersten Mal in der Nähe ist
func _update_posts(delta: float) -> void:
	if not _authority:
		return
	_post_t -= delta
	if _post_t > 0.0:
		return
	_post_t = 0.5
	var reach := float(_city.layout.raw().get("pneumatic_post", {}).get("activate_m", 14.0))
	for post in _posts:
		if post.active:
			continue
		for ctx: PlayerCtx in _players.values():
			if ctx.node.global_position.distance_to(post.global_position) < reach:
				_economy.state.posts.append(post.district_id)
				post.set_active(true)
				_econ_dirty = true
				_announce("Rohrpost-Station %s in Betrieb: Knäuel hier einwerfen, sie landen direkt im Serverraum." % post.district_name)
				break


func _build_ziplines() -> void:
	for cfg: Dictionary in _city.layout.raw().get("ziplines", []):
		var zl := Zipline.new()
		zl.name = String(cfg["id"])
		add_child(zl)
		zl.build(cfg, _city)
		_ziplines[zl.id] = zl
	_refresh_ziplines()


func _refresh_ziplines() -> void:
	for zl: Zipline in _ziplines.values():
		zl.set_unlocked(RackPlan.has_special(_economy.state, zl.unlock), "„%s“" % _zipline_service(zl))


func _zipline_service(zl: Zipline) -> String:
	for service in RackPlan.total_services():
		if String(RackPlan.service_def(service).get("special", "")) == zl.unlock:
			return "%s (%s)" % [RackPlan.service_name(service), RackPlan.service_place(service)]
	return "?"


## Station in Reichweite: [Strecke, 0 = äußeres Ende / 1 = Basis-Seite] oder []
func _station_near(pos: Vector3) -> Array:
	var reach := float(Balancing.zipline.get("station_reach_m", 3.0))
	for zl: Zipline in _ziplines.values():
		for k in 2:
			var st: Vector3 = zl.stations[k]
			if Vector2(st.x - pos.x, st.z - pos.z).length() < reach and absf(st.y - pos.y) < 3.0:
				return [zl, k]
	return []


## Fahrt starten: vom äußeren Ende zur Basis (dir +1) oder von der Basis-Seite hinaus (dir -1)
func _start_ride(zl: Zipline, station: int) -> void:
	if not RackPlan.has_special(_economy.state, zl.unlock):
		_show_message("Diese Seilbahn läuft erst, wenn der Dienst „%s“ wieder online ist." % _zipline_service(zl))
		return
	_ride = { "line": zl, "s": 0.0 if station == 0 else zl.length, "dir": 1.0 if station == 0 else -1.0,
		"v": float(Balancing.zipline.get("start_speed_m_per_s", 6.0)) }
	_player.riding = true
	if _trolley == null:
		_trolley = MeshInstance3D.new()
		var b := BoxMesh.new()
		b.size = Vector3(0.5, 0.35, 0.7)
		_trolley.mesh = b
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(0.97, 0.8, 0.3)
		_trolley.material_override = m
		add_child(_trolley)
	_trolley.visible = true
	_show_message("Festhalten!")


func _update_ride(delta: float) -> void:
	if _ride.is_empty():
		return
	var zl: Zipline = _ride["line"]
	var z: Dictionary = Balancing.zipline
	# Anfahren bis Höchsttempo, vor der Endstation abbremsen (Anschluss-Strecke zählt zur Bremsstrecke)
	var dir := float(_ride["dir"])
	var left := zl.length - float(_ride["s"]) if dir > 0.0 else float(_ride["s"])
	var next_line: Zipline = _ziplines.get(zl.continues) if dir > 0.0 else null
	if next_line and RackPlan.has_special(_economy.state, next_line.unlock):
		left += next_line.length
	var v_end := float(z.get("arrive_speed_m_per_s", 5.0))
	var v_max := minf(float(z.get("speed_m_per_s", 16.0)),
		sqrt(v_end * v_end + 2.0 * float(z.get("brake_m_per_s2", 12.0)) * maxf(left, 0.0)))
	var v := float(_ride.get("v", v_max))
	v = minf(v + float(z.get("accel_m_per_s2", 10.0)) * delta, v_max)
	_ride["v"] = v
	var s := float(_ride["s"]) + dir * v * delta
	_ride["s"] = s
	var on_rope := zl.point_at(s)
	_trolley.global_position = on_rope + Vector3(0, 0.1, 0)
	_player.global_position = on_rope - Vector3(0, float(z.get("hang_m", 2.3)), 0)
	_player.velocity = Vector3.ZERO
	var ahead := zl.point_at(s + float(_ride["dir"]) * 2.0) - on_rope
	if ahead.length() > 0.1:
		_player.face_direction(ahead)
	var done := s >= zl.length if float(_ride["dir"]) > 0.0 else s <= 0.0
	if not done:
		return
	# Weiter auf der Anschluss-Strecke Richtung Basis?
	var next: Zipline = _ziplines.get(zl.continues) if float(_ride["dir"]) > 0.0 else null
	if next and RackPlan.has_special(_economy.state, next.unlock):
		_ride = { "line": next, "s": 0.0, "dir": 1.0, "v": float(_ride["v"]) }
		return
	var st: Vector3 = zl.stations[1 if float(_ride["dir"]) > 0.0 else 0]
	_ride = {}
	_player.riding = false
	_player.global_position = st + Vector3(0, 0.35, 0)
	_trolley.visible = false
	_show_message("Angekommen.")


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
		if not r.is_transient():
			var rd := r.to_dict()
			if r.carried:
				rd["position"] = SaveGame.vec_to(_ground_spot(_player.global_position + _player.facing()))
			reels.append(rd)
	var items := []
	for item: CoilItem in _items.values():
		var idd := item.to_dict()
		if item.carried_by <= -100:
			# Von einer Drohne getragen: liegt im Spielstand unter der Drohne
			idd["carried_by"] = -1
			idd["position"] = SaveGame.vec_to(_ground_spot(item.position))
		items.append(idd)
	var orders := []
	for o in _order_heaps:
		orders.append({ "heap": (o["heap"] as HeapData).to_dict(), "first_id": o["first_id"] })
	return {
		"zone": { "seed": _zone.rng_seed, "ports": Array(_zone_ports), "first_id": _zone_first_id },
		"orders": orders,
		"removed_cables": _removed_ids.keys(),
		"cables": cables,
		"arm_cable": _arm_reel.cable_id,
		"reels": reels,
		"items": items,
		"wagon": _wagon.to_dict() if _wagon else {},
		"drones": { "anchor": SaveGame.vec_to(_tools.drone_anchor) },
		"economy": _economy.state.to_dict(),
		"cord": _cord.to_dict(),
		"player": _player.view_state(),
		"counters": { "next_cable_id": _next_cable_id, "next_reel_id": _next_reel_id,
			"next_item_id": _next_item_id, "done_count": _done_count, "orders": _orders },
	}


func _apply_save(d: Dictionary) -> void:
	_economy.state.load_dict(d.get("economy", {}))
	if d.has("drones"):
		_tools.drone_anchor = SaveGame.vec_from((d["drones"] as Dictionary).get("anchor", [0, 0, 0]))
	_apply_upgrades()
	_room.refresh(_economy.state)

	for o: Dictionary in d.get("orders", []):
		_add_order_heap(HeapData.from_dict(o["heap"]), int(o["first_id"]), false)
	for id in d.get("removed_cables", []):
		_drop_cable(int(id))

	for rd: Dictionary in d.get("reels", []):
		var reel := ReelData.from_dict(rd)
		reel.cable_id = -1
		_add_reel(reel)
	if not (d.get("wagon", {}) as Dictionary).is_empty():
		_spawn_wagon(d["wagon"])

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
			_on_cable_hooked(cable, reel)
			if reel == _arm_reel:
				_player.holding = true
				_player.tether_anchor = cable.path.points[0]
			if cable.is_stuck():
				_add_knot_marker(cable)

	# Client: Knäuel und Taschen meldet der Host gleich danach einzeln
	for idd: Dictionary in (d.get("items", []) if _authority else []):
		var item := CoilItem.from_dict(idd)
		_items[item.id] = item
		var iv := CoilItemView.new()
		add_child(iv)
		iv.setup(item)
		_item_views[item.id] = iv
		if item.carried_by >= 0 and not _bag_full():
			_put_in_bag(item)
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


## Neuer Auftrag (Prestige): alles zurück auf Anfang, Ruf und Kosmetik bleiben
func _start_new_job() -> void:
	if not _economy.can_prestige():
		return
	SaveGame.carry_meta = _economy.prestige_meta()
	if _saving_enabled:  # mit --nosave den echten Spielstand nicht anfassen
		SaveGame.delete()
	SaveGame.force_new = true
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	get_tree().reload_current_scene()


func _new_game() -> void:
	if _saving_enabled:  # mit --nosave den echten Spielstand nicht anfassen
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
	var important := 0
	for c: CableData in _system.cables.values():
		if c.is_important():
			important += 1
	var gp := _player.global_position
	var hit := get_world_3d().direct_space_state.intersect_ray(
		PhysicsRayQueryParameters3D.create(gp + Vector3(0, 0.5, 0), gp + Vector3(0, -60, 0), 1, [_player.get_rid()]))
	var under := "%s@%.1f" % [hit["collider"].name, hit["position"].y] if hit else "nichts"
	var extra := "wagen=%s rolle_getragen=%s fahrt=%s " % [
		("geparkt" if _wagon.parked else "folgt") + ":%d/%d" % [_wagon.free_slots(), _wagon.slots.size()] if _wagon else "-",
		str(_carried_reel != null), ("%s@%.0f" % [(_ride["line"] as Zipline).id, float(_ride["s"])]) if not _ride.is_empty() else "-"]
	extra += "auftrag=%d ruf=%d looks=%s " % [_economy.state.prestige_count + 1, _economy.state.reputation,
		JSON.stringify(_economy.state.looks)]
	return extra + ("fps=%d boden=%.1f unter=%s " % [Engine.get_frames_per_second(), _city.ground_height(gp.x, gp.z), under]) + "wichtig=%d dienste=%d einheiten=%s sperren=%d geld=%.2f ports=%s upgrades=%s kabel=%d rollen=%d haengt=%s knaeuel=%d getragen=%s fertig=%d lieferungen=%d cord=%s/%.2f pos=%s" % [
		important, _rack.active_services(), str(loaded), _blockers.size(),
		_economy.state.money, str(_economy.state.active_ports) if _economy.state.active_ports.size() <= 24 else "%d Ports" % _economy.state.active_ports.size(), JSON.stringify(_economy.state.upgrades), _system.cables.size(),
		_system.reels.size(), str(hooked), _items.size(), "%d/%d" % [_bag.size(), _economy.bag_capacity()], _done_count, _orders,
		_cord.phase, _cord.time_left, str(SaveGame.vec_to(_player.global_position))]


## Testoptionen, z. B.:
## godot -- --money=50 --buy=crank,extra_reel --grab --important --noknots --pull=40 --hang --plug --tablet --orbit=-120
## Testoption --network: als Client übers Netz ein Kabel greifen und 40-mal ziehen (prüft Absichten und Zustand)
func _test_network(important := false) -> void:
	await get_tree().create_timer(3.0).timeout
	var best: CableData = null
	var best_d := INF
	if important:
		# Zum nächsten wichtigen Kabel gehen (Figur daneben stellen)
		for c: CableData in _system.important.values():
			var d := c.path.points[0].distance_to(_local_player.global_position)
			if c.state == CableData.State.HEAP and d < best_d:
				best_d = d
				best = c
		if best:
			_local_player.global_position = best.path.points[0] + Vector3(0.6, 0.3, 0.6)
			await get_tree().create_timer(0.6).timeout
			best_d = 0.8
	for c: CableData in ([] if important else _system.cables_near(_local_player.global_position, 6.0)):
		if c.state == CableData.State.HEAP:
			var d := c.path.points[0].distance_to(_local_player.global_position)
			if d < best_d:
				best_d = d
				best = c
	if best == null:
		print("NETZTEST: kein Kabel in Reichweite")
		return
	print("NETZTEST: greife Kabel %d (%.1f m)" % [best.id, best_d])
	_request("interact", { "end": best.id, "tail": false, "knot": -1, "reel": -1, "item": -1, "rack": false,
		"stop": -1, "core": false, "station": [] })
	await get_tree().create_timer(0.5).timeout
	# Ziehen bzw. Knoten lösen, bis das Kabel fertig ist (höchstens 120 Schritte)
	for k in 120:
		await get_tree().create_timer(0.12).timeout
		var held := _system.cable_on(_arm_reel)
		if held == null and _removed_ids.has(best.id):
			break
		if held and held.is_stuck():
			_request("interact", { "end": -1, "knot": held.id, "reel": -1, "item": -1, "stop": -1, "station": [] })
		else:
			_request("pull")
	await get_tree().create_timer(1.0).timeout
	print("NETZTEST: Kabel %d fertig: %s, Geld %.2f, Mitspieler %d" % [best.id, str(_removed_ids.has(best.id)),
		_economy.state.money, _players.size()])
	if important:
		print("NETZTEST: Tasche %d, Knäuel gesamt %d" % [_bag.size(), _items.size()])
		_local_player.global_position = ServerRoomView.center() + Vector3(0, 0.1, 2.0)
		await get_tree().create_timer(0.8).timeout
		_request("interact", { "end": -1, "knot": -1, "reel": -1, "item": -1, "rack": true, "stop": -1, "station": [] })
		await get_tree().create_timer(1.5).timeout
		print("NETZTEST: nach Einstecken: Tasche %d, Ports %s" % [_bag.size(), str(_economy.state.active_ports)])
		return
	_request("buy", { "id": "crank" })
	await get_tree().create_timer(1.5).timeout
	print("NETZTEST: nach Kauf: Handkurbel Stufe %d, Rollen %d, Geld %.2f" % [_economy.state.level("crank"),
		_system.reels.size(), _economy.state.money])


## Testoption --anim: Bewegungen regelmäßig auslösen
func _run_test_anim() -> void:
	var f := _player.facing()
	var beat := int(_time * 60.0) % 40 == 0
	match _test_anim:
		"strain":
			_player.debug_strain = true
		"crank":
			var a := _time * 7.0
			var center := _player.global_position + f * 1.3
			var side := f.cross(Vector3.UP)
			_player.crank(center + Vector3(0, 1.3, 0) + (side * cos(a) + f * sin(a)) * 0.66, center)
		"tug", "reach", "pickup":
			if beat:
				_player.act(_test_anim)
		"wind":
			if int(_time * 60.0) % 12 == 0:
				_player._wiggle_arm()


func _apply_test_args() -> void:
	var opts := {}
	for arg in OS.get_cmdline_user_args():
		var parts := arg.trim_prefix("--").split("=")
		opts[parts[0]] = parts[1] if parts.size() > 1 else ""
	if opts.has("teleport"):
		# Zuerst versetzen und die Kabel dort sofort laden, damit z. B. --grab dort greift
		var at := String(opts["teleport"]).split(",")
		_player.global_position = Vector3(float(at[0]), 0.05, float(at[1]))
		_stream_update(true)
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
				for port in RackPlan.service_ports(_economy.locked_by(id)):
					_rack.plug(port)
			_room.refresh(_economy.state)
			_economy.state.money += _economy.cost(id)
			_economy.buy(id)
	if opts.has("turmopen"):
		# Aufzug im Turm freigeben, ohne alle Viertel zu schaffen
		_tower_open_override = true
		_refresh_finale(false)
	if opts.has("tower"):
		# --tower=<Halt>: an einen Aufzug-Halt (0 Erdgeschoss, 1 Etage 40, 2 Dach) versetzen, Kabel dort laden
		var stop: Dictionary = _tower.stops[clampi(int(opts["tower"]), 0, _tower.stops.size() - 1)]
		_player.global_position = (stop["pos"] as Vector3) + Vector3(0, 0.1, 0)
		_player.look_toward(_tower.core_pos if int(opts["tower"]) == 2 else (stop["pos"] as Vector3) + Vector3(0, 0, -10))
		_stream_update(true)
	if opts.has("finale"):
		# Alle Ports belegen und den Kern abschalten (Abspann)
		for port in RackPlan.total_ports():
			_rack.plug(port)
		_room.refresh(_economy.state)
		_refresh_finale(false)
		_use_core()
	if opts.has("phone"):
		_player.set_phone(true)
	if opts.has("vacuum"):
		# Kabelsauger dauerhaft an (wie Linksklick halten), z. B. --buy=vacuum --vacuum
		_tools.force_vacuum = true
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
	if opts.has("plug") and not _bag.is_empty():
		_deliver_bag()
	if opts.has("plugports"):
		# z. B. --plugports=0-19 oder --plugports=50-59: Ports direkt belegen
		var r := String(opts["plugports"]).split("-")
		for port in range(int(r[0]), int(r[-1]) + 1):
			_rack.plug(port)
		_room.refresh(_economy.state)
	if opts.has("room"):
		# Vor die Tür des Serverraums (--room=in: hinein)
		_player.global_position = (ServerRoomView.center() + Vector3(0, 0.05, -2.0)) if opts["room"] == "in" \
			else ServerRoomView.door_point() + Vector3(0, 0.05, -4.0)
		_player.look_toward(ServerRoomView.center() + Vector3(0, 0, 4.0))
	if opts.has("newjobafter") and not _test_newjob_done:
		# Test: nach so vielen Sekunden einen neuen Auftrag annehmen (Mehrspieler: Clients laden mit)
		_test_newjob_done = true
		get_tree().create_timer(float(opts["newjobafter"])).timeout.connect(func() -> void:
			_economy.state.finale_done = true
			_economy.state.total_earned = 1e8
			_start_new_job())
	if opts.has("newjob") and not _test_newjob_done:
		# --newjob[=<Mio. €>]: Finale geschafft, so viel verdient, neuen Auftrag annehmen (Szene lädt neu)
		_test_newjob_done = true
		_economy.state.finale_done = true
		_economy.state.total_earned = float(opts["newjob"]) * 1e6 if String(opts["newjob"]).is_valid_float() else 1e8
		_start_new_job.call_deferred()
		return
	if opts.has("nearimportant"):
		# Test: neben das nächste wichtige Kabel stellen und es anschauen
		var best: CableData = null
		for c: CableData in _system.important.values():
			if best == null or c.path.points[0].distance_to(_player.global_position) < best.path.points[0].distance_to(_player.global_position):
				best = c
		if best:
			var end := best.path.points[0]
			_player.global_position = end + Vector3(2.5, 0.3, 2.5)
			_player.look_toward(end)
	if opts.has("look"):
		# --look=hoodie_pink,shoes_weiss,fx_confetti: Kosmetik kaufen und anlegen
		for id in String(opts["look"]).split(","):
			var def := Economy.cosmetic_def(id)
			_economy.state.money += float(def.get("cost", 0.0))
			if not _economy.wear_cosmetic(id):
				push_warning("Kosmetik %s unbekannt" % id)
	if opts.has("roomview"):
		# Blick im Serverraum zur Vorderwand (Kaffeeecke, Leitstand) bzw. --roomview=back zu den Schränken
		var c := ServerRoomView.center()
		if opts["roomview"] == "back":
			_player.global_position = c + Vector3(0, 0.05, 0.5)
			_player.look_toward(c + Vector3(0, 0, 6.0))
		else:
			_player.global_position = c + Vector3(0, 0.05, 2.5)
			_player.look_toward(c + Vector3(0, 0, -6.0))
	if opts.has("tablet"):
		_open_tablet()
		if String(opts["tablet"]).is_valid_int():
			_tablet.show_tab(int(opts["tablet"]))  # --tablet=<0..3>: Reiter
	if opts.has("ask"):
		_cord.ask_now()
	if opts.has("order"):
		_spawn_order(_cord.order_count())
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
				_drop_cable(cid)
		_update_blockers()
	if opts.has("streamtest"):
		# Halb gezogenes Kabel einer Stadt-Einheit: entladen, Spielstand, wieder laden
		var u: CableUnit = _units.filter(func(x: CableUnit) -> bool: return not x.barrier)[0]
		_load_unit(u, true)
		print("STREAMTEST geladen=%d von %d (Blöcke %d)" % [range(u.first_id, u.last_id() + 1).filter(func(i: int) -> bool: return _system.cables.has(i)).size(), u.cable_total(), _batcher.batch_count()])
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
	if opts.has("runfor"):
		# Nach so vielen Sekunden (echte Zeit) Zustand ausgeben und beenden (Netz-Tests ohne Bild-Takt)
		get_tree().create_timer(float(opts["runfor"]), true, false, true).timeout.connect(func() -> void:
			print("ZUSTAND ", _summary())
			if opts.has("shot"):
				get_viewport().get_texture().get_image().save_png(String(opts["shot"]))
			get_tree().quit())
	if opts.has("host") and not Net.is_online():
		Net.host(Settings.port)  # Test: gleich als Host starten
	if opts.has("network"):
		_test_network(String(opts["network"]) == "important")
	if opts.has("fillbag"):
		# So viele wichtige Kabel fertig aufrollen, wie angegeben (z. B. --fillbag=5): Tasche füllt sich, Rest fällt zu Boden
		for k in int(opts["fillbag"]):
			for c: CableData in _system.cables.values():
				if c.is_important() and c.state == CableData.State.HEAP:
					c.knots_m = PackedFloat32Array()
					_system.hook(c, _arm_reel)
					_system.pull(_arm_reel, 1000.0)
					break
	if opts.has("post"):
		# Test: neben die Rohrpost-Station eines Viertels stellen (--post=wohnviertel); --usepost wirft dann ein
		for post in _posts:
			if post.district_id == String(opts["post"]):
				_player.global_position = post.global_position + Vector3(2.0, 0.5, 2.0)
				_player.look_toward(post.global_position)
				_stream_update(true)
				if opts.has("usepost"):
					get_tree().create_timer(2.0).timeout.connect(func() -> void:
						_request("interact", { "end": -1, "knot": -1, "reel": -1, "item": -1, "rack": true, "stop": -1,
							"station": [], "post": _posts.find(post) })
						print("ROHRPOST: Tasche %d, Ports %s" % [_bag.size(), str(_economy.state.active_ports)]))
	if opts.has("deliver"):
		_deliver_bag()
	if opts.has("jump"):
		_player.jump()
	if opts.has("snooze"):
		_on_snooze_requested()
	if opts.has("wagon"):
		# Wagen kaufen und alle Plätze mit Kabeln belegen (--wagon=fill)
		_economy.state.money += _economy.cost("wagon")
		_economy.buy("wagon")
		if opts["wagon"] == "fill":
			for slot in _wagon.slots:
				for c: CableData in _system.cables.values():
					if c.state == CableData.State.HEAP:
						_system.hook(c, slot)
						break
			_wagon.parked = true
	if opts.has("carryreel"):
		for r: ReelData in _system.reels.values():
			if r.is_movable() and r.is_free():
				_pick_up_reel(r)
				break
	if opts.has("zipline"):
		# --zipline=<Strecken-ID>: freischalten und zur äußeren Station; --zipline=<ID>,ride: gleich losfahren
		var parts := String(opts["zipline"]).split(",")
		var zl: Zipline = _ziplines.get(parts[0])
		if zl:
			for service in RackPlan.total_services():
				if String(RackPlan.service_def(service).get("special", "")) == zl.unlock:
					for port in RackPlan.service_ports(service):
						_rack.plug(port)
			_room.refresh(_economy.state)
			_player.global_position = zl.stations[0] + Vector3(0, 0.3, 1.5)
			if parts.size() > 1:
				_start_ride(zl, 0)
	if opts.has("closeup"):
		# Kamera nah an die Figur (für Bilder der Figur)
		_player._spring.spring_length = 2.2
		_player._pitch.rotation.x = -0.12
	if opts.has("anim"):
		# Bewegung der Figur vorführen (für Bilder): walk, run, back, strain, crank, tug, reach, pickup, wind
		_test_anim = String(opts["anim"])
		# Kamera mittig auf die ganze Figur
		_player._spring.position.x = 0.0
		_player._spring.spring_length = 3.2
		_player._pitch.rotation.x = -0.1
		_player.debug_no_look = true
		if opts.has("grab") and opts.has("orbit"):
			_player.orbit_camera(float(opts["orbit"]))
		match _test_anim:
			"walk": _player.debug_speed = 4.0
			"run": _player.debug_speed = 7.0
			"back": _player.debug_speed = -3.0
			"sulk": _cord_view.react("declined")
			"happy": _cord_view.react("placed")
	if opts.has("rigdump") and _player._skel:
		var sk: Skeleton3D = _player._skel
		for key: String in PlayerAnimator.BONES:
			var b: int = _player._anim.bone(key)
			var gp := sk.global_transform * sk.get_bone_global_pose(b)
			print("RIG %-7s pose_y=%s  welt_pos=%s  relativ=%s" % [key, str(sk.get_bone_global_pose(b).basis.y.normalized().snapped(Vector3.ONE * 0.01)),
				str(gp.origin.snapped(Vector3.ONE * 0.01)), str((_player.global_transform.affine_inverse() * gp.origin).snapped(Vector3.ONE * 0.01))])
	if opts.has("unitstats"):
		# Kabel je Einheit (Viertel, Sperre) mit Zahl der Haufen und wichtigen Kabel
		var total := 0
		for u in _units:
			var kinds := {}
			for h in u.heaps:
				kinds[h.kind] = int(kinds.get(h.kind, 0)) + 1
			print("UNIT %-22s kabel=%6d haufen=%d wichtig=%d" % [u.id, u.cable_total(), u.heaps.size(), u.important.size()], " ", kinds)
			total += u.cable_total()
		print("UNIT summe=", total)
	if opts.has("perf"):
		# Alle 2 s Bildrate, Rechenzeit und Zeichenlast ausgeben (Leistungstest)
		var timer := Timer.new()
		timer.wait_time = 2.0
		timer.autostart = true
		add_child(timer)
		timer.timeout.connect(func() -> void:
			print("PERF fps=%d proc=%.1fms objekte=%d dreiecke=%dk drawcalls=%d kabel=%d bloecke=%d" % [
				Engine.get_frames_per_second(), Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
				Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME),
				int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME) / 1000.0),
				Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME), _system.cables.size(),
				_batcher.batch_count()], " ", _batcher.stats(), " formen/bild=%.1f punkte/kabel=%d" % [
				CableView.stat_builds / maxf(_prof_frames, 1.0), CableView.stat_points / maxi(CableView.stat_builds, 1)],
				" form/duenn/roehre/stecker=%s" % str(CableView.stat_us.map(func(v: int) -> int: return v / maxi(_prof_frames, 1))), " us/bild: ",
				", ".join(_prof.keys().map(func(k: String) -> String: return "%s=%d" % [k, int(_prof[k]) / maxi(_prof_frames, 1)])),
				" batcher=%d" % (_batcher.prof_us / maxi(_prof_frames, 1)))
			_prof.clear()
			_batcher.prof_us = 0
			_prof_frames = 0
			CableView.stat_builds = 0
			CableView.stat_points = 0
			CableView.stat_us = [0, 0, 0, 0])
	if opts.has("dumpafter"):
		_dump_after = int(opts["dumpafter"])
	if opts.has("dump"):
		print("ZUSTAND ", _summary())
	if opts.has("saveexit"):
		_saving_enabled = true
		_save_game(false)
		get_tree().quit()


# --- Mehrspieler ----------------------------------------------------------------
## Der Host (bzw. Einzelspieler) rechnet alles; Clients schicken Absichten (`_request`) und übernehmen den
## Zustand (`net_snapshot`, `net_event`). Figuren-Lage schickt jeder selbst (`net_player_state`).

const PUPPET_SCENE := preload("res://scenes/player.tscn")
const MENU_SCENE := "res://scenes/main_menu.tscn"
## Kosmetik-Plätze, die jede Figur für sich hat (der Rest gilt für alle)
const PLAYER_SLOTS := ["hoodie", "pants", "headphones", "shoes"]
var _net_drones: Array[DroneView] = []  # Client: Drohnen nur zur Anzeige


## Absicht der eigenen Figur: offline und als Host gleich ausführen, als Client an den Host schicken
func _request(kind: String, args: Dictionary = {}) -> void:
	if _authority:
		_do_intent(_me, kind, args)
	else:
		Net.send_intent(kind, args)


## Für eine Figur handeln: `_actor` zeigt währenddessen auf ihren Kontext
func _act_as(ctx: PlayerCtx, fn: Callable) -> void:
	var before := _actor
	_actor = ctx
	fn.call()
	_actor = before


func _do_intent(ctx: PlayerCtx, kind: String, args: Dictionary) -> void:
	_act_as(ctx, _intent_core.bind(ctx, kind, args))


func _intent_core(ctx: PlayerCtx, kind: String, args: Dictionary) -> void:
	if OS.get_cmdline_user_args().has("--netlog"):
		var held := _system.cable_on(_arm_reel)
		print("ABSICHT %d %s %s am Arm: %s" % [ctx.id, kind, str(args.get("knot", "")), ("%d %.2f k%d p%d" % [held.id, held.pulled_m, held.knots_solved, held.knot_presses]) if held else "-"])
	match kind:
		"interact":
			_interact_with(args)
		"pull":
			_pull_core()
		"release":
			_release_core()
		"buy":
			var id := String(args.get("id", ""))
			if Balancing.upgrades.has(id) and _economy.buy(id):
				if ctx != _me:
					_announce_others("%s kauft %s." % [ctx.name, _economy.upgrade_name(id)], ctx.id)
				_econ_dirty = true
		"wear":
			_wear(ctx, String(args.get("id", "")))
		"decline":
			_cord.decline()
		"snooze":
			_on_snooze_requested()
		"recall":
			_tools.recall_drones(_player.global_position)
			_show_message("Die Drohnen arbeiten ab jetzt hier (Umkreis %d m)." % int(Balancing.drone.get("work_radius_m", 45.0)))


## Kosmetik anlegen (und vorher aus der gemeinsamen Kasse kaufen); Figur-Teile gehören der Figur
func _wear(ctx: PlayerCtx, id: String) -> void:
	var def := Economy.cosmetic_def(id)
	if def.is_empty():
		return
	var slot := String(def["slot"])
	if ctx.id == 1 or not PLAYER_SLOTS.has(slot):
		_economy.wear_cosmetic(id)
	else:
		if not _economy.owns_cosmetic(id):
			var price := float(def.get("cost", 0.0))
			if _economy.state.money < price - 1e-6:
				return
			_economy.state.money -= price
			_economy.state.cosmetics.append(id)
			_economy.money_changed.emit(_economy.state.money)
		ctx.looks[slot] = id
		Net.send_event("looks", { "id": ctx.id, "looks": ctx.looks })
		_apply_looks()
	_econ_dirty = true


## Angelegtes Stück einer Figur ("" = Grundausstattung)
func _look_of(ctx: PlayerCtx, slot: String) -> String:
	if PLAYER_SLOTS.has(slot) and ctx.id != 1:
		return String(ctx.looks.get(slot, ""))
	return _economy.look(slot)


## Meldung an alle (eigene Anzeige und Mitspieler)
func _announce(text: String) -> void:
	var before := _actor
	_actor = _me
	_show_message(text)
	_actor = before
	Net.send_event("msg", { "t": text })


## Meldung an alle außer einem Spieler
func _announce_others(text: String, except_id: int) -> void:
	if except_id != _me.id:
		var before := _actor
		_actor = _me
		_show_message(text)
		_actor = before
	for pid: int in Net.peers:
		if pid != 1 and pid != except_id:
			Net.send_event("msg", { "t": text }, pid)


## Schwebender Text bei allen
func _float(pos: Vector3, text: String, color := Color(1.0, 0.9, 0.3)) -> void:
	FloatText.spawn(self, pos, text, color)
	Net.send_event("float", { "p": pos, "t": text, "c": color })


## Effekt aus der Kosmetik bei allen
func _fx(pos: Vector3, kind: String, amount := 1.0) -> void:
	if kind == "":
		return
	CelebrationFx.spawn(self, pos, kind, amount)
	Net.send_event("fx", { "p": pos, "k": kind, "a": amount })


func _net_ready() -> void:
	if Net.is_client():
		_local_player.global_position += Vector3(1.5, 0.3, 1.5)  # nicht in der Figur des Hosts landen
		Net.send_intent("entered", { "looks": _me.looks })
	elif Net.is_host() and Net.peers.size() > 1:
		Net.send_welcome(0)  # neu geladen (z. B. neuer Auftrag): alle Clients laden mit


func _exit_tree() -> void:
	if Net.world == self:
		Net.world = null


## Zurück ins Hauptmenü (speichert vorher, Mehrspieler endet)
func _back_to_menu() -> void:
	if _authority:
		_save_game(false)
	Net.leave()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().change_scene_to_file(MENU_SCENE)


func net_back_to_menu() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().change_scene_to_file(MENU_SCENE)


## Client: Host hat neuen Spielstand geschickt (neuer Auftrag, Laden): Welt neu aufbauen
func net_reload_world() -> void:
	get_tree().reload_current_scene()


## Host: Spielstand für einen beitretenden Client
func net_snapshot_for_join() -> Dictionary:
	return _collect_save()


# ---- Figuren ----

func _make_puppet(id: int, name_value: String) -> Player:
	var p: Player = PUPPET_SCENE.instantiate()
	p.remote = true
	p.name = "Mitspieler_%d" % id
	add_child(p)
	p.global_position = _local_player.global_position + Vector3(2, 0, 2)
	var label := Label3D.new()
	label.text = name_value
	label.font = UiTheme.font()
	label.font_size = 64
	label.outline_size = 14
	label.pixel_size = 0.005
	label.modulate = Color(1.0, 0.95, 0.6)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.position = Vector3(0, 2.25, 0)
	p.add_child(label)
	return p


func _add_player(id: int, name_value: String) -> PlayerCtx:
	if _players.has(id):
		return _players[id]
	var ctx := PlayerCtx.new()
	ctx.id = id
	ctx.name = name_value
	ctx.node = _make_puppet(id, name_value)
	if _authority:
		var arm := ReelData.new(_remote_arm_next, ReelData.Kind.ARM)
		_remote_arm_next += 1
		arm.owner_id = id
		_system.add_reel(arm)
		ctx.arm_reel = arm
	_players[id] = ctx
	if _authority:
		_tools.sync(_economy)
	_apply_looks()
	return ctx


## Host: Mitspieler ist weg (Verbindung getrennt): Kabel los, Knäuel und Rolle ablegen
func net_player_left(id: int, name_value: String) -> void:
	var ctx: PlayerCtx = _players.get(id)
	if ctx == null:
		return
	if _authority:
		_act_as(ctx, _drop_everything)
		for r in ctx.vacuum_reels:
			if not r.is_free():
				_system.release(r)
			_system.remove_reel(r.id)
		if ctx.arm_reel:
			_system.remove_reel(ctx.arm_reel.id)
		_items_dirty = true
		Net.send_event("left", { "id": id, "name": name_value })
		_announce("%s hat das Spiel verlassen." % name_value)
	_remove_player(id)


## Figur, für die gerade gehandelt wird: Kabel los, Knäuel und Rolle ablegen
func _drop_everything() -> void:
	if _arm_reel and not _arm_reel.is_free():
		_system.release(_arm_reel)
	while not _bag.is_empty():
		_drop_from_bag()
	if _carried_reel:
		_put_down_reel()


func _remove_player(id: int) -> void:
	var ctx: PlayerCtx = _players.get(id)
	if ctx == null or ctx == _me:
		return
	if _wagon_driver == ctx:
		_wagon_driver = _me
	_tools.forget_player(id)
	ctx.node.queue_free()
	_players.erase(id)


## Lage und Haltung einer anderen Figur
func net_player_state(id: int, st: Array) -> void:
	var ctx: PlayerCtx = _players.get(id)
	if ctx == null:
		if _authority or not Net.peers.has(id):
			return  # Host legt Mitspieler erst bei „entered“ an
		ctx = _add_player(id, Net.player_name(id))
	ctx.node.apply_net_state(st)
	if st.size() > 13:
		ctx.vacuum_want = bool(st[13])


# ---- Host: Absichten ----

func net_intent(id: int, kind: String, args: Dictionary) -> void:
	if kind == "entered":
		var ctx := _add_player(id, Net.player_name(id))
		# Aussehen übernehmen, soweit die Stücke gekauft sind
		for slot: String in (args.get("looks", {}) as Dictionary):
			var item := String(args["looks"][slot])
			if PLAYER_SLOTS.has(slot) and _economy.owns_cosmetic(item):
				ctx.looks[slot] = item
		_apply_looks()
		Net.send_event("joined", { "id": id, "name": ctx.name })
		for other: PlayerCtx in _players.values():
			Net.send_event("looks", { "id": other.id, "looks": other.looks if other.id != 1 else {} })
		_items_dirty = true
		_econ_dirty = true
		_announce_others("%s spielt jetzt mit." % ctx.name, id)
		Net.send_event("msg", { "t": "Willkommen! Gemeinsame Kasse, gemeinsame Ports – Tab öffnet das Tablet." }, id)
		return
	var ctx: PlayerCtx = _players.get(id)
	if ctx:
		_do_intent(ctx, kind, args)


# ---- Host: Zustand verschicken ----

func _net_tick(delta: float) -> void:
	if not Net.is_online():
		return
	_pstate_t -= delta
	if _pstate_t <= 0.0:
		_pstate_t = 0.05
		var st := _local_player.net_state()
		st.append(_me.vacuum_want)
		Net.send_player_state(st)
	if not Net.is_host() or Net.peers.size() < 2:
		return
	_net_t -= delta
	if _net_t > 0.0:
		return
	_net_t = 0.1
	Net.send_snapshot(_snapshot_data())
	if _items_dirty:
		_items_dirty = false
		Net.send_event("items", { "list": _items_list() })
	if _econ_dirty:
		_econ_dirty = false
		Net.send_event("econ", _economy.state.to_dict())


func _snapshot_data() -> Dictionary:
	var reels := []
	var hooked := []
	for r: ReelData in _system.reels.values():
		reels.append([r.id, int(r.kind), r.position.x, r.position.y, r.position.z, r.owner_id, r.cable_id,
			r.carrier_id if r.carried else 0])
		var c := _system.cable_on(r)
		if c:
			hooked.append([c.id, r.id, c.pulled_m, c.knots_solved, c.knot_presses, c.reversed])
	var drones := []
	for d: Dictionary in _tools.drones:
		var p: Vector3 = d["pos"]
		drones.append([p.x, p.y, p.z, String(d["state"])])
	var wagon := []
	if _wagon:
		wagon = [_wagon.position.x, _wagon.position.y, _wagon.position.z, _wagon.yaw, _wagon.parked]
		for slot in _wagon.slots:
			wagon.append(slot.id)
	return { "reels": reels, "hooked": hooked, "drones": drones, "wagon": wagon,
		"money": _economy.state.money, "earned": _economy.state.total_earned, "snooze": _economy.state.snooze_cooldown,
		"cord": [int(_cord.phase), _cord.time_left], "done": _done_count }


## Knäuel: zuerst die Taschen (in ihrer Reihenfolge), dann der Rest
func _items_list() -> Array:
	var out := []
	var seen := {}
	for ctx: PlayerCtx in _players.values():
		for item in ctx.bag:
			out.append([item.id, item.port_id, item.position.x, item.position.y, item.position.z, ctx.id])
			seen[item.id] = true
	for item: CoilItem in _items.values():
		if not seen.has(item.id):
			out.append([item.id, item.port_id, item.position.x, item.position.y, item.position.z, item.carried_by])
	return out


# ---- Client: Zustand übernehmen ----

func net_snapshot(d: Dictionary) -> void:
	if _authority:
		return
	_replaying = true
	var now := Time.get_ticks_msec() / 1000.0
	# Aufwickler: anlegen, verschieben, entfernen
	var seen := {}
	for ctx: PlayerCtx in _players.values():
		if ctx != _me:
			ctx.carried_reel = null
	for e: Array in d.get("reels", []):
		var id := int(e[0])
		var kind := int(e[1]) as ReelData.Kind
		var owner := int(e[5])
		var pos := Vector3(e[2], e[3], e[4])
		seen[id] = true
		var r: ReelData = _system.reels.get(id)
		if r == null:
			if kind == ReelData.Kind.ARM and owner == _me.id:
				_system.remove_reel(_me.arm_reel.id)
				r = ReelData.new(id, kind)
				r.owner_id = owner
				_system.add_reel(r)
				_me.arm_reel = r
			else:
				r = ReelData.new(id, kind, pos)
				r.owner_id = owner
				if kind in [ReelData.Kind.HAND, ReelData.Kind.MOTOR, ReelData.Kind.WINCH, ReelData.Kind.WAGON]:
					_add_reel(r)
				else:
					_system.add_reel(r)
		if kind == ReelData.Kind.ARM and owner != _me.id and _players.has(owner):
			(_players[owner] as PlayerCtx).arm_reel = r
		if kind == ReelData.Kind.VACUUM and owner == _me.id and not _me.vacuum_reels.has(r):
			_me.vacuum_reels.append(r)
		var carrier := int(e[7])
		if r.carried != (carrier != 0) and _reel_views.has(r.id):
			_reel_views[r.id].set_carried(carrier != 0)
		r.carried = carrier != 0
		r.carrier_id = carrier
		if r.carried and _players.has(carrier):
			(_players[carrier] as PlayerCtx).carried_reel = r
		var local := kind == ReelData.Kind.ARM or (kind == ReelData.Kind.VACUUM and owner == _me.id) or r.carried \
			or kind == ReelData.Kind.WAGON
		if not local:
			r.position = pos
			if _reel_views.has(r.id):
				_reel_views[r.id].global_position = pos
	_me.carried_reel = null
	for e: Array in d.get("reels", []):
		if int(e[7]) == _me.id:
			_me.carried_reel = _system.reels.get(int(e[0]))
	for id: int in _system.reels.keys():
		if not seen.has(id) and id != _me.arm_reel.id:
			var r: ReelData = _system.reels[id]
			if not r.is_free():
				_system.release(r)
			_system.remove_reel(id)
			_me.vacuum_reels.erase(r)
			if _reel_views.has(id):
				_reel_views[id].queue_free()
				_reel_views.erase(id)
	# Eingehängte Kabel
	var desired := {}
	for e: Array in d.get("hooked", []):
		var cid := int(e[0])
		desired[cid] = true
		var c: CableData = _system.cables.get(cid)
		var reel: ReelData = _system.reels.get(int(e[1]))
		if c == null or reel == null:
			continue
		if c.state != CableData.State.HOOKED and c.reversed != bool(e[5]):
			c.reverse()
		_system.force_hook(c, reel)
		c.pulled_m = float(e[2])
		c.knots_solved = int(e[3])
		c.knot_presses = int(e[4])
		if c.is_stuck():
			_add_knot_marker(c)
		else:
			_remove_knot_marker(cid)
		_missing_since.erase(cid)
	for c in _system.hooked_cables():
		if desired.has(c.id):
			continue
		var since := float(_missing_since.get(c.id, now))
		_missing_since[c.id] = since
		if now - since > 0.6:
			_missing_since.erase(c.id)
			var reel := _system.reel_of(c)
			if reel:
				_system.release(reel)
	# Wagen
	var w: Array = d.get("wagon", [])
	if not w.is_empty():
		if _wagon == null:
			_spawn_wagon({ "slots": w.slice(5), "position": [w[0], w[1], w[2]], "yaw": w[3], "parked": w[4] })
		_wagon.position = Vector3(w[0], w[1], w[2])
		_wagon.yaw = float(w[3])
		_wagon.parked = bool(w[4])
	# Drohnen
	var dl: Array = d.get("drones", [])
	while _net_drones.size() < dl.size():
		var v := DroneView.new()
		add_child(v)
		_net_drones.append(v)
	for i in dl.size():
		var e: Array = dl[i]
		_net_drones[i].global_position = _net_drones[i].global_position.lerp(Vector3(e[0], e[1], e[2]), 0.6) \
			if _net_drones[i].global_position != Vector3.ZERO else Vector3(e[0], e[1], e[2])
		var st := String(e[3])
		_net_drones[i].set_mode("work" if st == "pull" else ("deliver" if st == "deliver" else "fly"))
	# Geld, C.O.R.D.
	_economy.state.money = float(d.get("money", 0.0))
	_economy.state.total_earned = float(d.get("earned", 0.0))
	_economy.state.snooze_cooldown = float(d.get("snooze", 0.0))
	_done_count = int(d.get("done", _done_count))
	var cord: Array = d.get("cord", [0, 0.0])
	if int(cord[0]) == CordLogic.Phase.ASKING:
		if not _cord_prompt.visible:
			_cord_view.set_asking(true, "Ersatz bestellen?")
			_cord_prompt.show_question(float(cord[1]))
		_cord_prompt.update_time(float(cord[1]))
	elif _cord_prompt.visible:
		_cord_view.set_asking(false)
		_cord_prompt.visible = false
	_replaying = false


func net_event(kind: String, a: Dictionary) -> void:
	match kind:
		"msg":
			_message = String(a.get("t", ""))
			_message_t = 4.0
		"float":
			FloatText.spawn(self, a["p"], String(a["t"]), a.get("c", Color(1.0, 0.9, 0.3)))
		"fx":
			CelebrationFx.spawn(self, a["p"], String(a["k"]), float(a.get("a", 1.0)))
		"elevator":
			_ride_elevator(int(a["from"]), bool(a["holding"]))
		"ride":
			if _ziplines.has(a["line"]):
				_start_ride(_ziplines[a["line"]], int(a["station"]))
		"done":
			_client_cable_done(a)
		"items":
			_client_items(a.get("list", []))
		"econ":
			_economy.state.load_dict(a)
			_apply_upgrades()
			_room.refresh(_economy.state)
			_refresh_ziplines()
			_refresh_finale(false)
			_apply_looks()
			_refresh_posts()
			_economy.money_changed.emit(_economy.state.money)
		"zone":
			var ports: Array[int] = []
			for p in a.get("ports", []):
				ports.append(int(p))
			_spawn_zone(int(a["seed"]), ports, int(a["first"]))
		"order":
			_add_order_heap(HeapData.from_dict(a["heap"]), int(a["first"]), true)
		"cord":
			match String(a.get("k", "")):
				"declined":
					_cord_view.react("declined")
				"placed":
					_cord_view.react("placed")
		"finale":
			_show_finale_screen()
		"post":
			var i := int(a.get("i", -1))
			if i >= 0 and i < _posts.size():
				_posts[i].launch()
		"looks":
			var id := int(a["id"])
			var looks: Dictionary = a.get("looks", {})
			if id == _me.id:
				_me.looks = looks.duplicate()
				Settings.looks = looks.duplicate()
				Settings.save_settings()
			elif _players.has(id):
				(_players[id] as PlayerCtx).looks = looks.duplicate()
			_apply_looks()
			_tablet.refresh()
		"joined":
			if int(a["id"]) != _me.id:
				_add_player(int(a["id"]), String(a["name"]))
		"left":
			_remove_player(int(a["id"]))
			_items_dirty = false
		"blockers":
			_update_blockers()


## Client: ein Kabel ist beim Host fertig geworden
func _client_cable_done(a: Dictionary) -> void:
	var cid := int(a["id"])
	_removed_ids[cid] = true
	_done_count += 1
	var c: CableData = _system.cables.get(cid)
	var reel: ReelData = _system.reels.get(int(a.get("reel", -1)))
	if reel and reel.cable_id == cid:
		reel.cable_id = -1
	_remove_knot_marker(cid)
	_missing_since.erase(cid)
	var view: CableView = _views.get(cid)
	if view:
		_views.erase(cid)
		if bool(a.get("imp", false)) or c == null:
			view.queue_free()
		else:
			if reel and reel.kind == ReelData.Kind.ARM and _players.has(reel.owner_id):
				view.show_on_arm((_players[reel.owner_id] as PlayerCtx).node.arm_transform())
			elif reel:
				view.show_on_reel(reel.position, ReelView.scale_of(reel))
			_fading.append(view)
	_batcher.set_hidden(cid, true)
	if c:
		_system.remove_cable(cid)
	var at := Vector3(a.get("p", Vector3.ZERO))
	if float(a.get("pay", 0.0)) > 0.0 and at.distance_to(_local_player.global_position) < 30.0:
		FloatText.spawn(self, at, "+" + Economy.format_money(float(a["pay"])))
	if at.distance_to(_local_player.global_position) < 40.0:
		CelebrationFx.spawn(self, at, _look_fx(), 0.5)
	var unit := _unit_of(cid)
	if unit and unit.barrier:
		_update_blockers()


## Client: Knäuel so, wie der Host sie meldet (am Boden, in Taschen, an Drohnen)
func _client_items(list: Array) -> void:
	var seen := {}
	for ctx: PlayerCtx in _players.values():
		ctx.bag.clear()
	for e: Array in list:
		var id := int(e[0])
		seen[id] = true
		var item: CoilItem = _items.get(id)
		if item == null:
			item = CoilItem.new()
			item.id = id
			item.port_id = int(e[1])
			_items[id] = item
			var iv := CoilItemView.new()
			add_child(iv)
			iv.setup(item)
			_item_views[id] = iv
		item.position = Vector3(e[2], e[3], e[4])
		item.carried_by = int(e[5])
		var view: CoilItemView = _item_views[id]
		view.visible = item.carried_by > -100
		if _players.has(item.carried_by):
			(_players[item.carried_by] as PlayerCtx).bag.append(item)
			view.set_carried(true)
		else:
			view.set_carried(false)
			view.lie_at(item.position)
	for id: int in _items.keys():
		if not seen.has(id):
			_items.erase(id)
			if _item_views.has(id):
				_item_views[id].queue_free()
				_item_views.erase(id)
	_room.refresh(_economy.state)
