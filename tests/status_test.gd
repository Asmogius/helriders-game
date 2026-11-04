extends SceneTree
## Headless test for §14 statuses, damage types and barrels: the buildup
## formula (resistance, drain, afterglow), the player's resistances (base 30
## plus plates, capped; an active shield's bonus), enemy resistances, the
## damage-type bonuses and CORRODED, each status on rigs (STUNNED, BURNING,
## TOXIC, SLICK from slime, GOOPED) and zombies (frozen, burning and its
## spread), and the five barrels (placed per job, shot or rammed, chained,
## fire ground lighting oil, acid, slime, Boomer).
##
## Run:  godot --headless --fixed-fps 60 --path . -s res://tests/status_test.gd

const Mission := preload("res://scripts/mission.gd")
const Missions := preload("res://scripts/missions.gd")
const Vehicle := preload("res://scripts/vehicle.gd")
const StatusBars := preload("res://scripts/status_bars.gd")
const Barrel := preload("res://scripts/barrel.gd")
const Parts := preload("res://scripts/parts.gd")
const Loadout := preload("res://scripts/loadout.gd")
const Arena := preload("res://scripts/arena.gd")
const T := preload("res://scripts/tuning.gd")

const SPOT := Vector2(1600, 1200)

var main: Mission
var frame := 0
var step := 0
var failures: Array[String] = []
var mark := {}


func _initialize() -> void:
	seed(20261105)
	var profile: Node = root.get_node("Profile")
	profile.set("persist", false)
	profile.call("new_game")
	_check_rules()
	main = (load("res://scenes/mission.tscn") as PackedScene).instantiate() as Mission
	main.mission_override = Missions.make("clear", 1, 7)
	main.auto_spawn_specials = false
	root.add_child(main)


func _process(_delta: float) -> bool:
	frame += 1
	var rig := main.vehicle
	match step:
		0:
			if frame == 3:
				main.zombies.clear_all()
				main.zombies.spawn_budget = 0
				rig.armor_max = 100000.0
				rig.armor = rig.armor_max
				_park(SPOT)
				_check(main.barrels.size() == T.BARRELS_PER_JOB, "%d barrels placed for the job" % T.BARRELS_PER_JOB)
				var on_spots := true
				for b in main.barrels:
					on_spots = on_spots and Arena.BARREL_SPOTS.has(b.position) and T.BARREL_TYPES.has(b.kind)
				_check(on_spots, "barrels sit on the layout's fixed spots, types rolled")
				# STUNNED: the stick does nothing.
				rig.fill_status(StatusBars.SHOCK)
				main.hud.left_stick.output = Vector2.DOWN
				mark.pos = rig.global_position
				mark.shots = main.bullets.shots_fired
				main.hud.right_stick.output = Vector2.RIGHT
			if frame == 3 + roundi(T.STATUS_TIME_RIG[0] * 60.0) - 6:
				_check(rig.global_position.distance_to(mark.pos) < 10.0 and main.bullets.shots_fired == int(mark.shots), "STUNNED: the rig can't drive or fire")
			if frame == 3 + roundi(T.STATUS_TIME_RIG[0] * 60.0) + 30:
				_check(rig.global_position.distance_to(mark.pos) > 20.0, "...for %.1f s, then it drives again" % T.STATUS_TIME_RIG[0])
				_park(SPOT)
				_next()
		1:  # BURNING, TOXIC, SLICK, GOOPED on the rig
			if frame == 1:
				rig.armor = rig.armor_max
				mark.hp = rig.hp
				mark.armor = rig.facing_armor[0] + rig.facing_armor[1] + rig.facing_armor[2] + rig.facing_armor[3]
				rig.shield = 0.0
				rig.fill_status(StatusBars.FIRE)
			if frame == 61:
				var armor := rig.facing_armor[0] + rig.facing_armor[1] + rig.facing_armor[2] + rig.facing_armor[3]
				_check(armor < float(mark.armor) - 5.0 and rig.hp == float(mark.hp), "BURNING eats armor across the facings, not HP while armor holds")
				rig.status.left[StatusBars.FIRE] = 0.0
				# TOXIC: blocked by a raised shield, then down to the floor.
				rig.armor = rig.armor_max
				rig.fill_status(StatusBars.TOXIC)
				mark.hp = rig.hp
			if frame == 91:
				_check(rig.hp == float(mark.hp), "TOXIC is blocked while the shield is up")
				rig.shield = 0.0
				rig.shield_max = 0.0
				rig.hp = rig.hp_max * T.TOXIC_FLOOR + 3.0
			if frame == 151:
				_check(is_equal_approx(rig.hp, rig.hp_max * T.TOXIC_FLOOR), "TOXIC goes straight to HP, never below 10%")
				rig.status.left[StatusBars.TOXIC] = 0.0
				rig.armor = rig.armor_max
				# SLICK builds on slime.
				main.hazards.add_slime(SPOT, 200.0)
				_park(SPOT)
				mark.slick_frame = -1
			if frame > 151 and frame < 151 + 360 and int(mark.slick_frame) < 0 and rig.is_status(StatusBars.SLIME):
				mark.slick_frame = frame - 151
			if frame == 151 + 360:
				var secs := float(mark.slick_frame) / 60.0
				var expect := T.STATUS_BAR / (T.STATUS_POOL_BUILDUP * (100.0 - 45.0) / 50.0)
				_check(int(mark.slick_frame) > 0 and absf(secs - expect) < 0.4, "SLICK builds on slime in ~%.1f s (%.1f s)" % [expect, secs])
				_check(rig.traction == T.SLIME_GRIP, "SLICK: grip down to %d%%" % roundi(T.SLIME_GRIP * 100.0))
				main.hazards.clear()
				rig.status.reset()
				rig.fill_status(StatusBars.GOOP)
				_check(main.hazards.is_marked(rig), "GOOPED marks the rig for the horde")
				main.hazards.clear()
				rig.status.reset()
				_next()
		2:  # Zombies: frozen, burning and its spread, fire's bonus
			if frame == 1:
				var z := main.zombies.spawn_at(SPOT + Vector2(500, 0), "brute")
				z.fill_status(StatusBars.SHOCK)
				mark.z = z
				mark.zpos = z.global_position
				var a := main.zombies.spawn_at(SPOT + Vector2(-600, 300), "brute")
				var b := main.zombies.spawn_at(SPOT + Vector2(-600, 320), "brute")
				a.fill_status(StatusBars.FIRE)
				mark.a = a
				mark.b = b
				mark.ahp = a.hp
				var c := main.zombies.spawn_at(SPOT + Vector2(0, 600), "shambler")
				c.take_hit(10.0, Vector2.ZERO, "blast", "fire")
				_check(is_equal_approx(c.hp, 40.0 - 10.0 * T.FIRE_VS_ZOMBIES), "fire does +50% to zombies")
			if frame == 60:
				var z: Node2D = mark.z
				_check(z.global_position.distance_to(mark.zpos) < 5.0, "STUNNED zombies freeze")
				var a: Node = mark.a
				_check(float(a.get("hp")) < float(mark.ahp) - 5.0, "BURNING zombies take damage")
			if frame == 200:
				var b: Node = mark.b
				_check((b.get("status") as StatusBars).active(StatusBars.FIRE), "BURNING spreads to a zombie it touches")
				main.zombies.clear_all()
				_next()
		3:  # Barrels
			if frame == 1:
				for b in main.barrels:
					b.deactivate()
				_park(SPOT)
				main.barrels[0].place(SPOT + Vector2(100, 0), "explosive")
				main.barrels[1].place(SPOT + Vector2(200, 0), "slime")
				main.barrels[2].place(SPOT + Vector2(-440, -400), "fire")
				main.barrels[3].place(SPOT + Vector2(-20, -150), "acid")
				main.barrels[4].place(SPOT + Vector2(-120, 0), "boomer")
				mark.gz = main.zombies.spawn_at(SPOT + Vector2(-200, 60), "shambler")
			if frame == 3:
				# (Barrels need a physics step after placing before blasts can find them.)
				var boom := main.barrels[0]
				var chain := main.barrels[1]
				mark.hp = rig.hp
				mark.armor = rig.armor
				mark.kills = main.kills
				boom.take_hit(5.0, Vector2.ZERO)
				_check(boom.active, "a few shots don't set a barrel off (20 HP)")
				boom.take_hit(30.0, Vector2.ZERO)
				_check(not boom.active and boom.blasts == 1, "enough shots blow it")
				_check(not chain.active and main.hazards.slime_at(SPOT + Vector2(200, 0)), "blasts chain: a nearby Slime barrel went too and left a pool")
				_check(rig.armor < float(mark.armor) and rig.hp == float(mark.hp), "barrels hurt the player too (splash: armor, not HP)")
				# Fire barrel: burning ground that lights oil.
				var fire := main.barrels[2]
				main.hazards.add_oil(SPOT + Vector2(-500, -400), 60.0, 12.0)
				fire.take_hit(100.0, Vector2.ZERO)
				_check(main.hazards.fire_at(SPOT + Vector2(-440, -400)) and main.hazards.fire_at(SPOT + Vector2(-520, -400)) and main.hazards.oil_count() == 0, "Fire barrel: the ground burns and the oil catches")
				# Acid barrel: acid buildup.
				var acid := main.barrels[3]
				rig.status.reset()
				rig.shield = 0.0
				acid.take_hit(100.0, Vector2.ZERO)
				var expect := T.BARREL_ACID_BUILDUP * (100.0 - float(rig.resist[StatusBars.ACID])) / 50.0
				_check(absf(rig.status.build[StatusBars.ACID] - expect) < 1.0, "Acid barrel: %d acid buildup (after resistance %.0f)" % [int(T.BARREL_ACID_BUILDUP), expect])
				# Boomer barrel: GOOPED outright.
				var goo := main.barrels[4]
				var gz: Node = mark.gz
				goo.take_hit(100.0, Vector2.ZERO)
				_check(rig.is_status(StatusBars.GOOP) and (gz.get("status") as StatusBars).active(StatusBars.GOOP), "Boomer barrel fills GOOPED on rigs and zombies in range")
				main.barrels[5].place(SPOT + Vector2(0, -300), "explosive")
			if frame == 5:
				# Rammed: any ram sets one off.
				var ram := main.barrels[5]
				_park(SPOT + Vector2(0, -150))
				rig.rotation = -PI / 2.0
				rig.velocity = Vector2(0, -500)
				main.hud.left_stick.output = Vector2.UP
				mark.ram = ram
			if frame == 45:
				_check(not (mark.ram as Barrel).active and (mark.ram as Barrel).last_hit_cause == "rammed", "ramming a barrel sets it off")
				_finish()
	return false


func _check_rules() -> void:
	var s := StatusBars.new()
	s.add(StatusBars.FIRE, 20.0, 50.0, 5.0)
	_check(is_equal_approx(s.build[StatusBars.FIRE], 20.0), "resistance 50: buildup x1")
	s.add(StatusBars.FIRE, 20.0, 0.0, 5.0)
	_check(is_equal_approx(s.build[StatusBars.FIRE], 60.0), "resistance 0: x2")
	s.add(StatusBars.FIRE, 50.0, 100.0, 5.0)
	_check(is_equal_approx(s.build[StatusBars.FIRE], 60.0), "resistance 100: immune")
	_check(s.add(StatusBars.FIRE, 40.0, 50.0, 5.0) and s.active(StatusBars.FIRE) and s.build[StatusBars.FIRE] == 0.0, "a full bar triggers the status")
	s.add(StatusBars.FIRE, 20.0, 50.0, 5.0)
	_check(is_equal_approx(s.build[StatusBars.FIRE], 10.0), "just after a trigger, buildup runs at half speed")
	s.tick(1.0)
	_check(is_equal_approx(s.build[StatusBars.FIRE], 10.0), "no drain in the first 1.5 s")
	s.tick(0.5)
	s.tick(0.4)
	_check(is_equal_approx(s.build[StatusBars.FIRE], 10.0 - T.STATUS_DRAIN * 0.4), "then it drains at 15/s")
	# Player resistances: base 30 + plates.
	var starter := Loadout.build(Parts.STARTER_LOADOUT)
	_check((starter.resist as Array) == [45.0, 45.0, 45.0, 45.0, 45.0, 45.0], "starter (Scrap Plating x3): 45 to everything")
	var riot := Parts.STARTER_LOADOUT.duplicate(true)
	for slot: String in ["armor_front", "armor_sides", "armor_rear"]:
		riot[slot] = "riot_plating"
	var r: Array = Loadout.build(riot).resist
	_check(float(r[0]) == 75.0 and float(r[1]) == 60.0 and float(r[2]) == 45.0, "Riot Plating x3: shock 75, fire 60, acid 45 (§14's High / Medium / Low)")
	var cap := Loadout.build(riot)
	var bonus := {"resist_bonus": [50.0, 0.0, 0.0, 0.0, 0.0, 0.0]}
	_check(float(Loadout.resistances({"armor_front": Parts.get_part("riot_plating"), "armor_sides": Parts.get_part("riot_plating"), "armor_rear": Parts.get_part("riot_plating")}, bonus, [] as Array[Dictionary])[0]) == T.STATUS_RESIST_CAP,
		"chassis and accessory bonuses add up, capped at %d" % int(T.STATUS_RESIST_CAP))
	var v := Vehicle.new()
	v.apply_stats(cap)
	v.shield = 10.0
	_check(v.resistance(StatusBars.SHOCK) == 90.0, "an active shield adds 15")
	v.shield = 0.0
	_check(v.resistance(StatusBars.SHOCK) == 75.0, "no shield, no bonus")
	# Damage types.
	v.armor = v.armor_max
	v.shield = 20.0
	v.take_damage(10.0, Vector2.RIGHT, false, "shock")
	_check(is_equal_approx(v.shield, 5.0), "shock hits shields 50% harder")
	v.shield = 0.0
	v.shield_max = 0.0
	var front := v.facing_armor[0]
	v.take_damage(10.0, Vector2.RIGHT, false, "acid")
	_check(is_equal_approx(front - v.facing_armor[0], 15.0), "acid eats plates 50% faster")
	v.status.reset()
	v.fill_status(StatusBars.ACID)
	front = v.facing_armor[0]
	v.take_damage(10.0, Vector2.RIGHT)
	_check(is_equal_approx(front - v.facing_armor[0], 12.5), "CORRODED: +25% damage taken")
	v.free()
	_check((T.SCRAPPER.resist as Array)[4] == 90.0 and (T.BULWARK.resist as Array)[2] == 35.0, "enemy resistances from §14's table")


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
		print("STATUS TEST PASSED")
		quit(0)
	else:
		print("STATUS TEST FAILED: %s" % ", ".join(failures))
		quit(1)
