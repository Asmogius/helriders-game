extends RefCounted
## QP7: bake a Quickplay level dict into a layout dict Arena.setup can consume
## (start, buildings, props, roads, checkpoints, barrel_spots, spawn_points).
##
## Solids — Arena builds one collision box each:
##   building -> buildings as Rect2. `pos` is the center. Arena buildings are
##   axis-aligned, so rotation snaps to 90° steps and an odd quarter-turn
##   swaps the catalog footprint.
##   wreck, prop -> props as [center, size, rotation, kind]. Kind is
##   0 wreck, 1 barrier, 2 crates (arena.gd _draw_prop). Rotation is kept
##   (the collision shape turns with it). Size stays the catalog footprint.
## Not solids (no collision box; runtime spawn/pickup is a later PR):
##   marker -> layout.start comes from the level's player_start field only.
##   spawner -> position appended to spawn_points.
##   pickup -> no box. barrel_fuel / barrel_acid positions append to
##   barrel_spots. pickup_scrap is skipped (no layout field for it yet).
## A solid that intersects the player-start pad (the player_start footprint
## centered on start) is dropped, including solids inherited from the base
## map, so the rig does not spawn inside geometry.
## A known base_map goes through Layouts.build (seed 0 = as drawn). Planned
## blanks and any other accepted base use a minimal synthetic layout on the
## same world size. Caps match the schema: at most MAX_PLACEABLES pieces are
## applied, and at most MAX_SPAWNERS of those become spawn points.

const T := preload("res://scripts/tuning.gd")
const Layouts := preload("res://scripts/layouts.gd")
const LevelData := preload("res://scripts/quickplay/level_data.gd")
const Registry := preload("res://scripts/quickplay/placeable_registry.gd")

## Categories that become Arena collision boxes. marker / spawner / pickup do not.
const SOLID_CATEGORIES: Array[String] = ["building", "wreck", "prop"]


static func bake(level: Dictionary) -> Dictionary:
	var clean := LevelData.sanitize(level)
	if clean.is_empty():
		clean = LevelData.make_empty()
	var base := str(clean.base_map)
	var out := _base_layout(base, int(clean.seed), str(clean.name))
	var start := LevelData.arr_to_vec2(clean.player_start, out.start as Vector2)
	out.start = start
	var pad := start_pad(start)
	var applied := 0
	var spawners := 0
	for raw_p: Variant in clean.placeables:
		if applied >= LevelData.MAX_PLACEABLES:
			break
		if not raw_p is Dictionary:
			continue
		applied += 1
		var piece: Dictionary = raw_p
		var entry := Registry.get_entry(str(piece.get("id", "")))
		if entry.is_empty():
			continue
		var category := str(entry.category)
		var pos := LevelData.arr_to_vec2(piece.get("pos", []), Vector2.ZERO)
		var rot := float(piece.get("rot", 0.0))
		if category == "spawner":
			if spawners >= LevelData.MAX_SPAWNERS:
				continue
			spawners += 1
			(out.spawn_points as Array).append(pos)
		elif category == "pickup":
			_add_barrel_spot(out, piece, entry, pos)
		elif not SOLID_CATEGORIES.has(category):
			pass
		elif category == "building":
			(out.buildings as Array).append(_building_rect(entry.footprint as Vector2, pos, rot))
		else:
			(out.props as Array).append(_prop_entry(entry, piece, pos, rot))
	_drop_solids_on_pad(out, pad)
	return out


## The open pad around the rig's spawn. Solids that touch it are not baked.
static func start_pad(start: Vector2) -> Rect2:
	var fp: Vector2 = Registry.get_entry("player_start").footprint
	if fp.x < 1.0 or fp.y < 1.0:
		fp = Vector2(80, 80)
	return Rect2(start - fp * 0.5, fp)


## True when a rotated prop box (center, size, radians) overlaps an axis-aligned rect.
static func prop_hits_rect(center: Vector2, size: Vector2, rot: float, rect: Rect2) -> bool:
	var half := size * 0.5
	var axes: Array[Vector2] = [
		Vector2.RIGHT,
		Vector2.DOWN,
		Vector2.RIGHT.rotated(rot),
		Vector2.DOWN.rotated(rot),
	]
	var prop_pts: Array[Vector2] = [
		center + Vector2(-half.x, -half.y).rotated(rot),
		center + Vector2(half.x, -half.y).rotated(rot),
		center + Vector2(half.x, half.y).rotated(rot),
		center + Vector2(-half.x, half.y).rotated(rot),
	]
	var r0 := rect.position
	var r1 := rect.end
	var rect_pts: Array[Vector2] = [r0, Vector2(r1.x, r0.y), r1, Vector2(r0.x, r1.y)]
	for axis: Vector2 in axes:
		if _separated(prop_pts, rect_pts, axis):
			return false
	return true


static func _base_layout(id: String, seed: int, level_name: String) -> Dictionary:
	if Layouts.LAYOUTS.has(id):
		return Layouts.build(id, seed)
	return {
		"id": id,
		"name": level_name,
		"start": T.WORLD_SIZE * 0.5,
		"buildings": [],
		"props": [],
		"roads": [],
		"checkpoints": [],
		"barrel_spots": [],
		"spawn_points": [],
		"district": "",
		"landmark": "",
		"arena": Rect2(Vector2.ZERO, T.WORLD_SIZE),
		"chokes": [],
		"blocks_used": 0,
		"surfaces": [],
	}


static func _building_rect(footprint: Vector2, center: Vector2, rot: float) -> Rect2:
	var size := footprint
	var quarter := posmod(int(round(rot / (PI * 0.5))), 4)
	if quarter == 1 or quarter == 3:
		size = Vector2(footprint.y, footprint.x)
	return Rect2(center - size * 0.5, size)


static func _prop_entry(entry: Dictionary, piece: Dictionary, pos: Vector2, rot: float) -> Array:
	var kind := int(entry.get("prop_kind", 0))
	var data: Variant = piece.get("data", {})
	if data is Dictionary and (data as Dictionary).has("prop_kind"):
		kind = int((data as Dictionary).prop_kind)
	kind = clampi(kind, 0, 2)
	return [pos, entry.footprint as Vector2, rot, kind]


static func _add_barrel_spot(out: Dictionary, piece: Dictionary, entry: Dictionary, pos: Vector2) -> void:
	var barrel := ""
	var data: Variant = piece.get("data", {})
	if data is Dictionary and (data as Dictionary).has("barrel"):
		barrel = str((data as Dictionary).barrel)
	elif (entry.data_defaults as Dictionary).has("barrel"):
		barrel = str((entry.data_defaults as Dictionary).barrel)
	if barrel == "fuel" or barrel == "acid":
		(out.barrel_spots as Array).append(pos)


static func _drop_solids_on_pad(out: Dictionary, pad: Rect2) -> void:
	var buildings: Array = []
	for b: Rect2 in out.buildings:
		if not b.intersects(pad):
			buildings.append(b)
	out.buildings = buildings
	var props: Array = []
	for p: Array in out.props:
		if p.size() < 4 or prop_hits_rect(p[0], p[1], float(p[2]), pad):
			continue
		props.append(p)
	out.props = props


static func _separated(a: Array[Vector2], b: Array[Vector2], axis: Vector2) -> bool:
	var min_a := a[0].dot(axis)
	var max_a := min_a
	for p: Vector2 in a:
		var d := p.dot(axis)
		min_a = minf(min_a, d)
		max_a = maxf(max_a, d)
	var min_b := b[0].dot(axis)
	var max_b := min_b
	for p: Vector2 in b:
		var d := p.dot(axis)
		min_b = minf(min_b, d)
		max_b = maxf(max_b, d)
	return max_a < min_b or max_b < min_a
