extends "res://tools/art/capture_step.gd"
## V6.1: every HUD button at once (longest labels), to check nothing is squeezed.


func run(cap: SceneTree) -> void:
	var hud: Node = cap.current_scene.hud
	hud.set_lock_available(true)
	var kinds: Array[String] = ["overcharge", "hard_line", "spikes"]
	hud.set_abilities(kinds)
	hud.banner("SCHEMATIC: OUTRIDER SPORT WHEELS", T.COL_ORANGE, 3.0)
