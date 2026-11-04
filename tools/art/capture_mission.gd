extends SceneTree
## Screenshot of the mission scene for art review (needs a display; not headless):
##   xvfb-run -s "-screen 0 1280x720x24" godot --path . -s res://tools/art/capture_mission.gd -- out.png
## Pick a map (sets mission_override before the mission starts):
##   ... -s res://tools/art/capture_mission.gd -- out.png --layout=crossroads [--seed=N] [--type=clear]
## Every layout, one <dir>/<id>.png each:
##   ... -s res://tools/art/capture_mission.gd -- out_dir --all-layouts [--seed=N] [--type=clear]
## With a layout picked, the camera pulls out to show the whole map.
## Tool only: runs on a throwaway profile (no save written), changes no gameplay.

const Missions := preload("res://scripts/missions.gd")
const Layouts := preload("res://scripts/layouts.gd")
const T := preload("res://scripts/tuning.gd")

var _frames := 0
var _out := "user://mission_capture.png"
var _queue: Array = []      # layout ids still to capture ("" = plain run, as before)
var _seed := 4242
var _type := ""
var _all := false
var _current: Node = null
var _layout := ""


func _init() -> void:
	var layout := ""
	var bad := false
	for a: String in OS.get_cmdline_user_args():
		if a == "--all-layouts":
			_all = true
		elif a.begins_with("--layout="):
			layout = a.substr(9)
		elif a.begins_with("--seed="):
			_seed = a.substr(7).to_int()
		elif a.begins_with("--type="):
			_type = a.substr(7)
		elif a.begins_with("--"):
			push_error("unknown option " + a)
			bad = true
		else:
			_out = a
	if layout != "" and not Layouts.LAYOUTS.has(layout):
		push_error("unknown layout %s (have %s)" % [layout, str(Layouts.LAYOUTS.keys())])
		bad = true
	if _type != "" and not Missions.TYPES.has(_type):
		push_error("unknown mission type %s (have %s)" % [_type, str(Missions.TYPES)])
		bad = true
	if bad:
		quit(1)
		return
	if _all:
		_queue = Layouts.LAYOUTS.keys()
		DirAccess.make_dir_recursive_absolute(_out)
	else:
		_queue = [layout]
	var profile := root.get_node_or_null("Profile")
	if profile != null and (layout != "" or _all):
		profile.persist = false
		profile.new_game()
	_next.call_deferred()


func _next() -> void:
	if _current != null:
		_current.free()
		_current = null
	if _queue.is_empty():
		quit()
		return
	_layout = str(_queue.pop_front())
	var mission := (load("res://scenes/mission.tscn") as PackedScene).instantiate()
	if _layout != "":
		var jobs: Array = Layouts.LAYOUTS[_layout].jobs
		var type := _type if _type != "" else str(jobs[0])
		if not jobs.has(type):
			print("note: %s jobs don't normally use %s" % [type, _layout])
		var spec := Missions.make(type, 3, _seed)
		spec["layout"] = _layout
		mission.set("mission_override", spec)
	root.add_child(mission)
	current_scene = mission
	_current = mission
	_frames = 0


func _process(_delta: float) -> bool:
	if _current == null:
		return false
	_frames += 1
	if _frames == 150:
		var cam := root.get_camera_2d()
		if cam != null:
			if _layout == "":
				cam.zoom = Vector2(2.5, 2.5)
			else:
				_frame_whole_map(cam)
	if _frames == 160:
		var path := _out.path_join(_layout + ".png") if _all else _out
		root.get_texture().get_image().save_png(path)
		print("saved ", path)
		_next.call_deferred()
	return false


func _frame_whole_map(cam: Camera2D) -> void:
	cam.set_physics_process(false)    # stop the chase camera re-zooming
	cam.set_process(false)
	cam.position_smoothing_enabled = false
	cam.limit_left = -100000
	cam.limit_top = -100000
	cam.limit_right = 100000
	cam.limit_bottom = 100000
	cam.offset = Vector2.ZERO
	var view := root.get_visible_rect().size
	var z := minf(view.x / T.WORLD_SIZE.x, view.y / T.WORLD_SIZE.y)
	cam.zoom = Vector2(z, z)
	cam.global_position = T.WORLD_SIZE * 0.5
