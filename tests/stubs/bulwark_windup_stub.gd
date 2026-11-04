extends "res://scripts/bulwark_rig.gd"
## Test stub: the wind-up interface Content's bulwark_rig.gd will provide.

signal windup_started

var stub_winding := false
var stub_progress := 0.0


func is_winding_up() -> bool:
	return stub_winding


func windup_progress() -> float:
	return stub_progress
