extends SceneTree
## Quickplay QP1: level schema round-trip, validation, caps, hardening.
##
## Run:  godot --headless --fixed-fps 60 --path . -s res://tests/quickplay_level_test.gd

const LevelData := preload("res://scripts/quickplay/level_data.gd")
const Registry := preload("res://scripts/quickplay/placeable_registry.gd")
const ProfileScript := preload("res://scripts/profile.gd")
const Layouts := preload("res://scripts/layouts.gd")
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
	_check_sanitize_rejects()
	_check_type_safety()
	_check_bounds_and_finite()
	_check_overlap_and_duplicates()
	_check_name_safety()
	_check_base_spawn_rails()
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
		{"id": "building_box_m", "pos": [400, 500], "rot": 1.5708, "snap": true, "data": {}},
		{
			"id": "spawner_zombie", "pos": [800, 900], "rot": 0.0, "snap": true, "key": "z1",
			"data": {"enemy": "brute", "count": 4, "rate": 3.0, "trigger": "player_radius", "radius": 350.0},
		},
		{
			"id": "spawner_rig", "pos": [1000, 1100], "rot": 0.0, "snap": false, "key": "r1",
			"data": {"enemy": "outrider", "count": 1, "rate": 10.0, "trigger": "spawner_cleared", "source_spawner": "z1"},
		},
	]
	# crossroads base has many spawn rails; keep placed spawners low enough for total <= 24
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
	var blank := LevelData.make_empty("Blank", "blank_m")
	_check(str(blank.base_map) == "blank_m", "planned blank_m base_map accepted")
	_check(LevelData.is_known_base_map("endless"), "endless base_map is known")


func _check_unknown_ids() -> void:
	var raw := {
		"schema_version": 1, "id": "lvl_test", "name": "Drop", "author": "",
		"created": 1, "modified": 1, "base_map": "crossroads",
		"size": [T.WORLD_SIZE.x, T.WORLD_SIZE.y], "seed": 0, "snap_cell": 40,
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
	_check(not clean.is_empty() and (clean.placeables as Array).size() == 1, "sanitize drops unknown placeable ids")
	_check(str((clean.placeables as Array)[0].id) == "building_box_s", "known placeable kept")


func _check_schema_version() -> void:
	var level := LevelData.make_empty("Ver", "crossroads")
	level.schema_version = 99
	_check(LevelData.validate_playable(level) == "unsupported schema_version", "future schema_version rejected")
	var with_float := LevelData.sanitize({
		"schema_version": 1.5, "id": "x", "name": "Half", "base_map": "crossroads",
		"player_start": [10, 10], "placeables": [],
	})
	_check(not with_float.is_empty(), "sanitize keeps 1.5 for validate")
	_check(LevelData.validate_playable(with_float) == "unsupported schema_version", "schema 1.5 rejected")
	var junk := LevelData.from_json("not-json")
	_check(junk.is_empty(), "bad json yields empty")


func _check_caps() -> void:
	# Use blank_m so base rails are 0 until Maps lands LAYOUTS entries.
	var level := LevelData.make_empty("Caps", "blank_m")
	var pieces: Array = []
	for i in LevelData.MAX_PLACEABLES + 1:
		# Space farther than snap cell (40) so duplicate-cell checks do not fire first.
		pieces.append({"id": "prop_crates", "pos": [80.0 + float(i % 20) * 50.0, 80.0 + float(i / 20) * 50.0], "rot": 0.0, "snap": true, "data": {}})
	level.placeables = pieces
	_check(LevelData.validate_playable(level) == "too many placeables", "301 placeables rejected")
	level.placeables = pieces.slice(0, LevelData.MAX_PLACEABLES)
	_check(LevelData.validate_playable(level) == "", "exactly 300 placeables ok: %s" % LevelData.validate_playable(level))

	var spawn_level := LevelData.make_empty("SpawnCaps", "blank_m")
	var spawners: Array = []
	for i in LevelData.MAX_SPAWNERS + 1:
		spawners.append({
			"id": "spawner_zombie", "pos": [150.0 + float(i) * 50.0, 150.0], "rot": 0.0, "snap": true, "key": "s%d" % i,
			"data": {"enemy": "shambler", "count": 1, "rate": 2.5, "trigger": "level_start", "radius": 100.0, "source_spawner": ""},
		})
	spawn_level.placeables = spawners
	_check(LevelData.validate_playable(spawn_level) == "too many spawners", "25 spawners rejected")
	spawn_level.placeables = spawners.slice(0, LevelData.MAX_SPAWNERS)
	_check(LevelData.validate_playable(spawn_level) == "", "exactly 24 spawners on blank ok: %s" % LevelData.validate_playable(spawn_level))


func _check_sanitize_rejects() -> void:
	_check(LevelData.sanitize({"foo": 1}).is_empty(), "junk-only dict rejected")
	_check(LevelData.sanitize({}).is_empty(), "empty dict rejected")
	_check(LevelData.sanitize({
		"schema_version": 1, "id": "x", "name": "P", "base_map": "../../etc/passwd",
		"player_start": [10, 10], "placeables": [],
	}).is_empty(), "path-like base_map rejected")
	_check(LevelData.sanitize({
		"schema_version": 1, "id": "x", "name": "P", "base_map": "nope_map",
		"player_start": [10, 10], "placeables": [],
	}).is_empty(), "unknown base_map rejected")
	_check(LevelData.sanitize({
		"schema_version": 1, "id": "x", "name": "P", "base_map": "crossroads", "placeables": [],
	}).is_empty(), "missing player_start rejected by sanitize")
	_check(LevelData.sanitize({
		"schema_version": 1, "id": "x", "name": "P", "base_map": "crossroads",
		"player_start": [10, 10], "placeables": {"a": 1},
	}).is_empty(), "dict placeables rejected by sanitize")
	# validate on raw (unsanitized) must not return playable or SCRIPT ERROR
	_check(LevelData.validate_playable({"placeables": {"a": 1}}) != "", "validate rejects dict placeables")
	_check(LevelData.validate_playable({"foo": 1}) != "", "validate rejects junk")


func _check_type_safety() -> void:
	var cases: Array = [
		{"schema_version": 1, "id": "t", "name": "T", "base_map": "blank_m", "player_start": [null, "x"], "placeables": []},
		{"schema_version": 1, "id": "t", "name": "T", "base_map": "blank_m", "player_start": [[1, 2], [3]], "placeables": []},
		{"schema_version": 1, "id": "t", "name": "T", "base_map": "blank_m", "player_start": [{"a": 1}, 2], "placeables": []},
	]
	for raw: Dictionary in cases:
		var clean := LevelData.sanitize(raw)
		_check(clean.is_empty(), "bad player_start rejected without a script error")
	var with_bad_pos := LevelData.sanitize({
		"schema_version": 1, "id": "t", "name": "T", "base_map": "blank_m",
		"player_start": [100, 100],
		"placeables": [{"id": "building_box_s", "pos": [null, "x"], "rot": 0.0, "snap": true, "data": {}}],
	})
	_check(not with_bad_pos.is_empty() and (with_bad_pos.placeables as Array).is_empty(), "null/str pos dropped, no SCRIPT ERROR")
	var with_nan_rot := LevelData.sanitize({
		"schema_version": 1, "id": "t", "name": "T", "base_map": "blank_m",
		"player_start": [100, 100],
		"placeables": [{"id": "building_box_s", "pos": [200, 200], "rot": NAN, "snap": true, "data": {}}],
	})
	_check((with_nan_rot.placeables as Array).is_empty(), "NaN rot drops placeable")
	var with_dict_count := LevelData.sanitize({
		"schema_version": 1, "id": "t", "name": "T", "base_map": "blank_m",
		"player_start": [100, 100],
		"placeables": [{
			"id": "spawner_zombie", "pos": [200, 200], "rot": 0.0, "snap": true, "key": "z",
			"data": {"enemy": "shambler", "count": {"x": 1}, "rate": 2.5, "trigger": "level_start", "radius": 100.0},
		}],
	})
	_check(not with_dict_count.is_empty(), "dict spawner count does not SCRIPT ERROR")
	var cnt: int = int((with_dict_count.placeables as Array)[0].data.count)
	_check(cnt >= 0 and cnt <= LevelData.MAX_SPAWNER_COUNT, "dict count coerced safely")


func _check_bounds_and_finite() -> void:
	var huge := LevelData.make_empty("Huge", "blank_m")
	huge.size = [1e12, 1e12]
	huge.player_start = [5e11, 5e11]
	_check(LevelData.validate_playable(huge) == "size too large", "1e12 size rejected")
	var inf_level := LevelData.make_empty("Inf", "blank_m")
	inf_level.player_start = [INF, -INF]
	_check(LevelData.sanitize(inf_level).is_empty() or LevelData.validate_playable(LevelData.sanitize({
		"schema_version": 1, "id": "i", "name": "I", "base_map": "blank_m",
		"player_start": [INF, -INF], "placeables": [],
	})) != "", "Inf player_start rejected")
	_check(LevelData.sanitize({
		"schema_version": 1, "id": "i", "name": "I", "base_map": "blank_m",
		"player_start": [INF, 10], "placeables": [],
	}).is_empty(), "sanitize rejects Inf player_start")
	var overcount := LevelData.make_empty("OC", "blank_m")
	overcount.placeables = [{
		"id": "spawner_zombie", "pos": [200, 200], "rot": 0.0, "snap": true, "key": "z",
		"data": {"enemy": "shambler", "count": int(1e12), "rate": 2.5, "trigger": "level_start", "radius": 100.0},
	}]
	var sanitized_oc := LevelData.sanitize(overcount)
	_check(int((sanitized_oc.placeables as Array)[0].data.count) <= LevelData.MAX_SPAWNER_COUNT, "1e12 spawner count clamped")
	# validate raw unsanitized huge count
	overcount.placeables[0].data.count = int(1e12)
	_check(LevelData.validate_playable(overcount) == "spawner count out of range", "validate rejects 1e12 count")


func _check_overlap_and_duplicates() -> void:
	var level := LevelData.make_empty("Ov", "blank_m")
	var start: Array = level.player_start
	level.placeables = [
		{"id": "building_box_l", "pos": [float(start[0]), float(start[1])], "rot": 0.0, "snap": true, "data": {}},
	]
	_check(LevelData.validate_playable(level) == "solid overlaps player_start", "building on player_start rejected")
	level = LevelData.make_empty("Dup", "blank_m")
	level.placeables = [
		{"id": "prop_crates", "pos": [200, 200], "rot": 0.0, "snap": true, "key": "a", "data": {}},
		{"id": "prop_crates", "pos": [200, 200], "rot": 0.0, "snap": true, "key": "b", "data": {}},
	]
	_check(LevelData.validate_playable(level) == "duplicate placeable at cell", "duplicate id at same cell rejected")
	level = LevelData.make_empty("Keys", "blank_m")
	level.placeables = [
		{"id": "prop_crates", "pos": [200, 200], "rot": 0.0, "snap": true, "key": "same", "data": {}},
		{"id": "prop_barrier", "pos": [400, 400], "rot": 0.0, "snap": true, "key": "same", "data": {}},
	]
	_check(LevelData.validate_playable(level) == "duplicate placeable key", "duplicate keys rejected")
	level = LevelData.make_empty("Ghost", "blank_m")
	level.placeables = [{
		"id": "spawner_zombie", "pos": [200, 200], "rot": 0.0, "snap": true, "key": "z",
		"data": {"enemy": "shambler", "count": 1, "rate": 2.5, "trigger": "spawner_cleared", "source_spawner": "ghost", "radius": 100.0},
	}]
	_check(LevelData.validate_playable(level) == "spawner_cleared needs source_spawner", "ghost source_spawner rejected")
	level = LevelData.make_empty("Multi", "blank_m")
	level.placeables = [
		{"id": "player_start", "pos": [200, 200], "rot": 0.0, "snap": true, "data": {}},
		{"id": "player_start", "pos": [400, 400], "rot": 0.0, "snap": true, "data": {}},
	]
	_check(LevelData.validate_playable(level) == "multiple player_start markers", "multiple start markers rejected")


func _check_name_safety() -> void:
	var long_name := ""
	for i in 80:
		long_name += "A"
	var level := LevelData.make_empty(long_name, "blank_m")
	_check(str(level.name).length() <= LevelData.MAX_NAME_LEN, "make_empty caps name length")
	var dirty := LevelData.sanitize({
		"schema_version": 1, "id": "../../../.config/evil", "name": "hi\nthere/../x",
		"base_map": "blank_m", "player_start": [100, 100], "placeables": [],
	})
	_check(not dirty.is_empty(), "dirty name/id still sanitizes when otherwise valid")
	_check(not str(dirty.id).contains("..") and not str(dirty.id).contains("/"), "id strips path characters")
	_check(not str(dirty.name).contains("/") and not str(dirty.name).contains("\n"), "name strips control and path characters")
	_check(str(dirty.name).length() <= LevelData.MAX_NAME_LEN, "sanitized name respects max len")


func _check_base_spawn_rails() -> void:
	var cross := LevelData.base_spawn_rail_count("crossroads")
	_check(cross == 12, "crossroads reports 12 base spawn rails (got %d)" % cross)
	for blank_id: String in ["blank_s", "blank_m", "blank_l", "endless"]:
		_check(LevelData.base_spawn_rail_count(blank_id) == 0, "%s reports 0 rails" % blank_id)
	_check(LevelData.base_spawn_rail_count("nope") == 0, "unknown base reports 0 (must not use Layouts.build fallback)")
	_check(LevelData.base_spawn_rail_count("../../etc/passwd") == 0, "path-like base reports 0")
	# Exactly 12 placed + 12 base = 24 → OK; 13 placed → reject.
	var ok_level := LevelData.make_empty("RailsOK", "crossroads")
	var spawners_ok: Array = []
	for i in 12:
		spawners_ok.append({
			"id": "spawner_zombie", "pos": [200.0 + float(i) * 50.0, 200.0], "rot": 0.0, "snap": true, "key": "ok%d" % i,
			"data": {"enemy": "shambler", "count": 1, "rate": 2.5, "trigger": "level_start", "radius": 100.0, "source_spawner": ""},
		})
	ok_level.placeables = spawners_ok
	_check(LevelData.validate_playable(ok_level) == "", "crossroads + 12 placed spawners passes: %s" % LevelData.validate_playable(ok_level))
	var bad_level := LevelData.make_empty("RailsBad", "crossroads")
	var spawners_bad: Array = spawners_ok.duplicate(true)
	spawners_bad.append({
		"id": "spawner_zombie", "pos": [200.0 + 12.0 * 50.0, 200.0], "rot": 0.0, "snap": true, "key": "ok12",
		"data": {"enemy": "shambler", "count": 1, "rate": 2.5, "trigger": "level_start", "radius": 100.0, "source_spawner": ""},
	})
	bad_level.placeables = spawners_bad
	_check(LevelData.validate_playable(bad_level) == "too many spawners", "crossroads + 13 placed spawners rejected")


func _check_triggers_and_snap() -> void:
	var level := LevelData.make_empty("Snap", "blank_m")
	level.snap_cell = 80
	_check(LevelData.validate_playable(level) == "", "snap_cell 80 allowed")
	level.snap_cell = 55
	var cleaned := LevelData.sanitize(level)
	_check(int(cleaned.snap_cell) == 40, "invalid snap_cell coerced to 40")
	level = LevelData.make_empty("Trig", "blank_m")
	level.placeables = [{
		"id": "spawner_zombie", "pos": [200, 200], "rot": 0.0, "snap": true, "key": "z",
		"data": {"enemy": "shambler", "count": 1, "rate": 2.5, "trigger": "always", "radius": 100.0, "source_spawner": ""},
	}]
	var s := LevelData.sanitize(level)
	_check(str((s.placeables as Array)[0].data.trigger) == "level_start", "unknown trigger coerced to level_start")
	# prior soft defaults for wrong top-level types
	_check(LevelData.sanitize({
		"schema_version": 1, "id": "x", "name": "M", "base_map": "crossroads",
		"player_start": [10, 10], "placeables": [], "created": "no",
	}).get("created", -1) == 0, "bad created becomes 0")


func _check(ok: bool, what: String) -> void:
	print(("  PASS  " if ok else "  FAIL  ") + what)
	if not ok:
		failures.append(what)
