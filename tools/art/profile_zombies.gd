extends SceneTree
## Headless frame-time profile: N Shamblers chasing the rig in the mission.
##   godot --headless --path . -s res://tools/art/profile_zombies.gd -- [count] [frames] [before]
## Reports CPU process/physics time per frame (Performance monitors), not fps.
## "before" turns the V3 atlas art off (code-drawn bodies) for comparison.
const Zombie := preload("res://scripts/zombie.gd")
var _n := 30
var _frames := 600
var _f := 0
var _m: Node
var _proc: PackedFloat64Array = []
var _phys: PackedFloat64Array = []
var _wall: PackedFloat64Array = []
var _last := 0


func _init() -> void:
	var a := OS.get_cmdline_user_args()
	if a.size() > 0: _n = int(a[0])
	if a.size() > 1: _frames = int(a[1])
	if a.size() > 2 and a[2] == "before":
		Zombie._art_tried = true
		Zombie._art_meta = {}
	_start.call_deferred()


func _start() -> void:
	var profile: Node = root.get_node("/root/Profile")
	profile.persist = false   # never touch a real save
	profile.new_game()
	change_scene_to_file("res://scenes/mission.tscn")


func _process(_d: float) -> bool:
	if _m == null:
		if current_scene == null or current_scene.get("zombies") == null:
			return false
		_m = current_scene
		_f = 30
	_f += 1
	if _f == 31:
		_m.set("auto_spawn_specials", false)
		_m.vehicle.armor_max = 1e9
		_m.vehicle.armor = 1e9
		var p: Vector2 = _m.vehicle.global_position
		for i in _n:
			_m.zombies.spawn_at(p + Vector2(260 + (i % 5) * 30, 0).rotated(i * TAU / _n), "shambler")
		_last = Time.get_ticks_usec()
	elif _f > 60 and _f <= 60 + _frames:
		var now := Time.get_ticks_usec()
		_wall.append((now - _last) / 1000.0)
		_last = now
		_proc.append(Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0)
		_phys.append(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0)
	elif _f > 60 + _frames:
		var alive := 0
		for z in _m.zombies.get_children():
			alive += 1
		print("zombies alive=%d frames=%d" % [alive, _frames])
		for pair in [["process", _proc], ["physics", _phys], ["wall", _wall]]:
			var v: Array = Array(pair[1]); v.sort()
			var s := 0.0
			for x in v: s += x
			print("%s ms: mean %.3f  p50 %.3f  p95 %.3f  max %.3f" % [pair[0], s / v.size(), v[v.size() / 2], v[int(v.size() * 0.95)], v.back()])
		quit()
	return false
