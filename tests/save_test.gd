extends SceneTree
## Headless test for save safety: saves go through a temp file and keep the
## last good save as .bak; an unreadable save loads the backup (or starts
## fresh) and is kept aside as .broken, never overwritten; fields of the wrong
## type load as a new game's instead of breaking the load; a save left as
## .tmp by a crash between write and swap is recovered.
##
## Run:  godot --headless --fixed-fps 60 --path . -s res://tests/save_test.gd

const ProfileScript := preload("res://scripts/profile.gd")

const PATH := "user://helriders_save_test.json"

var profile: ProfileScript
var failures: Array[String] = []


func _initialize() -> void:
	profile = root.get_node("Profile")
	profile.persist = false
	profile.new_game()
	_clean()
	profile.save_path = PATH
	profile.persist = true

	profile.scrap = 123
	profile.save_game()
	_check(FileAccess.file_exists(PATH) and not FileAccess.file_exists(PATH + ".tmp"), "a save lands in place, no temp file left")
	profile.scrap = 456
	profile.save_game()
	_check(int(ProfileScript.read_save(PATH + ".bak").get("scrap", 0)) == 123, "the previous save is kept as .bak")
	_check(profile.load_game() and profile.scrap == 456, "a good save loads")

	_write(PATH, "{\"scrap\": 9, oops")
	profile.notice = ""
	_check(profile.load_game() and profile.scrap == 123, "an unreadable save loads the backup")
	_check(profile.notice != "" and FileAccess.file_exists(PATH + ".broken"), "the player is told, and the broken file is kept aside")

	_write(PATH, "not json")
	_write(PATH + ".bak", "")
	profile.notice = ""
	profile.scrap = 5
	_check(not profile.load_game() and profile.notice.contains("fresh start"), "no readable save at all: a fresh start, with a notice")

	_write(PATH, JSON.stringify({"scrap": 77, "day": 3, "crew": 5, "storage": "x", "levels": [1, 2], "rehire_taken": "yes"}))
	var ok77 := profile.load_game()
	_check(ok77 and profile.scrap == 77 and profile.day == 3 and profile.storage.is_empty(), "fields of the wrong type load as a new game's")

	_clean()
	profile.scrap = 31
	var data := JSON.stringify(profile.save_data())
	_write(PATH + ".tmp", data)
	profile.scrap = 0
	_check(profile.load_game() and profile.scrap == 31 and FileAccess.file_exists(PATH), "a save stranded as .tmp by a crash is recovered")

	_clean()
	profile.persist = false
	profile.save_path = "user://helriders_save.json"
	if failures.is_empty():
		print("SAVE TEST PASSED")
		quit(0)
	else:
		print("SAVE TEST FAILED: %s" % ", ".join(failures))
		quit(1)


func _write(path: String, text: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(text)
	f.close()


func _clean() -> void:
	for ext: String in ["", ".bak", ".tmp", ".broken"]:
		if FileAccess.file_exists(PATH + ext):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(PATH + ext))


func _check(ok: bool, what: String) -> void:
	print(("  PASS  " if ok else "  FAIL  ") + what)
	if not ok:
		failures.append(what)
