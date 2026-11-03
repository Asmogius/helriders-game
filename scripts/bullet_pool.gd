extends Node2D
## Every bullet in the fight lives in this one node: packed arrays, one ray cast
## per bullet per tick, one draw call for all of them. No per-bullet nodes.
## Bullets carry a team so player fire and enemy fire hit different things.

const T := preload("res://scripts/tuning.gd")

const MAX_BULLETS := 96
const LIFETIME := 0.38  # range = bullet speed x this (~570 px for the starter turret)
const TRAIL := 16.0

const TEAM_PLAYER := 0
const TEAM_ENEMY := 1

# What each team's bullets can hit. Nobody shoots their own side.
const MASKS := [
	T.LAYER_WORLD | T.LAYER_ZOMBIE | T.LAYER_ENEMY,    # player
	T.LAYER_WORLD | T.LAYER_ZOMBIE | T.LAYER_VEHICLE,  # enemy
]

var fx: Node2D
var shots_fired := 0      # player shots (tests and stats)
var hits := 0             # player hits on anything that bleeds
var enemy_shots := 0

var _pos := PackedVector2Array()
var _vel := PackedVector2Array()
var _dmg := PackedFloat32Array()
var _life := PackedFloat32Array()
var _team := PackedByteArray()
var _count := 0
var _query := PhysicsRayQueryParameters2D.new()


func _ready() -> void:
	# Bullets fired from inside a zombie hugging the hull must still hit it.
	_query.hit_from_inside = true
	_pos.resize(MAX_BULLETS)
	_vel.resize(MAX_BULLETS)
	_dmg.resize(MAX_BULLETS)
	_life.resize(MAX_BULLETS)
	_team.resize(MAX_BULLETS)


func fire(origin: Vector2, velocity: Vector2, damage: float, team := TEAM_PLAYER) -> void:
	if team == TEAM_PLAYER:
		shots_fired += 1
	else:
		enemy_shots += 1
	if _count >= MAX_BULLETS:
		return
	_pos[_count] = origin
	_vel[_count] = velocity
	_dmg[_count] = damage
	_life[_count] = LIFETIME
	_team[_count] = team
	_count += 1


## A point-blank hit that never needed a bullet (a Hunter on your own hull).
func record_direct_hit() -> void:
	shots_fired += 1
	hits += 1


func active_count() -> int:
	return _count


func _physics_process(delta: float) -> void:
	if _count == 0:
		return
	var space := get_world_2d().direct_space_state
	var i := 0
	while i < _count:
		_life[i] -= delta
		var from := _pos[i]
		var to := from + _vel[i] * delta
		_query.from = from
		_query.to = to
		_query.collision_mask = MASKS[_team[i]]
		var hit := space.intersect_ray(_query)
		if not hit.is_empty():
			var collider: Object = hit.collider
			if collider != null and collider.has_method("take_hit"):
				collider.call("take_hit", _dmg[i], _vel[i].normalized() * 140.0)
				if _team[i] == TEAM_PLAYER:
					hits += 1
			if fx != null:
				# Armor that blunts the hit (a Bulwark's front) throws grey sparks.
				if collider != null and collider.has_method("deflects") and collider.call("deflects", hit.position):
					fx.call("deflect", hit.position, hit.normal)
				else:
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
	_team[i] = _team[_count]
	if _count == 0:
		queue_redraw()


func _draw() -> void:
	for i in _count:
		var head := _pos[i]
		var tail := head - _vel[i].normalized() * TRAIL
		if _team[i] == TEAM_PLAYER:
			draw_line(tail, head, T.COL_ORANGE, 3.0)
			draw_rect(Rect2(head - Vector2(2.0, 2.0), Vector2(4.0, 4.0)), Color(1.0, 0.9, 0.6))
		else:
			draw_line(tail, head, T.COL_ENEMY, 3.0)
			draw_rect(Rect2(head - Vector2(2.0, 2.0), Vector2(4.0, 4.0)), Color(1.0, 0.6, 0.55))
