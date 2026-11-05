extends "res://tools/art/capture_step.gd"
## The title screen (QP4): CAMPAIGN / QUICKPLAY / QUIT.

var _node: Control


func run(cap: SceneTree) -> void:
	_node = (load("res://scenes/title.tscn") as PackedScene).instantiate()
	_node.set("auto_resume", false)
	cap.root.add_child(_node)


func after(_cap: SceneTree) -> void:
	_node.queue_free()
