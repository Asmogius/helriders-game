extends RefCounted
## Quickplay QP5: Sandbox unlock-all at runtime. Sets Profile.persist = false
## and grants every schematic / max research level in memory. Never calls
## save_game(). Pair with begin()/end() so the campaign file is untouched.

const Parts := preload("res://scripts/parts.gd")
const Crew := preload("res://scripts/crew.gd")
const ProfileScript := preload("res://scripts/profile.gd")


## Snapshot campaign state, disable disk writes, unlock everything in memory.
## Returns the snapshot for end().
static func begin(profile: ProfileScript) -> Dictionary:
	# Deep copy: save_data() aliases live arrays (schematics/crew).
	var snap: Dictionary = profile.save_data().duplicate(true)
	profile.persist = false
	_unlock(profile)
	return snap


## Restore the snapshot and re-enable disk writes when persist_again is true.
static func end(profile: ProfileScript, snapshot: Dictionary, persist_again := true) -> void:
	if not snapshot.is_empty():
		profile.apply_data(snapshot)
	profile.persist = persist_again


static func _unlock(profile: ProfileScript) -> void:
	profile.schematics.clear()
	profile.levels = {}
	for id: String in Parts.CATALOG:
		profile.schematics.append(id)
		var part: Dictionary = Parts.get_part(id)
		var cap := maxi(Parts.max_level(part), 1)
		if cap > 1:
			profile.levels[id] = cap
	# Crew at a high level via XP (no Saloon grind in Sandbox).
	for m: Dictionary in profile.crew:
		var want := Crew.max_level(m)
		m.xp = float(Crew.xp_for_level(want))
		m.rest = 0
	if profile.crew.is_empty():
		var dice := RandomNumberGenerator.new()
		dice.seed = 11
		for pair: Array in [["driver", "wheelman"], ["gunner", "gunslinger"]]:
			var m: Dictionary = Crew.make(str(pair[0]), "Common", dice, str(pair[1]))
			m.id = int(profile.next_crew_id)
			profile.next_crew_id = int(profile.next_crew_id) + 1
			m.seated = true
			m.rest = 0
			m.xp = float(Crew.xp_for_level(Crew.max_level(m)))
			profile.crew.append(m)
