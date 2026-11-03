extends SceneTree
## Headless Comms and mission-type test: the daily board, Comms upgrades,
## district score, abandoning a run, then one short run of each mission type
## (Clear setup, Survive, Hunt, Courier) driven to its ending.
##
## Run:  godot --headless --fixed-fps 60 --path . -s res://tests/missions_test.gd

const Mission := preload("res://scripts/mission.gd")
const Missions := preload("res://scripts/missions.gd")
const ProfileScript := preload("res://scripts/profile.gd")
const Parts := preload("res://scripts/parts.gd")
const T := preload("res://scripts/tuning.gd")

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


func _process(_delta: float) -> bool:
	frame += 1
	match step:
		0:
			_check_board()
			_start(Missions.make("clear", 1, 7), true)
		1:
			if frame == 3:
				_check(mission.skulls == 1 and mission.target_kills == 31, "Clear 1 skull: 30 shamblers + 1 Hunter, no Outrider")
				_check(mission.zombies.cap == 24, "Clear 1 skull: crowd capped at 24")
				_next()
		2:
			_start(Missions.make("survive", 1, 7), true)
		3:
			if frame == 2:
				mark = {"scrap": profile.scrap, "day": profile.day, "known": profile.schematics.size()}
				mission.elapsed = 118.5
			if frame == 120:
				_check(mission.state == Mission.State.CLEARED and mission.hud.result_text().contains("HELD THE BLOCK"), "Survive ends when the timer runs out")
				_check(profile.scrap >= int(mark.scrap) + int(Missions.make("survive", 1, 7).reward), "Survive pays the job's reward")
				_check(profile.day == int(mark.day) + 1 and not profile.has_mission(), "finishing a job ends the day")
				_check(profile.schematics.size() == int(mark.known), "a 1-skull job never pays a schematic")
				_next()
		4:
			_start(Missions.make("hunt", 4, 7), true)
		5:
			if frame == 300:
				var e := mission.elite
				_check(e != null and e.is_inside_tree() and e.is_elite(), "Hunt: the Elite rolls in")
				print("  4-skull Elite armor %d" % roundi(e.armor_max))
				_check(is_equal_approx(e.armor_max, T.OUTRIDER.armor * 2.1) and e.lock_priority > mission.outrider.lock_priority, "4-skull Elite has 2.1x armor and is first in line for lock")
				e.take_damage(99999.0)
			if frame == 305:
				_check(mission.pickups.get_child_count() == 1, "the Elite always drops something")
				_check(mission.state == Mission.State.RUNNING, "Hunt isn't over until you grab the drop")
				mark = {"known": profile.schematics.size()}
				mission.vehicle.global_position = (mission.pickups.get_child(0) as Node2D).global_position
			if frame == 315:
				_check(mission.state == Mission.State.CLEARED and mission.hud.result_text().contains("TARGET DOWN"), "grabbing the Elite's drop completes the Hunt")
				_check(profile.schematics.size() == int(mark.known) + 1, "the Elite's schematic is banked")
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
			_finish()
	return false


func _start(m: Dictionary, specials: bool) -> void:
	if mission != null:
		mission.queue_free()
	mission = (load("res://scenes/mission.tscn") as PackedScene).instantiate() as Mission
	mission.mission_override = m
	mission.auto_spawn_specials = specials
	root.add_child(mission)
	# Keep the rig alive: these runs test objectives, not survival.
	mission.vehicle.armor_max = 1000000.0
	mission.vehicle.armor = 1000000.0
	frame = 0
	step += 1


func _next() -> void:
	frame = 0
	step += 1


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
	drops.assign(Parts.OUTRIDER_DROPS)
	profile.bank_run(0, drops)
	print("  district score after the four Outrider drops: %d" % profile.district_score())
	_check(profile.district_score() == 8 and not profile.is_district_open(1) and profile.is_district_open(0), "four Uncommons score 8 of Midtown's 40")
	profile.new_game()


func _check_abandon() -> void:
	var day := profile.day
	profile.start_run()
	profile.call("_ready")  # what happens on the next launch
	_check(profile.day == day + 1 and not profile.run_active and profile.notice != "", "quitting mid-run costs the day, nothing else")


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
