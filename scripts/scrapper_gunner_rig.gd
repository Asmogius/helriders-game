extends "res://scripts/scrapper_rig.gd"
## Scrapper Gunner: the original Scrapper, kept as a slightly harder variant
## (agreed with the owner). Tougher than the unarmed Scrapper, with a weak
## turret that plinks at you, and every 4 s it lays a mine, oil or a spike
## strip in turn. From 4 skulls it replaces the Scrapper in half the jobs.


## Voxel art: art/sprites/scrapper_gunner.json (see docs/ART_PIPELINE.md).
func art_id() -> String:
	return "scrapper_gunner"


func _init() -> void:
	team = BulletPool.TEAM_ENEMY
	apply_stats(T.SCRAPPER_GUNNER)
	body_len = 64.0
	body_wid = 34.0
	lock_priority = 3
	lock_radius = 42.0
	self_defense = false
	cycle = ["mine", "oil", "spikes"]
	next_trap = "mine"
	trap_every = T.SCRAPPER_GUNNER_TRAP_EVERY
	_trap_timer = trap_every * 0.5


func _draw() -> void:
	if _hull_art != null:
		return   # the voxel sheet draws the rig
	super()
	if is_wrecked:
		return
	# Bolted-on side plates mark the tougher variant.
	var half_l := body_len * 0.5
	var half_w := body_wid * 0.5
	draw_rect(Rect2(-half_l + 22.0, -half_w - 1.0, 22.0, 4.0), T.COL_STEEL)
	draw_rect(Rect2(-half_l + 22.0, half_w - 3.0, 22.0, 4.0), T.COL_STEEL)
