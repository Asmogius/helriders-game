extends Control
## The Saloon (DESIGN §5): hire crew. Three paid offers a day (rarity rolled
## by T.SALOON_ODDS, refreshed when the day ends) and a free Common Driver
## and Gunner who are always there. A new hire takes an empty seat of their
## role if the frame has one, otherwise waits at the Inn.

const T := preload("res://scripts/tuning.gd")
const UI := preload("res://scripts/ui_theme.gd")
const Crew := preload("res://scripts/crew.gd")
const CrewCard := preload("res://scripts/crew_card.gd")
const ProfileScript := preload("res://scripts/profile.gd")

const FREE_ROLES := ["driver", "gunner"]

var profile: ProfileScript
var selected := -1        # 0..offers-1 = paid offers, then the free Driver and Gunner

var _title: Label
var _info: Label
var _cards: HBoxContainer
var _hire: Button


func _ready() -> void:
	profile = get_node("/root/Profile")
	var bg := ColorRect.new()
	bg.color = Color(0.075, 0.075, 0.085)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	_title = UI.label("", 30, T.COL_CYAN)
	_title.position = Vector2(24, 14)
	add_child(_title)
	_info = UI.label("", 22, T.COL_ORANGE)
	_info.position = Vector2(24, 54)
	add_child(_info)

	var bar := HBoxContainer.new()
	bar.anchor_left = 1.0
	bar.anchor_right = 1.0
	bar.offset_left = -400.0
	bar.offset_right = -20.0
	bar.offset_top = 10.0
	bar.offset_bottom = 60.0
	bar.alignment = BoxContainer.ALIGNMENT_END
	add_child(bar)
	_hire = Button.new()
	_hire.text = "HIRE"
	_hire.focus_mode = Control.FOCUS_NONE
	_hire.custom_minimum_size = Vector2(220, 0)
	UI.accent(_hire, T.COL_ORANGE)
	_hire.pressed.connect(hire_selected)
	bar.add_child(_hire)

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

	var note := UI.label("New hires start at level 1 with a random specialty. Offers can be any class and change when the day ends. Free Common Drivers and Gunners are always here, so you can never get stuck without a Driver.", 18, UI.TEXT_DIM)
	note.anchor_right = 1.0
	note.offset_left = 24.0
	note.offset_right = -24.0
	note.offset_top = 420.0
	note.autowrap_mode = TextServer.AUTOWRAP_WORD
	add_child(note)

	profile.changed.connect(refresh)
	refresh()


func refresh() -> void:
	profile.ensure_saloon()
	_title.text = "SALOON   -   DAY %d" % profile.day
	_info.text = "SCRAP  %d      ROSTER  %d / %d" % [profile.scrap, profile.crew.size(), T.ROSTER_SIZE]
	for c in _cards.get_children():
		_cards.remove_child(c)
		c.queue_free()
	var count := offer_count()
	for i in count:
		var m := offer(i)
		var card := CrewCard.new()
		card.member = m
		card.selected = i == selected
		var price := profile.hire_price(m)
		if bool(m.get("hired", false)):
			card.status = "HIRED"
			card.status_color = T.COL_CYAN
			card.dim = true
		elif price == 0:
			card.status = "FREE"
			card.status_color = UI.GOOD
		else:
			card.status = "%d SCRAP" % price
			card.status_color = T.COL_ORANGE if price <= profile.scrap else UI.BAD
		card.pressed.connect(select.bind(i))
		_cards.add_child(card)
	var reason := _block(selected)
	_hire.disabled = reason != ""
	_hire.text = "HIRE" if selected < 0 or reason == "" else reason


## Paid offers first, then the free Driver and Gunner.
func offer_count() -> int:
	return profile.saloon.size() + FREE_ROLES.size()


func offer(i: int) -> Dictionary:
	if i < profile.saloon.size():
		return profile.saloon[i]
	var role: String = FREE_ROLES[i - profile.saloon.size()]
	return {"id": 0, "name": "Free %s" % Crew.ROLE_NAMES[role], "role": role, "rarity": "Common",
		"specialty": "", "xp": 0.0, "perks": [], "rest": 0, "seated": false, "price": 0}


## Why `i` can't be hired right now, or "".
func _block(i: int) -> String:
	if i < 0:
		return "PICK A HIRE"
	var m := offer(i)
	if bool(m.get("hired", false)):
		return "HIRED"
	if profile.roster_full():
		return "ROSTER FULL"
	if profile.hire_price(m) > profile.scrap:
		return "NEED %d SCRAP" % profile.hire_price(m)
	return ""


func select(i: int) -> void:
	selected = i
	refresh()


func hire_selected() -> bool:
	if _block(selected) != "":
		return false
	var ok := false
	if selected < profile.saloon.size():
		ok = profile.hire_offer(selected)
	else:
		ok = profile.hire_basic(FREE_ROLES[selected - profile.saloon.size()])
	refresh()
	return ok
