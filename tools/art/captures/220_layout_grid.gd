extends "res://tools/art/capture_step.gd"
## V6.2 layout grid: the safe_rect outline (MARGIN inside the viewport), a
## GRID-snapped panel row with GAP spacing, and a bottom_bar of buttons.


func run(cap: SceneTree) -> void:
	var strip: Control = cap.new_strip(T.COL_ROAD)
	var r := UI.safe_rect(strip)
	var frame := ReferenceRect.new()
	frame.border_color = T.COL_CYAN
	frame.border_width = 2.0
	frame.editor_only = false
	frame.position = r.position
	frame.size = r.size
	strip.add_child(frame)
	var w := UI.snap((r.size.x - UI.GAP * 3.0) / 4.0)
	for i in 4:
		var p := Panel.new()
		p.position = r.position + Vector2(i * (w + UI.GAP), UI.GRID * 4.0)
		p.size = Vector2(w, UI.GRID * 30.0)
		strip.add_child(p)
		var l := UI.label("PANEL %d" % (i + 1), 18, UI.TEXT)
		l.position = Vector2(UI.GRID * 2.0, UI.GRID * 2.0)
		p.add_child(l)
	var bar := UI.bottom_bar(strip)
	for t: String in ["BACK", "SETTINGS", "DEPLOY"]:
		var b := Button.new()
		b.text = t
		b.custom_minimum_size.x = 200.0
		bar.add_child(b)
