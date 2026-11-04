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
		main.zombies.clear_all()
		# Keyword popups: one per keyword per rig every 0.5 s, symbols on screen.
		var shown: int = main.keywords.shown
		rig._kw_last = {}   # the DRIFT earlier in this test is still inside its throttle
		rig.keyword_pop("DRIFT")
		rig.keyword_pop("DRIFT")
		_check(main.keywords.shown == shown + 1 and main.keywords.active_count() >= 1, "a DRIFT pops its symbol, once per 0.5 s")
		rig.fill_status(1)
		_check(int(main.keywords.counts.get("BURNING", 0)) >= 1, "a status starting pops its symbol (BURNING)")
		rig.status.reset()
		for k in 8:
			main.keywords.pop("RAM", rig.global_position)
		_check(main.keywords.active_count() <= T.KEYWORD_MAX_ON_SCREEN, "never more than 6 on screen")
		# Demolisher's Cook Off: barrels you set off with it blow 50% harder.
		var barrel: Node = main.barrels[0]
		barrel.call("place", rig.global_position + Vector2(0, -200), "explosive")
		rig._active["cook_off"] = {"left": 5.0}
		rig.player_pre_hit(barrel, 10.0, "", 0)
		_check(is_equal_approx(float(barrel.get("blast_mult")), T.COOK_OFF_BARREL_MULT), "Cook Off: a barrel you shoot blows 50% harder")
		rig._active.erase("cook_off")
		barrel.call("deactivate")
		# Outrider: badly hurt with a Patcher alive, it runs to the Patcher.
		var p := main.spawn_patcher(rig.global_position + Vector2(-700, -300))
		var o2: Node2D = (load("res://scripts/enemy_rig.gd") as GDScript).new()   # the job's one pooled Outrider is spent
		o2.set("player", rig)
		o2.set("bullets", main.bullets)
		o2.set("fx", main.fx)
		o2.position = rig.global_position + Vector2(500, 300)
		main.rigs.add_child(o2)
		mark.p = p
		mark.o2 = o2
	if frame == 24:
		var o2: Node = mark.o2
		o2.set("hp", float(o2.get("hp_max")) * 0.2)
	if frame == 30:
		var o2: Node = mark.o2
		_check(int(o2.get("retreats")) == 1 and int(o2.get("mode")) == 8, "an Outrider at 20% HP runs to the Patcher")
		# Its break-off turn slides (a DRIFT): grip drops for half a second.
		o2.set("hp", float(o2.get("hp_max")))
		o2.set("mode", 3)
		o2.call("_start_break", (rig.global_position - (o2 as Node2D).global_position), true)
	if frame == 32:
		var o2: Node = mark.o2
		_check(float(o2.get("grip_mult")) < 1.0, "its break-off turn slides (grip cut)")
		o2.call("take_damage", 1000000.0)
		(mark.p as Node).call("take_damage", 1000000.0)
		# Bulwark: screens a Gunner Rig you're closer to.
		var g := main.spawn_gunner(rig.global_position + Vector2(0, 250))
		g.set("player", null)
		g.velocity = Vector2.ZERO
		var bw := main.spawn_bulwark(rig.global_position + Vector2(0, 600))
		mark.bw = bw
	if frame == 40:
		var bw: Node = mark.bw
		_check(int(bw.get("screens")) >= 1, "a Bulwark body-blocks for a Gunner Rig you're closer to")
		# Retrieve: the Sludger answers a danger step's rig call, not a timer.
		var seed := 0
		for k in 500:
			if Missions.has_sludger(Missions.make("retrieve", 5, 300 + k)):
				seed = 300 + k
				break
		main.queue_free()
		main = (load("res://scenes/mission.tscn") as PackedScene).instantiate() as Mission
		main.mission_override = Missions.make("retrieve", 5, seed)
		main.auto_spawn_specials = false
		root.add_child(main)
	if frame == 44:
		var timed := main._events.filter(func(e: Array) -> bool: return str(e[1]) == "sludger")
		_check(main._sludger_call and timed.is_empty(), "Retrieve: no timed Sludger; it waits for a danger step")
		main._set_danger(T.RETRIEVE_RIG_STEPS[0])
		var called := main._events.filter(func(e: Array) -> bool: return str(e[1]) == "sludger")
		_check(called.size() == 1 and not main._sludger_call, "the first rig call brings it")
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
