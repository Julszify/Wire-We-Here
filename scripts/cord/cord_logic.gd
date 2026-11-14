class_name CordLogic
extends Node
## C.O.R.D. (Cable Ordering & Repair Daemon): stellt in Abständen die Bestellfalle.
## "Defektes Kabel erkannt. Ersatz bestellen?" – wer nicht rechtzeitig Nein sagt,
## bekommt eine Lieferung neuer Kabel. Reine Logik mit Signalen, Zufall nur über den Seed.

## Frage beginnt; `answer_time` Sekunden bis zur automatischen Bestellung
signal order_requested(answer_time: float)
## Spieler hat rechtzeitig Nein gesagt
signal order_declined
## Zeit abgelaufen: `count` neue Kabel kommen
signal order_placed(count: int)

enum Phase { IDLE, ASKING }

var phase: Phase = Phase.IDLE
## Sekunden bis zur nächsten Frage (IDLE) bzw. bis zur Bestellung (ASKING)
var time_left: float = 0.0
var orders_placed: int = 0
var orders_declined: int = 0
## Bei Tablet & Co. nicht pausieren: das Spiel läuft weiter (Koop-tauglich)
var enabled := true

var _rng := RandomNumberGenerator.new()


func setup(cord_seed: int) -> void:
	_rng.seed = cord_seed
	phase = Phase.IDLE
	time_left = float(Balancing.cord["first_ask_s"])


## Antwort des Spielers. Nur während der Frage wirksam.
func decline() -> void:
	if phase != Phase.ASKING:
		return
	orders_declined += 1
	_wait_for_next()
	order_declined.emit()


## Sofort fragen (zum Testen).
func ask_now() -> void:
	_start_asking()


func answer_time() -> float:
	return float(Balancing.cord["answer_time_s"])


func _process(delta: float) -> void:
	tick(delta)


## Zeit fortschreiben (auch direkt aus Tests aufrufbar).
func tick(delta: float) -> void:
	if not enabled:
		return
	time_left -= delta
	if time_left > 0.0:
		return
	if phase == Phase.IDLE:
		_start_asking()
	else:
		orders_placed += 1
		_wait_for_next()
		order_placed.emit(int(Balancing.cord["order_count"]))


func _start_asking() -> void:
	phase = Phase.ASKING
	time_left = answer_time()
	order_requested.emit(time_left)


func _wait_for_next() -> void:
	phase = Phase.IDLE
	var c: Dictionary = Balancing.cord
	time_left = _rng.randf_range(float(c["ask_interval_min_s"]), float(c["ask_interval_max_s"]))


func to_dict() -> Dictionary:
	# Zufallszustand als Text, damit große Zahlen im JSON nicht ungenau werden
	return { "phase": phase, "time_left": time_left, "rng_seed": str(_rng.seed), "rng_state": str(_rng.state),
		"orders_placed": orders_placed, "orders_declined": orders_declined }


func load_dict(d: Dictionary) -> void:
	_rng.seed = String(d.get("rng_seed", "0")).to_int()
	_rng.state = String(d.get("rng_state", "0")).to_int()
	phase = int(d.get("phase", Phase.IDLE)) as Phase
	time_left = float(d.get("time_left", 30.0))
	orders_placed = int(d.get("orders_placed", 0))
	orders_declined = int(d.get("orders_declined", 0))
