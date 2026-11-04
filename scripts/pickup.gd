extends Node2D
## A salvage crate on the ground holding one part. Drive over it to collect.

const T := preload("res://scripts/tuning.gd")
const Parts := preload("res://scripts/parts.gd")
const UI := preload("res://scripts/ui_theme.gd")
const COLLECT_RADIUS := 60.0

var part: Dictionary = {}       # a schematic, or empty for a scrap cache
var scrap_value := 0
var _t := 0.0


func _ready() -> void:
	z_index = 1


func _process(delta: float) -> void:
	_t += delta
	queue_redraw()


func _draw() -> void:
	if part.is_empty():
		_draw_cache()
		return
	var glow := UI.rarity_color(str(part.get("rarity", "")))
	var pulse := 0.5 + 0.5 * sin(_t * 5.0)
	_draw_beam(glow, pulse)
	draw_circle(Vector2.ZERO, 30.0 + pulse * 6.0, Color(glow, 0.12 + pulse * 0.1))
	draw_arc(Vector2.ZERO, 30.0 + pulse * 6.0, 0.0, TAU, 32, Color(glow, 0.7), 2.0)
	draw_rect(Rect2(-14.0, -14.0, 28.0, 28.0), Color(0.36, 0.3, 0.2))
	draw_rect(Rect2(-14.0, -3.0, 28.0, 6.0), T.COL_RUST)
	draw_rect(Rect2(-3.0, -14.0, 6.0, 28.0), T.COL_RUST)
	draw_rect(Rect2(-14.0, -14.0, 28.0, 28.0), glow, false, 2.0)
	var font := ThemeDB.fallback_font
	draw_string(font, Vector2(-50.0, -42.0), "SCHEMATIC", HORIZONTAL_ALIGNMENT_CENTER, 100.0, 16, Color(glow, 0.9))


## V1.3: a light beam whose height grows with rarity (Legendary is visible
## across the map). One polygon, drawn in this crate's own _draw.
func _draw_beam(glow: Color, pulse: float) -> void:
	var tier := UI.rarity_tier(str(part.get("rarity", "")))
	if tier <= 1:
		return
	var h: float = T.RARITY_BEAM[mini(tier, T.RARITY_BEAM.size()) - 1]
	var w := 8.0 + tier * 2.0
	var base := Color(glow, 0.35 + 0.15 * pulse)
	var top := Color(glow, 0.0)
	draw_polygon(PackedVector2Array([Vector2(-w, 0), Vector2(w, 0), Vector2(w * 0.4, -h), Vector2(-w * 0.4, -h)]),
		PackedColorArray([base, base, top, top]))


func _draw_cache() -> void:
	var pulse := 0.5 + 0.5 * sin(_t * 5.0)
	draw_circle(Vector2.ZERO, 26.0 + pulse * 4.0, Color(T.COL_ORANGE, 0.1 + pulse * 0.08))
	for i in 5:
		var p := Vector2(-14.0 + (i % 3) * 10.0, -8.0 + floorf(i / 3.0) * 10.0)
		draw_rect(Rect2(p, Vector2(9.0, 9.0)), T.COL_RUST.lightened(0.1 * (i % 2)))
	var font := ThemeDB.fallback_font
	draw_string(font, Vector2(-50.0, -36.0), "SCRAP", HORIZONTAL_ALIGNMENT_CENTER, 100.0, 16, Color(T.COL_ORANGE, 0.9))
