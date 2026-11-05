extends SceneTree
## Headless test for night jobs (approved 2026-11-04, PR #69): the per-job
## night roll by district (and Courier's 50/50), gating (never at 1 skull or
## before the first 3 clears), the roll saved with the job, the zombie-only
## multipliers (rigs unchanged), the surge timing and the night rewards.
##
## Run:  godot --headless --fixed-fps 60 --path . -s res://tests/night_test.gd

const Mission := preload("res://scripts/mission.gd")
const Missions := preload("res://scripts/missions.gd")
const Layouts := preload("res://scripts/layouts.gd")
const Director := preload("res://scripts/zombie_director.gd")
const T := preload("res://scripts/tuning.gd")

var profile: Node
var main: Mission
var frame := 0
var step := 0
var failures: Array[String] = []
var day_rig_damage := 0.0


func _check(ok: bool, what: String) -> void:
	if ok:
		print("  ok  ", what)
	else:
		print("  FAIL ", what)
		failures.append(what)


func _initialize() -> void:
	seed(20261104)
	profile = root.get_node("Profile")
	profile.set("persist", false)
	profile.call("new_game")
	_check_rolls()
	_check_gating()
	_check_saved()
	_check_job_rules()
	_check_fallback()
	_check_surge()
	_check_rewards()
	_start(false)


func _layout_in(district: String, type: String) -> String:
	for id: String in Layouts.LAYOUTS:
		if str(Layouts.LAYOUTS[id].get("district", "")) == district and (Layouts.LAYOUTS[id].jobs as Array).has(type):
			return id
	return ""


func _share(district: String, type: String) -> float:
	var layout := _layout_in(district, type)
	var nights := 0
	var n := 4000
	for i in n:
		var job := Missions.make(type, 3, i * 7919 + 13)
		job["layout"] = layout
		if Missions.roll_night(job, 99):
			nights += 1
	return float(nights) / n


func _check_rolls() -> void:
	var want := {"outer_blocks": 0.10, "midtown": 0.35, "industrial": 0.60, "core": 1.0}
	for d: String in want:
		var type := "clear" if _layout_in(d, "clear") != "" else "survive"
		_check(_layout_in(d, type) != "", "%s has a %s layout" % [d, type])
		var got := _share(d, type)
		_check(absf(got - float(want[d])) < 0.03, "%s night share %.3f ~ %.2f" % [d, got, want[d]])
	for d: String in want:
		if _layout_in(d, "courier") == "":
			continue
		var got := _share(d, "courier")
		var want_c := 1.0 if d == "core" else 0.5   # Core Couriers are always night
		_check(absf(got - want_c) < 0.03, "%s Courier night share %.3f ~ %.2f" % [d, got, want_c])
	_check(T.COL_NIGHT.to_html(false) == "512b11", "night colour is #512b11")


func _check_gating() -> void:
	var core := _layout_in("core", "clear")
	var job := Missions.make("clear", 4, 99)
	job["layout"] = core
	_check(Missions.roll_night(job, 3), "Core 4 skulls after 3 clears: night")
	_check(not Missions.roll_night(job, 2), "no night before the first 3 clears")
	var one := Missions.make("clear", 1, 99)
	one["layout"] = core
	_check(not Missions.roll_night(one, 50), "no night at 1 skull")
	var any_night := false
	for d in 30:
		for j: Dictionary in Missions.make_board(d, 6, 0, "outer_blocks", 0):
			any_night = any_night or Missions.is_night(j)
	_check(not any_night, "a new player's boards (0 clears) have no night jobs")


func _check_saved() -> void:
	var a: Array = Missions.make_board(12, 6, 0, "outer_blocks", 5)
	var b: Array = Missions.make_board(12, 6, 0, "outer_blocks", 5)
	var same := true
	for i in a.size():
		same = same and a[i].has("night") and bool(a[i].night) == bool(b[i].night)
	_check(same, "every board job carries a night flag, the same each time")
	a = a.slice(0, int(profile.call("board_size")))
	profile.set("board", a)
	profile.call("choose_mission", 0)
	var active: Dictionary = profile.get("active_mission")
	_check(active.has("night") and bool(active.night) == bool(a[0].night), "the chosen job keeps its night roll (saved)")
	var round_trip: Dictionary = profile.call("_clean_mission", JSON.parse_string(JSON.stringify({"type": "clear", "skulls": 3, "seed": 5, "reward": 84, "night": true})))
	_check(bool(round_trip.get("night", false)), "a loaded save keeps the night flag")


func _job(type: String, skulls: int, district: String, job_seed := 7) -> Dictionary:
	var job := Missions.make(type, skulls, job_seed)
	job["layout"] = _layout_in(district, type)
	return job


func _chance(type: String, skulls: int, district: String) -> float:
	var job := _job(type, skulls, district)
	if str(job.layout) == "":
		return -1.0   # no layout of this type in the district: skip
	return Missions.night_chance(job)


## #76's rules (approved 2026-11-05) and how they stack with ours.
func _check_job_rules() -> void:
	var cases := [
		["survive", 3, "midtown", 0.60], ["hunt", 5, "midtown", 0.60],
		["survive", 6, "industrial", 0.85], ["hunt", 3, "industrial", 0.85],
		["survive", 5, "core", 1.0], ["hunt", 6, "core", 1.0],
		["survive", 4, "outer_blocks", 1.0], ["hunt", 4, "outer_blocks", 1.0],
		["survive", 3, "outer_blocks", 0.35], ["hunt", 2, "outer_blocks", 0.35],
		["escort", 4, "core", 0.0], ["escort", 4, "industrial", 0.0], ["escort", 5, "midtown", 1.0], ["escort", 6, "industrial", 1.0],
		["courier", 5, "core", 1.0], ["courier", 3, "outer_blocks", 0.5], ["courier", 5, "industrial", 0.5],
		["clear", 3, "midtown", 0.35], ["retrieve", 4, "core", 1.0],
	]
	for c: Array in cases:
		var got := _chance(str(c[0]), int(c[1]), str(c[2]))
		if got < 0.0:
			print("  skip %s %d %s (no layout)" % c.slice(0, 3))
			continue
		_check(is_equal_approx(got, float(c[3])), "%s %d skulls in %s: night chance %.2f (want %.2f)" % [c[0], c[1], c[2], got, c[3]])
	# The gates still win over the sure-night rules.
	var esc := _job("escort", 6, "industrial")
	_check(Missions.roll_night(esc, 3) and not Missions.roll_night(esc, 2), "6-skull Escort is night, but not before 3 clears")
	var ob := _job("survive", 4, "outer_blocks")
	_check(Missions.roll_night(ob, 3), "Outer Blocks 4-skull Survive rolls night")
	var core1 := _job("courier", 1, "core")
	_check(not Missions.roll_night(core1, 50), "a 1-skull Core Courier is still day")
	var tut := _job("clear", 4, "core")
	tut["tutorial"] = true
	_check(not Missions.roll_night(tut, 50), "the tutorial never rolls night")
	tut["night"] = true
	_check(not Missions.is_night(tut), "the tutorial is day even if the flag says night")


## Old saves (no night flag) roll once on load, from the same seed.
func _check_fallback() -> void:
	var raw := _job("clear", 4, "industrial", 4242)
	raw.erase("night")
	var loaded: Dictionary = profile.call("_clean_mission", JSON.parse_string(JSON.stringify(raw)), 5)
	_check(loaded.has("night") and bool(loaded.night) == Missions.roll_night(raw, 5), "an old save's job rolls night on load from its seed")
	var core := _job("clear", 4, "core", 11)
	core.erase("night")
	var c_loaded: Dictionary = profile.call("_clean_mission", JSON.parse_string(JSON.stringify(core)), 5)
	_check(bool(c_loaded.get("night", false)), "an old Core job loads as night")
	var gated: Dictionary = profile.call("_clean_mission", JSON.parse_string(JSON.stringify(core)), 0)
	_check(not bool(gated.get("night", true)), "an old save before 3 clears loads as day")
	core["night"] = false
	var kept: Dictionary = profile.call("_clean_mission", JSON.parse_string(JSON.stringify(core)), 5)
	_check(not bool(kept.night), "a saved night flag wins over the roll")


func _check_surge() -> void:
	var d := Director.new()
	d.apply_night()
	var warned := [0]
	d.surge_warned.connect(func() -> void: warned[0] += 1)
	var dt := 1.0 / 60.0
	var t := 0.0
	var warn_at := -1.0
	var start_at := -1.0
	var end_at := -1.0
	var second_at := -1.0
	var was := false
	while t < 80.0:
		d._tick_surge(dt)
		t += dt
		if warned[0] == 1 and warn_at < 0.0:
			warn_at = t
		var now := d.surge_active()
		if now and not was:
			if start_at < 0.0:
				start_at = t
			elif second_at < 0.0:
				second_at = t
		if was and not now and end_at < 0.0:
			end_at = t
		was = now
	_check(absf(warn_at - (T.NIGHT_SURGE_EVERY - T.NIGHT_SURGE_WARN)) < 0.05, "surge warning at %.2f s" % warn_at)
	_check(absf(start_at - T.NIGHT_SURGE_EVERY) < 0.05, "first surge at %.2f s" % start_at)
	_check(absf(end_at - start_at - T.NIGHT_SURGE_TIME) < 0.05, "surge lasts %.2f s" % (end_at - start_at))
	_check(absf(second_at - start_at - (T.NIGHT_SURGE_EVERY + T.NIGHT_SURGE_TIME)) < 0.05, "next surge %.2f s later" % (second_at - start_at))
	_check(d.surge_count == 2 and warned[0] == 2, "two surges, two warnings in 80 s")
	var day := Director.new()
	day._tick_surge(40.0)
	_check(not day.surge_active(), "no surge by day")
	d.free()
	day.free()


func _check_rewards() -> void:
	var job := Missions.make("clear", 4, 7)
	_check(Missions.night_pay(100, job) == 100, "day pay unchanged")
	job["night"] = true
	_check(Missions.night_pay(100, job) == 130, "night pay x1.3")
	_check(Missions.night_pay(130, job) == 169, "night pay stacks on top of the job's pay")
	_check(Missions.night_kill_scrap(2, true) == 3 and Missions.night_kill_scrap(6, true) == 8 and Missions.night_kill_scrap(10, true) == 13, "kill scrap x1.25 rounded up (2->3, 6->8, 10->13)")
	_check(Missions.night_kill_scrap(2, false) == 2, "day kill scrap unchanged")
	var base := float(T.MISSION_SCHEMATIC_CHANCE[3])
	_check(is_equal_approx(Missions.schematic_chance(job), base + 0.10), "night schematic chance +0.10")
	var top := Missions.make("clear", 6, 7)
	top["night"] = true
	_check(Missions.schematic_chance(top) == 1.0, "schematic chance capped at 1.0")
	_check(is_equal_approx(Missions.night_xp(4.0, true), 5.0), "night XP x1.25")
	var riders: Array = profile.call("seated_crew")
	if not riders.is_empty():
		var before := float(riders[0].xp)
		profile.call("bank_crew", 4, [], false, false, T.NIGHT_XP_MULT)
		_check(is_equal_approx(float(riders[0].xp) - before, 5.0 / riders.size()), "bank_crew pays night XP x1.25")


func _start(at_night: bool) -> void:
	if main != null:
		main.free()
	main = (load("res://scenes/mission.tscn") as PackedScene).instantiate() as Mission
	var spec := Missions.make("clear", 4, 31)
	spec["night"] = at_night
	main.mission_override = spec
	main.push_override = 0
	main.auto_spawn_specials = false
	root.add_child(main)
	frame = 0


func _process(_delta: float) -> bool:
	frame += 1
	if frame < 3:
		return false
	var z := main.zombies
	var dmg := float(T.ENEMY_DAMAGE_BY_SKULL[3])
	match step:
		0:
			_check(not main.night and not z.night and is_equal_approx(z.damage_mult, dmg), "day job: no night multipliers")
			day_rig_damage = main.outrider.bullet_damage
			_start(true)
			step = 1
		1:
			_check(main.night and z.night, "night job runs at night")
			_check(is_equal_approx(z.damage_mult, dmg * T.NIGHT_ZOMBIE_DPS_MULT), "zombie damage x NIGHT_ZOMBIE_DPS_MULT on top of skulls")
			_check(z.start_count == mini(T.ZOMBIE_START, z.cap) + T.NIGHT_ZOMBIE_START_BONUS, "start count +4")
			_check(is_equal_approx(z.ramp_seconds, T.NIGHT_RAMP_SECONDS), "ramp every 3 s")
			_check(z.horde_size == T.NIGHT_HORDE_SIZE and z.tank_earliest == T.NIGHT_TANK_EARLIEST and z.tank_pack_chance == T.NIGHT_TANK_PACK_CHANCE, "night packs and Tanks")
			_check(z.bile_mark_range == T.NIGHT_BILE_MARK_RANGE, "bile draws from 650")
			_check(z.cap <= T.ZOMBIE_CAP, "cap unchanged at night")
			var zed := z.spawn_at(main.vehicle.global_position + Vector2(400, 0))
			_check(zed != null and zed.speed >= T.SHAMBLER_SPEED * 0.8 * T.NIGHT_ZOMBIE_SPEED_MULT - 0.01 and zed.speed <= T.SHAMBLER_SPEED * 1.2 * T.NIGHT_ZOMBIE_SPEED_MULT + 0.01, "shambler speed x NIGHT_ZOMBIE_SPEED_MULT")
			_check(is_equal_approx(zed.hp, T.SHAMBLER_HP), "shambler HP unchanged")
			var h: Variant = main.hunters[0]
			_check(is_equal_approx(h.night_speed, T.NIGHT_HUNTER_SPEED_MULT) and is_equal_approx(h.damage_mult, dmg * T.NIGHT_ZOMBIE_DPS_MULT), "Hunter speed x1.1, damage x NIGHT_ZOMBIE_DPS_MULT")
			_check(is_equal_approx(main.outrider.bullet_damage, day_rig_damage), "enemy rigs unchanged at night")
			var hunter_event := false
			for e: Array in main._events:
				hunter_event = hunter_event or (str(e[1]) == "hunter" and is_equal_approx(float(e[0]), T.NIGHT_HUNTER_SPAWN_TIME))
			_check(hunter_event, "Hunter due at 15 s at night")
			main.free()
			main = null
			if failures.is_empty():
				print("NIGHT TEST PASSED")
				quit(0)
			else:
				print("NIGHT TEST FAILED: ", failures)
				quit(1)
			return true
	return false
