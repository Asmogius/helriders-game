extends SceneTree
## Outer Blocks map style switch (P4): flag off = no bake (code-drawn look),
## flag on = whole-map bake (background thread, cached per layout+variation),
## missing art = code-drawn fallback; lot data never moves decor seeds.

const Arena := preload("res://scripts/arena.gd")
const Layouts := preload("res://scripts/layouts.gd")
const MapArt := preload("res://scripts/map_art.gd")
const Missions := preload("res://scripts/missions.gd")

var failures := 0


func _check(ok: bool, what: String) -> void:
	if not ok:
		failures += 1
		printerr("FAIL: ", what)


func _arena(id: String, vary: int) -> Arena:
	var a := Arena.new()
	a.setup(Layouts.build(id, vary))
	root.add_child(a)
	return a


func _initialize() -> void:
	_run.call_deferred()   # root joins the tree after _initialize


func _run() -> void:
	var profile := root.get_node("Profile")
	profile.persist = false
	profile.new_game()
	Arena.outer_blocks_style = false
	var a := _arena("lots", 3)
	_check(not a.is_baking() and not a.is_styled(), "flag off: no bake, code-drawn")
	a.free()
	Arena.outer_blocks_style = true
	a = _arena("alleys", 3)
	_check(not a.is_baking() and not a.is_styled(), "flag on, other district: code-drawn")
	a.free()
	a = _arena("lots", 3)
	_check(a.is_baking(), "flag on: bake runs in the background")
	a.finish_bake()
	_check(a.is_styled() and a.bake_bytes > 0 and not a.bake_cached, "flag on: baked")
	a.free()
	a = _arena("lots", 3)
	_check(a.is_styled() and a.bake_cached and not a.is_baking(), "restart: same map comes from the cache")
	_check((a._chunks as Array).size() == (1 if MapArt.max_texture_size() >= 4096 else 4), "default: one texture only on a confirmed 4096 query")
	a.free()
	MapArt.max_texture_override = 2048
	a = _arena("lots", 4)
	a.finish_bake()
	_check((a._chunks as Array).size() == 4, "no 4096 textures: four chunks")
	a.free()
	MapArt.max_texture_override = 4096
	a = _arena("lots", 5)
	a.finish_bake()
	_check((a._chunks as Array).size() == 1, "confirmed 4096 textures: one map texture")
	a.free()
	MapArt.max_texture_override = 0
	if RenderingServer.get_rendering_device() == null:
		_check(MapArt.max_texture_size() == 0, "no query (Compatibility): size 0, chunks")
	# Quitting mid-bake must not block on the worker.
	a = _arena("gas_station", 11)
	var t0 := Time.get_ticks_usec()
	a.free()
	_check(Time.get_ticks_usec() - t0 < 20000, "quit mid-bake returns at once")
	Arena.clear_cache()
	_check(Arena._cache_chunks.is_empty(), "clear_cache drops the map")
	MapArt.tiles_path = "res://art/map/missing_tiles"
	a = _arena("crossroads", 9)
	a.finish_bake()
	_check(not a.is_styled() and not a.is_baking(), "missing art: code-drawn fallback")
	a.free()
	MapArt.tiles_path = MapArt.TILES
	Arena.outer_blocks_style = false
	var l := Layouts.build("lots", 6)
	var bare := l.duplicate(true)
	bare.surfaces = []
	var a1 := Arena.new()
	a1.setup(l)
	var a2 := Arena.new()
	a2.setup(bare)
	_check(MapArt.seed_for(MapArt.snapshot(a1)) == MapArt.seed_for(MapArt.snapshot(a2)), "lot data does not move decor seeds")
	a1.free()
	a2.free()
	await _mission_hold()
	print("MAP STYLE TEST PASSED" if failures == 0 else "MAP STYLE TEST FAILED (%d)" % failures)
	quit(0 if failures == 0 else 1)


## The job start waits behind the loading screen while the styled map bakes.
func _mission_hold() -> void:
	Arena.outer_blocks_style = true
	Arena.clear_cache()
	var spec: Dictionary = Missions.default_mission().duplicate(true)
	spec["layout"] = "lots"
	spec["seed"] = 21
	var m: Node = (load("res://scenes/mission.tscn") as PackedScene).instantiate()
	m.set("mission_override", spec)
	m.set("auto_spawn_specials", false)
	root.add_child(m)
	_check(bool(m.loading_map) and paused and not m.arena.is_styled(), "style on: start held, tree paused, code-drawn map hidden")
	_check(bool(m.pad_button(JOY_BUTTON_START)) and m.menu == null, "pad buttons swallowed while loading")
	var frames := 0
	var t_end := Time.get_ticks_msec() + 15000
	while bool(m.loading_map) and Time.get_ticks_msec() < t_end:
		await process_frame
		frames += 1
	_check(not bool(m.loading_map) and not paused and m.arena.is_styled(), "start released once the map is baked (%d frames)" % frames)
	m.restart_job()
	await process_frame
	await process_frame
	var again: Node = null
	for n: Node in root.get_children():
		if n.has_method("restart_job"):
			again = n
	_check(again != null and not bool(again.loading_map) and again.arena.bake_cached, "restart: cached map, no hold")
	again.queue_free()
	await process_frame
	await process_frame
	_check(Arena._cache_chunks.is_empty(), "leaving the job frees the cached map")
	Arena.outer_blocks_style = false
	var off: Node = (load("res://scenes/mission.tscn") as PackedScene).instantiate()
	off.set("mission_override", spec)
	off.set("auto_spawn_specials", false)
	root.add_child(off)
	_check(not bool(off.loading_map) and not paused, "style off: no hold")
	off.queue_free()
	await process_frame
