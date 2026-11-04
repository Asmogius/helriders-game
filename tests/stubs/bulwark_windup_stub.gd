extends "res://scripts/bulwark_rig.gd"
## Test stub: the real rig, with its wind-up state set by the test (the
## signal comes from bulwark_rig.gd).

var stub_winding := false
var stub_progress := 0.0


func is_winding_up() -> bool:
	return stub_winding


func windup_progress() -> float:
	return stub_progress
