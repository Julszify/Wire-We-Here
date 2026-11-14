class_name Player
extends CharacterBody3D
## Spielfigur in Third-Person. Kennt keine Kabel-Logik, meldet nur Absichten per Signal.
## Steuerung: WASD laufen, Shift rennen, Maus umsehen, E greifen,
## Leertaste/linke Maustaste ziehen, Q loslassen, Esc Maus freigeben.

signal interact_pressed
signal pull_pressed
signal release_pressed

@onready var _body: Node3D = $Body
@onready var _arm: Node3D = $Body/WrapArm
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

var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var _arm_tween: Tween


func _ready() -> void:
	_spring.add_excluded_object(get_rid())
	_update_arm_pose()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _unhandled_input(event: InputEvent) -> void:
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
	var input := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var dir := (_yaw.global_basis * Vector3(input.x, 0.0, input.y))
	dir.y = 0.0
	dir = dir.normalized()
	var speed: float = p["sprint_speed_m_per_s"] if Input.is_action_pressed("sprint") else p["walk_speed_m_per_s"]
	velocity.x = dir.x * speed
	velocity.z = dir.z * speed
	velocity.y = 0.0 if is_on_floor() else velocity.y - _gravity * delta
	move_and_slide()

	# Mit Kabel in der Hand: nicht weiter als die Leine vom Haufen weg
	if holding:
		var offset := global_position - tether_anchor
		offset.y = 0.0
		var max_len: float = p["tether_length_m"]
		if offset.length() > max_len:
			var fixed := tether_anchor + offset.normalized() * max_len
			global_position = Vector3(fixed.x, global_position.y, fixed.z)

	# Körper dreht sich in Laufrichtung; mit Kabel schaut er zum Haufen
	var face := dir
	if holding:
		face = tether_anchor - global_position
		face.y = 0.0
	if face.length_squared() > 1e-4:
		var target := atan2(-face.x, -face.z)
		_body.rotation.y = lerp_angle(_body.rotation.y, target, 1.0 - exp(-12.0 * delta))


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


## Globale Lage des Unterarms, um den das Kabel gewickelt wird
func arm_transform() -> Transform3D:
	return _arm.global_transform


func _update_arm_pose() -> void:
	if _arm == null:
		return
	# Mit Kabel: Unterarm waagerecht nach vorn; sonst hängt er herunter
	_arm.rotation.x = 0.0 if holding else deg_to_rad(-80)


func _wiggle_arm() -> void:
	if not holding:
		return
	# Kleine Wickelbewegung pro Tastendruck
	if _arm_tween:
		_arm_tween.kill()
	_arm_tween = create_tween()
	_arm_tween.tween_property(_arm, "rotation:z", 0.25, 0.06)
	_arm_tween.tween_property(_arm, "rotation:z", 0.0, 0.12)
