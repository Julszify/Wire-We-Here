class_name CityTerrain
extends RefCounted
## Baut das Terrain3D-Gelände der Stadt aus der WorldLayout-Höhenfunktion.
## Wird beim Start erzeugt (unter 1 s) statt als Datei gespeichert; so bleibt world.json die einzige Quelle.
## Später, wenn Viertel von Hand nachmodelliert werden, kann das Ergebnis gespeichert werden.


static func build(parent: Node, layout: WorldLayout) -> Terrain3D:
	var t := Terrain3D.new()
	t.name = "Terrain3D"
	parent.add_child(t)
	t.region_size = Terrain3D.SIZE_1024
	t.vertex_spacing = layout.vertex_spacing_m
	t.material.world_background = Terrain3DMaterial.NONE
	t.show_checkered = true  # Blockout: Schachbrett zeigt Maßstab und Steigung
	t.free_editor_textures = false
	var half := layout.size_m * 0.5
	t.data.import_images([height_image(layout), null, null], Vector3(-half, 0.0, -half), 0.0, 1.0)
	return t


## Höhenkarte als Bild. Das Berechnen dauert einige Sekunden, deshalb wird das Ergebnis in user://
## zwischengespeichert und nur neu erzeugt, wenn sich world.json oder HEIGHT_VERSION ändert.
const HEIGHT_VERSION := 1  # erhöhen, wenn sich WorldLayout.height() ändert

static func height_image(layout: WorldLayout) -> Image:
	var key := hash([FileAccess.get_file_as_string(WorldLayout.PATH), HEIGHT_VERSION])
	var cache := "user://city_height_%d.res" % key
	if ResourceLoader.exists(cache):
		var tex := load(cache) as ImageTexture
		if tex:
			return tex.get_image()
	var px := int(layout.size_m / layout.vertex_spacing_m)
	var half := layout.size_m * 0.5
	var img := Image.create_empty(px, px, false, Image.FORMAT_RF)
	for py in px:
		for pxx in px:
			var x := pxx * layout.vertex_spacing_m - half
			var z := py * layout.vertex_spacing_m - half
			img.set_pixel(pxx, py, Color(layout.height(x, z), 0.0, 0.0, 1.0))
	ResourceSaver.save(ImageTexture.create_from_image(img), cache)
	return img


## Meeresfläche (ohne Kollision) auf Höhe 0, nur südlich der Stadt (sonst stünde der Krater unter Wasser)
static func build_sea(parent: Node, layout: WorldLayout) -> MeshInstance3D:
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
	return sea
