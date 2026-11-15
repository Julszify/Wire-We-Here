class_name ReelData
extends RefCounted
## Reiner Zustand eines "Aufwicklers": Arm der Spielfigur, Handkurbel oder Motorrolle.
## Der Arm ist bewusst auch ein Aufwickler – so laufen alle Werkzeuge durch dieselbe Logik.
## WAGON = ein Platz auf dem Kabeltrommel-Wagen (zieht wie eine Motorrolle, Lage kommt vom Wagen).

enum Kind { ARM, HAND, MOTOR, WAGON }

var id: int = 0
var kind: Kind = Kind.HAND
var position: Vector3 = Vector3.ZERO
## Eingehängtes Kabel, -1 = frei
var cable_id: int = -1
## Noch abzuarbeitende Meter aus Tastendrücken (Arm und Handkurbel)
var pending_m: float = 0.0
## Arm: Spieler, dem er gehört (für späteren Koop)
var owner_id: int = 0
## Wird gerade von einem Spieler getragen (Handkurbel oder Motorrolle umstellen); nicht gespeichert
var carried := false


func _init(reel_id: int = 0, reel_kind: Kind = Kind.HAND, pos: Vector3 = Vector3.ZERO) -> void:
	id = reel_id
	kind = reel_kind
	position = pos


func is_free() -> bool:
	return cable_id < 0


## Aufstellbares Werkzeug, das man aufheben und umstellen kann
func is_movable() -> bool:
	return kind == Kind.HAND or kind == Kind.MOTOR


## Zieht von selbst (Motorrolle, Wagen-Platz)
func is_motorized() -> bool:
	return kind == Kind.MOTOR or kind == Kind.WAGON


## Werte-Abschnitt aus balancing.json für diese Art von Aufwickler.
func tuning() -> Dictionary:
	match kind:
		Kind.ARM:
			return Balancing.hand_wrap
		Kind.HAND:
			return Balancing.hand_crank
		Kind.WAGON:
			return Balancing.wagon
		_:
			return Balancing.motor_reel


func to_dict() -> Dictionary:
	return { "id": id, "kind": kind, "position": SaveGame.vec_to(position), "cable_id": cable_id, "owner_id": owner_id }


static func from_dict(d: Dictionary) -> ReelData:
	var r := ReelData.new(int(d["id"]), int(d["kind"]) as Kind, SaveGame.vec_from(d.get("position", [0, 0, 0])))
	r.cable_id = int(d.get("cable_id", -1))
	r.owner_id = int(d.get("owner_id", 0))
	return r
