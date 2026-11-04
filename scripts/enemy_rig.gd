extends "res://scripts/vehicle.gd"
## Outrider: light enemy flanker with twin guns fixed forward. Same driving
## model as the player's rig; this script just decides the stick inputs.
## It makes strafing passes: lines up on you, fires, overshoots, loops back.
## It rams zombies in its way and its bullets hit them too.

enum Mode { ATTACK, PASS, UNSTICK }

const FEELER_ANGLE := 0.45   # radians either side of the nose
const PASS_DISTANCE := 260.0 # start peeling off this close to the player
const FIRE_CONE := 0.22      # radians off the nose it will still shoot at

var player: Node2D            # the player's rig
var mode := Mode.ATTACK
var elite_name := ""         # set on a Hunt target; empty for a regular Outrider

var _mode_time := 0.0
var _side := 1.0
var _stuck_time := 0.0
var _sight_timer := 0.0
var _sees_player := false


func _init() -> void:
	team = BulletPool.TEAM_ENEMY
	apply_stats(T.OUTRIDER)
	body_len = 68.0
	body_wid = 30.0
	lock_priority = 3


## Turn this rig into a named Hunt target: tougher, harder-hitting, gold-marked,
## and first in line for the player's lock after a Hunter on the hull.
func make_elite(title: String, armor_mult: float, damage_mult: float) -> void:
	var s: Dictionary = T.OUTRIDER.duplicate()
	for k: String in ["armor", "hp", "front", "side", "rear"]:   # every layer (§14)
		s[k] = float(s[k]) * armor_mult
	s.bullet_damage = float(s.bullet_damage) * damage_mult
	apply_stats(s)
	elite_name = title
	lock_priority = 4
	lock_radius = 46.0
	body_len = 74.0
	body_wid = 32.0
	if is_inside_tree():
		_update_art()   # a rig with art picks up the gold trim layer now


func is_elite() -> bool:
	return elite_name != ""


func _physics_process(delta: float) -> void:
	if not is_wrecked and player != null:
		_think(delta)
	super(delta)


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
			var player_vel: Vector2 = player.get("velocity")
			var lead := player.global_position + player_vel * clampf(dist / bullet_speed, 0.0, 0.6)
			goal = (lead - global_position).normalized()
			if player_down:
				throttle = 0.35  # circle the wreck
			elif dist < PASS_DISTANCE:
				# Close enough: peel off to one side and come around for another
				# run. It's a flanker, not a rammer; that's the Bulwark's job.
				mode = Mode.PASS
				_mode_time = randf_range(0.9, 1.4)
				_side = 1.0 if forward.cross(to_player) < 0.0 else -1.0
		Mode.PASS:
			goal = forward.rotated(_side * 1.0)
			if _mode_time <= 0.0:
				mode = Mode.ATTACK
		Mode.UNSTICK:
			# Pointing the stick behind a slow rig makes it reverse.
			goal = -forward.rotated(_side * 0.6)
			if _mode_time <= 0.0:
				mode = Mode.ATTACK

	if mode != Mode.UNSTICK:
		goal = _avoid_walls(goal, forward)
	drive_input = goal * throttle

	fire_trigger = (
		mode != Mode.UNSTICK
		and not player_down
		and _sees_player
		and dist < gun_range()
		and absf(forward.angle_to(to_player)) < FIRE_CONE
	)

	# Wedged against something: back out.
	if mode != Mode.UNSTICK and get_real_velocity().length() < 40.0:
		_stuck_time += delta
		if _stuck_time > 0.8:
			mode = Mode.UNSTICK
			_mode_time = 0.9
			_side = 1.0 if randf() < 0.5 else -1.0
			_stuck_time = 0.0
	else:
		_stuck_time = 0.0


## Two feelers off the nose; steer away from whichever one touches a wall.
func _avoid_walls(goal: Vector2, forward: Vector2) -> Vector2:
	var reach := 90.0 + velocity.length() * 0.35
	var space := get_world_2d().direct_space_state
	var steer := 0.0
	for s: float in [-1.0, 1.0]:
		_ray.from = global_position
		_ray.to = global_position + forward.rotated(s * FEELER_ANGLE) * reach
		if not space.intersect_ray(_ray).is_empty():
			steer -= s
	if steer == 0.0:
		return goal
	return forward.rotated(steer * 1.1)


## The art id for this rig: the plain Outrider is "outrider"; a subclass
## returns its own id (e.g. "torcher") and wears art/sprites/<id>.json once it
## exists. "" keeps the code-drawn look.
func art_id() -> String:
	return "outrider" if get_script() == preload("res://scripts/enemy_rig.gd") else ""


func _art_meta_path() -> String:
	return art_path(art_id())


## Enemy hulls carry no player parts; a Hunt elite wears the gold trim layer.
func art_layers() -> Array[String]:
	var ids: Array[String] = []
	if _hull_art != null and is_elite() and (_hull_art.meta.get("layers", {}) as Dictionary).has("elite_trim"):
		ids.append("elite_trim")
	return ids


func _draw_art_overlay() -> void:
	var o := _art_overlay
	if vuln_left > 0.0:
		o.draw_arc(Vector2.ZERO, body_len * 0.5 + 8.0, 0.0, TAU, 28, Color(0.95, 0.3, 0.25, 0.85), 2.5)
	if is_elite() and not art_layers().has("elite_trim"):
		o.draw_rect(Rect2(-body_len * 0.5 + 2.0, -2.0, body_len - 14.0, 4.0), T.COL_ELITE)


func _draw() -> void:
	var half_l := body_len * 0.5
	var half_w := body_wid * 0.5
	if _hull_art != null:
		return   # the voxel sheet draws the rig; marks go in _draw_art_overlay

	var hull := Color(0.3, 0.2, 0.16)
	if is_wrecked:
		hull = Color(0.1, 0.09, 0.085)
	elif _flash > 0.0:
		hull = hull.lerp(Color(1.0, 0.85, 0.7), _flash * 0.6)

	var tyre := Color(0.07, 0.07, 0.075)
	for sx: float in [-1.0, 1.0]:
		for sy: float in [-1.0, 1.0]:
			draw_rect(Rect2(Vector2(sx * half_l * 0.6 - 9.0, sy * half_w - 5.0), Vector2(18.0, 10.0)), tyre)
	# Long, low wedge.
	draw_colored_polygon(PackedVector2Array([
		Vector2(-half_l, -half_w + 2.0), Vector2(half_l - 10.0, -half_w + 4.0),
		Vector2(half_l, 0.0), Vector2(half_l - 10.0, half_w - 4.0), Vector2(-half_l, half_w - 2.0),
	]), hull)
	if is_wrecked:
		draw_rect(Rect2(-12.0, -6.0, 20.0, 12.0), Color(0.05, 0.04, 0.04))
		return
	# Twin guns on the nose.
	draw_rect(Rect2(half_l - 16.0, -11.0, 22.0, 4.0), Color(0.15, 0.15, 0.16))
	draw_rect(Rect2(half_l - 16.0, 7.0, 22.0, 4.0), Color(0.15, 0.15, 0.16))
	# Cockpit and red running lights: enemies read red, the player reads cyan.
	draw_rect(Rect2(-8.0, -6.0, 18.0, 12.0), hull.darkened(0.35))
	draw_rect(Rect2(-half_l + 4.0, -half_w + 3.0, body_len - 22.0, 2.0), T.COL_ENEMY)
	draw_rect(Rect2(-half_l + 4.0, half_w - 5.0, body_len - 22.0, 2.0), T.COL_ENEMY)
	draw_rect(Rect2(-half_l - 1.0, -4.0, 3.0, 8.0), T.COL_ENEMY)
	if vuln_left > 0.0:
		draw_arc(Vector2.ZERO, half_l + 8.0, 0.0, TAU, 28, Color(0.95, 0.3, 0.25, 0.85), 2.5)
	# A Hunt target wears gold: a stripe down the spine and a nose chevron.
	if is_elite():
		draw_rect(Rect2(-half_l + 2.0, -2.0, body_len - 14.0, 4.0), T.COL_ELITE)
		draw_colored_polygon(PackedVector2Array([Vector2(half_l - 22.0, -6.0), Vector2(half_l - 12.0, 0.0), Vector2(half_l - 22.0, 6.0)]), T.COL_ELITE)
	# Spikes along the flanks.
	for i in 3:
		var x := -half_l + 14.0 + i * 14.0
		draw_colored_polygon(PackedVector2Array([Vector2(x, -half_w + 1.0), Vector2(x + 6.0, -half_w - 6.0), Vector2(x + 8.0, -half_w + 1.0)]), T.COL_RUST)
		draw_colored_polygon(PackedVector2Array([Vector2(x, half_w - 1.0), Vector2(x + 6.0, half_w + 6.0), Vector2(x + 8.0, half_w - 1.0)]), T.COL_RUST)
