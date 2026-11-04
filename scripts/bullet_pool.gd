extends Node2D
## Every bullet in the fight lives in this one node: packed arrays, one ray cast
## per bullet per tick, one draw call for all of them. No per-bullet nodes.
## Bullets carry a team so player fire and enemy fire hit different things.

const T := preload("res://scripts/tuning.gd")
const StatusBars := preload("res://scripts/status_bars.gd")

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
var big_game := 1.0       # player bullets vs Hunters and rigs (Gunner perk)
var pierced := 0          # shamblers passed through (tests)
var shots_fired := 0      # player shots (tests and stats)
var hits := 0             # player hits on anything that bleeds
var enemy_shots := 0

var _pos := PackedVector2Array()
var _vel := PackedVector2Array()
var _dmg := PackedFloat32Array()
var _life := PackedFloat32Array()
var _team := PackedByteArray()
var _pierce := PackedByteArray()   # shamblers it can still pass through
var _dtype := PackedByteArray()    # damage type: 0 kinetic, else StatusBars kind + 1
var _chain := PackedByteArray()    # Arc Projector: 1 = jumps to one more target on a hit
var _rider := PackedFloat32Array() # Cook Off: share of damage added as a fire hit
var rider_hits := 0                # fire rider hits landed (tests)
var chained := 0                   # chain jumps (tests)
var typed_hits := 0                # typed (non-kinetic) hits landed (tests)
var _chain_query := PhysicsShapeQueryParameters2D.new()
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
	_pierce.resize(MAX_BULLETS)
	_dtype.resize(MAX_BULLETS)
	_chain.resize(MAX_BULLETS)
	_rider.resize(MAX_BULLETS)
	var circle := CircleShape2D.new()
	circle.radius = T.ARC_CHAIN_RANGE
	_chain_query.shape = circle


## `dtype` is a damage type ("" kinetic, "fire", "acid", "shock"...); `life` > 0
## overrides the range (seconds of flight); `chain` makes a hit jump once.
func fire(origin: Vector2, velocity: Vector2, damage: float, team := TEAM_PLAYER, pierce := 0, dtype := "", life := 0.0, chain := false, rider := 0.0) -> void:
	if team == TEAM_PLAYER:
		shots_fired += 1
	else:
		enemy_shots += 1
	if _count >= MAX_BULLETS:
		return
	_pos[_count] = origin
	_vel[_count] = velocity
	_dmg[_count] = damage
	_life[_count] = life if life > 0.0 else LIFETIME
	_team[_count] = team
	_pierce[_count] = clampi(pierce, 0, 255)
	_dtype[_count] = StatusBars.kind_of(dtype) + 1
	_chain[_count] = 1 if chain else 0
	_rider[_count] = rider
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
				var dmg := _dmg[i]
				var priority := int(collider.get("lock_priority")) if collider.get("lock_priority") != null else 0
				if _team[i] == TEAM_PLAYER and priority >= 2:
					dmg *= big_game  # Hunters and rigs
				var dtype := type_name(_dtype[i])
				collider.call("take_hit", dmg, _vel[i].normalized() * 140.0, "shot", dtype)
				if dtype != "":
					typed_hits += 1
				if _rider[i] > 0.0 and is_instance_valid(collider):
					collider.call("take_hit", dmg * _rider[i], Vector2.ZERO, "shot", "fire")
					rider_hits += 1
				if _chain[i] == 1:
					_chain_hit(collider as Node2D, hit.position, dmg * T.ARC_CHAIN_SHARE, _team[i], dtype)
				if _team[i] == TEAM_PLAYER:
					hits += 1
				# Piercing Rounds: carry on through a shambler.
				if _pierce[i] > 0 and priority == 1:
					_pierce[i] -= 1
					pierced += 1
					if fx != null:
						fx.sparks(hit.position, hit.normal)
					_pos[i] = hit.position + _vel[i].normalized() * 30.0
					i += 1
					continue
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
	_pierce[i] = _pierce[_count]
	_dtype[i] = _dtype[_count]
	_chain[i] = _chain[_count]
	_rider[i] = _rider[_count]
	if _count == 0:
		queue_redraw()


static func type_name(code: int) -> String:
	return "" if code <= 0 else str(T.STATUS_TYPES[code - 1])


## Arc Projector: a hit jumps to the nearest other target of the same side.
func _chain_hit(first: Node2D, at: Vector2, damage: float, team: int, dtype: String) -> void:
	if first == null:
		return
	_chain_query.transform = Transform2D(0.0, at)
	_chain_query.collision_mask = MASKS[team] & ~T.LAYER_WORLD
	var best: Node2D = null
	var best_d := INF
	for hit: Dictionary in get_world_2d().direct_space_state.intersect_shape(_chain_query, 16):
		var body := hit.collider as Node2D
		if body == null or body == first or not body.has_method("take_hit") or body.has_method("explode"):
			continue
		var d := body.global_position.distance_to(at)
		if d < best_d:
			best_d = d
			best = body
	if best != null:
		best.call("take_hit", damage, (best.global_position - at).normalized() * 100.0, "shot", dtype)
		chained += 1
		if fx != null:
			fx.sparks(best.global_position, (at - best.global_position).normalized())


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
