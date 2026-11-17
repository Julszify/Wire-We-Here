extends Node
## Autoload "Settings": Einstellungen des Spielers (nicht des Spielstands), gespeichert in user://settings.cfg.
## Maus, Vollbild, Grafikstufe, Lautstärke, Name und letzte Adresse für den Mehrspieler.

signal changed

const PATH := "user://settings.cfg"
const QUALITY_NAMES := ["Niedrig", "Mittel", "Hoch"]

## Faktor auf balancing.json → player.mouse_sensitivity
var mouse_factor := 1.0
var invert_y := false
var fullscreen := false
## 0 niedrig, 1 mittel, 2 hoch
var quality := 2
## 0..1 (Ton kommt später; der Master-Bus wird schon gesetzt)
var volume := 0.8
var player_name := ""
var last_address := "127.0.0.1"
var port := 24680
## Aussehen der eigenen Figur, wenn man bei anderen mitspielt (Platz -> Kosmetik-ID)
var looks: Dictionary = {}


func _ready() -> void:
	load_settings()
	apply()


func load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(PATH) != OK:
		player_name = _default_name()
		return
	mouse_factor = float(cfg.get_value("steuerung", "maus", mouse_factor))
	invert_y = bool(cfg.get_value("steuerung", "maus_umkehren", invert_y))
	fullscreen = bool(cfg.get_value("grafik", "vollbild", fullscreen))
	quality = clampi(int(cfg.get_value("grafik", "stufe", quality)), 0, 2)
	volume = float(cfg.get_value("ton", "lautstaerke", volume))
	player_name = String(cfg.get_value("mehrspieler", "name", _default_name()))
	last_address = String(cfg.get_value("mehrspieler", "adresse", last_address))
	port = int(cfg.get_value("mehrspieler", "port", port))
	looks = cfg.get_value("mehrspieler", "aussehen", {})


func save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("steuerung", "maus", mouse_factor)
	cfg.set_value("steuerung", "maus_umkehren", invert_y)
	cfg.set_value("grafik", "vollbild", fullscreen)
	cfg.set_value("grafik", "stufe", quality)
	cfg.set_value("ton", "lautstaerke", volume)
	cfg.set_value("mehrspieler", "name", player_name)
	cfg.set_value("mehrspieler", "adresse", last_address)
	cfg.set_value("mehrspieler", "port", port)
	cfg.set_value("mehrspieler", "aussehen", looks)
	cfg.save(PATH)


## Fenster, Lautstärke und Bildschärfe übernehmen; Schatten und Sichtweite lesen die Szenen selbst (shadow_*)
func apply() -> void:
	if DisplayServer.get_name() != "headless":
		var mode := DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen else DisplayServer.WINDOW_MODE_WINDOWED
		if DisplayServer.window_get_mode() != mode and not (mode == DisplayServer.WINDOW_MODE_WINDOWED
				and DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_MAXIMIZED):
			DisplayServer.window_set_mode(mode)
	var bus := AudioServer.get_bus_index("Master")
	AudioServer.set_bus_volume_db(bus, linear_to_db(maxf(volume, 0.0001)))
	AudioServer.set_bus_mute(bus, volume <= 0.001)
	var vp := get_viewport()
	if vp:
		vp.scaling_3d_scale = 0.75 if quality == 0 else 1.0
	changed.emit()


## Schattenweite der Sonne je Grafikstufe (0 = keine Schatten)
func shadow_distance() -> float:
	return [0.0, 90.0, 160.0][quality]


## Faktor auf Sichtweiten (Bäume im Umland, Detailstufen)
func view_factor() -> float:
	return [0.6, 0.8, 1.0][quality]


## Kein Systemname: der Name geht im Mehrspieler an andere Rechner
static func _default_name() -> String:
	return "Admin"
