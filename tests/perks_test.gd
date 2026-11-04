extends SceneTree
## Headless test for implement-03 (content proposal 01, approved 2026-11-03):
## flag mods (Napalm Mix, Etch, Cluster Shell, Bait Shell) and Major/Signature
## specialty perks, plus the §14 specialty reworks (Tune-Up, Power Divert,
## Scrap Drones, Miasma).
##
## Run:  godot --headless --fixed-fps 60 --path . -s res://tests/perks_test.gd

const Mission := preload("res://scripts/mission.gd")
const Missions := preload("res://scripts/missions.gd")
const Mods := preload("res://scripts/mods.gd")
const Loadout := preload("res://scripts/loadout.gd")
const Parts := preload("res://scripts/parts.gd")
const Crew := preload("res://scripts/crew.gd")
const BulletPool := preload("res://scripts/bullet_pool.gd")
const T := preload("res://scripts/tuning.gd")

const SPOT := Vector2(1600, 1200)

var main: Mission
var profile: Node
var frame := 0
var failures: Array[String] = []
var mark := {}
var dice := RandomNumberGenerator.new()


func _initialize() -> void:
	seed(20261105)
	dice.seed = 9
	profile = root.get_node("Profile")
	profile.set("persist", false)
	profile.call("new_game")
	main = (load("res://scenes/mission.tscn") as PackedScene).instantiate() as Mission
	main.mission_override = Missions.make("clear", 1, 7)
	main.auto_spawn_specials = false
	main.push_override = 0
	root.add_child(main)


func _m(role: String, spec: String, perks: Array) -> Dictionary:
	var m := Crew.make(role, "Mythic", dice, spec)
	m.perks = perks
	return m


func _seat(members: Array) -> void:
	for i in members.size():
		members[i].id = 900 + i
	main.vehicle.set_crew(members)
	main.call("_sync_hud_to_rig")


func _hold(rig: Node2D) -> void:
	rig.global_position = SPOT
	rig.velocity = Vector2.ZERO
	rig.rotation = 0.0


func _process(_delta: float) -> bool:
	frame += 1
	var rig := main.vehicle
	if frame > 3:
		_hold(rig)
	if frame == 3:
		main.zombies.spawn_budget = 0
		main.zombies.clear_all()
		for b in main.barrels:
			b.deactivate()
		_hold(rig)
		rig.armor_max = 100000.0
		rig.armor = rig.armor_max
		var o := main.spawn_outrider(SPOT + Vector2(1400, 0))
		o.set_physics_process(false)
		mark.o = o
		# Napalm Mix: +2 s BURNING on fire hits, once per BURNING.
		rig.mods = ["napalm_mix"]
		o.fill_status(1)
		var left := float(o.status.left[1])
		rig.player_post_hit(o, 5.0, "fire", false)
		var after := float(o.status.left[1])
		rig.player_post_hit(o, 5.0, "fire", false)
		_check(is_equal_approx(after - left, Mods.NAPALM_BURN_ADD) and is_equal_approx(float(o.status.left[1]), after), "Napalm Mix: +2 s BURNING, once per BURNING")
		# Cluster Shell: three bomblets.
		var cb: int = main.shells.cluster_bomblets
		main.shells.launch(SPOT + Vector2(0, 400), SPOT + Vector2(300, 400), 0.1, 30.0, 80.0, BulletPool.TEAM_PLAYER, "", {"cluster": true})
		mark.cb = cb
		mark.blasts = main.shells.blasts
		# Bait Shell: GOOPED + bait timer = +10% from zombies.
		o.fill_status(5)
		o.bait_shell_left = 3.0
		# Shutdown + Exposed (Marker).
		_seat([_m("driver", "", []), _m("spotter", "marker", ["sp_shutdown", "sp_exposed"])])
		rig.lock_target = o
		_check(main.use_crew_ability(1) and float(o.shutdown_left) > 2.9 and float(o.get("_shield_wait")) > 1.0, "Shutdown / Exposed: the MARKED rig loses abilities for 3 s and its shield stops recharging")
		rig.lock_target = null
		# Bounty.
		_seat([_m("scavenger", "salvager", ["sp_bounty"])])
		var s: float = main.scrap
		main.call("_rig_wreck_perks", o.global_position)
		_check(is_equal_approx(main.scrap - s, 10.0), "Bounty: +10 scrap per rig wreck")
		# Last Breath.
		_seat([_m("medic", "field_medic", ["sp_last_breath"])])
		rig.hp = 10.0
		rig.armor = 0.0
		for i in 4:
			rig.facing_armor[i] = 0.0
		rig.shield = 0.0
		rig.take_damage(500.0)
		_check(not rig.is_wrecked and is_equal_approx(rig.hp, 1.0), "Last Breath: HP floors at 1 once per mission")
		rig.take_damage(500.0)
		_check(not rig.is_wrecked, "...and the rig is invulnerable for 1 s")
		rig.hp = rig.hp_max
		rig.armor = rig.armor_max
		for i in 4:
			rig.facing_armor[i] = rig.facing_max[i]
		# Power Divert on the starter rig (spare power).
		_seat([_m("engineer", "conduit", [])])
		var spare := minf(maxf(rig.power_capacity() - rig.power_load(), 0.0), T.POWER_DIVERT_CAP)
		var smax: float = rig.shield_max
		_check(main.use_crew_ability(0) and is_equal_approx(rig.shield_max - smax, spare), "Power Divert: +1 shield per spare power point, cap 80 (+%d)" % int(spare))
		mark.smax = smax
	if frame == 10:
		var o: Node2D = mark.o
		_check(main.shells.cluster_bomblets == int(mark.cb) + 3 and main.shells.blasts == int(mark.blasts) + 3, "Cluster Shell: three 45 px bomblets")
		# Etch: CORRODED rigs take +20% from acid blasts while armored.
		o.fill_status(2)
		var etched: int = main.shells.etched
		main.shells._blast(o.global_position, 60.0, 10.0, BulletPool.TEAM_PLAYER, "acid", {"etch": true})
		_check(main.shells.etched == etched + 1, "Etch: an acid blast on a CORRODED, armored rig is boosted")
		o.call("_tick_perks", 0.016)
		_check(is_equal_approx(float(o.zombie_taken), 1.0 + Mods.BAIT_SHELL_ZOMBIE), "Bait Shell: GOOPED rigs take +10% from zombies")
	if frame == 600:
		_check(not rig.ability_active("power_divert") and is_equal_approx(rig.shield_max, float(mark.smax)), "Power Divert ends (6 s, x1.5 at Mythic); the bonus goes")
		# Miasma and Scrap Drones against a nearby rig.
		var o: Node2D = mark.o
		o.global_position = SPOT + Vector2(200, 0)
		o.status.left[3] = 0.0
		_seat([_m("medic", "poisoner", []), _m("engineer", "tinkerer", ["sp_third_wheel"])])
		_check(main.use_crew_ability(0), "Miasma fires")
		_check(main.use_crew_ability(1) and rig.drones.size() == 3, "Scrap Drones: 2 drones, 3 with Third Wheel")
		mark.hp = float(o.call("_armor_total")) + float(o.get("hp"))
	if frame == 720:
		var o: Node2D = mark.o
		_check(bool(o.call("is_status", 3)) or int(o.status.triggers) > 0, "Miasma: a rig in the 250 px cloud builds TOXIC")
		_check(not bool(rig.is_status(3)), "Miasma: your own rig is immune")
		var shots := 0
		for d in rig.drones:
			if is_instance_valid(d):
				shots += int(d.shots)
		_check(shots > 0, "Scrap Drones: drones shoot at a rig in range (%d shots)" % shots)
		_finish()
	return false


func _check(ok: bool, what: String) -> void:
	print(("  PASS  " if ok else "  FAIL  ") + what)
	if not ok:
		failures.append(what)


func _finish() -> void:
	if failures.is_empty():
		print("PERKS TEST PASSED")
		quit(0)
	else:
		print("PERKS TEST FAILED: %s" % ", ".join(failures))
		quit(1)
