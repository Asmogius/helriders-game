extends "res://tools/art/capture_step.gd"
## Playtest #7: fresh save points at the Tutorial.


func run(cap: SceneTree) -> void:
	cap.profile.new_game()
	cap.show_tab("GARAGE")
