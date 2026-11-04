extends "res://tools/art/capture_step.gd"
## V6.4: armor gauge + shield rail, button plates, textured sticks.


func run(cap: SceneTree) -> void:
	var m: Node = cap.current_scene
	m.set_process(false)   # hold these HUD values for the shot
	m.set_physics_process(false)
	m.hud.set_lock_available(true)
	var kinds: Array[String] = ["overcharge", "mines"]
	m.hud.set_abilities(kinds)
	m.hud.set_armor(0.62)
	m.hud.set_defense(0.4, PackedFloat32Array([0.8, 0.5, 0.6, 0.3]), 0.9)
