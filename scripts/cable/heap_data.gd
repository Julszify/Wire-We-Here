class_name HeapData
extends RefCounted
## Eine Gruppe von Kabeln: ein Haufen (rund, in der Mitte höher) oder Streukabel über eine Fläche.
## Die einzelnen Kabel-Seeds werden aus dem Seed der Gruppe abgeleitet (reproduzierbar).

enum Kind { HEAP, SCATTER, STREET }

var id: int = 0
var rng_seed: int = 0
var center: Vector3 = Vector3.ZERO
var cable_count: int = 0
var kind: Kind = Kind.HEAP
## Haufen: Radius; Streukabel: Radius der Fläche
var radius: float = 0.0
## Haufen: zusätzliche Höhe in der Mitte
var peak_height: float = 0.0
## Straßenkabel: Richtung, in die das Kabel vom greifbaren Ende aus liegt (radius = Länge)
var dir: Vector3 = Vector3.FORWARD
var name: String = ""


func _init(heap_id: int = 0, heap_seed: int = 0, heap_center: Vector3 = Vector3.ZERO, count: int = 0,
		heap_radius: float = -1.0, peak: float = -1.0, heap_kind: Kind = Kind.HEAP) -> void:
	id = heap_id
	rng_seed = heap_seed
	center = heap_center
	cable_count = count
	kind = heap_kind
	radius = heap_radius if heap_radius > 0.0 else float(Balancing.heap["radius_m"])
	peak_height = peak if peak > 0.0 else float(Balancing.heap["peak_extra_height_m"])


## Kabelzahl aus world.json / zone.json mal balancing.json → cable.count_factor (mindestens 1)
static func scaled(count: int) -> int:
	if count <= 0:
		return 0
	return maxi(1, roundi(count * float(Balancing.cable.get("count_factor", 1.0))))


func cable_seed(index: int) -> int:
	return hash([rng_seed, index])


## Erzeugt alle Kabel der Gruppe. `first_id` ist die erste freie Kabel-ID.
func create_cables(first_id: int) -> Array[CableData]:
	var out: Array[CableData] = []
	for i in cable_count:
		out.append(CableData.from_seed(first_id + i, cable_seed(i), center, self))
	return out


## Liegt `pos` (waagerecht betrachtet) im Haufen, mit zusätzlichem Abstand `margin`?
func contains(pos: Vector3, margin: float = 0.0) -> bool:
	if kind != Kind.HEAP:
		return false
	return Vector2(pos.x - center.x, pos.z - center.z).length() < radius + margin


func to_dict() -> Dictionary:
	return { "id": id, "seed": rng_seed, "center": SaveGame.vec_to(center), "count": cable_count,
		"kind": kind, "radius": radius, "peak_height": peak_height, "name": name, "dir": SaveGame.vec_to(dir) }


static func from_dict(d: Dictionary) -> HeapData:
	var h := HeapData.new(int(d["id"]), int(d["seed"]), SaveGame.vec_from(d["center"]), int(d["count"]),
		float(d["radius"]), float(d["peak_height"]), int(d.get("kind", Kind.HEAP)) as Kind)
	h.name = String(d.get("name", ""))
	if d.has("dir"):
		h.dir = SaveGame.vec_from(d["dir"])
	return h
