extends "res://tools/art/capture_step.gd"
## Playtest #10: no touch stick / CREW / LOCK on mouse-and-keyboard.


func run(cap: SceneTree) -> void:
	var pad: Node = cap.root.get_node_or_null("Pad")
	if pad != null:
		pad.set("kbm", true)
	if cap.current_scene != null and cap.current_scene.get("hud"):
		cap.current_scene.hud._pad_badges()


func after(cap: SceneTree) -> void:
	var pad: Node = cap.root.get_node_or_null("Pad")
	if pad != null:
		pad.set("kbm", false)
	if cap.current_scene != null and cap.current_scene.get("hud"):
		cap.current_scene.hud._pad_badges()
