class_name Waypoint
extends Control
## Wegweiser oben am Bildschirm: Pfeil in Richtung Ziel (relativ zur Kamera) und Entfernung.

var target := Vector3.ZERO
var label := ""
var camera: Camera3D
var _dist := 0.0


func _ready() -> void:
	set_anchors_preset(Control.PRESET_CENTER_TOP)
	offset_left = -150
	offset_right = 150
	offset_top = 100
	offset_bottom = 170
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(_delta: float) -> void:
	if visible:
		queue_redraw()


func _draw() -> void:
	if camera == null:
		return
	var to := target - camera.global_position
	_dist = Vector2(to.x, to.z).length()
	var fwd := -camera.global_basis.z
	var a := atan2(to.x, -to.z) - atan2(fwd.x, -fwd.z)
	var c := Vector2(size.x * 0.5, 22)
	var dir := Vector2(sin(a), -cos(a))
	var side := dir.orthogonal()
	var tip := c + dir * 18.0
	var pts := PackedVector2Array([tip, c - dir * 12.0 + side * 12.0, c - dir * 5.0, c - dir * 12.0 - side * 12.0])
	# Runde Plakette mit Pfeil, darunter Ziel und Entfernung als Pille
	draw_circle(c + Vector2(0, 3), 27.0, Color(0.05, 0.08, 0.15, 0.3))
	draw_circle(c, 26.0, UiTheme.GREEN_DARK)
	draw_circle(c + Vector2(0, -2), 24.0, UiTheme.GREEN)
	draw_colored_polygon(pts, Color.WHITE)
	var font := UiTheme.font()
	var text := "%s · %d m" % [label, roundi(_dist)]
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 19).x
	var pill := Rect2((size.x - w) * 0.5 - 14.0, 50.0, w + 28.0, 30.0)
	draw_style_box(UiTheme.hud_box(Color(0.1, 0.13, 0.22, 0.72), 15), pill)
	draw_string(font, Vector2((size.x - w) * 0.5, 71), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 19, Color.WHITE)
