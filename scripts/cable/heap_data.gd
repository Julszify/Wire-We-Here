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
func create_cables(first_id: int) -> Array[CableData]:
	var out: Array[CableData] = []
	for i in cable_count:
		out.append(CableData.from_seed(first_id + i, cable_seed(i), center))
	return out
