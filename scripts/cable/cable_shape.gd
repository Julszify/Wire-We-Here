class_name CableShape
extends RefCounted
## Setzt die sichtbare Form eines eingehängten Kabels aus drei Teilen zusammen:
##   1. Rest im Haufen: Bahn von Index (1 - p) * N bis 0 (hinteres Ende wandert nach vorne)
##   2. Verbindungsstück vom eingehängten Ende zum Aufwickler
##   3. Wicklung (Spirale auf der Rolle oder Schlaufen um den Arm) mit Länge p * Bahnlänge
## Reine Funktionen von (Kabel-Daten, Aufwickler-Lage) – kein eigener Zustand.


## Aussehen des Verbindungsstücks, von der Darstellung pro Bild gesetzt:
##   tension 0 = locker (liegt am Boden), 1 = straff (gerade Linie); jitter > 0 = zittert (am Knoten);
##   time = Sekunden für das Zittern; ground_y = Bodenhöhe am Aufwickler.
static func look(tension: float = 0.0, jitter: float = 0.0, time: float = 0.0, ground_y: float = NAN) -> Dictionary:
	return { "tension": tension, "jitter": jitter, "time": time, "ground_y": ground_y }


## Kabel auf einer Rolle. Ergebnis: { "points", "phase" } – phase = Drehwinkel der Trommel.
## `scale` < 1 = kleinere Trommel (Wagen). Das Kabel läuft tangential auf die Trommel.
static func build_on_reel(cable: CableData, reel_pos: Vector3, scale: float = 1.0, lk: Dictionary = {}) -> Dictionary:
	var anchor := cable.path.points[0]
	var feed_angle := atan2(anchor.z - reel_pos.z, anchor.x - reel_pos.x)
	# Tangential: an dieser Stelle zeigt die Wicklung in Richtung Haufen
	# Kleine Trommeln (Sauger, Drohne, Wagen) zeigen nur eine kurze Wicklung: man sieht sie kaum, spart viele Punkte
	var visual := coil_length(cable) * clampf(scale, 0.25, 1.0)
	var coil := coil_points(reel_pos, cable.progress() * visual, feed_angle - PI * 0.5, scale, cable.radius())
	var coil_pts: PackedVector3Array = coil["points"]
	var c: Dictionary = Balancing.connector
	var rise := float(c.get("rise_reel_m", 0.7)) * scale + 0.3
	var ground := float(lk.get("ground_y", NAN))
	if is_nan(ground):
		ground = reel_pos.y
	return { "points": _assemble(cable, coil_pts, lk, ground, rise), "phase": coil["phase"] }


## Kabel um den Arm gewickelt. `arm` ist die globale Lage des Unterarms
## (Ursprung am Ellbogen, Hand Richtung -Z, außen Richtung -X).
static func build_on_arm(cable: CableData, arm: Transform3D, lk: Dictionary = {}) -> PackedVector3Array:
	var visual := minf(coil_length(cable), float(Balancing.arm.get("visual_max_m", 6.5)))
	var coil_pts := arm_coil_points(arm, cable.progress() * visual, cable.radius())
	var c: Dictionary = Balancing.connector
	var ground := float(lk.get("ground_y", NAN))
	if is_nan(ground):
		ground = arm.origin.y - 1.0
	return _assemble(cable, coil_pts, lk, ground, float(c.get("rise_arm_m", 0.9)))


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


## Haufenrest + Verbindungsstück + Wicklung von außen nach innen.
## Das Verbindungsstück liegt locker am Boden (leicht geschlängelt) und hebt sich erst auf den letzten
## `rise` Metern zum Aufwickler; je straffer (tension), desto mehr wird es zur geraden Linie.
static func _assemble(cable: CableData, coil_pts: PackedVector3Array, lk: Dictionary, ground_y: float, rise: float) -> PackedVector3Array:
	var heap_pts := cable.path.points
	var n := heap_pts.size() - 1
	var c: Dictionary = Balancing.connector
	var time := float(lk.get("time", 0.0))
	var anchor := heap_pts[0]

	# 1. Rest im Haufen, stufenlos: das hintere Ende gleitet zwischen den Bahnpunkten nach vorn
	var kf := maxf((1.0 - cable.progress()) * n, 1.0)
	var k := mini(floori(kf), n)
	var frac := kf - k
	var heap := PackedVector3Array()
	if k < n and frac > 0.001:
		heap.append(heap_pts[k].lerp(heap_pts[k + 1], frac))
	for i in range(k, -1, -1):
		heap.append(heap_pts[i])
	# Kurz vor Schluss löst sich das Ende aus dem Haufen: hebt sich, rutscht zum Anker und schlägt nach
	var left_m := (1.0 - cable.progress()) * cable.path.length
	var whip_m := float(c.get("whip_m", 1.6))
	if left_m < whip_m and heap.size() > 1:
		var f := 1.0 - left_m / whip_m
		var last := heap.size() - 1
		for j in last:
			var w := 1.0 - float(j) / last  # 1 am losen Ende, 0 am Anker
			var p := heap[j].lerp(anchor + Vector3.UP * 0.25, f * w * 0.6)
			p.y += f * w * 0.35 + sin(time * 15.0 + w * 5.0) * 0.1 * f * w
			heap[j] = p
	var pts := heap

	# 2. Verbindungsstück
	var tension := clampf(float(lk.get("tension", 0.0)), 0.0, 1.0)
	var jitter := float(lk.get("jitter", 0.0))
	var coil_end := coil_pts[coil_pts.size() - 1]
	var flat := Vector2(coil_end.x - anchor.x, coil_end.z - anchor.z)
	var dist := flat.length()
	var side := Vector3(-flat.y, 0.0, flat.x).normalized() if dist > 0.01 else Vector3.RIGHT
	var lie := ground_y + cable.radius()
	rise = minf(rise, dist * 0.6)
	# Schlängeln: Stärke wächst mit der Länge, Richtung aus dem Seed (jedes Kabel liegt anders)
	var meander := minf(float(c.get("meander", 0.08)) * dist, 0.6) * (1.0 - tension)
	var wave := 1.0 if posmod(cable.rng_seed, 2) == 0 else -1.0
	var rope: CableRope = lk.get("rope")
	var mid := PackedVector3Array()
	if rope:
		# Weiches Seil: schwingt nach, strafft sich mit Schwung, liegt am Boden
		var nodes := rope.step(anchor, coil_end, lie, rise, tension, side * wave, meander, float(lk.get("delta", 0.016)))
		var ctrl := PackedVector3Array([anchor])
		ctrl.append_array(nodes)
		ctrl.append(coil_end)
		mid = _smooth(ctrl, 3)
		mid = mid.slice(1, mid.size() - 1)
	else:
		var samples := clampi(int(dist / 0.2), 8, 60)
		for i in range(1, samples):
			var t := float(i) / samples
			# Locker: am Boden entlang, kurz vor dem Ziel in einem weichen Bogen hoch
			var slack := anchor.lerp(coil_end, t)
			slack += side * wave * meander * sin(t * PI) * (1.0 - t)
			var left := (1.0 - t) * dist
			var ground_line := lerpf(anchor.y, lie, minf(t * 4.0, 1.0))
			if left < rise:
				var u := 1.0 - left / maxf(rise, 0.001)
				slack.y = lerpf(ground_line, coil_end.y, u * u * (3.0 - 2.0 * u))
			else:
				slack.y = ground_line
			var taut := anchor.lerp(coil_end, t)
			mid.append(slack.lerp(taut, tension * tension * (3.0 - 2.0 * tension)))
	var m := mid.size()
	for i in m:
		var t := float(i + 1) / (m + 1)
		var p := mid[i]
		if jitter > 0.0:
			var amp := float(c.get("knot_jitter_m", 0.025)) * jitter * sin(t * PI)
			p += side * amp * sin(time * 47.0 + t * 11.0) + Vector3.UP * amp * 0.6 * sin(time * 39.0 + t * 7.0)
		if not rope:
			p.y = maxf(p.y, lie)
		pts.append(p)

	# 3. Wicklung
	for i in range(coil_pts.size() - 1, -1, -1):
		pts.append(coil_pts[i])
	return pts


## Weiche Kurve durch Stützpunkte (Catmull-Rom), `sub` Zwischenpunkte je Abschnitt
static func _smooth(ctrl: PackedVector3Array, sub: int) -> PackedVector3Array:
	var out := PackedVector3Array()
	var n := ctrl.size()
	for i in n - 1:
		var p0 := ctrl[maxi(i - 1, 0)]
		var p1 := ctrl[i]
		var p2 := ctrl[i + 1]
		var p3 := ctrl[mini(i + 2, n - 1)]
		for s in sub:
			var t := float(s) / sub
			var t2 := t * t
			var t3 := t2 * t
			out.append(0.5 * ((2.0 * p1) + (-p0 + p2) * t + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2
				+ (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t3))
	out.append(ctrl[n - 1])
	return out


## Helix um die Trommel. Das äußere Ende liegt immer bei `end_angle` (Richtung Haufen),
## dadurch dreht sich die ganze Spirale beim Aufwickeln mit der Trommel.
## Ergebnis: { "points": innen -> außen, "phase": Winkel des inneren Anfangs }
## `cable_radius` > 0: Windungen und Lagen liegen genau Kabel an Kabel.
static func coil_points(center: Vector3, length: float, end_angle: float, scale: float = 1.0, cable_radius: float = 0.0) -> Dictionary:
	var r: Dictionary = Balancing.reel
	var step_len: float = r["coil_point_step_m"]
	var pitch: float = float(r["coil_pitch_m"]) * scale
	var min_h: float = float(r["coil_min_height_m"]) * scale
	var max_h: float = float(r["coil_max_height_m"]) * scale
	var layer_step: float = float(r["coil_layer_step_m"]) * scale
	if cable_radius > 0.0:
		pitch = cable_radius * 2.05
		layer_step = cable_radius * 1.8

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


## Wicklung um den Unterarm wie auf einer Spule: Windungen laufen um den Arm herum von der Hand zum
## Ellbogen und zurück, jede Lage etwas weiter außen. Ergebnis: innen -> außen, in globalen Koordinaten.
static func arm_coil_points(arm: Transform3D, length: float, cable_radius: float = 0.045) -> PackedVector3Array:
	var a: Dictionary = Balancing.arm
	var near := -float(a.get("wrap_from_m", 0.05))
	var far := -float(a.get("wrap_to_m", 0.31))
	var step_len: float = a["point_step_m"]
	var pitch := cable_radius * 2.05
	var layer := cable_radius * 1.85
	var radius := float(a.get("wrap_radius_m", 0.075)) + cable_radius

	var out := PackedVector3Array()
	var angle := 0.0
	var z := far
	var dir := 1.0
	var s := 0.0
	var layer_index := 0
	out.append(arm * Vector3(radius, 0.0, z))
	while s < length:
		var step := minf(step_len, length - s)
		s += step
		angle += step / radius
		z += dir * pitch * step / (TAU * radius)
		if z > near:
			z = near
			dir = -1.0
			radius += layer
			layer_index += 1
		elif z < far:
			z = far
			dir = 1.0
			radius += layer
			layer_index += 1
		# leicht unregelmäßig, damit es nach Hand gewickelt aussieht
		var r := radius * (1.0 + 0.05 * sin(angle * 3.0 + layer_index * 1.7))
		out.append(arm * Vector3(cos(angle) * r, sin(angle) * r, z))
	return out