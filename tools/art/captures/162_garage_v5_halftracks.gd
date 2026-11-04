extends "res://tools/art/capture_step.gd"
## #37 v5 HD workshop: Half-Track fitted (throwaway profile), DRIVE card open.

var _was: Variant


func run(cap: SceneTree) -> void:
	var p: Node = cap.profile
	_was = p.rig
	if not p.schematics.has("half_track"):
		p.schematics.append("half_track")
	p.apply_loadout(p.with_part(p.rig, "drive", 0, "half_track"))
	cap.show_tab("GARAGE")
	cap.garage.open_slot(2)


func wait() -> int:
	return 30


func after(cap: SceneTree) -> void:
	cap.profile.apply_loadout(_was)   # later shots see the stock rig
