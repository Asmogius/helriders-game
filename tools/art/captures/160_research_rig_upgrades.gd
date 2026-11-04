extends "res://tools/art/capture_step.gd"
## P7: the Research screen's RIG UPGRADES view, with enough scrap for live BUY buttons.

var _scrap := 0


func run(cap: SceneTree) -> void:
	_scrap = cap.profile.scrap
	cap.profile.scrap = 420
	cap.show_tab("RESEARCH")
	cap.garage._research.refresh()
	cap.garage._research.show_rig_upgrades(true)


func after(cap: SceneTree) -> void:
	cap.profile.scrap = _scrap   # later shots see the starting scrap again
	cap.garage._research.show_rig_upgrades(false)
