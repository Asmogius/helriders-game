extends Node2D
## P4 style sample: drifting seed fluff over the Outer Blocks corner. One node,
## packed arrays, one _draw() (perf rule); fixed pool built once, nothing is
## created or freed while it runs. Off on the Low preset.

const T := preload("res://scripts/tuning.gd")

var area := Rect2()
var _pos := PackedVector2Array()
var _vel := PackedVector2Array()
var _phase := PackedFloat32Array()


func setup(rect: Rect2, count: int) -> void:
	area = rect
	var rng := RandomNumberGenerator.new()
	rng.seed = 808
	_pos.resize(count)
	_vel.resize(count)
	_phase.resize(count)
	for i in count:
		_pos[i] = Vector2(rng.randf_range(area.position.x, area.end.x), rng.randf_range(area.position.y, area.end.y))
		_vel[i] = Vector2(rng.randf_range(6, 16), rng.randf_range(-3, 5))
		_phase[i] = rng.randf() * TAU


func _process(delta: float) -> void:
	if _pos.is_empty():
		return
	for i in _pos.size():
		_phase[i] += delta * 1.7
		var p := _pos[i] + (_vel[i] + Vector2(0, sin(_phase[i]) * 6.0)) * delta
		if p.x > area.end.x:
			p.x = area.position.x
		if p.y > area.end.y:
			p.y = area.position.y
		elif p.y < area.position.y:
			p.y = area.end.y
		_pos[i] = p
	queue_redraw()


func _draw() -> void:
	for i in _pos.size():
		var c := T.COL_OB_MOTE
		c.a *= 0.55 + 0.45 * sin(_phase[i] * 0.7)
		draw_rect(Rect2(_pos[i], Vector2(2, 2)), c)
