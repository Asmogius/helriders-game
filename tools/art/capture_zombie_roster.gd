extends SceneTree
## Day / night fight lineup of the zombie roster, for before/after sheets.
##   xvfb-run -s "-screen 0 1280x720x24" godot --path . --rendering-driver opengl3 \
##     -s res://tools/art/capture_zombie_roster.gd -- out.png day|night [tutorial]
## Night multiplies the world and each zombie by the same grade NightGrade.grade_for
## uses for #2a3550 (day average #60594f). The sheet itself stays day-authored.

const Zombie := preload("res://scripts/zombie.gd")

var _frames := 0
var _out := "user://zombie_roster.png"
var _night := false
var _tutorial := false
var _m: Node


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_out = args[0]
	_night = args.size() > 1 and args[1] == "night"
	_tutorial = args.size() > 2 and args[2] == "tutorial"
	var profile := root.get_node_or_null("Profile")
	if profile != null:
		profile.set("persist", false)
		profile.call("new_game")
	change_scene_to_file.call_deferred("res://scenes/mission.tscn")


func _grade() -> Color:
	# NightGrade.grade_for(Color8(0x2a, 0x35, 0x50)) against day average #60594f.
	var night := Color8(0x2a, 0x35, 0x50)
	var day := Color8(0x60, 0x59, 0x4f)
	return Color(minf(night.r / day.r, 1.0), minf(night.g / day.g, 1.0), minf(night.b / day.b, 1.0))


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames == 45:
		_m = current_scene
		if _m == null:
			push_error("mission scene missing")
			quit(1)
			return true
		_m.set("auto_spawn_specials", false)
		_m.zombies.set_physics_process(false)
		_m.zombies.spawn_budget = 0
		_m.zombies.cap = 0
		_m.zombies.clear_all()
		(_m.hud as CanvasLayer).visible = false
		(_m.hazards as Node).visible = false
		(_m.splats as Node).visible = false
		(_m.fx as Node).visible = false
		_m.vehicle.set_physics_process(false)
		_m.vehicle.velocity = Vector2.ZERO
		var cam: Node = _m.camera
		cam.set("base_zoom", 2.2)
		cam.set("speed_zoom", 2.2)
		cam.set("zoom", Vector2(2.2, 2.2))
		var p: Vector2 = _m.vehicle.global_position
		var grade := _grade()
		if _night:
			_m.arena.modulate = grade
		var lineup: Array[String] = ["shambler", "shambler", "shambler", "slimer", "hunter", "brute", "tank", "boomer"]
		for i in lineup.size():
			var kind := lineup[i]
			var at := p + Vector2(-252.0 + float(i) * 72.0, 48.0)
			if kind == "hunter":
				var h: Node2D = _m.spawn_hunter(at)
				if h != null:
					h.set_physics_process(false)
					h.rotation = -0.55
					if _night:
						h.self_modulate = grade
				continue
			var z: Node2D = _m.zombies.spawn_at(at, kind)
			if z == null:
				continue
			z.set_physics_process(false)
			z.rotation = -0.55
			if kind == "shambler" and "art_variant" in z:
				z.art_variant = i
			if kind == "shambler" and i == 2:
				z.art_pose_override = "lunge_1"
			if kind == "tank":
				z.charge = Zombie.Charge.WINDUP
				z.charge_time = 99.0
			if _tutorial and "highlight" in z:
				z.highlight = true
			if _night:
				z.self_modulate = grade
			z.queue_redraw()
	if _frames == 70:
		var img := root.get_texture().get_image()
		img.save_png(_out)
		print("saved ", _out, " night=", _night, " tutorial=", _tutorial)
		quit()
	return false
