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
const UI := preload("res://scripts/ui_theme.gd")
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
const Mods := preload("res://scripts/mods.gd")
const TorcherRig := preload("res://scripts/torcher_rig.gd")
const SludgerRig := preload("res://scripts/sludger_rig.gd")
const FriendlyTruck := preload("res://scripts/friendly_truck.gd")
const StatusBars := preload("res://scripts/status_bars.gd")
const Barrel := preload("res://scripts/barrel.gd")
const Crew := preload("res://scripts/crew.gd")
const Hunter := preload("res://scripts/hunter.gd")
const BulletPool := preload("res://scripts/bullet_pool.gd")
const MinePool := preload("res://scripts/mine_pool.gd")
const ShellPool := preload("res://scripts/shell_pool.gd")
const KeywordFx := preload("res://scripts/keyword_fx.gd")
const Fx := preload("res://scripts/fx.gd")
const Pickup := preload("res://scripts/pickup.gd")
const LockReticle := preload("res://scripts/lock_reticle.gd")
const ChaseCamera := preload("res://scripts/chase_camera.gd")
const Hud := preload("res://scripts/hud.gd")
const GameMenu := preload("res://scripts/game_menu.gd")
const NavGrid := preload("res://scripts/nav_grid.gd")
const ProfileScript := preload("res://scripts/profile.gd")
const PadScript := preload("res://scripts/pad.gd")
const GARAGE_SCENE := "res://scenes/garage.tscn"
const MISSION_SCENE := "res://scenes/mission.tscn"
const STATUS_IDS := ["shock", "fire", "acid", "toxic", "slime", "goop"]
const HUNTER_POOL := 2

enum State { RUNNING, WRECKED, CLEARED, FAILED }

## Off for tests that want to place the Hunter and Outriders themselves.
var auto_spawn_specials := true
## Tests: make every Outrider drop a schematic instead of rolling for it.
var always_drop_schematic := false
## Tests: Extract or Push. -1 = seeded as on the board, 0 = never, 1 = always.
var push_override := -1
## Tests: run this mission instead of the profile's.
var mission_override := {}
## Tests: ride with these crew (crew.gd dictionaries) instead of the seated ones.
var crew_override: Array = []

const HUD_REFRESH := 1.0 / 15.0   # seconds between HUD bar/number refreshes
var _hud_timer := 0.0
var _threat_points := PackedVector2Array()   # reused each frame (edge arrows)
var _threat_colors := PackedColorArray()
var loading_map := false        # start held (tree paused) while the styled map bakes
var _load_layer: CanvasLayer
var abandoned := false          # ABANDON JOB was used (tests)
var _restarting := false         # RESTART keeps the baked map cached; leaving drops it
var spec := {}                   # the mission being run
var night := false               # a night job (Missions.is_night): zombie rules and the world grade
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
var torchers: Array[EnemyRig] = []    # proposal 01: fire skirmishers, built up front
var torcher: TorcherRig
var sludgers: Array[EnemyRig] = []    # proposal 01: acid / goop artillery, built up front
var sludger: SludgerRig
# Extract or Push (§14, proposal 01). The push beacon and its own extraction
# marker appear when the objective is done (Retrieve: once every non-deep
# cache is taken; pending the owner's confirmation).
enum Push { NONE, CHOOSING, ACTIVE, EXTRACT, DONE }
var push_allowed := false        # this job may offer a push (seeded, hidden until the objective)
var push_state := Push.NONE
var push_at := Vector2.INF       # the orange push beacon
var push_extract := Vector2.INF  # the cyan extraction marker
var push_left := 0.0             # push timer, then the extraction window
var pushed := false              # the player pushed and made it out (pays x1.5)
var _push_rigs_due := 0
var _push_pending := {}          # the objective's result, held while you choose
var _push_finishing := false
var _push_blocked_warned := false
var _rig_crate := {}             # rig -> the crate its wreck dropped
var _held_crate := {}            # rig -> its uncollected crate, taken back when revived
var _revived := {}               # rigs a Patcher has brought back (they pay once)
var enemy_mines: MinePool        # the Scrappers' mines (hurt you and zombies)
var marked: Node2D               # the last target a Spotter marked (tests)
var bullets: BulletPool
var mines: MinePool
var shells: ShellPool             # Mortar shells in flight
var keywords: KeywordFx           # keyword popups (§14 feedback)
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
var truck_alert := false   # the low-HP warning is up
var truck_hit_at := -100.0  # elapsed when the truck last took damage
var _truck_banner_at := -100.0
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
var _sludger_call := false      # Retrieve: the Sludger comes with the next danger rig call
var _events: Array = []          # [seconds, kind, kills that also trigger it (-1 = none), fired]


func _ready() -> void:
	preload("res://scripts/ui_transitions.gd").fade_in(self)   # V6.5
	profile = get_node("/root/Profile")
	var pad := get_node_or_null("/root/Pad")
	if pad != null:
		pad.connect("mode_changed", _on_pad_mode)
	_music_start.call_deferred()
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
	night = Missions.is_night(spec)

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
	keywords = KeywordFx.new()
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
		# Readability for first-timers (playtest 06/07): a brighter street and
		# ringed zombies, so the "point at a zombie" step is obvious.
		arena.modulate = T.COL_TUTORIAL_GRADE
		zombies.highlight = true
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
	bullets.player_rig = vehicle      # perk hooks on player hits (implement-03)
	vehicle.zombies_ref = zombies
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
		_skull_damage(rig)
	if truck != null:
		# Escort: the truck rolls out behind you, and the zombies and enemy
		# rigs go for it.
		truck.position = arena.player_start + Vector2(0, 110)
		truck.rotation = -PI / 2.0
		# Agreed with the owner (audit): the truck's armor and HP scale with
		# the same multiplier as enemy damage, so it holds up alike at every skull.
		truck.apply_stats(truck_sheet(skulls))
		truck.bullets = bullets
		truck.fx = fx
		zombies.alt_target = truck
		for rig: EnemyRig in _all_enemy_rigs():
			rig.player = truck
	for h in hunters:
		h.damage_mult = float(T.ENEMY_DAMAGE_BY_SKULL[skulls - 1]) * (T.NIGHT_ZOMBIE_DPS_MULT if night else 1.0)
		h.night_speed = T.NIGHT_HUNTER_SPEED_MULT if night else 1.0
		h.target = vehicle
		h.nav = nav
	zombies.nav = nav
	zombies.hazards = hazards
	bullets.fx = fx
	mines.fx = fx
	shells.fx = fx
	shells.hazards = hazards
	for b in barrels:
		b.fx = fx
	enemy_mines.fx = fx
	zombies.target = vehicle
	zombies.spawn_points = arena.spawn_points
	camera.target = vehicle
	reticle.rig = vehicle
	markers.mission = self
	_apply_night_tint()

	# Tree order is also physics order:
	# inputs (here) -> zombies -> player rig -> enemy rigs -> hunters -> bullets.
	# Hunters run after the rig so they see this tick's wall contact.
	for node: Node in [arena, splats, hazards, markers, mines, enemy_mines, barrel_layer, pickups, zombies, vehicle, rigs]:
		add_child(node)
	if truck != null:
		add_child(truck)
	for h in hunters:
		add_child(h)
	for node: Node in [bullets, shells, keywords, fx, reticle, camera, hud]:
		add_child(node)

	camera.set_bounds(Rect2(Vector2.ZERO, T.WORLD_SIZE))
	camera.global_position = vehicle.global_position
	camera.make_current()

	zombies.zombie_killed.connect(_on_zombie_killed)
	zombies.surge_warned.connect(_on_surge_warned)
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
	for rig in torchers:
		rig.wrecked.connect(_on_torcher_wrecked.bind(rig))
	for rig in sludgers:
		rig.wrecked.connect(_on_sludger_wrecked.bind(rig))
	for rig in _all_enemy_rigs():
		rig.status_started.connect(_on_enemy_status.bind(rig))
	for rig in convoys:
		rig.wrecked.connect(_on_convoy_wrecked.bind(rig))
		(rig as ConvoyRig).trailer.wrecked.connect(_on_trailer_lost.bind(rig))
	if elite != null:
		elite.wrecked.connect(_on_elite_wrecked)
	if truck != null:
		truck.wrecked.connect(_on_truck_lost)
		truck.damaged.connect(func(_a: float) -> void: truck_hit_at = elapsed)
		truck.site_reached.connect(_on_site_reached)
		truck.site_done.connect(_on_site_done)
		hud.choice_made.connect(_on_optional_choice)
	hud.restart_requested.connect(return_to_garage)
	hud.pause_pressed.connect(open_menu)
	vehicle.keyword.connect(keywords.pop)
	for rig in _all_enemy_rigs():
		rig.keyword.connect(keywords.pop)
	for b in barrels:
		b.died.connect(func(_at: Vector2) -> void: profile.discover("hazards", "barrel_" + b.kind))
		b.died.connect(_chain_reaction)
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
	if arena.is_baking():
		_hold_for_bake()
	else:
		_start_banner()
	_refresh_hud()


## World grade only. Whether the job is night is Content's (Missions.is_night,
## already stored on `night`). A day job is left alone, so the tutorial's
## brighter street stays. Rigs, hazards, tracers and FX are not in this list.
func _apply_night_tint() -> void:
	if not night:
		return
	var tint := T.COL_NIGHT_WORLD
	arena.modulate = tint
	splats.modulate = tint
	zombies.modulate = tint
	for h: Hunter in hunters:
		h.modulate = tint


func _start_banner() -> void:
	var title := "%s  -  %s" % [Missions.label(spec), str(spec.name).to_upper()]
	hud.banner(("NIGHT  -  " + title) if night else title, _type_color(), 3.0)


## Outer Blocks style only: the map bakes on a worker; the job waits behind a
## loading screen (tree paused, input ignored) so the code-drawn map never
## shows and swaps. The flag-off path never gets here.
func _hold_for_bake() -> void:
	loading_map = true
	get_tree().paused = true
	_load_layer = CanvasLayer.new()
	_load_layer.layer = 120
	_load_layer.process_mode = Node.PROCESS_MODE_ALWAYS
	var bg := ColorRect.new()
	bg.color = Color(0.05, 0.05, 0.06)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_STOP   # swallows taps while loading
	_load_layer.add_child(bg)
	var label := Label.new()
	label.text = "LOADING MAP"
	label.add_theme_color_override("font_color", T.COL_CYAN)
	label.add_theme_font_size_override("font_size", 40)
	label.set_anchors_preset(Control.PRESET_FULL_RECT)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	bg.add_child(label)
	add_child(_load_layer)
	arena.bake_finished.connect(_on_map_ready, CONNECT_ONE_SHOT)


func _on_map_ready() -> void:
	loading_map = false
	if _load_layer != null:
		_load_layer.queue_free()
		_load_layer = null
	get_tree().paused = false
	_start_banner()


## Crowd size, specials and objective for this mission's type and skulls.
func _configure_mission() -> void:
	var cap: int = maxi(roundi(float(Missions.stat(spec, "cap")) * float(T.HORDE_SCALE_BY_SKULL[skulls - 1])), 1)   # smaller hordes at 1-2 skulls
	zombies.cap = cap
	zombies.damage_mult = float(T.ENEMY_DAMAGE_BY_SKULL[skulls - 1])
	zombies.set_mix(skulls, mission_type == "courier")
	var hunter_time := T.NIGHT_HUNTER_SPAWN_TIME if night else T.HUNTER_SPAWN_TIME
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
				_events.append([hunter_time + 35.0 * i, "hunter", T.HUNTER_SPAWN_KILLS if i == 0 else -1, false])
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
	# Torcher and Sludger (proposal 01): seeded per job, shown on Comms.
	# The Torcher takes the Scrapper's slot at 3 skulls and an Outrider's from 4.
	var torcher_count := 0
	if not tutorial and Missions.has_torcher(spec):
		torcher_count = 1
		if mission_type == "clear":
			var swap_scrapper := skulls <= 3 and scrapper_count > 0
			if swap_scrapper:
				scrapper_count -= 1
				_drop_event("scrapper")
			elif outrider_count > 0:
				outrider_count -= 1
				_drop_event("outrider")
			else:
				target_kills += 1
			_events.append([T.SCRAPPER_SPAWN_TIME + 10.0, "torcher", T.SCRAPPER_SPAWN_KILLS, false])
		else:
			if not _swap_event("scrapper" if skulls <= 3 else "outrider", "torcher"):
				_events.append([75.0, "torcher", -1, false])
	if not tutorial and Missions.has_sludger(spec):
		if mission_type == "retrieve":
			_sludger_call = true   # it answers the first rig call as the danger rises
		else:
			_events.append([90.0, "sludger", -1, false])
	for i in 1:
		torchers.append(TorcherRig.new())
		sludgers.append(SludgerRig.new())
	torcher = torchers[0] as TorcherRig
	sludger = sludgers[0] as SludgerRig
	# Extract or Push: hidden until the objective's done.
	push_allowed = not tutorial and Missions.has_push(spec) and not profile.push_blocked_today()
	if push_override >= 0:
		push_allowed = push_override == 1 and not tutorial and not T.PUSH_NO_TYPES.has(mission_type)
	if push_allowed:
		_push_rigs_due = 0
		outrider_count += 1   # one spare of each for the push's extra rigs
		gunner_count += 1
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
	if night:
		zombies.apply_night()   # speed, damage, start, ramp, packs, Tanks, bile, surge
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
	_tick_flare(delta)
	_seen_timer -= delta
	if _seen_timer <= 0.0:
		_seen_timer = 1.0
		for z in zombies.active_zombies():
			profile.discover("enemies", str(z.kind))
	vehicle.drive_input = hud.left_stick.output
	vehicle.aim_input = hud.right_stick.output
	_pad_input()
	_kbm_input()
	if tutorial:
		_tutorial_tick()
	if auto_spawn_specials:
		_run_events()
	_collect_pickups()
	_apply_slime(delta)
	match mission_type:
		"survive":
			if elapsed >= float(Missions.stat(spec, "seconds")) and push_state == Push.NONE:
				_succeed("HELD THE BLOCK", "", 1.0)
		"courier":
			if checkpoint_index < checkpoints.size() and vehicle.global_position.distance_to(checkpoints[checkpoint_index]) < T.COURIER_RADIUS:
				reach_checkpoint()
		"retrieve":
			_update_retrieve()
	_physics_extract_arm()
	_update_push(delta)


func _process(_delta: float) -> void:
	_pass_mark()
	zombies.contagion = vehicle.has_sp("sp_contagion")
	if vehicle.strip_pending > 0.0 and state != State.WRECKED:
		scrap += vehicle.strip_pending   # Strip Mine
		vehicle.strip_pending = 0.0
	# Bars, numbers and the status line at ~15 Hz (they allocate strings and
	# arrays); the edge arrows track the camera, so they update every frame.
	_hud_timer -= _delta
	if _hud_timer <= 0.0:
		_hud_timer = HUD_REFRESH
		_refresh_hud()
		hud.right_stick.set_gauges(vehicle.weapon_gauges())
	else:
		_refresh_threats()
	_music_tick(_delta)
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
				_mark_perks(target, float(a.time))
		"flare":
			var r2 := float(a.radius) * float(a.radius)
			for z in zombies.active_zombies():
				if z.global_position.distance_squared_to(vehicle.global_position) <= r2:
					z.apply_status(1.0 + float(a.vuln) + weak, 1.0 - minf(float(a.slow), 0.9), float(a.time))
			if vehicle.has_sp("sp_signal_flare"):
				# Signal Flare: rigs inside become MARKED (+30%, the Mark's own number).
				for c: Node2D in lock_candidates():
					if int(c.get("lock_priority")) >= 2 and c.global_position.distance_squared_to(vehicle.global_position) <= r2:
						c.call("apply_status", 1.3 + weak, 1.0, float(a.time))
						signal_flare_marks += 1
			if vehicle.has_sp("sp_flashbang"):
				# Flashbang: the ignition stuns zombies inside for 1.5 s.
				for z in zombies.active_zombies():
					if z.global_position.distance_squared_to(vehicle.global_position) <= r2:
						z.status.trigger(StatusBars.SHOCK, T.FLASHBANG_STUN)
						flashbanged += 1
			if vehicle.has_sp("sp_magnesium") or vehicle.has_sp("sp_pinned"):
				_flare = {"at": vehicle.global_position, "r": float(a.radius), "left": float(a.time),
					"burn": vehicle.has_sp("sp_magnesium"), "pin": vehicle.has_sp("sp_pinned")}
			fx.call("blast", vehicle.global_position, 60.0)
		"magnet":
			var r := float(a.radius)
			for p in pickups.get_children():
				if (p as Node2D).global_position.distance_to(vehicle.global_position) <= r:
					var lay := (p as Node2D).global_position
					if vehicle.has_sp("sp_second_look") and (p as Pickup).part.is_empty() and _rig_crate.values().has(p):
						_second_look(p as Pickup)
					_take_salvage(p as Pickup)
					if vehicle.has_sp("sp_shrapnel_storm"):
						# Shrapnel Storm: the pulled salvage tears through enemies where it lay.
						vehicle.call("_area_hit", lay, T.SHRAPNEL_STORM_RADIUS, T.SHRAPNEL_STORM_DAMAGE, "")
						shrapnel_storms += 1
					if vehicle.has_sp("sp_scrap_plating") and _scrap_plating < 30.0:
						var add := minf(2.0, 30.0 - _scrap_plating)   # Scrap Plating: 2 per pickup, cap 30
						_scrap_plating += add
						vehicle.repair_armor(add)


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
## The same tips for a controller (only the ones that differ).
const TUT_PAD_TIPS := {
	0: "DRIVE: push the %s stick where you want to go. The rig turns to follow. Pull back to reverse.",
	1: "SHOOT: aim the turret with the %s stick at a zombie and hold %s to fire.",
	2: "LOCK: press %s. While it's on, your turret picks targets and fires by itself.",
}


const TUT_KBM_TIPS := {
	0: "DRIVE: hold W A S D (or the arrow keys) for the way you want to go. The rig turns to follow.",
	1: "SHOOT: the turret follows your mouse. Point at a zombie and hold the left button to fire.",
	2: "LOCK: right-click. While it's on, your turret picks targets and fires by itself.",
}


## Touch <-> controller mid-tutorial: swap the tip's wording.
func _on_pad_mode(_on: bool) -> void:
	if tutorial and tut_step < TUT_TIPS.size() and not bool(_tut_mark.get("spawned", false)):
		hud.set_tip(_tut_tip(tut_step))


func _tut_tip(i: int) -> String:
	var pad := _pad()
	if pad != null and bool(pad.get("kbm")) and TUT_KBM_TIPS.has(i):
		return str(TUT_KBM_TIPS[i])
	if pad == null or not bool(pad.get("active")) or not TUT_PAD_TIPS.has(i):
		return TUT_TIPS[i]
	var swapped := bool(pad.call("sticks_swapped"))
	match i:
		0:
			return str(TUT_PAD_TIPS[0]) % ("RIGHT" if swapped else "LEFT")
		1:
			return str(TUT_PAD_TIPS[1]) % ["LEFT" if swapped else "RIGHT", str(pad.call("button_name", "fire"))]
		_:
			return str(TUT_PAD_TIPS[2]) % str(pad.call("button_name", "lock"))


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
		hud.set_tip(_tut_tip(tut_step))
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


# --- Wreck sequence ------------------------------------------------------------------
# Agreed with the owner: about 4 s, a tap skips to the card. Slow motion on
# the final hit, plates and fire, the horde closes in and everyone aboard is
# dragged out by name.

var wreck_skipped := false
var _in_wreck := false


func _wreck_sequence(aboard: Array[String]) -> void:
	_in_wreck = true
	wreck_skipped = false
	hud.set_tip("")
	hud.close_choice()
	hud.hide_controls()
	var at := vehicle.global_position
	fx.explosion(at, Vector2.ZERO)
	fx.blast(at, 120.0)
	camera.shake(1.0)
	# The horde smells blood: a ring of them closes on the wreck.
	for i in T.WRECK_SWARM:
		zombies.spawn_at(_open_spot(T.WRECK_SWARM_RANGE + 25.0 * i), "shambler")
	var drag := WreckCrew.new()
	drag.names = aboard
	drag.rig = vehicle
	drag.z_index = 7
	add_child(drag)
	Engine.time_scale = T.WRECK_SLOWMO
	var t := 0.0
	while t < T.WRECK_TIME and not wreck_skipped:
		await get_tree().process_frame
		t += get_process_delta_time() / maxf(Engine.time_scale, 0.01)
		if t > T.WRECK_SLOWMO_TIME:
			Engine.time_scale = 1.0
		if t > 0.9 and fx != null and randf() < 0.3:
			fx.flame(at + Vector2(randf_range(-26, 26), randf_range(-16, 16)))
	Engine.time_scale = 1.0
	_in_wreck = false


## A tap (or any pad button) during the wreck skips to the card.
func _input(event: InputEvent) -> void:
	if loading_map:
		get_viewport().set_input_as_handled()
		return
	if not _in_wreck:
		_kbm_event(event)
		return
	if (event is InputEventScreenTouch and (event as InputEventScreenTouch).pressed) or (event is InputEventMouseButton and (event as InputEventMouseButton).pressed) \
			or (event is InputEventJoypadButton and (event as InputEventJoypadButton).pressed):
		wreck_skipped = true


class WreckCrew extends Node2D:
	## The crew dragged from the wreck into the horde, one by one, names in red.
	const T := preload("res://scripts/tuning.gd")
	var names: Array[String] = []
	var rig: Node2D
	var _t := 0.0

	func _process(delta: float) -> void:
		_t += delta / maxf(Engine.time_scale, 0.01)   # real time, through the slow motion
		queue_redraw()

	func _draw() -> void:
		if rig == null:
			return
		var font := ThemeDB.fallback_font
		for i in names.size():
			var k := clampf((_t - 0.6 - 0.7 * i) / 1.3, 0.0, 1.0)
			if k <= 0.0:
				continue
			var dir := Vector2.RIGHT.rotated(-PI * 0.5 + TAU * float(i) / maxf(names.size(), 1.0) + 0.6)
			var at := to_local(rig.global_position) + dir * (20.0 + 150.0 * k)
			var fade := 1.0 - clampf((k - 0.8) / 0.2, 0.0, 1.0) * 0.6
			# Hauled out: a limp figure, a hand on each arm.
			draw_circle(at, 7.0, Color(0.75, 0.6, 0.5, fade))
			draw_line(at, at + dir * 14.0, Color(0.3, 0.28, 0.25, fade), 6.0)
			draw_circle(at + dir * 20.0 + dir.orthogonal() * 8.0, 6.0, Color(0.35, 0.45, 0.3, fade))
			draw_circle(at + dir * 20.0 - dir.orthogonal() * 8.0, 6.0, Color(0.35, 0.45, 0.3, fade))
			draw_string(font, at + Vector2(-120.0, -22.0), names[i].to_upper(), HORIZONTAL_ALIGNMENT_CENTER, 240.0, 22, Color(T.COL_ENEMY, fade))


## The skull's enemy damage on a rig (and a Convoy's trailer).
func _skull_damage(rig: Node) -> void:
	if bool(rig.call("is_elite")):
		return   # a Hunt Elite has its own damage table by skulls
	var m := float(T.ENEMY_DAMAGE_BY_SKULL[skulls - 1])
	rig.set("skull_damage", m)
	if m != 1.0:
		rig.call("scale_damage", m)
		var trailer: Variant = rig.get("trailer")
		if trailer is Node and (trailer as Node).has_method("scale_damage"):
			(trailer as Node).call("scale_damage", m)


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
	if rig is TorcherRig:
		return "torcher"
	if rig is SludgerRig:
		return "sludger"
	if rig is GunnerRig:
		return "gunner"
	return "outrider"


# --- Controller (pad.gd) ------------------------------------------------------------
# By default: left stick drives, right stick aims and R2 fires (a light push
# only turns the turret, as on the touch stick). Square / Triangle / Circle
# fire utilities 1-3, R1 toggles LOCK, L1 opens the crew wheel (point with a
# stick, Cross picks), Options pauses. All rebindable (Pad.binding), and the
# sticks can swap.

var pad_aim := Vector2.RIGHT   # last aim direction, for R2 with the stick centred


func _pad() -> Node:
	return get_node_or_null("/root/Pad")


func _pad_input() -> void:
	var pad := _pad()
	if pad == null or not bool(pad.get("active")):
		vehicle.fire_trigger = false   # put the pad down mid-shot: stop firing
		return
	var drive: Vector2 = pad.call("stick", true)
	var aim: Vector2 = pad.call("stick", false)
	if hud.is_crew_wheel_open():
		hud.pad_wheel_point(aim if aim != Vector2.ZERO else drive)
		vehicle.drive_input = Vector2.ZERO
		vehicle.aim_input = Vector2.ZERO
		return
	if drive != Vector2.ZERO:
		vehicle.drive_input = drive
	if aim != Vector2.ZERO:
		pad_aim = aim.normalized()
	if bool(pad.call("fire_held")):
		# Fire: full push (the Mortar keeps the stick's push for its range).
		var dir := pad_aim if aim == Vector2.ZERO else aim.normalized()
		var push := 1.0 if vehicle.has_weapon() and not _has_mortar() else maxf(aim.length(), 0.55)
		vehicle.aim_input = dir * push
		vehicle.fire_trigger = true
	elif aim != Vector2.ZERO:
		vehicle.aim_input = aim.limit_length(0.45)   # turn the turret without firing
		vehicle.fire_trigger = false
	else:
		vehicle.fire_trigger = false


# --- Mouse and keyboard (PC; pad.gd tracks the scheme) ------------------------------
# WASD / arrows drive, the turret follows the mouse. Fire / lock / pause /
# utilities / crew follow Pad.kbm_map (defaults LMB / RMB / Esc / Q E F / Tab).
# Esc always pauses as a hard fallback. With LOCK on and no fire, the turret
# is left to the lock.

var kbm_mouse_override := Vector2.INF   # tests: a world point standing in for the mouse
var kbm_fire_override := -1             # tests: 1 = left button held, 0 = not


func _kbm_on() -> bool:
	var pad := _pad()
	return pad != null and bool(pad.get("kbm"))


func _kbm_mouse() -> Vector2:
	return kbm_mouse_override if kbm_mouse_override != Vector2.INF else get_global_mouse_position()


func _kbm_firing() -> bool:
	if kbm_fire_override >= 0:
		return kbm_fire_override == 1
	var pad := _pad()
	if pad != null and pad.has_method("kbm_fire_held"):
		return bool(pad.call("kbm_fire_held"))
	return Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)


func _kbm_input() -> void:
	if not _kbm_on() or state != State.RUNNING:
		return
	if hud.is_crew_wheel_open():
		var dir := get_viewport().get_mouse_position() - hud.wheel_center()
		hud.pad_wheel_point(dir.normalized() if dir.length() > 40.0 else Vector2.ZERO)
		vehicle.drive_input = Vector2.ZERO
		vehicle.aim_input = Vector2.ZERO
		vehicle.fire_trigger = false
		return
	var drive := PadScript.kbm_drive()
	if drive != Vector2.ZERO:
		vehicle.drive_input = drive
	var to := _kbm_mouse() - vehicle.global_position
	var dir := to.normalized() if to.length() > 1.0 else Vector2.RIGHT.rotated(vehicle.rotation)
	if _kbm_firing():
		var push := 1.0
		var mortar := _mortar_stats()
		if not mortar.is_empty():
			# The shell lands where you point (within the Mortar's reach).
			var t := clampf(inverse_lerp(float(mortar.get("min_range", 300.0)), float(mortar.get("max_range", 1200.0)), to.length()), 0.0, 1.0)
			push = lerpf(Vehicle.AIM_DEADZONE, 1.0, t)
		vehicle.aim_input = dir * maxf(push, Vehicle.AIM_DEADZONE + 0.01)
		vehicle.fire_trigger = true
	else:
		vehicle.fire_trigger = false
		if not vehicle.lock_enabled:
			vehicle.aim_input = dir * 0.45   # the turret follows the mouse without firing


## Keys and clicks that do one thing per press.
func _kbm_event(event: InputEvent) -> void:
	var pad := _pad()
	if pad != null and ProfileScript.is_desktop() and (event is InputEventKey or event is InputEventMouseButton):
		pad.call("set_kbm", true)   # the fight hears input before Pad does
	if not _kbm_on() or state != State.RUNNING or menu != null or hud.is_result_visible() or hud.is_choice_open():
		return
	if event is InputEventMouseButton and (event as InputEventMouseButton).pressed:
		var mb := event as InputEventMouseButton
		var code := PadScript.kbm_encode_mouse(int(mb.button_index))
		if hud.is_crew_wheel_open():
			# Crew wheel UI keeps left-confirm / right-cancel regardless of fire/lock binds.
			if mb.button_index == MOUSE_BUTTON_LEFT:
				hud.pad_wheel_confirm()
			elif mb.button_index == MOUSE_BUTTON_RIGHT:
				hud.close_crew_wheel()
			return
		match PadScript.kbm_action(code):
			"lock":
				hud.pad_lock()
			"pause":
				open_menu()
			"ability_1":
				use_ability(0)
			"ability_2":
				use_ability(1)
			"ability_3":
				use_ability(2)
			"crew":
				if hud.is_crew_wheel_open():
					hud.close_crew_wheel()
				else:
					hud.open_crew_wheel()
	elif event is InputEventKey and (event as InputEventKey).pressed and not (event as InputEventKey).echo:
		var key := int((event as InputEventKey).physical_keycode)
		if hud.is_crew_wheel_open() and key >= KEY_1 and key <= KEY_9:
			hud.pick_crew(key - KEY_1)
			return
		match PadScript.kbm_action(key):
			"lock":
				hud.pad_lock()
			"pause":
				# Bound pause key (Esc is also handled in _unhandled_input as fallback).
				if key != KEY_ESCAPE:
					open_menu()
			"ability_1":
				use_ability(0)
			"ability_2":
				use_ability(1)
			"ability_3":
				use_ability(2)
			"crew":
				if hud.is_crew_wheel_open():
					hud.close_crew_wheel()
				else:
					hud.open_crew_wheel()


func _mortar_stats() -> Dictionary:
	for w: Dictionary in vehicle.gun_stats:
		if str(w.get("kind", "")) == "mortar":
			return w
	return {}


func _has_mortar() -> bool:
	for w: Dictionary in vehicle.gun_stats:
		if str(w.get("kind", "")) == "mortar":
			return true
	return false


## Menu focus only when a panel is up (the pause menu, results, the radio call).
func pad_wants_focus() -> bool:
	return menu != null or hud.is_result_visible() or hud.is_choice_open()


## A pad button in the fight (bound in Settings > CONTROLLER; pad.gd).
## Returns true when it was used. Start / OPTIONS always pauses as a fallback.
func pad_button(button: int) -> bool:
	if loading_map:
		return true   # swallowed behind the loading screen
	var pad := _pad()
	var action := str(pad.call("action_for", button)) if pad != null else ""
	var pause_press := action == "pause" or button == JOY_BUTTON_START
	if menu != null:
		if pause_press:
			menu.resume()
			return true
		return false
	if hud.is_result_visible() or hud.is_choice_open() or state != State.RUNNING:
		return false
	if hud.is_crew_wheel_open() and button == JOY_BUTTON_A:
		hud.pad_wheel_confirm()   # Cross picks in the wheel, whatever it's bound to
		return true
	if pause_press:
		open_menu()
		return true
	match action:
		"ability_1":
			use_ability(0)
		"ability_2":
			use_ability(1)
		"ability_3":
			use_ability(2)
		"lock":
			hud.pad_lock()
		"crew":
			if hud.is_crew_wheel_open():
				hud.close_crew_wheel()
			else:
				hud.open_crew_wheel()
		_:
			return false
	return true


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
	menu.abandon_requested.connect(abandon_job)
	hud.add_child(menu)
	return menu


func _on_menu_closed() -> void:
	menu = null
	get_tree().paused = false


## ABANDON JOB from the pause menu (playtest 2 #7): give the job up and go
## home. Like a failed job the day passes with no job pay, but nothing picked
## up comes home either (kill scrap, salvage, schematics). The rig and the
## crew are kept: not a wreck, no wreck count, no crew lost, no crew XP.
## Injuries already taken in this fight stand.
func abandon_job() -> void:
	if tutorial or state != State.RUNNING:
		return
	menu = null
	state = State.FAILED
	get_tree().paused = false
	Engine.time_scale = 1.0
	if _music != null:
		_music.end_combat()
	var hurt := _rest_ids()
	profile.finish_day()
	profile.bank_crew(0, hurt, bool(vehicle.crew_mod("triage")), vehicle.has_sp("sp_clean_bandage"))
	abandoned = true
	get_tree().change_scene_to_file(GARAGE_SCENE)


## The fight starts over: same job, same rig and crew, nothing lost.
func restart_job() -> void:
	_restarting = true
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
			go_back()
		NOTIFICATION_APPLICATION_PAUSED, NOTIFICATION_APPLICATION_FOCUS_OUT:
			if not DisplayServer.get_name() == "headless":
				open_menu()


## The phone's back button, or Esc on a PC: up a menu page, or pause.
func go_back() -> void:
	if menu != null:
		menu.back()
	else:
		open_menu()


func _unhandled_input(event: InputEvent) -> void:
	if loading_map:
		return
	if menu == null and event is InputEventKey and (event as InputEventKey).pressed and not (event as InputEventKey).echo and (event as InputEventKey).keycode == KEY_ESCAPE:
		go_back()
		get_viewport().set_input_as_handled()


func _exit_tree() -> void:
	Engine.time_scale = 1.0
	if not _restarting:
		Arena.clear_cache()   # left the job: free the baked map
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
	all.append_array(torchers)
	all.append_array(sludgers)
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
			"torcher":
				e[3] = spawn_torcher(zombies.pick_spawn_point()) != null
			"sludger":
				e[3] = spawn_sludger(zombies.pick_spawn_point()) != null
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


## Sends in the Torcher (proposal 01), if there's room under the rig cap.
func spawn_torcher(at: Vector2) -> EnemyRig:
	if active_rig_count() >= T.MAX_ENEMY_RIGS:
		return null
	for rig in torchers:
		if not rig.is_inside_tree():
			(rig as TorcherRig).hazards = hazards
			rig.position = at
			rig.rotation = (vehicle.global_position - at).angle()
			rigs.add_child(rig)
			hud.banner("TORCHER INBOUND  -  HIT ITS FUEL TANK", T.COL_ENEMY)
			return rig
	return null


## Sends in the Sludger (proposal 01), if there's room under the rig cap.
func spawn_sludger(at: Vector2) -> EnemyRig:
	if active_rig_count() >= T.MAX_ENEMY_RIGS:
		return null
	for rig in sludgers:
		if not rig.is_inside_tree():
			rig.shells = shells
			rig.position = at
			rig.rotation = (vehicle.global_position - at).angle()
			rigs.add_child(rig)
			hud.banner("SLUDGER INBOUND  -  WATCH THE SKY", T.COL_ENEMY)
			return rig
	return null


## Drop the first pending event of `kind` (a seeded rig took its slot).
func _drop_event(kind: String) -> void:
	for i in _events.size():
		if str(_events[i][1]) == kind and not _events[i][3]:
			_events.remove_at(i)
			return


## Turn the first pending event of `kind` into `into`. False if none.
func _swap_event(kind: String, into: String) -> bool:
	for e: Array in _events:
		if str(e[1]) == kind and not e[3]:
			e[1] = into
			return true
	return false


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
		_sfx("courier_complete")
		_succeed(title, "Time %s" % _clock(elapsed), float(T.COURIER_TIER_PAY[tier]))
	else:
		_sfx("courier_checkpoint")
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
	if rose and T.RETRIEVE_RIG_STEPS.has(step) and _sludger_call:
		# Retrieve's Sludger is called in like the other rigs, on the first
		# danger step that calls one (or the first step, if none are due).
		_sludger_call = false
		_events.append([elapsed, "sludger", -1, false])
		hud.banner("THE BLOCK IS STIRRING  -  DANGER %d" % step, Color(0.95, 0.8, 0.3), 2.0)
	elif rose and T.RETRIEVE_RIG_STEPS.has(step) and _rig_calls_made < _rig_calls:
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


## The Escort truck's HP share (0..1): what's left before it's wrecked.
func truck_hp_ratio() -> float:
	if truck == null or truck.is_wrecked:
		return 0.0
	return clampf(truck.hp / maxf(truck.hp_max, 1.0), 0.0, 1.0)


## The truck took damage in the last T.TRUCK_HIT_WINDOW seconds.
func truck_under_attack() -> bool:
	return truck != null and not truck.is_wrecked and elapsed - truck_hit_at < T.TRUCK_HIT_WINDOW


## The truck is outside the camera view.
func truck_off_screen() -> bool:
	if truck == null:
		return false
	var p := get_viewport().get_canvas_transform() * truck.global_position
	return not get_viewport().get_visible_rect().has_point(p)


## Escort: a pulsing warning while the truck's HP is low (playtest 15: it
## went from "65%" to wrecked with no signal).
func _truck_warning() -> void:
	if truck == null:
		return
	# Playtest 2: hit while off-screen, with no cue but the % text.
	if state == State.RUNNING and truck_under_attack() and truck_off_screen() and elapsed - _truck_banner_at > T.TRUCK_HIT_BANNER_EVERY:
		_truck_banner_at = elapsed
		hud.banner("TRUCK UNDER ATTACK", T.COL_UI_DANGER_TEXT, 1.6)
	var low := state == State.RUNNING and not truck.is_wrecked and truck_hp_ratio() <= T.TRUCK_LOW_WARN
	if low and not truck_alert:
		truck_alert = true
		hud.set_alert("TRUCK HP LOW  -  GET BACK TO IT")
		camera.shake(0.2)
	elif not low and truck_alert:
		truck_alert = false
		hud.set_alert("")


## The Escort truck's stat sheet at `skull_level`.
static func truck_sheet(skull_level: int) -> Dictionary:
	var mult := float(T.ENEMY_DAMAGE_BY_SKULL[clampi(skull_level, 1, 6) - 1])
	var sheet: Dictionary = T.TRUCK.duplicate()
	for key: String in ["armor", "hp", "front", "side", "rear"]:
		sheet[key] = float(T.TRUCK[key]) * mult
	return sheet


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
	if _music != null:
		_music.end_combat()
	# Only what you picked up comes home (a cleared job hauls in the rest).
	bank_report = profile.bank_run(int(scrap), _pending_ids(), false)
	profile.finish_day()
	profile.bank_crew(0, _rest_ids(), bool(vehicle.crew_mod("triage")), vehicle.has_sp("sp_clean_bandage"))
	var lines := detail + "\nKill scrap +%d    Time %s" % [int(scrap), _clock(elapsed)]
	hud.show_result(title, lines, "RETURN TO GARAGE", T.COL_ORANGE)
	hud.show_finds(_schematic_finds())   # V1.3


## Results card lines for the schematics banked this run (V1.3).
func _schematic_finds() -> Array:
	var finds: Array = []
	for id: String in bank_report.unlocked:
		var p := Parts.get_part(id)
		finds.append(["New schematic: " + Parts.describe(p), str(p.rarity)])
	return finds


# --- HUD -------------------------------------------------------------------------

func _refresh_hud() -> void:
	hud.set_armor((vehicle.armor + vehicle.hp) / maxf(vehicle.armor_max + vehicle.hp_max, 1.0))   # armor + HP: bar and number
	var plates := PackedFloat32Array([0.0, 0.0, 0.0, 0.0])
	for i in 4:
		plates[i] = vehicle.facing_armor[i] / vehicle.facing_max[i] if vehicle.facing_max[i] > 0.0 else -1.0
	hud.set_defense(vehicle.shield / vehicle.shield_max if vehicle.shield_max > 0.0 else -1.0, plates, vehicle.hp / maxf(vehicle.hp_max, 1.0))
	hud.set_statuses(vehicle.status.build, vehicle.status.left)
	# A dead rig draws nothing (retest: PWR stayed 100/100 at 0 HP).
	var draw := 0.0 if vehicle.hp <= 0.0 or state == State.WRECKED else vehicle.power_load()
	hud.set_power(draw, vehicle.power_capacity(), vehicle.weight_load, vehicle.weight_limit())
	for i in vehicle.crew.size():
		_crew_state(i)
	for i in vehicle.abilities.size():
		hud.set_ability_charge(i, vehicle.ability_charge(i))
	hud.set_status_text(_status_line())
	_truck_warning()
	hud.set_lock_state(vehicle.lock_enabled, vehicle.lock_target != null)
	_refresh_threats()


func _refresh_threats() -> void:
	# Edge arrows: specials always, the Courier's next stop, salvage, and the
	# last few shamblers in a Clear.
	var points := _threat_points
	var colors := _threat_colors
	var pulse := -1
	points.clear()
	colors.clear()
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
			if truck_under_attack():
				pulse = points.size() - 1   # playtest 2: its edge arrow pulses while it's hit
		if mission_type == "clear" and zombies.remaining() <= T.STRAGGLER_ARROWS:
			for p in zombies.active_positions():
				points.append(to_screen * p)
				colors.append(T.COL_ORANGE)
	hud.set_threats(points, colors, pulse)


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
			# HP, not armor + HP: armor sits on four facings, so the old total kept
			# counting an untouched side and read 65% when the truck was one bite
			# from a wreck (playtest 15).
			var hp := roundi(truck_hp_ratio() * 100.0)
			var site := "SALVAGING %ds" % ceili(truck.work_left) if truck.working else "DRIVING"
			return "ESCORT  SITE %d / %d   %s   TRUCK HP %d%%" % [mini(truck.site_index + 1, truck.sites.size()), truck.sites.size(), site, hp] + tail
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
	if state == State.WRECKED:
		return   # the rig's gone: kills behind the wreck pay nothing (hand playtest)
	kills += 1
	var mult := profile.salvage_mult() * float(vehicle.crew_mod("scrap"))
	if rig:
		mult *= float(vehicle.crew_mod("rig_scrap"))
		if vehicle.has_mod("cargo_bay"):
			mult *= 1.0 + Mods.CARGO_BAY   # Hauler Frame's Cargo Bay mod
	scrap += points * mult
	if vehicle.ability_active("gold_rush"):
		# Gold Rush's share of the kill (Safe Deposit banks it even on a wreck).
		var gr := 1.0 + float((vehicle._active["gold_rush"] as Dictionary).get("bonus", 0.0))
		gold_rush_scrap += points * mult * (1.0 - 1.0 / gr)
	if state == State.RUNNING and mission_type == "clear" and kills >= target_kills and push_state == Push.NONE:
		_succeed("BLOCK CLEARED", "", 1.0)


## Night surge telegraph (PR #69): NIGHT_SURGE_WARN s before the horde frenzies.
func _on_surge_warned() -> void:
	if state == State.RUNNING:
		hud.banner("THE HORDE STIRS", T.COL_ORANGE, T.NIGHT_SURGE_WARN + T.NIGHT_SURGE_TIME)


func _on_zombie_killed(at: Vector2, kind: String) -> void:
	splats.add(at)
	fx.gore(at, (at - vehicle.global_position).normalized())
	_add_kill(Missions.night_kill_scrap(int(T.ZOMBIE_KINDS[kind].scrap), night))
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
				["fire", hazards.fire_at(at, rig.team)], ["slime", hazards.slime_at(at)], ["bile", hazards.is_marked(rig)], ["acid", hazards.acid_at(at, rig.team)]]:
			if bool(pair[1]):
				profile.discover("hazards", str(pair[0]))
	rig.set_on_slime(hazards.slick_at(rig.global_position, rig.team), delta)
	rig.set_on_spikes(hazards.spike_at(rig.global_position, rig.team), delta)
	# A Scrapper has no immunity to its own oil once it's lit (approved 2026-11-03).
	var burn_victim := GroundHazards.NEUTRAL if rig is ScrapperRig else rig.team
	if hazards.fire_at(rig.global_position, burn_victim):
		rig.add_buildup(StatusBars.FIRE, T.STATUS_POOL_BUILDUP * delta)
	if hazards.acid_at(rig.global_position, rig.team):
		rig.add_buildup(StatusBars.ACID, T.STATUS_POOL_BUILDUP * delta)


## A status started on your rig. GOOPED marks it for the horde.
func _on_status_started(k: int) -> void:
	profile.discover("hazards", "status_" + str(STATUS_IDS[k]))
	if k == StatusBars.GOOP:
		hazards.mark(vehicle)
		# Say what it means (playtest 15: an unexplained GOOPED tag).
		hud.banner("GOOPED!  ZOMBIES NEARBY RUSH YOU", T.STATUS_COLORS[StatusBars.GOOP], 2.5)


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
	_add_kill(Missions.night_kill_scrap(T.HUNTER_SCRAP, night))


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
		_crate_pool[pickup] = pool
	var unknown := profile.unknown_schematics(Parts.DROP_POOLS[pool], _pending_ids())
	var chance := minf(profile.schematic_chance() + float(vehicle.crew_mod("schematic")), 0.95)
	if rig != null:
		_rig_wreck_perks(at)
		if vehicle.has_sp("sp_jackpot"):
			guaranteed = true   # Jackpot: rig wrecks always drop a schematic
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


func _on_torcher_wrecked(rig: EnemyRig) -> void:
	camera.shake(0.7)
	if _wrecked_again(rig):
		return
	_drop(rig.global_position, "torcher", false, T.TORCHER_SCRAP_CACHE, rig)
	hud.banner("TORCHER DOWN  -  GRAB THE SALVAGE", T.COL_CYAN)
	_add_kill(T.TORCHER_SCRAP, true)
	_salvage_plating()


func _on_sludger_wrecked(rig: EnemyRig) -> void:
	camera.shake(0.7)
	if _wrecked_again(rig):
		return
	_drop(rig.global_position, "sludger", false, T.SLUDGER_SCRAP_CACHE, rig)
	hud.banner("SLUDGER DOWN  -  GRAB THE SALVAGE", T.COL_CYAN)
	_add_kill(T.SLUDGER_SCRAP, true)
	_salvage_plating()


## An enemy rig went GOOPED (your Goop Launcher, a Boomer): the horde nearby
## goes for it instead of you.
func _on_enemy_status(k: int, rig: EnemyRig) -> void:
	if k == StatusBars.GOOP:
		zombies.bait = rig
		zombies.bait_left = float(T.STATUS_TIME_RIG[StatusBars.GOOP])


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
	if crate != null and is_instance_valid(crate) and (crate as Node).get_parent() == pickups and vehicle.has_sp("sp_snatch"):
		# Snatch (Magpie): the crate is yours before the Patcher can take it back.
		_take_salvage(crate as Pickup)
		snatched += 1
		crate = null
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
# --- Crew perks that reach past the rig (implement-03) -----------------------------

var signal_flare_marks := 0     # tests
var _scrap_plating := 0.0
var _mark_time := 0.0


## Exposed / Shutdown on a freshly MARKED rig.
func _mark_perks(target: Node2D, time: float) -> void:
	_mark_time = time
	if int(target.get("lock_priority")) < 2:
		return
	if vehicle.has_sp("sp_exposed"):
		target.set("_shield_wait", time)   # its shield stops recharging
	if vehicle.has_sp("sp_shutdown"):
		target.set("shutdown_left", 3.0)


## Pass It On: when a MARKED target dies, the Mark jumps to the nearest rig.
func _pass_mark() -> void:
	if marked == null or not vehicle.has_sp("sp_pass_it_on"):
		return
	var dead := not is_instance_valid(marked) or bool(marked.get("is_wrecked")) or not bool(marked.get("active") if marked.get("active") != null else true)
	if not dead:
		return
	var from := marked.global_position if is_instance_valid(marked) else vehicle.global_position
	marked = null
	var best := INF
	var next: Node2D = null
	for c: Node2D in lock_candidates():
		if int(c.get("lock_priority")) >= 2 and not bool(c.get("is_wrecked")):
			var d := c.global_position.distance_to(from)
			if d < best:
				best = d
				next = c
	if next != null:
		next.call("apply_status", 1.3 + float(vehicle.crew_mod("weak_spot")), 1.0, _mark_time)
		marked = next
		_mark_perks(next, _mark_time)


## Bounty (+10 scrap) and Powder Keg (wrecks during Cook Off burst like a Fire barrel).
func _rig_wreck_perks(at: Vector2) -> void:
	if vehicle.has_sp("sp_bounty"):
		scrap += 10.0
	if vehicle.has_sp("sp_powder_keg") and vehicle.ability_active("cook_off"):
		hazards.call("add_fire", at, T.BARREL_RADIUS * 0.7, T.BARREL_FIRE_GROUND_TIME)
		var r2 := T.BARREL_RADIUS * T.BARREL_RADIUS
		for z in zombies.active_zombies():
			if z.global_position.distance_squared_to(at) <= r2:
				z.call("take_hit", T.BARREL_FIRE_DAMAGE, (z.global_position - at).normalized() * 300.0, "blast", "fire")
		for c: Node2D in lock_candidates():
			if int(c.get("lock_priority")) >= 2 and c.global_position.distance_squared_to(at) <= r2:
				c.call("take_hit", T.BARREL_FIRE_DAMAGE, (c.global_position - at).normalized() * 300.0, "blast", "fire")
		fx.call("blast", at, T.BARREL_RADIUS)
		powder_kegs += 1


var powder_kegs := 0   # tests
var flashbanged := 0   # tests
var shrapnel_storms := 0
var snatched := 0
var second_looks := 0
var chain_reactions := 0
var gold_rush_scrap := 0.0
var _flare := {}
var _crate_pool := {}


## Magnesium (burns inside) and Pinned (no Hunter pounce) last as long as the Flare.
func _tick_flare(delta: float) -> void:
	if _flare.is_empty():
		return
	_flare.left = float(_flare.left) - delta
	if float(_flare.left) <= 0.0:
		_flare = {}
		return
	var at: Vector2 = _flare.at
	var r := float(_flare.r)
	if bool(_flare.burn):
		for z in zombies.active_zombies():
			if z.global_position.distance_to(at) <= r:
				z.add_buildup(StatusBars.FIRE, T.MAGNESIUM_BUILDUP * delta)
		for c: Node2D in lock_candidates():
			if int(c.get("lock_priority")) >= 2 and c.has_method("add_buildup") and c.global_position.distance_to(at) <= r:
				c.call("add_buildup", StatusBars.FIRE, T.MAGNESIUM_BUILDUP * delta)
	if bool(_flare.pin):
		for h in hunters:
			if h.active and h.global_position.distance_to(at) <= r:
				h.pinned_left = 0.2


## Second Look (Magpie): a pulled rig crate that rolled scrap rolls again.
func _second_look(p: Pickup) -> void:
	second_looks += 1
	var unknown := profile.unknown_schematics(Parts.DROP_POOLS[str(_crate_pool.get(p, "outrider"))], _pending_ids())
	var chance := minf(profile.schematic_chance() + float(vehicle.crew_mod("schematic")), 0.95)
	if not unknown.is_empty() and (always_drop_schematic or randf() < chance):
		p.part = Parts.get_part(unknown.pick_random())


## Chain Reaction (Demolisher): a barrel set off during Cook Off lights oil 200 px out.
func _chain_reaction(at: Vector2) -> void:
	if vehicle.ability_active("cook_off") and vehicle.has_sp("sp_chain_reaction"):
		hazards.call("ignite_oil", at, T.CHAIN_REACTION_OIL)
		chain_reactions += 1


## Crew who rest after the job (Full Recovery: nobody).
func _rest_ids() -> Array[int]:
	if vehicle.has_sp("sp_full_recovery"):
		var none: Array[int] = []
		return none
	return injured_crew_ids()


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
		hud.banner("SCHEMATIC: " + Parts.describe(pickup.part).to_upper(), UI.rarity_color(str(pickup.part.rarity)), 3.0)
	# A Hunt ends when the Elite's drop is in the rig. (Not "when the ground is
	# empty": a Tank's or escort's cache lying elsewhere mustn't block it.)
	var elite_drop: bool = elite != null and _rig_crate.get(elite) == pickup
	# Out of the tree now, so a second physics tick this frame can't collect it twice.
	pickups.remove_child(pickup)
	pickup.queue_free()
	if state == State.RUNNING and mission_type == "hunt" and elite != null and elite.is_wrecked and elite_drop:
		_succeed("TARGET DOWN", "", 1.0)


func _on_damaged(amount: float) -> void:
	if amount >= 2.0:
		camera.shake(amount / 30.0)


# --- Endings ---------------------------------------------------------------------

## Success: bank the run's scrap plus the job's pay (x `pay_mult`) and any
## schematics, end the day, show the results card.
func _succeed(title: String, detail: String, pay_mult: float) -> void:
	if state != State.RUNNING:
		return
	if not _push_finishing:
		if mission_type == "retrieve" and push_state == Push.ACTIVE:
			if not _push_blocked_warned:
				_push_blocked_warned = true
				hud.banner("HOLD OUT  -  THE PUSH ISN'T OVER", T.COL_ORANGE, 1.6)
			return
		if mission_type == "retrieve" and push_state == Push.EXTRACT:
			pushed = true
			push_state = Push.DONE
		elif mission_type != "retrieve" and push_state == Push.NONE and _push_offerable():
			_offer_push(title, detail, pay_mult)
			return
		elif push_state != Push.NONE and push_state != Push.DONE and mission_type != "retrieve":
			return
	if pushed:
		pay_mult *= T.PUSH_PAY
		detail = ("PUSHED  -  " + detail) if detail != "" else "PUSHED"
	hud.close_crew_wheel(false)
	Engine.time_scale = 1.0
	state = State.CLEARED
	if _music != null:
		_music.end_combat()
	# The job's done: anything still on the ground gets hauled home.
	for p in pickups.get_children():
		_take_salvage(p as Pickup)
	var pay := roundi(Missions.night_pay(int(spec.reward), spec) * pay_mult)
	var reward_part := _mission_reward_schematic(pay_mult)
	var ids := _pending_ids()
	if reward_part != "":
		ids.append(reward_part)
	if pushed:
		var extra := _push_schematic(ids)
		if extra != "":
			ids.append(extra)
	bank_report = profile.bank_run(int(scrap) + pay, ids)
	profile.finish_day()
	# After the day ends, so tonight doesn't count toward anyone's rest.
	var crew_lines := profile.bank_crew(roundi(skulls * T.PUSH_XP) if pushed else skulls, _rest_ids(), bool(vehicle.crew_mod("triage")), vehicle.has_sp("sp_clean_bandage"), T.NIGHT_XP_MULT if night else 1.0)
	var lines := "Job pay +%d    Kill scrap +%d    Time %s" % [pay, int(scrap), _clock(elapsed)]
	if detail != "":
		lines = detail + "\n" + lines
	if not crew_lines.is_empty():
		lines += "\nCrew: " + ";  ".join(crew_lines)
	Engine.time_scale = 1.0
	hud.show_result(title, lines, "RETURN TO GARAGE", _type_color())
	hud.show_finds(_schematic_finds())   # V1.3


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


# --- Extract or Push (§14, proposal 01) ------------------------------------------

## Can this job offer the push now? Escort only if the risky site was
## skipped (agreed with the owner, T.PUSH_RETRIEVE_ESCORT).
func _push_offerable() -> bool:
	if not push_allowed:
		return false
	if mission_type == "escort" and optional_taken:
		return false
	return true


## The objective's done: show both markers and hold the result.
func _offer_push(title: String, detail: String, pay_mult: float) -> void:
	_push_pending = {"title": title, "detail": detail, "pay": pay_mult}
	push_state = Push.CHOOSING
	push_extract = vehicle.global_position
	push_at = _open_spot(T.PUSH_MARKER_GAP)
	hud.banner("EXTRACT (CYAN) OR PUSH (ORANGE)?", T.COL_ORANGE, 3.0)


## Retrieve (pending confirmation): the beacon shows once every non-deep cache is out.
func _check_retrieve_push() -> void:
	if push_state != Push.NONE or not push_allowed:
		return
	for i in caches.size():
		if i != deep_cache and not cache_taken[i]:
			return
	push_state = Push.CHOOSING
	push_extract = extract_at
	push_at = _open_spot(T.PUSH_MARKER_GAP)
	hud.banner("PUSH BEACON UP  -  ORANGE TO PUSH, EXTRACT AS USUAL", T.COL_ORANGE, 3.0)


## The push's skull row: the job's skulls +1 (cap 6).
func push_skulls() -> int:
	return mini(skulls + 1, T.MAX_SKULLS)


## Extra rigs the push brings: one, or two at 6 skulls (instead of +1 skull).
func push_extra_rigs() -> int:
	return 2 if skulls >= T.MAX_SKULLS else 1


func start_push() -> void:
	push_state = Push.ACTIVE
	push_left = float(T.PUSH_SECONDS[skulls - 1])
	var up := spec.duplicate()
	up.skulls = push_skulls()
	zombies.set_mix(push_skulls(), false)
	zombies.cap = maxi(zombies.cap, int(Missions.stat(up, "cap")))
	zombies.spawn_budget = 1000000
	_push_rigs_due = push_extra_rigs()
	hud.banner("PUSHING  -  HOLD OUT %d s" % int(push_left), T.COL_ORANGE, 2.5)


func _update_push(delta: float) -> void:
	if mission_type == "retrieve":
		_check_retrieve_push()
	match push_state:
		Push.CHOOSING:
			var at := vehicle.global_position
			if at.distance_to(push_at) < T.PUSH_RADIUS:
				start_push()
			elif mission_type != "retrieve" and at.distance_to(push_extract) < T.PUSH_RADIUS and _left_extract_once():
				_finish_push(false)
		Push.ACTIVE:
			push_left -= delta
			while _push_rigs_due > 0 and active_rig_count() < T.MAX_ENEMY_RIGS:
				var rig: EnemyRig = spawn_outrider(zombies.pick_spawn_point()) if _push_rigs_due % 2 == 1 else spawn_gunner(zombies.pick_spawn_point())
				if rig == null:
					break
				_push_rigs_due -= 1
			if push_left <= 0.0:
				push_state = Push.EXTRACT
				push_extract = push_at
				push_left = T.PUSH_EXTRACT_WINDOW
				if mission_type == "retrieve":
					hud.banner("PUSH DONE  -  GET TO THE EXTRACTION POINT", T.COL_CYAN, 2.5)
				else:
					hud.banner("PUSH DONE  -  EXTRACT AT THE BEACON", T.COL_CYAN, 2.5)
		Push.EXTRACT:
			if mission_type == "retrieve":
				return   # extracting at the usual point ends it
			push_left -= delta
			if vehicle.global_position.distance_to(push_extract) < T.PUSH_RADIUS or push_left <= 0.0 or active_rig_count() == 0:
				_finish_push(true)


var _extract_left := false
## The extraction marker spawns under you: it counts once you've left it.
func _left_extract_once() -> bool:
	return _extract_left


func _physics_extract_arm() -> void:
	if push_state == Push.CHOOSING and not _extract_left and vehicle.global_position.distance_to(push_extract) > T.PUSH_RADIUS * 1.5:
		_extract_left = true


func _finish_push(did_push: bool) -> void:
	pushed = did_push
	push_state = Push.DONE
	_push_finishing = true
	_succeed(str(_push_pending.get("title", "DONE")), str(_push_pending.get("detail", "")), float(_push_pending.get("pay", 1.0)))
	_push_finishing = false


## The push's extra schematic roll, at the push's skull odds.
func _push_schematic(taken: Array[String]) -> String:
	var pool: Array = Parts.DROP_POOLS.get(mission_type, [])
	var unknown := profile.unknown_schematics(pool, taken)
	var up := spec.duplicate()
	up.skulls = push_skulls()
	if unknown.is_empty() or randf() >= Missions.schematic_chance(up):
		return ""
	return unknown.pick_random()


func _on_wrecked() -> void:
	if state != State.RUNNING:
		return
	hud.close_crew_wheel(false)
	Engine.time_scale = 1.0
	state = State.WRECKED
	if _music != null:
		_music.play_wreck()
	camera.shake(1.0)
	var aboard: Array[String] = []
	for m in profile.seated_crew():
		aboard.append(str(m.name))
	profile.record_wreck()
	var deposit := 0
	if vehicle.has_sp("sp_safe_deposit") and gold_rush_scrap >= 1.0:
		deposit = int(gold_rush_scrap)   # Safe Deposit: Gold Rush scrap survives the wreck
		profile.scrap += deposit
		scrap -= deposit
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
	if deposit > 0:
		lines += "\nSafe Deposit: %d Gold Rush scrap kept." % deposit
	if scrap >= 1.0 or not salvage.is_empty():
		lines += "\nSalvage lost with the rig: %d scrap" % int(scrap)
		if not salvage.is_empty():
			lines += ", %d schematic%s" % [salvage.size(), "" if salvage.size() == 1 else "s"]
		lines += "."
	await _wreck_sequence(aboard)
	hud.show_result("WRECKED", lines, "BACK TO THE YARD", T.COL_ORANGE)
	# Freeze the fight behind the result (hand playtest: it kept running and the
	# horde kept chewing). The overlay runs while paused; leaving unpauses (_exit_tree).
	if is_inside_tree():
		get_tree().paused = true


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
		if mission != null and (str(mission.get("mission_type")) in ["courier", "retrieve", "escort"] or int(mission.get("push_state")) != 0):
			queue_redraw()

	func _draw() -> void:
		if mission == null:
			return
		_draw_push()
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

	## Extract or Push: the cyan extraction marker and the orange push beacon.
	func _draw_push() -> void:
		var state: int = mission.get("push_state")
		if state == 0 or state == 4:
			return
		var pulse := 0.5 + 0.5 * sin(_t * 5.0)
		var ex: Vector2 = mission.get("push_extract")
		var beacon: Vector2 = mission.get("push_at")
		if state == 1 and beacon != Vector2.INF:
			draw_circle(beacon, T.PUSH_RADIUS, Color(T.COL_ORANGE, 0.10 + 0.08 * pulse))
			draw_arc(beacon, T.PUSH_RADIUS, 0.0, TAU, 48, Color(T.COL_ORANGE, 0.9), 4.0)
		if (state == 1 or state == 3) and ex != Vector2.INF and str(mission.get("mission_type")) != "retrieve":
			draw_circle(ex, T.PUSH_RADIUS, Color(T.COL_CYAN, 0.10 + 0.08 * pulse))
			draw_arc(ex, T.PUSH_RADIUS, 0.0, TAU, 48, Color(T.COL_CYAN, 0.9), 4.0)

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


# --- Music and effects (MusicManager autoload) ------------------------------------

var _music: Node = null
var _music_wait := 0.0
var _courier_tier := "gold"


func _music_start() -> void:
	_music = get_node_or_null("/root/MusicManager")
	if _music == null:
		return
	_music.start_combat(mission_type == "courier")
	for rig in _all_enemy_rigs():
		rig.wrecked.connect(_sfx.bind("rig_wrecked"))


## A few times a second: what's in the fight picks the combat layer. Rigs and
## zombies alive set the base; an elite alive, the player's rig low on armor
## and the last stretch of a Survive each push it up a step (tuning.gd).
func _music_tick(delta: float) -> void:
	if _music == null or state != State.RUNNING:
		return
	_music_wait -= delta
	if _music_wait > 0.0:
		return
	_music_wait = T.MUSIC_CHECK_EVERY
	_music.set_intensity(_music.intensity_for(active_rig_count(), zombies.active_count(), music_boosts()))
	if mission_type == "courier":
		var tier := courier_tier()
		if tier != _courier_tier:
			_courier_tier = tier
			_sfx("courier_warning")   # a par tier just slipped away


## Steps the music goes up on top of the rig/zombie count.
func music_boosts() -> int:
	var n := 0
	if _elite_alive():
		n += T.MUSIC_ELITE_BOOST
	if vehicle != null and vehicle.armor_max > 0.0 and vehicle.armor / vehicle.armor_max <= T.MUSIC_LOW_ARMOR:
		n += T.MUSIC_LOW_ARMOR_BOOST
	if mission_type == "survive" and float(Missions.stat(spec, "seconds")) - elapsed <= T.MUSIC_SURVIVE_FINAL_SECONDS:
		n += T.MUSIC_SURVIVE_FINAL_BOOST
	return n


func _elite_alive() -> bool:
	if elite != null and not elite.is_wrecked:
		return true
	for rig in convoys:
		if not rig.is_wrecked:
			return true
	return false


func _sfx(id: String) -> void:
	if _music != null:
		_music.play_sfx(id)
