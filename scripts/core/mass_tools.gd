class_name MassTools
extends Node
## Werkzeuge für die Masse: Kabelsauger, Haufen-Winden und Abräum-Drohnen.
## Alle drei hängen Kabel selbst an eigene Aufwickler (ReelData VACUUM, WINCH, DRONE); Ziehen und Knoten-Lösen
## erledigt CableSystem wie bei Motorrollen. Hier steckt nur, welches Kabel wann eingehängt wird und wie sich
## Sauger-Kegel und Drohnen bewegen. Die Hauptszene (world.gd) verdrahtet und übergibt sich als `world`.

var world: Node  # world.gd (Zugriff auf System, Spieler, Knäuel, Serverraum)

## Nur der Host (bzw. Einzelspieler) entscheidet, was eingehängt wird; Clients zeigen nur an
var authority := true
## Nur für Tests (--vacuum): Sauger an, als würde Linksklick gehalten
var force_vacuum := false
var _vacuum_t := 0.0
## Dauerbetrieb (Upgrade vacuum_auto): Linksklick schaltet an und aus (eigene Figur)
var vacuum_on := false
## Sauger-Kegel je Spieler (Peer-ID -> MeshInstance3D)
var _cones: Dictionary = {}

## Drohnen: { reel, view, pos, state, target, tail, goal, cargo, think_t }
var drones: Array[Dictionary] = []
## Einsatzort der Drohnen (Tablet: „Drohnen zu mir rufen“)
var drone_anchor := Vector3.ZERO
var _winch_t := 0.0
var _claimed: Dictionary = {}        # Kabel-ID -> true (eine Drohne fliegt hin)
var _claimed_items: Dictionary = {}  # Knäuel-ID -> true
## Eigene IDs für Sauger- und Drohnen-Aufwickler: werden nicht gespeichert und dürfen gespeicherten Rollen
## nicht in die Quere kommen
var _next_tool_reel_id := 900_000


## Sauger-Plätze der eigenen Figur
var vacuum_reels: Array[ReelData]:
	get:
		return world._me.vacuum_reels if world and world._me else ([] as Array[ReelData])
## Saugt die eigene Figur gerade?
var vacuum_active: bool:
	get:
		return world._me.vacuum_active if world and world._me else false


func _cone(id: int) -> MeshInstance3D:
	if _cones.has(id):
		return _cones[id]
	var fx := MeshInstance3D.new()
	var cone := CylinderMesh.new()
	cone.top_radius = 0.12
	cone.bottom_radius = 1.0
	cone.height = 1.0
	cone.radial_segments = 20
	cone.cap_top = false
	cone.cap_bottom = false
	fx.mesh = cone
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.45, 0.95, 1.0, 0.16)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	fx.material_override = m
	fx.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	fx.visible = false
	add_child(fx)
	_cones[id] = fx
	return fx


## Spieler verlässt das Spiel: Kegel weg (die Sauger-Plätze räumt world.gd ab)
func forget_player(id: int) -> void:
	if _cones.has(id):
		_cones[id].queue_free()
		_cones.erase(id)


# ---------------------------------------------------------------- Upgrades

## Aufwickler und Drohnen passend zu den gekauften Stufen anlegen; Tempo-Faktoren setzen
func sync(eco: Economy) -> void:
	if not authority:
		return
	var system: CableSystem = world._system
	var motor_bonus := eco.bonus("motor")
	# Kabelsauger: jede Figur hat so viele Plätze, wie die Düse erlaubt
	if eco.state.level("vacuum") > 0:
		var want := vacuum_slots(eco)
		for ctx: PlayerCtx in (world._players as Dictionary).values():
			while ctx.vacuum_reels.size() < want:
				var r := ReelData.new(_next_tool_reel_id, ReelData.Kind.VACUUM)
				r.owner_id = ctx.id
				_next_tool_reel_id += 1
				system.add_reel(r)
				ctx.vacuum_reels.append(r)
			for r in ctx.vacuum_reels:
				r.speed_factor = eco.factor("vacuum_power") * motor_bonus
	for r: ReelData in system.reels.values():
		if r.kind == ReelData.Kind.WINCH:
			r.speed_factor = eco.factor("winch_speed") * motor_bonus
	# Drohnen
	while drones.size() < eco.state.level("drone"):
		if drones.is_empty() and drone_anchor == Vector3.ZERO:
			drone_anchor = world._player.global_position
		_spawn_drone(drone_anchor + Vector3(0, float(Balancing.drone.get("cruise_height_m", 10.0)), 0))
	for d in drones:
		(d["reel"] as ReelData).speed_factor = eco.factor("drone_speed") * motor_bonus


## Kabel gleichzeitig: Grundwert + Breitere Düse + Zyklon-Kammer
static func vacuum_slots(eco: Economy) -> int:
	var cfg: Dictionary = Balancing.vacuum
	var cyclone := int(Balancing.upgrades.get("vacuum_cyclone", {}).get("effect_add", 3))
	return int(cfg.get("slots", 3)) + int(cfg.get("slots_per_nozzle", 2)) * eco.state.level("vacuum_nozzle") \
		+ cyclone * eco.state.level("vacuum_cyclone")


func vacuum_radius(eco: Economy) -> float:
	var cfg: Dictionary = Balancing.vacuum
	return float(cfg.get("radius_m", 3.5)) + float(cfg.get("radius_per_nozzle_m", 0.8)) * eco.state.level("vacuum_nozzle")


func drone_speed_factor(eco: Economy) -> float:
	return eco.factor("drone_speed")


## Orte, an denen Kabel geladen bleiben müssen (Drohnen-Einsatzort, Winden)
func stream_points() -> Array[Vector3]:
	var out: Array[Vector3] = []
	if not drones.is_empty():
		out.append(drone_anchor)
	for r: ReelData in (world._system as CableSystem).reels.values():
		if r.kind == ReelData.Kind.WINCH and not r.carried:
			out.append(r.position)
	return out


# ---------------------------------------------------------------- jedes Bild

func update(delta: float, eco: Economy) -> void:
	_update_local_vacuum(eco)
	for ctx: PlayerCtx in (world._players as Dictionary).values():
		_update_vacuum(ctx, eco)
	if not authority:
		return
	_vacuum_t -= delta
	if _vacuum_t <= 0.0:
		_vacuum_t = float(Balancing.vacuum.get("grab_interval_s", 0.12))
		for ctx: PlayerCtx in (world._players as Dictionary).values():
			_vacuum_grab(ctx, eco)
	_winch_t -= delta
	if _winch_t <= 0.0:
		_winch_t = float(Balancing.winch.get("grab_interval_s", 0.4))
		_update_winches()
	for i in drones.size():
		_update_drone(drones[i], i, delta, eco)


## Eigene Figur: will sie saugen? (Linksklick halten bzw. Dauerbetrieb an/aus)
func _update_local_vacuum(eco: Economy) -> void:
	var me: PlayerCtx = world._me
	var player: Player = me.node
	var captured := Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	var has_vacuum := eco.state.level("vacuum") > 0
	var free: bool = has_vacuum and player.input_enabled and _ctx_free(me) and not world._crank_in_reach()
	var want := force_vacuum
	if eco.state.level("vacuum_auto") > 0:
		if free and captured and Input.is_action_just_pressed("pull"):
			vacuum_on = not vacuum_on
			world._show_message("Kabelsauger läuft." if vacuum_on else "Kabelsauger aus.")
		want = want or vacuum_on
	else:
		vacuum_on = false
		want = want or (captured and Input.is_action_pressed("pull"))
	me.vacuum_want = free and want


## Arm frei, nichts getragen, nicht an der Seilbahn
static func _ctx_free(ctx: PlayerCtx) -> bool:
	return ctx.arm_reel != null and ctx.arm_reel.is_free() and ctx.carried_reel == null and ctx.ride.is_empty() \
		and not ctx.node.riding


## Sauger einer Figur: Plätze folgen der Düse, Kegel zeigen, solange gesaugt wird
func _update_vacuum(ctx: PlayerCtx, eco: Economy) -> void:
	var player: Player = ctx.node
	if player == null:
		return
	var nozzle := player.global_position + player.facing() * 0.75 + Vector3(0, 1.05, 0)
	for r in ctx.vacuum_reels:
		r.position = nozzle
	ctx.vacuum_active = ctx.vacuum_want and eco.state.level("vacuum") > 0 and _ctx_free(ctx)
	player.tool_hold = ctx.vacuum_active
	var fx := _cone(ctx.id)
	fx.visible = ctx.vacuum_active
	if ctx.vacuum_active:
		# Kegel von der Düse zur Saugmitte, leicht pulsierend
		var radius := vacuum_radius(eco)
		var center := player.global_position + player.facing() * float(Balancing.vacuum.get("reach_ahead_m", 2.2))
		var to := center + Vector3(0, 0.2, 0) - nozzle
		var len := to.length()
		var basis := Basis.looking_at(to.normalized(), Vector3.UP) * Basis(Vector3.RIGHT, -PI * 0.5)
		var pulse := 1.0 + 0.06 * sin(Time.get_ticks_msec() / 60.0)
		fx.global_transform = Transform3D(basis.scaled(Vector3(radius * 0.8 * pulse, len, radius * 0.8 * pulse)),
			nozzle + to * 0.5)


## Host: freie Sauger-Plätze greifen die nächsten Kabelenden vor der Figur
func _vacuum_grab(ctx: PlayerCtx, eco: Economy) -> void:
	if not ctx.vacuum_active:
		return
	var player: Player = ctx.node
	var radius := vacuum_radius(eco)
	var center := player.global_position + player.facing() * float(Balancing.vacuum.get("reach_ahead_m", 2.2))
	for r in ctx.vacuum_reels:
		if not r.is_free():
			continue
		var pick := _nearest_end(center, radius, 2.5)
		if pick.is_empty():
			break
		_hook(pick, r)


## Winden hängen das nächste Kabelende in ihrem Umkreis selbst ein
func _update_winches() -> void:
	var system: CableSystem = world._system
	var radius := float(Balancing.winch.get("radius_m", 10.0))
	for r: ReelData in system.reels.values():
		if r.kind != ReelData.Kind.WINCH or r.carried or not r.is_free():
			continue
		var pick := _nearest_end(r.position, radius, 6.0)
		if not pick.is_empty():
			_hook(pick, r)


## Nächstes freies Kabelende im Haufen um `center` (waagerecht höchstens `radius`, senkrecht `max_dy`).
## Ergebnis: { "cable", "tail", "point" } oder leer.
func _nearest_end(center: Vector3, radius: float, max_dy: float) -> Dictionary:
	var best: Dictionary = {}
	var best_d := radius
	var landing: Dictionary = world._landing
	for c: CableData in (world._system as CableSystem).cables_near(center, radius + 0.5):
		if c.state != CableData.State.HEAP or _claimed.has(c.id) or landing.has(c.id):
			continue
		var pts := c.path.points
		for tail in [false, true]:
			var p: Vector3 = pts[pts.size() - 1] if tail else pts[0]
			if absf(p.y - center.y) > max_dy:
				continue
			var d := Vector2(p.x - center.x, p.z - center.z).length()
			if d < best_d:
				best_d = d
				best = { "cable": c, "tail": tail, "point": p }
	return best


func _hook(pick: Dictionary, reel: ReelData) -> bool:
	var c: CableData = pick["cable"]
	if bool(pick["tail"]):
		c.reverse()  # vom anderen Ende aus aufwickeln
	return (world._system as CableSystem).hook(c, reel)


# ---------------------------------------------------------------- Drohnen

func _spawn_drone(at: Vector3) -> void:
	var reel := ReelData.new(_next_tool_reel_id, ReelData.Kind.DRONE, at)
	_next_tool_reel_id += 1
	(world._system as CableSystem).add_reel(reel)
	var view := DroneView.new()
	world.add_child(view)
	view.global_position = at
	drones.append({ "reel": reel, "view": view, "pos": at, "state": "seek", "target": -1, "tail": false,
		"goal": at, "cargo": [], "think_t": randf() * 0.5 })


## Einsatzort aller Drohnen verlegen (laufende Kabel ziehen sie noch fertig)
func recall_drones(to: Vector3) -> void:
	drone_anchor = to
	for d in drones:
		if d["state"] == "fly_cable":
			_claimed.erase(int(d["target"]))
			d["state"] = "seek"
		elif d["state"] == "fetch":
			_claimed_items.erase(int(d["target"]))
			d["state"] = "seek"


func _update_drone(d: Dictionary, index: int, delta: float, eco: Economy) -> void:
	var cfg: Dictionary = Balancing.drone
	var reel: ReelData = d["reel"]
	var view: DroneView = d["view"]
	var pos: Vector3 = d["pos"]
	var speed := float(cfg.get("fly_speed_m_per_s", 14.0)) * drone_speed_factor(eco)
	match String(d["state"]):
		"pull":
			view.set_mode("work")
			if reel.is_free():
				d["state"] = "seek"
		"seek":
			view.set_mode("fly")
			d["think_t"] = float(d["think_t"]) - delta
			if float(d["think_t"]) <= 0.0:
				d["think_t"] = 0.4
				_drone_decide(d)
		_:
			view.set_mode("deliver" if d["state"] == "deliver" else "fly")
			pos = _fly(pos, d["goal"], speed, delta, float(cfg.get("cruise_height_m", 10.0)))
			if pos.distance_to(d["goal"]) < 0.25:
				_drone_arrive(d, index)
	d["pos"] = pos
	reel.position = pos - Vector3(0, 0.35, 0)
	view.global_position = pos
	# Mitgeführte Knäuel hängen unter der Drohne
	var cargo: Array = d["cargo"]
	for k in cargo.size():
		var item: CoilItem = cargo[k]
		item.position = pos + Vector3(0, -0.6 - k * 0.12, 0)
		var iv: CoilItemView = world._item_views.get(item.id)
		if iv:
			iv.carry_at(Transform3D(Basis.IDENTITY, item.position))


## Nächste Aufgabe: abliefern, liegende Knäuel holen, Kabel abrollen oder warten
func _drone_decide(d: Dictionary) -> void:
	var cfg: Dictionary = Balancing.drone
	var cargo: Array = d["cargo"]
	var radius := float(cfg.get("work_radius_m", 45.0))
	if cargo.size() >= int(cfg.get("capacity", 3)):
		_drone_deliver(d)
		return
	# Liegende Knäuel im Einsatzgebiet (z. B. von Winden oder der eigenen Arbeit)
	var pos: Vector3 = d["pos"]
	var best_item: CoilItem = null
	var best_d := INF
	for item: CoilItem in (world._items as Dictionary).values():
		if item.carried_by != -1 or _claimed_items.has(item.id):
			continue
		var flat := Vector2(item.position.x - drone_anchor.x, item.position.z - drone_anchor.z).length()
		if flat > radius:
			continue
		var dist := pos.distance_to(item.position)
		if dist < best_d:
			best_d = dist
			best_item = item
	if best_item:
		_claimed_items[best_item.id] = true
		d["state"] = "fetch"
		d["target"] = best_item.id
		d["goal"] = best_item.position + Vector3(0, 0.9, 0)
		return
	# Kabelende: wichtige Kabel im Einsatzgebiet zuerst, sonst das nächste zur Drohne
	var pick := _nearest_important_for_drone(pos, radius)
	if pick.is_empty():
		pick = _nearest_end_for_drone(pos, radius)
	if not pick.is_empty():
		var c: CableData = pick["cable"]
		_claimed[c.id] = true
		d["state"] = "fly_cable"
		d["target"] = c.id
		d["tail"] = pick["tail"]
		d["goal"] = (pick["point"] as Vector3) + Vector3(0, float(cfg.get("hover_height_m", 1.6)), 0)
		return
	if not cargo.is_empty():
		_drone_deliver(d)
		return
	# Nichts zu tun: über dem Einsatzort warten
	d["state"] = "idle"
	d["goal"] = world._ground_spot(drone_anchor) + Vector3((d["reel"] as ReelData).id % 3 - 1, float(cfg.get("cruise_height_m", 10.0)), 0)


func _nearest_important_for_drone(from: Vector3, radius: float) -> Dictionary:
	var best: Dictionary = {}
	var best_d := INF
	for c: CableData in (world._system as CableSystem).important.values():
		if c.state != CableData.State.HEAP or _claimed.has(c.id):
			continue
		var pts := c.path.points
		for tail in [false, true]:
			var p: Vector3 = pts[pts.size() - 1] if tail else pts[0]
			if Vector2(p.x - drone_anchor.x, p.z - drone_anchor.z).length() > radius:
				continue
			var dist := from.distance_squared_to(p)
			if dist < best_d:
				best_d = dist
				best = { "cable": c, "tail": tail, "point": p }
	return best


func _nearest_end_for_drone(from: Vector3, radius: float) -> Dictionary:
	var best: Dictionary = {}
	var best_d := INF
	var landing: Dictionary = world._landing
	for c: CableData in (world._system as CableSystem).cables_near(drone_anchor, radius):
		if c.state != CableData.State.HEAP or _claimed.has(c.id) or landing.has(c.id):
			continue
		var pts := c.path.points
		for tail in [false, true]:
			var p: Vector3 = pts[pts.size() - 1] if tail else pts[0]
			if Vector2(p.x - drone_anchor.x, p.z - drone_anchor.z).length() > radius:
				continue
			var dist := from.distance_squared_to(p)
			if dist < best_d:
				best_d = dist
				best = { "cable": c, "tail": tail, "point": p }
	return best


func _drone_deliver(d: Dictionary) -> void:
	d["state"] = "deliver"
	# Nächste Abgabe: Rohrpost-Station in Betrieb oder der Serverraum
	var drop: Dictionary = world.delivery_point(d["pos"])
	d["post"] = drop["post"]
	d["goal"] = (drop["pos"] as Vector3) + Vector3(0, 2.5 if drop["post"] == null else 6.5, 0)


func _drone_arrive(d: Dictionary, _index: int) -> void:
	var system: CableSystem = world._system
	match String(d["state"]):
		"fly_cable":
			var cid := int(d["target"])
			_claimed.erase(cid)
			var c: CableData = system.cables.get(cid)
			if c and c.state == CableData.State.HEAP:
				if bool(d["tail"]):
					c.reverse()
				if system.hook(c, d["reel"]):
					d["state"] = "pull"
					return
			d["state"] = "seek"
		"fetch":
			var iid := int(d["target"])
			_claimed_items.erase(iid)
			var item: CoilItem = (world._items as Dictionary).get(iid)
			if item and item.carried_by == -1:
				item.carried_by = -100  # trägt eine Drohne (im Spielstand: liegt dort, wo die Drohne war)
				world._items_dirty = true
				(d["cargo"] as Array).append(item)
				var iv: CoilItemView = world._item_views.get(iid)
				if iv:
					iv.set_carried(true)
			d["state"] = "seek"
		"deliver":
			var cargo: Array = d["cargo"]
			if not cargo.is_empty():
				world._plug_items(cargo.duplicate(), (d["pos"] as Vector3) + Vector3(0, 0.6, 0))
				cargo.clear()
				var post: PneumaticPost = d.get("post")
				if post and is_instance_valid(post):
					post.launch()
					Net.send_event("post", { "i": (world._posts as Array).find(post) })
			d["state"] = "seek"
		_:
			d["state"] = "seek"


## Fliegt in Reisehöhe zum Ziel und senkt sich erst in der Nähe ab
static func _fly(pos: Vector3, goal: Vector3, speed: float, delta: float, cruise: float) -> Vector3:
	var flat := Vector2(goal.x - pos.x, goal.z - pos.z)
	var target := goal
	if flat.length() > 4.0:
		target.y = maxf(goal.y, pos.y if pos.y > goal.y + cruise * 0.5 else goal.y + cruise)
	var step := target - pos
	var dist := step.length()
	if dist <= speed * delta:
		return target
	return pos + step / dist * speed * delta
