extends "res://scripts/bulwark_rig.gd"
## Convoy Lead: elite enemy rig (DESIGN §8; agreed with the owner). An armored
## semi with a ram, towing a short trailer with a heavy turret
## (convoy_trailer.gd). The cab hunts and rams like a slower, wider-turning
## Bulwark (the ram takes half damage, from bulwark_rig.gd); two small guns on
## the nose cover the front, since the trailer turret can't fire through the
## cab. Shoot the trailer off and the cab drives on lighter and faster; wreck
## the cab and the trailer goes with it. Counts as one rig toward the cap.

const ConvoyTrailer := preload("res://scripts/convoy_trailer.gd")

var trailer: ConvoyTrailer
var unhitched := false        # lost its trailer


## Voxel art: art/sprites/convoy.json (see docs/ART_PIPELINE.md).
func art_id() -> String:
	return "convoy"


func _init() -> void:
	team = BulletPool.TEAM_ENEMY
	apply_stats(T.CONVOY)
	body_len = 96.0
	body_wid = 46.0
	lock_priority = 3
	lock_radius = 56.0
	trailer = ConvoyTrailer.new()
	trailer.cab = self
	trailer.top_level = true
	add_child(trailer)
	trailer.wrecked.connect(_on_trailer_wrecked)


func _ready() -> void:
	super()
	trailer.player = player
	trailer.bullets = bullets
	trailer.fx = fx
	add_collision_exception_with(trailer)
	trailer.add_collision_exception_with(self)
	trailer.hitch_up()


func _on_trailer_wrecked() -> void:
	if is_wrecked or unhitched:
		return
	unhitched = true
	trailer.cab = null   # it stays where it fell
	max_speed *= T.CONVOY_UNHITCHED_SPEED
	acceleration *= T.CONVOY_UNHITCHED_ACCEL
	turn_rate *= T.CONVOY_UNHITCHED_TURN


## Wrecking the cab finishes the trailer too (no separate payout).
func _wreck() -> void:
	super()
	if not trailer.is_wrecked:
		trailer.call("_wreck")


func _draw() -> void:
	if _hull_art != null:
		return   # the voxel sheet draws the rig
	var half_l := body_len * 0.5
	var half_w := body_wid * 0.5
	var hull := Color(0.24, 0.22, 0.21)
	if is_wrecked:
		hull = Color(0.09, 0.085, 0.08)
	elif _flash > 0.0:
		hull = hull.lerp(Color(1.0, 0.85, 0.7), _flash * 0.6)
	var tyre := Color(0.06, 0.06, 0.065)
	for sx: float in [-0.62, -0.3, 0.42]:
		for sy: float in [-1.0, 1.0]:
			draw_rect(Rect2(Vector2(sx * body_len - 10.0, sy * half_w - 6.0), Vector2(20.0, 12.0)), tyre)
	# Chassis rails, then the cab up front.
	draw_rect(Rect2(-half_l, -half_w + 8.0, body_len - 20.0, body_wid - 16.0), hull.darkened(0.3))
	draw_rect(Rect2(half_l - 46.0, -half_w + 2.0, 36.0, body_wid - 4.0), hull)
	draw_rect(Rect2(half_l - 40.0, -half_w + 6.0, 10.0, body_wid - 12.0), Color(0.12, 0.13, 0.15))   # windshield
	# Exhaust stacks behind the cab.
	draw_circle(Vector2(half_l - 50.0, -half_w + 6.0), 4.0, Color(0.15, 0.15, 0.16))
	draw_circle(Vector2(half_l - 50.0, half_w - 6.0), 4.0, Color(0.15, 0.15, 0.16))
	if is_wrecked:
		draw_rect(Rect2(half_l - 40.0, -10.0, 26.0, 20.0), Color(0.05, 0.04, 0.04))
		return
	# The ram: a wide steel plow across the nose.
	draw_colored_polygon(PackedVector2Array([
		Vector2(half_l - 10.0, -half_w - 3.0), Vector2(half_l + 4.0, -half_w + 6.0), Vector2(half_l + 10.0, 0.0),
		Vector2(half_l + 4.0, half_w - 6.0), Vector2(half_l - 10.0, half_w + 3.0),
	]), T.COL_STEEL)
	for i in 4:
		var y := -half_w + 8.0 + i * (body_wid - 16.0) / 3.0
		draw_line(Vector2(half_l - 6.0, y), Vector2(half_l + 6.0, y * 0.5), T.COL_STEEL.darkened(0.35), 2.0)
	# Two small guns on the nose.
	draw_rect(Rect2(half_l - 16.0, -half_w + 1.0, 18.0, 4.0), Color(0.15, 0.15, 0.16))
	draw_rect(Rect2(half_l - 16.0, half_w - 5.0, 18.0, 4.0), Color(0.15, 0.15, 0.16))
	# Red running lights.
	draw_rect(Rect2(half_l - 44.0, -half_w + 1.0, 30.0, 2.0), T.COL_ENEMY)
	draw_rect(Rect2(half_l - 44.0, half_w - 3.0, 30.0, 2.0), T.COL_ENEMY)
	if vuln_left > 0.0:
		draw_arc(Vector2.ZERO, half_l + 8.0, 0.0, TAU, 28, Color(0.95, 0.3, 0.25, 0.85), 2.5)
