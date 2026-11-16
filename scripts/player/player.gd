class_name Player
extends CharacterBody3D
## Spielfigur in Third-Person. Kennt keine Kabel-Logik, meldet nur Absichten per Signal.
## Steuerung: WASD laufen, Shift rennen, Leertaste springen, Maus umsehen, E greifen,
## linke Maustaste ziehen, Q loslassen, Esc Maus freigeben.

signal interact_pressed
signal pull_pressed
signal release_pressed

@onready var _body: Node3D = $Body
@onready var _arm: Node3D = $Body/UpperArmL/WrapArm
@onready var _arm_l: Node3D = $Body/UpperArmL
@onready var _arm_r: Node3D = $Body/ArmR
@onready var _leg_l: Node3D = $Body/LegL
@onready var _leg_r: Node3D = $Body/LegR
@onready var _yaw: Node3D = $CameraYaw
@onready var _pitch: Node3D = $CameraYaw/CameraPitch
@onready var _spring: SpringArm3D = $CameraYaw/CameraPitch/SpringArm3D
@onready var camera: Camera3D = $CameraYaw/CameraPitch/SpringArm3D/Camera3D

## Wird von außen gesetzt, solange ein Kabel um den Arm gewickelt wird
var holding := false:
	set(value):
		holding = value
		_update_arm_pose()
## Haltepunkt des Kabels im Haufen und maximale Entfernung davon
var tether_anchor := Vector3.ZERO
## Leine aktiv: nur solange ein Kabel aus dem Haufen am Arm hängt (nicht beim Tragen eines Knäuels)
var tethered := false
## Steht die Figur gerade am Ende der Leine?
var at_tether_limit := false
## Aus, solange z. B. das Tablet offen ist
var input_enabled := true
## Dauerzug-Upgrade: Züge pro Sekunde bei gehaltener Taste (0 = aus)
var auto_pull_rate := 0.0
var _auto_pull_t := 0.0

## Modell der Figur aus Blender (tools/blender/player_designs.py). Es besteht aus Einzelteilen,
## deren Ursprung im Gelenk liegt; jedes Teil wird an den passenden Gelenk-Node gehängt.
## Fehlt die Datei, bleiben die Grundformen aus player.tscn sichtbar.
const MODEL_PATH := "res://assets/models/player/player_hoodie.glb"
## Teil im Modell -> [Gelenk-Node, Grundformen, die es ersetzt]
const MODEL_PARTS := {
	"Body": ["Body", ["Body/Torso", "Body/Head"]],
	"LegL": ["Body/LegL", ["Body/LegL/Mesh"]],
	"LegR": ["Body/LegR", ["Body/LegR/Mesh"]],
	"UpperArmL": ["Body/UpperArmL", ["Body/UpperArmL/Mesh"]],
	"UpperArmR": ["Body/ArmR", ["Body/ArmR/Mesh"]],
	"ForearmL": ["Body/UpperArmL/WrapArm", ["Body/UpperArmL/WrapArm/Forearm", "Body/UpperArmL/WrapArm/Hand"]],
	"ForearmR": ["Body/ArmR/ForearmR", ["Body/ArmR/ForearmR/Mesh", "Body/ArmR/ForearmR/Hand"]],
}

## Geriggtes Modell (Tripo3D, Mixamo-Skelett). Ist es vorhanden, ersetzt es die Einzelteile: die Knochen
## werden per Code gestellt (Laufen, Arme, Wickel-Haltung), der linke Unterarm-Knochen trägt die Kabel-Wicklung.
const RIG_PATH := "res://assets/models/player/tripo/admin_tripo.glb"
## Modell ist ca. 1 m hoch und schaut nach +Z; Spielfigur ist ca. 1,75 m und schaut nach -Z
const RIG_SCALE := 1.75
var _rig: Node3D
var _skel: Skeleton3D
var _anim: PlayerAnimator      # stellt die Knochen (Laufen, Arbeiten mit Kabeln, Seilbahn)
var _wiggle := 0.0             # Wickelzug pro Tastendruck (wird per Tween gesetzt)

var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var _arm_tween: Tween
var _walk_phase := 0.0
## Sprung: kurz vor der Landung gedrückt zählt noch (Puffer), kurz nach der Kante auch (Coyote-Zeit)
var _jump_buffer := 0.0
var _air_time := 0.0
## Tempo-Faktor aus reaktivierten Diensten
var speed_factor := 1.0
## Trägt eine Rolle (rechte Hand)
var carrying := false
## Hält den Kabelsauger (Arme nach vorn)
var tool_hold := false
var _phone: Node3D                # Smartphone in der rechten Hand (Intro)
var _phone_bone := -1
## Griff der Handkurbel, an der gerade gedreht wird (Weltposition)
var crank_point := Vector3.ZERO
var _crank_t := 0.0
var _crank_center := Vector3.ZERO
var _last_body_yaw := 0.0
## Nur für Tests (--anim): Lauftempo bzw. Ziehen gegen die Leine vortäuschen
var debug_speed := 0.0
var debug_strain := false
var debug_no_look := false


func _ready() -> void:
	_spring.add_excluded_object(get_rid())
	if not _apply_rig():
		_apply_model()
	_update_arm_pose()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _unhandled_input(event: InputEvent) -> void:
	if not input_enabled:
		return
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		# Erster Klick fängt die Maus wieder ein und zählt nicht als Zug
		if event is InputEventMouseButton and event.pressed:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
			get_viewport().set_input_as_handled()
		return
	if event is InputEventKey and event.pressed and event.physical_keycode == KEY_ESCAPE:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		return
	if event is InputEventMouseMotion:
		var sens: float = Balancing.player["mouse_sensitivity"]
		_yaw.rotation.y -= event.relative.x * sens
		_pitch.rotation.x = clampf(_pitch.rotation.x - event.relative.y * sens, deg_to_rad(-75), deg_to_rad(35))
	elif event.is_action_pressed("jump", false):
		jump()
	elif event.is_action_pressed("pull", false):
		pull_pressed.emit()
		_wiggle_arm()
	elif event.is_action_pressed("interact", false):
		interact_pressed.emit()
	elif event.is_action_pressed("release", false):
		release_pressed.emit()


## Hängt an der Seilbahn: Bewegung kommt von außen
var riding := false


func _physics_process(delta: float) -> void:
	if riding:
		at_tether_limit = false
		_animate_walk(delta, 0.0, 1.0)
		return
	var p: Dictionary = Balancing.player
	var input := Input.get_vector("move_left", "move_right", "move_forward", "move_back") if input_enabled else Vector2.ZERO
	var dir := (_yaw.global_basis * Vector3(input.x, 0.0, input.y))
	dir.y = 0.0
	dir = dir.normalized()
	var speed: float = p["sprint_speed_m_per_s"] if Input.is_action_pressed("sprint") else p["walk_speed_m_per_s"]
	speed *= speed_factor
	var on_floor := is_on_floor()
	# Am Boden direkt, in der Luft träger lenken
	var accel := float(p.get("ground_accel_m_per_s2", 45.0)) if on_floor else float(p.get("air_accel_m_per_s2", 14.0))
	var flat := Vector2(velocity.x, velocity.z).move_toward(Vector2(dir.x, dir.z) * speed, accel * delta)
	velocity.x = flat.x
	velocity.z = flat.y
	_air_time = 0.0 if on_floor else _air_time + delta
	_jump_buffer = maxf(_jump_buffer - delta, 0.0)
	var g := _gravity * float(p.get("gravity_factor", 1.0))
	if on_floor:
		velocity.y = 0.0
	else:
		velocity.y -= g * delta
	if _jump_buffer > 0.0 and _air_time <= float(p.get("coyote_time_s", 0.1)) and velocity.y <= 0.01:
		velocity.y = sqrt(2.0 * g * float(p.get("jump_height_m", 1.2)))
		_jump_buffer = 0.0
		_air_time = 1.0  # kein zweiter Sprung in der Coyote-Zeit
	move_and_slide()
	# Tempo mit Vorzeichen: rückwärts (z. B. mit Kabel vom Haufen weg) laufen die Beine andersherum
	var ground_speed := Vector2(velocity.x, velocity.z).length()
	if Vector3(velocity.x, 0.0, velocity.z).dot(facing()) < -0.3 * ground_speed:
		ground_speed = -ground_speed
	if debug_speed != 0.0:
		ground_speed = debug_speed
	_animate_walk(delta, ground_speed, float(p["walk_speed_m_per_s"]))

	# Mit Kabel in der Hand: nicht weiter als die Leine vom Haufen weg
	at_tether_limit = false
	if tethered:
		var offset := global_position - tether_anchor
		offset.y = 0.0
		var max_len: float = p["tether_length_m"]
		at_tether_limit = offset.length() > max_len - 0.05 and dir.dot(offset) > 0.0
		if offset.length() > max_len:
			var fixed := tether_anchor + offset.normalized() * max_len
			global_position = Vector3(fixed.x, global_position.y, fixed.z)

	# Körper dreht sich in Laufrichtung; mit Kabel schaut er zum Haufen
	var face := dir
	if tethered:
		face = tether_anchor - global_position
		face.y = 0.0
	elif _crank_t > 0.0 and dir == Vector3.ZERO:
		face = _crank_center - global_position
		face.y = 0.0
	if face.length_squared() > 1e-4:
		var target := atan2(-face.x, -face.z)
		_body.rotation.y = lerp_angle(_body.rotation.y, target, 1.0 - exp(-12.0 * delta))


func _process(delta: float) -> void:
	# Dauerzug: gehaltene Zieh-Taste löst regelmäßig Züge aus
	var holding_key := input_enabled and auto_pull_rate > 0.0 \
		and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and Input.is_action_pressed("pull")
	if not holding_key:
		_auto_pull_t = 0.0
		return
	_auto_pull_t += delta
	var interval := 1.0 / auto_pull_rate
	# Der erste Zug kommt schon vom Tastendruck selbst
	while _auto_pull_t >= interval:
		_auto_pull_t -= interval
		pull_pressed.emit()
		_wiggle_arm()


## Sprung auslösen (wie ein Druck auf die Sprungtaste; auch für Tests)
func jump() -> void:
	_jump_buffer = float(Balancing.player.get("jump_buffer_s", 0.12))


## Strahl durch die Bildschirmmitte (Fadenkreuz): [Ursprung, Richtung]
func aim_ray() -> Array:
	var center := get_viewport().get_visible_rect().size * 0.5
	return [camera.project_ray_origin(center), camera.project_ray_normal(center)]


## Kamera und Körper auf einen Punkt ausrichten (z. B. beim Spawnen)
func look_toward(point: Vector3) -> void:
	var d := point - global_position
	_yaw.rotation.y = atan2(-d.x, -d.z)
	_body.rotation.y = _yaw.rotation.y


## Nur für Tests: Kamera um die Figur drehen (Grad)
func orbit_camera(degrees: float) -> void:
	_yaw.rotation.y += deg_to_rad(degrees)


## Körper in eine Richtung drehen (z. B. Fahrtrichtung der Seilbahn)
func face_direction(d: Vector3) -> void:
	_body.rotation.y = atan2(-d.x, -d.z)


## Blickrichtung des Körpers (waagerecht)
func facing() -> Vector3:
	var f := -_body.global_basis.z
	f.y = 0.0
	return f.normalized()


## Position und Blickrichtung für den Spielstand
func view_state() -> Dictionary:
	return { "position": SaveGame.vec_to(global_position), "yaw": _yaw.rotation.y,
		"pitch": _pitch.rotation.x, "body_yaw": _body.rotation.y }


func set_view_state(d: Dictionary) -> void:
	global_position = SaveGame.vec_from(d.get("position", [0, 0, 0]))
	_yaw.rotation.y = float(d.get("yaw", 0.0))
	_pitch.rotation.x = float(d.get("pitch", -0.5))
	_body.rotation.y = float(d.get("body_yaw", 0.0))


## Globale Lage des Unterarms, um den das Kabel gewickelt wird
## (Ursprung am Ellbogen, Hand Richtung -Z, außen Richtung -X)
func arm_transform() -> Transform3D:
	if _skel == null:
		return _arm.global_transform
	var elbow := _skel.global_transform * _skel.get_bone_global_pose(_anim.bone("fore_l"))
	var hand_dir := elbow.basis.y.normalized()
	var z := -hand_dir
	var x := Vector3.UP.cross(z).normalized()
	var y := z.cross(x).normalized()
	return Transform3D(Basis(x, y, z), elbow.origin)


## Platz Nr. `index` für ein Knäuel am Rücken (Tasche): drei nebeneinander, weitere dahinter
func back_transform(index: int) -> Transform3D:
	var col := index % 3
	var layer := floori(index / 3.0)
	# Der Ring liegt flach in der xz-Ebene; am Rücken hängt er aufrecht, leicht schräg wie umgehängt
	var tilt := Basis(Vector3.RIGHT, PI * 0.5) * Basis(Vector3.UP, (col - 1) * 0.35)
	var local := Transform3D(tilt, Vector3((col - 1) * 0.17, 1.12, 0.3 + layer * 0.1))
	return _body.global_transform * local


## Einfaches Beine- und Armschwingen, Stärke abhängig vom Tempo (Rückfall-Figur aus Einzelteilen);
## beim geriggten Modell stellt der PlayerAnimator die Knochen.
func _animate_walk(delta: float, speed: float, walk_speed: float) -> void:
	if _anim:
		_update_animator(delta, speed)
		return
	_walk_phase += delta * absf(speed) * 2.4
	var amount := clampf(absf(speed) / walk_speed, 0.0, 1.0)
	var swing := sin(_walk_phase) * 0.6 * amount
	var k := 1.0 - exp(-15.0 * delta)
	_leg_l.rotation.x = lerpf(_leg_l.rotation.x, swing, k)
	_leg_r.rotation.x = lerpf(_leg_r.rotation.x, -swing, k)
	_arm_r.rotation.x = lerpf(_arm_r.rotation.x, -swing * 0.8, k)
	# Linker Arm schwingt nur ohne Kabel; mit Kabel bleibt er ruhig
	var left := 0.0 if holding else swing * 0.8
	_arm_l.rotation.x = lerpf(_arm_l.rotation.x, left, k)


## Zustand an den Animator geben und Knochen stellen
func _update_animator(delta: float, speed: float) -> void:
	var p: Dictionary = Balancing.player
	_anim.walk_speed = float(p["walk_speed_m_per_s"]) * speed_factor
	_anim.sprint_speed = float(p["sprint_speed_m_per_s"]) * speed_factor
	_anim.speed = speed
	_anim.on_floor = is_on_floor() or riding
	var yaw := _body.rotation.y
	_anim.turn_rate = wrapf(yaw - _last_body_yaw, -PI, PI) / maxf(delta, 1e-4)
	_last_body_yaw = yaw
	_anim.holding = holding
	_anim.riding = riding
	_anim.carrying = carrying
	_anim.tool_hold = tool_hold
	_anim.straining = at_tether_limit or debug_strain
	_anim.wind = _wiggle
	_anim.look_yaw = 0.0 if debug_no_look else wrapf(_yaw.rotation.y - yaw, -PI, PI)
	_anim.look_pitch = 0.0 if debug_no_look else (_pitch.rotation.x + 0.35) * 0.6
	_crank_t = maxf(_crank_t - delta, 0.0)
	if _crank_t > 0.0:
		var shoulder := _skel.global_transform * _skel.get_bone_global_pose(_anim.bone("arm_r")).origin
		_anim.crank_dir = (_rig.global_basis.orthonormalized().inverse() * (crank_point - shoulder)).normalized()
	else:
		_anim.crank_dir = Vector3.ZERO
	_anim.update(delta)
	if _phone and _phone.visible and _phone_bone >= 0:
		_phone.global_transform = _skel.global_transform * _skel.get_bone_global_pose(_phone_bone)


## Smartphone in die rechte Hand nehmen bzw. wegstecken (Anruf im Intro)
func set_phone(on: bool) -> void:
	if _anim:
		_anim.phoning = on
	if on and _phone == null and _skel:
		var path := "res://assets/models/props/pub/tripo/smartphone.glb"
		if not ResourceLoader.exists(path):
			return
		# Halter folgt dem Hand-Knochen; die Lage setzt _update_animator jedes Bild aus der Knochen-Pose
		# (BoneAttachment3D folgt per Code gesetzten Posen nicht zuverlässig)
		var att := Node3D.new()
		add_child(att)
		_phone_bone = _skel.find_bone("mixamorig_RightHand")
		att.global_transform = _skel.global_transform * _skel.get_bone_global_pose(_phone_bone)
		var model := (load(path) as PackedScene).instantiate() as Node3D
		att.add_child(model)
		# Auf 32 cm Höhe in Weltmaßen bringen (die Spielzeug-Hand ist groß), mittig in die Hand
		var box := ChefView._world_aabb(model)
		model.scale *= 0.32 / maxf(box.size.y, 0.001)
		box = ChefView._world_aabb(model)
		var local_center := att.global_transform.affine_inverse() * box.get_center()
		model.position -= local_center
		# Vor die Faust (in Blickrichtung der Figur) und etwas höher, damit es nicht in der Hand verschwindet
		var basis := att.global_transform.basis
		model.position += basis.inverse() * (facing() * 0.16 + Vector3(0, 0.1, 0))
		_phone = att
	if _phone:
		_phone.visible = on


## Kurze Bewegung abspielen: "tug" (Knoten-Ruck), "reach" (Einstecken), "pickup" (Aufheben)
func act(kind: String) -> void:
	if _anim:
		_anim.trigger(kind)


## An einer Handkurbel drehen: Hand greift den Griff (Weltposition), Körper dreht sich hin
func crank(handle: Vector3, center: Vector3) -> void:
	crank_point = handle
	_crank_center = center
	_crank_t = 0.45


func is_cranking() -> bool:
	return _crank_t > 0.0


## Geriggtes Modell laden und unter den Körper hängen; Grundformen ausblenden. false, wenn es fehlt.
func _apply_rig() -> bool:
	if not ResourceLoader.exists(RIG_PATH):
		return false
	var scene := load(RIG_PATH) as PackedScene
	if scene == null:
		return false
	_rig = scene.instantiate() as Node3D
	var skels := _rig.find_children("*", "Skeleton3D", true, false)
	if skels.is_empty():
		_rig.free()
		return false
	_skel = skels[0]
	# Das Skelett kann im Modell gedreht sein: Basis vom Skelett bis zur Modell-Wurzel aufmultiplizieren
	var chain := Basis()
	var n: Node = _skel
	while n != _rig and n != null:
		if n is Node3D:
			chain = (n as Node3D).transform.basis * chain
		n = n.get_parent()
	_rig.name = "Rig"
	_rig.rotation.y = PI
	_rig.scale = Vector3.ONE * RIG_SCALE
	_anim = PlayerAnimator.new()
	if not _anim.setup(_skel, _rig, chain.orthonormalized().inverse()):
		_rig.free()
		_skel = null
		_anim = null
		return false
	for mi in _body.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).visible = false
	_body.add_child(_rig)
	_last_body_yaw = _body.rotation.y
	_anim.update(0.0)
	return true


func _apply_model() -> void:
	if not ResourceLoader.exists(MODEL_PATH):
		return
	var scene := load(MODEL_PATH) as PackedScene
	if scene == null:
		return
	var model := scene.instantiate()
	for part_name: String in MODEL_PARTS:
		var part := model.find_child(part_name, true, false) as Node3D
		var entry: Array = MODEL_PARTS[part_name]
		var joint := get_node_or_null(String(entry[0])) as Node3D
		if part == null or joint == null:
			push_warning("Figur-Modell: Teil %s fehlt" % part_name)
			continue
		part.owner = null
		part.get_parent().remove_child(part)
		joint.add_child(part)
		# Im Modell liegt der Ursprung im Gelenk; Drehung der Vorschau-Pose verwerfen
		part.transform = Transform3D.IDENTITY
		for old_path: String in entry[1]:
			var old := get_node_or_null(old_path) as Node3D
			if old:
				old.visible = false
	model.free()


func _update_arm_pose() -> void:
	if _arm == null:
		return
	# Mit Kabel: Unterarm waagerecht nach vorn; sonst hängt er leicht angewinkelt herunter
	# (mit Kabel zusätzlich 35° nach außen gedreht, damit das Knäuel neben dem Körper sichtbar ist)
	_arm.rotation = Vector3(0.0, deg_to_rad(35), 0.0) if holding else Vector3(deg_to_rad(-70), 0.0, 0.0)


func _wiggle_arm() -> void:
	if not holding:
		return
	if _skel:
		if _arm_tween:
			_arm_tween.kill()
		_anim.trigger("wind")
		_arm_tween = create_tween()
		_arm_tween.tween_property(self, "_wiggle", 1.0, 0.06)
		_arm_tween.tween_property(self, "_wiggle", 0.0, 0.14)
		return
	# Kleine Wickelbewegung pro Tastendruck
	if _arm_tween:
		_arm_tween.kill()
	_arm_tween = create_tween()
	_arm_tween.tween_property(_arm, "rotation:z", 0.25, 0.06)
	_arm_tween.tween_property(_arm, "rotation:z", 0.0, 0.12)
