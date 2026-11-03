extends "res://scripts/gunner_rig.gd"
## Scrapper: fast, light enemy trap layer (DESIGN §8; agreed with the owner).
## It weaves back and forth across the road ahead of you, 250-400 px out, and
## every 6 s drops a trap behind it: a mine (40 damage to your rig, zombies set
## it off too), then an oil slick (you slide like on slime), alternating. One
## weak turret plinks at you. Hunt it down before the street fills with traps.
## Shares the Gunner Rig's turret aiming; only the driving and traps differ.

var enemy_mines: Node2D       # MinePool with enemy = true (mission sets it)
var traps_dropped := 0        # tests
var next_trap := "mine"       # alternates "mine" / "oil"

var _trap_timer := 0.0
var _weave := 1.0             # which side of your path it's crossing to


func _init() -> void:
	team = BulletPool.TEAM_ENEMY
	apply_stats(T.SCRAPPER)
	body_len = 62.0
	body_wid = 32.0
	lock_priority = 3
	lock_radius = 40.0
	self_defense = false
	_trap_timer = T.SCRAPPER_TRAP_EVERY * 0.5


func _enter_tree() -> void:
	super()
	_weave = 1.0 if randf() < 0.5 else -1.0


func _physics_process(delta: float) -> void:
	super(delta)
	if is_wrecked or player == null or bool(player.get("is_wrecked")):
		return
	_trap_timer -= delta
	if _trap_timer <= 0.0:
		_trap_timer = T.SCRAPPER_TRAP_EVERY
		drop_trap()


## Drop the next trap behind the rig. Returns what it dropped.
func drop_trap() -> String:
	var back := -Vector2.RIGHT.rotated(rotation)
	var kind := next_trap
	if kind == "mine":
		if enemy_mines != null:
			enemy_mines.call("drop", global_position + back * (body_len * 0.5 + 20.0), T.SCRAPPER_MINE_DAMAGE,
				T.SCRAPPER_MINE_RADIUS, T.SCRAPPER_MINE_ARM, T.SCRAPPER_MINE_LIFE)
		next_trap = "oil"
	else:
		if hazards != null:
			hazards.call("add_oil", global_position + back * (body_len * 0.5 + T.OIL_RADIUS * 0.6), T.OIL_RADIUS, T.OIL_TIME_SCRAPPER)
		next_trap = "mine"
	traps_dropped += 1
	return kind


## Weave across the road ahead of the player, inside 250-400 px.
func _steer(_delta: float, engaging: bool, to_player: Vector2, forward: Vector2) -> Vector2:
	if mode == Mode.UNSTICK:
		return -forward.rotated(_side * 0.6)
	var dist := to_player.length()
	if not engaging:
		return to_player.normalized() * 0.5 if dist > T.SCRAPPER_RANGE_MAX else Vector2.ZERO
	if dist < T.SCRAPPER_RANGE_MIN:
		return (-to_player.normalized()).rotated(_weave * 0.6)
	# The point it's crossing to: ahead of the player, off to one side.
	var player_vel: Vector2 = player.get("velocity")
	var heading := player_vel.normalized() if player_vel.length() > 60.0 else Vector2.RIGHT.rotated(player.rotation)
	var ahead := player.global_position + heading * 320.0 + heading.orthogonal() * _weave * 260.0
	var to_ahead := ahead - global_position
	if to_ahead.length() < 110.0:
		_weave = -_weave   # made the crossing: go back the other way
	return to_ahead.normalized()


func _draw() -> void:
	var half_l := body_len * 0.5
	var half_w := body_wid * 0.5
	var hull := Color(0.33, 0.27, 0.18)
	if is_wrecked:
		hull = Color(0.1, 0.09, 0.085)
	elif _flash > 0.0:
		hull = hull.lerp(Color(1.0, 0.85, 0.7), _flash * 0.6)
	var tyre := Color(0.07, 0.07, 0.075)
	for sx: float in [-1.0, 1.0]:
		for sy: float in [-1.0, 1.0]:
			draw_rect(Rect2(Vector2(sx * half_l * 0.6 - 8.0, sy * half_w - 5.0), Vector2(16.0, 10.0)), tyre)
	# Light buggy: a short wedge with an open tray on the back.
	draw_colored_polygon(PackedVector2Array([
		Vector2(-half_l, -half_w + 3.0), Vector2(half_l - 8.0, -half_w + 5.0),
		Vector2(half_l, 0.0), Vector2(half_l - 8.0, half_w - 5.0), Vector2(-half_l, half_w - 3.0),
	]), hull)
	if is_wrecked:
		draw_rect(Rect2(-10.0, -6.0, 18.0, 12.0), Color(0.05, 0.04, 0.04))
		return
	draw_rect(Rect2(-half_l + 2.0, -half_w + 6.0, 20.0, body_wid - 12.0), hull.darkened(0.4))   # the tray
	# Its cargo: a mine and an oil drum.
	draw_circle(Vector2(-half_l + 8.0, -4.0), 4.0, Color(0.4, 0.2, 0.15))
	draw_circle(Vector2(-half_l + 16.0, 4.0), 4.5, Color(0.08, 0.08, 0.09))
	draw_rect(Rect2(-half_l + 4.0, -half_w + 3.0, body_len - 16.0, 2.0), T.COL_ENEMY)
	draw_rect(Rect2(-half_l + 4.0, half_w - 5.0, body_len - 16.0, 2.0), T.COL_ENEMY)
	draw_rect(Rect2(-half_l - 1.0, -4.0, 3.0, 8.0), T.COL_ENEMY)
	if vuln_left > 0.0:
		draw_arc(Vector2.ZERO, half_l + 8.0, 0.0, TAU, 28, Color(0.95, 0.3, 0.25, 0.85), 2.5)
