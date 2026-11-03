extends "res://scripts/vehicle.gd"
## The Convoy Lead's trailer: a short box on a hitch behind the cab, with the
## heavy turret on top (DESIGN §8; agreed with the owner). It doesn't drive:
## each tick it swings in behind the hitch, so it sweeps wide on turns. It has
## its own armor; shot off, it stays where it fell as a burning wreck and the
## cab drives on lighter. The turret can't fire forward through the cab (the
## 90 degrees facing the hitch): the cab's nose guns cover that.
## A top-level child of the cab, so it isn't one of the mission's rigs on its
## own (it doesn't count toward the rig cap); the mission adds it to lock-on.

var cab: Node2D               # the ConvoyRig towing it
var player: Node2D            # the player's rig (the cab hands it over)
var blocked := false          # target is in the arc the cab hides (tests)

var _sight_timer := 0.0
var _sees_player := false


func _init() -> void:
	team = BulletPool.TEAM_ENEMY
	apply_stats(T.CONVOY_TRAILER)
	body_len = 70.0
	body_wid = 40.0
	lock_priority = 3
	lock_radius = 44.0


func _physics_process(delta: float) -> void:
	if is_wrecked or cab == null:
		super(delta)   # a dropped trailer just burns where it is
		return
	_follow(delta)
	if vuln_left > 0.0:
		vuln_left -= delta
		if vuln_left <= 0.0:
			queue_redraw()
	_aim(delta)
	_weapons(delta)
	if _flash > 0.0:
		_flash = maxf(_flash - delta * 5.0, 0.0)
		queue_redraw()


## Swing in behind the cab's hitch, pulled along like a real trailer.
func _follow(delta: float) -> void:
	var cab_len := float(cab.get("body_len"))
	var hitch := cab.global_position - Vector2.RIGHT.rotated(cab.rotation) * (cab_len * 0.5)
	var to_hitch := hitch - global_position
	var dir := to_hitch.normalized() if to_hitch.length() > 1.0 else Vector2.RIGHT.rotated(cab.rotation)
	# A hitch only folds so far: past that the trailer is dragged round with the cab.
	var bend := angle_difference(cab.rotation, dir.angle())
	if absf(bend) > T.CONVOY_MAX_JACKKNIFE:
		dir = Vector2.RIGHT.rotated(cab.rotation + signf(bend) * T.CONVOY_MAX_JACKKNIFE)
	var before := global_position
	global_position = hitch - dir * (body_len * 0.5 + T.CONVOY_HITCH_GAP)
	rotation = dir.angle()
	velocity = (global_position - before) / maxf(delta, 0.001)


## Put the trailer straight behind the cab (when it rolls in).
func hitch_up() -> void:
	var back := -Vector2.RIGHT.rotated(cab.rotation)
	rotation = cab.rotation
	global_position = cab.global_position + back * (float(cab.get("body_len")) * 0.5 + T.CONVOY_HITCH_GAP + body_len * 0.5)


func _aim(delta: float) -> void:
	fire_trigger = false
	aim_input = Vector2.ZERO
	blocked = false
	if player == null or bool(player.get("is_wrecked")) or _turrets.is_empty() or _turrets[0] == null:
		return
	_sight_timer -= delta
	if _sight_timer <= 0.0:
		_sight_timer = 0.2
		_sees_player = _has_los(player.global_position)
	var turret := _turrets[0]
	var want := (_lead_point(player, bullet_speed) - turret.global_position).angle()
	if not _sees_player or turret.global_position.distance_to(player.global_position) > gun_range():
		return
	# The cab is in the way: swing to the edge of the clear arc and hold fire.
	var off := angle_difference(rotation, want)
	if absf(off) < T.CONVOY_TURRET_BLOCK:
		blocked = true
		aim_input = Vector2.RIGHT.rotated(rotation + signf(off if off != 0.0 else 1.0) * T.CONVOY_TURRET_BLOCK) * 0.4
		return
	var on_target := absf(angle_difference(turret.global_rotation, want)) < T.GUNNER_FIRE_CONE
	aim_input = Vector2.RIGHT.rotated(want) * (1.0 if on_target else 0.4)


func _draw() -> void:
	var half_l := body_len * 0.5
	var half_w := body_wid * 0.5
	var box := Color(0.3, 0.26, 0.22)
	if is_wrecked:
		box = Color(0.1, 0.09, 0.085)
	elif _flash > 0.0:
		box = box.lerp(Color(1.0, 0.85, 0.7), _flash * 0.6)
	var tyre := Color(0.06, 0.06, 0.065)
	for sx: float in [-0.55, -0.25]:
		for sy: float in [-1.0, 1.0]:
			draw_rect(Rect2(Vector2(sx * body_len - 9.0, sy * half_w - 5.0), Vector2(18.0, 10.0)), tyre)
	draw_rect(Rect2(-half_l, -half_w + 2.0, body_len, body_wid - 4.0), box)
	draw_rect(Rect2(half_l - 4.0, -4.0, 10.0, 8.0), Color(0.15, 0.15, 0.16))   # the hitch bar
	if is_wrecked:
		draw_rect(Rect2(-12.0, -8.0, 22.0, 16.0), Color(0.05, 0.04, 0.04))
		return
	# Riveted sides and red lights.
	for i in 4:
		draw_rect(Rect2(-half_l + 6.0 + i * 16.0, -half_w + 4.0, 3.0, body_wid - 8.0), box.darkened(0.25))
	draw_rect(Rect2(-half_l - 1.0, -half_w + 4.0, 3.0, 6.0), T.COL_ENEMY)
	draw_rect(Rect2(-half_l - 1.0, half_w - 10.0, 3.0, 6.0), T.COL_ENEMY)
	if vuln_left > 0.0:
		draw_arc(Vector2.ZERO, half_l + 8.0, 0.0, TAU, 28, Color(0.95, 0.3, 0.25, 0.85), 2.5)
