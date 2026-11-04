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
var blockers: Array[Control] = []  # buttons inside our zone that own their touches
var gauges: Array[Dictionary] = []  # fire stick: a ring per weapon with ammo or heat
var _gauge_key := ""
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
	for blocker in blockers:
		if blocker.visible and blocker.get_global_rect().grow(12.0).has_point(point):
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


## Ammo and heat rings (§14), one per weapon that has either. Redraws only
## when a ring visibly changes.
func set_gauges(list: Array[Dictionary]) -> void:
	var key := ""
	for g in list:
		key += "%s%d%s%s|" % [str(g.kind), roundi(float(g.fill) * 40.0), "r" if bool(g.reloading) else "", "h" if bool(g.hot) else ""]
	if key == _gauge_key:
		return
	_gauge_key = key
	gauges = list
	queue_redraw()


func _draw_gauges(at: Vector2) -> void:
	for i in gauges.size():
		var g: Dictionary = gauges[i]
		var r := radius + 9.0 + 8.0 * i
		var fill := float(g.fill)
		draw_arc(at, r, 0.0, TAU, 48, Color(0.0, 0.0, 0.0, 0.35), 5.0)
		if fill <= 0.01:
			continue
		var col := Color(0.95, 0.92, 0.85, 0.8)
		if str(g.kind) == "heat":
			col = Color(1.0, 0.55, 0.15, 0.85).lerp(Color(1.0, 0.15, 0.1, 0.95), fill)
			if bool(g.hot):
				col = Color(1.0, 0.15, 0.1, 0.95)
		elif bool(g.reloading):
			col = Color(0.6, 0.6, 0.6, 0.6)   # filling back up
		# Clockwise from the top.
		draw_arc(at, r, -PI * 0.5, -PI * 0.5 + TAU * fill, maxi(4, roundi(48.0 * fill)), col, 4.0)


## V6.4: the resting stick, textured: a knurled outer ring (tick marks), a
## faint well and a ridged knob. Subtle, so it never competes with the fight.
func _draw_rest(at: Vector2, accent: Color) -> void:
	draw_circle(at, radius, Color(0, 0, 0, 0.12))
	draw_arc(at, radius, 0.0, TAU, 48, Color(accent, 0.22), 3.0)
	for k in 36:
		var a := TAU * k / 36.0
		var d := Vector2.RIGHT.rotated(a)
		draw_line(at + d * (radius - 7.0), at + d * (radius - 2.0), Color(accent, 0.14), 2.0)
	draw_circle(at, 34.0, Color(accent, 0.12))
	draw_arc(at, 34.0, 0.0, TAU, 32, Color(accent, 0.2), 2.0)
	for k in 3:
		draw_line(at + Vector2(-12, -8 + k * 8), at + Vector2(12, -8 + k * 8), Color(accent, 0.18), 2.0)


func _draw() -> void:
	var size := get_viewport_rect().size
	var accent := T.COL_CYAN if left_side else T.COL_ORANGE
	if _touch == -1:
		if not enabled:
			return
		var rest := Vector2(170.0, size.y - 160.0) if left_side else Vector2(size.x - 170.0, size.y - 160.0)
		var pad := get_node_or_null("/root/Pad")
		if pad == null or not bool(pad.get("kbm")):   # V6.4: no touch sticks in mouse-and-keyboard mode
			_draw_rest(rest, accent)
		_draw_gauges(rest)   # ammo and heat rings stay in every mode
		return
	draw_circle(_base, radius, Color(0.0, 0.0, 0.0, 0.25))
	_draw_gauges(_base)
	draw_arc(_base, radius, 0.0, TAU, 48, Color(accent, 0.6), 3.0)
	var knob := _base + (_knob - _base).limit_length(radius)
	draw_circle(knob, 38.0, Color(accent, 0.55))
