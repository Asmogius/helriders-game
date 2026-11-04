extends SceneTree
## V5 garage sample: cost of the HD preview. Run under a renderer for texture
## memory and draw calls (xvfb-run ... --resolution 1280x720), or --headless
## for CPU frame times only:
##   godot --path . -s res://tools/art/profile_garage.gd -- [hd|sd] [frames]
const GarageLayout := preload("res://scripts/garage_layout.gd")
var _mode := "hd"
var _cpu: Array = []   # main-thread time from end of our _process to the next (engine frame work)
var _cpu_t0 := 0
var _frames := 300
var _f := 0
var _g: Control
var _wall: Array = []
var _proc: Array = []
var _draws: Array = []
var _last := 0


func _init() -> void:
	var a := OS.get_cmdline_user_args()
	if a.size() > 0: _mode = a[0]
	if a.size() > 1: _frames = int(a[1])
	GarageLayout.hd_enabled = _mode == "hd"
	_start.call_deferred()


func _start() -> void:
	var p: Node = root.get_node("/root/Profile")
	p.persist = false
	p.new_game()
	change_scene_to_file("res://scenes/garage.tscn")


func _process(_d: float) -> bool:
	_f += 1
	if _f == 30:
		_g = current_scene
		_g.set("auto_resume", false)
	if _f == 40:
		_g.call("open_slot", 2)   # DRIVE open: highlight, line, dim on
		_last = Time.get_ticks_usec()
	elif _f > 40 and _f <= 40 + _frames:
		var now := Time.get_ticks_usec()
		_cpu.append((now - _cpu_t0) / 1000.0)
		_wall.append((now - _last) / 1000.0)
		_last = now
		_cpu_t0 = Time.get_ticks_usec()
		_proc.append(Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0)
		_draws.append(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
		(_g.get("_rig_holder") as Node2D).rotation += 0.02   # keep frames changing
		if (_f - 40) % 15 == 0:
			var t0 := Time.get_ticks_usec()
			_g.call("open_slot", ((_f - 40) / 15) % 8)
			if OS.has_environment("PG_TRACE"): print("open_slot ms %.1f" % ((Time.get_ticks_usec() - t0) / 1000.0))   # browse slots: swaps art
	elif _f > 40 + _frames:
		print("mode=%s texture_mem_MB=%.2f video_mem_MB=%.2f" % [_mode,
			Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED) / 1048576.0,
			Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0])
		for pair in [["wall_ms", _wall], ["process_ms", _proc], ["draw_calls", _draws], ["frame_cpu_ms", _cpu]]:
			var v: Array = pair[1].duplicate()
			v.sort()
			var s := 0.0
			for x in v: s += x
			print("%s mean %.2f p50 %.2f p95 %.2f max %.2f" % [pair[0], s / v.size(), v[v.size() / 2], v[int(v.size() * 0.95)], v[-1]])
		quit()
	return false
