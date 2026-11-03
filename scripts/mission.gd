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
const Splats := preload("res://scripts/splats.gd")
const ZombieDirector := preload("res://scripts/zombie_director.gd")
const Vehicle := preload("res://scripts/vehicle.gd")
const EnemyRig := preload("res://scripts/enemy_rig.gd")
const BulwarkRig := preload("res://scripts/bulwark_rig.gd")
const Crew := preload("res://scripts/crew.gd")
const Hunter := preload("res://scripts/hunter.gd")
const BulletPool := preload("res://scripts/bullet_pool.gd")
const MinePool := preload("res://scripts/mine_pool.gd")
const Fx := preload("res://scripts/fx.gd")
const Pickup := preload("res://scripts/pickup.gd")
const LockReticle := preload("res://scripts/lock_reticle.gd")
const ChaseCamera := preload("res://scripts/chase_camera.gd")
const Hud := preload("res://scripts/hud.gd")
const NavGrid := preload("res://scripts/nav_grid.gd")
const ProfileScript := preload("res://scripts/profile.gd")
const GARAGE_SCENE := "res://scenes/garage.tscn"
const HUNTER_POOL := 2

enum State { RUNNING, WRECKED, CLEARED }

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
var marked: Node2D               # the last target a Spotter marked (tests)
var bullets: BulletPool
var mines: MinePool
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

var _events: Array = []          # [seconds, kind, kills that also trigger it (-1 = none), fired]


func _ready() -> void:
	profile = get_node("/root/Profile")
	if not mission_override.is_empty():
		spec = mission_override
	elif profile.has_mission():
		spec = profile.active_mission
	else:
		spec = Missions.default_mission()
	mission_type = str(spec.type)
	skulls = Missions.skulls(spec)

	arena = Arena.new()
	splats = Splats.new()
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
	fx = Fx.new()
	fx.z_index = 5
	pickups = Node2D.new()
	reticle = LockReticle.new()
	camera = ChaseCamera.new()
	hud = Hud.new()
	nav = NavGrid.new()
	markers = CourierMarkers.new()
	markers.z_index = 1

	# The rig from the garage. Tests (or a missing rig) fall back to the starter.
	var loadout: Dictionary = profile.rig if profile.has_rig() else Parts.STARTER_LOADOUT
	vehicle.apply_stats(Loadout.build(loadout))
	vehicle.set_crew(crew_override if not crew_override.is_empty() else profile.seated_crew())
	profile.start_run()

	_configure_mission()

	# Wire references before adding to the tree so every _ready() sees them.
	vehicle.position = Arena.PLAYER_START
	vehicle.rotation = -PI / 2.0
	vehicle.bullets = bullets
	vehicle.mines = mines
	vehicle.fx = fx
	vehicle.lock_candidates = lock_candidates
	for rig: EnemyRig in _all_enemy_rigs():
		rig.player = vehicle
		rig.bullets = bullets
		rig.fx = fx
	for h in hunters:
		h.target = vehicle
		h.nav = nav
	zombies.nav = nav
	bullets.fx = fx
	mines.fx = fx
	zombies.target = vehicle
	zombies.spawn_points = arena.spawn_points
	camera.target = vehicle
	reticle.rig = vehicle
	markers.mission = self

	# Tree order is also physics order:
	# inputs (here) -> zombies -> player rig -> enemy rigs -> hunters -> bullets.
	# Hunters run after the rig so they see this tick's wall contact.
	for node: Node in [arena, splats, markers, mines, pickups, zombies, vehicle, rigs]:
		add_child(node)
	for h in hunters:
		add_child(h)
	for node: Node in [bullets, fx, reticle, camera, hud]:
		add_child(node)

	camera.set_bounds(Rect2(Vector2.ZERO, T.WORLD_SIZE))
	camera.global_position = vehicle.global_position
	camera.make_current()

	zombies.zombie_killed.connect(_on_zombie_killed)
	vehicle.wrecked.connect(_on_wrecked)
	vehicle.crew_injured.connect(_on_crew_injured)
	vehicle.crew_healed.connect(_on_crew_healed)
	vehicle.crew_ability_used.connect(_on_crew_ability)
	vehicle.damaged.connect(_on_damaged)
	for h in hunters:
		h.died.connect(_on_hunter_died.bind(h))
		h.latched_on.connect(func() -> void: hud.set_alert("HUNTER ON THE HULL  -  SCRAPE IT ON A WALL"))
		h.let_go.connect(_on_hunter_let_go)
	for rig in outriders:
		rig.wrecked.connect(_on_outrider_wrecked.bind(rig))
	for rig in bulwarks:
		rig.wrecked.connect(_on_bulwark_wrecked.bind(rig))
	if elite != null:
		elite.wrecked.connect(_on_elite_wrecked)
	hud.restart_requested.connect(return_to_garage)
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
	var outrider_count := 0
	var bulwark_count := 0
	match mission_type:
		"clear":
			var shamblers: int = Missions.stat(spec, "shamblers")
			var hunter_count: int = Missions.stat(spec, "hunters")
			outrider_count = Missions.stat(spec, "outriders")
			bulwark_count = Missions.stat(spec, "bulwarks")
			zombies.spawn_budget = shamblers
			zombies.start_count = mini(T.ZOMBIE_START, cap)
			target_kills = shamblers + hunter_count + outrider_count + bulwark_count
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
			for e: Array in Missions.stat(spec, "events"):
				_events.append([float(e[0]), str(e[1]), -1, false])
				if e[1] == "outrider":
					outrider_count += 1
				elif e[1] == "bulwark":
					bulwark_count += 1
		"hunt":
			zombies.spawn_budget = 1000000
			zombies.start_count = mini(8, cap)
			elite = EnemyRig.new()
			elite.make_elite(str(spec.name).to_upper(), Missions.stat(spec, "elite_armor"), Missions.stat(spec, "elite_damage"))
			_events.append([3.0, "elite", -1, false])
			outrider_count = Missions.stat(spec, "escorts")
			for i in outrider_count:
				_events.append([3.0, "escort", -1, false])
			bulwark_count = Missions.stat(spec, "bulwark_escorts")
			for i in bulwark_count:
				_events.append([3.0, "bulwark_escort", -1, false])
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


func _physics_process(delta: float) -> void:
	if state != State.RUNNING:
		vehicle.drive_input = Vector2.ZERO
		vehicle.aim_input = Vector2.ZERO
		return
	elapsed += delta
	vehicle.drive_input = hud.left_stick.output
	vehicle.aim_input = hud.right_stick.output
	if auto_spawn_specials:
		_run_events()
	_collect_pickups()
	match mission_type:
		"survive":
			if elapsed >= float(Missions.stat(spec, "seconds")):
				_succeed("HELD THE BLOCK", "", 1.0)
		"courier":
			if checkpoint_index < checkpoints.size() and vehicle.global_position.distance_to(checkpoints[checkpoint_index]) < T.COURIER_RADIUS:
				reach_checkpoint()


func _process(_delta: float) -> void:
	_refresh_hud()
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
	get_tree().change_scene_to_file(GARAGE_SCENE)


func _exit_tree() -> void:
	Engine.time_scale = 1.0
	# Rigs are built up front; free any that never made it into the fight.
	for rig in _all_enemy_rigs():
		if not rig.is_inside_tree():
			rig.free()


func _all_enemy_rigs() -> Array[EnemyRig]:
	var all: Array[EnemyRig] = outriders.duplicate()
	all.append_array(bulwarks)
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


## Activates a pooled Hunter. Returns it, or null if both are already out.
func spawn_hunter(at: Vector2) -> Hunter:
	for h in hunters:
		if not h.active:
			h.activate(at)
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
	return out


# --- Courier -------------------------------------------------------------------

## Picks a route of `count` checkpoints from the arena's list, each a fair
## drive from the last, and sets par times from the nav-grid path length.
func _plan_route(count: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(spec.seed)
	var pool: Array = Arena.CHECKPOINTS.duplicate()
	var at := Arena.PLAYER_START
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


# --- HUD -------------------------------------------------------------------------

func _refresh_hud() -> void:
	hud.set_armor(vehicle.armor / vehicle.armor_max)
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
		if mission_type == "clear" and zombies.remaining() <= T.STRAGGLER_ARROWS:
			for p in zombies.active_positions():
				points.append(to_screen * p)
				colors.append(T.COL_ORANGE)
	hud.set_threats(points, colors)


func _status_line() -> String:
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


func _on_zombie_killed(at: Vector2) -> void:
	splats.add(at)
	fx.gore(at, (at - vehicle.global_position).normalized())
	_add_kill(T.SCRAP_PER_KILL)


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


func _drop(at: Vector2, pool: String, guaranteed: bool, cache: int) -> void:
	var pickup := Pickup.new()
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
	_drop(rig.global_position, "outrider", false, T.SCRAP_CACHE)
	hud.banner("RIG DOWN  -  GRAB THE SALVAGE", T.COL_CYAN)
	_add_kill(T.OUTRIDER_SCRAP, true)
	_salvage_plating()


func _on_bulwark_wrecked(rig: EnemyRig) -> void:
	camera.shake(0.8)
	_drop(rig.global_position, "bulwark", false, T.BULWARK_SCRAP_CACHE)
	hud.banner("BULWARK DOWN  -  GRAB THE SALVAGE", T.COL_CYAN)
	_add_kill(T.BULWARK_SCRAP, true)
	_salvage_plating()


func _on_elite_wrecked() -> void:
	camera.shake(0.9)
	_drop(elite.global_position, "elite", true, T.ELITE_SCRAP_CACHE)
	hud.banner("%s DOWN  -  GRAB THE SCHEMATIC" % elite.elite_name, T.COL_ELITE, 3.0)
	_add_kill(T.ELITE_SCRAP, true)
	_salvage_plating()


## Mechanic perk: each enemy rig wreck restores some armor.
func _salvage_plating() -> void:
	if bool(vehicle.crew_mod("salvage_plating")) and not vehicle.is_wrecked:
		vehicle.armor = minf(vehicle.armor + 15.0 * float(vehicle.crew_mod("repair")), vehicle.armor_max)


func _collect_pickups() -> void:
	for p in pickups.get_children():
		var pickup := p as Pickup
		if vehicle.global_position.distance_to(pickup.global_position) < Pickup.COLLECT_RADIUS:
			_take_salvage(pickup)


func _take_salvage(pickup: Pickup) -> void:
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
	if unknown.is_empty() or randf() >= Missions.schematic_chance(spec):
		return ""
	return unknown.pick_random()


func _on_wrecked() -> void:
	if state != State.RUNNING:
		return
	hud.close_crew_wheel(false)
	Engine.time_scale = 1.0
	state = State.WRECKED
	camera.shake(1.0)
	var lost: Array[String] = []
	for m in profile.seated_crew():
		lost.append(str(m.name))
	var penalty := profile.record_wreck()
	profile.finish_day()
	var lines := "Rig destroyed with every part on it."
	lines += (" Crew lost: %s." % ", ".join(lost)) if not lost.is_empty() else " No crew aboard."
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
	## The Courier route on the ground: the next checkpoint pulses, the one
	## after it is a faint ring, so you can line up the turn.
	const T := preload("res://scripts/tuning.gd")
	var mission: Node2D
	var _t := 0.0

	func _process(delta: float) -> void:
		_t += delta
		if mission != null and str(mission.get("mission_type")) == "courier":
			queue_redraw()

	func _draw() -> void:
		if mission == null or str(mission.get("mission_type")) != "courier":
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
