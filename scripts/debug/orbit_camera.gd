extends Node3D
## Einfache Orbit-Kamera für Testszenen.
## Rechte Maustaste halten + ziehen: drehen
## Mittlere Maustaste halten + ziehen: verschieben
## Mausrad: zoomen
## Wird später durch die Third-Person-Kamera der Spielfigur ersetzt.

@export var distance: float = 8.0
@export var min_distance: float = 1.5
@export var max_distance: float = 40.0
@export var yaw_deg: float = 35.0
@export var pitch_deg: float = -30.0
@export var rotate_speed: float = 0.25
@export var pan_speed: float = 0.01
@export var zoom_step: float = 1.1

@onready var _camera: Camera3D = $Camera3D

var _rotating := false
var _panning := false


func _ready() -> void:
	_apply_transform()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		match event.button_index:
			MOUSE_BUTTON_RIGHT:
				_rotating = event.pressed
			MOUSE_BUTTON_MIDDLE:
				_panning = event.pressed
			MOUSE_BUTTON_WHEEL_UP:
				if event.pressed:
					distance = max(min_distance, distance / zoom_step)
			MOUSE_BUTTON_WHEEL_DOWN:
				if event.pressed:
					distance = min(max_distance, distance * zoom_step)
		_apply_transform()
	elif event is InputEventMouseMotion:
		if _rotating:
			yaw_deg -= event.relative.x * rotate_speed
			pitch_deg = clamp(pitch_deg - event.relative.y * rotate_speed, -85.0, -5.0)
			_apply_transform()
		elif _panning:
			# Verschieben in der Bodenebene, relativ zur Blickrichtung
			var right := global_basis.x
			var forward := Vector3(global_basis.z.x, 0.0, global_basis.z.z).normalized()
			var pan_scale := pan_speed * distance * 0.1
			global_position += (-right * event.relative.x + -forward * event.relative.y) * pan_scale
			_apply_transform()


func _apply_transform() -> void:
	rotation_degrees = Vector3(pitch_deg, yaw_deg, 0.0)
	_camera.position = Vector3(0.0, 0.0, distance)
