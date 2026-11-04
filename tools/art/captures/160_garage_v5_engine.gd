extends "res://tools/art/capture_step.gd"
## #37 v5 HD workshop: ENGINE card open, engine_mount layer lit, callout on.


func run(cap: SceneTree) -> void:
	cap.show_tab("GARAGE")
	cap.garage.open_slot(1)


func wait() -> int:
	return 30   # let the callout fade in
