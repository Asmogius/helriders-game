extends CharacterBody2D
## A rig: arcade drift handling, weapons, ramming, armor. The player's rig and
## enemy rigs share this script; enemy_rig.gd extends it with an AI brain.
##
## Driving: point the left stick where you want to go; pull it behind you while
## slow to reverse. Turret rigs aim with the right stick (push past halfway to
## fire) or, with lock on, aim and fire at the locked target by themselves.
##
## Crew (player only, crew.gd): the seated Driver and Gunner add passives and
## a triggered ability each, and a big hit can injure one mid-fight. A turret
## turns only with a Gunner seated or a targeting computer fitted.

signal wrecked
signal damaged(amount: float)
signal crew_injured(index: int)
signal crew_healed(index: int)
signal crew_ability_used(kind: String, ability: Dictionary)   # Mark, Flare, Magnet: the mission acts

const T := preload("res://scripts/tuning.gd")
const Hostile := preload("res://scripts/hostile.gd")
const BulletPool := preload("res://scripts/bullet_pool.gd")
const Parts := preload("res://scripts/parts.gd")
const Loadout := preload("res://scripts/loadout.gd")
const Crew := preload("res://scripts/crew.gd")

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
var manual_aim := true             # a targeting computer can aim turrets (enemy rigs: always)
var injury_mult := 1.0             # crew injury chance multiplier (Roll Cage)

# Crew riding this rig: one entry per seated member, see set_crew().
var crew: Array[Dictionary] = []
var big_hits := 0                  # big hits taken (tests and stats)
# Live crew modifiers, rebuilt by _refresh_crew_mods() when anything changes.
var crew_mods: Dictionary = Crew.base_mods()
var latch_mult := 1.0              # latched Hunter damage (hunter.gd reads it)
var vuln := 1.0                    # damage taken while marked (enemy rigs)
var vuln_left := 0.0
var crew_accel := 1.0
var crew_turn := 1.0
var crew_grip := 0.0
var crew_speed := 1.0
var crew_aim := 1.0
var crew_spread := 1.0
var crew_lock := 1.0
var crew_fire := 1.0
var crew_damage := 1.0

var team := BulletPool.TEAM_PLAYER
var armor := 0.0
var traction := 1.0                # grip multiplier: slime lowers it (set_on_slime)
var slime_left := 0.0               # seconds of slick tyres left after leaving slime
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
var hazards: Node2D                # GroundHazards, for the Oil Slick

var _turret: Node2D                # the first turret, if any
var _turrets: Array[Node2D] = []   # one per weapon; null for fixed guns
var _cooldowns: Array[float] = []
var _burst_left: Array[int] = []     # rounds still to go in each gun's burst
var _burst_gap: Array[float] = []
var _fire_cooldown := 0.0
var _flash := 0.0
var _reversing := false
var _burn_timer := 0.0
var _burn_left := 0.0
var _barrel_side := 1.0
var _lock_check := 0.0
var _lock_blind := 0.0
var _ray := PhysicsRayQueryParameters2D.new()
var _active := {}                  # crew ability kind -> its numbers + "left"
var _base_armor := 0.0
var _streak_timer := 0.0
# Damage taken per 0.1 s over the last second (big-hit check). No allocation.
var _dmg_buckets := PackedFloat32Array([0, 0, 0, 0, 0, 0, 0, 0, 0, 0])
var _bucket_i := 0
var _bucket_t := 0.0


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
	_base_armor = s.armor
	armor_max = _base_armor * float(crew_mods.armor)   # Reinforced keeps across a part swap
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
	manual_aim = bool(s.get("manual_aim", true))
	injury_mult = float(s.get("injury_mult", 1.0))
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
			"id": str(s.get("gun_id", "")), "mount": int(s.mount), "fire_rate": float(s.fire_rate),
			"bullet_damage": float(s.bullet_damage), "bullet_speed": float(s.bullet_speed),
			"spread_deg": float(s.spread_deg), "turret_turn_rate": float(s.turret_turn_rate),
			"lock_range": float(s.lock_range), "pellets": int(s.get("pellets", 1)),
			"burst": int(s.get("burst", 1)), "burst_rate": float(s.get("burst_rate", 0.0)),
		})
	_cooldowns.clear()
	_burst_left.clear()
	_burst_gap.clear()
	for w in gun_stats:
		_cooldowns.append(0.0)
		_burst_left.append(0)
		_burst_gap.append(0.0)
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
		sprite.enemy = team != BulletPool.TEAM_PLAYER
		sprite.position = turret_position(i, count)
		add_child(sprite)
		_turrets.append(sprite)
		if _turret == null:
			_turret = sprite
	queue_redraw()


func can_lock() -> bool:
	return lock_range > 0.0


## Lock range with an Epic+ Gunner's bonus.
func lock_reach() -> float:
	return lock_range * crew_lock


## Turrets turn only with a Gunner seated or a targeting computer fitted.
func can_aim_turrets() -> bool:
	if manual_aim:
		return true
	for c in crew:
		if str(c.role) == "gunner":
			return true
	return false


# --- Crew -----------------------------------------------------------------------

## Seat `members` (crew.gd dictionaries) on this rig for the run.
func set_crew(members: Array) -> void:
	crew.clear()
	for m: Dictionary in members:
		var e := Crew.entry(m)
		e.merge({"id": int(m.id), "name": str(m.name), "specialty": Crew.specialty(m),
			"tough": Crew.has_perk(m, "tough"), "ability": Crew.ability(m), "ready_in": 0.0})
		crew.append(e)
	_active.clear()
	_refresh_crew_mods()
	armor = armor_max


func _refresh_crew_mods() -> void:
	var active := {}
	for kind: String in _active:
		active[kind] = _active[kind]
	crew_mods = Crew.compute_mods(crew, active)
	crew_turn = float(crew_mods.turn)
	crew_grip = float(crew_mods.grip)
	crew_speed = float(crew_mods.speed)
	crew_accel = float(crew_mods.accel)
	crew_aim = float(crew_mods.aim)
	crew_spread = float(crew_mods.spread)
	crew_lock = float(crew_mods.lock)
	crew_fire = float(crew_mods.fire)
	crew_damage = float(crew_mods.damage)
	latch_mult = float(crew_mods.latch)
	if _base_armor > 0.0:
		armor_max = _base_armor * float(crew_mods.armor)
		armor = minf(armor, armor_max)
	for t in _turrets:
		if t != null:
			t.set("hot", _active.has("overcharge") or _active.has("deadeye"))
			t.queue_redraw()
	queue_redraw()


## A crew modifier by name (see Crew.base_mods()).
func crew_mod(key: String) -> Variant:
	return crew_mods.get(key, Crew.base_mods().get(key))


## Fire crew member `index`'s triggered ability (from the crew wheel).
func use_crew_ability(index: int) -> bool:
	if is_wrecked or index < 0 or index >= crew.size():
		return false
	var c := crew[index]
	if bool(c.injured) or float(c.ready_in) > 0.0:
		return false
	var a: Dictionary = c.ability
	var kind := str(a.kind)
	match kind:
		"field_dressing":
			# Only with someone to treat.
			var patient := -1
			for i in crew.size():
				if bool(crew[i].injured):
					patient = i
					break
			if patient < 0:
				return false
			crew[patient].injured = false
			crew_healed.emit(patient)
		"field_repair":
			armor = minf(armor + float(a.heal) * float(crew_mods.repair), armor_max)
			throw_off_hunters()
			if fx != null:
				fx.call("repair", global_position)
			if bool(a.get("epic", false)):
				_active["repair_guard"] = {"dr": float(a.epic_dr), "left": float(a.epic_time)}
		"bootleg":
			# Snap to face the left stick (or swing round), keeping speed.
			var heading := drive_input.angle() if drive_input.length() > 0.2 else rotation + PI
			var speed := velocity.length()
			rotation = heading
			velocity = Vector2.RIGHT.rotated(heading) * speed
		"reroute":
			for u in abilities:
				u.ready_in = float(u.ready_in) * (1.0 - minf(float(a.cut), 0.95))
		"shockwave":
			_shockwave(float(a.damage), float(a.radius))
		"mark", "flare", "magnet":
			crew_ability_used.emit(kind, a)
			if a.time > 0.0:
				var timed := a.duplicate()
				timed.left = float(a.time)
				_active[kind] = timed
		_:
			var timed := a.duplicate()
			timed.left = float(a.time)
			_active[kind] = timed
	c.ready_in = float(a.cooldown)
	_refresh_crew_mods()
	return true


## 0 when ready, up to 1 right after use.
func crew_charge(index: int) -> float:
	if index < 0 or index >= crew.size():
		return 0.0
	var c := crew[index]
	return clampf(float(c.ready_in) / maxf(float(c.ability.cooldown), 0.01), 0.0, 1.0)


func is_crew_injured(index: int) -> bool:
	return index >= 0 and index < crew.size() and bool(crew[index].injured)


func ability_active(kind: String) -> bool:
	return _active.has(kind)


func hard_line_active() -> bool:
	return _active.has("hard_line")


func overcharge_active() -> bool:
	return _active.has("overcharge")


## Throw every Hunter off the hull (Field Repair, Shake It Off).
func throw_off_hunters() -> void:
	for h: Node2D in latched.duplicate():
		var away := (h.global_position - global_position).normalized()
		h.call("knock_off", away if away != Vector2.ZERO else Vector2.RIGHT)


func _shockwave(damage: float, radius: float) -> void:
	var shape := CircleShape2D.new()
	shape.radius = radius
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = shape
	query.transform = Transform2D(0.0, global_position)
	query.collision_mask = T.LAYER_ZOMBIE | (T.LAYER_ENEMY if team == BulletPool.TEAM_PLAYER else T.LAYER_VEHICLE)
	for hit: Dictionary in get_world_2d().direct_space_state.intersect_shape(query, 32):
		var body: Object = hit.collider
		if body != null and body != self and body.has_method("take_hit"):
			var away: Vector2 = ((body as Node2D).global_position - global_position).normalized()
			body.call("take_hit", damage, away * 500.0, "shockwave")
	throw_off_hunters()
	if fx != null:
		fx.call("blast", global_position, radius)


## Injure crew member `index` now: their passive, perks and ability are gone
## for the run, and the rig takes their class's debuff.
func injure_crew(index: int) -> void:
	if index < 0 or index >= crew.size() or bool(crew[index].injured):
		return
	var c := crew[index]
	c.injured = true
	_active.erase(str(c.ability.kind))
	if str(c.ability.kind) == "field_repair":
		_active.erase("repair_guard")
	_refresh_crew_mods()
	crew_injured.emit(index)


## A big hit (over the big-hit share of max armor inside a second) may injure
## a random crew member who isn't hurt yet. Tough crew are half as likely to
## be the one.
func _check_big_hit() -> void:
	var total := 0.0
	for v in _dmg_buckets:
		total += v
	if total <= armor_max * float(crew_mods.big_hit):
		return
	big_hits += 1
	_dmg_buckets.fill(0.0)
	if bool(crew_mods.immune):
		return
	if randf() >= T.CREW_INJURY_CHANCE * injury_mult * float(crew_mods.injury):
		return
	var weights := 0.0
	for c in crew:
		if not bool(c.injured):
			weights += 0.5 if bool(c.tough) else 1.0
	if weights <= 0.0:
		return
	var roll := randf() * weights
	for i in crew.size():
		if bool(crew[i].injured):
			continue
		roll -= 0.5 if bool(crew[i].tough) else 1.0
		if roll <= 0.0:
			injure_crew(i)
			return


func _tick_crew(delta: float) -> void:
	# Roll the damage window forward in 0.1 s steps.
	_bucket_t += delta
	while _bucket_t >= 0.1:
		_bucket_t -= 0.1
		_bucket_i = (_bucket_i + 1) % _dmg_buckets.size()
		_dmg_buckets[_bucket_i] = 0.0
	for c in crew:
		c.ready_in = maxf(float(c.ready_in) - delta, 0.0)
	if _active.is_empty():
		return
	var ended: Array[String] = []
	for kind: String in _active:
		var a: Dictionary = _active[kind]
		a.left = float(a.left) - delta
		if float(a.left) <= 0.0:
			ended.append(kind)
	# Tyre streaks while a driving ability runs: cyan Hard Line, orange Floor It.
	var streak := T.COL_CYAN if _active.has("hard_line") else (T.COL_ORANGE if _active.has("floor_it") or _active.has("overclock") else Color.TRANSPARENT)
	if streak.a > 0.0:
		_streak_timer -= delta
		if fx != null and _streak_timer <= 0.0 and velocity.length() > 120.0:
			_streak_timer = 0.04
			var back := -Vector2.RIGHT.rotated(rotation) * body_len * 0.4
			var side := Vector2.RIGHT.rotated(rotation).orthogonal() * body_wid * 0.5
			for s: float in [-1.0, 1.0]:
				fx.call("emit", global_position + back + side * s, -velocity * 0.1, 0.35, 4.0, streak, 4.0)
	if not ended.is_empty():
		for kind in ended:
			_active.erase(kind)
		_refresh_crew_mods()


## Power drawn by the build (crew can trim it). Fixed by what's installed,
## not by what's switched on.
func power_load() -> float:
	return power_draw * float(crew_mods.draw)


## The engine's output with crew bonuses (Engineer).
func power_capacity() -> float:
	return power_output * float(crew_mods.power)


func weight_limit() -> float:
	return weight_capacity * float(crew_mods.weight_cap)


func is_overloaded() -> bool:
	return is_power_overloaded() or is_weight_overloaded()


func is_power_overloaded() -> bool:
	return power_output > 0.0 and power_load() > power_capacity()


func is_weight_overloaded() -> bool:
	return weight_capacity > 0.0 and weight_load > weight_limit()


## 1.0 within budget; less when overloaded on power or weight (scales top
## speed and acceleration). Overclock ignores overload while it runs.
func mobility() -> float:
	if bool(crew_mods.ignore_overload):
		return 1.0
	return Loadout.mobility({"power_draw": power_load(), "power_output": power_capacity(),
		"weight": weight_load, "weight_capacity": weight_limit()})


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
	if not crew.is_empty():
		_tick_crew(delta)
	if vuln_left > 0.0:
		vuln_left -= delta
		if vuln_left <= 0.0:
			queue_redraw()
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
		var max_turn := turn_rate * crew_turn * authority * delta
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
		var target := throttle * max_speed * power * crew_speed
		var rate := acceleration * power * crew_accel if fwd_speed < target else coast
		if fwd_speed < 0.0:
			rate = brake
		fwd_speed = move_toward(fwd_speed, target, rate * delta)
	elif throttle < 0.0:
		var rate := brake if fwd_speed > 0.0 else acceleration * power * crew_accel
		fwd_speed = move_toward(fwd_speed, throttle * reverse_speed * power, rate * delta)
	else:
		fwd_speed = move_toward(fwd_speed, 0.0, coast * delta)

	side_speed *= exp(-(grip + crew_grip) * traction * delta)
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
			var damage := ram_damage * float(crew_mods.ram) * clampf(impact / max_speed, 0.0, 1.2)
			hostile.take_hit(damage, pre_velocity.normalized() * impact * 0.6, "rammed")
			if bool(crew_mods.shake_off):
				throw_off_hunters()
			if not hostile.active:
				plowed_through = true
		elif other != null and other.has_method("receive_ram"):
			# Another rig. Hit it hard enough and it hurts; it'll hit back from its side.
			# Friendly rigs (your rig and an Escort's truck) only bump.
			if already_hit.has(other) or impact < RAM_MIN_SPEED:
				continue
			if team == BulletPool.TEAM_PLAYER and int(other.get("team")) == BulletPool.TEAM_PLAYER:
				continue
			already_hit.append(other)
			other.call("receive_ram", ram_damage * float(crew_mods.ram) * clampf(impact / max_speed, 0.0, 1.2))
			if bool(crew_mods.shake_off):
				throw_off_hunters()
		else:
			hit_wall = true
			normal = collision.get_normal()
			impact_max = maxf(impact_max, impact)

	# Only a fresh crash counts as an impact; grinding along a wall doesn't.
	wall_impact = impact_max if hit_wall and not touching_wall else 0.0
	if wall_impact > WALL_DAMAGE_SPEED:
		take_damage((wall_impact - WALL_DAMAGE_SPEED) * 0.05 * float(crew_mods.wall))
	touching_wall = hit_wall
	wall_normal = normal

	if plowed_through and not hit_wall:
		# Plowing through a body that died shouldn't stop the rig dead.
		velocity = pre_velocity * (1.0 if bool(crew_mods.plow) else 0.88)
	else:
		# Keep only the speed we actually achieved, so pinning the rig against
		# a wall doesn't leave phantom speed in the model.
		velocity = get_real_velocity()


# --- Lock-on -------------------------------------------------------------------

func _update_lock(delta: float) -> void:
	if not lock_enabled or lock_reach() <= 0.0 or not lock_candidates.is_valid():
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
	return global_position.distance_to(target.global_position) <= lock_reach() * 1.15


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
		if global_position.distance_to(c.global_position) > lock_reach():
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
	var can_aim := can_aim_turrets()
	for i in gun_stats.size():
		var w := gun_stats[i]
		_cooldowns[i] = maxf(_cooldowns[i] - delta, 0.0)
		var wants_fire := false
		var direction := forward
		var muzzle := global_position + forward * (body_len * 0.25)
		var turret := _turrets[i] if i < _turrets.size() else null
		if turret != null and not can_aim:
			# No Gunner and no targeting computer: the turret stays facing
			# forward and fires on the trigger like a fixed gun.
			turret.rotation = lerp_angle(turret.rotation, 0.0, 1.0 - exp(-6.0 * delta))
			direction = Vector2.RIGHT.rotated(turret.global_rotation)
			muzzle = turret.global_position
			wants_fire = trigger or fire_trigger
		elif turret != null:
			var want_angle := 0.0
			if manual:
				want_angle = aim_input.angle()
			elif locked:
				want_angle = (_lead_point(lock_target, float(w.bullet_speed)) - turret.global_position).angle()
			if manual or locked:
				turret.rotation = rotate_toward(turret.rotation, wrapf(want_angle - rotation, -PI, PI), float(w.turret_turn_rate) * crew_aim * delta)
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
		var burst := int(w.get("burst", 1))
		if burst > 1:
			# Burst guns: one pull fires `burst` rounds a beat apart; the burst
			# finishes even if the trigger lets go. The cooldown runs from its start.
			if _burst_left[i] > 0:
				_burst_gap[i] -= delta
				if _burst_gap[i] <= 0.0:
					_burst_left[i] -= 1
					_burst_gap[i] = 1.0 / maxf(float(w.burst_rate), 1.0)
					_shoot(w, muzzle, direction)
			elif wants_fire and _cooldowns[i] <= 0.0:
				_cooldowns[i] = 1.0 / (float(w.fire_rate) * crew_fire)
				_burst_left[i] = burst - 1
				_burst_gap[i] = 1.0 / maxf(float(w.burst_rate), 1.0)
				_shoot(w, muzzle, direction)
		elif wants_fire and _cooldowns[i] <= 0.0:
			_cooldowns[i] = 1.0 / (float(w.fire_rate) * crew_fire)
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
	var damage := float(w.bullet_damage) * crew_damage
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
	var cone := deg_to_rad(float(w.spread_deg) * crew_spread)
	var speed := float(w.bullet_speed) * float(crew_mods.bullet_speed)
	var pierce := int(crew_mods.pierce)
	for p in pellets:
		var dir := direction.rotated(randf_range(-cone, cone))
		bullets.fire(muzzle, dir * speed * randf_range(0.95, 1.05) if pellets > 1 else dir * speed, damage, team, pierce)


# --- Utilities ---------------------------------------------------------------------

## Fire utility `index` (its HUD button). Returns false if it's still cooling down.
func use_ability(index: int) -> bool:
	if is_wrecked or index < 0 or index >= abilities.size():
		return false
	var a := abilities[index]
	if float(a.ready_in) > 0.0:
		return false
	a.ready_in = float(a.cooldown) * float(crew_mods.util_cd)
	match str(a.ability):
		"patch":
			armor = minf(armor + float(a.heal) * float(crew_mods.patch) * float(crew_mods.repair), armor_max)
			if fx != null:
				fx.call("repair", global_position)
		"oil":
			if hazards != null:
				var back := -Vector2.RIGHT.rotated(rotation)
				hazards.call("add_oil", global_position + back * (body_len * 0.5 + float(a.oil_radius) * 0.6), float(a.oil_radius), float(a.oil_time))
		"mines":
			if mines != null:
				var back := -Vector2.RIGHT.rotated(rotation)
				var count := int(a.mines)
				for m in count:
					var side := (float(m) - (count - 1) * 0.5) * 34.0
					var at := global_position + back * (body_len * 0.5 + 18.0) + back.orthogonal() * side
					mines.call("drop", at, float(a.mine_damage) * float(crew_mods.mine), float(a.mine_radius), float(a.mine_arm), float(a.mine_life))
	return true


## 0 when ready, up to 1 right after use.
func ability_charge(index: int) -> float:
	if index < 0 or index >= abilities.size():
		return 0.0
	var a := abilities[index]
	return clampf(float(a.ready_in) / maxf(float(a.cooldown) * float(crew_mods.util_cd), 0.01), 0.0, 1.0)


# --- Damage ----------------------------------------------------------------------

## Slimer trails: on slime (and for a moment after) the tyres lose grip.
func set_on_slime(on: bool, delta: float) -> void:
	slime_left = T.SLIME_LINGER if on else maxf(slime_left - delta, 0.0)
	traction = T.SLIME_GRIP if slime_left > 0.0 else 1.0


func take_hit(damage: float, impulse: Vector2, _cause := "shot") -> void:
	if not is_wrecked:
		velocity += impulse * 0.15
	if vuln_left > 0.0:
		damage *= vuln
	take_damage(damage)


func receive_ram(damage: float) -> void:
	take_damage(damage * float(crew_mods.ram_taken))


## Marked by a Spotter: takes `mult` damage for `seconds`.
func apply_status(mult: float, _slow: float, seconds: float) -> void:
	vuln = mult
	vuln_left = seconds
	queue_redraw()


func take_damage(amount: float) -> void:
	if is_wrecked or amount <= 0.0:
		return
	amount *= float(crew_mods.taken)
	armor -= amount
	if amount >= 2.0:
		_flash = 1.0
		queue_redraw()
	damaged.emit(amount)
	if not crew.is_empty() and armor > 0.0:
		_dmg_buckets[_bucket_i] += amount
		_check_big_hit()
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
			if _active.has("overcharge") or _active.has("deadeye"):
				draw_rect(Rect2(half_l + 2.0, -12.0, 4.0, 4.0), Color(1.0, 0.95, 0.8))
				draw_rect(Rect2(half_l + 2.0, 8.0, 4.0, 4.0), Color(1.0, 0.95, 0.8))
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
	if internal.has("roll_cage"):
		# Bars over the cabin.
		var cage := Rect2(-half_l * 0.35, -half_w + 6.0, half_l * 0.6, body_wid - 12.0)
		draw_rect(cage, Color(0.12, 0.12, 0.13), false, 2.5)
		draw_line(cage.position, cage.end, Color(0.12, 0.12, 0.13), 2.0)
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
	var hot := false # Overcharge: white-hot muzzle
	var enemy := false  # enemy turrets wear red

	func _draw() -> void:
		match kind:
			"scattergun_turret":
				# Short, wide, flared.
				draw_rect(Rect2(0.0, -5.0, 20.0, 10.0), Color(0.18, 0.18, 0.19))
				draw_colored_polygon(PackedVector2Array([Vector2(18, -5), Vector2(25, -8), Vector2(25, 8), Vector2(18, 5)]), T.COL_ORANGE.darkened(0.2))
			"burst_turret", "gunner_rig":
				# Twin slim barrels with a muzzle brake.
				draw_rect(Rect2(0.0, -5.0, 32.0, 3.0), Color(0.17, 0.17, 0.18))
				draw_rect(Rect2(0.0, 2.0, 32.0, 3.0), Color(0.17, 0.17, 0.18))
				draw_rect(Rect2(30.0, -6.0, 4.0, 12.0), T.COL_ENEMY if enemy else T.COL_ORANGE)
			"convoy_turret":
				# Heavy: a thick barrel on a wide armored mount.
				draw_rect(Rect2(-2.0, -9.0, 14.0, 18.0), Color(0.2, 0.2, 0.21))
				draw_rect(Rect2(0.0, -5.0, 40.0, 10.0), Color(0.15, 0.15, 0.16))
				draw_rect(Rect2(36.0, -6.0, 5.0, 12.0), T.COL_ENEMY)
			"heavy_mg_turret":
				# Long and thick, with a cooling jacket.
				draw_rect(Rect2(0.0, -4.0, 38.0, 8.0), Color(0.16, 0.16, 0.17))
				for k in 4:
					draw_rect(Rect2(10.0 + k * 6.0, -5.0, 2.0, 10.0), Color(0.26, 0.26, 0.27))
				draw_rect(Rect2(34.0, -4.0, 4.0, 8.0), T.COL_ORANGE)
			_:
				draw_rect(Rect2(0.0, -3.0, 30.0, 6.0), Color(0.18, 0.18, 0.19))
				draw_rect(Rect2(26.0, -3.0, 4.0, 6.0), T.COL_ORANGE)
		if hot:
			# Overcharge: the muzzle glows white-hot.
			var tip := {"scattergun_turret": 25.0, "heavy_mg_turret": 38.0}.get(kind, 30.0) as float
			draw_rect(Rect2(tip - 5.0, -4.0, 6.0, 8.0), Color(1.0, 0.95, 0.8))
		draw_circle(Vector2.ZERO, 11.0, Color(0.22, 0.225, 0.235))
		draw_arc(Vector2.ZERO, 11.0, 0.0, TAU, 20, T.COL_ENEMY if enemy else T.COL_CYAN, 2.0)
		draw_rect(Rect2(-4.0, -4.0, 8.0, 8.0), Color(0.14, 0.14, 0.15))
