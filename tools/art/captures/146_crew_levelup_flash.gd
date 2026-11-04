extends "res://tools/art/capture_step.gd"
## V6.5: the Inn right after a crew member levels up: their card flashes.
## Uses the throwaway capture profile, so the XP never reaches a save.

const Crew := preload("res://scripts/crew.gd")


func run(cap: SceneTree) -> void:
	var m: Dictionary = cap.profile.crew[0]
	m.xp = float(Crew.xp_for_level(Crew.level(m) + 1))
	cap.show_tab("INN")   # rebuilds the crew cards; the levelled one flashes


func wait() -> int:
	return 6   # inside the first bright pulse
