extends Control
## One shared rarity frame drawer (VISUAL_PLAN P0; V1.2 extends the tiers).
## Fills its parent, draws a border, a top strip and a pip row (1-6 pips) so
## the tier reads without colour. Static: redraws only when rarity or size
## changes. Add it with `UI.rarity_frame(control, rarity)`.

const T := preload("res://scripts/tuning.gd")

const BORDER := 2.0
const STRIP := 4.0
const PIP := 5.0
const PIP_GAP := 3.0

var rarity := "Common":
	set(v):
		if v != rarity:
			rarity = v
			queue_redraw()


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	resized.connect(queue_redraw)


func tier() -> int:
	return T.RARITY_ORDER.find(rarity) + 1


func color() -> Color:
	return T.RARITY_COLORS.get(rarity, Color.WHITE)


func _draw() -> void:
	var c := color()
	var r := Rect2(Vector2.ZERO, size)
	draw_rect(r.grow(-BORDER * 0.5), c, false, BORDER)
	draw_rect(Rect2(0, 0, size.x, STRIP), c)
	var n := tier()
	var x := size.x - BORDER - 4.0 - n * (PIP + PIP_GAP) + PIP_GAP
	for i in n:
		draw_rect(Rect2(x + i * (PIP + PIP_GAP), STRIP + 3.0, PIP, PIP), c)
