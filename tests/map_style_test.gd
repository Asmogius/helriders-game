extends SceneTree
## Outer Blocks map style switch (P4): flag off = no bake (code-drawn look),
## flag on = whole-map bake (background thread, cached per layout+variation),
## missing art = code-drawn fallback; lot data never moves decor seeds.

const Arena := preload("res://scripts/arena.gd")
const Layouts := preload("res://scripts/layouts.gd")
const MapArt := preload("res://scripts/map_art.gd")

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
	a.free()
	MapArt.max_texture_override = 2048
	a = _arena("lots", 4)
	a.finish_bake()
	_check((a._chunks as Array).size() == 4, "no 4096 textures: four chunks")
	a.free()
	MapArt.max_texture_override = 0
	a = _arena("lots", 5)
	a.finish_bake()
	_check((a._chunks as Array).size() == 1, "4096 textures: one map texture")
	a.free()
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
	print("MAP STYLE TEST PASSED" if failures == 0 else "MAP STYLE TEST FAILED (%d)" % failures)
	quit(0 if failures == 0 else 1)
