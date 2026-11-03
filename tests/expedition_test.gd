extends SceneTree
## Headless expeditions and station-upgrade test: the unlock, the daily board,
## odds/pay/bonus math, sending a team (and what away crew can't do), trips
## coming home (success, failure, injuries, bonus finds), every Inn and Saloon
## upgrade, the save file, the Inn and Saloon screens driven like a player, and
## Last Rites saving crew from a real wreck in a mission.
##
## Run:  godot --headless --fixed-fps 60 --path . -s res://tests/expedition_test.gd

const Garage := preload("res://scripts/garage.gd")
const Mission := preload("res://scripts/mission.gd")
const Missions := preload("res://scripts/missions.gd")
const ProfileScript := preload("res://scripts/profile.gd")
const Crew := preload("res://scripts/crew.gd")
const T := preload("res://scripts/tuning.gd")

var profile: ProfileScript
var garage: Garage
var mission: Mission
var riders: Array = []
var frame := 0
var failures: Array[String] = []


func _initialize() -> void:
	profile = root.get_node("Profile")
	profile.persist = false
	profile.new_game()


func _process(_delta: float) -> bool:
	frame += 1
	if frame == 2:
		_check_rules()
		_check_trips()
		_check_inn_upgrades()
		_check_saloon_upgrades()
		_check_save()
		_fresh()
		garage = (load("res://scenes/garage.tscn") as PackedScene).instantiate() as Garage
		root.add_child(garage)
	if frame == 4:
		_check_screens()
		garage.queue_free()
		garage = null
		# Last Rites in a real wreck: both seated crew pull through.
		_fresh()
		profile.upgrades.last_rites = 2
		profile.roll_override = 0.0
		mission = (load("res://scenes/mission.tscn") as PackedScene).instantiate() as Mission
		mission.mission_override = Missions.make("clear", 1, 7)
		mission.auto_spawn_specials = false
		root.add_child(mission)
	if frame == 8:
		riders = profile.seated_crew().map(func(m: Dictionary) -> int: return int(m.id))
		mission.vehicle.wrecked.emit()
	if frame == 8 + 60 * 3:
		var text := str(mission.hud._subtitle.text)
		_check(text.contains("Last Rites:") and not text.contains("Crew lost"), "the wreck card says who Last Rites saved")
		_check(riders.size() == 2 and profile.crew.size() == 6, "both seated crew survived the wreck")
		var resting := riders.all(func(id: int) -> bool:
			var m := profile.member(id)
			return not m.is_empty() and int(m.rest) > 0 and not bool(m.seated))
		_check(resting, "survivors come home injured and unseated")
		_finish()
	return false


## A new game where 3 jobs are cleared and 4 more benched crew wait at the Inn.
func _fresh() -> void:
	profile.new_game()
	profile.roll_override = -1.0
	profile.record.clears = T.EXPEDITION_UNLOCK_CLEARS
	profile.scrap = 5000
	var dice := RandomNumberGenerator.new()
	dice.seed = 7
	for role: String in ["mechanic", "medic", "spotter", "bruiser"]:
		var m := profile._add_crew(Crew.make(role, "Rare", dice))
		m.xp = float(Crew.xp_for_level(3))  # level 3 each


func _bench() -> Array:
	var ids: Array = []
	for m: Dictionary in profile.crew:
		if profile.can_send(m):
			ids.append(int(m.id))
	return ids


func _check_rules() -> void:
	profile.new_game()
	_check(not profile.expeditions_open() and profile.send_block(0, [1]) == "LOCKED", "expeditions are locked on day 1")
	profile.record.clears = 2
	_check(not profile.expeditions_open(), "still locked after 2 clears")
	profile.record.clears = 3
	_check(profile.expeditions_open(), "the board opens after 3 successful jobs")

	profile.ensure_exp_board()
	_check(profile.exp_board.size() == 3, "3 trips on the board")
	var first := str(profile.exp_board)
	profile.exp_board_day = 0
	profile.ensure_exp_board()
	_check(str(profile.exp_board) == first, "the board is the same all day")
	var bands := true
	var lengths := {}
	var bonuses := 0
	var entries := 0
	for d in range(1, 200):
		profile.day = d
		profile.ensure_exp_board()
		for i in profile.exp_board.size():
			var e: Dictionary = profile.exp_board[i]
			bands = bands and int(e.skulls) >= i * 2 + 1 and int(e.skulls) <= i * 2 + 2
			lengths[int(e.days)] = true
			entries += 1
			if str(e.bonus) != "":
				bonuses += 1
	_check(bands, "one easy (1-2), one middling (3-4) and one hard (5-6) trip each day")
	_check(lengths.size() == 3, "trips last 1, 2 or 3 days")
	var share := float(bonuses) / entries
	_check(share > 0.18 and share < 0.32, "about 1 in 4 trips offers a bonus find (%d%%)" % roundi(share * 100.0))
	profile.day = 1
	profile.exp_board_day = 0

	var trip := {"skulls": 3, "days": 2, "bonus": "schematic"}
	_check(ProfileScript.recommended_level(trip) == 10, "3 skulls: recommended team level 10")
	_check(ProfileScript.expedition_scrap(trip) == 76 and ProfileScript.expedition_xp(trip) == 6, "3 skulls, 2 days pays 76 scrap and 6 XP")
	_check(is_equal_approx(ProfileScript.bonus_chance(trip), 0.18), "bonus chance 3% per skull per day (18%)")
	_check(ProfileScript.bonus_chance({"skulls": 3, "days": 2, "bonus": ""}) == 0.0, "no bonus listed, no bonus roll")

	# Odds: crew levels against the recommended level.
	_fresh()
	var ids := _bench()   # four level-3 crew
	var one := [ids[0]]
	var e1 := {"skulls": 1, "days": 1, "bonus": ""}
	_check(is_equal_approx(profile.expedition_odds(e1, one), 0.70), "at the recommended level: 70%")
	_check(is_equal_approx(profile.expedition_odds(e1, [ids[0], ids[1]]), 0.82), "3 levels over: +12% (82%)")
	_check(is_equal_approx(profile.expedition_odds(e1, ids), 0.95), "odds top out at 95%")
	var e2 := {"skulls": 2, "days": 1, "bonus": ""}
	_check(is_equal_approx(profile.expedition_odds(e2, one), 0.46), "3 levels under: -24% (46%)")
	_check(is_equal_approx(profile.expedition_odds({"skulls": 6, "days": 1, "bonus": ""}, one), 0.05), "odds bottom out at 5%")
	profile.upgrades.scout_network = 2
	_check(is_equal_approx(profile.expedition_odds(e2, one), 0.56), "Scout Network +5% a step")


func _check_trips() -> void:
	_fresh()
	profile.ensure_exp_board()
	var seated := profile.seated_in("driver")
	_check(profile.send_block(0, [int(seated.id)]) == "CREW NOT FREE", "seated crew can't go")
	var ids := _bench()
	var resting := profile.member(int(ids[3]))
	resting.rest = 2
	_check(profile.send_block(0, [int(ids[3])]) == "CREW NOT FREE", "resting crew can't go")
	resting.rest = 0
	_check(profile.send_block(0, []) == "PICK A TEAM", "a team needs someone")

	# Force a 2-day trip and send three.
	var e: Dictionary = profile.exp_board[1]
	e.days = 2
	e.bonus = "schematic"
	var team := [ids[0], ids[1], ids[2]]
	var odds := profile.expedition_odds(e, team)
	_check(profile.send_expedition(1, team), "SEND puts the team on the road")
	_check(bool(e.taken) and profile.send_block(1, [ids[3]]) == "ALREADY SENT", "a trip goes once")
	_check(profile.send_block(0, [ids[3]]) == "TEAM ALREADY OUT", "one team out at a time")
	var away := profile.member(int(ids[0]))
	_check(profile.is_away(away) and profile.seat_block(away) == "ON EXPEDITION" and not profile.seat_member(int(ids[0])),
		"away crew can't be seated")
	_check(not profile.dismiss(int(ids[0])), "away crew can't be dismissed")
	_check(is_equal_approx(float(profile.expeditions[0].odds), odds), "the odds are fixed when they leave")

	# Second Team: a second trip can go.
	profile.upgrades.second_team = 1
	_check(profile.expeditions_at_once() == 2 and profile.send_block(0, [ids[3]]) == "", "Second Team: two out at once")

	# Day 1 passes: still out. Day 2: back, a success with the bonus find.
	profile.roll_override = 0.0
	var scrap0 := profile.scrap
	var xp0 := float(away.xp)
	var known := profile.schematics.size()
	profile.finish_day()
	_check(profile.is_away(away) and int(profile.expeditions[0].days_left) == 1, "after one day the team is still out")
	profile.finish_day()
	_check(not profile.is_away(away) and profile.expeditions.is_empty(), "after two days they're home")
	var pay := ProfileScript.expedition_scrap(e)
	_check(profile.scrap == scrap0 + pay, "success pays the full scrap (%d)" % pay)
	_check(is_equal_approx(float(away.xp) - xp0, float(ProfileScript.expedition_xp(e)) / 3.0), "XP is split among the team")
	_check(profile.schematics.size() == known + 1 and profile.expedition_reports.any(func(l: String) -> bool: return l.begins_with("New schematic")),
		"the bonus find brought a new schematic")
	_check(profile.notice.contains("Details at the Inn"), "the Garage gets a notice when a trip comes home")

	# A failed trip: part of the scrap, half the XP, injuries on a low roll.
	_fresh()
	profile.ensure_exp_board()
	ids = _bench()
	var hard: Dictionary = profile.exp_board[2]
	hard.days = 1
	_check(profile.send_expedition(2, [ids[0]]), "a lone level-3 goes on a hard trip")
	var lone := profile.member(int(ids[0]))
	profile.roll_override = 0.2   # over the 5% odds, under the 25% injury roll
	scrap0 = profile.scrap
	xp0 = float(lone.xp)
	profile.finish_day()
	var fail_pay := roundi(ProfileScript.expedition_scrap(hard) * T.EXPEDITION_FAIL_SCRAP)
	_check(profile.scrap == scrap0 + fail_pay, "failure brings back 25%% of the scrap (%d)" % fail_pay)
	_check(is_equal_approx(float(lone.xp) - xp0, ProfileScript.expedition_xp(hard) * 0.5), "failure: half the XP")
	_check(int(lone.rest) == T.CREW_REST_DAYS and profile.crew.has(lone), "failure can injure, but nobody is lost")

	# A recruit with no free bunk.
	_fresh()
	while not profile.roster_full():
		profile._add_crew(Crew.make("medic", "Common", RandomNumberGenerator.new()))
	_check(profile._bonus_find("recruit").contains("no free bunk"), "a recruit needs a free bunk")
	profile.dismiss(int(profile.crew[profile.crew.size() - 1].id))
	var size := profile.crew.size()
	_check(profile._bonus_find("recruit").begins_with("New recruit") and profile.crew.size() == size + 1, "a recruit joins the roster")


func _check_inn_upgrades() -> void:
	_fresh()
	_check(profile.roster_cap() == 6 and profile.buy_upgrade("bunkhouse") and profile.roster_cap() == 7, "Bunkhouse: roster +1")
	_check(profile.rest_days(2) == 2 and profile.buy_upgrade("infirmary") and profile.rest_days(2) == 1 and profile.rest_days(1) == 1,
		"Infirmary: rest a day shorter, never under 1")
	# Drill Yard: idle crew learn a share; away crew don't.
	profile.buy_upgrade("drill_yard")
	profile.ensure_exp_board()
	var ids := _bench()
	profile.send_expedition(0, [ids[0]])
	var idle := profile.member(int(ids[1]))
	var gone := profile.member(int(ids[0]))
	var xi := float(idle.xp)
	var xg := float(gone.xp)
	var lines := profile.bank_crew(4, [])
	_check(is_equal_approx(float(idle.xp) - xi, 1.0), "Drill Yard: idle crew get 25% of a 4-skull job (1 XP)")
	_check(float(gone.xp) == xg, "away crew don't get Drill Yard XP")
	_check(lines.any(func(l: String) -> bool: return l.begins_with("Drill Yard")), "the results card lists Drill Yard XP")

	# Last Rites: locked until Industrial Spine, then saves crew on a wreck.
	_check(profile.upgrade_block("last_rites") != "" and not profile.buy_upgrade("last_rites"), "Last Rites waits for Industrial Spine")
	for id: String in ["bulwark_frame", "diesel_block", "half_track", "composite_plating", "heavy_mg_turret", "advanced_targeting", "mine_dropper"]:
		profile.schematics.append(id)
		profile.levels[id] = 5
	_check(profile.is_district_open(T.LAST_RITES_DISTRICT) and profile.buy_upgrade("last_rites"), "Last Rites on sale once Industrial Spine opens")
	profile.roll_override = 0.05
	var driver := profile.seated_in("driver")
	profile.record_wreck()
	_check(profile.crew.has(driver) and int(driver.rest) == T.LAST_RITES_REST and not bool(driver.seated), "a 10% roll saves a seated crew member, injured")
	_fresh()
	profile.upgrades.last_rites = 1
	profile.roll_override = 0.5
	var before := profile.crew.size()
	profile.record_wreck()
	_check(profile.crew.size() == before - 2 and profile.last_wreck_survivors.is_empty(), "a miss and the crew are lost as before")


func _check_saloon_upgrades() -> void:
	_fresh()
	profile.upgrades.bunkhouse = 2   # room to hire
	profile.ensure_saloon()
	var first := str(profile.saloon[0].name)
	profile.hire_offer(0)
	_check(profile.buy_upgrade("back_room") and profile.saloon.size() == 4, "Back Room: a 4th offer today")
	_check(str(profile.saloon[0].name) == first and bool(profile.saloon[0].hired), "today's offers stay as they were")
	var odds := ProfileScript.saloon_odds(3)
	var total := 0.0
	for r: String in odds:
		total += float(odds[r])
	_check(is_equal_approx(total, 100.0) and float(odds.Rare) == 43.0 and float(odds.Epic) == 15.0, "Word Gets Around x3: Rare 43%, Epic 15%, still 100%")
	_check(profile.buy_upgrade("house_credit") and profile.hire_price({"price": 200}) == 180, "House Credit: 10% off")
	profile.buy_upgrade("seasoned_hands")
	var size := profile.crew.size()
	_check(profile.hire_basic("driver") and Crew.level(profile.crew[size]) == 2, "Seasoned Hands: hires start at level 2")
	_check(Crew.level(profile.saloon[1]) == 2, "unhired offers show the new starting level")


func _check_save() -> void:
	_fresh()
	profile.ensure_exp_board()
	var ids := _bench()
	profile.send_expedition(0, [ids[0], ids[1]])
	profile.expedition_reports = ["Old trip: fine."]
	profile.persist = true
	profile.save_path = "user://helriders_expedition_test_save.json"
	profile.save_game()
	var trips := str(profile.expeditions)
	var board := str(profile.exp_board)
	profile.expeditions = []
	profile.exp_board = []
	_check(profile.load_game() and str(profile.expeditions) == trips and str(profile.exp_board) == board, "trips and the board round-trip")
	_check(profile.expedition_reports == ["Old trip: fine."] and profile.is_away(profile.member(int(ids[0]))), "reports and away crew survive a reload")
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(profile.save_path))
	for key: String in ["exp_board", "exp_board_day", "expeditions", "expedition_reports"]:
		data.erase(key)
	var file := FileAccess.open(profile.save_path, FileAccess.WRITE)
	file.store_string(JSON.stringify(data))
	file.close()
	_check(profile.load_game() and profile.expeditions.is_empty(), "a save from before expeditions loads with nobody away")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(profile.save_path))
	profile.persist = false


func _check_screens() -> void:
	var inn := garage._inn
	garage.show_tab("INN")
	profile.record.clears = 0
	inn.open_expeditions()
	_check(inn.is_showing_expeditions() and inn.send_selected() == false, "the locked board can't send anyone")
	inn.close_expeditions()
	profile.record.clears = T.EXPEDITION_UNLOCK_CLEARS
	inn.open_expeditions()
	_check(inn.trip == 0, "the first trip is picked")
	var ids := _bench()
	for id: Variant in ids:
		inn.toggle_team(int(id))
	inn.toggle_team(int(ids[3]))
	_check(inn.team.size() == 3, "tap crew to add them, tap again to take them off")
	inn.toggle_team(int(profile.seated_in("driver").id))
	_check(inn.team.size() == 3, "seated crew can't join the team")
	_check(inn.send_selected() and profile.expeditions.size() == 1, "SEND from the Inn")
	inn.close_expeditions()
	inn.refresh()
	var away_cards := 0
	for card: Node in inn._cards.get_children():
		if str(card.get("status")).begins_with("AWAY"):
			away_cards += 1
	_check(away_cards == 3, "away crew show AWAY on their cards")
	_check(inn._away.text.begins_with("OUT:"), "the Inn shows who's out")
	var panel := inn.open_upgrades()
	var scrap := profile.scrap
	_check(panel.buy_track("bunkhouse") and profile.scrap == scrap - 150 and inn._title.text.ends_with("/ 7"), "buy an Inn upgrade from its panel")
	inn.close_upgrades()

	garage.show_tab("SALOON")
	var saloon := garage._saloon
	var spanel := saloon.open_upgrades()
	_check(spanel.buy_track("back_room") and saloon._cards.get_child_count() == profile.saloon_offers() + 2, "Back Room adds a card at the Saloon")
	saloon.close_upgrades()
	_check(saloon._note.text.contains("Odds today:"), "the Saloon shows today's odds")


func _check(ok: bool, what: String) -> void:
	print(("  PASS  " if ok else "  FAIL  ") + what)
	if not ok:
		failures.append(what)


func _finish() -> void:
	if failures.is_empty():
		print("EXPEDITION TEST PASSED")
		quit(0)
	else:
		print("EXPEDITION TEST FAILED: %s" % ", ".join(failures))
		quit(1)
