extends SceneTree
## Headless Research test: the per-level math (main stats grow, power and
## weight don't, internals and utilities, the Legendary bonus hook), costs and
## max levels, the daily cap and both Research upgrades, district score,
## levels surviving a wreck without changing build cost or the penalty, the
## save file (and a save from before Research), the Research tab driven like a
## player, and that a mission rig rolls out with the levelled stats.
##
## Run:  godot --headless --fixed-fps 60 --path . -s res://tests/research_test.gd

const Garage := preload("res://scripts/garage.gd")
const Mission := preload("res://scripts/mission.gd")
const Missions := preload("res://scripts/missions.gd")
const ProfileScript := preload("res://scripts/profile.gd")
const Parts := preload("res://scripts/parts.gd")
const Loadout := preload("res://scripts/loadout.gd")
const T := preload("res://scripts/tuning.gd")

var profile: ProfileScript
var garage: Garage
var mission: Mission
var frame := 0
var failures: Array[String] = []


func _initialize() -> void:
	profile = root.get_node("Profile")
	profile.persist = false
	profile.new_game()


func _process(_delta: float) -> bool:
	frame += 1
	if frame == 2:
		_check_math()
		_check_profile_rules()
		_check_wreck_and_save()
		profile.new_game()
		garage = (load("res://scenes/garage.tscn") as PackedScene).instantiate() as Garage
		root.add_child(garage)
	if frame == 4:
		_check_tab()
		garage.queue_free()
		garage = null
		mission = (load("res://scenes/mission.tscn") as PackedScene).instantiate() as Mission
		mission.mission_override = Missions.make("clear", 1, 7)
		mission.auto_spawn_specials = false
		root.add_child(mission)
	if frame == 6:
		var built := profile.build_stats(profile.rig)
		var expected := float(built.armor) + float(built.shield)   # every layer, shield included
		_check(is_equal_approx(mission.vehicle.armor_max, expected) and expected > float(Loadout.build(profile.rig).armor),
			"the mission rig rolls out with levelled armor (%d)" % int(mission.vehicle.armor_max))
		_finish()
	return false


func _check_math() -> void:
	var diesel := Parts.get_part("diesel_block")
	var d3 := Parts.at_level(diesel, 3)
	_check(is_equal_approx(float(d3.power_output), 150.0 * 1.08) and is_equal_approx(float(d3.acceleration), 580.0 * 1.08),
		"Engine L3: power output and accel +8%")
	_check(float(d3.weight) == float(diesel.weight) and float(d3.power) == float(diesel.power), "power draw and weight never change")
	_check(Parts.at_level(diesel, 1) == diesel.merged({"level": 1}), "level 1 is the plain schematic")
	_check(int(Parts.at_level(diesel, 99).level) == 12, "levels clamp to the rarity's max (Rare 12)")
	var mg := Parts.at_level(Parts.get_part("heavy_mg_turret"), 12)
	_check(is_equal_approx(float(mg.bullet_damage), 11.0 * 1.44) and float(mg.fire_rate) == 9.0, "Weapon L12: damage +44%, fire rate unchanged")
	var wheels := Parts.at_level(Parts.get_part("street_wheels"), 5)
	_check(is_equal_approx(float(wheels.turn_mult), 1.16) and is_equal_approx(float(wheels.grip), 5.5 * 1.16) and float(wheels.brake) == 1500.0,
		"Drive: turn and grip grow, braking doesn't")
	var frame_part := Parts.at_level(Parts.get_part("scrap_frame"), 2)
	_check(is_equal_approx(float(frame_part.hp), 150.0 * 1.04) and is_equal_approx(float(frame_part.weight_capacity), 104.0)
		and float(frame_part.max_speed) == 560.0, "Chassis: HP and weight capacity grow")
	var coolant := Parts.at_level(Parts.get_part("coolant_loop"), 8)
	_check(is_equal_approx(float(coolant.fire_rate_mult), 1.0 + 0.15 * 1.28), "Internal: the modifier grows (Coolant +15% -> +19%)")
	var cage := Parts.at_level(Parts.get_part("roll_cage"), 8)
	_check(is_equal_approx(float(cage.injury_mult), 1.0 - 0.5 * 1.28), "Roll Cage cuts crew injury further")
	var patch := Parts.at_level(Parts.get_part("emergency_patch"), 6)
	_check(is_equal_approx(float(patch.cooldown), 25.0 / 1.2) and float(patch.heal) == 35.0, "Utility: shorter cooldown, same effect")
	_check(not Parts.can_level(Parts.get_part("targeting_computer")), "the plain Targeting Computer has nothing to level")
	_check(Parts.can_level(Parts.get_part("advanced_targeting")), "the Advanced Targeting Computer levels its lock and aim")
	# The Legendary hook: a test-only part with a bonus at level 18.
	var legend := {"name": "Test", "category": "Weapon", "rarity": "Legendary", "bullet_damage": 10.0,
		"legendary_bonus": {"at": 18, "add": {"pellets_bonus": 2.0}, "text": "test"}}
	_check(not Parts.at_level(legend, 17).has("pellets_bonus") and float(Parts.at_level(legend, 18).pellets_bonus) == 2.0,
		"a Legendary bonus switches on at its level")

	var plain := Loadout.build(Parts.STARTER_LOADOUT)
	var lv := {"scrap_frame": 5, "scrap_plating": 5, "pintle_turret": 3}
	var levelled := Loadout.build(Parts.STARTER_LOADOUT, lv)
	_check(is_equal_approx(float(levelled.hp), 150.0 * 1.16) and is_equal_approx(float(levelled.front), 80.0 * 1.16) and is_equal_approx(float(levelled.side), 80.0 * 1.16),
		"the build uses the levelled frame HP and plating on every facing")
	_check(is_equal_approx(float(levelled.bullet_damage), 9.0 * 1.08), "the build's weapon uses its level")
	_check(float(levelled.power_draw) == float(plain.power_draw) and float(levelled.weight) == float(plain.weight),
		"levels don't touch the power or weight budget")


func _check_profile_rules() -> void:
	profile.new_game()
	profile.scrap = 10000
	_check(profile.research_cost("scrap_frame") == 30, "Common L2 costs 30")
	profile.schematics.append("heavy_mg_turret")
	profile.levels["heavy_mg_turret"] = 11
	_check(profile.research_cost("heavy_mg_turret") == 720, "Rare L12 costs 720")
	profile.levels.erase("heavy_mg_turret")
	_check(profile.research_block("diesel_block") == "NOT OWNED", "you can only research schematics you own")
	_check(profile.research_block("targeting_computer") == "NOTHING TO IMPROVE", "nothing-to-improve parts can't be levelled")

	_check(profile.research_cap() == 3, "3 levels a day to start")
	var before := profile.scrap
	_check(profile.research("scrap_frame") and profile.part_level("scrap_frame") == 2 and profile.scrap == before - 30,
		"LEVEL UP takes the scrap and raises the level")
	_check(profile.research("scrap_frame") and profile.research("scrap_frame") and profile.part_level("scrap_frame") == 4, "three levels in a day")
	_check(profile.research_block("scrap_plating") == "DONE FOR TODAY" and not profile.research("scrap_plating"), "a 4th level waits for tomorrow")
	profile.finish_day()
	_check(profile.research_left() == 3, "the cap resets when the day ends")
	_check(profile.research("scrap_frame") and profile.part_level("scrap_frame") == 5, "Common tops out at 5...")
	_check(profile.research_block("scrap_frame") == "MAX LEVEL" and profile.research_cost("scrap_frame") == -1, "...and goes no higher")

	_check(profile.buy_upgrade("research_speed") and profile.research_cap() == 4, "Second Shift: 4 levels a day")
	_check(profile.buy_upgrade("research_speed") and profile.research_cap() == 5 and profile.upgrade_cost("research_speed") == -1,
		"Second Shift maxes at 5 a day")
	_check(profile.buy_upgrade("research_discount") and profile.research_cost("scrap_plating") == 27, "Bench Discount: 10% off (30 -> 27)")

	profile.new_game()
	profile.scrap = 0
	_check(profile.research_block("scrap_frame") == "NEED 30 SCRAP", "no scrap, no research")

	# District score: extracted schematics only, rarity points x level.
	profile.schematics.append("diesel_block")
	profile.schematics.append("riot_plating")
	_check(profile.district_score() == 4 + 2, "score at level 1: Rare 4 + Uncommon 2")
	profile.levels["diesel_block"] = 3
	profile.levels["scrap_frame"] = 5
	_check(profile.district_score() == 12 + 2, "a level-3 Rare counts 12; starter levels don't count")
	var every := 0
	for id: String in Parts.CATALOG:
		var p := Parts.get_part(id)
		if not Parts.STARTER_SCHEMATICS.has(id):
			every += int(T.RARITY_POINTS[str(p.rarity)]) * Parts.max_level(p)
	_check(every >= int(T.DISTRICTS[3].need), "every schematic maxed opens Core Collapse (%d)" % every)


func _check_wreck_and_save() -> void:
	profile.new_game()
	profile.scrap = 500
	profile.research("scrap_plating")
	profile.research("scrap_plating")
	var value := ProfileScript.build_value(profile.rig)
	var penalty := profile.wreck_penalty(profile.rig)
	_check(value == ProfileScript.build_value(Parts.STARTER_LOADOUT), "levels don't change a build's value")
	_check(profile.record_wreck() == penalty and profile.part_level("scrap_plating") == 3, "a wreck keeps Research levels")
	_check(profile.build_cost(Parts.STARTER_LOADOUT) == 0, "rebuilding levelled Commons is still free")

	profile.persist = true
	profile.save_path = "user://helriders_research_test_save.json"
	profile.save_game()
	profile.levels = {}
	profile.research_today = 0
	_check(profile.load_game() and profile.part_level("scrap_plating") == 3 and profile.research_today == 2,
		"levels and today's count round-trip through the save")
	# A save from before Research (no "levels" key) and one with junk levels.
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(profile.save_path))
	data.erase("levels")
	data.erase("research_today")
	var upgrades: Dictionary = data.upgrades
	upgrades.erase("research_speed")
	_write(data)
	_check(profile.load_game() and profile.levels.is_empty() and profile.research_cap() == 3, "an old save loads at level 1 with no Research upgrades")
	data["levels"] = {"scrap_plating": 99, "no_such_part": 4, "riot_plating": 0}
	_write(data)
	_check(profile.load_game() and profile.part_level("scrap_plating") == 5 and profile.levels.size() == 1, "bad levels are clamped or dropped")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(profile.save_path))
	profile.persist = false


func _write(data: Dictionary) -> void:
	var file := FileAccess.open(profile.save_path, FileAccess.WRITE)
	file.store_string(JSON.stringify(data))
	file.close()


func _check_tab() -> void:
	profile.scrap = 1000
	var armor_before := float(garage._built(profile.rig).armor)
	garage.show_tab("RESEARCH")
	var research := garage._research
	_check(research.visible and research._rows.get_child_count() == profile.schematics.size(), "the Research tab lists every schematic you own")
	research.select("scrap_plating")
	_check(research._level_up.text == "LEVEL UP  -  30 SCRAP" and not research._level_up.disabled, "the button shows the next level's cost")
	_check(research.level_selected() and research.level_selected() and profile.part_level("scrap_plating") == 3, "LEVEL UP from the tab")
	_check(research._level.text.begins_with("LEVEL 3 / 5"), "the detail panel shows the new level")
	research.select("targeting_computer")
	_check(research._level_up.disabled and research._level_up.text == "NOTHING TO IMPROVE", "nothing to improve: the button says so")
	research.open_upgrades()
	_check(research._upgrades != null, "Research upgrades open")
	research.close_upgrades()
	_check_rig_upgrades(research)
	garage.show_tab("GARAGE")
	_check(not research.visible, "back to the Garage")
	_check(float(garage._built(profile.rig).armor) > armor_before, "the Garage stat sheet uses the new level")
	_check(garage._tags[3].part_name.ends_with("LV 3"), "the armor slot tag shows its level")


## Rig upgrades on the Research screen: same data, same buy call, display updates.
func _check_rig_upgrades(research: Node) -> void:
	# Numbers are unchanged by the move (a change here is a gameplay change).
	_check(T.UPGRADES.fabrication == {"name": "Fabrication Discount", "costs": [120, 300, 600], "per_level": 0.10}
		and T.UPGRADES.loot == {"name": "Loot Quality", "costs": [150, 350, 700], "per_level": 0.15}
		and T.UPGRADES.salvage == {"name": "Salvage Yield", "costs": [100, 250, 500], "per_level": 0.15},
		"rig upgrade costs and effects unchanged")
	profile.scrap = 2000
	research.show_rig_upgrades(true)
	_check(research._rig_view.visible and not research._rows.get_parent().visible, "RIG UPGRADES replaces the schematic list")
	_check(research._rig_rows.get_child_count() == 3, "three rig tracks listed")
	var buy: Button = research._rig_rows.find_child("Buy_fabrication", true, false)
	_check(buy != null and buy.text == "BUY  120" and buy.custom_minimum_size.y >= 64.0, "BUY shows the cost, touch-sized")
	var scrap := profile.scrap
	var price := profile.fab_mult()
	buy.pressed.emit()
	_check(profile.upgrade_level("fabrication") == 1 and profile.scrap == scrap - 120, "buying from Research uses profile.buy_upgrade")
	_check(is_equal_approx(profile.fab_mult(), price - 0.10), "the bought level has the same effect")
	buy = research._rig_rows.find_child("Buy_fabrication", true, false)
	_check(buy.text == "BUY  300" and str(research._rig_rows.get_child(0).get_child(1).text) == "LV 1/3", "the display updates after buying")
	_check(research._rig_scrap.text == "Scrap  %d" % profile.scrap, "scrap shown updates")
	research.buy_rig_upgrade("fabrication")
	research.buy_rig_upgrade("fabrication")
	buy = research._rig_rows.find_child("Buy_fabrication", true, false)
	_check(buy.text == "MAXED" and buy.disabled and not research.buy_rig_upgrade("fabrication"), "maxed track can't be bought")
	_check(garage._upgrade_effect("fabrication") == research.RigUpgrades.effect_text(profile, "fabrication"), "garage and Research show the same effect text")
	research.show_rig_upgrades(false)
	_check(not research._rig_view.visible and research._rows.get_parent().visible, "back to schematics")


func _check(ok: bool, what: String) -> void:
	print(("  PASS  " if ok else "  FAIL  ") + what)
	if not ok:
		failures.append(what)


func _finish() -> void:
	if failures.is_empty():
		print("RESEARCH TEST PASSED")
		quit(0)
	else:
		print("RESEARCH TEST FAILED: %s" % ", ".join(failures))
		quit(1)
