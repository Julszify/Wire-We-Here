class_name ServiceRack
extends Node
## Logik des Serverraums: Ports belegen, Dienste reaktivieren.
## Welcher Port zu welchem Dienst gehört, steht in RackPlan; der Zustand (belegte Ports) liegt in
## GameState, damit er gespeichert werden kann.

## Ein Knäuel steckt in seinem Port
signal port_plugged(port_id: int)
## Alle Ports eines Dienstes sind belegt (bei Einzel-Diensten sofort, sonst mit der vollen Reihe)
signal service_activated(service_id: int, service_name: String, unlocks: String)

var state: GameState


func _init(game_state: GameState = null) -> void:
	state = game_state


static func port_count() -> int:
	return RackPlan.total_ports()


func is_active(port_id: int) -> bool:
	return state.has_port(port_id)


## Belegte Ports
func active_count() -> int:
	return state.active_ports.size()


func active_services() -> int:
	return RackPlan.active_services(state)


## Steckt ein wichtiges Kabel in seinen Port. Gibt false zurück, wenn der Port schon belegt ist.
func plug(port_id: int) -> bool:
	if port_id < 0 or port_id >= port_count() or is_active(port_id):
		return false
	state.add_port(port_id)
	port_plugged.emit(port_id)
	var service := RackPlan.service_of(port_id)
	if RackPlan.service_active(state, service):
		service_activated.emit(service, RackPlan.service_name(service), RackPlan.service_unlocks(service))
	return true
