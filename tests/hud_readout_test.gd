extends SceneTree
## Playtest 2 #12: the HUD's big number read "100" while the gauge beside it
## had halved. The number showed HP and the gauge showed armor. Both now show
## the rig's durability (armor + HP), and the number must always match the
## gauge: through the mission's own HUD refresh, as armor drains and then HP,
## when it heals back up, and it never reads 0 while the rig is still alive.
##
## Run:  godot --headless --fixed-fps 60 --path . -s res://tests/hud_readout_test.gd

const Mission := preload("res://scripts/mission.gd")
const Missions := preload("res://scripts/missions.gd")

const WAIT := 10   # frames for the mission's 15 Hz HUD refresh to land

var main: Mission
var frame := 0
var step := 0
var failures: Array[String] = []
# [armor share, HP share, what]
var cases := [
	[1.0, 1.0, "full"],
	[0.5, 1.0, "armor half gone (the playtest case)"],
	[0.0, 1.0, "armor gone, HP full"],
	[0.0, 0.37, "armor gone, HP draining"],
	[0.0, 0.001, "a sliver of HP left"],
	[0.8, 0.6, "patched back up"],
	[1.0, 1.0, "full again"],
]


func _initialize() -> void:
	seed(20261105)
	var profile: Node = root.get_node("Profile")
	profile.set("persist", false)
	profile.call("new_game")
	main = (load("res://scenes/mission.tscn") as PackedScene).instantiate() as Mission
	main.mission_override = Missions.make("courier", 2, 7)
	main.auto_spawn_specials = false
	main.push_override = 0
	root.add_child(main)


func _process(_delta: float) -> bool:
	frame += 1
	if step >= cases.size():
		_finish()
		return false
	var rig := main.vehicle
	var c: Array = cases[step]
	if frame == 5:
		main.zombies.clear_all()
		main.zombies.spawn_budget = 0
		rig.armor = rig.armor_max * float(c[0])
		rig.hp = rig.hp_max * float(c[1])
	if frame == 5 + WAIT:
		var r: Dictionary = main.hud.durability_readout()
		var want := (rig.armor + rig.hp) / (rig.armor_max + rig.hp_max)
		var shown := int(r.number)
		var bar := float(r.bar)
		print("  %s: bar %.3f, number %d" % [c[2], bar, shown])
		_check(absf(bar - want) < 0.01, "%s: the gauge shows armor + HP (%.3f, want %.3f)" % [c[2], bar, want])
		_check(shown == maxi(roundi(bar * 100.0), 1 if bar > 0.0 else 0), "%s: the number matches the gauge (%d vs %.1f%%)" % [c[2], shown, bar * 100.0])
		_check(bar <= 0.0 or shown >= 1, "%s: a live rig never reads 0" % c[2])
		frame = 0
		step += 1
	return false


func _finish() -> void:
	if failures.is_empty():
		print("HUD READOUT TEST PASSED")
		quit(0)
	else:
		for f in failures:
			print("TEST FAILED: " + f)
		quit(1)


func _check(ok: bool, what: String) -> void:
	print(("  PASS  " if ok else "  FAIL  ") + what)
	if not ok:
		failures.append(what)
