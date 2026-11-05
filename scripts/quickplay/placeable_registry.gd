extends RefCounted
## Quickplay placeable catalog (QP1). Data only: ids, footprints, categories,
## default spawner settings. Art fills tray icons; runtime factories land in
## later PRs. No mutable static state.
##
## QP7 (Maps): building / wreck / prop entries are the solids level_bake.gd
## turns into Arena boxes. Footprints match arena collision:
##   building_box_l is a Crossroads block, Rect2(180, 180, 420, 300)
##   building_box_m / _s are the smaller snap-aligned boxes (7×5 and 4×3 cells)
##   prop_wreck / prop_barrier / prop_crates match layouts.gd prop triples and
##   arena.gd _draw_prop kinds: 0 wreck 110×54, 1 barrier 150×36, 2 crates 64×64
## `solid` is false for markers, spawners and pickups (bake records those as
## start / spawn_points / barrel_spots, not collision).

const SNAP_CELL_DEFAULT := 40
const SNAP_CELL_COARSE := 80

const CATEGORIES := ["marker", "spawner", "building", "wreck", "prop", "pickup"]

## Cameron-approved v1 spawner triggers.
const TRIGGERS := ["level_start", "player_radius", "spawner_cleared"]

const ZOMBIE_ENEMIES := ["shambler", "brute", "tank", "boomer", "slimer"]
const RIG_ENEMIES := ["outrider", "bulwark", "gunner", "scrapper", "scrapper_gunner", "convoy", "patcher", "torcher", "sludger"]

## id -> entry. footprint is the snap / collision size in world units.
const CATALOG := {
	"player_start": {
		"category": "marker",
		"footprint": Vector2(80, 80),
		"snap_default": true,
		"solid": false,
		"prop_kind": -1,
		"tray_icon": "res://art/ui/quickplay/player_start.png",
		"data_defaults": {},
	},
	"spawner_zombie": {
		"category": "spawner",
		"footprint": Vector2(64, 64),
		"snap_default": true,
		"solid": false,
		"prop_kind": -1,
		"tray_icon": "res://art/ui/quickplay/spawner_zombie.png",
		"data_defaults": {
			"enemy": "shambler",
			"count": 6,
			"rate": 2.5,
			"trigger": "level_start",
			"radius": 400.0,
			"source_spawner": "",
		},
	},
	"spawner_rig": {
		"category": "spawner",
		"footprint": Vector2(96, 96),
		"snap_default": true,
		"solid": false,
		"prop_kind": -1,
		"tray_icon": "res://art/ui/quickplay/spawner_rig.png",
		"data_defaults": {
			"enemy": "outrider",
			"count": 1,
			"rate": 8.0,
			"trigger": "level_start",
			"radius": 500.0,
			"source_spawner": "",
		},
	},
	# --- QP7 (Maps): solids. Sizes are the boxes Arena.setup collides. ---
	"building_box_s": {
		"category": "building",
		"footprint": Vector2(160, 120),
		"snap_default": true,
		"solid": true,
		"prop_kind": -1,
		"tray_icon": "res://art/ui/quickplay/building_box_s.png",
		"data_defaults": {},
	},
	"building_box_m": {
		"category": "building",
		"footprint": Vector2(280, 200),
		"snap_default": true,
		"solid": true,
		"prop_kind": -1,
		"tray_icon": "res://art/ui/quickplay/building_box_m.png",
		"data_defaults": {},
	},
	"building_box_l": {
		"category": "building",
		"footprint": Vector2(420, 300),
		"snap_default": true,
		"solid": true,
		"prop_kind": -1,
		"tray_icon": "res://art/ui/quickplay/building_box_l.png",
		"data_defaults": {},
	},
	# Prop kinds match arena.gd _draw_prop: 0 wreck, 1 barrier, 2 crates.
	"prop_wreck": {
		"category": "wreck",
		"footprint": Vector2(110, 54),
		"snap_default": true,
		"solid": true,
		"prop_kind": 0,
		"tray_icon": "res://art/ui/quickplay/prop_wreck.png",
		"data_defaults": {"prop_kind": 0},
	},
	"prop_barrier": {
		"category": "prop",
		"footprint": Vector2(150, 36),
		"snap_default": true,
		"solid": true,
		"prop_kind": 1,
		"tray_icon": "res://art/ui/quickplay/prop_barrier.png",
		"data_defaults": {"prop_kind": 1},
	},
	"prop_crates": {
		"category": "prop",
		"footprint": Vector2(64, 64),
		"snap_default": true,
		"solid": true,
		"prop_kind": 2,
		"tray_icon": "res://art/ui/quickplay/prop_crates.png",
		"data_defaults": {"prop_kind": 2},
	},
	"barrel_fuel": {
		"category": "pickup",
		"footprint": Vector2(40, 40),
		"snap_default": true,
		"solid": false,
		"prop_kind": -1,
		"tray_icon": "res://art/ui/quickplay/barrel_fuel.png",
		"data_defaults": {"barrel": "fuel"},
	},
	"barrel_acid": {
		"category": "pickup",
		"footprint": Vector2(40, 40),
		"snap_default": true,
		"solid": false,
		"prop_kind": -1,
		"tray_icon": "res://art/ui/quickplay/barrel_acid.png",
		"data_defaults": {"barrel": "acid"},
	},
	"pickup_scrap": {
		"category": "pickup",
		"footprint": Vector2(48, 48),
		"snap_default": true,
		"solid": false,
		"prop_kind": -1,
		"tray_icon": "res://art/ui/quickplay/pickup_scrap.png",
		"data_defaults": {"scrap": 5},
	},
}


static func has_id(id: String) -> bool:
	return CATALOG.has(id)


static func get_entry(id: String) -> Dictionary:
	if not CATALOG.has(id):
		return {}
	var src: Dictionary = CATALOG[id]
	return {
		"id": id,
		"category": str(src.category),
		"footprint": src.footprint as Vector2,
		"snap_default": bool(src.snap_default),
		"solid": bool(src.get("solid", false)),
		"prop_kind": int(src.get("prop_kind", -1)),
		"tray_icon": str(src.tray_icon),
		"data_defaults": (src.data_defaults as Dictionary).duplicate(true),
	}


static func all_ids() -> Array[String]:
	var out: Array[String] = []
	for id: String in CATALOG:
		out.append(id)
	out.sort()
	return out


static func ids_in(category: String) -> Array[String]:
	var out: Array[String] = []
	for id: String in CATALOG:
		if str((CATALOG[id] as Dictionary).category) == category:
			out.append(id)
	out.sort()
	return out


static func is_spawner(id: String) -> bool:
	if not CATALOG.has(id):
		return false
	return str((CATALOG[id] as Dictionary).category) == "spawner"


static func is_known_trigger(trigger: String) -> bool:
	return TRIGGERS.has(trigger)


static func is_known_enemy(enemy: String, spawner_id: String) -> bool:
	if spawner_id == "spawner_zombie":
		return ZOMBIE_ENEMIES.has(enemy)
	if spawner_id == "spawner_rig":
		return RIG_ENEMIES.has(enemy)
	return ZOMBIE_ENEMIES.has(enemy) or RIG_ENEMIES.has(enemy)
