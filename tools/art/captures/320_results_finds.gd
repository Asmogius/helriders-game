extends "res://tools/art/capture_step.gd"
## The results panel with three new schematics found.


func run(cap: SceneTree) -> void:
	var hud: Node = cap.current_scene.hud
	hud.show_result("JOB DONE", "Job pay +120    Kill scrap +45    Time 3:12", "RETURN TO GARAGE", T.COL_ORANGE)
	hud.show_finds([["New schematic: Courier Frame", "Uncommon"], ["New schematic: Bulwark Frame", "Rare"], ["New schematic: Hauler Frame", "Epic"]])


func wait() -> int:
	return 70
