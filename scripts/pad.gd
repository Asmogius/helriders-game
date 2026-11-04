extends Node
## Controller support (autoload `Pad`). A PlayStation-style pad (or any pad
## Godot maps) switches the game into controller mode on its first press;
## touching the screen switches back. In controller mode:
##  - menus: every visible, enabled button can take focus; the D-pad or left
##    stick moves it (Godot's ui_* actions), Cross presses it, Circle backs out
##    of the top panel. A cyan ring marks the focused button. While a panel in
##    the "pad_modal" group is open, focus stays inside it.
##  - fights: mission.gd reads the sticks and R2 here and maps the face and
##    shoulder buttons (pad_button). The current scene can turn menu focus off
##    while you drive (pad_wants_focus).
## Every button press goes first to the open modal, then to the current
## scene's pad_button(button) if it has one.

signal mode_changed(active: bool)

const DEAD := 0.18           # stick deadzone
const TRIGGER := 0.4         # R2 counts as held past this
const REFRESH := 0.2         # seconds between focus scans

var active := false
var device := 0
var _ring: FocusRing
var _scan := 0.0
var _modal: Control          # the modal at the last scan (a new one rescans at once)
var override := {}           # tests: "left" / "right" Vector2 and "r2" bool stand in for the pad


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var layer := CanvasLayer.new()
	layer.layer = 120
	add_child(layer)
	_ring = FocusRing.new()
	_ring.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_ring)


func _input(event: InputEvent) -> void:
	if event is InputEventJoypadButton and (event as InputEventJoypadButton).pressed:
		device = event.device
		set_active(true)
		_route(int((event as InputEventJoypadButton).button_index))
	elif event is InputEventJoypadMotion and absf((event as InputEventJoypadMotion).axis_value) > 0.5:
		device = event.device
		set_active(true)
	elif (event is InputEventScreenTouch and (event as InputEventScreenTouch).pressed) \
			or (event is InputEventMouseButton and (event as InputEventMouseButton).pressed):
		set_active(false)


func set_active(on: bool) -> void:
	if on == active:
		return
	active = on
	_scan = 0.0
	if not on:
		_apply_focus(false, null)
		var owner := get_viewport().gui_get_focus_owner()
		if owner != null:
			owner.release_focus()
	mode_changed.emit(on)


## The touch wording, or the pad's while a controller is in use (hints and
## tips; screens listen to mode_changed to swap them).
static func hint(touch: String, pad: String) -> String:
	var tree := Engine.get_main_loop() as SceneTree
	var p: Node = tree.root.get_node_or_null("Pad") if tree != null else null
	return pad if p != null and bool(p.get("active")) else touch


# --- Fights: the sticks and triggers ---------------------------------------------

## A stick with the deadzone taken out (screen directions, like the thumb sticks).
func stick(left: bool) -> Vector2:
	if override.has("left" if left else "right"):
		return override["left" if left else "right"]
	var v := Vector2(Input.get_joy_axis(device, JOY_AXIS_LEFT_X if left else JOY_AXIS_RIGHT_X),
		Input.get_joy_axis(device, JOY_AXIS_LEFT_Y if left else JOY_AXIS_RIGHT_Y))
	var l := v.length()
	if l < DEAD:
		return Vector2.ZERO
	return v / l * clampf((l - DEAD) / (1.0 - DEAD), 0.0, 1.0)


func r2() -> bool:
	if override.has("r2"):
		return bool(override.r2)
	return Input.get_joy_axis(device, JOY_AXIS_TRIGGER_RIGHT) > TRIGGER


# --- Buttons ---------------------------------------------------------------------

func _route(button: int) -> void:
	var modal := top_modal()
	if modal != null:
		if button == JOY_BUTTON_B and modal.has_meta("pad_close"):
			(modal.get_meta("pad_close") as Callable).call()
		if modal.has_method("pad_button") and bool(modal.call("pad_button", button)):
			return
		if button == JOY_BUTTON_B:
			return
	var scene := get_tree().current_scene
	for n: Node in _scene_handlers(scene):
		if bool(n.call("pad_button", button)):
			return


## The current scene, or (in tests and the mission, which are added to the
## root by hand) the newest root child that handles pad buttons.
func _scene_handlers(scene: Node) -> Array[Node]:
	var out: Array[Node] = []
	if scene != null and scene.has_method("pad_button"):
		out.append(scene)
	var kids := get_tree().root.get_children()
	for i in range(kids.size() - 1, -1, -1):
		var k := kids[i]
		if k != scene and k.has_method("pad_button") and not out.has(k):
			out.append(k)
			break
	return out


## The topmost open panel in the "pad_modal" group, or null.
func top_modal() -> Control:
	var best: Control = null
	for n: Node in get_tree().get_nodes_in_group("pad_modal"):
		var c := n as Control
		if c == null or not c.is_visible_in_tree():
			continue
		if best == null or c.is_greater_than(best):
			best = c
	return best


# --- Menus: focus ----------------------------------------------------------------

func _process(delta: float) -> void:
	if not active:
		_ring.target = null
		return
	_scan -= delta
	var modal := top_modal()
	if modal != _modal:
		_scan = 0.0
	if _scan > 0.0:
		_ring.target = get_viewport().gui_get_focus_owner()
		return
	_scan = REFRESH
	var want := true
	for n: Node in _scene_handlers(get_tree().current_scene):
		if n.has_method("pad_wants_focus"):
			want = bool(n.call("pad_wants_focus"))
	_modal = modal
	if modal != null:
		want = true
	_apply_focus(want, modal)
	var owner := get_viewport().gui_get_focus_owner()
	if want and (owner == null or not owner.is_visible_in_tree() or owner.focus_mode == Control.FOCUS_NONE):
		var first := _first_button(modal)
		if first != null:
			first.grab_focus()
	elif not want and owner != null:
		owner.release_focus()
	_ring.target = get_viewport().gui_get_focus_owner() if want else null


## Buttons that may take focus now: visible, enabled, and inside the open
## modal if there is one. Scroll boxes follow the focus.
func _apply_focus(on: bool, modal: Control) -> void:
	for b: Node in get_tree().root.find_children("*", "BaseButton", true, false):
		var button := b as BaseButton
		var ok := on and button.is_visible_in_tree() and not button.disabled and (modal == null or modal.is_ancestor_of(button))
		button.focus_mode = Control.FOCUS_ALL if ok else Control.FOCUS_NONE
	if on:
		for s: Node in get_tree().root.find_children("*", "ScrollContainer", true, false):
			(s as ScrollContainer).follow_focus = true


func _first_button(modal: Control) -> BaseButton:
	var root: Node = modal if modal != null else get_tree().root
	for b: Node in root.find_children("*", "BaseButton", true, false):
		var button := b as BaseButton
		if button.focus_mode != Control.FOCUS_NONE and button.is_visible_in_tree():
			return button
	return null


class FocusRing extends Control:
	## A cyan ring around the focused button (custom-drawn cards hide the
	## theme's own focus box).
	const T := preload("res://scripts/tuning.gd")
	var target: Control:
		set(value):
			if value != target:
				target = value
				queue_redraw()

	func _process(_delta: float) -> void:
		if target != null:
			queue_redraw()

	func _draw() -> void:
		if target == null or not is_instance_valid(target) or not target.is_visible_in_tree():
			return
		var r := target.get_global_rect().grow(4.0)
		draw_rect(r, T.COL_CYAN, false, 3.0)
