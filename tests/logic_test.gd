extends Node
## Automatischer Logik-Test (ohne Grafik):
## godot --headless res://tests/logic_test.tscn
## Gibt "ALLE TESTS OK" aus oder bricht mit Fehlercode 1 ab.

var _failed := 0


func _ready() -> void:
	_test_knots_and_completion()
	_test_transfer_and_motor()
	_test_economy()
	_test_determinism()
	_test_rack_and_unlocks()
	_test_important_ports()
	_test_multipliers()
	_test_cord()
	_test_save_roundtrip()
	print("ALLE TESTS OK" if _failed == 0 else "%d TEST(S) FEHLGESCHLAGEN" % _failed)
	get_tree().quit(1 if _failed > 0 else 0)


func _check(cond: bool, what: String) -> void:
	if not cond:
		_failed += 1
		push_error("FEHLER: " + what)


func _cable_with_knots(min_knots: int) -> CableData:
	for s in range(1, 500):
		var c := CableData.from_seed(s, s, Vector3.ZERO)
		if c.knots_m.size() >= min_knots:
			return c
	return null


func _test_knots_and_completion() -> void:
	var sys := CableSystem.new()
	var arm := ReelData.new(0, ReelData.Kind.ARM)
	sys.add_reel(arm)
	var c := _cable_with_knots(2)
	sys.add_cable(c)
	var completed := []
	sys.cable_completed.connect(func(cc, _r): completed.append(cc))
	_check(sys.hook(c, arm), "Einhängen an Arm")
	sys.pull(arm, 1000.0)
	_check(is_equal_approx(c.pulled_m, c.knots_m[0]), "Stopp am ersten Knoten")
	_check(c.is_stuck(), "Kabel hängt fest")
	sys.press(arm)
	_check(arm.pending_m == 0.0, "Kein Ziehen am Knoten")
	for i in int(Balancing.knot["untie_presses"]):
		sys.untie(c)
	_check(not c.is_stuck() and c.knots_solved == 1, "Erster Knoten gelöst")
	sys.pull(arm, 1000.0)
	_check(is_equal_approx(c.pulled_m, c.knots_m[1]), "Stopp am zweiten Knoten")
	for i in int(Balancing.knot["untie_presses"]):
		sys.untie(c)
	sys.pull(arm, 1000.0)
	_check(completed.size() == 1 and c.state == CableData.State.DONE, "Kabel fertig")
	_check(arm.is_free(), "Arm wieder frei")
	sys.free()


func _test_transfer_and_motor() -> void:
	var sys := CableSystem.new()
	var arm := ReelData.new(0, ReelData.Kind.ARM)
	var motor := ReelData.new(1, ReelData.Kind.MOTOR, Vector3(5, 0, 0))
	sys.add_reel(arm)
	sys.add_reel(motor)
	var c := CableData.from_seed(1, 777, Vector3.ZERO)
	c.knots_m = PackedFloat32Array()
	sys.add_cable(c)
	sys.hook(c, arm)
	sys.pull(arm, 2.0)
	_check(sys.transfer(arm, motor), "Umhängen Arm -> Motorrolle")
	_check(arm.is_free() and motor.cable_id == c.id, "Rollen nach Umhängen")
	_check(is_equal_approx(c.pulled_m, 2.0), "Fortschritt bleibt beim Umhängen")
	sys._process(4.0)
	var expected := 2.0 + 4.0 * float(Balancing.motor_reel["pull_speed_m_per_s"])
	_check(is_equal_approx(c.pulled_m, expected), "Motor zieht von selbst (%.2f statt %.2f)" % [c.pulled_m, expected])
	sys.release(motor)
	_check(c.state == CableData.State.HEAP and c.pulled_m == 0.0 and motor.is_free(), "Loslassen setzt zurück")
	sys.free()


func _test_economy() -> void:
	var eco := Economy.new()
	add_child(eco)
	_check(Economy.format_money(1234.5) == "1.234,50 €", "Geldformat: " + Economy.format_money(1234.5))
	_check(Economy.format_money(0.05) == "0,05 €", "Geldformat klein: " + Economy.format_money(0.05))
	var paid := eco.pay_for_cable(20.0)
	_check(is_equal_approx(paid, 20.0 * float(Balancing.economy["money_per_meter"])), "Bezahlung pro Meter")
	_check(not eco.buy("extra_reel") or eco.state.money >= 0.0, "Kein Minus-Kontostand")
	var before := eco.state.money
	var half := eco.pay_for_cable(20.0, 0.5)
	_check(is_equal_approx(half, paid * 0.5) and is_equal_approx(eco.state.money, before + half), "Wichtiges Kabel bringt halben Preis")
	eco.state.money = 100.0
	_check(eco.buy("crank"), "Handkurbel kaufen")
	_check(eco.is_maxed("crank") and not eco.buy("crank"), "Handkurbel nur einmal")
	var c1 := eco.cost("extra_reel")
	eco.buy("extra_reel")
	_check(eco.cost("extra_reel") > c1, "Motorrolle wird teurer")
	eco.queue_free()


func _test_determinism() -> void:
	var a := HeapData.new(0, 42, Vector3.ZERO, 5).create_cables(0)
	var b := HeapData.new(0, 42, Vector3.ZERO, 5).create_cables(0)
	var same := true
	for i in 5:
		same = same and a[i].length_m == b[i].length_m and a[i].path.points == b[i].path.points and a[i].knots_m == b[i].knots_m
	_check(same, "Gleicher Seed = gleicher Haufen")


func _test_rack_and_unlocks() -> void:
	var eco := Economy.new()
	add_child(eco)
	var rack := ServiceRack.new(eco.state)
	_check(ServiceRack.port_count() == 20, "20 Ports im Schrank")
	eco.state.money = 1000.0
	_check(eco.is_locked("grip") and not eco.buy("grip"), "Festerer Griff anfangs gesperrt")
	_check(not eco.is_locked("crank") and not eco.is_locked("extra_reel"), "Kurbel und Motorrolle frei")
	var port := eco.locked_by("grip")
	var events := []
	rack.service_activated.connect(func(p, _n, u): events.append([p, u]))
	_check(rack.plug(port), "Einstecken")
	_check(not rack.plug(port), "Port nicht doppelt belegbar")
	_check(events.size() == 1 and events[0][1] == "grip", "Signal mit Freischaltung")
	_check(not eco.is_locked("grip") and eco.buy("grip"), "Festerer Griff nach Dienst kaufbar")
	_check(is_equal_approx(eco.factor("grip"), 1.5), "Griff-Faktor 1,5")
	rack.free()
	eco.queue_free()


func _test_important_ports() -> void:
	var zone := ZoneData.from_config(1234)
	var free: Array[int] = []
	for p in 20:
		free.append(p)
	var cables := zone.create_cables(0, free)
	_check(cables.size() == zone.cable_total() and cables.size() >= 500, "Über 500 Kabel in der Zone (%d)" % cables.size())
	var ports := []
	var heaps_with_important := {}
	for c in cables:
		if c.is_important():
			ports.append(c.port_id)
	ports.sort()
	_check(ports == free, "Genau 20 wichtige Kabel, Ports 0–19")
	var ids := {}
	for c in cables:
		ids[c.id] = true
	_check(ids.size() == cables.size(), "Kabel-IDs eindeutig")
	var again := ZoneData.from_config(1234).create_cables(0, free)
	var same := true
	for i in [0, 100, 300, cables.size() - 1]:
		same = same and again[i].path.points == cables[i].path.points and again[i].port_id == cables[i].port_id
	_check(same, "Zone reproduzierbar aus dem Seed")
	var few: Array[int] = [3, 7]
	var n := 0
	for c in ZoneData.from_config(1234).create_cables(0, few):
		if c.is_important():
			n += 1
	_check(n == 2, "Nur freie Ports werden vergeben")


func _test_multipliers() -> void:
	var sys := CableSystem.new()
	var arm := ReelData.new(0, ReelData.Kind.ARM)
	sys.add_reel(arm)
	var c := CableData.from_seed(1, 5, Vector3.ZERO)
	c.knots_m = PackedFloat32Array()
	sys.add_cable(c)
	sys.hook(c, arm)
	sys.press_multiplier = 1.5
	sys.press(arm)
	_check(is_equal_approx(arm.pending_m, 0.25 * 1.5), "Festerer Griff wirkt auf Tastendruck")
	sys.free()


func _test_cord() -> void:
	var cord := CordLogic.new()
	cord.setup(42)
	var events := []
	cord.order_requested.connect(func(_t): events.append("frage"))
	cord.order_declined.connect(func(): events.append("nein"))
	cord.order_placed.connect(func(n): events.append("bestellt %d" % n))
	cord.tick(float(Balancing.cord["first_ask_s"]) + 0.01)
	_check(cord.phase == CordLogic.Phase.ASKING and events == ["frage"], "C.O.R.D. fragt nach Startzeit")
	cord.decline()
	_check(cord.phase == CordLogic.Phase.IDLE and events[-1] == "nein", "Nein bricht ab")
	_check(cord.time_left >= float(Balancing.cord["ask_interval_min_s"]), "Danach Pause")
	cord.decline()
	_check(events.size() == 2, "Nein ohne Frage wirkungslos")
	cord.ask_now()
	cord.tick(cord.answer_time() + 0.01)
	_check(events[-1] == "bestellt %d" % int(Balancing.cord["order_count"]), "Ohne Antwort wird bestellt")
	_check(cord.orders_placed == 1 and cord.orders_declined == 1, "Zähler")
	var a := CordLogic.new()
	var b := CordLogic.new()
	a.setup(7)
	b.setup(7)
	a.ask_now()
	b.ask_now()
	a.decline()
	b.decline()
	_check(a.time_left == b.time_left, "Pausen reproduzierbar aus dem Seed")
	a.free()
	b.free()
	cord.free()


func _test_save_roundtrip() -> void:
	# GameState
	var gs := GameState.new()
	gs.money = 123.45
	gs.upgrades = { "grip": 2, "crank": 1 }
	gs.active_ports.append_array([0, 4])
	var gs2 := GameState.new()
	gs2.load_dict(JSON.parse_string(JSON.stringify(gs.to_dict())))
	_check(is_equal_approx(gs2.money, 123.45) and gs2.level("grip") == 2 and gs2.active_ports == gs.active_ports, "GameState über JSON")

	# C.O.R.D.: nach dem Laden gleiche Zufallsfolge
	var a := CordLogic.new()
	a.setup(99)
	a.ask_now()
	a.decline()
	var b := CordLogic.new()
	b.setup(1)
	b.load_dict(JSON.parse_string(JSON.stringify(a.to_dict())))
	_check(is_equal_approx(b.time_left, a.time_left) and b.phase == a.phase, "C.O.R.D.-Zustand über JSON")
	a.ask_now()
	a.decline()
	b.ask_now()
	b.decline()
	_check(a.time_left == b.time_left, "C.O.R.D.-Zufall läuft nach dem Laden gleich weiter")
	a.free()
	b.free()

	# Rolle, Knäuel, Haufen, Kabelzustand
	var r := ReelData.new(3, ReelData.Kind.MOTOR, Vector3(1.5, 0, -2.25))
	r.cable_id = 7
	var r2 := ReelData.from_dict(JSON.parse_string(JSON.stringify(r.to_dict())))
	_check(r2.id == 3 and r2.kind == ReelData.Kind.MOTOR and r2.position.is_equal_approx(r.position) and r2.cable_id == 7, "Rolle über JSON")
	var h := HeapData.new(8, 4242, Vector3(3, 0, 4), 12, 2.5, 1.4)
	var h2 := HeapData.from_dict(JSON.parse_string(JSON.stringify(h.to_dict())))
	_check(h2.create_cables(0)[5].path.points == h.create_cables(0)[5].path.points, "Lieferungs-Haufen über JSON gleich")
	var c := CableData.from_seed(1, 5, Vector3.ZERO)
	c.state = CableData.State.HOOKED
	c.pulled_m = 3.25
	c.knots_solved = 1
	var c2 := CableData.from_seed(1, 5, Vector3.ZERO)
	c2.load_state(JSON.parse_string(JSON.stringify(c.state_dict())))
	_check(c2.state == CableData.State.HOOKED and is_equal_approx(c2.pulled_m, 3.25) and c2.knots_solved == 1, "Kabelzustand über JSON")
