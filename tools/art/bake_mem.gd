extends SceneTree
## Peak RAM of one whole-map bake, measured in a fresh process (one layout per run):
##   godot --headless --path . -s res://tools/art/bake_mem.gd -- --layout=lots [--seed=N] [--single]
## Prints static memory before the bake, the process peak before and after it,
## and the rise of the peak caused by the bake. Tool only.

const Layouts := preload("res://scripts/layouts.gd")
const MapArt := preload("res://scripts/map_art.gd")
const Arena := preload("res://scripts/arena.gd")


func _initialize() -> void:
	var id := "lots"
	var vary := 4242
	var single := false
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--layout="):
			id = a.substr(9)
		elif a.begins_with("--seed="):
			vary = int(a.substr(7))
		elif a == "--single":
			single = true
	var arena := Arena.new()
	arena.setup(Layouts.build(id, vary | 1))
	var data := MapArt.snapshot(arena)
	var src := MapArt.load_sources()   # atlases loaded before the measurement window
	var use0 := OS.get_static_memory_usage()
	var peak0 := OS.get_static_memory_peak_usage()
	var t0 := Time.get_ticks_usec()
	var imgs := MapArt.bake_images(data, src, single)
	var ms := (Time.get_ticks_usec() - t0) / 1000.0
	var peak1 := OS.get_static_memory_peak_usage()
	var held := OS.get_static_memory_usage() - use0
	print("BAKEMEM layout=%s single=%s chunks=%d bake_ms=%.0f before_mb=%.1f peak_before_mb=%.1f peak_after_mb=%.1f bake_peak_rise_mb=%.1f result_held_mb=%.1f" % [
		id, str(single), imgs.size(), ms, use0 / 1048576.0, peak0 / 1048576.0, peak1 / 1048576.0,
		maxi(0, peak1 - use0) / 1048576.0 if peak1 > peak0 else -1.0, held / 1048576.0])
	imgs.clear()
	arena.free()
	quit()
