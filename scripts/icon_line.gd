extends Control
## A row of icon + value pairs, centred (V6.3): the garage stat line. Falls
## back to "LABEL value" text if the icon atlas is missing.
## items: [[icon_id, label, value_text, color], ...]

const UI := preload("res://scripts/ui_theme.gd")

const ICON := 20.0
const GAP := 8.0      # icon to value
const SPACING := 26.0 # between pairs
const FONT_SIZE := 19

var _icons: RefCounted = UI.icons()   # keeps the shared atlas alive while shown
var items: Array = []:
	set(v):
		items = v
		queue_redraw()


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	if items.is_empty():
		return
	var font := get_theme_default_font()
	var has_icons: bool = _icons.ok()
	var widths: Array[float] = []
	var total := 0.0
	for it: Array in items:
		var text := str(it[2]) if has_icons else "%s %s" % [it[1], it[2]]
		var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE).x + ((ICON + GAP) if has_icons else 0.0)
		widths.append(w)
		total += w
	total += SPACING * (items.size() - 1)
	var x := maxf((size.x - total) * 0.5, 0.0)
	var base := (size.y + font.get_ascent(FONT_SIZE) - font.get_descent(FONT_SIZE)) * 0.5
	for i in items.size():
		var it: Array = items[i]
		var c: Color = it[3]
		var tx := x
		if has_icons:
			_icons.draw(self, str(it[0]), Rect2(x, (size.y - ICON) * 0.5, ICON, ICON), c)
			tx += ICON + GAP
		draw_string(font, Vector2(tx, base), str(it[2]) if has_icons else "%s %s" % [it[1], it[2]], HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, UI.TEXT)
		x += widths[i] + SPACING
