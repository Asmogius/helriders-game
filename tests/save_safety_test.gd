extends SceneTree
## Headless test for save safety (bug hunt: a bad nested value wiped saves).
## Every corrupt case from the troubleshooter's fuzz loads without stopping
## partway and keeps the rest of the save; an unreadable save is copied to a
## timestamped .broken file (never overwritten) and the .bak is tried before a
## fresh start; a save from a newer version is refused and never written over;
## scrap from 1e400 is clamped.
##
## Run:  godot --headless --fixed-fps 60 --path . -s res://tests/save_safety_test.gd

const ProfileScript := preload("res://scripts/profile.gd")
const PATH := "user://helriders_save_safety_test.json"

var profile: ProfileScript
var failures: Array[String] = []

const CASES := [
	["storage_val_array", {"storage": {"scrap_plating": [1]}}],
	["levels_val_dict", {"levels": {"scrap_plating": {"a": 1}}}],
	["upgrades_val_array", {"upgrades": {"loot": [1]}}],
	["record_val_array", {"record": {"runs": [1]}}],
	["next_crew_id_bad", {"crew": [], "next_crew_id": [1]}],
	["crew_id_array", {"crew": [{"role": "gunner", "rarity": "Common", "id": [1], "xp": {"a": 1}, "perks": "x"}]}],
	["board_item", {"board": [{"type": [1], "skulls": "x"}, {"type": "clear", "skulls": [2], "seed": {"a": 1}, "reward": "lots"}]}],
	["active_mission_bad", {"active_mission": {"type": "clear", "skulls": {"x": 1}}, "run_active": true}],
	["expedition_team_bad", {"crew": [], "expeditions": [{"name": "x", "team": "abc", "days_left": [1]}]}],
	["exp_board_taken_list", {"exp_board": [{"name": "x", "taken": [1], "skulls": {"a": 1}}]}],
	["discovered_nested", {"discovered": {"parts": "abc"}}],
	["rig_bad", {"rig": {"chassis": [1], "weapons": "x"}}],
	["presets_bad", {"presets": [{"chassis": {"a": 1}}, 5, "x"]}],
	["saloon_bad_price", {"crew": [], "saloon": [{"role": "gunner", "rarity": "Common", "price": [1], "hired": "x"}]}],
	["lost_bad", {"crew": [], "lost": [{"role": "gunner", "rarity": "Rare", "back_in": [2]}], "rehire_pick": "x"}],
]


func _initialize() -> void:
	profile = root.get_node("Profile")
	profile.persist = false
	profile.new_game()
	_clean()
	profile.save_path = PATH
	profile.persist = true

	for c: Array in CASES:
		var data: Dictionary = (c[1] as Dictionary).duplicate(true)
		data["version"] = 1
		data["scrap"] = 9999
		data["day"] = 42
		_write(PATH, JSON.stringify(data))
		var ok := profile.load_game()
		_check(ok and profile.scrap == 9999 and profile.day == 42, "%s: loads, keeping the rest of the save (scrap %d, day %d)" % [c[0], profile.scrap, profile.day])
		_check(FileAccess.file_exists(PATH) and _broken_files().is_empty(), "%s: the save stays in place, nothing set aside" % c[0])

	# The original repro: the half-loaded state used to be saved mid-load.
	_clean()
	var orig := JSON.stringify({"version": 1, "scrap": 9999, "day": 42, "exp_board": [{"name": "x", "taken": [1]}]})
	_write(PATH, orig)
	_check(profile.load_game() and profile.scrap == 9999 and profile.day == 42, "troubleshooter repro: progress kept")
	_check(FileAccess.get_file_as_string(PATH) == orig, "...and the file isn't rewritten while it loads")

	# Unreadable save: copied aside (timestamped), the .bak loads.
	_clean()
	_write(PATH + ".bak", JSON.stringify({"version": 1, "scrap": 321, "day": 9}))
	_write(PATH, "{\"scrap\": 9, oops")
	_check(profile.load_game() and profile.scrap == 321 and profile.day == 9, "unreadable save: the .bak loads")
	var kept := _broken_files()
	_check(kept.size() == 1 and FileAccess.get_file_as_string(PATH.get_base_dir().path_join(kept[0])) == "{\"scrap\": 9, oops", "...and the unreadable file is kept as " + ", ".join(kept))
	_write(PATH, "still broken")
	profile.load_game()
	_check(_broken_files().size() == 2, "a second broken save gets its own copy (never clobbered)")

	# Nothing readable: both copied aside before the fresh start writes.
	_clean()
	_write(PATH, "not json")
	_write(PATH + ".bak", "nor this")
	_check(not profile.load_game(), "nothing readable: a fresh start")
	var both := _broken_files().map(func(f: String) -> String: return FileAccess.get_file_as_string(PATH.get_base_dir().path_join(f)))
	_check(both.has("not json") and both.has("nor this"), "...after keeping both the save and the .bak as .broken copies")

	# A newer save: refused, never overwritten.
	_clean()
	var future := JSON.stringify({"version": 99, "scrap": 5, "day": 7, "new_field": {"x": 1}})
	_write(PATH, future)
	_check(not profile.load_game() and profile.save_locked and profile.notice.contains("newer version"), "a save from a newer version is refused, with a notice")
	profile.new_game()
	profile.scrap = 1
	profile.save_game()
	_check(FileAccess.get_file_as_string(PATH) == future and not FileAccess.file_exists(PATH + ".bak"), "...and never written over")

	# Overflow.
	_clean()
	_write(PATH, "{\"version\": 1, \"scrap\": 1e400, \"day\": 1e300}")
	_check(profile.load_game() and profile.scrap == ProfileScript.MAX_SCRAP and profile.day >= 1, "scrap 1e400 is clamped to %d (not INT64_MIN): %d" % [ProfileScript.MAX_SCRAP, profile.scrap])

	_clean()
	profile.save_locked = false
	profile.persist = false
	profile.save_path = "user://helriders_save.json"
	if failures.is_empty():
		print("SAVE SAFETY TEST PASSED")
		quit(0)
	else:
		print("SAVE SAFETY TEST FAILED: %s" % ", ".join(failures))
		quit(1)


func _write(path: String, text: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(text)
	f.close()


func _broken_files() -> Array[String]:
	var out: Array[String] = []
	for f: String in DirAccess.get_files_at(PATH.get_base_dir()):
		if f.begins_with(PATH.get_file() + ".broken"):
			out.append(f)
	return out


func _clean() -> void:
	for ext: String in ["", ".bak", ".tmp"]:
		if FileAccess.file_exists(PATH + ext):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(PATH + ext))
	for f in _broken_files():
		DirAccess.remove_absolute(ProjectSettings.globalize_path(PATH.get_base_dir().path_join(f)))


func _check(ok: bool, what: String) -> void:
	print(("  PASS  " if ok else "  FAIL  ") + what)
	if not ok:
		failures.append(what)
