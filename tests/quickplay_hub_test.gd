extends SceneTree
## Headless test for the title screen and the Quickplay hub (QP4): boot lands on
## the title; QUICKPLAY opens the hub; SANDBOX / ENDLESS stub notes; BACK and the
## phone's back button return to the title; CAMPAIGN still reaches the garage;
## a job quit mid-fight skips the title into the garage; nothing touches saves.
##
## Run:  godot --headless --fixed-fps 60 --path . -s res://tests/quickplay_hub_test.gd

const ProfileScript := preload("res://scripts/profile.gd")
const Missions := preload("res://scripts/missions.gd")

var profile: ProfileScript
var frame := 0
var step := 0
var failures: Array[String] = []
var scrap0 := 0
var day0 := 0


func _initialize() -> void:
	profile = root.get_node("Profile")
	profile.persist = false
	profile.new_game()
	scrap0 = profile.scrap
	day0 = profile.day
	var main := str(ProjectSettings.get_setting("application/run/main_scene"))
	_check(main == "res://scenes/title.tscn", "boot scene is the title (got %s)" % main)
	change_scene_to_file(main)


func _scene() -> Node:
	return current_scene


func _process(_delta: float) -> bool:
	frame += 1
	if frame % 10 != 0:
		return false
	var s := _scene()
	match step:
		0:
			_check(s != null and s.name == "Title", "title shows at boot")
			_check(s.campaign_button.text == "CAMPAIGN" and s.quickplay_button.text == "QUICKPLAY", "title has CAMPAIGN and QUICKPLAY")
			_check(s.campaign_button.get_theme_color("font_color") == preload("res://scripts/ui_theme.gd").PANEL_DEEP, "CAMPAIGN is a primary (gold) button")
			s.quickplay_button.pressed.emit()
		1:
			_check(s != null and s.name == "QuickplayHub", "QUICKPLAY opens the hub")
			_check(s.sandbox_button.text == "SANDBOX" and s.endless_button.text == "ENDLESS" and s.back_button.text == "BACK", "hub has SANDBOX / ENDLESS / BACK")
			s.sandbox_button.pressed.emit()
			_check(_scene() == s and s.note.text.contains("SANDBOX"), "SANDBOX stub stays on the hub with a note")
			s.endless_button.pressed.emit()
			_check(s.note.text.contains("ENDLESS"), "ENDLESS stub stays on the hub with a note")
			s.back_button.pressed.emit()
		2:
			_check(s != null and s.name == "Title", "BACK returns to the title")
			s.quickplay_button.pressed.emit()
		3:
			s.propagate_notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
		4:
			_check(s != null and s.name == "Title", "the phone's back button returns to the title")
			s.campaign_button.pressed.emit()
		5:
			_check(s != null and s.name == "Garage", "CAMPAIGN still reaches the garage")
			_check(profile.scrap == scrap0 and profile.day == day0, "the hub never changes campaign scrap or day")
			# Mid-job quit: the title steps aside and the garage resumes the job.
			profile.active_mission = Missions.make("clear", 1, 7)
			profile.run_active = true
			change_scene_to_file("res://scenes/title.tscn")
		6:
			_check(s == null or s.name != "Title" or not s.is_inside_tree(), "a pending job skips the title")
			_check(s != null and s.name in ["Garage", "Mission"], "the title hands a pending job to the garage, which resumes it (got %s)" % (s.name if s else "null"))
			profile.run_active = false
			profile.active_mission = {}
		7:
			for f in failures:
				print("FAIL: ", f)
			print("QUICKPLAY HUB TEST PASSED" if failures.is_empty() else "QUICKPLAY HUB TEST FAILED")
			quit(0 if failures.is_empty() else 1)
			return true
	step += 1
	return false


func _check(ok: bool, what: String) -> void:
	if not ok:
		failures.append(what)
