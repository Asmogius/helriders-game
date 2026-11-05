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
## Baked cast shadow (meta "shadow", from voxel_render.py): a child drawn behind
## this sprite at the same frame. Null when the sheet has none.
var shadow: Sprite2D = null
## Emissive pixels of the sheet (meta "lights"): a child drawn over this sprite.
## The night grade sets this sprite's self_modulate only, so lights stay bright.
## Null when the sheet has none. Hide it for a burnt-out wreck.
var lights: Sprite2D = null


func _init() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST


func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	if meta_path != "":
		load_meta(meta_path)
	_pick()


## Reads the sheet's .json and loads the composite sheet beside it.
## Parsed sheet json, shared and read-only, keyed by path. Kept on Engine
## metadata (plain data) instead of a static var: a static var on this
## class_name script kept the script alive at exit (leak warning).
const META_CACHE := &"directional_sprite_meta_cache"
static func read_meta(path: String) -> Variant:
	if not Engine.has_meta(META_CACHE):
		Engine.set_meta(META_CACHE, {})
	var cache: Dictionary = Engine.get_meta(META_CACHE)
	if cache.has(path):
		return cache[path]
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return null
	var d: Variant = JSON.parse_string(f.get_as_text())
	cache[path] = d
	return d


func load_meta(path: String) -> bool:
	var d: Variant = read_meta(path)
	if d is Dictionary:
		d = (d as Dictionary).duplicate(true)
	if not d is Dictionary:
		return false
	meta = d
	directions = int(meta.directions)
	columns = int(meta.columns)
	texture = load(path.get_base_dir().path_join(String(meta.sheet)))
	_load_shadow(path.get_base_dir())
	_load_lights(path.get_base_dir())
	_apply_grid()
	_pick()
	return true


func _load_lights(dir: String) -> void:
	var ld: Dictionary = meta.get("lights", {})
	var p := dir.path_join(String(ld.get("sheet", "")))
	if ld.is_empty() or not ResourceLoader.exists(p):
		if lights != null:
			lights.queue_free()
			lights = null
		return
	if lights == null:
		lights = Sprite2D.new()
		lights.name = "Lights"
		lights.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		add_child(lights)
	lights.texture = load(p)
	lights.hframes = columns
	lights.vframes = int(ceil(directions / float(columns)))


func _load_shadow(dir: String) -> void:
	var sd: Dictionary = meta.get("shadow", {})
	var p := dir.path_join(String(sd.get("sheet", "")))
	if sd.is_empty() or not ResourceLoader.exists(p):
		if shadow != null:
			shadow.queue_free()
			shadow = null
		return
	if shadow == null:
		shadow = Sprite2D.new()
		shadow.name = "Shadow"
		shadow.show_behind_parent = true
		shadow.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		add_child(shadow)
	shadow.texture = load(p)
	shadow.hframes = columns
	shadow.vframes = int(ceil(directions / float(columns)))
	var al: float = sd.get("alpha", 0.82)  # voxel_render.SHADOW_ALPHA; contact peak
	shadow.modulate = Color(1.0, 1.0, 1.0, al)


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
	return Vector2(float(o[0]), float(o[1])) / ppv()


## Sheet pixels per voxel: 1 in game, 2 for the garage HD sheets. Offsets come
## back in voxel-pixels and the sprite scale divides by it, so both match.
func ppv() -> float:
	return float(meta.get("px_per_voxel", 1))


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
	if shadow != null:
		shadow.frame = frame
	if lights != null:
		lights.frame = frame
