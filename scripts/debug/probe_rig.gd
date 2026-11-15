extends SceneTree
## Gibt Knochen und Größe eines geriggten Modells aus (nur zur Untersuchung):
## godot --headless -s res://scripts/debug/probe_rig.gd -- res://assets/models/player/tripo/admin_tripo.glb

func _init() -> void:
	var path := OS.get_cmdline_user_args()[0]
	var root := (load(path) as PackedScene).instantiate()
	get_root().add_child(root)
	await process_frame
	var sk := root.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	print("SKELETON ", root.get_path_to(sk), " bones=", sk.get_bone_count(), " scale=", sk.global_transform.basis.get_scale())
	for i in sk.get_bone_count():
		var n := sk.get_bone_name(i)
		if n.contains("Hand") and not n.ends_with("Hand"):
			continue
		var g := sk.global_transform * sk.get_bone_global_rest(i)
		print("BONE %2d %-28s parent=%2d pos=%s y=%s" % [i, n, sk.get_bone_parent(i), str(g.origin.snapped(Vector3.ONE * 0.001)),
			str(g.basis.y.snapped(Vector3.ONE * 0.01))])
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		print("MESH ", mi.name, " aabb=", (mi as MeshInstance3D).get_aabb())
	quit()
