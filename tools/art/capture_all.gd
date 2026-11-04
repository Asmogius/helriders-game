extends SceneTree
## Every-screen capture set for art review (VISUAL_PLAN P0). Needs a display:
##   xvfb-run -s "-screen 0 1280x720x24" godot --rendering-driver opengl3 --path . -s res://tools/art/capture_all.gd -- out_dir
## Writes into out_dir (default user://captures):
##   garage_<tab>.png for GARAGE, RESEARCH, SALOON, INN, COMMS
##   rarity_tiers.png  (all six rarity frames side by side)
##   art_swatches.png (every art-only colour in tuning.gd, named)
##   fight.png         (the mission scene after a few seconds)
##   map_outer_blocks_before.png / _after.png (P4 style sample corner), _full_* (whole
##   corner), _readability (rig + every zombie kind on the decorated corner)
## Optional second arg: only shots whose name starts with it, e.g. "map_".
## Uses a throwaway profile (persist = false), so no save is touched.
## Packages add their shots as new steps in `_steps()`.

const UI := preload("res://scripts/ui_theme.gd")
const T := preload("res://scripts/tuning.gd")

const TABS := ["GARAGE", "RESEARCH", "SALOON", "INN", "COMMS"]
const SETTLE := 12   # frames to wait before each shot

var _dir := "user://captures"
var _steps: Array[Callable] = []
var _names: Array[String] = []
var _step := -1
var _wait := 0
var _garage: Node
var _strip: Control


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_dir = args[0]
	DirAccess.make_dir_recursive_absolute(_dir)
	var profile: Node = root.get_node("Profile")
	profile.persist = false
	profile.new_game()
	# P1: own a schematic of each rarity there is, so frames show on cards.
	for id: String in ["courier_frame", "bulwark_frame", "hauler_frame"]:
		if not profile.schematics.has(id):
			profile.schematics.append(id)
	for t: String in TABS:
		_add("garage_" + t.to_lower(), _show_tab.bind(t))
	_add("garage_part_cards", _show_part_cards)
	_add("rarity_tiers", _show_rarity)
	# --- P4 map corner (VISUAL_PLAN V5.5 style sample) ---
	_add("map_outer_blocks_before", _show_map_corner.bind(false))
	_add("map_outer_blocks_after", _show_map_corner.bind(true))
	_add("map_outer_blocks_full_before", _show_map_corner.bind(false, 0.68, Vector2(750, 440)))
	_add("map_outer_blocks_full_after", _show_map_corner.bind(true, 0.68, Vector2(750, 440)))
	_add("map_outer_blocks_readability", _show_map_corner.bind(true, 1.2, Vector2(680, 640), true))
	_add("art_swatches", _show_swatches)
	_add("fight", _show_fight)
	_add("fight_crates", _show_crates)
	_add("results_finds", _show_finds)
	if args.size() > 1:
		var keep_names: Array[String] = []
		var keep_steps: Array[Callable] = []
		for i in _names.size():
			if _names[i].begins_with(args[1]):
				keep_names.append(_names[i])
				keep_steps.append(_steps[i])
		_names = keep_names
		_steps = keep_steps


func _add(shot: String, setup: Callable) -> void:
	_names.append(shot)
	_steps.append(setup)


func _show_tab(t: String) -> void:
	if _garage == null:
		_garage = (load("res://scenes/garage.tscn") as PackedScene).instantiate()
		root.add_child(_garage)
	_garage.show_tab(t)


func _show_part_cards() -> void:
	_garage.show_tab("GARAGE")
	_garage.open_slot(0)   # chassis: Common, Uncommon, Rare and Epic cards


func _show_rarity() -> void:
	_garage.queue_free()
	_garage = null
	_strip = Control.new()
	_strip.theme = UI.make()
	_strip.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(_strip)
	var bg := ColorRect.new()
	bg.color = UI.PANEL
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_strip.add_child(bg)
	for i in T.RARITY_ORDER.size():
		var r: String = T.RARITY_ORDER[i]
		var card := Panel.new()
		card.position = Vector2(40 + i * 205, 260)
		card.size = Vector2(185, 200)
		_strip.add_child(card)
		var l := UI.label(r, 24, UI.rarity_color(r))
		l.position = Vector2(14, 40)
		card.add_child(l)
		UI.rarity_frame(card, r).set("t", 1.0)   # shimmer mid-sweep for the shot


var _map: Node2D


func _show_map_corner(sample: bool, zoom := 0.84, at := Vector2(750, 440), crowd := false) -> void:
	for n: Node in [_garage, _strip, _map]:
		if n != null and is_instance_valid(n):
			n.queue_free()
	_garage = null
	_strip = null
	var Arena := load("res://scripts/arena.gd")
	Arena.outer_blocks_style = sample
	_map = Node2D.new()
	root.add_child(_map)
	var arena: Node2D = Arena.new()
	_map.add_child(arena)
	if arena.has_method("finish_bake"):
		arena.finish_bake()   # the bake runs on a worker; shoot the finished map
	var cam := Camera2D.new()
	cam.position = at
	cam.zoom = Vector2(zoom, zoom)
	_map.add_child(cam)
	cam.make_current()
	if crowd:
		_crowd(at)


## Readability check: the player's rig and a pack of every zombie kind,
## frozen, standing on the decorated corner (road, kerb, lawn, near decor).
func _crowd(at: Vector2) -> void:
	var rig: Node2D = load("res://scripts/vehicle.gd").new()
	_map.add_child(rig)
	var profile: Node = root.get_node("Profile")
	rig.apply_stats(profile.build_stats(profile.rig if profile.has_rig() else load("res://scripts/parts.gd").STARTER_LOADOUT))
	rig.position = at + Vector2(40, 60)
	var dir: Node2D = load("res://scripts/zombie_director.gd").new()
	dir.start_count = 0
	_map.add_child(dir)
	var kinds := ["shambler", "shambler", "brute", "shambler", "slimer", "boomer", "shambler", "tank", "shambler", "shambler", "brute", "shambler"]
	var spots := [Vector2(-300, -70), Vector2(-250, -40), Vector2(-180, -130), Vector2(-120, -150), Vector2(-60, -200),
		Vector2(120, -170), Vector2(230, -110), Vector2(300, 40), Vector2(-330, 90), Vector2(-200, 150), Vector2(180, 170), Vector2(60, -60)]
	for i in kinds.size():
		var z: Node2D = dir.spawn_at(at + spots[i], kinds[i])
		if z != null:
			z.rotation = float(i) * 0.7
	dir.process_mode = Node.PROCESS_MODE_DISABLED


const SWATCHES := [
	"COL_OB_GRASS", "COL_OB_PAVE", "COL_OB_SIDING", "COL_OB_ROOF", "COL_OB_GRADE", "COL_OB_MOTE",
	"COL_FX_HOT", "COL_FX_WHITE_HOT", "COL_FX_EMBER", "COL_FX_SCORCH",
	"COL_FX_SCORCH_EDGE", "COL_FX_SMOKE",
	"COL_GARAGE_FLOOR", "COL_GARAGE_FLOOR_LINE", "COL_GARAGE_OIL", "COL_GARAGE_PEGBOARD",
	"COL_GARAGE_WALL", "COL_GARAGE_STREET_NIGHT", "COL_GARAGE_GAS_RED",
	"COL_GARAGE_DUST", "COL_GARAGE_SPARK",
	"COL_ZOMBIE_SHIRT_0", "COL_ZOMBIE_PANTS_0",
	"COL_ZOMBIE_SHIRT_1", "COL_ZOMBIE_PANTS_1",
	"COL_ZOMBIE_SHIRT_2", "COL_ZOMBIE_PANTS_2",
	"COL_ZOMBIE_SHIRT_3", "COL_ZOMBIE_PANTS_3",
	"COL_ZOMBIE_SHIRT_4", "COL_ZOMBIE_PANTS_4",
	"COL_ZOMBIE_SHIRT_5", "COL_ZOMBIE_PANTS_5",
	"COL_ZOMBIE_EYE", "COL_ZOMBIE_FLASH", "COL_TANK_SHIRT", "COL_TANK_PANTS", "COL_TANK_SKIN",
]


func _show_swatches() -> void:
	_strip.queue_free()
	_strip = Control.new()
	_strip.theme = UI.make()
	_strip.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(_strip)
	var bg := ColorRect.new()
	bg.color = T.COL_ROAD
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_strip.add_child(bg)
	var consts: Dictionary = T.new().get_script().get_script_constant_map()
	for i in SWATCHES.size():
		var n: String = SWATCHES[i]
		var pos := Vector2(16 + (i % 9) * 140, 16 + (i / 9) * 140)
		var sw := ColorRect.new()
		sw.color = consts[n]
		sw.position = pos
		sw.size = Vector2(130, 90)
		_strip.add_child(sw)
		var l := UI.label(n.trim_prefix("COL_"), 11, Color(0.9, 0.9, 0.88))
		l.position = pos + Vector2(0, 94)
		_strip.add_child(l)


func _show_fight() -> void:
	for n: Node in [_strip, _map]:
		if n != null and is_instance_valid(n):
			n.queue_free()
	load("res://scripts/arena.gd").outer_blocks_style = false
	change_scene_to_file("res://scenes/mission.tscn")


## One schematic crate per rarity in a row ahead of the rig (beams by tier).
func _show_crates() -> void:
	var m: Node = current_scene
	var Pickup: GDScript = load("res://scripts/pickup.gd")
	var at: Vector2 = m.vehicle.global_position + Vector2(-250, 150)
	for i in T.RARITY_ORDER.size():
		var p: Node2D = Pickup.new()
		p.part = {"name": T.RARITY_ORDER[i], "rarity": T.RARITY_ORDER[i], "category": "Weapon"}
		p.position = at + Vector2(i * 100, 0)
		m.pickups.add_child(p)
	m.hud.banner("SCHEMATIC: HAULER FRAME", UI.rarity_color("Epic"), 3.0)


func _show_finds() -> void:
	var hud: Node = current_scene.hud
	hud.show_result("JOB DONE", "Job pay +120    Kill scrap +45    Time 3:12", "RETURN TO GARAGE", T.COL_ORANGE)
	hud.show_finds([["New schematic: Courier Frame", "Uncommon"], ["New schematic: Bulwark Frame", "Rare"], ["New schematic: Hauler Frame", "Epic"]])


func _process(_delta: float) -> bool:
	if _wait > 0:
		_wait -= 1
		return false
	if _step >= 0:
		var path := "%s/%s.png" % [_dir, _names[_step]]
		root.get_texture().get_image().save_png(path)
		print("saved ", path)
	_step += 1
	if _step >= _steps.size():
		quit()
		return true
	_steps[_step].call()
	_wait = 150 if _names[_step] == "fight" else (70 if _names[_step] == "results_finds" else SETTLE)
	return false
