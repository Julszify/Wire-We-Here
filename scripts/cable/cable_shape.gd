class_name CableShape
extends RefCounted
## Setzt die sichtbare Form eines eingehängten Kabels aus drei Teilen zusammen:
##   1. Rest im Haufen: Bahn von Index (1 - p) * N bis 0 (hinteres Ende wandert nach vorne)
##   2. Verbindungsstück vom eingehängten Ende zum Aufwickler
##   3. Wicklung (Spirale auf der Rolle oder Schlaufen um den Arm) mit Länge p * Bahnlänge
## Reine Funktionen von (Kabel-Daten, Aufwickler-Lage) – kein eigener Zustand.


## Kabel auf einer Rolle. Ergebnis: { "points", "phase" } – phase = Drehwinkel der Trommel.
## `scale` < 1 = kleinere Trommel (Wagen).
static func build_on_reel(cable: CableData, reel_pos: Vector3, scale: float = 1.0) -> Dictionary:
	var anchor := cable.path.points[0]
	var feed_angle := atan2(anchor.z - reel_pos.z, anchor.x - reel_pos.x)
	var coil := coil_points(reel_pos, cable.progress() * coil_length(cable), feed_angle, scale)
	var coil_pts: PackedVector3Array = coil["points"]
	var coil_end := coil_pts[coil_pts.size() - 1]
	# Verbindungsstück leicht nach oben gebogen
	var mid_y := maxf(anchor.y, coil_end.y) + float(Balancing.reel["connector_lift_m"])
	return { "points": _assemble(cable, coil_pts, mid_y), "phase": coil["phase"] }


## Kabel um den Arm gewickelt. `arm` ist die globale Lage des Unterarms
## (Ursprung am Ellbogen, Hand Richtung -Z, außen Richtung -X).
static func build_on_arm(cable: CableData, arm: Transform3D) -> PackedVector3Array:
	var coil_pts := arm_coil_points(arm, cable.progress() * coil_length(cable))
	var anchor := cable.path.points[0]
	var coil_end := coil_pts[coil_pts.size() - 1]
	# Verbindungsstück hängt durch, aber nicht durch den Boden
	var mid_y := maxf((anchor.y + coil_end.y) * 0.5 - float(Balancing.arm["connector_sag_m"]),
		float(Balancing.cable["radius_m"]))
	return _assemble(cable, coil_pts, mid_y)


## Fertiges Knäuel als ordentlicher Kabelring: Windungen im Kreis um die Y-Achse, leicht versetzt,
## damit sie nebeneinander liegen. `length` bestimmt die Zahl der Windungen.
static func ring_coil_points(length: float) -> PackedVector3Array:
	var r := 0.17
	var turns := clampf(length / (TAU * r) * 0.45, 4.0, 9.0)
	var steps := int(turns * 20.0)
	var pts := PackedVector3Array()
	for i in steps + 1:
		var t := float(i) / steps
		var a := t * turns * TAU
		# Windungen wandern in einem kleinen Kreis um den Ringquerschnitt
		var k := t * turns * 2.4
		var rr := r + cos(k) * 0.035
		pts.append(Vector3(cos(a) * rr, sin(k) * 0.035, sin(a) * rr))
	return pts


## Sichtbare Länge der Wicklung bei voll aufgerolltem Kabel (begrenzt, damit
## lange Bahnen im großen Berg keine riesigen Knäuel ergeben).
static func coil_length(cable: CableData) -> float:
	return minf(cable.path.length, float(Balancing.cable.get("coil_visual_max_m", 18.0)))


## Haufenrest + Verbindungsstück (quadratische Bézierkurve) + Wicklung von außen nach innen.
static func _assemble(cable: CableData, coil_pts: PackedVector3Array, mid_y: float) -> PackedVector3Array:
	var heap_pts := cable.path.points
	var n := heap_pts.size() - 1
	var k := maxi(1, roundi((1.0 - cable.progress()) * n))

	var pts := PackedVector3Array()
	for i in range(k, -1, -1):
		pts.append(heap_pts[i])

	var anchor := heap_pts[0]
	var coil_end := coil_pts[coil_pts.size() - 1]
	var mid := (anchor + coil_end) * 0.5
	mid.y = mid_y
	var samples := int(Balancing.reel["connector_samples"])
	for i in range(1, samples):
		var t := float(i) / samples
		pts.append(anchor.lerp(mid, t).lerp(mid.lerp(coil_end, t), t))

	for i in range(coil_pts.size() - 1, -1, -1):
		pts.append(coil_pts[i])
	return pts


## Helix um die Trommel. Das äußere Ende liegt immer bei `end_angle` (Richtung Haufen),
## dadurch dreht sich die ganze Spirale beim Aufwickeln mit der Trommel.
## Ergebnis: { "points": innen -> außen, "phase": Winkel des inneren Anfangs }
static func coil_points(center: Vector3, length: float, end_angle: float, scale: float = 1.0) -> Dictionary:
	var r: Dictionary = Balancing.reel
	var step_len: float = r["coil_point_step_m"]
	var pitch: float = float(r["coil_pitch_m"]) * scale
	var min_h: float = float(r["coil_min_height_m"]) * scale
	var max_h: float = float(r["coil_max_height_m"]) * scale
	var layer_step: float = float(r["coil_layer_step_m"]) * scale

	var radius: float = float(r["coil_start_radius_m"]) * scale
	var angle := 0.0
	var h := min_h
	var dir := 1.0
	var s := 0.0
	var raw: Array[Vector3] = [Vector3(radius, angle, h)]  # (Radius, Winkel, Höhe)
	while s < length:
		var step := minf(step_len, length - s)
		s += step
		angle += step / radius
		h += dir * pitch * step / (TAU * radius)
		# Am oberen bzw. unteren Rand: Richtung wechseln, nächste Lage etwas weiter außen
		if h > max_h:
			h = max_h
			dir = -1.0
			radius += layer_step
		elif h < min_h:
			h = min_h
			dir = 1.0
			radius += layer_step
		raw.append(Vector3(radius, angle, h))

	var offset := end_angle - angle
	var out := PackedVector3Array()
	out.resize(raw.size())
	for i in raw.size():
		var v := raw[i]
		var a := v.y + offset
		out[i] = center + Vector3(v.x * cos(a), v.z, v.x * sin(a))
	return { "points": out, "phase": offset }


## Ovale Schlaufen zwischen Hand und Ellbogen. Jede Schlaufe wird etwas größer und
## liegt etwas weiter außen, so entsteht ein dicker werdendes Knäuel.
## Ergebnis: innen -> außen, in globalen Koordinaten.
static func arm_coil_points(arm: Transform3D, length: float) -> PackedVector3Array:
	var a: Dictionary = Balancing.arm
	var center_z := -float(a["forearm_length_m"]) * 0.5
	var half_len: float = a["loop_half_length_m"]
	var half_h: float = a["loop_half_height_m"]
	var growth: float = a["loop_growth_m"]
	var lateral: float = a["loop_lateral_step_m"]
	var step_len: float = a["point_step_m"]

	var out := PackedVector3Array()
	var theta := 0.0
	var s := 0.0
	out.append(arm * Vector3(0.0, 0.0, center_z + half_len))
	while s < length:
		var loops := theta / TAU
		var hl := half_len + growth * loops
		var hh := half_h + growth * loops
		# Winkelschritt so wählen, dass die Bogenlänge ungefähr step_len ist
		var speed := sqrt(pow(hl * sin(theta), 2.0) + pow(hh * cos(theta), 2.0))
		var step := minf(step_len, length - s)
		theta += step / maxf(speed, 0.02)
		s += step
		loops = theta / TAU
		hl = half_len + growth * loops
		hh = half_h + growth * loops
		var local := Vector3(-lateral * loops, hh * sin(theta), center_z + hl * cos(theta))
		out.append(arm * local)
	return out
