extends "res://scripts/enemy_rig.gd"
## Patcher: unarmed support rig (§14; agreed with the owner). It throws a
## grappling hook on a 400 px cable onto another enemy rig and repairs it
## (12 armor/s to its most damaged facing); the ally drags it along. The hook
## pops when either rig takes a big hit (over 15% of its max inside 1 s) or
## crashes hard, or when you ram the cable at speed; throwing it again takes a
## 3 s wind-up you can see. With no ally alive it parks by a wreck and brings
## it back at 10% over 4 s; any damage to it restarts that. It never repairs
## itself. Like every enemy rig it only decides stick inputs.

const ConvoyRig := preload("res://scripts/convoy_rig.gd")
const Vehicle := preload("res://scripts/vehicle.gd")

var hooked_to: Vehicle           # the ally on the cable, or null
var reviving: Vehicle            # the wreck it's bringing back, or null
var pops := 0                    # times the hook popped (tests)
var revives := 0                 # wrecks brought back (tests)
var wind_left := T.PATCHER_REHOOK   # hook wind-up; it flies at zero
var revive_left := T.PATCHER_REVIVE_TIME

var _seek: Vehicle               # the ally it's heading for
var _think_timer := 0.0
var _self_hits := PackedFloat32Array([0, 0, 0, 0, 0, 0, 0, 0, 0, 0])
var _ally_hits := PackedFloat32Array([0, 0, 0, 0, 0, 0, 0, 0, 0, 0])
var _hook_i := 0
var _hook_t := 0.0
var _circle_side := 1.0


func _init() -> void:
	team = BulletPool.TEAM_ENEMY
	apply_stats(T.PATCHER)
	body_len = 66.0
	body_wid = 34.0
	lock_priority = 3
	lock_radius = 42.0
	damaged.connect(_on_self_damaged)


func _enter_tree() -> void:
	_circle_side = 1.0 if randf() < 0.5 else -1.0


func is_hooked() -> bool:
	return hooked_to != null


func _physics_process(delta: float) -> void:
	super(delta)
	if is_wrecked:
		if hooked_to != null:
			unhook()
		reviving = null
		return
	_roll_buckets(delta)
	if hooked_to != null:
		if not is_instance_valid(hooked_to) or not hooked_to.is_inside_tree() or hooked_to.is_wrecked:
			unhook()
		else:
			_tow(delta)
			hooked_to.repair_armor(T.PATCHER_REPAIR * delta)
			_check_pops()
	if hooked_to != null or reviving != null or (wind_left < T.PATCHER_REHOOK and wind_left > 0.0):
		queue_redraw()   # the cable, the wind-up and the revive ring move every tick


func _think(delta: float) -> void:
	_mode_time -= delta
	_think_timer -= delta
	if _think_timer <= 0.0:
		_think_timer = 0.25
		if hooked_to == null:
			_seek = _nearest_ally()
	var forward := Vector2.RIGHT.rotated(rotation)
	var goal := Vector2.ZERO
	var throttle := 1.0
	if mode == Mode.UNSTICK:
		goal = -forward.rotated(_side * 0.6)
		if _mode_time <= 0.0:
			mode = Mode.ATTACK
	elif hooked_to != null:
		reviving = null
		var spot := _keep_spot(hooked_to)
		var to_spot := spot - global_position
		goal = to_spot.normalized()
		throttle = clampf(to_spot.length() / 200.0, 0.0, 1.0)
	elif _seek != null:
		reviving = null
		revive_left = T.PATCHER_REVIVE_TIME
		var to_ally := _seek.global_position - global_position
		# Close in to about 300 px, then hang off the far side while winding up.
		goal = (_keep_spot(_seek) - global_position).normalized() if to_ally.length() < 300.0 else to_ally.normalized()
		if to_ally.length() <= T.PATCHER_HOOK_RANGE:
			# In reach: wind up while it has a clear throw (a lamp post in the
			# way only pauses it).
			if _has_los(_seek.global_position):
				wind_left -= delta
				if wind_left <= 0.0:
					hook(_seek)
		elif to_ally.length() > T.PATCHER_HOOK_RANGE + 150.0:
			wind_left = T.PATCHER_REHOOK   # well out of reach: the wind-up starts over
	else:
		var wreck := _nearest_wreck() if revives < T.PATCHER_MAX_REVIVES else null   # 3 per job
		if wreck != null:
			if reviving != wreck:
				reviving = wreck
				revive_left = T.PATCHER_REVIVE_TIME
			var to_wreck := wreck.global_position - global_position
			if to_wreck.length() > T.PATCHER_REVIVE_REACH:
				goal = to_wreck.normalized()
				throttle = clampf(to_wreck.length() / 250.0, 0.4, 1.0)
			else:
				throttle = 0.0
				revive_left -= delta
				if revive_left <= 0.0:
					wreck.revive(T.PATCHER_REVIVE_TO)
					if fx != null:
						fx.call("repair", wreck.global_position)
					revives += 1
					reviving = null
					revive_left = T.PATCHER_REVIVE_TIME
					_seek = wreck
		else:
			# Alone and nothing to fix: keep clear of you.
			reviving = null
			var away := global_position - player.global_position
			if away.length() < 520.0:
				goal = away.normalized().rotated(_circle_side * 0.4)
			else:
				goal = away.normalized().rotated(_circle_side * PI * 0.5)
				throttle = 0.4
	if goal != Vector2.ZERO and mode != Mode.UNSTICK:
		goal = _avoid_walls(goal, forward)
	drive_input = goal * throttle
	fire_trigger = false
	aim_input = Vector2.ZERO
	if mode != Mode.UNSTICK and throttle > 0.3 and goal != Vector2.ZERO and get_real_velocity().length() < 40.0:
		_stuck_time += delta
		if _stuck_time > 0.8:
			mode = Mode.UNSTICK
			_mode_time = 0.9
			_side = 1.0 if randf() < 0.5 else -1.0
			_stuck_time = 0.0
	else:
		_stuck_time = 0.0


## Throw the cable onto `ally`.
func hook(ally: Vehicle) -> void:
	if ally == null or ally.is_wrecked or ally == self:
		return
	unhook()
	hooked_to = ally
	ally.damaged.connect(_on_ally_damaged)
	_ally_hits.fill(0.0)
	wind_left = T.PATCHER_REHOOK
	queue_redraw()


## Let go of the cable (no wind-up reset: pop_hook does that).
func unhook() -> void:
	if hooked_to != null and is_instance_valid(hooked_to) and hooked_to.damaged.is_connected(_on_ally_damaged):
		hooked_to.damaged.disconnect(_on_ally_damaged)
	hooked_to = null
	queue_redraw()


## The hook tears loose; it needs a full wind-up to throw it again.
func pop_hook() -> void:
	if hooked_to == null:
		return
	unhook()
	pops += 1
	wind_left = T.PATCHER_REHOOK
	if fx != null:
		fx.call("sparks", global_position, Vector2.RIGHT.rotated(rotation + PI))


## Where it hangs off an ally: on the far side from you, inside the cable.
func _keep_spot(ally: Vehicle) -> Vector2:
	var away := ally.global_position - player.global_position
	if away.length() < 1.0:
		away = Vector2.RIGHT
	return ally.global_position + away.normalized() * T.PATCHER_KEEP


## The cable is taut: the ally drags it along.
func _tow(_delta: float) -> void:
	var to_ally := hooked_to.global_position - global_position
	var dist := to_ally.length()
	if dist <= T.PATCHER_CABLE:
		return
	var dir := to_ally / dist
	move_and_collide(dir * (dist - T.PATCHER_CABLE))
	var pull := hooked_to.velocity.dot(dir)
	var own := velocity.dot(dir)
	if own < pull:
		velocity += dir * (pull - own)


func _check_pops() -> void:
	if _sum(_self_hits) > armor_max * T.PATCHER_POP_HIT or _sum(_ally_hits) > hooked_to.armor_max * T.PATCHER_POP_HIT:
		pop_hook()
		return
	if wall_impact > T.PATCHER_POP_CRASH or hooked_to.wall_impact > T.PATCHER_POP_CRASH:
		pop_hook()
		return
	# You, ramming the cable at speed.
	if player != null and player != hooked_to and not bool(player.get("is_wrecked")):
		var pv: Vector2 = player.get("velocity")
		if pv.length() > T.PATCHER_POP_RAM:
			var p := player.global_position
			var on := Geometry2D.get_closest_point_to_segment(p, global_position, hooked_to.global_position)
			var reach := float(player.get("body_wid")) * 0.5 + 10.0
			if p.distance_to(on) < reach and p.distance_to(global_position) > body_len * 0.5 and p.distance_to(hooked_to.global_position) > hooked_to.body_len * 0.5:
				pop_hook()


func _on_self_damaged(amount: float) -> void:
	_self_hits[_hook_i] += amount
	if reviving != null:
		revive_left = T.PATCHER_REVIVE_TIME   # hit while working: start over


func _on_ally_damaged(amount: float) -> void:
	_ally_hits[_hook_i] += amount


func _roll_buckets(delta: float) -> void:
	_hook_t += delta
	while _hook_t >= 0.1:
		_hook_t -= 0.1
		_hook_i = (_hook_i + 1) % 10
		_self_hits[_hook_i] = 0.0
		_ally_hits[_hook_i] = 0.0


static func _sum(a: PackedFloat32Array) -> float:
	var t := 0.0
	for v in a:
		t += v
	return t


## The closest working enemy rig (not another Patcher).
func _nearest_ally() -> Vehicle:
	var best: Vehicle = null
	var best_d := INF
	for n in get_parent().get_children():
		var rig := n as Vehicle
		if rig == null or rig == self or rig.is_wrecked or rig.has_method("pop_hook"):
			continue
		var d := global_position.distance_squared_to(rig.global_position)
		if d < best_d:
			best_d = d
			best = rig
	return best


## The closest wreck it can bring back (not a Convoy Lead, which lost its
## trailer, and not another Patcher).
func _nearest_wreck() -> Vehicle:
	if reviving != null and is_instance_valid(reviving) and reviving.is_wrecked and reviving.is_inside_tree():
		return reviving
	var best: Vehicle = null
	var best_d := INF
	for n in get_parent().get_children():
		var rig := n as Vehicle
		if rig == null or rig == self or not rig.is_wrecked or rig.has_method("pop_hook") or rig is ConvoyRig:
			continue
		var d := global_position.distance_squared_to(rig.global_position)
		if d < best_d:
			best_d = d
			best = rig
	return best


func _draw() -> void:
	var half_l := body_len * 0.5
	var half_w := body_wid * 0.5
	var hull := Color(0.24, 0.27, 0.22)
	if is_wrecked:
		hull = Color(0.1, 0.09, 0.085)
	elif _flash > 0.0:
		hull = hull.lerp(Color(1.0, 0.85, 0.7), _flash * 0.6)
	var tyre := Color(0.07, 0.07, 0.075)
	for sx: float in [-1.0, 1.0]:
		for sy: float in [-1.0, 1.0]:
			draw_rect(Rect2(Vector2(sx * half_l * 0.6 - 8.0, sy * half_w - 5.0), Vector2(16.0, 10.0)), tyre)
	# Tow truck: a cab up front, a flat bed with a winch boom on the back.
	draw_rect(Rect2(-half_l, -half_w + 3.0, body_len, body_wid - 6.0), hull)
	draw_rect(Rect2(half_l - 22.0, -half_w + 5.0, 20.0, body_wid - 10.0), hull.lightened(0.08))
	if is_wrecked:
		draw_rect(Rect2(-12.0, -7.0, 22.0, 14.0), Color(0.05, 0.04, 0.04))
		return
	var winch := Vector2(-half_l + 8.0, 0.0)
	draw_line(Vector2(-half_l + 26.0, 0.0), winch, Color(0.6, 0.55, 0.35), 4.0)   # the boom
	draw_circle(winch, 6.0, Color(0.15, 0.15, 0.16))
	# Wrench mark on the cab roof: the one that fixes the others.
	draw_line(Vector2(half_l - 17.0, -6.0), Vector2(half_l - 7.0, 6.0), Color(0.95, 0.75, 0.25), 3.0)
	draw_circle(Vector2(half_l - 17.0, -6.0), 3.5, Color(0.95, 0.75, 0.25))
	draw_rect(Rect2(-half_l + 4.0, -half_w + 4.0, body_len - 26.0, 2.0), T.COL_ENEMY)
	draw_rect(Rect2(-half_l + 4.0, half_w - 6.0, body_len - 26.0, 2.0), T.COL_ENEMY)
	draw_rect(Rect2(-half_l - 1.0, -4.0, 3.0, 8.0), T.COL_ENEMY)
	if vuln_left > 0.0:
		draw_arc(Vector2.ZERO, half_l + 8.0, 0.0, TAU, 28, Color(0.95, 0.3, 0.25, 0.85), 2.5)
	var cable_col := Color(0.85, 0.8, 0.55)
	if hooked_to != null and is_instance_valid(hooked_to):
		var end := to_local(hooked_to.global_position)
		draw_line(winch, end, cable_col, 2.0)
		draw_circle(end, 5.0, Color(0.35, 0.95, 0.5, 0.8))   # repairs flowing
	elif _seek != null and wind_left < T.PATCHER_REHOOK:
		# Wind-up: the hook spins faster as it's about to fly.
		var t := 1.0 - wind_left / T.PATCHER_REHOOK
		var spin := Time.get_ticks_msec() * 0.001 * (4.0 + 14.0 * t)
		var hook_at := winch + Vector2(16.0 + 8.0 * t, 0.0).rotated(spin)
		draw_line(winch, hook_at, cable_col, 1.5)
		draw_circle(hook_at, 4.0, Color(0.95, 0.75, 0.25))
		draw_arc(winch, 26.0, -PI * 0.5, -PI * 0.5 + TAU * t, 24, Color(0.95, 0.75, 0.25, 0.8), 2.0)
	if reviving != null and is_instance_valid(reviving):
		var at := to_local(reviving.global_position)
		var t := 1.0 - revive_left / T.PATCHER_REVIVE_TIME
		draw_line(winch, at, cable_col, 1.5)
		draw_arc(at, 44.0, -PI * 0.5, -PI * 0.5 + TAU * t, 32, Color(0.35, 0.95, 0.5, 0.9), 4.0)
