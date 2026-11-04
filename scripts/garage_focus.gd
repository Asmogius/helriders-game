extends Node
## V2.3 sample (P6): while a slot card is open, its part lights up on the rig
## (a solid outline plus an additive copy of that part's sprite sheet, pulsing)
## and one callout line runs from the card to the part. Nothing is drawn while
## no slot is open. Uses the rig's own art: part layers (drive, armor, utility and
## internal kits), turret sheets (weapons), the hull (chassis and engine: the
## engine has no layer of its own). Code-drawn rigs (no art) get nothing.

const Vehicle := preload("res://scripts/vehicle.gd")
const T := preload("res://scripts/tuning.gd")
const UI := preload("res://scripts/ui_theme.gd")
const LAYER_FOR := {   # fitted part id -> its layer on the hull sheet
	"shock_pulse": "shock_emitter", "emergency_patch": "patch_kit", "mine_dropper": "mine_rack",
	"targeting_computer": "sensor_dish", "advanced_targeting": "sensor_dish", "roll_cage": "roll_cage",
}

const SILHOUETTE := "shader_type canvas_item;\nuniform vec4 tint : source_color;\nvoid fragment() { COLOR = vec4(tint.rgb, tint.a * texture(TEXTURE, UV).a); }"

var garage: Control
var _overlay: Sprite2D = null
var _outline: Array[Sprite2D] = []   # 8 solid copies, 1 texel out, behind the part
static var _shader: Shader
var line: Control   # the callout, drawn above the rig (tests read it)


func _ready() -> void:
	line = Control.new()
	line.name = "FocusLine"
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.set_anchors_preset(Control.PRESET_FULL_RECT)
	line.draw.connect(_draw_line)
	garage.add_child.call_deferred(line)   # last child: above the rig and the cards


## Card edge -> elbow -> the part's point on the rig, or [] when nothing is open.
func callout_points() -> PackedVector2Array:
	if garage == null or int(garage.get("selected")) < 0 or garage.get("tab") != "GARAGE":
		return PackedVector2Array()
	var i := int(garage.get("selected"))
	var tag: Control = (garage.get("_tags") as Array)[i]
	var rig: Node2D = garage.get("preview")
	if tag == null or rig == null or not rig.is_visible_in_tree():
		return PackedVector2Array()
	var r := tag.get_global_rect()
	var grid_right := r.end.x
	for t: Control in garage.get("_tags"):
		if t.visible:
			grid_right = maxf(grid_right, t.get_global_rect().end.x)
	var to: Vector2 = rig.to_global(garage.call("slot_anchor", i))
	var slot: Dictionary = garage.SLOTS[i]
	if _target != null and is_instance_valid(_target) and slot.key != "engine" and slot.key != "chassis":
		var c := part_centre(_target)
		if c != Vector2.INF:
			to = c
	# Square routing in the gutters: out of the card, along the gutter right of
	# the grid to the part's height, then straight across to the part. The
	# line never crosses another card or the part sheet.
	var gx := grid_right + UI.GAP
	if r.end.x >= grid_right - 1.0:   # right-hand card: straight out of its edge
		var from := Vector2(r.end.x, r.get_center().y)
		return PackedVector2Array([from, Vector2(gx, from.y), Vector2(gx, to.y), to])
	# left-hand card: down into the gap under it first
	var gy := r.end.y + UI.GAP * 0.5
	var from := Vector2(r.end.x - 2.0 * UI.GRID, r.end.y)
	return PackedVector2Array([from, Vector2(from.x, gy), Vector2(gx, gy), Vector2(gx, to.y), to])


static var _centres := {}   # "texture rid:frame" -> local centre of the opaque pixels


## Global centre of the visible pixels of `sp`'s current frame (Vector2.INF if none).
static func part_centre(sp: Sprite2D) -> Vector2:
	if sp.texture == null:
		return Vector2.INF
	var key := "%s:%d" % [sp.texture.get_rid(), sp.frame]
	if not _centres.has(key):
		var img := sp.texture.get_image()
		var fw := img.get_width() / sp.hframes
		var fh := img.get_height() / sp.vframes
		var ox := (sp.frame % sp.hframes) * fw
		var oy := (sp.frame / sp.hframes) * fh
		var sum := Vector2.ZERO
		var n := 0
		for y in range(0, fh, 2):
			for x in range(0, fw, 2):
				if img.get_pixel(ox + x, oy + y).a > 0.5:
					sum += Vector2(x, y)
					n += 1
		_centres[key] = Vector2.INF if n == 0 else sum / n - Vector2(fw, fh) * (0.5 if sp.centered else 0.0) + sp.offset
	var local: Vector2 = _centres[key]
	return Vector2.INF if local == Vector2.INF else sp.get_global_transform() * local


func _draw_line() -> void:
	var p := callout_points()
	if p.is_empty():
		return
	var gt := line.get_global_transform().affine_inverse()
	for k in p.size():
		p[k] = gt * p[k]
	var c := T.COL_ORANGE
	line.draw_polyline(p, Color(0, 0, 0, 0.6), 6.0)   # dark edge: reads on any floor
	line.draw_polyline(p, c, 3.0)
	line.draw_circle(p[0], 5.0, c)
	var end := p[p.size() - 1]
	var pulse := 10.0 + 2.0 * sin(_t * 5.0)
	line.draw_arc(end, pulse, 0.0, TAU, 24, Color(0, 0, 0, 0.6), 5.0)
	line.draw_arc(end, pulse, 0.0, TAU, 24, c, 2.5)
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
	if line != null:
		line.queue_redraw()
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
			for d: Vector2 in [Vector2.LEFT, Vector2.RIGHT, Vector2.UP, Vector2.DOWN, Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)]:
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
		_overlay.modulate = Color(T.COL_ORANGE, 0.45 + 0.2 * sin(_t * 5.0))
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
