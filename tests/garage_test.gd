extends SceneTree
## Headless Garage and economy test. Drives the Garage the way a player would
## (open a slot, tap a card) and checks scrap, storage, power, presets,
## upgrades, the wreck penalty and rebuild rules, banking a run, the save file,
## the crew (Inn, Saloon, seats, deploy rules, crew lost in a wreck), and that
## DEPLOY launches the mission with the rig you built.
##
## Run:  godot --headless --fixed-fps 60 --path . -s res://tests/garage_test.gd

const Garage := preload("res://scripts/garage.gd")
const ProfileScript := preload("res://scripts/profile.gd")
const Parts := preload("res://scripts/parts.gd")
const Loadout := preload("res://scripts/loadout.gd")
const Crew := preload("res://scripts/crew.gd")
const T := preload("res://scripts/tuning.gd")

const CHASSIS := 0      # indexes into Garage.SLOTS
const DRIVE := 2
const ARMOR := 3        # ARMOR FRONT (then SIDES 4, REAR 5)
const WEAPON_2 := 7
const INTERNAL_1 := 8
const UTILITY_2 := 11

var profile: ProfileScript
var garage: Garage
var frame := 0
var failures: Array[String] = []


func _initialize() -> void:
	profile = root.get_node("Profile")
	profile.persist = false
	profile.new_game()
	garage = (load("res://scenes/garage.tscn") as PackedScene).instantiate() as Garage
	root.add_child(garage)


func _process(_delta: float) -> bool:
	frame += 1
	if frame == 3:
		_run_checks()
	if frame == 4:
		# No job yet: DEPLOY sends you to Comms instead of launching.
		garage.deploy()
		_check(garage._comms.visible and garage.is_inside_tree() and current_scene == null, "DEPLOY without a job opens Comms")
		var cards := garage._comms._cards.get_children().size()
		_check(cards == profile.board_size(), "Comms shows today's board (%d jobs)" % cards)
		garage._comms.select(0)
		_check(garage._comms.take_selected() and profile.has_mission(), "TAKE JOB sets the mission")
		_check(not garage._comms.visible and garage._job.text.begins_with("JOB:"), "taking a job returns to the Garage with the job shown")
		garage.deploy()
	if frame == 30:
		var mission := current_scene
		var ok := mission != null and mission.name == "Mission"
		_check(ok, "DEPLOY launches the mission")
		if ok:
			var rig: Node = mission.get("vehicle")
			_check(not rig.call("can_lock"), "the mission rig is the one built in the garage (no targeting, no lock)")
		_finish()
	return false


func _run_checks() -> void:
	# --- New game ----------------------------------------------------------------
	_check(profile.has_rig() and profile.scrap == 60, "new game: starter rig and 60 scrap")
	_check(profile.schematics.size() == 7, "new game: the seven starter schematics")
	_check(not garage._deploy.disabled, "DEPLOY is available with a complete rig")
	var visible_tags := garage._tags.filter(func(t: Control) -> bool: return t.visible).size()
	_check(visible_tags == 10, "Scrap Frame shows 10 slots (3 core, 3 armor, 1 weapon, 2 internal, 1 utility)")
	var seated := profile.seated_crew()
	_check(seated.size() == 2 and seated[0].role == "driver" and seated[1].role == "gunner" and seated[0].rarity == "Common", "new game: a free Common Driver and Gunner, seated")
	_check(garage._crew_line.visible and garage._crew_line.text.contains("DRIVER") and garage._crew_line.text.contains(str(seated[1].name)), "the crew line under the rig names the seats")
	_check(profile.deploy_block() == "", "Driver and Gunner seated: nothing blocks DEPLOY")
	var with_crew := garage._built(profile.rig)
	_check(float(with_crew.turn_rate) > float(Loadout.build(profile.rig).turn_rate), "the stat sheet includes the Driver's turn bonus")

	# The starter has no targeting computer; fit the free one in place of its
	# Junk Emitter (same power) for the power checks.
	garage.open_slot(INTERNAL_1)
	_check(garage.choose("targeting_computer") and profile.scrap == 60, "the Targeting Computer is a free Common schematic")
	garage.close_sheet()

	# --- Building a new part costs scrap; the old one goes to storage ---------------
	garage.open_slot(DRIVE)
	_check(_card_count() == 1, "only owned schematics appear as cards")
	profile.bank_run(0, ["outrider_sport_wheels"] as Array[String])
	profile.scrap = 100
	garage.open_slot(-1)
	garage.open_slot(DRIVE)
	_check(_card_count() == 2, "a newly found schematic shows up in the sheet")
	_check(garage.choose("outrider_sport_wheels"), "tapping a card builds and installs the part")
	_check(profile.scrap == 30, "building Sport Wheels cost 70 scrap")
	_check(int(profile.storage.get("street_wheels", 0)) == 1, "the old wheels went to storage")
	var stats := Loadout.build(profile.rig)
	print("  power with Sport Wheels %d / %d" % [int(stats.power_draw), int(stats.power_output)])
	_check(float(stats.power_draw) > float(stats.power_output), "Sport Wheels + Targeting Computer overloads the starter")
	_check(garage.choose("street_wheels") and profile.scrap == 30, "putting stored wheels back on is free")

	# --- Two-tap cards and the full stat sheet ------------------------------------
	_check(not garage.press_card("outrider_sport_wheels"), "first tap on a card only previews it")
	_check(profile.rig.drive == "street_wheels", "previewing doesn't change the rig")
	var sheet: Variant = garage._stat_sheet
	var speed_now: float = sheet.now.speed
	var speed_after: float = sheet.after.speed
	print("  stat sheet top speed %d > %d (overload included), power load %d > %d" % [roundi(speed_now), roundi(speed_after), int(sheet.now.load), int(sheet.after.load)])
	_check(sheet.visible and int(sheet.after.load) == 110 and float(sheet.after.mobility) < 1.0, "stat sheet shows the previewed part's power and overload")
	_check(garage.press_card("outrider_sport_wheels") and profile.rig.drive == "outrider_sport_wheels", "second tap fits the part")
	_check(garage.press_card("street_wheels") == false and garage.press_card("street_wheels") and profile.scrap == 30, "two taps to swap back, still free")
	garage.close_sheet()
	# V2.3 sample: the stats panel stays on the right (whole-rig stats) when the sheet closes.
	_check(not garage._sheet.visible and sheet.title == "RIG STATS" and garage._rig_holder.visible, "closing the sheet brings the rig back")
	garage.open_slot(DRIVE)

	# --- Taking a part off frees its slot and power -----------------------------------
	garage.open_slot(INTERNAL_1)
	_check(garage.choose("") and int(profile.storage.get("targeting_computer", 0)) == 1, "removing the Targeting Computer stores it")
	_check(float(Loadout.build(profile.rig).lock_range) == 0.0, "no Targeting Computer, no lock")
	garage.close_sheet()

	# --- Presets ----------------------------------------------------------------------
	profile.save_preset(0)
	garage.open_slot(INTERNAL_1)
	garage.choose("targeting_computer")
	_check(profile.build_cost(profile.preset(0)) == 0, "switching to a preset of parts you own is free")
	_check(profile.load_preset(0) and (profile.rig.internal as Array).is_empty(), "loading a preset swaps the rig")
	garage.close_sheet()
	# Preset names: NAME opens a text box; DONE saves it, empty goes back to P1.
	_check(profile.preset_name(0) == "P1", "an unnamed preset shows as P1")
	garage.open_rename(0)
	garage._rename_edit.text = "  Brawler build\n"
	garage.finish_rename(0)
	_check(profile.preset_name(0) == "Brawler build" and not profile.preset(0).is_empty(), "naming a preset keeps its rig (name trimmed)")
	_check(ProfileScript.clean_preset_name("A very long preset name indeed").length() == T.PRESET_NAME_MAX, "names stop at %d letters" % T.PRESET_NAME_MAX)
	profile.save_preset(0)
	_check(profile.preset_name(0) == "Brawler build", "saving over a preset keeps its name")
	var snap: Dictionary = JSON.parse_string(JSON.stringify(profile.save_data()))
	profile.rename_preset(0, "")
	_check(profile.preset_name(0) == "P1", "an empty name goes back to P1")
	profile.apply_data(snap)
	_check(profile.preset_name(0) == "Brawler build", "names round-trip through the save")
	garage._close_overlay()
	# The phone's back button steps back a level at a time.
	garage.open_slot(DRIVE)
	garage.go_back()
	_check(garage.selected == -1 and garage.menu == null, "back closes the part sheet")
	garage._open_presets()
	garage.go_back()
	_check((garage._overlay == null or not is_instance_valid(garage._overlay) or garage._overlay.is_queued_for_deletion()) and garage.menu == null, "back closes an open panel")
	garage.show_tab("INN")
	garage.go_back()
	_check(garage.tab == "GARAGE" and garage.menu == null, "back leaves a station for the garage")
	garage.go_back()
	_check(garage.menu != null, "back on the garage itself opens MENU")
	garage.go_back()
	_check(garage.menu == null or garage.menu.is_queued_for_deletion(), "and back again closes it")
	garage.menu = null

	# --- Weight, frames with more slots, two weapons --------------------------------
	profile.scrap = 1000
	profile.bank_run(0, ["riot_plating", "bulwark_frame", "courier_frame"] as Array[String])
	profile.scrap = 1000
	garage.open_slot(ARMOR)
	garage.preview_part("riot_plating")
	print("  Riot Plating weight %d / %d, mobility %.2f" % [int(sheet.after.weight), int(sheet.after.capacity), float(sheet.after.mobility)])
	_check(int(sheet.now.weight) == 90 and int(sheet.after.weight) == 96, "stat sheet shows weight load (Riot Plating on the front: 90 > 96 of 100)")
	garage.close_sheet()
	var heavy := Parts.STARTER_LOADOUT.duplicate(true)
	for slot: String in ["armor_front", "armor_sides", "armor_rear"]:
		heavy = profile.with_part(heavy, slot, 0, "riot_plating")
	heavy.internal = ["targeting_computer"]
	var heavy_stats := Loadout.build(heavy)
	_check(int(heavy_stats.weight) == 119 and Loadout.mobility(heavy_stats) < 1.0, "Riot Plating all round on the starter is 119 / 100 weight: overloaded")
	_check(garage.StatSheet.overload_cause(heavy_stats).contains("WT 119/100"), "the overload names weight as the cause")
	garage.open_slot(CHASSIS)
	_check(garage.choose("bulwark_frame") and profile.rig.chassis == "bulwark_frame", "Bulwark Frame fitted")
	garage.close_sheet()
	_check(garage._tags[WEAPON_2].visible and not garage._tags[UTILITY_2].visible, "Bulwark shows a WEAPON 2 slot and one utility")
	_check(garage._tags[WEAPON_2].compact, "five tags on the right go compact")
	garage.open_slot(WEAPON_2)
	_check(garage.choose("pintle_turret") and (profile.rig.weapons as Array).size() == 2, "a second Pintle goes on the second hardpoint")
	var twin := Loadout.build(profile.rig)
	_check((twin.weapons as Array).size() == 2 and roundi(Loadout.total_dps(twin)) == 86, "both weapons count: DPS 43 + 43 (sustained, with reloads)")
	_check(int(sheet.now.weapon) == 1 and roundi(float(sheet.now.dps)) == 86, "the WEAPON 2 sheet shows that gun and the total DPS")
	garage.close_sheet()
	garage.open_slot(CHASSIS)
	garage.choose("courier_frame")
	garage.close_sheet()
	_check(not garage._tags[WEAPON_2].visible and garage._tags[UTILITY_2].visible, "Courier: one weapon, two utility slots")
	_check((profile.rig.weapons as Array).size() == 1 and int(profile.storage.get("pintle_turret", 0)) == 1, "the extra gun goes to storage when the frame can't carry it")
	_check(profile.seated_in("gunner").is_empty() and not profile.seated_in("driver").is_empty(), "the Courier seats only a Driver: the Gunner goes back to the Inn")
	_check(profile.deploy_block().contains("turret"), "a turret with no Gunner and no computer blocks DEPLOY")
	_check(profile.load_preset(0), "back to the saved preset")

	# --- Crew: Inn and Saloon -------------------------------------------------------
	garage.show_tab("INN")
	var inn: Variant = garage._inn
	var gunner_id := -1
	for m: Dictionary in profile.crew:
		if m.role == "gunner":
			gunner_id = int(m.id)
	inn.select(gunner_id)
	_check(inn.visible and inn.seat_selected() and int(profile.seated_in("gunner").id) == gunner_id, "the Inn seats the Gunner again")
	var driver_id := int(profile.seated_in("driver").id)
	inn.select(driver_id)
	inn.seat_selected()
	_check(profile.seated_in("driver").is_empty() and profile.deploy_block().contains("Driver"), "no Driver seated blocks DEPLOY")
	inn.seat_selected()
	garage.show_tab("SALOON")
	var saloon: Variant = garage._saloon
	_check(saloon.visible and profile.saloon.size() == 3 and saloon.offer_count() == 5, "the Saloon shows 3 offers plus a free Driver and Gunner")
	var odds_ok := true
	for m: Dictionary in profile.saloon:
		odds_ok = odds_ok and m.rarity != "Common" and int(m.price) == int(T.CREW_PRICES[m.rarity])
	_check(odds_ok, "paid offers are Uncommon or better, priced by rarity")
	profile.scrap = 2000
	var price := int(profile.saloon[0].price)
	saloon.select(0)
	_check(saloon.hire_selected() and profile.scrap == 2000 - price and profile.crew.size() == 3, "hiring an offer costs its price and joins the roster")
	_check(bool(profile.saloon[0].hired) and not saloon.hire_selected(), "an offer can only be hired once")
	saloon.select(3)
	while profile.crew.size() < T.ROSTER_SIZE:
		saloon.hire_selected()
	saloon.select(1)
	_check(profile.crew.size() == T.ROSTER_SIZE and not saloon.hire_selected(), "the roster holds 6: paid hires stop there")
	saloon.select(3)
	_check(saloon.hire_selected() and profile.crew.size() == T.ROSTER_SIZE + 1 and not saloon.hire_selected(), "the free hire can go one over (never stuck without a Driver), no further")
	var spare: Dictionary = profile.crew[profile.crew.size() - 1]
	garage.show_tab("INN")
	inn.select(int(spare.id))
	_check(not inn.dismiss_selected() and profile.crew.size() == T.ROSTER_SIZE + 1, "DISMISS asks first")
	_check(inn.dismiss_selected() and profile.crew.size() == T.ROSTER_SIZE, "a second tap dismisses")
	garage.show_tab("GARAGE")

	# --- Upgrades -------------------------------------------------------------------
	profile.scrap = 200
	_check(profile.buy_upgrade("fabrication") and profile.scrap == 80, "Fabrication Discount level 1 costs 120")
	_check(profile.fab_cost("outrider_twin_guns") == 72, "discount takes 10% off building parts")
	_check(profile.fab_cost("scrap_frame") == 0 and profile.fab_cost("targeting_computer") == 0, "Common parts are free to build")
	_check(not profile.buy_upgrade("loot"), "can't buy an upgrade you can't afford")

	# --- Banking a run; drops never repeat a known schematic ------------------------
	var report := profile.bank_run(15, ["outrider_twin_guns"] as Array[String])
	_check((report.unlocked as Array).has("outrider_twin_guns"), "a new schematic is unlocked on extraction")
	_check(profile.scrap == 80 + 15, "run scrap is banked")
	var unknown := profile.unknown_schematics(Parts.OUTRIDER_DROPS)
	_check(unknown.size() == 4 and unknown.has("outrider_light_plating") and unknown.has("coolant_loop") and unknown.has("shock_pulse") and unknown.has("nitro_bottle"), "drops only offer schematics you don't own")
	_check(profile.unknown_schematics(Parts.OUTRIDER_DROPS, ["outrider_light_plating", "coolant_loop", "shock_pulse", "nitro_bottle"]).is_empty(), "nor ones already picked up this run")

	# --- Wreck: penalty, rebuild, free starter ----------------------------------------
	profile.scrap = 500
	garage.open_slot(DRIVE)
	garage.choose("outrider_sport_wheels")
	garage.close_sheet()
	var plan: Dictionary = profile.rig.duplicate(true)
	var value := profile.build_value(profile.rig)
	var before := profile.scrap
	var aboard := profile.seated_crew().size()
	var roster := profile.crew.size()
	var penalty := profile.record_wreck()
	print("  lost build worth %d, wreck penalty %d" % [value, penalty])
	_check(penalty == roundi(value * 0.25) and profile.scrap == before - penalty, "a wreck costs 25% of the lost build's value")
	_check(aboard >= 2 and profile.crew.size() == roster - aboard and profile.seated_crew().is_empty(), "a wreck kills the seated crew; the Inn's crew survive")
	garage._refresh()
	_check(not profile.has_rig() and garage._deploy.disabled, "a wreck leaves no rig; DEPLOY is off")
	_check(garage._rebuild.visible and profile.plan == plan, "REBUILD offers your last build")
	var cost := profile.build_cost(profile.plan)
	print("  rebuild cost %d (storage: %s)" % [cost, profile.storage])
	_check(cost == profile.fab_cost("outrider_sport_wheels"), "rebuilding charges only for non-Common parts")
	profile.scrap = 10
	garage._refresh()
	_check(garage._rebuild.text == "STARTER RIG  FREE" and not garage._rebuild.disabled, "can't afford your build: a free starter is offered")
	_check(garage.rebuild() and profile.has_rig() and profile.scrap == 10, "the starter rig costs nothing")
	profile.scrap = 3
	_check(profile.record_wreck() == 3 and profile.scrap == 0, "the penalty never takes you below zero")
	_check(profile.schematics.has("outrider_twin_guns"), "schematics survive a wreck")
	_check(profile.apply_loadout(Parts.STARTER_LOADOUT) and profile.has_rig(), "broke and wrecked, you can still roll out")

	# --- Save file round trip ---------------------------------------------------------
	profile.persist = true
	profile.save_path = "user://helriders_test_save.json"
	profile.scrap = 1234
	profile.save_game()
	profile.scrap = 0
	profile.schematics.clear()
	var crew_before := str(profile.crew)
	profile.crew.clear()
	_check(profile.load_game() and profile.scrap == 1234 and profile.schematics.has("outrider_twin_guns"), "save file round-trips")
	_check(str(profile.crew) == crew_before, "the crew round-trip through the save")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(profile.save_path))
	profile.persist = false

	# Leave a no-lock rig for the deploy check, with a free Driver and Gunner
	# from the Saloon (the wreck took the last pair).
	var no_lock := Parts.STARTER_LOADOUT.duplicate(true)
	no_lock.internal = []
	profile.scrap = 500
	profile.apply_loadout(no_lock)
	for role: String in ["driver", "gunner"]:
		if profile.seated_in(role).is_empty():
			if profile.roster_full():
				profile.dismiss(int(profile.crew[0].id))
			profile.hire_basic(role)
	_check(profile.deploy_block() == "", "free Saloon hires get a wrecked player back on the road")


func _card_count() -> int:
	return garage._cards.get_children().filter(func(c: Node) -> bool: return c is Button).size()


func _check(ok: bool, what: String) -> void:
	print(("  PASS  " if ok else "  FAIL  ") + what)
	if not ok:
		failures.append(what)


func _finish() -> void:
	if failures.is_empty():
		print("GARAGE TEST PASSED")
		quit(0)
	else:
		print("GARAGE TEST FAILED: %s" % ", ".join(failures))
		quit(1)
