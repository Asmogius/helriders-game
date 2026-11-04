extends RefCounted
## Loads a generated atlas: `res://art/<area>/<name>.png` plus `<name>.json`
## ({"regions": {"id": [x, y, w, h], ...}}). Used by the effects, zombie and
## map packages to draw regions from one texture in a single drawer.
## Missing or broken files give an empty atlas (`ok()` false) so callers keep
## their code-drawn fallback (VISUAL_PLAN rule: fallback stays).

var texture: Texture2D
var regions := {}

static var _cache := {}


## Cached per path (without extension), e.g. load_atlas("res://art/fx/fx").
static func load_atlas(base: String) -> RefCounted:
	if _cache.has(base):
		return _cache[base]
	var a := new()
	a._load(base)
	_cache[base] = a
	return a


func _load(base: String) -> void:
	if not ResourceLoader.exists(base + ".png") or not FileAccess.file_exists(base + ".json"):
		return
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(base + ".json"))
	if typeof(data) != TYPE_DICTIONARY or typeof(data.get("regions")) != TYPE_DICTIONARY:
		return
	texture = load(base + ".png")
	for id: String in data.regions:
		var v: Variant = data.regions[id]
		if typeof(v) == TYPE_ARRAY and v.size() == 4:
			regions[id] = Rect2(float(v[0]), float(v[1]), float(v[2]), float(v[3]))


func ok() -> bool:
	return texture != null and not regions.is_empty()


func has(id: String) -> bool:
	return regions.has(id)


func region(id: String) -> Rect2:
	return regions.get(id, Rect2())


## Draws region `id` into `dest` on `canvas`. Returns false (draws nothing)
## when the region is missing, so the caller can draw its fallback.
func draw(canvas: CanvasItem, id: String, dest: Rect2, modulate := Color.WHITE) -> bool:
	if texture == null or not regions.has(id):
		return false
	canvas.draw_texture_rect_region(texture, dest, regions[id], modulate)
	return true
