extends "res://tools/art/capture_step.gd"
## The mission scene after a few seconds.


func run(cap: SceneTree) -> void:
	if cap.strip != null:
		cap.strip.queue_free()
		cap.strip = null
	cap.change_scene_to_file("res://scenes/mission.tscn")


func wait() -> int:
	return 150
