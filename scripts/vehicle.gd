extends CharacterBody2D
## A rig: arcade drift handling, weapons, ramming, armor. The player's rig and
## enemy rigs share this script; enemy_rig.gd extends it with an AI brain.
##
## Driving: point the left stick where you want to go; pull it behind you while
## slow to reverse. Turret rigs aim with the right stick (push past halfway to
## fire) or, with lock on, aim and fire at the locked target by themselves.

signal wrecked
signal damaged(amount: float)

const T := preload("res://scripts/tuning.gd")
const Hostile := preload("res://scripts/hostile.gd")
const BulletPool := preload("res://scripts/bullet_pool.gd")
const Parts := preload("res://scripts/parts.gd")
const Loadout := preload("res://scripts/loadout.gd")

enum Mount { TURRET, FIXED }

const REVERSE_ANGLE := 2.27        # ~130 degrees: stick this far behind = reverse
const AIM_DEADZONE := 0.2
const FIRE_THRESHOLD := 0.5
const RAM_MIN_SPEED := 150.0       # impact speed needed to hurt anything
const WALL_DAMAGE_SPEED := 300.0   # impact speed before walls hurt you
const LOCK_FIRE_CONE := 0.15       # radians: turret must be this close to fire on lock

var body_len := 64.0
var body_wid := 36.0

# Final stats (filled from a stats dictionary, see apply_stats).
var max_speed := 0.0
var reverse_speed := 0.0
var acceleration := 0.0
var brake := 0.0
var coast := 0.0
var turn_rate := 0.0
var grip := 0.0
var armor_max := 0.0
var ram_damage := 0.0
var mount := Mount.TURRET
var fire_rate := 0.0
var bullet_damage := 0.0
var bullet_speed := 0.0
var spread := 0.0
var turret_turn_rate := 0.0
var lock_range := 0.0             # 0 = no lock (weapon can't, or no targeting system)
var power_output := 0.0            # engine budget (0 = no power model, e.g. enemy rigs)
var power_draw := 0.0              # constant draw of everything installed
var weight_load := 0.0             # weight of everything installed
var weight_capacity := 0.0         # chassis limit (0 = no weight model, e.g. enemy rigs)
var gun_stats: Array[Dictionary] = []   # every weapon (see loadout.gd)
var abilities: Array[Dictionary] = []   # utility parts, each with "ready_in" seconds
var look := {}                     # which parts are installed, for drawing

var team := BulletPool.TEAM_PLAYER
var armor := 0.0
var traction := 1.0                # Slimer trails will lower this later
var is_wrecked := false
var lock_priority := 3             # when someone else locks onto this rig
var lock_radius := 40.0

# Inputs, set every tick by the player (mission.gd) or the AI (enemy_rig.gd).
var drive_input := Vector2.ZERO
var aim_input := Vector2.ZERO
var fire_trigger := false          # fixed-mount weapons
var lock_enabled := false:
	set(value):
		# No targeting system (or a weapon that can't lock): lock stays off.
		lock_enabled = value and can_lock()
		if not lock_enabled:
			lock_target = null
var lock_target: Node2D = null
var lock_candidates := Callable()  # returns Array[Node2D] of things to lock onto

# Wall contact this tick, read by Hunters clinging to the hull.
var touching_wall := false
var wall_normal := Vector2.ZERO
var wall_impact := 0.0             # crash speed of a fresh impact this tick, else 0
var latched: Array[Node2D] = []    # Hunters on the hull

var bullets: Node2D                # BulletPool
var fx: Node2D                     # Fx
var mines: Node2D                  # MinePool, for the Mine Dropper

var _turret: Node2D                # the first turret, if any
var _turrets: Array[Node2D] = []   # one per weapon; null for fixed guns
var _cooldowns: Array[float] = []
var _fire_cooldown := 0.0
var _flash := 0.0
var _reversing := false
var _burn_timer := 0.0
var _burn_left := 0.0
var _barrel_side := 1.0
var _lock_check := 0.0
var _lock_blind := 0.0
var _ray := PhysicsRayQueryParameters2D.new()


func _init() -> void:
	apply_stats(Loadout.build(Parts.STARTER_LOADOUT))


func apply_stats(s: Dictionary) -> void:
	max_speed = s.max_speed
	reverse_speed = s.reverse_speed
	acceleration = s.acceleration
	brake = s.brake
	coast = s.coast
	turn_rate = s.turn_rate
	grip = s.grip
	armor_max = s.armor
	ram_damage = s.ram_damage
	mount = s.mount
	fire_rate = s.fire_rate
	bullet_damage = s.bullet_damage
	bullet_speed = s.bullet_speed
	spread = deg_to_rad(s.spread_deg)
	turret_turn_rate = s.turret_turn_rate
	lock_range = s.lock_range
	power_output = s.get("power_output", 0.0)
	power_draw = s.get("power_draw", 0.0)
	weight_load = s.get("weight", 0.0)
	weight_capacity = s.get("weight_capacity", 0.0)
	look = s.get("look", {})
	if s.has("body"):
		body_len = float(s.body[0])
		body_wid = float(s.body[1])
	# Weapons: a list from loadout.gd, or one gun from a flat enemy stat sheet.
	gun_stats.clear()
	if s.has("weapons"):
		for w: Dictionary in s.weapons:
			gun_stats.append(w)
	elif float(s.fire_rate) > 0.0:
		gun_stats.append({
			"id": "", "mount": int(s.mount), "fire_rate": float(s.fire_rate),
			"bullet_damage": float(s.bullet_damage), "bullet_speed": float(s.bullet_speed),
			"spread_deg": float(s.spread_deg), "turret_turn_rate": float(s.turret_turn_rate),
			"lock_range": float(s.lock_range), "pellets": int(s.get("pellets", 1)),
		})
	_cooldowns.clear()
	for w in gun_stats:
		_cooldowns.append(0.0)
	abilities.clear()
	for a: Dictionary in s.get("abilities", []):
		var copy := a.duplicate()
		copy["ready_in"] = 0.0
		abilities.append(copy)
	armor = armor_max
	if not can_lock():
		lock_enabled = false
	if is_inside_tree():
		_sync_parts()


## Where turret `index` of `count` sits on the hull: one gun mid-hull, two
## front and back.
func turret_position(index: int, count: int) -> Vector2:
	if count <= 1:
		return Vector2(-4.0, 0.0)
	return Vector2(body_len * (0.2 if index == 0 else -0.3), 0.0)


func has_weapon() -> bool:
	return not gun_stats.is_empty()


## Turret sprites to match the weapons (fixed guns are drawn on the nose).
func _sync_parts() -> void:
	for t in _turrets:
		if t != null:
			t.queue_free()
	_turrets.clear()
	_turret = null
	var count := gun_stats.size()
	for i in count:
		var w := gun_stats[i]
		if int(w.mount) != Mount.TURRET:
			_turrets.append(null)
			continue
		var sprite := TurretSprite.new()
		sprite.kind = str(w.get("id", ""))
		sprite.position = turret_position(i, count)
		add_child(sprite)
		_turrets.append(sprite)
		if _turret == null:
			_turret = sprite
	queue_redraw()


func can_lock() -> bool:
	return lock_range > 0.0


## Power drawn by the build. Fixed by what's installed, not by what's switched on.
func power_load() -> float:
	return power_draw


func is_overloaded() -> bool:
	return is_power_overloaded() or is_weight_overloaded()


func is_power_overloaded() -> bool:
	return power_output > 0.0 and power_load() > power_output


func is_weight_overloaded() -> bool:
	return weight_capacity > 0.0 and weight_load > weight_capacity


## 1.0 within budget; less when overloaded on power or weight (scales top
## speed and acceleration).
func mobility() -> float:
	return Loadout.mobility({"power_draw": power_load(), "power_output": power_output,
		"weight": weight_load, "weight_capacity": weight_capacity})


func _ready() -> void:
	motion_mode = CharacterBody2D.MOTION_MODE_FLOATING
	if team == BulletPool.TEAM_PLAYER:
		collision_layer = T.LAYER_VEHICLE
		collision_mask = T.LAYER_WORLD | T.LAYER_ZOMBIE | T.LAYER_ENEMY
	else:
		collision_layer = T.LAYER_ENEMY
		collision_mask = T.LAYER_WORLD | T.LAYER_ZOMBIE | T.LAYER_VEHICLE | T.LAYER_ENEMY
	_ray.collision_mask = T.LAYER_WORLD
	var capsule := CapsuleShape2D.new()
	capsule.radius = body_wid * 0.5
	capsule.height = body_len
	var shape := CollisionShape2D.new()
	shape.shape = capsule
	shape.rotation = PI / 2.0
	add_child(shape)
	_sync_parts()


func is_targetable() -> bool:
	return not is_wrecked and is_inside_tree()


func gun_range() -> float:
	return bullet_speed * BulletPool.LIFETIME


func _physics_process(delta: float) -> void:
	if is_wrecked:
		velocity = velocity.move_toward(Vector2.ZERO, 900.0 * delta)
		move_and_slide()
		touching_wall = false
		wall_impact = 0.0
		_burn(delta)
		return
	_drive(delta)
	_update_lock(delta)
	_weapons(delta)
	for a in abilities:
		a.ready_in = maxf(float(a.ready_in) - delta, 0.0)
	if _flash > 0.0:
		_flash = maxf(_flash - delta * 5.0, 0.0)
		queue_redraw()


# --- Driving -------------------------------------------------------------------

func _drive(delta: float) -> void:
	var forward := Vector2.RIGHT.rotated(rotation)
	var fwd_speed := velocity.dot(forward)
	var stick := drive_input.length()
	var throttle := 0.0

	if stick > 0.0:
		var desired := drive_input.angle()
		var diff := wrapf(desired - rotation, -PI, PI)
		if absf(diff) > REVERSE_ANGLE and (fwd_speed < max_speed * 0.2 or _reversing):
			# Stick points behind us and we're slow: back up, steering the tail.
			_reversing = true
			diff = wrapf(desired + PI - rotation, -PI, PI)
			throttle = -stick
		else:
			_reversing = false
			# Ease off the gas while turning hard; that's where drifts come from.
			throttle = stick * clampf(0.35 + 0.65 * cos(diff), 0.15, 1.0)
		var authority := clampf(absf(fwd_speed) / (max_speed * 0.3), 0.3, 1.0)
		var max_turn := turn_rate * authority * delta
		rotation += clampf(diff, -max_turn, max_turn)
	else:
		_reversing = false

	# Re-project velocity onto the new heading. Leftover sideways speed is the
	# drift, and grip decides how quickly it dies.
	forward = Vector2.RIGHT.rotated(rotation)
	var side := forward.orthogonal()
	fwd_speed = velocity.dot(forward)
	var side_speed := velocity.dot(side)

	# An overloaded power plant can't deliver full speed or acceleration.
	var power := mobility()
	if throttle > 0.0:
		var target := throttle * max_speed * power
		var rate := acceleration * power if fwd_speed < target else coast
		if fwd_speed < 0.0:
			rate = brake
		fwd_speed = move_toward(fwd_speed, target, rate * delta)
	elif throttle < 0.0:
		var rate := brake if fwd_speed > 0.0 else acceleration * power
		fwd_speed = move_toward(fwd_speed, throttle * reverse_speed * power, rate * delta)
	else:
		fwd_speed = move_toward(fwd_speed, 0.0, coast * delta)

	side_speed *= exp(-grip * traction * delta)
	velocity = forward * fwd_speed + side * side_speed

	var pre_velocity := velocity
	move_and_slide()
	_resolve_collisions(pre_velocity)


func _resolve_collisions(pre_velocity: Vector2) -> void:
	var hit_wall := false
	var plowed_through := false
	var already_hit: Array[Object] = []
	var normal := Vector2.ZERO
	var impact_max := 0.0
	for i in get_slide_collision_count():
		var collision := get_slide_collision(i)
		var other := collision.get_collider()
		var impact := -pre_velocity.dot(collision.get_normal())
		if other is Hostile:
			var hostile := other as Hostile
			if already_hit.has(hostile) or impact < RAM_MIN_SPEED:
				continue
			already_hit.append(hostile)
			var damage := ram_damage * clampf(impact / max_speed, 0.0, 1.2)
			hostile.take_hit(damage, pre_velocity.normalized() * impact * 0.6, "rammed")
			if not hostile.active:
				plowed_through = true
		elif other != null and other.has_method("receive_ram"):
			# Another rig. Hit it hard enough and it hurts; it'll hit back from its side.
			if already_hit.has(other) or impact < RAM_MIN_SPEED:
				continue
			already_hit.append(other)
			other.call("receive_ram", ram_damage * clampf(impact / max_speed, 0.0, 1.2))
		else:
			hit_wall = true
			normal = collision.get_normal()
			impact_max = maxf(impact_max, impact)

	# Only a fresh crash counts as an impact; grinding along a wall doesn't.
	wall_impact = impact_max if hit_wall and not touching_wall else 0.0
	if wall_impact > WALL_DAMAGE_SPEED:
		take_damage((wall_impact - WALL_DAMAGE_SPEED) * 0.05)
	touching_wall = hit_wall
	wall_normal = normal

	if plowed_through and not hit_wall:
		# Plowing through a body that died shouldn't stop the rig dead.
		velocity = pre_velocity * 0.88
	else:
		# Keep only the speed we actually achieved, so pinning the rig against
		# a wall doesn't leave phantom speed in the model.
		velocity = get_real_velocity()


# --- Lock-on -------------------------------------------------------------------

func _update_lock(delta: float) -> void:
	if not lock_enabled or lock_range <= 0.0 or not lock_candidates.is_valid():
		lock_target = null
		return
	if lock_target != null and not _lock_still_valid(lock_target):
		lock_target = null
	if lock_target != null:
		# Drop a target we've lost sight of for a moment.
		_lock_blind = 0.0 if _has_los(lock_target.global_position) else _lock_blind + delta
		if _lock_blind > 0.5:
			lock_target = null
	_lock_check -= delta
	if lock_target == null or _lock_check <= 0.0:
		_lock_check = 0.25
		var best := _best_lock_target()
		# Only switch if nothing locked yet or something more dangerous showed up.
		if best != null and (lock_target == null or _priority_of(best) > _priority_of(lock_target)):
			lock_target = best
			_lock_blind = 0.0


func _lock_still_valid(target: Node2D) -> bool:
	if not is_instance_valid(target) or not target.call("is_targetable"):
		return false
	return global_position.distance_to(target.global_position) <= lock_range * 1.15


func _priority_of(target: Node2D) -> int:
	if latched.has(target):
		return 10  # a Hunter on the hull beats everything
	return int(target.get("lock_priority"))


func _best_lock_target() -> Node2D:
	var candidates: Array = lock_candidates.call()
	var best: Node2D = null
	var best_score := -INF
	var checks := 0
	# Score: priority first, then distance. Check line of sight on the best few.
	candidates.sort_custom(func(a: Node2D, b: Node2D) -> bool:
		return _score(a) > _score(b))
	for c: Node2D in candidates:
		if global_position.distance_to(c.global_position) > lock_range:
			continue
		if not c.call("is_targetable"):
			continue
		if checks >= 4:
			break
		checks += 1
		if _has_los(c.global_position):
			var s := _score(c)
			if s > best_score:
				best_score = s
				best = c
	return best


func _score(c: Node2D) -> float:
	return _priority_of(c) * 10000.0 - global_position.distance_to(c.global_position)


func _has_los(to: Vector2) -> bool:
	_ray.from = global_position
	_ray.to = to
	return get_world_2d().direct_space_state.intersect_ray(_ray).is_empty()


# --- Weapons -------------------------------------------------------------------

func _weapons(delta: float) -> void:
	if bullets == null or not has_weapon():
		return
	var manual := aim_input.length() >= AIM_DEADZONE
	var trigger := aim_input.length() >= FIRE_THRESHOLD
	var locked := lock_target != null
	var forward := Vector2.RIGHT.rotated(rotation)
	for i in gun_stats.size():
		var w := gun_stats[i]
		_cooldowns[i] = maxf(_cooldowns[i] - delta, 0.0)
		var wants_fire := false
		var direction := forward
		var muzzle := global_position + forward * (body_len * 0.25)
		var turret := _turrets[i] if i < _turrets.size() else null
		if turret != null:
			var want_angle := 0.0
			if manual:
				want_angle = aim_input.angle()
			elif locked:
				want_angle = (_lead_point(lock_target, float(w.bullet_speed)) - turret.global_position).angle()
			if manual or locked:
				turret.rotation = rotate_toward(turret.rotation, wrapf(want_angle - rotation, -PI, PI), float(w.turret_turn_rate) * delta)
			else:
				turret.rotation = lerp_angle(turret.rotation, 0.0, 1.0 - exp(-4.0 * delta))
			direction = Vector2.RIGHT.rotated(turret.global_rotation)
			# Rays start at the turret pivot, not the muzzle tip, so a zombie
			# pressed against the hull is still in the line of fire.
			muzzle = turret.global_position
			if manual:
				wants_fire = trigger
			elif locked:
				wants_fire = absf(angle_difference(turret.global_rotation, want_angle)) < LOCK_FIRE_CONE
		else:
			# Fixed guns fire straight ahead: on the AI's trigger, when the player
			# pushes the right stick, or when a locked target is in front.
			wants_fire = fire_trigger or trigger
			if locked and not wants_fire:
				wants_fire = absf(forward.angle_to(lock_target.global_position - global_position)) < 0.2
			# Twin fixed guns alternate barrels.
			muzzle += forward.orthogonal() * 9.0 * _barrel_side
		if wants_fire and _cooldowns[i] <= 0.0:
			_cooldowns[i] = 1.0 / float(w.fire_rate)
			if turret == null:
				_barrel_side = -_barrel_side
			_shoot(w, muzzle, direction)


func _lead_point(target: Node2D, speed := 1500.0) -> Vector2:
	var at := target.global_position
	if latched.has(target):
		return at
	var vel: Vector2 = target.get("velocity")
	var t := clampf(global_position.distance_to(at) / maxf(speed, 1.0), 0.0, 0.5)
	return at + vel * t


func _shoot(w: Dictionary, muzzle: Vector2, direction: Vector2) -> void:
	var pellets := int(w.get("pellets", 1))
	var damage := float(w.bullet_damage)
	# A Hunter clinging to the hull is too close for a bullet to travel:
	# if the gun is pointing at it, it's a point-blank hit (every pellet).
	for h in latched:
		var to_h := h.global_position - global_position
		if absf(direction.angle_to(to_h)) < 0.6:
			h.call("take_hit", damage * pellets, Vector2.ZERO, "shot")
			if fx != null:
				fx.sparks(h.global_position, -to_h.normalized())
			bullets.record_direct_hit()
			return
	var cone := deg_to_rad(float(w.spread_deg))
	for p in pellets:
		var dir := direction.rotated(randf_range(-cone, cone))
		bullets.fire(muzzle, dir * float(w.bullet_speed) * randf_range(0.95, 1.05) if pellets > 1 else dir * float(w.bullet_speed), damage, team)


# --- Utilities ---------------------------------------------------------------------

## Fire utility `index` (its HUD button). Returns false if it's still cooling down.
func use_ability(index: int) -> bool:
	if is_wrecked or index < 0 or index >= abilities.size():
		return false
	var a := abilities[index]
	if float(a.ready_in) > 0.0:
		return false
	a.ready_in = float(a.cooldown)
	match str(a.ability):
		"patch":
			armor = minf(armor + float(a.heal), armor_max)
			if fx != null:
				fx.call("repair", global_position)
		"mines":
			if mines != null:
				var back := -Vector2.RIGHT.rotated(rotation)
				var count := int(a.mines)
				for m in count:
					var side := (float(m) - (count - 1) * 0.5) * 34.0
					var at := global_position + back * (body_len * 0.5 + 18.0) + back.orthogonal() * side
					mines.call("drop", at, float(a.mine_damage), float(a.mine_radius), float(a.mine_arm), float(a.mine_life))
	return true


## 0 when ready, up to 1 right after use.
func ability_charge(index: int) -> float:
	if index < 0 or index >= abilities.size():
		return 0.0
	var a := abilities[index]
	return clampf(float(a.ready_in) / maxf(float(a.cooldown), 0.01), 0.0, 1.0)


# --- Damage ----------------------------------------------------------------------

func take_hit(damage: float, impulse: Vector2, _cause := "shot") -> void:
	if not is_wrecked:
		velocity += impulse * 0.15
	take_damage(damage)


func receive_ram(damage: float) -> void:
	take_damage(damage)


func take_damage(amount: float) -> void:
	if is_wrecked or amount <= 0.0:
		return
	armor -= amount
	if amount >= 2.0:
		_flash = 1.0
		queue_redraw()
	damaged.emit(amount)
	if armor <= 0.0:
		armor = 0.0
		_wreck()


func _wreck() -> void:
	is_wrecked = true
	lock_target = null
	_burn_left = 6.0
	for t in _turrets:
		if t != null:
			t.visible = false
	queue_redraw()
	if fx != null:
		fx.explosion(global_position, velocity)
	wrecked.emit()


func _burn(delta: float) -> void:
	if _burn_left <= 0.0 or fx == null:
		return
	_burn_left -= delta
	_burn_timer -= delta
	if _burn_timer <= 0.0:
		_burn_timer = 0.06
		var jitter := Vector2(randf_range(-22.0, 22.0), randf_range(-12.0, 12.0)).rotated(rotation)
		fx.flame(global_position + jitter)


# --- Look ----------------------------------------------------------------------

func _draw() -> void:
	var half_l := body_len * 0.5
	var half_w := body_wid * 0.5
	var hull := T.COL_STEEL
	if is_wrecked:
		hull = Color(0.11, 0.1, 0.095)
	elif _flash > 0.0:
		hull = hull.lerp(Color(1.0, 0.85, 0.7), _flash * 0.6)

	# Wheels first so the hull overlaps them. Each drive reads differently.
	var tyre := Color(0.07, 0.07, 0.075)
	var drive := str(look.get("drive", ""))
	if drive == "half_track":
		# Tracks at the back, small wheels up front.
		for sy: float in [-1.0, 1.0]:
			draw_rect(Rect2(Vector2(-half_l + 2.0, sy * half_w - 6.0), Vector2(body_len * 0.55, 12.0)), tyre)
			for k in 5:
				draw_rect(Rect2(Vector2(-half_l + 4.0 + k * body_len * 0.1, sy * half_w - 5.0), Vector2(3.0, 10.0)), Color(0.18, 0.18, 0.19))
			draw_rect(Rect2(Vector2(half_l * 0.55 - 7.0, sy * half_w - 4.0), Vector2(14.0, 8.0)), tyre)
	else:
		var big := drive == "off_road_tires"
		var size := Vector2(19.0, 13.0) if big else Vector2(16.0, 10.0)
		for sx: float in [-1.0, 1.0]:
			for sy: float in [-1.0, 1.0]:
				var wheel := Rect2(Vector2(sx * half_l * 0.55, sy * half_w) - size * 0.5, size)
				draw_rect(wheel, tyre)
				if drive == "outrider_sport_wheels":
					draw_rect(wheel.grow(-3.0), T.COL_ORANGE.darkened(0.2))
				elif big:
					for k in 3:
						draw_rect(Rect2(wheel.position + Vector2(3.0 + k * 5.0, 1.0), Vector2(2.0, size.y - 2.0)), Color(0.16, 0.16, 0.17))

	draw_rect(Rect2(-half_l, -half_w + 3.0, body_len, body_wid - 6.0), hull)
	if is_wrecked:
		draw_rect(Rect2(-10.0, -8.0, 22.0, 16.0), Color(0.05, 0.04, 0.04))
		return
	# Cab.
	draw_rect(Rect2(-half_l + 8.0, -half_w + 7.0, 26.0, body_wid - 14.0), hull.darkened(0.25))
	# Frame details: Bulwark gets side skirts, Courier a racing stripe.
	match str(look.get("chassis", "")):
		"bulwark_frame":
			draw_rect(Rect2(-half_l + 10.0, -half_w + 1.0, body_len - 24.0, 4.0), hull.darkened(0.4))
			draw_rect(Rect2(-half_l + 10.0, half_w - 5.0, body_len - 24.0, 4.0), hull.darkened(0.4))
		"courier_frame":
			draw_rect(Rect2(-half_l + 4.0, -3.0, body_len - 16.0, 6.0), T.COL_CYAN.darkened(0.35))
	# Front armor: each plate has its own nose.
	match str(look.get("armor", "scrap_plating")):
		"scrap_plating":
			draw_rect(Rect2(half_l - 11.0, -half_w + 2.0, 11.0, body_wid - 4.0), T.COL_RUST)
			draw_rect(Rect2(half_l - 4.0, -half_w + 2.0, 4.0, body_wid - 4.0), T.COL_RUST.darkened(0.3))
		"outrider_light_plating":
			draw_rect(Rect2(half_l - 7.0, -half_w + 3.0, 7.0, body_wid - 6.0), Color(0.3, 0.2, 0.16))
			draw_rect(Rect2(half_l - 7.0, -1.0, 7.0, 2.0), T.COL_ENEMY)
		"riot_plating":
			draw_rect(Rect2(half_l - 14.0, -half_w, 14.0, body_wid), Color(0.36, 0.37, 0.38))
			for k in 3:
				draw_rect(Rect2(half_l - 12.0, -half_w + 4.0 + k * (body_wid - 8.0) / 3.0, 10.0, 2.0), Color(0.22, 0.22, 0.23))
		"spiked_ram_plate":
			draw_rect(Rect2(half_l - 10.0, -half_w + 2.0, 10.0, body_wid - 4.0), T.COL_RUST.darkened(0.2))
			for k in 4:
				var y := -half_w + 4.0 + k * (body_wid - 8.0) / 3.0
				draw_colored_polygon(PackedVector2Array([Vector2(half_l, y - 3.0), Vector2(half_l + 9.0, y), Vector2(half_l, y + 3.0)]), Color(0.75, 0.72, 0.66))
		"composite_plating":
			draw_rect(Rect2(half_l - 13.0, -half_w + 1.0, 13.0, body_wid - 2.0), Color(0.24, 0.27, 0.3))
			draw_rect(Rect2(half_l - 13.0, -half_w + 1.0, 13.0, body_wid - 2.0), T.COL_CYAN.darkened(0.4), false, 1.5)
	# Fixed guns on the nose instead of a turret.
	for w in gun_stats:
		if int(w.mount) == Mount.FIXED:
			draw_rect(Rect2(half_l - 16.0, -12.0, 22.0, 4.0), Color(0.15, 0.15, 0.16))
			draw_rect(Rect2(half_l - 16.0, 8.0, 22.0, 4.0), Color(0.15, 0.15, 0.16))
			break
	# Utilities: a patch kit (green cross) or a mine rack at the tail.
	var utils: Array = look.get("utility", [])
	if utils.has("emergency_patch"):
		draw_rect(Rect2(-half_l + 12.0, half_w - 13.0, 8.0, 8.0), Color(0.2, 0.2, 0.21))
		draw_rect(Rect2(-half_l + 15.0, half_w - 12.0, 2.0, 6.0), Color(0.45, 0.85, 0.5))
		draw_rect(Rect2(-half_l + 13.0, half_w - 10.0, 6.0, 2.0), Color(0.45, 0.85, 0.5))
	if utils.has("mine_dropper"):
		draw_rect(Rect2(-half_l - 3.0, -12.0, 7.0, 24.0), Color(0.12, 0.12, 0.13))
		for k in 3:
			var p := Vector2(-half_l + 0.5, -8.0 + k * 8.0)
			draw_circle(p, 3.0, Color(0.3, 0.29, 0.25))
			draw_circle(p, 1.2, T.COL_ENEMY)
	# Targeting computer: a sensor dish behind the cab.
	var internal: Array = look.get("internal", [])
	if internal.has("targeting_computer") or internal.has("advanced_targeting"):
		draw_rect(Rect2(-half_l + 2.0, -5.0, 7.0, 10.0), Color(0.16, 0.17, 0.18))
		draw_circle(Vector2(-half_l + 5.5, 0.0), 2.5, T.COL_CYAN)
	# Practical lights: cyan edge strips, white headlights, orange tail lights.
	draw_rect(Rect2(-half_l + 6.0, -half_w + 3.0, body_len - 20.0, 2.0), T.COL_CYAN)
	draw_rect(Rect2(-half_l + 6.0, half_w - 5.0, body_len - 20.0, 2.0), T.COL_CYAN)
	draw_rect(Rect2(half_l - 2.0, -half_w + 5.0, 3.0, 6.0), Color(1.0, 0.96, 0.82))
	draw_rect(Rect2(half_l - 2.0, half_w - 11.0, 3.0, 6.0), Color(1.0, 0.96, 0.82))
	draw_rect(Rect2(-half_l - 1.0, -half_w + 5.0, 3.0, 6.0), T.COL_ORANGE)
	draw_rect(Rect2(-half_l - 1.0, half_w - 11.0, 3.0, 6.0), T.COL_ORANGE)


class TurretSprite extends Node2D:
	const T := preload("res://scripts/tuning.gd")
	var kind := ""   # weapon part id: changes the barrel

	func _draw() -> void:
		match kind:
			"scattergun_turret":
				# Short, wide, flared.
				draw_rect(Rect2(0.0, -5.0, 20.0, 10.0), Color(0.18, 0.18, 0.19))
				draw_colored_polygon(PackedVector2Array([Vector2(18, -5), Vector2(25, -8), Vector2(25, 8), Vector2(18, 5)]), T.COL_ORANGE.darkened(0.2))
			"heavy_mg_turret":
				# Long and thick, with a cooling jacket.
				draw_rect(Rect2(0.0, -4.0, 38.0, 8.0), Color(0.16, 0.16, 0.17))
				for k in 4:
					draw_rect(Rect2(10.0 + k * 6.0, -5.0, 2.0, 10.0), Color(0.26, 0.26, 0.27))
				draw_rect(Rect2(34.0, -4.0, 4.0, 8.0), T.COL_ORANGE)
			_:
				draw_rect(Rect2(0.0, -3.0, 30.0, 6.0), Color(0.18, 0.18, 0.19))
				draw_rect(Rect2(26.0, -3.0, 4.0, 6.0), T.COL_ORANGE)
		draw_circle(Vector2.ZERO, 11.0, Color(0.22, 0.225, 0.235))
		draw_arc(Vector2.ZERO, 11.0, 0.0, TAU, 20, T.COL_CYAN, 2.0)
		draw_rect(Rect2(-4.0, -4.0, 8.0, 8.0), Color(0.14, 0.14, 0.15))
