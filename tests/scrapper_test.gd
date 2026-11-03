extends SceneTree
## Headless test for the Scrapper and the Oil Slick: the mission tables and
## Comms text, the Oil Slick part and its HUD button, the Scrapper weaving
## ahead of you and plinking with its turret, its traps (mines that hurt you
## and zombies but not enemy rigs, oil that makes rigs slide and slows
## zombies), and its salvage.
##
## Run:  godot --headless --fixed-fps 60 --path . -s res://tests/scrapper_test.gd

const Mission := preload("res://scripts/mission.gd")
const Missions := preload("res://scripts/missions.gd")
const ScrapperRig := preload("res://scripts/scrapper_rig.gd")
const Parts := preload("res://scripts/parts.gd")
const Loadout := preload("res://scripts/loadout.gd")
const T := preload("res://scripts/tuning.gd")

const SPOT := Vector2(1600, 1200)
const OIL_BUILD := {
	"chassis": "scrap_frame", "engine": "junk_v6", "drive": "street_wheels", "armor": "scrap_plating",
	"weapons": ["pintle_turret"], "utility": ["oil_slick"], "internal": [],
}

var main: Mission
var frame := 0
var step := 0
var failures: Array[String] = []
var s: ScrapperRig
var mark := {}


func _initialize() -> void:
	seed(20261105)
	var profile: Node = root.get_node("Profile")
	profile.set("persist", false)
	profile.call("new_game")
	main = (load("res://scenes/mission.tscn") as PackedScene).instantiate() as Mission
	main.mission_override = Missions.make("clear", 1, 7)
	main.auto_spawn_specials = false
	main.always_drop_schematic = true
	root.add_child(main)


func _process(_delta: float) -> bool:
	frame += 1
	var rig := main.vehicle
	match step:
		0:
			if frame == 3:
				_check_tables()
				main.zombies.spawn_budget = 0
				main.zombies.clear_all()
				# The Oil Slick on your rig.
				main.apply_rig(Loadout.build(OIL_BUILD))
				rig.armor_max = 100000.0
				rig.armor = rig.armor_max
				_park(SPOT)
				_check(main.use_ability(0) and main.hazards.oil_count() == 1, "Oil Slick: the button pours a slick")
				var behind := SPOT - Vector2.RIGHT.rotated(rig.rotation) * (rig.body_len * 0.5 + 42.0)
				_check(main.hazards.oil_at(behind) and not main.hazards.oil_at(SPOT + Vector2.RIGHT.rotated(rig.rotation) * 160.0), "...behind the rig, not in front")
				_check(not main.use_ability(0), "...then cools down")
				var z := main.zombies.spawn_at(behind, "shambler")
				mark.z = z
			if frame == 6:
				_check(bool((mark.z as Node).get("oiled")), "zombies in oil are slowed")
				rig.global_position = SPOT - Vector2.RIGHT.rotated(rig.rotation) * (rig.body_len * 0.5 + 42.0)
			if frame == 8:
				_check(is_equal_approx(rig.traction, T.SLIME_GRIP), "your own rig slides on your oil too")
				main.zombies.clear_all()
				main.hazards.clear()
				main.apply_rig(Loadout.build(Parts.STARTER_LOADOUT))
				rig.armor_max = 100000.0
				rig.armor = rig.armor_max
				_park(SPOT)
				_next()
		1:  # Weaves ahead of you and plinks
			if frame == 1:
				s = main.spawn_scrapper(SPOT + Vector2(700, 0)) as ScrapperRig
				_check(s != null and s == main.scrapper, "spawn_scrapper sends in a Scrapper")
				mark.shots = main.bullets.enemy_shots
				mark.armor = rig.armor
			if frame == 420:
				var d := s.global_position.distance_to(rig.global_position)
				_check(d > T.SCRAPPER_RANGE_MIN - 100.0 and d < T.SCRAPPER_RANGE_MAX + 200.0, "it works in close, 250-400 px out (%.0f px)" % d)
				_check(main.bullets.enemy_shots > int(mark.shots), "its turret plinks at you")
				_check(s.traps_dropped >= 1, "it drops traps on its own (%d in 7 s)" % s.traps_dropped)
				_next()
		2:  # Its traps
			if frame == 1:
				s.next_trap = "mine"
				var mines_before: int = main.enemy_mines.active_count()
				_check(s.drop_trap() == "mine" and main.enemy_mines.active_count() == mines_before + 1, "trap 1: a mine")
				var oil_before := main.hazards.oil_count()
				_check(s.drop_trap() == "oil" and main.hazards.oil_count() == oil_before + 1, "trap 2: an oil slick (they alternate)")
				# A mine right under your rig.
				_park(SPOT + Vector2(0, -400))
				s.global_position = SPOT + Vector2(0, 600)
				mark.armor = rig.armor
				mark.det = main.enemy_mines.detonations
				main.enemy_mines.drop(rig.global_position, T.SCRAPPER_MINE_DAMAGE, T.SCRAPPER_MINE_RADIUS, 0.0, 10.0)
			if frame == 8:
				_check(main.enemy_mines.detonations == int(mark.det) + 1, "your rig sets off its mine")
				var lost := float(mark.armor) - rig.armor
				_check(lost >= T.SCRAPPER_MINE_DAMAGE * 0.9, "the mine hits you for ~%d (%.0f)" % [int(T.SCRAPPER_MINE_DAMAGE), lost])
				# A zombie walks onto one.
				var at := SPOT + Vector2(-700, 300)
				mark.z = main.zombies.spawn_at(at, "brute")
				main.enemy_mines.drop(at, T.SCRAPPER_MINE_DAMAGE, T.SCRAPPER_MINE_RADIUS, 0.0, 10.0)
				mark.det = main.enemy_mines.detonations
			if frame == 16:
				var z: Node = mark.z
				_check(main.enemy_mines.detonations == int(mark.det) + 1 and float(z.get("hp")) <= 200.0 - T.SCRAPPER_MINE_DAMAGE + 0.1, "zombies set its mines off too (and take the blast)")
				main.zombies.clear_all()
				# Enemy rigs drive over their own mines.
				s.global_position = SPOT + Vector2(700, 600)
				s.velocity = Vector2.ZERO
				main.enemy_mines.drop(s.global_position, T.SCRAPPER_MINE_DAMAGE, T.SCRAPPER_MINE_RADIUS, 0.0, 10.0)
				mark.det = main.enemy_mines.detonations
			if frame == 24:
				_check(main.enemy_mines.detonations == int(mark.det), "enemy rigs don't set off their own mines")
				_next()
		3:  # Wrecked
			if frame == 1:
				mark.scrap = main.scrap
				mark.pickups = main.pickups.get_child_count()
				s.take_damage(100000.0)
			if frame == 3:
				var mult := main.profile.salvage_mult() * float(rig.crew_mod("scrap")) * float(rig.crew_mod("rig_scrap"))
				_check(is_equal_approx(main.scrap - float(mark.scrap), T.SCRAPPER_SCRAP * mult), "it pays %d scrap" % T.SCRAPPER_SCRAP)
				var drop: Node = main.pickups.get_child(main.pickups.get_child_count() - 1)
				var part: Dictionary = drop.get("part")
				_check(Parts.DROP_POOLS.scrapper.has(str(part.get("id", ""))), "it drops from its pool (%s)" % str(part.get("name", "")))
				mark.before = s.traps_dropped
			if frame == 60 * 7:
				_check(s.traps_dropped == int(mark.before), "a wreck drops no more traps")
				_finish()
	return false


func _check_tables() -> void:
	var part := Parts.get_part("oil_slick")
	_check(part.rarity == "Uncommon" and int(part.cost) == 90 and float(part.power) == 10.0 and float(part.weight) == 10.0 and float(part.cooldown) == 14.0,
		"Oil Slick: Uncommon, 90 scrap, 10 power, 10 weight, every 14 s")
	_check(float(part.oil_radius) * 2.0 == 140.0 and float(part.oil_time) == 12.0, "Oil Slick: 140 wide for 12 s")
	var dps := float(T.SCRAPPER.fire_rate) * float(T.SCRAPPER.bullet_damage)
	_check(is_equal_approx(dps, 10.0) and float(T.SCRAPPER.armor) == 200.0 and float(T.SCRAPPER.max_speed) == 580.0, "Scrapper: 200 armor, speed 580, ~10 damage/s")
	_check(not Missions.threats_text(Missions.make("clear", 1, 7)).contains("Scrapper"), "Clear 1 skull: no Scrapper")
	_check(Missions.threats_text(Missions.make("clear", 2, 7)).contains("1 Scrapper"), "Clear 2 skulls: the first enemy rig is a Scrapper")
	_check(Missions.threats_text(Missions.make("courier", 2, 7)).contains("1 Scrapper"), "Courier 2 skulls: a Scrapper on the route")
	_check(not Missions.threats_text(Missions.make("survive", 2, 7)).contains("Scrapper") and Missions.threats_text(Missions.make("survive", 3, 7)).contains("1 Scrapper"),
		"Survive: a Scrapper joins from 3 skulls")
	var hunts := true
	for k in range(1, 7):
		hunts = hunts and not Missions.threats_text(Missions.make("hunt", k, 7)).contains("Scrapper")
	_check(hunts, "Hunt: no Scrappers")


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
