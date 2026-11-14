class_name CoilItem
extends RefCounted
## Fertig aufgerolltes wichtiges Kabel: ein beschriftetes Knäuel, das zum Schrank getragen wird.
## Reine Daten; liegt entweder am Boden oder wird von einem Spieler getragen.

var id: int = 0
var port_id: int = -1
var color_index: int = 0
## Sichtbare Länge für die Darstellung der Schlaufen
var visual_length: float = 0.0
var position: Vector3 = Vector3.ZERO
## Spieler, der es trägt (-1 = liegt am Boden)
var carried_by: int = -1


static func from_cable(item_id: int, cable: CableData) -> CoilItem:
	var item := CoilItem.new()
	item.id = item_id
	item.port_id = cable.port_id
	item.color_index = cable.color_index
	item.visual_length = CableShape.coil_length(cable)
	return item


func color() -> Color:
	return Color.html(Balancing.cable["palette"][color_index])
