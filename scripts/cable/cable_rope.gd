class_name CableRope
extends RefCounted
## Weiches Seil für das Verbindungsstück eines aktiven Kabels (Haufen → Aufwickler): wenige Knoten mit
## Verlet-Integration, Schwerkraft, fester Länge und Boden. Dadurch schwingt das Kabel nach, wenn sich die
## Figur bewegt, strafft sich mit Schwung beim Ziehen und ruckt am Knoten. Nur Darstellung, keine Spiellogik.
## Werte in balancing.json → connector (rope_*).

var pos := PackedVector3Array()
var prev := PackedVector3Array()
var _kick := Vector3.ZERO


## Einmaliger Stoß (z. B. Ruck am Knoten): wirkt im nächsten Schritt auf die Mitte des Seils
func kick(impulse: Vector3) -> void:
	_kick += impulse


## Einen Schritt rechnen und die Knoten (ohne Endpunkte) zurückgeben.
## anchor = Ende im Haufen, end = Anfang der Wicklung; floor_y(t) als Bodenlinie über anchor.y → lie;
## tension 0 locker … 1 straff; side = Richtung fürs Schlängeln; wave = Startform locker.
func step(anchor: Vector3, end: Vector3, lie: float, rise: float, tension: float, side: Vector3, meander: float,
		delta: float) -> PackedVector3Array:
	var c: Dictionary = Balancing.connector
	var count := int(c.get("rope_nodes", 14))
	var dist := anchor.distance_to(end)
	if pos.size() != count + 1 or pos[0].distance_to(anchor) > 3.0 or pos[count].distance_to(end) > 3.0:
		_reset(anchor, end, lie, rise, side, meander, count)
	delta = clampf(delta, 0.0, 1.0 / 30.0)
	var slack := float(c.get("rope_slack", 0.14)) * (1.0 - tension)
	var seg := dist * (1.0 + slack) / count
	var damping := float(c.get("rope_damping", 0.94))
	var g := Vector3(0, -float(c.get("rope_gravity", 14.0)), 0) * delta * delta
	# Bewegung: Schwung aus dem letzten Schritt, Schwerkraft, Stoß in der Mitte
	for i in range(1, count):
		var p := pos[i]
		var v := (p - prev[i]) * damping
		prev[i] = p
		var bump := _kick * sin(PI * float(i) / count)
		pos[i] = p + v + g + bump * delta
	_kick = Vector3.ZERO
	pos[0] = anchor
	pos[count] = end
	prev[0] = anchor
	prev[count] = end
	# Länge halten (einige Durchgänge), Boden, beim Straffen Richtung gerade Linie
	var straight := tension * tension * float(c.get("rope_straighten", 0.35))
	for it in int(c.get("rope_iterations", 6)):
		for i in count:
			var a := pos[i]
			var b := pos[i + 1]
			var d := b - a
			var len := d.length()
			if len < 1e-6:
				continue
			var corr := d * ((len - seg) / len) * 0.5
			if i > 0:
				pos[i] = a + corr
			if i + 1 < count:
				pos[i + 1] = b - corr
		for i in range(1, count):
			var t := float(i) / count
			if straight > 0.0:
				pos[i] = pos[i].lerp(anchor.lerp(end, t), straight / float(it + 1))
			var floor := _floor(anchor, end, lie, rise, t, dist)
			if pos[i].y < floor:
				pos[i].y = floor
				# Reibung am Boden: waagerechte Bewegung bremsen
				prev[i].x = lerpf(prev[i].x, pos[i].x, 0.35)
				prev[i].z = lerpf(prev[i].z, pos[i].z, 0.35)
	return pos.slice(1, count)


## Bodenlinie: vom Haufen-Ende hinunter auf den Boden, kurz vor dem Aufwickler darf es hoch
func _floor(anchor: Vector3, end: Vector3, lie: float, rise: float, t: float, dist: float) -> float:
	var ground := lerpf(anchor.y, lie, minf(t * 4.0, 1.0))
	var left := (1.0 - t) * dist
	if left < rise:
		return minf(ground, end.y)  # auf dem letzten Stück schwebt es zum Aufwickler hoch
	return ground


func _reset(anchor: Vector3, end: Vector3, lie: float, rise: float, side: Vector3, meander: float, count: int) -> void:
	pos.resize(count + 1)
	prev.resize(count + 1)
	var dist := anchor.distance_to(end)
	for i in count + 1:
		var t := float(i) / count
		var p := anchor.lerp(end, t) + side * meander * sin(t * PI) * (1.0 - t)
		p.y = maxf(_floor(anchor, end, lie, rise, t, dist), lerpf(anchor.y, end.y, t) - 0.3)
		pos[i] = p
		prev[i] = p
