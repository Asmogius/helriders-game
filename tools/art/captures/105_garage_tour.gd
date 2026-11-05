extends "res://tools/art/capture_step.gd"
## Playtest #2/#8: garage tour card above the footer, clear of ARMOR FRONT,
## naming weight / overload on the fit step.


func run(cap: SceneTree) -> void:
	cap.profile.begin_tour()
	cap.show_tab("GARAGE")
	if cap.garage.tour == null:
		cap.garage.start_tour()


func after(cap: SceneTree) -> void:
	if cap.garage != null and cap.garage.tour != null:
		cap.garage.tour.finish()
