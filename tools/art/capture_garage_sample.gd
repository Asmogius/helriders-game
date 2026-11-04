extends SceneTree
## V2 style sample capture: the Workshop bay room in the garage (needs a display):
##   xvfb-run -s "-screen 0 1280x720x24" godot --path . -s res://tools/art/capture_garage_sample.gd -- out.png [before|fade]
## "before": the room off (old floor grid). "fade": mid-fade to the RESEARCH tab.
## Uses HOME as given; run with a throwaway HOME so no real save is touched.

var _frames := 0
var _out := "user://garage_sample.png"
var _mode := ""
var _g: Node


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_out = args[0]
	if args.size() > 1:
		_mode = args[1]
	change_scene_to_file.call_deferred("res://scenes/garage.tscn")


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames == 30:
		_g = current_scene
		if _mode == "before" and _g.get("_workshop") != null:
			_g._workshop.set_open(false, true)
	if _frames == 50 and _mode == "fade":
		_g.call("show_tab", "RESEARCH")
	if _frames == (57 if _mode == "fade" else 90):
		root.get_texture().get_image().save_png(_out)
		print("saved ", _out)
		quit()
	return false
