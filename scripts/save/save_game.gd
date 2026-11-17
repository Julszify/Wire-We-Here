class_name SaveGame
extends RefCounted
## Spielstand als JSON-Datei lesen und schreiben.
## Gespeichert werden nur Seeds und veränderlicher Zustand; Kabelformen entstehen beim Laden neu.

## Beim nächsten Start der Welt diesen Spielstand laden (z. B. nach F9). Leer = normal starten.
static var pending_load := false
## Beim nächsten Start ohne Spielstand neu beginnen (nach "Neues Spiel").
static var force_new := false
## Neuer Auftrag (Prestige): was in den neuen Spielstand übernommen wird (Ruf, Kosmetik). Leer = nichts.
static var carry_meta: Dictionary = {}


static func path() -> String:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--savefile="):
			return arg.trim_prefix("--savefile=")
	return String(Balancing.save.get("path", "user://savegame.json"))


static func exists() -> bool:
	return FileAccess.file_exists(path())


static func write(data: Dictionary) -> bool:
	data["version"] = int(Balancing.save.get("version", 1))
	data["saved_at"] = Time.get_datetime_string_from_system()
	var f := FileAccess.open(path(), FileAccess.WRITE)
	if f == null:
		push_error("Spielstand konnte nicht geschrieben werden: %s" % path())
		return false
	f.store_string(JSON.stringify(data, "\t"))
	return true


## Liest den Spielstand oder gibt {} zurück (fehlt, kaputt oder falsche Version).
static func read() -> Dictionary:
	if not exists():
		return {}
	var f := FileAccess.open(path(), FileAccess.READ)
	if f == null:
		return {}
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		push_warning("Spielstand ist kein gültiges JSON und wird ignoriert.")
		return {}
	if int(parsed.get("version", 0)) != int(Balancing.save.get("version", 1)):
		push_warning("Spielstand hat eine andere Version und wird ignoriert.")
		return {}
	return parsed


static func delete() -> void:
	if exists():
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path()))


static func vec_to(v: Vector3) -> Array:
	return [snappedf(v.x, 0.0001), snappedf(v.y, 0.0001), snappedf(v.z, 0.0001)]


static func vec_from(a: Array) -> Vector3:
	return Vector3(float(a[0]), float(a[1]), float(a[2]))
