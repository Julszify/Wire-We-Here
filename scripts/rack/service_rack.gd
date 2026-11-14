class_name ServiceRack
extends Node
## Logik des Server-Schranks: Ports belegen, Dienste reaktivieren.
## Der Zustand (welche Ports aktiv sind) liegt in GameState, damit er gespeichert werden kann.

signal service_activated(port_id: int, service_name: String, unlocks: String)

var state: GameState


func _init(game_state: GameState = null) -> void:
	state = game_state


static func port_count() -> int:
	return Balancing.services.size()


static func service_name(port_id: int) -> String:
	if port_id < 0 or port_id >= Balancing.services.size():
		return "?"
	return String(Balancing.services[port_id].get("name", "Dienst %d" % (port_id + 1)))


static func service_unlocks(port_id: int) -> String:
	if port_id < 0 or port_id >= Balancing.services.size():
		return ""
	return String(Balancing.services[port_id].get("unlocks", ""))


func is_active(port_id: int) -> bool:
	return state.active_ports.has(port_id)


func active_count() -> int:
	return state.active_ports.size()


## Steckt ein wichtiges Kabel in seinen Port. Gibt false zurück, wenn der Port schon belegt ist.
func plug(port_id: int) -> bool:
	if port_id < 0 or port_id >= port_count() or is_active(port_id):
		return false
	state.active_ports.append(port_id)
	service_activated.emit(port_id, service_name(port_id), service_unlocks(port_id))
	return true
