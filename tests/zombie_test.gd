extends SceneTree
## Headless test for the zombie variants: the mix by skulls and the Comms
## text, then each kind live in a mission with the regular horde cleared away:
## Brute (armor, shove, scrap), Tank (roar, charge, shove, stumble after a
## miss, cache crate), Boomer (bile pool, marked rig, frenzy, bursting on
## contact), Slimer (trail, death puddle, rig grip) and the hazard pool cap.
##
## Run:  godot --headless --fixed-fps 60 --path . -s res://tests/zombie_test.gd

const Mission := preload("res://scripts/mission.gd")
const Missions := preload("res://scripts/missions.gd")
const ZombieDirector := preload("res://scripts/zombie_director.gd")
# No `const Zombie := preload(...)` here: a test-level reference to zombie.gd next
# to mission.gd keeps both scripts alive past exit (5 resources still in use).
# Reach it through the director instead.
const T := preload("res://scripts/tuning.gd")

const SPOT := Vector2(1600, 1200)     # the player start: open ground

var main: Mission
var frame := 0
var step := 0
var failures: Array[String] = []
var z: Node2D   # a zombie.gd instance
var mark := {}


func _initialize() -> void:
	seed(20261103)
	var profile: Node = root.get_node("Profile")
	profile.set("persist", false)
	profile.call("new_game")
	main = (load("res://scenes/mission.tscn") as PackedScene).instantiate() as Mission
	main.mission_override = Missions.make("clear", 1, 7)
	main.auto_spawn_specials = false
	root.add_child(main)


func _process(_delta: float) -> bool:
	if main == null:
		return false   # finished: tearing down
	frame += 1
	var rig := main.vehicle
	match step:
		0:
			if frame == 3:
				_check_tables()
				main.zombies.spawn_budget = 0
				main.zombies.clear_all()
				rig.armor_max = 100000.0
				rig.armor = rig.armor_max
				_park(SPOT)
				_next()
		1:  # Brute: armor, shove, scrap
			if frame == 1:
				z = main.zombies.spawn_at(SPOT + Vector2(600, 0), "brute")
				z.take_hit(40.0, Vector2.ZERO)
				_check(is_equal_approx(z.hp, 180.0), "Brute: bullets do half (40 -> 20)")
				z.take_hit(40.0, Vector2.ZERO, "rammed")
				_check(is_equal_approx(z.hp, 140.0), "Brute: rams do full damage")
				_check(z.deflects(z.global_position) and z.is_armored(), "Brute: grey sparks")
				z.global_position = SPOT + Vector2(60, 0)
				mark.pos = rig.global_position
			if frame == 60:
				_check(rig.global_position.distance_to(mark.pos) > 5.0, "Brute: leaning on the rig shoves it (%.0f px)" % rig.global_position.distance_to(mark.pos))
				mark.scrap = main.scrap
				z.take_hit(1000.0, Vector2.ZERO, "rammed")
				_check(is_equal_approx(main.scrap - float(mark.scrap), 6.0 * _scrap_mult()), "Brute pays 6 scrap")
				_park(SPOT)
				_next()
		2:  # Tank: roar, charge, hit
			if frame == 1:
				z = main.zombies.spawn_at(SPOT + Vector2(260, 0), "tank")
				z.charge_cooldown = 0.0
				mark.armor = rig.armor
				mark.pos = rig.global_position
			if frame == 5:
				_check(z.is_charging() and z.charge == ZombieDirector.Zombie.Charge.WINDUP, "Tank: roars before it charges")
			if frame == 120:
				_check(z.charge_hits == 1, "Tank: the charge lands")
				_check(mark.armor - rig.armor >= T.TANK_CHARGE_DAMAGE, "Tank: a charge hit deals %d" % int(T.TANK_CHARGE_DAMAGE))
				_check(rig.global_position.distance_to(mark.pos) > 40.0, "Tank: the hit shoves the rig hard (%.0f px)" % rig.global_position.distance_to(mark.pos))
				_check(not z.is_charging() and z.charge_cooldown > 5.0, "Tank: then cools down")
				z.take_hit(100.0, Vector2.ZERO)
				_check(is_equal_approx(z.hp, 400.0), "Tank: bullets do half")
				_park(SPOT)
				z.global_position = SPOT + Vector2(260, 0)
				z.charge_cooldown = 0.0
				_next()
		3:  # Tank: dodge the charge, it stumbles
			if frame == roundi((T.TANK_WINDUP - T.TANK_AIM_LOCK) * 60.0) + 6:
				_check(z.is_charging(), "Tank: charging again")
				rig.global_position = SPOT + Vector2(0, 400)  # swerve once its aim is locked
			if frame == roundi((T.TANK_WINDUP + T.TANK_CHARGE_TIME) * 60.0) + 15:
				_check(z.is_stumbling() and z.charge_hits == 1, "Tank: a missed charge leaves it stumbling")
				mark.scrap = main.scrap
				mark.pickups = main.pickups.get_child_count()
				z.take_hit(1000.0, Vector2.ZERO, "rammed")
				_check(is_equal_approx(main.scrap - float(mark.scrap), 15.0 * _scrap_mult()), "Tank pays 15 scrap")
				_check(main.pickups.get_child_count() == int(mark.pickups) + 1, "Tank drops a cache crate")
				var crate: Node = main.pickups.get_child(main.pickups.get_child_count() - 1)
				_check(int(crate.get("scrap_value")) == roundi(T.TANK_CACHE * float(rig.crew_mod("cache"))), "the crate holds %d scrap" % T.TANK_CACHE)
				main.pickups.remove_child(crate)
				crate.free()
				_park(SPOT)
				_next()
		4:  # Boomer: shot near the rig marks it and frenzies the horde
			if frame == 1:
				var near := main.zombies.spawn_at(SPOT + Vector2(-300, 0), "shambler")
				mark.near = near
				var far := main.zombies.spawn_at(SPOT + Vector2(-1000, 700), "shambler")
				mark.far = far
				z = main.zombies.spawn_at(SPOT + Vector2(80, 0), "boomer")
				mark.scrap = main.scrap
				z.take_hit(100.0, Vector2.ZERO)
				_check(main.hazards.bile_count() == 1 and main.hazards.bile_at(SPOT + Vector2(80, 0)), "Boomer: dies into a bile pool")
				_check(main.hazards.is_marked(rig), "Boomer: the burst marks a rig caught in it")
				_check(is_equal_approx(main.scrap - float(mark.scrap), 3.0 * _scrap_mult()), "Boomer pays 3 scrap")
			if frame == 3:
				_check((mark.near as Object).get("frenzy") and not (mark.far as Object).get("frenzy"), "marked: zombies within %d rush the rig, others don't" % int(T.BILE_MARK_RANGE))
			if frame == 3 + roundi(T.BILE_MARK_TIME * 60.0) + 5:
				_check(not main.hazards.is_marked(rig) and not (mark.near as Object).get("frenzy"), "the mark wears off")
				(mark.far as Node2D).global_position = SPOT + Vector2(80, 0)
			if frame == 3 + roundi(T.BILE_MARK_TIME * 60.0) + 7:
				var in_pool: Node2D = mark.far
				_check(main.hazards.bile_at(in_pool.global_position) and in_pool.frenzy, "a zombie standing in bile frenzies")
				main.zombies.clear_all()
				# Far away: no mark.
				z = main.zombies.spawn_at(SPOT + Vector2(700, 0), "boomer")
				z.take_hit(100.0, Vector2.ZERO)
				_check(not main.hazards.is_marked(rig), "Boomer: popped at range, no mark")
				# Walks into the rig: bursts on its own.
				z = main.zombies.spawn_at(SPOT + Vector2(45, 0), "boomer")
				mark.kills = main.kills
			if frame == 3 + roundi(T.BILE_MARK_TIME * 60.0) + 12:
				_check(not z.active and main.kills == int(mark.kills) + 1 and main.hazards.is_marked(rig), "Boomer: bursts when it reaches the rig")
				main.hazards.clear()
				main.zombies.clear_all()
				_park(SPOT)
				_next()
		5:  # Slimer: trail, puddle, grip
			if frame == 1:
				z = main.zombies.spawn_at(SPOT + Vector2(-600, 0), "slimer")
			if frame == 90:
				_check(main.hazards.slime_count() >= 3, "Slimer: leaves a trail as it walks (%d blobs)" % main.hazards.slime_count())
				var at := z.global_position
				z.take_hit(1000.0, Vector2.ZERO)
				_check(main.hazards.slime_at(at + Vector2(T.SLIME_PUDDLE_RADIUS - 5.0, 0)), "Slimer: dies into a puddle")
				rig.global_position = at
				rig.velocity = Vector2.ZERO
			# Slime builds SLICK (§14): ~5 s on it with the shield up (+15 resist), then the tyres slide.
			if frame == 93 + 360:
				_check(is_equal_approx(rig.traction, T.SLIME_GRIP), "sitting on slime builds SLICK: the rig keeps %d%% of its grip" % roundi(T.SLIME_GRIP * 100.0))
				rig.global_position = SPOT + Vector2(0, 500)
			if frame == 93 + 360 + 60:
				_check(is_equal_approx(rig.traction, T.SLIME_GRIP), "still slick after leaving the slime (SLICK lasts %d s)" % int(T.STATUS_TIME_RIG[4]))
			if frame == 93 + 360 + roundi(T.STATUS_TIME_RIG[4] * 60.0) + 10:
				_check(is_equal_approx(rig.traction, 1.0), "then the tyres grip again")
				var enemy := main.spawn_outrider(SPOT + Vector2(-600, 0))
				enemy.player = null   # parked: no one to chase, so it sits in the slime
				main.hazards.add_slime(enemy.global_position, 200.0)
				mark.enemy = enemy
			if frame == 93 + 360 + roundi(T.STATUS_TIME_RIG[4] * 60.0) + 10 + 240:
				_check(is_equal_approx((mark.enemy as Node).get("traction"), T.SLIME_GRIP), "enemy rigs slide on slime too")
				for i in 400:
					main.hazards.add_slime(SPOT + Vector2(i, 0), 10.0)
				_check(main.hazards.slime_count() <= main.hazards.SLIME_CAP, "slime is a fixed pool (%d max)" % main.hazards.SLIME_CAP)
				_finish()
	return false


func _check_tables() -> void:
	var d: ZombieDirector = main.zombies
	d.set_mix(1)
	_check(d.mix.is_empty() and d.tanks_left == 0, "1 skull: Shamblers only")
	d.set_mix(2)
	_check(d.mix.keys() == ["slimer"], "2 skulls: Slimers join")
	d.set_mix(3)
	_check(d.mix.has("brute") and d.mix.has("boomer") and d.tanks_left == 0, "3 skulls: Brutes and Boomers")
	d.set_mix(4)
	_check(d.tanks_left == 1, "4 skulls: a Tank")
	d.set_mix(6)
	_check(d.tanks_left == 2 and is_equal_approx(float(d.mix.slimer), 0.10) and is_equal_approx(float(d.mix.brute), 0.10) and is_equal_approx(float(d.mix.boomer), 0.08),
		"6 skulls: 10% Slimer, 10% Brute, 8% Boomer, up to 2 Tanks")
	var counts := {}
	for i in 4000:
		var k := d.roll_kind()
		counts[k] = int(counts.get(k, 0)) + 1
	_check(absf(float(counts.get("brute", 0)) / 4000.0 - 0.10) < 0.025 and float(counts.get("shambler", 0)) / 4000.0 > 0.65,
		"packs roll kinds by share (Brutes %d%%)" % roundi(float(counts.get("brute", 0)) / 40.0))
	d.set_mix(6, true)
	_check(not d.mix.has("brute") and d.mix.has("slimer") and d.mix.has("boomer") and d.tanks_left == 0, "Courier: Slimers and Boomers only")
	_check(Missions.zombie_kinds_text(Missions.make("clear", 1, 7)) == "", "Comms: nothing extra at 1 skull")
	_check(Missions.threats_text(Missions.make("clear", 4, 7)).contains("Slimers, Brutes, Boomers, up to 1 Tank"), "Comms lists the zombie types on the card")
	_check(Missions.zombie_kinds_text(Missions.make("courier", 6, 7)) == "Slimers, Boomers", "Comms: Courier shows Slimers and Boomers")
	# Tanks show up in packs, and no more than the job allows.
	d.set_mix(6)
	d.spawn_budget = 400
	d._elapsed = T.TANK_EARLIEST + 1.0
	var tanks := 0
	for i in 60:
		d._spawn_pack(d.cap)
		tanks += d.count_kind("tank")
		d.clear_all()
	_check(tanks == 2 and d.tanks_left == 0, "Tanks arrive with packs, 2 at most at 6 skulls")
	d.set_mix(1)


func _scrap_mult() -> float:
	return main.profile.salvage_mult() * float(main.vehicle.crew_mod("scrap"))


func _park(at: Vector2) -> void:
	var rig := main.vehicle
	rig.global_position = at
	rig.velocity = Vector2.ZERO
	rig.rotation = PI / 2.0
	rig.armor = rig.armor_max
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
	# Teardown: free the mission, drop the test's node refs, and let a few
	# frames pass so everything is gone at exit.
	step = -1   # _process stops driving the test
	z = null
	mark.clear()
	main.queue_free()
	main = null
	for i in 3:
		await process_frame
	if failures.is_empty():
		print("ZOMBIE TEST PASSED")
		quit(0)
	else:
		print("ZOMBIE TEST FAILED: %s" % ", ".join(failures))
		quit(1)
