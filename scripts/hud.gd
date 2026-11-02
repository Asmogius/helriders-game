extends CanvasLayer
## Minimal combat HUD: armor bar, objective, FPS readout, twin sticks, and the
## results card. The vehicle stays the visual focus.

signal restart_requested

const T := preload("res://scripts/tuning.gd")
const ThumbStick := preload("res://scripts/thumb_stick.gd")

var left_stick: ThumbStick
var right_stick: ThumbStick

var _root: Control
var _armor_bar: ArmorBar
var _arrows: ThreatArrows
var _status: Label
var _fps: Label
var _hint: Label
var _overlay: Control
var _title: Label
var _subtitle: Label
var _button: Button
var _fps_timer := 0.0


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

	_status = _label(24, Color(0.85, 0.83, 0.78))
	_status.position = Vector2(24, 40)
	_root.add_child(_status)

	_fps = _label(20, Color(0.6, 0.6, 0.58))
	_fps.anchor_left = 1.0
	_fps.anchor_right = 1.0
	_fps.offset_left = -320.0
	_fps.offset_right = -24.0
	_fps.offset_top = 14.0
	_fps.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_root.add_child(_fps)

	_hint = _label(24, Color(0.85, 0.83, 0.78))
	_hint.text = "LEFT THUMB  DRIVE        RIGHT THUMB  AIM + FIRE"
	_hint.anchor_left = 0.0
	_hint.anchor_right = 1.0
	_hint.anchor_top = 1.0
	_hint.anchor_bottom = 1.0
	_hint.offset_top = -60.0
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_root.add_child(_hint)
	var fade := create_tween()
	fade.tween_interval(6.0)
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

	_build_overlay()


func set_armor(ratio: float) -> void:
	_armor_bar.set_ratio(ratio)


## Screen-space positions of threats to point at when they're off-screen.
func set_threats(points: PackedVector2Array) -> void:
	_arrows.set_points(points)


func set_status(kills: int, target: int, scrap: int) -> void:
	_status.text = "CLEAR  %d / %d      SCRAP  %d" % [kills, target, scrap]


func _process(delta: float) -> void:
	_fps_timer -= delta
	if _fps_timer <= 0.0:
		_fps_timer = 0.25
		var version := str(ProjectSettings.get_setting("application/config/version", ""))
		_fps.text = "%d FPS   v%s" % [Engine.get_frames_per_second(), version]


func show_result(title: String, subtitle: String, button_text: String, accent: Color) -> void:
	left_stick.enabled = false
	right_stick.enabled = false
	_title.text = title
	_title.add_theme_color_override("font_color", accent)
	_subtitle.text = subtitle
	_button.text = button_text
	_overlay.visible = true
	_overlay.modulate.a = 0.0
	create_tween().tween_property(_overlay, "modulate:a", 1.0, 0.35)


func is_result_visible() -> bool:
	return _overlay.visible


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


func _box(fill: Color, border: Color) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = fill
	box.border_color = border
	box.set_border_width_all(3)
	return box


class ThreatArrows extends Control:
	## Orange chevrons on the screen edge pointing at off-screen stragglers.
	const T := preload("res://scripts/tuning.gd")
	const MARGIN := 48.0
	var points := PackedVector2Array()

	func set_points(value: PackedVector2Array) -> void:
		if value.is_empty() and points.is_empty():
			return
		points = value
		queue_redraw()

	func _draw() -> void:
		var area := Rect2(Vector2.ZERO, size).grow(-MARGIN)
		var center := area.get_center()
		for p in points:
			if area.grow(MARGIN).has_point(p):
				continue  # on screen already
			var dir := (p - center).normalized()
			# Walk from the centre toward the threat until we hit the inset edge.
			var tx := INF if is_zero_approx(dir.x) else (area.size.x * 0.5) / absf(dir.x)
			var ty := INF if is_zero_approx(dir.y) else (area.size.y * 0.5) / absf(dir.y)
			var tip := center + dir * minf(tx, ty)
			var side := dir.orthogonal() * 12.0
			draw_colored_polygon(PackedVector2Array([tip + dir * 14.0, tip - dir * 8.0 + side, tip - dir * 8.0 - side]), Color(T.COL_ORANGE, 0.85))


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
