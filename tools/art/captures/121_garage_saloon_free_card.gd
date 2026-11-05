extends "res://tools/art/capture_step.gd"
## The SALOON with the free Driver card picked: the card must name the person
## HIRE adds (name, class, specialty), playtest 18.png.


func run(cap: SceneTree) -> void:
	cap.show_tab("SALOON")
	var saloon: Node = cap.garage._saloon
	saloon.select(cap.profile.saloon.size())
