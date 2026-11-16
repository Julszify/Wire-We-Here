class_name CableSystem
extends Node
## Spiellogik für Kabel und Aufwickler (Arm, Handkurbel, Motorrolle):
## einhängen, umhängen, ziehen, Knoten lösen, loslassen, fertigstellen.
## Hält nur Daten und sendet Signale; Darstellung hört zu.
## Später läuft genau diese Logik beim Koop-Host, Clients bekommen den Zustand.

signal cable_hooked(cable: CableData, reel: ReelData)
signal cable_pulled(cable: CableData, reel: ReelData, meters: float)
signal cable_released(cable: CableData, reel: ReelData)
signal cable_completed(cable: CableData, reel: ReelData)
signal knot_hit(cable: CableData, reel: ReelData)
signal knot_progress(cable: CableData, presses: int, needed: int)
signal knot_solved(cable: CableData)

var cables: Dictionary = {}  # id -> CableData
var reels: Dictionary = {}   # id -> ReelData

## Upgrade-Wirkungen, von außen gesetzt (Festerer Griff, Stärkere Motoren)
var press_multiplier: float = 1.0
var motor_multiplier: float = 1.0
## Dienst-Bonus: so viele Drücke weniger (negativ) oder mehr pro Knoten
var untie_delta: int = 0


## Raster der Kabelenden (Zelle -> Kabel), damit das Anvisieren bei zehntausenden Kabeln schnell bleibt
const GRID_CELL_M := 4.0
var _grid: Dictionary = {}


## Geladene wichtige Kabel (id -> CableData), für Detektor und Drohnen
var important: Dictionary = {}


func add_cable(cable: CableData) -> void:
	cables[cable.id] = cable
	_index(cable, true)
	if cable.is_important():
		important[cable.id] = cable


func remove_cable(cable_id: int) -> void:
	var cable: CableData = cables.get(cable_id)
	if cable:
		_index(cable, false)
	cables.erase(cable_id)
	important.erase(cable_id)


## Kabel, deren Enden in Zellen um `pos` liegen (Radius in Metern); ein Kabel kann doppelt vorkommen
func cables_near(pos: Vector3, radius: float) -> Array:
	var out: Array = []
	var lo := _cell(pos - Vector3(radius, 0, radius))
	var hi := _cell(pos + Vector3(radius, 0, radius))
	for x in range(lo.x, hi.x + 1):
		for z in range(lo.y, hi.y + 1):
			var list: Variant = _grid.get(Vector2i(x, z))
			if list != null:
				out.append_array(list)
	return out


## Kabel, die gerade an einem Aufwickler hängen
func hooked_cables() -> Array:
	var out: Array = []
	for reel: ReelData in reels.values():
		var c := cable_on(reel)
		if c:
			out.append(c)
	return out


func _cell(p: Vector3) -> Vector2i:
	return Vector2i(floori(p.x / GRID_CELL_M), floori(p.z / GRID_CELL_M))


func _index(cable: CableData, add: bool) -> void:
	var pts := cable.path.points
	if pts.is_empty():
		return
	var keys := [_cell(pts[0])]
	var tail := _cell(pts[pts.size() - 1])
	if tail != keys[0]:
		keys.append(tail)
	for k: Vector2i in keys:
		var list: Array = _grid.get(k, [])
		if add:
			list.append(cable)
			_grid[k] = list
		else:
			list.erase(cable)
			if list.is_empty():
				_grid.erase(k)
			else:
				_grid[k] = list


func add_reel(reel: ReelData) -> void:
	reels[reel.id] = reel


func cable_on(reel: ReelData) -> CableData:
	return cables.get(reel.cable_id) if reel.cable_id >= 0 else null


func reel_of(cable: CableData) -> ReelData:
	return reels.get(cable.reel_id) if cable.reel_id >= 0 else null


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


## Hängt ein Kabel von einem Aufwickler an einen anderen (z. B. Arm -> Rolle).
## Der Fortschritt bleibt erhalten.
func transfer(from_reel: ReelData, to_reel: ReelData) -> bool:
	var cable := cable_on(from_reel)
	if cable == null or not to_reel.is_free():
		return false
	from_reel.cable_id = -1
	from_reel.pending_m = 0.0
	cable.reel_id = to_reel.id
	to_reel.cable_id = cable.id
	to_reel.pending_m = 0.0
	cable_hooked.emit(cable, to_reel)
	return true


## Ein Tastendruck (Arm oder Handkurbel). Die Meter werden über einige Frames
## abgearbeitet, damit das Ziehen flüssig aussieht.
func press(reel: ReelData) -> void:
	if reel.is_motorized() or reel.is_free():
		return
	var cable := cable_on(reel)
	if cable.is_stuck():
		return
	reel.pending_m += float(reel.tuning()["pull_per_press_m"]) * press_multiplier


## Ein Tastendruck am Knoten. Nach genügend Drücken ist der Knoten gelöst.
func untie(cable: CableData) -> void:
	if not cable.is_stuck():
		return
	var needed := untie_needed()
	cable.knot_presses += 1
	knot_progress.emit(cable, cable.knot_presses, needed)
	if cable.knot_presses >= needed:
		cable.knot_presses = 0
		cable.knots_solved += 1
		knot_solved.emit(cable)


func untie_needed() -> int:
	return maxi(1, int(Balancing.knot["untie_presses"]) + untie_delta)


## Kabel loslassen: es rutscht komplett zurück in den Haufen, der Fortschritt geht verloren.
## Bereits gelöste Knoten bleiben gelöst.
func release(reel: ReelData) -> void:
	var cable := cable_on(reel)
	if cable == null:
		return
	cable.state = CableData.State.HEAP
	cable.pulled_m = 0.0
	cable.knot_presses = 0
	cable.reel_id = -1
	reel.cable_id = -1
	reel.pending_m = 0.0
	cable_released.emit(cable, reel)


## Zieht `meters` am Kabel des Aufwicklers, höchstens bis zum nächsten Knoten.
## Gibt die tatsächlich gezogenen Meter zurück.
func pull(reel: ReelData, meters: float) -> float:
	var cable := cable_on(reel)
	if cable == null or meters <= 0.0 or cable.is_stuck():
		return 0.0
	var limit := minf(cable.length_m, cable.next_knot_m())
	var applied := minf(meters, limit - cable.pulled_m)
	cable.pulled_m += applied
	cable_pulled.emit(cable, reel, applied)
	if cable.pulled_m >= cable.length_m - 1e-5:
		cable.pulled_m = cable.length_m
		_complete(cable, reel)
	elif cable.is_stuck():
		reel.pending_m = 0.0
		knot_hit.emit(cable, reel)
	return applied


func _process(delta: float) -> void:
	for reel: ReelData in reels.values():
		if reel.is_free():
			continue
		if reel.is_automatic():
			# Sauger, Winde, Drohne: eigenes Tempo (Upgrades der Werkzeug-Art), Knoten lösen sich nach einer Weile
			var cable := cable_on(reel)
			if cable.is_stuck():
				reel.stuck_t += delta
				if reel.stuck_t >= float(reel.tuning().get("auto_untie_s", 2.0)):
					reel.stuck_t = 0.0
					cable.knot_presses = 0
					cable.knots_solved += 1
					knot_solved.emit(cable)
				continue
			reel.stuck_t = 0.0
			pull(reel, float(reel.tuning()["pull_speed_m_per_s"]) * reel.speed_factor * delta)
		elif reel.is_motorized():
			pull(reel, float(reel.tuning()["pull_speed_m_per_s"]) * motor_multiplier * delta)
		elif reel.pending_m > 0.0:
			var feed: float = float(reel.tuning()["feed_speed_m_per_s"]) * press_multiplier
			var step := minf(reel.pending_m, feed * delta)
			reel.pending_m -= step
			pull(reel, step)


func _complete(cable: CableData, reel: ReelData) -> void:
	cable.state = CableData.State.DONE
	reel.cable_id = -1
	reel.pending_m = 0.0
	cable_completed.emit(cable, reel)
