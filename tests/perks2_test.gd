extends SceneTree
## Headless test for implement-04: Tow Hitch and Wrecking Ball (mods), and
## the remaining Major / Signature crew perks.
##
## Run:  godot --headless --fixed-fps 60 --path . -s res://tests/perks2_test.gd

const Mission := preload("res://scripts/mission.gd")
const Missions := preload("res://scripts/missions.gd")
const Crew := preload("res://scripts/crew.gd")
const Tether := preload("res://scripts/tether.gd")
const BulletPool := preload("res://scripts/bullet_pool.gd")
const Pickup := preload("res://scripts/pickup.gd")
const T := preload("res://scripts/tuning.gd")

const SPOT := Vector2(1600, 1200)

var main: Mission
var profile: Node
var frame := 0
var step := 0
var failures: Array[String] = []
var mark := {}
var dice := RandomNumberGenerator.new()


func _initialize() -> void:
	seed(20261106)
	dice.seed = 11
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


## Seat one specialist with `perks` and fire their ability.
func _use(role: String, spec: String, perks: Array) -> bool:
	_seat([_m(role, spec, perks)])
	main.vehicle.crew[0].ready_in = 0.0
	return main.use_crew_ability(0)


func _hold(rig: Node2D, at := SPOT) -> void:
	rig.global_position = at
	rig.velocity = Vector2.ZERO
	rig.rotation = 0.0


func _fresh_rig() -> void:
	var rig := main.vehicle
	rig.mods = []
	rig.release_tether()
	rig.hp = rig.hp_max
	for i in 4:
		rig.facing_armor[i] = rig.facing_max[i]
	_seat([])
	rig.armor_max = 1000000.0   # a ram mustn't pop a tether in these tests
	rig.armor = rig.armor_max


func _process(_delta: float) -> bool:
	frame += 1
	var rig := main.vehicle
	match step:
		0:
			if frame == 2:
				main.zombies.spawn_budget = 0
				main.zombies.clear_all()
				for b in main.barrels:
					b.deactivate()
				_hold(rig)
				var o := main.spawn_outrider(SPOT + Vector2(900, 0))
				o.set_physics_process(false)
				mark.r = o
			if frame == 4:
				_hold(rig)
				_instant_checks()
			if frame == 8:
				var near: Array = []
				for d in rig.drones:
					if is_instance_valid(d):
						near.append(d)
				_check(main.bullets.shrapnel_splashes == int(mark.shrapnel) + 1, "Shrapnel: a burst's last round splashes 40 px")
				_check(near.size() > 0 and near.has(main.zombies.bait), "Bait Drones: zombies go for the drones")
				for d in near:
					d.queue_free()
				_next()
		1:  # Tow Hitch: ramming a rig shoves it 50% further
			if frame == 1:
				_fresh_rig()
				rig.mods = ["tow_hitch"]
				var o: CharacterBody2D = _rig_at(SPOT + Vector2(140, 0))
				o.rotation = 0.0
				mark.o = o
			if frame >= 2 and frame < 30:
				rig.velocity = Vector2(500, 0)
			if frame == 30:
				_check(int(rig.perk_hits.get("tow_hitch", 0)) >= 1, "Tow Hitch: a RAM shoves the rig 50% further")
				_park()
				_next()
		2:  # Wrecking Ball: a harpooned rig crashing over 250 px/s takes 2x, min 40
			if frame == 1:
				_fresh_rig()
				_hold(rig)
				rig.mods = ["wrecking_ball"]
				var o: CharacterBody2D = _rig_at(SPOT + Vector2(0, 200))
				o.rotation = 0.0
				rig.tether = Tether.new(rig, o, 500.0)
				o.wrecking_by = rig
				mark.o = o
				mark.total = float(o.hp) + float(o.call("_armor_total"))
			if frame >= 2 and frame < 20:
				_hold(rig)
				var o: CharacterBody2D = mark.o
				o.velocity = Vector2(0, -600)
				var pre := o.velocity
				o.move_and_slide()
				o.call("_resolve_collisions", pre)
			if frame == 20:
				var o: Node = mark.o
				var lost := float(mark.total) - float(o.get("hp")) - float(o.call("_armor_total"))
				print("  Wrecking Ball crash took %.0f" % lost)
				_check(int(rig.perk_hits.get("wrecking_ball", 0)) >= 1 and lost >= 40.0, "Wrecking Ball: a 600 px/s crash on the tether takes at least 40")
				rig.release_tether()
				_park()
				_next()
		3:  # Afterglow, Clean Lines: Tune-Up fades out over 4 s
			if frame == 1:
				_fresh_rig()
				_check(_use("mechanic", "gearhead", ["sp_afterglow", "sp_clean_lines"]), "Tune-Up fires")
			if frame == 3:
				_check(is_equal_approx(rig.status.drain_mult, 2.0), "Clean Lines: status drains 2x during Tune-Up")
			if frame == 60 * 9 + 30:   # Mythic Tune-Up is 9 s
				var s: float = rig.crew_speed
				_check(not rig.ability_active("tune_up") and rig.ability_active("tune_glow") and s > 1.0 and s < 1.0 + 0.15 * 1.5, "Afterglow: after Tune-Up the boost fades instead of stopping (speed x%.3f)" % s)
			if frame == 60 * 14:
				_check(not rig.ability_active("tune_glow") and is_equal_approx(rig.crew_speed, 1.0), "Afterglow: gone after 4 s")
				_next()
		4:  # Slingshot + Bulldog (Chain Drag)
			if frame == 1:
				_fresh_rig()
				_hold(rig)
				var o: CharacterBody2D = _rig_at(SPOT + Vector2(220, 0))
				mark.o = o
			if frame == 3:
				_check(_use("bruiser", "wrangler", ["sp_bulldog", "sp_slingshot"]) and rig.tether != null and is_equal_approx(rig.tether.reel_to, T.BULLDOG_REEL_TO), "Bulldog: Chain Drag reels to 120 px")
			if frame > 3 and frame < 120:
				rig.global_position = SPOT
				var o: CharacterBody2D = mark.o
				var pre := o.velocity
				o.move_and_slide()
				o.call("_resolve_collisions", pre)
				rig.call("_tick_tether", 1.0 / 60.0)
			if frame == 120:
				_check(int(rig.perk_hits.get("sp_bulldog", 0)) == 1, "Bulldog: a free RAM once it's reeled in")
				rig.velocity = Vector2(400, 0)
				if rig.tether == null:   # the free RAM can pop the chain; put it back for the release
					rig.tether = Tether.new(rig, mark.o, 260.0)
				var a: Dictionary = rig._active.chain_drag
				rig.call("_on_ability_ended", "chain_drag", a)
				var o: Node = mark.o
				_check(rig.tether == null and float(o.get("slung_left")) > 0.0, "Slingshot: releasing at speed flings the rig")
				_park()
				_next()
		5:  # Tail Swipe: the rear rams while the Bootleg Turn swings
			if frame == 1:
				_fresh_rig()
				_hold(rig)
				var o: CharacterBody2D = _rig_at(SPOT + Vector2(-80, 0))
				mark.o = o
				rig.drive_input = Vector2.ZERO
			if frame == 3:
				rig.rotation = PI   # facing away, so the swing brings the rear round
				_check(_use("driver", "bootlegger", ["sp_tail_swipe"]), "Bootleg Turn fires")
			if frame > 3 and frame < 12:
				rig.global_position = SPOT
			if frame == 12:
				_check(rig.tail_swipes >= 1, "Tail Swipe: the rear hits as a RAM while swinging")
				_park()
				_next()
		6:  # Afterburn: a burning trail during Floor It
			if frame == 1:
				_fresh_rig()
				_hold(rig)
				var o: CharacterBody2D = _rig_at(SPOT + Vector2(-60, 0))
				mark.o = o
			if frame == 3:
				_check(_use("driver", "speedster", ["sp_afterburn"]), "Floor It fires")
			if frame == 30:
				var o: Node = mark.o
				_check(rig.afterburn_trail.size() > 0 and (float(o.status.build[1]) > 0.0 or bool(o.call("is_status", 1))), "Afterburn: the trail builds BURNING on a rig in it")
				_park()
				_next()
		7:  # Counterweight + Juggernaut: a braced RAM hits 25% harder, doesn't slow you, flings the rig
			if frame == 1:
				_fresh_rig()
				_hold(rig)
				_rig_at(SPOT + Vector2(140, 0))
			if frame == 3:
				_check(_use("bruiser", "bracer", ["sp_counterweight", "sp_juggernaut"]), "Brace fires")
			if frame > 3 and frame < 30:
				rig.velocity = Vector2(500, 0)
				var o: CharacterBody2D = mark.r
				if frame == 4:
					mark.ov = 0.0
				mark.ov = maxf(float(mark.ov), o.velocity.length())
			if frame == 30:
				_check(int(rig.perk_hits.get("sp_counterweight", 0)) >= 1, "Counterweight: braced RAMs hit 25% harder")
				_check(int(rig.perk_hits.get("sp_juggernaut", 0)) >= 1 and float(mark.ov) > 100.0, "Juggernaut: the rammed rig goes flying (%.0f px/s)" % float(mark.ov))
				_park()
				_next()
		8:  # Arc Feedback, real rounds: a Gunner Rig shoots your shield during Power Divert
			if frame == 1:
				_fresh_rig()
				_hold(rig)
				_park()
				var g := main.spawn_gunner(SPOT + Vector2(450, 0), false)
				mark.g = g
			if frame == 3:
				_check(_use("engineer", "conduit", ["sp_arc_feedback"]) and rig.shield_max > 0.0, "Power Divert fires (shield up)")
				mark.af = rig.arc_feedbacks
			if frame > 1 and frame < 400:
				_hold(rig)
				rig.shield = rig.shield_max   # every round lands on the shield
				var g: Node2D = mark.g
				g.global_position = SPOT + Vector2(450, 0)
				(g as CharacterBody2D).velocity = Vector2.ZERO
			if frame == 400:
				var g: Node = mark.g
				var n: int = rig.arc_feedbacks - int(mark.af)
				print("  Arc Feedback: %d shocks, gunner shock %.0f / triggered %s" % [n, float(g.status.build[0]), g.call("is_status", 0)])
				_check(n >= 1 and (float(g.status.build[0]) > 0.0 or bool(g.call("is_status", 0))), "Arc Feedback: the Gunner Rig's rounds on your shield shock it")
				_check(n <= int(397.0 / 60.0 / T.ARC_FEEDBACK_CD) + 1, "Arc Feedback: at most once per 0.5 s per attacker")
				g.get_parent().remove_child(g)   # out of the arena, so later chains can't pick it
				_next()
		9:  # Racing Line, real near-misses from enemy rounds
			if frame == 1:
				_fresh_rig()
				_hold(rig)
				_check(_use("driver", "wheelman", ["sp_racing_line"]), "Hard Line fires")
				mark.nm = rig.near_misses
				var side := float(rig.body_wid) * 0.5 + 20.0
				# One round skims past 20 px off the hull, one goes by 300 px away.
				main.bullets.fire(SPOT + Vector2(-500, side), Vector2(1500, 0), 1.0, BulletPool.TEAM_ENEMY, 0, "", 2.0)
				main.bullets.fire(SPOT + Vector2(-500, 300), Vector2(1500, 0), 1.0, BulletPool.TEAM_ENEMY, 0, "", 2.0)
			if frame > 1:
				_hold(rig)
			if frame == 2:
				mark.left = float(rig._active.hard_line.left)
			if frame == 40:
				var gained := float(rig._active.hard_line.left) - (float(mark.left) - 38.0 / 60.0)
				_check(rig.near_misses == int(mark.nm) + 1 and absf(gained - 0.5) < 0.05, "Racing Line: a round skimming past adds 0.5 s; a distant one doesn't (+%.2f s)" % gained)
				var side := float(rig.body_wid) * 0.5 + 20.0
				for k in 10:
					main.bullets.fire(SPOT + Vector2(-300 - k * 50, side), Vector2(1500, 0), 1.0, BulletPool.TEAM_ENEMY, 0, "", 2.0)
			if frame == 140:
				print("  Racing Line: near-misses %d, added %.2f s" % [rig.near_misses - int(mark.nm), rig._racing_added])
				_check(rig.near_misses == int(mark.nm) + 11 and is_equal_approx(rig._racing_added, T.RACING_LINE_CAP), "Racing Line: 11 near-misses cap at +3 s")
				_next()
		10, 11:  # Immovable Line, a real Tank charge: first without the perk (it shoves), then with it
			var perk := step == 11
			if frame == 1:
				_fresh_rig()
				_hold(rig)
				main.zombies.clear_all()
				_check(_use("driver", "wheelman", ["sp_immovable_line"] if perk else []), "Hard Line fires")
				mark.tank = main.zombies.spawn_at(SPOT + Vector2(300, 0), "tank")
				mark.shove = 0.0
			if frame > 1:
				mark.shove = maxf(float(mark.shove), rig.velocity.length())
				_hold(rig)
			var tank: Node = mark.tank
			if frame > 1 and int(tank.get("charge_hits")) > 0 and not mark.has("hit_at"):
				mark.hit_at = frame
			if (mark.has("hit_at") and frame == int(mark.hit_at) + 3) or frame == 300:
				print("  Tank charge (%s): hits %d, rig speed after %.0f" % ["Immovable Line" if perk else "no perk", int(tank.get("charge_hits")), float(mark.shove)])
				if perk:
					_check(int(tank.get("charge_hits")) >= 1 and float(mark.shove) < 100.0, "Immovable Line: a Tank's charge lands but doesn't shove you")
				else:
					_check(int(tank.get("charge_hits")) >= 1 and float(mark.shove) > T.TANK_SHOVE * 0.5, "(control) without it, the Tank's charge shoves you")
				mark.erase("hit_at")
				main.zombies.clear_all()
				_next()
		12:  # Slingshot, a real wall crash: release at speed flings the rig into the west wall
			if frame == 1:
				_fresh_rig()
				# Under the north boundary wall at x 1600 (clear ground; the west edge has props).
				_hold(rig, Vector2(SPOT.x, 520))
				var o: CharacterBody2D = _rig_at(Vector2(SPOT.x, 300))
				o.rotation = -PI / 2.0
			if frame == 3:
				_check(_use("bruiser", "wrangler", ["sp_slingshot"]) and rig.tether != null, "Chain Drag hooks the rig")
				mark.hits = int((mark.r as Node).get("slung_hits"))
				mark.hp = float((mark.r as Node).get("hp")) + float((mark.r as Node).call("_armor_total"))
			if frame == 3:
				# The rig itself is parked (physics off) but its crew and tether run
				# through the real code, so the chain lets go while it reads 400 px/s.
				rig.set_physics_process(false)
			if frame > 3:
				rig.global_position = Vector2(SPOT.x, 520)
				rig.velocity = Vector2(0, -400)   # driving hard at the wall when the chain lets go
				rig.call("_tick_crew", 1.0 / 60.0)
				rig.call("_tick_perks", 1.0 / 60.0)
				rig.call("_tick_tether", 1.0 / 60.0)
				var o: CharacterBody2D = mark.r
				if rig.ability_active("chain_drag"):
					o.global_position = Vector2(SPOT.x, 300)   # held on the chain, clear of the wall
					o.velocity = Vector2.ZERO
				var pre := o.velocity
				o.move_and_slide()
				o.call("_resolve_collisions", pre)
				o.call("_tick_perks", 1.0 / 60.0)
			if frame == 3 + 60 * 6:
				var o: Node = mark.r
				var lost := float(mark.hp) - float(o.get("hp")) - float(o.call("_armor_total"))
				print("  Slingshot: wall RAMs %d, damage %.0f" % [int(o.get("slung_hits")) - int(mark.hits), lost])
				_check(int(o.get("slung_hits")) == int(mark.hits) + 1 and lost > 0.0, "Slingshot: flung at the wall, the crash lands as a RAM")
				rig.set_physics_process(true)
				_park()
				_next()
		13:  # Copycat: drones fire your gun's damage type
			if frame == 1:
				_fresh_rig()
				_hold(rig)
				_rig_at(SPOT + Vector2(200, 0))
				mark.dt = str(rig.gun_stats[0].get("dtype", ""))
				rig.gun_stats[0].dtype = "acid"
			if frame == 3:
				_check(_use("engineer", "tinkerer", ["sp_copycat"]), "Scrap Drones fire")
				mark.th = main.bullets.typed_hits
				mark.acid = float((mark.r as Node).status.build[2])
			if frame > 3:
				_hold(rig)
			if frame == 90:
				var o: Node = mark.r
				var ok := true
				for d in rig.drones:
					ok = ok and is_instance_valid(d) and str(d.dtype) == "acid"
				print("  Copycat: typed hits +%d, target acid %.1f" % [main.bullets.typed_hits - int(mark.th), float(o.status.build[2])])
				_check(ok and main.bullets.typed_hits > int(mark.th) and (float(o.status.build[2]) > float(mark.acid) or bool(o.call("is_status", 2))), "Copycat: drones fire acid rounds like your gun, building CORRODED")
				rig.gun_stats[0].dtype = str(mark.dt)
				_park()
				_finish()
	return false


## Checks that need no simulation time.
func _instant_checks() -> void:
	var rig := main.vehicle
	var o: CharacterBody2D = _rig_at(SPOT + Vector2(900, 0))

	# Insulated Feed: shield status bonus doubled during Power Divert.
	_check(_use("engineer", "conduit", ["sp_insulated_feed", "sp_arc_feedback"]), "Power Divert fires")
	rig.shield = maxf(rig.shield, 1.0)
	var base := float(rig.resist[0])
	_check(is_equal_approx(rig.resistance(0), minf(base + T.STATUS_SHIELD_RESIST * 2.0, 100.0)), "Insulated Feed: the shield's status bonus doubles")
	# Neurotoxin.
	_seat([_m("medic", "poisoner", ["sp_neurotoxin"])])
	o.fill_status(3)
	rig.call("_tick_perks", 0.016)
	_check(float(o.neuro_left) > 0.0, "Neurotoxin: TOXIC rigs are slowed")
	# Fresh Weld.
	rig.facing_armor[0] = rig.facing_max[0] * 0.5
	_seat([_m("mechanic", "patcher", ["sp_fresh_weld"])])
	rig.facing_armor[0] = rig.facing_max[0] * 0.5
	var fw_ok := main.use_crew_ability(0)
	_check(fw_ok and rig._fresh_weld_facing == 0 and rig._fresh_weld_left > 3.9, "Fresh Weld: the repaired facing is marked for 4 s")
	rig.shield = 0.0
	var a0: float = rig.facing_armor[0]
	rig.take_damage(10.0, Vector2.RIGHT)
	var lost := a0 - float(rig.facing_armor[0])
	_check(lost < 10.0 * float(rig.crew_mod("taken")) * 0.81, "Fresh Weld: it takes -20%% (%.1f of 10)" % lost)
	# Clean Bandage: injured crew rest half the days (rounded up).
	var pa: Dictionary = profile.call("_add_crew", _m("gunner", "", []))
	var pb: Dictionary = profile.call("_add_crew", _m("gunner", "", []))
	for pm: Dictionary in profile.crew:
		pm.seated = false
	pa.seated = true
	profile.call("bank_crew", 1, [int(pa.id)], false, false)
	pa.seated = false
	pb.seated = true
	profile.call("bank_crew", 1, [int(pb.id)], false, true)
	pb.seated = false
	print("  rest days: plain %d, Clean Bandage %d" % [int(pa.rest), int(pb.rest)])
	_check(int(pa.rest) == T.CREW_REST_DAYS and int(pb.rest) == maxi(ceili(T.CREW_REST_DAYS / 2.0), 1), "Clean Bandage: half the rest days")
	_seat([_m("medic", "field_medic", ["sp_clean_bandage"])])
	_check(main.vehicle.has_sp("sp_clean_bandage"), "Clean Bandage: the mission passes it to the bank")
	# Strip Mine.
	_seat([_m("scavenger", "salvager", ["sp_strip_mine", "sp_safe_deposit"])])
	var s0: float = main.scrap
	rig.armor_dealt(80.0)
	main.call("_process", 0.016)
	_check(is_equal_approx(main.scrap - s0, 2.0), "Strip Mine: 1 scrap per 40 armor dealt")
	rig.armor_dealt(100000.0)
	_check(is_equal_approx(rig.strip_total, T.STRIP_MINE_CAP), "Strip Mine: capped at 25")
	# Safe Deposit: Gold Rush's share is tracked for a wreck.
	rig.crew[0].ready_in = 0.0
	main.use_crew_ability(0)
	main.call("_add_kill", 10)
	_check(main.gold_rush_scrap > 0.0, "Safe Deposit: Gold Rush scrap is set aside (%.1f)" % main.gold_rush_scrap)
	# Full Recovery.
	_seat([_m("medic", "field_medic", ["sp_full_recovery"]), _m("driver", "", [])])
	rig.injure_crew(1)
	_check(main.injured_crew_ids().size() == 1 and main.call("_rest_ids").is_empty(), "Full Recovery: injured crew need no rest days")
	# Flare: Flashbang, Magnesium, Pinned.
	_seat([_m("spotter", "scout", ["sp_flashbang", "sp_magnesium", "sp_pinned"])])
	var z: Node2D = main.zombies.spawn_at(SPOT + Vector2(150, 0))
	var h: Node2D = main.spawn_hunter(SPOT + Vector2(0, 200))
	_check(main.use_crew_ability(0) and z.status.active(0), "Flashbang: zombies inside are stunned")
	main.call("_tick_flare", 0.5)
	_check(float(z.status.build[1]) > 0.0 or z.status.active(1), "Magnesium: the Flare builds BURNING")
	_check(float(h.get("pinned_left")) > 0.0, "Pinned: Hunters inside can't pounce")
	h.call("deactivate")
	# Contagion.
	_seat([_m("medic", "poisoner", ["sp_contagion"])])
	main.call("_process", 0.016)
	var z2: Node2D = main.zombies.spawn_at(SPOT + Vector2(200, 0))
	z.fill_status(3)
	z.call("take_hit", 99999.0, Vector2.ZERO, "shot", "")
	_check(main.zombies.contagion_bursts == 1 and (float(z2.status.build[3]) > 0.0 or z2.status.active(3)), "Contagion: a TOXIC zombie bursts and spreads it")
	main.zombies.clear_all()
	# Shockwave Clear Out.
	_check(_use("bruiser", "breaker", ["sp_clear_out"]) and int(rig.perk_hits.get("sp_clear_out", 0)) == 1, "Clear Out: the Shockwave hurls zombies")
	# Chain Reaction.
	_check(_use("gunner", "demolisher", ["sp_chain_reaction", "sp_shrapnel"]), "Cook Off fires")
	main.call("_chain_reaction", SPOT)
	_check(main.chain_reactions == 1, "Chain Reaction: a barrel during Cook Off lights oil 200 px out")
	# Shrapnel: a flagged round splashes.
	var sp: int = main.bullets.shrapnel_splashes
	main.bullets.fire(o.global_position - Vector2(60, 0), Vector2(900, 0), 5.0, BulletPool.TEAM_PLAYER, 0, "", 0.0, false, 0.0, rig, true)
	mark.shrapnel = sp
	# Magpie: Second Look, Shrapnel Storm, Snatch.
	_seat([_m("scavenger", "magpie", ["sp_second_look", "sp_shrapnel_storm", "sp_snatch"])])
	main.always_drop_schematic = false
	var crate := Pickup.new()
	crate.scrap_value = 10
	crate.position = SPOT + Vector2(300, 0)
	main.pickups.add_child(crate)
	main._rig_crate[o] = crate
	main.always_drop_schematic = true
	var looks: int = main.second_looks
	_check(main.use_crew_ability(0) and main.second_looks == looks + 1 and main.shrapnel_storms >= 1, "Second Look rerolls a pulled rig crate; Shrapnel Storm hits where it lay")
	main.always_drop_schematic = false
	var crate2 := Pickup.new()
	crate2.scrap_value = 10
	crate2.position = SPOT + Vector2(3000, 0)
	main.pickups.add_child(crate2)
	main._rig_crate[o] = crate2
	main.call("_on_rig_revived", o)
	_check(main.snatched == 1 and not crate2.is_inside_tree(), "Snatch: the crate is yours before a revive")
	# Tinkerer: Bait Drones, Copycat.
	_check(_use("engineer", "tinkerer", ["sp_bait_drones", "sp_copycat"]) and rig.drones.size() == 2 and rig.drones[0].bait, "Scrap Drones with Bait Drones")
	o.global_position = SPOT + Vector2(900, 0)


## The test's one enemy rig, moved to `at`, repaired, statuses cleared.
func _rig_at(at: Vector2) -> CharacterBody2D:
	var o: CharacterBody2D = mark.r
	o.global_position = at
	o.rotation = 0.0
	o.velocity = Vector2.ZERO
	o.set("hp", float(o.get("hp_max")))
	o.set("facing_armor", PackedFloat32Array([100000.0, 100000.0, 100000.0, 100000.0]))   # can't wreck mid-test
	o.status.reset()
	o.set("slung_left", 0.0)
	return o


func _park() -> void:
	_rig_at(SPOT + Vector2(900, 0))


func _next() -> void:
	frame = 0
	step += 1


func _check(ok: bool, what: String) -> void:
	if what == "":
		return
	print(("  PASS  " if ok else "  FAIL  ") + what)
	if not ok:
		failures.append(what)


func _finish() -> void:
	if failures.is_empty():
		print("PERKS2 TEST PASSED")
		quit(0)
	else:
		print("PERKS2 TEST FAILED: %s" % ", ".join(failures))
		quit(1)
