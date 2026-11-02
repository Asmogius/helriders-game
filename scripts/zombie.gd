extends CharacterBody2D
## Shambler. Pooled: the ZombieDirector activates, steers, and recycles these.
## Zombies don't collide with each other (the director keeps them apart with a
## cheap separation pass), but they do block the rig, which is what clogs
## movement in a crowd.

signal died(at: Vector2)

const T := preload("res://scripts/tuning.gd")
const CONTACT_DISTANCE := 40.0

var active := false
var hp := 0.0
var speed := T.SHAMBLER_SPEED

var _shape: CollisionShape2D
var _knock := Vector2.ZERO
var _flash := 0.0
var _stuck_time := 0.0
var _detour := Vector2.ZERO
var _detour_time := 0.0
var _detour_sign := 1.0  # each zombie always circles buildings the same way


func _ready() -> void:
	motion_mode = CharacterBody2D.MOTION_MODE_FLOATING
	var circle := CircleShape2D.new()
	circle.radius = T.SHAMBLER_RADIUS
	_shape = CollisionShape2D.new()
	_shape.shape = circle
	add_child(_shape)
	deactivate()


func activate(at: Vector2) -> void:
	position = at
	rotation = randf() * TAU
	hp = T.SHAMBLER_HP
	speed = T.SHAMBLER_SPEED * randf_range(0.8, 1.2)
	velocity = Vector2.ZERO
	_knock = Vector2.ZERO
	_flash = 0.0
	_stuck_time = 0.0
	_detour_time = 0.0
	_detour_sign = 1.0 if randf() < 0.5 else -1.0
	active = true
	visible = true
	collision_layer = T.LAYER_ZOMBIE
	collision_mask = T.LAYER_WORLD | T.LAYER_VEHICLE
	_shape.set_deferred("disabled", false)
	queue_redraw()


func deactivate() -> void:
	active = false
	visible = false
	collision_layer = 0
	collision_mask = 0
	_shape.set_deferred("disabled", true)
	position = Vector2(-10000.0, -10000.0)


## Called by the director once per physics tick with the steering it wants.
## `target` is the player rig (duck-typed: needs take_damage(amount)).
func step(delta: float, desired: Vector2, target: Node2D) -> void:
	_knock = _knock.move_toward(Vector2.ZERO, 900.0 * delta)
	# Walking around a building: hold a wall-following direction for a while.
	if _detour_time > 0.0:
		_detour_time -= delta
		desired = _detour * speed
	velocity = desired + _knock
	if desired.length_squared() > 1.0:
		rotation = lerp_angle(rotation, desired.angle(), 1.0 - exp(-6.0 * delta))
	move_and_slide()

	var touching := false
	var wall_normal := Vector2.ZERO
	for i in get_slide_collision_count():
		var collision := get_slide_collision(i)
		if collision.get_collider() == target:
			touching = true
		else:
			wall_normal = collision.get_normal()

	# Pressed flat against a wall with the target behind it: pick a side and
	# follow the wall. Cheap stand-in for pathfinding in an open city block.
	if wall_normal != Vector2.ZERO and get_real_velocity().length() < speed * 0.35:
		_stuck_time += delta
		if _stuck_time > 0.4 and _detour_time <= 0.0:
			_detour = wall_normal.orthogonal() * _detour_sign
			_detour_time = randf_range(1.5, 2.5)
			_stuck_time = 0.0
	else:
		_stuck_time = 0.0

	if target != null:
		if touching or position.distance_to(target.position) < CONTACT_DISTANCE:
			target.call("take_damage", T.SHAMBLER_DPS * delta)

	if _flash > 0.0:
		_flash = maxf(_flash - delta * 6.0, 0.0)
		queue_redraw()


func take_hit(damage: float, impulse: Vector2) -> void:
	if not active:
		return
	hp -= damage
	_knock += impulse
	_flash = 1.0
	queue_redraw()
	if hp <= 0.0:
		var at := global_position
		deactivate()
		died.emit(at)


func _draw() -> void:
	var skin := T.COL_ZOMBIE.lerp(Color(1.0, 0.95, 0.9), _flash * 0.7)
	draw_rect(Rect2(-9.0, -11.0, 14.0, 22.0), T.COL_ZOMBIE_DARK)  # shoulders
	draw_rect(Rect2(3.0, -11.0, 12.0, 5.0), skin)                 # arms reaching
	draw_rect(Rect2(3.0, 6.0, 12.0, 5.0), skin)
	draw_rect(Rect2(-3.0, -6.0, 11.0, 12.0), skin)                # head
	draw_rect(Rect2(4.0, -3.0, 3.0, 2.0), Color(0.12, 0.08, 0.06))
	draw_rect(Rect2(4.0, 1.0, 3.0, 2.0), Color(0.12, 0.08, 0.06))
