extends Control
## Base for a garage room (V2, P6). Cameron's call: the garage is separate
## rooms that fade between each other (no panning panorama). A room is a
## self-contained full-screen Control under the garage UI; the garage asks it
## to open or close and it fades. Other rooms (Research, Saloon, Inn, Comms)
## extend this and reuse the same hook.
##
##   room.set_open(true)          # fade in (or snap with instant = true)
##   room.set_open(false)         # fade out, then hide
##   signal faded(open: bool)     # after a fade finishes
##   room.is_open()

signal faded(open: bool)

const FADE_TIME := 0.25

var room_id := ""
var _open := false
var _tween: Tween


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	modulate.a = 0.0
	visible = false


func is_open() -> bool:
	return _open


func set_open(open: bool, instant := false) -> void:
	if open == _open and not instant:
		return
	_open = open
	if _tween != null and _tween.is_valid():
		_tween.kill()
	if open:
		visible = true
	if instant or not is_inside_tree():
		modulate.a = 1.0 if open else 0.0
		visible = open
		faded.emit(open)
		return
	_tween = create_tween()
	_tween.tween_property(self, "modulate:a", 1.0 if open else 0.0, FADE_TIME).set_trans(Tween.TRANS_SINE)
	_tween.tween_callback(_fade_done)


func _fade_done() -> void:
	visible = _open
	faded.emit(_open)
