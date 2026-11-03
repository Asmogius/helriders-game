extends CanvasLayer
## Minimal combat HUD: armor bar, objective, FPS readout, twin sticks, lock
## button, utility buttons, event banners, threat arrows, and the results
## card. The vehicle stays the visual focus.

signal restart_requested
signal lock_toggled(on: bool)
signal ability_pressed(index: int)

const T := preload("res://scripts/tuning.gd")
const ThumbStick := preload("res://scripts/thumb_stick.gd")

var left_stick: ThumbStick
var right_stick: ThumbStick

var _root: Control
var _armor_bar: ArmorBar
var _power_bar: PowerBar
var _arrows: ThreatArrows
var _lock_button: LockButton
var _ability_buttons: Array[AbilityButton] = []
var _status: Label
var _fps: Label
var _hint: Label
var _banner: Label
var _banner_tween: Tween
var _alert: Label
var _overlay: Control
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

	_armor_bar = ArmorBar.new()
	_armor_bar.position = Vector2(24, 18)
	_armor_bar.size = Vector2(300, 16)
	_root.add_child(_armor_bar)

	_power_bar = PowerBar.new()
	_power_bar.position = Vector2(24, 38)
	_power_bar.size = Vector2(300, 8)
	_root.add_child(_power_bar)

	_status = _label(24, Color(0.85, 0.83, 0.78))
	_status.position = Vector2(24, 52)
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

	_build_overlay()


## One round button per utility part, in a row left of LOCK. `kinds` are the
## parts' ability names ("patch", "mines"). Built once at mission start.
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
		var right := -190.0 - i * 124.0
		b.offset_left = right - 104.0
		b.offset_right = right
		b.offset_top = -444.0
		b.offset_bottom = -340.0
		b.pressed.connect(func() -> void: ability_pressed.emit(i))
		_root.add_child(b)
		_ability_buttons.append(b)
		right_stick.blockers.append(b)


## 0 = ready, 1 = just used.
func set_ability_charge(index: int, charge: float) -> void:
	if index >= 0 and index < _ability_buttons.size():
		_ability_buttons[index].set_charge(charge)


func ability_count() -> int:
	return _ability_buttons.size()


## Test hook: same as tapping utility button `index`.
func press_ability(index: int) -> void:
	if index >= 0 and index < _ability_buttons.size():
		_ability_buttons[index].press()


func set_armor(ratio: float) -> void:
	_armor_bar.set_ratio(ratio)


## Power in use vs the engine's budget, and weight vs the chassis's capacity.
## Over either budget shows as an overload.
func set_power(used: float, output: float, weight := 0.0, capacity := 0.0) -> void:
	_power_bar.set_values(used, output, weight, capacity)


## Only rigs with a targeting system (and a lock-capable weapon) get the button.
func set_lock_available(available: bool) -> void:
	_lock_button.visible = available


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
	var kind := ""      # "patch" or "mines"
	var charge := 0.0   # 0 ready, 1 just used

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func press() -> void:
		pressed.emit()

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
		var ready := charge <= 0.0
		var accent := Color(0.45, 0.9, 0.5) if kind == "patch" else T.COL_ORANGE
		var tint := accent if ready else Color(0.6, 0.58, 0.55)
		draw_circle(c, r, Color(0.0, 0.0, 0.0, 0.5))
		if not ready:
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
		draw_arc(c, r, 0.0, TAU, 40, Color(tint, 0.9 if ready else 0.5), 4.0 if ready else 2.5)
		match kind:
			"patch":
				draw_rect(Rect2(c - Vector2(5, 16), Vector2(10, 32)), tint)
				draw_rect(Rect2(c - Vector2(16, 5), Vector2(32, 10)), tint)
			"mines":
				for k in 3:
					var p := c + Vector2(-16.0 + k * 16.0, 0.0)
					draw_circle(p, 6.0, tint)
					draw_circle(p, 2.0, Color(0, 0, 0, 0.7))
		var font := ThemeDB.fallback_font
		var label := "PATCH" if kind == "patch" else ("MINES" if kind == "mines" else kind.to_upper())
		draw_string(font, Vector2(0.0, size.y + 18.0), label, HORIZONTAL_ALIGNMENT_CENTER, size.x, 18, Color(tint, 0.9))


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
