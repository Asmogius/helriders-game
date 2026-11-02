extends Camera2D
## Tight top-down follow cam: rotation-locked, looks ahead along velocity,
## pulls out slightly at speed, and shakes on big hits.

var target: CharacterBody2D
var look_ahead := 0.28      # seconds of velocity to lead by
var base_zoom := 1.3       # >1 zooms in; tight framing reads better on a phone
var speed_zoom := 1.05     # zoom at full speed (lower = see more)
var full_speed := 560.0

var _lead := Vector2.ZERO
var _shake := 0.0


func _ready() -> void:
	process_callback = Camera2D.CAMERA2D_PROCESS_PHYSICS
	position_smoothing_enabled = false
	zoom = Vector2(base_zoom, base_zoom)
	ignore_rotation = true


func set_bounds(bounds: Rect2) -> void:
	limit_left = int(bounds.position.x)
	limit_top = int(bounds.position.y)
	limit_right = int(bounds.end.x)
	limit_bottom = int(bounds.end.y)


func shake(amount: float) -> void:
	_shake = clampf(maxf(_shake, amount), 0.0, 1.0)


func _physics_process(delta: float) -> void:
	if target == null:
		return
	var vel := target.velocity
	_lead = _lead.lerp(vel * look_ahead, 1.0 - exp(-3.0 * delta))
	global_position = target.global_position + _lead
	var t := clampf(vel.length() / full_speed, 0.0, 1.0)
	var z := lerpf(base_zoom, speed_zoom, t)
	zoom = zoom.lerp(Vector2(z, z), 1.0 - exp(-2.0 * delta))
	if _shake > 0.0:
		offset = Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * _shake * 14.0
		_shake = maxf(_shake - delta * 2.5, 0.0)
	else:
		offset = Vector2.ZERO
