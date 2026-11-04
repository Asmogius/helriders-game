extends "res://tools/art/capture_step.gd"
## V6.4: mouse-and-keyboard mode, no touch sticks.


func run(cap: SceneTree) -> void:
	var pad: Node = cap.root.get_node_or_null("Pad")
	if pad != null:
		pad.set("kbm", true)
	cap.current_scene.hud._pad_badges()


## Back to touch mode so the shots after this one keep the sticks.
func after(cap: SceneTree) -> void:
	var pad: Node = cap.root.get_node_or_null("Pad")
	if pad != null:
		pad.set("kbm", false)
	cap.current_scene.hud._pad_badges()
