extends SceneTree
## Day / night before-after of the HD-2D look test. Needs a display:
##   xvfb-run -s "-screen 0 1280x720x24" godot --rendering-driver opengl3 --path . -s res://tools/art/capture_looktest.gd -- concepts/looktest
## Writes day_before, day_after, night_before, night_after, and perf.txt.

const Fight := preload("res://scripts/looktest_fight.gd")

var _fight: Node
var _out := ""
var _phase := "wait"
var _cool := 0
var _draws: Array[String] = []


func _init() -> void:
	if DisplayServer.get_name() == "headless":
		printerr("capture_looktest: needs a display (xvfb).")
		quit(2)
		return
	for a: String in OS.get_cmdline_user_args():
		if not a.begins_with("--"):
			_out = a
	_boot.call_deferred()


func _boot() -> void:
	if _out == "":
		_out = ProjectSettings.globalize_path("res://concepts/looktest")
	elif not _out.begins_with("/"):
		_out = ProjectSettings.globalize_path("res://").path_join(_out)
	DirAccess.make_dir_recursive_absolute(_out)
	_fight = Fight.new()
	root.add_child(_fight)


func _process(_delta: float) -> bool:
	if _fight == null or not bool(_fight.get("posed")):
		return false
	_cool += 1
	if _cool < 3:
		return false
	var stack: Node = _fight.get("stack")
	match _phase:
		"wait":
			_shot("day_before.png")
			stack.call("set_mode", "day")
			stack.call("set_practicals", true)
			stack.call("set_enabled", true)
			_phase = "day"
		"day":
			_shot("day_after.png")
			stack.call("set_mode", "night")
			stack.call("set_practicals", false)
			_phase = "night_flat"
		"night_flat":
			_shot("night_before.png")
			stack.call("set_practicals", true)
			_phase = "night"
		"night":
			_shot("night_after.png")
			_write_perf(stack)
			print("LOOKTEST CAPTURE DONE ", _out)
			quit()
			return false
	_cool = 0
	return false


func _shot(name: String) -> void:
	var path := _out.path_join(name)
	var tex := root.get_texture()
	var img: Image = tex.get_image() if tex != null else null
	if img == null or img.is_empty():
		printerr("capture_looktest: no image")
		quit(2)
		return
	img.save_png(path)
	var draws := int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
	var stack: Node = _fight.get("stack")
	var lights := int(stack.call("active_light_count"))
	var line := "%s draw_calls=%d lights=%d" % [name, draws, lights]
	_draws.append(line)
	print("saved ", path, " ", line)


func _write_perf(stack: Node) -> void:
	var f := FileAccess.open(_out.path_join("perf.txt"), FileAccess.WRITE)
	if f == null:
		return
	f.store_line("looktest capture")
	f.store_line("light_cap_now=%d" % int(stack.call("light_cap")))
	for line: String in _draws:
		f.store_line(line)
