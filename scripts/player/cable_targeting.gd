class_name CableTargeting
extends RefCounted
## Findet das Kabelende, auf das das Fadenkreuz zeigt.
## Reine Mathematik (Abstand Punkt–Strahl), keine Physik-Kollision nötig –
## bleibt auch bei tausenden Kabeln günstig.


## Gibt das beste greifbare Kabel zurück oder null.
static func find_end(cables: Array, ray_origin: Vector3, ray_dir: Vector3, player_pos: Vector3) -> CableData:
	var p: Dictionary = Balancing.player
	var reach: float = p["reach_m"]
	var best: CableData = null
	var best_d: float = p["aim_radius_m"]
	for cable: CableData in cables:
		if cable.state != CableData.State.HEAP:
			continue
		var end := cable.path.points[0]
		if Vector2(end.x - player_pos.x, end.z - player_pos.z).length() > reach:
			continue
		var v := end - ray_origin
		var t := v.dot(ray_dir)
		if t < 0.0:
			continue
		var d := (v - ray_dir * t).length()
		if d < best_d:
			best_d = d
			best = cable
	return best
