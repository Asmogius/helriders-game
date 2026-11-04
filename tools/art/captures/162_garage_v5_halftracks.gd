extends "res://tools/art/capture_step.gd"
## #37 v5 HD workshop: Half-Track fitted (throwaway profile), DRIVE card open.
## after() restores the rig, scrap, storage and schematics, so later shots
## (the fight) see the stock rig.

var _saved := {}


func run(cap: SceneTree) -> void:
	var p: Node = cap.profile
	for k: String in ["rig", "scrap", "storage", "schematics"]:
		var v: Variant = p.get(k)
		_saved[k] = v.duplicate(true) if v is Dictionary or v is Array else v
	if not p.schematics.has("half_track"):
		p.schematics.append("half_track")
	p.scrap += 1000
	p.apply_loadout(p.with_part(p.rig, "drive", 0, "half_track"))
	cap.show_tab("GARAGE")
	cap.garage.open_slot(2)


func wait() -> int:
	return 30


func after(cap: SceneTree) -> void:
	for k: String in _saved:
		cap.profile.set(k, _saved[k])
