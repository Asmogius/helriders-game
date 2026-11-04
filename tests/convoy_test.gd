extends SceneTree
## Headless test for the Convoy Lead: its numbers and new parts, the seeded
## per-job roll and the Comms card, a job that brings one (taking an
## Outrider's place), then a live semi: the trailer hitched behind and
## swinging on turns, the trailer turret held back when the cab is in the way
## while the nose guns fire, the half-damage ram, shooting the trailer off
## (crate, lighter cab), and wrecking the cab (payout, pool, trailer goes too).
##
## Run:  godot --headless --fixed-fps 60 --path . -s res://tests/convoy_test.gd

const Mission := preload("res://scripts/mission.gd")
const Missions := preload("res://scripts/missions.gd")
const ConvoyRig := preload("res://scripts/convoy_rig.gd")
const Parts := preload("res://scripts/parts.gd")
const T := preload("res://scripts/tuning.gd")

const SPOT := Vector2(1600, 1200)

var main: Mission
var frame := 0
var step := 0
var failures: Array[String] = []
var c: ConvoyRig
var mark := {}


func _initialize() -> void:
	seed(20261106)
	var profile: Node = root.get_node("Profile")
	profile.set("persist", false)
	profile.call("new_game")
	_check_tables()
	# A 4-skull Clear that rolls a Convoy Lead.
	var spec := Missions.make("clear", 4, _convoy_seed("clear", 4))
	main = (load("res://scenes/mission.tscn") as PackedScene).instantiate() as Mission
	main.mission_override = spec
	main.auto_spawn_specials = false
	main.always_drop_schematic = true
	root.add_child(main)


func _process(_delta: float) -> bool:
	frame += 1
	var rig := main.vehicle
	match step:
		0:
			if frame == 3:
				var kinds: Array = main._events.map(func(e: Array) -> String: return str(e[1]))
				_check(kinds.has("convoy") and not kinds.has("outrider"), "a convoy job sends the Convoy Lead in the Outrider's place")
				main.zombies.spawn_budget = 0
				main.zombies.clear_all()
				rig.armor_max = 100000.0
				rig.armor = rig.armor_max
				_park(SPOT)
				c = main.spawn_convoy(SPOT + Vector2(-700, 0)) as ConvoyRig
				_check(c != null and c == main.convoy and main.active_rig_count() == 1, "spawn_convoy: cab and trailer count as one rig")
				_check(main.lock_candidates().has(c.trailer), "the trailer can be locked on its own")
			if frame == 6:
				_check(_hitch_ok(), "the trailer rolls in hitched behind the cab")
			if frame == 150:
				_check(_hitch_ok(), "it stays on the hitch while the semi drives")
				mark.swing = 0.0
			if frame > 150 and frame < 330:
				mark.swing = maxf(float(mark.swing), absf(angle_difference(c.rotation, c.trailer.rotation)))
			if frame == 330:
				_check(float(mark.swing) > 0.15, "the trailer swings wide on turns (%.0f deg)" % rad_to_deg(float(mark.swing)))
				_check(float(mark.swing) <= T.CONVOY_MAX_JACKKNIFE + 0.01, "...but never folds past %d deg" % roundi(rad_to_deg(T.CONVOY_MAX_JACKKNIFE)))
				_next()
		1:  # Who shoots when you're dead ahead
			if frame == 1:
				c.velocity = Vector2.ZERO
				c.global_position = SPOT + Vector2(-380, 0)
				c.rotation = 0.0
				c.trailer.hitch_up()
				_park(SPOT)
				mark.shots = main.bullets.enemy_shots
			if frame == 20:
				_check(c.trailer.blocked, "you're ahead of the cab: the trailer turret holds fire")
				_check(main.bullets.enemy_shots > int(mark.shots), "the nose guns cover the front")
				# Now come at it from behind.
				c.velocity = Vector2.ZERO
				c.global_position = SPOT + Vector2(500, 0)
				c.rotation = 0.0
				c.trailer.hitch_up()
				_park(SPOT)
			if frame == 24:
				_check(not c.trailer.blocked, "from behind, the trailer turret has a clear shot")
				# The ram takes half.
				var hp := c.hp
				c.take_hit(40.0, Vector2.LEFT * 10.0)   # travelling left: hit from in front
				_check(c.last_facing == c.FRONT and c.facing_max[0] == 250.0 and c.hp == hp, "the plow is a very heavy front plate (250); a nose hit never reaches HP")
				_next()
		2:  # Shoot the trailer off
			if frame == 1:
				mark.speed = c.max_speed
				mark.kills = main.kills
				mark.pickups = main.pickups.get_child_count()
				c.trailer.take_damage(100000.0)
			if frame == 3:
				_check(c.trailer.is_wrecked and not c.is_wrecked and c.unhitched, "the trailer can be shot off on its own")
				_check(is_equal_approx(c.max_speed, float(mark.speed) * T.CONVOY_UNHITCHED_SPEED), "the cab drives on lighter and faster")
				_check(main.pickups.get_child_count() == int(mark.pickups) + 1 and int(main.pickups.get_child(main.pickups.get_child_count() - 1).get("scrap_value")) == roundi(T.CONVOY_TRAILER_CRATE * float(rig.crew_mod("cache"))),
					"the trailer drops a %d-scrap crate" % T.CONVOY_TRAILER_CRATE)
				_check(main.kills == int(mark.kills), "the trailer isn't a kill on its own")
				_check(not main.lock_candidates().has(c.trailer), "a dropped trailer leaves the lock list")
				mark.at = c.trailer.global_position
			if frame == 60:
				_check(c.trailer.global_position.distance_to(mark.at) < 5.0, "the dropped trailer stays where it fell")
				_next()
		3:  # Wreck the cab of a fresh semi
			if frame == 1:
				var fresh := ConvoyRig.new()
				fresh.player = rig
				fresh.bullets = main.bullets
				fresh.fx = main.fx
				main.convoys.append(fresh)
				fresh.wrecked.connect(main._on_convoy_wrecked.bind(fresh))
				fresh.trailer.wrecked.connect(main._on_trailer_lost.bind(fresh))
				c.take_damage(100000.0)
				c = main.spawn_convoy(SPOT + Vector2(0, 600)) as ConvoyRig
				_check(c == fresh, "a second Convoy Lead rolls in")
			if frame == 4:
				mark.scrap = main.scrap
				mark.kills = main.kills
				mark.pickups = main.pickups.get_child_count()
				c.take_damage(100000.0)
			if frame == 6:
				_check(c.is_wrecked and c.trailer.is_wrecked, "wreck the cab and the trailer goes with it")
				_check(main.kills == int(mark.kills) + 1, "one kill for the whole rig")
				var mult := main.profile.salvage_mult() * float(rig.crew_mod("scrap")) * float(rig.crew_mod("rig_scrap"))
				_check(is_equal_approx(main.scrap - float(mark.scrap), T.CONVOY_SCRAP * mult), "it pays %d scrap" % T.CONVOY_SCRAP)
				_check(main.pickups.get_child_count() == int(mark.pickups) + 1, "one drop, no extra trailer crate")
				var part: Dictionary = main.pickups.get_child(main.pickups.get_child_count() - 1).get("part")
				_check(Parts.DROP_POOLS.convoy.has(str(part.get("id", ""))), "it drops from its pool (%s)" % str(part.get("name", "")))
				_finish()
	return false


func _hitch_ok() -> bool:
	var hitch := c.global_position - Vector2.RIGHT.rotated(c.rotation) * (c.body_len * 0.5)
	var d := c.trailer.global_position.distance_to(hitch)
	return absf(d - (c.trailer.body_len * 0.5 + T.CONVOY_HITCH_GAP)) < 2.0


func _convoy_seed(type: String, skulls: int) -> int:
	for s in range(1, 500):
		if Missions.has_convoy(Missions.make(type, skulls, s)):
			return s
	return 1


func _check_tables() -> void:
	var cow := Parts.get_part("cowcatcher_ram")
	_check(cow.rarity == "Rare" and float(cow.armor) == 124.0 and float(cow.ram_damage) == 170.0 and float(cow.weight) == 22.0 and bool(cow.front_only) and int(cow.cost) == 180,
		"Cowcatcher Ram: Rare, front only, 124 armor, ram 170, weight 22, 180 scrap")
	var hood := Parts.get_part("hood_guns")
	_check(hood.rarity == "Rare" and int(hood.mount) == 1 and absf(float(hood.fire_rate) * float(hood.bullet_damage) - 56.0) < 0.1 and float(hood.power) == 40.0 and float(hood.weight) == 20.0 and int(hood.cost) == 170,
		"Hood Guns: Rare fixed, ~56 DPS, 40 power, 20 weight, 170 scrap")
	_check(Parts.DROP_POOLS.convoy.has("cowcatcher_ram") and Parts.DROP_POOLS.convoy.has("hood_guns") and Parts.DROP_POOLS.convoy.has("heavy_mg_turret"), "its pool: Rare parts plus both new ones")
	_check(float(T.CONVOY.armor) == 650.0 and float(T.CONVOY_TRAILER.armor) == 350.0 and float(T.CONVOY.ram_damage) == 120.0, "cab 650, trailer 350 in total, ram 120")
	_check(absf(float(T.CONVOY_TRAILER.fire_rate) * float(T.CONVOY_TRAILER.bullet_damage) - 30.0) < 0.1 and absf(float(T.CONVOY.fire_rate) * float(T.CONVOY.bullet_damage) - 32.0) < 0.1,
		"turret ~30 damage/s, nose guns ~32")
	var spec := Missions.make("clear", 4, 77)
	_check(Missions.has_convoy(spec) == Missions.has_convoy(spec), "the roll is the same every time for a job")
	var rolls := {}
	for key: String in ["clear3", "clear4", "clear6", "hunt4", "hunt5", "courier6", "survive4"]:
		var type := key.rstrip("0123456789")
		var k := int(key.substr(type.length()))
		var n := 0
		for s in 1000:
			if Missions.has_convoy(Missions.make(type, k, s)):
				n += 1
		rolls[key] = n / 1000.0
	_check(float(rolls.clear3) == 0.0 and absf(float(rolls.clear4) - 0.35) < 0.05 and absf(float(rolls.clear6) - 0.5) < 0.05,
		"Clear: none below 4 skulls, ~35%% at 4, ~50%% at 6 (%.2f, %.2f)" % [float(rolls.clear4), float(rolls.clear6)])
	_check(absf(float(rolls.survive4) - 0.35) < 0.05, "Survive: ~35% at 4 skulls")
	_check(float(rolls.hunt4) == 0.0 and absf(float(rolls.hunt5) - 0.35) < 0.05, "Hunt: escorts the Elite from 5 skulls")
	_check(float(rolls.courier6) == 0.0, "Courier: never")
	var with := Missions.make("clear", 5, _convoy_seed("clear", 5))
	var text := Missions.threats_text(with)
	_check(text.contains("1 Convoy Lead") and text.contains("1 Outrider,"), "Comms card: '1 Convoy Lead', one Outrider fewer (%s)" % text)


func _park(at: Vector2) -> void:
	var rig := main.vehicle
	rig.global_position = at
	rig.velocity = Vector2.ZERO
	rig.rotation = PI / 2.0
	main.hud.left_stick.output = Vector2.ZERO
	main.hud.right_stick.output = Vector2.ZERO


func _next() -> void:
	frame = 0
	step += 1


func _check(ok: bool, what: String) -> void:
	print(("  PASS  " if ok else "  FAIL  ") + what)
	if not ok:
		failures.append(what)


func _finish() -> void:
	if failures.is_empty():
		print("CONVOY TEST PASSED")
		quit(0)
	else:
		print("CONVOY TEST FAILED: %s" % ", ".join(failures))
		quit(1)
