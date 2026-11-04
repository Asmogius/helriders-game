extends "res://tools/art/capture_step.gd"
## P2 V4 sample: an explosion and tracers in the running fight.


func run(cap: SceneTree) -> void:
	var m: Node = cap.current_scene
	var p: Vector2 = m.vehicle.global_position
	m.fx.explosion(p + Vector2(140, -50), Vector2.ZERO)
	for i in 6:
		m.bullets.fire(p + Vector2(30 + i * 22, -10), Vector2(900, -120), 0.0, m.bullets.TEAM_PLAYER)
