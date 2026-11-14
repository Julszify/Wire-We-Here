class_name Player
extends CharacterBody3D
## Spielfigur in Third-Person. Kennt keine Kabel-Logik, meldet nur Absichten per Signal.
## Steuerung: WASD laufen, Shift rennen, Maus umsehen, E greifen,
## Leertaste/linke Maustaste ziehen, Q loslassen, Esc Maus freigeben.

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

var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var _arm_tween: Tween
var _walk_phase := 0.0


func _ready() -> void:
	_spring.add_excluded_object(get_rid())
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
	elif event.is_action_pressed("pull", false):
		pull_pressed.emit()
		_wiggle_arm()
	elif event.is_action_pressed("interact", false):
		interact_pressed.emit()
	elif event.is_action_pressed("release", false):
		release_pressed.emit()


func _physics_process(delta: float) -> void:
	var p: Dictionary = Balancing.player
	var input := Input.get_vector("move_left", "move_right", "move_forward", "move_back") if input_enabled else Vector2.ZERO
	var dir := (_yaw.global_basis * Vector3(input.x, 0.0, input.y))
	dir.y = 0.0
	dir = dir.normalized()
	var speed: float = p["sprint_speed_m_per_s"] if Input.is_action_pressed("sprint") else p["walk_speed_m_per_s"]
	velocity.x = dir.x * speed
	velocity.z = dir.z * speed
	velocity.y = 0.0 if is_on_floor() else velocity.y - _gravity * delta
	move_and_slide()
	_animate_walk(delta, Vector2(velocity.x, velocity.z).length(), float(p["walk_speed_m_per_s"]))

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
func arm_transform() -> Transform3D:
	return _arm.global_transform


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


func _update_arm_pose() -> void:
	if _arm == null:
		return
	# Mit Kabel: Unterarm waagerecht nach vorn; sonst hängt er leicht angewinkelt herunter
	# (mit Kabel zusätzlich 35° nach außen gedreht, damit das Knäuel neben dem Körper sichtbar ist)
	_arm.rotation = Vector3(0.0, deg_to_rad(35), 0.0) if holding else Vector3(deg_to_rad(-70), 0.0, 0.0)


func _wiggle_arm() -> void:
	if not holding:
		return
	# Kleine Wickelbewegung pro Tastendruck
	if _arm_tween:
		_arm_tween.kill()
	_arm_tween = create_tween()
	_arm_tween.tween_property(_arm, "rotation:z", 0.25, 0.06)
	_arm_tween.tween_property(_arm, "rotation:z", 0.0, 0.12)
