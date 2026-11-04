extends Node2D
## Slime, bile and oil on the ground, all in one node (packed arrays, one
## _draw). Oil comes from Scrappers and the Oil Slick utility: rigs on it slide
## like on slime, zombies in it slow down.
## Slimers drop slime blobs as they walk and a puddle where they die; rigs on
## slime lose grip. Boomers burst into bile pools; zombies in a pool frenzy.
## Fixed capacity: the oldest blob is overwritten when the pool is full.
## Also draws the bile ring around a marked rig.

const T := preload("res://scripts/tuning.gd")

const SLIME_CAP := 192
const BILE_CAP := 8
const OIL_CAP := 16
const FIRE_CAP := 12
const REDRAW_EVERY := 0.2   # fading is slow; a few redraws a second is plenty

var marked: Node2D           # the rig wearing bile, if any (mission sets it)
var marked_left := 0.0

var _slime_pos := PackedVector2Array()
var _slime_r := PackedFloat32Array()
var _slime_life := PackedFloat32Array()
var _slime_next := 0
var _bile_pos := PackedVector2Array()
var _bile_life := PackedFloat32Array()
var _oil_pos := PackedVector2Array()
var _oil_r := PackedFloat32Array()
var _oil_life := PackedFloat32Array()
var _oil_next := 0
var _fire_pos := PackedVector2Array()
var _fire_r := PackedFloat32Array()
var _fire_life := PackedFloat32Array()
var _fire_next := 0
var _redraw := 0.0


func _ready() -> void:
	_slime_pos.resize(SLIME_CAP)
	_slime_r.resize(SLIME_CAP)
	_slime_life.resize(SLIME_CAP)
	_bile_pos.resize(BILE_CAP)
	_bile_life.resize(BILE_CAP)
	_oil_pos.resize(OIL_CAP)
	_oil_r.resize(OIL_CAP)
	_oil_life.resize(OIL_CAP)
	_fire_pos.resize(FIRE_CAP)
	_fire_r.resize(FIRE_CAP)
	_fire_life.resize(FIRE_CAP)
	clear()


func clear() -> void:
	_slime_life.fill(0.0)
	_bile_life.fill(0.0)
	_oil_life.fill(0.0)
	_fire_life.fill(0.0)
	marked = null
	marked_left = 0.0
	queue_redraw()


func add_slime(at: Vector2, radius: float) -> void:
	_slime_pos[_slime_next] = at
	_slime_r[_slime_next] = radius
	_slime_life[_slime_next] = T.SLIME_TIME
	_slime_next = (_slime_next + 1) % SLIME_CAP
	_redraw = 0.0


func add_bile(at: Vector2) -> void:
	var slot := 0
	for i in BILE_CAP:
		if _bile_life[i] <= 0.0:
			slot = i
			break
		if _bile_life[i] < _bile_life[slot]:
			slot = i
	_bile_pos[slot] = at
	_bile_life[slot] = T.BOOMER_POOL_TIME
	queue_redraw()


func add_oil(at: Vector2, radius: float, seconds: float) -> void:
	_oil_pos[_oil_next] = at
	_oil_r[_oil_next] = radius
	_oil_life[_oil_next] = seconds
	_oil_next = (_oil_next + 1) % OIL_CAP
	queue_redraw()


func oil_at(p: Vector2) -> bool:
	for i in OIL_CAP:
		if _oil_life[i] > 0.0 and p.distance_squared_to(_oil_pos[i]) < _oil_r[i] * _oil_r[i]:
			return true
	return false


func oil_count() -> int:
	var n := 0
	for i in OIL_CAP:
		if _oil_life[i] > 0.0:
			n += 1
	return n


## Burning ground (§14): a Fire barrel's blast, or oil set alight. Anything
## standing in it builds BURNING (the mission and director add it).
func add_fire(at: Vector2, radius: float, seconds: float) -> void:
	_fire_pos[_fire_next] = at
	_fire_r[_fire_next] = radius
	_fire_life[_fire_next] = seconds
	_fire_next = (_fire_next + 1) % FIRE_CAP
	ignite_oil(at, radius)
	queue_redraw()


func fire_at(p: Vector2) -> bool:
	for i in FIRE_CAP:
		if _fire_life[i] > 0.0 and p.distance_squared_to(_fire_pos[i]) < _fire_r[i] * _fire_r[i]:
			return true
	return false


func fire_count() -> int:
	var n := 0
	for i in FIRE_CAP:
		if _fire_life[i] > 0.0:
			n += 1
	return n


## Explosions and fire light oil: every slick touching the circle turns to
## burning ground for the rest of its life. Returns how many caught.
func ignite_oil(at: Vector2, radius: float) -> int:
	var lit := 0
	for i in OIL_CAP:
		if _oil_life[i] > 0.0 and at.distance_to(_oil_pos[i]) < radius + _oil_r[i]:
			var life := _oil_life[i]
			_oil_life[i] = 0.0
			lit += 1
			_fire_pos[_fire_next] = _oil_pos[i]
			_fire_r[_fire_next] = _oil_r[i]
			_fire_life[_fire_next] = life
			_fire_next = (_fire_next + 1) % FIRE_CAP
	if lit > 0:
		queue_redraw()
	return lit


## Slime or oil: a rig here loses grip.
func slick_at(p: Vector2) -> bool:
	return slime_at(p) or oil_at(p)


func slime_at(p: Vector2) -> bool:
	for i in SLIME_CAP:
		if _slime_life[i] > 0.0 and p.distance_squared_to(_slime_pos[i]) < _slime_r[i] * _slime_r[i]:
			return true
	return false


func bile_at(p: Vector2) -> bool:
	var r2 := T.BOOMER_POOL_RADIUS * T.BOOMER_POOL_RADIUS
	for i in BILE_CAP:
		if _bile_life[i] > 0.0 and p.distance_squared_to(_bile_pos[i]) < r2:
			return true
	return false


func slime_count() -> int:
	var n := 0
	for i in SLIME_CAP:
		if _slime_life[i] > 0.0:
			n += 1
	return n


func bile_count() -> int:
	var n := 0
	for i in BILE_CAP:
		if _bile_life[i] > 0.0:
			n += 1
	return n


func mark(rig: Node2D) -> void:
	marked = rig
	marked_left = T.BILE_MARK_TIME


func is_marked(rig: Node2D) -> bool:
	return marked == rig and marked_left > 0.0


func _physics_process(delta: float) -> void:
	for i in SLIME_CAP:
		if _slime_life[i] > 0.0:
			_slime_life[i] -= delta
	for i in BILE_CAP:
		if _bile_life[i] > 0.0:
			_bile_life[i] -= delta
	for i in OIL_CAP:
		if _oil_life[i] > 0.0:
			_oil_life[i] -= delta
	for i in FIRE_CAP:
		if _fire_life[i] > 0.0:
			_fire_life[i] -= delta
	if marked_left > 0.0:
		marked_left -= delta
		queue_redraw()   # the ring follows the rig
	_redraw -= delta
	if _redraw <= 0.0:
		_redraw = REDRAW_EVERY
		queue_redraw()


func _draw() -> void:
	for i in FIRE_CAP:
		var life := _fire_life[i]
		if life > 0.0:
			var c := T.COL_FIRE_GROUND
			c.a *= clampf(life / 1.5, 0.0, 1.0)
			var flick := 0.85 + 0.15 * sin(float(Time.get_ticks_msec()) * 0.02 + i)
			draw_circle(_fire_pos[i], _fire_r[i] * flick, c)
			draw_circle(_fire_pos[i], _fire_r[i] * 0.55 * flick, Color(1.0, 0.75, 0.3, c.a))
	for i in OIL_CAP:
		var life := _oil_life[i]
		if life > 0.0:
			var c := T.COL_OIL
			c.a *= clampf(life / 2.0, 0.0, 1.0)
			draw_circle(_oil_pos[i], _oil_r[i], c)
			# A rainbow-ish sheen so it reads as oil, not a shadow.
			draw_arc(_oil_pos[i] + Vector2(-8, -6), _oil_r[i] * 0.55, 0.4, 2.2, 12, Color(0.4, 0.3, 0.6, c.a * 0.6), 3.0)
			draw_arc(_oil_pos[i] + Vector2(6, 4), _oil_r[i] * 0.4, 3.5, 5.3, 10, Color(0.3, 0.55, 0.5, c.a * 0.6), 3.0)
	for i in SLIME_CAP:
		var life := _slime_life[i]
		if life > 0.0:
			var c := T.COL_SLIME
			c.a *= clampf(life / 2.0, 0.0, 1.0)
			draw_circle(_slime_pos[i], _slime_r[i], c)
	for i in BILE_CAP:
		var life := _bile_life[i]
		if life > 0.0:
			var c := T.COL_BILE
			c.a *= clampf(life / 1.5, 0.0, 1.0)
			draw_circle(_bile_pos[i], T.BOOMER_POOL_RADIUS, c)
			draw_arc(_bile_pos[i], T.BOOMER_POOL_RADIUS, 0.0, TAU, 28, Color(c.r, c.g, c.b, c.a * 1.6), 3.0)
	if marked != null and marked_left > 0.0:
		var pulse := 0.6 + 0.4 * sin(marked_left * 10.0)
		var c := T.COL_BILE
		c.a = 0.75 * pulse
		draw_arc(marked.global_position, 46.0, 0.0, TAU, 28, c, 4.0)
