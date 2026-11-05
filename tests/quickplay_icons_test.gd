extends SceneTree
## QP3 tray icons for the quickplay level editor.
##
## The twelve paths are the placeable registry ids agreed with QP1
## (scripts/quickplay/placeable_registry.gd CATALOG tray_icon fields, PR #92).
## That script is not on main yet, so the ids are hardcoded. When QP1 merges,
## switch this list to iterating CATALOG instead of ICONS.
##
## Missing-icon fallback: a path that is not in the project still holds (the
## editor draws a colored rect and does not crash). A path that exists must
## load as a 64x64 Texture2D. This set ships all twelve, so fallback count is 0.
##
## Run:  godot --headless --fixed-fps 60 --path . -s res://tests/quickplay_icons_test.gd

const T := preload("res://scripts/tuning.gd")

const SIZE := 64
## Registry ids, in the QP1 catalog order. One PNG each under art/ui/quickplay/.
const ICONS: Array[String] = [
	"player_start", "spawner_zombie", "spawner_rig",
	"building_box_s", "building_box_m", "building_box_l",
	"prop_wreck", "prop_barrier", "prop_crates",
	"barrel_fuel", "barrel_acid", "pickup_scrap",
]

var failures: Array[String] = []


func _check(ok: bool, what: String) -> void:
	if ok:
		print("  PASS  ", what)
	else:
		failures.append(what)
		print("FAIL: ", what)


func _init() -> void:
	_run.call_deferred()


func _path(id: String) -> String:
	return "res://art/ui/quickplay/%s.png" % id


## Pixels close to `want` (alpha ignored, so COL_ACID_GROUND's alpha doesn't matter).
func _count(img: Image, want: Color) -> int:
	var n := 0
	for y in img.get_height():
		for x in img.get_width():
			var c := img.get_pixel(x, y)
			if c.a > 0.5 and absf(c.r - want.r) < 0.03 and absf(c.g - want.g) < 0.03 and absf(c.b - want.b) < 0.03:
				n += 1
	return n


func _run() -> void:
	var profile: Node = root.get_node("Profile")
	profile.persist = false
	profile.new_game()
	var loaded := 0
	var fallback := 0
	var coverage := {}
	var pixels: Array[PackedByteArray] = []
	for id in ICONS:
		var path := _path(id)
		if not ResourceLoader.exists(path):
			fallback += 1
			print("  FALLBACK  ", id, " (file missing; a colored rect stands in)")
			continue
		var tex := load(path) as Texture2D
		if tex == null:
			_check(false, id + ": file exists but did not load as Texture2D")
			continue
		loaded += 1
		_check(tex.get_width() == SIZE and tex.get_height() == SIZE, id + ": 64x64")
		var img := tex.get_image()
		_check(img != null and img.get_width() == SIZE, id + ": image readable")
		if img == null:
			continue
		var opaque := 0
		var clear := 0
		for y in img.get_height():
			for x in img.get_width():
				var a := img.get_pixel(x, y).a
				if a > 0.9:
					opaque += 1
				elif a < 0.1:
					clear += 1
		_check(opaque > 400, id + ": has a drawn silhouette (%d px)" % opaque)
		_check(clear > 400, id + ": keeps a transparent margin (%d px)" % clear)
		coverage[id] = opaque
		pixels.append(img.get_data())
		if id != "player_start":
			_check(_count(img, T.COL_CYAN) == 0, id + ": no player cyan (that colour is the start flag only)")
	_check(loaded + fallback == ICONS.size(), "every id loads or uses the missing-icon fallback")
	_check(fallback == 0, "all twelve icons are shipped (fallback is only for a missing file)")
	_check(loaded == ICONS.size(), "twelve textures loaded")
	var copies := 0
	for i in pixels.size():
		for j in i:
			if pixels[i] == pixels[j]:
				copies += 1
				_check(false, "icon %d is a copy of icon %d" % [i, j])
	_check(copies == 0 and pixels.size() == ICONS.size(), "all twelve icons differ")
	if coverage.has("building_box_s") and coverage.has("building_box_m") and coverage.has("building_box_l"):
		var s: int = coverage["building_box_s"]
		var m: int = coverage["building_box_m"]
		var l: int = coverage["building_box_l"]
		_check(s < m and m < l, "building icons grow with the box (s %d < m %d < l %d)" % [s, m, l])
	_sig("player_start", T.COL_CYAN, 80)
	_sig("player_start", T.COL_UI_ACCENT, 40)
	_sig("spawner_zombie", T.COL_ZOMBIE, 80)
	_sig("spawner_zombie", T.COL_ZOMBIE_EYE, 16)
	_sig("spawner_rig", T.COL_ENEMY, 80)
	_sig("spawner_rig", T.COL_UI_ACCENT, 40)
	_sig("prop_wreck", T.COL_RUST, 80)
	_sig("prop_wreck", T.COL_ENEMY, 0)
	_sig("prop_barrier", T.COL_ORANGE, 40)
	_sig("prop_crates", T.COL_RUST, 40)
	_sig("barrel_fuel", T.COL_ENEMY, 80)
	_sig("barrel_fuel", T.COL_ORANGE, 40)
	_sig("barrel_acid", T.COL_ACID_GROUND, 80)
	_sig("pickup_scrap", T.COL_RUST, 40)
	_sig("pickup_scrap", T.COL_STEEL, 40)
	_sig("pickup_scrap", T.COL_ORANGE, 4)
	if failures.is_empty():
		print("QUICKPLAY ICONS TEST PASSED")
	else:
		print("QUICKPLAY ICONS TEST FAILED (%d)" % failures.size())
	quit(0 if failures.is_empty() else 1)


func _sig(id: String, color: Color, at_least: int) -> void:
	var path := _path(id)
	if not ResourceLoader.exists(path):
		return
	var tex := load(path) as Texture2D
	if tex == null:
		return
	var n := _count(tex.get_image(), color)
	if at_least == 0:
		_check(n == 0, id + ": no %s pixels" % color)
	else:
		_check(n >= at_least, "%s: %d px of signature colour (want >= %d)" % [id, n, at_least])
