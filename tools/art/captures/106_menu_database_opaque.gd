extends "res://tools/art/capture_step.gd"
## Playtest #13: Database panel is opaque charcoal.


func run(cap: SceneTree) -> void:
	cap.show_tab("GARAGE")
	var g: Node = cap.garage
	var m: Node = g.open_menu()
	m.show_page("database")
	m.show_category("enemies")
