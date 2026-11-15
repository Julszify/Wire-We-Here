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
	_test_rack_plan()
	_test_both_ends()
	_test_bonuses_and_bag()
	_test_unit_important()
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
	_check(RackPlan.tutorial_count() == 20, "20 Einzel-Dienste im Campus-Schrank")
	eco.state.money = 1000.0
	_check(eco.is_locked("grip") and not eco.buy("grip"), "Festerer Griff anfangs gesperrt")
	_check(not eco.is_locked("crank") and not eco.is_locked("extra_reel"), "Kurbel und Motorrolle frei")
	var port := eco.locked_by("grip")
	var events := []
	rack.service_activated.connect(func(p, _n, u): events.append([p, u]))
	port = RackPlan.service_ports(port)[0]
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
	cord.count_factor = 0.5
	_check(cord.order_count() == int(Balancing.cord["order_count"]) / 2, "Dienst-Bonus verkleinert die Bestellung")
	cord.ask_now()
	cord.snooze(300.0)
	_check(cord.phase == CordLogic.Phase.IDLE and cord.time_left >= 300.0, "Abschaltknopf: Frage weg, lange Ruhe")
	var before := events.size()
	cord.tick(299.0)
	_check(events.size() == before, "Während der Ruhe fragt C.O.R.D. nicht")
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
	gs.add_port(0)
	gs.add_port(4)
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


func _test_rack_plan() -> void:
	_check(RackPlan.total_ports() == 2000, "2000 Ports im Plan (%d)" % RackPlan.total_ports())
	_check(RackPlan.sections().size() == 10, "Zehn Schränke")
	_check(RackPlan.total_services() == 20 + 198, "20 Einzel-Dienste + 198 Reihen (%d)" % RackPlan.total_services())
	_check(RackPlan.service_of(7) == 7 and RackPlan.service_ports(7) == [7], "Einzel-Dienst = ein Port")
	_check(RackPlan.service_of(20) == 20 and RackPlan.service_of(29) == 20 and RackPlan.service_of(30) == 21, "Reihen à 10 Ports")
	var wohn := RackPlan.section("wohnviertel")
	_check(int(wohn["first_port"]) == 50 and int(wohn["count"]) == 100 and int(wohn["rows"]) == 10, "Wohnviertel: Ports 50–149")
	_check(RackPlan.row_ports("campus").size() == 30 and RackPlan.row_ports("campus")[0] == 20, "Campus: 30 Reihen-Ports")
	_check(RackPlan.port_label(4) == "Port 5 · Chef-Kalender", "Etikett Einzel-Dienst: " + RackPlan.port_label(4))
	_check(RackPlan.port_label(63).begins_with("Wohnviertel, Reihe 2"), "Etikett Reihe: " + RackPlan.port_label(63))
	_check(RackPlan.service_of(1999) == RackPlan.total_services() - 1 and RackPlan.service_of(2000) == -1, "Letzter Port")
	# Reihe wird erst mit dem zehnten Knäuel zum Dienst
	var gs := GameState.new()
	var rack := ServiceRack.new(gs)
	var events := []
	rack.service_activated.connect(func(s, _n, _u): events.append(s))
	for p in range(50, 59):
		rack.plug(p)
	_check(events.is_empty() and rack.active_services() == 0, "Neun Ports: Reihe noch nicht online")
	rack.plug(59)
	_check(events == [RackPlan.service_of(50)] and rack.active_services() == 1, "Zehnter Port: Dienst online")
	rack.free()


func _test_bonuses_and_bag() -> void:
	var eco := Economy.new()
	add_child(eco)
	var rack := ServiceRack.new(eco.state)
	_check(eco.bag_capacity() == int(Balancing.bag["capacity"]), "Tasche: Startgröße")
	var base := eco.pay_for_cable(10.0)
	# Dienste mit Geld-Bonus aus services.json einstecken
	var expected := 1.0
	var bag_extra := 0
	for port in 20:
		var def := RackPlan.service_def(port)
		expected *= float(def.get("bonus", {}).get("money", 1.0))
		bag_extra += int(def.get("bonus", {}).get("bag", 0))
		rack.plug(port)
	eco.refresh_bonuses()
	_check(is_equal_approx(eco.bonus("money"), expected) and expected > 1.0, "Geld-Bonus der Dienste (×%.2f)" % expected)
	_check(is_equal_approx(eco.pay_for_cable(10.0), base * expected), "Bonus wirkt auf die Bezahlung")
	_check(eco.bag_capacity() == int(Balancing.bag["capacity"]) + bag_extra, "Tasche wächst durch Dienste")
	_check(RackPlan.has_special(eco.state, "cord_snooze"), "Port 20 schaltet den Abschaltknopf frei")
	_check(eco.is_locked("bag"), "Größere Tasche gesperrt bis zur ersten Campus-Reihe")
	for port in RackPlan.service_ports(eco.locked_by("bag")):
		rack.plug(port)
	eco.state.money = 1000.0
	var cap := eco.bag_capacity()
	_check(eco.buy("bag") and eco.bag_capacity() == cap + int(Balancing.upgrades["bag"]["effect_add"]), "Upgrade Größere Tasche")
	var sys := CableSystem.new()
	sys.untie_delta = int(eco.bonus("knot_presses"))
	_check(sys.untie_needed() == int(Balancing.knot["untie_presses"]) - 1, "Knoten brauchen einen Druck weniger")
	sys.free()
	rack.free()
	eco.queue_free()


func _test_unit_important() -> void:
	# Einheit ohne Stadt: Haufen von Hand, Ports des Wohnviertels verteilen
	var u := CableUnit.new()
	u.id = "wohnviertel"
	u.first_id = CableUnit.ID_BASE
	u.heaps.append(HeapData.new(1, 11, Vector3.ZERO, 180))
	u.heaps.append(HeapData.new(2, 12, Vector3(20, 0, 0), 60))
	u._assign_important("wohnviertel", 2001)
	var ports := []
	for i in u.cable_total():
		var c := u.make_cable(i)
		if c.is_important():
			ports.append(c.port_id)
	ports.sort()
	_check(ports.size() == 100 and ports[0] == 50 and ports[-1] == 149, "Wohnviertel: 100 wichtige Kabel für Ports 50–149")
	var again := CableUnit.new()
	again.id = "wohnviertel"
	again.heaps = u.heaps
	again._assign_important("wohnviertel", 2001)
	_check(again.important == u.important, "Verteilung der wichtigen Kabel reproduzierbar")


func _test_both_ends() -> void:
	var c := CableData.from_seed(1, 5, Vector3.ZERO)
	var first := c.path.points[0]
	var last := c.path.points[c.path.points.size() - 1]
	# Strahl von oben auf das hintere Ende: wird als greifbares Ende erkannt
	var hit := CableTargeting.find_end([c], last + Vector3(0, 2, 0), Vector3.DOWN, last)
	_check(hit == c and CableTargeting.hit_tail, "Hinteres Kabelende ist greifbar")
	hit = CableTargeting.find_end([c], first + Vector3(0, 2, 0), Vector3.DOWN, first)
	_check(hit == c and not CableTargeting.hit_tail, "Vorderes Kabelende wie bisher")
	c.reverse()
	_check(c.path.points[0] == last and c.reversed, "Umdrehen: gegriffenes Ende ist points[0]")
	c.state = CableData.State.HOOKED
	c.pulled_m = 2.0
	var c2 := CableData.from_seed(1, 5, Vector3.ZERO)
	c2.load_state(JSON.parse_string(JSON.stringify(c.state_dict())))
	_check(c2.reversed and c2.path.points[0] == last, "Umgedrehtes Kabel über JSON")
