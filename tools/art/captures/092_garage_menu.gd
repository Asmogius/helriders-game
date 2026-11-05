extends "res://tools/art/capture_step.gd"
## The garage MENU (QP4) with BACK TO TITLE.


func run(cap: SceneTree) -> void:
	cap.show_tab("GARAGE")
	cap.garage.open_menu()


func after(cap: SceneTree) -> void:
	if cap.garage.menu != null:
		cap.garage.menu.close()
