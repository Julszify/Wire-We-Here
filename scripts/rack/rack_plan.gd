class_name RackPlan
extends RefCounted
## Plan aller Ports im Serverraum, abgeleitet aus world.json (important_plan) und services.json.
## Jedes Viertel hat einen Schrank; die Ports sind über alle Schränke durchnummeriert (0 … 1999).
##   - Die ersten `tutorial_ports` Ports (Campus) sind Einzel-Dienste: ein Port = ein Dienst.
##   - Alle übrigen Ports bilden Reihen à `row_size`; eine volle Reihe = ein Dienst.
## Dienste sind ebenfalls durchnummeriert: erst die Einzel-Dienste, dann die Reihen in Port-Reihenfolge.
## Reine Funktionen ohne Zustand; welche Ports belegt sind, steht in GameState.

## Diese Boni werden addiert, alle anderen multipliziert
const ADDITIVE := ["bag", "answer_time", "knot_presses"]

static var _sections: Array[Dictionary] = []


## Schränke in Spielreihenfolge: { id, name, first_port, count, tutorial, rows, first_service }
static func sections() -> Array[Dictionary]:
	if _sections.is_empty():
		_build()
	return _sections


static func reset() -> void:
	_sections.clear()


static func row_size() -> int:
	return int(Balancing.world.get("important_plan", {}).get("row_size", 10))


static func tutorial_count() -> int:
	return int(sections()[0]["tutorial"]) if not sections().is_empty() else 0


static func total_ports() -> int:
	var s := sections()
	return int(s[-1]["first_port"]) + int(s[-1]["count"]) if not s.is_empty() else 0


static func total_services() -> int:
	var s := sections()
	return int(s[-1]["first_service"]) + int(s[-1]["tutorial"]) + int(s[-1]["rows"]) if not s.is_empty() else 0


static func section(id: String) -> Dictionary:
	for s in sections():
		if s["id"] == id:
			return s
	return {}


static func section_of_port(port: int) -> Dictionary:
	for s in sections():
		if port >= int(s["first_port"]) and port < int(s["first_port"]) + int(s["count"]):
			return s
	return {}


static func section_of_service(service: int) -> Dictionary:
	for s in sections():
		if service >= int(s["first_service"]) and service < int(s["first_service"]) + int(s["tutorial"]) + int(s["rows"]):
			return s
	return {}


## Ports eines Schranks, die zu Reihen gehören (ohne die Einzel-Dienste)
## Eingesteckte Ports eines Schranks (Fortschritt eines Viertels)
## Viertel am Netz: Schränke, in denen alle Ports belegt sind (Fortschritt für Upgrade-Stufen)
static func districts_online(state: GameState) -> int:
	var counts := {}
	for sec in sections():
		counts[String(sec["id"])] = 0
	for p in state.active_ports:
		var sec := section_of_port(p)
		if not sec.is_empty():
			counts[String(sec["id"])] = int(counts[String(sec["id"])]) + 1
	var n := 0
	for sec in sections():
		if int(counts[String(sec["id"])]) >= int(sec["count"]):
			n += 1
	return n


static func section_plugged(state: GameState, section_id: String) -> int:
	var sec := section(section_id)
	if sec.is_empty():
		return 0
	var first := int(sec["first_port"])
	var n := 0
	for p in state.active_ports:
		if p >= first and p < first + int(sec["count"]):
			n += 1
	return n


## Sind alle Ports bis auf die des letzten Schranks (Turm) belegt? Dann fährt der Aufzug zum Finale.
static func all_but_last_plugged(state: GameState) -> bool:
	var s := sections()
	if s.is_empty():
		return false
	return state.active_ports.size() >= int(s[-1]["first_port"]) and _plugged_below(state, int(s[-1]["first_port"]))


static func _plugged_below(state: GameState, limit: int) -> bool:
	var n := 0
	for p in state.active_ports:
		if p < limit:
			n += 1
	return n >= limit


static func row_ports(section_id: String) -> Array[int]:
	var out: Array[int] = []
	var s := section(section_id)
	if s.is_empty():
		return out
	for p in range(int(s["first_port"]) + int(s["tutorial"]), int(s["first_port"]) + int(s["count"])):
		out.append(p)
	return out


## Dienst, zu dem ein Port gehört (-1 = Port gibt es nicht)
static func service_of(port: int) -> int:
	var s := section_of_port(port)
	if s.is_empty():
		return -1
	var local := port - int(s["first_port"])
	var tut := int(s["tutorial"])
	if local < tut:
		return int(s["first_service"]) + local
	return int(s["first_service"]) + tut + floori(float(local - tut) / row_size())


## Alle Ports eines Dienstes (ein Port bei Einzel-Diensten, sonst eine Reihe)
static func service_ports(service: int) -> Array[int]:
	var out: Array[int] = []
	var s := section_of_service(service)
	if s.is_empty():
		return out
	var local := service - int(s["first_service"])
	var tut := int(s["tutorial"])
	if local < tut:
		out.append(int(s["first_port"]) + local)
		return out
	var first := int(s["first_port"]) + tut + (local - tut) * row_size()
	for p in range(first, first + row_size()):
		out.append(p)
	return out


## Reihe des Dienstes in seinem Schrank (0 = erste Reihe), -1 bei Einzel-Diensten
static func row_of_service(service: int) -> int:
	var s := section_of_service(service)
	if s.is_empty():
		return -1
	var local := service - int(s["first_service"]) - int(s["tutorial"])
	return local if local >= 0 else -1


## Eintrag des Dienstes aus services.json ({} wenn dort noch nichts steht)
static func service_def(service: int) -> Dictionary:
	var s := section_of_service(service)
	if s.is_empty():
		return {}
	var row := row_of_service(service)
	if row < 0:
		var local := service - int(s["first_service"])
		return Balancing.services[local] if local < Balancing.services.size() else {}
	var rows: Array = Balancing.service_rows.get(s["id"], [])
	return rows[row] if row < rows.size() else {}


static func service_name(service: int) -> String:
	var def := service_def(service)
	if def.has("name"):
		return String(def["name"])
	var s := section_of_service(service)
	if s.is_empty():
		return "?"
	return "%s, Reihe %d" % [s["name"], row_of_service(service) + 1]


static func service_unlocks(service: int) -> String:
	return String(service_def(service).get("unlocks", ""))


## Wo der Dienst im Serverraum zu finden ist, z. B. "Port 5" oder "Wohnviertel, Reihe 3"
static func service_place(service: int) -> String:
	var s := section_of_service(service)
	if s.is_empty():
		return "?"
	var row := row_of_service(service)
	if row < 0:
		return "Port %d" % (service_ports(service)[0] + 1)
	return "%s, Reihe %d" % [s["name"], row + 1]


## Etikett eines wichtigen Kabels bzw. Knäuels
static func port_label(port: int) -> String:
	var service := service_of(port)
	if service < 0:
		return "?"
	var def := service_def(service)
	var place := service_place(service)
	return "%s · %s" % [place, def["name"]] if def.has("name") else place


static func service_active(state: GameState, service: int) -> bool:
	var ports := service_ports(service)
	if ports.is_empty():
		return false
	for p in ports:
		if not state.has_port(p):
			return false
	return true


static func active_services(state: GameState) -> int:
	# Zählt über die belegten Ports (schneller als alle Dienste zu prüfen)
	var seen := {}
	var n := 0
	for p in state.active_ports:
		var service := service_of(p)
		if service >= 0 and not seen.has(service):
			seen[service] = true
			if service_active(state, service):
				n += 1
	return n


## Summe aller Boni der laufenden Dienste: Schlüssel -> Faktor (bzw. Summe bei ADDITIVE)
static func bonuses(state: GameState) -> Dictionary:
	var out := {}
	var seen := {}
	for p in state.active_ports:
		var service := service_of(p)
		if service < 0 or seen.has(service):
			continue
		seen[service] = true
		var bonus: Dictionary = service_def(service).get("bonus", {})
		if bonus.is_empty() or not service_active(state, service):
			continue
		for key: String in bonus:
			if ADDITIVE.has(key):
				out[key] = float(out.get(key, 0.0)) + float(bonus[key])
			else:
				out[key] = float(out.get(key, 1.0)) * float(bonus[key])
	return out


## Hat ein laufender Dienst diese Besonderheit (Feld "special" in services.json)?
static func has_special(state: GameState, special: String) -> bool:
	for service in total_services():
		var def := service_def(service)
		if def.is_empty():
			continue
		if String(def.get("special", "")) == special and service_active(state, service):
			return true
	return false


static func _build() -> void:
	var w: Dictionary = Balancing.world
	var plan: Dictionary = w.get("important_plan", {})
	var row := int(plan.get("row_size", 10))
	var first_port := 0
	var first_service := 0
	var order: Array = plan.get("order", [])
	for i in order.size():
		var id := String(order[i])
		var count := int(plan.get(id, 0))
		var name := id
		for d: Dictionary in w.get("districts", []):
			if d["id"] == id:
				count = int(d.get("important_cables", 0))
				name = String(d["name"])
		for l: Dictionary in w.get("landmarks", []):
			if l["id"] == id:
				name = String(l["name"])
		var tut := mini(int(plan.get("tutorial_ports", 0)), count) if i == 0 else 0
		var rows := floori(float(count - tut) / row)
		_sections.append({ "id": id, "name": name, "first_port": first_port, "count": tut + rows * row,
			"tutorial": tut, "rows": rows, "first_service": first_service })
		first_port += tut + rows * row
		first_service += tut + rows
