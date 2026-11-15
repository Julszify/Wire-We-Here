class_name WorldLayout
extends RefCounted
## Grobe Anordnung der Stadt aus data/world.json: Geländehöhe, Viertel, Landmarken.
## Reine Daten und Funktionen ohne Szene; Gelände, Blockout und Teleport lesen alle von hier.

const PATH := "res://data/world.json"

var size_m: float = 2048.0
var vertex_spacing_m: float = 2.0
var districts: Array[Dictionary] = []
var landmarks: Array[Dictionary] = []
var spawn: Vector2 = Vector2.ZERO
var _d: Dictionary = {}


static func load_default() -> WorldLayout:
	var text := FileAccess.get_file_as_string(PATH)
	var data = JSON.parse_string(text)
	assert(data is Dictionary, "world.json fehlt oder ist kaputt")
	var w := WorldLayout.new()
	w._d = data
	w.size_m = float(data["size_m"])
	w.vertex_spacing_m = float(data["vertex_spacing_m"])
	for d: Dictionary in data["districts"]:
		w.districts.append(d)
	for l: Dictionary in data.get("landmarks", []):
		w.landmarks.append(l)
	w.spawn = _v2(data["spawn"])
	return w


func district(id: String) -> Dictionary:
	for d in districts:
		if d["id"] == id:
			return d
	return {}


## Viertel, in dessen Fläche (x, z) liegt; leer, wenn keins
func district_at(x: float, z: float) -> Dictionary:
	for d in districts:
		var c := _v2(d["center"])
		var half := _v2(d["size"]) * 0.5
		if absf(x - c.x) <= half.x and absf(z - c.y) <= half.y:
			return d
	return {}


## Geländehöhe in Metern an (x, z)
func height(x: float, z: float) -> float:
	var h := float(_d["valley_height_m"])
	h += sin(x * 0.013) * cos(z * 0.011) * 1.5  # leichte Unebenheit

	# Hügel am Kartenrand
	for hill: Dictionary in _d.get("hills", []):
		var t := 0.0
		match String(hill["side"]):
			"north":
				t = smoothstep(float(hill["from_m"]), float(hill["to_m"]), z)
				h += t * float(hill["height_m"]) * (0.7 + 0.3 * sin(x * 0.005))
			"east":
				t = smoothstep(float(hill["from_m"]), float(hill["to_m"]), x)
				h += t * float(hill["height_m"]) * (0.7 + 0.3 * sin(z * 0.006))
			"west":
				t = smoothstep(float(hill["from_m"]), float(hill["to_m"]), x)
				h += t * float(hill["height_m"]) * (0.7 + 0.3 * cos(z * 0.005))

	# Küste: hinter der welligen Küstenlinie fällt das Gelände zum Meeresgrund
	var coast: Dictionary = _d["coast"]
	var cz := float(coast["z_m"]) + float(coast["wobble_m"]) * sin(x * 0.004)
	var sea_t := smoothstep(cz - 40.0, cz + float(coast["width_m"]) - 40.0, z)
	h = lerpf(h, float(_d["sea_floor_m"]), sea_t)

	# Viertel einebnen (weicher Rand = Rampe)
	for d in districts:
		var edge := float(d["edge_m"])
		if edge <= 0.0:
			continue
		var dist := _rect_distance(Vector2(x, z), _v2(d["center"]), _v2(d["size"]) * 0.5, 30.0)
		var w := 1.0 - smoothstep(0.0, edge, dist)
		h = lerpf(h, float(d["height_m"]), w)

	# Krater: Ringwall und Mulde
	var cr: Dictionary = _d["crater"]
	var dc := Vector2(x, z).distance_to(_v2(cr["center"]))
	var rim := float(cr["rim_radius_m"])
	h += exp(-pow((dc - rim) / 45.0, 2.0)) * float(cr["rim_height_m"])
	var floor_w := 1.0 - smoothstep(float(cr["floor_radius_m"]), rim - 20.0, dc)
	h = lerpf(h, float(cr["floor_m"]), floor_w)

	# Hafenbecken mit steiler Kaimauer
	var hb: Dictionary = _d["harbor_basin"]
	var db := _rect_distance(Vector2(x, z), _v2(hb["center"]), _v2(hb["size"]) * 0.5, 6.0)
	if db < 4.0:
		h = lerpf(float(hb["depth_m"]), h, smoothstep(-2.0, 4.0, db))
	return h


## Nördlichste Stelle, an der Meer sein kann (Küstenlinie minus Welle, etwas Puffer)
func sea_north_edge_m() -> float:
	var coast: Dictionary = _d["coast"]
	return minf(float(coast["z_m"]) - float(coast["wobble_m"]) - 40.0,
		float(_d["harbor_basin"]["center"][1]) - float(_d["harbor_basin"]["size"][1]) * 0.5 - 10.0)


## Abstand zum Rand eines abgerundeten Rechtecks (negativ = innen)
static func _rect_distance(p: Vector2, center: Vector2, half: Vector2, radius: float) -> float:
	var q := (p - center).abs() - half + Vector2(radius, radius)
	return Vector2(maxf(q.x, 0.0), maxf(q.y, 0.0)).length() + minf(maxf(q.x, q.y), 0.0) - radius


static func _v2(a: Array) -> Vector2:
	return Vector2(float(a[0]), float(a[1]))
