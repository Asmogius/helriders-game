extends "res://tools/art/capture_step.gd"
## The Quickplay hub (QP4): SANDBOX / ENDLESS / BACK.

var _node: Control


func run(cap: SceneTree) -> void:
	_node = (load("res://scenes/quickplay_hub.tscn") as PackedScene).instantiate()
	cap.root.add_child(_node)


func after(_cap: SceneTree) -> void:
	_node.queue_free()
