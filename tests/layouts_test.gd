extends SceneTree
## Headless test for the map layouts: six layouts, at least four per job
## type, every spot (start, stops, barrel spots, spawn points, the Escort
## truck) on open ground and reachable from the start in each layout as
## drawn and in 25 seeded variations (mirrored, props nudged, roads
## barricaded, fewer spawn sides), variations repeat for the same seed, the
## board hands out layouts its jobs can use, saves keep them, and a real job
## runs on every layout.
##
## Run:  godot --headless --fixed-fps 60 --path . -s res://tests/layouts_test.gd

const Mission := preload("res://scripts/mission.gd")
const Missions := preload("res://scripts/missions.gd")
const Layouts := preload("res://scripts/layouts.gd")
const Arena := preload("res://scripts/arena.gd")
const NavGrid := preload("res://scripts/nav_grid.gd")
const ProfileScript := preload("res://scripts/profile.gd")
const T := preload("res://scripts/tuning.gd")

const RUNS := {"crossroads": "clear", "main_drag": "courier", "lots": "survive", "alleys": "retrieve", "rail_yard": "escort", "plaza": "hunt"}

var profile: ProfileScript
var main: Mission
var frame := 0
var queue: Array = []
var failures: Array[String] = []


func _initialize() -> void:
	profile = root.get_node("Profile")
	profile.persist = false
	profile.new_game()
	_check(Layouts.LAYOUTS.size() == 6, "six layouts")
	for type: String in T.MISSIONS:
		_check(Layouts.ids_for(type).size() >= 4, "%s has %d layouts (4+)" % [type, Layouts.ids_for(type).size()])
	for id: String in Layouts.LAYOUTS:
		_check_layout(id)
	_check(JSON.stringify(Layouts.build("alleys", 77)) == JSON.stringify(Layouts.build("alleys", 77)), "the same job seed builds the same map")
	_check(JSON.stringify(Layouts.build("alleys", 77)) != JSON.stringify(Layouts.build("alleys", 78)), "another seed varies it")
	var used := {}
	for day in range(1, 15):
		for job: Dictionary in Missions.make_board(day, 4, 0):
			var lid := str(job.get("layout", ""))
			used[lid] = true
			if not Layouts.ids_for(str(job.type)).has(lid):
				_check(false, "a %s job got a layout it can't use (%s)" % [job.type, lid])
	_check(used.size() >= 5, "two weeks of boards use most layouts (%d)" % used.size())
	var job: Dictionary = Missions.make_board(3, 4, 0)[0]
	_check(Missions.threats_text(job).begins_with(str(Layouts.LAYOUTS[str(job.layout)].name)), "the Comms card names the map")
	_check(str(ProfileScript._clean_mission(JSON.parse_string(JSON.stringify(job))).get("layout", "")) == str(job.layout), "saves keep a job's layout")
	for id: String in RUNS:
		queue.append(id)


func _check_layout(id: String) -> void:
	var bad := []
	var blocked_any := 0
	for vary in range(0, 26):
		var arena := Arena.new()
		arena.setup(Layouts.build(id, vary))
		if int(arena.layout.blocks_used) > 0:
			blocked_any += 1
		var nav := NavGrid.new(arena)
		var start: Vector2 = arena.player_start
		var spots: Array = [["start", start]]
		for p: Vector2 in arena.checkpoints:
			spots.append(["stop", p])
		for p: Vector2 in arena.barrel_spots:
			spots.append(["barrel", p])
		for p: Vector2 in arena.spawn_points:
			spots.append(["spawn", p])
		if (Layouts.LAYOUTS[id].jobs as Array).has("escort"):
			spots.append(["truck", start + Vector2(0, 110)])
		for s: Array in spots:
			var p: Vector2 = s[1]
			if nav._blocked(p):
				bad.append("%s %s blocked (vary %d)" % [s[0], str(p), vary])
			elif nav.astar.get_id_path(nav.cell_of(start), nav.cell_of(p)).is_empty():
				bad.append("%s %s cut off (vary %d)" % [s[0], str(p), vary])
		if arena.spawn_points.size() < 4:
			bad.append("only %d spawn points (vary %d)" % [arena.spawn_points.size(), vary])
		arena.free()
	_check(bad.is_empty(), "%s: every spot open and reachable in 26 variations%s" % [id, "" if bad.is_empty() else ": " + str(bad.slice(0, 4))])
	_check(blocked_any == 25, "%s: every variation barricades a road" % id)
	var stops := (Layouts.LAYOUTS[id].checkpoints as Array).size()
	_check(stops >= 13, "%s: %d stops for routes and caches" % [id, stops])


func _process(_delta: float) -> bool:
	frame += 1
	if main == null:
		if queue.is_empty():
			_finish()
			return true
		var id: String = queue.pop_front()
		var spec := Missions.make(str(RUNS[id]), 3, 4242)
		spec["layout"] = id
		main = (load("res://scenes/mission.tscn") as PackedScene).instantiate() as Mission
		main.mission_override = spec
		root.add_child(main)
		frame = 0
		return false
	if frame == 90:
		var id := str(main.arena.layout.id)
		_check(main.vehicle.global_position.distance_to(main.arena.player_start) < 400.0 and not main.vehicle.is_wrecked,
			"a %s job runs on %s" % [str(main.mission_type), id])
		_check(profile.is_discovered("places", "map_" + id), "and the map goes in the Database")
		main.free()
		main = null
	return false


func _check(ok: bool, what: String) -> void:
	print(("  PASS  " if ok else "  FAIL  ") + what)
	if not ok:
		failures.append(what)


func _finish() -> void:
	if failures.is_empty():
		print("LAYOUTS TEST PASSED")
		quit(0)
	else:
		print("LAYOUTS TEST FAILED: %s" % ", ".join(failures))
		quit(1)
