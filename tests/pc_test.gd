extends SceneTree
## Headless test for playing on a PC: Esc is the back button (garage: one
## level at a time; fight: pause, and Esc again resumes), the Settings page
## has a DISPLAY (windowed / fullscreen) toggle that is saved, and F11 or
## Alt+Enter flips it. Mouse and keyboard: WASD drive, the mouse aims, left
## click fires, right click LOCK, Q/E/F utilities, Tab and 1-4 the crew wheel.
## Fire / lock / pause are rebindable; Esc always pauses as a fallback.
##
## Run:  godot --headless --fixed-fps 60 --path . -s res://tests/pc_test.gd

const Garage := preload("res://scripts/garage.gd")
const Mission := preload("res://scripts/mission.gd")
const Missions := preload("res://scripts/missions.gd")
const ProfileScript := preload("res://scripts/profile.gd")
const Parts := preload("res://scripts/parts.gd")
const Crew := preload("res://scripts/crew.gd")

var profile: ProfileScript
var garage: Garage
var main: Mission
var frame := 0
var failures: Array[String] = []
var mark_picked := false


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


func _hold(code: Key, down: bool) -> void:
	var e := InputEventKey.new()
	e.keycode = code
	e.physical_keycode = code
	e.pressed = down
	Input.parse_input_event(e)
	Input.flush_buffered_events()


func _click(button: MouseButton) -> void:
	for down: bool in [true, false]:
		var e := InputEventMouseButton.new()
		e.button_index = button
		e.pressed = down
		e.position = Vector2(640, 360)
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
			var kbm_btn := false
			for b: Node in garage.menu.find_children("*", "Button", true, false):
				if (b as Button).text == "KEYBOARD & MOUSE":
					kbm_btn = true
					(b as Button).pressed.emit()
			_check(kbm_btn and garage.menu.page == "kbm", "Settings has KEYBOARD & MOUSE")
			var pad: Node = root.get_node("Pad")
			pad.call("start_kbm_capture", "ability_1")
			garage.menu.show_page("kbm")
			_check(str(pad.get("capturing_kbm")) == "ability_1", "KBM rebind is waiting for a key")
			_key(KEY_ESCAPE)
			_check(str(pad.get("capturing_kbm")) == "" and garage.menu.page == "kbm", "Esc cancels KBM rebind without leaving the page")
			# Fire / lock / pause are rebindable (mouse + keys). Esc on PAUSE assigns Esc.
			_check(pad.call("bind_kbm", "fire", KEY_R) and str(pad.call("kbm_button_name", "fire")) == "R", "FIRE rebinds to a key")
			pad.call("start_kbm_capture", "lock")
			garage.menu.show_page("kbm")
			_click(MOUSE_BUTTON_MIDDLE)
			_check(str(pad.get("capturing_kbm")) == "" and str(pad.call("kbm_button_name", "lock")) == "MIDDLE CLICK", "LOCK rebinds to a mouse button without leaving capture stuck")
			_check(garage.menu.page == "kbm", "mouse rebind did not press a Settings button underneath")
			pad.call("start_kbm_capture", "pause")
			garage.menu.show_page("kbm")
			_key(KEY_ESCAPE)
			_check(str(pad.get("capturing_kbm")) == "" and int(pad.call("kbm_binding", "pause")) == KEY_ESCAPE, "Esc while rebinding PAUSE assigns Esc-pause")
			_check(pad.call("bind_kbm", "pause", KEY_P) and int(pad.call("kbm_binding", "pause")) == KEY_P, "PAUSE rebinds to P")
			_check(int(pad.call("kbm_binding", "fire")) >= 0, "swap left FIRE bound after pause move")
			pad.call("reset_kbm_map")
			_check(str(pad.call("kbm_button_name", "fire")) == "LEFT CLICK" and str(pad.call("kbm_button_name", "pause")) == "ESC", "RESET restores fire/lock/pause defaults")
			# Defaults cover every fight action; map persists with settings.
			var defaults: Dictionary = pad.get("KBM_DEFAULT")
			for a: String in ["fire", "lock", "pause", "ability_1", "ability_2", "ability_3", "crew"]:
				_check(defaults.has(a) and int(pad.call("kbm_binding", a)) == int(defaults[a]), "KBM default binds %s" % a)
			pad.call("bind_kbm", "ability_2", KEY_G)
			profile.persist = true
			var ppath: String = profile.settings_path
			profile.settings_path = "user://helriders_kbm_map_test.cfg"
			profile.save_settings()
			profile.settings.erase("kbm_map")
			profile.load_settings()
			_check(int(pad.call("kbm_binding", "ability_2")) == KEY_G, "kbm_map survives save/load")
			DirAccess.remove_absolute(ProjectSettings.globalize_path(profile.settings_path))
			profile.settings_path = ppath
			profile.persist = false
			pad.call("reset_kbm_map")
			# Device detection / touch chrome hide (simulated joy + scheme).
			pad.set("joy_connected", true)
			pad.call("set_scheme", "pad")
			_check(bool(pad.call("touch_chrome_hidden")), "joy_connected hides touch chrome")
			pad.set("joy_connected", false)
			pad.call("set_scheme", "kbm")
			pad.set("kbm", true)
			_check(bool(pad.call("touch_chrome_hidden")), "kbm hides touch chrome")
			garage.menu.show_page("settings")
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
			_check(bool(root.get_node("Pad").get("kbm")), "keys on a PC switch to mouse-and-keyboard mode")
			_check(garage._hint.text.begins_with("Click a slot"), "garage hints say click, not tap")
			garage.queue_free()
			main = (load("res://scenes/mission.tscn") as PackedScene).instantiate() as Mission
			main.mission_override = Missions.make("clear", 1, 7)
			main.auto_spawn_specials = false
			var rng := RandomNumberGenerator.new()
			rng.seed = 3
			main.crew_override = [Crew.make("driver", "Common", rng)]
			root.add_child(main)
		11:
			main.zombies.spawn_budget = 0
			main.zombies.clear_all()
			var l: Dictionary = Parts.STARTER_LOADOUT.duplicate(true)
			l.utility = ["nitro_bottle"]
			l.engine = "patched_v8"   # power headroom: an overloaded rig's utilities go offline
			main.apply_rig(profile.build_stats(l))
			main.vehicle.armor_max = 100000.0
			main.vehicle.armor = main.vehicle.armor_max
			_hold(KEY_W, true)
			main.kbm_mouse_override = main.vehicle.global_position + Vector2(300, 0)
			main.kbm_fire_override = 0
		13:
			var v := main.vehicle
			_check(v.drive_input.distance_to(Vector2(0, -1)) < 0.01, "W drives up the screen")
			_check(v.aim_input.distance_to(Vector2(0.45, 0)) < 0.01 and not v.fire_trigger, "the turret follows the mouse without firing")
			_hold(KEY_W, false)
			main.kbm_fire_override = 1
		15:
			var v := main.vehicle
			_check(v.fire_trigger and v.aim_input.length() > 0.99, "holding the left button fires")
			main.kbm_fire_override = 0
			var hud: Variant = main.get("hud")
			_check(hud._ability_buttons[0].pad_badge == "Q" and hud._crew_button.pad_badge == "TAB" and str(hud._hint.text).begins_with("WASD"), "HUD shows key badges and the WASD control line")
			# Playtest #4: PWR label under the bar (not over HP); banner below status.
			var hp_r: Rect2 = hud._hp_value.get_rect()
			hp_r.position = hud._hp_value.global_position
			var pwr_r := Rect2(hud._power_bar.global_position, hud._power_bar.size)
			var status_r := Rect2(hud._status.global_position, Vector2(800, 28))
			var banner_r := Rect2(Vector2(hud._banner_bg.offset_left + 640, hud._banner_bg.offset_top), Vector2(840, 48))
			_check(pwr_r.end.y <= status_r.position.y + 1.0, "PWR block sits above the status line")
			_check(not pwr_r.intersects(hp_r), "PWR block does not cover the HP number")
			_check(status_r.end.y <= hud._banner_bg.offset_top + 1.0, "status line sits above the mission title band")
			# Playtest #10: touch stick chrome hidden on KBM (keys still work).
			hud.set_lock_available(true)
			_check(not hud._lock_button.visible and not hud._crew_button.visible, "LOCK and CREW buttons hide on KBM")
			_check(not hud.left_stick.visible and not hud.right_stick.visible and not hud.pause_button.visible, "sticks and pause hide on KBM/PC")
			_check(hud._ability_buttons.is_empty() or not hud._ability_buttons[0].visible, "ability buttons hide on KBM/PC")
			_check(hud.rig_health_slot != null and hud.rig_health_slot.name == "RigHealthSlot", "HUD leaves a RigHealthSlot anchor for ui-rig-health-hud")
			_check(str(hud._hint.text).contains("PAUSE"), "KBM control line shows the pause glyph")
			_check(bool(root.get_node("Pad").get("kbm")), "still in KBM mode")
			_key(KEY_Q)
			_check(float(main.vehicle.abilities[0].ready_in) > 0.0, "Q fires the first utility")
			var lock: bool = hud._lock_button.on
			_click(MOUSE_BUTTON_RIGHT)
			_check(hud._lock_button.on != lock, "right click toggles LOCK")
			_key(KEY_TAB)
			_check(hud.is_crew_wheel_open(), "Tab opens the crew wheel")
			mark_picked = false
			hud.crew_picked.connect(func(_i: int) -> void: mark_picked = true)
			_key(KEY_1)
			_check(mark_picked and not hud.is_crew_wheel_open(), "1 picks the first crew member")
		18:
			# Pause rebound away from Esc: Esc still pauses (hard fallback).
			root.get_node("Pad").call("bind_kbm", "pause", KEY_P)
			_key(KEY_ESCAPE)
			_check(paused and main.menu != null, "Esc pauses the fight even when PAUSE is rebound to P")
		20:
			_key(KEY_ESCAPE)
			_check(not paused and main.menu == null, "Esc again resumes")
			# Bound pause key also pauses.
			_key(KEY_P)
			_check(paused and main.menu != null, "rebound PAUSE key pauses the fight")
			_key(KEY_ESCAPE)
			_check(not paused and main.menu == null, "Esc resumes after rebound pause")
			root.get_node("Pad").call("reset_kbm_map")
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
