extends SceneTree
## Headless test for the DRIFT and OVERLOAD keywords and what hangs on them:
## a DRIFT counts once a sideways slide that lasted long enough dies down;
## Hit and Run (+15% damage for 2 s), Drift Fuel (3 s off the Nitro Bottle)
## and Clean Exit (1 s off Hard Line) fire on it. OVERLOAD is a heat gun at
## 75%+ of its bar: Overload Coil chains 2 extra targets, Feedback Loop locks
## OVERLOADed enemy guns hot. Mobile Workshop restores 15% HP once, the first
## time HP falls under 30%. The Outrider's heat shows under it.
##
## Run:  godot --headless --fixed-fps 60 --path . -s res://tests/keywords_test.gd

const Mission := preload("res://scripts/mission.gd")
const Missions := preload("res://scripts/missions.gd")
const Loadout := preload("res://scripts/loadout.gd")
const Crew := preload("res://scripts/crew.gd")
const T := preload("res://scripts/tuning.gd")

var main: Mission
var frame := 0
var failures: Array[String] = []
var mark := {}


func _initialize() -> void:
	var profile: Node = root.get_node("Profile")
	profile.set("persist", false)
	profile.call("new_game")
	main = (load("res://scenes/mission.tscn") as PackedScene).instantiate() as Mission
	main.mission_override = Missions.make("clear", 1, 7)
	main.auto_spawn_specials = false
	root.add_child(main)


func _member(role: String, spec: String, perks: Array) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(spec)
	var m := Crew.make(role, "Legendary", rng, spec)
	m.id = hash(spec) % 100000
	m.perks = perks
	m.xp = float(Crew.xp_for_level(17))
	return m


func _process(_delta: float) -> bool:
	frame += 1
	var rig := main.vehicle
	if frame == 3:
		main.zombies.spawn_budget = 0
		main.zombies.clear_all()
		for b in main.barrels:
			b.deactivate()
		rig.armor_max = 100000.0
		rig.armor = rig.armor_max
		# DRIFT: a long enough slide that dies down counts once; a flick doesn't.
		var d0 := rig.drifts
		for i in 2:
			rig._track_drift(0.1, 300.0, 300.0)
		rig._track_drift(0.1, 0.0, 300.0)
		_check(rig.drifts == d0, "a 0.2 s flick isn't a DRIFT")
		for i in 6:
			rig._track_drift(0.1, 300.0, 300.0)
		_check(rig.is_drifting(), "sliding sideways at speed is a DRIFT")
		rig._track_drift(0.1, 0.0, 300.0)
		_check(rig.drifts == d0 + 1 and not rig.is_drifting(), "it counts when the slide dies down")
		# Hit and Run and Drift Fuel.
		rig.mods = ["hit_and_run", "drift_fuel"]
		rig.abilities = [{"ability": "nitro", "cooldown": 14.0, "ready_in": 10.0, "nitro_speed": 0.4, "nitro_accel": 1.0, "nitro_time": 1.5}]
		rig.end_drift()
		_check(is_equal_approx(rig.hit_run_left, T.HIT_AND_RUN_TIME), "Hit and Run: +15% damage for 2 s after a DRIFT")
		_check(is_equal_approx(float(rig.abilities[0].ready_in), 7.0), "Drift Fuel: 3 s off the Nitro Bottle")
		rig.mods = []
		rig.abilities = []
		# Clean Exit: during Hard Line, a DRIFT takes 1 s off its cooldown.
		rig.set_crew([_member("driver", "wheelman", ["sp_clean_exit"])])
		_check(rig.use_crew_ability(0), "Hard Line on")
		var before := float(rig.crew[0].ready_in)
		rig.end_drift()
		_check(is_equal_approx(float(rig.crew[0].ready_in), before - T.CLEAN_EXIT_REFUND), "Clean Exit: a DRIFT during Hard Line takes 1 s off it")
		# Mobile Workshop.
		rig.armor_max = 300.0
		rig.armor = rig.armor_max
		rig.mods = ["mobile_workshop"]
		for f in 4:
			rig.facing_armor[f] = 0.0
		rig.shield = 0.0
		rig.take_damage(rig.hp - rig.hp_max * 0.25)
		var healed := rig.hp
		_check(rig.workshop_used and absf(healed - rig.hp_max * 0.40) < 1.0, "Mobile Workshop: under 30%% HP, 15%% comes back (%.0f of %.0f)" % [healed, rig.hp_max])
		rig.take_damage(rig.hp - rig.hp_max * 0.2)
		_check(rig.hp < rig.hp_max * 0.25, "only once per mission")
		rig.mods = []
		rig.armor_max = 100000.0
		rig.armor = rig.armor_max
		# OVERLOAD and Feedback Loop on an Outrider.
		var o := main.spawn_outrider(rig.global_position + Vector2(160, 0))
		o.set("player", null)
		mark.o = o
		(o.get("_heat") as Array)[0] = 0.8
		_check(bool(o.call("is_overloaded_gun")), "a heat gun at 80% is OVERLOADed")
	if frame == 5:
		var o: Node = mark.o
		(o.get("_heat") as Array)[0] = 0.8
		rig.set_crew([_member("spotter", "jammer", ["sp_feedback_loop"])])
		rig.static_burst(400.0, 5.0, 1.0)
		_check(bool(o.call("is_overheated", 0)), "Feedback Loop: Static Burst locks an OVERLOADed gun hot")
		(o.get("_overheated") as Array)[0] = false
		(o.get("_heat") as Array)[0] = 0.5
	if frame == 8:
		var o: Node = mark.o
		var bar: Node = o.get("_status_bar")
		_check(bar.visible and absf(float(bar.get("heat")) - float(o.call("heat_of", 0))) < 0.1, "the Outrider's heat shows under it")
		o.call("take_damage", 1000000.0)
		# Overload Coil: a chained round with 3 jumps hits three more targets.
		var at := rig.global_position + Vector2(0, -260)
		var first := main.zombies.spawn_at(at, "tank")
		mark.extra = []
		for k in 4:
			mark.extra.append(main.zombies.spawn_at(at + Vector2(60 + 50 * k, 0), "tank"))
		mark.chained = main.bullets.chained
		main.bullets.fire(rig.global_position + Vector2(0, -60), Vector2(0, -1500), 5.0, 0, 0, "shock", 0.0, true, 0.0, rig, false, T.OVERLOAD_COIL_JUMPS)
		mark.first = first
	if frame == 20:
		var n := main.bullets.chained - int(mark.chained)
		_check(n == T.OVERLOAD_COIL_JUMPS, "Overload Coil: the chain hits 2 extra targets (%d jumps)" % n)
		_finish()
	return false


func _check(ok: bool, what: String) -> void:
	print(("  PASS  " if ok else "  FAIL  ") + what)
	if not ok:
		failures.append(what)


func _finish() -> void:
	if failures.is_empty():
		print("KEYWORDS TEST PASSED")
		quit(0)
	else:
		print("KEYWORDS TEST FAILED: %s" % ", ".join(failures))
		quit(1)
