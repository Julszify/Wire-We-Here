class_name Detector
extends Control
## Kabel-Detektor unten rechts: ein Kreis pulsiert schneller und wird von Blau über Orange zu Rot, je näher
## das nächste wichtige Kabel im Haufen ist (warm/kalt). Mit dem Upgrade „Peilantenne“ zeigt ein Pfeil die
## Richtung und die Entfernung. Werte in balancing.json → detector. Die Hauptszene setzt Ziel und Abstand.

var camera: Camera3D
## Nächstes wichtiges Kabelende (gültig, wenn has_target)
var target := Vector3.ZERO
var has_target := false
var distance := INF
var show_arrow := false
var _t := 0.0


func _ready() -> void:
	set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	offset_left = -300
	offset_right = -20
	offset_top = -190
	offset_bottom = -90
	mouse_filter = Control.MOUSE_FILTER_IGNORE


## 0 = kalt (nichts in Reichweite) … 1 = direkt davor
func signal_strength() -> float:
	if not has_target:
		return 0.0
	var range_m := float(Balancing.detector.get("range_m", 80.0))
	return clampf(1.0 - distance / range_m, 0.0, 1.0)


func _process(delta: float) -> void:
	var s := signal_strength()
	_t += delta * lerpf(0.5, 7.0, s * s)
	queue_redraw()


func _draw() -> void:
	var s := signal_strength()
	var c := Vector2(48, 50)
	var cold := Color(0.35, 0.6, 1.0)
	var warm := Color(1.0, 0.65, 0.2)
	var hot := Color(1.0, 0.25, 0.2)
	var col := cold.lerp(warm, clampf(s * 2.0, 0.0, 1.0)).lerp(hot, clampf(s * 2.0 - 1.0, 0.0, 1.0))
	var pulse := 0.5 + 0.5 * sin(_t * TAU)
	draw_circle(c, 40.0, Color(0.05, 0.08, 0.15, 0.3))  # Schatten
	draw_circle(c + Vector2(0, -3), 37.0, UiTheme.PAPER)
	draw_circle(c, 34.0, Color(0.1, 0.13, 0.22, 0.85))
	draw_circle(c, 14.0 + 16.0 * pulse * (0.3 + 0.7 * s), Color(col, 0.35 + 0.4 * s))
	draw_circle(c, 10.0, col)
	draw_arc(c, 34.0, 0.0, TAU, 40, Color(col, 0.9), 3.0)
	var word := "kalt"
	if s > 0.75:
		word = "heiß!"
	elif s > 0.45:
		word = "warm"
	elif s > 0.0:
		word = "lau"
	var text := "Detektor: " + word
	if show_arrow and has_target:
		text += "\n%d m" % roundi(distance)
	var font := UiTheme.font()
	var lines := text.split("\n")
	for i in lines.size():
		var at := Vector2(94, 46 + i * 24)
		draw_string_outline(font, at, lines[i], HORIZONTAL_ALIGNMENT_LEFT, -1, 20, 7, Color(0.08, 0.1, 0.18))
		draw_string(font, at, lines[i], HORIZONTAL_ALIGNMENT_LEFT, -1, 20, col.lightened(0.35))
	if show_arrow and has_target and camera:
		# Pfeil um den Kreis herum, in Richtung des Kabels (relativ zur Blickrichtung)
		var to := target - camera.global_position
		var fwd := -camera.global_basis.z
		var a := atan2(to.x, -to.z) - atan2(fwd.x, -fwd.z)
		var dir := Vector2(sin(a), -cos(a))
		var side := dir.orthogonal()
		var tip := c + dir * 46.0
		draw_colored_polygon(PackedVector2Array([tip, c + dir * 34.0 + side * 9.0, c + dir * 34.0 - side * 9.0]), col)
