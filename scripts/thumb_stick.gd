extends Control
## Floating thumb stick. Touch anywhere in this stick's half of the screen and
## drag. `output` is a Vector2 of length 0..1 in screen space; the camera never
## rotates, so screen directions are world directions.

const T := preload("res://scripts/tuning.gd")
const TOP_STRIP := 90.0  # reserved for HUD, never starts a stick

@export var left_side := true

var radius := 100.0
var deadzone := 0.12
var output := Vector2.ZERO
var enabled := true:
	set(value):
		enabled = value
		if not value:
			_release()

var _touch := -1
var _base := Vector2.ZERO
var _knob := Vector2.ZERO


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func is_held() -> bool:
	return _touch != -1


func _input(event: InputEvent) -> void:
	if not enabled:
		return
	if event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		if touch.pressed and _touch == -1 and _in_zone(touch.position):
			_touch = touch.index
			_base = touch.position
			_knob = touch.position
			_update_output()
			get_viewport().set_input_as_handled()
		elif not touch.pressed and touch.index == _touch:
			_release()
			get_viewport().set_input_as_handled()
	elif event is InputEventScreenDrag:
		var drag := event as InputEventScreenDrag
		if drag.index == _touch:
			_knob = drag.position
			var offset := _knob - _base
			# Drag the base along so the stick never "runs out" of travel.
			if offset.length() > radius:
				_base = _knob - offset.normalized() * radius
			_update_output()
			get_viewport().set_input_as_handled()


func _in_zone(point: Vector2) -> bool:
	var size := get_viewport_rect().size
	if point.y < TOP_STRIP:
		return false
	if left_side:
		return point.x < size.x * 0.5
	return point.x >= size.x * 0.5


func _update_output() -> void:
	var offset := (_knob - _base) / radius
	var length := offset.length()
	if length < deadzone:
		output = Vector2.ZERO
	else:
		output = offset.normalized() * minf((length - deadzone) / (1.0 - deadzone), 1.0)
	queue_redraw()


func _release() -> void:
	_touch = -1
	output = Vector2.ZERO
	queue_redraw()


func _draw() -> void:
	var size := get_viewport_rect().size
	var accent := T.COL_CYAN if left_side else T.COL_ORANGE
	if _touch == -1:
		if not enabled:
			return
		var rest := Vector2(170.0, size.y - 160.0) if left_side else Vector2(size.x - 170.0, size.y - 160.0)
		draw_arc(rest, radius, 0.0, TAU, 48, Color(accent, 0.22), 3.0)
		draw_circle(rest, 34.0, Color(accent, 0.12))
		return
	draw_circle(_base, radius, Color(0.0, 0.0, 0.0, 0.25))
	draw_arc(_base, radius, 0.0, TAU, 48, Color(accent, 0.6), 3.0)
	var knob := _base + (_knob - _base).limit_length(radius)
	draw_circle(knob, 38.0, Color(accent, 0.55))
