extends "res://tools/art/capture_step.gd"
## Playtest #3: overload part card shows CONFIRM OVERLOAD (not green FIT).


func run(cap: SceneTree) -> void:
	cap.show_tab("GARAGE")
	# Starter is already at 100/100 power; preview Targeting Computer on INTERNAL 2.
	var g: Node = cap.garage
	g.open_slot(9)   # INTERNAL 2
	g.press_card("targeting_computer")
