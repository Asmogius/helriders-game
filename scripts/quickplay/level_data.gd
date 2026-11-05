extends RefCounted
## Quickplay level schema (QP1): sanitize, validate, JSON round-trip.
## Head Dev: schema_version/id/name/author/created/modified/base_map;
## caps 300 placeables / 24 spawners; snap 40 (option 80). Pure functions —
## no mutable static state, no disk IO (store is a later PR).

const T := preload("res://scripts/tuning.gd")
const Layouts := preload("res://scripts/layouts.gd")
const Registry := preload("res://scripts/quickplay/placeable_registry.gd")

const SCHEMA_VERSION := 1
const MAX_PLACEABLES := 300
const MAX_SPAWNERS := 24

## Blank / Endless bases Maps will add; accepted early so levels can name them.
const PLANNED_BASE_MAPS: Array[String] = ["blank_s", "blank_m", "blank_l", "endless"]

const _LEVEL_TYPES := {
	"schema_version": TYPE_FLOAT,
	"id": TYPE_STRING,
	"name": TYPE_STRING,
	"author": TYPE_STRING,
	"created": TYPE_FLOAT,
	"modified": TYPE_FLOAT,
	"base_map": TYPE_STRING,
	"size": TYPE_ARRAY,
	"seed": TYPE_FLOAT,
	"snap_cell": TYPE_FLOAT,
	"player_start": TYPE_ARRAY,
	"placeables": TYPE_ARRAY,
}

const _PLACEABLE_TYPES := {
	"id": TYPE_STRING,
	"pos": TYPE_ARRAY,
	"rot": TYPE_FLOAT,
	"snap": TYPE_BOOL,
	"data": TYPE_DICTIONARY,
	"key": TYPE_STRING,
}


## A fresh empty level dict ready for the editor (not yet playable until a start is set).
static func make_empty(level_name := "Untitled", base_map := Layouts.DEFAULT) -> Dictionary:
	var now := int(Time.get_unix_time_from_system())
	var size := T.WORLD_SIZE
	return {
		"schema_version": SCHEMA_VERSION,
		"id": _new_id(now),
		"name": level_name,
		"author": "",
		"created": now,
		"modified": now,
		"base_map": base_map if is_known_base_map(base_map) else Layouts.DEFAULT,
		"size": [size.x, size.y],
		"seed": 0,
		"snap_cell": Registry.SNAP_CELL_DEFAULT,
		"player_start": [size.x * 0.5, size.y * 0.5],
		"placeables": [],
	}


static func is_known_base_map(id: String) -> bool:
	if id == "":
		return false
	if Layouts.LAYOUTS.has(id):
		return true
	return PLANNED_BASE_MAPS.has(id)


static func known_base_maps() -> Array[String]:
	var out: Array[String] = []
	for id: String in Layouts.LAYOUTS:
		out.append(id)
	for id in PLANNED_BASE_MAPS:
		if not out.has(id):
			out.append(id)
	out.sort()
	return out


## Drop wrong-typed fields, unknown placeable ids, and normalize defaults.
## Unknown schema_version is kept so validate_playable can reject it.
static func sanitize(raw: Dictionary) -> Dictionary:
	if raw.is_empty():
		return {}
	var out := {}
	for key: Variant in raw:
		var k := str(key)
		var want: int = _LEVEL_TYPES.get(k, -1)
		var v: Variant = raw[key]
		var got := typeof(v)
		if want == -1:
			continue
		if got == want or (want == TYPE_FLOAT and got == TYPE_INT) or (want == TYPE_BOOL and got == TYPE_FLOAT):
			out[k] = v
	if not out.has("schema_version"):
		out["schema_version"] = SCHEMA_VERSION
	if not out.has("id") or str(out.id) == "":
		out["id"] = _new_id(int(Time.get_unix_time_from_system()))
	out["name"] = str(out.get("name", "Untitled"))
	out["author"] = str(out.get("author", ""))
	out["created"] = int(out.get("created", 0))
	out["modified"] = int(out.get("modified", out.created))
	var base := str(out.get("base_map", Layouts.DEFAULT))
	out["base_map"] = base if is_known_base_map(base) else Layouts.DEFAULT
	out["size"] = _clean_vec2_arr(out.get("size", [T.WORLD_SIZE.x, T.WORLD_SIZE.y]), T.WORLD_SIZE)
	out["seed"] = int(out.get("seed", 0))
	var snap := int(out.get("snap_cell", Registry.SNAP_CELL_DEFAULT))
	if snap != Registry.SNAP_CELL_DEFAULT and snap != Registry.SNAP_CELL_COARSE:
		snap = Registry.SNAP_CELL_DEFAULT
	out["snap_cell"] = snap
	out["player_start"] = _clean_vec2_arr(out.get("player_start", [T.WORLD_SIZE.x * 0.5, T.WORLD_SIZE.y * 0.5]), T.WORLD_SIZE * 0.5)
	var cleaned: Array = []
	var raw_placeables: Variant = out.get("placeables", [])
	if raw_placeables is Array:
		for raw_p: Variant in raw_placeables:
			var p := _sanitize_placeable(raw_p)
			if not p.is_empty():
				cleaned.append(p)
	out["placeables"] = cleaned
	out["schema_version"] = int(out.schema_version)
	return out


## Ids that were present in raw but dropped because they are not in the registry.
static func dropped_placeable_ids(raw: Dictionary) -> Array[String]:
	var dropped: Array[String] = []
	var seen := {}
	for raw_p: Variant in raw.get("placeables", []):
		if not raw_p is Dictionary:
			continue
		var id := str((raw_p as Dictionary).get("id", ""))
		if id == "" or Registry.has_id(id) or seen.has(id):
			continue
		seen[id] = true
		dropped.append(id)
	return dropped


## "" if the level can be played; otherwise a short reason.
static func validate_playable(level: Dictionary) -> String:
	if level.is_empty():
		return "empty level"
	if int(level.get("schema_version", -1)) != SCHEMA_VERSION:
		return "unsupported schema_version"
	if str(level.get("id", "")) == "":
		return "missing id"
	if str(level.get("name", "")).strip_edges() == "":
		return "missing name"
	if not is_known_base_map(str(level.get("base_map", ""))):
		return "unknown base_map"
	var size := arr_to_vec2(level.get("size", []), T.WORLD_SIZE)
	if size.x < 800.0 or size.y < 600.0:
		return "size too small"
	var snap := int(level.get("snap_cell", Registry.SNAP_CELL_DEFAULT))
	if snap != Registry.SNAP_CELL_DEFAULT and snap != Registry.SNAP_CELL_COARSE:
		return "invalid snap_cell"
	var start := arr_to_vec2(level.get("player_start", []), Vector2.INF)
	if start == Vector2.INF:
		return "missing player_start"
	if start.x < 0.0 or start.y < 0.0 or start.x > size.x or start.y > size.y:
		return "player_start out of bounds"
	var placeables: Array = level.get("placeables", [])
	if placeables.size() > MAX_PLACEABLES:
		return "too many placeables"
	var spawners := 0
	for p: Variant in placeables:
		if not p is Dictionary:
			return "bad placeable"
		var entry: Dictionary = p
		var pid := str(entry.get("id", ""))
		if not Registry.has_id(pid):
			return "unknown placeable id"
		var pos := arr_to_vec2(entry.get("pos", []), Vector2.INF)
		if pos == Vector2.INF:
			return "placeable missing pos"
		if pos.x < 0.0 or pos.y < 0.0 or pos.x > size.x or pos.y > size.y:
			return "placeable out of bounds"
		if Registry.is_spawner(pid):
			spawners += 1
			var err := _validate_spawner_data(pid, entry.get("data", {}))
			if err != "":
				return err
	if spawners > MAX_SPAWNERS:
		return "too many spawners"
	return ""


static func to_json(level: Dictionary) -> String:
	return JSON.stringify(sanitize(level), "\t")


static func from_json(text: String) -> Dictionary:
	var parsed: Variant = JSON.parse_string(text)
	if not parsed is Dictionary:
		return {}
	return sanitize(parsed)


static func vec2_to_arr(v: Vector2) -> Array:
	return [v.x, v.y]


static func arr_to_vec2(v: Variant, fallback: Vector2 = Vector2.ZERO) -> Vector2:
	if v is Vector2:
		return v
	if v is Array and (v as Array).size() >= 2:
		return Vector2(float((v as Array)[0]), float((v as Array)[1]))
	return fallback


static func _sanitize_placeable(raw_p: Variant) -> Dictionary:
	if not raw_p is Dictionary:
		return {}
	var raw: Dictionary = raw_p
	var id := str(raw.get("id", ""))
	if not Registry.has_id(id):
		return {}
	var entry := Registry.get_entry(id)
	var out := {
		"id": id,
		"pos": _clean_vec2_arr(raw.get("pos", [0, 0]), Vector2.ZERO),
		"rot": float(raw.get("rot", 0.0)),
		"snap": bool(raw.get("snap", entry.snap_default)),
		"data": _sanitize_data(id, raw.get("data", {})),
	}
	var key := str(raw.get("key", ""))
	if key != "":
		out["key"] = key
	return out


static func _sanitize_data(placeable_id: String, raw_data: Variant) -> Dictionary:
	var defaults: Dictionary = Registry.get_entry(placeable_id).data_defaults
	var out := defaults.duplicate(true)
	if not raw_data is Dictionary:
		return out
	var raw: Dictionary = raw_data
	for k: Variant in raw:
		var key := str(k)
		if not defaults.has(key) and key != "source_spawner" and key != "radius" and key != "enemy" and key != "count" and key != "rate" and key != "trigger" and key != "prop_kind" and key != "barrel" and key != "scrap":
			continue
		out[key] = raw[k]
	if Registry.is_spawner(placeable_id):
		var trigger := str(out.get("trigger", "level_start"))
		if not Registry.is_known_trigger(trigger):
			out["trigger"] = "level_start"
		var enemy := str(out.get("enemy", defaults.get("enemy", "shambler")))
		if not Registry.is_known_enemy(enemy, placeable_id):
			out["enemy"] = str(defaults.get("enemy", "shambler"))
		out["count"] = maxi(int(out.get("count", 0)), 0)
		out["rate"] = maxf(float(out.get("rate", 0.1)), 0.1)
		out["radius"] = maxf(float(out.get("radius", 0.0)), 0.0)
		out["source_spawner"] = str(out.get("source_spawner", ""))
	return out


static func _validate_spawner_data(placeable_id: String, data: Variant) -> String:
	if not data is Dictionary:
		return "spawner missing data"
	var d: Dictionary = data
	if not Registry.is_known_trigger(str(d.get("trigger", ""))):
		return "invalid spawner trigger"
	if not Registry.is_known_enemy(str(d.get("enemy", "")), placeable_id):
		return "invalid spawner enemy"
	if str(d.get("trigger", "")) == "spawner_cleared" and str(d.get("source_spawner", "")) == "":
		return "spawner_cleared needs source_spawner"
	return ""


static func _clean_vec2_arr(v: Variant, fallback: Vector2) -> Array:
	return vec2_to_arr(arr_to_vec2(v, fallback))


static func _new_id(now: int) -> String:
	# No static counter: time + a fresh rng keeps ids unique without leaked state.
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	return "lvl_%d_%d" % [now, rng.randi() % 1000000]
