extends Node2D
## Every player bullet lives in this one node: packed arrays, one ray cast per
## bullet per tick, one draw call for all of them. No per-bullet nodes.

const T := preload("res://scripts/tuning.gd")
const Zombie := preload("res://scripts/zombie.gd")

const MAX_BULLETS := 64
const LIFETIME := 0.38  # ~570 px range: no sniping things off-screen
const TRAIL := 16.0

var fx: Node2D
var exclude: Array[RID] = []
var shots_fired := 0
var hits := 0

var _pos := PackedVector2Array()
var _vel := PackedVector2Array()
var _dmg := PackedFloat32Array()
var _life := PackedFloat32Array()
var _count := 0
var _query := PhysicsRayQueryParameters2D.new()


func _ready() -> void:
	_pos.resize(MAX_BULLETS)
	_vel.resize(MAX_BULLETS)
	_dmg.resize(MAX_BULLETS)
	_life.resize(MAX_BULLETS)
	_query.collision_mask = T.LAYER_WORLD | T.LAYER_ZOMBIE


func fire(origin: Vector2, velocity: Vector2, damage: float) -> void:
	if _count >= MAX_BULLETS:
		return
	_pos[_count] = origin
	_vel[_count] = velocity
	_dmg[_count] = damage
	_life[_count] = LIFETIME
	_count += 1
	shots_fired += 1


func active_count() -> int:
	return _count


func _physics_process(delta: float) -> void:
	if _count == 0:
		return
	var space := get_world_2d().direct_space_state
	_query.exclude = exclude
	var i := 0
	while i < _count:
		_life[i] -= delta
		var from := _pos[i]
		var to := from + _vel[i] * delta
		_query.from = from
		_query.to = to
		var hit := space.intersect_ray(_query)
		if not hit.is_empty():
			var collider: Object = hit.collider
			if collider is Zombie:
				(collider as Zombie).take_hit(_dmg[i], _vel[i].normalized() * 140.0)
				hits += 1
			if fx != null:
				fx.sparks(hit.position, hit.normal)
			_remove(i)
			continue
		_pos[i] = to
		if _life[i] <= 0.0:
			_remove(i)
			continue
		i += 1
	queue_redraw()


func _remove(i: int) -> void:
	_count -= 1
	_pos[i] = _pos[_count]
	_vel[i] = _vel[_count]
	_dmg[i] = _dmg[_count]
	_life[i] = _life[_count]
	if _count == 0:
		queue_redraw()


func _draw() -> void:
	for i in _count:
		var head := _pos[i]
		var tail := head - _vel[i].normalized() * TRAIL
		draw_line(tail, head, T.COL_ORANGE, 3.0)
		draw_rect(Rect2(head - Vector2(2.0, 2.0), Vector2(4.0, 4.0)), Color(1.0, 0.9, 0.6))
