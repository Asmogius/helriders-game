extends PanelContainer
## The garage tour after the Training Run (optional tutorial; agreed with
## the owner). A card above the footer walks through fitting the salvaged
## part, then Comms, the Inn, the Saloon and Research, and ends on the
## one rule: crew are lost only if your rig is wrecked. It runs on a
## sandbox copy (Profile.begin_tour); finishing or skipping puts the garage
## back exactly as it was.
##
## Anchored to the bottom so it never covers the slot tags (ARMOR FRONT
## softlocked the tour when the card sat on top of it).

signal finished

const T := preload("res://scripts/tuning.gd")
const UI := preload("res://scripts/ui_theme.gd")
const Parts := preload("res://scripts/parts.gd")
const PadScript := preload("res://scripts/pad.gd")

# "ARMOR FRONT" stays on one line (NBSP); the card sits above the footer so
# that slot stays clickable. Weight / overload are named on the fit step so
# the red OVER WT on Riot Plating is the lesson, not a surprise.
const STEPS := [
	{"tab": "GARAGE", "text": "SALVAGE INTO PARTS: the %s you hauled home is in storage. Click ARMOR\u00A0FRONT (left of the rig), then click the plating twice to fit it. Watch WEIGHT LOAD: going over the chassis cap turns the bar red and OVERLOAD cuts speed and acceleration.", "pad_text": "SALVAGE INTO PARTS: the %s you hauled home is in storage. Pick ARMOR\u00A0FRONT with Cross, then press Cross twice on the plating to fit it. Watch WEIGHT LOAD: going over the chassis cap turns the bar red and OVERLOAD cuts speed and acceleration.", "wait": true},
	{"tab": "COMMS", "text": "COMMS: each day, pick one job from the board. More skulls mean a harder job, better pay and better parts."},
	{"tab": "INN", "text": "INN: your crew live here. Seat them on the rig, let the injured rest, and send spares out on expeditions."},
	{"tab": "SALOON", "text": "SALOON: hire new crew. Free Common Drivers and Gunners are always at the bar, so you're never stuck."},
	{"tab": "RESEARCH", "text": "RESEARCH: spend scrap to level up the schematics you own. Every level makes the part stronger."},
	{"tab": "GARAGE", "text": "ONE RULE: crew are lost only if your rig is wrecked. A rough job just means a few days' rest. Bring them home and they level up. That's it: good hunting."},
]

var garage: Node            # garage.gd (show_tab)
var profile: Node
var step := 0

var _text: Label
var _next: Button


func _ready() -> void:
	add_theme_stylebox_override("panel", UI.box(UI.PANEL, T.COL_UI_ACCENT, 2))
	# Bottom of the garage, clear of the slot tags and the rig. Footer is
	# BAR_H; job / hint lines sit just above it — keep a gap so the card
	# does not cover ARMOR FRONT (playtest softlock).
	anchor_left = 0.5
	anchor_right = 0.5
	anchor_top = 1.0
	anchor_bottom = 1.0
	offset_left = -440.0
	offset_right = 440.0
	offset_top = -(UI.BAR_H + 168.0)
	offset_bottom = -(UI.BAR_H + 16.0)
	z_index = 20
	# Pass clicks through the panel chrome so a slot under the card still
	# works; only the buttons stop the mouse.
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override("separation", 10)
	add_child(box)
	_text = UI.label("", 21, UI.TEXT)
	_text.autowrap_mode = TextServer.AUTOWRAP_WORD
	_text.custom_minimum_size = Vector2(840, 0)
	_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(_text)
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.alignment = BoxContainer.ALIGNMENT_END
	row.add_theme_constant_override("separation", 10)
	box.add_child(row)
	var skip := Button.new()
	skip.text = "SKIP TOUR"
	skip.focus_mode = Control.FOCUS_NONE
	skip.custom_minimum_size = Vector2(170, 52)
	skip.mouse_filter = Control.MOUSE_FILTER_STOP
	skip.pressed.connect(finish)
	row.add_child(skip)
	_next = Button.new()
	_next.focus_mode = Control.FOCUS_NONE
	_next.custom_minimum_size = Vector2(170, 52)
	_next.mouse_filter = Control.MOUSE_FILTER_STOP
	UI.accent(_next, T.COL_UI_ACCENT)
	_next.pressed.connect(next)
	row.add_child(_next)
	profile.changed.connect(_check_fit)
	var pad := get_node_or_null("/root/Pad")
	if pad != null:
		pad.connect("mode_changed", func(_on: bool) -> void:
			if STEPS[step].has("pad_text") and not _fitted():
				_show())
	_show()


func _show() -> void:
	var s: Dictionary = STEPS[step]
	garage.call("show_tab", str(s.tab))
	var text := str(s.text)
	if s.has("pad_text"):
		text = PadScript.hint(text, str(s.pad_text))
	if text.contains("%s"):
		text = text % str(Parts.get_part(T.TUTORIAL_PART).name)
	_text.text = text
	var waiting := bool(s.get("wait", false)) and not _fitted()
	_next.visible = not waiting
	_next.text = "FINISH" if step == STEPS.size() - 1 else "NEXT"


func _fitted() -> bool:
	return str((profile.get("rig") as Dictionary).get("armor_front", "")) == T.TUTORIAL_PART


## The plating went on: the first step is done.
func _check_fit() -> void:
	if step == 0 and _fitted() and not _next.visible:
		_text.text = "Fitted. Every part you salvage becomes a schematic you can build and fit like this. Over the weight cap, OVERLOAD slows you — strip a plate or research a sturdier chassis."
		_next.visible = true


func next() -> void:
	if step >= STEPS.size() - 1:
		finish()
		return
	step += 1
	_show()


func finish() -> void:
	if profile.changed.is_connected(_check_fit):
		profile.changed.disconnect(_check_fit)
	profile.call("end_tour")
	garage.call("show_tab", "GARAGE")
	finished.emit()
	queue_free()
