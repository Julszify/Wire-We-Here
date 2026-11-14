extends Node
## Autoload "Balancing": lädt alle Spielwerte aus data/balancing.json.
## Kein Spielcode soll Zahlenwerte fest einbauen, sondern hier nachschlagen.

const DATA_PATH := "res://data/balancing.json"

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
