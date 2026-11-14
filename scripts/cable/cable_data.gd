class_name CableData
extends RefCounted
## Reiner Spielzustand eines Kabels. Keine Darstellung, keine Szenen-Abhängigkeit.
## Gespeichert (und später übers Netz synchronisiert) werden nur Seed und veränderlicher Zustand;
## alles andere lässt sich aus `rng_seed` und `heap_center` deterministisch neu erzeugen.

enum State { HEAP, HOOKED, DONE }

var id: int = 0
var rng_seed: int = 0
var heap_center: Vector3 = Vector3.ZERO

# --- Aus dem Seed abgeleitet ---
## Spiel-Länge in Metern (bestimmt Geld und Knotenpositionen)
var length_m: float = 0.0
## Positionen der Knoten in gezogenen Metern, aufsteigend
var knots_m: PackedFloat32Array = PackedFloat32Array()
var color_index: int = 0
## Wichtiges Kabel: gehört an diesen Port im Server-Schrank (-1 = gewöhnliches Kabel)
var port_id: int = -1
## Sichtbare Bahn im Haufen (abgeleitet, wird nicht gespeichert)
var path: CablePath

# --- Veränderlicher Zustand ---
var state: State = State.HEAP
var pulled_m: float = 0.0
var reel_id: int = -1
var knots_solved: int = 0
## Tastendrücke am aktuellen Knoten
var knot_presses: int = 0


## Erzeugt ein Kabel vollständig aus dem Seed. Gleicher Seed = gleiches Kabel.
static func from_seed(cable_id: int, cable_seed: int, center: Vector3) -> CableData:
	var c: Dictionary = Balancing.cable
	var rng := RandomNumberGenerator.new()
	rng.seed = cable_seed

	var d := CableData.new()
	d.id = cable_id
	d.rng_seed = cable_seed
	d.heap_center = center
	# Reihenfolge der Zufallsaufrufe nicht ändern, sonst ändern sich alle Haufen
	d.path = CablePath.generate_heap_path(rng, center)
	d.length_m = rng.randf_range(c["length_min_m"], c["length_max_m"])

	var knot_count := 0
	if rng.randf() < float(c["knot_chance"]):
		knot_count = 2 if rng.randf() < float(c["double_knot_chance"]) else 1
	var knots: Array[float] = []
	for i in knot_count:
		knots.append(d.length_m * rng.randf_range(c["knot_min_fraction"], c["knot_max_fraction"]))
	knots.sort()
	d.knots_m = PackedFloat32Array(knots)

	d.color_index = rng.randi_range(0, (c["palette"] as Array).size() - 1)
	return d


func is_important() -> bool:
	return port_id >= 0


## Fortschritt 0..1
func progress() -> float:
	return clampf(pulled_m / length_m, 0.0, 1.0) if length_m > 0.0 else 0.0


## Position des nächsten ungelösten Knotens in Metern, INF wenn keiner mehr kommt
func next_knot_m() -> float:
	return knots_m[knots_solved] if knots_solved < knots_m.size() else INF


## Hängt das Kabel gerade an einem Knoten fest?
func is_stuck() -> bool:
	return pulled_m >= next_knot_m() - 1e-5


func color() -> Color:
	return Color.html(Balancing.cable["palette"][color_index])
