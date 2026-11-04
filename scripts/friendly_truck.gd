extends "res://scripts/vehicle.gd"
## The Escort job's salvage truck (DESIGN §7; agreed with the owner). A slow,
## tough, unarmed friendly rig that drives to each salvage site in turn and
## works it while you keep the zombies and enemy rigs off it (they go for it).
## It stops when something blocks the road and waits for you to clear it. If
## it's wrecked the job fails. Like every rig it only decides stick inputs.

const NavGrid := preload("res://scripts/nav_grid.gd")

signal site_reached(index: int)
signal site_done(index: int)

var nav: NavGrid
var sites := PackedVector2Array() # where it salvages, in order
var site_times: Array[float] = [] # seconds of work at each
var site_index := 0
var working := false
var work_left := 0.0

var _nav_timer := 0.0
var _waypoint := Vector2.ZERO
var _stuck := 0.0
var _reverse := 0.0
var _side := 1.0


func _init() -> void:
	team = BulletPool.TEAM_PLAYER
	apply_stats(T.TRUCK)
	body_len = 78.0
	body_wid = 40.0
	lock_priority = 0


## A friendly bump from your rig doesn't hurt it.
func receive_ram(_damage: float, _from := Vector2.INF) -> void:
	pass


func is_done() -> bool:
	return site_index >= sites.size()


## 0..1 progress at the site it's working.
func work_progress() -> float:
	if not working or site_index >= site_times.size():
		return 0.0
	return 1.0 - work_left / maxf(site_times[site_index], 0.01)


## Add a stop to the route (the optional site) as the next one.
func insert_site(at: Vector2, seconds: float) -> void:
	sites.insert(site_index, at)
	site_times.insert(site_index, seconds)


func _physics_process(delta: float) -> void:
	if not is_wrecked:
		_think(delta)
	super(delta)


func _think(delta: float) -> void:
	drive_input = Vector2.ZERO
	if is_done():
		return
	var site := sites[site_index]
	if working:
		queue_redraw()   # the crane swings
		work_left -= delta
		if work_left <= 0.0:
			working = false
			site_index += 1
			site_done.emit(site_index - 1)
		return
	var to_site := site - global_position
	if to_site.length() < 45.0:
		working = true
		work_left = site_times[site_index]
		site_reached.emit(site_index)
		return
	if _reverse > 0.0:
		# Backing off whatever it got stuck on.
		_reverse -= delta
		drive_input = -Vector2.RIGHT.rotated(rotation).rotated(_side * 0.5)
		return
	_nav_timer -= delta
	if _nav_timer <= 0.0 or global_position.distance_to(_waypoint) < 30.0:
		_nav_timer = 0.4
		_waypoint = site
		if nav != null:
			_waypoint = nav.next_waypoint(get_world_2d().direct_space_state, global_position, site)
	var throttle := clampf(to_site.length() / 220.0, 0.35, 1.0)
	drive_input = (_waypoint - global_position).normalized() * throttle
	# Pinned against a wall (not just held up by a crowd): back out.
	if get_real_velocity().length() < 15.0 and touching_wall:
		_stuck += delta
		if _stuck > 1.2:
			_stuck = 0.0
			_reverse = 0.8
			_side = -_side
	else:
		_stuck = 0.0


func _draw() -> void:
	var half_l := body_len * 0.5
	var half_w := body_wid * 0.5
	var body := Color(0.32, 0.36, 0.28)
	if is_wrecked:
		body = Color(0.1, 0.09, 0.085)
	elif _flash > 0.0:
		body = body.lerp(Color(1.0, 0.85, 0.7), _flash * 0.6)
	var tyre := Color(0.06, 0.06, 0.065)
	for sx: float in [-0.55, -0.2, 0.5]:
		for sy: float in [-1.0, 1.0]:
			draw_rect(Rect2(Vector2(sx * body_len - 9.0, sy * half_w - 5.0), Vector2(18.0, 10.0)), tyre)
	draw_rect(Rect2(-half_l, -half_w + 3.0, body_len - 22.0, body_wid - 6.0), body.darkened(0.15))   # flatbed
	draw_rect(Rect2(half_l - 24.0, -half_w + 2.0, 24.0, body_wid - 4.0), body)                        # cab
	if is_wrecked:
		draw_rect(Rect2(-10.0, -8.0, 22.0, 16.0), Color(0.05, 0.04, 0.04))
		return
	draw_rect(Rect2(half_l - 18.0, -half_w + 6.0, 7.0, body_wid - 12.0), Color(0.12, 0.13, 0.15))    # windshield
	# The crane arm on the bed; it swings while the crew works.
	var swing := sin(float(Time.get_ticks_msec()) * 0.004) * 0.6 if working else 0.0
	var base := Vector2(-half_l + 16.0, 0.0)
	draw_line(base, base + Vector2(30.0, 0.0).rotated(PI + swing), Color(0.85, 0.7, 0.2), 4.0)
	draw_circle(base, 6.0, Color(0.2, 0.2, 0.21))
	# Green running lights: it's on your side.
	draw_rect(Rect2(-half_l + 4.0, -half_w + 3.0, body_len - 30.0, 2.0), T.COL_TRUCK)
	draw_rect(Rect2(-half_l + 4.0, half_w - 5.0, body_len - 30.0, 2.0), T.COL_TRUCK)
