class_name DirectionalSprite
extends Sprite2D
## Shows the pre-rendered voxel frame closest to a heading. The sprite itself
## never rotates (the camera is tilted, so rotating a flat sprite would look
## wrong); set `heading` (radians, Godot convention: 0 = +x, clockwise) each
## frame, e.g. from the rig's `rotation`, and keep this node's global
## rotation at 0 (top_level or counter-rotate).
## Sheets come from tools/art/voxel_render.py: `directions` frames, laid out
## in `hframes` columns, frame i = heading i * TAU / directions.

@export var directions := 16
@export var heading := 0.0:
	set(v):
		heading = v
		_pick()


func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	if hframes <= 1:
		hframes = 4
		vframes = int(ceil(directions / 4.0))
	_pick()


func _pick() -> void:
	var step := TAU / float(directions)
	frame = posmod(int(round(heading / step)), directions)
