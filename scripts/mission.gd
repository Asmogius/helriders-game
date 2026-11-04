extends Node2D
## One mission in the Outer Blocks, set by the job taken in Comms
## (Profile.active_mission). Four types share the block:
##   Clear    kill every shambler, Hunter and enemy rig on the list
##   Survive  hold out until the timer runs down; waves and specials escalate
##   Hunt     wreck the named Elite Outrider and grab the schematic it drops
##   Courier  hit every checkpoint in order; the faster, the better the pay
## Success banks the run's scrap, the job's pay and any schematics. A wreck
## destroys the rig and loses the run's loot. Either way, the day ends.
## Builds the whole scene in code (see AGENTS.md).

const T := preload("res://scripts/tuning.gd")
const Parts := preload("res://scripts/parts.gd")
const Loadout := preload("res://scripts/loadout.gd")
const Missions := preload("res://scripts/missions.gd")
const Arena := preload("res://scripts/arena.gd")
const Layouts := preload("res://scripts/layouts.gd")
const Splats := preload("res://scripts/splats.gd")
const GroundHazards := preload("res://scripts/ground_hazards.gd")
const ZombieDirector := preload("res://scripts/zombie_director.gd")
const Vehicle := preload("res://scripts/vehicle.gd")
const EnemyRig := preload("res://scripts/enemy_rig.gd")
const BulwarkRig := preload("res://scripts/bulwark_rig.gd")
const GunnerRig := preload("res://scripts/gunner_rig.gd")
const ScrapperRig := preload("res://scripts/scrapper_rig.gd")
const ScrapperGunnerRig := preload("res://scripts/scrapper_gunner_rig.gd")
const ConvoyRig := preload("res://scripts/convoy_rig.gd")
const PatcherRig := preload("res://scripts/patcher_rig.gd")
const FriendlyTruck := preload("res://scripts/friendly_truck.gd")
const StatusBars := preload("res://scripts/status_bars.gd")
const Barrel := preload("res://scripts/barrel.gd")
const Crew := preload("res://scripts/crew.gd")
const Hunter := preload("res://scripts/hunter.gd")
const BulletPool := preload("res://scripts/bullet_pool.gd")
const MinePool := preload("res://scripts/mine_pool.gd")
const ShellPool := preload("res://scripts/shell_pool.gd")
const Fx := preload("res://scripts/fx.gd")
const Pickup := preload("res://scripts/pickup.gd")
const LockReticle := preload("res://scripts/lock_reticle.gd")
const ChaseCamera := preload("res://scripts/chase_camera.gd")
const Hud := preload("res://scripts/hud.gd")
const GameMenu := preload("res://scripts/game_menu.gd")
const NavGrid := preload("res://scripts/nav_grid.gd")
const ProfileScript := preload("res://scripts/profile.gd")
const GARAGE_SCENE := "res://scenes/garage.tscn"
const MISSION_SCENE := "res://scenes/mission.tscn"
const STATUS_IDS := ["shock", "fire", "acid", "toxic", "slime", "goop"]
const HUNTER_POOL := 2

enum State { RUNNING, WRECKED, CLEARED, FAILED }

## Off for tests that want to place the Hunter and Outriders themselves.
var auto_spawn_specials := true
## Tests: make every Outrider drop a schematic instead of rolling for it.
var always_drop_schematic := false
## Tests: run this mission instead of the profile's.
var mission_override := {}
## Tests: ride with these crew (crew.gd dictionaries) instead of the seated ones.
var crew_override: Array = []

var spec := {}                   # the mission being run
var mission_type := "clear"
var skulls := 3                  # difficulty, 1 to 6

var arena: Arena
var splats: Splats
var hazards: GroundHazards
var barrels: Array[Barrel] = []
var barrel_layer: Node2D
var zombies: ZombieDirector
var vehicle: Vehicle
var rigs: Node2D                 # enemy rigs live here
var hunters: Array[Hunter] = []
var hunter: Hunter               # the first Hunter (tests use it)
var outriders: Array[EnemyRig] = []   # built up front, added when they spawn
var outrider: EnemyRig           # the first Outrider (tests use it)
var elite: EnemyRig              # the Hunt target, if any
var bulwarks: Array[EnemyRig] = []    # heavy rammers, built up front like Outriders
var bulwark: BulwarkRig          # the first Bulwark (tests use it)
var gunners: Array[EnemyRig] = []     # standoff turret rigs, built up front too
var gunner: GunnerRig            # the first Gunner Rig (tests use it)
var scrappers: Array[EnemyRig] = []   # trap layers, built up front too
var scrapper: ScrapperRig        # the first Scrapper (tests use it)
var scrapper_gunners: Array[EnemyRig] = []   # the harder variant, built up front too
var scrapper_gunner: ScrapperGunnerRig       # the first one (tests use it)
var use_scrapper_gunner := false             # this job's Scrapper is the Gunner variant
var convoys: Array[EnemyRig] = []     # elite semis with trailers, built up front too
var convoy: ConvoyRig            # the first Convoy Lead (tests use it)
var patchers: Array[EnemyRig] = []    # support rigs, built up front too
var patcher: PatcherRig          # the first Patcher (tests use it)
var use_patcher := false         # this job brings a Patcher (seeded, on Comms)
var _rig_crate := {}             # rig -> the crate its wreck dropped
var _held_crate := {}            # rig -> its uncollected crate, taken back when revived
var _revived := {}               # rigs a Patcher has brought back (they pay once)
var enemy_mines: MinePool        # the Scrappers' mines (hurt you and zombies)
var marked: Node2D               # the last target a Spotter marked (tests)
var bullets: BulletPool
var mines: MinePool
var shells: ShellPool             # Mortar shells in flight
var fx: Fx
var pickups: Node2D
var reticle: LockReticle
var camera: ChaseCamera
var hud: Hud
var nav: NavGrid
var markers: CourierMarkers

var state := State.RUNNING
var profile: ProfileScript          # the /root/Profile autoload
var kills := 0
var target_kills := 0            # Clear: everything that has to die
var scrap := 0.0                 # this run's scrap; only banked if you succeed
var elapsed := 0.0
var salvage: Array[Dictionary] = []
var bank_report := {}

# Courier
var checkpoints := PackedVector2Array()
var checkpoint_index := 0
var par := {}                    # "gold" / "silver" / "bronze" seconds
# Retrieve: caches around the block, an extraction point, rising danger.
var caches := PackedVector2Array()
var cache_taken: Array[bool] = []
var deep_cache := -1             # index of the guarded, double-value cache
var extract_at := Vector2.ZERO
var extract_armed := false       # left the zone once, so driving back in counts
var danger := 0                  # caches grabbed + one per RETRIEVE_STEP_SECONDS
var _base_cap := 0
var _rig_calls := 0              # rigs the job may still call in as danger climbs
var _rig_calls_made := 0
var _empty_warned := false
# Escort: the salvage truck, its sites and the driver's optional detour.
var truck: FriendlyTruck
var optional_site := Vector2.INF
var optional_offered := false
var optional_taken := false
var optional_index := -1
var optional_name := ""

var menu: GameMenu              # the pause menu while it's open
var tutorial := false           # the Training Run (optional, from MENU)
var tut_step := 0               # 0 drive, 1 shoot, 2 lock, 3 rig, 4 salvage, 5 done
var _tut_mark := {}
var _seen_timer := 0.0
var _events: Array = []          # [seconds, kind, kills that also trigger it (-1 = none), fired]


func _ready() -> void:
	profile = get_node("/root/Profile")
	tutorial = profile.tutorial_active or bool(mission_override.get("tutorial", false))
	if tutorial:
		spec = Missions.make("clear", 1, 1)
		spec.name = "Training Run"
		spec["tutorial"] = true
	elif not mission_override.is_empty():
		spec = mission_override
	elif profile.has_mission():
		spec = profile.active_mission
	else:
		spec = Missions.default_mission()
	mission_type = str(spec.type)
	skulls = Missions.skulls(spec)

	arena = Arena.new()
	# Board jobs carry a layout and vary it by their seed; test and tutorial
	# runs (no layout) use the Crossroads as drawn.
	if spec.has("layout"):
		arena.setup(Layouts.build(str(spec.layout), int(spec.get("seed", 0)) | 1))
	profile.discover("places", "map_" + str(arena.layout.id))
	splats = Splats.new()
	hazards = GroundHazards.new()
	barrel_layer = Node2D.new()
	for i in T.BARRELS_PER_JOB:
		var b := Barrel.new()
		b.hazards = hazards
		barrels.append(b)
		barrel_layer.add_child(b)
	_place_barrels()
	splats.z_index = -5
	zombies = ZombieDirector.new()
	vehicle = Vehicle.new()
	rigs = Node2D.new()
	for i in HUNTER_POOL:
		hunters.append(Hunter.new())
	hunter = hunters[0]
	bullets = BulletPool.new()
	bullets.z_index = 4
	mines = MinePool.new()
	shells = ShellPool.new()
	enemy_mines = MinePool.new()
	enemy_mines.enemy = true
	fx = Fx.new()
	fx.z_index = 5
	pickups = Node2D.new()
	reticle = LockReticle.new()
	camera = ChaseCamera.new()
	hud = Hud.new()
	nav = NavGrid.new(arena)
	markers = CourierMarkers.new()
	markers.z_index = 1

	# The rig from the garage. Tests (or a missing rig) fall back to the starter.
	if tutorial:
		# A loaner rig and crew: nothing of yours rides, nothing can be lost.
		vehicle.apply_stats(Loadout.build(T.TUTORIAL_LOADOUT))
		vehicle.cannot_wreck = true
		var dice := RandomNumberGenerator.new()
		dice.seed = 7
		vehicle.set_crew([Crew.make("driver", "Common", dice), Crew.make("gunner", "Common", dice)])
	else:
		var loadout: Dictionary = profile.rig if profile.has_rig() else Parts.STARTER_LOADOUT
		vehicle.apply_stats(profile.build_stats(loadout))
		vehicle.set_crew(crew_override if not crew_override.is_empty() else profile.seated_crew())
		profile.start_run()

	_configure_mission()

	# Wire references before adding to the tree so every _ready() sees them.
	vehicle.position = arena.player_start
	vehicle.rotation = -PI / 2.0
	vehicle.bullets = bullets
	vehicle.mines = mines
	vehicle.shells = shells
	vehicle.hazards = hazards
	vehicle.fx = fx
	vehicle.lock_candidates = lock_candidates
	for rig: EnemyRig in _all_enemy_rigs():
		rig.player = vehicle
		rig.bullets = bullets
		rig.fx = fx
		rig.arm_for_skulls(skulls)   # Gunner Rigs and the Convoy cab carry a shield from 4 skulls
	if truck != null:
		# Escort: the truck rolls out behind you, and the zombies and enemy
		# rigs go for it.
		truck.position = arena.player_start + Vector2(0, 110)
		truck.rotation = -PI / 2.0
		truck.bullets = bullets
		truck.fx = fx
		zombies.alt_target = truck
		for rig: EnemyRig in _all_enemy_rigs():
			rig.player = truck
	for h in hunters:
		h.target = vehicle
		h.nav = nav
	zombies.nav = nav
	zombies.hazards = hazards
	bullets.fx = fx
	mines.fx = fx
	shells.fx = fx
	for b in barrels:
		b.fx = fx
	enemy_mines.fx = fx
	zombies.target = vehicle
	zombies.spawn_points = arena.spawn_points
	camera.target = vehicle
	reticle.rig = vehicle
	markers.mission = self

	# Tree order is also physics order:
	# inputs (here) -> zombies -> player rig -> enemy rigs -> hunters -> bullets.
	# Hunters run after the rig so they see this tick's wall contact.
	for node: Node in [arena, splats, hazards, markers, mines, enemy_mines, barrel_layer, pickups, zombies, vehicle, rigs]:
		add_child(node)
	if truck != null:
		add_child(truck)
	for h in hunters:
		add_child(h)
	for node: Node in [bullets, shells, fx, reticle, camera, hud]:
		add_child(node)

	camera.set_bounds(Rect2(Vector2.ZERO, T.WORLD_SIZE))
	camera.global_position = vehicle.global_position
	camera.make_current()

	zombies.zombie_killed.connect(_on_zombie_killed)
	vehicle.wrecked.connect(_on_wrecked)
	vehicle.status_started.connect(_on_status_started)
	vehicle.crew_injured.connect(_on_crew_injured)
	vehicle.crew_healed.connect(_on_crew_healed)
	vehicle.crew_ability_used.connect(_on_crew_ability)
	vehicle.damaged.connect(_on_damaged)
	for h in hunters:
		h.died.connect(_on_hunter_died.bind(h))
		h.latched_on.connect(func() -> void: hud.set_alert("HUNTER ON THE HULL  -  SCRAPE IT ON A WALL"))
		h.let_go.connect(_on_hunter_let_go)
	for rig in _all_enemy_rigs():
		rig.tree_entered.connect(func() -> void: profile.discover("enemies", _rig_key(rig)))
	for rig in outriders:
		rig.wrecked.connect(_on_outrider_wrecked.bind(rig))
	for rig in bulwarks:
		rig.wrecked.connect(_on_bulwark_wrecked.bind(rig))
	for rig in gunners:
		rig.wrecked.connect(_on_gunner_wrecked.bind(rig))
	for rig in scrappers:
		rig.wrecked.connect(_on_scrapper_wrecked.bind(rig))
	for rig in scrapper_gunners:
		rig.wrecked.connect(_on_scrapper_gunner_wrecked.bind(rig))
	for rig in patchers:
		rig.wrecked.connect(_on_patcher_wrecked.bind(rig))
	for rig in _all_enemy_rigs():
		rig.revived.connect(_on_rig_revived.bind(rig))
	for rig in convoys:
		rig.wrecked.connect(_on_convoy_wrecked.bind(rig))
		(rig as ConvoyRig).trailer.wrecked.connect(_on_trailer_lost.bind(rig))
	if elite != null:
		elite.wrecked.connect(_on_elite_wrecked)
	if truck != null:
		truck.wrecked.connect(_on_truck_lost)
		truck.site_reached.connect(_on_site_reached)
		truck.site_done.connect(_on_site_done)
		hud.choice_made.connect(_on_optional_choice)
	hud.restart_requested.connect(return_to_garage)
	hud.pause_pressed.connect(open_menu)
	for b in barrels:
		b.died.connect(func(_at: Vector2) -> void: profile.discover("hazards", "barrel_" + b.kind))
	# Quality preset: how much is drawn, and how hard the camera shakes.
	var q := profile.quality()
	fx.density = float(q.fx)
	splats.density = float(q.splats)
	camera.shake_mult = float(q.shake) if bool(profile.settings.get("shake", true)) else 0.0
	hud.lock_toggled.connect(func(on: bool) -> void: vehicle.lock_enabled = on)
	hud.ability_pressed.connect(use_ability)
	hud.crew_picked.connect(use_crew_ability)
	hud.crew_wheel_toggled.connect(_on_crew_wheel)
	_sync_hud_to_rig()
	hud.banner("%s  -  %s" % [Missions.label(spec), str(spec.name).to_upper()], _type_color(), 3.0)
	_refresh_hud()


## Crowd size, specials and objective for this mission's type and skulls.
func _configure_mission() -> void:
	var cap: int = Missions.stat(spec, "cap")
	zombies.cap = cap
	zombies.set_mix(skulls, mission_type == "courier")
	var outrider_count := 0
	var bulwark_count := 0
	var gunner_count := 0
	var scrapper_count := 0
	var convoy_count := 0
	match mission_type:
		"clear":
			var shamblers: int = Missions.stat(spec, "shamblers")
			var hunter_count: int = Missions.stat(spec, "hunters")
			outrider_count = Missions.stat(spec, "outriders")
			bulwark_count = Missions.stat(spec, "bulwarks")
			gunner_count = Missions.stat(spec, "gunners")
			scrapper_count = Missions.stat(spec, "scrappers")
			if Missions.has_convoy(spec):
				convoy_count = 1
				outrider_count = maxi(outrider_count - 1, 0)
				_events.append([T.OUTRIDER_SPAWN_TIME, "convoy", T.OUTRIDER_SPAWN_KILLS, false])
			zombies.spawn_budget = shamblers
			zombies.start_count = mini(T.ZOMBIE_START, cap)
			target_kills = shamblers + hunter_count + outrider_count + bulwark_count + gunner_count + scrapper_count + convoy_count
			for i in scrapper_count:
				_events.append([T.SCRAPPER_SPAWN_TIME + 40.0 * i, "scrapper", T.SCRAPPER_SPAWN_KILLS if i == 0 else -1, false])
			for i in gunner_count:
				_events.append([T.GUNNER_SPAWN_TIME + 40.0 * i, "gunner", T.GUNNER_SPAWN_KILLS if i == 0 else -1, false])
			for i in bulwark_count:
				_events.append([T.BULWARK_SPAWN_TIME + 40.0 * i, "bulwark", T.BULWARK_SPAWN_KILLS if i == 0 else -1, false])
			for i in hunter_count:
				_events.append([T.HUNTER_SPAWN_TIME + 35.0 * i, "hunter", T.HUNTER_SPAWN_KILLS if i == 0 else -1, false])
			for i in outrider_count:
				_events.append([T.OUTRIDER_SPAWN_TIME + 40.0 * i, "outrider", T.OUTRIDER_SPAWN_KILLS if i == 0 else -1, false])
		"survive":
			zombies.spawn_budget = 1000000
			zombies.start_count = 10
			zombies.ramp_seconds = Missions.stat(spec, "ramp")
			var swap := Missions.has_convoy(spec)
			for e: Array in Missions.stat(spec, "events"):
				var kind := str(e[1])
				if swap and kind == "outrider":
					kind = "convoy"   # the Convoy Lead takes the first Outrider's slot
					swap = false
					convoy_count += 1
				_events.append([float(e[0]), kind, -1, false])
				if kind == "outrider":
					outrider_count += 1
				elif e[1] == "bulwark":
					bulwark_count += 1
				elif e[1] == "gunner":
					gunner_count += 1
				elif e[1] == "scrapper":
					scrapper_count += 1
		"hunt":
			zombies.spawn_budget = 1000000
			zombies.start_count = mini(8, cap)
			elite = EnemyRig.new()
			elite.make_elite(str(spec.name).to_upper(), Missions.stat(spec, "elite_armor"), Missions.stat(spec, "elite_damage"))
			_events.append([3.0, "elite", -1, false])
			outrider_count = Missions.stat(spec, "escorts")
			if Missions.has_convoy(spec):
				convoy_count = 1
				outrider_count = maxi(outrider_count - 1, 0)
				_events.append([3.0, "convoy_escort", -1, false])
			for i in outrider_count:
				_events.append([3.0, "escort", -1, false])
			bulwark_count = Missions.stat(spec, "bulwark_escorts")
			for i in bulwark_count:
				_events.append([3.0, "bulwark_escort", -1, false])
			gunner_count = Missions.stat(spec, "gunner_escorts")
			for i in gunner_count:
				_events.append([3.0, "gunner_escort", -1, false])
			for i in int(Missions.stat(spec, "hunters")):
				_events.append([40.0 + 40.0 * i, "hunter", -1, false])
		"courier":
			zombies.spawn_budget = 1000000
			zombies.start_count = mini(6, cap)
			zombies.ramp_seconds = 5.0
			_plan_route(int(Missions.stat(spec, "checkpoints")))
			for i in int(Missions.stat(spec, "hunters")):
				_events.append([30.0, "hunter", -1, false])
			outrider_count = Missions.stat(spec, "outriders")
			for i in outrider_count:
				_events.append([50.0, "outrider", -1, false])
			gunner_count = Missions.stat(spec, "gunners")
			for i in gunner_count:
				_events.append([3.0, "gunner_guard", -1, false])
			scrapper_count = Missions.stat(spec, "scrappers")
			for i in scrapper_count:
				_events.append([20.0, "scrapper", -1, false])
	match mission_type:
		"retrieve":
			zombies.spawn_budget = 1000000
			zombies.pool_size = T.ZOMBIE_CAP
			zombies.start_count = mini(8, cap)
			_base_cap = cap
			extract_at = arena.player_start
			_plan_caches(int(Missions.stat(spec, "caches")))
			for i in int(Missions.stat(spec, "hunters")):
				_events.append([50.0 + 45.0 * i, "hunter", -1, false])
			_rig_calls = int(Missions.stat(spec, "rig_calls"))
			for i in _rig_calls:
				match _rig_call_kind(i):
					"scrapper":
						scrapper_count += 1
					"outrider":
						outrider_count += 1
					_:
						gunner_count += 1
			gunner_count += 1   # the deep cache's guard
			_events.append([1.0, "deep_guard", -1, false])
		"escort":
			zombies.spawn_budget = 1000000
			zombies.pool_size = T.ZOMBIE_CAP
			zombies.start_count = mini(8, cap)
			zombies.ramp_seconds = Missions.stat(spec, "ramp")
			for e: Array in Missions.stat(spec, "events"):
				var kind := str(e[1])
				_events.append([float(e[0]), kind, -1, false])
				match kind:
					"outrider":
						outrider_count += 1
					"bulwark":
						bulwark_count += 1
					"gunner":
						gunner_count += 1
					"scrapper":
						scrapper_count += 1
			outrider_count += 1   # the optional site may call one in
			for i in int(Missions.stat(spec, "hunters")):
				_events.append([60.0 + 45.0 * i, "hunter", -1, false])
			truck = FriendlyTruck.new()
			truck.nav = nav
			_plan_sites(int(Missions.stat(spec, "sites")))
	# Always keep one Outrider ready (tests spawn one by hand); never more
	# rigs than the design's cap of three.
	var room := T.MAX_ENEMY_RIGS - (1 if elite != null else 0)
	for i in clampi(maxi(outrider_count, 1), 1, room):
		outriders.append(EnemyRig.new())
	outrider = outriders[0]
	# Same for Bulwarks: one always ready, never past the cap together.
	for i in clampi(maxi(bulwark_count, 1), 1, maxi(room - outrider_count, 1)):
		bulwarks.append(BulwarkRig.new())
	bulwark = bulwarks[0] as BulwarkRig
	# Gunner Rigs: one always ready. Spawns wait for room under the cap.
	for i in maxi(gunner_count, 1):
		gunners.append(GunnerRig.new())
	gunner = gunners[0] as GunnerRig
	use_scrapper_gunner = Missions.has_scrapper_gunner(spec)
	for i in (1 if use_scrapper_gunner else maxi(scrapper_count, 1)):
		scrappers.append(ScrapperRig.new())
	scrapper = scrappers[0] as ScrapperRig
	for i in (maxi(scrapper_count, 1) if use_scrapper_gunner else 1):
		scrapper_gunners.append(ScrapperGunnerRig.new())
	scrapper_gunner = scrapper_gunners[0] as ScrapperGunnerRig
	for i in maxi(convoy_count, 1):
		convoys.append(ConvoyRig.new())
	convoy = convoys[0] as ConvoyRig
	if tutorial:
		# Scripted: nothing comes on its own.
		_events.clear()
		zombies.spawn_budget = 0
		zombies.start_count = 0
		target_kills = 1 << 30
	# Patcher: one, rolled per job; it waits for an ally to work on.
	use_patcher = Missions.has_patcher(spec)
	patchers.append(PatcherRig.new())
	patcher = patchers[0] as PatcherRig
	if use_patcher:
		_events.append([0.0, "patcher", -1, false])
		if mission_type == "clear":
			target_kills += 1


func _physics_process(delta: float) -> void:
	if state != State.RUNNING:
		vehicle.drive_input = Vector2.ZERO
		vehicle.aim_input = Vector2.ZERO
		return
	elapsed += delta
	_seen_timer -= delta
	if _seen_timer <= 0.0:
		_seen_timer = 1.0
		for z in zombies.active_zombies():
			profile.discover("enemies", str(z.kind))
	vehicle.drive_input = hud.left_stick.output
	vehicle.aim_input = hud.right_stick.output
	if tutorial:
		_tutorial_tick()
	if auto_spawn_specials:
		_run_events()
	_collect_pickups()
	_apply_slime(delta)
	match mission_type:
		"survive":
			if elapsed >= float(Missions.stat(spec, "seconds")):
				_succeed("HELD THE BLOCK", "", 1.0)
		"courier":
			if checkpoint_index < checkpoints.size() and vehicle.global_position.distance_to(checkpoints[checkpoint_index]) < T.COURIER_RADIUS:
				reach_checkpoint()
		"retrieve":
			_update_retrieve()


func _process(_delta: float) -> void:
	_refresh_hud()
	hud.right_stick.set_gauges(vehicle.weapon_gauges())
	bullets.big_game = float(vehicle.crew_mod("big_game"))


## Swap the player's rig to `stats` mid-mission (tests) and update the HUD.
func apply_rig(stats: Dictionary) -> void:
	vehicle.apply_stats(stats)
	_sync_hud_to_rig()


## LOCK, the CREW wheel and utility buttons follow the rig's parts and crew.
func _sync_hud_to_rig() -> void:
	hud.set_lock_available(vehicle.can_lock())
	var kinds: Array[String] = []
	for a in vehicle.abilities:
		kinds.append(str(a.ability))
	hud.set_abilities(kinds)
	var entries: Array[Dictionary] = []
	for c in vehicle.crew:
		entries.append({"kind": str(c.ability.kind), "ability": str(c.ability.name), "name": str(c.name), "role": str(c.role)})
	hud.set_crew_wheel(entries)
	for i in vehicle.crew.size():
		_crew_state(i)


func _crew_state(i: int) -> void:
	var injured := vehicle.is_crew_injured(i)
	var usable := _crew_usable(i)
	hud.set_crew_state(i, vehicle.crew_charge(i), injured or not usable, "INJURED" if injured else ("NO ONE HURT" if not usable else ""))


## Field Dressing only works with someone to treat.
func _crew_usable(i: int) -> bool:
	if str(vehicle.crew[i].ability.kind) != "field_dressing":
		return true
	for c in vehicle.crew:
		if bool(c.injured):
			return true
	return false


## The crew wheel slows the fight while it's open.
func _on_crew_wheel(open: bool) -> void:
	Engine.time_scale = T.CREW_WHEEL_SLOWMO if open and state == State.RUNNING else 1.0


## Fire the rig's utility `index`.
func use_ability(index: int) -> bool:
	if state != State.RUNNING:
		return false
	return vehicle.use_ability(index)


## Fire crew member `index`'s triggered ability.
func use_crew_ability(index: int) -> bool:
	if state != State.RUNNING:
		return false
	var ok := vehicle.use_crew_ability(index)
	if ok:
		for i in vehicle.crew.size():
			_crew_state(i)
		var c := vehicle.crew[index]
		hud.banner("%s  -  %s" % [str(c.ability.name).to_upper(), str(c.name).to_upper()], Crew.ROLE_COLORS.get(str(c.role), T.COL_CYAN), 1.2)
	return ok


const INJURY_TEXT := {
	"driver": "STEERING HALVED", "gunner": "TURRET AIM HALVED", "mechanic": "REPAIRS HALVED",
	"spotter": "UTILITY COOLDOWNS UP", "engineer": "POWER DOWN", "medic": "CREW MORE AT RISK",
	"scavenger": "KILL SCRAP HALVED", "bruiser": "RAMS HURT MORE",
}


func _on_crew_injured(index: int) -> void:
	var c := vehicle.crew[index]
	var role := str(c.role)
	hud.banner("%s INJURED  -  %s" % [role.to_upper(), INJURY_TEXT.get(role, "")], T.COL_ENEMY, 2.5)
	camera.shake(0.6)


func _on_crew_healed(index: int) -> void:
	hud.banner("%s PATCHED UP" % str(vehicle.crew[index].name).to_upper(), Color(0.45, 0.9, 0.5), 1.8)


## Crew abilities that reach past the rig: Mark, Flare, Magnet.
func _on_crew_ability(kind: String, a: Dictionary) -> void:
	var weak := float(vehicle.crew_mod("weak_spot"))
	match kind:
		"mark":
			var target: Node2D = vehicle.lock_target
			if target == null:
				var best := INF
				for c: Node2D in lock_candidates():
					if int(c.get("lock_priority")) < 2:
						continue
					var d := c.global_position.distance_to(vehicle.global_position)
					if d < best:
						best = d
						target = c
			if target != null:
				target.call("apply_status", 1.0 + float(a.vuln) + weak, 1.0, float(a.time))
				marked = target
		"flare":
			var r2 := float(a.radius) * float(a.radius)
			for z in zombies.active_zombies():
				if z.global_position.distance_squared_to(vehicle.global_position) <= r2:
					z.apply_status(1.0 + float(a.vuln) + weak, 1.0 - minf(float(a.slow), 0.9), float(a.time))
			fx.call("blast", vehicle.global_position, 60.0)
		"magnet":
			var r := float(a.radius)
			for p in pickups.get_children():
				if (p as Node2D).global_position.distance_to(vehicle.global_position) <= r:
					_take_salvage(p as Pickup)


func return_to_garage() -> void:
	Engine.time_scale = 1.0
	if tutorial:
		# Done: on to the garage tour (a sandbox; end_tour puts it all back).
		profile.tutorial_active = false
		if tut_step >= 5:
			profile.begin_tour()
	get_tree().change_scene_to_file(GARAGE_SCENE)


# --- Tutorial: the Training Run ------------------------------------------------------

const TUT_TIPS := [
	"DRIVE: push the LEFT stick where you want to go. The rig turns to follow. Pull back to reverse.",
	"SHOOT: push the RIGHT stick toward a zombie to aim the turret. Push it all the way to fire.",
	"LOCK: tap the LOCK button. While it's on, your turret picks targets and fires by itself.",
	"ENEMY RIG: an Outrider is coming. Keep moving, it shoots back. Wreck it.",
	"SALVAGE: drive over the crate to pick up its schematic.",
]


func _tutorial_tick() -> void:
	if not _tut_mark.has("step") or int(_tut_mark.step) != tut_step:
		_tut_begin()
	match tut_step:
		0:
			if vehicle.global_position.distance_to(_tut_mark.from) > 350.0:
				_tut_next()
		1:
			if kills - int(_tut_mark.kills) >= 4:
				_tut_next()
		2:
			if not bool(_tut_mark.get("spawned", false)):
				if vehicle.lock_enabled:
					_tut_mark.spawned = true
					_tut_mark.kills = kills
					hud.set_tip("Good. Now let LOCK do the aiming: just drive.")
					_tut_spawn_pack(4)
			elif kills - int(_tut_mark.kills) >= 4:
				_tut_next()
			elif zombies.active_zombies().is_empty():
				_tut_spawn_pack(4 - (kills - int(_tut_mark.kills)))
		3:
			if outrider.is_wrecked:
				_tut_next()
		4:
			if not salvage.is_empty():
				_tut_next()


func _tut_begin() -> void:
	_tut_mark = {"step": tut_step, "kills": kills, "from": vehicle.global_position}
	if tut_step < TUT_TIPS.size():
		hud.set_tip(TUT_TIPS[tut_step])
	match tut_step:
		1:
			_tut_spawn_pack(4)
		3:
			var o := spawn_outrider(_open_spot(650.0))
			if o != null:
				o.armor_max = o.armor_max * 0.6   # a softer one for practice
				o.armor = o.armor_max
		5:
			hud.set_tip("")
			state = State.CLEARED
			hud.show_result("TRAINING DONE",
				"That's the fight: drive, shoot, lock on, wreck rigs and haul their salvage home.\nNext, the garage: that's where salvage turns into parts.\nNothing here counted: no day passed and nothing was paid.",
				"TO THE GARAGE", T.COL_CYAN)


func _tut_next() -> void:
	tut_step += 1
	hud.banner("NICE", T.COL_CYAN, 1.0)


func _tut_spawn_pack(count: int) -> void:
	for i in maxi(count, 0):
		zombies.spawn_at(_open_spot(360.0 + 40.0 * i), "shambler")


## A clear spot about `dist` from the rig (not inside a building), with a
## line of sight to it.
func _open_spot(dist: float) -> Vector2:
	var space := get_world_2d().direct_space_state
	var q := PhysicsPointQueryParameters2D.new()
	q.collision_mask = T.LAYER_WORLD
	var start := randf() * TAU
	for k in 16:
		var at := vehicle.global_position + Vector2.RIGHT.rotated(start + TAU * k / 16.0) * dist
		if at.x < 80.0 or at.y < 80.0 or at.x > T.WORLD_SIZE.x - 80.0 or at.y > T.WORLD_SIZE.y - 80.0:
			continue
		q.position = at
		if space.intersect_point(q, 1).is_empty() and vehicle._has_los(at):
			return at
	return vehicle.global_position + Vector2.RIGHT.rotated(start) * dist


## Leave the Training Run from the pause menu: back to the garage, no tour.
func leave_tutorial() -> void:
	menu = null
	get_tree().paused = false
	profile.tutorial_active = false
	Engine.time_scale = 1.0
	get_tree().change_scene_to_file(GARAGE_SCENE)


## The Database id of an enemy rig.
func _rig_key(rig: EnemyRig) -> String:
	if rig.is_elite():
		return "elite"
	if rig is ConvoyRig:
		return "convoy"
	if rig is BulwarkRig:
		return "bulwark"
	if rig is ScrapperGunnerRig:
		return "scrapper_gunner"
	if rig is ScrapperRig:
		return "scrapper"
	if rig is PatcherRig:
		return "patcher"
	if rig is GunnerRig:
		return "gunner"
	return "outrider"


# --- Pause menu ------------------------------------------------------------------------

## Pause and open the menu (the HUD's II button, the phone's back button, or
## the app going to the background). Not over a result card or the driver's
## radio call.
func open_menu() -> GameMenu:
	if menu != null or state != State.RUNNING or hud.is_result_visible() or get_tree().paused:
		return menu
	hud.close_crew_wheel(false)
	Engine.time_scale = 1.0
	get_tree().paused = true
	menu = GameMenu.new()
	menu.setup(profile, true, tutorial)
	menu.leave_requested.connect(leave_tutorial)
	menu.resumed.connect(_on_menu_closed)
	menu.restart_requested.connect(restart_job)
	hud.add_child(menu)
	return menu


func _on_menu_closed() -> void:
	menu = null
	get_tree().paused = false


## The fight starts over: same job, same rig and crew, nothing lost.
func restart_job() -> void:
	menu = null
	get_tree().paused = false
	Engine.time_scale = 1.0
	if mission_override.is_empty():
		get_tree().change_scene_to_file(MISSION_SCENE)
		return
	# Tests run a job from an override: rebuild it in place.
	var again := (load(MISSION_SCENE) as PackedScene).instantiate()
	again.set("mission_override", mission_override)
	again.set("auto_spawn_specials", auto_spawn_specials)
	var parent := get_parent()
	queue_free()
	parent.add_child(again)


func _notification(what: int) -> void:
	match what:
		NOTIFICATION_WM_GO_BACK_REQUEST:
			if menu != null:
				menu.back()
			else:
				open_menu()
		NOTIFICATION_APPLICATION_PAUSED, NOTIFICATION_APPLICATION_FOCUS_OUT:
			if not DisplayServer.get_name() == "headless":
				open_menu()


func _exit_tree() -> void:
	Engine.time_scale = 1.0
	if is_inside_tree():
		get_tree().paused = false
	# Rigs are built up front; free any that never made it into the fight.
	for rig in _all_enemy_rigs():
		if not rig.is_inside_tree():
			rig.free()
	for crate: Variant in _held_crate.values():
		if is_instance_valid(crate):
			(crate as Node).free()


func _all_enemy_rigs() -> Array[EnemyRig]:
	var all: Array[EnemyRig] = outriders.duplicate()
	all.append_array(bulwarks)
	all.append_array(gunners)
	all.append_array(scrappers)
	all.append_array(scrapper_gunners)
	all.append_array(convoys)
	all.append_array(patchers)
	if elite != null:
		all.append(elite)
	return all


# --- Spawning ----------------------------------------------------------------

func _run_events() -> void:
	for e: Array in _events:
		if e[3]:
			continue
		var due := elapsed >= float(e[0]) or (int(e[2]) >= 0 and kills >= int(e[2]))
		if not due:
			continue
		match str(e[1]):
			"hunter":
				e[3] = spawn_hunter(zombies.pick_spawn_point()) != null
			"outrider":
				e[3] = spawn_outrider(zombies.pick_spawn_point()) != null
			"elite":
				spawn_elite(zombies.pick_spawn_point())
				e[3] = true
			"escort":
				var near: Vector2 = elite.global_position + Vector2(randf_range(-80, 80), randf_range(-80, 80)) if elite.is_inside_tree() else zombies.pick_spawn_point()
				e[3] = spawn_outrider(near) != null
			"bulwark":
				e[3] = spawn_bulwark(zombies.pick_spawn_point()) != null
			"bulwark_escort":
				var near: Vector2 = elite.global_position + Vector2(randf_range(-120, 120), randf_range(-120, 120)) if elite.is_inside_tree() else zombies.pick_spawn_point()
				e[3] = spawn_bulwark(near) != null
			"gunner":
				e[3] = spawn_gunner(zombies.pick_spawn_point()) != null
			"scrapper":
				e[3] = spawn_scrapper(zombies.pick_spawn_point()) != null
			"convoy":
				e[3] = spawn_convoy(zombies.pick_spawn_point()) != null
			"patcher":
				# Only alongside another rig, unless none are left to come.
				if _ally_in_fight() or not _rig_events_pending():
					e[3] = spawn_patcher(zombies.pick_spawn_point()) != null
			"deep_guard":
				# A Gunner Rig parked on the deep cache.
				var post := caches[deep_cache] if deep_cache >= 0 else zombies.pick_spawn_point()
				var guard := spawn_gunner(post + Vector2(randf_range(-110, 110), randf_range(-110, 110)), false)
				if guard != null:
					(guard as GunnerRig).guard_point = post
				e[3] = guard != null
			"convoy_escort":
				var near: Vector2 = elite.global_position + Vector2(randf_range(-180, 180), randf_range(-180, 180)) if elite.is_inside_tree() else zombies.pick_spawn_point()
				e[3] = spawn_convoy(near) != null
			"gunner_escort":
				var near: Vector2 = elite.global_position + Vector2(randf_range(-160, 160), randf_range(-160, 160)) if elite.is_inside_tree() else zombies.pick_spawn_point()
				e[3] = spawn_gunner(near) != null
			"gunner_guard":
				# Covers a checkpoint about halfway along the route.
				var post := checkpoints[checkpoints.size() / 2] if not checkpoints.is_empty() else zombies.pick_spawn_point()
				var rig := spawn_gunner(post + Vector2(randf_range(-120, 120), randf_range(-120, 120)), false)
				if rig != null:
					(rig as GunnerRig).guard_point = post
				e[3] = rig != null


## Activates a pooled Hunter. Returns it, or null if both are already out.
func spawn_hunter(at: Vector2) -> Hunter:
	for h in hunters:
		if not h.active:
			h.activate(at)
			profile.discover("enemies", "hunter")
			hud.banner("HUNTER IN THE BLOCK", T.COL_HUNTER)
			return h
	return null


## Sends in the next Outrider. Returns it, or null if they're all out.
func spawn_outrider(at: Vector2) -> EnemyRig:
	for rig in outriders:
		if not rig.is_inside_tree():
			rig.position = at
			rig.rotation = (vehicle.global_position - at).angle()
			rigs.add_child(rig)
			hud.banner("ENEMY RIG INBOUND", T.COL_ENEMY)
			return rig
	return null


## Sends in the next Bulwark. Returns it, or null if they're all out.
func spawn_bulwark(at: Vector2) -> EnemyRig:
	for rig in bulwarks:
		if not rig.is_inside_tree():
			rig.position = at
			rig.rotation = (vehicle.global_position - at).angle()
			rigs.add_child(rig)
			hud.banner("BULWARK INBOUND  -  HIT ITS SIDES", T.COL_ENEMY)
			return rig
	return null


## Sends in the next Gunner Rig, if there's room under the rig cap. Returns
## it, or null (the event tries again later).
func spawn_gunner(at: Vector2, announce := true) -> EnemyRig:
	if active_rig_count() >= T.MAX_ENEMY_RIGS:
		return null
	for rig in gunners:
		if not rig.is_inside_tree():
			rig.position = at
			rig.rotation = (vehicle.global_position - at).angle()
			rigs.add_child(rig)
			if announce:
				hud.banner("GUNNER RIG INBOUND  -  KEEP MOVING", T.COL_ENEMY)
			return rig
	return null


## Sends in the next Scrapper (this job's variant), if there's room under the
## rig cap. `gunner` forces the Scrapper Gunner (tests).
func spawn_scrapper(at: Vector2, gunner := false) -> EnemyRig:
	if active_rig_count() >= T.MAX_ENEMY_RIGS:
		return null
	var pool := scrapper_gunners if (gunner or use_scrapper_gunner) else scrappers
	for rig in pool:
		if not rig.is_inside_tree():
			var s := rig as ScrapperRig
			s.enemy_mines = enemy_mines
			s.hazards = hazards
			rig.position = at
			rig.rotation = (vehicle.global_position - at).angle()
			rigs.add_child(rig)
			hud.banner(("SCRAPPER GUNNER" if rig is ScrapperGunnerRig else "SCRAPPER") + " INBOUND  -  WATCH FOR TRAPS", T.COL_ENEMY)
			return rig
	return null


## Sends in the next Convoy Lead (cab and trailer, one rig toward the cap).
func spawn_convoy(at: Vector2) -> EnemyRig:
	if active_rig_count() >= T.MAX_ENEMY_RIGS:
		return null
	for rig in convoys:
		if not rig.is_inside_tree():
			rig.position = at
			rig.rotation = (vehicle.global_position - at).angle()
			rigs.add_child(rig)
			hud.banner("CONVOY LEAD INBOUND  -  GET BESIDE IT", T.COL_ENEMY)
			return rig
	return null


## Sends in the Patcher, if there's room under the rig cap.
func spawn_patcher(at: Vector2) -> EnemyRig:
	if active_rig_count() >= T.MAX_ENEMY_RIGS:
		return null
	for rig in patchers:
		if not rig.is_inside_tree():
			rig.position = at
			rig.rotation = (vehicle.global_position - at).angle()
			rigs.add_child(rig)
			hud.banner("PATCHER INBOUND  -  CUT ITS CABLE", T.COL_ENEMY)
			return rig
	return null


## A working enemy rig (not a Patcher) is in the fight.
func _ally_in_fight() -> bool:
	for rig in rigs.get_children():
		if not rig.get("is_wrecked") and not rig is PatcherRig:
			return true
	return false


## Rig events that haven't fired yet (not counting the Patcher's own).
func _rig_events_pending() -> bool:
	for e: Array in _events:
		if not e[3] and str(e[1]) != "patcher" and str(e[1]) != "hunter":
			return true
	return mission_type == "retrieve" and _rig_calls_made < _rig_calls


## Enemy rigs in the fight right now (wrecks don't count).
func active_rig_count() -> int:
	var n := 0
	for rig in rigs.get_children():
		if not rig.get("is_wrecked"):
			n += 1
	return n


func spawn_elite(at: Vector2) -> void:
	if elite == null or elite.is_inside_tree():
		return
	elite.position = at
	elite.rotation = (vehicle.global_position - at).angle()
	rigs.add_child(elite)
	hud.banner("TARGET: %s" % elite.elite_name, T.COL_ELITE, 3.0)


## Everything the player's lock-on may consider.
func lock_candidates() -> Array[Node2D]:
	var out: Array[Node2D] = []
	for z in zombies.active_zombies():
		out.append(z)
	for h in hunters:
		if h.active:
			out.append(h)
	for rig in rigs.get_children():
		if not rig.get("is_wrecked"):
			out.append(rig as Node2D)
		var trailer: Variant = rig.get("trailer")
		if trailer is Node2D and not (trailer as Node2D).get("is_wrecked"):
			out.append(trailer as Node2D)
	return out


# --- Courier -------------------------------------------------------------------

## Picks a route of `count` checkpoints from the arena's list, each a fair
## drive from the last, and sets par times from the nav-grid path length.
func _plan_route(count: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(spec.seed)
	var pool: Array = arena.checkpoints.duplicate()
	var at := arena.player_start
	var length := 0.0
	for i in count:
		var options: Array = pool.filter(func(p: Vector2) -> bool:
			var d := at.distance_to(p)
			return d >= 500.0 and d <= 1700.0)
		if options.is_empty():
			options = pool
		var next: Vector2 = options[rng.randi_range(0, options.size() - 1)]
		pool.erase(next)
		checkpoints.append(next)
		length += _path_length(at, next)
		at = next
	var gold := (length / T.COURIER_PAR_SPEED + T.COURIER_PAR_PER_CHECKPOINT * count) * float(vehicle.crew_mod("par"))
	par = {"gold": gold, "silver": gold * T.COURIER_SILVER, "bronze": gold * T.COURIER_BRONZE}


func _path_length(a: Vector2, b: Vector2) -> float:
	var path := nav.astar.get_point_path(nav.cell_of(a), nav.cell_of(b), true)
	if path.size() < 2:
		return a.distance_to(b)
	var total := a.distance_to(path[0])
	for i in range(1, path.size()):
		total += path[i - 1].distance_to(path[i])
	return total + path[path.size() - 1].distance_to(b)


func reach_checkpoint() -> void:
	checkpoint_index += 1
	if checkpoint_index >= checkpoints.size():
		var tier := courier_tier()
		var title := "DELIVERED  -  %s" % tier.to_upper() if tier != "late" else "DELIVERED LATE"
		_succeed(title, "Time %s" % _clock(elapsed), float(T.COURIER_TIER_PAY[tier]))
	else:
		hud.banner("CHECKPOINT %d / %d" % [checkpoint_index, checkpoints.size()], T.COL_CYAN, 1.2)


func courier_tier() -> String:
	for tier: String in ["gold", "silver", "bronze"]:
		if elapsed <= float(par[tier]):
			return tier
	return "late"


# --- Retrieve ----------------------------------------------------------------------

## Spread the caches over the block, away from the extraction point; the
## farthest one is the deep cache.
func _plan_caches(count: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(spec.seed)
	var pool: Array = arena.checkpoints.filter(func(p: Vector2) -> bool: return p.distance_to(extract_at) >= 500.0)
	_shuffle(pool, rng)
	caches = PackedVector2Array()
	for p: Vector2 in pool:
		if caches.size() >= count:
			break
		# Not two caches on the same corner.
		var crowded := false
		for c in caches:
			crowded = crowded or c.distance_to(p) < 450.0
		if not crowded:
			caches.append(p)
	for p: Vector2 in pool:
		if caches.size() >= count:
			break
		if not caches.has(p):
			caches.append(p)
	cache_taken.clear()
	deep_cache = -1
	var far := -1.0
	for i in caches.size():
		cache_taken.append(false)
		var d := caches[i].distance_to(extract_at)
		if d > far:
			far = d
			deep_cache = i


static func _shuffle(list: Array, rng: RandomNumberGenerator) -> void:
	for i in range(list.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp: Variant = list[i]
		list[i] = list[j]
		list[j] = tmp


## The rigs a Retrieve calls in as danger climbs, in order.
static func _rig_call_kind(i: int) -> String:
	return ["scrapper", "outrider", "gunner"][i % 3]


func caches_grabbed() -> int:
	return cache_taken.count(true)


func _update_retrieve() -> void:
	var at := vehicle.global_position
	for i in caches.size():
		if not cache_taken[i] and at.distance_to(caches[i]) < T.CACHE_RADIUS:
			take_cache(i)
	var step := caches_grabbed() + int(elapsed / T.RETRIEVE_STEP_SECONDS)
	if step != danger:
		_set_danger(step)
	var d := at.distance_to(extract_at)
	if not extract_armed:
		extract_armed = d > T.EXTRACT_ARM_DISTANCE
	elif d < T.EXTRACT_RADIUS:
		if caches_grabbed() > 0:
			_succeed("EXTRACTED", "Caches %d / %d%s" % [caches_grabbed(), caches.size(), ", deep cache too" if cache_taken[deep_cache] else ""], retrieve_pay_mult())
		elif not _empty_warned:
			_empty_warned = true
			hud.banner("NOTHING TO EXTRACT YET  -  GRAB A CACHE", Color(0.95, 0.8, 0.3), 2.0)
	elif d > T.EXTRACT_RADIUS * 2.0:
		_empty_warned = false


## Grab cache `i` (driving over it does this). The deep cache carries a sure
## schematic, which rides with the rest of the salvage.
func take_cache(i: int) -> void:
	if i < 0 or i >= caches.size() or cache_taken[i]:
		return
	cache_taken[i] = true
	if i == deep_cache:
		var unknown := profile.unknown_schematics(Parts.DROP_POOLS.retrieve, _pending_ids())
		if unknown.is_empty():
			hud.banner("DEEP CACHE  -  DOUBLE PAY", T.COL_ELITE, 2.5)
		else:
			var part := Parts.get_part(unknown.pick_random())
			salvage.append(part)
			hud.banner("DEEP CACHE  -  SCHEMATIC: " + Parts.describe(part).to_upper(), T.COL_ELITE, 3.0)
	else:
		hud.banner("CACHE %d / %d" % [caches_grabbed(), caches.size()], Color(0.95, 0.8, 0.3), 1.6)


func _set_danger(step: int) -> void:
	var rose := step > danger
	danger = step
	zombies.cap = mini(_base_cap + step * T.RETRIEVE_CAP_STEP, T.ZOMBIE_CAP)
	zombies.speed_bonus = 1.0 + step * T.RETRIEVE_SPEED_STEP
	if rose and T.RETRIEVE_RIG_STEPS.has(step) and _rig_calls_made < _rig_calls:
		_events.append([elapsed, _rig_call_kind(_rig_calls_made), -1, false])
		_rig_calls_made += 1
		hud.banner("THE BLOCK IS STIRRING  -  DANGER %d" % step, Color(0.95, 0.8, 0.3), 2.0)


## Pay share for what you bring out: 30% for getting out, the rest by caches
## (the deep cache counts double).
func retrieve_pay_mult() -> float:
	var total := float(caches.size() - 1) + T.RETRIEVE_DEEP_MULT
	var got := 0.0
	for i in caches.size():
		if cache_taken[i]:
			got += T.RETRIEVE_DEEP_MULT if i == deep_cache else 1.0
	return T.RETRIEVE_BASE_SHARE + (1.0 - T.RETRIEVE_BASE_SHARE) * got / maxf(total, 1.0)


# --- Escort -------------------------------------------------------------------------

## The truck's salvage sites, chained across the block, plus the optional one
## the driver may offer (well away from the route).
func _plan_sites(count: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(spec.seed)
	var pool: Array = arena.checkpoints.duplicate()
	var at := arena.player_start
	for i in count:
		var options: Array = pool.filter(func(p: Vector2) -> bool:
			var d := at.distance_to(p)
			return d >= 450.0 and d <= 1300.0)
		if options.is_empty():
			options = pool
		var next: Vector2 = options[rng.randi_range(0, options.size() - 1)]
		pool.erase(next)
		truck.sites.append(next)
		truck.site_times.append(T.ESCORT_SALVAGE_TIME)
		at = next
	var risky: Array = pool.filter(func(p: Vector2) -> bool:
		for s in truck.sites:
			if s.distance_to(p) < 500.0:
				return false
		return true)
	if risky.is_empty():
		risky = pool
	if not risky.is_empty():
		optional_site = risky[rng.randi_range(0, risky.size() - 1)]
	var names := ["an overturned tanker", "a collapsed parts depot", "a burned-out wrecker yard", "a stalled freight train"]
	optional_name = str(names[rng.randi_range(0, names.size() - 1)])


func _on_site_reached(i: int) -> void:
	if optional_taken and i == optional_index:
		# They heard the crane: a big wave and a rig converge on the site.
		zombies.cap = mini(zombies.cap + T.ESCORT_OPTIONAL_WAVE, T.ZOMBIE_CAP)
		for k in T.ESCORT_OPTIONAL_WAVE:
			var p := zombies.pick_spawn_point()
			zombies.spawn_at(p + Vector2(randf_range(-20, 20), randf_range(-20, 20)), zombies.roll_kind())
		_events.append([elapsed, "outrider", -1, false])
		hud.banner("THEY HEARD THE CRANE  -  HOLD THEM OFF", T.COL_ENEMY, 2.5)
	else:
		hud.banner("TRUCK ON SITE  -  KEEP THEM OFF IT", T.COL_TRUCK, 1.8)


func _on_site_done(i: int) -> void:
	if state != State.RUNNING:
		return
	if optional_taken and i == optional_index:
		zombies.cap = maxi(zombies.cap - T.ESCORT_OPTIONAL_WAVE, int(Missions.stat(spec, "cap")))
	if truck.is_done():
		var detail := "All %d sites salvaged%s" % [truck.sites.size(), ", including the risky one" if optional_taken else ""]
		_succeed("SALVAGE RUN DONE", detail, T.ESCORT_OPTIONAL_PAY if optional_taken else 1.0)
		return
	hud.banner("SITE DONE  -  MOVING ON", T.COL_TRUCK, 1.6)
	if i == 0 and not optional_offered and optional_site != Vector2.INF:
		_offer_optional()


## The driver radios about the risky site; the game waits for your answer.
func _offer_optional() -> void:
	optional_offered = true
	get_tree().paused = true
	hud.show_choice("SALVAGE TRUCK DRIVER",
		"\"There's %s a few blocks over. Loaded with parts, but crawling with them, and it's slow work. Could be worth it. Your call.\"" % optional_name,
		"TAKE THE RISK  (+60% PAY, SCHEMATIC)",
		"STICK TO THE PLAN")


func _on_optional_choice(yes: bool) -> void:
	get_tree().paused = false
	if not yes or truck == null or truck.is_wrecked:
		hud.banner("STICKING TO THE PLAN", T.COL_TRUCK, 1.6)
		return
	optional_taken = true
	optional_index = truck.site_index
	truck.insert_site(optional_site, T.ESCORT_OPTIONAL_TIME)
	hud.banner("DETOUR  -  THE TRUCK'S HEADING FOR IT", T.COL_ORANGE, 2.0)


func _on_truck_lost() -> void:
	if state != State.RUNNING:
		return
	_fail("TRUCK LOST", "The salvage truck was wrecked. No job pay.")


## The job failed but your rig made it home: the day passes, you keep what
## you picked up, no job pay and no wreck penalty.
func _fail(title: String, detail: String) -> void:
	hud.close_crew_wheel(false)
	hud.close_choice()
	get_tree().paused = false
	Engine.time_scale = 1.0
	state = State.FAILED
	for p in pickups.get_children():
		_take_salvage(p as Pickup)
	bank_report = profile.bank_run(int(scrap), _pending_ids())
	profile.finish_day()
	profile.bank_crew(0, injured_crew_ids(), bool(vehicle.crew_mod("triage")))
	var lines := detail + "\nKill scrap +%d    Time %s" % [int(scrap), _clock(elapsed)]
	for id: String in bank_report.unlocked:
		lines += "\nNew schematic: " + Parts.describe(Parts.get_part(id))
	hud.show_result(title, lines, "RETURN TO GARAGE", T.COL_ORANGE)


# --- HUD -------------------------------------------------------------------------

func _refresh_hud() -> void:
	hud.set_armor(vehicle.armor / vehicle.armor_max)
	var plates := PackedFloat32Array([0.0, 0.0, 0.0, 0.0])
	for i in 4:
		plates[i] = vehicle.facing_armor[i] / vehicle.facing_max[i] if vehicle.facing_max[i] > 0.0 else -1.0
	hud.set_defense(vehicle.shield / vehicle.shield_max if vehicle.shield_max > 0.0 else -1.0, plates, vehicle.hp / maxf(vehicle.hp_max, 1.0))
	hud.set_statuses(vehicle.status.build, vehicle.status.left)
	hud.set_power(vehicle.power_load(), vehicle.power_capacity(), vehicle.weight_load, vehicle.weight_limit())
	for i in vehicle.crew.size():
		_crew_state(i)
	for i in vehicle.abilities.size():
		hud.set_ability_charge(i, vehicle.ability_charge(i))
	hud.set_status_text(_status_line())
	hud.set_lock_state(vehicle.lock_enabled, vehicle.lock_target != null)
	# Edge arrows: specials always, the Courier's next stop, salvage, and the
	# last few shamblers in a Clear.
	var points := PackedVector2Array()
	var colors := PackedColorArray()
	if state == State.RUNNING:
		var to_screen := get_viewport().get_canvas_transform()
		for h in hunters:
			if h.active and not h.is_latched():
				points.append(to_screen * h.global_position)
				colors.append(T.COL_HUNTER)
		for rig in rigs.get_children():
			if not rig.get("is_wrecked"):
				points.append(to_screen * (rig as Node2D).global_position)
				colors.append(T.COL_ELITE if rig == elite else T.COL_ENEMY)
		for p in pickups.get_children():
			points.append(to_screen * (p as Node2D).global_position)
			colors.append(T.COL_CYAN)
		if mission_type == "courier" and checkpoint_index < checkpoints.size():
			points.append(to_screen * checkpoints[checkpoint_index])
			colors.append(T.COL_CYAN)
		if mission_type == "retrieve":
			for i in caches.size():
				if not cache_taken[i]:
					points.append(to_screen * caches[i])
					colors.append(T.COL_ELITE if i == deep_cache else Color(0.95, 0.8, 0.3))
			if caches_grabbed() > 0:
				points.append(to_screen * extract_at)
				colors.append(T.COL_CYAN)
		if mission_type == "escort" and truck != null and not truck.is_wrecked:
			points.append(to_screen * truck.global_position)
			colors.append(T.COL_TRUCK)
		if mission_type == "clear" and zombies.remaining() <= T.STRAGGLER_ARROWS:
			for p in zombies.active_positions():
				points.append(to_screen * p)
				colors.append(T.COL_ORANGE)
	hud.set_threats(points, colors)


func _status_line() -> String:
	if tutorial:
		return "TRAINING RUN   %d / 5" % mini(tut_step + 1, 5)
	var tail := "      SCRAP  %d" % int(scrap)
	match mission_type:
		"survive":
			var left := maxf(float(Missions.stat(spec, "seconds")) - elapsed, 0.0)
			return "SURVIVE  %s" % _clock(left) + tail
		"hunt":
			if elite != null and elite.is_wrecked:
				return "HUNT  %s DOWN  -  GRAB THE SCHEMATIC" % elite.elite_name + tail
			var hp := elite.armor / elite.armor_max if elite != null else 1.0
			return "HUNT  %s  %d%%" % [elite.elite_name if elite != null else "", roundi(hp * 100.0)] + tail
		"courier":
			var tier := courier_tier()
			var goal := ("%s %s" % [tier.to_upper(), _clock(float(par[tier]))]) if tier != "late" else "LATE"
			return "COURIER  %d / %d   %s   %s" % [checkpoint_index, checkpoints.size(), _clock(elapsed), goal] + tail
		"retrieve":
			var out := "EXTRACT OPEN" if caches_grabbed() > 0 else "GRAB A CACHE"
			return "RETRIEVE  %d / %d   DANGER %d   %s" % [caches_grabbed(), caches.size(), danger, out] + tail
		"escort":
			if truck == null:
				return "ESCORT" + tail
			var hp := roundi(truck.armor / truck.armor_max * 100.0)
			var site := "SALVAGING %ds" % ceili(truck.work_left) if truck.working else "DRIVING"
			return "ESCORT  SITE %d / %d   %s   TRUCK %d%%" % [mini(truck.site_index + 1, truck.sites.size()), truck.sites.size(), site, hp] + tail
	return "CLEAR  %d / %d" % [kills, target_kills] + tail


static func _clock(seconds: float) -> String:
	return "%d:%02d" % [int(seconds / 60.0), int(seconds) % 60]


func _type_color() -> Color:
	match mission_type:
		"survive":
			return T.COL_ORANGE
		"hunt":
			return T.COL_ELITE
		"courier":
			return Color(0.45, 0.85, 0.5)
		"retrieve":
			return Color(0.95, 0.8, 0.3)
		"escort":
			return Color(0.4, 0.8, 0.75)
	return T.COL_CYAN


# --- Kills and drops -----------------------------------------------------------

func _add_kill(points: int, rig := false) -> void:
	kills += 1
	var mult := profile.salvage_mult() * float(vehicle.crew_mod("scrap"))
	if rig:
		mult *= float(vehicle.crew_mod("rig_scrap"))
	scrap += points * mult
	if state == State.RUNNING and mission_type == "clear" and kills >= target_kills:
		_succeed("BLOCK CLEARED", "", 1.0)


func _on_zombie_killed(at: Vector2, kind: String) -> void:
	splats.add(at)
	fx.gore(at, (at - vehicle.global_position).normalized())
	_add_kill(int(T.ZOMBIE_KINDS[kind].scrap))
	match kind:
		"tank":
			hud.banner("TANK DOWN", T.COL_ORANGE, 1.8)
			drop_cache(at, T.TANK_CACHE)
		"boomer":
			fx.call("blast", at, T.BOOMER_POOL_RADIUS)
			if hazards.is_marked(vehicle) and hazards.marked_left > T.BILE_MARK_TIME - 0.05:
				hud.banner("BILE!  THE HORDE IS COMING", T.COL_BOOMER, 2.0)


## Barrels at fixed spots, their types rolled from the job's seed (§14).
func _place_barrels() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("helriders-barrels-%d" % int(spec.seed))
	var spots: Array = arena.barrel_spots.duplicate()
	_shuffle(spots, rng)
	for i in barrels.size():
		var kind: String = T.BARREL_TYPES[rng.randi_range(0, T.BARREL_TYPES.size() - 1)]
		barrels[i].place(spots[i], kind)


## Ground hazards on every rig (yours, the enemies', an Escort's truck):
## slime and oil build SLICK, burning ground builds BURNING (§14).
func _apply_slime(delta: float) -> void:
	_ground_on(vehicle, delta)
	for rig in rigs.get_children():
		_ground_on(rig as Vehicle, delta)
	if truck != null:
		_ground_on(truck, delta)


func _ground_on(rig: Vehicle, delta: float) -> void:
	if rig == null or rig.is_wrecked:
		return
	if rig == vehicle and _seen_timer >= 0.99:   # once a second, the tick the timer resets
		var at := rig.global_position
		for pair: Array in [["oil", hazards.oil_at(at, rig.team)], ["spikes", hazards.spike_at(at, rig.team)],
				["fire", hazards.fire_at(at, rig.team)], ["slime", hazards.slime_at(at)], ["bile", hazards.is_marked(rig)]]:
			if bool(pair[1]):
				profile.discover("hazards", str(pair[0]))
	rig.set_on_slime(hazards.slick_at(rig.global_position, rig.team), delta)
	rig.set_on_spikes(hazards.spike_at(rig.global_position, rig.team), delta)
	if hazards.fire_at(rig.global_position, rig.team):
		rig.add_buildup(StatusBars.FIRE, T.STATUS_POOL_BUILDUP * delta)


## A status started on your rig. GOOPED marks it for the horde.
func _on_status_started(k: int) -> void:
	profile.discover("hazards", "status_" + str(STATUS_IDS[k]))
	if k == StatusBars.GOOP:
		hazards.mark(vehicle)


## A scrap crate at `at` (a Tank's), scaled like other caches.
func drop_cache(at: Vector2, value: int) -> void:
	var pickup := Pickup.new()
	pickup.scrap_value = roundi(value * float(vehicle.crew_mod("cache")))
	pickup.position = at
	pickups.add_child(pickup)


func _on_hunter_died(at: Vector2, h: Hunter) -> void:
	splats.add(at)
	fx.gore(at, Vector2.ZERO)
	_on_hunter_let_go()
	var how := {"crushed": "HUNTER CRUSHED", "scraped": "HUNTER SCRAPED OFF", "rammed": "HUNTER RUN DOWN", "mine": "HUNTER BLOWN UP"}
	hud.banner(how.get(h.last_hit_cause, "HUNTER DOWN"), T.COL_HUNTER, 1.8)
	_add_kill(T.HUNTER_SCRAP)


func _on_hunter_let_go() -> void:
	for h in hunters:
		if h.is_latched():
			return
	hud.set_alert("")


func _pending_ids() -> Array[String]:
	var ids: Array[String] = []
	for part in salvage:
		ids.append(str(part.id))
	return ids


func _drop(at: Vector2, pool: String, guaranteed: bool, cache: int, rig: Node = null) -> void:
	var pickup := Pickup.new()
	if rig != null:
		_rig_crate[rig] = pickup
	var unknown := profile.unknown_schematics(Parts.DROP_POOLS[pool], _pending_ids())
	var chance := minf(profile.schematic_chance() + float(vehicle.crew_mod("schematic")), 0.95)
	if not unknown.is_empty() and (guaranteed or always_drop_schematic or randf() < chance):
		pickup.part = Parts.get_part(unknown.pick_random())
	else:
		pickup.scrap_value = roundi(cache * float(vehicle.crew_mod("cache")))
	# Beside the burning wreck, toward the player.
	pickup.position = at + (vehicle.global_position - at).normalized() * 70.0
	pickups.add_child(pickup)


func _on_outrider_wrecked(rig: EnemyRig) -> void:
	camera.shake(0.6)
	if _wrecked_again(rig):
		return
	if tutorial:
		var crate := Pickup.new()
		crate.part = Parts.get_part(T.TUTORIAL_PART)
		crate.position = rig.global_position + (vehicle.global_position - rig.global_position).normalized() * 70.0
		pickups.add_child(crate)
		hud.banner("RIG DOWN", T.COL_CYAN)
		return
	_drop(rig.global_position, "outrider", false, T.SCRAP_CACHE, rig)
	hud.banner("RIG DOWN  -  GRAB THE SALVAGE", T.COL_CYAN)
	_add_kill(T.OUTRIDER_SCRAP, true)
	_salvage_plating()


func _on_bulwark_wrecked(rig: EnemyRig) -> void:
	camera.shake(0.8)
	if _wrecked_again(rig):
		return
	_drop(rig.global_position, "bulwark", false, T.BULWARK_SCRAP_CACHE, rig)
	hud.banner("BULWARK DOWN  -  GRAB THE SALVAGE", T.COL_CYAN)
	_add_kill(T.BULWARK_SCRAP, true)
	_salvage_plating()


func _on_gunner_wrecked(rig: EnemyRig) -> void:
	camera.shake(0.7)
	if _wrecked_again(rig):
		return
	_drop(rig.global_position, "gunner", false, T.GUNNER_SCRAP_CACHE, rig)
	hud.banner("GUNNER RIG DOWN  -  GRAB THE SALVAGE", T.COL_CYAN)
	_add_kill(T.GUNNER_SCRAP, true)
	_salvage_plating()


func _on_scrapper_wrecked(rig: EnemyRig) -> void:
	camera.shake(0.5)
	if _wrecked_again(rig):
		return
	_drop(rig.global_position, "scrapper", false, T.SCRAPPER_SCRAP_CACHE, rig)
	hud.banner("SCRAPPER DOWN  -  GRAB THE SALVAGE", T.COL_CYAN)
	_add_kill(T.SCRAPPER_SCRAP, true)
	_salvage_plating()


func _on_scrapper_gunner_wrecked(rig: EnemyRig) -> void:
	camera.shake(0.55)
	if _wrecked_again(rig):
		return
	_drop(rig.global_position, "scrapper", false, T.SCRAPPER_GUNNER_SCRAP_CACHE, rig)
	hud.banner("SCRAPPER GUNNER DOWN  -  GRAB THE SALVAGE", T.COL_CYAN)
	_add_kill(T.SCRAPPER_GUNNER_SCRAP, true)
	_salvage_plating()


func _on_convoy_wrecked(rig: EnemyRig) -> void:
	camera.shake(1.0)
	if _wrecked_again(rig):
		return
	_drop(rig.global_position, "convoy", false, T.CONVOY_SCRAP_CACHE, rig)
	hud.banner("CONVOY LEAD DOWN  -  GRAB THE SALVAGE", T.COL_CYAN)
	_add_kill(T.CONVOY_SCRAP, true)
	_salvage_plating()


func _on_patcher_wrecked(rig: EnemyRig) -> void:
	camera.shake(0.5)
	_drop(rig.global_position, "patcher", false, T.PATCHER_SCRAP_CACHE, rig)
	hud.banner("PATCHER DOWN  -  GRAB THE SALVAGE", T.COL_CYAN)
	_add_kill(T.PATCHER_SCRAP, true)
	_salvage_plating()


## A Patcher brought a wreck back: it's a live rig again (its kill no longer
## counts) and its crate, if still on the ground, goes back into it.
func _on_rig_revived(rig: EnemyRig) -> void:
	_revived[rig] = true
	kills -= 1
	var crate: Variant = _rig_crate.get(rig)
	if crate != null and is_instance_valid(crate) and (crate as Node).get_parent() == pickups:
		pickups.remove_child(crate)
		_held_crate[rig] = crate
	_rig_crate.erase(rig)
	hud.banner("A PATCHER BROUGHT A RIG BACK", T.COL_ENEMY)


## A revived rig wrecked again: it counts as a kill, but its loot is paid
## once per job. Its crate drops again if it took one back.
func _wrecked_again(rig: EnemyRig) -> bool:
	if not _revived.has(rig):
		return false
	var crate: Variant = _held_crate.get(rig)
	if crate != null:
		_held_crate.erase(rig)
		var pickup := crate as Pickup
		pickup.position = rig.global_position + (vehicle.global_position - rig.global_position).normalized() * 70.0
		pickups.add_child(pickup)
		_rig_crate[rig] = pickup
	hud.banner("RIG DOWN AGAIN", T.COL_CYAN)
	_add_kill(0, true)
	return true


## The trailer shot off a running Convoy Lead: a scrap crate where it fell.
func _on_trailer_lost(rig: EnemyRig) -> void:
	if rig.is_wrecked:
		return   # wrecking the cab took it; that payout covers both
	var trailer := (rig as ConvoyRig).trailer
	camera.shake(0.5)
	drop_cache(trailer.global_position, T.CONVOY_TRAILER_CRATE)
	hud.banner("TRAILER DOWN  -  THE CAB'S STILL COMING", T.COL_CYAN)


func _on_elite_wrecked() -> void:
	camera.shake(0.9)
	if _wrecked_again(elite):
		return
	_drop(elite.global_position, "elite", true, T.ELITE_SCRAP_CACHE, elite)
	hud.banner("%s DOWN  -  GRAB THE SCHEMATIC" % elite.elite_name, T.COL_ELITE, 3.0)
	_add_kill(T.ELITE_SCRAP, true)
	_salvage_plating()


## Mechanic perk: each enemy rig wreck restores some armor.
func _salvage_plating() -> void:
	if bool(vehicle.crew_mod("salvage_plating")) and not vehicle.is_wrecked:
		vehicle.repair_armor(15.0 * float(vehicle.crew_mod("repair")))


func _collect_pickups() -> void:
	for p in pickups.get_children():
		var pickup := p as Pickup
		if vehicle.global_position.distance_to(pickup.global_position) < Pickup.COLLECT_RADIUS:
			_take_salvage(pickup)


func _take_salvage(pickup: Pickup) -> void:
	if not pickup.part.is_empty():
		profile.discover("parts", str(pickup.part.id))
	if pickup.part.is_empty():
		scrap += pickup.scrap_value
		hud.banner("SCRAP CACHE  +%d" % pickup.scrap_value, T.COL_ORANGE, 2.0)
	else:
		salvage.append(pickup.part)
		hud.banner("SCHEMATIC: " + Parts.describe(pickup.part).to_upper(), Parts.color_of(pickup.part), 3.0)
	# Out of the tree now, so a second physics tick this frame can't collect it twice.
	pickups.remove_child(pickup)
	pickup.queue_free()
	# A Hunt ends when the Elite's drop is in the rig.
	if state == State.RUNNING and mission_type == "hunt" and elite != null and elite.is_wrecked and pickups.get_child_count() == 0:
		_succeed("TARGET DOWN", "", 1.0)


func _on_damaged(amount: float) -> void:
	if amount >= 2.0:
		camera.shake(amount / 30.0)


# --- Endings ---------------------------------------------------------------------

## Success: bank the run's scrap plus the job's pay (x `pay_mult`) and any
## schematics, end the day, show the results card.
func _succeed(title: String, detail: String, pay_mult: float) -> void:
	hud.close_crew_wheel(false)
	Engine.time_scale = 1.0
	state = State.CLEARED
	# The job's done: anything still on the ground gets hauled home.
	for p in pickups.get_children():
		_take_salvage(p as Pickup)
	var pay := roundi(int(spec.reward) * pay_mult)
	var reward_part := _mission_reward_schematic(pay_mult)
	var ids := _pending_ids()
	if reward_part != "":
		ids.append(reward_part)
	bank_report = profile.bank_run(int(scrap) + pay, ids)
	profile.finish_day()
	# After the day ends, so tonight doesn't count toward anyone's rest.
	var crew_lines := profile.bank_crew(skulls, injured_crew_ids(), bool(vehicle.crew_mod("triage")))
	var lines := "Job pay +%d    Kill scrap +%d    Time %s" % [pay, int(scrap), _clock(elapsed)]
	if detail != "":
		lines = detail + "\n" + lines
	for id: String in bank_report.unlocked:
		lines += "\nNew schematic: " + Parts.describe(Parts.get_part(id))
	if not crew_lines.is_empty():
		lines += "\nCrew: " + ";  ".join(crew_lines)
	Engine.time_scale = 1.0
	hud.show_result(title, lines, "RETURN TO GARAGE", _type_color())


## Ids of crew hurt during this run.
func injured_crew_ids() -> Array[int]:
	var out: Array[int] = []
	for c in vehicle.crew:
		if bool(c.injured):
			out.append(int(c.id))
	return out


## A job may pay a schematic from its type's pool: odds by skulls, and a
## Courier only pays one for a gold time.
func _mission_reward_schematic(pay_mult: float) -> String:
	if mission_type == "courier" and pay_mult < 1.0:
		return ""
	var pool: Array = Parts.DROP_POOLS.get(mission_type, [])
	var unknown := profile.unknown_schematics(pool, _pending_ids())
	var sure := mission_type == "escort" and optional_taken   # the risky site pays a schematic
	if unknown.is_empty() or (not sure and randf() >= Missions.schematic_chance(spec)):
		return ""
	return unknown.pick_random()


func _on_wrecked() -> void:
	if state != State.RUNNING:
		return
	hud.close_crew_wheel(false)
	Engine.time_scale = 1.0
	state = State.WRECKED
	camera.shake(1.0)
	var aboard: Array[String] = []
	for m in profile.seated_crew():
		aboard.append(str(m.name))
	var penalty := profile.record_wreck()
	var saved := profile.last_wreck_survivors.duplicate()
	var lost := aboard.filter(func(n: String) -> bool: return not saved.has(n))
	profile.finish_day()
	var lines := "Rig destroyed with every part on it."
	if aboard.is_empty():
		lines += " No crew aboard."
	elif not lost.is_empty():
		lines += " Crew lost: %s." % ", ".join(lost)
		var back: Array[String] = []
		for m: Dictionary in profile.lost:
			if lost.has(str(m.name)):
				back.append("%s in %d day%s" % [str(m.name), int(m.back_in), "" if int(m.back_in) == 1 else "s"])
		if not back.is_empty():
			lines += "\nThey may turn up at the Saloon again: %s." % ", ".join(back)
	if not saved.is_empty():
		lines += "\nLast Rites: %s pulled through, resting %d days." % [", ".join(saved), T.LAST_RITES_REST]
	if penalty > 0:
		lines += "\nWreck penalty: -%d scrap." % penalty
	if scrap >= 1.0 or not salvage.is_empty():
		lines += "\nSalvage lost with the rig: %d scrap" % int(scrap)
		if not salvage.is_empty():
			lines += ", %d schematic%s" % [salvage.size(), "" if salvage.size() == 1 else "s"]
		lines += "."
	# Let the wreck burn for a beat before the results card.
	await get_tree().create_timer(1.6).timeout
	Engine.time_scale = 1.0
	hud.show_result("WRECKED", lines, "BACK TO THE YARD", T.COL_ORANGE)


class CourierMarkers extends Node2D:
	## Objectives on the ground. Courier: the next checkpoint pulses, the one
	## after it is a faint ring, so you can line up the turn. Retrieve: crates
	## for the caches (gold for the deep one) and the extraction zone. Escort:
	## the truck's next site with its work ring, and the risky site once taken.
	const T := preload("res://scripts/tuning.gd")
	var mission: Node2D
	var _t := 0.0

	func _process(delta: float) -> void:
		_t += delta
		if mission != null and str(mission.get("mission_type")) in ["courier", "retrieve", "escort"]:
			queue_redraw()

	func _draw() -> void:
		if mission == null:
			return
		match str(mission.get("mission_type")):
			"retrieve":
				_draw_retrieve()
				return
			"escort":
				_draw_escort()
				return
			"courier":
				pass
			_:
				return
		var points: PackedVector2Array = mission.get("checkpoints")
		var index: int = mission.get("checkpoint_index")
		var font := ThemeDB.fallback_font
		var green := Color(0.45, 0.85, 0.5)
		for i in range(index, mini(index + 2, points.size())):
			var p := points[i]
			var r := T.COURIER_RADIUS
			if i == index:
				var pulse := 0.5 + 0.5 * sin(_t * 5.0)
				draw_circle(p, r, Color(green, 0.10 + 0.08 * pulse))
				draw_arc(p, r, 0.0, TAU, 48, Color(green, 0.9), 4.0)
				draw_arc(p, r + 8.0 + 6.0 * pulse, 0.0, TAU, 48, Color(green, 0.35), 2.0)
			else:
				draw_arc(p, r * 0.7, 0.0, TAU, 40, Color(green, 0.35), 2.0)
			draw_string(font, p + Vector2(-30, 10), str(i + 1), HORIZONTAL_ALIGNMENT_CENTER, 60, 30, Color(green, 0.95 if i == index else 0.4))

	func _draw_retrieve() -> void:
		var pulse := 0.5 + 0.5 * sin(_t * 4.0)
		var font := ThemeDB.fallback_font
		var caches: PackedVector2Array = mission.get("caches")
		var taken: Array = mission.get("cache_taken")
		var deep: int = mission.get("deep_cache")
		var gold := Color(0.95, 0.8, 0.3)
		for i in caches.size():
			if bool(taken[i]):
				continue
			var p := caches[i]
			var c := T.COL_ELITE if i == deep else gold
			draw_arc(p, T.CACHE_RADIUS + 4.0 * pulse, 0.0, TAU, 32, Color(c, 0.5), 2.0)
			draw_rect(Rect2(p - Vector2(14, 11), Vector2(28, 22)), c.darkened(0.45))
			draw_rect(Rect2(p - Vector2(14, 11), Vector2(28, 22)), c, false, 3.0)
			draw_line(p - Vector2(14, 0), p + Vector2(14, 0), c, 2.0)
			if i == deep:
				draw_string(font, p + Vector2(-40, -24), "DEEP", HORIZONTAL_ALIGNMENT_CENTER, 80, 18, c)
		var out: Vector2 = mission.get("extract_at")
		var open := int(mission.call("caches_grabbed")) > 0
		var cyan := Color(T.COL_CYAN, 0.9 if open else 0.35)
		draw_circle(out, T.EXTRACT_RADIUS, Color(T.COL_CYAN, (0.08 + 0.06 * pulse) if open else 0.04))
		draw_arc(out, T.EXTRACT_RADIUS, 0.0, TAU, 48, cyan, 4.0 if open else 2.0)
		draw_string(font, out + Vector2(-60, 8), "EXTRACT", HORIZONTAL_ALIGNMENT_CENTER, 120, 22, cyan)

	func _draw_escort() -> void:
		var truck: Node2D = mission.get("truck")
		if truck == null:
			return
		var sites: PackedVector2Array = truck.get("sites")
		var index: int = truck.get("site_index")
		var teal := Color(0.4, 0.8, 0.75)
		var font := ThemeDB.fallback_font
		var risky_at: int = mission.get("optional_index") if bool(mission.get("optional_taken")) else -1
		for i in range(index, sites.size()):
			var p := sites[i]
			var c := T.COL_ORANGE if i == risky_at else teal
			var r := T.ESCORT_SITE_RADIUS
			if i == index:
				draw_circle(p, r, Color(c, 0.08))
				draw_arc(p, r, 0.0, TAU, 48, Color(c, 0.85), 3.0)
				var done := float(truck.call("work_progress"))
				if done > 0.0:
					draw_arc(p, r + 10.0, -PI / 2.0, -PI / 2.0 + TAU * done, 48, c, 8.0)
			else:
				draw_arc(p, r * 0.7, 0.0, TAU, 40, Color(c, 0.35), 2.0)
			draw_string(font, p + Vector2(-30, 10), str(i + 1), HORIZONTAL_ALIGNMENT_CENTER, 60, 30, Color(c, 0.95 if i == index else 0.4))
