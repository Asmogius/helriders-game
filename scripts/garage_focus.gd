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
const FADE := 0.15   # s, callout fade in / out
const DIM := 0.6     # the rest of the rig while one part is lit
var line_alpha := 0.0
var _last_points := PackedVector2Array()
var _preview_key := ""   # selected slot + browsed part the rig shows now


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
	var p := _last_points
	if p.is_empty() or line_alpha <= 0.0:
		return
	var gt := line.get_global_transform().affine_inverse()
	for k in p.size():
		p[k] = gt * p[k]
	var c := Color(T.COL_ORANGE, line_alpha)
	line.draw_polyline(p, Color(0, 0, 0, 0.6 * line_alpha), 6.0)   # dark edge: reads on any floor  # TODO: T.COL_GARAGE_FOCUS_EDGE once UI colours PR lands
	line.draw_polyline(p, c, 3.0)
	line.draw_circle(p[0], 5.0, c)
	var end := p[p.size() - 1]
	var pulse := 10.0 + 2.0 * sin(_t * 5.0)
	line.draw_arc(end, pulse, 0.0, TAU, 24, Color(0, 0, 0, 0.6 * line_alpha), 5.0)  # TODO: T.COL_GARAGE_FOCUS_EDGE once UI colours PR lands
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
		"engine":
			# #64's engine_mount layer ("engine:<id>"); the hull only if this frame has none.
			for id: String in layers:
				if id.begins_with("engine:"):
					return layers[id]
			return hull
		"chassis":
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
	_live_preview()
	var pts := callout_points()
	if not pts.is_empty():
		_last_points = pts
	line_alpha = move_toward(line_alpha, 1.0 if not pts.is_empty() else 0.0, delta / FADE)
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
	_dim(want)
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


## While a part is lit, the rest of the rig steps back (the lit part keeps
## full brightness by undoing the dim on itself).
func _dim(want: Sprite2D) -> void:
	var holder: CanvasItem = garage.get("_rig_holder") if garage != null else null
	if holder == null:
		return
	var hull: Sprite2D = garage.get("preview").get("_hull_art") if garage.get("preview") != null else null
	var on := want != null and want != hull
	holder.modulate = Color(DIM, DIM, DIM) if on else Color.WHITE
	if want != null and is_instance_valid(want):
		want.self_modulate = Color(1.0 / DIM, 1.0 / DIM, 1.0 / DIM) if on else Color.WHITE


## Browsing a candidate puts it on the rig at once (display only: the preview
## rig gets the candidate's build; the real loadout changes only on EQUIP).
func _live_preview() -> void:
	if garage == null or garage.get("preview") == null:
		return
	var sel := int(garage.get("selected"))
	var key := ""
	if sel >= 0:
		key = "%d:%s:%s" % [sel, garage.get("_preview"), str(garage.profile.rig)]
	if key == _preview_key:
		return
	_preview_key = key
	var prof: Node = garage.profile
	if sel < 0 or not prof.has_rig():
		return   # close_sheet() refreshes the rig back to the fitted build
	var slot: Dictionary = garage.SLOTS[sel]
	var cand: Dictionary = prof.with_part(prof.rig, slot.key, slot.index, str(garage.get("_preview")))
	garage.get("preview").apply_stats(garage.call("_built", cand))


func _clear() -> void:
	if _target != null and is_instance_valid(_target):
		_target.self_modulate = Color.WHITE
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
