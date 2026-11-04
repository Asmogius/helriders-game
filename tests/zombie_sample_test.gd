extends SceneTree
## V3 style sample: Shambler and Tank voxel sheets, poses, fallback.

const Zombie := preload("res://scripts/zombie.gd")
var fails := 0


func check(ok: bool, msg: String) -> void:
	if not ok:
		fails += 1
		printerr("FAIL: ", msg)


func _init() -> void:
	_run.call_deferred()


func _z(kind: String) -> Node2D:
	var z: Node2D = Zombie.new()
	root.add_child(z)
	z.activate(Vector2.ZERO, kind)
	return z


func _run() -> void:
	var meta := Zombie.art_atlas()
	if not meta.is_empty():
		var s := _z("shambler")
		check(s.has_art(), "shambler has art")
		var kinds: Dictionary = meta.kinds
		check(int(kinds.shambler.variants) == 6, "6 Shambler variants")
		check((kinds.shambler.rows as Dictionary).has(s.art_row()), "shambler row exists: " + s.art_row())
		for v in 6:
			for pose in ["walk_0", "walk_3", "lunge_0", "lunge_1"]:
				check((kinds.shambler.rows as Dictionary).has("v%d_%s" % [v, pose]), "row v%d_%s" % [v, pose])
		s.rotation = 5 * TAU / 16.0
		check(s.art_heading() == 5, "heading frame follows rotation")
		s._flash = 1.0
		check(s.art_row() == "flash", "hit flash row")
		var t := _z("tank")
		check(t.has_art() and t.art_row().begins_with("walk_"), "tank walks")
		t.charge = Zombie.Charge.WINDUP
		check(t.art_row().begins_with("roar_"), "tank roars in the wind-up")
		t.charge = Zombie.Charge.CHARGE
		check(t.art_row() == "charge", "tank charge pose")
		t.charge = Zombie.Charge.STUMBLE
		check(t.art_row() == "stumble", "tank stumble pose")
		var b := _z("brute")
		check(not b.has_art(), "brute keeps the code-drawn body (not in the sample)")
		check(int(kinds.tank.frame_w) > int(kinds.shambler.frame_w) * 1.6, "tank about 2x the shambler")
		check(s.radius == 13.0 and t.radius == 25.0, "hit circles unchanged")
	# Fallback: no atlas -> code-drawn, no error.
	Zombie._art_meta = {}
	Zombie._art_tried = true
	var f := _z("shambler")
	check(not f.has_art(), "fallback without the atlas")
	f.queue_redraw()
	Zombie._art_tex = null
	print("ZOMBIE SAMPLE TEST ", "PASSED" if fails == 0 else "FAILED (%d)" % fails)
	quit(1 if fails else 0)
