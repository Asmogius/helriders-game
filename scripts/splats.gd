extends Node2D
## Ground stains left by kills. Ring buffer; only redraws when a splat is added.

const T := preload("res://scripts/tuning.gd")
const MAX_SPLATS := 120

var density := 1.0      # share of splats drawn (quality preset)
var _skip := 0.0

var _pos := PackedVector2Array()
var _rot := PackedFloat32Array()
var _seed := PackedInt32Array()
var _next := 0
var _count := 0


func _ready() -> void:
	_pos.resize(MAX_SPLATS)
	_rot.resize(MAX_SPLATS)
	_seed.resize(MAX_SPLATS)


func add(at: Vector2) -> void:
	if density < 1.0:
		_skip += density
		if _skip < 1.0:
			return
		_skip -= 1.0
	_pos[_next] = at
	_rot[_next] = randf() * TAU
	_seed[_next] = randi()
	_next = (_next + 1) % MAX_SPLATS
	_count = mini(_count + 1, MAX_SPLATS)
	queue_redraw()


func _draw() -> void:
	var rng := RandomNumberGenerator.new()
	for i in _count:
		rng.seed = _seed[i]
		draw_set_transform(_pos[i], _rot[i], Vector2.ONE)
		draw_rect(Rect2(-10.0, -8.0, 20.0, 16.0), T.COL_BLOOD)
		for j in 5:
			var p := Vector2(rng.randf_range(-22.0, 22.0), rng.randf_range(-16.0, 16.0))
			var s := rng.randf_range(3.0, 8.0)
			draw_rect(Rect2(p, Vector2(s, s)), T.COL_BLOOD)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
