extends SceneTree
## Headless crew test (numbers from the "Helriders: Crew Expansion Draft"
## doc). First the data and the save game: the eight classes and their
## passives, injury debuffs, specialty scaling, perks (offers, picks, effects),
## open seats and one-of-each-class, Haggler prices, the Inn's perk picker,
## and loading crew from before specialties. Then one mission, firing every
## specialty's ability on a live rig.
##
## Run:  godot --headless --fixed-fps 60 --path . -s res://tests/crew_test.gd

const Mission := preload("res://scripts/mission.gd")
const Missions := preload("res://scripts/missions.gd")
const ProfileScript := preload("res://scripts/profile.gd")
const Parts := preload("res://scripts/parts.gd")
const Loadout := preload("res://scripts/loadout.gd")
const Crew := preload("res://scripts/crew.gd")
const Inn := preload("res://scripts/inn.gd")
const Pickup := preload("res://scripts/pickup.gd")
const BulletPool := preload("res://scripts/bullet_pool.gd")
const T := preload("res://scripts/tuning.gd")
const Vehicle := preload("res://scripts/vehicle.gd")

const OPEN_SPOT := Vector2(1600, 1200)
# Overloaded on power (115 / 100): Sport Wheels and the Advanced Targeting
# Computer on the Junk V6.
const OVERLOAD_BUILD := {
	"chassis": "scrap_frame", "engine": "junk_v6", "drive": "outrider_sport_wheels", "armor": "scrap_plating",
	"weapons": ["pintle_turret"], "utility": [], "internal": ["advanced_targeting"],
}
const COURIER_BUILD := {
	"chassis": "courier_frame", "engine": "junk_v6", "drive": "street_wheels", "armor": "outrider_light_plating",
	"weapons": ["pintle_turret"], "utility": ["emergency_patch", "mine_dropper"], "internal": [],
}

var profile: ProfileScript
var failures: Array[String] = []
var frame := 0
var mission: Mission
var rig: Vehicle
var rng := RandomNumberGenerator.new()
var mark := {}
var near: Array = []   # shamblers placed by the test


func _initialize() -> void:
	rng.seed = 20261102
	seed(20261102)
	profile = root.get_node("Profile")
	profile.persist = false
	profile.new_game()


func _process(_delta: float) -> bool:
	frame += 1
	if frame == 2:
		_check_classes()
		_check_specialties()
		_check_perks()
		_check_seats()
		_check_saloon()
		_check_old_crew()
		profile.new_game()
		_check_inn_picker()
	if frame == 6:
		profile.new_game()
		mission = (load("res://scenes/mission.tscn") as PackedScene).instantiate() as Mission
		mission.mission_override = Missions.make("survive", 1, 7)
		mission.auto_spawn_specials = false
		root.add_child(mission)
		rig = mission.vehicle
	if frame >= 8:
		_mission_step(frame - 8)
	return false


# --- Data ----------------------------------------------------------------------------

func _member(role: String, rarity := "Common", specialty := "", perks: Array = []) -> Dictionary:
	var m := Crew.make(role, rarity, rng, specialty)
	m.perks = perks.duplicate()
	return m


func _mods(members: Array, injured: Array = []) -> Dictionary:
	var entries: Array = []
	for i in members.size():
		var e := Crew.entry(members[i])
		e.injured = injured.has(i)
		entries.append(e)
	return Crew.compute_mods(entries)


func _check_classes() -> void:
	_check(Crew.CLASSES.size() == 8 and Crew.OPEN_CLASSES.size() == 6, "eight crew classes: Driver, Gunner and six for the open seats")
	var every := true
	for role: String in Crew.CLASSES:
		for spec: String in Crew.SPECIALTIES[role]:
			every = every and Crew.ABILITIES.has(spec) and str(Crew.ABILITIES[spec].kind) != ""
		var m := _member(role)
		every = every and (Crew.SPECIALTIES[role] as Array).has(str(m.specialty)) and Crew.summary(m) != ""
	_check(every, "every class rolls a specialty with its own ability")

	# Passives at level 1, Common and Mythic, and the per-level step.
	var mech := Crew.passive(_member("mechanic"))
	var mech_m := Crew.passive(_member("mechanic", "Mythic"))
	var spot := Crew.passive(_member("spotter"))
	var eng := Crew.passive(_member("engineer", "Mythic"))
	var med := Crew.passive(_member("medic"))
	var scav := Crew.passive(_member("scavenger", "Mythic"))
	var bru := Crew.passive(_member("bruiser"))
	_check(is_equal_approx(float(mech.taken), 0.04) and is_equal_approx(float(mech_m.taken), 0.09), "Mechanic: damage taken -4% Common, -9% Mythic")
	_check(is_equal_approx(float(spot.util_cd), 0.08) and is_equal_approx(float(eng.power), 0.15) and is_equal_approx(float(med.injury), 0.15), "Spotter cooldowns -8%, Engineer power +15% Mythic, Medic injury chance -15%")
	_check(is_equal_approx(float(scav.scrap), 0.35) and is_equal_approx(float(scav.schematic), 0.07), "Mythic Scavenger: kill scrap +35%, schematic odds +7 points")
	_check(is_equal_approx(float(bru.ram), 0.10) and is_equal_approx(float(bru.ram_taken), 0.10), "Bruiser: ram +10%, ram taken -10%")
	var vet := _member("mechanic")
	vet.xp = float(Crew.xp_for_level(5))
	_check(Crew.level(vet) == 5 and is_equal_approx(float(Crew.passive(vet).taken), 0.05), "each level adds the class's step (Mechanic L5: -5%)")

	# Passives fold into one set of modifiers.
	var crew := [_member("mechanic"), _member("spotter"), _member("engineer"), _member("medic"), _member("scavenger"), _member("bruiser")]
	var m := _mods(crew)
	_check(is_equal_approx(float(m.taken), 0.96) and is_equal_approx(float(m.util_cd), 0.92) and is_equal_approx(float(m.power), 1.05), "compute_mods: damage taken, cooldowns and power")
	_check(is_equal_approx(float(m.injury), 0.85) and is_equal_approx(float(m.scrap), 1.1) and is_equal_approx(float(m.schematic), 0.02), "compute_mods: injury chance, kill scrap, schematic odds")
	_check(is_equal_approx(float(m.ram), 1.1) and is_equal_approx(float(m.ram_taken), 0.9), "compute_mods: ram dealt and taken")

	# Injury debuffs: the passive is gone and the class's penalty applies.
	var hurt := _mods(crew, [0, 1, 2, 3, 4, 5])
	_check(is_equal_approx(float(hurt.repair), 0.5) and is_equal_approx(float(hurt.taken), 1.0), "injured Mechanic: repairs halved, no armor bonus")
	_check(is_equal_approx(float(hurt.util_cd), 1.5) and is_equal_approx(float(hurt.power), 0.8), "injured Spotter: cooldowns x1.5; injured Engineer: power x0.8")
	_check(is_equal_approx(float(hurt.injury), 1.5) and is_equal_approx(float(hurt.scrap), 0.5) and is_equal_approx(float(hurt.ram_taken), 1.5), "injured Medic, Scavenger, Bruiser: injury x1.5, scrap x0.5, ram taken x1.5")

	# The Garage stat sheet uses the same numbers.
	var stats := Loadout.build(Parts.STARTER_LOADOUT)
	var shown := Crew.apply_passives(stats, [_member("engineer")])
	_check(is_equal_approx(float(shown.power_output), float(stats.power_output) * 1.05), "the stat sheet shows an Engineer's power bonus")


func _check_specialties() -> void:
	var floor_c := Crew.ability(_member("driver", "Common", "speedster"))
	var floor_m := Crew.ability(_member("driver", "Mythic", "speedster"))
	print("  Floor It Common %.2f for %.1f s / %d s, Mythic %.3f for %.1f s / %d s" % [float(floor_c.speed), float(floor_c.time), int(floor_c.cooldown), float(floor_m.speed), float(floor_m.time), int(floor_m.cooldown)])
	_check(is_equal_approx(float(floor_c.speed), 0.35) and is_equal_approx(float(floor_c.time), 3.0) and is_equal_approx(float(floor_c.cooldown), 20.0), "Floor It (Common): +35% speed, 3 s, every 20 s")
	_check(is_equal_approx(float(floor_m.speed), 0.525) and is_equal_approx(float(floor_m.time), 4.5) and is_equal_approx(float(floor_m.cooldown), 15.0), "each rarity step: +10% effect and time, -1 s cooldown")
	var flare := Crew.ability(_member("spotter", "Mythic", "scout"))
	_check(is_equal_approx(float(flare.radius), 600.0), "fixed numbers don't scale (Flare stays 600 px)")
	var hl := Crew.ability(_member("driver", "Mythic", "wheelman"))
	_check(is_equal_approx(float(hl.time), 5.5) and is_equal_approx(float(hl.cooldown), 14.0), "Hard Line keeps its approved table")
	_check(not bool(Crew.ability(_member("mechanic", "Rare", "patcher")).epic) and bool(Crew.ability(_member("mechanic", "Epic", "patcher")).epic), "Field Repair adds damage cover from Epic up")
	var gear := _member("mechanic", "Common", "gearhead")
	_check(Crew.specialty_name(gear) == "Gearhead" and Crew.ability_name(gear) == "Tune-Up" and Crew.summary(gear).contains("TUNE-UP"), "cards name the specialty and its ability")
	_check(Crew.specialty(_member("mechanic", "Common", "welder")) == "gearhead" and Crew.specialty(_member("medic", "Common", "combat_medic")) == "poisoner" and Crew.specialty(_member("engineer", "Common", "overclocker")) == "conduit", "old saves: Welder, Combat Medic and Overclocker become Gearhead, Poisoner and Conduit")


func _check_perks() -> void:
	var m := profile._add_crew(_member("spotter", "Rare"))
	_check(Crew.perks_due(m) == 0 and profile.perk_offer(m).is_empty(), "no perk below level 3")
	m.xp = float(Crew.xp_for_level(3))
	var offer := profile.perk_offer(m)
	var pool := Crew.perk_pool(m)
	var distinct := {}
	for p in offer:
		distinct[p] = true
	print("  level 3 Spotter offer: %s" % ", ".join(offer))
	_check(Crew.perks_due(m) == 1 and offer.size() == 3 and distinct.size() == 3, "level 3: three different perks on offer")
	var in_pool := true
	for p in offer:
		in_pool = in_pool and pool.has(p) and (Crew.SHARED_PERKS.has(p) or (Crew.tier_pool(m) as Array).has(p))
	# Tiered perks (proposal 01): a tiered specialty's first pick offers its 2
	# Minor perks plus the 4 shared; others keep the class's 4.
	var tiered := Crew.SPECIALTY_PERKS.has(Crew.specialty(m))
	_check(in_pool and Crew.tier_pool(m).size() == 6 if tiered else (in_pool and pool.size() == 8), "offers come from the 4 shared perks plus the specialty's Minor tier (or the class's 4)")
	_check(str(profile.perk_offer(m)) == str(offer), "the offer stays the same until you pick")
	_check(not profile.choose_perk(int(m.id), "spikes"), "you can't take a perk that isn't on offer")
	_check(profile.choose_perk(int(m.id), offer[0]) and Crew.has_perk(m, offer[0]) and Crew.perks_due(m) == 0, "picking a perk keeps it")
	m.xp = float(Crew.xp_for_level(6))
	var second := profile.perk_offer(m)
	_check(second.size() == 3 and not second.has(offer[0]), "the next offer (level 6) never repeats a perk you have")
	var common := _member("driver")
	common.xp = 9999.0
	var mythic := _member("driver", "Mythic")
	mythic.xp = 9999.0
	_check(Crew.level(common) == 5 and Crew.perks_due(common) == 1 and Crew.level(mythic) == 20 and Crew.perks_due(mythic) == 6, "a Common caps at 1 perk, a Mythic earns 6")

	# Perk effects.
	_check(is_equal_approx(float(Crew.passive(_member("mechanic", "Common", "", ["veteran"])).taken), 0.05), "Veteran: passive +25%")
	var quick := Crew.ability(_member("mechanic", "Common", "gearhead", ["quick_hands", "endurance"]))
	_check(is_equal_approx(float(quick.cooldown), 17.6) and is_equal_approx(float(quick.time), 7.8), "Quick Hands: cooldown -20%; Endurance: lasts 30% longer")
	var driver := _member("driver")
	var morale := _mods([driver, _member("medic", "Common", "", ["morale"])])
	var plain := _mods([driver])
	_check(is_equal_approx(float(morale.turn) - 1.0, (float(plain.turn) - 1.0) * 1.1), "Morale: other crew's passives +10%")
	var steady := _mods([_member("mechanic"), _member("medic", "Common", "", ["steady"])], [0])
	_check(is_equal_approx(float(steady.taken), 0.98) and is_equal_approx(float(steady.repair), 0.5), "Steady: an injured Mechanic keeps half the passive (and still repairs at half)")
	var calm := _mods([_member("medic", "Common", "", ["calm"])])
	_check(is_equal_approx(float(calm.big_hit), 0.20), "Calm: a big hit needs 20% of max armor")
	var mix := _mods([_member("gunner", "Common", "", ["big_game"]), _member("mechanic", "Common", "", ["reinforced", "hardened"]), _member("scavenger", "Common", "", ["sharp_eye", "packrat", "strip_mine"])])
	_check(is_equal_approx(float(mix.big_game), 1.15) and is_equal_approx(float(mix.armor), 1.1) and is_equal_approx(float(mix.latch), 0.5), "Big Game, Reinforced, Hardened")
	_check(is_equal_approx(float(mix.schematic), 0.07) and is_equal_approx(float(mix.cache), 1.5) and is_equal_approx(float(mix.rig_scrap), 1.5), "Sharp Eye, Packrat, Strip Mine")
	var hurt_vet := _mods([_member("driver", "Common", "", ["drift_king"])], [0])
	_check(is_equal_approx(float(hurt_vet.grip), 0.0), "an injured crew member's perks stop working too")

	# Tough and Triage: a day less at the Inn.
	profile.new_game()
	var gunner := profile.seated_in("gunner")
	gunner.perks = ["tough"]
	profile.bank_crew(1, [int(gunner.id)])
	_check(int(gunner.rest) == T.CREW_REST_DAYS - 1, "Tough: rests a day less")
	profile.new_game()
	var d := profile.seated_in("driver")
	profile.bank_crew(1, [int(d.id)], true)
	_check(int(d.rest) == T.CREW_REST_DAYS - 1, "Triage on the run: injured crew rest a day less")
	profile.new_game()
	d = profile.seated_in("driver")
	d.xp = float(Crew.xp_for_level(3)) - 0.1
	var lines := profile.bank_crew(2, [])
	_check(" ".join(lines).contains("level 3, PERK READY") and profile.perks_waiting() == 1, "the results card flags a perk ready")
	profile.new_game()


func _check_seats() -> void:
	profile.new_game()
	_check(str(profile.seats()) == str(["driver", "gunner", "open"]), "Scrap Frame: Driver, Gunner and one open seat")
	profile.scrap = 5000
	var mech := _hire("mechanic", "welder")
	_check(bool(mech.seated) and profile.seated_crew().size() == 3, "a new Mechanic takes the empty open seat")
	var spot := _hire("spotter", "marker")
	_check(not bool(spot.seated) and profile.seat_block(spot) == "OPEN SEATS FULL" and not profile.seat_member(int(spot.id)), "the open seat is taken: the Spotter waits at the Inn")
	var mech2 := _hire("mechanic", "patcher")
	_check(not bool(mech2.seated) and profile.seat_block(mech2) == "", "a second Mechanic waits too, but can swap in")
	_check(profile.seat_member(int(mech2.id)) and bool(mech2.seated) and not bool(mech.seated), "one of each class: seating a Mechanic swaps out the other")
	var order: Array[String] = []
	for m in profile.seated_crew():
		order.append(str(m.role))
	_check(str(order) == str(["driver", "gunner", "mechanic"]), "riders in seat order: Driver, Gunner, open seats")
	profile.rig.chassis = "bulwark_frame"
	profile._fit_seats()
	_check(profile.seats().count("open") == 2 and profile.seat_member(int(spot.id)) and profile.seated_crew().size() == 4, "Bulwark Frame: two open seats, room for the Spotter")
	profile.rig.chassis = "courier_frame"
	profile._fit_seats()
	var courier: Array[String] = []
	for m in profile.seated_crew():
		courier.append(str(m.role))
	_check(str(courier) == str(["driver", "mechanic"]) and not bool(spot.seated), "Courier: Driver and one open seat; the rest go back to the Inn")
	profile.rig.chassis = "scrap_frame"
	profile._fit_seats()
	spot.rest = 2
	_check(profile.seat_block(spot) == "RESTING", "resting crew can't be seated")
	spot.rest = 0
	_check(profile.seat_block(_member("driver")) == "", "Driver and Gunner keep their own seats")

	# Haggler: Saloon prices -10% while a Scavenger with it is on the roster.
	var offer := {"price": 200}
	_check(profile.hire_price(offer) == 200, "Saloon price before Haggler")
	var scav := _hire("scavenger", "magpie")
	scav.perks = ["haggler"]
	_check(profile.hire_price(offer) == 180, "Haggler: 10% off at the Saloon")
	profile.new_game()


## Hire a Rare `role` through today's first Saloon offer.
func _hire(role: String, specialty: String) -> Dictionary:
	profile.ensure_saloon()
	var m := _member(role, "Rare", specialty)
	m["price"] = int(T.CREW_PRICES.Rare)
	m["hired"] = false
	profile.saloon[0] = m
	profile.hire_offer(0)
	return profile.crew[profile.crew.size() - 1]


func _check_saloon() -> void:
	var roles := {}
	var day := profile.day
	for d in range(1, 31):
		profile.day = d
		profile.saloon_day = 0
		profile.ensure_saloon()
		for m: Dictionary in profile.saloon:
			roles[str(m.role)] = true
			_check_quiet((Crew.SPECIALTIES[str(m.role)] as Array).has(str(m.specialty)), "Saloon offers have a specialty")
	profile.day = day
	profile.saloon_day = 0
	profile.ensure_saloon()
	print("  30 days of Saloon offers: %s" % str(roles.keys()))
	_check(roles.size() >= 7, "Saloon offers can be any class")
	_check(not profile.hire_basic("mechanic") and profile.hire_basic("gunner"), "the free hires are still a Driver and a Gunner")
	# Soft-lock guard: a full roster whose only Driver is resting can still take
	# the free Driver (one over the cap), but nothing else joins until someone leaves.
	profile.new_game()
	while not profile.roster_full():
		profile.hire_basic("gunner")
	var hurt: Dictionary = profile.seated_in("driver")
	hurt.rest = 2
	hurt.seated = false   # injured crew go to the Inn
	_check(profile.deploy_block() != "", "full roster, the Driver resting: can't deploy")
	_check(profile.hire_basic("driver") and profile.crew.size() == profile.roster_cap() + 1, "the free Driver joins anyway, one over the cap")
	_check(not profile.hire_basic("gunner"), "but only one over")
	profile.scrap = 100000
	profile.ensure_saloon()
	_check(profile.saloon.is_empty() or not profile.hire_offer(0), "paid hires wait until someone leaves")
	_check(profile.seat_member(int(profile.crew[profile.crew.size() - 1].id)) and profile.deploy_block() == "", "seat the new Driver and the rig can go")
	profile.new_game()


func _check_old_crew() -> void:
	var driver := ProfileScript._clean_member({"id": 3, "name": "Old Hand", "role": "driver", "rarity": "Rare", "xp": 12.0, "rest": 0, "seated": true})
	var gunner := ProfileScript._clean_member({"id": 4, "name": "Old Shot", "role": "gunner", "rarity": "Common", "xp": 2.0, "perks": ["bogus", "veteran", "veteran"]})
	_check(driver.specialty == "wheelman" and (driver.perks as Array).is_empty(), "a Driver from before specialties loads as a Wheelman")
	_check(gunner.specialty == "gunslinger" and str(gunner.perks) == str(["veteran"]), "a Gunner loads as a Gunslinger; unknown and doubled perks are dropped")
	_check(ProfileScript._clean_member({"role": "medic", "rarity": "Epic", "specialty": "welder"}).specialty == "field_medic", "a specialty from another class falls back to the class's first")
	_check(ProfileScript._clean_member({"role": "pilot", "rarity": "Epic"}).is_empty(), "an unknown class is dropped")
	profile.persist = true
	profile.save_path = "user://helriders_crew_test.json"
	var file := FileAccess.open(profile.save_path, FileAccess.WRITE)
	file.store_string(JSON.stringify({"version": 3, "scrap": 90, "schematics": ["scrap_frame"], "rig": Parts.STARTER_LOADOUT, "day": 4,
		"crew": [{"id": 1, "name": "Mae Voss", "role": "driver", "rarity": "Common", "xp": 3.0, "rest": 0, "seated": true},
			{"id": 2, "name": "Jo Kade", "role": "gunner", "rarity": "Uncommon", "xp": 0.0, "rest": 1, "seated": false}],
		"next_crew_id": 3}))
	file.close()
	var loaded := profile.load_game()
	_check(loaded and profile.crew.size() == 2 and str(profile.crew[0].specialty) == "wheelman" and str(profile.crew[1].specialty) == "gunslinger", "a save from the first crew build loads with specialties filled in")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(profile.save_path))
	profile.persist = false
	profile.save_path = "user://helriders_save.json"


func _check_inn_picker() -> void:
	var m := profile.seated_in("driver")
	m.xp = float(Crew.xp_for_level(3))
	var inn := Inn.new()
	root.add_child(inn)
	inn.select(int(m.id))
	_check(inn._perk.visible, "the Inn shows PICK PERK for a crew member with a perk waiting")
	_check(inn.open_perk_picker() and inn.is_picking_perk(), "PICK PERK opens three perk cards")
	var offer := profile.perk_offer(m)
	_check(inn.pick_perk(offer[1]) and not inn.is_picking_perk() and Crew.has_perk(m, offer[1]) and not inn._perk.visible, "tapping a card takes the perk")
	inn.queue_free()
	profile.new_game()


# --- Specialties on a live rig ------------------------------------------------------

func _seat(members: Array) -> void:
	for i in members.size():
		members[i].id = 900 + i
	rig.set_crew(members)
	mission.call("_sync_hud_to_rig")
	rig.armor = rig.armor_max


func _place(at: Vector2) -> Node2D:
	var z: Node2D = mission.zombies.spawn_at(at)
	near.append(z)
	return z


func _mission_step(f: int) -> void:
	if f == 0:
		mission.zombies.spawn_budget = 0
		mission.zombies.clear_all()
		rig.global_position = OPEN_SPOT
		rig.rotation = 0.0
		rig.velocity = Vector2.ZERO
		# Speedster, Marksman, Gearhead.
		_seat([_member("driver", "Common", "speedster"), _member("gunner", "Common", "marksman"), _member("mechanic", "Common", "gearhead")])
		_check(mission.hud.crew_wheel_size() == 3, "the crew wheel has a slice for each rider")
		_check(is_equal_approx(float(rig.crew_mod("taken")), 0.96), "a seated Mechanic takes 4% off damage")
		var hp := rig.armor
		rig.take_damage(10.0)
		_check(is_equal_approx(hp - rig.armor, 9.6), "the rig takes 9.6 of a 10-damage hit")
		var speed: float = rig.crew_speed
		_check(mission.use_crew_ability(0) and is_equal_approx(rig.crew_speed, speed * 1.35) and is_equal_approx(rig.crew_accel, 1.5), "Floor It: +35% top speed, +50% acceleration")
		_check(mission.use_crew_ability(1) and is_equal_approx(rig.crew_spread, 0.0) and is_equal_approx(float(rig.crew_mod("bullet_speed")), 1.5) and is_equal_approx(rig.crew_damage, 1.25), "Deadeye: no spread, bullets +50% faster, +25% damage")
		var fire := float(rig.crew_mod("fire"))
		_check(mission.use_crew_ability(2) and is_equal_approx(rig.crew_speed, speed * 1.35 * 1.15) and is_equal_approx(float(rig.crew_mod("fire")), fire * 1.15), "Tune-Up: +15% speed and fire rate")
		_check(mission.hud.is_crew_disabled(0) == false and rig.crew_charge(0) > 0.9, "a used ability cools down on the wheel")
	if f == 200:
		_check(not rig.ability_active("floor_it") and rig.ability_active("tune_up") and is_equal_approx(rig.crew_speed, 1.15), "Floor It ends after 3 s; Tune-Up still holds")
	if f == 250:
		_check(rig.ability_active("tune_up") and is_equal_approx(float(rig.crew_mod("taken")), 0.96), "Tune-Up lasts past 4 s (6 s)")
		# Bootlegger, Breacher, Epic Patcher.
		_seat([_member("driver", "Common", "bootlegger"), _member("gunner", "Common", "breacher"), _member("mechanic", "Epic", "patcher")])
		rig.global_position = OPEN_SPOT
		rig.rotation = 0.0
		rig.velocity = Vector2(300, 0)
		_check(mission.use_crew_ability(0) and is_equal_approx(absf(rig.rotation), PI) and rig.velocity.x < -290.0, "Bootleg Turn: swings round, keeping speed")
		rig.velocity = Vector2.ZERO
		rig.rotation = 0.0
		rig.armor = rig.armor_max
		rig.facing_armor[0] = rig.facing_max[0] - 60.0   # a battered nose for the repair to fix
		var hp := rig.armor
		_check(mission.use_crew_ability(2) and is_equal_approx(rig.armor - hp, 39.0), "Field Repair (Epic): 39 armor back")
		_check(rig.ability_active("repair_guard") and is_equal_approx(float(rig.crew_mod("taken")), 0.7 * (1.0 - 0.07)), "an Epic Patcher's repair also cuts damage 30% for 3 s")
		_check(mission.use_crew_ability(1) and int(rig.crew_mod("pierce")) == 3, "Piercing Rounds: bullets pass through 3 shamblers")
		near.clear()
		for k in 5:
			_place(OPEN_SPOT + Vector2(140 + k * 60, 0))
	if f == 254:
		mark = {"pierced": mission.bullets.pierced, "hits": mission.bullets.hits}
		mission.bullets.fire(OPEN_SPOT + Vector2(70, 0), Vector2(1500, 0), 5.0, BulletPool.TEAM_PLAYER, int(rig.crew_mod("pierce")))
	if f == 270:
		var pierced := mission.bullets.pierced - int(mark.pierced)
		var hits := mission.bullets.hits - int(mark.hits)
		print("  a piercing round passed through %d shamblers and hit %d" % [pierced, hits])
		_check(pierced == 3 and hits == 4, "one piercing round hits four shamblers in a row")
		mission.zombies.clear_all()
		near.clear()
		# Marker, Conduit, Magpie on an overloaded rig.
		mission.apply_rig(Loadout.build(OVERLOAD_BUILD))
		_seat([_member("driver"), _member("spotter", "Common", "marker"), _member("engineer", "Common", "conduit"), _member("scavenger", "Common", "magpie")])
		rig.global_position = OPEN_SPOT
		rig.velocity = Vector2.ZERO
		print("  overloaded: power %.0f / %.0f, mobility %.2f" % [rig.power_load(), rig.power_capacity(), rig.mobility()])
		_check(is_equal_approx(rig.power_capacity(), rig.power_output * 1.05), "a seated Engineer adds 5% power output")
		_check(rig.is_power_overloaded() and rig.mobility() < 1.0, "the test build is still overloaded")
		var sh_max: float = rig.shield_max
		_check(mission.use_crew_ability(2) and rig.ability_active("power_divert") and is_equal_approx(rig.shield_max, sh_max), "Power Divert: an overloaded rig has no spare power, so no bonus shield")
		mark = {"hunter": mission.spawn_hunter(OPEN_SPOT + Vector2(0, 320))}
		var close := Pickup.new()
		close.scrap_value = 10
		close.position = OPEN_SPOT + Vector2(800, 0)
		mission.pickups.add_child(close)
		var far := Pickup.new()
		far.scrap_value = 10
		far.position = OPEN_SPOT + Vector2(-1000, 0)
		mission.pickups.add_child(far)
		mark.scrap = mission.scrap
		mark.far = far
	if f == 272:
		var hunter: Node2D = mark.hunter
		_check(mission.use_crew_ability(1) and mission.marked == hunter and is_equal_approx(float(hunter.get("vuln")), 1.3), "Mark: the nearest Hunter or rig takes +30% damage")
		_check(mission.use_crew_ability(3) and is_equal_approx(mission.scrap - float(mark.scrap), 10.0) and mission.pickups.get_child_count() == 1 and (mark.far as Node).is_inside_tree(), "Magnet: pulls in salvage within 900 px, not further")
		hunter.call("deactivate")
		(mark.far as Node).queue_free()
	if f == 280:
		# Scout, Field Medic, Breaker, Salvager.
		mission.apply_rig(Loadout.build(Parts.STARTER_LOADOUT))
		_seat([_member("spotter", "Common", "scout"), _member("medic", "Common", "field_medic"), _member("bruiser", "Common", "breaker"), _member("scavenger", "Common", "salvager")])
		rig.global_position = OPEN_SPOT
		rig.velocity = Vector2.ZERO
		near.clear()
		_place(OPEN_SPOT + Vector2(100, 0))
		_place(OPEN_SPOT + Vector2(0, 400))
		_place(OPEN_SPOT + Vector2(-800, 0))
	if f == 284:
		mission.call("_refresh_hud")
		_check(mission.hud.is_crew_disabled(1) and not mission.use_crew_ability(1), "Field Dressing greys out with no one hurt")
		_check(mission.use_crew_ability(0), "Flare fires")
		var close: Node2D = near[1]
		var far: Node2D = near[2]
		_check(is_equal_approx(float(close.get("vuln")), 1.2) and is_equal_approx(float(close.call("speed_mult")), 0.6) and is_equal_approx(float(far.call("speed_mult")), 1.0), "Flare: shamblers within 600 px slowed 40% and take +20%")
		mark = {"kills": mission.kills}
		_check(mission.use_crew_ability(2), "Shockwave fires")
		var hit: Node2D = near[0]
		_check(not hit.get("active") and mission.kills == int(mark.kills) + 1 and close.get("active"), "Shockwave: 40 damage within 150 px kills the shambler beside the rig only")
		rig.injure_crew(2)
		mission.call("_refresh_hud")
		_check(not mission.hud.is_crew_disabled(1) and mission.use_crew_ability(1) and not rig.is_crew_injured(2) and mission.injured_crew_ids().is_empty(), "Field Dressing: the injured Bruiser is back in the fight and won't need rest")
		var scrap := mission.scrap
		mission.call("_add_kill", 10)
		var normal := mission.scrap - scrap
		_check(mission.use_crew_ability(3), "Gold Rush fires")
		scrap = mission.scrap
		mission.call("_add_kill", 10)
		print("  kill scrap %.1f, with Gold Rush %.1f" % [normal, mission.scrap - scrap])
		_check(is_equal_approx(mission.scrap - scrap, normal * 3.0), "Gold Rush: triple kill scrap")
		mission.zombies.clear_all()
		near.clear()
	if f == 290:
		# Poisoner, Bracer, Tinkerer on a Courier with utilities.
		mission.apply_rig(Loadout.build(COURIER_BUILD))
		_seat([_member("driver"), _member("medic", "Common", "poisoner"), _member("bruiser", "Common", "bracer"), _member("engineer", "Common", "tinkerer")])
		_check(mission.use_crew_ability(1) and rig.ability_active("miasma") and float(rig.status.left[3]) <= 0.0, "Miasma: the cloud is up and your own rig is immune")
		var ram: float = rig.crew_mod("ram")
		_check(mission.use_crew_ability(2) and is_equal_approx(float(rig.crew_mod("ram")), ram * 1.5) and is_equal_approx(float(rig.crew_mod("taken")), 0.4), "Brace: damage taken -60%, ram +50%")
		_check(mission.use_crew_ability(3) and rig.drones.size() == 2, "Scrap Drones: two drones launch")
		# A Spotter trims utility cooldowns.
		_seat([_member("driver"), _member("spotter")])
		rig.abilities[1].ready_in = 0.0
		mission.use_ability(1)
		_check(is_equal_approx(float(rig.abilities[1].ready_in), float(rig.abilities[1].cooldown) * 0.92), "a seated Spotter takes 8% off utility cooldowns")
		_finish()


# --- Helpers ----------------------------------------------------------------------------

func _check(ok: bool, what: String) -> void:
	print(("  PASS  " if ok else "  FAIL  ") + what)
	if not ok:
		failures.append(what)


## Only reports failures (for checks inside loops).
func _check_quiet(ok: bool, what: String) -> void:
	if not ok and not failures.has(what):
		print("  FAIL  " + what)
		failures.append(what)


func _finish() -> void:
	Engine.time_scale = 1.0
	if failures.is_empty():
		print("CREW TEST PASSED")
		quit(0)
	else:
		print("CREW TEST FAILED: %s" % ", ".join(failures))
		quit(1)
