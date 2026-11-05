extends "res://tools/art/capture_step.gd"
## Playtest #12: job-taken toast above the footer.


func run(cap: SceneTree) -> void:
	cap.show_tab("COMMS")
	var g: Node = cap.garage
	g._comms.select(0)
	g._comms.take_selected()
