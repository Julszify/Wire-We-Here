class_name CityWorld
extends Node3D
## Die ganze Stadt als ein Baustein: Gelände (Terrain3D), Meer und Blockout (Straßen, Gebäude, Turm).
## `offset` verschiebt alles; die Hauptszene legt damit den Wolkig-Hinterhof auf (0, 0, 0),
## damit die bisherige Zone (Haufen, Schrank, Spielstand) ihre Koordinaten behält.

var layout: WorldLayout
var terrain: Terrain3D
var blockout: CityBlockout
var offset := Vector3.ZERO


## Verschiebung, die den Hinterhof auf den Ursprung und auf Höhe 0 legt
static func backyard_offset(world_layout: WorldLayout) -> Vector3:
	var c := WorldLayout._v2(world_layout.raw()["backyard"]["center"])
	return Vector3(-c.x, -world_layout.height(c.x, c.y), -c.y)


func build(city_offset: Vector3, follow: Node3D, world_layout: WorldLayout = null) -> void:
	offset = city_offset
	layout = world_layout if world_layout else WorldLayout.load_default()
	terrain = CityTerrain.build(self, layout, offset)
	terrain.collision_target = follow
	terrain.clipmap_target = follow
	CityTerrain.build_sea(self, layout, offset)
	blockout = CityBlockout.new()
	blockout.name = "Blockout"
	add_child(blockout)
	blockout.position = offset
	blockout.build(layout)


## Geländehöhe an einer Stelle der Szene (in Szenen-Koordinaten)
func ground_height(global_x: float, global_z: float) -> float:
	return layout.height(global_x - offset.x, global_z - offset.z) + offset.y


## Viertel an einer Stelle der Szene (leer, wenn keins)
func district_at(global_x: float, global_z: float) -> Dictionary:
	return layout.district_at(global_x - offset.x, global_z - offset.z)
