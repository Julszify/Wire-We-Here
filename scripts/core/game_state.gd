class_name GameState
extends RefCounted
## Spielerübergreifender Zustand: Geld und gekaufte Upgrades.
## Reine Daten – wird in M8 gespeichert und später im Koop vom Host verwaltet.

var money: float = 0.0
var total_earned: float = 0.0
## Upgrade-ID -> Stufe bzw. Anzahl
var upgrades: Dictionary = {}


func level(upgrade_id: String) -> int:
	return int(upgrades.get(upgrade_id, 0))
