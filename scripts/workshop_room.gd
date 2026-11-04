extends "res://scripts/garage_room.gd"
## V2.2 style sample: the Workshop bay (GARAGE tab) as a voxel diorama room.
## The backdrop is rendered by tools/art/garage_scenes.py at the rig's tilt and
## shown at the rig preview's scale (RIG_SCALE 3.4, one room voxel = one rig
## voxel), with the hydraulic lift under the rig. Missing art -> the room draws
## nothing and the old dark floor grid shows (fallback).

const Ambient := preload("res://scripts/garage_ambient.gd")
const ART := "res://art/garage/"

var meta := {}
var zoom := 1.0                  # garage_layout.gd: the rig's extra zoom (pad stays under it)
var lift_at := Vector2.INF       # garage_layout.gd: where the rig sits (INF = default spot)
var _back: TextureRect
var _lights: TextureRect
var ambient: Control


func _init() -> void:
	super()
	room_id = "GARAGE"
	var path := ART + "workshop_bay.json"
	if not FileAccess.file_exists(path):
		return
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not (data is Dictionary) or not ResourceLoader.exists(ART + "workshop_bay_wide.png"):
		return
	meta = data
	_back = TextureRect.new()
	_back.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_back.stretch_mode = TextureRect.STRETCH_SCALE
	_back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_back)
	if ResourceLoader.exists(ART + "workshop_bay_lights.png"):
		_lights = TextureRect.new()
		_lights.texture = load(ART + "workshop_bay_lights.png")
		_lights.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		_lights.stretch_mode = TextureRect.STRETCH_SCALE
		_lights.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var add := CanvasItemMaterial.new()
		add.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
		_lights.material = add
		add_child(_lights)
	ambient = Ambient.new()
	ambient.room = self
	add_child(ambient)
	resized.connect(_layout)


func has_art() -> bool:
	return _back != null


## Pixels per room voxel on screen (the garage's 720-high layout uses 3.4).
func px() -> float:
	return (size.y / 212.0 if size.y > 0.0 else float(meta.get("scale", 3.4))) * zoom


## Lift centre in this Control's coordinates; garage.gd puts the rig at
## (size.x * 0.5, 290) on a 720-high screen.
func lift_point() -> Vector2:
	if lift_at != Vector2.INF:
		return lift_at
	return Vector2(size.x * 0.5, 290.0 * size.y / 720.0)


## Move/zoom the room so the floor pad sits under the rig.
func frame_rig(at: Vector2, new_zoom: float) -> void:
	if at == lift_at and is_equal_approx(new_zoom, zoom):
		return
	lift_at = at
	zoom = new_zoom
	_layout()


func _layout() -> void:
	if _back == null:
		return
	var wide := size.x / maxf(size.y, 1.0) > 1.85
	var name := "workshop_bay_wide" if wide else "workshop_bay"
	_back.texture = load(ART + name + ".png")
	var s := px()
	var tex_size := Vector2(_back.texture.get_size()) * s
	var lift: Array = meta[name].lift
	var origin := lift_point() - Vector2(float(lift[0]), float(lift[1])) * s
	for r: TextureRect in [_back, _lights]:
		if r == null:
			continue
		r.position = origin
		r.size = tex_size
	if _lights != null and not wide:
		# The light overlay is rendered wide; shift it to the narrow crop.
		var dw: float = (float(meta.workshop_bay_wide.size[0]) - float(meta.workshop_bay.size[0])) * 0.5 * s
		_lights.position = origin - Vector2(dw, 0.0)
		_lights.size = Vector2(_lights.texture.get_size()) * s
	ambient.size = size


func lights_node() -> TextureRect:
	return _lights
