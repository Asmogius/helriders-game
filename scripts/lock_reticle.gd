extends Node2D
## Corner brackets around whatever the player's rig has locked onto.

const T := preload("res://scripts/tuning.gd")

var rig: Node2D   # the player's rig (has lock_target)
var _t := 0.0


func _ready() -> void:
	z_index = 6


func _process(delta: float) -> void:
	_t += delta
	var target: Node2D = rig.get("lock_target") if rig != null else null
	var was_visible := visible
	visible = target != null and is_instance_valid(target)
	if visible:
		global_position = target.global_position
		var r: float = target.get("lock_radius")
		scale = Vector2.ONE * (r / 20.0)
		queue_redraw()
	elif was_visible:
		queue_redraw()


func _draw() -> void:
	var size := 20.0 + 3.0 * sin(_t * 8.0)
	var arm := 8.0
	var color := T.COL_ORANGE
	for corner: Vector2 in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
		var c := corner * size
		draw_line(c, c - Vector2(corner.x * arm, 0.0), color, 2.5)
		draw_line(c, c - Vector2(0.0, corner.y * arm), color, 2.5)
	draw_rect(Rect2(-1.5, -1.5, 3.0, 3.0), color)
