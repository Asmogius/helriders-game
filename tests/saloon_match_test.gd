extends SceneTree
## Headless test: every Saloon card (paid offers, the free Driver and Gunner,
## today's rehire) is exactly who HIRE adds: same name, class, specialty and
## rarity (playtest 18.png: card Wheelman/HARD LINE, hire Speedster/FLOOR IT).
##
## Run:  godot --headless --fixed-fps 60 --path . -s res://tests/saloon_match_test.gd

const Garage := preload("res://scripts/garage.gd")
const ProfileScript := preload("res://scripts/profile.gd")
const Crew := preload("res://scripts/crew.gd")

var profile: ProfileScript
var garage: Garage
var frame := 0
var failures: Array[String] = []


func _initialize() -> void:
	profile = root.get_node("Profile")
	profile.persist = false
	profile.new_game()


func _process(_delta: float) -> bool:
	frame += 1
	if frame == 2:
		_run()
	if frame == 4:
		_finish()
	return false


func _same(card: Dictionary, hired: Dictionary, what: String) -> void:
	for k: String in ["name", "role", "specialty", "rarity"]:
		_check(str(card.get(k, "")) == str(hired.get(k, "")), "%s: card %s '%s' == hire '%s'" % [what, k, str(card.get(k, "")), str(hired.get(k, ""))])
	_check(str(card.get("specialty", "")) != "", what + ": the card names a specialty")


func _hire(saloon: Node, i: int, what: String) -> void:
	saloon.select(i)
	var card: Dictionary = (saloon.offer(i) as Dictionary).duplicate(true)
	var before := profile.crew.size()
	_check(saloon.hire_selected(), what + ": HIRE works")
	_check(profile.crew.size() == before + 1, what + ": one new crew member")
	_same(card, profile.crew.back(), what)
	profile.crew.pop_back()   # keep the roster open for the next card


func _run() -> void:
	profile.scrap = 100000
	profile.day = 2
	# Room for every hire, and a rehire waiting.
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var back := Crew.make("medic", "Rare", rng)
	back.id = 999
	profile.rehire_pool.append(back)
	garage = (load("res://scenes/garage.tscn") as PackedScene).instantiate() as Garage
	root.add_child(garage)
	garage.show_tab("SALOON")
	var saloon: Node = garage._saloon
	saloon.refresh()
	var paid: int = profile.saloon.size()
	# Free hires first (their roll depends on next_crew_id, so check each just before hiring).
	_hire(saloon, paid, "free Driver")
	_hire(saloon, paid + 1, "free Gunner")
	var n: int = saloon.offer_count()
	if saloon.is_rehire(n - 1):
		_hire(saloon, n - 1, "rehire")
	else:
		_check(false, "a rehire card is offered")
	for i in paid:
		_hire(saloon, i, "paid offer %d" % i)
	garage.queue_free()


func _check(ok: bool, what: String) -> void:
	print(("  PASS  " if ok else "  FAIL  ") + what)
	if not ok:
		failures.append(what)


func _finish() -> void:
	if failures.is_empty():
		print("SALOON MATCH TEST PASSED")
		quit(0)
	else:
		print("SALOON MATCH TEST FAILED: %s" % ", ".join(failures))
		quit(1)
