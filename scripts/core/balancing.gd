extends Node
## Autoload "Balancing": lädt alle Spielwerte aus data/balancing.json.
## Kein Spielcode soll Zahlenwerte fest einbauen, sondern hier nachschlagen.

const DATA_PATH := "res://data/balancing.json"
const SERVICES_PATH := "res://data/services.json"
const ZONE_PATH := "res://data/zone.json"

var cable: Dictionary = {}
var heap: Dictionary = {}
var economy: Dictionary = {}
var upgrades: Dictionary = {}
var hand_wrap: Dictionary = {}
var hand_crank: Dictionary = {}
var motor_reel: Dictionary = {}
var reel: Dictionary = {}
var player: Dictionary = {}
var arm: Dictionary = {}
var knot: Dictionary = {}
var placement: Dictionary = {}
var rack: Dictionary = {}
var cord: Dictionary = {}
var save: Dictionary = {}
var tablet_order: Array = []
## Ein Dienst pro Port: { "name", optional "unlocks" }
var services: Array = []
## Anordnung der Zone (Haufen, Streukabel, Schrank, Start)
var zone: Dictionary = {}


func _init() -> void:
	reload()


## Liest die JSON-Datei neu ein (praktisch beim Balancing-Testen).
func reload() -> void:
	var file := FileAccess.open(DATA_PATH, FileAccess.READ)
	if file == null:
		push_error("Balancing: %s konnte nicht geöffnet werden" % DATA_PATH)
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("Balancing: %s ist kein gültiges JSON-Objekt" % DATA_PATH)
		return
	cable = parsed.get("cable", {})
	heap = parsed.get("heap", {})
	economy = parsed.get("economy", {})
	upgrades = parsed.get("upgrades", {})
	hand_wrap = parsed.get("hand_wrap", {})
	hand_crank = parsed.get("hand_crank", {})
	motor_reel = parsed.get("motor_reel", {})
	reel = parsed.get("reel", {})
	player = parsed.get("player", {})
	arm = parsed.get("arm", {})
	knot = parsed.get("knot", {})
	placement = parsed.get("placement", {})
	rack = parsed.get("rack", {})
	cord = parsed.get("cord", {})
	save = parsed.get("save", {})
	tablet_order = parsed.get("tablet_order", [])
	services = _load_json(SERVICES_PATH).get("services", [])
	zone = _load_json(ZONE_PATH)


func _load_json(path: String) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_error("Balancing: %s konnte nicht geöffnet werden" % path)
		return {}
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	return parsed if typeof(parsed) == TYPE_DICTIONARY else {}
