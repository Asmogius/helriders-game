extends Node2D
## "Clear" mission in the Outer Blocks: drive, shoot, ram. Clear 40 shamblers,
## the Hunter that shows up partway in, and the Outrider rig that comes looking
## for you; grab what it drops. Clearing banks the run's scrap and schematics
## into the profile. A wreck destroys the rig and loses the run's loot.
## Builds the whole scene in code (see AGENTS.md).

const T := preload("res://scripts/tuning.gd")
const Parts := preload("res://scripts/parts.gd")
const Loadout := preload("res://scripts/loadout.gd")
const Arena := preload("res://scripts/arena.gd")
const Splats := preload("res://scripts/splats.gd")
const ZombieDirector := preload("res://scripts/zombie_director.gd")
const Vehicle := preload("res://scripts/vehicle.gd")
const EnemyRig := preload("res://scripts/enemy_rig.gd")
const Hunter := preload("res://scripts/hunter.gd")
const BulletPool := preload("res://scripts/bullet_pool.gd")
const Fx := preload("res://scripts/fx.gd")
const Pickup := preload("res://scripts/pickup.gd")
const LockReticle := preload("res://scripts/lock_reticle.gd")
const ChaseCamera := preload("res://scripts/chase_camera.gd")
const Hud := preload("res://scripts/hud.gd")
const NavGrid := preload("res://scripts/nav_grid.gd")
const ProfileScript := preload("res://scripts/profile.gd")
const GARAGE_SCENE := "res://scenes/garage.tscn"

enum State { RUNNING, WRECKED, CLEARED }

## Off for tests that want to place the Hunter and Outrider themselves.
var auto_spawn_specials := true
## Tests: make every Outrider drop a schematic instead of rolling for it.
var always_drop_schematic := false

var arena: Arena
var splats: Splats
var zombies: ZombieDirector
var vehicle: Vehicle
var rigs: Node2D                 # enemy rigs live here
var hunter: Hunter
var outrider: EnemyRig           # created up front, added when it spawns
var bullets: BulletPool
var fx: Fx
var pickups: Node2D
var reticle: LockReticle
var camera: ChaseCamera
var hud: Hud

var state := State.RUNNING
var profile: ProfileScript          # the /root/Profile autoload
var kills := 0
var scrap := 0.0                 # this run's scrap; only banked if you clear
var elapsed := 0.0
var salvage: Array[Dictionary] = []
var bank_report := {}

var _hunter_spawned := false
var _outrider_spawned := false


func _ready() -> void:
	profile = get_node("/root/Profile")
	arena = Arena.new()
	splats = Splats.new()
	splats.z_index = -5
	zombies = ZombieDirector.new()
	vehicle = Vehicle.new()
	rigs = Node2D.new()
	hunter = Hunter.new()
	outrider = EnemyRig.new()
	bullets = BulletPool.new()
	bullets.z_index = 4
	fx = Fx.new()
	fx.z_index = 5
	pickups = Node2D.new()
	reticle = LockReticle.new()
	camera = ChaseCamera.new()
	hud = Hud.new()

	# The rig from the garage. Tests (or a missing rig) fall back to the starter.
	var loadout: Dictionary = profile.rig if profile.has_rig() else Parts.STARTER_LOADOUT
	vehicle.apply_stats(Loadout.build(loadout))
	profile.start_run()

	# Wire references before adding to the tree so every _ready() sees them.
	vehicle.position = Arena.PLAYER_START
	vehicle.rotation = -PI / 2.0
	vehicle.bullets = bullets
	vehicle.fx = fx
	vehicle.lock_candidates = lock_candidates
	outrider.player = vehicle
	outrider.bullets = bullets
	outrider.fx = fx
	hunter.target = vehicle
	var nav := NavGrid.new()
	hunter.nav = nav
	zombies.nav = nav
	bullets.fx = fx
	zombies.target = vehicle
	zombies.spawn_points = arena.spawn_points
	camera.target = vehicle
	reticle.rig = vehicle

	# Tree order is also physics order:
	# inputs (here) -> zombies -> player rig -> enemy rigs -> hunter -> bullets.
	# The Hunter runs after the rig so it sees this tick's wall contact.
	for node: Node in [arena, splats, pickups, zombies, vehicle, rigs, hunter, bullets, fx, reticle, camera, hud]:
		add_child(node)

	camera.set_bounds(Rect2(Vector2.ZERO, T.WORLD_SIZE))
	camera.global_position = vehicle.global_position
	camera.make_current()

	zombies.zombie_killed.connect(_on_zombie_killed)
	vehicle.wrecked.connect(_on_wrecked)
	vehicle.damaged.connect(_on_damaged)
	hunter.died.connect(_on_hunter_died)
	hunter.latched_on.connect(func() -> void: hud.set_alert("HUNTER ON THE HULL  -  SCRAPE IT ON A WALL"))
	hunter.let_go.connect(func() -> void: hud.set_alert(""))
	outrider.wrecked.connect(_on_outrider_wrecked)
	hud.restart_requested.connect(return_to_garage)
	hud.lock_toggled.connect(func(on: bool) -> void: vehicle.lock_enabled = on)
	hud.set_lock_available(vehicle.can_lock())
	_refresh_hud()


func _physics_process(delta: float) -> void:
	if state != State.RUNNING:
		vehicle.drive_input = Vector2.ZERO
		vehicle.aim_input = Vector2.ZERO
		return
	elapsed += delta
	vehicle.drive_input = hud.left_stick.output
	vehicle.aim_input = hud.right_stick.output
	if auto_spawn_specials:
		if not _hunter_spawned and (elapsed >= T.HUNTER_SPAWN_TIME or kills >= T.HUNTER_SPAWN_KILLS):
			spawn_hunter(zombies.pick_spawn_point())
		if not _outrider_spawned and (elapsed >= T.OUTRIDER_SPAWN_TIME or kills >= T.OUTRIDER_SPAWN_KILLS):
			spawn_outrider(zombies.pick_spawn_point())
	_collect_pickups()


func _process(_delta: float) -> void:
	_refresh_hud()


func return_to_garage() -> void:
	get_tree().change_scene_to_file(GARAGE_SCENE)


func _exit_tree() -> void:
	# The Outrider is built up front; free it if it never made it into the fight.
	if outrider != null and not outrider.is_inside_tree():
		outrider.free()


func spawn_hunter(at: Vector2) -> void:
	_hunter_spawned = true
	hunter.activate(at)
	hud.banner("HUNTER IN THE BLOCK", T.COL_HUNTER)


func spawn_outrider(at: Vector2) -> void:
	_outrider_spawned = true
	outrider.position = at
	outrider.rotation = (vehicle.global_position - at).angle()
	rigs.add_child(outrider)
	hud.banner("ENEMY RIG INBOUND", T.COL_ENEMY)


## Everything the player's lock-on may consider.
func lock_candidates() -> Array[Node2D]:
	var out: Array[Node2D] = []
	for z in zombies.active_zombies():
		out.append(z)
	if hunter.active:
		out.append(hunter)
	for rig in rigs.get_children():
		if not rig.get("is_wrecked"):
			out.append(rig as Node2D)
	return out


func _refresh_hud() -> void:
	hud.set_armor(vehicle.armor / vehicle.armor_max)
	hud.set_power(vehicle.power_load(), vehicle.power_output)
	hud.set_status(kills, T.CLEAR_TARGET, int(scrap))
	hud.set_lock_state(vehicle.lock_enabled, vehicle.lock_target != null)
	# Edge arrows: the Hunter and enemy rigs always, the last few shamblers too.
	var points := PackedVector2Array()
	var colors := PackedColorArray()
	if state == State.RUNNING:
		var to_screen := get_viewport().get_canvas_transform()
		if hunter.active and not hunter.is_latched():
			points.append(to_screen * hunter.global_position)
			colors.append(T.COL_HUNTER)
		for rig in rigs.get_children():
			if not rig.get("is_wrecked"):
				points.append(to_screen * (rig as Node2D).global_position)
				colors.append(T.COL_ENEMY)
		for p in pickups.get_children():
			points.append(to_screen * (p as Node2D).global_position)
			colors.append(T.COL_CYAN)
		if zombies.remaining() <= T.STRAGGLER_ARROWS:
			for p in zombies.active_positions():
				points.append(to_screen * p)
				colors.append(T.COL_ORANGE)
	hud.set_threats(points, colors)


func _add_kill(points: int) -> void:
	kills += 1
	scrap += points * profile.salvage_mult()
	if state == State.RUNNING and kills >= T.CLEAR_TARGET:
		_on_cleared()


func _on_zombie_killed(at: Vector2) -> void:
	splats.add(at)
	fx.gore(at, (at - vehicle.global_position).normalized())
	_add_kill(T.SCRAP_PER_KILL)


func _on_hunter_died(at: Vector2) -> void:
	splats.add(at)
	fx.gore(at, Vector2.ZERO)
	hud.set_alert("")
	var how := {"crushed": "HUNTER CRUSHED", "scraped": "HUNTER SCRAPED OFF", "rammed": "HUNTER RUN DOWN"}
	hud.banner(how.get(hunter.last_hit_cause, "HUNTER DOWN"), T.COL_HUNTER, 1.8)
	_add_kill(T.HUNTER_SCRAP)


func _on_outrider_wrecked() -> void:
	camera.shake(0.6)
	var pickup := Pickup.new()
	# Loot quality raises the odds of a schematic over a plain scrap cache.
	# Only schematics you don't own yet drop; once you have them all, scrap.
	var pending: Array[String] = []
	for part in salvage:
		pending.append(str(part.id))
	var unknown := profile.unknown_schematics(Parts.OUTRIDER_DROPS, pending)
	if not unknown.is_empty() and (always_drop_schematic or randf() < profile.schematic_chance()):
		pickup.part = Parts.get_part(unknown.pick_random())
	else:
		pickup.scrap_value = T.SCRAP_CACHE
	# Drop it beside the burning wreck, toward the player.
	var away := (vehicle.global_position - outrider.global_position).normalized()
	pickup.position = outrider.global_position + away * 70.0
	pickups.add_child(pickup)
	hud.banner("RIG DOWN  -  GRAB THE SALVAGE", T.COL_CYAN)
	_add_kill(T.OUTRIDER_SCRAP)


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


func _on_damaged(amount: float) -> void:
	if amount >= 2.0:
		camera.shake(amount / 30.0)


func _on_cleared() -> void:
	state = State.CLEARED
	# The block is yours: anything still on the ground gets hauled home.
	for p in pickups.get_children():
		_take_salvage(p as Pickup)
	var ids: Array[String] = []
	for part in salvage:
		ids.append(str(part.id))
	bank_report = profile.bank_run(int(scrap), ids)
	var time := "%d:%02d" % [int(elapsed / 60.0), int(elapsed) % 60]
	var lines := "Scrap banked +%d    Time %s" % [int(scrap), time]
	for id: String in bank_report.unlocked:
		lines += "\nNew schematic: " + Parts.describe(Parts.get_part(id))
	hud.show_result("BLOCK CLEARED", lines, "RETURN TO GARAGE", T.COL_CYAN)


func _on_wrecked() -> void:
	if state != State.RUNNING:
		return
	state = State.WRECKED
	camera.shake(1.0)
	var penalty := profile.record_wreck()
	var lines := "Rig destroyed with every part on it. Crew lost."
	if penalty > 0:
		lines += "\nWreck penalty: -%d scrap." % penalty
	if scrap >= 1.0 or not salvage.is_empty():
		lines += "\nSalvage lost with the rig: %d scrap" % int(scrap)
		if not salvage.is_empty():
			lines += ", %d schematic%s" % [salvage.size(), "" if salvage.size() == 1 else "s"]
		lines += "."
	# Let the wreck burn for a beat before the results card.
	await get_tree().create_timer(1.6).timeout
	hud.show_result("WRECKED", lines, "BACK TO THE YARD", T.COL_ORANGE)
