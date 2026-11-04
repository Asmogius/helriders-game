extends SceneTree
## Headless test for the §14 defense layers: which facing a hit lands on, the
## shield soaking first and recharging after its delay, a stripped facing
## passing hits to HP, splash (full + 25% to the neighbours, never HP while
## armor remains), repairs to the most damaged facing (capped), the starter
## and part numbers, front-only plates, old saves and old-style loadouts,
## enemy layers (Gunner Rig shield from 4 skulls, Hunt Elites on every
## layer), and the HUD rig icon.
##
## Run:  godot --headless --fixed-fps 60 --path . -s res://tests/defense_test.gd

const Mission := preload("res://scripts/mission.gd")
const Missions := preload("res://scripts/missions.gd")
const Vehicle := preload("res://scripts/vehicle.gd")
const EnemyRig := preload("res://scripts/enemy_rig.gd")
const GunnerRig := preload("res://scripts/gunner_rig.gd")
const ProfileScript := preload("res://scripts/profile.gd")
const Parts := preload("res://scripts/parts.gd")
const Loadout := preload("res://scripts/loadout.gd")
const T := preload("res://scripts/tuning.gd")

var profile: Node
var main: Mission
var frame := 0
var failures: Array[String] = []
var mark := {}


func _initialize() -> void:
	profile = root.get_node("Profile")
	profile.set("persist", false)
	profile.call("new_game")
	_check_numbers()
	_check_model()
	_check_loadouts()
	main = (load("res://scenes/mission.tscn") as PackedScene).instantiate() as Mission
	main.mission_override = Missions.make("clear", 4, 9)
	main.auto_spawn_specials = false
	root.add_child(main)


func _process(_delta: float) -> bool:
	frame += 1
	if frame == 3:
		main.zombies.clear_all()
		main.zombies.spawn_budget = 0
		var rig := main.vehicle
		rig.velocity = Vector2.ZERO
		_check(rig.shield_max == 30.0 and rig.hp_max == 150.0 and rig.facing_max[0] == 80.0, "the mission rig rolls out with all three layers")
		# The shield soaks, then waits out its delay, then refills.
		rig.take_damage(25.0, Vector2.RIGHT.rotated(rig.rotation))
		_check(is_equal_approx(rig.shield, 5.0) and rig.facing_armor[0] == 80.0, "a hit drains the shield before any armor")
		mark.t = 0
		var g := main.gunner
		_check(g.shield_max == 30.0 and g.shield == 30.0, "4 skulls: Gunner Rigs carry a 30 shield")
		main.hud.set_defense(0.5, PackedFloat32Array([1.0, 0.25, 0.0, -1.0]), 0.6)
		var icon := main.hud.defense_icon_values()
		_check(is_equal_approx(float(icon.shield), 0.5) and is_equal_approx(float(icon.hp), 0.6) and (icon.facings as PackedFloat32Array)[3] == -1.0, "the HUD rig icon takes shield, plates and HP")
	if frame == 3 + roundi(T.DEFAULT_SHIELD_DELAY * 60.0) - 10:
		_check(is_equal_approx(main.vehicle.shield, 5.0), "no recharge during the %d s delay" % int(T.DEFAULT_SHIELD_DELAY))
	if frame == 3 + roundi((T.DEFAULT_SHIELD_DELAY + 5.0) * 60.0) + 10:
		_check(is_equal_approx(main.vehicle.shield, 30.0), "then it refills (Junk Emitter: full in ~5 s)")
		_finish()
	return false


func _check_numbers() -> void:
	_check(float(Parts.CATALOG.scrap_frame.hp) == 150.0 and float(Parts.CATALOG.courier_frame.hp) == 105.0 and float(Parts.CATALOG.bulwark_frame.hp) == 270.0, "frame HP 150 / 105 / 270")
	var plates := {"outrider_light_plating": [62, 7, 12], "scrap_plating": [80, 12, 21], "riot_plating": [115, 18, 33], "composite_plating": [142, 17, 30]}
	var ok := true
	for id: String in plates:
		var p: Dictionary = Parts.CATALOG[id]
		var want: Array = plates[id]
		ok = ok and float(p.armor) == float(want[0]) and float(p.weight) == float(want[1]) and float(p.weight_sides) == float(want[2])
	_check(ok, "plates per facing and slot weights from §14")
	_check(Parts.CATALOG.spiked_ram_plate.name == "Zed Sled" and bool(Parts.CATALOG.spiked_ram_plate.front_only) and float(Parts.CATALOG.spiked_ram_plate.armor) == 71.0, "Zed Sled: front only, 71")
	_check(float(Parts.CATALOG.composite_plating.power) == 4.0 and float(Parts.CATALOG.composite_plating.power_sides) == 7.0, "Composite costs 4 power front/rear, 7 on the sides")
	_check(float(Parts.CATALOG.structural_bracing.hp_bonus) == 25.0, "Structural Bracing raises max HP by 25")
	var e: Dictionary = Parts.CATALOG.junk_emitter
	_check(float(e.shield) == 30.0 and float(e.shield_delay) == 3.0 and float(e.shield_refill) == 5.0 and float(e.power) == 25.0, "Junk Emitter: 30 shield, 3 s delay, ~5 s refill, 25 power")
	var rigs := [[T.OUTRIDER, 100, 40, 40, 40], [T.GUNNER, 120, 60, 55, 55], [T.BULWARK, 180, 180, 55, 50], [T.SCRAPPER, 90, 35, 35, 35],
		[T.CONVOY, 200, 250, 70, 60], [T.CONVOY_TRAILER, 120, 50, 65, 50]]
	ok = true
	for row: Array in rigs:
		var r: Dictionary = row[0]
		var want: Array = row.slice(1)
		ok = ok and float(r.hp) == float(want[0]) and float(r.front) == float(want[1]) and float(r.side) == float(want[2]) and float(r.rear) == float(want[3])
		ok = ok and is_equal_approx(float(r.armor), float(want[0]) + float(want[1]) + 2.0 * float(want[2]) + float(want[3]))
	_check(ok, "enemy layers from §14's table, totals add up")


func _check_model() -> void:
	var v := Vehicle.new()
	v.apply_stats({"name": "Test", "max_speed": 100.0, "reverse_speed": 50.0, "acceleration": 100.0, "brake": 100.0, "coast": 100.0,
		"turn_rate": 1.0, "grip": 5.0, "hp": 100.0, "front": 50.0, "side": 40.0, "rear": 30.0, "shield": 20.0,
		"ram_damage": 10.0, "mount": 0, "fire_rate": 0.0, "bullet_damage": 0.0, "bullet_speed": 1000.0, "spread_deg": 0.0,
		"turret_turn_rate": 0.0, "lock_range": 0.0})
	v.rotation = 0.0   # facing +x
	_check(v.facing_of(Vector2.RIGHT) == v.FRONT and v.facing_of(Vector2.LEFT) == v.REAR and v.facing_of(Vector2.DOWN) == v.RIGHT and v.facing_of(Vector2.UP) == v.LEFT,
		"four 90-degree arcs: front, rear, right, left")
	_check(is_equal_approx(v.armor_max, 100.0 + 50.0 + 80.0 + 30.0 + 20.0) and v.armor == v.armor_max, "armor_max totals every layer")
	v.take_damage(30.0, Vector2.LEFT)   # from behind
	_check(v.shield == 0.0 and is_equal_approx(v.facing_armor[3], 20.0) and v.hp == 100.0, "shield first, then the facing hit")
	v.take_damage(50.0, Vector2.LEFT)
	_check(v.facing_armor[3] == 0.0 and is_equal_approx(v.hp, 70.0), "a stripped facing passes the rest to HP")
	v.take_damage(10.0, Vector2.RIGHT)
	_check(is_equal_approx(v.facing_armor[0], 40.0) and is_equal_approx(v.hp, 70.0), "other facings still protect")
	v.take_damage(20.0, Vector2.DOWN, true)   # a blast on the right
	_check(is_equal_approx(v.facing_armor[2], 20.0) and is_equal_approx(v.facing_armor[0], 35.0) and v.facing_armor[3] == 0.0 and is_equal_approx(v.hp, 70.0),
		"splash: full to the nearest facing, 25% to each neighbour, none to HP")
	var got := v.repair_armor(100.0)
	_check(is_equal_approx(got, 30.0) and is_equal_approx(v.facing_armor[3], 30.0) and is_equal_approx(v.hp, 70.0), "repairs fix the most damaged facing, capped at its max, never HP")
	for i in 4:
		v.facing_armor[i] = 0.0
	v.take_damage(15.0, Vector2.UP, true)
	_check(is_equal_approx(v.hp, 55.0), "with every facing stripped, splash reaches HP")
	v.take_damage(1000.0, Vector2.RIGHT)
	_check(v.is_wrecked and v.hp == 0.0, "HP at zero: wrecked")
	v.free()
	# Enemy shields from 4 skulls; Hunt Elites on every layer.
	var g := GunnerRig.new()
	_check(g.shield_max == 0.0, "a Gunner Rig's shield is off until the job says")
	g.arm_for_skulls(3)
	_check(g.shield_max == 0.0, "3 skulls: no shield")
	g.arm_for_skulls(4)
	_check(g.shield_max == 30.0 and g.shield == 30.0, "4 skulls: shield 30")
	g.free()
	var elite := EnemyRig.new()
	elite.make_elite("TEST", 2.0, 1.0)
	_check(elite.hp_max == 200.0 and elite.facing_max[0] == 80.0 and elite.facing_max[1] == 80.0 and elite.facing_max[3] == 80.0, "Hunt Elite armor multiplier applies to every layer")
	elite.free()


func _check_loadouts() -> void:
	var s := Loadout.build(Parts.STARTER_LOADOUT)
	_check(float(s.hp) == 150.0 and float(s.front) == 80.0 and float(s.side) == 80.0 and float(s.rear) == 80.0 and float(s.shield) == 30.0, "starter: HP 150, 80 a facing, shield 30")
	var cow := Parts.STARTER_LOADOUT.duplicate(true)
	cow.armor_sides = "cowcatcher_ram"
	print("  (one \"can't go in\" warning below is expected)")
	_check(float(Loadout.build(cow).side) == 0.0, "a front-only plate does nothing in the Sides slot")
	cow.armor_sides = "scrap_plating"
	cow.armor_front = "cowcatcher_ram"
	var cs := Loadout.build(cow)
	_check(float(cs.front) == 124.0 and float(cs.ram_damage) == 170.0, "on the front, the Cowcatcher gives 124 armor and its ram")
	var braced := Parts.STARTER_LOADOUT.duplicate(true)
	braced.internal = ["structural_bracing"]
	_check(float(Loadout.build(braced).hp) == 175.0, "Structural Bracing: +25 max HP")
	var old := {"chassis": "scrap_frame", "engine": "junk_v6", "drive": "street_wheels", "armor": "riot_plating", "weapons": ["pintle_turret"], "utility": [], "internal": []}
	var os := Loadout.build(old)
	_check(float(os.front) == 115.0 and float(os.side) == 115.0 and float(os.rear) == 115.0, "an old one-plate loadout puts the plate on all three slots")
	var clean := ProfileScript._clean_loadout(old)
	_check(clean.armor_front == "riot_plating" and clean.armor_sides == "riot_plating" and clean.armor_rear == "riot_plating", "old saves: the plate goes on all three slots")
	var old_ram := old.duplicate()
	old_ram.armor = "spiked_ram_plate"
	var clean_ram := ProfileScript._clean_loadout(old_ram)
	_check(clean_ram.armor_front == "spiked_ram_plate" and clean_ram.armor_sides == "" and clean_ram.armor_rear == "", "old saves: a ram plate goes on the front only")


func _check(ok: bool, what: String) -> void:
	print(("  PASS  " if ok else "  FAIL  ") + what)
	if not ok:
		failures.append(what)


func _finish() -> void:
	if failures.is_empty():
		print("DEFENSE TEST PASSED")
		quit(0)
	else:
		print("DEFENSE TEST FAILED: %s" % ", ".join(failures))
		quit(1)
