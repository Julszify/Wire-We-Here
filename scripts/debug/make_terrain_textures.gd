extends SceneTree
## Erzeugt die Bodentexturen der Stadt (kachelbar, Spielzeug-Look) als PNG in assets/textures/terrain/.
## Je Boden zwei Bilder, wie Terrain3D sie erwartet:
##   <name>_alb.png  RGB = Farbe, A = Höhe (für weiche Übergänge zwischen Böden)
##   <name>_nrm.png  RGB = Normale, A = Rauheit
## Aufruf: godot --headless -s res://scripts/debug/make_terrain_textures.gd
## Die Reihenfolge der Namen entspricht den Textur-IDs in data/world.json (ground.textures).

const SIZE := 512
const OUT := "res://assets/textures/terrain/"


func _init() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	_make("gras", _grass)
	_make("pflaster", _cobble)
	_make("platten", _slabs)
	_make("beton", _concrete)
	_make("sand", _sand)
	_make("kies", _gravel)
	_make("fels", _rock)
	print("BODENTEXTUREN fertig")
	quit()


## Ruft f(u, v) -> [Farbe, Höhe 0..1, Rauheit] für jedes Pixel auf und speichert beide Bilder.
func _make(name: String, f: Callable) -> void:
	var t0 := Time.get_ticks_msec()
	var alb := Image.create_empty(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	var heights := PackedFloat32Array()
	heights.resize(SIZE * SIZE)
	var rough := PackedFloat32Array()
	rough.resize(SIZE * SIZE)
	for y in SIZE:
		for x in SIZE:
			var r: Array = f.call(float(x) / SIZE, float(y) / SIZE)
			var c: Color = r[0]
			var h := clampf(r[1], 0.0, 1.0)
			heights[y * SIZE + x] = h
			rough[y * SIZE + x] = r[2]
			alb.set_pixel(x, y, Color(c.r, c.g, c.b, h))
	# Normale aus der Höhe (kachelbar: Nachbarn über den Rand hinweg)
	var nrm := Image.create_empty(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	var strength := 3.0
	for y in SIZE:
		for x in SIZE:
			var hl := heights[y * SIZE + posmod(x - 1, SIZE)]
			var hr := heights[y * SIZE + posmod(x + 1, SIZE)]
			var hu := heights[posmod(y - 1, SIZE) * SIZE + x]
			var hd := heights[posmod(y + 1, SIZE) * SIZE + x]
			var n := Vector3((hl - hr) * strength, (hu - hd) * strength, 1.0).normalized()
			nrm.set_pixel(x, y, Color(n.x * 0.5 + 0.5, n.y * 0.5 + 0.5, n.z * 0.5 + 0.5, rough[y * SIZE + x]))
	alb.save_png(OUT + name + "_alb.png")
	nrm.save_png(OUT + name + "_nrm.png")
	print("  %s in %d ms" % [name, Time.get_ticks_msec() - t0])


# ---------------------------------------------------------------- Rauschen und Zellen (kachelbar)

var _noise := {}

func _fnl(seed_value: int, freq: float, octaves: int = 3) -> FastNoiseLite:
	var key := "%d_%f_%d" % [seed_value, freq, octaves]
	if not _noise.has(key):
		var n := FastNoiseLite.new()
		n.seed = seed_value
		n.frequency = freq
		n.fractal_octaves = octaves
		n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		_noise[key] = n
	return _noise[key]


## Kachelbares Rauschen 0..1. u und v laufen als Winkel um Kreise, dadurch ist das Ergebnis an den
## Kanten nahtlos (angenäherter 4D-Torus aus zwei 3D-Proben). `scale` = ungefähre Zahl der Flecken je Kachel.
func _tile_noise(u: float, v: float, seed_value: int, scale: float, octaves: int = 3) -> float:
	var n := _fnl(seed_value, 1.0, octaves)
	var r := scale / TAU
	var a := u * TAU
	var b := v * TAU
	var s := n.get_noise_3d(cos(a) * r, sin(a) * r, cos(b) * r + 17.0) \
		+ n.get_noise_3d(sin(b) * r + 31.0, cos(b) * r, sin(a) * r)
	return clampf((s * 0.7 + 1.0) * 0.5, 0.0, 1.0)


## Zellen (Worley) auf einem Gitter mit g x g Zellen, kachelbar. Ergebnis: [Abstand zum Punkt, Abstand Rand, Zell-ID]
func _cells(u: float, v: float, g: int, jitter: float, seed_value: int) -> Array:
	var px := u * g
	var py := v * g
	var cx := floori(px)
	var cy := floori(py)
	var d1 := 99.0
	var d2 := 99.0
	var id := 0
	for oy in range(-1, 2):
		for ox in range(-1, 2):
			var gx := cx + ox
			var gy := cy + oy
			var wx := posmod(gx, g)
			var wy := posmod(gy, g)
			var hsh := hash([wx, wy, seed_value])
			var jx := float(hsh & 1023) / 1023.0
			var jy := float((hsh >> 10) & 1023) / 1023.0
			var fx := gx + 0.5 + (jx - 0.5) * jitter
			var fy := gy + 0.5 + (jy - 0.5) * jitter
			var d := Vector2(px - fx, py - fy).length()
			if d < d1:
				d2 = d1
				d1 = d
				id = hsh
			elif d < d2:
				d2 = d
	return [d1, d2 - d1, id]


func _id_rand(id: int, k: int) -> float:
	return float(hash([id, k]) & 0xffff) / 65535.0


# ---------------------------------------------------------------- Böden

func _grass(u: float, v: float) -> Array:
	var big := _tile_noise(u, v, 1, 3.0)
	var fine := _tile_noise(u, v, 2, 24.0, 2)
	var blades := _tile_noise(u, v, 3, 90.0, 1)
	var c := Color(0.33, 0.44, 0.24).lerp(Color(0.43, 0.52, 0.29), big)
	c = c.lerp(Color(0.27, 0.37, 0.20), fine * 0.35)
	c = c.lightened((blades - 0.5) * 0.12)
	return [c, 0.35 + fine * 0.3 + blades * 0.25, 0.9]


func _cobble(u: float, v: float) -> Array:
	var cell := _cells(u, v, 9, 0.7, 11)
	var edge: float = cell[1]
	var id: int = cell[2]
	var stone := smoothstep(0.04, 0.16, edge)
	var tint := _id_rand(id, 1)
	var base := Color(0.58, 0.52, 0.45).lerp(Color(0.66, 0.62, 0.56), tint)
	base = base.darkened(_id_rand(id, 2) * 0.12)
	var grain := _tile_noise(u, v, 12, 40.0, 2)
	var c := Color(0.30, 0.28, 0.26).lerp(base.lightened((grain - 0.5) * 0.1), stone)
	var dome := 1.0 - clampf(float(cell[0]) * 1.4, 0.0, 1.0)
	return [c, stone * (0.55 + dome * 0.45), lerpf(0.95, 0.7, stone)]


func _slabs(u: float, v: float) -> Array:
	var n := 4  # 4 x 4 Platten pro Kachel
	var tx := u * n
	var ty := v * n
	var fx := tx - floorf(tx)
	var fy := ty - floorf(ty)
	var joint := minf(minf(fx, 1.0 - fx), minf(fy, 1.0 - fy))
	var slab := smoothstep(0.012, 0.03, joint)
	var id := hash([posmod(floori(tx), n), posmod(floori(ty), n), 21])
	var tint := _id_rand(id, 1)
	var grain := _tile_noise(u, v, 22, 30.0, 3)
	var stain := _tile_noise(u, v, 23, 4.0, 2)
	var base := Color(0.68, 0.67, 0.64).lerp(Color(0.74, 0.73, 0.70), tint)
	base = base.darkened(stain * 0.12).lightened((grain - 0.5) * 0.08)
	var c := Color(0.42, 0.42, 0.41).lerp(base, slab)
	return [c, slab * (0.6 + grain * 0.2), lerpf(0.9, 0.8, slab)]


func _concrete(u: float, v: float) -> Array:
	var grain := _tile_noise(u, v, 31, 60.0, 2)
	var blot := _tile_noise(u, v, 32, 4.0, 3)
	var c := Color(0.52, 0.52, 0.51).lerp(Color(0.60, 0.60, 0.58), blot)
	c = c.darkened(smoothstep(0.65, 0.85, blot) * 0.08).lightened((grain - 0.5) * 0.06)
	return [c, 0.4 + grain * 0.2, 0.85]


func _sand(u: float, v: float) -> Array:
	var big := _tile_noise(u, v, 41, 3.0)
	var fine := _tile_noise(u, v, 42, 80.0, 1)
	var ripple := 0.5 + 0.5 * sin((v * 14.0 + _tile_noise(u, v, 43, 2.0) * 3.0) * TAU)
	var c := Color(0.82, 0.74, 0.56).lerp(Color(0.88, 0.80, 0.62), big)
	c = c.darkened(ripple * 0.06).lightened((fine - 0.5) * 0.08)
	return [c, 0.3 + ripple * 0.3 + fine * 0.1, 0.95]


func _gravel(u: float, v: float) -> Array:
	var cell := _cells(u, v, 22, 0.9, 51)
	var id: int = cell[2]
	var stone := smoothstep(0.02, 0.12, float(cell[1]))
	var base := Color(0.55, 0.52, 0.48).lerp(Color(0.68, 0.64, 0.58), _id_rand(id, 1))
	base = base.darkened(_id_rand(id, 2) * 0.2)
	var c := Color(0.36, 0.33, 0.30).lerp(base, stone)
	var dome := 1.0 - clampf(float(cell[0]) * 1.6, 0.0, 1.0)
	return [c, stone * (0.4 + dome * 0.6), 0.9]


func _rock(u: float, v: float) -> Array:
	var big := _tile_noise(u, v, 61, 2.5, 4)
	var strata := 0.5 + 0.5 * sin((v * 6.0 + big * 2.0) * TAU)
	var fine := _tile_noise(u, v, 62, 30.0, 3)
	var c := Color(0.50, 0.47, 0.43).lerp(Color(0.62, 0.58, 0.52), big)
	c = c.darkened(strata * 0.12).lightened((fine - 0.5) * 0.12)
	return [c, 0.3 + big * 0.4 + fine * 0.3, 0.85]
