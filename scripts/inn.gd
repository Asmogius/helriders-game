extends Control
## The Inn (DESIGN §5): your crew roster. Tap a crew member, then SEAT them
## on the rig (Driver and Gunner seats, or an open seat for the other classes,
## one of each class), UNSEAT them, DISMISS them, or PICK PERK when a perk is
## waiting. Injured crew rest here until healed.
##
## EXPEDITIONS opens the day's board once it's unlocked: tap a trip, tap
## benched crew to build the team (their total level sets the odds), SEND.
## UPGRADES opens the Inn's tracks (upgrade_panel.gd).

const T := preload("res://scripts/tuning.gd")
const UI := preload("res://scripts/ui_theme.gd")
const Crew := preload("res://scripts/crew.gd")
const CrewCard := preload("res://scripts/crew_card.gd")
const ProfileScript := preload("res://scripts/profile.gd")
const UpgradePanel := preload("res://scripts/upgrade_panel.gd")
const PadScript := preload("res://scripts/pad.gd")

const INN_UPGRADES := ["bunkhouse", "drill_yard", "infirmary", "second_team", "scout_network", "last_rites"]

var profile: ProfileScript
var selected_id := -1

var _title: Label
var _seats: Label
var _cards: HBoxContainer
var _seat: Button
var _dismiss: Button
var _empty: Label
var _perk: Button
var _picker: Control
var _confirm_dismiss := -1
var _away: Label
var _expeditions: Control
var _upgrades: UpgradePanel
var trip := -1                     # board index picked on the expedition screen
var team: Array[int] = []          # crew ids picked for it


func _ready() -> void:
	profile = get_node("/root/Profile")
	var bg := ColorRect.new()
	bg.color = Color(0.075, 0.075, 0.085)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	_title = UI.label("", 30, T.COL_UI_ACCENT)
	_title.position = Vector2(24, 14)
	add_child(_title)
	_seats = UI.label("", 20, UI.TEXT)
	_seats.position = Vector2(24, 56)
	add_child(_seats)

	var bar := HBoxContainer.new()
	bar.anchor_left = 1.0
	bar.anchor_right = 1.0
	bar.offset_left = -760.0
	bar.offset_right = -20.0
	bar.offset_top = 10.0
	bar.offset_bottom = 60.0
	bar.alignment = BoxContainer.ALIGNMENT_END
	bar.add_theme_constant_override("separation", 10)
	add_child(bar)
	_perk = _button("PICK PERK", 190)
	UI.accent(_perk, T.COL_ORANGE)
	_perk.pressed.connect(open_perk_picker)
	bar.add_child(_perk)
	_dismiss = _button("DISMISS", 170)
	_dismiss.pressed.connect(dismiss_selected)
	bar.add_child(_dismiss)
	_seat = _button("SEAT", 200)
	UI.accent(_seat, T.COL_UI_ACCENT)
	_seat.pressed.connect(seat_selected)
	bar.add_child(_seat)

	var scroll := ScrollContainer.new()
	scroll.anchor_right = 1.0
	scroll.offset_left = 20.0
	scroll.offset_right = -20.0
	scroll.offset_top = 96.0
	scroll.offset_bottom = 96.0 + CrewCard.SIZE.y + 6.0
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.scroll_deadzone = 14
	add_child(scroll)
	_cards = HBoxContainer.new()
	_cards.add_theme_constant_override("separation", 14)
	scroll.add_child(_cards)

	_empty = UI.label("", 20, UI.TEXT_DIM)
	_empty.anchor_right = 1.0
	_empty.offset_left = 24.0
	_empty.offset_right = -24.0
	_empty.offset_top = 420.0
	_empty.autowrap_mode = TextServer.AUTOWRAP_WORD
	add_child(_empty)

	var bottom := HBoxContainer.new()
	bottom.anchor_top = 1.0
	bottom.anchor_right = 1.0
	bottom.anchor_bottom = 1.0
	bottom.offset_left = 24.0
	bottom.offset_right = -20.0
	bottom.offset_top = -66.0
	bottom.offset_bottom = -12.0
	bottom.add_theme_constant_override("separation", 10)
	add_child(bottom)
	_away = UI.label("", 18, T.COL_ORANGE)
	_away.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_away.clip_text = true
	_away.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	bottom.add_child(_away)
	var exp_button := _button("EXPEDITIONS", 220)
	UI.accent(exp_button, T.COL_ORANGE)
	exp_button.pressed.connect(open_expeditions)
	bottom.add_child(exp_button)
	var up_button := _button("UPGRADES", 170)
	up_button.pressed.connect(open_upgrades)
	bottom.add_child(up_button)

	profile.changed.connect(refresh)
	refresh()


func refresh() -> void:
	if not is_inside_tree():
		return
	_title.text = "INN   -   ROSTER %d / %d" % [profile.crew.size(), profile.roster_cap()]
	var seat_bits: Array[String] = []
	var riders := profile.seated_crew()
	for seat: String in profile.seats():
		if seat == "open":
			continue
		var m := profile.seated_in(seat)
		seat_bits.append("%s  %s" % [str(Crew.ROLE_NAMES[seat]).to_upper(), str(m.name) if not m.is_empty() else "empty"])
	var open := profile.seats().count("open")
	if open > 0:
		var others: Array[String] = []
		for m in riders:
			if Crew.OPEN_CLASSES.has(str(m.role)):
				others.append("%s %s" % [Crew.role_name(m), m.name])
		while others.size() < open:
			others.append("empty")
		seat_bits.append("OPEN  " + ", ".join(others))
	_seats.text = "SEATS:   " + ("      ".join(seat_bits) if not seat_bits.is_empty() else "build a rig first")
	for c in _cards.get_children():
		_cards.remove_child(c)
		c.queue_free()
	if profile.member(selected_id).is_empty():
		selected_id = -1
	for m: Dictionary in profile.crew:
		var card := CrewCard.new()
		card.member = m
		card.selected = int(m.id) == selected_id
		_status(card, m)
		card.pressed.connect(select.bind(int(m.id)))
		_cards.add_child(card)
	var sel := profile.member(selected_id)
	_seat.disabled = sel.is_empty() or (not bool(sel.seated) and not _can_seat(sel))
	_seat.text = "UNSEAT" if not sel.is_empty() and bool(sel.seated) else "SEAT"
	_dismiss.disabled = sel.is_empty() or profile.is_away(sel)
	_perk.visible = not sel.is_empty() and Crew.perks_due(sel) > 0
	_dismiss.text = PadScript.hint("TAP AGAIN", "PRESS AGAIN") if _confirm_dismiss == selected_id and selected_id >= 0 else "DISMISS"
	var hints: Array[String] = []
	if profile.crew.is_empty():
		hints.append("No crew. The Saloon always has a free Common Driver and Gunner.")
	var waiting := profile.perks_waiting()
	if waiting > 0:
		hints.append("%d perk pick%s waiting: %s a PERK READY card, then PICK PERK." % [waiting, "" if waiting == 1 else "s", PadScript.hint("tap", "pick")])
	hints.append("Every 3rd level, pick 1 of 3 perks. Injured crew rest here after a run; each job ends a day. Dismissed crew are gone for good. A wreck kills everyone seated; crew at the Inn or away are safe.")
	_empty.text = "\n".join(hints)
	_away.text = _away_text()
	if _expeditions != null:
		_fill_expeditions()


func _can_seat(m: Dictionary) -> bool:
	return profile.seat_block(m) == ""


func _status(card: CrewCard, m: Dictionary) -> void:
	var block := profile.seat_block(m)
	if bool(m.seated):
		card.status = "SEATED"
		card.status_color = T.COL_UI_ACCENT
	elif profile.is_away(m):
		card.status = "AWAY  -  %s" % _days_left_text(m)
		card.status_color = T.COL_ORANGE
		card.dim = true
	elif profile.is_resting(m):
		card.status = "INJURED  -  RESTING %d DAY%s" % [int(m.rest), "" if int(m.rest) == 1 else "S"]
		card.status_color = UI.BAD
		card.dim = true
	elif block != "":
		card.status = block
		card.status_color = UI.TEXT_DIM
	elif not profile.seated_in(str(m.role)).is_empty():
		card.status = "READY  -  SWAPS WITH THE %s" % Crew.role_name(m).to_upper()
		card.status_color = UI.GOOD
	else:
		card.status = "READY"
		card.status_color = UI.GOOD


func _days_left_text(m: Dictionary) -> String:
	for e: Dictionary in profile.expeditions:
		if (e.team as Array).has(int(m.id)):
			var d := int(e.days_left)
			return "BACK IN %d DAY%s" % [d, "" if d == 1 else "S"]
	return ""


func _away_text() -> String:
	if not profile.expeditions_open():
		return "Expeditions open after %d successful jobs (%d so far)." % [T.EXPEDITION_UNLOCK_CLEARS, int(profile.record.clears)]
	if profile.expeditions.is_empty():
		return "No team out. Send benched crew on an expedition for scrap and XP."
	var bits: Array[String] = []
	for e: Dictionary in profile.expeditions:
		bits.append("%s (%d skull%s): back in %d day%s" % [e.name, int(e.skulls), "" if int(e.skulls) == 1 else "s",
			int(e.days_left), "" if int(e.days_left) == 1 else "s"])
	return "OUT:  " + "    ".join(bits)


func select(id: int) -> void:
	selected_id = id
	_confirm_dismiss = -1
	refresh()


## SEAT the selected crew member, or send them back to the Inn if seated.
func seat_selected() -> bool:
	var m := profile.member(selected_id)
	if m.is_empty():
		return false
	_confirm_dismiss = -1
	if bool(m.seated):
		profile.unseat_member(selected_id)
		return true
	return profile.seat_member(selected_id)


## First tap asks, second tap dismisses.
func dismiss_selected() -> bool:
	if selected_id < 0:
		return false
	if _confirm_dismiss != selected_id:
		_confirm_dismiss = selected_id
		refresh()
		return false
	_confirm_dismiss = -1
	var ok := profile.dismiss(selected_id)
	selected_id = -1
	refresh()
	return ok


## Shows the selected crew member's 3 perk offers over the roster.
func open_perk_picker() -> bool:
	var m := profile.member(selected_id)
	var offer := profile.perk_offer(m) if not m.is_empty() else ([] as Array[String])
	if offer.is_empty():
		return false
	close_perk_picker()
	_picker = Control.new()
	_picker.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_picker)
	var bg := ColorRect.new()
	bg.color = Color(0.075, 0.075, 0.085, 0.97)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_picker.add_child(bg)
	var title := UI.label("%s  -  PICK A PERK" % str(m.name).to_upper(), 30, T.COL_ORANGE)
	title.position = Vector2(24, 14)
	_picker.add_child(title)
	var sub := "Level %d %s %s %s. Pick 1 of 3; you keep it for good." % [Crew.level(m), m.rarity, Crew.specialty_name(m), Crew.role_name(m)]
	_picker.add_child(_note(sub, Vector2(24, 58)))
	var card_size := Vector2(360, 220)
	var gap := 20.0
	var row := HBoxContainer.new()
	row.position = Vector2(maxf((size.x - (card_size.x * 3.0 + gap * 2.0)) * 0.5, 24.0), 110.0)
	row.add_theme_constant_override("separation", int(gap))
	_picker.add_child(row)
	for perk in offer:
		row.add_child(_perk_card(m, perk, card_size))
	var cancel := _button("LATER", 180)
	cancel.position = Vector2(row.position.x, 110.0 + card_size.y + 24.0)
	cancel.pressed.connect(close_perk_picker)
	_picker.add_child(cancel)
	return true


## One perk as a tappable card: name, whose perk it is, what it does.
func _perk_card(m: Dictionary, perk: String, card_size: Vector2) -> Button:
	var card := Button.new()
	card.focus_mode = Control.FOCUS_NONE
	card.custom_minimum_size = card_size
	card.pressed.connect(pick_perk.bind(perk))
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_FULL_RECT)
	box.offset_left = 20.0
	box.offset_right = -20.0
	box.offset_top = 22.0
	box.add_theme_constant_override("separation", 10)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(box)
	var shared := Crew.SHARED_PERKS.has(perk)
	UI.rarity_frame(card, UI.perk_rarity(_perk_tier(m, perk)))   # V1.3: perk tier colours
	var parts: Array = [
		[Crew.perk_name(perk).to_upper(), 26, T.COL_ORANGE],
		["ANY CLASS" if shared else "%s PERK" % Crew.role_name(m).to_upper(), 15, UI.TEXT_DIM if shared else Crew.role_color(m)],
		[Crew.perk_text(perk), 21, UI.TEXT],
	]
	for p: Array in parts:
		var l := UI.label(str(p[0]), int(p[1]), p[2])
		l.autowrap_mode = TextServer.AUTOWRAP_WORD
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.add_child(l)
	return card


## "minor", "major" or "signature" for a specialty perk; "" for old class perks.
func _perk_tier(m: Dictionary, perk: String) -> String:
	var tiers: Dictionary = Crew.SPECIALTY_PERKS.get(Crew.specialty(m), {})
	for tier: String in tiers:
		if (tiers[tier] as Array).has(perk):
			return tier
	return ""


func pick_perk(perk: String) -> bool:
	var ok := profile.choose_perk(selected_id, perk)
	close_perk_picker()
	refresh()
	return ok


func close_perk_picker() -> void:
	if _picker != null:
		_picker.queue_free()
		_picker = null


func is_picking_perk() -> bool:
	return _picker != null


# --- Expeditions ------------------------------------------------------------------

func open_expeditions() -> void:
	close_expeditions()
	close_perk_picker()
	profile.ensure_exp_board()
	trip = -1
	team = []
	for i in profile.exp_board.size():
		if not bool((profile.exp_board[i] as Dictionary).taken):
			trip = i
			break
	_expeditions = Control.new()
	_expeditions.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_expeditions)
	_fill_expeditions()


func close_expeditions() -> void:
	if _expeditions != null:
		_expeditions.queue_free()
		_expeditions = null


func is_showing_expeditions() -> bool:
	return _expeditions != null


func pick_trip(index: int) -> void:
	trip = index
	_fill_expeditions()


## Add crew `id` to the team, or take them off it.
func toggle_team(id: int) -> void:
	if team.has(id):
		team.erase(id)
	elif team.size() < T.EXPEDITION_MAX_TEAM and profile.can_send(profile.member(id)):
		team.append(id)
	_fill_expeditions()


func send_selected() -> bool:
	var ok := profile.send_expedition(trip, team)
	if ok:
		team = []
		trip = -1
	refresh()
	return ok


func _fill_expeditions() -> void:
	for c in _expeditions.get_children():
		_expeditions.remove_child(c)
		c.queue_free()
	var bg := ColorRect.new()
	bg.color = Color(0.075, 0.075, 0.085)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	_expeditions.add_child(bg)
	var title := UI.label("EXPEDITIONS   -   DAY %d" % profile.day, 30, T.COL_ORANGE)
	title.position = Vector2(24, 14)
	_expeditions.add_child(title)
	var close := _button("CLOSE", 140)
	close.anchor_left = 1.0
	close.anchor_right = 1.0
	close.offset_left = -160.0
	close.offset_right = -20.0
	close.offset_top = 10.0
	close.offset_bottom = 60.0
	close.pressed.connect(close_expeditions)
	_expeditions.add_child(close)
	var sub := "Teams out  %d / %d      Scrap  %d" % [profile.expeditions.size(), profile.expeditions_at_once(), profile.scrap]
	_expeditions.add_child(_note(sub, Vector2(24, 58)))
	if not profile.expeditions_open():
		var locked := UI.label("The expedition board opens after %d successful jobs. You have %d.\n\nBenched crew can then go out for 1-3 days to bring back scrap and XP, and sometimes a schematic or a recruit. Nobody is ever lost on an expedition." % [T.EXPEDITION_UNLOCK_CLEARS, int(profile.record.clears)], 22, UI.TEXT)
		locked.autowrap_mode = TextServer.AUTOWRAP_WORD
		locked.position = Vector2(24, 120)
		locked.size = Vector2(900, 300)
		_expeditions.add_child(locked)
		return

	# Left: today's trips.
	var trips := VBoxContainer.new()
	trips.position = Vector2(24, 96)
	trips.custom_minimum_size = Vector2(600, 0)
	trips.add_theme_constant_override("separation", 10)
	_expeditions.add_child(trips)
	for i in profile.exp_board.size():
		trips.add_child(_trip_card(i))
	if not profile.expedition_reports.is_empty():
		var report := UI.label("LAST RETURN\n" + "\n".join(profile.expedition_reports), 16, UI.TEXT_DIM)
		report.autowrap_mode = TextServer.AUTOWRAP_WORD
		report.custom_minimum_size = Vector2(600, 0)
		trips.add_child(report)

	# Right: the team.
	var right := VBoxContainer.new()
	right.position = Vector2(650, 96)
	right.custom_minimum_size = Vector2(606, 0)
	right.add_theme_constant_override("separation", 10)
	_expeditions.add_child(right)
	right.add_child(UI.label("TEAM  -  %s benched crew (up to %d)" % [PadScript.hint("tap", "pick"), T.EXPEDITION_MAX_TEAM], 20, T.COL_UI_ACCENT))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	right.add_child(grid)
	var free := 0
	for m: Dictionary in profile.crew:
		if not profile.can_send(m):
			continue
		free += 1
		var b := _button("%s   L%d %s" % [m.name, Crew.level(m), Crew.role_name(m)], 299)
		b.custom_minimum_size.y = 50
		b.clip_text = true
		if team.has(int(m.id)):
			UI.accent(b, T.COL_UI_ACCENT)
		b.pressed.connect(toggle_team.bind(int(m.id)))
		grid.add_child(b)
	if free == 0:
		right.add_child(UI.label("No benched crew. Seated, resting and away crew can't go.", 18, UI.TEXT_DIM))
	var odds_label := UI.label("", 22, UI.TEXT)
	right.add_child(odds_label)
	var send := _button("SEND", 0)
	send.custom_minimum_size = Vector2(0, 58)
	UI.accent(send, T.COL_ORANGE)
	send.pressed.connect(send_selected)
	right.add_child(send)
	if trip >= 0 and trip < profile.exp_board.size():
		var e: Dictionary = profile.exp_board[trip]
		var odds := profile.expedition_odds(e, team)
		odds_label.text = "TEAM LEVEL  %d  /  %d recommended      ODDS  %d%%" % [profile.team_level(team), ProfileScript.recommended_level(e), roundi(odds * 100.0)]
		odds_label.add_theme_color_override("font_color", UI.GOOD if odds >= T.EXPEDITION_ODDS else (T.COL_ORANGE if odds >= 0.4 else UI.BAD))
	var block := profile.send_block(trip, team)
	send.disabled = block != ""
	send.text = "SEND" if block == "" else block
	right.add_child(_note_wrap("Success: full scrap and XP (split among the team) and the bonus roll. Failure: %d%% of the scrap, half the XP, and each member may come back injured. Nobody is ever lost." % roundi(T.EXPEDITION_FAIL_SCRAP * 100.0)))


func _trip_card(i: int) -> Button:
	var e: Dictionary = profile.exp_board[i]
	var card := _button("", 0)
	card.custom_minimum_size = Vector2(600, 104)
	if i == trip:
		UI.accent(card, T.COL_UI_ACCENT)
	card.pressed.connect(pick_trip.bind(i))
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_FULL_RECT)
	box.offset_left = 16.0
	box.offset_right = -16.0
	box.offset_top = 8.0
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override("separation", 2)
	card.add_child(box)
	var skulls := int(e.skulls)
	var days := int(e.days)
	var head := "%s      %d SKULL%s   %d DAY%s" % [str(e.name).to_upper(), skulls, "" if skulls == 1 else "S", days, "" if days == 1 else "S"]
	box.add_child(UI.label(head, 21, UI.skull_color(skulls) if not bool(e.taken) else UI.TEXT_DIM))
	box.add_child(UI.label("Recommended team level %d     Pays %d scrap, %d XP" % [ProfileScript.recommended_level(e), ProfileScript.expedition_scrap(e), ProfileScript.expedition_xp(e)], 17, UI.TEXT))
	var extra := "SENT" if bool(e.taken) else ""
	if str(e.bonus) != "":
		extra = ("%s    " % extra if extra != "" else "") + "%s CHANCE %d%%" % [str(e.bonus).to_upper(), roundi(ProfileScript.bonus_chance(e) * 100.0)]
	box.add_child(UI.label(extra, 17, T.COL_ORANGE if not bool(e.taken) else UI.TEXT_DIM))
	return card


func _note_wrap(text: String) -> Label:
	var l := UI.label(text, 16, UI.TEXT_DIM)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD
	l.custom_minimum_size = Vector2(600, 0)
	return l


# --- Upgrades ----------------------------------------------------------------------

func open_upgrades() -> UpgradePanel:
	close_upgrades()
	_upgrades = UpgradePanel.new()
	_upgrades.setup(profile, "INN UPGRADES", INN_UPGRADES, _upgrade_effect,
		"Last Rites goes on sale once %s is open." % str(T.DISTRICTS[T.LAST_RITES_DISTRICT].name))
	_upgrades.closed.connect(func() -> void: _upgrades = null)
	add_child(_upgrades)
	return _upgrades


func close_upgrades() -> void:
	if _upgrades != null:
		_upgrades.close()


func _upgrade_effect(key: String) -> String:
	var lv := profile.upgrade_level(key)
	var step := float(T.UPGRADES[key].per_level)
	match key:
		"bunkhouse":
			return "Roster holds %d crew" % profile.roster_cap()
		"drill_yard":
			return "Crew idle at the Inn learn %d%% of each job's XP" % roundi(step * lv * 100.0)
		"infirmary":
			return "Injury rest %d day%s shorter (never under 1)" % [lv, "" if lv == 1 else "s"]
		"second_team":
			return "Expeditions out at once: %d" % profile.expeditions_at_once()
		"scout_network":
			return "Expedition odds +%d%%" % roundi(step * lv * 100.0)
		"last_rites":
			return "On a wreck, each seated crew member survives %d%% of the time (injured, %d days' rest)" % [roundi(step * lv * 100.0), T.LAST_RITES_REST]
	return ""


func _note(text: String, at: Vector2) -> Label:
	var l := UI.label(text, 20, UI.TEXT_DIM)
	l.position = at
	return l


func _button(text: String, min_width: float) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(min_width, 0)
	return b
