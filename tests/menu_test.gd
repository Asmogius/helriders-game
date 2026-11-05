extends SceneTree
## Headless test for the pause menu, settings and the Database: the II button
## pauses the job, RESUME carries on, the back button opens and closes it,
## RESTART JOB (two taps) starts the fight over without costing the day, a
## quit mid-job resumes the job at the next launch, the quality presets and
## shake setting reach the mission, settings round-trip through their file,
## the garage MENU button, and the Database censoring what you haven't met.
##
## Run:  godot --headless --fixed-fps 60 --path . -s res://tests/menu_test.gd

const Mission := preload("res://scripts/mission.gd")
const Missions := preload("res://scripts/missions.gd")
const Garage := preload("res://scripts/garage.gd")
const GameMenu := preload("res://scripts/game_menu.gd")
const Codex := preload("res://scripts/codex.gd")
const ProfileScript := preload("res://scripts/profile.gd")
const T := preload("res://scripts/tuning.gd")
const UI := preload("res://scripts/ui_theme.gd")

var profile: ProfileScript
var main: Mission
var frame := 0
var step := 0
var failures: Array[String] = []
var mark := {}


func _initialize() -> void:
	profile = root.get_node("Profile")
	profile.persist = false
	profile.new_game()
	profile.load_settings()
	_check_settings()
	profile.active_mission = Missions.make("clear", 1, 7)
	main = (load("res://scenes/mission.tscn") as PackedScene).instantiate() as Mission
	main.mission_override = profile.active_mission
	main.auto_spawn_specials = false
	root.add_child(main)


func _process(_delta: float) -> bool:
	frame += 1
	match step:
		0:
			if frame == 5:
				_check_database()
			if frame == 30:
				mark.elapsed = main.elapsed
				main.hud.pause_pressed.emit()
				_check(paused and main.menu != null, "the II button pauses the job and opens the menu")
			if frame == 60:
				_check(is_equal_approx(main.elapsed, float(mark.elapsed)), "nothing moves while paused")
				main.menu.resume()
				_check(not paused and main.menu == null, "RESUME carries on")
				main.propagate_notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
				_check(paused and main.menu != null, "the phone's back button opens the menu")
				main.menu.show_page("settings")
				main.propagate_notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
				_check(main.menu != null and main.menu.page == "main", "back steps up a page first")
				main.propagate_notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
				_check(not paused and main.menu == null, "and then resumes")
			if frame == 70:
				mark.day = profile.day
				mark.runs = int(profile.record.runs)
				main.vehicle.take_damage(50.0)
				var m := main.open_menu()
				_check(not m.restart() and m.restart_armed, "RESTART JOB asks for a second tap")
				m.restart()
			if frame == 74:
				main = root.get_child(root.get_child_count() - 1) as Mission
				_check(main != null and main.elapsed < 0.2 and is_equal_approx(main.vehicle.armor, main.vehicle.armor_max), "the fight starts over, the rig repaired")
				_check(profile.day == int(mark.day) and int(profile.record.runs) == int(mark.runs) and profile.run_active, "a restart costs no day and isn't a new run")
				_check(not paused, "and isn't paused")
				_check(is_equal_approx(main.fx.density, float(T.QUALITY[str(profile.settings.quality)].fx)), "the quality preset reaches the effects")
				# A quit mid-job: the next launch drops you back in.
				_check(profile.resume_job(), "quit mid-job: the job is still on at the next launch")
				_next()
		1:
			if frame == 2:
				var g := (load("res://scenes/garage.tscn") as PackedScene).instantiate() as Garage
				g.auto_resume = false
				root.add_child(g)
				mark.g = g
			if frame == 4:
				var g: Garage = mark.g
				var m := g.open_menu()
				_check(m != null and not m.in_job, "the garage's MENU opens settings, the Database and quit (no restart)")
				g.propagate_notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
				_check(g.menu == null, "back closes it")
				_finish()
	return false


func _check_settings() -> void:
	_check(str(profile.settings.quality) == "Ultra", "headless runs default to Ultra")
	profile.set_setting("quality", "Low")
	_check(Engine.max_fps == 30, "Low caps the frame rate at 30")
	profile.set_setting("shake", false)
	profile.set_setting("music", 0.3)
	profile.persist = true
	profile.settings_path = "user://helriders_menu_test_settings.cfg"
	profile.save_settings()
	profile.settings = {}
	profile.load_settings()
	_check(str(profile.settings.quality) == "Low" and not bool(profile.settings.shake) and is_equal_approx(float(profile.settings.music), 0.3), "settings round-trip through their own file")
	var bus := AudioServer.get_bus_index("Music")
	_check(bus >= 0 and absf(AudioServer.get_bus_volume_db(bus) - linear_to_db(0.3)) < 0.1, "music volume reaches its bus")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(profile.settings_path))
	profile.persist = false
	profile.new_game()
	_check(str(profile.settings.quality) == "Low", "settings survive a new game")
	profile.set_setting("quality", "Medium")
	profile.set_setting("shake", true)


func _check_database() -> void:
	var menu := GameMenu.new()
	menu.setup(profile, false)
	root.add_child(menu)
	menu.show_category("enemies")
	_check(not profile.is_discovered("enemies", "brute"), "a Brute you haven't met is censored")
	profile.discover("enemies", "brute")
	_check(profile.is_discovered("enemies", "brute"), "meeting one reveals it")
	_check(profile.is_discovered("parts", "pintle_turret") and not profile.is_discovered("parts", "mortar"), "owned schematics count; others wait to be found")
	_check(profile.is_discovered("places", "outer_blocks") and not profile.is_discovered("places", "core"), "open districts count")
	_check(profile.is_discovered("crew", str(profile.crew[0].specialty)), "your crew's specialties count")
	var text := ""
	for l: Node in menu.find_children("*", "Label", true, false):
		text += (l as Label).text + "|"
	_check(text.contains("? ? ? ? ?") and text.contains("ENEMIES"), "the Database lists censored entries")
	menu.show_category("enemies")
	text = ""
	for l: Node in menu.find_children("*", "Label", true, false):
		text += (l as Label).text + "|"
	_check(text.contains("Brute"), "and shows what you've met")
	for cat: String in Codex.CATEGORIES:
		_check(not Codex.entries(cat).is_empty(), "the %s tab has entries" % cat)
	# Playtest #13: Database / menu panel fill is opaque charcoal.
	var flat: StyleBoxFlat = UI.box(UI.PANEL, UI.PANEL_EDGE, 2)
	_check(is_equal_approx(flat.bg_color.a, 1.0), "UI.box forces opaque panel fills")
	menu._panel.add_theme_stylebox_override("panel", flat)
	_check(is_equal_approx((menu._panel.get_theme_stylebox("panel") as StyleBoxFlat).bg_color.a, 1.0), "menu panel fill is opaque")
	menu.queue_free()


func _next() -> void:
	frame = 0
	step += 1


func _check(ok: bool, what: String) -> void:
	print(("  PASS  " if ok else "  FAIL  ") + what)
	if not ok:
		failures.append(what)


func _finish() -> void:
	if failures.is_empty():
		print("MENU TEST PASSED")
		quit(0)
	else:
		print("MENU TEST FAILED: %s" % ", ".join(failures))
		quit(1)
