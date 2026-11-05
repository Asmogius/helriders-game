extends SceneTree
## Quickplay QP7: bake a level into an Arena layout.
## Solids are buildings (Rect2) and wreck/prop boxes. player_start stays clear.
## Prop kinds 0/1/2 match arena.gd _draw_prop and draw without error.
##
## Run:  godot --headless --fixed-fps 60 --path . -s res://tests/quickplay_bake_test.gd

const LevelData := preload("res://scripts/quickplay/level_data.gd")
const LevelBake := preload("res://scripts/quickplay/level_bake.gd")
const Registry := preload("res://scripts/quickplay/placeable_registry.gd")
const Layouts := preload("res://scripts/layouts.gd")
const Arena := preload("res://scripts/arena.gd")
const NavGrid := preload("res://scripts/nav_grid.gd")
const ProfileScript := preload("res://scripts/profile.gd")
const T := preload("res://scripts/tuning.gd")

var failures: Array[String] = []
var frame := 0
var arena: Node2D
var space: PhysicsDirectSpaceState2D
var building_at := Vector2(480, 640)
var wreck_at := Vector2(1100, 900)
var start_at := Vector2(1600, 1400)


func _initialize() -> void:
	var profile: ProfileScript = root.get_node("Profile")
	profile.persist = false
	profile.new_game()

	_check_catalog_footprints()
	_check_blank_bake()
	_check_rotation_and_kinds()
	_check_non_solids()
	_check_start_stays_clear()
	_check_base_overlay()
	_check_caps()
	_arm_collision_and_draw()


func _process(_delta: float) -> bool:
	frame += 1
	if frame < 3:
		return false
	if space == null and arena != null:
		space = arena.get_world_2d().direct_space_state
	RenderingServer.force_draw()
	_check_collision_and_draw()
	_finish()
	return true


func _check_catalog_footprints() -> void:
	_check(Registry.SNAP_CELL_DEFAULT == 40 and Registry.SNAP_CELL_COARSE == 80, "snap stays 40 / 80")
	var small := Registry.get_entry("building_box_s")
	var mid := Registry.get_entry("building_box_m")
	var large := Registry.get_entry("building_box_l")
	_check(small.footprint == Vector2(160, 120) and bool(small.solid), "small building 160x120 solid")
	_check(mid.footprint == Vector2(280, 200) and bool(mid.solid), "medium building 280x200 solid")
	# Crossroads block Rect2(180, 180, 420, 300) — large box matches that size.
	_check(large.footprint == Vector2(420, 300) and bool(large.solid), "large building matches a Crossroads block")
	_check(Registry.get_entry("prop_wreck").footprint == Vector2(110, 54) and int(Registry.get_entry("prop_wreck").prop_kind) == 0, "wreck footprint and kind 0")
	_check(Registry.get_entry("prop_barrier").footprint == Vector2(150, 36) and int(Registry.get_entry("prop_barrier").prop_kind) == 1, "barrier footprint and kind 1")
	_check(Registry.get_entry("prop_crates").footprint == Vector2(64, 64) and int(Registry.get_entry("prop_crates").prop_kind) == 2, "crates footprint and kind 2")
	_check(not bool(Registry.get_entry("spawner_zombie").solid) and not bool(Registry.get_entry("pickup_scrap").solid), "spawners and pickups are not solids")
	_check(LevelBake.SOLID_CATEGORIES.has("building") and LevelBake.SOLID_CATEGORIES.has("wreck") and LevelBake.SOLID_CATEGORIES.has("prop"), "solid categories")
	_check(not LevelBake.SOLID_CATEGORIES.has("spawner") and not LevelBake.SOLID_CATEGORIES.has("marker") and not LevelBake.SOLID_CATEGORIES.has("pickup"), "non-solids stay out of the solid list")


func _check_blank_bake() -> void:
	var level := _level("blank_m", start_at)
	level.placeables = [
		_piece("building_box_m", building_at, 0.0),
		_piece("prop_wreck", wreck_at, 0.35),
	]
	var layout := LevelBake.bake(level)
	_check(str(layout.get("id", "")) == "blank_m", "synthetic blank keeps the base id")
	_check(layout.start == start_at, "layout start is the level player_start")
	var buildings: Array = layout.get("buildings", [])
	_check(buildings.size() == 1, "one baked building, got %d" % buildings.size())
	if buildings.size() >= 1:
		var box: Rect2 = buildings[0]
		var fp: Vector2 = Registry.get_entry("building_box_m").footprint
		_check(box.size == fp and box.get_center().distance_to(building_at) < 0.1, "building rect is the footprint centered on pos")
	var props: Array = layout.get("props", [])
	_check(props.size() == 1, "one baked wreck")
	if props.size() >= 1:
		_check((props[0][0] as Vector2).distance_to(wreck_at) < 0.1, "wreck center is pos")
		_check(props[0][1] == Vector2(110, 54), "wreck size")
		_check(is_equal_approx(float(props[0][2]), 0.35) and int(props[0][3]) == 0, "wreck rot and kind 0")
	_check((layout.roads as Array).is_empty(), "blank canvas has no roads")
	var arena_try := Arena.new()
	arena_try.setup(layout)
	_check(arena_try.buildings.size() == 1 and arena_try.props.size() == 1 and arena_try.player_start == start_at, "Arena.setup consumes the baked layout")
	arena_try.free()


func _check_rotation_and_kinds() -> void:
	var level := _level("blank_s", start_at)
	level.placeables = [
		_piece("building_box_s", Vector2(800, 500), PI * 0.5),
		_piece("prop_wreck", Vector2(900, 800), 0.2),
		_piece("prop_barrier", Vector2(1200, 800), -0.4),
		_piece("prop_crates", Vector2(1500, 800), 1.1),
	]
	var layout := LevelBake.bake(level)
	var built: Array = layout.get("buildings", [])
	if built.is_empty():
		_check(false, "quarter-turn swaps the building footprint, got no building")
	else:
		var box: Rect2 = built[0]
		_check(box.size == Vector2(120, 160), "quarter-turn swaps the building footprint, got %s" % box.size)
	var kinds: Array[int] = []
	for p: Array in layout.props:
		kinds.append(int(p[3]))
		_check((p[1] as Vector2).x > 1.0 and (p[1] as Vector2).y > 1.0, "prop size stays positive")
	_check(kinds == [0, 1, 2], "prop kinds are wreck, barrier, crates")


func _check_non_solids() -> void:
	var level := _level("blank_l", start_at)
	var spawn_at := Vector2(400, 400)
	var barrel_at := Vector2(600, 700)
	var scrap_at := Vector2(700, 700)
	level.placeables = [
		_piece("player_start", Vector2(200, 200), 0.0),
		_piece("spawner_zombie", spawn_at, 0.0),
		_piece("spawner_rig", Vector2(500, 500), 0.0),
		_piece("barrel_fuel", barrel_at, 0.0),
		_piece("barrel_acid", Vector2(640, 700), 0.0),
		_piece("pickup_scrap", scrap_at, 0.0),
		_piece("building_box_s", Vector2(1000, 1000), 0.0),
	]
	var layout := LevelBake.bake(level)
	_check((layout.buildings as Array).size() == 1, "only the building is a building box")
	_check((layout.props as Array).is_empty(), "markers, spawners and pickups are not props")
	var spawns: Array = layout.spawn_points
	_check(spawns.has(spawn_at), "zombie spawner is recorded as a spawn point")
	_check(spawns.size() == 2, "both spawners become spawn points, got %d" % spawns.size())
	var barrels: Array = layout.barrel_spots
	_check(barrels.has(barrel_at) and barrels.size() == 2, "barrels are spots, not collision, got %d" % barrels.size())
	_check(not barrels.has(scrap_at) and not spawns.has(scrap_at), "scrap pickup is skipped")


func _check_start_stays_clear() -> void:
	var level := _level("blank_m", start_at)
	level.placeables = [
		_piece("building_box_l", start_at, 0.0),
		_piece("prop_barrier", start_at + Vector2(10, 0), 0.0),
		_piece("building_box_s", Vector2(400, 400), 0.0),
		_piece("prop_crates", Vector2(2200, 1800), 0.5),
	]
	var layout := LevelBake.bake(level)
	_check(layout.start == start_at, "covered start is still the start")
	var pad := LevelBake.start_pad(start_at)
	for b: Rect2 in layout.buildings:
		_check(not b.intersects(pad), "no building overlaps the start pad %s" % b)
	for p: Array in layout.props:
		_check(not LevelBake.prop_hits_rect(p[0], p[1], float(p[2]), pad), "no prop overlaps the start pad")
	_check((layout.buildings as Array).size() == 1, "the clear building is kept")
	_check((layout.props as Array).size() == 1, "the clear crate stack is kept")
	var nav_arena := _arena_of(layout)
	var nav := NavGrid.new(nav_arena)
	_check(not nav._blocked(start_at), "player_start cell is open")
	_check(nav._blocked(Vector2(400, 400)), "kept building blocks nav")
	nav_arena.free()


func _check_base_overlay() -> void:
	var base := Layouts.build("crossroads")
	var level := _level("crossroads", start_at)
	level.seed = 0
	level.placeables = [_piece("building_box_s", Vector2(1500, 1100), 0.0)]
	var layout := LevelBake.bake(level)
	_check(str(layout.id) == "crossroads", "known base keeps its id")
	_check((layout.roads as Array).size() == (base.roads as Array).size(), "base roads kept")
	_check((layout.buildings as Array).size() == (base.buildings as Array).size() + 1, "placed building is added to the base")
	# Crossroads block Rect2(180, 180, 420, 300) covers its own center.
	var buried := Vector2(390, 330)
	var buried_level := _level("crossroads", buried)
	var buried_layout := LevelBake.bake(buried_level)
	var pad := LevelBake.start_pad(buried)
	var hit := false
	for b: Rect2 in buried_layout.buildings:
		if b.intersects(pad):
			hit = true
	_check(not hit and buried_layout.start == buried, "a base building covering the start is dropped")


func _check_caps() -> void:
	var level := _level("blank_s", start_at)
	var pieces: Array = []
	for i in LevelData.MAX_PLACEABLES + 5:
		var x := 200.0 + float(i % 40) * 70.0
		var y := 200.0 + float(i / 40) * 70.0
		pieces.append(_piece("prop_crates", Vector2(x, y), 0.0))
	level.placeables = pieces
	var layout := LevelBake.bake(level)
	_check((layout.props as Array).size() == LevelData.MAX_PLACEABLES, "bake keeps 300 props and drops the rest, got %d" % (layout.props as Array).size())
	var spawners: Array = []
	for i in LevelData.MAX_SPAWNERS + 3:
		spawners.append(_piece("spawner_zombie", Vector2(300.0 + float(i) * 50.0, 300.0), 0.0))
	level.placeables = spawners
	layout = LevelBake.bake(level)
	_check((layout.spawn_points as Array).size() == LevelData.MAX_SPAWNERS, "bake keeps 24 spawn points and drops the rest, got %d" % (layout.spawn_points as Array).size())
	_check((layout.props as Array).is_empty() and (layout.buildings as Array).is_empty(), "spawners over the cap still are not solids")


func _arm_collision_and_draw() -> void:
	var level := _level("blank_m", start_at)
	level.placeables = [
		_piece("building_box_m", building_at, 0.0),
		_piece("prop_wreck", wreck_at, 0.4),
		_piece("prop_barrier", Vector2(1400, 900), 0.0),
		_piece("prop_crates", Vector2(1700, 900), 0.2),
	]
	var layout := LevelBake.bake(level)
	var scr := GDScript.new()
	scr.source_code = "extends \"res://scripts/arena.gd\"\nvar draws := 0\nfunc _draw() -> void:\n\tsuper()\n\tdraws += 1\n"
	var err: Error = scr.reload()
	_check(err == OK, "draw probe script compiles")
	if err != OK:
		return
	arena = scr.new()
	arena.setup(layout)
	arena.position = Vector2.ZERO
	root.add_child(arena)


func _check_collision_and_draw() -> void:
	if arena == null:
		_check(false, "arena missing")
		return
	var body := arena.get_child(0) as StaticBody2D
	_check(body != null and body.get_child_count() == 4 + arena.buildings.size() + arena.props.size(), "walls plus one collision box per solid")
	_check(_hits(building_at), "building center collides")
	_check(_hits(wreck_at), "wreck center collides")
	_check(not _hits(start_at), "player_start does not collide")
	var kinds_seen := {}
	for p: Array in arena.props:
		kinds_seen[int(p[3])] = true
	_check(kinds_seen.has(0) and kinds_seen.has(1) and kinds_seen.has(2), "arena holds all three prop kinds")
	_check(int(arena.get("draws")) >= 1, "prop kinds drew without error (draws=%s)" % str(arena.get("draws")))


func _hits(at: Vector2) -> bool:
	if space == null:
		return false
	var q := PhysicsPointQueryParameters2D.new()
	q.position = at
	q.collision_mask = T.LAYER_WORLD
	q.collide_with_bodies = true
	q.collide_with_areas = false
	return not space.intersect_point(q, 4).is_empty()


func _arena_of(layout: Dictionary) -> Node2D:
	var a := Arena.new()
	a.setup(layout)
	return a


func _level(base_map: String, start: Vector2) -> Dictionary:
	var level := LevelData.make_empty("Bake", base_map)
	level.player_start = [start.x, start.y]
	level.placeables = []
	level.seed = 0
	return level


func _piece(id: String, at: Vector2, rot: float) -> Dictionary:
	return {"id": id, "pos": [at.x, at.y], "rot": rot, "snap": true, "data": {}}


func _finish() -> void:
	if failures.is_empty():
		print("QUICKPLAY BAKE TEST PASSED")
		quit(0)
	else:
		print("QUICKPLAY BAKE TEST FAILED: %s" % ", ".join(failures))
		quit(1)


func _check(ok: bool, what: String) -> void:
	print(("  PASS  " if ok else "  FAIL  ") + what)
	if not ok:
		failures.append(what)
