extends Control
## The Saloon (DESIGN §5): hire crew. Crew lost in a wreck turn up again
## after a few days: one of them sits at the end of the row each day, cheaper
## than a fresh hire, and can be sent away for good (§14). Three paid offers a day (rarity rolled
## by T.SALOON_ODDS, refreshed when the day ends) and a free Common Driver
## and Gunner who are always there. A new hire takes an empty seat of their
## role if the frame has one, otherwise waits at the Inn.

const T := preload("res://scripts/tuning.gd")
const UI := preload("res://scripts/ui_theme.gd")
const Crew := preload("res://scripts/crew.gd")
const CrewCard := preload("res://scripts/crew_card.gd")
const ProfileScript := preload("res://scripts/profile.gd")
const UpgradePanel := preload("res://scripts/upgrade_panel.gd")

const SALOON_UPGRADES := ["back_room", "word_around", "seasoned_hands", "house_credit", "old_faces"]

const FREE_ROLES := ["driver", "gunner"]

var profile: ProfileScript
var selected := -1        # 0..offers-1 = paid offers, then the free Driver and Gunner, then a rehire

var _title: Label
var _info: Label
var _cards: HBoxContainer
var _hire: Button
var _send_away: Button
var _note: Label
var _upgrades: UpgradePanel


func _ready() -> void:
	profile = get_node("/root/Profile")
	var bg := ColorRect.new()
	bg.color = Color(0.075, 0.075, 0.085)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	_title = UI.label("", 30, T.COL_UI_ACCENT)
	_title.position = Vector2(24, 14)
	add_child(_title)
	_info = UI.label("", 22, T.COL_ORANGE)
	_info.position = Vector2(24, 54)
	add_child(_info)

	var bar := HBoxContainer.new()
	bar.anchor_left = 1.0
	bar.anchor_right = 1.0
	bar.offset_left = -600.0
	bar.offset_right = -20.0
	bar.offset_top = 10.0
	bar.offset_bottom = 60.0
	bar.alignment = BoxContainer.ALIGNMENT_END
	bar.add_theme_constant_override("separation", 10)
	add_child(bar)
	var up := Button.new()
	up.text = "UPGRADES"
	up.focus_mode = Control.FOCUS_NONE
	up.custom_minimum_size = Vector2(170, 0)
	up.pressed.connect(open_upgrades)
	bar.add_child(up)
	_send_away = Button.new()
	_send_away.text = "SEND AWAY"
	_send_away.focus_mode = Control.FOCUS_NONE
	_send_away.custom_minimum_size = Vector2(170, 0)
	_send_away.pressed.connect(send_away_selected)
	bar.add_child(_send_away)
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

	_note = UI.label("", 18, UI.TEXT_DIM)
	_note.anchor_right = 1.0
	_note.offset_left = 24.0
	_note.offset_right = -24.0
	_note.offset_top = 420.0
	_note.autowrap_mode = TextServer.AUTOWRAP_WORD
	add_child(_note)

	profile.changed.connect(refresh)
	refresh()


func refresh() -> void:
	if not is_inside_tree():
		return
	profile.ensure_saloon()
	_title.text = "SALOON   -   DAY %d" % profile.day
	_info.text = "SCRAP  %d      ROSTER  %d / %d" % [profile.scrap, profile.crew.size(), profile.roster_cap()]
	var start := 1 + profile.upgrade_level("seasoned_hands")
	_note.text = "New hires start at level %d (capped by rarity) with a random specialty. Offers can be any class and change when the day ends. Free Common Drivers and Gunners are always here, even with a full roster (one over the cap), so you can never get stuck without a Driver.\nOdds today: %s" % [start, odds_text()]
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
		if bool(m.get("rehire", false)):
			card.status = "BACK  %d SCRAP" % price
			card.status_color = T.COL_ORANGE if price <= profile.scrap else UI.BAD
		elif bool(m.get("hired", false)):
			card.status = "HIRED"
			card.status_color = T.COL_UI_ACCENT
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
	_send_away.visible = is_rehire(selected)
	if not profile.rehire_pool.is_empty() or not profile.lost.is_empty():
		_note.text += "\nLost crew coming back: %d on the way, %d waiting for their card." % [profile.lost.size(), profile.rehire_pool.size()]


## Paid offers first, then the free Driver and Gunner, then today's rehire.
func offer_count() -> int:
	return profile.saloon.size() + FREE_ROLES.size() + (0 if profile.rehire_offer().is_empty() else 1)


func is_rehire(i: int) -> bool:
	return i >= 0 and i == profile.saloon.size() + FREE_ROLES.size() and not profile.rehire_offer().is_empty()


func offer(i: int) -> Dictionary:
	if i < profile.saloon.size():
		return profile.saloon[i]
	if is_rehire(i):
		return profile.rehire_offer()
	var role: String = FREE_ROLES[i - profile.saloon.size()]
	var m := {"id": 0, "name": "Free %s" % Crew.ROLE_NAMES[role], "role": role, "rarity": "Common",
		"specialty": "", "xp": 0.0, "perks": [], "rest": 0, "seated": false, "price": 0}
	m.xp = profile.hire_start_xp(m)
	return m


func odds_text() -> String:
	var odds := ProfileScript.saloon_odds(profile.upgrade_level("word_around"))
	var bits: Array[String] = []
	for r: String in odds:
		bits.append("%s %s%%" % [r, str(snappedf(float(odds[r]), 0.1)).trim_suffix(".0")])
	return "   ".join(bits)


func open_upgrades() -> UpgradePanel:
	close_upgrades()
	_upgrades = UpgradePanel.new()
	_upgrades.setup(profile, "SALOON UPGRADES", SALOON_UPGRADES, _upgrade_effect)
	_upgrades.closed.connect(func() -> void: _upgrades = null)
	add_child(_upgrades)
	return _upgrades


func close_upgrades() -> void:
	if _upgrades != null:
		_upgrades.close()


func _upgrade_effect(key: String) -> String:
	var lv := profile.upgrade_level(key)
	match key:
		"back_room":
			return "Paid offers per day: %d" % profile.saloon_offers()
		"word_around":
			return "Odds: " + odds_text()
		"seasoned_hands":
			return "Hires start at level %d" % (1 + lv)
		"house_credit":
			return "Hire prices %d%% lower" % roundi(float(T.UPGRADES.house_credit.per_level) * lv * 100.0)
		"old_faces":
			return "Rehires %d%% below a fresh hire" % roundi((T.REHIRE_DISCOUNT + float(T.UPGRADES.old_faces.per_level) * lv) * 100.0)
	return ""


## Why `i` can't be hired right now, or "".
func _block(i: int) -> String:
	if i < 0:
		return "PICK A HIRE"
	var m := offer(i)
	if bool(m.get("hired", false)):
		return "HIRED"
	var free := i >= profile.saloon.size() and not is_rehire(i)
	if free and not profile.can_hire_basic():
		return "ROSTER FULL"
	if not free and profile.roster_full():
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
	if is_rehire(selected):
		selected = -1   # the card goes once hired; refreshes mid-hire mustn't point at it
		ok = profile.rehire()
	elif selected < profile.saloon.size():
		ok = profile.hire_offer(selected)
	else:
		ok = profile.hire_basic(FREE_ROLES[selected - profile.saloon.size()])
	refresh()
	return ok


## Today's rehire goes for good (back to the general hire pool).
func send_away_selected() -> bool:
	if not is_rehire(selected):
		return false
	var ok := profile.dismiss_rehire()
	selected = -1
	refresh()
	return ok
