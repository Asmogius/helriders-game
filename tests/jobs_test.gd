extends SceneTree
## Headless test for the Retrieve and Escort jobs: tables, pools and Comms
## text; Retrieve's caches, deep cache (guarded, schematic), extraction rules,
## danger climbing with caches and time (bigger, faster horde, rigs called
## in) and pay; Escort's truck driving to its sites, zombies and rigs going
## for it, the paused driver call about the risky site, the risky site's wave
## and its +60% pay and sure schematic, and the job failing when the truck is
## wrecked.
##
## Run:  godot --headless --fixed-fps 60 --path . -s res://tests/jobs_test.gd

const Mission := preload("res://scripts/mission.gd")
const Missions := preload("res://scripts/missions.gd")
const Parts := preload("res://scripts/parts.gd")
const T := preload("res://scripts/tuning.gd")
const Arena := preload("res://scripts/arena.gd")

var profile: Node
var main: Mission
var frame := 0
var step := 0
var failures: Array[String] = []
var mark := {}


func _initialize() -> void:
	seed(20261107)
	profile = root.get_node("Profile")
	profile.set("persist", false)
	profile.call("new_game")
	_check_tables()
	_start(Missions.make("retrieve", 3, 21))


func _start(spec: Dictionary) -> void:
	if main != null:
		main.queue_free()
	main = (load("res://scenes/mission.tscn") as PackedScene).instantiate() as Mission
	main.mission_override = spec
	main.push_override = 0   # push_test covers Extract or Push
	root.add_child(main)
	frame = 0


func _process(_delta: float) -> bool:
	frame += 1
	var rig := main.vehicle if main != null else null
	if frame == 2 and rig != null:
		rig.armor_max = 100000.0   # these runs test the jobs, not survival
		rig.armor = rig.armor_max
	match step:
		0:  # Retrieve
			if frame == 3:
				_check(main.caches.size() == 4 and main.deep_cache >= 0, "Retrieve 3 skulls: 4 caches, one deep")
				var far := true
				for c in main.caches:
					far = far and c.distance_to(main.extract_at) <= main.caches[main.deep_cache].distance_to(main.extract_at)
				_check(far, "the deep cache is the farthest from extraction")
				_check(not main.extract_armed, "you start inside extraction; it doesn't count yet")
				main.zombies.clear_all()
			if frame == 90:
				var guard: Node = main.gunner
				_check(guard.is_inside_tree() and bool(guard.call("is_guarding")) and guard.get("guard_point") == main.caches[main.deep_cache], "a Gunner Rig guards the deep cache")
				# Drive out, then back in with nothing: no extraction.
				rig.global_position = main.extract_at + Vector2(0, -500)
			if frame == 92:
				_check(main.extract_armed, "leaving the zone arms extraction")
				rig.global_position = main.extract_at
			if frame == 94:
				_check(main.state == Mission.State.RUNNING, "no caches: extraction waits")
				# Grab the first plain cache.
				mark.base_cap = main.zombies.cap
				var plain := 0 if main.deep_cache != 0 else 1
				mark.plain = plain
				rig.global_position = main.caches[plain]
			if frame == 96:
				_check(main.cache_taken[int(mark.plain)] and main.caches_grabbed() == 1, "drive over a cache to grab it")
				_check(main.danger >= 1 and main.zombies.cap == int(mark.base_cap) + T.RETRIEVE_CAP_STEP, "each cache raises the danger: a bigger crowd")
				_check(main.zombies.speed_bonus > 1.0, "...and a faster one")
				# Time raises it too.
				mark.danger = main.danger
				main.elapsed += T.RETRIEVE_STEP_SECONDS
			if frame == 98:
				_check(main.danger == int(mark.danger) + 1, "every %d s raises it a step too" % int(T.RETRIEVE_STEP_SECONDS))
				var calls: Array = main._events.filter(func(e: Array) -> bool: return str(e[1]) == "scrapper")
				_check(not calls.is_empty(), "danger 2 calls in a rig (a Scrapper)")
				# The deep cache.
				mark.salvage = main.salvage.size()
				rig.global_position = main.caches[main.deep_cache]
			if frame == 100:
				_check(main.cache_taken[main.deep_cache] and main.salvage.size() == int(mark.salvage) + 1, "the deep cache carries a schematic")
				var expect := T.RETRIEVE_BASE_SHARE + (1.0 - T.RETRIEVE_BASE_SHARE) * (1.0 + T.RETRIEVE_DEEP_MULT) / (3.0 + T.RETRIEVE_DEEP_MULT)
				_check(is_equal_approx(main.retrieve_pay_mult(), expect), "pay share: 30%% + the rest by caches, deep counts double (%.2f)" % expect)
				mark.scrap = profile.get("scrap")
				mark.day = profile.get("day")
				rig.global_position = main.extract_at + Vector2(0, -500)
			if frame == 102:
				rig.global_position = main.extract_at
			if frame == 104:
				_check(main.state == Mission.State.CLEARED and main.hud.result_text().begins_with("EXTRACTED"), "drive into extraction with caches: job done")
				var pay := roundi(float(main.spec.reward) * main.retrieve_pay_mult())
				_check(main.hud.result_text().contains("Job pay +%d" % pay), "it pays reward x share (+%d)" % pay)
				_check(int(profile.get("day")) == int(mark.day) + 1, "the day ends")
				_start(Missions.make("escort", 2, 33))
				step = 1
		1:  # Escort
			if frame == 3:
				var truck := main.truck
				_check(truck != null and truck.sites.size() == 2 and main.optional_site != Vector2.INF, "Escort 2 skulls: a truck, 2 sites and a risky extra")
				_check(main.zombies.alt_target == truck, "zombies go for the truck too")
				_check(main.outrider.player == truck and main.scrapper.player == truck, "enemy rigs go for the truck")
				mark.d0 = truck.global_position.distance_to(truck.sites[0])
				var before := truck.armor
				truck.receive_ram(80.0)
				_check(truck.armor == before, "bumping the truck doesn't hurt it")
				main.zombies.clear_all()
				main.zombies.spawn_budget = 0
			if frame == 180:
				var truck := main.truck
				_check(truck.global_position.distance_to(truck.sites[0]) < float(mark.d0) - 150.0, "the truck drives to its first site")
				var z := main.zombies.spawn_at(truck.global_position + Vector2(0, 260), "shambler")
				z.set("speed", 80.0)
				mark.z = z
				mark.zd = z.global_position.distance_to(truck.global_position)
				rig.global_position = truck.global_position + Vector2(1200, 0)
			if frame == 240:
				var z: Node2D = mark.z
				_check(z.global_position.distance_to(main.truck.global_position) < float(mark.zd) - 30.0, "a zombie near the truck goes for it, not you")
				main.zombies.clear_all()
				main.truck.global_position = main.truck.sites[0]
				main.truck.velocity = Vector2.ZERO
			if frame == 244:
				_check(main.truck.working, "on site it gets to work")
				main.truck.work_left = 0.05
			if frame == 250:
				_check(main.hud.is_choice_open() and paused, "after the first site the driver radios; the game pauses")
				mark.elapsed = main.elapsed
			if frame == 260:
				_check(main.elapsed == float(mark.elapsed), "...and stays paused while you choose")
				main.hud.pick_choice(true)
			if frame == 262:
				_check(not paused and main.optional_taken and main.truck.sites[main.truck.site_index] == main.optional_site, "TAKE THE RISK: the risky site is next")
				mark.alive = main.zombies.active_count()
				main.truck.global_position = main.optional_site
				main.truck.velocity = Vector2.ZERO
			if frame == 266:
				_check(main.truck.working and is_equal_approx(main.truck.site_times[main.truck.site_index], T.ESCORT_OPTIONAL_TIME), "the risky site takes %d s" % int(T.ESCORT_OPTIONAL_TIME))
				_check(main.zombies.active_count() >= int(mark.alive) + T.ESCORT_OPTIONAL_WAVE - 2, "...and wakes a big wave")
				_check(main._events.any(func(e: Array) -> bool: return str(e[1]) == "outrider" and float(e[0]) > 1.0), "...and calls in a rig")
				main.zombies.clear_all()
				main.truck.work_left = 0.05
			if frame == 272:
				main.truck.global_position = main.truck.sites[main.truck.site_index]
				main.truck.velocity = Vector2.ZERO
				mark.known = (profile.get("schematics") as Array).size()
			if frame == 276:
				main.truck.work_left = 0.05
			if frame == 282:
				_check(main.state == Mission.State.CLEARED and main.hud.result_text().begins_with("SALVAGE RUN DONE"), "every site worked: job done")
				var pay := roundi(float(main.spec.reward) * T.ESCORT_OPTIONAL_PAY)
				_check(main.hud.result_text().contains("Job pay +%d" % pay), "the risky site pays +60%% (+%d)" % pay)
				_check((profile.get("schematics") as Array).size() > int(mark.known), "...and a sure schematic")
				_start(Missions.make("escort", 1, 34))
				step = 2
		2:  # Escort: the truck is wrecked
			if frame == 3:
				mark.scrap = profile.get("scrap")
				mark.day = profile.get("day")
				mark.clears = int((profile.get("record") as Dictionary).clears)
				main.scrap = 10.0
				main.drop_cache(main.vehicle.global_position + Vector2(0, 900), 50)   # left on the ground
				main.truck.take_damage(100000.0)
			if frame == 5:
				_check(main.state == Mission.State.FAILED and main.hud.result_text().begins_with("TRUCK LOST"), "truck wrecked: the job fails")
				_check(int(profile.get("day")) == int(mark.day) + 1 and int(profile.get("scrap")) == int(mark.scrap) + 10, "the day passes; no job pay, you keep your kill scrap")
				_check(profile.call("has_rig"), "your rig and crew come home (no wreck)")
				_check(int((profile.get("record") as Dictionary).clears) == int(mark.clears), "a failed job isn't a clear (Expeditions unlock on clears)")
				_check(int(profile.get("scrap")) == int(mark.scrap) + 10, "a crate left on the ground stays there")
				_finish()
	return false


func _check_tables() -> void:
	var t1 := Mission.truck_sheet(1)
	var t6 := Mission.truck_sheet(6)
	_check(is_equal_approx(float(t6.hp), float(T.TRUCK.hp) * float(T.ENEMY_DAMAGE_BY_SKULL[5])) and float(t1.front) < float(T.TRUCK.front), "the truck's armor and HP scale with enemy damage by skull (%.0f at 1, %.0f at 6)" % [float(t1.armor), float(t6.armor)])
	_check(Missions.TYPES.has("retrieve") and Missions.TYPES.has("escort"), "both jobs are on the Comms board's list")
	_check(Parts.DROP_POOLS.retrieve == ["turbo_four", "off_road_tires", "oil_slick", "mine_dropper", "raider_frame"], "Retrieve pool: Turbo Four, Off-Road Tires, Oil Slick, Mine Dropper, Raider Frame (proposal 01)")
	_check(Parts.DROP_POOLS.escort == ["structural_bracing", "riot_plating", "emergency_patch", "burst_turret"], "Escort pool: Bracing, Riot Plating, Emergency Patch, Burst Turret")
	var clear: Array = T.MISSIONS.clear.reward
	var ret: Array = T.MISSIONS.retrieve.reward
	var ok := true
	for i in 6:
		ok = ok and absf(float(ret[i]) / float(clear[i]) - 1.3) < 0.02
	_check(ok, "Retrieve with every cache pays ~1.3x a Clear")
	_check(T.MISSIONS.escort.reward == T.MISSIONS.survive.reward, "Escort pays like Survive")
	_check(T.MISSIONS.retrieve.caches == [3, 3, 4, 4, 5, 5] and T.MISSIONS.escort.sites == [2, 2, 3, 3, 3, 3], "caches 3/3/4/4/5/5, sites 2/2/3/3/3/3")
	_check(float(T.TRUCK.armor) == 400.0 and float(T.TRUCK.max_speed) == 230.0, "the truck: 400 armor, speed 230")
	_check(Missions.threats_text(Missions.make("retrieve", 4, 5)).contains("4 caches (1 deep"), "Comms: Retrieve lists its caches")
	_check(Missions.threats_text(Missions.make("escort", 5, 5)).contains("3 salvage sites"), "Comms: Escort lists its sites")
	var board := Missions.make_board(1, 6, 0, "outer_blocks", 99)   # every type unlocked
	var types := {}
	for m: Dictionary in board:
		types[str(m.type)] = true
	_check(types.size() == 6, "a six-job board shows every type once")


func _check(ok: bool, what: String) -> void:
	print(("  PASS  " if ok else "  FAIL  ") + what)
	if not ok:
		failures.append(what)


func _finish() -> void:
	if failures.is_empty():
		print("JOBS TEST PASSED")
		quit(0)
	else:
		print("JOBS TEST FAILED: %s" % ", ".join(failures))
		quit(1)
