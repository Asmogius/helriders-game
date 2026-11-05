extends SceneTree
## V3 style sample: Shambler and Tank voxel sheets, poses, fallback.

const Zombie := preload("res://scripts/zombie.gd")
const Hunter := preload("res://scripts/hunter.gd")
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
		check(int(kinds.shambler.variants) == 3, "3 Shambler variants")
		check((kinds.shambler.rows as Dictionary).has(s.art_row()), "shambler row exists: " + s.art_row())
		for v in 3:
			for pose in ["walk_0", "walk_3", "lunge_0", "lunge_1"]:
				check((kinds.shambler.rows as Dictionary).has("v%d_%s" % [v, pose]), "row v%d_%s" % [v, pose])
		check(not (kinds.shambler.rows as Dictionary).has("v3_walk_0"), "no fourth shambler look")
		s.art_variant = 5
		check(s.art_row().begins_with("v2_"), "variant 5 wraps to v2 (5 mod 3)")
		s.art_variant = 3
		check(s.art_row().begins_with("v0_"), "variant 3 wraps to v0")
		s.art_variant = 4
		check(s.art_row().begins_with("v1_"), "variant 4 wraps to v1")
		s.art_variant = -1
		check(s.art_pose_index() < 16, "shambler pose index fits the redraw key")
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
		check(int(kinds.tank.frame_w) > int(kinds.shambler.frame_w) * 1.6, "tank about 2x the shambler")
		check(t.art_pose_index() < 16, "tank pose index fits the redraw key")
		for kind in ["brute", "slimer", "boomer"]:
			var z := _z(kind)
			check(z.has_art(), kind + " has art")
			check((kinds[kind].rows as Dictionary).has(z.art_row()), kind + " row " + z.art_row())
			check(z.art_pose_index() < 16, kind + " pose index fits the redraw key")
		var hunter := Hunter.new()
		root.add_child(hunter)
		hunter.activate(Vector2.ZERO)
		check(hunter.has_art(), "hunter has art")
		check(hunter._art_row().begins_with("walk_"), "hunter walks")
		hunter.state = Hunter.State.WINDUP
		check(hunter._art_row() == "windup", "hunter windup pose")
		hunter.state = Hunter.State.POUNCE
		check(hunter._art_row() == "pounce", "hunter pounce pose")
		hunter._sheet_flash = 1.0
		check(hunter._art_row() == "flash", "hunter hit flash")
		check(s.radius == 13.0 and t.radius == 25.0, "hit circles unchanged")
		s.highlight = true
		s.queue_redraw()
	# Fallback: no atlas -> code-drawn, no error.
	Zombie.disable_art()
	var f := _z("shambler")
	check(not f.has_art(), "fallback without the atlas")
	f.queue_redraw()
	print("ZOMBIE SAMPLE TEST ", "PASSED" if fails == 0 else "FAILED (%d)" % fails)
	quit(1 if fails else 0)
