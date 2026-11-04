extends SceneTree
## Headless test for playing on a PC: Esc is the back button (garage: one
## level at a time; fight: pause, and Esc again resumes), the Settings page
## has a DISPLAY (windowed / fullscreen) toggle that is saved, and F11 or
## Alt+Enter flips it.
##
## Run:  godot --headless --fixed-fps 60 --path . -s res://tests/pc_test.gd

const Garage := preload("res://scripts/garage.gd")
const Mission := preload("res://scripts/mission.gd")
const Missions := preload("res://scripts/missions.gd")
const ProfileScript := preload("res://scripts/profile.gd")

var profile: ProfileScript
var garage: Garage
var main: Mission
var frame := 0
var failures: Array[String] = []


func _initialize() -> void:
	profile = root.get_node("Profile")
	profile.persist = false
	profile.new_game()
	profile.load_settings()
	garage = (load("res://scenes/garage.tscn") as PackedScene).instantiate() as Garage
	root.add_child(garage)


func _key(code: Key, alt := false) -> void:
	for down: bool in [true, false]:
		var e := InputEventKey.new()
		e.keycode = code
		e.physical_keycode = code
		e.pressed = down
		e.alt_pressed = alt
		Input.parse_input_event(e)
	Input.flush_buffered_events()


func _process(_delta: float) -> bool:
	frame += 1
	match frame:
		3:
			_check(ProfileScript.is_desktop(), "this run counts as a PC")
			garage.open_slot(2)
			_key(KEY_ESCAPE)
			_check(garage.selected == -1 and garage.menu == null, "Esc closes the part sheet")
			garage.show_tab("COMMS")
			_key(KEY_ESCAPE)
			_check(garage.tab == "GARAGE" and garage.menu == null, "Esc leaves a station")
			_key(KEY_ESCAPE)
			_check(garage.menu != null, "Esc on the garage opens MENU")
			garage.menu.show_page("settings")
			var found := false
			for b: Node in garage.menu.find_children("*", "Button", true, false):
				if (b as Button).text.begins_with("DISPLAY: WINDOWED"):
					found = true
					(b as Button).pressed.emit()
			_check(found, "Settings shows DISPLAY: WINDOWED on a PC")
			_check(bool(profile.settings.get("fullscreen", false)), "the DISPLAY toggle turns fullscreen on")
		5:
			_key(KEY_F11)
			_check(not bool(profile.settings.get("fullscreen", true)), "F11 flips it back to windowed")
			_key(KEY_ENTER, true)
			_check(bool(profile.settings.get("fullscreen", false)), "Alt+Enter flips it too")
			_key(KEY_ENTER)
			_check(bool(profile.settings.get("fullscreen", false)), "plain Enter doesn't")
			# Saved with the settings.
			profile.persist = true
			var old_path: String = profile.settings_path
			profile.settings_path = "user://helriders_pc_test.cfg"
			profile.save_settings()
			profile.settings.fullscreen = false
			profile.load_settings()
			_check(bool(profile.settings.get("fullscreen", false)), "fullscreen survives a relaunch")
			DirAccess.remove_absolute(ProjectSettings.globalize_path(profile.settings_path))
			profile.settings_path = old_path
			profile.persist = false
			profile.set_setting("fullscreen", false)
			_key(KEY_ESCAPE)
			_key(KEY_ESCAPE)
		8:
			_check(garage.menu == null, "Esc backs out of the menu (settings, then closed)")
			garage.queue_free()
			main = (load("res://scenes/mission.tscn") as PackedScene).instantiate() as Mission
			main.mission_override = Missions.make("clear", 1, 7)
			main.auto_spawn_specials = false
			root.add_child(main)
		12:
			_key(KEY_ESCAPE)
			_check(paused and main.menu != null, "Esc pauses the fight")
		14:
			_key(KEY_ESCAPE)
			_check(not paused and main.menu == null, "Esc again resumes")
			_finish()
	return false


func _check(ok: bool, what: String) -> void:
	print(("  PASS  " if ok else "  FAIL  ") + what)
	if not ok:
		failures.append(what)


func _finish() -> void:
	if failures.is_empty():
		print("PC TEST PASSED")
		quit(0)
	else:
		print("PC TEST FAILED: %s" % ", ".join(failures))
		quit(1)
