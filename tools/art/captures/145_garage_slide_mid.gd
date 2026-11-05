extends "res://tools/art/capture_step.gd"
## V6.5: Saloon cards caught mid slide-in.


func run(cap: SceneTree) -> void:
	cap.show_tab("SALOON")


func wait() -> int:
	return 6
