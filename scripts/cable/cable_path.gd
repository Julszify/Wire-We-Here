class_name CablePath
extends RefCounted
## Feste Bahn eines Kabels im Haufen: Punkte gleichmäßig nach Bogenlänge abgetastet.
## Index 0 ist das Ende, das später an der Rolle eingehängt wird.
## Die Bahn wird nie gespeichert, sondern aus dem Seed neu erzeugt.

## points[0..N], Abstand zwischen Nachbarn ist überall gleich
var points: PackedVector3Array = PackedVector3Array()
## Sichtbare Länge der Bahn in Metern
var length: float = 0.0


## Erzeugt eine zufällige Haufen-Bahn um `center`. Verbraucht Zufallszahlen aus `rng`.
## `radius` und `peak` (zusätzliche Höhe in der Mitte) bestimmen die Größe des Haufens.
static func generate_heap_path(rng: RandomNumberGenerator, center: Vector3, radius: float = -1.0, peak: float = -1.0) -> CablePath:
	var h: Dictionary = Balancing.heap
	var c: Dictionary = Balancing.cable
	if radius <= 0.0:
		radius = h["radius_m"]
	if peak <= 0.0:
		peak = h["peak_extra_height_m"]
	var inner: float = radius * float(h["inner_fraction"])

	# Startpunkt am Rand des Haufens, damit das Ende gut erreichbar ist
	var a0 := rng.randf() * TAU
	var ctrl := PackedVector3Array()
	ctrl.append(center + Vector3(radius * cos(a0), h["end_height_m"], radius * sin(a0)))
	ctrl.append(center + Vector3(inner * cos(a0 + 0.15), 0.35, inner * sin(a0 + 0.15)))

	# Weitere Stützpunkte im Haufen; in der Mitte höher als am Rand (Hügelform)
	var count := rng.randi_range(int(c["control_points_min"]), int(c["control_points_max"]))
	for i in count:
		var r := sqrt(rng.randf()) * inner
		var t := rng.randf() * TAU
		var height_max: float = h["base_height_m"] + peak * (1.0 - pow(r / radius, 2.0))
		var y: float = h["min_height_m"] + rng.randf() * height_max
		ctrl.append(center + Vector3(r * cos(t), y, r * sin(t)))

	var dense := catmull_rom_centripetal(ctrl, 24)
	var path := CablePath.new()
	path.points = resample_even(dense, int(c["path_samples"]))
	path.length = polyline_length(path.points)
	return path


## Einzelnes Kabel, das quer über den Boden läuft (Zufallsweg mit leichten Kurven).
## Index 0 ist ein Ende auf dem Boden, an dem man es greifen kann.
static func generate_scatter_path(rng: RandomNumberGenerator, center: Vector3, area_radius: float) -> CablePath:
	var sc: Dictionary = Balancing.zone.get("scatter", {})
	var ctrl := PackedVector3Array()
	var r := sqrt(rng.randf()) * area_radius
	var a := rng.randf() * TAU
	var pos := center + Vector3(r * cos(a), 0.0, r * sin(a))
	var heading := rng.randf() * TAU
	var count := rng.randi_range(int(sc.get("points_min", 5)), int(sc.get("points_max", 8)))
	var turn := deg_to_rad(float(sc.get("turn_max_deg", 70.0)))
	for i in count:
		pos.y = rng.randf_range(float(sc.get("height_min_m", 0.06)), float(sc.get("height_max_m", 0.16)))
		ctrl.append(pos)
		heading += rng.randf_range(-turn, turn)
		var step := rng.randf_range(float(sc.get("step_min_m", 1.8)), float(sc.get("step_max_m", 3.2)))
		pos += Vector3(cos(heading), 0.0, sin(heading)) * step
	var dense := catmull_rom_centripetal(ctrl, 16)
	var path := CablePath.new()
	path.points = resample_even(dense, int(Balancing.cable["path_samples"]))
	path.length = polyline_length(path.points)
	return path


## Zentripetale Catmull-Rom-Kurve durch alle Punkte; `steps` Abtastungen pro Segment.
static func catmull_rom_centripetal(ctrl: PackedVector3Array, steps: int) -> PackedVector3Array:
	var out := PackedVector3Array()
	var n := ctrl.size()
	if n < 2:
		return ctrl
	for seg in n - 1:
		# Randpunkte spiegeln, damit die Kurve durch den ersten und letzten Punkt läuft
		var p0 := ctrl[seg - 1] if seg > 0 else ctrl[0] * 2.0 - ctrl[1]
		var p1 := ctrl[seg]
		var p2 := ctrl[seg + 1]
		var p3 := ctrl[seg + 2] if seg + 2 < n else ctrl[n - 1] * 2.0 - ctrl[n - 2]
		var t0 := 0.0
		var t1 := t0 + _knot_step(p0, p1)
		var t2 := t1 + _knot_step(p1, p2)
		var t3 := t2 + _knot_step(p2, p3)
		var last := steps if seg == n - 2 else steps - 1
		for i in last + 1:
			var t := lerpf(t1, t2, float(i) / steps)
			var a1 := _mix(p0, p1, t0, t1, t)
			var a2 := _mix(p1, p2, t1, t2, t)
			var a3 := _mix(p2, p3, t2, t3, t)
			var b1 := _mix(a1, a2, t0, t2, t)
			var b2 := _mix(a2, a3, t1, t3, t)
			out.append(_mix(b1, b2, t1, t2, t))
	return out


## Tastet eine Polylinie in `segments` gleich lange Stücke ab (segments + 1 Punkte).
static func resample_even(src: PackedVector3Array, segments: int) -> PackedVector3Array:
	var cum := PackedFloat32Array()
	cum.resize(src.size())
	cum[0] = 0.0
	for i in range(1, src.size()):
		cum[i] = cum[i - 1] + src[i].distance_to(src[i - 1])
	var total := cum[src.size() - 1]
	var out := PackedVector3Array()
	out.resize(segments + 1)
	var j := 0
	for i in segments + 1:
		var target := total * float(i) / segments
		while j < src.size() - 2 and cum[j + 1] < target:
			j += 1
		var span := cum[j + 1] - cum[j]
		var f := 0.0 if span <= 0.0 else clampf((target - cum[j]) / span, 0.0, 1.0)
		out[i] = src[j].lerp(src[j + 1], f)
	return out


static func polyline_length(pts: PackedVector3Array) -> float:
	var total := 0.0
	for i in range(1, pts.size()):
		total += pts[i].distance_to(pts[i - 1])
	return total


static func _knot_step(a: Vector3, b: Vector3) -> float:
	# Alpha 0,5 = zentripetal: vermeidet Schlaufen und Spitzen
	return maxf(pow(a.distance_to(b), 0.5), 1e-4)


static func _mix(a: Vector3, b: Vector3, ta: float, tb: float, t: float) -> Vector3:
	return a * ((tb - t) / (tb - ta)) + b * ((t - ta) / (tb - ta))
