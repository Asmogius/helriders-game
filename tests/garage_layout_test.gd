extends SceneTree
## V2.3 sample: the GARAGE tab's reading order and the slot focus on the rig.

const GarageLayout := preload("res://scripts/garage_layout.gd")
const GarageFocus := preload("res://scripts/garage_focus.gd")
const UI := preload("res://scripts/ui_theme.gd")
var fails := 0


func check(ok: bool, msg: String) -> void:
	if not ok:
		fails += 1
		printerr("FAIL: ", msg)


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var profile: Node = root.get_node("/root/Profile")
	profile.persist = false
	profile.new_game()
	change_scene_to_file("res://scenes/garage.tscn")
	for i in 10:
		await process_frame
	var g: Control = current_scene
	g.set("auto_resume", false)
	for sz: Vector2 in [Vector2(1280, 720), Vector2(1600, 720)]:
		root.size = Vector2i(sz)
		g.size = sz
		await process_frame
		await process_frame
		var cols := GarageLayout.columns(sz, g.FOOTER_H, UI.safe_rect(g))
		check(cols[0].end.x < cols[1].position.x and cols[1].end.x < cols[2].position.x, "%s: three columns, no overlap" % sz)
		check(cols[1].size.x >= 400.0, "%s: room for the rig (%d)" % [sz, cols[1].size.x])
		var tags: Array = g.get("_tags")
		for t: Control in tags:
			if t.visible:
				check(t.size.y >= UI.MIN_TOUCH and t.position.x < cols[1].position.x, "%s: slot card on the left, touch size" % sz)
		var stats: Control = g.get("_stat_sheet")
		check(stats.visible and stats.position.x >= cols[2].position.x - 1.0, "%s: stats panel on the right" % sz)
		var holder: Node2D = g.get("_rig_holder")
		check(absf(holder.position.x - cols[1].get_center().x) < 1.0, "%s: rig centred in the middle column" % sz)
		check(not (g.get("_callouts") as CanvasItem).visible and not (g.get("_rings") as CanvasItem).visible, "no callout lines or rings")
		var bar: Control = (g.get("_deploy") as Control).get_parent()
		check(bar.visible and bar.position.y + bar.size.y <= sz.y - g.FOOTER_H + 0.5, "%s: action bar above the tabs" % sz)
	# Focus: opening a slot lights that part's sprite; closing clears it.
	var focus: Node = null
	for c in g.get_children():
		if c.get_script() == GarageFocus:
			focus = c
	check(focus != null, "focus pass present")
	var rig: Node2D = g.get("preview")
	var lit_any := false
	var seen := {}
	for i in [0, 2, 3, 6]:   # chassis, drive, armor front, weapon 1
		g.open_slot(i)
		for f in 3:
			await process_frame
		var s: Sprite2D = focus.lit()
		var want := GarageFocus.target_for(rig, g.SLOTS[i], g._slot_part(g.SLOTS[i]))
		check(s == want, "slot %d lights its own sprite" % i)
		if s != null:
			lit_any = true
			seen[s] = true
			check(s.get_node_or_null("FocusGlow") != null, "slot %d: glow on the part" % i)
		var bar2: Node = (g.get("_deploy") as Control).get_parent()
		check(bar2.get_node("Back").visible and bar2.get_node("Equip").visible and not (g.get("_deploy") as Control).visible, "open slot: BACK and EQUIP in the bar")
		g.close_sheet()
		for f in 2:
			await process_frame
		check(focus.lit() == null, "closed: nothing lit")
	if rig.get("_hull_art") != null:
		check(lit_any and seen.size() >= 3, "different slots light different parts (%d)" % seen.size())
	print("GARAGE LAYOUT TEST ", "PASSED" if fails == 0 else "FAILED (%d)" % fails)
	quit(1 if fails else 0)
