extends SceneTree
## Headless test for the reworked Scrapper (§14) and the Scrapper Gunner: the
## numbers and Comms text (Gunner from 4 skulls in half the Scrapper jobs),
## your Oil Slick and Spike Strip Droppers (enemies only: your hazards never
## hurt you), the unarmed Scrapper weaving ahead and laying oil and spikes
## (spikes slow rigs, hurt and slow zombies; at most 6 hazards), its oil set
## alight, the Scrapper Gunner's turret and mines, and both rigs' salvage.
##
## Run:  godot --headless --fixed-fps 60 --path . -s res://tests/scrapper_test.gd

const Mission := preload("res://scripts/mission.gd")
const Missions := preload("res://scripts/missions.gd")
const ScrapperRig := preload("res://scripts/scrapper_rig.gd")
const ScrapperGunnerRig := preload("res://scripts/scrapper_gunner_rig.gd")
const StatusBars := preload("res://scripts/status_bars.gd")
const Parts := preload("res://scripts/parts.gd")
const Loadout := preload("res://scripts/loadout.gd")
const T := preload("res://scripts/tuning.gd")

const SPOT := Vector2(1600, 1200)
const DROPPER_BUILD := {
	"chassis": "courier_frame", "engine": "junk_v6", "drive": "street_wheels",
	"armor_front": "scrap_plating", "armor_sides": "scrap_plating", "armor_rear": "scrap_plating",
	"weapons": ["pintle_turret"], "utility": ["oil_slick", "spike_strip"], "internal": [],
}

var main: Mission
var frame := 0
var step := 0
var failures: Array[String] = []
var s: ScrapperRig
var mark := {}


func _initialize() -> void:
	seed(20261106)
	var profile: Node = root.get_node("Profile")
	profile.set("persist", false)
	profile.call("new_game")
	_check_tables()
	main = (load("res://scenes/mission.tscn") as PackedScene).instantiate() as Mission
	main.mission_override = Missions.make("clear", 1, 7)
	main.auto_spawn_specials = false
	main.always_drop_schematic = true
	root.add_child(main)


func _process(_delta: float) -> bool:
	frame += 1
	var rig := main.vehicle
	match step:
		0:  # Your droppers: they only catch enemies
			if frame == 3:
				main.zombies.spawn_budget = 0
				main.zombies.clear_all()
				for b in main.barrels:
					b.deactivate()
				main.apply_rig(Loadout.build(DROPPER_BUILD))
				rig.set_crew(main.profile.seated_crew().filter(func(m: Dictionary) -> bool: return m.role == "driver"))
				rig.armor_max = 100000.0
				rig.armor = rig.armor_max
				_park(SPOT)
				_check(main.hud.ability_count() == 2, "both droppers get a HUD button")
				_check(main.use_ability(0) and main.hazards.oil_count() == 1, "Oil Slick Dropper pours a slick behind you")
				_check(main.use_ability(1) and main.hazards.spike_count() == 1, "Spike Strip Dropper lays a strip behind you")
				# The strip runs across the road behind you; the slick is just past it.
				var back := -Vector2.RIGHT.rotated(rig.rotation)
				var strip := SPOT + back * (rig.body_len * 0.5 + 24.0)
				var across := back.orthogonal() * 54.0
				var z := main.zombies.spawn_at(strip + across, "brute")
				z.fill_status(StatusBars.SHOCK)   # stunned, so it stays on the strip
				mark.z = z
				var enemy := main.spawn_outrider(strip - across)
				enemy.player = null   # parked on your hazards
				mark.enemy = enemy
				rig.global_position = strip   # your rig sits on its own oil and spikes
				rig.velocity = Vector2.ZERO
			if frame == 6:
				var z: Node = mark.z
				_check(bool(z.get("oiled")) and bool(z.get("spiked")), "zombies are caught by your oil and spikes")
				mark.zhp = z.get("hp")
			if frame == 66:
				var z: Node = mark.z
				_check(float(z.get("hp")) < float(mark.zhp) - 5.0, "spikes hurt zombies (%d a second)" % int(T.SPIKE_ZOMBIE_DPS))
				_check((mark.enemy as Node).get("spike_left") > 0.0, "enemy rigs on your spikes are slowed")
				_check(rig.spike_left == 0.0, "your own spikes never slow you")
			if frame == 300:
				_check(rig.traction == 1.0 and rig.status.build[StatusBars.SLIME] == 0.0, "your own oil never makes you slide")
				_check(is_equal_approx((mark.enemy as Node).get("traction"), T.SLIME_GRIP), "enemy rigs slide on your oil")
				main.zombies.clear_all()
				main.hazards.clear()
				(mark.enemy as Node).call("take_damage", 100000.0)
				main.apply_rig(Loadout.build(Parts.STARTER_LOADOUT))
				rig.set_crew(main.profile.seated_crew())
				rig.armor_max = 100000.0
				rig.armor = rig.armor_max
				_park(SPOT)
				_next()
		1:  # The unarmed Scrapper weaves ahead and lays hazards
			if frame == 1:
				s = main.spawn_scrapper(SPOT + Vector2(700, 0)) as ScrapperRig
				_check(s != null and s == main.scrapper and not s is ScrapperGunnerRig, "spawn_scrapper sends in a Scrapper")
				_check(not s.has_weapon(), "the Scrapper is unarmed (§14)")
				mark.shots = main.bullets.enemy_shots
			if frame == 420:
				var d := s.global_position.distance_to(rig.global_position)
				_check(d > T.SCRAPPER_RANGE_MIN - 100.0 and d < T.SCRAPPER_RANGE_MAX + 250.0, "it works in close, 250-400 px out (%.0f px)" % d)
				_check(main.bullets.enemy_shots == int(mark.shots), "it never shoots")
				_check(s.traps_dropped >= 2, "it lays hazards on its own (%d in 7 s, one every %d s)" % [s.traps_dropped, int(T.SCRAPPER_TRAP_EVERY)])
				_next()
		2:  # Its hazards
			if frame == 1:
				main.hazards.clear()
				s.laid.clear()
				s.next_trap = "oil"
				s.set("_cycle_i", 0)
				var oil0 := main.hazards.oil_count()
				_check(s.drop_trap() == "oil" and main.hazards.oil_count() == oil0 + 1, "hazard 1: oil")
				var sp0 := main.hazards.spike_count()
				_check(s.drop_trap() == "spikes" and main.hazards.spike_count() == sp0 + 1, "hazard 2: a spike strip (they alternate)")
				for i in 8:
					s.global_position += Vector2(0, 40)
					s.drop_trap()
				_check(s.laid.size() == T.SCRAPPER_MAX_HAZARDS and main.hazards.oil_count() + main.hazards.spike_count() == T.SCRAPPER_MAX_HAZARDS,
					"at most %d of its hazards at once (oldest go first)" % T.SCRAPPER_MAX_HAZARDS)
				main.hazards.clear()
				# Its spikes slow your rig.
				s.global_position = SPOT + Vector2(0, 800)
				s.velocity = Vector2.ZERO
				main.hazards.add_spike(SPOT + Vector2(-60, -200), SPOT + Vector2(60, -200), 15.0, s.team)
				_park(SPOT + Vector2(0, -120))
				rig.rotation = -PI / 2.0
				main.hud.left_stick.output = Vector2.UP
			if frame == 30:
				_check(rig.spike_left > 0.0, "crossing its spike strip slows your rig (-%d%% for %d s)" % [roundi((1.0 - T.SPIKE_RIG_SPEED) * 100.0), int(T.SPIKE_RIG_TIME)])
				_park(SPOT)
				# Its oil, set alight, burns you (§14: enemy oil hurts you even when you lit it).
				main.hazards.add_oil(SPOT, 70.0, 12.0, s.team)
				main.hazards.add_fire(SPOT + Vector2(90, 0), 30.0, 6.0)
				rig.status.reset()
				rig.shield = 0.0
				rig.shield_max = 0.0
			if frame == 90:
				_check(main.hazards.fire_at(SPOT, rig.team) and rig.status.build[StatusBars.FIRE] > 10.0, "its burning oil builds BURNING on your rig")
				main.hazards.clear()
				rig.status.reset()
				_next()
		3:  # Wreck the Scrapper; bring on the Gunner
			if frame == 1:
				mark.scrap = main.scrap
				mark.pickups = main.pickups.get_child_count()
				s.take_damage(100000.0)
			if frame == 3:
				var mult := main.profile.salvage_mult() * float(rig.crew_mod("scrap")) * float(rig.crew_mod("rig_scrap"))
				_check(is_equal_approx(main.scrap - float(mark.scrap), T.SCRAPPER_SCRAP * mult), "the Scrapper pays %d scrap" % T.SCRAPPER_SCRAP)
				var part: Dictionary = main.pickups.get_child(main.pickups.get_child_count() - 1).get("part")
				_check(Parts.DROP_POOLS.scrapper.has(str(part.get("id", ""))), "it drops hazard utilities and grip parts (%s)" % str(part.get("name", "")))
				var g := main.spawn_scrapper(SPOT + Vector2(-600, 0), true) as ScrapperGunnerRig
				_check(g != null and g == main.scrapper_gunner, "the Scrapper Gunner rolls in")
				_check(g.hp_max == 110.0 and g.facing_max[0] == 45.0 and g.has_weapon(), "Scrapper Gunner: HP 110, 45 a facing, a turret")
				mark.g = g
				mark.shots = main.bullets.enemy_shots
			if frame == 300:
				var g: ScrapperGunnerRig = mark.g
				_check(main.bullets.enemy_shots > int(mark.shots), "its turret plinks at you")
				g.laid.clear()
				g.next_trap = "mine"
				g.set("_cycle_i", 0)
				var mines0: int = main.enemy_mines.active_count()
				_check(g.drop_trap() == "mine" and main.enemy_mines.active_count() == mines0 + 1, "it lays a mine...")
				_check(g.drop_trap() == "oil" and g.drop_trap() == "spikes", "...then oil, then spikes, in turn")
				mark.scrap = main.scrap
				g.take_damage(100000.0)
			if frame == 302:
				var mult := main.profile.salvage_mult() * float(rig.crew_mod("scrap")) * float(rig.crew_mod("rig_scrap"))
				_check(is_equal_approx(main.scrap - float(mark.scrap), T.SCRAPPER_GUNNER_SCRAP * mult), "the Scrapper Gunner pays %d scrap" % T.SCRAPPER_GUNNER_SCRAP)
				_finish()
	return false


func _check_tables() -> void:
	var oil := Parts.get_part("oil_slick")
	_check(oil.name == "Oil Slick Dropper" and float(oil.power) == 15.0 and float(oil.weight) == 15.0 and float(oil.cooldown) == 14.0 and float(oil.oil_time) == 12.0,
		"Oil Slick Dropper: 15 power, 15 weight, every 14 s, a 12 s pool")
	var spikes := Parts.get_part("spike_strip")
	_check(spikes.rarity == "Uncommon" and float(spikes.power) == 15.0 and float(spikes.weight) == 15.0 and float(spikes.cooldown) == 12.0 and float(spikes.spike_time) == 15.0,
		"Spike Strip Dropper: Uncommon, 15 power, 15 weight, every 12 s, a 15 s strip")
	_check(Parts.DROP_POOLS.scrapper.has("spike_strip") and Parts.DROP_POOLS.scrapper.has("oil_slick") and Parts.DROP_POOLS.scrapper.has("mine_dropper"), "the Scrapper's pool has the hazard utilities")
	_check(float(T.SCRAPPER.fire_rate) == 0.0 and float(T.SCRAPPER.hp) == 90.0 and float(T.SCRAPPER.max_speed) == 580.0 and T.SCRAPPER_TRAP_EVERY == 3.0,
		"Scrapper: unarmed, HP 90, speed 580, a hazard every 3 s")
	_check(float(T.SCRAPPER_GUNNER.hp) == 110.0 and float(T.SCRAPPER_GUNNER.front) == 45.0 and T.SCRAPPER_GUNNER_TRAP_EVERY == 4.0 and T.SCRAPPER_GUNNER_SCRAP == 35,
		"Scrapper Gunner: HP 110, 45 a facing, a trap every 4 s, 35 scrap")
	var low := 0
	var high := 0
	for seed_i in 1000:
		if Missions.has_scrapper_gunner(Missions.make("clear", 3, seed_i)):
			low += 1
		if Missions.has_scrapper_gunner(Missions.make("clear", 4, seed_i)):
			high += 1
	_check(low == 0 and absf(high / 1000.0 - 0.5) < 0.05, "Scrapper Gunner: never below 4 skulls, half the Scrapper jobs from 4 (%.2f)" % (high / 1000.0))
	var with := 1
	for seed_i in range(1, 500):
		if Missions.has_scrapper_gunner(Missions.make("courier", 5, seed_i)):
			with = seed_i
			break
	_check(Missions.threats_text(Missions.make("courier", 5, with)).contains("1 Scrapper Gunner"), "the Comms card names the Scrapper Gunner")
	_check(Missions.threats_text(Missions.make("clear", 2, 7)).contains("1 Scrapper") and not Missions.threats_text(Missions.make("clear", 2, 7)).contains("Gunner"), "2 skulls: a plain Scrapper")


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
		print("SCRAPPER TEST PASSED")
		quit(0)
	else:
		print("SCRAPPER TEST FAILED: %s" % ", ".join(failures))
		quit(1)
