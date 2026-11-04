extends SceneTree
## The garage shows the rig at RIG_SCALE (3.4x). Voxel art sprites are
## top_level, so they must copy the rig's scale and scale their offsets by it.

var fails := 0


func check(ok: bool, msg: String) -> void:
	if not ok:
		fails += 1
		printerr("FAIL: ", msg)


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var profile: Node = root.get_node("/root/Profile")
	profile.persist = false
	profile.new_game()
	change_scene_to_file("res://scenes/garage.tscn")
	for i in 10:
		await process_frame
	var g: Node = current_scene
	var v: Node2D = g.get("preview")
	check(v != null, "garage has a rig preview")
	if v != null:
		var sc := absf(v.global_scale.x)
		check(sc > 2.0, "preview is shown scaled up (%.2f)" % sc)
		var hull: Sprite2D = v.get("_hull_art")
		if hull == null:
			print("preview_scale_test: no hull art on this rig, scale check skipped")
		else:
			v.call("_update_art")
			var hp: float = hull.call("ppv") if hull.has_method("ppv") else 1.0
			check(is_equal_approx(hull.scale.x * hp, sc), "hull art copies the rig scale / px-per-voxel (%.2f x %.1f vs %.2f)" % [hull.scale.x, hp, sc])
			for t: Node2D in v.get("_turrets"):
				if t == null:
					continue
				var a: Variant = t.get("art")
				if a != null:
					var tp: float = a.call("ppv") if a.has_method("ppv") else 1.0
					check(is_equal_approx(a.scale.x * tp, sc), "turret art copies the rig scale / px-per-voxel")
	print("PREVIEW SCALE TEST ", "PASSED" if fails == 0 else "FAILED (%d)" % fails)
	quit(1 if fails else 0)
