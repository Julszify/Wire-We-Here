class_name FloatText
extends Label3D
## Schwebender Text in der Welt (z. B. "+12,50 €"), steigt auf und verblasst.


static func spawn(parent: Node, pos: Vector3, text_value: String, color := Color(1.0, 0.9, 0.3)) -> void:
	var t := FloatText.new()
	t.text = text_value
	t.modulate = color
	t.outline_modulate = Color(0, 0, 0, 0.8)
	t.font_size = 72
	t.outline_size = 14
	t.pixel_size = 0.004
	t.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	t.no_depth_test = true
	parent.add_child(t)
	t.global_position = pos
	var tw := t.create_tween().set_parallel()
	tw.tween_property(t, "global_position", pos + Vector3(0, 1.0, 0), 1.4).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tw.tween_property(t, "modulate:a", 0.0, 1.4).set_ease(Tween.EASE_IN)
	tw.chain().tween_callback(t.queue_free)
