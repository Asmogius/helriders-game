extends "res://tools/art/capture_step.gd"
## CONTROLLER BUTTONS: all fight actions rebindable.


func run(cap: SceneTree) -> void:
	cap.show_tab("GARAGE")
	var m: Node = cap.garage.open_menu()
	m.show_page("controller")
