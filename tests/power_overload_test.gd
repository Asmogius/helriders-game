extends SceneTree
## Headless test: power overload disables systems on top of the mobility
## scaling (DESIGN §4; DRAFT thresholds in vehicle.gd). Over budget the
## utilities go offline (HUD buttons disabled, a banner); at
## Vehicle.POWER_SHIELD_OFFLINE x output the shield stops recharging too;
## both come back when the draw is within budget; Overclock ignores it.
##
## Run:  godot --headless --fixed-fps 60 --path . -s res://tests/power_overload_test.gd

const Mission := preload("res://scripts/mission.gd")
const Missions := preload("res://scripts/missions.gd")
const Loadout := preload("res://scripts/loadout.gd")
const Parts := preload("res://scripts/parts.gd")
const Vehicle := preload("res://scripts/vehicle.gd")

var main: Mission
var frame := 0
var failures: Array[String] = []


func _initialize() -> void:
	var profile := root.get_node("Profile")
	profile.set("persist", false)
	profile.call("new_game")
	main = (load("res://scenes/mission.tscn") as PackedScene).instantiate() as Mission
	main.mission_override = Missions.make("clear", 1, 5)
	main.push_override = 0
	root.add_child(main)


func _banner() -> String:
	return (main.hud.get("_banner") as Label).text


func _process(_delta: float) -> bool:
	frame += 1
	var rig := main.vehicle
	match frame:
		3:
			var loadout: Dictionary = Parts.STARTER_LOADOUT.duplicate(true)
			loadout.utility = ["emergency_patch"]
			main.apply_rig(Loadout.build(loadout))
			main.zombies.clear_all()
			main.zombies.spawn_budget = 0
			rig.armor_max = 100000.0
			rig.armor = rig.armor_max
			rig.power_draw = rig.power_output   # exactly at budget (the Patch alone puts the starter 12 over)
			_check(not rig.utilities_offline() and not rig.shield_offline(), "within budget: every system online")
			rig.power_draw = rig.power_output * 1.1
		20:
			_check(rig.utilities_offline() and not rig.shield_offline(), "10% over: utilities offline, shield still on")
			_check(not rig.use_ability(0), "an offline utility can't be fired")
			_check(main.hud.is_ability_disabled(0), "its HUD button shows disabled")
			_check(_banner().contains("UTILITIES OFFLINE") and not _banner().contains("SHIELD"), "banner: " + _banner())
			_check(rig.mobility() < 1.0, "mobility still scales as before")
			rig.power_draw = rig.power_output * Vehicle.POWER_SHIELD_OFFLINE
			rig.shield = 0.0
		40:
			_check(rig.shield_offline(), "at %d%%: the shield goes offline too" % roundi(Vehicle.POWER_SHIELD_OFFLINE * 100.0))
			_check(_banner().contains("SHIELD OFFLINE"), "banner: " + _banner())
		400:   # well past the shield delay + refill
			_check(rig.shield == 0.0, "an offline shield doesn't recharge")
			rig.crew_mods.ignore_overload = true
			_check(not rig.utilities_offline(), "Overclock ignores it")
			rig.crew_mods.ignore_overload = false
			rig.power_draw = rig.power_output
		420:
			_check(not rig.utilities_offline() and not main.hud.is_ability_disabled(0), "back within budget: utilities online")
			_check(_banner().contains("SYSTEMS ONLINE"), "banner: " + _banner())
			_check(rig.use_ability(0), "and they fire again")
		700:
			_check(rig.shield > 0.0, "the shield recharges again")
			_finish()
	return false


func _check(ok: bool, what: String) -> void:
	print(("  PASS  " if ok else "  FAIL  ") + what)
	if not ok:
		failures.append(what)


func _finish() -> void:
	main.queue_free()
	if failures.is_empty():
		print("POWER OVERLOAD TEST PASSED")
		quit(0)
	else:
		print("POWER OVERLOAD TEST FAILED: %s" % ", ".join(failures))
		quit(1)
