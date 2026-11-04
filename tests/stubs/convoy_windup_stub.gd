extends "res://scripts/convoy_rig.gd"
## Test stub: the wind-up interface the Convoy inherits from bulwark_rig.gd.

var stub_winding := false
var stub_progress := 0.0


func is_winding_up() -> bool:
	return stub_winding


func windup_progress() -> float:
	return stub_progress
