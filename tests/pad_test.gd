extends SceneTree
## Headless test for controller support (pad.gd): a pad press switches to
## controller mode and puts focus on a button; the D-pad moves it, Cross
## presses it (opens a part sheet), Circle closes the sheet, R1 / L1 switch
## stations, Options opens MENU with focus kept inside it and Circle backs out.
## In a fight the sticks drive and aim, R2 fires, Square uses a utility, R1
## toggles LOCK, L1 opens the crew wheel (point and Cross picks), Options
## pauses and resumes. A screen touch switches back to touch mode.
##
## Run:  godot --headless --fixed-fps 60 --path . -s res://tests/pad_test.gd

const Garage := preload("res://scripts/garage.gd")
const Mission := preload("res://scripts/mission.gd")
const Missions := preload("res://scripts/missions.gd")
const Crew := preload("res://scripts/crew.gd")
const Parts := preload("res://scripts/parts.gd")
const ProfileScript := preload("res://scripts/profile.gd")

var profile: ProfileScript
var pad: Node
var garage: Garage
var main: Mission
var frame := 0
var failures: Array[String] = []
var mark := {}


func _initialize() -> void:
	profile = root.get_node("Profile")
	profile.persist = false
	profile.new_game()
	pad = root.get_node("Pad")
	garage = (load("res://scenes/garage.tscn") as PackedScene).instantiate() as Garage
	root.add_child(garage)


func _button(b: int) -> void:
	var e := InputEventJoypadButton.new()
	e.button_index = b as JoyButton
	e.pressed = true
	Input.parse_input_event(e)
	var up := InputEventJoypadButton.new()
	up.button_index = b as JoyButton
	up.pressed = false
	Input.parse_input_event(up)
	Input.flush_buffered_events()


func _trigger(axis: JoyAxis, value: float) -> void:
	var e := InputEventJoypadMotion.new()
	e.axis = axis
	e.axis_value = value
	Input.parse_input_event(e)
	Input.flush_buffered_events()


func _action(name: String) -> void:
	for down: bool in [true, false]:
		var e := InputEventAction.new()
		e.action = name
		e.pressed = down
		Input.parse_input_event(e)
	Input.flush_buffered_events()


func _focus() -> Control:
	return root.gui_get_focus_owner()


func _process(_delta: float) -> bool:
	frame += 1
	match frame:
		3:
			_check(not bool(pad.get("active")) and _focus() == null, "touch mode to start: no focus")
			_button(JOY_BUTTON_DPAD_DOWN)
			_check(bool(pad.get("active")), "a pad press switches to controller mode")
		6:
			var f := _focus()
			_check(f is BaseButton and f.is_visible_in_tree(), "a visible button takes focus")
			_check(garage._hint.text.contains("Cross") and str(garage._tags[9].detail).contains("Cross"), "hints name the pad buttons in controller mode")
			mark.first = f
			_action("ui_down")
		8:
			_check(_focus() != null and _focus() != mark.first, "the D-pad moves the focus")
			# Cross on a slot tag opens its part sheet.
			var tag: Control = garage._tags[0]
			tag.grab_focus()
			_action("ui_accept")
		10:
			_check(garage.selected == 0, "Cross presses the focused button (opens the part sheet)")
			_button(JOY_BUTTON_B)
			_check(garage.selected == -1, "Circle closes the sheet")
			_button(JOY_BUTTON_RIGHT_SHOULDER)
			_check(garage.tab == "RESEARCH", "R1 goes to the next station")
			_button(JOY_BUTTON_LEFT_SHOULDER)
			_button(JOY_BUTTON_LEFT_SHOULDER)
			_check(garage.tab == "COMMS", "L1 goes back (and wraps)")
			_button(JOY_BUTTON_B)
			_check(garage.tab == "GARAGE", "Circle returns to the garage from a station")
			_button(JOY_BUTTON_START)
			_check(garage.menu != null, "Options opens MENU")
		14:
			var f := _focus()
			_check(f != null and garage.menu.is_ancestor_of(f), "focus stays inside the open menu")
			var outside := 0
			for b: Node in garage.find_children("*", "BaseButton", true, false):
				if not garage.menu.is_ancestor_of(b) and (b as Control).focus_mode != Control.FOCUS_NONE:
					outside += 1
			_check(outside == 0, "buttons behind the menu can't take focus")
			garage.menu.show_page("settings")
			_button(JOY_BUTTON_B)
			_check(garage.menu != null and garage.menu.page == "main", "Circle steps up a menu page")
			_button(JOY_BUTTON_B)
		16:
			_check(garage.menu == null, "and then closes the menu")
			# A screen touch hands back to touch mode.
			var t := InputEventScreenTouch.new()
			t.pressed = true
			t.position = Vector2(5, 5)
			Input.parse_input_event(t)
			Input.flush_buffered_events()
			_check(not bool(pad.get("active")) and _focus() == null, "a screen touch switches back to touch mode")
			var focusable := 0
			for b: Node in root.find_children("*", "BaseButton", true, false):
				if (b as Control).focus_mode != Control.FOCUS_NONE:
					focusable += 1
			_check(focusable == 0, "touch mode: no button keeps focus")
			_check(garage._hint.text.begins_with("Tap"), "and the hints go back to touch wording")
			# The fight.
			garage.queue_free()
			main = (load("res://scenes/mission.tscn") as PackedScene).instantiate() as Mission
			main.mission_override = Missions.make("clear", 1, 7)
			main.auto_spawn_specials = false
			var rng := RandomNumberGenerator.new()
			rng.seed = 5
			main.crew_override = [Crew.make("driver", "Common", rng)]
			root.add_child(main)
		20:
			main.zombies.spawn_budget = 0
			main.zombies.clear_all()
			main.vehicle.armor_max = 100000.0
			main.vehicle.armor = main.vehicle.armor_max
			var l: Dictionary = Parts.STARTER_LOADOUT.duplicate(true)
			l.utility = ["nitro_bottle"]
			main.apply_rig(profile.build_stats(l))
			_button(JOY_BUTTON_DPAD_UP)
			pad.set("override", {"left": Vector2(0, -1), "right": Vector2(1, 0), "r2": false})
		22:
			var v := main.vehicle
			_check(v.drive_input.distance_to(Vector2(0, -1)) < 0.01, "the left stick drives")
			var hud: Variant = _hud()
			_check(hud._ability_buttons.size() >= 1 and hud._ability_buttons[0].pad_badge == "square" and hud._lock_button.pad_badge == "R1" and hud._crew_button.pad_badge == "L1", "HUD buttons show their pad buttons (Square, R1, L1)")
			_check(str(hud._hint.text).contains("R2"), "the control line names the sticks and R2")
			_check(absf(v.aim_input.length() - 0.45) < 0.01 and v.aim_input.x > 0.0 and not v.fire_trigger, "the right stick turns the turret without firing")
			pad.set("override", {"right": Vector2(1, 0), "r2": true})
		24:
			var v := main.vehicle
			_check(v.fire_trigger and v.aim_input.length() > 0.99, "R2 fires")
			pad.set("override", {"r2": true})
		26:
			_check(main.vehicle.fire_trigger and main.vehicle.aim_input.x > 0.99, "R2 with the stick centred fires the last way you aimed")
			pad.set("override", {})
		28:
			_check(not main.vehicle.fire_trigger, "let go of R2: stop firing")
			var ab: Array = main.vehicle.abilities
			_check(ab.size() >= 1, "the rig has a utility to fire")
			if ab.size() >= 1:
				_button(JOY_BUTTON_X)
				_check(float(ab[0].ready_in) > 0.0, "Square uses the first utility")
			var lock: bool = _hud()._lock_button.on
			_hud().set_lock_available(true)   # starter apply_rig has no targeting; force LOCK for the pad check
			_button(JOY_BUTTON_RIGHT_SHOULDER)
			_check(_hud()._lock_button.on != lock, "R1 toggles LOCK")
		30:
			if _hud().has_crew_button():
				_button(JOY_BUTTON_LEFT_SHOULDER)
				_check(_hud().is_crew_wheel_open(), "L1 opens the crew wheel")
				pad.set("override", {"right": Vector2(0, -1)})
			else:
				_check(false, "the crew button shows with a driver seated")
		32:
			_check(_hud()._wheel.hover == 0, "the stick points at a crew slice")
			_check(main.vehicle.drive_input == Vector2.ZERO, "the rig doesn't drive while the wheel is open")
			pad.set("override", {})
			mark.picked = false
			_hud().crew_picked.connect(func(_i: int) -> void: mark.picked = true)
			_button(JOY_BUTTON_A)
			_check(bool(mark.picked) and not _hud().is_crew_wheel_open(), "Cross picks the highlighted crew member")
			_button(JOY_BUTTON_START)
			_check(paused and main.menu != null, "Options pauses the fight")
		36:
			var f := _focus()
			_check(f != null and main.menu.is_ancestor_of(f), "the pause menu takes focus")
			_button(JOY_BUTTON_START)
			_check(not paused and main.menu == null, "Options again resumes")
		40:
			_check(_focus() == null, "no menu focus while you drive")
			# Button mapping: Settings > CONTROLLER BUTTONS.
			_button(JOY_BUTTON_START)
			main.menu.show_page("settings")
			main.menu.show_page("controller")
			main.menu.rebind("ability_1")
			_check(str(pad.get("capturing")) == "ability_1", "picking an action waits for a button")
			_button(JOY_BUTTON_RIGHT_SHOULDER)
			_check(int(pad.call("binding", "ability_1")) == JOY_BUTTON_RIGHT_SHOULDER and int(pad.call("binding", "lock")) == JOY_BUTTON_X, "the next press binds it; LOCK swaps over to Square")
			_check(main.menu != null and main.menu.page == "controller", "binding a button keeps you on the page")
			main.menu.rebind("crew")
			_trigger(JOY_AXIS_TRIGGER_LEFT, 1.0)
			_trigger(JOY_AXIS_TRIGGER_LEFT, 0.0)
			_check(int(pad.call("binding", "crew")) == 100 + JOY_AXIS_TRIGGER_LEFT and str(pad.call("button_name", "crew")) == "L2", "L2 can be bound (CREW WHEEL on L2)")
			main.menu.rebind("pause")
			_button(JOY_BUTTON_B)
			_check(int(pad.call("binding", "pause")) == JOY_BUTTON_B and main.menu != null, "Circle can be bound too, and binding it doesn't close the menu")
			main.menu.rebind("pause")
			_button(JOY_BUTTON_START)
			main.menu.resume()
		42:
			var hud: Variant = _hud()
			_check(hud._ability_buttons[0].pad_badge == "R1" and hud._lock_button.pad_badge == "square" and hud._crew_button.pad_badge == "L2", "HUD badges follow the new buttons")
			hud.set_lock_available(true)
			var lock: bool = hud._lock_button.on
			_button(JOY_BUTTON_X)
			_check(hud._lock_button.on != lock, "Square now toggles LOCK")
			_button(JOY_BUTTON_LEFT_SHOULDER)
			_check(not hud.is_crew_wheel_open(), "L1 no longer opens the wheel")
			hud.crew_wheel_cooldown = 0.0
			_trigger(JOY_AXIS_TRIGGER_LEFT, 1.0)
			_trigger(JOY_AXIS_TRIGGER_LEFT, 0.0)
			_check(hud.is_crew_wheel_open(), "a pull on L2 opens it")
			hud.close_crew_wheel(false)
			pad.call("set_sticks_swapped", true)
			pad.set("override", {"right": Vector2(0, -1), "left": Vector2(1, 0)})
		44:
			_check(main.vehicle.drive_input.distance_to(Vector2(0, -1)) < 0.01, "swapped sticks: the right stick drives")
			_check(str(_hud()._hint.text).begins_with("RIGHT STICK  DRIVE"), "and the control line says so")
			pad.set("override", {})
			# The mapping is saved with the settings.
			profile.persist = true
			var old_path: String = profile.settings_path
			profile.settings_path = "user://helriders_pad_test.cfg"
			profile.save_settings()
			profile.settings.erase("pad_map")
			profile.settings.pad_swap = false
			profile.load_settings()
			_check(int(pad.call("binding", "lock")) == JOY_BUTTON_X and bool(pad.call("sticks_swapped")), "the mapping survives a relaunch")
			DirAccess.remove_absolute(ProjectSettings.globalize_path(profile.settings_path))
			profile.settings_path = old_path
			profile.persist = false
			pad.call("reset_map")
			# The Database (text only) scrolls with the right stick; sliders take focus.
			_button(JOY_BUTTON_START)
			main.menu.show_page("database")
			pad.set("override", {"right": Vector2(0, 1)})
			mark.scroll = main.menu.find_children("*", "ScrollContainer", true, false)[0]
		46:
			pass
		54:
			var box: ScrollContainer = mark.scroll
			_check(box.scroll_vertical > 0, "the right stick scrolls the Database (%d px)" % box.scroll_vertical)
			pad.set("override", {})
			main.menu.show_page("settings")
		60:
			var sliders := main.menu.find_children("*", "HSlider", true, false)
			_check(not sliders.is_empty() and (sliders[0] as Control).focus_mode == Control.FOCUS_ALL, "the volume sliders can take the pad's focus")
			var slider := sliders[0] as HSlider
			slider.grab_focus()
			var before := slider.value
			_action("ui_left")
			_check(slider.value < before, "and the D-pad moves them")
			main.menu.resume()
			_check(int(pad.call("binding", "lock")) == JOY_BUTTON_RIGHT_SHOULDER and int(pad.call("binding", "fire")) == 100 + JOY_AXIS_TRIGGER_RIGHT and not bool(pad.call("sticks_swapped")), "RESET TO DEFAULT puts it all back")
			_finish()
	return false


func _check(ok: bool, what: String) -> void:
	print(("  PASS  " if ok else "  FAIL  ") + what)
	if not ok:
		failures.append(what)


func _finish() -> void:
	if failures.is_empty():
		print("PAD TEST PASSED")
		quit(0)
	else:
		print("PAD TEST FAILED: %s" % ", ".join(failures))
		quit(1)


func _hud() -> Variant:
	return main.get("hud")
