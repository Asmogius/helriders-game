extends "res://scripts/gunner_rig.gd"
## Sludger (content proposal 01, approved 2026-11-03): acid / goop artillery.
## It parks 500-800 px off and lobs shells from a turret (like your Mortar),
## alternating acid shells (damage + an acid puddle) and goop shells (fill
## GOOPED, so the horde comes for you). It backs off if you close inside
## 300 px and never rams on purpose. The landing circle shows where it hits.

var shells_thrown := 0     # tests


func _init() -> void:
	team = BulletPool.TEAM_ENEMY
	apply_stats(T.SLUDGER)
	body_len = 72.0
	body_wid = 40.0
	lock_priority = 3
	lock_radius = 44.0
	self_defense = false


## A thicker shield at 6 skulls.
func arm_for_skulls(skulls: int) -> void:
	super(skulls)
	if skulls >= 6 and shield_max > 0.0:
		shield_max = T.SLUDGER_SHIELD_6
		shield = shield_max


func _steer(_delta: float, engaging: bool, to_player: Vector2, forward: Vector2) -> Vector2:
	if mode == Mode.UNSTICK:
		if _mode_time <= 0.0:
			mode = Mode.ATTACK
		return -forward.rotated(_side * 0.6)
	var dist := to_player.length()
	if not engaging:
		return Vector2.ZERO
	if dist < T.SLUDGER_FLEE:
		return (-to_player.normalized()).rotated(_circle_side * 0.3)
	if dist < T.SLUDGER_RANGE_MIN:
		return (-to_player.normalized()).rotated(_circle_side * 0.6) * 0.7
	if dist > T.SLUDGER_RANGE_MAX:
		return to_player.normalized().rotated(_circle_side * 0.3) * 0.8
	return to_player.normalized().rotated(_circle_side * PI * 0.5) * 0.35


## Lobber aim: the stick's direction is the bearing, its push the distance.
func _aim(_delta: float, engaging: bool, dist: float) -> void:
	shooting_at = null
	fire_trigger = false
	var w: Dictionary = gun_stats[0] if not gun_stats.is_empty() else {}
	var min_r := float(w.get("min_range", 300.0))
	var max_r := float(w.get("max_range", 900.0))
	if not engaging or bool(player.get("is_wrecked")) or dist < min_r or dist > max_r:
		aim_input = Vector2.ZERO
		return
	shooting_at = player
	var flight := float(w.get("flight", 1.1))
	var vel: Vector2 = player.get("velocity")
	var aim_at := player.global_position + vel * flight * 0.6
	var to := aim_at - global_position
	var push := clampf(inverse_lerp(min_r, max_r, to.length()), 0.0, 1.0)
	aim_input = to.normalized() * lerpf(AIM_DEADZONE + 0.001, 1.0, push)


func _lob(w: Dictionary, from: Vector2, landing: Vector2, flight: float) -> bool:
	var ok := super(w, from, landing, flight)
	if ok:
		shells_thrown += 1
		var music := get_node_or_null("/root/MusicManager")
		if music != null:
			music.play_sfx("acid_fire")
	return ok


## Art id (PR #15 looks up res://art/sprites/<id>.json). Until #15 lands the
## base rig never calls this and the rig keeps its code-drawn look.
func art_id() -> String:
	return "sludger"
