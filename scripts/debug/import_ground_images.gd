extends SceneTree
## Übernimmt Bodenbilder (z. B. aus Midjourney, nahtlos kachelbar) als Terrain3D-Texturen.
## Quelle: tools/textures/midjourney/ground_<name>.png (tools/ ist vom Godot-Import ausgenommen)
## Ziel:   assets/textures/terrain/<name>_alb.png (RGB Farbe, A Höhe) und <name>_nrm.png (RGB Normale, A Rauheit)
## Die Höhe wird aus der Helligkeit geschätzt (weichgezeichnet, auf 0..1 gestreckt), die Normale daraus.
## Fehlt ein Bild, bleibt die bisherige (prozedurale) Textur stehen.
## Aufruf: godot --headless -s res://scripts/debug/import_ground_images.gd

const SIZE := 1024
const SRC := "res://tools/textures/midjourney/ground_%s.png"
const OUT := "res://assets/textures/terrain/"
## name: [Normalen-Stärke, Rauheit, Weichzeichnen der Höhe in Pixeln]
const GROUNDS := {
	"gras": [2.0, 0.9, 2],
	"pflaster": [5.0, 0.8, 2],
	"platten": [4.0, 0.75, 1],
	"beton": [1.5, 0.8, 1],
	"sand": [2.0, 0.95, 3],
	"kies": [5.0, 0.85, 1],
	"fels": [5.0, 0.85, 2],
}


func _init() -> void:
	for name: String in GROUNDS:
		var path := ProjectSettings.globalize_path(SRC % name)
		if not FileAccess.file_exists(path):
			print("  %s: kein Bild, bleibt prozedural" % name)
			continue
		var img := Image.load_from_file(path)
		img.convert(Image.FORMAT_RGBA8)
		if img.get_width() != SIZE or img.get_height() != SIZE:
			img.resize(SIZE, SIZE, Image.INTERPOLATE_LANCZOS)
		var p: Array = GROUNDS[name]
		_convert(name, img, p[0], p[1], p[2])
	print("BODENBILDER fertig")
	quit()


func _convert(name: String, img: Image, strength: float, roughness: float, blur: int) -> void:
	var n := SIZE * SIZE
	var h := PackedFloat32Array()
	h.resize(n)
	for y in SIZE:
		for x in SIZE:
			var c := img.get_pixel(x, y)
			h[y * SIZE + x] = c.r * 0.3 + c.g * 0.59 + c.b * 0.11
	for i in blur:
		h = _box_blur(h)
	# Strecken auf 0..1 (1. und 99. Perzentil), damit Terrain3D gut zwischen Böden überblendet
	var sorted := h.duplicate()
	sorted.sort()
	var lo := sorted[int(n * 0.01)]
	var hi := sorted[int(n * 0.99)]
	var span := maxf(hi - lo, 0.001)
	for i in n:
		h[i] = clampf((h[i] - lo) / span, 0.0, 1.0)

	var alb := Image.create_empty(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	var nrm := Image.create_empty(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	var k := strength * SIZE / 512.0 * 0.5
	for y in SIZE:
		for x in SIZE:
			var c := img.get_pixel(x, y)
			alb.set_pixel(x, y, Color(c.r, c.g, c.b, h[y * SIZE + x]))
			var hl := h[y * SIZE + posmod(x - 1, SIZE)]
			var hr := h[y * SIZE + posmod(x + 1, SIZE)]
			var hu := h[posmod(y - 1, SIZE) * SIZE + x]
			var hd := h[posmod(y + 1, SIZE) * SIZE + x]
			var nv := Vector3((hl - hr) * k, (hu - hd) * k, 1.0).normalized()
			nrm.set_pixel(x, y, Color(nv.x * 0.5 + 0.5, nv.y * 0.5 + 0.5, nv.z * 0.5 + 0.5, roughness))
	alb.save_png(OUT + name + "_alb.png")
	nrm.save_png(OUT + name + "_nrm.png")
	print("  %s übernommen" % name)


## 3×3-Mittelwert, über die Ränder hinweg (kachelbar)
func _box_blur(src: PackedFloat32Array) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(src.size())
	for y in SIZE:
		for x in SIZE:
			var s := 0.0
			for dy in [-1, 0, 1]:
				for dx in [-1, 0, 1]:
					s += src[posmod(y + dy, SIZE) * SIZE + posmod(x + dx, SIZE)]
			out[y * SIZE + x] = s / 9.0
	return out
