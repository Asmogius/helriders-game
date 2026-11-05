extends RefCounted
## Quickplay level schema (QP1): sanitize, validate, JSON round-trip.
## Head Dev: schema_version/id/name/author/created/modified/base_map;
## caps 300 placeables / 24 spawners (base rails + placed); snap 40 (option 80).
## Pure functions — no mutable static state, no disk IO.

const T := preload("res://scripts/tuning.gd")
const Layouts := preload("res://scripts/layouts.gd")
const Registry := preload("res://scripts/quickplay/placeable_registry.gd")

const SCHEMA_VERSION := 1
const MAX_PLACEABLES := 300
const MAX_SPAWNERS := 24
const MAX_NAME_LEN := 48
const MAX_ID_LEN := 64
const MAX_AUTHOR_LEN := 48
const MAX_SPAWNER_COUNT := 500       # emitted units per spawner
const MAX_SPAWNER_RATE := 120.0
const MIN_SPAWNER_RATE := 0.1
const MAX_SPAWNER_RADIUS := 4000.0
const MIN_SIZE := Vector2(800, 600)

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


## A fresh empty level dict ready for the editor.
static func make_empty(level_name := "Untitled", base_map := Layouts.DEFAULT) -> Dictionary:
	var now := int(Time.get_unix_time_from_system())
	var size := T.WORLD_SIZE
	var base := base_map if is_known_base_map(base_map) else Layouts.DEFAULT
	return {
		"schema_version": SCHEMA_VERSION,
		"id": _new_id(now),
		"name": _clean_name(level_name),
		"author": "",
		"created": now,
		"modified": now,
		"base_map": base,
		"size": [size.x, size.y],
		"seed": 0,
		"snap_cell": Registry.SNAP_CELL_DEFAULT,
		"player_start": [size.x * 0.5, size.y * 0.5],
		"placeables": [],
	}


static func is_known_base_map(id: String) -> bool:
	if id == "" or not _is_safe_token(id):
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


## Spawn rails the base_map contributes toward MAX_SPAWNERS.
## Matches LevelBake.base_spawn_count (#106): blank_s/m/l and endless = 0,
## unknown = 0, crossroads = 12. Must check LAYOUTS.has before Layouts.build
## (build falls back to crossroads for unknown ids). Prefer LevelBake.base_spawn_count
## once #106 is on the branch.
static func base_spawn_rail_count(base_map: String) -> int:
	# Planned Quickplay canvases: Maps #104 empties them; always 0 here too.
	if PLANNED_BASE_MAPS.has(base_map):
		return 0
	if not Layouts.LAYOUTS.has(base_map):
		return 0
	var layout: Dictionary = Layouts.build(base_map, 0)
	var pts: Variant = layout.get("spawn_points", [])
	return pts.size() if pts is Array else 0


## World size for this level (clamped). Bake should use this, not T.WORLD_SIZE alone.
static func world_size_of(level: Dictionary) -> Vector2:
	return arr_to_vec2(level.get("size", []), T.WORLD_SIZE)


## Sanitize + require known base_map and a finite player_start.
## Returns {} on junk / unknown base_map / missing or bad player_start / bad placeables type.
## Does NOT invent a playable crossroads level from garbage.
static func sanitize(raw: Dictionary) -> Dictionary:
	if raw.is_empty():
		return {}
	# Refuse wrong-typed placeables up front (dict masquerading as list, etc.).
	if raw.has("placeables") and not raw.placeables is Array:
		return {}
	var out := {}
	for key: Variant in raw:
		var k := str(key)
		var want: int = _LEVEL_TYPES.get(k, -1)
		var v: Variant = raw[key]
		var got := typeof(v)
		if want == -1:
			continue
		if got == want or (want == TYPE_FLOAT and got == TYPE_INT):
			out[k] = v
	# schema_version: missing -> current; non-int-equal-to-1 kept for validate to reject.
	if not out.has("schema_version"):
		out["schema_version"] = SCHEMA_VERSION
	elif not _is_exact_schema(out.schema_version):
		# Keep 1.5 / 2 / etc. so validate_playable rejects; never int-truncate into 1.
		if typeof(out.schema_version) != TYPE_FLOAT and typeof(out.schema_version) != TYPE_INT:
			return {}
	else:
		out["schema_version"] = SCHEMA_VERSION

	# base_map required and known — never silently rewrite to crossroads.
	if not out.has("base_map") or typeof(out.base_map) != TYPE_STRING:
		return {}
	var base := str(out.base_map)
	if not is_known_base_map(base):
		return {}
	out["base_map"] = base

	# player_start required, finite, in-range of declared size (checked fully in validate).
	if not out.has("player_start"):
		return {}
	var start := _finite_vec2(out.player_start)
	if start == Vector2.INF:
		return {}
	out["player_start"] = vec2_to_arr(start)

	# id / name / author
	var id := _clean_id(str(out.get("id", "")))
	if id == "":
		id = _new_id(int(Time.get_unix_time_from_system()))
	out["id"] = id
	if not out.has("name") or typeof(out.name) != TYPE_STRING:
		return {}
	var nm := _clean_name(str(out.name))
	if nm == "":
		return {}
	out["name"] = nm
	out["author"] = _clean_name(str(out.get("author", "")), MAX_AUTHOR_LEN, true)

	out["created"] = _safe_int(out.get("created", 0), 0)
	out["modified"] = _safe_int(out.get("modified", out.created), int(out.created))
	out["seed"] = _safe_int(out.get("seed", 0), 0)

	var size := _finite_vec2(out.get("size", [T.WORLD_SIZE.x, T.WORLD_SIZE.y]))
	if size == Vector2.INF:
		size = T.WORLD_SIZE
	out["size"] = vec2_to_arr(size)

	var snap := _safe_int(out.get("snap_cell", Registry.SNAP_CELL_DEFAULT), Registry.SNAP_CELL_DEFAULT)
	if snap != Registry.SNAP_CELL_DEFAULT and snap != Registry.SNAP_CELL_COARSE:
		snap = Registry.SNAP_CELL_DEFAULT
	out["snap_cell"] = snap

	var cleaned: Array = []
	for raw_p: Variant in out.get("placeables", []):
		var p := _sanitize_placeable(raw_p)
		if not p.is_empty():
			cleaned.append(p)
	out["placeables"] = cleaned
	return out


## Ids present in raw but dropped as unknown (raw.placeables must be an Array).
static func dropped_placeable_ids(raw: Dictionary) -> Array[String]:
	var dropped: Array[String] = []
	var seen := {}
	var raw_placeables: Variant = raw.get("placeables", [])
	if not raw_placeables is Array:
		return dropped
	for raw_p: Variant in raw_placeables:
		if not raw_p is Dictionary:
			continue
		var id := str((raw_p as Dictionary).get("id", ""))
		if id == "" or Registry.has_id(id) or seen.has(id):
			continue
		seen[id] = true
		dropped.append(id)
	return dropped


## "" if the level can be played; otherwise a short reason. Never returns "" on an error path.
static func validate_playable(level: Dictionary) -> String:
	if level.is_empty():
		return "empty level"
	if not level is Dictionary:
		return "not a level"
	# Wrong-typed placeables must not crash or look playable.
	var placeables_v: Variant = level.get("placeables", [])
	if not placeables_v is Array:
		return "bad placeables"
	if not _is_exact_schema(level.get("schema_version", -1)):
		return "unsupported schema_version"
	var id := str(level.get("id", ""))
	if id == "" or not _is_safe_token(id):
		return "missing id"
	var nm := str(level.get("name", "")).strip_edges()
	if nm == "":
		return "missing name"
	if nm.length() > MAX_NAME_LEN:
		return "name too long"
	var base := str(level.get("base_map", ""))
	if not is_known_base_map(base):
		return "unknown base_map"
	var size := _finite_vec2(level.get("size", []))
	if size == Vector2.INF:
		return "invalid size"
	if size.x < MIN_SIZE.x or size.y < MIN_SIZE.y:
		return "size too small"
	if size.x > T.WORLD_SIZE.x or size.y > T.WORLD_SIZE.y:
		return "size too large"
	var snap := _safe_int(level.get("snap_cell", Registry.SNAP_CELL_DEFAULT), -1)
	if snap != Registry.SNAP_CELL_DEFAULT and snap != Registry.SNAP_CELL_COARSE:
		return "invalid snap_cell"
	var start := _finite_vec2(level.get("player_start", []))
	if start == Vector2.INF:
		return "missing player_start"
	if start.x < 0.0 or start.y < 0.0 or start.x > size.x or start.y > size.y:
		return "player_start out of bounds"
	var placeables: Array = placeables_v
	if placeables.size() > MAX_PLACEABLES:
		return "too many placeables"
	var spawners := 0
	var keys_seen := {}
	var cell_ids_seen := {}
	var start_markers := 0
	var start_pad := _start_pad(start)
	for p: Variant in placeables:
		if not p is Dictionary:
			return "bad placeable"
		var entry: Dictionary = p
		var pid := str(entry.get("id", ""))
		if not Registry.has_id(pid):
			return "unknown placeable id"
		var pos := _finite_vec2(entry.get("pos", []))
		if pos == Vector2.INF:
			return "placeable missing pos"
		if pos.x < 0.0 or pos.y < 0.0 or pos.x > size.x or pos.y > size.y:
			return "placeable out of bounds"
		var rot_v: Variant = entry.get("rot", 0.0)
		if not _is_finite_number(rot_v):
			return "invalid rotation"
		var key := str(entry.get("key", ""))
		if key != "":
			if keys_seen.has(key):
				return "duplicate placeable key"
			keys_seen[key] = true
		var cell := _snap_cell(pos, snap if snap > 0 else Registry.SNAP_CELL_DEFAULT)
		var cell_key := "%s:%d:%d" % [pid, cell.x, cell.y]
		if cell_ids_seen.has(cell_key):
			return "duplicate placeable at cell"
		cell_ids_seen[cell_key] = true
		if pid == "player_start":
			start_markers += 1
		var reg := Registry.get_entry(pid)
		var category := str(reg.get("category", ""))
		if category == "building" or category == "wreck" or category == "prop":
			var fp: Vector2 = reg.footprint
			var solid := Rect2(pos - fp * 0.5, fp)
			if solid.intersects(start_pad):
				return "solid overlaps player_start"
		if Registry.is_spawner(pid):
			spawners += 1
			var err := _validate_spawner_data(pid, entry.get("data", {}), keys_seen)
			if err != "":
				return err
	if start_markers > 1:
		return "multiple player_start markers"
	var total_spawners := spawners + base_spawn_rail_count(base)
	if total_spawners > MAX_SPAWNERS:
		return "too many spawners"
	# spawner_cleared sources must resolve (second pass once keys are known)
	for p: Variant in placeables:
		var entry: Dictionary = p
		if not Registry.is_spawner(str(entry.get("id", ""))):
			continue
		var data: Variant = entry.get("data", {})
		if not data is Dictionary:
			continue
		var d: Dictionary = data
		if str(d.get("trigger", "")) != "spawner_cleared":
			continue
		var src := str(d.get("source_spawner", ""))
		if src == "" or not keys_seen.has(src):
			return "spawner_cleared needs source_spawner"
	return ""


static func to_json(level: Dictionary) -> String:
	var clean := sanitize(level)
	if clean.is_empty():
		return ""
	return JSON.stringify(clean, "\t")


static func from_json(text: String) -> Dictionary:
	var parsed: Variant = JSON.parse_string(text)
	if not parsed is Dictionary:
		return {}
	return sanitize(parsed)


static func vec2_to_arr(v: Vector2) -> Array:
	return [v.x, v.y]


static func arr_to_vec2(v: Variant, fallback: Vector2 = Vector2.ZERO) -> Vector2:
	var got := _finite_vec2(v)
	return fallback if got == Vector2.INF else got


# --- internals -------------------------------------------------------------------

static func _is_exact_schema(v: Variant) -> bool:
	if typeof(v) == TYPE_INT:
		return int(v) == SCHEMA_VERSION
	if typeof(v) == TYPE_FLOAT:
		return is_equal_approx(float(v), float(SCHEMA_VERSION))
	return false


static func _finite_vec2(v: Variant) -> Vector2:
	if v is Vector2:
		var vv: Vector2 = v
		if _is_finite_f(vv.x) and _is_finite_f(vv.y):
			return vv
		return Vector2.INF
	if v is Array:
		var a: Array = v
		if a.size() < 2:
			return Vector2.INF
		if not _is_finite_number(a[0]) or not _is_finite_number(a[1]):
			return Vector2.INF
		return Vector2(float(a[0]), float(a[1]))
	return Vector2.INF


static func _is_finite_number(v: Variant) -> bool:
	var t := typeof(v)
	if t == TYPE_INT:
		return true
	if t == TYPE_FLOAT:
		return _is_finite_f(float(v))
	return false


static func _is_finite_f(f: float) -> bool:
	return not is_nan(f) and not is_inf(f)


static func _safe_int(v: Variant, fallback: int) -> int:
	if typeof(v) == TYPE_INT:
		return int(v)
	if typeof(v) == TYPE_FLOAT and _is_finite_f(float(v)):
		return int(v)
	return fallback


static func _safe_float(v: Variant, fallback: float) -> float:
	if not _is_finite_number(v):
		return fallback
	return float(v)


static func _sanitize_placeable(raw_p: Variant) -> Dictionary:
	if not raw_p is Dictionary:
		return {}
	var raw: Dictionary = raw_p
	if typeof(raw.get("id", null)) != TYPE_STRING:
		return {}
	var id := str(raw.id)
	if not Registry.has_id(id):
		return {}
	var entry := Registry.get_entry(id)
	var pos := _finite_vec2(raw.get("pos", null))
	if pos == Vector2.INF:
		return {}
	var rot := _safe_float(raw.get("rot", 0.0), INF)
	if not _is_finite_f(rot):
		return {}
	# Normalize to (-PI, PI]
	rot = wrapf(rot, -PI, PI)
	var snap := bool(raw.get("snap", entry.snap_default)) if typeof(raw.get("snap", entry.snap_default)) == TYPE_BOOL else bool(entry.snap_default)
	var out := {
		"id": id,
		"pos": vec2_to_arr(pos),
		"rot": rot,
		"snap": snap,
		"data": _sanitize_data(id, raw.get("data", {})),
	}
	if raw.has("key") and typeof(raw.key) == TYPE_STRING:
		var key := _clean_id(str(raw.key))
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
		if not defaults.has(key) and not ["source_spawner", "radius", "enemy", "count", "rate", "trigger", "prop_kind", "barrel", "scrap"].has(key):
			continue
		out[key] = raw[k]
	if Registry.is_spawner(placeable_id):
		var trigger := str(out.get("trigger", "level_start"))
		if not Registry.is_known_trigger(trigger):
			out["trigger"] = "level_start"
		var enemy := str(out.get("enemy", defaults.get("enemy", "shambler")))
		if not Registry.is_known_enemy(enemy, placeable_id):
			out["enemy"] = str(defaults.get("enemy", "shambler"))
		var count := _safe_int(out.get("count", 0), 0)
		out["count"] = clampi(count, 0, MAX_SPAWNER_COUNT)
		var rate := _safe_float(out.get("rate", MIN_SPAWNER_RATE), MIN_SPAWNER_RATE)
		out["rate"] = clampf(rate, MIN_SPAWNER_RATE, MAX_SPAWNER_RATE)
		var radius := _safe_float(out.get("radius", 0.0), 0.0)
		out["radius"] = clampf(radius, 0.0, MAX_SPAWNER_RADIUS)
		out["source_spawner"] = _clean_id(str(out.get("source_spawner", "")))
	elif out.has("prop_kind"):
		out["prop_kind"] = clampi(_safe_int(out.get("prop_kind", 0), 0), 0, 2)
	elif out.has("scrap"):
		out["scrap"] = clampi(_safe_int(out.get("scrap", 0), 0), 0, 100000)
	return out


static func _validate_spawner_data(placeable_id: String, data: Variant, _keys_seen: Dictionary) -> String:
	if not data is Dictionary:
		return "spawner missing data"
	var d: Dictionary = data
	if not Registry.is_known_trigger(str(d.get("trigger", ""))):
		return "invalid spawner trigger"
	if not Registry.is_known_enemy(str(d.get("enemy", "")), placeable_id):
		return "invalid spawner enemy"
	var count := _safe_int(d.get("count", 0), -1)
	if count < 0 or count > MAX_SPAWNER_COUNT:
		return "spawner count out of range"
	var rate := _safe_float(d.get("rate", MIN_SPAWNER_RATE), -1.0)
	if rate < MIN_SPAWNER_RATE or rate > MAX_SPAWNER_RATE:
		return "spawner rate out of range"
	var radius := _safe_float(d.get("radius", 0.0), -1.0)
	if radius < 0.0 or radius > MAX_SPAWNER_RADIUS:
		return "spawner radius out of range"
	return ""


static func _start_pad(start: Vector2) -> Rect2:
	var fp: Vector2 = Registry.get_entry("player_start").footprint
	if fp.x < 1.0 or fp.y < 1.0:
		fp = Vector2(80, 80)
	return Rect2(start - fp * 0.5, fp)


static func _snap_cell(pos: Vector2, cell: int) -> Vector2i:
	var c := maxi(cell, 1)
	return Vector2i(int(floor(pos.x / float(c))), int(floor(pos.y / float(c))))


static func _clean_name(text: String, max_len := MAX_NAME_LEN, allow_empty := false) -> String:
	var out := ""
	for i in text.length():
		var ch := text[i]
		var code := ch.unicode_at(0)
		if code < 32 or code == 127:
			continue
		if ch == "/" or ch == "\\" or ch == ":" or ch == "*" or ch == "?" or ch == "\"" or ch == "<" or ch == ">" or ch == "|":
			continue
		if ch == "." and out.ends_with("."):
			continue
		out += ch
		if out.length() >= max_len:
			break
	out = out.strip_edges()
	while out.begins_with("."):
		out = out.substr(1)
	if out == "" and not allow_empty:
		return ""
	return out


static func _clean_id(text: String) -> String:
	var out := ""
	for i in text.length():
		var ch := text[i]
		var code := ch.unicode_at(0)
		var ok := (code >= 97 and code <= 122) or (code >= 65 and code <= 90) or (code >= 48 and code <= 57) or ch == "_" or ch == "-"
		if ok:
			out += ch
		if out.length() >= MAX_ID_LEN:
			break
	return out


static func _is_safe_token(text: String) -> bool:
	if text == "" or text.length() > MAX_ID_LEN:
		return false
	if text.contains("..") or text.contains("/") or text.contains("\\"):
		return false
	return _clean_id(text) == text


static func _new_id(now: int) -> String:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	return "lvl_%d_%d" % [now, rng.randi() % 1000000]
