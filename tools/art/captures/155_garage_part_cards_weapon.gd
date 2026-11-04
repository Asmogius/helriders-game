extends "res://tools/art/capture_step.gd"
## V6.3b: a weapon slot: weapon cards (category icons) and the gun rows of the stat sheet.


func run(cap: SceneTree) -> void:
	cap.show_tab("GARAGE")
	cap.garage.open_slot(7)
