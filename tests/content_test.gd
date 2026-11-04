extends SceneTree
## Headless test for content proposal 01 (approved 2026-11-03): the four new
## weapons, four parts, two frames, three crew specialties, enemy ammo and
## heat, the Patcher's revive cap, keyword colors, the Torcher and Sludger,
## the Scrapper catching fire in its own lit oil, and Extract or Push.
##
## Run:  godot --headless --fixed-fps 60 --path . -s res://tests/content_test.gd

const Mission := preload("res://scripts/mission.gd")
const Missions := preload("res://scripts/missions.gd")
const Parts := preload("res://scripts/parts.gd")
const Loadout := preload("res://scripts/loadout.gd")
const Crew := preload("res://scripts/crew.gd")
const StatusBars := preload("res://scripts/status_bars.gd")
const BulletPool := preload("res://scripts/bullet_pool.gd")
const EnemyRig := preload("res://scripts/enemy_rig.gd")
const GunnerRig := preload("res://scripts/gunner_rig.gd")
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
	seed(20261103)
	profile = root.get_node("Profile")
	profile.set("persist", false)
	profile.call("new_game")
	_check_static()
	main = (load("res://scenes/mission.tscn") as PackedScene).instantiate() as Mission
	main.mission_override = Missions.make("clear", 1, 7)
	main.auto_spawn_specials = false
	main.push_override = 1
	root.add_child(main)


func _build(weapons: Array, internal: Array, utility: Array = []) -> Dictionary:
	var b: Dictionary = BASE.duplicate()
	b.weapons = weapons
	b.internal = internal
	b.utility = utility
	return Loadout.build(b)


func _hex(c: Color) -> String:
	return c.to_html(false).to_upper()


func _check_static() -> void:
	# Weapons: sustained DPS the garage's way.
	var rivet := Loadout.total_dps(_build(["rivet_gun"], []))
	var flame := Loadout.total_dps(_build(["flame_sprayer"], []))
	var lobber := Loadout.total_dps(_build(["acid_lobber"], []))
	var arc := Loadout.total_dps(_build(["arc_projector"], []))
	_check(absf(rivet - 38.8) < 0.5, "Rivet Gun: magazine 12 / 2.2 s, ~39 sustained (%.1f)" % rivet)
	_check(absf(flame - 24.6) < 0.5, "Flame Sprayer: heat 4 s / 2.5 s, ~25 sustained (%.1f)" % flame)
	_check(absf(lobber - 24.4) < 0.5, "Acid Lobber: magazine 5 / 2.5 s, ~24 sustained (%.1f)" % lobber)
	_check(absf(arc - 22.5) < 0.5, "Arc Projector: heat 5 s / 3 s, ~23 sustained before chains (%.1f)" % arc)
	var sink := _build(["flame_sprayer"], ["ceramic_heat_sink"])
	_check(is_equal_approx(float(sink.weapons[0].heat_time), 4.8), "Ceramic Heat Sink: heat weapons +20% heat time")
	_check(is_equal_approx(float(sink.resist[1]) - float(_build(["flame_sprayer"], []).resist[1]), 5.0), "Ceramic Heat Sink: +5 fire resistance")
	var slag: Dictionary = Parts.get_part("slag_plating")
	_check(float(slag.armor) == 125.0 and str(slag.rarity) == "Rare" and int(slag.cost) == 170, "Slag Plating: Rare, 125 per facing, 170 scrap")
	var raider: Dictionary = Parts.get_part("raider_frame")
	var hauler: Dictionary = Parts.get_part("hauler_frame")
	_check(float(raider.hp) == 125.0 and int(raider.hardpoints) == 2 and int(raider.cost) == 120, "Raider Frame: 125 HP, 2 hardpoints, 120 scrap")
	_check(float(hauler.hp) == 320.0 and (hauler.seats as Array).count("open") == 3 and str(hauler.rarity) == "Epic", "Hauler Frame: Epic, 320 HP, 3 open seats")
	_check(str(Parts.get_part("goop_launcher").ability) == "goop" and str(Parts.get_part("nitro_bottle").ability) == "nitro", "Goop Launcher and Nitro Bottle are utilities")
	for pool: String in ["torcher", "sludger"]:
		_check(Parts.DROP_POOLS.has(pool), "%s has a drop pool" % pool)
	# Enemy ammo (approved): Outrider heat, Gunner Rig magazine.
	var o := EnemyRig.new()
	_check(float(o.gun_stats[0].get("heat_time", 0.0)) == 6.0 and float(o.gun_stats[0].get("lockout", 0.0)) == 3.0, "Outrider guns overheat after 6 s, 3 s lockout")
	o.free()
	var g := GunnerRig.new()
	_check(int(g.gun_stats[0].get("mag", 0)) == 6 and float(g.gun_stats[0].get("reload", 0.0)) == 2.5, "Gunner Rig: 6 bursts, 2.5 s reload")
	g.free()
	_check(T.PATCHER_MAX_REVIVES == 3, "Patcher revives capped at 3 per job")
	# Keyword colors (approved): BURNING orange, GOOPED mustard; none reuse threat colors.
	_check(_hex(T.STATUS_COLORS[1]) == "FF5A1F" and _hex(T.STATUS_COLORS[5]) == "E0A458", "BURNING #FF5A1F, GOOPED #E0A458")
	_check(T.KEYWORDS.size() == 11, "11 keywords, each with a symbol, animation and color")
	var threats := [_hex(T.COL_ENEMY), _hex(T.COL_ELITE), _hex(T.COL_HUNTER), _hex(T.COL_SHIELD)]
	var clash := false
	for k: String in T.KEYWORDS:
		clash = clash or threats.has(_hex(T.KEYWORDS[k].color))
	_check(not clash, "no keyword reuses a threat color")
	# Crew.
	_check((Crew.SPECIALTIES.gunner as Array).has("demolisher") and (Crew.SPECIALTIES.spotter as Array).has("jammer") and (Crew.SPECIALTIES.bruiser as Array).has("wrangler"), "Demolisher, Jammer and Wrangler join their classes")
	var dice := RandomNumberGenerator.new()
	dice.seed = 3
	var w := Crew.make("bruiser", "Rare", dice, "wrangler")
	var a := Crew.ability(w)
	_check(str(a.kind) == "chain_drag" and is_equal_approx(float(a.cooldown), 20.0) and is_equal_approx(float(a.ram), 0.48), "Chain Drag scales with rarity (Rare: 20 s, +48% ram)")
	var e := Crew.entry(w)
	e.injured = true
	var hurt := Crew.compute_mods([e])
	var fine := Crew.compute_mods([Crew.entry(w)])
	_check(float(hurt.ram) < float(fine.ram) * 0.85, "an injured Wrangler costs ram dealt")
	# Extract or Push eligibility.
	var hits := 0
	var courier := 0
	for i in 400:
		if Missions.has_push(Missions.make("clear", 3, i)):
			hits += 1
		if Missions.has_push(Missions.make("courier", 3, i)):
			courier += 1
	_check(hits > 100 and hits < 165, "about a third of jobs offer a push (%d / 400)" % hits)
	_check(courier == 0, "Courier never offers a push")
	var today := int(profile.get("day"))
	profile.set("day", 5)
	profile.set("wreck_day", 4)
	_check(bool(profile.call("push_blocked_today")), "no push the day after a wreck")
	profile.set("wreck_day", 0)
	profile.set("day", today)
	var torch := 0
	var early := 0
	for i in 400:
		if Missions.has_torcher(Missions.make("clear", 3, i)):
			torch += 1
		if Missions.has_torcher(Missions.make("clear", 2, i)) or Missions.has_sludger(Missions.make("survive", 3, i)):
			early += 1
	_check(torch > 80 and torch < 160 and early == 0, "Torcher ~30%% of 3-skull Clears, none earlier; Sludger not before 4 (%d)" % torch)


func _process(_delta: float) -> bool:
	frame += 1
	var rig := main.vehicle
	match step:
		0:  # Flame Sprayer: fire damage that builds BURNING
			if frame == 3:
				main.zombies.spawn_budget = 0
				main.zombies.clear_all()
				for b in main.barrels:
					b.deactivate()
				main.apply_rig(_build(["flame_sprayer"], []))
				rig.armor_max = 1000000.0
				rig.armor = rig.armor_max
				_park(SPOT)
				mark.z = main.zombies.spawn_at(SPOT + Vector2(0, 150), "brute")
				main.hud.right_stick.output = Vector2.DOWN
			if frame == 60:
				var z: Node = mark.z
				_check(main.bullets.typed_hits > 0, "flame hits carry fire (%d)" % main.bullets.typed_hits)
				_check(not bool(z.get("active")) or (z.get("status") as StatusBars).build[StatusBars.FIRE] > 0.0 or (z.get("status") as StatusBars).active(StatusBars.FIRE), "the flame builds BURNING")
				_next()
		1:  # Arc Projector: hits chain to a second target
			if frame == 2:
				main.zombies.clear_all()
				main.apply_rig(_build(["arc_projector"], ["targeting_computer"]))
				rig.armor_max = 1000000.0
				rig.armor = rig.armor_max
				_park(SPOT)
				main.zombies.spawn_at(SPOT + Vector2(0, 200), "brute")
				main.zombies.spawn_at(SPOT + Vector2(60, 230), "brute")
				main.hud.right_stick.output = Vector2.DOWN
			if frame == 90:
				_check(main.bullets.chained > 0, "Arc Projector hits jump to a second target (%d)" % main.bullets.chained)
				_next()
		2:  # Acid Lobber: globs leave acid ground
			if frame == 2:
				main.zombies.clear_all()
				main.apply_rig(_build(["acid_lobber"], ["targeting_computer"]))
				rig.armor_max = 1000000.0
				rig.armor = rig.armor_max
				_park(SPOT)
				main.hud.right_stick.output = Vector2.RIGHT * 0.6
			if frame == 150:
				_check(main.hazards.acid_count() > 0, "Acid Lobber globs leave acid puddles")
				main.hud.right_stick.output = Vector2.ZERO
				_next()
		3:  # Torcher: a hard rear hit ruptures the tank
			if frame == 2:
				var t := main.spawn_torcher(SPOT + Vector2(400, 0))
				t.player = null
				mark.t = t
			if frame == 5:
				var t: Node = mark.t
				var behind := Vector2.RIGHT.rotated(float(t.get("rotation")) + PI)
				t.call("take_damage", 50.0, behind, false, "")
				_check(bool(t.get("ruptured")) and main.hazards.fire_count() > 0, "a 40+ rear hit ruptures the Torcher's tank into burning ground")
				t.call("take_damage", 100000.0, Vector2.ZERO, false, "")
				_next()
		4:  # Sludger: lobs alternating acid and goop shells
			if frame == 2:
				var s := main.spawn_sludger(SPOT + Vector2(650, 0))
				mark.s = s
			if frame == 420:
				var s: Node = mark.s
				_check(int(s.get("shells_thrown")) >= 2, "the Sludger lobs shells from range (%d)" % int(s.get("shells_thrown")))
				s.call("take_damage", 100000.0, Vector2.ZERO, false, "")
				_next()
		5:  # Jammer, Goop Launcher, Scrapper in its own lit oil
			if frame == 2:
				var g := main.spawn_gunner(SPOT + Vector2(250, 0), false)
				g.player = null
				mark.g = g
				var sc := main.spawn_scrapper(SPOT + Vector2(-500, 300))
				sc.player = null
				mark.sc = sc
			if frame == 4:
				var g: Node = mark.g
				_check(rig.static_burst(450.0, 60.0, 4.0) >= 1 and float(g.get("jammed_left")) > 0.0, "Static Burst shocks rigs and stops their shields recharging")
				_check(rig.goop_shot(500.0, 90.0) >= 1 and bool(g.call("is_status", StatusBars.GOOP)), "Goop Launcher GOOPs the nearest enemy rig")
				_check(main.zombies.bait == g, "the horde is baited onto the GOOPED rig")
				var sc: Node2D = mark.sc
				sc.set("velocity", Vector2.ZERO)
				main.hazards.add_fire(sc.global_position, 90.0, 10.0, BulletPool.TEAM_ENEMY)
			if frame == 60:
				var sc: Node = mark.sc
				var st := sc.get("status") as StatusBars
				_check(st.build[StatusBars.FIRE] > 0.0 or st.active(StatusBars.FIRE), "a Scrapper burns in its own side's lit oil")
				(mark.g as Node).call("take_damage", 100000.0, Vector2.ZERO, false, "")
				sc.call("take_damage", 100000.0, Vector2.ZERO, false, "")
				_next()
		6:  # Extract or Push: objective done -> choose -> push -> extract -> x1.5
			if frame == 2:
				main.zombies.clear_all()
				mark.scrap = int(profile.get("scrap"))
				main._succeed("BLOCK CLEARED", "", 1.0)
				_check(main.push_state == Mission.Push.CHOOSING and main.state == Mission.State.RUNNING, "the objective shows both markers instead of ending the job")
				_check(main.push_at.distance_to(main.push_extract) >= T.PUSH_MARKER_GAP - 1.0, "the push beacon sits 600+ px from the extraction marker")
				rig.global_position = main.push_at
			if frame == 4:
				_check(main.push_state == Mission.Push.ACTIVE, "driving into the beacon starts the push")
				_check(is_equal_approx(main.push_left, float(T.PUSH_SECONDS[0]) - 1.0 / 60.0) or main.push_left > 55.0, "a 1-skull push lasts 60 s")
				main.push_left = 0.01
				rig.global_position = main.push_at + Vector2(0, 300)
			if frame == 6:
				_check(main.push_state == Mission.Push.EXTRACT, "the timer ends the push; extract at the beacon")
				rig.global_position = main.push_extract
			if frame == 8:
				_check(main.state == Mission.State.CLEARED and main.pushed, "extracting after the push ends the job, pushed")
				var paid := int(profile.get("scrap")) - int(mark.scrap)
				_check(paid >= roundi(int(main.spec.reward) * T.PUSH_PAY), "a push pays the job x1.5 (%d)" % paid)
				_finish()
	return false


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
		print("CONTENT TEST PASSED")
		quit(0)
	else:
		print("CONTENT TEST FAILED: %s" % ", ".join(failures))
		quit(1)
