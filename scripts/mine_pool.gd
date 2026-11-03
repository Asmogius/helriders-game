extends Node2D
## Every mine on the map lives in this one node (Mine Dropper utility): packed
## arrays, a staggered proximity check, one draw pass. No per-mine nodes.
## Mines are the player's: they only trigger on and hurt zombies, Hunters and
## enemy rigs.

const T := preload("res://scripts/tuning.gd")

const MAX_MINES := 12
const TRIGGER_RADIUS := 34.0   # how close a hostile must get to set one off
const CHECK_INTERVAL := 3      # proximity check every N physics ticks
const MASK := T.LAYER_ZOMBIE | T.LAYER_ENEMY

var fx: Node2D
var detonations := 0   # tests and stats

var _pos := PackedVector2Array()
var _dmg := PackedFloat32Array()
var _radius := PackedFloat32Array()
var _arm := PackedFloat32Array()    # seconds until armed
var _life := PackedFloat32Array()   # seconds until it fizzles
var _count := 0
var _tick := 0
var _trigger := PhysicsShapeQueryParameters2D.new()
var _blast := PhysicsShapeQueryParameters2D.new()
var _trigger_shape := CircleShape2D.new()
var _blast_shape := CircleShape2D.new()


func _ready() -> void:
	_pos.resize(MAX_MINES)
	_dmg.resize(MAX_MINES)
	_radius.resize(MAX_MINES)
	_arm.resize(MAX_MINES)
	_life.resize(MAX_MINES)
	_trigger_shape.radius = TRIGGER_RADIUS
	_trigger.shape = _trigger_shape
	_trigger.collision_mask = MASK
	_blast.shape = _blast_shape
	_blast.collision_mask = MASK


func drop(at: Vector2, damage: float, radius: float, arm: float, life: float) -> void:
	if _count >= MAX_MINES:
		# Full: the oldest mine fizzles to make room.
		_remove(0)
	_pos[_count] = at
	_dmg[_count] = damage
	_radius[_count] = radius
	_arm[_count] = arm
	_life[_count] = life
	_count += 1
	queue_redraw()


func active_count() -> int:
	return _count


## Set off mine `i` now (tests call this; normally proximity does).
func detonate(i: int) -> void:
	if i < 0 or i >= _count:
		return
	var at := _pos[i]
	var damage := _dmg[i]
	_blast_shape.radius = _radius[i]
	_blast.transform = Transform2D(0.0, at)
	_remove(i)
	detonations += 1
	if fx != null:
		fx.call("blast", at, _blast_shape.radius)
	var space := get_world_2d().direct_space_state
	for hit: Dictionary in space.intersect_shape(_blast, 32):
		var body: Object = hit.collider
		if body != null and body.has_method("take_hit"):
			var away: Vector2 = (body as Node2D).global_position - at
			body.call("take_hit", damage, away.normalized() * 320.0, "mine")


func _physics_process(delta: float) -> void:
	if _count == 0:
		return
	_tick += 1
	var check := _tick % CHECK_INTERVAL == 0
	var space := get_world_2d().direct_space_state
	var i := 0
	var redraw := false
	while i < _count:
		var was_armed := _arm[i] <= 0.0
		_arm[i] -= delta
		_life[i] -= delta
		if _life[i] <= 0.0:
			_remove(i)
			redraw = true
			continue
		if _arm[i] <= 0.0 and not was_armed:
			redraw = true
		if check and _arm[i] <= 0.0:
			_trigger.transform = Transform2D(0.0, _pos[i])
			if not space.intersect_shape(_trigger, 1).is_empty():
				detonate(i)
				redraw = true
				continue
		i += 1
	if redraw:
		queue_redraw()


func _remove(i: int) -> void:
	_count -= 1
	for k in range(i, _count):
		_pos[k] = _pos[k + 1]
		_dmg[k] = _dmg[k + 1]
		_radius[k] = _radius[k + 1]
		_arm[k] = _arm[k + 1]
		_life[k] = _life[k + 1]
	queue_redraw()


func _draw() -> void:
	for i in _count:
		var p := _pos[i]
		draw_circle(p, 9.0, Color(0.1, 0.1, 0.1))
		draw_circle(p, 7.0, Color(0.32, 0.3, 0.26))
		# Red light once armed.
		draw_circle(p, 3.0, T.COL_ENEMY if _arm[i] <= 0.0 else Color(0.4, 0.4, 0.38))
