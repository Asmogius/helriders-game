extends "res://tools/art/capture_step.gd"
## V6.5: results card numbers counting up.


func run(cap: SceneTree) -> void:
	cap.current_scene.hud.show_result("JOB DONE", "Job pay +120    Kill scrap +45    Time 3:12", "RETURN TO GARAGE", T.COL_ORANGE)


func wait() -> int:
	return 18
