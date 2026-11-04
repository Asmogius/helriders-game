extends "res://scripts/hostile.gd"
## A pooled zombie: Shambler, Brute, Tank, Boomer or Slimer (`kind`, stats in
## T.ZOMBIE_KINDS). The ZombieDirector activates, steers and recycles them in
## one loop; this script only moves itself along the steering it's given and
## does its kind's trick:
##   Brute   armored (bullets do half, grey sparks), heavy, shoves the rig
##   Tank    a heavier Brute that roars, then charges in a straight line; a hit
##           shoves the rig hard, a miss leaves it stumbling
##   Boomer  bursts into a bile pool when it dies or reaches the rig (the
##           director handles the pool and marking the rig)
##   Slimer  drops a slime trail as it walks (the director lays it down)
## Zombies don't collide with each other (the director keeps them apart with a
## cheap separation pass), but they do block the rig, which is what clogs
## movement in a crowd.

const StatusBars := preload("res://scripts/status_bars.gd")
const CONTACT_DISTANCE := 40.0
const KINDS := ["shambler", "brute", "tank", "boomer", "slimer"]
enum Charge { WALK, WINDUP, CHARGE, STUMBLE }

var kind := "shambler"
var speed := T.SHAMBLER_SPEED
var radius := T.SHAMBLER_RADIUS
var frenzy := false          # set by the director: bile pool or a marked rig nearby
var slime_timer := 0.0       # Slimer: seconds to the next trail blob (director)
var burst := false           # Boomer reached the rig: the director pops it after the loop
var oiled := false           # set by the director: wading through oil
var status := StatusBars.new()  # §14 statuses; zombies are neutral (T.ZOMBIE_RESIST)
var pending_damage := 0.0    # burning / toxic / spike damage the director applies after its loop
var spiked := false          # set by the director: on a spike strip

# Path following, driven by the director.
var nav_timer := 0.0
var nav_point := Vector2.ZERO
var nav_direct := true

# Tank charge.
var charge := Charge.WALK
var charge_time := 0.0
var charge_cooldown := 0.0
var charge_dir := Vector2.ZERO
var charge_hits := 0         # tests and feedback

var _stats: Dictionary = T.ZOMBIE_KINDS.shambler
var damage_mult := 1.0     # the skull's enemy damage (the director sets it)
var _circle: CircleShape2D
var _shape: CollisionShape2D
var _knock := Vector2.ZERO
var _flash := 0.0
var _stuck_time := 0.0
var _detour := Vector2.ZERO
var _detour_time := 0.0
var _detour_sign := 1.0  # each zombie always circles buildings the same way


func _ready() -> void:
	motion_mode = CharacterBody2D.MOTION_MODE_FLOATING
	_circle = CircleShape2D.new()
	_circle.radius = T.SHAMBLER_RADIUS
	_shape = CollisionShape2D.new()
	_shape.shape = _circle
	add_child(_shape)
	deactivate()


func activate(at: Vector2, as_kind := "shambler") -> void:
	kind = as_kind if T.ZOMBIE_KINDS.has(as_kind) else "shambler"
	_stats = T.ZOMBIE_KINDS[kind]
	position = at
	rotation = randf() * TAU
	hp = float(_stats.hp)
	radius = float(_stats.radius)
	_circle.radius = radius
	speed = float(_stats.speed) * randf_range(0.8, 1.2)
	lock_priority = 2 if kind == "tank" else 1
	lock_radius = radius + 5.0
	velocity = Vector2.ZERO
	_knock = Vector2.ZERO
	_flash = 0.0
	_stuck_time = 0.0
	_detour_time = 0.0
	nav_timer = 0.0
	nav_direct = true
	frenzy = false
	oiled = false
	status.reset()
	pending_damage = 0.0
	spiked = false
	burst = false
	slime_timer = randf() * T.SLIME_DROP_EVERY
	charge = Charge.WALK
	charge_time = 0.0
	charge_cooldown = 3.0
	charge_hits = 0
	_detour_sign = 1.0 if randf() < 0.5 else -1.0
	clear_status()
	active = true
	visible = true
	collision_layer = T.LAYER_ZOMBIE
	collision_mask = T.LAYER_WORLD | T.LAYER_VEHICLE | T.LAYER_ENEMY
	_shape.set_deferred("disabled", false)
	queue_redraw()


func deactivate() -> void:
	active = false
	visible = false
	collision_layer = 0
	collision_mask = 0
	_shape.set_deferred("disabled", true)
	position = Vector2(-10000.0, -10000.0)


func is_armored() -> bool:
	return float(_stats.bullet) < 1.0


## Bullets do the kind's share; rams, mines and bursts do full damage. Fire
## does extra to zombies; a typed hit builds its status; CORRODED takes more.
func take_hit(damage: float, impulse: Vector2, cause := "shot", dtype := "") -> void:
	if not active:
		return
	if cause == "shot":
		damage *= float(_stats.bullet)
	var k := StatusBars.kind_of(dtype)
	if k >= 0:
		add_buildup(k, damage * T.STATUS_HIT_BUILDUP)
	if dtype == "fire":
		damage *= T.FIRE_VS_ZOMBIES
	if status.active(StatusBars.ACID):
		damage *= T.CORRODED_TAKEN
	super.take_hit(damage, impulse, cause, dtype)


func add_buildup(k: int, amount: float) -> void:
	if active and status.add(k, amount, T.ZOMBIE_RESIST, float(T.STATUS_TIME_ZOMBIE[k])):
		queue_redraw()


func fill_status(k: int) -> void:
	status.trigger(k, float(T.STATUS_TIME_ZOMBIE[k]))
	queue_redraw()


## Armored kinds throw grey sparks at bullets (bullet_pool.gd).
func deflects(_at: Vector2) -> bool:
	return is_armored()


## Called by the director once per physics tick with the steering it wants.
## `target` is the player rig (duck-typed: take_damage(amount, from), velocity).
func step(delta: float, desired: Vector2, target: Node2D) -> void:
	_knock = _knock.move_toward(Vector2.ZERO, 900.0 * delta)
	if tick_status(delta):
		queue_redraw()
	var had := status.any_active()
	status.tick(delta)
	if had != status.any_active():
		queue_redraw()
	if status.active(StatusBars.FIRE):
		pending_damage += T.BURNING_ZOMBIE_DPS * delta
	if status.active(StatusBars.TOXIC):
		pending_damage += T.TOXIC_DPS * delta
	if spiked:
		pending_damage += T.SPIKE_ZOMBIE_DPS * delta
	desired *= speed_mult()
	if status.active(StatusBars.SHOCK):
		desired = Vector2.ZERO   # STUNNED: frozen
	if status.active(StatusBars.SLIME):
		desired *= T.SLICK_ZOMBIE_SPEED
	if spiked:
		desired *= T.SPIKE_ZOMBIE_SPEED
	if frenzy or status.active(StatusBars.GOOP):
		desired *= T.BILE_FRENZY
	if oiled:
		desired *= T.OIL_ZOMBIE_SPEED
	# Walking around a building: hold a wall-following direction for a while.
	if _detour_time > 0.0:
		_detour_time -= delta
		desired = _detour * speed
	if kind == "tank":
		desired = _tank(delta, desired, target)
	velocity = desired + _knock
	if desired.length_squared() > 1.0:
		rotation = lerp_angle(rotation, desired.angle(), 1.0 - exp(-6.0 * delta))
	move_and_slide()
	if not active:
		return

	var touching := false
	var wall_normal := Vector2.ZERO
	for i in get_slide_collision_count():
		var collision := get_slide_collision(i)
		if collision.get_collider() == target:
			touching = true
		else:
			wall_normal = collision.get_normal()

	if kind == "tank" and charge == Charge.CHARGE:
		_charge_contact(target, touching, wall_normal)
	elif wall_normal != Vector2.ZERO and get_real_velocity().length() < speed * 0.35:
		# Pressed flat against a wall with the target behind it: pick a side and
		# follow the wall. Cheap stand-in for pathfinding in an open city block.
		_stuck_time += delta
		if _stuck_time > 0.4 and _detour_time <= 0.0:
			_detour = wall_normal.orthogonal() * _detour_sign
			_detour_time = randf_range(1.5, 2.5)
			_stuck_time = 0.0
	else:
		_stuck_time = 0.0

	if target != null and not status.active(StatusBars.SHOCK):
		var reach := CONTACT_DISTANCE + (radius - T.SHAMBLER_RADIUS)
		if touching or position.distance_to(target.position) < reach:
			if kind == "boomer":
				burst = true
				return
			target.call("take_damage", float(_stats.dps) * damage_mult * delta * _taken_by(target), position - target.position)
			if kind == "brute" or kind == "tank":
				var push := (target.position - position).normalized() * T.BRUTE_SHOVE * delta
				target.set("velocity", (target.get("velocity") as Vector2) + push)

	if _flash > 0.0:
		_flash = maxf(_flash - delta * 6.0, 0.0)
		queue_redraw()


## Tank: walk, roar, charge, stumble. Returns the velocity it wants.
func _tank(delta: float, desired: Vector2, target: Node2D) -> Vector2:
	charge_cooldown -= delta
	match charge:
		Charge.WALK:
			if target != null and charge_cooldown <= 0.0 and position.distance_to(target.position) < T.TANK_CHARGE_RANGE:
				charge = Charge.WINDUP
				charge_time = T.TANK_WINDUP
				queue_redraw()
			return desired
		Charge.WINDUP:
			charge_time -= delta
			if target != null and charge_time > T.TANK_AIM_LOCK:
				charge_dir = (target.position - position).normalized()
				rotation = charge_dir.angle()
			if charge_time <= 0.0:
				charge = Charge.CHARGE
				charge_time = T.TANK_CHARGE_TIME
			queue_redraw()
			return Vector2.ZERO
		Charge.CHARGE:
			charge_time -= delta
			if charge_time <= 0.0:
				_stumble()
			return charge_dir * T.TANK_CHARGE_SPEED
		Charge.STUMBLE:
			charge_time -= delta
			if charge_time <= 0.0:
				charge = Charge.WALK
				queue_redraw()
			return Vector2.ZERO
	return desired


func _charge_contact(target: Node2D, touching: bool, wall_normal: Vector2) -> void:
	var hit := target != null and (touching or position.distance_to(target.position) < radius + 40.0)
	if hit:
		charge_hits += 1
		target.call("take_damage", T.TANK_CHARGE_DAMAGE * _taken_by(target), position - target.position)
		if not (target.has_method("immovable") and bool(target.call("immovable"))):   # Immovable Line
			target.set("velocity", (target.get("velocity") as Vector2) + charge_dir * T.TANK_SHOVE)
		target.rotation += randf_range(0.2, 0.4) * (1.0 if randf() < 0.5 else -1.0)
		charge = Charge.WALK
		charge_cooldown = T.TANK_CHARGE_COOLDOWN
		queue_redraw()
	elif wall_normal != Vector2.ZERO:
		_stumble()


func _stumble() -> void:
	charge = Charge.STUMBLE
	charge_time = T.TANK_STUMBLE
	charge_cooldown = T.TANK_CHARGE_COOLDOWN
	queue_redraw()


func is_charging() -> bool:
	return kind == "tank" and (charge == Charge.WINDUP or charge == Charge.CHARGE)


func is_stumbling() -> bool:
	return kind == "tank" and charge == Charge.STUMBLE


func _on_hit(_damage: float, impulse: Vector2) -> void:
	_knock += impulse * float(_stats.knock)
	_flash = 1.0
	queue_redraw()


func _draw() -> void:
	match kind:
		"brute":
			_draw_body(1.45, T.COL_BRUTE, T.COL_ZOMBIE_DARK.darkened(0.2))
			draw_rect(Rect2(-12.0, -15.0, 6.0, 30.0), T.COL_STEEL)     # scrap plates on the back
		"tank":
			_draw_body(1.9, T.COL_TANK, T.COL_TANK.darkened(0.45))
			draw_rect(Rect2(-17.0, -20.0, 8.0, 40.0), T.COL_STEEL)
			if charge == Charge.WINDUP:
				var t := 1.0 - charge_time / T.TANK_WINDUP
				draw_arc(Vector2.ZERO, radius + 6.0 + 14.0 * t, -0.6, 0.6, 12, Color(0.95, 0.3, 0.2, 0.9), 4.0)
			elif charge == Charge.STUMBLE:
				draw_arc(Vector2(-4.0, 0.0), 10.0, 0.0, TAU, 10, Color(1.0, 0.9, 0.4, 0.8), 2.0)
		"boomer":
			var skin := T.COL_BOOMER.lerp(Color(1.0, 0.95, 0.9), _flash * 0.7)
			draw_circle(Vector2.ZERO, radius, T.COL_BOOMER.darkened(0.35))
			draw_circle(Vector2(-2.0, 0.0), radius - 3.0, skin)
			draw_rect(Rect2(6.0, -5.0, 8.0, 10.0), skin)
			draw_circle(Vector2(-3.0, -5.0), 3.0, T.COL_BILE.lightened(0.3))
			draw_circle(Vector2(-6.0, 5.0), 2.5, T.COL_BILE.lightened(0.3))
		"slimer":
			_draw_body(1.05, T.COL_SLIMER, T.COL_SLIMER.darkened(0.4))
			draw_circle(Vector2(-10.0, 0.0), 5.0, T.COL_SLIME.lightened(0.2))
		_:
			_draw_body(1.0, T.COL_ZOMBIE, T.COL_ZOMBIE_DARK)
	draw_status(radius + 4.0)
	# §14 statuses: a ring in the status's colour (the strongest-showing one).
	for k in [StatusBars.FIRE, StatusBars.SHOCK, StatusBars.ACID, StatusBars.TOXIC, StatusBars.GOOP, StatusBars.SLIME]:
		if status.active(k):
			draw_arc(Vector2.ZERO, radius + 7.0, 0.0, TAU, 16, Color(T.STATUS_COLORS[k], 0.85), 3.0)
			break


func _draw_body(s: float, color: Color, dark: Color) -> void:
	var skin := color.lerp(Color(1.0, 0.95, 0.9), _flash * 0.7)
	draw_rect(Rect2(Vector2(-9.0, -11.0) * s, Vector2(14.0, 22.0) * s), dark)   # shoulders
	draw_rect(Rect2(Vector2(3.0, -11.0) * s, Vector2(12.0, 5.0) * s), skin)     # arms reaching
	draw_rect(Rect2(Vector2(3.0, 6.0) * s, Vector2(12.0, 5.0) * s), skin)
	draw_rect(Rect2(Vector2(-3.0, -6.0) * s, Vector2(11.0, 12.0) * s), skin)    # head
	draw_rect(Rect2(Vector2(4.0, -3.0) * s, Vector2(3.0, 2.0) * s), Color(0.12, 0.08, 0.06))
	draw_rect(Rect2(Vector2(4.0, 1.0) * s, Vector2(3.0, 2.0) * s), Color(0.12, 0.08, 0.06))


## Bait Shell (Goop Launcher mod): a GOOPED rig takes extra from zombies.
func _taken_by(target: Node) -> float:
	var t = target.get("zombie_taken")
	return float(t) if t != null else 1.0
