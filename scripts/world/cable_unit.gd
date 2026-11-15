class_name CableUnit
extends RefCounted
## Ein ladbares Paket Kabel in der Stadt: die Kabel eines Viertels oder eine Sperre (großer Kabelberg).
## Rein aus world.json und Seeds abgeleitet; die Kabel-IDs liegen fest in einem eigenen Bereich
## (ID_BASE + Index * ID_STEP), damit Spielstände auch dann passen, wenn die Einheit gerade entladen ist.
## Der Hinterhof gehört nicht dazu: er bleibt die bisherige, immer geladene Zone (IDs ab 0).

const ID_BASE := 1_000_000
const ID_STEP := 100_000

var id: String = ""
var name: String = ""
## Mitte in Szenen-Koordinaten; Ladeabstand wird vom Rand (center ± half) gemessen
var center: Vector3 = Vector3.ZERO
var half: Vector2 = Vector2.ZERO
var heaps: Array[HeapData] = []
var first_id: int = 0
## Sperre: blockiert eine Lücke, bis clear_fraction der Kabel abgetragen ist
var barrier := false
var clear_fraction := 0.75
## Unsichtbare Wände der Sperre: [Mitte, Größe] je Kiste
var blocker_boxes: Array[Array] = []
## Wichtige Kabel der Einheit: Index des Kabels -> Port im Serverraum (aus RackPlan, zufällig verteilt)
var important: Dictionary = {}


## Alle Einheiten der Stadt (in Szenen-Koordinaten der übergebenen Stadt)
static func build_all(city: CityWorld) -> Array[CableUnit]:
	var units: Array[CableUnit] = []
	var layout := city.layout
	for b: Dictionary in layout.raw().get("barriers", []):
		units.append(_barrier(city, b, units.size()))
	for d in layout.districts:
		if d.has("cables"):
			units.append(_district(city, d, units.size()))
	return units


func cable_total() -> int:
	var n := 0
	for h in heaps:
		n += h.cable_count
	return n


func last_id() -> int:
	return first_id + cable_total() - 1


func owns(cable_id: int) -> bool:
	return cable_id >= first_id and cable_id <= last_id()


## Waagerechter Abstand eines Punkts zum Rand der Einheit (0 = innerhalb)
func distance_to(pos: Vector3) -> float:
	var q := Vector2(absf(pos.x - center.x), absf(pos.z - center.z)) - half
	return Vector2(maxf(q.x, 0.0), maxf(q.y, 0.0)).length()


## Kabel i der Einheit (in der Reihenfolge der Haufen); erzeugt die Daten aus dem Seed
func make_cable(index: int) -> CableData:
	var k := index
	for h in heaps:
		if k < h.cable_count:
			var cable := CableData.from_seed(first_id + index, h.cable_seed(k), h.center, h)
			cable.port_id = int(important.get(index, -1))
			return cable
		k -= h.cable_count
	return null


## Verteilt die Reihen-Ports eines Schranks (RackPlan) zufällig, aber reproduzierbar auf die Kabel
func _assign_important(section_id: String, unit_seed: int) -> void:
	important.clear()
	var ports := RackPlan.row_ports(section_id)
	if ports.is_empty():
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([unit_seed, id, "important"])
	var pool: Array[int] = []
	for i in cable_total():
		pool.append(i)
	for k in mini(ports.size(), pool.size()):
		important[pool.pop_at(rng.randi_range(0, pool.size() - 1))] = ports[k]


# ---------------------------------------------------------------- Aufbau

static func _barrier(city: CityWorld, b: Dictionary, index: int) -> CableUnit:
	var layout := city.layout
	var from := layout.district(String(b["road"][0]))
	var to := layout.district(String(b["road"][1]))
	var p := layout.exit_point(from, to)
	var out := (WorldLayout._v2(to["center"]) - WorldLayout._v2(from["center"]))
	out = Vector2(signf(out.x), 0.0) if absf(out.x) > absf(out.y) else Vector2(0.0, signf(out.y))
	var hc := p + out * float(b.get("offset_m", 0.0))
	var u := CableUnit.new()
	u.id = String(b["id"])
	u.name = String(b.get("name", u.id))
	u.barrier = true
	u.clear_fraction = float(b.get("clear_fraction", 0.75))
	u.first_id = ID_BASE + index * ID_STEP
	var r := float(b["radius_m"])
	u.center = city.to_scene(hc)
	u.half = Vector2(r, r)
	var heap := HeapData.new(9000 + index, hash([int(b.get("seed", 1)), u.id]), u.center, int(b["count"]), r,
		float(b["peak_m"]), HeapData.Kind.HEAP)
	heap.name = u.name
	u.heaps.append(heap)
	# Blockade hinter dem Berg (von innen gesehen): eine Rückwand jenseits des Zauns und zwei Seitenwände
	# zurück zum Zaun. So bleibt der ganze Berg von der Campus-Seite aus erreichbar.
	var wall: Dictionary = from.get("wall", {})
	var gap := float(wall.get("gap_m", 20.0))
	var depth := maxf(float(b.get("offset_m", 0.0)) + r + float(b.get("blocker_margin_m", 1.5)), 1.0)
	var bp := city.to_scene(p)
	var out3 := Vector3(out.x, 0, out.y)
	var side3 := Vector3(-out.y, 0, out.x)
	var up := Vector3(0, 2.0, 0)
	u.blocker_boxes.append([bp + out3 * depth + up, _box_size(side3, gap + 2.0, out3, 1.0)])
	for sgn in [-1.0, 1.0]:
		u.blocker_boxes.append([bp + out3 * depth * 0.5 + side3 * sgn * (gap * 0.5 + 0.5) + up,
			_box_size(side3, 1.0, out3, depth + 1.0)])
	if b.has("important_section"):
		u._assign_important(String(b["important_section"]), int(b.get("seed", 1)))
	return u


## Größe einer achsparallelen Kiste: `across` Meter quer (Richtung side), `along` Meter längs (Richtung out)
static func _box_size(side: Vector3, across: float, out: Vector3, along: float) -> Vector3:
	return Vector3(absf(side.x) * across + absf(out.x) * along, 4.0, absf(side.z) * across + absf(out.z) * along)


static func _district(city: CityWorld, d: Dictionary, index: int) -> CableUnit:
	var layout := city.layout
	var cfg: Dictionary = d["cables"]
	var bo: Dictionary = d.get("blockout", {})
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([int(cfg.get("seed", 1)), String(d["id"])])
	var u := CableUnit.new()
	u.id = String(d["id"])
	u.name = String(d["name"])
	u.first_id = ID_BASE + index * ID_STEP
	var c := WorldLayout._v2(d["center"])
	var half := WorldLayout._v2(d["size"]) * 0.5
	u.center = city.to_scene(c)
	u.half = half
	var block := float(bo.get("block_m", 60.0))
	var street := float(bo.get("street_m", 10.0))
	var xs := WorldLayout.grid_lines(c.x, half.x, block)
	var zs := WorldLayout.grid_lines(c.y, half.y, block)

	# Haufen auf zufällig gewählten Kreuzungen
	var crossings: Array[Vector2] = []
	for x in xs:
		for z in zs:
			crossings.append(Vector2(x, z))
	var wanted := mini(int(cfg.get("crossing_heaps", 0)), crossings.size())
	var hid := 9100 + index * 100
	for k in wanted:
		var p: Vector2 = crossings.pop_at(rng.randi_range(0, crossings.size() - 1))
		var heap := HeapData.new(hid, rng.randi(), city.to_scene(p),
			rng.randi_range(int(cfg["heap_count"][0]), int(cfg["heap_count"][1])),
			rng.randf_range(float(cfg["heap_radius"][0]), float(cfg["heap_radius"][1])),
			rng.randf_range(float(cfg["heap_peak"][0]), float(cfg["heap_peak"][1])), HeapData.Kind.HEAP)
		heap.name = "%s, Kreuzung" % u.name
		u.heaps.append(heap)
		hid += 1

	# Einzelne Kabel entlang der Straßen (je ein "Haufen" mit einem Kabel)
	for k in int(cfg.get("street_cables", 0)):
		var along_x := rng.randf() < 0.5
		var line: float = (zs if along_x else xs)[rng.randi_range(0, (zs if along_x else xs).size() - 1)]
		var length := rng.randf_range(float(cfg["street_length_m"][0]), float(cfg["street_length_m"][1]))
		var span := (half.x if along_x else half.y) - length - 4.0
		var t := rng.randf_range(-span, span)
		var lateral := rng.randf_range(-street * 0.3, street * 0.3)
		var start := Vector2(c.x + t, line + lateral) if along_x else Vector2(line + lateral, c.y + t)
		var heap := HeapData.new(hid, rng.randi(), city.to_scene(start), 1, length, -1.0, HeapData.Kind.STREET)
		var sign := 1.0 if rng.randf() < 0.5 else -1.0
		heap.dir = Vector3(sign, 0, 0) if along_x else Vector3(0, 0, sign)
		heap.name = "%s, Straße" % u.name
		u.heaps.append(heap)
		hid += 1
	u._assign_important(u.id, int(cfg.get("seed", 1)))
	return u
