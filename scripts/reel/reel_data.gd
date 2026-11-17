class_name ReelData
extends RefCounted
## Reiner Zustand eines "Aufwicklers": Arm der Spielfigur, Handkurbel oder Motorrolle.
## Der Arm ist bewusst auch ein Aufwickler – so laufen alle Werkzeuge durch dieselbe Logik.
## WAGON = ein Platz auf dem Kabeltrommel-Wagen (zieht wie eine Motorrolle, Lage kommt vom Wagen).
## Werkzeuge für die Masse: VACUUM = ein Platz im Kabelsauger (Düse vor der Figur), WINCH = Haufen-Winde
## (aufgestellt, hängt Kabel in der Nähe selbst ein), DRONE = Abräum-Drohne (fliegt, zieht, liefert ab).
## Diese drei ziehen von selbst und lösen Knoten nach auto_untie_s selbst (Werte in balancing.json).

enum Kind { ARM, HAND, MOTOR, WAGON, VACUUM, WINCH, DRONE }

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
## Wer sie trägt (Peer-ID), solange carried
var carrier_id := 0
## Tempo-Faktor aus Upgrades dieser Werkzeug-Art (Sauger, Winde, Drohne); von außen gesetzt
var speed_factor := 1.0
## Wie lange das Kabel schon am Knoten hängt (für selbstständiges Lösen); nicht gespeichert
var stuck_t := 0.0


func _init(reel_id: int = 0, reel_kind: Kind = Kind.HAND, pos: Vector3 = Vector3.ZERO) -> void:
	id = reel_id
	kind = reel_kind
	position = pos


func is_free() -> bool:
	return cable_id < 0


## Aufstellbares Werkzeug, das man aufheben und umstellen kann
func is_movable() -> bool:
	return kind == Kind.HAND or kind == Kind.MOTOR or kind == Kind.WINCH


## Zieht von selbst (Motorrolle, Wagen-Platz, Sauger, Winde, Drohne)
func is_motorized() -> bool:
	return kind != Kind.ARM and kind != Kind.HAND


## Gehört zu einem Werkzeug, das Kabel selbst einhängt und Knoten selbst löst
func is_automatic() -> bool:
	return kind == Kind.VACUUM or kind == Kind.WINCH or kind == Kind.DRONE


## Wird nicht gespeichert (entsteht beim Start aus den Upgrades neu)
func is_transient() -> bool:
	return kind == Kind.ARM or kind == Kind.VACUUM or kind == Kind.DRONE


## Werte-Abschnitt aus balancing.json für diese Art von Aufwickler.
func tuning() -> Dictionary:
	match kind:
		Kind.ARM:
			return Balancing.hand_wrap
		Kind.HAND:
			return Balancing.hand_crank
		Kind.WAGON:
			return Balancing.wagon
		Kind.VACUUM:
			return Balancing.vacuum
		Kind.WINCH:
			return Balancing.winch
		Kind.DRONE:
			return Balancing.drone
		_:
			return Balancing.motor_reel


func to_dict() -> Dictionary:
	return { "id": id, "kind": kind, "position": SaveGame.vec_to(position), "cable_id": cable_id, "owner_id": owner_id }


static func from_dict(d: Dictionary) -> ReelData:
	var r := ReelData.new(int(d["id"]), int(d["kind"]) as Kind, SaveGame.vec_from(d.get("position", [0, 0, 0])))
	r.cable_id = int(d.get("cable_id", -1))
	r.owner_id = int(d.get("owner_id", 0))
	return r
