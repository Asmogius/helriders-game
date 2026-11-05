extends SceneTree
## Headless test for the §14 weapons: the Harpoon, Mortar, Shock Pulse,
## EMP-Hardened Computer and Reflex Emitter numbers and drop pools, magazine
## DPS, the Mortar's stick-set distance, landing and magazine, the Harpoon
## piercing zombies and tethering a rig (reel, mass, pop, let go), and the
## Shock Pulse's burst.
##
## Run:  godot --headless --fixed-fps 60 --path . -s res://tests/weapons_test.gd

const Mission := preload("res://scripts/mission.gd")
const Missions := preload("res://scripts/missions.gd")
const Parts := preload("res://scripts/parts.gd")
const Loadout := preload("res://scripts/loadout.gd")
const StatusBars := preload("res://scripts/status_bars.gd")
const T := preload("res://scripts/tuning.gd")

const SPOT := Vector2(1600, 1200)   # open ground at the player start
const BASE := {"chassis": "scrap_frame", "engine": "junk_v6", "drive": "street_wheels",
	"armor_front": "scrap_plating", "armor_sides": "scrap_plating", "armor_rear": "scrap_plating"}

var main: Mission
var frame := 0
var step := 0
var failures: Array[String] = []
var mark := {}


func _initialize() -> void:
	seed(20261104)
	var profile: Node = root.get_node("Profile")
	profile.set("persist", false)
	profile.call("new_game")
	_check_parts()
	main = (load("res://scenes/mission.tscn") as PackedScene).instantiate() as Mission
	main.mission_override = Missions.make("clear", 1, 7)
	main.auto_spawn_specials = false
	root.add_child(main)


func _build(weapons: Array, internal: Array, utility: Array = []) -> Dictionary:
	var b: Dictionary = BASE.duplicate()
	b.weapons = weapons
	b.internal = internal
	b.utility = utility
	return Loadout.build(b)


func _process(_delta: float) -> bool:
	frame += 1
	var rig := main.vehicle
	match step:
		0:  # Mortar: the push sets the distance; a magazine of 3
			if frame == 3:
				main.zombies.spawn_budget = 0
				main.zombies.clear_all()
				for b in main.barrels:
					b.deactivate()
				main.apply_rig(_build(["mortar"], ["targeting_computer"]))
				rig.armor_max = 100000.0
				rig.armor = rig.armor_max
				_park(SPOT)
				# Rig faces down (+y); aim right. A full push reaches the screen's
				# edge (less half the blast), so aim a third of the way to it.
				var reach := clampf(rig.view_reach(SPOT, Vector2.RIGHT, 45.0), 300.0, 1200.0)
				mark.reach = reach
				var want := lerpf(300.0, reach, 1.0 / 3.0)
				mark.want = want
				var push := 0.2 + 0.8 * (1.0 / 3.0)
				var o := main.spawn_bulwark(SPOT + Vector2(want, 0))
				o.player = null   # parked under the circle
				o.velocity = Vector2.ZERO
				mark.z = o
				mark.zhp = float(o.get("armor"))
				main.hud.right_stick.output = Vector2.RIGHT * push
			if frame == 3 + 90:
				var aim: Vector2 = main.shells.aim_at
				_check(aim != Vector2.INF and absf(aim.distance_to(SPOT) - float(mark.want)) < 25.0, "the landing circle sits where the push puts it (%.0f px out, want %.0f; screen reach %.0f)" % [aim.distance_to(SPOT), float(mark.want), float(mark.reach)])
			if frame == 3 + 150:
				_check(main.shells.blasts >= 1 and main.shells.last_blast.distance_to(SPOT + Vector2(float(mark.want), 0)) < 30.0, "shells land on the circle")
				var mm: Node = root.get_node("MusicManager")
				_check(int(mm.sfx_counts.get("mortar_fire", 0)) >= 1 and int(mm.sfx_counts.get("explosion", 0)) >= 1, "the Mortar thumps and its shells go bang (sound)")
				var z: Node = mark.z
				_check(float(z.get("armor")) < float(mark.zhp) - 50.0, "the blast hurts what's under it (-%.0f)" % (float(mark.zhp) - float(z.get("armor"))))
			if frame == 3 + 200:
				var fired: int = main.shells.blasts + main.shells.active_count()
				_check(fired == 3 and rig.ammo_left(0) == 0, "a magazine of 3, then it reloads (%d shells)" % fired)
			if frame == 3 + 200 + 60:
				var fired: int = main.shells.blasts + main.shells.active_count()
				_check(fired == 3, "still reloading a second later (%d shells)" % fired)
			if frame == 3 + 200 + 260:
				var fired: int = main.shells.blasts + main.shells.active_count()
				_check(fired > 3, "after the 4 s reload it fires again (%d shells)" % fired)
				(mark.z as Node).call("take_damage", 100000.0)
				main.hud.right_stick.output = Vector2.RIGHT * 0.21
			if frame == 3 + 200 + 280:
				var aim: Vector2 = main.shells.aim_at
				_check(absf(aim.distance_to(SPOT) - 300.0) < 25.0, "a light push lobs at the 300 px minimum (%.0f px)" % aim.distance_to(SPOT))
				main.hud.right_stick.output = Vector2.RIGHT   # full push
			if frame == 3 + 200 + 330:
				var aim: Vector2 = main.shells.aim_at
				var vp := main.get_viewport()
				var view: Rect2 = vp.get_canvas_transform().affine_inverse() * vp.get_visible_rect()
				_check(aim != Vector2.INF and view.has_point(aim) and aim.distance_to(SPOT) < 1200.0 - 1.0, "a full push lands at the screen's edge, not off it (%.0f px; view %s)" % [aim.distance_to(SPOT), view])
				main.hud.right_stick.output = Vector2.ZERO
				main.zombies.clear_all()
				_next()
		1:  # Harpoon: pierces zombies, sticks in a rig, tethers it
			if frame == 1:
				main.apply_rig(_build(["harpoon"], []))
				rig.armor_max = 100000.0
				rig.armor = rig.armor_max
				_park(SPOT)
				var zs: Array = []
				for d: float in [110.0, 190.0]:
					var z := main.zombies.spawn_at(SPOT + Vector2(0, d), "shambler")
					zs.append(z)
				mark.zs = zs
				var o := main.spawn_outrider(SPOT + Vector2(0, 420))
				o.player = null
				o.velocity = Vector2.ZERO
				o.rotation = 0.0
				mark.o = o
			if frame == 4:
				var o: Node = mark.o
				mark.o_armor = float(o.get("armor"))
				mark.o_pos = (o as Node2D).global_position
				mark.r_pos = rig.global_position
				main.hud.right_stick.output = Vector2.DOWN
			if frame == 6:
				main.hud.right_stick.output = Vector2.ZERO
				var hurt := 0
				for z: Node in mark.zs:
					if float(z.get("hp")) <= float(T.ZOMBIE_KINDS.shambler.hp) - 29.0 or not bool(z.get("active")):
						hurt += 1
				_check(hurt == 2, "the spear goes through the zombies in its path (%d of 2)" % hurt)
				var o: Node = mark.o
				_check(float(mark.o_armor) - float(o.get("armor")) > 40.0, "it hits the rig for about 45 (-%.0f)" % (float(mark.o_armor) - float(o.get("armor"))))
				_check(rig.tether != null and rig.tether.b == o, "and tethers it")
				for z: Node in mark.zs:
					z.call("take_hit", 10000.0, Vector2.ZERO)
			if frame == 150:
				var o: Node2D = mark.o
				var d := o.global_position.distance_to(rig.global_position)
				var o_moved := o.global_position.distance_to(mark.o_pos)
				var r_moved := rig.global_position.distance_to(mark.r_pos)
				_check(rig.tether != null and d < 400.0, "the cable reels in (%.0f px apart)" % d)
				_check(o_moved > r_moved, "the lighter rig gets pulled more (Outrider %.0f px, you %.0f px)" % [o_moved, r_moved])
				o.call("take_damage", float(o.get("armor_max")) * 0.2)
			if frame == 152:
				_check(rig.tether == null, "a big hit pops the tether")
				_park(SPOT)
				var o: Node2D = mark.o
				o.global_position = SPOT + Vector2(0, 300)
				o.velocity = Vector2.ZERO
				main.hud.right_stick.output = Vector2.DOWN
			if frame == 156:
				main.hud.right_stick.output = Vector2.ZERO
				_check(rig.tether != null, "it re-tethers on the next spear")
				mark.first = rig.tether
			if frame == 320:
				main.hud.right_stick.output = Vector2.DOWN
			if frame == 324:
				main.hud.right_stick.output = Vector2.ZERO
				_check(rig.tether != mark.first, "firing again lets the old cable go")
				rig.release_tether()
				(mark.o as Node).call("take_damage", 100000.0)
				_next()
		2:  # Shock Pulse
			if frame == 1:
				main.apply_rig(_build(["pintle_turret"], [], ["shock_pulse"]))
				rig.armor_max = 100000.0
				rig.armor = rig.armor_max
				_park(SPOT)
				mark.near = main.zombies.spawn_at(SPOT + Vector2(120, 0), "brute")
				mark.far = main.zombies.spawn_at(SPOT + Vector2(-320, 0), "brute")
				var g := main.spawn_gunner(SPOT + Vector2(0, -150))
				g.set("player", null)
				g.velocity = Vector2.ZERO
				mark.g = g
			if frame == 3:
				var g: Node = mark.g
				mark.g_total = float(g.get("armor"))
				mark.near_hp = float((mark.near as Node).get("hp"))
				_check(main.use_ability(0), "the Shock Pulse fires")
			if frame == 4:
				var near: Node = mark.near
				var far: Node = mark.far
				var g: Node = mark.g
				var nb := float((near.get("status") as StatusBars).build[StatusBars.SHOCK])
				var gb := float((g.get("status") as StatusBars).build[StatusBars.SHOCK])
				_check(float(near.get("hp")) <= float(mark.near_hp) - 14.0, "it hurts zombies within 180 px (15)")
				_check(nb > 50.0 or (near.get("status") as StatusBars).active(StatusBars.SHOCK), "and builds heavy shock on them (%.0f)" % nb)
				_check(gb > 50.0 or (g.get("status") as StatusBars).active(StatusBars.SHOCK), "rigs in range take the shock too (%.0f)" % gb)
				_check(float((far.get("status") as StatusBars).build[StatusBars.SHOCK]) == 0.0, "nothing past 180 px")
				_check(not main.use_ability(0), "then an 18 s cooldown")
				_next()
		3:  # Ammo: the Pintle's magazine, the Twin Guns' heat, the fire-stick rings
			if frame == 1:
				main.zombies.clear_all()
				var b: Dictionary = BASE.duplicate()
				b.chassis = "bulwark_frame"   # two hardpoints
				b.engine = "diesel_block"
				b.weapons = ["pintle_turret", "outrider_twin_guns"]
				b.internal = ["targeting_computer"]
				b.utility = []
				main.apply_rig(Loadout.build(b))
				rig.armor_max = 100000.0
				rig.armor = rig.armor_max
				_park(SPOT)
				mark.shots = main.bullets.shots_fired
				main.hud.right_stick.output = Vector2.UP   # away from the twin guns' nose: only the turret aims...
				rig.fire_trigger = false
			if frame == 2:
				var g := rig.weapon_gauges()
				_check(g.size() == 2 and str(g[0].kind) == "mag" and str(g[1].kind) == "heat", "the fire stick gets a ring per gun: magazine, then heat")
			if frame == 3 + 240:
				_check(rig.is_overheated(1) == false and rig.heat_of(1) > 0.5, "the Twin Guns heat up while firing (%.0f%%)" % (rig.heat_of(1) * 100.0))
			if frame == 3 + 290:
				_check(rig.ammo_left(0) == 0 and bool(rig.weapon_gauges()[0].reloading), "the Pintle runs its 28 rounds dry, then reloads")
			if frame == 3 + 420:
				_check(rig.ammo_left(0) > 0 and not bool(rig.weapon_gauges()[0].reloading), "2 s later it's firing again (%d left)" % rig.ammo_left(0))
				_check(rig.is_overheated(1), "after 6 s nonstop the Twin Guns overheat")
				mark.locked_at = main.bullets.shots_fired
			if frame == 3 + 420 + 60:
				_check(rig.is_overheated(1), "and stay locked while the bar drains")
			if frame == 3 + 420 + 200:
				_check(not rig.is_overheated(1) and rig.heat_of(1) < 0.2, "after the 3 s lockout they fire again")
				main.hud.right_stick.output = Vector2.ZERO
			if frame == 3 + 420 + 230:
				mark.heat = rig.heat_of(1)
			if frame == 3 + 420 + 290:
				_check(rig.heat_of(1) <= float(mark.heat) - 0.2 or rig.heat_of(1) == 0.0, "idle guns cool off (25%/s)")
				var dps := Loadout.total_dps(_build(["pintle_turret"], []))
				_check(absf(dps - 63.0 * 28.0 / 7.0 / (27.0 / 7.0 + 2.0)) < 0.5, "sustained DPS counts the reload (Pintle %.0f)" % dps)
				var twin := Loadout.total_dps(_build(["outrider_twin_guns"], []))
				_check(absf(twin - 48.0 * 6.0 / 9.0) < 0.5, "and the heat lockout (Twin Guns %.0f)" % twin)
				_finish()
	return false


func _check_parts() -> void:
	var h := Parts.get_part("harpoon")
	_check(h.rarity == "Rare" and int(h.cost) == 170 and float(h.power) == 40.0 and float(h.weight) == 20.0 and int(h.mount) == 1
		and float(h.bullet_damage) == 45.0 and float(h.zombie_damage) == 30.0 and int(h.pierce) == 4 and int(h.mag) == 1
		and float(h.reload) == 2.5 and float(h.range) == 600.0 and float(h.cable) == 500.0,
		"Harpoon: Rare fixed, 170 scrap, 40/20, 45 to rigs, 30 to up to 4 zombies, mag 1, 2.5 s, 600 px, 500 px cable")
	var m := Parts.get_part("mortar")
	_check(m.rarity == "Uncommon" and int(m.cost) == 120 and float(m.power) == 45.0 and float(m.weight) == 25.0 and int(m.mount) == 0
		and float(m.bullet_damage) == 60.0 and float(m.blast) == 90.0 and int(m.mag) == 3 and float(m.reload) == 4.0
		and float(m.min_range) == 300.0 and float(m.max_range) == 1200.0 and float(m.flight) == 1.2,
		"Mortar: Uncommon turret, 120 scrap, 45/25, 60 per shell, 90 px blast, mag 3, 4 s, 300-1200 px, 1.2 s flight")
	var p := Parts.get_part("shock_pulse")
	_check(p.rarity == "Uncommon" and int(p.cost) == 90 and float(p.power) == 20.0 and float(p.weight) == 10.0
		and float(p.cooldown) == 18.0 and float(p.pulse_radius) == 180.0 and float(p.pulse_damage) == 15.0 and float(p.pulse_buildup) == 90.0,
		"Shock Pulse: 90 scrap, 20/10, every 18 s, 180 px, 15 damage, 90 shock")
	var e := Parts.get_part("emp_computer")
	_check(e.rarity == "Uncommon" and int(e.cost) == 90 and float(e.power) == 30.0 and float(e.weight) == 5.0, "EMP-Hardened Computer: 90 scrap, 30/5")
	var r := Parts.get_part("reflex_emitter")
	_check(r.rarity == "Rare" and int(r.cost) == 160 and float(r.power) == 40.0 and float(r.shield) == 45.0
		and float(r.shield_delay) == 1.0 and float(r.shield_refill) == 3.0, "Reflex Emitter: Rare, 160 scrap, 40 power, 45 shield, 1 s delay, ~3 s refill")
	_check(Parts.DROP_POOLS.bulwark.has("harpoon") and Parts.DROP_POOLS.gunner.has("mortar") and Parts.DROP_POOLS.gunner.has("emp_computer")
		and Parts.DROP_POOLS.outrider.has("shock_pulse") and Parts.DROP_POOLS.elite.has("reflex_emitter"),
		"drop sources: Harpoon (Bulwark), Mortar and EMP computer (Gunner Rig), Shock Pulse (Outrider), Reflex Emitter (Hunt Elite)")
	var mortar_dps := Loadout.total_dps(_build(["mortar"], []))
	_check(absf(mortar_dps - 34.6) < 1.0, "Mortar: about 35 damage/s over a full magazine and reload (%.1f)" % mortar_dps)
	var harpoon_dps := Loadout.total_dps(_build(["harpoon"], []))
	_check(absf(harpoon_dps - 18.0) < 0.5, "Harpoon: 18 damage/s against rigs (%.1f)" % harpoon_dps)
	var plain := _build(["pintle_turret"], [])
	var emp := _build(["pintle_turret"], ["emp_computer"])
	_check(bool(emp.manual_aim) and float(emp.lock_range) == 0.0, "EMP computer aims turrets, with no LOCK")
	_check(float((emp.resist as Array)[StatusBars.SHOCK]) == float((plain.resist as Array)[StatusBars.SHOCK]) + 15.0, "and adds shock resistance (+15)")
	var reflex := _build(["pintle_turret"], ["reflex_emitter"])
	_check(float(reflex.shield) == 45.0 and float(reflex.shield_delay) == 1.0, "Reflex Emitter fits as a shield")


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
		print("WEAPONS TEST PASSED")
		quit(0)
	else:
		print("WEAPONS TEST FAILED: %s" % ", ".join(failures))
		quit(1)
