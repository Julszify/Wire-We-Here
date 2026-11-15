class_name WagonData
extends RefCounted
## Kabeltrommel-Wagen: reiner Zustand. Er folgt dem Spieler oder steht geparkt; auf ihm sitzen
## mehrere Plätze (ReelData mit Kind.WAGON), die wie Motorrollen ziehen. Die Lage der Plätze folgt aus
## Position und Drehung des Wagens.

var position := Vector3.ZERO
## Drehung um die Hochachse; Vorderseite (Deichsel) zeigt nach -Z der Drehung
var yaw := 0.0
## Geparkt: bleibt stehen. Sonst folgt er dem Spieler.
var parked := false
var slots: Array[ReelData] = []


func any_hooked() -> bool:
	for s in slots:
		if not s.is_free():
			return true
	return false


func free_slots() -> int:
	var n := 0
	for s in slots:
		if s.is_free():
			n += 1
	return n


## Lage der Plätze aus Position und Drehung (in Fahrtrichtung hintereinander)
func update_slots() -> void:
	var w: Dictionary = Balancing.wagon
	var spacing := float(w.get("slot_spacing_m", 1.2))
	var bed := float(w.get("bed_height_m", 0.62))
	var basis := Basis(Vector3.UP, yaw)
	for i in slots.size():
		var along := (i - (slots.size() - 1) * 0.5) * spacing
		slots[i].position = position + basis * Vector3(0, bed, along)


func owns(reel: ReelData) -> bool:
	return slots.has(reel)


func to_dict() -> Dictionary:
	var ids := []
	for s in slots:
		ids.append(s.id)
	return { "position": SaveGame.vec_to(position), "yaw": yaw, "parked": parked, "slots": ids }
