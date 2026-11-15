class_name CityTerrain
extends RefCounted
## Baut das Terrain3D-Gelände der Stadt aus der WorldLayout-Höhenfunktion.
## Wird beim Start erzeugt (zwischengespeichert) statt als Datei im Projekt; so bleibt world.json die einzige Quelle.
## Später, wenn Viertel von Hand nachmodelliert werden, kann das Ergebnis gespeichert werden.


## `offset` verschiebt die ganze Stadt (die Hauptszene legt so den Hinterhof auf den Ursprung).
static func build(parent: Node, layout: WorldLayout, offset: Vector3 = Vector3.ZERO) -> Terrain3D:
	var t := Terrain3D.new()
	t.name = "Terrain3D"
	t.free_editor_textures = false  # vor add_child, sonst warnt Terrain3D beim Eintritt in den Baum
	parent.add_child(t)
	t.region_size = Terrain3D.SIZE_1024
	t.vertex_spacing = layout.vertex_spacing_m
	t.material.world_background = Terrain3DMaterial.NONE
	var textured := _setup_textures(t, layout)
	t.show_checkered = not textured  # ohne Bodentexturen: Schachbrett zeigt Maßstab und Steigung
	var maps := build_maps(layout)
	var half := layout.size_m * 0.5
	t.data.import_images([maps[0], maps[1], null], Vector3(-half + offset.x, 0.0, -half + offset.z),
		offset.y, 1.0)
	return t


## Bodentexturen aus assets/textures/terrain/ (siehe ground in world.json) und Automatik für Hänge
static func _setup_textures(t: Terrain3D, layout: WorldLayout) -> bool:
	var g: Dictionary = layout.raw().get("ground", {})
	var list: Array = g.get("textures", [])
	if list.is_empty():
		return false
	for i in list.size():
		var e: Dictionary = list[i]
		var alb := _load_texture("res://assets/textures/terrain/%s_alb.png" % e["name"])
		var nrm := _load_texture("res://assets/textures/terrain/%s_nrm.png" % e["name"])
		if alb == null or nrm == null:
			push_warning("Bodentextur fehlt: %s (scripts/debug/make_terrain_textures.gd ausführen)" % e["name"])
			return false
		var ta := Terrain3DTextureAsset.new()
		ta.name = String(e["name"])
		ta.albedo_texture = alb
		ta.normal_texture = nrm
		ta.uv_scale = float(e.get("uv_scale", 0.1))
		if e.get("detiling", false):
			ta.detiling_rotation = 0.3
			ta.detiling_shift = 0.3
		t.assets.set_texture_asset(i, ta)
	# Welcher Boden wo liegt, steht vollständig in der Steuerkarte (build_maps); keine Terrain3D-Automatik
	t.material.auto_shader_enabled = false
	t.material.macro_variation_enabled = true
	t.material.set_shader_param("blend_sharpness", 0.85)
	return true


## PNG als Textur mit Mipmaps (Terrain3D braucht gleiche Größe und gleiches Format für alle Böden)
static func _load_texture(path: String) -> ImageTexture:
	if not ResourceLoader.exists(path):
		return null
	var img := (load(path) as Texture2D).get_image()
	if img.is_compressed():
		img.decompress()
	img.convert(Image.FORMAT_RGBA8)
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


## Höhenkarte und Steuerkarte (welcher Boden wo) als Bilder. Das Berechnen dauert einige Sekunden,
## deshalb werden beide in user:// zwischengespeichert und nur neu erzeugt, wenn sich world.json
## oder MAPS_VERSION ändert.
const MAPS_VERSION := 3  # erhöhen, wenn sich WorldLayout.height() oder ground_at() ändert

static func build_maps(layout: WorldLayout) -> Array[Image]:
	var key := hash([FileAccess.get_file_as_string(WorldLayout.PATH), MAPS_VERSION])
	var cache_h := "user://city_height_%d.res" % key
	var cache_c := "user://city_control_%d.res" % key
	if ResourceLoader.exists(cache_h) and ResourceLoader.exists(cache_c):
		var th := load(cache_h) as ImageTexture
		var tc := load(cache_c) as ImageTexture
		if th and tc:
			return [th.get_image(), tc.get_image()]
	var px := int(layout.size_m / layout.vertex_spacing_m)
	var half := layout.size_m * 0.5
	var himg := Image.create_empty(px, px, false, Image.FORMAT_RF)
	var cimg := Image.create_empty(px, px, false, Image.FORMAT_RF)
	# 1. Höhen
	var hs := PackedFloat32Array()
	hs.resize(px * px)
	for py in px:
		for pxx in px:
			var h := layout.height(pxx * layout.vertex_spacing_m - half, py * layout.vertex_spacing_m - half)
			hs[py * px + pxx] = h
			himg.set_pixel(pxx, py, Color(h, 0.0, 0.0, 1.0))
	# 2. Boden je Pixel; Steigung aus den Nachbarhöhen
	var step := layout.vertex_spacing_m * 2.0
	for py in px:
		for pxx in px:
			var x := pxx * layout.vertex_spacing_m - half
			var z := py * layout.vertex_spacing_m - half
			var dx := hs[py * px + mini(pxx + 1, px - 1)] - hs[py * px + maxi(pxx - 1, 0)]
			var dz := hs[mini(py + 1, px - 1) * px + pxx] - hs[maxi(py - 1, 0) * px + pxx]
			var slope := Vector2(dx, dz).length() / step
			var gnd := layout.ground_at(x, z, hs[py * px + pxx], slope)
			var bits: int = Terrain3DUtil.enc_base(gnd[0]) | Terrain3DUtil.enc_overlay(gnd[1]) \
				| Terrain3DUtil.enc_blend(int(clampf(gnd[2], 0.0, 1.0) * 255.0))
			cimg.set_pixel(pxx, py, Color(Terrain3DUtil.as_float(bits), 0.0, 0.0, 1.0))
	ResourceSaver.save(ImageTexture.create_from_image(himg), cache_h)
	ResourceSaver.save(ImageTexture.create_from_image(cimg), cache_c)
	return [himg, cimg]


## Meeresfläche (ohne Kollision) auf Höhe 0, nur südlich der Stadt (sonst stünde der Krater unter Wasser)
static func build_sea(parent: Node, layout: WorldLayout, offset: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var sea := MeshInstance3D.new()
	sea.name = "Sea"
	var pm := PlaneMesh.new()
	var north_edge := layout.sea_north_edge_m()
	pm.size = Vector2(layout.size_m, 3000.0)
	pm.center_offset = Vector3(0, 0, north_edge + 1500.0)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.15, 0.4, 0.65, 0.85)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.roughness = 0.1
	pm.material = mat
	sea.mesh = pm
	parent.add_child(sea)
	sea.position = offset
	return sea
