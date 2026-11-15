extends Node
## Autoload "Balancing": lädt alle Spielwerte aus data/balancing.json.
## Kein Spielcode soll Zahlenwerte fest einbauen, sondern hier nachschlagen.

const DATA_PATH := "res://data/balancing.json"
const SERVICES_PATH := "res://data/services.json"
const ZONE_PATH := "res://data/zone.json"
const WORLD_PATH := "res://data/world.json"

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
var bag: Dictionary = {}
var wagon: Dictionary = {}
var zipline: Dictionary = {}
var connector: Dictionary = {}
var server_room: Dictionary = {}
## Blöcke ruhender Kabel (CableBatch): Detailstufen und Thread-Aufträge
var cable_batch: Dictionary = {}
var tablet_order: Array = []
## Ein Dienst pro Port: { "name", optional "unlocks" }
var services: Array = []
## Anordnung der Zone (Haufen, Streukabel, Schrank, Start)
var zone: Dictionary = {}
## Dienste der Reihen je Schrank: Viertel-ID -> [ { "name", optional "unlocks"/"bonus"/"effect" } ]
var service_rows: Dictionary = {}
## Rohdaten der Stadt (world.json); der Port-Plan (RackPlan) liest daraus
var world: Dictionary = {}


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
	bag = parsed.get("bag", {})
	wagon = parsed.get("wagon", {})
	zipline = parsed.get("zipline", {})
	connector = parsed.get("connector", {})
	server_room = parsed.get("server_room", {})
	cable_batch = parsed.get("cable_batch", {})
	tablet_order = parsed.get("tablet_order", [])
	var sv := _load_json(SERVICES_PATH)
	services = sv.get("services", [])
	service_rows = sv.get("rows", {})
	zone = _load_json(ZONE_PATH)
	world = _load_json(WORLD_PATH)


func _load_json(path: String) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_error("Balancing: %s konnte nicht geöffnet werden" % path)
		return {}
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	return parsed if typeof(parsed) == TYPE_DICTIONARY else {}
