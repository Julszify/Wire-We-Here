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
## Beim Tripo-Rig hängt der Oberarm fast ganz am Schulter-Knochen (der Arm-Knochen ist sehr kurz),
## deshalb werden Schulter und Arm gemeinsam ausgerichtet.
const RIG_BONES := { "leg_l": "mixamorig_LeftUpLeg", "leg_r": "mixamorig_RightUpLeg",
	"sh_l": "mixamorig_LeftShoulder", "sh_r": "mixamorig_RightShoulder", "arm_l": "mixamorig_LeftArm",
	"arm_r": "mixamorig_RightArm", "fore_l": "mixamorig_LeftForeArm", "fore_r": "mixamorig_RightForeArm" }
var _rig: Node3D
var _skel: Skeleton3D
var _bone: Dictionary = {}     # Kurzname -> Knochen-Index
var _wiggle := 0.0             # kleine Wickelbewegung des Unterarms (wird per Tween gesetzt)
var _to_skel := Basis()        # Richtungen vom Modell-Raum (+Z vorn, +X links) in den Skelett-Raum

var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var _arm_tween: Tween
var _walk_phase := 0.0
## Sprung: kurz vor der Landung gedrückt zählt noch (Puffer), kurz nach der Kante auch (Coyote-Zeit)
var _jump_buffer := 0.0
var _air_time := 0.0
## Tempo-Faktor aus reaktivierten Diensten
var speed_factor := 1.0


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
	_animate_walk(delta, Vector2(velocity.x, velocity.z).length() if is_on_floor() else 0.0, float(p["walk_speed_m_per_s"]))

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
	var elbow := _skel.global_transform * _skel.get_bone_global_pose(_bone["fore_l"])
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


## Einfaches Beine- und Armschwingen, Stärke abhängig vom Tempo
func _animate_walk(delta: float, speed: float, walk_speed: float) -> void:
	_walk_phase += delta * speed * 2.4
	var amount := clampf(speed / walk_speed, 0.0, 1.0)
	var swing := sin(_walk_phase) * 0.6 * amount
	var k := 1.0 - exp(-15.0 * delta)
	_leg_l.rotation.x = lerpf(_leg_l.rotation.x, swing, k)
	_leg_r.rotation.x = lerpf(_leg_r.rotation.x, -swing, k)
	_arm_r.rotation.x = lerpf(_arm_r.rotation.x, -swing * 0.8, k)
	# Linker Arm schwingt nur ohne Kabel; mit Kabel bleibt er ruhig
	var left := 0.0 if holding else swing * 0.8
	_arm_l.rotation.x = lerpf(_arm_l.rotation.x, left, k)
	if _skel:
		_pose_rig()


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
	for key: String in RIG_BONES:
		_bone[key] = _skel.find_bone(String(RIG_BONES[key]))
		if int(_bone[key]) < 0:
			push_warning("Figur-Skelett: Knochen %s fehlt" % RIG_BONES[key])
			_rig.free()
			_skel = null
			return false
	# Das Skelett kann im Modell gedreht sein: Basis vom Skelett bis zur Modell-Wurzel aufmultiplizieren
	var chain := Basis()
	var n: Node = _skel
	while n != _rig and n != null:
		if n is Node3D:
			chain = (n as Node3D).transform.basis * chain
		n = n.get_parent()
	_to_skel = chain.orthonormalized().inverse()
	_rig.name = "Rig"
	_rig.rotation.y = PI
	_rig.scale = Vector3.ONE * RIG_SCALE
	for mi in _body.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).visible = false
	_body.add_child(_rig)
	_pose_rig()
	return true


## Knochen so drehen, dass ihre Längsachse (Y) in `dir` zeigt (Richtung im Modell-Raum: +Z vorn, +X links)
func _aim_bone(bone: int, dir: Vector3) -> void:
	var rest := _skel.get_bone_global_rest(bone)
	var q := Quaternion(rest.basis.y.normalized(), (_to_skel * dir).normalized())
	var want := Basis(q) * rest.basis
	var parent := _skel.get_bone_parent(bone)
	var parent_basis := _skel.get_bone_global_pose(parent).basis if parent >= 0 else Basis.IDENTITY
	_skel.set_bone_pose_rotation(bone, Quaternion((parent_basis.inverse() * want).orthonormalized()))


## Pose aus Laufen und Haltung: Beine und Arme schwingen, Arme hängen am Körper, mit Kabel zeigt der
## linke Unterarm waagerecht nach vorn (leicht nach außen), damit das Kabel darum gewickelt werden kann.
func _pose_rig() -> void:
	var swing := _leg_l.rotation.x  # Schwung aus _animate_walk (Bogenmaß)
	var arm_swing := _arm_r.rotation.x
	_aim_bone(_bone["leg_l"], Vector3(0.05, -cos(swing), -sin(swing)))
	_aim_bone(_bone["leg_r"], Vector3(-0.05, -cos(swing), sin(swing)))
	# Arme nur mäßig absenken: bei steilerem Winkel verschwindet der Oberarm im runden Bauch
	var up_r := Vector3(-0.6, -0.8 * cos(arm_swing), -0.8 * sin(arm_swing))
	_aim_bone(_bone["sh_r"], up_r)
	_aim_bone(_bone["arm_r"], up_r)
	_aim_bone(_bone["fore_r"], Vector3(-0.35, -0.85, 0.3 - sin(arm_swing) * 0.5))
	if riding:
		# An der Seilbahn: beide Arme nach oben zum Laufwagen
		for side in [["sh_l", "arm_l", "fore_l", 1.0], ["sh_r", "arm_r", "fore_r", -1.0]]:
			var up := Vector3(0.25 * float(side[3]), 1.0, 0.05)
			_aim_bone(_bone[side[0]], up)
			_aim_bone(_bone[side[1]], up)
			_aim_bone(_bone[side[2]], Vector3(-0.1 * float(side[3]), 1.0, 0.0))
	elif holding:
		_aim_bone(_bone["sh_l"], Vector3(0.62, -0.75, 0.2))
		_aim_bone(_bone["arm_l"], Vector3(0.62, -0.75, 0.2))
		var fwd := Vector3(sin(deg_to_rad(30)), 0.08 + _wiggle, cos(deg_to_rad(30)))
		_aim_bone(_bone["fore_l"], fwd)
	else:
		var left_swing := _arm_l.rotation.x
		var up_l := Vector3(0.6, -0.8 * cos(left_swing), 0.8 * sin(left_swing))
		_aim_bone(_bone["sh_l"], up_l)
		_aim_bone(_bone["arm_l"], up_l)
		_aim_bone(_bone["fore_l"], Vector3(0.35, -0.85, 0.3 + sin(left_swing) * 0.5))


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
		_arm_tween = create_tween()
		_arm_tween.tween_property(self, "_wiggle", 0.35, 0.06)
		_arm_tween.tween_property(self, "_wiggle", 0.0, 0.12)
		return
	# Kleine Wickelbewegung pro Tastendruck
	if _arm_tween:
		_arm_tween.kill()
	_arm_tween = create_tween()
	_arm_tween.tween_property(_arm, "rotation:z", 0.25, 0.06)
	_arm_tween.tween_property(_arm, "rotation:z", 0.0, 0.12)
