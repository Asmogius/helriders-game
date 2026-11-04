extends "res://tools/art/capture_step.gd"
## #37 v5 HD workshop: WEAPON 1 card open, turret lit, rest of the rig dimmed.


func run(cap: SceneTree) -> void:
	cap.show_tab("GARAGE")
	cap.garage.open_slot(6)


func wait() -> int:
	return 30
