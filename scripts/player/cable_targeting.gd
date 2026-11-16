class_name CableTargeting
extends RefCounted
## Findet, worauf das Fadenkreuz zeigt: Kabelende (eins von beiden), Knoten oder Rolle.
## Reine Mathematik (Abstand Punkt–Strahl), keine Physik-Kollision nötig –
## bleibt auch bei tausenden Kabeln günstig.


## Bei find_end: wurde das hintere Ende der Bahn getroffen (statt points[0])?
static var hit_tail := false


## Kabel mit greifbarem Ende im Haufen oder null. Beide Enden zählen; `hit_tail` sagt, welches es war.
static func find_end(cables: Array, ray_origin: Vector3, ray_dir: Vector3, player_pos: Vector3) -> CableData:
	var p: Dictionary = Balancing.player
	var best: CableData = null
	var best_d: float = p["aim_radius_m"]
	hit_tail = false
	for cable: CableData in cables:
		if cable.state != CableData.State.HEAP:
			continue
		var pts := cable.path.points
		var d := _hit(pts[0], ray_origin, ray_dir, player_pos, p["reach_m"])
		if d < best_d:
			best_d = d
			best = cable
			hit_tail = false
		d = _hit(pts[pts.size() - 1], ray_origin, ray_dir, player_pos, p["reach_m"])
		if d < best_d:
			best_d = d
			best = cable
			hit_tail = true
	return best


## Kabel, das an einem Knoten festhängt und in Reichweite ist, oder null.
## Der Knoten sitzt dort, wo das Kabel aus dem Haufen kommt.
static func find_knot(cables: Array, ray_origin: Vector3, ray_dir: Vector3, player_pos: Vector3) -> CableData:
	var p: Dictionary = Balancing.player
	var best: CableData = null
	var best_d: float = float(p["aim_radius_m"]) * 1.5
	for cable: CableData in cables:
		if cable.state != CableData.State.HOOKED or not cable.is_stuck():
			continue
		var d := _hit(cable.path.points[0], ray_origin, ray_dir, player_pos, p["reach_m"])
		if d < best_d:
			best_d = d
			best = cable
	return best


## Rolle (Handkurbel oder Motorrolle) in Reichweite oder null.
static func find_reel(reels: Array, ray_origin: Vector3, ray_dir: Vector3, player_pos: Vector3) -> ReelData:
	var p: Dictionary = Balancing.player
	var best: ReelData = null
	var best_d: float = Balancing.reel["flange_radius_m"]
	for reel: ReelData in reels:
		if reel.kind == ReelData.Kind.ARM or reel.kind == ReelData.Kind.VACUUM or reel.kind == ReelData.Kind.DRONE:
			continue
		var center := reel.position + Vector3(0.0, 0.6, 0.0)
		var d := _hit(center, ray_origin, ray_dir, player_pos, p["reel_reach_m"])
		if d < best_d:
			best_d = d
			best = reel
	return best


## Nächste Rolle in Reichweite der Figur (ohne Zielen), z. B. zum Kurbeln.
static func nearest_reel(reels: Array, player_pos: Vector3, kind: ReelData.Kind) -> ReelData:
	var best: ReelData = null
	var best_d: float = Balancing.player["reel_reach_m"]
	for reel: ReelData in reels:
		if reel.kind != kind:
			continue
		var d := Vector2(reel.position.x - player_pos.x, reel.position.z - player_pos.z).length()
		if d < best_d:
			best_d = d
			best = reel
	return best


## Abstand des Punkts vom Strahl; INF wenn außer Reichweite oder hinter der Kamera.
static func _hit(point: Vector3, origin: Vector3, dir: Vector3, player_pos: Vector3, reach: float) -> float:
	if Vector2(point.x - player_pos.x, point.z - player_pos.z).length() > reach:
		return INF
	var v := point - origin
	var t := v.dot(dir)
	if t < 0.0:
		return INF
	return (v - dir * t).length()
