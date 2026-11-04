extends Control
## V2.4 style sample (P6): ambient life for the Workshop bay, one drawer.
## Flickering fluorescent tubes (the light overlay's alpha), dust motes in the
## light, and an occasional spark shower at the welding bench. Cheap: a fixed
## array of motes, one _draw(). Low quality (Profile settings) turns it off.

const MOTES := 26

var room: Control
var enabled := true
var _t := 0.0
var _motes := PackedVector3Array()   # x, y in room voxels, phase
var _sparks := PackedVector4Array()  # x, y, vx, vy (room voxels); life in _spark_life
var _spark_life := PackedFloat32Array()
var _next_spark := 1.5
var _rng := RandomNumberGenerator.new()


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rng.seed = 11   # fixed: the garage never consumes the game's RNG
	for i in MOTES:
		_motes.append(Vector3(_rng.randf_range(80.0, 380.0), _rng.randf_range(20.0, 200.0), _rng.randf() * TAU))


func _ready() -> void:
	var profile := get_node_or_null("/root/Profile")
	if profile != null:
		var q := str((profile.get("settings") as Dictionary).get("quality", "High"))
		enabled = q != "Low"


func _process(delta: float) -> void:
	if not enabled or room == null or not room.visible:
		return
	_t += delta
	var lights: TextureRect = room.call("lights_node")
	if lights != null:
		# Fluorescent flicker: mostly steady, a quick stutter every few seconds.
		var stutter := fmod(_t, 4.7) < 0.18 and int(_t * 30.0) % 2 == 0
		lights.modulate.a = 0.35 if stutter else 0.8 + 0.06 * sin(_t * 9.0)
	_next_spark -= delta
	if _next_spark <= 0.0:
		_next_spark = _rng.randf_range(1.5, 3.5)
		for i in 10:
			_sparks.append(Vector4(0.0, 0.0, _rng.randf_range(-30.0, 30.0), _rng.randf_range(-45.0, -15.0)))
			_spark_life.append(_rng.randf_range(0.3, 0.6))
	var i := 0
	while i < _sparks.size():
		_spark_life[i] -= delta
		if _spark_life[i] <= 0.0:
			_sparks.remove_at(i)
			_spark_life.remove_at(i)
			continue
		var s := _sparks[i]
		s.x += s.z * delta
		s.y += s.w * delta
		s.w += 90.0 * delta
		_sparks[i] = s
		i += 1
	queue_redraw()


func _draw() -> void:
	if not enabled or room == null:
		return
	var s: float = room.call("px")
	var lift: Vector2 = room.call("lift_point")
	var origin := lift - Vector2(size.x * 0.5 / s, 85.3) * s   # room voxel (0,0) on screen, narrow-crop frame
	for m in _motes:
		var p := Vector2(m.x + 6.0 * sin(_t * 0.3 + m.z), m.y - fmod(_t * 3.0 + m.z * 10.0, 40.0))
		var a := 0.10 + 0.08 * sin(_t + m.z)
		draw_rect(Rect2(origin + p * s, Vector2(s, s)), Color(0.9, 0.88, 0.8, a))
	# Weld sparks: from the welding bench (right of the lift), orange-white.
	var weld := lift + Vector2(118.0, -64.0) * s
	for k in _sparks.size():
		var sp := _sparks[k]
		var c := Color(1.0, 0.85, 0.5, clampf(_spark_life[k] * 2.0, 0.0, 1.0))
		draw_rect(Rect2(weld + Vector2(sp.x, sp.y) * s, Vector2(s, s)), c)
