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
## `length_m` = Länge der Bahn in Metern (= Spiel-Länge des Kabels): kurze Kabel sind Stummel am Rand,
## lange schlängeln sich mit vielen Stützpunkten durch den Haufen. <= 0: alte feste Form.
## Der Rand ist pro Haufen unregelmäßig (Wellen aus der Lage abgeleitet), manche Enden laufen als
## Ausläufer über den Boden, und die Kabel liegen eher nahe der Hügeloberfläche als quer im Inneren.
static func generate_heap_path(rng: RandomNumberGenerator, center: Vector3, radius: float = -1.0, peak: float = -1.0,
		length_m: float = -1.0) -> CablePath:
	var h: Dictionary = Balancing.heap
	var c: Dictionary = Balancing.cable
	if radius <= 0.0:
		radius = h["radius_m"]
	if peak <= 0.0:
		peak = h["peak_extra_height_m"]
	var inner_frac: float = h["inner_fraction"]
	var phases := _rim_phases(center)
	var end_y: float = h["end_height_m"]

	# Startpunkt am (welligen) Rand; manchmal als Ausläufer weiter draußen auf dem Boden
	var a0 := rng.randf() * TAU
	var rim := radius * _rim_factor(a0, phases)
	var start_r := rim * rng.randf_range(0.88, 1.08)
	var is_tail := rng.randf() < float(h.get("tail_chance", 0.0))
	if is_tail:
		start_r = rim * rng.randf_range(1.15, float(h.get("tail_reach", 1.5)))
	var ctrl := PackedVector3Array()
	ctrl.append(center + Vector3(start_r * cos(a0), end_y, start_r * sin(a0)))
	if is_tail:
		# Ausläufer schlängelt sich seitlich zum Haufen zurück statt gerade nach innen
		var bend := rng.randf_range(0.25, 0.6) * (1.0 if rng.randf() < 0.5 else -1.0)
		var mid_r := (start_r + rim) * 0.5
		var am := a0 + bend * 0.6 + rng.randf_range(-0.1, 0.1)
		ctrl.append(center + Vector3(mid_r * cos(am), end_y, mid_r * sin(am)))
		var a1 := a0 + bend
		ctrl.append(center + Vector3(rim * 1.02 * cos(a1), end_y, rim * 1.02 * sin(a1)))
	var surface_min: float = h.get("surface_min_fraction", 0.0)
	var count := rng.randi_range(int(c["control_points_min"]), int(c["control_points_max"]))
	var local_r := float(h.get("local_radius_m", 4.5))
	if radius > float(h.get("local_from_radius_m", 9.0)):
		# Großer Berg: jedes Kabel windet sich in einem kleineren Bereich, der vom Rand aus unterschiedlich
		# tief im Berg liegt (statt in langen Bahnen quer über den ganzen Berg). Wirkt dichter und wirrer.
		var depth := sqrt(rng.randf())
		var ta := a0 + rng.randf_range(-0.25, 0.25)
		var tr := rim * (1.0 - depth * 0.92) - local_r * 0.4
		var target := Vector2(maxf(tr, 0.0) * cos(ta), maxf(tr, 0.0) * sin(ta))
		# Zwischenpunkte auf dem Weg vom Rand zum Bereich (sonst ein langes gerades Stück)
		var first := Vector2(ctrl[ctrl.size() - 1].x - center.x, ctrl[ctrl.size() - 1].z - center.z)
		var steps := int(first.distance_to(target) / (local_r * 1.2))
		for k in steps:
			var m := first.lerp(target, float(k + 1) / (steps + 1)) + Vector2.from_angle(rng.randf() * TAU) * local_r * 0.4
			var mr := m.length()
			var mrim := radius * _rim_factor(atan2(m.y, m.x), phases)
			var ms := float(h["base_height_m"]) + peak * pow(maxf(0.0, 1.0 - pow(minf(mr / mrim, 1.0), 2.0)), 0.8)
			ctrl.append(center + Vector3(m.x, h["min_height_m"] + ms * rng.randf_range(maxf(surface_min, 0.7), 1.0), m.y))
		var i_big := 0
		var acc_big := _ctrl_length(ctrl)
		while i_big < count or (length_m > 0.0 and acc_big < length_m * 1.25 and i_big < 400):
			i_big += 1
			var off := Vector2.from_angle(rng.randf() * TAU) * sqrt(rng.randf()) * local_r
			var q := target + off
			var qr := q.length()
			var local_rim := radius * _rim_factor(atan2(q.y, q.x), phases)
			if qr > local_rim * inner_frac:
				q *= local_rim * inner_frac / qr
				qr = local_rim * inner_frac
			var surface := float(h["base_height_m"]) + peak * pow(maxf(0.0, 1.0 - pow(qr / local_rim, 2.0)), 0.8)
			var y: float = h["min_height_m"] + surface * rng.randf_range(surface_min, 1.0)
			ctrl.append(center + Vector3(q.x, y, q.y))
			acc_big += ctrl[ctrl.size() - 1].distance_to(ctrl[ctrl.size() - 2]) * 1.1
		return _finish(catmull_rom_centripetal(ctrl, 24), length_m)

	var r1 := rim * inner_frac
	ctrl.append(center + Vector3(r1 * cos(a0 + 0.15), 0.35, r1 * sin(a0 + 0.15)))

	# Weitere Stützpunkte im Haufen, meist knapp unter der Hügeloberfläche
	var i_pt := 0
	var acc := _ctrl_length(ctrl)
	while i_pt < count or (length_m > 0.0 and acc < length_m * 1.25 and i_pt < 400):
		i_pt += 1
		var t := rng.randf() * TAU
		var local_rim := radius * _rim_factor(t, phases)
		var r := sqrt(rng.randf()) * local_rim * inner_frac
		var surface := float(h["base_height_m"]) + peak * pow(maxf(0.0, 1.0 - pow(r / local_rim, 2.0)), 0.8)
		var y: float = h["min_height_m"] + surface * rng.randf_range(surface_min, 1.0)
		ctrl.append(center + Vector3(r * cos(t), y, r * sin(t)))
		acc += ctrl[ctrl.size() - 1].distance_to(ctrl[ctrl.size() - 2]) * 1.1

	return _finish(catmull_rom_centripetal(ctrl, 24), length_m)


## Bahn fertig machen: auf `target` Meter kürzen (falls > 0) und gleichmäßig abtasten. Punktabstand aus
## balancing.json → cable.path_spacing_m (kurze Kabel wenige Punkte, lange viele).
static func _finish(dense: PackedVector3Array, target: float) -> CablePath:
	var c: Dictionary = Balancing.cable
	if target > 0.0:
		dense = cut_to_length(dense, target)
	var len := polyline_length(dense)
	var segs := int(c["path_samples"])
	if target > 0.0:
		segs = clampi(ceili(len / float(c.get("path_spacing_m", 0.25))), int(c.get("path_samples_min", 6)),
			int(c.get("path_samples_max", 500)))
	var path := CablePath.new()
	path.points = resample_even(dense, segs)
	path.length = polyline_length(path.points)
	return path


## Polylinie nach `length` Metern abschneiden (ist sie kürzer, bleibt sie, wie sie ist).
static func cut_to_length(pts: PackedVector3Array, length: float) -> PackedVector3Array:
	var out := PackedVector3Array()
	if pts.size() < 2:
		return pts
	out.append(pts[0])
	var acc := 0.0
	for i in range(1, pts.size()):
		var d := pts[i].distance_to(pts[i - 1])
		if acc + d >= length:
			out.append(pts[i - 1].lerp(pts[i], (length - acc) / maxf(d, 1e-6)))
			return out
		acc += d
		out.append(pts[i])
	return out  # kürzer als gewünscht (selten): lieber etwas kürzer als ein gerader Stab


## Grobe Länge der Stützpunkte (Kurve wird etwas länger)
static func _ctrl_length(ctrl: PackedVector3Array) -> float:
	return polyline_length(ctrl) * 1.1


## Radius-Faktor des welligen Haufenrands in Richtung `angle` (1 = Nennradius)
static func _rim_factor(angle: float, phases: Vector3) -> float:
	var w: float = Balancing.heap.get("rim_wobble", 0.0)
	return 1.0 + w * (0.6 * sin(2.0 * angle + phases.x) + 0.3 * sin(3.0 * angle + phases.y)
		+ 0.2 * sin(5.0 * angle + phases.z))


## Wellen-Phasen eines Haufens, aus seiner Lage abgeleitet (gleich für alle seine Kabel)
static func _rim_phases(center: Vector3) -> Vector3:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([snappedf(center.x, 0.01), snappedf(center.z, 0.01), "rim"])
	return Vector3(rng.randf() * TAU, rng.randf() * TAU, rng.randf() * TAU)


## Einzelnes Kabel, das quer über den Boden läuft (Zufallsweg mit leichten Kurven).
## Index 0 ist ein Ende auf dem Boden, an dem man es greifen kann.
static func generate_scatter_path(rng: RandomNumberGenerator, center: Vector3, area_radius: float,
		length_m: float = -1.0) -> CablePath:
	var sc: Dictionary = Balancing.zone.get("scatter", {})
	var ctrl := PackedVector3Array()
	var r := sqrt(rng.randf()) * area_radius
	var a := rng.randf() * TAU
	var pos := center + Vector3(r * cos(a), 0.0, r * sin(a))
	var heading := rng.randf() * TAU
	var count := rng.randi_range(int(sc.get("points_min", 5)), int(sc.get("points_max", 8)))
	var turn := deg_to_rad(float(sc.get("turn_max_deg", 70.0)))
	var i_sc := 0
	var acc_sc := 0.0
	while i_sc < count or (length_m > 0.0 and acc_sc < length_m * 1.1 and i_sc < 400):
		i_sc += 1
		pos.y = rng.randf_range(float(sc.get("height_min_m", 0.06)), float(sc.get("height_max_m", 0.16)))
		ctrl.append(pos)
		heading += rng.randf_range(-turn, turn)
		var step := rng.randf_range(float(sc.get("step_min_m", 1.8)), float(sc.get("step_max_m", 3.2)))
		pos += Vector3(cos(heading), 0.0, sin(heading)) * step
		acc_sc += step
	return _finish(catmull_rom_centripetal(ctrl, 16), length_m)


## Kabel, das eine Straße entlang liegt: vom greifbaren Ende `start` aus in Richtung `dir`, `length` Meter,
## mit leichten Schlenkern zur Seite. Höhe relativ zu start.y (Straßen liegen auf verschiedenen Höhen).
static func generate_street_path(rng: RandomNumberGenerator, start: Vector3, dir: Vector3, length: float) -> CablePath:
	var forward := Vector3(dir.x, 0.0, dir.z).normalized()
	var side := forward.cross(Vector3.UP)
	var count := maxi(3, int(length / 4.0))
	var ctrl := PackedVector3Array()
	var lateral := 0.0
	for i in count + 1:
		var t := float(i) / count
		lateral = clampf(lateral + rng.randf_range(-0.8, 0.8), -1.6, 1.6)
		var p := start + forward * (t * length) + side * lateral
		p.y = start.y + rng.randf_range(0.06, 0.14)
		ctrl.append(p)
	return _finish(catmull_rom_centripetal(ctrl, 12), length)


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
