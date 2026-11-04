extends "res://tools/art/capture_step.gd"
## V6.3: status icons on the HUD strip.


func run(cap: SceneTree) -> void:
	var m: Node = cap.current_scene
	m.set_process(false)   # freeze the fight so the HUD keeps these values for the shot
	m.set_physics_process(false)
	m.hud.set_statuses(PackedFloat32Array([40, 100, 70, 0, 100, 25]), PackedFloat32Array([0, 3, 0, 0, 2, 0]))
