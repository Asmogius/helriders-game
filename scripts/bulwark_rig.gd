extends "res://scripts/enemy_rig.gd"
## Bulwark: heavy enemy rammer (DESIGN §8; numbers approved in the
## "Helriders: Bulwark Draft" doc). A relentless bull: it always drives at
## where you're heading, never telegraphs, and turns slowly, so you beat it by
## out-turning it and shooting its sides. After ramming you it backs off for a
## moment, then comes again. A light gun fixed forward plinks you while it
## lines up. Its front plate is very heavy (§14 defense layers; it used to
## halve hits on the front), and bullets on it throw grey sparks.

## Pre-ram wind-up, Art's contract (docs/ART_PIPELINE.md on PR #15):
## is_winding_up(), windup_progress() 0..1, and windup_started. windup_ended
## fires when the wind-up stops (it charges, or a ram, wreck or getting stuck
## cuts it short). The Convoy Lead extends this script and inherits it all.
signal windup_started
signal windup_ended
signal rammed_player   # it hit you and backs off (ram impact sound)

const BACKOFF_STEER := 0.5   # radians off straight back while reversing

var backoffs := 0            # times it rammed you and backed off (tests)
var front_hits := 0          # hits its armor blunted (tests)
var charges := 0             # charges started (tests)
var windups := 0             # wind-up telegraphs shown (tests)
var _charge_dir := Vector2.ZERO


## Voxel art: art/sprites/bulwark.json (see docs/ART_PIPELINE.md).
func art_id() -> String:
	return "bulwark"


## Pre-ram wind-up glow (art contract, docs/ART_PIPELINE.md): the plow heats
## to bright enemy red while the rig winds up, pulsing faster as it nears 1.
## Read defensively: only if this rig provides is_winding_up() /
## windup_progress() (Content's wind-up state); the optional windup_started
## signal restarts the pulse. Without them no glow is shown.
const WINDUP_LAYER := "windup_glow"
var _windup_t0 := 0.0


func _has_windup_art() -> bool:
	return _hull_art != null and (_hull_art.meta.get("layers", {}) as Dictionary).has(WINDUP_LAYER)


func art_winding_up() -> bool:
	return not is_wrecked and has_method("is_winding_up") and bool(call("is_winding_up"))


func art_windup_progress() -> float:
	if not art_winding_up():
		return 0.0
	if has_method("windup_progress"):
		return clampf(float(call("windup_progress")), 0.0, 1.0)
	return 1.0


func art_layers() -> Array[String]:
	var ids := super()
	if _has_windup_art() and art_winding_up():
		ids.append(WINDUP_LAYER)
	return ids


func art_layer_modulate(id: String) -> Color:
	if id != WINDUP_LAYER:
		return super(id)
	var p := art_windup_progress()
	var t := Time.get_ticks_msec() * 0.001 - _windup_t0
	var pulse := 0.5 + 0.5 * sin(t * TAU * lerpf(2.0, 7.0, p))   # 2 Hz -> 7 Hz
	var a := clampf(lerpf(0.25, 0.7, p) + lerpf(0.25, 0.3, p) * pulse, 0.0, 1.0)
	return Color(1.0, 1.0, 1.0, a)


func _on_windup_started() -> void:
	_windup_t0 = Time.get_ticks_msec() * 0.001


func _ready() -> void:
	super()
	# Once per rig, also for subclasses (the Convoy) that call super().
	if has_signal("windup_started") and not is_connected("windup_started", _on_windup_started):
		connect("windup_started", _on_windup_started)


const GUNNER_SCRIPT := preload("res://scripts/gunner_rig.gd")

var screening := false   # body-blocking for an ally right now
var screens := 0          # times it started screening (tests)


func _init() -> void:
	team = BulletPool.TEAM_ENEMY
	apply_stats(T.BULWARK)
	body_len = 84.0
	body_wid = 46.0
	lock_priority = 3
	lock_radius = 50.0


## True during the wind-up before a charge (Art's warning glow).
func is_winding_up() -> bool:
	return mode == Mode.WINDUP and not is_wrecked


## How far along the wind-up is, 0..1 (0 when not winding up).
func windup_progress() -> float:
	if not is_winding_up():
		return 0.0
	return clampf(1.0 - _mode_time / T.BULWARK_WINDUP, 0.0, 1.0)


func _physics_process(delta: float) -> void:
	var was_winding := mode == Mode.WINDUP
	super(delta)
	if was_winding and not is_winding_up():
		windup_ended.emit()
		if _music() != null:
			_music().stop_windup(self)
	if is_wrecked or player == null or mode == Mode.UNSTICK:
		return
	# Rammed the player this tick: back off, then come again.
	for i in get_slide_collision_count():
		if get_slide_collision(i).get_collider() == player and mode != Mode.PASS and mode != Mode.WINDUP:
			mode = Mode.PASS   # PASS doubles as "backing off" for the Bulwark
			_mode_time = T.BULWARK_BACKOFF
			_side = 1.0 if randf() < 0.5 else -1.0
			backoffs += 1
			rammed_player.emit()
			if _music() != null:
				_music().play_sfx("ram_impact")
			break


func _think(delta: float) -> void:
	_mode_time -= delta
	var to_player := player.global_position - global_position
	var dist := to_player.length()
	var forward := Vector2.RIGHT.rotated(rotation)
	var player_down: bool = player.get("is_wrecked")

	_sight_timer -= delta
	if _sight_timer <= 0.0:
		_sight_timer = 0.2
		_sees_player = _has_los(player.global_position)

	var goal := Vector2.ZERO
	var throttle := 1.0
	match mode:
		Mode.ATTACK:
			# Aim at where the player is heading, not where they are.
			var player_vel: Vector2 = player.get("velocity")
			goal = (player.global_position + player_vel * clampf(dist / max_speed, 0.0, 0.5) - global_position).normalized()
			# Screening: a Gunner Rig or Patcher close by, and you closer to it
			# than to us: drive in between and body-block.
			var ward := _ward(dist)
			screening = ward != null
			if screening:
				var block := ward.global_position + (player.global_position - ward.global_position).normalized() * T.BULWARK_SCREEN_GAP
				goal = (block - global_position).normalized()
			if player_down:
				throttle = 0.3
			elif _sees_player and dist >= float(T.BULWARK_CHARGE_RANGE[0]) and dist <= float(T.BULWARK_CHARGE_RANGE[1]) \
					and absf(forward.angle_to(to_player)) <= T.BULWARK_CHARGE_CONE and shutdown_left <= 0.0:
				# Lined up: wind up (the telegraph), then charge.
				mode = Mode.WINDUP
				_mode_time = T.BULWARK_WINDUP
				windups += 1
				windup_started.emit()
				if _music() != null:
					_music().start_windup(self)   # engine roar, pitch follows windup_progress()
				queue_redraw()
		Mode.WINDUP:
			# Engine roar and headlight flare: it holds and keeps its nose on you.
			goal = to_player.normalized()   # keeps rolling in, nose on you
			if _mode_time <= 0.0:
				mode = Mode.CHARGE
				_mode_time = T.BULWARK_CHARGE_TIME
				_charge_dir = forward
				charges += 1
		Mode.CHARGE:
			# Straight line at top speed; it doesn't steer, so it can overshoot.
			goal = _charge_dir
			if _mode_time <= 0.0:
				mode = Mode.RECOVER   # missed: a slow turn with its sides open
				_mode_time = T.BULWARK_RECOVER
		Mode.RECOVER:
			goal = to_player.normalized()
			throttle = 0.25
			if _mode_time <= 0.0:
				mode = Mode.ATTACK
		Mode.PASS:
			# Backing off after a ram: stick behind us reverses a slow rig.
			goal = -forward.rotated(_side * BACKOFF_STEER)
			if _mode_time <= 0.0:
				mode = Mode.ATTACK
		Mode.UNSTICK:
			goal = -forward.rotated(_side * 0.6)
			if _mode_time <= 0.0:
				mode = Mode.ATTACK

	if mode == Mode.ATTACK or mode == Mode.RECOVER:
		goal = _avoid_walls(goal, forward)
	drive_input = goal * throttle

	fire_trigger = (
		(mode == Mode.ATTACK or mode == Mode.WINDUP)   # the gun works only while lining up
		and not player_down
		and _sees_player
		and dist < gun_range()
		and absf(forward.angle_to(to_player)) < FIRE_CONE
	)

	# Wedged against a wall (not the player): back out.
	if (mode == Mode.ATTACK or mode == Mode.CHARGE) and get_real_velocity().length() < 30.0 and dist > body_len and _mode_time < T.BULWARK_CHARGE_TIME - 0.4:
		_stuck_time += delta
		if _stuck_time > 1.0:
			mode = Mode.UNSTICK
			_mode_time = 1.0
			_side = 1.0 if randf() < 0.5 else -1.0
			_stuck_time = 0.0
	else:
		_stuck_time = 0.0


## True if a hit coming from world point `from` lands on the armored front.
## The ally it should screen (a Gunner Rig or Patcher within range that you're
## closer to than you are to this Bulwark), or null.
func _ward(dist_to_player: float) -> Node2D:
	var parent := get_parent()
	if parent == null or player == null:
		return null
	for n in parent.get_children():
		if n == self or bool(n.get("is_wrecked")) or not (n.has_method("pop_hook") or n.get_script() == GUNNER_SCRIPT):
			continue
		var ally := n as Node2D
		if ally.global_position.distance_to(global_position) <= T.BULWARK_SCREEN_RANGE \
				and player.global_position.distance_to(ally.global_position) < dist_to_player:
			if not screening:
				screens += 1
			return ally
	return null


func is_front(from: Vector2) -> bool:
	var forward := Vector2.RIGHT.rotated(rotation)
	return absf(forward.angle_to(from - global_position)) < T.BULWARK_FRONT_ARC


## Bullets hitting the armored front throw grey sparks (bullet_pool.gd).
## (While the front plate holds.)
func deflects(at: Vector2) -> bool:
	return not is_wrecked and is_front(at) and facing_armor[FRONT] > 0.0


func take_hit(damage: float, impulse: Vector2, cause := "shot", dtype := "") -> void:
	# The impulse points the way the hit travels, so it came from behind it.
	if impulse != Vector2.ZERO and is_front(global_position - impulse.normalized() * 100.0):
		front_hits += 1
	super(damage, impulse, cause, dtype)


func _draw() -> void:
	if _hull_art != null:
		return   # the voxel sheet draws the rig
	var half_l := body_len * 0.5
	var half_w := body_wid * 0.5
	var hull := Color(0.2, 0.21, 0.22)
	if is_wrecked:
		hull = Color(0.09, 0.085, 0.08)
	elif _flash > 0.0:
		hull = hull.lerp(Color(1.0, 0.85, 0.7), _flash * 0.6)

	# Six wheels: heavy.
	var tyre := Color(0.06, 0.06, 0.065)
	for sx: float in [-0.62, 0.0, 0.62]:
		for sy: float in [-1.0, 1.0]:
			draw_rect(Rect2(Vector2(sx * half_l - 10.0, sy * half_w - 7.0), Vector2(20.0, 14.0)), tyre)
	# Slab hull.
	draw_rect(Rect2(-half_l, -half_w + 3.0, body_len - 12.0, body_wid - 6.0), hull)
	if is_wrecked:
		draw_rect(Rect2(-14.0, -8.0, 24.0, 16.0), Color(0.05, 0.04, 0.04))
		return
	# Armor bands.
	for k in 3:
		draw_rect(Rect2(-half_l + 8.0 + k * 18.0, -half_w + 3.0, 4.0, body_wid - 6.0), hull.darkened(0.35))
	# Wide spiked plow: the armored front.
	var plow := Color(0.38, 0.33, 0.28)
	draw_colored_polygon(PackedVector2Array([
		Vector2(half_l - 14.0, -half_w - 4.0), Vector2(half_l + 2.0, -half_w + 6.0),
		Vector2(half_l + 2.0, half_w - 6.0), Vector2(half_l - 14.0, half_w + 4.0),
	]), plow)
	for k in 5:
		var y := -half_w + 4.0 + k * (body_wid - 8.0) / 4.0
		draw_colored_polygon(PackedVector2Array([Vector2(half_l + 2.0, y - 3.0), Vector2(half_l + 11.0, y), Vector2(half_l + 2.0, y + 3.0)]), Color(0.72, 0.68, 0.6))
	# The light gun, centered on the nose.
	draw_rect(Rect2(half_l - 24.0, -2.5, 26.0, 5.0), Color(0.12, 0.12, 0.13))
	if vuln_left > 0.0:
		draw_arc(Vector2.ZERO, half_l + 10.0, 0.0, TAU, 28, Color(0.95, 0.3, 0.25, 0.85), 2.5)
	# Cab, and red lights: enemies read red.
	draw_rect(Rect2(-10.0, -9.0, 22.0, 18.0), hull.darkened(0.45))
	draw_rect(Rect2(-half_l + 4.0, -half_w + 4.0, body_len - 30.0, 2.0), T.COL_ENEMY)
	draw_rect(Rect2(-half_l + 4.0, half_w - 6.0, body_len - 30.0, 2.0), T.COL_ENEMY)
	draw_rect(Rect2(-half_l - 1.0, -6.0, 3.0, 12.0), T.COL_ENEMY)
	draw_rect(Rect2(half_l - 18.0, -half_w + 2.0, 4.0, 5.0), T.COL_ENEMY)
	draw_rect(Rect2(half_l - 18.0, half_w - 7.0, 4.0, 5.0), T.COL_ENEMY)
	if mode == Mode.WINDUP:
		# Charge telegraph: headlights flare ahead of the plow.
		var flare := Color(1.0, 0.95, 0.75, 0.75)
		for sy: float in [-1.0, 1.0]:
			draw_circle(Vector2(half_l + 6.0, sy * (half_w - 8.0)), 9.0, flare)
		draw_colored_polygon(PackedVector2Array([Vector2(half_l + 6.0, -half_w), Vector2(half_l + 120.0, -half_w - 30.0),
			Vector2(half_l + 120.0, half_w + 30.0), Vector2(half_l + 6.0, half_w)]), Color(1.0, 0.95, 0.75, 0.18))


func _music() -> Node:
	return get_node_or_null("/root/MusicManager")
