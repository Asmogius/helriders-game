extends SceneTree
## Job-type unlocks (T.JOB_UNLOCK_CLEARS): early boards offer only simple
## types, the rest open by clear count, boards stay full, old saves with more
## clears get everything their count allows.
##
## Run:  godot --headless --fixed-fps 60 --path . -s res://tests/job_unlock_test.gd

const T := preload("res://scripts/tuning.gd")
const Missions := preload("res://scripts/missions.gd")
const ProfileScript := preload("res://scripts/profile.gd")

var failures: Array[String] = []

func _check(ok: bool, what: String) -> void:
	print(("  PASS  " if ok else "  FAIL  ") + what)
	if not ok:
		failures.append(what)

func _initialize() -> void:
	for type: String in Missions.TYPES:
		_check(T.JOB_UNLOCK_CLEARS.has(type), "%s has an unlock count" % type)
	_check(int(T.JOB_UNLOCK_CLEARS.clear) == 0 and int(T.JOB_UNLOCK_CLEARS.survive) == 0, "Clear and Survive open from the start")
	_check(Missions.unlocked_types(0) == ["clear", "survive"], "0 clears: Clear and Survive only")
	var last := 0
	for c in range(0, 12):
		var n := Missions.unlocked_types(c).size()
		_check(n >= last, "unlocks never go backwards (%d clears)" % c)
		last = n
	_check(Missions.unlocked_types(99).size() == Missions.TYPES.size(), "enough clears open every type")
	# Boards: only unlocked types, always the full count, every size.
	for c in range(0, 8):
		var open := Missions.unlocked_types(c)
		for day in range(1, 21):
			for count in [3, 4, 5, 6]:
				var board: Array = Missions.make_board(day, count, 0, "outer_blocks", c)
				var ok: bool = board.size() == count
				for m: Dictionary in board:
					ok = ok and open.has(str(m.type))
				if not ok:
					_check(false, "day %d, %d clears, %d jobs: full board of unlocked types" % [day, c, count])
	_check(true, "boards stay full and only offer unlocked types (8 clear counts x 20 days x 4 sizes)")
	var seen := {}
	for day in range(1, 41):
		for m: Dictionary in Missions.make_board(day, 3, 0, "outer_blocks", 1):
			seen[str(m.type)] = true
	_check(seen.has("courier") and not seen.has("hunt"), "1 clear: Courier appears, Hunt doesn't yet")
	# Profile: a new game is gated; an old save with many clears is not.
	var p: Node = ProfileScript.new()
	p.set("persist", false)
	p.new_game()
	var ok0 := true
	for m: Dictionary in p.board:
		ok0 = ok0 and Missions.unlocked_types(0).has(str(m.type))
	_check(ok0, "a new game's day-1 board is Clear / Survive only")
	p.record.clears = 10
	p.finish_day()
	var seen_p := {}
	for i in 30:
		for m: Dictionary in p.board:
			seen_p[str(m.type)] = true
		p.finish_day()
	_check(seen_p.size() > 2, "an old save with 10 clears gets the later types (%s)" % str(seen_p.keys()))
	p.free()
	print("JOB UNLOCK TEST PASSED" if failures.is_empty() else "JOB UNLOCK TEST FAILED")
	quit(0 if failures.is_empty() else 1)
