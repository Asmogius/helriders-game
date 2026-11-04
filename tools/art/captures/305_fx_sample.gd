extends "res://tools/art/capture_step.gd"
## P2 V4 sample: an explosion and tracers in the running fight. Placed up and
## left of the rig, clear of the ability buttons and banner (301 fight_hud).


func run(cap: SceneTree) -> void:
	var m: Node = cap.current_scene
	var p: Vector2 = m.vehicle.global_position
	m.fx.explosion(p + Vector2(-200, -40), Vector2.ZERO)
	for i in 6:
		m.bullets.fire(p + Vector2(-30 - i * 22, -10), Vector2(-900, -60), 0.0, m.bullets.TEAM_PLAYER)
