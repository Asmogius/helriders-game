extends SceneTree
## Headless smoke test. Boots the main scene, fakes thumb-stick and button
## input, and checks each core mechanic in its own short scenario:
## driving, lock-on, the Hunter (latch, shoot off, crush), the Outrider
## (hunts and shoots you, drops salvage), the Bulwark (charges, rams, armored
## front, drops salvage), a Brute's armor, the Gunner Rig, Scrapper, Convoy Lead and Patcher, power and weight overload, two
## weapons with pellets, fixed guns, the utilities, crew (passives, the crew
## wheel, Hard Line, Overcharge, big-hit injuries, turret aim rule), and the
## wreck.
##
## Run:  godot --headless --fixed-fps 60 --path . -s res://tests/smoke_test.gd
## Exit code 0 = pass, 1 = fail. CI also fails on any "SCRIPT ERROR" output.

const Main := preload("res://scripts/mission.gd")
const Hunter := preload("res://scripts/hunter.gd")
const Vehicle := preload("res://scripts/vehicle.gd")
const Parts := preload("res://scripts/parts.gd")
const Loadout := preload("res://scripts/loadout.gd")
const T := preload("res://scripts/tuning.gd")

const OPEN_SPOT := Vector2(1600, 1200)     # clear ground around the start
const ROAD_WEST := Vector2(400, 720)       # straight run west to the boundary wall
const ROAD_EAST := Vector2(150, 720)       # long clear run east along the same road
# The starter with LOCK: the Advanced Targeting Computer needs the Patched V8's
# power (105 / 125).
const LOCK_BUILD := {
	"chassis": "scrap_frame", "engine": "patched_v8", "drive": "street_wheels", "armor": "scrap_plating",
	"weapons": ["pintle_turret"], "utility": [], "internal": ["advanced_targeting"],
}

var main: Main
var frame := 0
var failures: Array[String] = []
var started_usec := 0
var mark := Vector2.ZERO
var armor_mark := 0.0
var shots_mark := 0
var lock_frames := 0
var enemy_damage := 0.0
var free_run := 0.0


func _initialize() -> void:
	# Same spawns every run, so CI doesn't depend on where the packs land.
	seed(20261102)
	# Fresh in-memory profile: never touch a real save file.
	var profile: Node = root.get_node("Profile")
	profile.set("persist", false)
	profile.call("new_game")
	var known: Array[String] = profile.get("schematics")
	known.append_array(["patched_v8", "advanced_targeting"])
	profile.set("rig", LOCK_BUILD.duplicate(true))
	var scene: PackedScene = load("res://scenes/mission.tscn")
	main = scene.instantiate() as Main
	main.auto_spawn_specials = false  # this test places the Hunter and Outrider
	main.always_drop_schematic = true
	root.add_child(main)


func _process(_delta: float) -> bool:
	frame += 1
	if frame == 30:
		started_usec = Time.get_ticks_usec()
	var rig := main.vehicle

	# --- Parts, slots and power ---------------------------------------------------
	if frame == 5:
		_check_loadouts(rig)

	# --- Driving ----------------------------------------------------------------
	if frame == 10:
		_check(main.zombies.active_count() > 0, "zombies spawned at start")
		rig.rotation = PI / 2.0  # face south, the clearest straight lane
		mark = rig.global_position
		main.hud.left_stick.output = Vector2.DOWN
	if frame == 130:
		var moved := rig.global_position.distance_to(mark)
		free_run = moved
		print("  drove %.0f px, speed %.0f" % [moved, rig.velocity.length()])
		_check(moved > 300.0, "rig drives forward")
		main.hud.left_stick.output = Vector2.RIGHT
	if frame == 190:
		print("  heading after turn %.2f rad" % wrapf(rig.rotation, -PI, PI))
		_check(absf(wrapf(rig.rotation, -PI, PI)) < 0.8, "rig steers toward the stick")

	# --- Lock-on: no aim input at all, lock does the aiming and firing ------------
	if frame == 200:
		main.hud.press_lock()
		_check(rig.lock_enabled, "lock button turns lock on")
		print("  power with lock on %.0f / %.0f, mobility %.2f" % [rig.power_load(), rig.power_output, rig.mobility()])
		_check(is_equal_approx(rig.power_load(), rig.power_draw), "switching lock on costs no extra power")
		_check(not rig.is_overloaded() and rig.mobility() == 1.0, "starter rig runs at full mobility with lock on")
		shots_mark = main.bullets.shots_fired
	if frame > 200 and frame < 1200:
		main.hud.left_stick.output = Vector2.RIGHT.rotated(frame * 0.01) * 0.6
		main.hud.right_stick.output = Vector2.ZERO
		if rig.lock_target != null:
			lock_frames += 1
		rig.armor = rig.armor_max  # this scenario tests lock, not survival
	if frame == 1200:
		var shots := main.bullets.shots_fired - shots_mark
		print("  locked %d frames, %d shots, %d hits, %d kills" % [lock_frames, shots, main.bullets.hits, main.kills])
		_check(lock_frames > 60, "lock acquires targets")
		_check(shots > 20, "lock aims and fires on its own")
		_check(main.kills > 0, "locked fire kills zombies")
		_check(main.zombies.active_count() <= 28, "zombie cap respected")
		main.hud.press_lock()
		_check(not rig.lock_enabled and rig.lock_target == null, "lock button turns lock off")

	# --- Hunter: pounces and latches, then gets shot off --------------------------
	if frame == 1210:
		_reset_rig(OPEN_SPOT, 0.0)
		main.zombies.clear_all()
		main.zombies.spawn_budget = 0
		main.spawn_hunter(OPEN_SPOT + Vector2(260, 0))
	if frame > 1210 and frame < 1330:
		main.hud.left_stick.output = Vector2.ZERO
	if frame == 1300:
		armor_mark = rig.armor
	if frame == 1330:
		print("  hunter state %d, latched list %d" % [main.hunter.state, rig.latched.size()])
		_check(main.hunter.is_latched(), "hunter pounces and latches on")
		_check(rig.armor < armor_mark, "latched hunter chews armor")
		main.hud.press_lock()
	if frame == 1450:
		print("  hunter active %s, cause %s" % [main.hunter.active, main.hunter.last_hit_cause])
		_check(not main.hunter.active and main.hunter.last_hit_cause == "shot", "lock shoots a latched hunter off the hull")
		_check(rig.latched.is_empty(), "hull is clear after the hunter dies")
		main.hud.press_lock()

	# --- Hunter: crushed by driving into a wall -----------------------------------
	if frame == 1460:
		_reset_rig(ROAD_WEST, PI)
		main.hunter.activate(ROAD_WEST)
		main.hunter.force_latch(rig, Vector2(30.0, 0.0))  # on the nose
		main.hud.left_stick.output = Vector2.LEFT
	if frame == 1600:
		print("  hunter active %s, cause %s" % [main.hunter.active, main.hunter.last_hit_cause])
		_check(not main.hunter.active and main.hunter.last_hit_cause == "crushed", "ramming a wall crushes a latched hunter")
		main.hud.left_stick.output = Vector2.ZERO

	# --- Outrider: hunts the parked rig and shoots it, then drops salvage ---------
	if frame == 1610:
		_reset_rig(OPEN_SPOT, 0.0)
		main.spawn_outrider(Vector2(2240, 700))
		mark = Vector2(2240, 700)
		rig.damaged.connect(func(amount: float) -> void: enemy_damage += amount)
	if frame > 1610 and frame < 2200:
		main.hud.left_stick.output = Vector2.ZERO
		rig.armor = rig.armor_max  # parked on purpose; keep it alive to observe
	if frame == 2200:
		var traveled := main.outrider.global_position.distance_to(mark)
		print("  outrider traveled %.0f px, enemy shots %d, damage dealt %.0f" % [traveled, main.bullets.enemy_shots, enemy_damage])
		_check(traveled > 200.0, "outrider drives at the player")
		_check(main.bullets.enemy_shots > 0, "outrider opens fire")
		_check(enemy_damage > 0.0, "outrider hurts the rig")
		main.outrider.take_damage(9999.0)
	if frame == 2205:
		_check(main.outrider.is_wrecked, "outrider can be wrecked")
		_check(main.pickups.get_child_count() == 1, "wrecked outrider drops salvage")
		if main.pickups.get_child_count() > 0:
			rig.global_position = (main.pickups.get_child(0) as Node2D).global_position
	if frame == 2215:
		_check(main.salvage.size() == 1, "driving over a schematic collects it")

	# --- Overload is felt: same straight run as the start, over-budget build ---------
	if frame == 2220:
		# Two Targeting Computers: identical handling, 25 power over budget.
		var greedy := Parts.STARTER_LOADOUT.duplicate(true)
		greedy.internal = ["targeting_computer", "targeting_computer"]
		rig.apply_stats(Loadout.build(greedy))
		_reset_rig(ROAD_EAST, 0.0)
		mark = rig.global_position
		main.hud.left_stick.output = Vector2.RIGHT
	if frame == 2340:
		var moved := rig.global_position.distance_to(mark)
		print("  overloaded build (%.0f / %.0f) ran %.0f px vs %.0f px in budget" % [rig.power_load(), rig.power_output, moved, free_run])
		_check(rig.is_overloaded() and moved < free_run * 0.95, "an over-budget build costs speed")
		main.hud.left_stick.output = Vector2.ZERO

	# --- Weight overload: same run with Riot Plating all round (114 / 100 weight) -
	if frame == 2345:
		var heavy := Parts.STARTER_LOADOUT.duplicate(true)
		for slot: String in ["armor_front", "armor_sides", "armor_rear"]:
			heavy[slot] = "riot_plating"
		heavy.internal = []  # 114 / 100 weight, 75 / 100 power
		main.apply_rig(Loadout.build(heavy))
		_reset_rig(ROAD_EAST, 0.0)
		mark = rig.global_position
		main.hud.left_stick.output = Vector2.RIGHT
	if frame == 2465:
		var moved := rig.global_position.distance_to(mark)
		print("  overweight build (%.0f / %.0f) ran %.0f px vs %.0f px in budget" % [rig.weight_load, rig.weight_capacity, moved, free_run])
		_check(rig.is_weight_overloaded() and not rig.is_power_overloaded() and moved < free_run * 0.97, "an overweight build costs speed")
		main.hud.left_stick.output = Vector2.ZERO

	# --- Bulwark: two turrets fire together, the Scattergun throws pellets --------
	if frame == 2470:
		var bulwark := {
			"chassis": "bulwark_frame", "engine": "diesel_block", "drive": "half_track", "armor": "scrap_plating",
			"weapons": ["pintle_turret", "scattergun_turret"], "utility": [], "internal": ["targeting_computer"],
		}
		main.apply_rig(Loadout.build(bulwark))
		_reset_rig(OPEN_SPOT, 0.0)
		main.zombies.clear_all()
		_check(rig.gun_stats.size() == 2 and rig._turrets.size() == 2 and rig._turrets[0] != null and rig._turrets[1] != null, "Bulwark mounts two turrets")
		_check(rig._turrets[0].position.x > rig._turrets[1].position.x, "one turret forward, one aft")
		shots_mark = main.bullets.shots_fired
		main.hud.right_stick.output = Vector2.UP
	if frame == 2530:
		var shots := main.bullets.shots_fired - shots_mark
		print("  two turrets fired %d bullets in 1 s (Pintle 7/s + Scattergun 2.5/s x 6 pellets)" % shots)
		_check(shots >= 20, "both weapons fire together, the Scattergun in pellets")
		var aim_ok := true
		for t: Node2D in rig._turrets:
			aim_ok = aim_ok and absf(angle_difference(t.global_rotation, -PI / 2.0)) < 0.15
		_check(aim_ok, "both turrets follow the aim stick")
		main.hud.right_stick.output = Vector2.ZERO

	# --- Fixed guns fire for the player too ------------------------------------------
	if frame == 2535:
		var twin := Parts.STARTER_LOADOUT.duplicate(true)
		twin.weapons = ["outrider_twin_guns"]
		main.apply_rig(Loadout.build(twin))
		_reset_rig(OPEN_SPOT, 0.0)
		shots_mark = main.bullets.shots_fired
		main.hud.right_stick.output = Vector2.UP  # any push fires; the guns point ahead
	if frame == 2565:
		var shots := main.bullets.shots_fired - shots_mark
		print("  fixed twin guns fired %d shots in 0.5 s" % shots)
		_check(shots >= 3 and not main.hud.is_lock_button_visible(), "player fires fixed guns with the right stick (no lock on fixed guns)")
		main.hud.right_stick.output = Vector2.ZERO

	# --- Utilities: Emergency Patch and Mine Dropper ----------------------------------
	if frame == 2570:
		var courier := {
			"chassis": "courier_frame", "engine": "junk_v6", "drive": "street_wheels",
			"armor_front": "outrider_light_plating", "armor_sides": "outrider_light_plating", "armor_rear": "outrider_light_plating",
			"weapons": ["pintle_turret"], "utility": ["emergency_patch", "mine_dropper"], "internal": [],
		}
		main.apply_rig(Loadout.build(courier))
		# The Courier seats only a Driver.
		rig.set_crew(main.profile.seated_crew().filter(func(m: Dictionary) -> bool: return m.role == "driver"))
		main.call("_sync_hud_to_rig")
		_reset_rig(OPEN_SPOT, 0.0)
		main.zombies.clear_all()
		_check(main.hud.ability_count() == 2 and main.hud.has_crew_button() and main.hud.crew_wheel_size() == 1, "two utilities: two HUD buttons, plus CREW for the Driver")
		rig.armor = 20.0   # HP 20, every facing stripped
		main.hud.press_ability(0)
		_check(is_equal_approx(rig.armor, 55.0) and is_equal_approx(rig.hp, 20.0), "Emergency Patch restores 35 armor (to a facing, not HP)")
		main.hud.press_ability(0)
		_check(is_equal_approx(rig.armor, 55.0) and rig.ability_charge(0) > 0.9, "the patch has to cool down before it works again")
		main.hud.press_ability(1)
		_check(main.mines.active_count() == 3, "Mine Dropper lays three mines")
		mark = main.mines._pos[1]
		_check(mark.x < rig.global_position.x, "mines go down behind the rig")
	if frame == 2610:
		# Armed after 0.5 s: walk a shambler onto the middle mine.
		var z := main.zombies.spawn_at(mark)
		_check(z != null, "test shambler placed on a mine")
		armor_mark = float(main.kills)
	if frame == 2625:
		print("  mines left %d, detonations %d, kills %d" % [main.mines.active_count(), main.mines.detonations, main.kills])
		_check(main.mines.detonations >= 1 and main.kills > int(armor_mark), "a shambler on an armed mine sets it off and dies")
		_check(rig.armor > 50.0, "your own mines don't hurt you")

	# --- Bulwark: drives at the parked rig, rams, shoots, armored front ----------
	if frame == 2630:
		main.apply_rig(Loadout.build(LOCK_BUILD))
		_reset_rig(OPEN_SPOT, 0.0)
		main.zombies.clear_all()
		if is_instance_valid(main.outrider):
			main.outrider.global_position = OPEN_SPOT + Vector2(0, 900)   # its wreck sat in the charge lane
		main.spawn_bulwark(OPEN_SPOT + Vector2(560, 0))   # 0.5 s wind-up now comes first (proposal 01 §1.2)
		mark = OPEN_SPOT + Vector2(560, 0)
		enemy_damage = 0.0
		shots_mark = main.bullets.enemy_shots
	if frame > 2630 and frame < 2750:
		main.hud.left_stick.output = Vector2.ZERO
		rig.armor = rig.armor_max
	if frame == 2750:
		var bw := main.bulwark
		print("  bulwark traveled %.0f px, rams %d, shots %d, damage dealt %.0f" % [bw.global_position.distance_to(mark), bw.backoffs, main.bullets.enemy_shots - shots_mark, enemy_damage])
		_check(bw.is_inside_tree() and bw.backoffs >= 1, "the Bulwark drives straight at you and rams")
		# Its gun only fires while lining up (proposal 01 §1.2): from 640 px it
		# winds up out of gun range and charges, so mods_test checks the gun.
		_check(enemy_damage > 0.0, "the Bulwark hurts the rig")
		# Defense layers (§14): a very heavy front plate, a thin rear one.
		bw.armor = bw.armor_max
		var forward := Vector2.RIGHT.rotated(bw.rotation)
		bw.take_hit(20.0, -forward * 140.0)   # travelling backwards: hits the nose
		var front_hit := bw.last_facing
		bw.take_hit(20.0, forward * 140.0)    # travelling forwards: hits the tail
		print("  Bulwark front %.0f / %.0f, rear %.0f / %.0f, HP %.0f" % [bw.facing_armor[0], bw.facing_max[0], bw.facing_armor[3], bw.facing_max[3], bw.hp])
		_check(front_hit == Vehicle.FRONT and bw.last_facing == Vehicle.REAR, "hits land on the facing they come from")
		_check(bw.facing_max[0] == 180.0 and bw.facing_max[3] == 50.0 and is_equal_approx(bw.facing_armor[0], 160.0) and is_equal_approx(bw.facing_armor[3], 30.0) and bw.hp == bw.hp_max,
			"the Bulwark's heavy front plate and thin rear both soak hits before HP")
		armor_mark = float(main.pickups.get_child_count())
		# Step away first, so the salvage isn't scooped up on the spot.
		rig.global_position = bw.global_position + Vector2(0, 420)
		bw.take_damage(99999.0)
	if frame == 2755:
		_check(main.bulwark.is_wrecked and main.pickups.get_child_count() == int(armor_mark) + 1, "a wrecked Bulwark drops salvage")
		var pickup: Node = main.pickups.get_child(main.pickups.get_child_count() - 1)
		var part: Dictionary = pickup.get("part")
		_check(Parts.DROP_POOLS.bulwark.has(str(part.get("id", ""))), "its schematic comes from the heavy-parts pool")

	# --- Crew: passives, Hard Line, Overcharge, aim rule, big-hit injuries -------
	if frame == 2770:
		main.apply_rig(Loadout.build(LOCK_BUILD))
		rig.set_crew(main.profile.seated_crew())
		main.call("_sync_hud_to_rig")
		_reset_rig(OPEN_SPOT, 0.0)
		print("  crew: turn x%.2f, grip +%.1f, turret aim x%.2f, spread x%.2f" % [rig.crew_turn, rig.crew_grip, rig.crew_aim, rig.crew_spread])
		_check(rig.crew.size() == 2 and rig.crew_turn > 1.0 and rig.crew_grip > 0.0, "the seated Driver sharpens steering and grip")
		_check(rig.crew_aim > 1.0 and rig.crew_spread < 1.0, "the seated Gunner speeds turret aim and tightens spread")
		_check(main.hud.ability_count() == 0 and main.hud.has_crew_button() and main.hud.is_lock_button_visible(), "the CREW button sits beside LOCK")
		# The crew wheel: slow motion while it's open, pick or close, then a short cooldown.
		_check(main.hud.open_crew_wheel() and main.hud.is_crew_wheel_open() and is_equal_approx(Engine.time_scale, T.CREW_WHEEL_SLOWMO), "opening the crew wheel slows the fight to 25%")
		var turn_before := rig.crew_turn
		_check(main.hud.pick_crew(0) and not main.hud.is_crew_wheel_open() and is_equal_approx(Engine.time_scale, 1.0), "picking a crew ability closes the wheel at full speed")
		_check(rig.hard_line_active() and rig.crew_turn > turn_before and rig.crew_grip >= 3.0, "Hard Line boosts turn and grip")
		_check(not main.hud.open_crew_wheel() and main.hud.crew_wheel_cooldown > 0.0, "the wheel has a short cooldown after it closes")
		main.hud.crew_wheel_cooldown = 0.0
		main.hud.open_crew_wheel()
		_check(not main.hud.pick_crew(0) and main.hud.is_crew_wheel_open(), "a cooling-down crew ability can't be picked")
		main.hud.pick_crew(1)
		_check(rig.overcharge_active() and rig.crew_fire > 1.3 and rig.crew_damage > 1.1, "Overcharge boosts fire rate and damage")
		_check(not rig.use_crew_ability(0), "Hard Line has a cooldown")
		main.hud.crew_wheel_cooldown = 0.0
		main.hud.open_crew_wheel()
		main.hud.close_crew_wheel()
		_check(not main.hud.is_crew_wheel_open() and is_equal_approx(Engine.time_scale, 1.0) and main.hud.crew_wheel_cooldown > 0.0, "closing the wheel without a pick restores speed and still cools down")
		main.hud.crew_wheel_cooldown = 0.0
		# Chip damage isn't a big hit; a burst over 15% of max armor is.
		var hits_before := rig.big_hits
		rig._dmg_buckets.fill(0.0)
		rig.take_damage(rig.armor_max * 0.05)
		_check(rig.big_hits == hits_before, "chip damage never counts as a big hit")
		rig.take_damage(rig.armor_max * 0.12)
		_check(rig.big_hits == hits_before + 1, "a burst over 15% of max armor in a second is a big hit")
		rig.armor = rig.armor_max
	if frame == 2780:
		var aim_before := rig.crew_aim
		rig.injure_crew(1)
		print("  injured Gunner: turret aim x%.2f (was x%.2f)" % [rig.crew_aim, aim_before])
		_check(is_equal_approx(rig.crew_aim, 0.5) and is_equal_approx(rig.crew_spread, 1.0), "an injured Gunner halves turret aim and loses their bonus")
		main.call("_refresh_hud")
		_check(not rig.overcharge_active() and main.hud.is_crew_disabled(1) and not rig.use_crew_ability(1), "an injured Gunner's Overcharge stops and greys out on the wheel")
		rig.injure_crew(0)
		_check(is_equal_approx(rig.crew_turn, 0.5) and is_equal_approx(rig.crew_grip, 0.0), "an injured Driver halves turn rate")
		_check(main.injured_crew_ids().size() == 2, "the run remembers who was hurt")
	if frame == 2785:
		var bare := Parts.STARTER_LOADOUT.duplicate(true)
		main.apply_rig(Loadout.build(bare))
		rig.set_crew(main.profile.seated_crew().filter(func(m: Dictionary) -> bool: return m.role == "driver"))
		_check(not rig.can_aim_turrets(), "no Gunner and no targeting computer: the turret can't aim")
		bare.internal = ["targeting_computer"]
		main.apply_rig(Loadout.build(bare))
		_check(rig.can_aim_turrets() and not rig.can_lock(), "the Targeting Computer aims the turret without a Gunner, but gives no LOCK")
		rig.set_crew(main.profile.seated_crew())
		main.call("_sync_hud_to_rig")

	# --- Zombie variants (full checks in zombie_test.gd) -----------------------------
	if frame == 2787:
		var brute := main.zombies.spawn_at(rig.global_position + Vector2(600, 0), "brute")
		brute.take_hit(20.0, Vector2.ZERO)
		_check(is_equal_approx(brute.hp, 190.0) and brute.deflects(brute.global_position), "a Brute's armor halves bullet damage and throws grey sparks")
		var kills_before := main.kills
		brute.take_hit(500.0, Vector2.ZERO, "rammed")
		_check(not brute.active and main.kills == kills_before + 1, "a ram finishes a Brute and it counts as a kill")
		var gun := main.spawn_gunner(rig.global_position + Vector2(0, 900))
		_check(gun != null and gun.has_weapon() and int(gun.gun_stats[0].burst) == 4, "a Gunner Rig rolls in with a burst-firing turret")
		gun.take_damage(100000.0)
		_check(gun.is_wrecked and main.kills == kills_before + 2, "a wrecked Gunner Rig counts as a kill")
		var scr := main.spawn_scrapper(rig.global_position + Vector2(0, -900))
		_check(scr != null and not scr.has_weapon() and scr.call("drop_trap") == "oil" and main.hazards.oil_count() >= 1, "an unarmed Scrapper lays oil (§14)")
		scr.take_damage(100000.0)
		_check(scr.is_wrecked and main.kills == kills_before + 3, "a wrecked Scrapper counts as a kill")
		var semi := main.spawn_convoy(rig.global_position + Vector2(-900, 0))
		var trailer: Node = semi.get("trailer") if semi != null else null
		_check(trailer != null and main.lock_candidates().has(trailer as Node2D), "a Convoy Lead rolls in towing a lockable trailer")
		semi.take_damage(100000.0)
		_check(semi.is_wrecked and bool(trailer.get("is_wrecked")) and main.kills == kills_before + 4, "wrecking the Convoy Lead's cab takes the trailer too")
		var fixer := main.spawn_patcher(rig.global_position + Vector2(900, 0))
		_check(fixer != null and not fixer.has_weapon() and fixer.has_method("hook"), "an unarmed Patcher rolls in (§14)")
		fixer.take_damage(100000.0)
		_check(fixer.is_wrecked and main.kills == kills_before + 5, "a wrecked Patcher counts as a kill")
		# §14 weapons (full checks in weapons_test.gd).
		_check(main.vehicle.shells == main.shells and main.shells.launch(rig.global_position, rig.global_position + Vector2(400, 0), 0.5, 1.0, 40.0, 0), "the Mortar's shell pool is wired up")
		# Barrels and statuses (full checks in status_test.gd).
		var barrel: Node = main.barrels[0]
		_check(main.barrels.size() == T.BARRELS_PER_JOB and bool(barrel.get("active")), "barrels stand at their spots")
		barrel.call("take_hit", 100.0, Vector2.ZERO)
		_check(not bool(barrel.get("active")), "shooting a barrel sets it off")
		rig.fill_status(1)
		_check(rig.is_status(1), "statuses start on the rig (BURNING)")
		rig.status.reset()

	# --- Wreck -------------------------------------------------------------------
	if frame == 2790:
		rig.take_damage(99999.0)
	if frame == 2800:
		_check(main.state == Main.State.WRECKED, "wreck ends the run")
		_check(Engine.time_scale < 1.0, "the final hit plays in slow motion")
		var dragged := main.get_children().filter(func(n: Node) -> bool: return n is Main.WreckCrew)
		_check(dragged.size() == 1 and (dragged[0].get("names") as Array).size() >= 1, "the crew are dragged from the wreck by name")
		_check(main.zombies.active_zombies().size() >= T.WRECK_SWARM, "the horde closes on the wreck")
		_check(not main.hud.is_result_visible(), "no card yet")
	if frame == 2840:
		var tap := InputEventScreenTouch.new()
		tap.pressed = true
		main._input(tap)
	if frame == 2846:
		_check(main.hud.is_result_visible() and Engine.time_scale == 1.0, "a tap skips to the card")
	if frame == 2930:
		_check(main.hud.is_result_visible(), "results card shown")
		_check(main.hud.result_text().contains("Crew lost"), "results card names the crew lost")
		_check((main.profile.crew as Array).is_empty(), "a wreck kills everyone seated")
		_check(main.hud.result_text().contains("Salvage lost"), "results card reports lost salvage")
		var profile: Node = root.get_node("Profile")
		_check(not profile.call("has_rig"), "the wreck destroyed the rig")
		_check(main.hud.result_text().contains("Wreck penalty"), "results card shows the wreck penalty")
		var cost_ms := (Time.get_ticks_usec() - started_usec) / 1000.0 / (frame - 30)
		print("  avg CPU cost %.2f ms/frame (headless, no rendering, this machine)" % cost_ms)
		_finish()
	return false


func _check_loadouts(rig: Vehicle) -> void:
	var starter := Loadout.build(Parts.STARTER_LOADOUT)
	_check(is_equal_approx(starter.max_speed, 560.0) and is_equal_approx(starter.acceleration, 640.0)
		and float(starter.hp) == 150.0 and float(starter.front) == 80.0 and float(starter.side) == 80.0 and float(starter.rear) == 80.0 and float(starter.shield) == 30.0,
		"starter parts add up: HP 150, Scrap Plating 80 on every facing, a 30 shield")
	_check(float(starter.lock_range) == 0.0 and int(starter.power_draw) == 100 and int(starter.weight) == 95, "the starter (with its Junk Emitter) runs 100 / 100 power, 95 / 100 weight, no LOCK")
	_check(rig.can_lock() and main.hud.is_lock_button_visible(), "the Advanced Targeting Computer gives LOCK")
	print("  lock build power %.0f / %.0f" % [rig.power_draw, rig.power_output])
	_check(rig.power_draw <= rig.power_output, "the lock build fits its power budget")

	var basic := Parts.STARTER_LOADOUT.duplicate(true)
	basic.internal = ["targeting_computer"]
	var basic_stats := Loadout.build(basic)
	_check(float(basic_stats.lock_range) == 0.0 and bool(basic_stats.manual_aim), "the basic Targeting Computer aims turrets but gives no LOCK")

	var no_targeting := LOCK_BUILD.duplicate(true)
	no_targeting.internal = []
	var stats := Loadout.build(no_targeting)
	var bare := Vehicle.new()
	bare.apply_stats(stats)
	bare.lock_enabled = true
	_check(not bare.can_lock() and not bare.lock_enabled, "no Advanced Targeting Computer, no lock")
	var computer: float = Parts.CATALOG.advanced_targeting.power
	_check(computer > 0.0 and is_equal_approx(bare.power_load(), rig.power_draw - computer), "pulling the computer frees its power")
	bare.free()

	var fixed_guns := LOCK_BUILD.duplicate(true)
	fixed_guns.weapons = ["outrider_twin_guns"]
	_check(float(Loadout.build(fixed_guns).lock_range) == 0.0, "fixed guns can't lock even with targeting")

	print("  (one \"no slot\" warning below is expected)")
	var crammed := LOCK_BUILD.duplicate(true)
	crammed.internal = ["targeting_computer", "targeting_computer", "targeting_computer"]
	var crammed_stats := Loadout.build(crammed)
	_check((crammed_stats.dropped as Array).size() == 1, "chassis slot limit is enforced")


func _reset_rig(at: Vector2, facing: float) -> void:
	var rig := main.vehicle
	rig.global_position = at
	rig.rotation = facing
	rig.velocity = Vector2.ZERO
	rig.armor = rig.armor_max
	main.hud.left_stick.output = Vector2.ZERO
	main.hud.right_stick.output = Vector2.ZERO


func _check(ok: bool, what: String) -> void:
	print(("  PASS  " if ok else "  FAIL  ") + what)
	if not ok:
		failures.append(what)


func _finish() -> void:
	if failures.is_empty():
		print("SMOKE TEST PASSED")
		quit(0)
	else:
		print("SMOKE TEST FAILED: %s" % ", ".join(failures))
		quit(1)
