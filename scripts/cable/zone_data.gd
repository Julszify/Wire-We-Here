class_name ZoneData
extends RefCounted
## Eine ganze Zone voller Kabel: Kabelberg, Haufen und Streukabel aus data/zone.json.
## Alles liegt von Anfang an da. Genau `important_count` Kabel werden wichtig
## und bekommen nacheinander die Ports 0, 1, 2, … – zufällig über die Zone verteilt.

var rng_seed: int = 0
var heaps: Array[HeapData] = []


static func from_config(zone_seed: int) -> ZoneData:
	var z: Dictionary = Balancing.zone
	var zone := ZoneData.new()
	zone.rng_seed = zone_seed
	var hid := 0
	for h: Dictionary in z.get("heaps", []):
		zone.heaps.append(HeapData.new(hid, hash([zone_seed, hid]), _vec(h["center"]), int(h["count"]),
			float(h["radius"]), float(h["peak_height"]), HeapData.Kind.HEAP))
		zone.heaps[-1].name = String(h.get("name", ""))
		hid += 1
	var sc: Dictionary = z.get("scatter", {})
	if int(sc.get("count", 0)) > 0:
		zone.heaps.append(HeapData.new(hid, hash([zone_seed, hid]), _vec(sc["center"]), int(sc["count"]),
			float(sc["radius"]), -1.0, HeapData.Kind.SCATTER))
	return zone


## Erzeugt alle Kabel der Zone. Wichtige Kabel bekommen nacheinander die Ports aus `free_ports`.
func create_cables(first_id: int, free_ports: Array[int]) -> Array[CableData]:
	var all: Array[CableData] = []
	var next_id := first_id
	for heap in heaps:
		all.append_array(heap.create_cables(next_id))
		next_id += heap.cable_count

	# Wichtige Kabel zufällig, aber reproduzierbar über die ganze Zone verteilen
	var wanted := mini(mini(int(Balancing.zone.get("important_count", 0)), free_ports.size()), all.size())
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([rng_seed, "important"])
	var pool: Array[int] = []
	for i in all.size():
		pool.append(i)
	for k in wanted:
		all[pool.pop_at(rng.randi_range(0, pool.size() - 1))].port_id = free_ports[k]
	return all


func cable_total() -> int:
	var n := 0
	for h in heaps:
		n += h.cable_count
	return n


## Liegt `pos` in einem Haufen (mit Abstand `margin`)? Gibt den Haufen zurück oder null.
func heap_at(pos: Vector3, margin: float = 0.0) -> HeapData:
	for h in heaps:
		if h.contains(pos, margin):
			return h
	return null


static func _vec(a: Array) -> Vector3:
	return Vector3(float(a[0]), float(a[1]), float(a[2]))
