extends SceneTree
## Renderer face-fix review shots (needs a display):
##   xvfb-run -s "-screen 0 1280x720x24" godot --rendering-driver opengl3 --path . -s res://tools/art/capture_renderer_fix.gd -- out.png rigs|fight
## rigs:  Scrap Frame, Bulwark Frame, Outrider, Courier Frame, Pintle turret,
##        each at 6 headings, 3x zoom, straight from the sheets.
## fight: the mission with two enemy rigs (Outrider, Bulwark) and a zombie
##        crowd (Shamblers and Tanks) around the player's rig.

const DS := preload("res://scripts/directional_sprite.gd")
const SHEETS := ["scrap_frame", "bulwark_frame", "outrider", "courier_frame", "pintle_turret"]

var _out := "user://renderer_fix.png"
var _mode := "rigs"
var _frames := 0
var _m: Node


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_out = args[0]
	if args.size() > 1:
		_mode = args[1]
	if _mode == "fight":
		change_scene_to_file.call_deferred("res://scenes/mission.tscn")
	else:
		_build_rigs.call_deferred()


func _build_rigs() -> void:
	var w := Node2D.new()
	root.add_child(w)
	var bg := ColorRect.new()
	bg.color = Color(0.16, 0.16, 0.17)
	bg.size = Vector2(1280, 720)
	w.add_child(bg)
	for r in SHEETS.size():
		for c in 6:
			var s: Sprite2D = DS.new()
			s.meta_path = "res://art/sprites/%s.json" % SHEETS[r]
			s.position = Vector2(110 + c * 210, 75 + r * 142)
			s.scale = Vector2(2.2, 2.2)
			w.add_child(s)
			s.heading = c * TAU / 6.0 + 0.3


func _process(_d: float) -> bool:
	_frames += 1
	if _mode == "fight" and _frames == 40:
		_m = current_scene
		_m.set("auto_spawn_specials", false)
		var cam := root.get_camera_2d()
		if cam != null:
			cam.zoom = Vector2(2.2, 2.2)
		var p: Vector2 = _m.vehicle.global_position
		_m.vehicle.set_physics_process(false)
		_m.spawn_outrider(p + Vector2(-190, -60))
		_m.spawn_bulwark(p + Vector2(200, 70))
		for i in 12:
			_m.zombies.spawn_at(p + Vector2(130, 0).rotated(i * TAU / 12.0 + 0.2) * (1.0 if i % 2 == 0 else 0.8), "shambler")
		_m.zombies.spawn_at(p + Vector2(-40, -150), "tank")
		_m.zombies.spawn_at(p + Vector2(60, 150), "tank")
	if _frames == (80 if _mode == "fight" else 10):
		root.get_texture().get_image().save_png(_out)
		print("saved ", _out)
		quit()
	return false
