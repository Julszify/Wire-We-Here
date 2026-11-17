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
var _port_set: Dictionary = {}
## C.O.R.D.-Abschaltknopf: Sekunden, bis er wieder gedrückt werden kann
var snooze_cooldown: float = 0.0
## Finale geschafft: C.O.R.D.s Kern auf dem Turm abgeschaltet (C.O.R.D. bestellt nichts mehr)
var finale_done := false
## Neuer Auftrag (Prestige): wie oft schon neu begonnen und gesammelte Ruf-Punkte. Bleiben beim neuen Auftrag.
var prestige_count := 0
var reputation := 0
## Kosmetik: gekaufte Stücke und was je Platz angelegt ist (Platz -> Stück-ID). Bleiben beim neuen Auftrag.
var cosmetics: Array[String] = []
var looks: Dictionary = {}


func level(upgrade_id: String) -> int:
	return int(upgrades.get(upgrade_id, 0))


func has_port(port: int) -> bool:
	return _port_set.has(port)


func add_port(port: int) -> void:
	if not _port_set.has(port):
		_port_set[port] = true
		active_ports.append(port)


func to_dict() -> Dictionary:
	return { "money": money, "total_earned": total_earned, "upgrades": upgrades.duplicate(), "active_ports": Array(active_ports),
		"snooze_cooldown": snooze_cooldown, "finale_done": finale_done, "meta": meta_dict() }


## Was einen neuen Auftrag überdauert: Ruf, Zahl der Aufträge, Kosmetik
func meta_dict() -> Dictionary:
	return { "prestige_count": prestige_count, "reputation": reputation, "cosmetics": Array(cosmetics),
		"looks": looks.duplicate() }


func load_meta(d: Dictionary) -> void:
	prestige_count = int(d.get("prestige_count", 0))
	reputation = int(d.get("reputation", 0))
	cosmetics.clear()
	for c in d.get("cosmetics", []):
		cosmetics.append(String(c))
	looks = {}
	var l: Dictionary = d.get("looks", {})
	for k in l:
		looks[String(k)] = String(l[k])


func load_dict(d: Dictionary) -> void:
	money = float(d.get("money", 0.0))
	total_earned = float(d.get("total_earned", 0.0))
	upgrades = {}
	var ups: Dictionary = d.get("upgrades", {})
	for k in ups:
		upgrades[String(k)] = int(ups[k])
	active_ports.clear()
	_port_set.clear()
	for p in d.get("active_ports", []):
		add_port(int(p))
	snooze_cooldown = float(d.get("snooze_cooldown", 0.0))
	finale_done = bool(d.get("finale_done", false))
	load_meta(d.get("meta", {}))
