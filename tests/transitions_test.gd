extends SceneTree
## V6.5 transitions: the crew-card level-up flash plays once when a member's
## level is higher than the last card showed, and a new game forgets the levels.
##
## Run:  godot --headless --fixed-fps 60 --path . -s res://tests/transitions_test.gd

const Crew := preload("res://scripts/crew.gd")
const CrewCard := preload("res://scripts/crew_card.gd")

var failures: Array[String] = []


func _check(ok: bool, what: String) -> void:
	if ok:
		print("  PASS  ", what)
	else:
		failures.append(what)
		print("FAIL: ", what)


func _card(m: Dictionary) -> CrewCard:
	var c := CrewCard.new()
	c.member = m
	root.add_child(c)
	return c


var _done := false


func _process(_delta: float) -> bool:
	if _done:
		return true
	_done = true
	_run()
	return false


func _run() -> void:   # in _process: cards need the tree for _ready
	var profile: Node = root.get_node("Profile")
	profile.persist = false
	profile.new_game()
	var m: Dictionary = profile.crew[0]
	m.xp = 0.0
	var first := _card(m)
	_check(not first.flashed, "first card for a member doesn't flash")
	var again := _card(m)
	_check(not again.flashed, "same level shown again doesn't flash")
	m.xp = float(Crew.xp_for_level(Crew.level(m) + 1))
	var up := _card(m)
	_check(Crew.level(m) == 2 and up.flashed, "a card after a level-up flashes")
	var after := _card(m)
	_check(not after.flashed, "the flash plays once per level-up")
	# A new game starts the ids over. Without the reset, the old game's level-1
	# card would make this game's first sight of a level-2 member "flash".
	var old_id := int(m.id)
	m.xp = 0.0
	_card(m)   # old game: last shown at level 1
	profile.new_game()
	var fresh: Dictionary = profile.crew[0]
	_check(int(fresh.id) == old_id, "new game reuses the member id (the case the reset covers)")
	fresh.xp = float(Crew.xp_for_level(2))
	_check(not _card(fresh).flashed, "new game: no flash carried over from the last game")
	fresh.xp = float(Crew.xp_for_level(3))
	_check(_card(fresh).flashed, "new game: a real level-up still flashes")
	for c in root.get_children():
		if c is CrewCard:
			c.queue_free()
	if failures.is_empty():
		print("TRANSITIONS TEST PASSED")
	else:
		print("TRANSITIONS TEST FAILED: ", failures.size())
	quit(0 if failures.is_empty() else 1)
