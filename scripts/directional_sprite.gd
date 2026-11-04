class_name DirectionalSprite
extends Sprite2D
## Shows the pre-rendered voxel frame closest to a heading. The sprite never
## rotates (the camera is tilted, so a rotated flat sprite would look wrong):
## set `heading` (radians, Godot convention: 0 = +x, clockwise) every frame,
## e.g. from the rig's `rotation`, and keep this node's global rotation at 0.
## Sheets and their .json come from tools/art/voxel_render.py: `directions`
## frames in `columns` columns, frame i = heading i * TAU / directions.
## Each wreck chunk has its own aligned sheet plus per-frame pixel offsets.

@export_file("*.json") var meta_path := ""
@export var directions := 32
@export var columns := 8
@export var heading := 0.0:
	set(v):
		heading = v
		_pick()

var meta: Dictionary = {}


func _init() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST


func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	if meta_path != "":
		load_meta(meta_path)
	_pick()


## Reads the sheet's .json and loads the composite sheet beside it.
func load_meta(path: String) -> bool:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return false
	var d: Variant = JSON.parse_string(f.get_as_text())
	if not d is Dictionary:
		return false
	meta = d
	directions = int(meta.directions)
	columns = int(meta.columns)
	texture = load(path.get_base_dir().path_join(String(meta.sheet)))
	_apply_grid()
	_pick()
	return true


static func frame_for(h: float, dirs: int) -> int:
	return posmod(int(round(h / (TAU / float(dirs)))), dirs)


## Pixel offset of a wreck chunk's centre from the sprite centre at the
## current frame (spawn the chunk there and fling it outward along it).
func chunk_offset(chunk: String) -> Vector2:
	var o: Array = meta.chunks[chunk].offsets[frame]
	return Vector2(float(o[0]), float(o[1]))


## Pixel offset of a named model point (e.g. "turret_mount", "pivot") from
## the sprite centre at frame `at` (default: the current frame).
func point_offset(point: String, at := -1) -> Vector2:
	if not meta.has("points") or not meta.points.has(point):
		return Vector2.ZERO
	var o: Array = meta.points[point][frame if at < 0 else at]
	return Vector2(float(o[0]), float(o[1]))


## Texture of a wreck chunk's sheet (same frame layout as the composite).
func chunk_texture(chunk: String) -> Texture2D:
	return load(meta_path.get_base_dir().path_join(String(meta.chunks[chunk].sheet)))


func _apply_grid() -> void:
	hframes = columns
	vframes = int(ceil(directions / float(columns)))


func _pick() -> void:
	if hframes != columns:
		_apply_grid()
	frame = frame_for(heading, directions)
