extends SceneTree
## V3 style sample capture (needs a display; not headless):
##   xvfb-run -s "-screen 0 1280x720x24" godot --path . -s res://tools/art/capture_zombies_sample.gd -- out.png [before]
## In the mission scene: a ring of Shamblers (the 3 clothing variants, walking
## toward the rig, two in the lunge pose, one hit-flashing) and three Tanks
## (walking, roaring in the wind-up, charging). "before": the code-drawn look.

const Zombie := preload("res://scripts/zombie.gd")

var _frames := 0
var _out := "user://zombies_sample.png"
var _before := false
var _m: Node
var _z: Array = []


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_out = args[0]
	_before = args.size() > 1 and args[1] == "before"
	change_scene_to_file.call_deferred("res://scenes/mission.tscn")


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames == 40:
		_m = current_scene
		_m.set("auto_spawn_specials", false)
		if _before:
			Zombie.disable_art()
		var cam := root.get_camera_2d()
		if cam != null:
			cam.zoom = Vector2(2.6, 2.6)
		var p: Vector2 = _m.vehicle.global_position
		_m.vehicle.set_physics_process(false)
		for i in 10:
			var at := p + Vector2(150, 0).rotated(i * TAU / 10.0 + 0.2) * (1.0 if i % 2 == 0 else 0.75)
			var z: Node2D = _m.zombies.spawn_at(at, "shambler")
			if z != null:
				_z.append(z)
				if i == 3 or i == 7:
					z.art_pose_override = "lunge_1"
		for off: Vector2 in [Vector2(-200, -95), Vector2(215, -90), Vector2(-20, 125)]:
			var t: Node2D = _m.zombies.spawn_at(p + off, "tank")
			if t != null:
				_z.append(t)
	if _frames == 70 and not _z.is_empty():
		var tanks := _z.filter(func(z): return z.kind == "tank")
		if tanks.size() >= 2:
			tanks[1].charge = Zombie.Charge.WINDUP
			tanks[1].charge_time = 99.0
		if tanks.size() >= 3:
			tanks[2].charge = Zombie.Charge.CHARGE
			tanks[2].charge_time = 99.0
		_z[0]._flash = 1.0
		_z[0].queue_redraw()
	if _frames == 74:
		root.get_texture().get_image().save_png(_out)
		print("saved ", _out)
		quit()
	return false
