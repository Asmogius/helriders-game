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
		check(stats.visible and stats.position.x >= cols[2].position.x - 1.0 and stats.get("headline"), "%s: one small stats box, top right, headline stats" % sz)
		check(stats.HEADLINE.size() >= 4 and stats.HEADLINE.size() <= 5, "4-5 headline stats")
		var holder: Node2D = g.get("_rig_holder")
		check(absf(holder.position.x - cols[1].get_center().x) < 1.0, "%s: rig centred in the middle column" % sz)
		check(holder.scale.x >= 1.5, "%s: rig shown big (zoom %.2f)" % [sz, holder.scale.x])
		var room: Control = g.get("_workshop")
		if room.has_art():
			check(room.lift_point().distance_to(holder.position) < 1.0, "%s: floor pad under the rig" % sz)
		check(not (g.get("_callouts") as CanvasItem).visible and not (g.get("_rings") as CanvasItem).visible, "old all-slot callouts off")
		var crew: Control = g.get("_crew_line")
		check(crew.size.y >= UI.MIN_TOUCH, "%s: crew row is touch size (%d)" % [sz, crew.size.y])
		var abar: Control = (g.get("_deploy") as Control).get_parent()
		for b: Node in abar.get_children():
			if b is Button and (b as Button).visible:
				check((b as Button).size.y >= UI.MIN_TOUCH, "%s: action button %s touch size" % [sz, (b as Button).text])
		var bar: Control = (g.get("_deploy") as Control).get_parent()
		check(bar.visible and bar.position.y + bar.size.y <= sz.y - g.FOOTER_H + 0.5, "%s: action bar above the tabs" % sz)
	# Focus: opening a slot lights that part's sprite; closing clears it.
	var focus: Node = null
	for c in g.get_children():
		if c.get_script() == GarageFocus:
			focus = c
	check(focus != null, "focus pass present")
	await process_frame
	check(focus.callout_points().is_empty(), "nothing selected: no callout line")
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
		check(focus.line_alpha < 1.0, "slot %d: callout fades in" % i)
		for f in 10:
			await process_frame
		check(is_equal_approx(focus.line_alpha, 1.0), "slot %d: faded in within ~150 ms" % i)
		if i != 0:
			check((g.get("_rig_holder") as CanvasItem).modulate.r < 0.99, "slot %d: rest of the rig dimmed" % i)
		var pts: PackedVector2Array = focus.callout_points()
		check(pts.size() >= 3, "slot %d: callout line drawn" % i)
		if pts.size() >= 3:
			var tr: Rect2 = (g.get("_tags")[i] as Control).get_global_rect().grow(1.0)
			check(tr.has_point(pts[0]), "slot %d: line starts on its card" % i)
			for t: Control in g.get("_tags"):
				if t != g.get("_tags")[i] and t.visible:
					var other := t.get_global_rect()
					for k in pts.size() - 1:
						var mid := (pts[k] + pts[k + 1]) * 0.5
						check(not (other.has_point(pts[k + 1]) or other.has_point(mid)), "slot %d: line clear of other cards" % i)
		var sheet: Control = g.get("_sheet")
		var cards_fit: float = (sheet.size.x - 28.0) / (262.0 + 12.0)
		check(cards_fit >= 2.5, "part sheet fits %.1f cards (>= 2.5)" % cards_fit)
		var bar2: Node = (g.get("_deploy") as Control).get_parent()
		check(bar2.get_node("Back").visible and bar2.get_node("Equip").visible and not (g.get("_deploy") as Control).visible, "open slot: BACK and EQUIP in the bar")
		g.close_sheet()
		for f in 2:
			await process_frame
		check(focus.lit() == null and focus.callout_points().is_empty(), "closed: nothing lit, no line")
		for f in 12:
			await process_frame
		check(focus.line_alpha == 0.0 and (g.get("_rig_holder") as CanvasItem).modulate == Color.WHITE, "closed: line faded out, rig undimmed")
	if rig.get("_hull_art") != null:
		check(lit_any and seen.size() >= 3, "different slots light different parts (%d)" % seen.size())
	# Browsing a candidate shows it on the rig at once; the loadout is unchanged.
	if rig.get("_hull_art") != null:
		profile.schematics.append("half_track")
		profile.scrap += 1000
		g.open_slot(2)
		g.preview_part("half_track")
		for f in 3:
			await process_frame
		var lay: Dictionary = rig.get("_layer_sprites")
		check(lay.has("drive:half_track") and profile.rig.drive != "half_track", "browsing Half-Track shows it on the rig, not fitted")
		g.close_sheet()
		for f in 3:
			await process_frame
		check(not (rig.get("_layer_sprites") as Dictionary).has("drive:half_track"), "closing puts the fitted drive back")
	# Equipped parts are drawn: fitting the Half-Track swaps the rig's drive layer.
	if rig.get("_hull_art") != null:
		check(profile.apply_loadout(profile.with_part(profile.rig, "drive", 0, "half_track")), "fit half track")
		for f in 3:
			await process_frame
		var layers: Dictionary = rig.get("_layer_sprites")
		check(layers.has("drive:half_track") and not layers.has("drive:street_wheels"), "the preview wears the Half-Track layer (%s)" % [layers.keys()])
		g.open_slot(2)
		for f in 3:
			await process_frame
		check(focus.lit() == layers.get("drive:half_track"), "DRIVE open lights the Half-Track")
		g.close_sheet()
	print("GARAGE LAYOUT TEST ", "PASSED" if fails == 0 else "FAILED (%d)" % fails)
	quit(1 if fails else 0)
