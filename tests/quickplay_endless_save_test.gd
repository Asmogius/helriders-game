extends SceneTree
## Quickplay QP5: level store atomic IO + EndlessProfile isolation from campaign.
##
## Run: godot --headless --fixed-fps 60 --path . -s res://tests/quickplay_endless_save_test.gd

const LevelData := preload("res://scripts/quickplay/level_data.gd")
const LevelStore := preload("res://scripts/quickplay/level_store.gd")
const EndlessProfile := preload("res://scripts/quickplay/endless_profile.gd")
const SandboxUnlock := preload("res://scripts/quickplay/sandbox_unlock.gd")
const ProfileScript := preload("res://scripts/profile.gd")
const Parts := preload("res://scripts/parts.gd")

const STORE_DIR := "user://quickplay_test_levels_qp5"
const ENDLESS_PATH := "user://helriders_endless_test_qp5.json"

var profile: ProfileScript
var failures: Array[String] = []


func _initialize() -> void:
	profile = root.get_node("Profile")
	profile.persist = false
	profile.new_game()
	_clean_store()
	_clean_endless()

	_check_level_store()
	_check_endless_isolation()
	_check_sandbox_unlock()
	_check_campaign_save_keys_untouched()

	_clean_store()
	_clean_endless()
	EndlessProfile.clear_tree(self)

	if failures.is_empty():
		print("QUICKPLAY ENDLESS SAVE TEST PASSED")
		quit(0)
	else:
		print("QUICKPLAY ENDLESS SAVE TEST FAILED: %s" % ", ".join(failures))
		quit(1)


func _check_level_store() -> void:
	var store := LevelStore.new()
	store.root_dir = STORE_DIR
	store.persist = true
	var level := LevelData.make_empty("Alpha Yard", "crossroads")
	level.author = "test"
	level.placeables = [{"id": "building_box_s", "pos": [200, 200], "rot": 0.0, "snap": true, "data": {}}]
	_check(store.save_level(level), "save_level writes")
	_check(FileAccess.file_exists(store.path_for(str(level.id))), "level file exists")
	var listed := store.list_levels()
	_check(listed.size() == 1 and str(listed[0].name) == "Alpha Yard", "list_levels finds the save")
	var loaded := store.load_level(str(level.id))
	_check(str(loaded.name) == "Alpha Yard" and (loaded.placeables as Array).size() == 1, "load_level round-trip")

	level.name = "Alpha Yard 2"
	store.save_level(level)
	_check(FileAccess.file_exists(store.path_for(str(level.id)) + ".bak"), "previous save kept as .bak")
	_check(str(store.load_level(str(level.id)).name) == "Alpha Yard 2", "loads the new name")

	# Corrupt the live file → bak fallback.
	_write(store.path_for(str(level.id)), "{not json")
	var recovered := store.load_level(str(level.id))
	_check(str(recovered.name) == "Alpha Yard", "corrupt level loads .bak")
	_check(FileAccess.file_exists(store.path_for(str(level.id)) + ".broken"), "broken file kept aside")

	# persist=false blocks writes.
	store.persist = false
	var other := LevelData.make_empty("NoWrite", "crossroads")
	_check(not store.save_level(other), "persist false blocks save")
	store.persist = true
	_check(store.delete_level(str(level.id)), "delete_level removes files")
	_check(store.list_levels().is_empty(), "list empty after delete")


func _check_endless_isolation() -> void:
	var campaign_scrap := int(profile.scrap)
	var campaign_day := int(profile.day)
	var before_keys := profile.save_data().keys()
	before_keys.sort()

	var endless := EndlessProfile.new()
	endless.persist = true
	endless.save_path = ENDLESS_PATH
	endless.new_profile()
	endless.bank_scrap(40)
	endless.record_run(7, 1200, true)
	endless.unlock_schematic("pintle_turret")
	_check(endless.scrap == 40 and endless.best_wave == 7 and endless.best_score == 1200, "endless banks scrap and bests")
	_check(endless.knows("pintle_turret"), "endless unlocks schematic")
	_check(int(profile.scrap) == campaign_scrap and int(profile.day) == campaign_day, "campaign scrap/day unchanged after endless writes")

	var again := EndlessProfile.new()
	again.persist = true
	again.save_path = ENDLESS_PATH
	_check(again.load_game() and again.scrap == 40 and again.best_wave == 7, "endless save reloads")

	# Atomic / bak behaviour.
	again.scrap = 99
	again.save_game()
	_check(int(EndlessProfile.read_save(ENDLESS_PATH + ".bak").get("scrap", 0)) == 40, "endless previous save is .bak")
	_write(ENDLESS_PATH, "{broken")
	again.notice = ""
	_check(again.load_game() and again.scrap == 40, "unreadable endless loads .bak")
	_check(again.notice != "" and FileAccess.file_exists(ENDLESS_PATH + ".broken"), "endless broken kept aside")

	# Tree-root cache (no static).
	var shared: RefCounted = EndlessProfile.from_tree(self)
	(shared as Object).set("scrap", 3)
	var shared2: RefCounted = EndlessProfile.from_tree(self)
	_check(int((shared2 as Object).get("scrap")) == 3, "from_tree returns the same instance")

	var after_keys := profile.save_data().keys()
	after_keys.sort()
	_check(str(before_keys) == str(after_keys), "campaign save_data keys unchanged by EndlessProfile")
	_check(not profile.save_data().has("best_wave") and not profile.save_data().has("starter_id"), "campaign save has no endless fields")


func _check_sandbox_unlock() -> void:
	profile.persist = true
	profile.save_path = "user://helriders_save_qp5_sandbox.json"
	_clean_path(profile.save_path)
	profile.new_game()
	var scrap_before := int(profile.scrap)
	var schem_before := profile.schematics.size()
	profile.save_game()
	var disk_before := FileAccess.get_file_as_string(profile.save_path)

	var snap := SandboxUnlock.begin(profile)
	_check(not profile.persist, "sandbox begin disables persist")
	_check(profile.schematics.size() == Parts.CATALOG.size(), "sandbox unlocks every schematic")
	_check(profile.schematics.size() > schem_before, "more schematics than a new game")
	profile.scrap = scrap_before + 999
	# Must not have rewritten the campaign file.
	var disk_mid := FileAccess.get_file_as_string(profile.save_path)
	_check(disk_mid == disk_before, "sandbox unlock writes no campaign save")

	SandboxUnlock.end(profile, snap, true)
	_check(profile.persist, "sandbox end restores persist")
	_check(int(profile.scrap) == scrap_before, "sandbox end restores scrap")
	_check(profile.schematics.size() == schem_before, "sandbox end restores schematics")
	_check(FileAccess.get_file_as_string(profile.save_path) == disk_before, "campaign file still untouched after end")
	_clean_path(profile.save_path)
	profile.persist = false
	profile.save_path = "user://helriders_save.json"


func _check_campaign_save_keys_untouched() -> void:
	var keys := profile.save_data().keys()
	for forbidden: String in ["best_wave", "best_score", "starter_id", "endless_scrap"]:
		_check(not keys.has(forbidden), "campaign save_data has no %s" % forbidden)


func _write(path: String, text: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(text)
	f.close()


func _clean_store() -> void:
	var abs := ProjectSettings.globalize_path(STORE_DIR)
	if DirAccess.dir_exists_absolute(abs):
		var dir := DirAccess.open(abs)
		if dir != null:
			dir.list_dir_begin()
			var n := dir.get_next()
			while n != "":
				if not dir.current_is_dir():
					DirAccess.remove_absolute(abs.path_join(n))
				n = dir.get_next()
			dir.list_dir_end()
		DirAccess.remove_absolute(abs)


func _clean_endless() -> void:
	_clean_path(ENDLESS_PATH)


func _clean_path(path: String) -> void:
	for ext: String in ["", ".bak", ".tmp", ".broken"]:
		var p := path + ext
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(p))


func _check(ok: bool, what: String) -> void:
	print(("  PASS  " if ok else "  FAIL  ") + what)
	if not ok:
		failures.append(what)
