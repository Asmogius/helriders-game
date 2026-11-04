extends "res://tools/art/capture_step.gd"
## Shared base for the P4 map-corner shots (VISUAL_PLAN V5.5 style sample) in
## tools/art/captures/20x_map_*.gd. A shot sets `sample`, `zoom`, `at`, `crowd`.
## after() frees the map and turns the style flag back off for later shots.

var sample := true
var zoom := 0.84
var at := Vector2(750, 440)
var crowd := false
var _map: Node2D


func run(cap: SceneTree) -> void:
	if cap.garage != null:
		cap.garage.queue_free()
		cap.garage = null
	if cap.strip != null:
		cap.strip.queue_free()
		cap.strip = null
	var Arena := load("res://scripts/arena.gd")
	Arena.outer_blocks_style = sample
	_map = Node2D.new()
	cap.root.add_child(_map)
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
		_crowd(cap)


## Readability check: the player's rig and a pack of every zombie kind,
## frozen, standing on the decorated corner (road, kerb, lawn, near decor).
func _crowd(cap: SceneTree) -> void:
	var rig: Node2D = load("res://scripts/vehicle.gd").new()
	_map.add_child(rig)
	var profile: Node = cap.profile
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


func after(_cap: SceneTree) -> void:
	if _map != null and is_instance_valid(_map):
		_map.queue_free()
	_map = null
	load("res://scripts/arena.gd").outer_blocks_style = false
