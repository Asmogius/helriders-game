extends SceneTree
## Quickplay QP1: level schema round-trip, validation errors, caps,
## schema_version, and unknown placeable ids.
##
## Run:  godot --headless --fixed-fps 60 --path . -s res://tests/quickplay_level_test.gd

const LevelData := preload("res://scripts/quickplay/level_data.gd")
const Registry := preload("res://scripts/quickplay/placeable_registry.gd")
const ProfileScript := preload("res://scripts/profile.gd")
const T := preload("res://scripts/tuning.gd")

var failures: Array[String] = []


func _initialize() -> void:
	var profile: ProfileScript = root.get_node("Profile")
	profile.persist = false
	profile.new_game()

	_check_registry()
	_check_round_trip()
	_check_unknown_ids()
	_check_schema_version()
	_check_caps()
	_check_validation_errors()
	_check_triggers_and_snap()

	if failures.is_empty():
		print("QUICKPLAY LEVEL TEST PASSED")
		quit(0)
	else:
		print("QUICKPLAY LEVEL TEST FAILED: %s" % ", ".join(failures))
		quit(1)


func _check_registry() -> void:
	_check(Registry.has_id("spawner_zombie") and Registry.has_id("building_box_m"), "registry has core ids")
	_check(Registry.is_spawner("spawner_zombie") and not Registry.is_spawner("building_box_s"), "is_spawner distinguishes spawners")
	_check(Registry.ids_in("spawner").size() == 2, "two spawner kinds")
	_check(Registry.all_ids().size() >= 10, "registry lists placeables")
	_check(Registry.is_known_trigger("level_start") and Registry.is_known_trigger("player_radius") and Registry.is_known_trigger("spawner_cleared"), "v1 triggers registered")
	_check(not Registry.is_known_trigger("always"), "legacy always trigger is not v1")
	var entry := Registry.get_entry("spawner_zombie")
	_check(entry.has("footprint") and entry.category == "spawner", "get_entry returns footprint and category")
	_check(Registry.SNAP_CELL_DEFAULT == 40 and Registry.SNAP_CELL_COARSE == 80, "snap cells 40 and 80")


func _check_round_trip() -> void:
	var level := LevelData.make_empty("Yard One", "crossroads")
	level.author = "Cameron"
	level.placeables = [
		{
			"id": "building_box_m",
			"pos": [400, 500],
			"rot": 1.5708,
			"snap": true,
			"data": {},
		},
		{
			"id": "spawner_zombie",
			"pos": [800, 900],
			"rot": 0.0,
			"snap": true,
			"key": "z1",
			"data": {
				"enemy": "brute",
				"count": 4,
				"rate": 3.0,
				"trigger": "player_radius",
				"radius": 350.0,
			},
		},
		{
			"id": "spawner_rig",
			"pos": [1000, 1100],
			"rot": 0.0,
			"snap": false,
			"key": "r1",
			"data": {
				"enemy": "outrider",
				"count": 1,
				"rate": 10.0,
				"trigger": "spawner_cleared",
				"source_spawner": "z1",
			},
		},
	]
	_check(LevelData.validate_playable(level) == "", "hand-built level is playable: %s" % LevelData.validate_playable(level))
	var text := LevelData.to_json(level)
	var back := LevelData.from_json(text)
	_check(int(back.schema_version) == LevelData.SCHEMA_VERSION, "round-trip keeps schema_version")
	_check(str(back.id) == str(level.id), "round-trip keeps id")
	_check(str(back.name) == "Yard One" and str(back.author) == "Cameron", "round-trip keeps name and author")
	_check(int(back.created) == int(level.created) and int(back.modified) == int(level.modified), "round-trip keeps timestamps")
	_check(str(back.base_map) == "crossroads", "round-trip keeps base_map")
	_check((back.placeables as Array).size() == 3, "round-trip keeps placeables")
	var z: Dictionary = back.placeables[1]
	_check(str(z.data.trigger) == "player_radius" and str(z.data.enemy) == "brute", "round-trip keeps spawner data")
	var r: Dictionary = back.placeables[2]
	_check(str(r.data.trigger) == "spawner_cleared" and str(r.data.source_spawner) == "z1", "round-trip keeps spawner_cleared link")
	# Planned bases accepted before Maps lands them.
	var blank := LevelData.make_empty("Blank", "blank_m")
	_check(str(blank.base_map) == "blank_m", "planned blank_m base_map accepted")
	_check(LevelData.is_known_base_map("endless"), "endless base_map is known")


func _check_unknown_ids() -> void:
	var raw := {
		"schema_version": 1,
		"id": "lvl_test",
		"name": "Drop",
		"author": "",
		"created": 1,
		"modified": 1,
		"base_map": "crossroads",
		"size": [T.WORLD_SIZE.x, T.WORLD_SIZE.y],
		"seed": 0,
		"snap_cell": 40,
		"player_start": [100, 100],
		"placeables": [
			{"id": "building_box_s", "pos": [200, 200], "rot": 0.0, "snap": true, "data": {}},
			{"id": "building_from_future", "pos": [300, 300], "rot": 0.0, "snap": true, "data": {}},
			{"id": "totally_fake", "pos": [400, 400], "rot": 0.0, "snap": true, "data": {}},
		],
	}
	var dropped := LevelData.dropped_placeable_ids(raw)
	_check(dropped.has("building_from_future") and dropped.has("totally_fake"), "dropped_placeable_ids lists unknowns")
	var clean := LevelData.sanitize(raw)
	_check((clean.placeables as Array).size() == 1, "sanitize drops unknown placeable ids")
	_check(str((clean.placeables as Array)[0].id) == "building_box_s", "known placeable kept")


func _check_schema_version() -> void:
	var level := LevelData.make_empty("Ver", "crossroads")
	level.schema_version = 99
	_check(LevelData.validate_playable(level) == "unsupported schema_version", "future schema_version rejected")
	var raw := LevelData.sanitize({"name": "NoVer", "base_map": "crossroads", "player_start": [10, 10], "placeables": []})
	_check(int(raw.schema_version) == LevelData.SCHEMA_VERSION, "missing schema_version defaults to current")
	var junk := LevelData.from_json("not-json")
	_check(junk.is_empty(), "bad json yields empty")


func _check_caps() -> void:
	var level := LevelData.make_empty("Caps", "crossroads")
	var pieces: Array = []
	for i in LevelData.MAX_PLACEABLES + 1:
		pieces.append({"id": "prop_crates", "pos": [100.0 + float(i % 50), 100.0 + float(i / 50)], "rot": 0.0, "snap": true, "data": {}})
	level.placeables = pieces
	_check(LevelData.validate_playable(level) == "too many placeables", "301 placeables rejected")
	level.placeables = pieces.slice(0, LevelData.MAX_PLACEABLES)
	_check(LevelData.validate_playable(level) == "", "exactly 300 placeables ok: %s" % LevelData.validate_playable(level))

	var spawn_level := LevelData.make_empty("SpawnCaps", "crossroads")
	var spawners: Array = []
	for i in LevelData.MAX_SPAWNERS + 1:
		spawners.append({
			"id": "spawner_zombie",
			"pos": [150.0 + float(i) * 10.0, 150.0],
			"rot": 0.0,
			"snap": true,
			"data": {"enemy": "shambler", "count": 1, "rate": 2.5, "trigger": "level_start", "radius": 100.0, "source_spawner": ""},
		})
	spawn_level.placeables = spawners
	_check(LevelData.validate_playable(spawn_level) == "too many spawners", "25 spawners rejected")
	spawn_level.placeables = spawners.slice(0, LevelData.MAX_SPAWNERS)
	_check(LevelData.validate_playable(spawn_level) == "", "exactly 24 spawners ok: %s" % LevelData.validate_playable(spawn_level))


func _check_validation_errors() -> void:
	_check(LevelData.validate_playable({}) == "empty level", "empty level fails")
	var level := LevelData.make_empty("Err", "crossroads")
	level.name = "   "
	_check(LevelData.validate_playable(level) == "missing name", "blank name fails")
	level = LevelData.make_empty("Err2", "crossroads")
	level.player_start = [-10, 50]
	_check(LevelData.validate_playable(level) == "player_start out of bounds", "start out of bounds fails")
	level = LevelData.make_empty("Err3", "crossroads")
	level.placeables = [{"id": "building_box_s", "pos": [99999, 10], "rot": 0.0, "snap": true, "data": {}}]
	_check(LevelData.validate_playable(level) == "placeable out of bounds", "placeable out of bounds fails")
	level = LevelData.make_empty("Err4", "crossroads")
	level.placeables = [{
		"id": "spawner_zombie",
		"pos": [200, 200],
		"rot": 0.0,
		"snap": true,
		"data": {"enemy": "shambler", "count": 1, "rate": 2.5, "trigger": "spawner_cleared", "source_spawner": "", "radius": 100.0},
	}]
	_check(LevelData.validate_playable(level) == "spawner_cleared needs source_spawner", "spawner_cleared without source fails")
	# Wrong-typed top-level fields are dropped / defaulted, not crashy.
	var messy := LevelData.sanitize({"schema_version": 1, "id": "x", "name": "M", "base_map": "nope", "placeables": "nope", "player_start": "x", "created": "no"})
	_check(str(messy.base_map) == "crossroads", "unknown base_map falls back to default")
	_check(messy.placeables is Array, "bad placeables field becomes array")


func _check_triggers_and_snap() -> void:
	var level := LevelData.make_empty("Snap", "crossroads")
	level.snap_cell = 80
	_check(LevelData.validate_playable(level) == "", "snap_cell 80 allowed")
	level.snap_cell = 55
	var cleaned := LevelData.sanitize(level)
	_check(int(cleaned.snap_cell) == 40, "invalid snap_cell coerced to 40")
	level = LevelData.make_empty("Trig", "crossroads")
	level.placeables = [{
		"id": "spawner_zombie",
		"pos": [200, 200],
		"rot": 0.0,
		"snap": true,
		"data": {"enemy": "shambler", "count": 1, "rate": 2.5, "trigger": "always", "radius": 100.0, "source_spawner": ""},
	}]
	var s := LevelData.sanitize(level)
	_check(str((s.placeables as Array)[0].data.trigger) == "level_start", "unknown trigger coerced to level_start")


func _check(ok: bool, what: String) -> void:
	print(("  PASS  " if ok else "  FAIL  ") + what)
	if not ok:
		failures.append(what)
