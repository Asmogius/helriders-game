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
var kbm := false             # PC: mouse and keyboard in use (pad.gd tracks all three schemes)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if _desktop():
		# On a PC the mouse aims and clicks; it mustn't grab the touch sticks.
		Input.emulate_touch_from_mouse = false
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
		var b := int((event as InputEventJoypadButton).button_index)
		if capturing != "":
			_capture(b)
			get_viewport().set_input_as_handled()   # the press binds; it doesn't also click
			return
		_route(b)
	elif event is InputEventJoypadMotion:
		var m := event as InputEventJoypadMotion
		if absf(m.axis_value) > 0.5:
			device = event.device
			set_active(true)
		# L2 / R2 are axes: a pull past halfway counts as a press (rebindable).
		if m.axis == JOY_AXIS_TRIGGER_LEFT or m.axis == JOY_AXIS_TRIGGER_RIGHT:
			var k := 0 if m.axis == JOY_AXIS_TRIGGER_LEFT else 1
			var down := m.axis_value > 0.6
			if down and not _trig_down[k]:
				var code := TRIGGER_BASE + int(m.axis)
				if capturing != "":
					_capture(code)
					get_viewport().set_input_as_handled()
				else:
					_route(code)
			if down or m.axis_value < 0.3:
				_trig_down[k] = down
	elif event is InputEventKey and (event as InputEventKey).pressed and not (event as InputEventKey).echo:
		var k := event as InputEventKey
		if capturing_kbm != "":
			# Esc cancels any rebind except PAUSE, where Esc assigns Esc-pause.
			if k.keycode == KEY_ESCAPE and capturing_kbm != "pause":
				cancel_kbm_capture()
			elif k.keycode == KEY_ESCAPE and capturing_kbm == "pause":
				_capture_kbm(KEY_ESCAPE)
			else:
				_capture_kbm(int(k.physical_keycode))
			get_viewport().set_input_as_handled()
			return
		if _desktop():
			set_kbm(true)
		if k.keycode == KEY_F11 or ((k.keycode == KEY_ENTER or k.keycode == KEY_KP_ENTER) and k.alt_pressed):
			_toggle_fullscreen()
			get_viewport().set_input_as_handled()
	elif event is InputEventScreenTouch and (event as InputEventScreenTouch).pressed:
		capturing = ""
		capturing_kbm = ""
		set_active(false)
		set_kbm(false)
	elif event is InputEventMouseButton and (event as InputEventMouseButton).pressed:
		var mb := event as InputEventMouseButton
		if capturing_kbm != "":
			# Bind the click; mark handled so Settings buttons underneath do not press.
			_capture_kbm(kbm_encode_mouse(int(mb.button_index)))
			get_viewport().set_input_as_handled()
			return
		capturing = ""
		set_active(false)
		if _desktop():
			set_kbm(true)
	elif event is InputEventMouseMotion and _desktop() and (event as InputEventMouseMotion).relative.length() > 3.0:
		set_kbm(true)


## F11 or Alt+Enter on a PC: windowed <-> fullscreen (saved like the Settings toggle).
func _toggle_fullscreen() -> void:
	var profile := get_node_or_null("/root/Profile")
	if profile == null or not bool(profile.call("is_desktop")):
		return
	profile.call("set_setting", "fullscreen", not bool(_settings().get("fullscreen", false)))


## Mouse and keyboard on a PC (a pad press or a touch switches back).
func set_kbm(on: bool) -> void:
	if on == kbm:
		return
	kbm = on
	if on and active:
		set_active(false)
		return   # set_active emitted the change
	mode_changed.emit(active)


static func _desktop() -> bool:
	return not OS.has_feature("mobile") and not OS.has_feature("web")


func set_active(on: bool) -> void:
	if on == active:
		return
	if on:
		kbm = false
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
static func hint(touch: String, pad: String, mouse := "") -> String:
	var tree := Engine.get_main_loop() as SceneTree
	var p: Node = tree.root.get_node_or_null("Pad") if tree != null else null
	if p != null and bool(p.get("active")):
		return pad
	if p != null and bool(p.get("kbm")):
		# Mouse and keyboard: its own wording, or the touch text with clicks for taps.
		return mouse if mouse != "" else touch.replace("Tap", "Click").replace("tap", "click").replace("TAP", "CLICK")
	return touch


# --- Fights: the sticks and triggers ---------------------------------------------

## A stick with the deadzone taken out (screen directions, like the thumb sticks).
func stick(left: bool) -> Vector2:
	if sticks_swapped():
		left = not left
	if override.has("left" if left else "right"):
		return override["left" if left else "right"]
	var v := Vector2(Input.get_joy_axis(device, JOY_AXIS_LEFT_X if left else JOY_AXIS_RIGHT_X),
		Input.get_joy_axis(device, JOY_AXIS_LEFT_Y if left else JOY_AXIS_RIGHT_Y))
	var l := v.length()
	if l < DEAD:
		return Vector2.ZERO
	return v / l * clampf((l - DEAD) / (1.0 - DEAD), 0.0, 1.0)


## Is the FIRE button (R2 unless rebound) held?
func fire_held() -> bool:
	if override.has("r2"):
		return bool(override.r2)
	return held("fire")


## Is the button bound to `action` held right now?
func held(action: String) -> bool:
	var code := binding(action)
	if code >= TRIGGER_BASE:
		return Input.get_joy_axis(device, (code - TRIGGER_BASE) as JoyAxis) > TRIGGER
	return code >= 0 and Input.is_joy_button_pressed(device, code as JoyButton)


# --- Button mapping (Settings > CONTROLLER) ---------------------------------------
# Fight actions can be rebound to any pad button, L2 or R2; menus keep the
# D-pad, Cross, Circle and L1 / R1. The map lives in Profile.settings
# ("pad_map": action -> code, "pad_swap": sticks swapped), saved with the
# other settings. Codes are Godot joypad buttons, or TRIGGER_BASE + axis for
# L2 / R2.

const TRIGGER_BASE := 100
const ACTIONS := ["fire", "ability_1", "ability_2", "ability_3", "lock", "crew", "pause"]
const ACTION_NAMES := {"fire": "FIRE", "ability_1": "UTILITY 1", "ability_2": "UTILITY 2", "ability_3": "UTILITY 3",
	"lock": "LOCK", "crew": "CREW WHEEL", "pause": "PAUSE"}
const DEFAULT_MAP := {"fire": TRIGGER_BASE + JOY_AXIS_TRIGGER_RIGHT, "ability_1": JOY_BUTTON_X, "ability_2": JOY_BUTTON_Y,
	"ability_3": JOY_BUTTON_B, "lock": JOY_BUTTON_RIGHT_SHOULDER, "crew": JOY_BUTTON_LEFT_SHOULDER, "pause": JOY_BUTTON_START}
## PlayStation names (Godot's buttons use the Xbox layout's positions).
const BUTTON_NAMES := {JOY_BUTTON_A: "CROSS", JOY_BUTTON_B: "CIRCLE", JOY_BUTTON_X: "SQUARE", JOY_BUTTON_Y: "TRIANGLE",
	JOY_BUTTON_BACK: "CREATE", JOY_BUTTON_GUIDE: "PS", JOY_BUTTON_START: "OPTIONS", JOY_BUTTON_LEFT_STICK: "L3",
	JOY_BUTTON_RIGHT_STICK: "R3", JOY_BUTTON_LEFT_SHOULDER: "L1", JOY_BUTTON_RIGHT_SHOULDER: "R1",
	JOY_BUTTON_DPAD_UP: "D-PAD UP", JOY_BUTTON_DPAD_DOWN: "D-PAD DOWN", JOY_BUTTON_DPAD_LEFT: "D-PAD LEFT",
	JOY_BUTTON_DPAD_RIGHT: "D-PAD RIGHT", JOY_BUTTON_MISC1: "MUTE", JOY_BUTTON_TOUCHPAD: "TOUCHPAD",
	TRIGGER_BASE + JOY_AXIS_TRIGGER_LEFT: "L2", TRIGGER_BASE + JOY_AXIS_TRIGGER_RIGHT: "R2"}

## Mouse and keyboard: WASD / arrows drive, the mouse aims. Fire / lock / pause /
## utilities / CREW are all rebindable (Settings > KEYBOARD & MOUSE). Defaults:
## LMB fire, RMB lock, Esc pause, Q / E / F utilities, Tab crew.
## Mouse buttons are stored as KBM_MOUSE_BASE + MouseButton index.
const KBM_MOUSE_BASE := 1000000
const KBM_DEFAULT := {
	"fire": KBM_MOUSE_BASE + MOUSE_BUTTON_LEFT,
	"lock": KBM_MOUSE_BASE + MOUSE_BUTTON_RIGHT,
	"pause": KEY_ESCAPE,
	"ability_1": KEY_Q, "ability_2": KEY_E, "ability_3": KEY_F, "crew": KEY_TAB,
}
const KBM_KEYS := KBM_DEFAULT   # compat alias for older callers / tests
const KBM_REBIND := ["fire", "lock", "pause", "ability_1", "ability_2", "ability_3", "crew"]
const KBM_NAMES := {"fire": "LEFT CLICK", "lock": "RIGHT CLICK", "ability_1": "Q", "ability_2": "E", "ability_3": "F", "crew": "TAB", "pause": "ESC"}
const KBM_BADGES := {"fire": "LMB", "lock": "RMB", "ability_1": "Q", "ability_2": "E", "ability_3": "F", "crew": "TAB", "pause": "ESC"}
var capturing_kbm := ""   # action waiting for a key/click (Settings), or ""


static func kbm_encode_mouse(button_index: int) -> int:
	return KBM_MOUSE_BASE + button_index


static func kbm_is_mouse(code: int) -> bool:
	return code >= KBM_MOUSE_BASE and code < KBM_MOUSE_BASE + 32


static func kbm_mouse_index(code: int) -> int:
	return code - KBM_MOUSE_BASE if kbm_is_mouse(code) else -1


## Physical key or encoded mouse button currently bound to a KBM action.
func kbm_binding(action: String) -> int:
	var m: Variant = _settings().get("kbm_map", {})
	if m is Dictionary and (m as Dictionary).has(action):
		return int(m[action])
	return int(KBM_DEFAULT.get(action, -1))


## Display name for a KBM binding (mouse button or key).
func kbm_code_name(code: int) -> String:
	if kbm_is_mouse(code):
		match kbm_mouse_index(code):
			MOUSE_BUTTON_LEFT:
				return "LEFT CLICK"
			MOUSE_BUTTON_RIGHT:
				return "RIGHT CLICK"
			MOUSE_BUTTON_MIDDLE:
				return "MIDDLE CLICK"
			MOUSE_BUTTON_XBUTTON1:
				return "MOUSE 4"
			MOUSE_BUTTON_XBUTTON2:
				return "MOUSE 5"
			_:
				return "MOUSE %d" % kbm_mouse_index(code)
	if code == KEY_ESCAPE:
		return "ESC"
	if code >= 0:
		return OS.get_keycode_string(code as Key).to_upper()
	return "?"


## Display name for a KBM action's current binding.
func kbm_button_name(action: String) -> String:
	return kbm_code_name(kbm_binding(action))


## HUD badge for a KBM action (short form of the current binding).
func kbm_badge(action: String) -> String:
	var code := kbm_binding(action)
	if kbm_is_mouse(code):
		match kbm_mouse_index(code):
			MOUSE_BUTTON_LEFT:
				return "LMB"
			MOUSE_BUTTON_RIGHT:
				return "RMB"
			MOUSE_BUTTON_MIDDLE:
				return "MMB"
			_:
				return "M%d" % kbm_mouse_index(code)
	var name := kbm_code_name(code)
	return name.left(3) if name.length() > 3 else name


## True while the bound fire input is held (mouse button or key).
func kbm_fire_held() -> bool:
	var code := kbm_binding("fire")
	if kbm_is_mouse(code):
		return Input.is_mouse_button_pressed(kbm_mouse_index(code) as MouseButton)
	return code >= 0 and Input.is_physical_key_pressed(code as Key)


## True if this event triggers pause: the pause binding, or Esc as hard fallback
## so pause is never lost when rebound away from Esc.
func kbm_is_pause_event(event: InputEvent) -> bool:
	if event is InputEventKey and (event as InputEventKey).pressed and not (event as InputEventKey).echo:
		var key := event as InputEventKey
		if key.keycode == KEY_ESCAPE or int(key.physical_keycode) == KEY_ESCAPE:
			return true   # Esc always pauses (fallback if pause was rebound)
		return int(key.physical_keycode) == kbm_binding("pause")
	if event is InputEventMouseButton and (event as InputEventMouseButton).pressed:
		var code := kbm_binding("pause")
		return kbm_is_mouse(code) and kbm_mouse_index(code) == int((event as InputEventMouseButton).button_index)
	return false


## The fight action a key/mouse code is bound to, or "".
func kbm_action_of(code: int) -> String:
	for a: String in KBM_REBIND:
		if kbm_binding(a) == code:
			return a
	return ""


## Static entry (preload callers): prefers the live Pad map.
static func kbm_action(code: int) -> String:
	var tree := Engine.get_main_loop() as SceneTree
	var node: Node = tree.root.get_node_or_null("Pad") if tree != null else null
	if node != null and node.has_method("kbm_action_of"):
		return str(node.call("kbm_action_of", code))
	for a: String in KBM_DEFAULT:
		if int(KBM_DEFAULT[a]) == code:
			return a
	return ""


## The WASD / arrow keys as a stick (screen directions).
static func kbm_drive() -> Vector2:
	var v := Vector2(
		float(Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT)) - float(Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT)),
		float(Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN)) - float(Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP)))
	return v.normalized()


signal map_changed
var capturing := ""          # an action waiting for its new button (Settings), or ""
var _trig_down := [false, false]


func _settings() -> Dictionary:
	var profile := get_node_or_null("/root/Profile")
	return profile.get("settings") if profile != null else {}


## The code bound to `action` (DEFAULT_MAP unless rebound).
func binding(action: String) -> int:
	var m: Variant = _settings().get("pad_map", {})
	if m is Dictionary and (m as Dictionary).has(action):
		return int(m[action])
	return int(DEFAULT_MAP.get(action, -1))


## The fight action a pressed code is bound to, or "".
func action_for(code: int) -> String:
	for a: String in ACTIONS:
		if binding(a) == code:
			return a
	return ""


## "R2", "SQUARE"... for an action's button.
func button_name(action: String) -> String:
	return code_name(binding(action))


static func code_name(code: int) -> String:
	return str(BUTTON_NAMES.get(code, "BUTTON %d" % code))


## The HUD badge for an action: a face-button shape, or its short name.
func badge(action: String) -> String:
	var code := binding(action)
	match code:
		JOY_BUTTON_A:
			return "cross"
		JOY_BUTTON_B:
			return "circle"
		JOY_BUTTON_X:
			return "square"
		JOY_BUTTON_Y:
			return "triangle"
	var n := code_name(code)
	return {"OPTIONS": "OPT", "CREATE": "CRT", "TOUCHPAD": "PAD", "D-PAD UP": "UP", "D-PAD DOWN": "DN",
		"D-PAD LEFT": "LT", "D-PAD RIGHT": "RT", "MUTE": "MUT"}.get(n, n.left(3))


## Bind `action` to `code`. An action already on that button swaps over to
## this one's old button, so nothing is ever left unbound.
func bind(action: String, code: int) -> void:
	var m := {}
	for a: String in ACTIONS:
		m[a] = binding(a)
	var old: int = m[action]
	for a: String in ACTIONS:
		if a != action and int(m[a]) == code:
			m[a] = old
	m[action] = code
	_store("pad_map", m)


func reset_map() -> void:
	_store("pad_map", DEFAULT_MAP.duplicate())
	_store("pad_swap", false)


## Left stick aims and right stick drives (Settings).
func sticks_swapped() -> bool:
	return bool(_settings().get("pad_swap", false))


func set_sticks_swapped(on: bool) -> void:
	_store("pad_swap", on)


## Wait for the next pad press and bind it to `action`.
func start_capture(action: String) -> void:
	capturing = action
	capturing_kbm = ""


func cancel_capture() -> void:
	capturing = ""


func start_kbm_capture(action: String) -> void:
	capturing_kbm = action
	capturing = ""


func cancel_kbm_capture() -> void:
	capturing_kbm = ""
	map_changed.emit()


## Bind `action` to `code` (key or encoded mouse). An action already on that
## input swaps over so nothing is left unbound. Refuses a bind that would leave
## pause with no code (should not happen with swap, but guarded anyway).
func bind_kbm(action: String, code: int) -> bool:
	if action not in KBM_REBIND or code < 0:
		return false
	var m := {}
	for a: String in KBM_REBIND:
		m[a] = kbm_binding(a)
	var old_code: int = int(m[action])
	for a: String in KBM_REBIND:
		if a != action and int(m[a]) == code:
			m[a] = old_code
	m[action] = code
	if int(m.get("pause", -1)) < 0:
		return false   # pause must never end up unbound
	_store("kbm_map", m)
	return true


func reset_kbm_map() -> void:
	_store("kbm_map", KBM_DEFAULT.duplicate())


func _capture_kbm(code: int) -> void:
	var a := capturing_kbm
	capturing_kbm = ""
	if a != "":
		bind_kbm(a, code)


func _capture(code: int) -> void:
	var a := capturing
	capturing = ""
	bind(a, code)


func _store(key: String, value: Variant) -> void:
	var profile := get_node_or_null("/root/Profile")
	if profile != null:
		profile.call("set_setting", key, value)
	map_changed.emit()


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
		if c == null or not c.is_visible_in_tree() or c.is_queued_for_deletion():
			continue
		if best == null or c.is_greater_than(best):
			best = c
	return best


# --- Menus: focus ----------------------------------------------------------------

func _process(delta: float) -> void:
	if not active:
		_ring.target = null
		return
	_scroll_lists(delta)
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
	# Driving with no menu up: nothing to focus, so skip the tree scan after
	# the first pass turned focus off (a fight has a lot of nodes).
	if want or _focus_on:
		_apply_focus(want, modal)
		_focus_on = want
	var owner := get_viewport().gui_get_focus_owner()
	if want and (owner == null or not owner.is_visible_in_tree() or owner.focus_mode == Control.FOCUS_NONE):
		var first := _first_button(modal)
		if first != null:
			first.grab_focus()
	elif not want and owner != null:
		owner.release_focus()
	_ring.target = get_viewport().gui_get_focus_owner() if want else null


var _focus_on := true   # focus was last turned on (so a scan is needed to turn it off)


## Buttons (and sliders) that may take focus now: visible, enabled, and
## inside the open modal if there is one. Scroll boxes follow the focus.
func _apply_focus(on: bool, modal: Control) -> void:
	for b: Node in get_tree().root.find_children("*", "BaseButton", true, false):
		var button := b as BaseButton
		var ok := on and button.is_visible_in_tree() and not button.disabled and (modal == null or modal.is_ancestor_of(button))
		button.focus_mode = Control.FOCUS_ALL if ok else Control.FOCUS_NONE
	for sl: Node in get_tree().root.find_children("*", "Slider", true, false):
		var slider := sl as Slider
		var ok := on and slider.is_visible_in_tree() and slider.editable and (modal == null or modal.is_ancestor_of(slider))
		slider.focus_mode = Control.FOCUS_ALL if ok else Control.FOCUS_NONE
	if on:
		for s: Node in get_tree().root.find_children("*", "ScrollContainer", true, false):
			(s as ScrollContainer).follow_focus = true


## The right stick scrolls a list that has no buttons to step through (the
## Database, long notes): the first visible scroll box in the open panel.
func _scroll_lists(delta: float) -> void:
	if not _focus_on:
		return   # driving: the stick aims
	var y := stick(false).y
	if absf(y) < 0.2:
		return
	var root: Node = top_modal()
	if root == null:
		root = get_tree().current_scene
	if root == null:
		return
	for s: Node in root.find_children("*", "ScrollContainer", true, false):
		var box := s as ScrollContainer
		if box.is_visible_in_tree() and box.get_v_scroll_bar().visible:
			box.scroll_vertical += int(y * 900.0 * delta)
			return


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
		draw_rect(r, T.COL_UI_ACCENT, false, 3.0)
