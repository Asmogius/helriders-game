extends "res://tools/art/capture_step.gd"
## Playtest #9: KEYBOARD & MOUSE settings page.


func run(cap: SceneTree) -> void:
	cap.show_tab("GARAGE")
	var m: Node = cap.garage.open_menu()
	m.show_page("kbm")
