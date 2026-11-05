extends "res://tools/art/capture_step.gd"
## Playtest #11: unaffordable Comms upgrade disabled.


func run(cap: SceneTree) -> void:
	cap.profile.scrap = 60
	cap.show_tab("COMMS")
	cap.garage._comms._open_upgrades()
