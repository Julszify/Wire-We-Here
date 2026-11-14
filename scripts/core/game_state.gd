class_name GameState
extends RefCounted
## Spielerübergreifender Zustand: Geld und gekaufte Upgrades.
## Reine Daten – wird in M8 gespeichert und später im Koop vom Host verwaltet.

var money: float = 0.0
var total_earned: float = 0.0
## Upgrade-ID -> Stufe bzw. Anzahl
var upgrades: Dictionary = {}
## Belegte Ports im Server-Schrank (= reaktivierte Dienste)
var active_ports: Array[int] = []


func level(upgrade_id: String) -> int:
	return int(upgrades.get(upgrade_id, 0))


func to_dict() -> Dictionary:
	return { "money": money, "total_earned": total_earned, "upgrades": upgrades.duplicate(), "active_ports": Array(active_ports) }


func load_dict(d: Dictionary) -> void:
	money = float(d.get("money", 0.0))
	total_earned = float(d.get("total_earned", 0.0))
	upgrades = {}
	var ups: Dictionary = d.get("upgrades", {})
	for k in ups:
		upgrades[String(k)] = int(ups[k])
	active_ports.clear()
	for p in d.get("active_ports", []):
		active_ports.append(int(p))
