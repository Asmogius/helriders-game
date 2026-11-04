extends Node
## V2.3 sample (P6): while a slot card is open, its part lights up on the rig
## (an additive copy of that part's sprite sheet, pulsing), instead of callout
## lines. Uses the rig's own art: part layers (drive, armor, utility and
## internal kits), turret sheets (weapons), the hull (chassis and engine: the
## engine has no layer of its own). Code-drawn rigs (no art) get nothing.

const Vehicle := preload("res://scripts/vehicle.gd")
const T := preload("res://scripts/tuning.gd")
const LAYER_FOR := {   # fitted part id -> its layer on the hull sheet
	"shock_pulse": "shock_emitter", "emergency_patch": "patch_kit", "mine_dropper": "mine_rack",
	"targeting_computer": "sensor_dish", "advanced_targeting": "sensor_dish", "roll_cage": "roll_cage",
}

const SILHOUETTE := "shader_type canvas_item;\nuniform vec4 tint : source_color;\nvoid fragment() { COLOR = vec4(tint.rgb, tint.a * texture(TEXTURE, UV).a); }"

var garage: Control
var _overlay: Sprite2D = null
var _outline: Array[Sprite2D] = []   # 4 solid copies, 1 texel out, behind the part
static var _shader: Shader
var _target: Sprite2D = null
var _t := 0.0


## The sprite that shows slot `i`'s part on `rig`, or null.
static func target_for(rig: Node2D, slot: Dictionary, part_id: String) -> Sprite2D:
	var hull: Sprite2D = rig.get("_hull_art")
	if hull == null:
		return null
	var layers: Dictionary = rig.get("_layer_sprites")
	var key := String(slot.key)
	match key:
		"chassis", "engine":
			return hull
		"drive", "armor_front", "armor_sides", "armor_rear":
			var prefix := "drive:" if key == "drive" else "armor:"
			for id: String in layers:
				if id.begins_with(prefix):
					return layers[id]
			return null
		"weapons":
			var turrets: Array = rig.get("_turrets")
			var i := int(slot.index)
			if i < turrets.size() and turrets[i] != null and turrets[i].get("art") != null:
				return turrets[i].art
			for id: String in ["nose_guns_hot", "nose_guns"]:
				if layers.has(id):
					return layers[id]
			return null
		_:
			var layer: String = LAYER_FOR.get(part_id, "")
			return layers.get(layer, null)


func _process(delta: float) -> void:
	_t += delta
	var want: Sprite2D = null
	if garage != null and int(garage.get("selected")) >= 0 and garage.get("preview") != null:
		var i := int(garage.get("selected"))
		var slot: Dictionary = garage.SLOTS[i]
		want = target_for(garage.get("preview"), slot, garage.call("_slot_part", slot))
	if want != _target:
		_clear()
		_target = want
		if want != null:
			_overlay = Sprite2D.new()
			_overlay.name = "FocusGlow"
			var mat := CanvasItemMaterial.new()
			mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
			_overlay.material = mat
			_overlay.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			want.add_child(_overlay)
			if _shader == null:
				_shader = Shader.new()
				_shader.code = SILHOUETTE
			for d: Vector2 in [Vector2.LEFT, Vector2.RIGHT, Vector2.UP, Vector2.DOWN]:
				var o := Sprite2D.new()
				o.name = "FocusOutline"
				var sm := ShaderMaterial.new()
				sm.shader = _shader
				sm.set_shader_parameter("tint", T.COL_ORANGE)
				o.material = sm
				o.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
				o.show_behind_parent = true
				o.position = d
				want.add_child(o)
				_outline.append(o)
	if _overlay != null and is_instance_valid(_target):
		_overlay.texture = _target.texture
		_overlay.hframes = _target.hframes
		_overlay.vframes = _target.vframes
		_overlay.frame = _target.frame
		_overlay.centered = _target.centered
		_overlay.offset = _target.offset
		_overlay.modulate = Color(T.COL_ORANGE, 0.3 + 0.15 * sin(_t * 5.0))
		for o in _outline:
			o.texture = _target.texture
			o.hframes = _target.hframes
			o.vframes = _target.vframes
			o.frame = _target.frame
			o.centered = _target.centered
			o.offset = _target.offset
	elif _overlay != null:
		_clear()


func _clear() -> void:
	if _overlay != null and is_instance_valid(_overlay):
		_overlay.queue_free()
	for o in _outline:
		if is_instance_valid(o):
			o.queue_free()
	_outline.clear()
	_overlay = null
	_target = null


## Tests: the sprite lit now (null when nothing is).
func lit() -> Sprite2D:
	return _target if _overlay != null else null
