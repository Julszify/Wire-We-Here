class_name Crosshair
extends Control
## Fadenkreuz in der Bildschirmmitte. Wird zur Hand, wenn ein Kabelende anvisiert ist.

var targeting := false:
	set(value):
		if value != targeting:
			targeting = value
			queue_redraw()


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	var c := size * 0.5
	var outline := Color(0, 0, 0, 0.6)
	if not targeting:
		for o in [outline, Color.WHITE]:
			var w := 4.0 if o == outline else 2.0
			draw_line(c + Vector2(-9, 0), c + Vector2(9, 0), o, w)
			draw_line(c + Vector2(0, -9), c + Vector2(0, 9), o, w)
		return
	# Einfache Hand: Handfläche, vier Finger, Daumen
	var skin := Color(1.0, 0.85, 0.3)
	var parts: Array[Rect2] = [
		Rect2(c + Vector2(-11, -2), Vector2(22, 16)),   # Handfläche
		Rect2(c + Vector2(-11, -15), Vector2(5, 14)),   # Finger
		Rect2(c + Vector2(-5, -18), Vector2(5, 17)),
		Rect2(c + Vector2(1, -17), Vector2(5, 16)),
		Rect2(c + Vector2(7, -13), Vector2(4, 12)),
		Rect2(c + Vector2(-17, 0), Vector2(7, 5)),      # Daumen
	]
	for r in parts:
		draw_rect(r.grow(2), outline)
	for r in parts:
		draw_rect(r, skin)
