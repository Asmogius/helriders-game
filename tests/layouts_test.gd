extends SceneTree
## Headless test for the map layouts: twelve layouts (three per district,
## each with a landmark, an open arena, a choke point, two or more routes
## and barrel clusters, checked in every variation), at least four per job
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

const RUNS := {"crossroads": "clear", "main_drag": "courier", "lots": "survive", "alleys": "retrieve", "rail_yard": "escort", "plaza": "hunt",
	"gas_station": "escort", "overpass": "courier", "stadium_gate": "hunt", "factory_yard": "survive", "rail_bridge": "retrieve", "crater_rim": "clear"}

var profile: ProfileScript
var main: Mission
var frame := 0
var queue: Array = []
var failures: Array[String] = []


func _initialize() -> void:
	profile = root.get_node("Profile")
	profile.persist = false
	profile.new_game()
	_check(Layouts.LAYOUTS.size() == 12, "twelve layouts")
	var per_district := {}
	for id: String in Layouts.LAYOUTS:
		var d := str(Layouts.LAYOUTS[id].get("district", ""))
		per_district[d] = int(per_district.get(d, 0)) + 1
		_check(str(Layouts.LAYOUTS[id].get("landmark", "")) != "", "%s has a landmark" % id)
	for d: Dictionary in T.DISTRICTS:
		_check(int(per_district.get(str(d.id), 0)) == 3, "%s has three layouts" % str(d.name))
	_check(per_district.size() == T.DISTRICTS.size(), "every layout sits in a known district")
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
	_check(used.size() >= 9, "two weeks of boards use most layouts (%d)" % used.size())
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
		bad.append_array(_design_issues(arena, nav, start, arena.layout, vary))
		if arena.spawn_points.size() < 4:
			bad.append("only %d spawn points (vary %d)" % [arena.spawn_points.size(), vary])
		arena.free()
	_check(bad.is_empty(), "%s: every spot open and reachable in 26 variations%s" % [id, "" if bad.is_empty() else ": " + str(bad.slice(0, 6))])
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


## V5.7 design checks on one built variation: an open arena space, at least
## one choke point (open, reachable, walled in on two opposite sides), two
## routes from the start to the far spawn (the second avoids the first's
## cells), and at least two barrel clusters (spots within 300 px).
func _design_issues(arena: Arena, nav: NavGrid, start: Vector2, built: Dictionary, vary: int) -> Array:
	var out := []
	var area: Rect2 = built.arena
	if area.size.x < 400.0 or area.size.y < 400.0:
		out.append("arena too small (vary %d)" % vary)
	else:
		var total := 0
		var open := 0
		for x in range(int(area.position.x) + 20, int(area.end.x), 40):
			for y in range(int(area.position.y) + 20, int(area.end.y), 40):
				total += 1
				if not nav._blocked(Vector2(x, y)):
					open += 1
		if float(open) < 0.8 * float(total):
			out.append("arena only %d/%d open (vary %d)" % [open, total, vary])
	var chokes := 0
	for c: Vector2 in built.chokes:
		if nav._blocked(c) or nav.astar.get_id_path(nav.cell_of(start), nav.cell_of(c)).is_empty():
			out.append("choke %s blocked (vary %d)" % [str(c), vary])
		elif (_wall_near(nav, c, Vector2.LEFT) and _wall_near(nav, c, Vector2.RIGHT)) or (_wall_near(nav, c, Vector2.UP) and _wall_near(nav, c, Vector2.DOWN)):
			chokes += 1
		else:
			out.append("choke %s is not narrow (vary %d)" % [str(c), vary])
	if chokes < 1:
		out.append("no choke point (vary %d)" % vary)
	var far: Vector2 = start
	for p: Vector2 in arena.spawn_points:
		if p.distance_to(start) > far.distance_to(start):
			far = p
	var a := nav.cell_of(start)
	var b := nav.cell_of(far)
	var first := nav.astar.get_id_path(a, b)
	var shut: Array[Vector2i] = []
	for cell: Vector2i in first:
		if cell.distance_to(a) > 4.0 and cell.distance_to(b) > 4.0 and not nav.astar.is_point_solid(cell):
			nav.astar.set_point_solid(cell, true)
			shut.append(cell)
	if nav.astar.get_id_path(a, b).is_empty():
		out.append("only one route to %s (vary %d)" % [str(far), vary])
	for cell: Vector2i in shut:
		nav.astar.set_point_solid(cell, false)
	# Real clusters: connected groups (union-find, links within 300 px) of at
	# least two barrel spots. Lone spots don't count.
	var spots: Array = arena.barrel_spots
	var parent: Array[int] = []
	for i in spots.size():
		parent.append(i)
	for i in spots.size():
		for j in range(i + 1, spots.size()):
			if (spots[i] as Vector2).distance_to(spots[j]) <= 300.0:
				var ri := _root(parent, i)
				var rj := _root(parent, j)
				if ri != rj:
					parent[ri] = rj
	var sizes := {}
	for i in spots.size():
		var r := _root(parent, i)
		sizes[r] = int(sizes.get(r, 0)) + 1
	var clusters := 0
	for r: int in sizes:
		if int(sizes[r]) >= 2:
			clusters += 1
	if clusters < 2:
		out.append("only %d barrel clusters (vary %d)" % [clusters, vary])
	return out


func _root(parent: Array[int], i: int) -> int:
	while parent[i] != i:
		parent[i] = parent[parent[i]]
		i = parent[i]
	return i


func _wall_near(nav: NavGrid, p: Vector2, dir: Vector2) -> bool:
	var side := Vector2(-dir.y, dir.x)
	for lane in [-30.0, 0.0, 30.0]:
		for step in range(1, 19):
			if nav._blocked(p + side * float(lane) + dir * 10.0 * step):
				return true
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
