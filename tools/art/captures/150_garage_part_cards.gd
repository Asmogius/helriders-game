extends "res://tools/art/capture_step.gd"
## Chassis slot picker: Common, Uncommon, Rare and Epic part cards.


func run(cap: SceneTree) -> void:
	cap.show_tab("GARAGE")
	cap.garage.open_slot(0)
