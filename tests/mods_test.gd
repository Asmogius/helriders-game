extends SceneTree
## Headless test for implement-02 (content proposal 01, approved 2026-11-03):
## part mods (tiers unlock at 3/7/11/14/18, attached per schematic, wired
## stat effects), tiered crew perks, the general Hunt elite, the Outrider's
## flank-and-break and the Bulwark's charge wind-up (with Art's hooks).
##
## Run:  godot --headless --fixed-fps 60 --path . -s res://tests/mods_test.gd

const Mission := preload("res://scripts/mission.gd")
const Missions := preload("res://scripts/missions.gd")
const Parts := preload("res://scripts/parts.gd")
const Mods := preload("res://scripts/mods.gd")
const Loadout := preload("res://scripts/loadout.gd")
const Crew := preload("res://scripts/crew.gd")
const Garage := preload("res://scripts/garage.gd")
const EnemyRig := preload("res://scripts/enemy_rig.gd")
const BulwarkRig := preload("res://scripts/bulwark_rig.gd")
const GunnerRig := preload("res://scripts/gunner_rig.gd")
const PatcherRig := preload("res://scripts/patcher_rig.gd")
const TorcherRig := preload("res://scripts/torcher_rig.gd")
const SludgerRig := preload("res://scripts/sludger_rig.gd")
const ScrapperRig := preload("res://scripts/scrapper_rig.gd")
const T := preload("res://scripts/tuning.gd")

const SPOT := Vector2(1600, 1200)
const BASE := {"chassis": "scrap_frame", "engine": "diesel_block", "drive": "street_wheels",
	"armor_front": "scrap_plating", "armor_sides": "scrap_plating", "armor_rear": "scrap_plating"}

var main: Mission
var profile: Node
var frame := 0
var step := 0
var failures: Array[String] = []
var mark := {}


func _initialize() -> void:
	seed(20261104)
	profile = root.get_node("Profile")
	profile.set("persist", false)
	profile.call("new_game")
	_check_mods()
	_check_perks()
	_check_elites()
	main = (load("res://scenes/mission.tscn") as PackedScene).instantiate() as Mission
	main.mission_override = Missions.make("clear", 1, 7)
	main.auto_spawn_specials = false
	main.push_override = 0
	root.add_child(main)


func _build(b: Dictionary, levels := {}) -> Dictionary:
	var d: Dictionary = BASE.duplicate()
	d.merge(b, true)
	return Loadout.build(d, levels)


func _check_mods() -> void:
	_check(T.MOD_UNLOCK.minor == 3 and T.MOD_UNLOCK.major == 7 and T.MOD_UNLOCK.signature == 11 and T.MOD_UNLOCK.major2 == 14 and T.MOD_UNLOCK.unique == 18, "mod tiers unlock at 3 / 7 / 11 / 14 / 18")
	for id: String in Mods.MODS:
		_check(not Parts.get_part(id).is_empty(), "mods attach to a real schematic: %s" % id)
	# Rarity caps the tiers: Common Minor only; Rare reaches Signature.
	_check(Mods.reachable("rivet_gun", Parts.max_level(Parts.get_part("rivet_gun"))).size() == 1, "Common Rivet Gun: Minor only")
	_check(Mods.reachable("arc_projector", Parts.max_level(Parts.get_part("arc_projector"))).size() == 3, "Rare Arc Projector reaches its Signature")
	_check(Mods.reachable("hauler_frame", Parts.max_level(Parts.get_part("hauler_frame"))).size() == 4, "Epic Hauler reaches its second Major at 14")
	# Locked below the level, on at it.
	_check(int(Parts.at_level(Parts.get_part("rivet_gun"), 2).pierce) == 1, "Countersunk locked at LV2")
	_check(int(Parts.at_level(Parts.get_part("rivet_gun"), 3).pierce) == 2, "Countersunk: +1 pierce at LV3")
	var h7 := Parts.at_level(Parts.get_part("harpoon"), 7)
	_check(int(h7.pierce) == 5 and is_equal_approx(float(h7.reel_speed), 130.0) and is_equal_approx(float(h7.reel_to), 150.0), "Harpoon: Barbed Tip pierce 5, Power Winch 130 px/s to 150 px")
	var m3 := Parts.at_level(Parts.get_part("mortar"), 3)
	_check(absf(float(m3.blast) - 108.0) < 0.01 or absf(float(m3.blast) - 108.0 * (1.0 + T.RESEARCH_GROWTH * 2)) < 0.01, "Mortar Heavy Charge: blast x1.2 (90 -> 108 before Research growth)")
	var p3 := Parts.at_level(Parts.get_part("shock_pulse"), 3)
	_check(is_equal_approx(float(p3.pulse_radius), 216.0), "Shock Pulse Wide Field: 180 -> 216 px")
	_check((Parts.at_level(Parts.get_part("shock_pulse"), 7).mods as Array).has("drain_arc"), "Shock Pulse Drain Arc unlocks at LV7")
	# Through the loadout.
	var sink := _build({"weapons": ["flame_sprayer"], "internal": ["ceramic_heat_sink"]}, {"ceramic_heat_sink": 7})
	_check(is_equal_approx(float(sink.weapons[0].lockout), 2.5 * 0.75) and is_equal_approx(float(sink.weapons[0].cool), 0.25 * 1.15), "Heat Sink Fins +15% cool, Vent Purge -25% lockout")
	var raider := _build({"chassis": "raider_frame", "weapons": ["rivet_gun"]}, {"raider_frame": 3})
	_check(is_equal_approx(float(raider.weapons[0].fire_rate), 4.0 * 1.05), "Raider Gun Rack: fixed weapons +5% fire rate")
	var hauler := _build({"chassis": "hauler_frame"}, {"hauler_frame": 14})
	_check((hauler.mods as Array).has("cargo_bay") and (hauler.mods as Array).has("mobile_workshop"), "the loadout lists unlocked flag mods (Hauler LV14)")
	var lob := _build({"weapons": ["acid_lobber"]}, {"acid_lobber": 3})
	_check(is_equal_approx(float(lob.weapons[0].puddle_add), 2.0), "Acid Lobber Sticky Glob: puddles +2 s")
	# Garage card: mods show while locked.
	var line := Garage.mod_line(Parts.at_level(Parts.get_part("flame_sprayer"), 1))
	_check(line.contains("WIDE NOZZLE LV3") and line.contains("NAPALM MIX LV7"), "garage card shows locked mods and their level (%s)" % line)
	_check(Garage.mod_line(Parts.at_level(Parts.get_part("flame_sprayer"), 3)).contains("WIDE NOZZLE  /"), "unlocked mods drop the level tag")


func _check_perks() -> void:
	var dice := RandomNumberGenerator.new()
	dice.seed = 5
	var m := Crew.make("gunner", "Mythic", dice, "demolisher")
	m.id = 77
	_check(Crew.next_tier(m) == "minor", "pick 1 is Minor")
	var offer := Crew.roll_perk_offer(m)
	var ok := offer.size() == 3
	for p in offer:
		ok = ok and (Crew.SHARED_PERKS.has(p) or (Crew.SPECIALTY_PERKS.demolisher.minor as Array).has(p))
	_check(ok, "a Minor pick offers 3 from the 2 Minor specialty perks + 4 shared (%s)" % ", ".join(offer))
	m.perks = ["sp_long_fuse", "sp_quick_strike"]
	_check(Crew.next_tier(m) == "major", "picks 3-4 are Major")
	var offer2 := Crew.roll_perk_offer(m)
	ok = true
	for p in offer2:
		ok = ok and not (Crew.SPECIALTY_PERKS.demolisher.minor as Array).has(p) and not m.perks.has(p)
	_check(ok, "no repeats and no off-tier specialty perks")
	var a := Crew.ability(m)
	var base := Crew.ability(Crew.make("gunner", "Mythic", dice, "demolisher"))
	_check(is_equal_approx(float(a.time), float(base.time) + 1.0) and is_equal_approx(float(a.cooldown), float(base.cooldown) * 0.85), "Long Fuse +1 s, Quick Strike -15% cooldown")
	m.perks = ["veteran", "endurance", "sp_chain_reaction", "tough"]
	_check(Crew.next_tier(m) == "signature", "picks 5-6 are Signature")
	var j := Crew.make("spotter", "Rare", dice, "jammer")
	j.perks = ["sp_wide_band", "sp_lingering_static"]
	var ja := Crew.ability(j)
	_check(is_equal_approx(float(ja.radius), 525.0) and is_equal_approx(float(ja.jam_add), 2.0), "Wide Band +75 px; Lingering Static +2 s")
	var g := Crew.make("gunner", "Rare", dice, "gunslinger")
	g.perks = ["sp_red_hot"]
	_check(is_equal_approx(float(Crew.ability(g).red_hot), 0.3), "Red Hot: 30% of each shot as fire")
	var welder := Crew.make("mechanic", "Rare", dice, "welder")
	_check(Crew.perk_pool(welder).has("reinforced"), "unreworked specialties keep their class perks")
	var old := Crew.make("gunner", "Rare", dice, "marksman")
	old.perks = ["steady_aim"]
	_check(Crew.perk_known(old).has("steady_aim"), "perks picked before tiers stay valid in saves")
	_check(Crew.perk_name("sp_opening_shot") == "Opening Shot", "tiered perks have names")


func _check_elites() -> void:
	for script: GDScript in [EnemyRig, BulwarkRig, GunnerRig, PatcherRig, TorcherRig, SludgerRig, ScrapperRig]:
		var r: Node = script.new()
		r.call("arm_for_skulls", 6)
		var hp := float(r.get("hp_max"))
		var f: PackedFloat32Array = (r.get("facing_max") as PackedFloat32Array).duplicate()
		var sh := float(r.get("shield_max"))
		var dmg := float(r.get("bullet_damage"))
		r.call("make_elite", "TEST", 2.0, 1.5)
		var nf: PackedFloat32Array = r.get("facing_max")
		var ok := is_equal_approx(float(r.get("hp_max")), hp * 2.0) and is_equal_approx(float(r.get("shield_max")), sh * 2.0) and is_equal_approx(float(r.get("bullet_damage")), dmg * 1.5)
		for i in 4:
			ok = ok and is_equal_approx(nf[i], f[i] * 2.0)
		ok = ok and bool(r.call("is_elite")) and is_equal_approx(float(r.get("hp")), float(r.get("hp_max")))
		var name := script.resource_path.get_file().get_basename()
		_check(ok, "%s can be an elite: HP, facings, shield x2, damage x1.5 (shield %d)" % [name, int(sh)])
		r.call("make_elite", "AGAIN", 2.0, 1.5)
		_check(is_equal_approx(float(r.get("hp_max")), hp * 2.0), "%s: elite multipliers don't stack" % name)
		r.free()


func _process(_delta: float) -> bool:
	frame += 1
	var rig := main.vehicle
	match step:
		0:  # Bulwark: lines up, winds up (signals for Art), charges
			if frame == 3:
				main.zombies.spawn_budget = 0
				main.zombies.clear_all()
				for b in main.barrels:
					b.deactivate()
				rig.armor_max = 1000000.0
				rig.armor = rig.armor_max
				rig.global_position = SPOT
				rig.velocity = Vector2.ZERO
				var b := main.spawn_bulwark(SPOT + Vector2(500, 0))
				b.rotation = PI
				mark.b = b
				mark.started = 0
				mark.ended = 0
				mark.seen = false
				mark.shots = main.bullets.enemy_shots
				b.windup_started.connect(func() -> void: mark.started = int(mark.started) + 1)
				b.windup_ended.connect(func() -> void: mark.ended = int(mark.ended) + 1)
			if frame > 3 and frame < 200:
				var b: Node = mark.b
				rig.global_position = SPOT
				rig.velocity = Vector2.ZERO
				if bool(b.call("is_winding_up")):
					mark.seen = true
					var pr := float(b.call("windup_progress"))
					var mm := root.get_node_or_null("MusicManager")
					if mm != null:
						mark.pitch_max = maxf(float(mark.get("pitch_max", 0.0)), float(mm.call("windup_pitch")))
					mark.prog_ok = bool(mark.get("prog_ok", true)) and pr >= 0.0 and pr <= 1.0
					if not mark.has("wind_speed"):
						mark.wind_speed = (b.get("velocity") as Vector2).length()
			if frame == 200:
				var b: Node = mark.b
				_check(int(b.get("windups")) >= 1 and bool(mark.seen), "lined up at 250-700 px, the Bulwark winds up first")
				_check(int(mark.started) >= 1 and int(mark.ended) >= 1, "windup_started / windup_ended fire for Art (%d / %d)" % [int(mark.started), int(mark.ended)])
				_check(bool(mark.get("prog_ok", false)), "windup_progress() stays in 0..1 while winding up")
				_check(main.bullets.enemy_shots > int(mark.shots), "its light gun fires while it lines up")
				_check(int(b.get("charges")) >= 1, "after the 0.5 s wind-up it charges")
				var mm := root.get_node("MusicManager")
				_check(int(mm.sfx_counts.get("bulwark_windup", 0)) >= 1, "the wind-up plays the engine roar on Effects")
				_check(float(mark.get("pitch_max", 0.0)) > float(T.SFX_WINDUP_PITCH[0]) + 0.1, "the roar's pitch rises with windup_progress() (%.2f)" % float(mark.get("pitch_max", 0.0)))
				print("  ram impacts heard: %d (rams: %d)" % [int(mm.sfx_counts.get("ram_impact", 0)), int(b.get("backoffs"))])
				_check(int(mm.sfx_counts.get("ram_impact", 0)) == int(b.get("backoffs")), "every ram on the player plays the ram impact")
				b.call("take_damage", 1000000.0, Vector2.ZERO, false, "")
				_next()
		1:  # Outrider: flanks into the side/rear arcs, strafes, breaks on overheat
			if frame == 2:
				rig.global_position = SPOT
				rig.rotation = 0.0
				var o := main.spawn_outrider(SPOT + Vector2(600, 200))
				mark.o = o
			if frame > 2:
				rig.global_position = SPOT
				rig.velocity = Vector2.ZERO
				rig.rotation = 0.0
			if frame == 600:
				var o: Node = mark.o
				_check(int(o.get("strafes")) >= 1, "the Outrider strafes from the player's side or rear (%d)" % int(o.get("strafes")))
				# Its guns lock hot: it breaks away.
				mark.b0 = int(o.get("breaks"))
				o.set("mode", EnemyRig.Mode.FLANK)
				(o.get("_heat") as Array)[0] = 1.0
				(o.get("_overheated") as Array)[0] = true
			if frame == 603:
				var o: Node = mark.o
				_check(int(o.get("breaks")) == int(mark.b0) + 1 and int(o.get("mode")) == EnemyRig.Mode.BREAK, "overheated, it breaks off 500-700 px")
				var to: Vector2 = o.get("_break_to")
				var d := to.distance_to(SPOT)
				_check(d >= 499.0 and d <= 701.0, "the break point is 500-700 px from the player (%d)" % int(d))
			if frame == 900:
				var o: Node = mark.o
				_check(int(o.get("mode")) != EnemyRig.Mode.BREAK, "then it re-flanks")
				mark.b1 = int(o.get("breaks"))
				o.set("mode", EnemyRig.Mode.FLANK)
				var fa: PackedFloat32Array = o.get("facing_armor")
				fa[2] = 0.0
				o.set("facing_armor", fa)
			if frame == 903:
				var o: Node = mark.o
				_check(int(o.get("breaks")) == int(mark.b1) + 1, "a stripped facing also makes it break")
				_finish()
	return false


func _next() -> void:
	frame = 0
	step += 1


func _check(ok: bool, what: String) -> void:
	print(("  PASS  " if ok else "  FAIL  ") + what)
	if not ok:
		failures.append(what)


func _finish() -> void:
	if failures.is_empty():
		print("MODS TEST PASSED")
		quit(0)
	else:
		print("MODS TEST FAILED: %s" % ", ".join(failures))
		quit(1)
