extends Node2D
## Prototype "Clear" mission in the Outer Blocks: drive, shoot, ram, clear the
## block or get wrecked. Builds the whole scene in code (see AGENTS.md).

const T := preload("res://scripts/tuning.gd")
const Arena := preload("res://scripts/arena.gd")
const Splats := preload("res://scripts/splats.gd")
const ZombieDirector := preload("res://scripts/zombie_director.gd")
const Vehicle := preload("res://scripts/vehicle.gd")
const BulletPool := preload("res://scripts/bullet_pool.gd")
const Fx := preload("res://scripts/fx.gd")
const ChaseCamera := preload("res://scripts/chase_camera.gd")
const Hud := preload("res://scripts/hud.gd")

enum State { RUNNING, WRECKED, CLEARED }

var arena: Arena
var splats: Splats
var zombies: ZombieDirector
var vehicle: Vehicle
var bullets: BulletPool
var fx: Fx
var camera: ChaseCamera
var hud: Hud

var state := State.RUNNING
var kills := 0
var scrap := 0
var elapsed := 0.0


func _ready() -> void:
	arena = Arena.new()
	splats = Splats.new()
	splats.z_index = -5
	zombies = ZombieDirector.new()
	vehicle = Vehicle.new()
	bullets = BulletPool.new()
	fx = Fx.new()
	fx.z_index = 5
	camera = ChaseCamera.new()
	hud = Hud.new()

	# Wire references before adding to the tree so every _ready() sees them.
	vehicle.position = Arena.PLAYER_START
	vehicle.rotation = -PI / 2.0
	vehicle.bullets = bullets
	vehicle.fx = fx
	bullets.fx = fx
	zombies.target = vehicle
	zombies.spawn_points = arena.spawn_points
	camera.target = vehicle

	# Tree order is also physics order: inputs (here) -> zombies -> rig -> bullets.
	for node: Node in [arena, splats, zombies, vehicle, bullets, fx, camera, hud]:
		add_child(node)

	bullets.exclude = [vehicle.get_rid()]
	camera.set_bounds(Rect2(Vector2.ZERO, T.WORLD_SIZE))
	camera.global_position = vehicle.global_position
	camera.make_current()

	zombies.zombie_killed.connect(_on_zombie_killed)
	vehicle.wrecked.connect(_on_wrecked)
	vehicle.damaged.connect(_on_damaged)
	hud.restart_requested.connect(restart)
	_refresh_hud()


func _physics_process(delta: float) -> void:
	if state == State.RUNNING:
		elapsed += delta
		vehicle.drive_input = hud.left_stick.output
		vehicle.aim_input = hud.right_stick.output
	else:
		vehicle.drive_input = Vector2.ZERO
		vehicle.aim_input = Vector2.ZERO


func _process(_delta: float) -> void:
	_refresh_hud()


func restart() -> void:
	get_tree().reload_current_scene()


func _refresh_hud() -> void:
	hud.set_armor(vehicle.armor / vehicle.armor_max)
	hud.set_status(kills, T.CLEAR_TARGET, scrap)
	# Point at the last few stragglers so a Clear never stalls.
	var threats := PackedVector2Array()
	if state == State.RUNNING and T.CLEAR_TARGET - kills <= 6:
		var to_screen := get_viewport().get_canvas_transform()
		for p in zombies.active_positions():
			threats.append(to_screen * p)
	hud.set_threats(threats)


func _on_zombie_killed(at: Vector2) -> void:
	kills += 1
	scrap += T.SCRAP_PER_KILL
	splats.add(at)
	fx.gore(at, (at - vehicle.global_position).normalized())
	if state == State.RUNNING and kills >= T.CLEAR_TARGET:
		state = State.CLEARED
		var time := "%d:%02d" % [int(elapsed / 60.0), int(elapsed) % 60]
		hud.show_result("BLOCK CLEARED", "Scrap +%d    Time %s" % [scrap, time], "RUN IT AGAIN", T.COL_CYAN)


func _on_damaged(amount: float) -> void:
	if amount >= 2.0:
		camera.shake(amount / 20.0)


func _on_wrecked() -> void:
	if state != State.RUNNING:
		return
	state = State.WRECKED
	camera.shake(1.0)
	# Let the wreck burn for a beat before the results card.
	await get_tree().create_timer(1.6).timeout
	hud.show_result("WRECKED", "Rig destroyed. Crew lost.", "RUN IT BACK", T.COL_ORANGE)
