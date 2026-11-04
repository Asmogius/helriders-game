extends "res://tools/art/capture_step.gd"
## One schematic crate per rarity in a row ahead of the rig (beams by tier).


func run(cap: SceneTree) -> void:
	var m: Node = cap.current_scene
	var Pickup: GDScript = load("res://scripts/pickup.gd")
	var at: Vector2 = m.vehicle.global_position + Vector2(-250, 150)
	for i in T.RARITY_ORDER.size():
		var p: Node2D = Pickup.new()
		p.part = {"name": T.RARITY_ORDER[i], "rarity": T.RARITY_ORDER[i], "category": "Weapon"}
		p.position = at + Vector2(i * 100, 0)
		m.pickups.add_child(p)
	m.hud.banner("SCHEMATIC: HAULER FRAME", UI.rarity_color("Epic"), 3.0)
