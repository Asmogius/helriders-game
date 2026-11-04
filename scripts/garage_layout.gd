extends RefCounted
## V2.3 sample (P6/P7): the GARAGE tab's reading order, one grid.
##   left:   the slot cards, a 2-column grid
##   centre: the rig (the hero) on its floor pad, power/weight under it,
##           the part sheet under that when a slot is open
##   right:  the stats, one panel (always on; shows now -> after while previewing)
##   bottom: one action bar above the station tabs (BACK / EQUIP while a slot
##           is open, PRESETS / UPGRADES / REBUILD / DEPLOY otherwise)
## No callout lines: the open slot's part lights up on the rig (garage_focus.gd).
## garage.gd builds the nodes as before and calls apply() from _layout(),
## _layout_tags() and _show_stat_sheet(), so the rarity code (P1) is untouched.
## Grid: UI's shared layout grid (ui_theme.gd, PR #57): MARGIN, GAP, GRID,
## BAR_H, MIN_TOUCH and safe_rect(). The action bar sits on top of the station
## tabs (the footer is the screen's bottom bar), so it is placed here rather
## than with UI.bottom_bar(), which assumes it is the bottom-most bar.

const UI := preload("res://scripts/ui_theme.gd")
const T := preload("res://scripts/tuning.gd")

const M := UI.MARGIN
const GAP := UI.GAP
const BAR_H := UI.BAR_H              # action bar, buttons MIN_TOUCH tall
const TOP_H := 6.0 * UI.GRID         # top bar row (scrap / day, MENU): 48
const CARD_W := 23.0 * UI.GRID       # slot card cell: 184 x 64
const CARD_H := UI.MIN_TOUCH
const STATS_W := 36.0 * UI.GRID      # 288: one small stats box, 5 headline stats
const STATS_H := 25.0 * UI.GRID      # 200
const RIG_ZOOM := 1.6                # rig (and its floor pad) zoom with nothing open
const STACK_H := 44.0 + 4.0 + 64.0 + 48.0   # meters, crew row, job + hint under the rig
const OPEN_SCALE := 1.0  # zoom while the part sheet is open # rig scale while the part sheet is open


static func left_w() -> float:
	return CARD_W * 2.0 + GAP


## The three columns for a garage of `size`: [left, centre, right] Rects.
static func columns(size: Vector2, footer_h: float, safe := Rect2()) -> Array[Rect2]:
	if not safe.has_area():
		safe = Rect2(Vector2(M, M), size - Vector2(2.0 * M, 2.0 * M))
	var top := safe.position.y + TOP_H + GAP
	var bottom := size.y - footer_h - BAR_H - GAP
	var h := bottom - top
	var left := Rect2(safe.position.x, top, left_w(), h)
	var right := Rect2(safe.end.x - STATS_W, top, STATS_W, STATS_H)
	var cx := left.end.x + GAP * 2.0
	var centre := Rect2(cx, top, right.position.x - GAP - cx, h)
	return [left, centre, right]


static func _place(c: Control, r: Rect2) -> void:
	c.set_anchors_preset(Control.PRESET_TOP_LEFT)
	c.position = r.position
	c.size = r.size
	c.offset_left = r.position.x
	c.offset_top = r.position.y
	c.offset_right = r.end.x
	c.offset_bottom = r.end.y


static func apply(g: Control) -> void:
	if g.get("_deploy") == null or g.get("_stat_sheet") == null or g.get("_sheet") == null:
		return
	var size: Vector2 = g.size
	if size.x < 10.0:
		return
	var footer_h: float = g.FOOTER_H
	var safe := UI.safe_rect(g) if g.is_inside_tree() else Rect2()
	var cols := columns(size, footer_h, safe)
	var left: Rect2 = cols[0]
	var centre: Rect2 = cols[1]
	var right: Rect2 = cols[2]
	var open: bool = int(g.get("selected")) >= 0
	var on_garage: bool = g.get("tab") == "GARAGE"

	# --- left: slot cards, 2 columns, top-down in slot order -----------------
	var tags: Array = g.get("_tags")
	var k := 0
	for i in tags.size():
		var tag: Control = tags[i]
		if not g.call("_slot_exists", g.SLOTS[i]):
			continue
		tag.set("side", 0)
		tag.set("compact", true)
		var r := Rect2(left.position + Vector2((k % 2) * (CARD_W + GAP), (k / 2) * (CARD_H + GAP)), Vector2(CARD_W, CARD_H))
		_place(tag, r)
		k += 1

	# --- no callout lines or rings; the focus pass marks the part instead ----
	(g.get("_callouts") as CanvasItem).visible = false
	(g.get("_rings") as CanvasItem).visible = false
	var stats_label: Control = g.get("_stats_label")
	stats_label.visible = false   # the stats panel says it all

	# --- right: one small stats box (5 headline stats), top right -----------
	var sheet_stats: Control = g.get("_stat_sheet")
	sheet_stats.set("single_column", true)
	sheet_stats.set("headline", true)
	var sheet_h: float = g.SHEET_H
	_place(sheet_stats, right)
	sheet_stats.visible = on_garage and g.profile.has_rig()
	if not open and sheet_stats.visible:
		var now: Dictionary = g.call("_built", g.profile.rig)
		sheet_stats.call("set_data", "RIG STATS", now, now, 0)

	# --- centre: the rig, big; the meters stack, or the part sheet -----------
	var holder: Node2D = g.get("_rig_holder")
	var sheet: Control = g.get("_sheet")
	var rig_area := Rect2(centre.position, Vector2(centre.size.x, centre.size.y - STACK_H - GAP))
	if open:   # bottom sheet: from the slot grid to the right edge (3 cards at 1280)
		rig_area = Rect2(centre.position, Vector2(centre.size.x, centre.size.y - sheet_h - GAP))
		_place(sheet, Rect2(centre.position.x, centre.end.y - sheet_h, right.end.x - centre.position.x, sheet_h))
		var title: Label = g.get("_sheet_title")
		title.clip_text = true
		title.size = Vector2(right.end.x - centre.position.x - 4.0 * UI.GRID, 4.0 * UI.GRID)
		title.add_theme_font_size_override("font_size", 15)
	var zoom := OPEN_SCALE if open else RIG_ZOOM
	holder.position = rig_area.get_center()
	holder.scale = Vector2.ONE * zoom
	holder.visible = on_garage and g.profile.has_rig()
	var room: Control = g.get("_workshop")
	if room != null and room.has_method("frame_rig"):
		room.call("frame_rig", holder.position, zoom)
	var touch: Control = g.get("_rig_touch")
	_place(touch, rig_area)
	touch.mouse_filter = Control.MOUSE_FILTER_IGNORE if open else Control.MOUSE_FILTER_STOP
	var meter: Control = g.get("_power_meter")
	# meters 44, crew row MIN_TOUCH (it opens the INN), job and hint 24 each
	var heights := {"_crew_line": UI.MIN_TOUCH, "_job": 3.0 * UI.GRID, "_hint": 3.0 * UI.GRID}
	var y := centre.end.y - STACK_H
	_place(meter, Rect2(centre.position.x, y, centre.size.x, 44.0))
	meter.visible = not open and g.profile.has_rig()
	y += 48.0
	for name: String in ["_crew_line", "_job", "_hint"]:
		var c: Control = g.get(name)
		var h: float = heights[name]
		_place(c, Rect2(centre.position.x, y, centre.size.x, h))
		c.custom_minimum_size.y = h
		if c is Label:
			(c as Label).clip_text = true
			(c as Label).vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		c.add_theme_font_size_override("font_size", 15)
		y += h
	(g.get("_crew_line") as Control).visible = not open
	(g.get("_job") as Control).visible = not open
	(g.get("_hint") as Control).visible = not open
	var no_rig: Control = g.get("_no_rig")
	_place(no_rig, Rect2(centre.position.x, centre.position.y + 120.0, centre.size.x, 120.0))

	# --- bottom: one action bar ------------------------------------------------
	_action_bar(g, size, footer_h, open, safe)


static func _action_bar(g: Control, size: Vector2, footer_h: float, open: bool, safe: Rect2) -> void:
	if not safe.has_area():
		safe = Rect2(Vector2(M, M), size - Vector2(2.0 * M, 2.0 * M))
	var deploy: Button = g.get("_deploy")
	var bar: HBoxContainer = deploy.get_parent()
	if not bar.has_meta("v23"):
		bar.set_meta("v23", true)
		var menu: Button = bar.get_child(0)          # MENU goes up to the top bar
		bar.remove_child(menu)
		g.add_child(menu)
		g.move_child(menu, bar.get_index())   # same depth as before (stations cover it)
		menu.set_meta("v23_menu", true)
		var back := Button.new()
		back.text = "BACK"
		back.name = "Back"
		back.focus_mode = Control.FOCUS_NONE
		back.pressed.connect(g.close_sheet)
		bar.add_child(back)
		bar.move_child(back, 0)
		var spacer := Control.new()
		spacer.name = "Spacer"
		spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		bar.add_child(spacer)
		bar.move_child(spacer, 1)
		var equip := Button.new()
		equip.text = "EQUIP"
		equip.name = "Equip"
		equip.focus_mode = Control.FOCUS_NONE
		equip.custom_minimum_size = Vector2(180, 0)
		UI.accent(equip, T.COL_ORANGE)
		equip.pressed.connect(func() -> void: g.choose(g.get("_preview")))
		bar.add_child(equip)
		(g.get("_sheet") as Control).get_child(1).visible = false   # sheet's CLOSE: BACK does it
	bar.alignment = BoxContainer.ALIGNMENT_BEGIN
	bar.add_theme_constant_override("separation", int(GAP))
	_place(bar, Rect2(safe.position.x, size.y - footer_h - BAR_H, safe.size.x, UI.MIN_TOUCH))
	for b: Node in bar.get_children():
		if b is Button:
			(b as Button).custom_minimum_size.y = UI.MIN_TOUCH
	var on_garage: bool = g.get("tab") == "GARAGE"
	bar.visible = on_garage
	for b: Node in bar.get_children():
		var n := String(b.name)
		if n == "Back" or n == "Equip":
			(b as Control).visible = open
		elif b is Button:
			(b as Control).visible = not open
	if open:
		var equip: Button = bar.get_node("Equip")
		var slot: Dictionary = g.SLOTS[int(g.get("selected"))]
		equip.disabled = g.call("_slot_part", slot) == g.get("_preview")
	for c: Node in g.get_children():
		if c.has_meta("v23_menu"):
			_place(c as Control, Rect2(safe.end.x - 18.0 * UI.GRID, safe.position.y - UI.GRID, 18.0 * UI.GRID, TOP_H))
