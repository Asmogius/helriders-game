extends Control
## The Inn (DESIGN §5): your crew roster. Tap a crew member, then SEAT them
## on the rig (one per role, if the frame has that seat), send them back to
## the Inn, or DISMISS them. Injured crew rest here until healed.

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
	bar.offset_left = -560.0
	bar.offset_right = -20.0
	bar.offset_top = 10.0
	bar.offset_bottom = 60.0
	bar.alignment = BoxContainer.ALIGNMENT_END
	bar.add_theme_constant_override("separation", 10)
	add_child(bar)
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
	for seat: String in profile.seats():
		var m := profile.seated_in(seat)
		var who := str(m.name) if not m.is_empty() else "empty"
		if seat == "mechanic":
			who = "(coming later)"
		seat_bits.append("%s  %s" % [str(Crew.ROLE_NAMES[seat]).to_upper(), who])
	_seats.text = "SEATS ON THIS FRAME:   " + ("      ".join(seat_bits) if not seat_bits.is_empty() else "build a rig first")
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
	_dismiss.text = "TAP AGAIN" if _confirm_dismiss == selected_id and selected_id >= 0 else "DISMISS"
	var hints: Array[String] = []
	if profile.crew.is_empty():
		hints.append("No crew. The Saloon always has a free Common Driver and Gunner.")
	hints.append("Injured crew rest here after a run; each job ends a day. Dismissed crew are gone for good. A wreck kills everyone seated.")
	_empty.text = "\n".join(hints)


func _can_seat(m: Dictionary) -> bool:
	return not profile.is_resting(m) and profile.seats().has(str(m.role))


func _status(card: CrewCard, m: Dictionary) -> void:
	if bool(m.seated):
		card.status = "SEATED"
		card.status_color = T.COL_CYAN
	elif profile.is_resting(m):
		card.status = "INJURED  -  RESTING %d DAY%s" % [int(m.rest), "" if int(m.rest) == 1 else "S"]
		card.status_color = UI.BAD
		card.dim = true
	elif not profile.seats().has(str(m.role)):
		card.status = "NO %s SEAT ON THIS FRAME" % Crew.role_name(m).to_upper()
		card.status_color = UI.TEXT_DIM
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


func _button(text: String, min_width: float) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(min_width, 0)
	return b
