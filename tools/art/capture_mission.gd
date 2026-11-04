extends SceneTree
## Screenshot of the mission scene for art review (needs a display; not headless):
##   xvfb-run -s "-screen 0 1280x720x24" godot --path . -s res://tools/art/capture_mission.gd -- out.png

var _frames := 0
var _out := "user://mission_capture.png"


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_out = args[0]
	change_scene_to_file.call_deferred("res://scenes/mission.tscn")


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames == 150:
		var cam := root.get_camera_2d()
		if cam != null:
			cam.zoom = Vector2(2.5, 2.5)
	if _frames == 160:
		root.get_texture().get_image().save_png(_out)
		print("saved ", _out)
		quit()
	return false
