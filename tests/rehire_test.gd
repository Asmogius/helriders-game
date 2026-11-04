extends SceneTree
## Headless test for lost crew and rehires (§14): who is lost in a wreck (and
## that Commons and Last Rites survivors aren't), return days by rarity, the
## rehire pool (level 1, perks reset, same specialty and rarity), the daily
## rehire card and its price (20% off, Old Faces, House Credit, Seasoned
## Hands), hiring and sending away, the save file, the Saloon screen, and the
## wreck card naming who'll be back.
##
## Run:  godot --headless --fixed-fps 60 --path . -s res://tests/rehire_test.gd

const Garage := preload("res://scripts/garage.gd")
const Mission := preload("res://scripts/mission.gd")
const Missions := preload("res://scripts/missions.gd")
const ProfileScript := preload("res://scripts/profile.gd")
const Crew := preload("res://scripts/crew.gd")
const T := preload("res://scripts/tuning.gd")

var profile: ProfileScript
var garage: Garage
var mission: Mission
var frame := 0
var failures: Array[String] = []


func _initialize() -> void:
	profile = root.get_node("Profile")
	profile.persist = false
	profile.new_game()


func _process(_delta: float) -> bool:
	frame += 1
	if frame == 2:
		_check_rules()
		_check_save()
		_check_screen()
		_start_wreck()
	if frame == 10:
		mission.vehicle.take_damage(1000000.0)
	if frame == 330:   # the card comes up after the ~4 s wreck sequence
		var text := str((mission.hud.get("_subtitle") as Label).text)
		_check(text.contains("turn up at the Saloon again") and text.contains("in 2 days"), "the wreck card says who'll turn up again, and when: " + text.replace("\n", " / "))
		_finish()
	return false


## A seated member of `role` and `rarity` (the old one in that seat goes to the bench).
func _seat(role: String, rarity: String) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(role + rarity)
	var old := profile.seated_in(role)
	if not old.is_empty():
		old.seated = false
	var m := profile._add_crew(Crew.make(role, rarity, rng))
	m.seated = true
	return m


func _check_rules() -> void:
	profile.scrap = 5000
	var common := profile.seated_in("driver")   # the free Common Driver
	var gun := _seat("gunner", "Uncommon")
	gun.xp = float(Crew.xp_for_level(5))
	gun.perks = Crew.perk_pool(gun).slice(0, 1)
	var spec := str(gun.specialty)
	var rare := profile.member(int(_seat("mechanic", "Rare").id))
	var rare_name := str(rare.name)
	profile.record_wreck()
	_check(profile.lost.size() == 2, "the Uncommon and Rare are lost; the Common doesn't come back (%d)" % profile.lost.size())
	_check(profile.member(int(gun.id)).is_empty() and profile.member(int(common.id)).is_empty(), "everyone seated is gone from the roster")
	var by_name := {}
	for m: Dictionary in profile.lost:
		by_name[str(m.name)] = int(m.back_in)
	_check(int(by_name.get(str(gun.name), 0)) == 3 and int(by_name.get(rare_name, 0)) == 4, "back in 3 days (Uncommon) and 4 (Rare)")
	profile.finish_day()
	profile.finish_day()
	_check(profile.rehire_pool.is_empty(), "not back yet after 2 days")
	profile.finish_day()
	_check(profile.rehire_pool.size() == 1 and profile.lost.size() == 1, "the Uncommon turns up on day 3")
	var back: Dictionary = profile.rehire_pool[0]
	_check(str(back.name) == str(gun.name) and str(back.specialty) == spec and str(back.rarity) == "Uncommon", "same name, specialty and rarity")
	_check(Crew.level(back) == 1 and (back.perks as Array).is_empty(), "back at level 1 with perks reset")

	var offer := profile.rehire_offer()
	_check(str(offer.name) == str(gun.name) and profile.hire_price(offer) == 64, "the day's rehire card: 20%% below a fresh hire (80 -> %d)" % profile.hire_price(offer))
	profile.upgrades.old_faces = 3
	_check(profile.hire_price(profile.rehire_offer()) == 40, "Old Faces 3: half price (%d)" % profile.hire_price(profile.rehire_offer()))
	profile.upgrades.house_credit = 1
	_check(profile.hire_price(profile.rehire_offer()) == 36, "House Credit stacks (%d)" % profile.hire_price(profile.rehire_offer()))
	profile.upgrades.seasoned_hands = 1
	_check(Crew.level(profile.rehire_offer()) == 2, "Seasoned Hands: they come back a level higher")

	var before := profile.scrap
	var roster := profile.crew.size()
	_check(profile.rehire() and profile.scrap == before - 36 and profile.crew.size() == roster + 1, "rehire them for the card price")
	_check(profile.rehire_pool.is_empty() and profile.rehire_offer().is_empty(), "one card a day: gone once hired")
	var rehired := profile.crew[profile.crew.size() - 1] as Dictionary
	_check(Crew.level(rehired) == 2 and str(rehired.name) == str(gun.name), "rehired at the Seasoned Hands level")

	profile.finish_day()
	_check(profile.rehire_pool.size() == 1 and str(profile.rehire_offer().name) == rare_name, "the Rare turns up a day later")
	# Starting above level 1 still leaves every perk pick to the player.
	profile.upgrades.seasoned_hands = 2
	var card := profile.rehire_offer()
	_check(Crew.level(card) == 3 and Crew.perks_due(card) == 1, "a rehire starting at level 3 has its level-3 perk pick waiting")
	profile.ensure_saloon()
	var idx := -1
	for i in profile.saloon.size():
		if Crew.max_level(profile.saloon[i]) >= 3 and not bool(profile.saloon[i].hired):
			idx = i
			break
	if idx >= 0 and profile.hire_offer(idx):
		var hired := profile.crew[profile.crew.size() - 1] as Dictionary
		_check(Crew.level(hired) == 3 and Crew.perks_due(hired) == 1 and profile.perk_offer(hired).size() > 0, "so does a fresh hire: the pick is offered, not made for them")
	else:
		_check(false, "a fresh hire at level 3 (no offer could reach level 3 today)")
	profile.upgrades.seasoned_hands = 1
	_check(profile.dismiss_rehire() and profile.rehire_pool.is_empty() and profile.rehire_offer().is_empty(), "SEND AWAY: gone for good")
	_check(profile.lost.is_empty(), "nobody left on the way back")

	# Last Rites survivors aren't lost.
	profile.upgrades.last_rites = 1
	profile.roll_override = 0.0
	var lucky := _seat("gunner", "Rare")
	profile.record_wreck()
	profile.roll_override = -1.0
	_check(not profile.member(int(lucky.id)).is_empty() and profile.lost.is_empty(), "Last Rites survivors stay on the roster, not in the lost list")
	profile.upgrades.last_rites = 0


func _check_save() -> void:
	_seat("driver", "Common")
	_seat("gunner", "Epic")
	_seat("medic", "Uncommon")
	profile.record_wreck()
	profile.finish_day()
	profile.finish_day()
	profile.finish_day()   # the Uncommon is in the pool, the Epic still out
	profile.persist = true
	profile.save_path = "user://helriders_rehire_test_save.json"
	profile.save_game()
	var lost := _names(profile.lost)
	var pool := _names(profile.rehire_pool)
	var card := str(profile.rehire_offer())
	profile.lost = []
	profile.rehire_pool = []
	_check(profile.load_game() and _names(profile.lost) == lost and _names(profile.rehire_pool) == pool and not lost.is_empty() and not pool.is_empty(),
		"the lost and the rehire pool round-trip (%s / %s)" % [lost, pool])
	_check(str(profile.rehire_offer()) == card, "and so does today's card")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(profile.save_path))
	profile.persist = false


func _names(list: Array) -> String:
	var out: Array[String] = []
	for m: Dictionary in list:
		out.append("%s:%s:%s:%d" % [str(m.name), str(m.rarity), str(m.specialty), int(m.get("back_in", 0))])
	return ",".join(out)


func _check_screen() -> void:
	garage = (load("res://scenes/garage.tscn") as PackedScene).instantiate() as Garage
	root.add_child(garage)
	garage.show_tab("SALOON")
	var saloon := garage._saloon
	saloon.refresh()
	var n := saloon.offer_count()
	_check(n == profile.saloon.size() + 3 and saloon.is_rehire(n - 1), "the rehire card sits at the end of the Saloon row")
	var card: Node = saloon._cards.get_child(n - 1)
	_check(str(card.get("status")).begins_with("BACK"), "marked BACK with its price")
	saloon.select(n - 1)
	_check(saloon._send_away.visible, "SEND AWAY shows for the rehire")
	var roster := profile.crew.size()
	_check(saloon.hire_selected() and profile.crew.size() == roster + 1 and saloon.offer_count() == n - 1, "HIRE takes them back; the card goes")
	_check(saloon._note.text.contains("Lost crew coming back: 1 on the way"), "the Saloon says who's still on the way")
	var panel := saloon.open_upgrades()
	_check(panel.keys.has("old_faces"), "Old Faces is in the Saloon upgrades")
	saloon.close_upgrades()
	garage.queue_free()


## A real wreck in a mission, with an Uncommon Gunner aboard.
func _start_wreck() -> void:
	profile.rig = (load("res://scripts/parts.gd").STARTER_LOADOUT as Dictionary).duplicate(true)
	_seat("driver", "Common")
	_seat("gunner", "Uncommon")
	mission = (load("res://scenes/mission.tscn") as PackedScene).instantiate() as Mission
	mission.mission_override = Missions.make("clear", 1, 7)
	mission.auto_spawn_specials = false
	root.add_child(mission)


func _check(ok: bool, what: String) -> void:
	print(("  PASS  " if ok else "  FAIL  ") + what)
	if not ok:
		failures.append(what)


func _finish() -> void:
	if failures.is_empty():
		print("REHIRE TEST PASSED")
		quit(0)
	else:
		print("REHIRE TEST FAILED: %s" % ", ".join(failures))
		quit(1)
