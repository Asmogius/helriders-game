extends SceneTree
## Headless check of the voxel sprite sheets: loads each sheet's metadata,
## checks texture size against the frame grid, and that DirectionalSprite
## picks the right frame for all 32 headings (with jitter, negatives, wrap).

const DS := preload("res://scripts/directional_sprite.gd")
var fails := 0


func check(ok: bool, msg: String) -> void:
	if not ok:
		fails += 1
		printerr("FAIL: ", msg)


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	for name in ["scrap_frame", "outrider", "pintle_turret"]:
		var path := "res://art/sprites/%s.json" % name
		var s: Sprite2D = DS.new()
		s.meta_path = path
		root.add_child(s)
		check(s.load_meta(path), name + ": meta loads")
		check(s.texture != null, name + ": texture loads")
		if s.texture == null:
			continue
		var m: Dictionary = s.meta
		check(int(m.directions) == 32, name + ": 32 directions")
		check(s.texture.get_width() == int(m.frame_w) * int(m.columns), name + ": sheet width")
		check(s.texture.get_height() == int(m.frame_h) * int(ceil(float(m.directions) / m.columns)), name + ": sheet height")
		check(s.texture_filter == CanvasItem.TEXTURE_FILTER_NEAREST, name + ": nearest filter")
		var step := TAU / 32.0
		for i in 32:
			for jitter in [0.0, step * 0.49, -step * 0.49]:
				s.heading = i * step + jitter
				check(s.frame == i, "%s: heading %d%+.2f -> frame %d" % [name, i, jitter, s.frame])
				s.heading = i * step + jitter - TAU * 3.0
				check(s.frame == i, "%s: wrapped heading %d -> frame %d" % [name, i, s.frame])
		for chunk in m.chunks:
			check(s.chunk_texture(chunk) != null, name + ": chunk sheet " + chunk)
			check((m.chunks[chunk].offsets as Array).size() == 32, name + ": offsets " + chunk)
			s.heading = 0.0
			s.chunk_offset(chunk)
	_check_points()
	_check_vehicle()
	print("art_sheet_test: ", "PASS" if fails == 0 else "%d FAILURES" % fails)
	quit(1 if fails else 0)


## Mount points: 32 offsets each; the hull's turret mount turns with the rig
## (same distance from centre in x at headings 0 and 180, mirrored), and the
## projection lifts raised points up the screen.
func _check_points() -> void:
	var hull: Sprite2D = DS.new()
	check(hull.load_meta("res://art/sprites/scrap_frame.json"), "hull meta")
	var tur: Sprite2D = DS.new()
	check(tur.load_meta("res://art/sprites/pintle_turret.json"), "turret meta")
	check(hull.meta.has("points") and (hull.meta.points.turret_mount as Array).size() == 32, "hull: 32 turret_mount offsets")
	check(tur.meta.has("points") and (tur.meta.points.pivot as Array).size() == 32, "turret: 32 pivot offsets")
	var m0: Vector2 = hull.point_offset("turret_mount", 0)
	var m16: Vector2 = hull.point_offset("turret_mount", 16)
	check(is_equal_approx(m0.x, -m16.x), "mount mirrors x at 180 degrees: %s %s" % [m0, m16])
	check(m0.x < 0.0, "mount sits behind centre at heading 0: %s" % m0)
	for i in 32:
		hull.heading = i * TAU / 32.0
		check(hull.point_offset("turret_mount") == hull.point_offset("turret_mount", i), "point_offset follows frame %d" % i)
	check(hull.point_offset("nope") == Vector2.ZERO, "unknown point is zero")
	hull.free()
	tur.free()


## The starter rig wears the Scrap Frame sheet and its turret sits on the
## projected mount; gameplay pivot is unchanged.
func _check_vehicle() -> void:
	var Vehicle := load("res://scripts/vehicle.gd")
	var Loadout := load("res://scripts/loadout.gd")
	var Parts := load("res://scripts/parts.gd")
	var v: Node2D = Vehicle.new()
	root.add_child(v)
	v.apply_stats(Loadout.build(Parts.STARTER_LOADOUT))
	check(v._hull_art != null, "starter rig has hull art")
	check(v._turret != null and v._turret.art != null, "starter turret has art")
	if v._hull_art == null or v._turret == null or v._turret.art == null:
		return
	for i in 32:
		v.rotation = i * TAU / 32.0
		v._turret.rotation = 0.7
		v._update_art()
		check(v._hull_art.frame == i, "hull frame %d at heading %d" % [v._hull_art.frame, i])
		var a: Sprite2D = v._turret.art
		check(a.frame == DS.frame_for(v._turret.global_rotation, 32), "turret frame follows aim at %d" % i)
		var want: Vector2 = v.global_position + v._hull_art.point_offset("turret_mount") - a.point_offset("pivot")
		check(a.global_position.distance_to(want) < 0.01, "turret art on mount at %d" % i)
	check(v._turret.position == v.turret_position(0, 1), "gameplay turret pivot unchanged")
	v.queue_free()
