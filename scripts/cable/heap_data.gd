class_name HeapData
extends RefCounted
## Ein Kabelhaufen: Mittelpunkt, Seed und Anzahl Kabel.
## Die einzelnen Kabel-Seeds werden aus dem Haufen-Seed abgeleitet (reproduzierbar).

var id: int = 0
var rng_seed: int = 0
var center: Vector3 = Vector3.ZERO
var cable_count: int = 0


func _init(heap_id: int = 0, heap_seed: int = 0, heap_center: Vector3 = Vector3.ZERO, count: int = 0) -> void:
	id = heap_id
	rng_seed = heap_seed
	center = heap_center
	cable_count = count


func cable_seed(index: int) -> int:
	return hash([rng_seed, index])


## Erzeugt alle Kabel des Haufens. `first_id` ist die erste freie Kabel-ID.
## Wichtige Kabel bekommen der Reihe nach Ports ab `first_port` (bis `port_count`).
func create_cables(first_id: int, first_port: int = 0, port_count: int = 0) -> Array[CableData]:
	var out: Array[CableData] = []
	for i in cable_count:
		out.append(CableData.from_seed(first_id + i, cable_seed(i), center))
	var next_port := first_port
	for i in important_indices():
		if next_port >= port_count:
			break
		out[i].port_id = next_port
		next_port += 1
	return out


## Welche Kabel des Haufens wichtig sind (aus dem Seed, aufsteigend sortiert).
func important_indices() -> Array[int]:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([rng_seed, "important"])
	var pool: Array[int] = []
	for i in cable_count:
		pool.append(i)
	var picked: Array[int] = []
	var wanted := mini(int(Balancing.heap.get("important_per_heap", 0)), cable_count)
	for n in wanted:
		picked.append(pool.pop_at(rng.randi_range(0, pool.size() - 1)))
	picked.sort()
	return picked
