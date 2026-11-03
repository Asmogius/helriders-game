extends Control
## The Inn (DESIGN §5): your crew roster. Tap a crew member, then SEAT them
## on the rig (Driver and Gunner seats, or an open seat for the other classes,
## one of each class), UNSEAT them, DISMISS them, or PICK PERK when a perk is
## waiting. Injured crew rest here until healed.

const T := preload("res://scripts/tuning.gd")
const UI := preload("res://scripts/ui_theme.gd")
const Crew := preload("res://scripts/crew.gd")
const CrewCard := preload("res://scripts/crew_card.gd")
const ProfileScript := preload("res://scripts/profile.gd")

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


func _ready() -> void:
	profile = get_node("/root/Profile")
	var bg := ColorRect.new()
	bg.color = Color(0.075, 0.075, 0.085)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	_title = UI.label("", 30, T.COL_CYAN)
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
	UI.accent(_seat, T.COL_CYAN)
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

	profile.changed.connect(refresh)
	refresh()


func refresh() -> void:
	_title.text = "INN   -   ROSTER %d / %d" % [profile.crew.size(), T.ROSTER_SIZE]
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
	_dismiss.disabled = sel.is_empty()
	_perk.visible = not sel.is_empty() and Crew.perks_due(sel) > 0
	_dismiss.text = "TAP AGAIN" if _confirm_dismiss == selected_id and selected_id >= 0 else "DISMISS"
	var hints: Array[String] = []
	if profile.crew.is_empty():
		hints.append("No crew. The Saloon always has a free Common Driver and Gunner.")
	var waiting := profile.perks_waiting()
	if waiting > 0:
		hints.append("%d perk pick%s waiting: tap a PERK READY card, then PICK PERK." % [waiting, "" if waiting == 1 else "s"])
	hints.append("Every 3rd level, pick 1 of 3 perks. Injured crew rest here after a run; each job ends a day. Dismissed crew are gone for good. A wreck kills everyone seated.")
	_empty.text = "\n".join(hints)


func _can_seat(m: Dictionary) -> bool:
	return profile.seat_block(m) == ""


func _status(card: CrewCard, m: Dictionary) -> void:
	var block := profile.seat_block(m)
	if bool(m.seated):
		card.status = "SEATED"
		card.status_color = T.COL_CYAN
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
