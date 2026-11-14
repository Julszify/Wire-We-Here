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
