extends CanvasLayer
## Minimal combat HUD: armor bar, objective, FPS readout, twin sticks, lock
## button, utility buttons, event banners, threat arrows, and the results
## card. The vehicle stays the visual focus.

signal restart_requested
signal pause_pressed
signal lock_toggled(on: bool)
signal ability_pressed(index: int)
signal crew_picked(index: int)
signal crew_wheel_toggled(open: bool)
signal choice_made(yes: bool)

const T := preload("res://scripts/tuning.gd")
const ThumbStick := preload("res://scripts/thumb_stick.gd")

var left_stick: ThumbStick
var right_stick: ThumbStick

var _root: Control
var _armor_bar: ArmorBar
var _rig_icon: RigIcon
var _status_strip: StatusStrip
var _power_bar: PowerBar
var _arrows: ThreatArrows
var _lock_button: LockButton
var _ability_buttons: Array[AbilityButton] = []
var _crew_button: CrewButton
var _wheel: CrewWheel
var crew_wheel_cooldown := 0.0
var _status: Label
var _fps: Label
var pause_button: Button
var tip: Label                     # the tutorial's instructions
var _hint: Label
var _banner: Label
var _banner_tween: Tween
var _alert: Label
var _overlay: Control
var _choice: Control             # the Escort driver's radio call
var _title: Label
var _subtitle: Label
var _button: Button
var _fps_timer := 0.0
var _alert_t := 0.0


func _ready() -> void:
	layer = 10
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)

	_rig_icon = RigIcon.new()
	_rig_icon.position = Vector2(20, 10)
	_rig_icon.size = Vector2(64, 76)
	_root.add_child(_rig_icon)

	_status_strip = StatusStrip.new()
	_status_strip.position = Vector2(20, 90)
	_status_strip.size = Vector2(150, 70)
	_root.add_child(_status_strip)

	_armor_bar = ArmorBar.new()
	_armor_bar.position = Vector2(94, 18)
	_armor_bar.size = Vector2(300, 16)
	_root.add_child(_armor_bar)

	_power_bar = PowerBar.new()
	_power_bar.position = Vector2(94, 38)
	_power_bar.size = Vector2(300, 8)
	_root.add_child(_power_bar)

	_status = _label(24, Color(0.85, 0.83, 0.78))
	_status.position = Vector2(94, 52)
	_root.add_child(_status)

	_fps = _label(20, Color(0.6, 0.6, 0.58))
	_fps.anchor_left = 1.0
	_fps.anchor_right = 1.0
	_fps.offset_left = -320.0
	_fps.offset_right = -24.0
	_fps.offset_top = 14.0
	_fps.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_root.add_child(_fps)

	_banner = _centered_label(30, T.COL_ORANGE, 96.0)
	_banner.modulate.a = 0.0
	_alert = _centered_label(26, T.COL_ENEMY, 140.0)
	_alert.visible = false

	_hint = _label(22, Color(0.85, 0.83, 0.78))
	_hint.text = "LEFT THUMB  DRIVE      RIGHT THUMB  AIM + FIRE      LOCK  AUTO-AIM"
	_hint.anchor_left = 0.0
	_hint.anchor_right = 1.0
	_hint.anchor_top = 1.0
	_hint.anchor_bottom = 1.0
	_hint.offset_top = -56.0
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_root.add_child(_hint)
	var fade := create_tween()
	fade.tween_interval(7.0)
	fade.tween_property(_hint, "modulate:a", 0.0, 1.0)

	_arrows = ThreatArrows.new()
	_arrows.set_anchors_preset(Control.PRESET_FULL_RECT)
	_arrows.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_arrows)

	left_stick = ThumbStick.new()
	left_stick.left_side = true
	_root.add_child(left_stick)
	right_stick = ThumbStick.new()
	right_stick.left_side = false
	_root.add_child(right_stick)

	# Above the right stick, in reach of the right thumb.
	_lock_button = LockButton.new()
	_lock_button.anchor_left = 1.0
	_lock_button.anchor_right = 1.0
	_lock_button.anchor_top = 1.0
	_lock_button.anchor_bottom = 1.0
	_lock_button.offset_left = -170.0
	_lock_button.offset_right = -60.0
	_lock_button.offset_top = -450.0
	_lock_button.offset_bottom = -340.0
	_lock_button.toggled.connect(func(on: bool) -> void: lock_toggled.emit(on))
	_root.add_child(_lock_button)
	right_stick.blockers.append(_lock_button)
	pause_button = Button.new()
	pause_button.text = "II"
	pause_button.focus_mode = Control.FOCUS_NONE
	pause_button.anchor_left = 1.0
	pause_button.anchor_right = 1.0
	pause_button.offset_left = -96.0
	pause_button.offset_right = -24.0
	pause_button.offset_top = 46.0
	pause_button.offset_bottom = 110.0
	pause_button.add_theme_font_size_override("font_size", 28)
	pause_button.pressed.connect(func() -> void: pause_pressed.emit())
	_root.add_child(pause_button)
	tip = _label(26, Color(1.0, 0.92, 0.7))
	tip.anchor_left = 0.5
	tip.anchor_right = 0.5
	tip.offset_left = -430.0
	tip.offset_right = 430.0
	tip.offset_top = 150.0
	tip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tip.autowrap_mode = TextServer.AUTOWRAP_WORD
	tip.visible = false
	_root.add_child(tip)
	right_stick.blockers.append(pause_button)

	_crew_button = CrewButton.new()
	_crew_button.anchor_left = 1.0
	_crew_button.anchor_right = 1.0
	_crew_button.anchor_top = 1.0
	_crew_button.anchor_bottom = 1.0
	_crew_button.offset_top = -444.0
	_crew_button.offset_bottom = -340.0
	_crew_button.visible = false
	_crew_button.pressed.connect(func() -> void: open_crew_wheel())
	_root.add_child(_crew_button)
	right_stick.blockers.append(_crew_button)

	_wheel = CrewWheel.new()
	_wheel.set_anchors_preset(Control.PRESET_FULL_RECT)
	_wheel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_wheel.visible = false
	_wheel.picked.connect(func(i: int) -> void: pick_crew(i))
	_wheel.closed.connect(func() -> void: close_crew_wheel())
	_root.add_child(_wheel)

	_build_overlay()


## One round button per utility part ("patch", "mines"), in a row left of
## LOCK and the CREW button. Built at mission start.
func set_abilities(kinds: Array[String]) -> void:
	for b in _ability_buttons:
		right_stick.blockers.erase(b)
		b.queue_free()
	_ability_buttons.clear()
	for i in kinds.size():
		var b := AbilityButton.new()
		b.kind = kinds[i]
		b.anchor_left = 1.0
		b.anchor_right = 1.0
		b.anchor_top = 1.0
		b.anchor_bottom = 1.0
		b.offset_top = -444.0
		b.offset_bottom = -340.0
		b.pressed.connect(func() -> void: ability_pressed.emit(i))
		_root.add_child(b)
		_ability_buttons.append(b)
		right_stick.blockers.append(b)
	_layout_buttons()


## Right to left: LOCK (if any), CREW (if any crew), then utilities.
func _layout_buttons() -> void:
	var right := -60.0
	if _lock_button.visible:
		right -= 130.0
	if _crew_button.visible:
		_crew_button.offset_right = right
		_crew_button.offset_left = right - 104.0
		right -= 124.0
	for b in _ability_buttons:
		b.offset_right = right
		b.offset_left = right - 104.0
		right -= 124.0


## The crew on the rig, for the CREW wheel: one entry each with "kind",
## "ability" (name), "name" and "role". Empty hides the CREW button.
func set_crew_wheel(entries: Array[Dictionary]) -> void:
	_wheel.entries = entries.duplicate(true)
	_wheel.charges.resize(entries.size())
	_wheel.charges.fill(0.0)
	_wheel.off.resize(entries.size())
	_wheel.off.fill(false)
	_wheel.notes.resize(entries.size())
	_wheel.notes.fill("")
	_crew_button.visible = not entries.is_empty()
	_layout_buttons()
	_wheel.queue_redraw()


## Crew member `index`: cooldown (0 ready, 1 just used), greyed out, and why.
func set_crew_state(index: int, charge: float, disabled: bool, note := "") -> void:
	if index < 0 or index >= _wheel.entries.size():
		return
	if absf(_wheel.charges[index] - charge) >= 0.01 or _wheel.off[index] != disabled or _wheel.notes[index] != note or (charge == 0.0 and _wheel.charges[index] != 0.0):
		_wheel.charges[index] = charge
		_wheel.off[index] = disabled
		_wheel.notes[index] = note
		if _wheel.visible:
			_wheel.queue_redraw()
	var any := false
	for i in _wheel.entries.size():
		any = any or (_wheel.charges[i] <= 0.0 and not _wheel.off[i])
	_crew_button.set_state(any, crew_wheel_cooldown / T.CREW_WHEEL_COOLDOWN)


## Opens the crew wheel (slow motion, via crew_wheel_toggled) unless it's
## cooling down.
func open_crew_wheel() -> bool:
	if _wheel.visible or not _crew_button.visible or crew_wheel_cooldown > 0.0 or _overlay.visible:
		return false
	_wheel.visible = true
	_wheel.queue_redraw()
	right_stick.enabled = false
	crew_wheel_toggled.emit(true)
	return true


## Closes the wheel; starts its cooldown unless the run just ended.
func close_crew_wheel(cooldown := true) -> void:
	if not _wheel.visible:
		return
	_wheel.visible = false
	if not _overlay.visible:
		right_stick.enabled = true
	if cooldown:
		crew_wheel_cooldown = T.CREW_WHEEL_COOLDOWN
	crew_wheel_toggled.emit(false)


## Fire crew member `index` from the open wheel, if it's ready.
func pick_crew(index: int) -> bool:
	if not _wheel.visible or index < 0 or index >= _wheel.entries.size():
		return false
	if _wheel.charges[index] > 0.0 or _wheel.off[index]:
		return false
	crew_picked.emit(index)
	close_crew_wheel()
	return true


func is_crew_wheel_open() -> bool:
	return _wheel.visible


func has_crew_button() -> bool:
	return _crew_button.visible


## Test hook: crew slice `index` is greyed out (injured, or nothing to do).
func is_crew_disabled(index: int) -> bool:
	return index >= 0 and index < _wheel.off.size() and _wheel.off[index]


func crew_wheel_size() -> int:
	return _wheel.entries.size()


## 0 = ready, 1 = just used.
func set_ability_charge(index: int, charge: float) -> void:
	if index >= 0 and index < _ability_buttons.size():
		_ability_buttons[index].set_charge(charge)


## Greys a button out (an injured crew member's ability).
func set_ability_disabled(index: int, off: bool) -> void:
	if index >= 0 and index < _ability_buttons.size():
		_ability_buttons[index].set_disabled(off)


func is_ability_disabled(index: int) -> bool:
	return index >= 0 and index < _ability_buttons.size() and _ability_buttons[index].disabled


func ability_count() -> int:
	return _ability_buttons.size()


## Test hook: same as tapping utility button `index`.
func press_ability(index: int) -> void:
	if index >= 0 and index < _ability_buttons.size():
		_ability_buttons[index].press()


func set_armor(ratio: float) -> void:
	_armor_bar.set_ratio(ratio)


## The rig icon (§14): shield ring, each facing's plate, the HP block. All
## 0..1; a facing with no armor fitted is -1 (drawn empty).
func set_defense(shield_ratio: float, facings: PackedFloat32Array, hp_ratio: float) -> void:
	_rig_icon.set_values(shield_ratio, facings, hp_ratio)


## Status buildup (0..100 per bar) and seconds left on each active status
## (§14), shown under the rig icon only while something's building or on.
func set_statuses(build: PackedFloat32Array, left: PackedFloat32Array) -> void:
	_status_strip.set_values(build, left)


func status_strip_visible() -> bool:
	return _status_strip.showing


func defense_icon_values() -> Dictionary:
	return {"shield": _rig_icon.shield, "facings": _rig_icon.facings, "hp": _rig_icon.hp}


## Power in use vs the engine's budget, and weight vs the chassis's capacity.
## Over either budget shows as an overload.
func set_power(used: float, output: float, weight := 0.0, capacity := 0.0) -> void:
	_power_bar.set_values(used, output, weight, capacity)


## Only rigs with a targeting system (and a lock-capable weapon) get the button.
func set_lock_available(available: bool) -> void:
	_lock_button.visible = available
	_layout_buttons()
	_hint.text = "LEFT THUMB  DRIVE      RIGHT THUMB  AIM + FIRE" + ("      LOCK  AUTO-AIM" if available else "")


func set_status(kills: int, target: int, scrap: int) -> void:
	_status.text = "CLEAR  %d / %d      SCRAP  %d" % [kills, target, scrap]


## The objective line under the bars; each mission type writes its own.
func set_status_text(text: String) -> void:
	_status.text = text


## Screen-space positions (and colors) of threats to point at when off-screen.
func set_threats(points: PackedVector2Array, colors: PackedColorArray) -> void:
	_arrows.set_points(points, colors)


## Lock state as the game sees it (on/off, and whether something is locked).
func set_lock_state(on: bool, has_target: bool) -> void:
	_lock_button.set_state(on, has_target)


## Test/keyboard hook: same as tapping the lock button.
func press_lock() -> void:
	if _lock_button.visible:
		_lock_button.press()


func is_lock_button_visible() -> bool:
	return _lock_button.visible


## A short message that fades out (enemy inbound, salvage picked up...).
func banner(text: String, color: Color, seconds := 2.5) -> void:
	_banner.text = text
	_banner.add_theme_color_override("font_color", color)
	if _banner_tween != null:
		_banner_tween.kill()
	_banner.modulate.a = 1.0
	_banner_tween = create_tween()
	_banner_tween.tween_interval(seconds)
	_banner_tween.tween_property(_banner, "modulate:a", 0.0, 0.6)


## A warning that stays (and pulses) until cleared with an empty string.
func set_alert(text: String) -> void:
	_alert.text = text
	_alert.visible = text != ""


func _process(delta: float) -> void:
	if crew_wheel_cooldown > 0.0 and not _wheel.visible:
		crew_wheel_cooldown = maxf(crew_wheel_cooldown - delta, 0.0)
		_crew_button.set_state(_crew_button.has_ready, crew_wheel_cooldown / T.CREW_WHEEL_COOLDOWN)
	_fps_timer -= delta
	if _fps_timer <= 0.0:
		_fps_timer = 0.25
		var version := str(ProjectSettings.get_setting("application/config/version", ""))
		_fps.text = "%d FPS   v%s" % [Engine.get_frames_per_second(), version]
	if _alert.visible:
		_alert_t += delta
		_alert.modulate.a = 0.6 + 0.4 * sin(_alert_t * 10.0)


func show_result(title: String, subtitle: String, button_text: String, accent: Color) -> void:
	left_stick.enabled = false
	right_stick.enabled = false
	_lock_button.visible = false
	close_crew_wheel(false)
	_crew_button.visible = false
	for b in _ability_buttons:
		b.visible = false
	set_alert("")
	_title.text = title
	_title.add_theme_color_override("font_color", accent)
	_subtitle.text = subtitle
	_button.text = button_text
	_overlay.visible = true
	_overlay.modulate.a = 0.0
	create_tween().tween_property(_overlay, "modulate:a", 1.0, 0.35)


## A paused, two-way choice (the Escort driver's radio call). The mission
## pauses the game while it's open; this panel keeps running.
func show_choice(speaker: String, text: String, yes_text: String, no_text: String) -> void:
	close_choice()
	_choice = Control.new()
	_choice.set_anchors_preset(Control.PRESET_FULL_RECT)
	_choice.process_mode = Node.PROCESS_MODE_ALWAYS
	_root.add_child(_choice)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_choice.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_choice.add_child(center)
	var panel := PanelContainer.new()
	var box := StyleBoxFlat.new()
	box.bg_color = Color(0.08, 0.085, 0.09, 0.97)
	box.border_color = T.COL_TRUCK
	box.set_border_width_all(3)
	box.content_margin_left = 24
	box.content_margin_right = 24
	box.content_margin_top = 18
	box.content_margin_bottom = 18
	panel.add_theme_stylebox_override("panel", box)
	panel.custom_minimum_size = Vector2(720, 0)
	center.add_child(panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 14)
	panel.add_child(column)
	var who := Label.new()
	who.text = speaker
	who.add_theme_font_size_override("font_size", 22)
	who.add_theme_color_override("font_color", T.COL_TRUCK)
	column.add_child(who)
	var said := Label.new()
	said.text = text
	said.autowrap_mode = TextServer.AUTOWRAP_WORD
	said.custom_minimum_size = Vector2(670, 0)
	said.add_theme_font_size_override("font_size", 24)
	column.add_child(said)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	column.add_child(row)
	for pick: Array in [[yes_text, true, T.COL_ORANGE], [no_text, false, Color(0.75, 0.75, 0.72)]]:
		var b := Button.new()
		b.text = str(pick[0])
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(320, 64)
		b.add_theme_font_size_override("font_size", 22)
		b.add_theme_color_override("font_color", pick[2])
		b.pressed.connect(pick_choice.bind(bool(pick[1])))
		row.add_child(b)


func is_choice_open() -> bool:
	return _choice != null


## Answer the open choice (its buttons call this; tests can too).
func pick_choice(yes: bool) -> void:
	if _choice == null:
		return
	close_choice()
	choice_made.emit(yes)


func close_choice() -> void:
	if _choice != null:
		_choice.queue_free()
		_choice = null


func is_result_visible() -> bool:
	return _overlay.visible


func result_text() -> String:
	return _title.text + " | " + _subtitle.text


func _build_overlay() -> void:
	_overlay = Control.new()
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.visible = false
	_root.add_child(_overlay)

	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0.03, 0.03, 0.035, 0.72)
	_overlay.add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.add_child(center)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 18)
	center.add_child(column)

	_title = _label(72, T.COL_ORANGE)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(_title)

	_subtitle = _label(26, Color(0.8, 0.78, 0.74))
	_subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(_subtitle)

	_button = Button.new()
	_button.custom_minimum_size = Vector2(340, 84)
	_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_button.add_theme_font_size_override("font_size", 30)
	_button.add_theme_color_override("font_color", Color(0.95, 0.93, 0.88))
	_button.add_theme_stylebox_override("normal", _box(Color(0.12, 0.12, 0.13), T.COL_ORANGE))
	_button.add_theme_stylebox_override("hover", _box(Color(0.16, 0.16, 0.17), T.COL_ORANGE))
	_button.add_theme_stylebox_override("pressed", _box(Color(0.3, 0.16, 0.07), T.COL_ORANGE))
	_button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	_button.pressed.connect(func() -> void: restart_requested.emit())
	column.add_child(_button)


func _label(font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	label.add_theme_constant_override("outline_size", 6)
	return label


func _centered_label(font_size: int, color: Color, top: float) -> Label:
	var label := _label(font_size, color)
	label.anchor_left = 0.0
	label.anchor_right = 1.0
	label.offset_top = top
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_root.add_child(label)
	return label


func _box(fill: Color, border: Color) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = fill
	box.border_color = border
	box.set_border_width_all(3)
	return box


class LockButton extends Control:
	## Round toggle. Handles its own touches; the right stick ignores this area.
	signal toggled(on: bool)
	const T := preload("res://scripts/tuning.gd")
	var on := false
	var has_target := false

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func press() -> void:
		on = not on
		toggled.emit(on)
		queue_redraw()

	func set_state(value: bool, target: bool) -> void:
		if value != on or target != has_target:
			on = value
			has_target = target
			queue_redraw()

	func _input(event: InputEvent) -> void:
		if not visible or not event is InputEventScreenTouch:
			return
		var touch := event as InputEventScreenTouch
		if touch.pressed and get_global_rect().has_point(touch.position):
			press()
			get_viewport().set_input_as_handled()

	func _draw() -> void:
		var c := size * 0.5
		var r := minf(size.x, size.y) * 0.5 - 4.0
		var accent := T.COL_ORANGE if on else Color(0.7, 0.68, 0.64)
		draw_circle(c, r, Color(0.0, 0.0, 0.0, 0.55 if on else 0.35))
		draw_arc(c, r, 0.0, TAU, 40, Color(accent, 0.9 if on else 0.5), 4.0 if on else 2.5)
		# Crosshair brackets.
		var s := r * 0.45
		for corner: Vector2 in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
			var p := c + corner * s
			draw_line(p, p - Vector2(corner.x * 9.0, 0.0), accent, 3.0)
			draw_line(p, p - Vector2(0.0, corner.y * 9.0), accent, 3.0)
		if on and has_target:
			draw_circle(c, 5.0, accent)
		var font := ThemeDB.fallback_font
		draw_string(font, Vector2(0.0, size.y + 18.0), "LOCK", HORIZONTAL_ALIGNMENT_CENTER, size.x, 18, Color(accent, 0.9))


class ThreatArrows extends Control:
	## Chevrons on the screen edge pointing at off-screen threats.
	const MARGIN := 48.0
	var points := PackedVector2Array()
	var colors := PackedColorArray()

	func set_points(value: PackedVector2Array, tint: PackedColorArray) -> void:
		if value.is_empty() and points.is_empty():
			return
		points = value
		colors = tint
		queue_redraw()

	func _draw() -> void:
		var area := Rect2(Vector2.ZERO, size).grow(-MARGIN)
		var center := area.get_center()
		for i in points.size():
			var p := points[i]
			if area.grow(MARGIN).has_point(p):
				continue  # on screen already
			var dir := (p - center).normalized()
			# Walk from the centre toward the threat until we hit the inset edge.
			var tx := INF if is_zero_approx(dir.x) else (area.size.x * 0.5) / absf(dir.x)
			var ty := INF if is_zero_approx(dir.y) else (area.size.y * 0.5) / absf(dir.y)
			var tip := center + dir * minf(tx, ty)
			var side := dir.orthogonal() * 12.0
			var color := colors[i] if i < colors.size() else Color(1, 0.5, 0.2)
			draw_colored_polygon(PackedVector2Array([tip + dir * 14.0, tip - dir * 8.0 + side, tip - dir * 8.0 - side]), Color(color, 0.85))


class AbilityButton extends Control:
	## Round utility button with a cooldown sweep. Handles its own touches;
	## the right stick ignores this area.
	signal pressed
	const T := preload("res://scripts/tuning.gd")
	const LABELS := {"patch": "PATCH", "mines": "MINES", "oil": "OIL", "spikes": "SPIKES", "pulse": "PULSE", "hard_line": "HARD LINE", "overcharge": "OVERCHARGE"}
	var kind := ""      # "hard_line", "overcharge", "patch", "mines" or "oil"
	var charge := 0.0   # 0 ready, 1 just used
	var disabled := false

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func press() -> void:
		if not disabled:
			pressed.emit()

	func set_disabled(off: bool) -> void:
		if off != disabled:
			disabled = off
			queue_redraw()

	func set_charge(value: float) -> void:
		# Redraw in small steps, not every frame.
		if absf(value - charge) >= 0.01 or (value == 0.0 and charge != 0.0):
			charge = value
			queue_redraw()

	func _input(event: InputEvent) -> void:
		if not visible or not event is InputEventScreenTouch:
			return
		var touch := event as InputEventScreenTouch
		if touch.pressed and get_global_rect().has_point(touch.position):
			press()
			get_viewport().set_input_as_handled()

	func _draw() -> void:
		var c := size * 0.5
		var r := minf(size.x, size.y) * 0.5 - 4.0
		var is_ready := charge <= 0.0 and not disabled
		var accent: Color = {"patch": Color(0.45, 0.9, 0.5), "hard_line": T.COL_CYAN, "overcharge": Color(1.0, 0.92, 0.7)}.get(kind, T.COL_ORANGE)
		var tint := accent if is_ready else Color(0.6, 0.58, 0.55)
		if disabled:
			tint = Color(0.42, 0.4, 0.38)
		draw_circle(c, r, Color(0.0, 0.0, 0.0, 0.5))
		if not is_ready and not disabled:
			# Dark wedge for the time left, shrinking clockwise.
			var shade := Color(0.0, 0.0, 0.0, 0.45)
			if charge >= 0.97:
				draw_circle(c, r, shade)
			elif charge > 0.02:
				var points := PackedVector2Array([c])
				var steps := maxi(2, ceili(32.0 * charge))
				for k in steps + 1:
					var ang := -PI / 2.0 + TAU * charge * float(k) / steps
					points.append(c + Vector2.RIGHT.rotated(ang) * r)
				draw_colored_polygon(points, shade)
		draw_arc(c, r, 0.0, TAU, 40, Color(tint, 0.9 if is_ready else 0.5), 4.0 if is_ready else 2.5)
		match kind:
			"patch":
				draw_rect(Rect2(c - Vector2(5, 16), Vector2(10, 32)), tint)
				draw_rect(Rect2(c - Vector2(16, 5), Vector2(32, 10)), tint)
			"mines":
				for k in 3:
					var p := c + Vector2(-16.0 + k * 16.0, 0.0)
					draw_circle(p, 6.0, tint)
					draw_circle(p, 2.0, Color(0, 0, 0, 0.7))
			"spikes":
				# A strip of teeth.
				draw_line(c + Vector2(-18, 4), c + Vector2(18, 4), tint, 4.0)
				for k in 5:
					var x := c.x - 16.0 + k * 8.0
					draw_colored_polygon(PackedVector2Array([Vector2(x - 3.0, c.y + 2.0), Vector2(x, c.y - 10.0), Vector2(x + 3.0, c.y + 2.0)]), tint)
			"pulse":
				# A spark inside two rings.
				draw_arc(c, 8.0, 0.0, TAU, 16, tint, 2.5)
				draw_arc(c, 16.0, 0.0, TAU, 24, Color(tint, 0.6), 2.0)
				draw_polyline(PackedVector2Array([c + Vector2(-3, -12), c + Vector2(3, -2), c + Vector2(-3, 2), c + Vector2(3, 12)]), tint, 2.5)
			"oil":
				# A drop over a puddle.
				draw_colored_polygon(PackedVector2Array([c + Vector2(0, -18), c + Vector2(8, -2), c + Vector2(-8, -2)]), tint)
				draw_circle(c + Vector2(0, -2), 8.0, tint)
				draw_arc(c + Vector2(0, 14), 14.0, PI + 0.4, TAU - 0.4, 12, tint, 3.0)
			"hard_line":
				# Two chevrons: a sharp line through the turn.
				for k in 2:
					var x := c.x - 10.0 + k * 14.0
					draw_polyline(PackedVector2Array([Vector2(x - 6.0, c.y - 14.0), Vector2(x + 6.0, c.y), Vector2(x - 6.0, c.y + 14.0)]), tint, 4.0)
			"overcharge":
				# A lightning bolt.
				draw_colored_polygon(PackedVector2Array([c + Vector2(4, -20), c + Vector2(-10, 3), c + Vector2(-1, 3),
					c + Vector2(-5, 20), c + Vector2(10, -4), c + Vector2(1, -4)]), tint)
		if disabled:
			draw_line(c + Vector2(-r * 0.6, -r * 0.6), c + Vector2(r * 0.6, r * 0.6), T.COL_ENEMY, 3.0)
		var font := ThemeDB.fallback_font
		var label: String = LABELS.get(kind, kind.to_upper())
		if disabled:
			label = "INJURED"
		draw_string(font, Vector2(-20.0, size.y + 18.0), label, HORIZONTAL_ALIGNMENT_CENTER, size.x + 40.0, 15, Color(tint, 0.9))


class CrewButton extends Control:
	## Opens the crew wheel. A dot when any crew ability is ready; a sweep
	## while the wheel itself cools down.
	signal pressed
	const T := preload("res://scripts/tuning.gd")
	var has_ready := false
	var cooldown := 0.0   # 0..1

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func set_state(any_ready: bool, cool: float) -> void:
		cool = clampf(cool, 0.0, 1.0)
		if any_ready != has_ready or absf(cool - cooldown) >= 0.02 or (cool == 0.0 and cooldown != 0.0):
			has_ready = any_ready
			cooldown = cool
			queue_redraw()

	func _input(event: InputEvent) -> void:
		if not visible or not event is InputEventScreenTouch:
			return
		var touch := event as InputEventScreenTouch
		if touch.pressed and get_global_rect().has_point(touch.position):
			pressed.emit()
			get_viewport().set_input_as_handled()

	func _draw() -> void:
		var c := size * 0.5
		var r := minf(size.x, size.y) * 0.5 - 4.0
		var tint := Color(0.95, 0.93, 0.88) if cooldown <= 0.0 else Color(0.55, 0.53, 0.5)
		draw_circle(c, r, Color(0, 0, 0, 0.5))
		if cooldown > 0.02:
			var points := PackedVector2Array([c])
			var steps := maxi(2, ceili(32.0 * cooldown))
			for k in steps + 1:
				points.append(c + Vector2.RIGHT.rotated(-PI / 2.0 + TAU * cooldown * float(k) / steps) * r)
			if cooldown < 0.97:
				draw_colored_polygon(points, Color(0, 0, 0, 0.45))
			else:
				draw_circle(c, r, Color(0, 0, 0, 0.45))
		draw_arc(c, r, 0.0, TAU, 40, Color(tint, 0.85), 3.0)
		# Three heads: the crew.
		for k in 3:
			var p := c + Vector2(-16.0 + k * 16.0, -2.0)
			draw_circle(p, 6.0, tint)
			draw_rect(Rect2(p + Vector2(-6.0, 7.0), Vector2(12.0, 7.0)), tint)
		if has_ready and cooldown <= 0.0:
			draw_circle(c + Vector2(r * 0.65, -r * 0.65), 8.0, T.COL_ORANGE)
		var font := ThemeDB.fallback_font
		draw_string(font, Vector2(-20.0, size.y + 18.0), "CREW", HORIZONTAL_ALIGNMENT_CENTER, size.x + 40.0, 15, Color(tint, 0.9))


class CrewWheel extends Control:
	## The crew wheel: one slice per crew member around a close button. The
	## game runs slowly while it's open (mission.gd); pick an ability or close.
	signal picked(index: int)
	signal closed
	const T := preload("res://scripts/tuning.gd")
	const Crew := preload("res://scripts/crew.gd")
	const RING := 150.0
	const SLICE := 50.0
	var entries: Array[Dictionary] = []
	var charges := PackedFloat32Array()
	var off: Array[bool] = []
	var notes: Array[String] = []

	func center() -> Vector2:
		return Vector2(size.x * 0.68, size.y * 0.5)   # below the banner line

	func slice_pos(i: int) -> Vector2:
		var n := maxi(entries.size(), 1)
		return center() + Vector2.RIGHT.rotated(-PI / 2.0 + TAU * float(i) / n) * RING

	func _input(event: InputEvent) -> void:
		if not visible or not event is InputEventScreenTouch:
			return
		var touch := event as InputEventScreenTouch
		if not touch.pressed:
			return
		var at := touch.position - get_global_rect().position
		for i in entries.size():
			if at.distance_to(slice_pos(i)) <= SLICE + 8.0:
				picked.emit(i)
				get_viewport().set_input_as_handled()
				return
		if at.distance_to(center()) <= 48.0:
			closed.emit()
			get_viewport().set_input_as_handled()

	func _draw() -> void:
		var font := ThemeDB.fallback_font
		var c := center()
		draw_circle(c, RING + SLICE + 18.0, Color(0, 0, 0, 0.45))
		draw_arc(c, RING, 0.0, TAU, 64, Color(1, 1, 1, 0.12), 2.0)
		# Close button.
		draw_circle(c, 40.0, Color(0.1, 0.1, 0.11, 0.9))
		draw_arc(c, 40.0, 0.0, TAU, 32, Color(0.8, 0.78, 0.74), 2.5)
		draw_line(c + Vector2(-12, -12), c + Vector2(12, 12), Color(0.85, 0.83, 0.78), 3.0)
		draw_line(c + Vector2(-12, 12), c + Vector2(12, -12), Color(0.85, 0.83, 0.78), 3.0)
		for i in entries.size():
			var e := entries[i]
			var p := slice_pos(i)
			var role := str(e.role)
			var col: Color = Crew.ROLE_COLORS.get(role, Color.WHITE)
			var is_ready := charges[i] <= 0.0 and not off[i]
			var tint := col if is_ready else Color(0.5, 0.48, 0.46)
			draw_circle(p, SLICE, Color(0.08, 0.08, 0.09, 0.95))
			if charges[i] > 0.0 and not off[i]:
				if charges[i] >= 0.97:
					draw_circle(p, SLICE, Color(0, 0, 0, 0.5))
				elif charges[i] > 0.02:
					var points := PackedVector2Array([p])
					var steps := maxi(2, ceili(32.0 * charges[i]))
					for k in steps + 1:
						points.append(p + Vector2.RIGHT.rotated(-PI / 2.0 + TAU * charges[i] * float(k) / steps) * SLICE)
					draw_colored_polygon(points, Color(0, 0, 0, 0.5))
			draw_arc(p, SLICE, 0.0, TAU, 40, Color(tint, 0.95 if is_ready else 0.5), 3.5 if is_ready else 2.0)
			draw_string(font, p + Vector2(-SLICE, -6.0), str(Crew.ROLE_NAMES.get(role, role)).to_upper(), HORIZONTAL_ALIGNMENT_CENTER, SLICE * 2.0, 13, Color(tint, 0.9))
			draw_string(font, p + Vector2(-SLICE, 16.0), str(e.ability).to_upper(), HORIZONTAL_ALIGNMENT_CENTER, SLICE * 2.0, 13, Color(0.92, 0.9, 0.86) if is_ready else Color(0.55, 0.53, 0.5))
			var under := notes[i] if off[i] and notes[i] != "" else str(e.name)
			draw_string(font, p + Vector2(-SLICE - 20.0, SLICE + 18.0), under, HORIZONTAL_ALIGNMENT_CENTER, SLICE * 2.0 + 40.0, 13, Color(0.85, 0.83, 0.78, 0.9))
		draw_string(font, c + Vector2(-200.0, RING + SLICE + 44.0), "SLOW MOTION  -  PICK AN ABILITY OR CLOSE", HORIZONTAL_ALIGNMENT_CENTER, 400.0, 15, Color(0.85, 0.83, 0.78, 0.8))


class PowerBar extends Control:
	## Thin bar under armor: power in use / engine output. Overload (power or
	## weight) spills past the end in orange with a label.
	const T := preload("res://scripts/tuning.gd")
	var used := 0.0
	var output := 0.0
	var weight := 0.0
	var capacity := 0.0

	func set_values(new_used: float, new_output: float, new_weight := 0.0, new_capacity := 0.0) -> void:
		if not is_equal_approx(new_used, used) or not is_equal_approx(new_output, output) \
				or not is_equal_approx(new_weight, weight) or not is_equal_approx(new_capacity, capacity):
			used = new_used
			output = new_output
			weight = new_weight
			capacity = new_capacity
			queue_redraw()

	func _draw() -> void:
		if output <= 0.0:
			return
		var over := used > output
		var heavy := capacity > 0.0 and weight > capacity
		draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, 0.55))
		var inner := size.x - 4.0
		var fill := minf(used / output, 1.0) * inner
		var color := T.COL_ORANGE if over or heavy else Color(0.95, 0.85, 0.4)
		draw_rect(Rect2(Vector2(2, 2), Vector2(fill, size.y - 4.0)), color)
		var font := ThemeDB.fallback_font
		var text := "PWR %d/%d" % [roundi(used), roundi(output)]
		if heavy:
			text += "  WT %d/%d" % [roundi(weight), roundi(capacity)]
		if over or heavy:
			text += "  OVERLOAD"
		draw_string(font, Vector2(size.x + 10.0, size.y + 1.0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, color)


class StatusStrip extends Control:
	## One thin bar per status that's building, in its colour, with its name;
	## a status that's on shows full and bright. Hidden when nothing is going.
	const T := preload("res://scripts/tuning.gd")
	var build := PackedFloat32Array([0, 0, 0, 0, 0, 0])
	var left := PackedFloat32Array([0, 0, 0, 0, 0, 0])
	var showing := false

	func set_values(new_build: PackedFloat32Array, new_left: PackedFloat32Array) -> void:
		var changed := false
		for k in 6:
			changed = changed or absf(new_build[k] - build[k]) > 0.5 or (new_left[k] > 0.0) != (left[k] > 0.0)
		if not changed:
			return
		build = new_build.duplicate()
		left = new_left.duplicate()
		showing = false
		for k in 6:
			showing = showing or build[k] > 0.0 or left[k] > 0.0
		queue_redraw()

	func _draw() -> void:
		var font := get_theme_default_font()
		var y := 0.0
		for k in 6:
			var on := left[k] > 0.0
			if not on and build[k] <= 0.0:
				continue
			var c: Color = T.STATUS_COLORS[k]
			var fill := 1.0 if on else clampf(build[k] / T.STATUS_BAR, 0.0, 1.0)
			draw_rect(Rect2(0, y, 70, 7), Color(0, 0, 0, 0.55))
			draw_rect(Rect2(1, y + 1, 68.0 * fill, 5), c if on else Color(c, 0.75))
			draw_string(font, Vector2(76, y + 8), str(T.STATUS_NAMES[k]), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, c if on else Color(c, 0.7))
			y += 11.0


class RigIcon extends Control:
	## A small top-down rig (pointing up): four plates for the facings, a ring
	## for the shield, the body block drains as HP drops. Redraws on change.
	const T := preload("res://scripts/tuning.gd")
	var shield := -1.0
	var facings := PackedFloat32Array([1.0, 1.0, 1.0, 1.0])
	var hp := 1.0

	func set_values(shield_ratio: float, new_facings: PackedFloat32Array, hp_ratio: float) -> void:
		var changed := absf(shield_ratio - shield) > 0.01 or absf(hp_ratio - hp) > 0.01
		for i in 4:
			changed = changed or absf(new_facings[i] - facings[i]) > 0.01
		if not changed:
			return
		shield = shield_ratio
		facings = new_facings.duplicate()
		hp = hp_ratio
		queue_redraw()

	func _plate_color(v: float) -> Color:
		if v < 0.0:
			return Color(0.25, 0.25, 0.27, 0.6)   # nothing fitted
		if v <= 0.0:
			return Color(0.45, 0.12, 0.1)          # stripped
		return T.COL_ORANGE.lerp(T.COL_CYAN, clampf(v * 1.4 - 0.2, 0.0, 1.0)).darkened(0.35 * (1.0 - v))

	func _draw() -> void:
		var c := size * 0.5
		var bw := 20.0
		var bh := 34.0
		var body := Rect2(c - Vector2(bw, bh) * 0.5, Vector2(bw, bh))
		# Shield ring.
		if shield >= 0.0:
			draw_arc(c, 34.0, 0.0, TAU, 40, Color(T.COL_SHIELD, 0.18), 4.0)
			if shield > 0.0:
				draw_arc(c, 34.0, -PI / 2.0, -PI / 2.0 + TAU * shield, 40, Color(T.COL_SHIELD, 0.9), 4.0)
		# HP: the body block drains from the top.
		draw_rect(body, Color(0.08, 0.08, 0.09, 0.9))
		var fill := clampf(hp, 0.0, 1.0)
		var hp_col := Color(0.85, 0.83, 0.78) if fill > 0.35 else T.COL_ENEMY
		draw_rect(Rect2(body.position + Vector2(0, bh * (1.0 - fill)), Vector2(bw, bh * fill)), Color(hp_col, 0.85))
		# Plates: front (top), left, right, rear (bottom).
		draw_rect(Rect2(body.position + Vector2(-2, -9), Vector2(bw + 4, 6)), _plate_color(facings[0]))
		draw_rect(Rect2(body.position + Vector2(-9, 2), Vector2(6, bh - 4)), _plate_color(facings[1]))
		draw_rect(Rect2(body.position + Vector2(bw + 3, 2), Vector2(6, bh - 4)), _plate_color(facings[2]))
		draw_rect(Rect2(body.position + Vector2(-2, bh + 3), Vector2(bw + 4, 6)), _plate_color(facings[3]))
		draw_rect(body, Color(0.5, 0.5, 0.5, 0.6), false, 1.0)


class ArmorBar extends Control:
	const T := preload("res://scripts/tuning.gd")
	var ratio := 1.0

	func set_ratio(value: float) -> void:
		value = clampf(value, 0.0, 1.0)
		if not is_equal_approx(value, ratio):
			ratio = value
			queue_redraw()

	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, 0.55))
		var fill := T.COL_CYAN if ratio > 0.35 else T.COL_ORANGE
		draw_rect(Rect2(Vector2(2, 2), Vector2((size.x - 4.0) * ratio, size.y - 4.0)), fill)
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.5, 0.5, 0.5, 0.5), false, 1.0)


## The tutorial's instruction line ("" hides it).
func set_tip(text: String) -> void:
	tip.text = text
	tip.visible = text != ""
