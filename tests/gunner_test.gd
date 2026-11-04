extends SceneTree
## Headless test for the Gunner Rig and the Burst Turret: the part's numbers
## and bursts on the player's rig, the Gunner Rig holding its distance and
## shooting, backing off when you close in, turning on zombies at its door,
## dropping salvage, waiting for room under the rig cap, the mission tables
## and Comms text, and guarding a checkpoint in a Courier job.
##
## Run:  godot --headless --fixed-fps 60 --path . -s res://tests/gunner_test.gd

const Mission := preload("res://scripts/mission.gd")
const Missions := preload("res://scripts/missions.gd")
const GunnerRig := preload("res://scripts/gunner_rig.gd")
const Parts := preload("res://scripts/parts.gd")
const Loadout := preload("res://scripts/loadout.gd")
const T := preload("res://scripts/tuning.gd")

const SPOT := Vector2(1600, 1200)   # open ground at the player start
const BURST_BUILD := {
	"chassis": "scrap_frame", "engine": "junk_v6", "drive": "street_wheels", "armor": "scrap_plating",
	"weapons": ["burst_turret"], "utility": [], "internal": [],
}

var main: Mission
var frame := 0
var step := 0
var failures: Array[String] = []
var g: GunnerRig
var mark := {}


func _initialize() -> void:
	seed(20261104)
	var profile: Node = root.get_node("Profile")
	profile.set("persist", false)
	profile.call("new_game")
	_start(Missions.make("clear", 1, 7))


func _start(spec: Dictionary) -> void:
	if main != null:
		main.queue_free()
	main = (load("res://scenes/mission.tscn") as PackedScene).instantiate() as Mission
	main.mission_override = spec
	main.auto_spawn_specials = false
	main.always_drop_schematic = true
	root.add_child(main)
	frame = 0


func _process(_delta: float) -> bool:
	frame += 1
	var rig := main.vehicle
	match step:
		0:
			if frame == 3:
				_check_part()
				_check_tables()
				main.zombies.spawn_budget = 0
				main.zombies.clear_all()
				for b in main.barrels:
					b.deactivate()   # this test is about the Gunner Rig, not stray barrels
				rig.armor_max = 100000.0
				rig.armor = rig.armor_max
				main.apply_rig(Loadout.build(BURST_BUILD))
				_park(SPOT)
				mark.shots = main.bullets.shots_fired
				main.hud.right_stick.output = Vector2.RIGHT
			if frame == 3 + 20:
				var fired: int = main.bullets.shots_fired - int(mark.shots)
				_check(fired == 4, "Burst Turret: one pull fires a 4-round burst (%d)" % fired)
			if frame == 3 + 20 + 55:
				var fired: int = main.bullets.shots_fired - int(mark.shots)
				_check(fired == 8, "Burst Turret: the next burst ~0.9 s later (%d rounds by 1.2 s)" % fired)
				main.hud.right_stick.output = Vector2.ZERO
				main.apply_rig(Loadout.build(Parts.STARTER_LOADOUT))
				rig.armor_max = 100000.0
				rig.armor = rig.armor_max
				_next()
		1:  # Holds its distance and shoots
			if frame == 1:
				_park(SPOT)
				g = main.spawn_gunner(SPOT + Vector2(900, 0)) as GunnerRig
				_check(g != null and g == main.gunner, "spawn_gunner sends in a Gunner Rig")
				mark.armor = rig.armor
			if frame == 300:
				var d := g.global_position.distance_to(rig.global_position)
				_check(d > T.GUNNER_RANGE_MIN - 80.0 and d < T.GUNNER_RANGE_MAX + 120.0, "it closes to its standoff ring (%.0f px)" % d)
				_check(main.bullets.enemy_shots > 0 and rig.armor < float(mark.armor), "its turret works you over (-%.0f armor)" % (float(mark.armor) - rig.armor))
				rig.global_position = g.global_position + Vector2.RIGHT.rotated(g.rotation) * 160.0
				rig.velocity = Vector2.ZERO
				mark.close = rig.global_position.distance_to(g.global_position)
			if frame == 420:
				var d := g.global_position.distance_to(rig.global_position)
				_check(d > float(mark.close) + 80.0, "it backs off when you close in (%.0f -> %.0f px)" % [float(mark.close), d])
				_next()
		2:  # Zombies at the door get the turret
			if frame == 1:
				g.velocity = Vector2.ZERO
				rig.global_position = g.global_position + Vector2(0, 450)   # in its ring: it circles slowly
				var turret: Node2D = g._turrets[0]
				var at := g.global_position + Vector2.RIGHT.rotated(turret.global_rotation + 0.8) * 75.0
				mark.z = main.zombies.spawn_at(at, "brute")
			if frame == 20:
				_check(g.shooting_at == mark.z, "a zombie within %d px gets the turret first" % int(T.GUNNER_SELF_DEFENSE))
			if frame == 90:
				var z: Node = mark.z
				_check(not z.get("active") or float(z.get("hp")) < 200.0, "it shoots the zombie")
				main.zombies.clear_all()
				_next()
		3:  # Wrecked: salvage and scrap
			if frame == 1:
				mark.scrap = main.scrap
				mark.kills = main.kills
				mark.pickups = main.pickups.get_child_count()
				g.take_damage(100000.0)
			if frame == 3:
				_check(g.is_wrecked and main.kills == int(mark.kills) + 1, "wrecked, it counts as a kill")
				var mult := main.profile.salvage_mult() * float(rig.crew_mod("scrap")) * float(rig.crew_mod("rig_scrap"))
				_check(is_equal_approx(main.scrap - float(mark.scrap), T.GUNNER_SCRAP * mult), "it pays %d scrap" % T.GUNNER_SCRAP)
				var drop: Node = main.pickups.get_child(main.pickups.get_child_count() - 1)
				var part: Dictionary = drop.get("part")
				_check(main.pickups.get_child_count() == int(mark.pickups) + 1 and Parts.DROP_POOLS.gunner.has(str(part.get("id", ""))),
					"it drops a schematic from its pool (%s)" % str(part.get("name", "")))
				# The cap: three rigs in the fight, no fourth.
				main.spawn_outrider(SPOT + Vector2(-900, 0))
				main.spawn_bulwark(SPOT + Vector2(-900, 300))
				main.gunners.append(GunnerRig.new())
				main.gunners[1].player = rig
				main.gunners[1].bullets = main.bullets
				main.gunners[1].fx = main.fx
				_check(main.spawn_gunner(SPOT + Vector2(0, -900)) != null and main.active_rig_count() == 3, "a second Gunner Rig fills the third slot")
				main.gunners.append(GunnerRig.new())
				_check(main.spawn_gunner(SPOT + Vector2(0, 900)) == null, "a fourth rig waits for room under the cap")
				_start(Missions.make("courier", 4, 11))
				main.auto_spawn_specials = true
				_next()
		4:  # Courier: it guards a checkpoint
			if frame == 3:
				main.zombies.spawn_budget = 0
				main.zombies.clear_all()
				main.vehicle.armor_max = 100000.0
				main.vehicle.armor = 100000.0
			if frame == 300:
				g = main.gunner
				var post := main.checkpoints[main.checkpoints.size() / 2]
				_check(g.is_inside_tree() and g.is_guarding() and g.guard_point == post, "Courier: a Gunner Rig covers a checkpoint halfway along")
				_check(g.global_position.distance_to(post) < T.GUNNER_GUARD_RADIUS + 120.0, "it stays by its post while you're far away (%.0f px)" % g.global_position.distance_to(post))
				_finish()
	return false


func _check_part() -> void:
	var part := Parts.get_part("burst_turret")
	_check(part.rarity == "Uncommon" and int(part.cost) == 110 and float(part.power) == 40.0 and float(part.weight) == 15.0 and float(part.lock_range) == 600.0,
		"Burst Turret: Uncommon, 110 scrap, 40 power, 15 weight, lock 600")
	var stats := Loadout.build(BURST_BUILD)
	_check(absf(Loadout.total_dps(stats) - 50.1) < 0.5, "Burst Turret: about 62 DPS firing, 50 sustained with its 6-burst magazine (%.1f)" % Loadout.total_dps(stats))
	_check(int((stats.weapons as Array)[0].burst) == 4, "the loadout carries the burst")
	var g_dps := float(T.GUNNER.fire_rate) * float(T.GUNNER.bullet_damage) * int(T.GUNNER.burst)
	_check(absf(g_dps - 20.0) < 0.5, "Gunner Rig: about 20 damage/s (%.1f)" % g_dps)


func _check_tables() -> void:
	_check(Missions.threats_text(Missions.make("clear", 3, 7)).contains("1 Gunner Rig"), "Clear 3 skulls: a Gunner Rig on the card")
	_check(not Missions.threats_text(Missions.make("clear", 2, 7)).contains("Gunner"), "no Gunner Rigs below 3 skulls")
	_check(Missions.threats_text(Missions.make("survive", 4, 7)).contains("1 Gunner Rig"), "Survive 4 skulls: one joins the waves")
	_check(not Missions.threats_text(Missions.make("survive", 3, 7)).contains("Gunner"), "Survive 3 skulls: none")
	_check(Missions.threats_text(Missions.make("hunt", 5, 7)).contains("1 Gunner Rig"), "Hunt 5 skulls: one escorts the Elite")
	_check(Missions.threats_text(Missions.make("courier", 4, 7)).contains("1 Gunner Rig"), "Courier 4 skulls: one guards the route")
	_check(not Missions.threats_text(Missions.make("courier", 3, 7)).contains("Gunner"), "Courier 3 skulls: none")


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
		print("GUNNER TEST PASSED")
		quit(0)
	else:
		print("GUNNER TEST FAILED: %s" % ", ".join(failures))
		quit(1)
