extends Node2D
## A salvage crate on the ground holding one part. Drive over it to collect.

const T := preload("res://scripts/tuning.gd")
const Parts := preload("res://scripts/parts.gd")
const COLLECT_RADIUS := 60.0

var part: Dictionary = {}
var _t := 0.0


func _ready() -> void:
	z_index = 1


func _process(delta: float) -> void:
	_t += delta
	queue_redraw()


func _draw() -> void:
	var glow := Parts.color_of(part)
	var pulse := 0.5 + 0.5 * sin(_t * 5.0)
	draw_circle(Vector2.ZERO, 30.0 + pulse * 6.0, Color(glow, 0.12 + pulse * 0.1))
	draw_arc(Vector2.ZERO, 30.0 + pulse * 6.0, 0.0, TAU, 32, Color(glow, 0.7), 2.0)
	draw_rect(Rect2(-14.0, -14.0, 28.0, 28.0), Color(0.36, 0.3, 0.2))
	draw_rect(Rect2(-14.0, -3.0, 28.0, 6.0), T.COL_RUST)
	draw_rect(Rect2(-3.0, -14.0, 6.0, 28.0), T.COL_RUST)
	draw_rect(Rect2(-14.0, -14.0, 28.0, 28.0), glow, false, 2.0)
	var font := ThemeDB.fallback_font
	draw_string(font, Vector2(-40.0, -42.0), "SALVAGE", HORIZONTAL_ALIGNMENT_CENTER, 80.0, 16, Color(glow, 0.9))
