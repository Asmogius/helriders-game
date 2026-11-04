extends "res://scripts/enemy_rig.gd"
## Torcher (content proposal 01, approved 2026-11-03): a fire skirmisher. It
## closes to 150-220 px, hoses you with a fixed flame nozzle (fire: builds
## BURNING) until it overheats, then peels off and comes back. Its fuel tank
## is on the back: a rear hit of T.TORCHER_RUPTURE_HIT inside 1 s, or its
## wreck, ruptures it into a Fire-barrel blast that catches everything
## (zombies, you, and other enemy rigs) and lights any oil. It drives through
## oil happily and lights it with its flame.

var ruptured := false              # tests
var _rear := PackedFloat32Array([0, 0, 0, 0, 0, 0, 0, 0, 0, 0])
var _rear_i := 0
var _rear_t := 0.0
var _rupture_query := PhysicsShapeQueryParameters2D.new()


func _init() -> void:
	team = BulletPool.TEAM_ENEMY
	apply_stats(T.TORCHER)
	body_len = 66.0
	body_wid = 34.0
	lock_priority = 3
	var circle := CircleShape2D.new()
	circle.radius = T.BARREL_RADIUS
	_rupture_query.shape = circle
	_rupture_query.collision_mask = T.LAYER_ZOMBIE | T.LAYER_ENEMY | T.LAYER_VEHICLE


func _physics_process(delta: float) -> void:
	_rear_t += delta
	while _rear_t >= 0.1:
		_rear_t -= 0.1
		_rear_i = (_rear_i + 1) % _rear.size()
		_rear[_rear_i] = 0.0
	super(delta)


func _think(delta: float) -> void:
	super(delta)
	if mode == Mode.UNSTICK:
		return
	var to_player := player.global_position - global_position
	var dist := to_player.length()
	var forward := Vector2.RIGHT.rotated(rotation)
	if is_overheated(0):
		# Lockout: peel off and get some room.
		drive_input = _avoid_walls((-to_player.normalized()).rotated(_side * 0.6), forward)
		fire_trigger = false
		return
	if dist < T.TORCHER_KEEP:
		# Close enough: hold here and keep the nozzle on you.
		drive_input = to_player.normalized() * 0.25
	fire_trigger = (
		_sees_player and not bool(player.get("is_wrecked"))
		and dist < T.TORCHER_RANGE
		and absf(forward.angle_to(to_player)) < 0.35
	)
	# The flame lights oil it plays over.
	if fire_trigger and hazards != null:
		hazards.call("ignite_oil", global_position + forward * T.TORCHER_RANGE * 0.6, 40.0)


## Rear hits add up toward rupturing the tank.
func take_damage(amount: float, from := Vector2.ZERO, splash := false, dtype := "") -> void:
	var before := hp + _armor_total() + shield
	super(amount, from, splash, dtype)
	if ruptured or from == Vector2.ZERO:
		return
	if facing_of(from) == REAR:
		_rear[_rear_i] += maxf(before - (hp + _armor_total() + shield), 0.0)
		var total := 0.0
		for v in _rear:
			total += v
		if total >= T.TORCHER_RUPTURE_HIT:
			rupture()


func _wreck() -> void:
	super()
	rupture()


## The fuel tank goes: a Fire-barrel blast around the rig.
func rupture() -> void:
	if ruptured or not is_inside_tree():
		return
	ruptured = true
	var at := global_position
	if fx != null:
		fx.call("blast", at, T.BARREL_RADIUS * 0.7)
	if hazards != null:
		hazards.call("add_fire", at, T.BARREL_RADIUS * 0.7, T.BARREL_FIRE_GROUND_TIME)
	_rupture_query.transform = Transform2D(0.0, at)
	_rupture_query.exclude = [get_rid()]
	for hit: Dictionary in get_world_2d().direct_space_state.intersect_shape(_rupture_query, 48):
		var body := hit.collider as Node2D
		if body == null or not body.has_method("take_hit"):
			continue
		body.call("take_hit", T.BARREL_FIRE_DAMAGE, (body.global_position - at).normalized() * 300.0, "blast", "fire")
