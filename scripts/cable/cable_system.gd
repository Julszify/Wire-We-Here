class_name CableSystem
extends Node
## Spiellogik für Kabel und Aufwickler (Arm, Handkurbel, Motorrolle):
## einhängen, ziehen, loslassen, fertigstellen.
## Hält nur Daten und sendet Signale; Darstellung hört zu.
## Später läuft genau diese Logik beim Koop-Host, Clients bekommen den Zustand.

signal cable_hooked(cable: CableData, reel: ReelData)
signal cable_pulled(cable: CableData, reel: ReelData, meters: float)
signal cable_released(cable: CableData, reel: ReelData)
signal cable_completed(cable: CableData, reel: ReelData)

var cables: Dictionary = {}  # id -> CableData
var reels: Dictionary = {}   # id -> ReelData


func add_cable(cable: CableData) -> void:
	cables[cable.id] = cable


func remove_cable(cable_id: int) -> void:
	cables.erase(cable_id)


func add_reel(reel: ReelData) -> void:
	reels[reel.id] = reel


func cable_on(reel: ReelData) -> CableData:
	return cables.get(reel.cable_id) if reel.cable_id >= 0 else null


## Hängt ein Kabel aus dem Haufen an einen freien Aufwickler. Gibt false zurück, wenn nicht möglich.
func hook(cable: CableData, reel: ReelData) -> bool:
	if cable.state != CableData.State.HEAP or not reel.is_free():
		return false
	cable.state = CableData.State.HOOKED
	cable.reel_id = reel.id
	reel.cable_id = cable.id
	reel.pending_m = 0.0
	cable_hooked.emit(cable, reel)
	return true


## Ein Tastendruck (Arm oder Handkurbel). Die Meter werden über einige Frames
## abgearbeitet, damit das Ziehen flüssig aussieht.
func press(reel: ReelData) -> void:
	if reel.kind == ReelData.Kind.MOTOR or reel.is_free():
		return
	reel.pending_m += float(reel.tuning()["pull_per_press_m"])


## Kabel loslassen: es rutscht komplett zurück in den Haufen, der Fortschritt geht verloren.
func release(reel: ReelData) -> void:
	var cable := cable_on(reel)
	if cable == null:
		return
	cable.state = CableData.State.HEAP
	cable.pulled_m = 0.0
	cable.reel_id = -1
	reel.cable_id = -1
	reel.pending_m = 0.0
	cable_released.emit(cable, reel)


## Zieht `meters` am Kabel des Aufwicklers. Gibt die tatsächlich gezogenen Meter zurück.
func pull(reel: ReelData, meters: float) -> float:
	var cable := cable_on(reel)
	if cable == null or meters <= 0.0:
		return 0.0
	var applied := minf(meters, cable.length_m - cable.pulled_m)
	cable.pulled_m += applied
	cable_pulled.emit(cable, reel, applied)
	if cable.pulled_m >= cable.length_m - 1e-5:
		cable.pulled_m = cable.length_m
		_complete(cable, reel)
	return applied


func _process(delta: float) -> void:
	for reel: ReelData in reels.values():
		if reel.pending_m > 0.0:
			var feed: float = reel.tuning()["feed_speed_m_per_s"]
			var step := minf(reel.pending_m, feed * delta)
			reel.pending_m -= step
			pull(reel, step)


func _complete(cable: CableData, reel: ReelData) -> void:
	cable.state = CableData.State.DONE
	reel.cable_id = -1
	reel.pending_m = 0.0
	cable_completed.emit(cable, reel)
