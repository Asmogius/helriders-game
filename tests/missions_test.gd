extends SceneTree
## Headless Comms and mission-type test: the daily board, Comms upgrades,
## district score, abandoning a run, then one short run of each mission type
## (Clear setup, Survive, Hunt, Courier) driven to its ending. Along the way:
## crew XP split, an injury and its rest days, a level-up, Saloon offers and
## odds, and loading a save from before crew.
##
## Run:  godot --headless --fixed-fps 60 --path . -s res://tests/missions_test.gd

const Mission := preload("res://scripts/mission.gd")
const Missions := preload("res://scripts/missions.gd")
const ProfileScript := preload("res://scripts/profile.gd")
const Parts := preload("res://scripts/parts.gd")
const Layouts := preload("res://scripts/layouts.gd")
const T := preload("res://scripts/tuning.gd")
const Crew := preload("res://scripts/crew.gd")

var profile: ProfileScript
var failures: Array[String] = []
var frame := 0
var step := 0
var mission: Mission
var mark := {}


func _initialize() -> void:
	profile = root.get_node("Profile")
	profile.persist = false
	profile.new_game()
	seed(20261104)   # deterministic spawns and rolls, so a failure always reproduces


func _process(_delta: float) -> bool:
	frame += 1
	match step:
		0:
			_check_board()
			_check_districts()
			_check_bulwark_tables()
			_start(Missions.make("clear", 1, 7), true)
		1:
			if frame == 3:
				_check(mission.skulls == 1 and mission.target_kills == 31, "Clear 1 skull: 30 shamblers + 1 Hunter, no Outrider")
				_check(mission.bulwarks.size() == 1 and not mission.bulwark.is_inside_tree(), "one Bulwark is built up front but stays out of a 1-skull Clear")
				_check(mission.zombies.cap == 19, "Clear 1 skull: crowd capped at 19 (24, 20% smaller at 1 skull)")
				_next()
		2:
			_start(Missions.make("survive", 1, 7), true)
		3:
			if frame == 2:
				mark = {"scrap": profile.scrap, "day": profile.day, "known": profile.schematics.size()}
				mission.elapsed = 118.5
				mission.vehicle.injure_crew(1)  # the Gunner
				_check(mission.music_boosts() >= T.MUSIC_SURVIVE_FINAL_BOOST, "Survive's last stretch pushes the music up")
			if frame == 120:
				_check(mission.state == Mission.State.CLEARED and mission.hud.result_text().contains("HELD THE BLOCK"), "Survive ends when the timer runs out")
				_check(profile.scrap >= int(mark.scrap) + int(Missions.make("survive", 1, 7).reward), "Survive pays the job's reward")
				_check(profile.day == int(mark.day) + 1 and not profile.has_mission(), "finishing a job ends the day")
				_check(profile.schematics.size() == int(mark.known), "a 1-skull job never pays a schematic")
				var driver: Dictionary = profile.crew[0]
				var gunner: Dictionary = profile.crew[1]
				_check(is_equal_approx(float(driver.xp), 0.5) and is_equal_approx(float(gunner.xp), 0.5), "a 1-skull job's XP is split: 0.5 each for two crew")
				_check(int(gunner.rest) == T.CREW_REST_DAYS and not bool(gunner.seated) and profile.is_resting(gunner), "the injured Gunner goes to the Inn for 2 days")
				_check(not profile.seat_member(int(gunner.id)), "resting crew can't be seated")
				_check(mission.hud.result_text().contains("Crew:") and mission.hud.result_text().contains("injured"), "the results card reports crew XP and the injury")
				_next()
		4:
			_start(Missions.make("hunt", 4, 7), true)
		5:
			if frame == 300:
				var e := mission.elite
				_check(e != null and e.is_inside_tree() and e.is_elite(), "Hunt: the Elite rolls in")
				_check(mission.music_boosts() >= T.MUSIC_ELITE_BOOST, "an Elite alive pushes the music up")
				_check(mission.bulwark.is_inside_tree(), "a 4-skull Hunt brings a Bulwark escort")
				print("  4-skull Elite armor %d" % roundi(e.armor_max))
				_check(is_equal_approx(e.armor_max, T.OUTRIDER.armor * 2.1) and e.lock_priority > mission.outrider.lock_priority, "4-skull Elite has 2.1x armor and is first in line for lock")
				# Back off first, or a drop landing beside you is picked up at once.
				var away := mission.vehicle.global_position - e.global_position
				mission.vehicle.global_position = e.global_position + (away.normalized() if away.length() > 1.0 else Vector2.RIGHT) * 500.0
				# A stray cache elsewhere on the ground (a Tank's, say) must not
				# stop the Hunt finishing: place one every run, so this is tested
				# every time rather than only when a Tank happens to drop one.
				mission.drop_cache(mission.vehicle.global_position + Vector2(0, 900), 10)
				e.take_damage(99999.0)
			if frame == 305:
				# Its wreck blast can take a nearby rig (its Patcher, say) with it,
				# so look for the Elite's own crate rather than the newest one.
				var crate: Variant = mission._rig_crate.get(mission.elite)
				# Check the Elite's own crate, not the crate count: moving the rig
				# can land it on an older crate (a Tank's cache, a rig's salvage)
				# and pick that up in these frames, so the count may not grow.
				_check(crate != null and is_instance_valid(crate) and (crate as Node).get_parent() == mission.pickups, "the Elite always drops something")
				_check(mission.state == Mission.State.RUNNING, "Hunt isn't over until you grab the drop")
				mark = {"known": profile.schematics.size()}
				if crate != null:
					mission.vehicle.global_position = (crate as Node2D).global_position
			if frame == 315:
				_check(mission.state == Mission.State.CLEARED and mission.hud.result_text().contains("TARGET DOWN"), "grabbing the Elite's drop completes the Hunt")
				_check(profile.schematics.size() >= int(mark.known) + 1, "the Elite's schematic is banked")
				var driver: Dictionary = profile.crew[0]
				print("  Driver XP after the Hunt %.1f, level %d" % [float(driver.xp), Crew.level(driver)])
				_check(is_equal_approx(float(driver.xp), 4.5) and Crew.level(driver) == 2, "riding alone, the Driver takes all 4 XP and reaches level 2")
				_check(mission.hud.result_text().contains("level 2"), "the results card shows the level-up")
				_check(int(profile.crew[1].rest) == 1 and is_equal_approx(float(profile.crew[1].xp), 0.5), "the resting Gunner earns nothing and heals a day")
				_next()
		6:
			_start(Missions.make("courier", 1, 7), false)
		7:
			if frame == 3:
				print("  courier route %s, par gold %.1fs silver %.1fs bronze %.1fs" % [mission.checkpoints, mission.par.gold, mission.par.silver, mission.par.bronze])
				_check(mission.checkpoints.size() == 5, "Courier 1 skull: five checkpoints")
				_check(float(mission.par.gold) > 10.0 and float(mission.par.bronze) > float(mission.par.gold), "par times are set from the route")
				var ok := true
				for i in mission.checkpoints.size():
					var p := mission.checkpoints[i]
					var prev: Vector2 = mission.checkpoints[i - 1] if i > 0 else Vector2(1600, 1200)
					ok = ok and prev.distance_to(p) >= 499.0 and not mission.nav.astar.is_point_solid(mission.nav.cell_of(p))
				_check(ok, "checkpoints sit on open ground, a fair drive apart")
				mark = {"scrap": profile.scrap}
			if frame >= 5 and frame % 4 == 0 and mission.state == Mission.State.RUNNING:
				mission.vehicle.global_position = mission.checkpoints[mission.checkpoint_index]
			if frame == 60:
				_check(mission.state == Mission.State.CLEARED and mission.hud.result_text().contains("GOLD"), "hitting every checkpoint fast is a gold delivery")
				_check(profile.scrap >= int(mark.scrap) + int(Missions.make("courier", 1, 7).reward), "gold pays the full reward")
				var gunner: Dictionary = profile.crew[1]
				_check(int(gunner.rest) == 0 and profile.seat_member(int(gunner.id)), "two days later the Gunner is healed and can ride again")
				_next()
		8:
			_start(Missions.make("courier", 2, 9), false)
		9:
			if frame == 3:
				mission.elapsed = float(mission.par.bronze) + 5.0
				for i in mission.checkpoints.size():
					mission.reach_checkpoint()
				_check(mission.hud.result_text().contains("LATE"), "too slow is a late delivery")
				_next()
		10:
			_check_abandon()
			_check_saloon_and_old_save()
			_finish()
	return false


func _start(m: Dictionary, specials: bool) -> void:
	if mission != null:
		mission.queue_free()
	mission = (load("res://scenes/mission.tscn") as PackedScene).instantiate() as Mission
	mission.mission_override = m
	mission.auto_spawn_specials = specials
	mission.push_override = 0   # these runs test objectives; push_test covers Extract or Push
	root.add_child(mission)
	# Keep the rig alive: these runs test objectives, not survival.
	mission.vehicle.armor_max = 1000000.0
	mission.vehicle.armor = 1000000.0
	frame = 0
	step += 1


func _next() -> void:
	frame = 0
	step += 1


func _check_bulwark_tables() -> void:
	var clear3 := Missions.make("clear", 3, 7)
	_check(Missions.threats_text(clear3).contains("1 Bulwark") and not Missions.threats_text(clear3).contains("Outrider"), "a 3-skull Clear lists a Bulwark instead of an Outrider")
	_check(not Missions.threats_text(Missions.make("clear", 2, 7)).contains("Bulwark"), "no Bulwarks below 3 skulls")
	_check(Missions.threats_text(Missions.make("survive", 6, 7)).contains("1 Bulwark"), "a 6-skull Survive sends a Bulwark")
	_check(not Missions.threats_text(Missions.make("courier", 6, 7)).contains("Bulwark"), "Courier jobs stay Bulwark-free")
	var most := 0
	for type: String in ["clear", "survive", "hunt"]:
		for level in range(1, T.MAX_SKULLS + 1):
			var m := Missions.make(type, level, 7)
			var rigs := 0
			for key: String in ["outriders", "escorts", "bulwarks", "bulwark_escorts"]:
				rigs += Missions._count(m, key)
			if type == "hunt":
				rigs += 1  # the Elite
			most = maxi(most, rigs)
	_check(most <= T.MAX_ENEMY_RIGS, "no job sends more than 3 enemy rigs (most: %d)" % most)


func _check_board() -> void:
	_check(profile.board.size() == 3 and profile.day == 1, "day 1 board has three jobs")
	var again := Missions.make_board(1, 3, 0)
	_check(str(again) == str(profile.board), "the board is the same every time you look that day")
	var types := {}
	for m: Dictionary in profile.board:
		types[m.type] = true
	_check(types.size() == 3, "three different job types on the board")
	var in_band := true
	var seen := {}
	for d in range(1, 41):
		for m: Dictionary in Missions.make_board(d, 3, 0):
			in_band = in_band and int(m.skulls) >= 1 and int(m.skulls) <= 4
			seen[int(m.skulls)] = true
	_check(in_band and seen.size() == 4, "Outer Blocks jobs roll 1 to 4 skulls (40 days: %s)" % str(seen.keys()))
	_check(Missions.skull_band("midtown") == Vector2i(2, 5) and Missions.skull_band("core") == Vector2i(4, 6), "district skull bands climb")
	_check(Missions.schematic_chance(Missions.make("clear", 1, 1)) == 0.0 and Missions.schematic_chance(Missions.make("clear", 6, 1)) == 1.0, "schematic odds run 0% at 1 skull to 100% at 6")
	var old_save: Dictionary = ProfileScript._clean_mission({"type": "hunt", "threat": 3, "name": "Rustjaw", "seed": 1, "reward": 170})
	_check(int(old_save.skulls) == 6 and not old_save.has("threat"), "an old save's threat 3 job loads as 6 skulls")
	profile.choose_mission(1)
	_check(profile.has_mission() and profile.active_mission.id == profile.board[1].id, "taking a job sets it for DEPLOY")
	var day1 := str(profile.board)
	profile.finish_day()
	_check(profile.day == 2 and str(profile.board) != day1 and not profile.has_mission(), "a new day brings a new board")

	profile.scrap = 1000
	var first_three := str(profile.board.slice(0, 3))
	_check(profile.buy_upgrade("choices") and profile.board.size() == 4, "Wider Net adds a fourth job")
	_check(str(profile.board.slice(0, 3)) == first_three, "the first three jobs stay put")
	var pay_before := int(profile.board[0].reward)
	_check(profile.buy_upgrade("quality") and int(profile.board[0].reward) > pay_before, "Better Leads raises the pay")

	_check(profile.district_score() == 0, "starter schematics don't count toward districts")
	var drops: Array[String] = []
	drops.assign(Parts.OUTRIDER_DROPS.slice(0, 4))   # four Uncommons
	profile.bank_run(0, drops)
	print("  district score after four Outrider drops: %d" % profile.district_score())
	_check(profile.district_score() == 8 and not profile.is_district_open(1) and profile.is_district_open(0), "four Uncommons score 8 of Midtown's 40")
	profile.new_game()


## Playtest P1-1 / P2-3: the board follows the furthest open district (skull
## band and layouts), on a throwaway profile so the run's own save is untouched.
func _check_districts() -> void:
	var p: Node = ProfileScript.new()
	p.set("persist", false)
	p.new_game()
	_check(p.board_district() == "outer_blocks", "a new game's board is Outer Blocks")
	for m: Dictionary in Missions.make_board(3, 6, 0, "outer_blocks"):
		_check(str(Layouts.LAYOUTS[str(m.layout)].district) == "outer_blocks", "Outer Blocks board uses only Outer Blocks maps (%s)" % m.layout)
	# Extract parts (not starters) until Midtown opens.
	var need := int(T.DISTRICTS[1].need)
	for id: String in Parts.CATALOG:
		if p.district_score() >= need:
			break
		if not Parts.STARTER_SCHEMATICS.has(id) and not p.schematics.has(id):
			p.schematics.append(id)
	_check(p.is_district_open(1) and p.board_district() != "outer_blocks", "unlocking Midtown moves the board's district (%s, score %d)" % [p.board_district(), p.district_score()])
	p.board = []
	p.ensure_board()
	var band: Vector2i = Missions.skull_band(p.board_district())
	var open: Array = Missions.districts_through(p.board_district())
	var ok := true
	for m: Dictionary in p.board:
		ok = ok and int(m.skulls) >= band.x and int(m.skulls) <= band.y and open.has(str(Layouts.LAYOUTS[str(m.layout)].district))
	_check(ok, "the Profile's board rolls the open district's band %s with open-district maps" % str(band))
	var seen := {}
	for d in range(1, 41):
		for m: Dictionary in Missions.make_board(d, 3, 0, "midtown"):
			seen[int(m.skulls)] = true
	_check(seen.has(5), "Midtown boards reach 5 skulls")
	p.free()


func _check_saloon_and_old_save() -> void:
	# Offers are the same all day and change with the day.
	var today := str(profile.saloon)
	profile.saloon_day = 0
	profile.ensure_saloon()
	_check(str(profile.saloon) == today, "the Saloon's offers are the same every time you look that day")
	profile.finish_day()
	_check(str(profile.saloon) != today and profile.saloon.size() == T.SALOON_OFFERS, "a new day brings new offers")
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var counts := {}
	for i in 4000:
		var r := ProfileScript._roll_rarity(rng)
		counts[r] = int(counts.get(r, 0)) + 1
	print("  4000 Saloon rolls: %s" % str(counts))
	var uncommon := float(counts.get("Uncommon", 0)) / 4000.0
	var epic := float(counts.get("Epic", 0)) / 4000.0
	_check(absf(uncommon - 0.6) < 0.04 and absf(epic - 0.09) < 0.02 and not counts.has("Common") and int(counts.get("Mythic", 0)) < 60, "rarity odds follow 60 / 28 / 9 / 2.5 / 0.5")

	# A save from before crew loads with the starter pair seated.
	profile.persist = true
	profile.save_path = "user://helriders_old_save_test.json"
	var file := FileAccess.open(profile.save_path, FileAccess.WRITE)
	file.store_string(JSON.stringify({"version": 1, "scrap": 90, "schematics": ["scrap_frame"], "rig": Parts.STARTER_LOADOUT, "day": 4}))
	file.close()
	var loaded := profile.load_game()
	_check(loaded and profile.crew.size() == 2 and profile.seated_crew().size() == 2, "an old save without crew gets the starter Driver and Gunner")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(profile.save_path))
	profile.persist = false


func _check_abandon() -> void:
	var day := profile.day
	profile.active_mission = Missions.make("clear", 1, 7)
	profile.start_run()
	profile.call("_ready")  # what happens on the next launch
	_check(profile.day == day and profile.run_active and profile.resume_job(), "quitting mid-run costs nothing: the next launch drops you back into the job")
	profile.run_active = false
	profile.active_mission = {}


func _check(ok: bool, what: String) -> void:
	print(("  PASS  " if ok else "  FAIL  ") + what)
	if not ok:
		failures.append(what)


func _finish() -> void:
	if failures.is_empty():
		print("MISSIONS TEST PASSED")
		quit(0)
	else:
		print("MISSIONS TEST FAILED: %s" % ", ".join(failures))
		quit(1)
