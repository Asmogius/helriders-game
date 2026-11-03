extends RefCounted
## Shared look for menu screens (Garage and the other stations): dark steel
## panels, phone-sized text, cyan/orange accents. Apply with `control.theme`.

const T := preload("res://scripts/tuning.gd")

const TEXT := Color(0.88, 0.86, 0.82)
const TEXT_DIM := Color(0.6, 0.59, 0.56)
const PANEL := Color(0.085, 0.085, 0.095, 0.97)
const PANEL_EDGE := Color(0.26, 0.27, 0.29)
const GOOD := Color(0.45, 0.85, 0.5)
const BAD := Color(0.95, 0.38, 0.3)


static func make() -> Theme:
	var th := Theme.new()
	th.default_font_size = 22
	th.set_color("font_color", "Label", TEXT)
	th.set_color("font_outline_color", "Label", Color(0, 0, 0, 0.8))
	th.set_constant("outline_size", "Label", 4)

	th.set_stylebox("normal", "Button", box(Color(0.13, 0.13, 0.145), PANEL_EDGE, 2))
	th.set_stylebox("hover", "Button", box(Color(0.16, 0.16, 0.175), PANEL_EDGE, 2))
	th.set_stylebox("pressed", "Button", box(Color(0.22, 0.14, 0.08), T.COL_ORANGE, 2))
	th.set_stylebox("disabled", "Button", box(Color(0.1, 0.1, 0.105), Color(0.18, 0.18, 0.19), 2))
	th.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	th.set_color("font_color", "Button", TEXT)
	th.set_color("font_hover_color", "Button", Color.WHITE)
	th.set_color("font_pressed_color", "Button", Color.WHITE)
	th.set_color("font_disabled_color", "Button", Color(0.42, 0.42, 0.42))

	th.set_stylebox("panel", "Panel", box(PANEL, PANEL_EDGE, 2))
	th.set_stylebox("panel", "PanelContainer", box(PANEL, PANEL_EDGE, 2))
	return th


static func box(fill: Color, border: Color, width: int) -> StyleBoxFlat:
	var b := StyleBoxFlat.new()
	b.bg_color = fill
	b.border_color = border
	b.set_border_width_all(width)
	b.content_margin_left = 12
	b.content_margin_right = 12
	b.content_margin_top = 6
	b.content_margin_bottom = 6
	return b


## An accent button (Deploy): orange border and bold text.
static func accent(button: Button, color: Color) -> void:
	button.add_theme_stylebox_override("normal", box(Color(0.16, 0.11, 0.07), color, 3))
	button.add_theme_stylebox_override("hover", box(Color(0.2, 0.13, 0.08), color, 3))
	button.add_theme_stylebox_override("pressed", box(Color(0.32, 0.18, 0.08), color, 3))
	button.add_theme_color_override("font_color", color.lightened(0.3))


static func label(text: String, size := 22, color := TEXT) -> Label:
	var l := Label.new()
	l.text = text
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l
