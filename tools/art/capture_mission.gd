extends SceneTree
## Screenshot of the mission scene for art review (needs a display; not headless):
##   xvfb-run -s "-screen 0 1280x720x24" godot --path . -s res://tools/art/capture_mission.gd -- out.png
## Pick a map (sets mission_override before the mission starts):
##   ... -s res://tools/art/capture_mission.gd -- out.png --layout=crossroads [--seed=N] [--type=clear]
## Every layout, one <dir>/<id>.png each (layout i uses seed N+i; a banner names the layout):
##   ... -s res://tools/art/capture_mission.gd -- out_dir --all-layouts [--seed=N] [--type=clear]
## --style forces the Outer Blocks map style on (arena.gd `outer_blocks_style`; only
## Outer Blocks layouts change). --perf prints bake time, draw calls, texture memory
## and FPS for each capture (FPS is meaningless under software rendering / vsync).
## Under --headless there is no rendered image: it prints an error and exits with code 2.
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
var _index := -1
var _perf := false
var _fps: Array = []            # position in the --all-layouts run (seed = _seed + _index)


func _init() -> void:
	if DisplayServer.get_name() == "headless":
		printerr("capture_mission: rendering is unavailable under --headless, so there is nothing to capture.")
		printerr("  Run it without --headless under a virtual display, e.g.:")
		printerr("  xvfb-run -s \"-screen 0 1280x720x24\" godot --rendering-driver opengl3 --path . -s res://tools/art/capture_mission.gd -- out.png")
		quit(2)
		return
	var layout := ""
	var bad := false
	for a: String in OS.get_cmdline_user_args():
		if a == "--all-layouts":
			_all = true
		elif a.begins_with("--layout="):
			layout = a.substr(9)
		elif a.begins_with("--seed="):
			_seed = a.substr(7).to_int()
		elif a == "--style":
			load("res://scripts/arena.gd").outer_blocks_style = true
		elif a == "--perf":
			_perf = true
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
	_index += 1
	var mission := (load("res://scenes/mission.tscn") as PackedScene).instantiate()
	if _layout != "":
		var jobs: Array = Layouts.LAYOUTS[_layout].jobs
		var type := _type if _type != "" else str(jobs[0])
		if not jobs.has(type):
			print("note: %s jobs don't normally use %s" % [type, _layout])
		var seed := _seed + _index if _all else _seed
		var spec := Missions.make(type, 3, seed)
		spec["layout"] = _layout
		mission.set("mission_override", spec)
	root.add_child(mission)
	current_scene = mission
	_current = mission
	if _all:
		_add_banner(mission, "%s  (seed %d)" % [_layout, _seed + _index])
	_frames = 0
	_fps.clear()


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
	if _frames > 150 and _frames < 160:
		_fps.append(Performance.get_monitor(Performance.TIME_FPS))
	if _frames == 160:
		if _perf:
			_print_perf()
		var path := _out.path_join(_layout + ".png") if _all else _out
		var tex := root.get_texture()
		var img: Image = tex.get_image() if tex != null else null
		if img == null or img.is_empty():
			printerr("capture_mission: no rendered image to save (is a display/renderer available?)")
			quit(2)
			return false
		img.save_png(path)
		print("saved ", path)
		_next.call_deferred()
	return false


func _print_perf() -> void:
	var arena: Variant = _current.get("arena")
	var styled := false
	var bake := 0.0
	var bytes := 0
	if arena is Object and is_instance_valid(arena) and (arena as Object).has_method("is_styled"):
		styled = arena.is_styled()
		bake = float(arena.bake_ms)
		bytes = int(arena.bake_bytes)
	var fps := 0.0
	for f: float in _fps:
		fps += f
	fps /= maxf(1.0, _fps.size())
	print("PERF layout=%s styled=%s bake_ms=%.0f map_tex_mb=%.1f draw_calls=%d tex_mem_mb=%.1f fps=%.1f" % [
		_layout, str(styled), bake, bytes / 1048576.0,
		int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
		Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED) / 1048576.0, fps])


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


## A name banner over the capture (top centre, under the HUD's job title). Drawn by a CanvasLayer
## child of the mission, so it is freed with it.
func _add_banner(mission: Node, text: String) -> void:
	var layer := CanvasLayer.new()
	layer.layer = 128
	var bg := ColorRect.new()
	bg.color = Color(0, 0, 0, 0.7)
	var w := 32.0 + 17.0 * text.length()
	bg.size = Vector2(w, 52)
	bg.position = Vector2((root.get_visible_rect().size.x - w) * 0.5, 150)
	layer.add_child(bg)
	var label := Label.new()
	label.text = text.to_upper()
	label.size = bg.size
	label.position = bg.position
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 30)
	label.add_theme_color_override("font_color", Color(1, 1, 1))
	layer.add_child(label)
	mission.add_child(layer)
