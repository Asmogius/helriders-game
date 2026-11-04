extends Node2D
## V4 style sample: atlas-sprite particles (one pooled node, one _draw()).
## fx.gd owns three of these: an additive glow layer (flash, fireball,
## shockwave), a normal layer (smoke column, debris chips) and a decal layer
## under the rigs (scorch). Nothing is allocated in the combat loop: fixed
## packed arrays, swap-remove on death, like fx.gd.

const MAX := 160

var atlas: RefCounted          # fx_atlas_local.gd (P0 stand-in)
var density := 1.0
var _skip := 0.0

var _pos := PackedVector2Array()
var _vel := PackedVector2Array()
var _life := PackedFloat32Array()
var _max := PackedFloat32Array()
var _s0 := PackedFloat32Array()
var _s1 := PackedFloat32Array()
var _rot := PackedFloat32Array()
var _spin := PackedFloat32Array()
var _drag := PackedFloat32Array()
var _rise := PackedFloat32Array()   # upward drift added per second (smoke)
var _col := PackedColorArray()
var _frame0 := PackedInt32Array()   # index into _names
var _frames := PackedInt32Array()
var _fade := PackedFloat32Array()   # 0 = linear fade, 1 = hold then fade in the last third
var _names: Array[String] = []      # region names (frame k of a sequence = base + "_k")
var _rects: Array[Rect2] = []
var _count := 0


func setup(a: RefCounted, additive: bool) -> void:
	atlas = a
	for arr in [_pos, _vel]:
		arr.resize(MAX)
	for arr in [_life, _max, _s0, _s1, _rot, _spin, _drag, _rise, _fade]:
		arr.resize(MAX)
	_col.resize(MAX)
	_frame0.resize(MAX)
	_frames.resize(MAX)
	_names.clear()
	_rects.clear()
	for k: String in a.regions:
		_names.append(k)
		_rects.append(a.regions[k])
	if additive:
		var m := CanvasItemMaterial.new()
		m.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
		material = m
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST


## region: a name, or a sequence base ("fireball") with `frames` > 1.
func spawn(region: String, frames: int, at: Vector2, vel: Vector2, life: float, s0: float, s1: float,
		color := Color.WHITE, drag := 0.0, rot := 0.0, spin := 0.0, rise := 0.0, fade := 0.0, always := false) -> void:
	if _count >= MAX:
		return
	if density < 1.0 and not always:
		_skip += density
		if _skip < 1.0:
			return
		_skip -= 1.0
	var first := region + "_0" if frames > 1 else region
	var idx := _names.find(first)
	if idx < 0:
		return
	var i := _count
	_pos[i] = at
	_vel[i] = vel
	_life[i] = life
	_max[i] = life
	_s0[i] = s0
	_s1[i] = s1
	_rot[i] = rot
	_spin[i] = spin
	_drag[i] = drag
	_rise[i] = rise
	_col[i] = color
	_frame0[i] = idx
	_frames[i] = frames
	_fade[i] = fade
	_count += 1
	queue_redraw()


func clear() -> void:
	_count = 0
	queue_redraw()


func live_count() -> int:
	return _count


func _process(delta: float) -> void:
	if _count == 0:
		return
	var i := 0
	while i < _count:
		_life[i] -= delta
		if _life[i] <= 0.0:
			_count -= 1
			_pos[i] = _pos[_count]; _vel[i] = _vel[_count]; _life[i] = _life[_count]; _max[i] = _max[_count]
			_s0[i] = _s0[_count]; _s1[i] = _s1[_count]; _rot[i] = _rot[_count]; _spin[i] = _spin[_count]
			_drag[i] = _drag[_count]; _rise[i] = _rise[_count]; _col[i] = _col[_count]
			_frame0[i] = _frame0[_count]; _frames[i] = _frames[_count]; _fade[i] = _fade[_count]
			continue
		_vel[i] = _vel[i] * exp(-_drag[i] * delta) + Vector2(0.0, -_rise[i] * delta)
		_pos[i] += _vel[i] * delta
		_rot[i] += _spin[i] * delta
		i += 1
	queue_redraw()


func _draw() -> void:
	if atlas == null:
		return
	var tex: Texture2D = atlas.texture
	for i in _count:
		var t := 1.0 - _life[i] / _max[i]          # 0 -> 1 over the life
		var frame := mini(int(t * _frames[i]), _frames[i] - 1)
		var name_i := _frame0[i]
		if _frames[i] > 1:
			name_i = _names.find(_names[_frame0[i]].trim_suffix("_0") + "_%d" % frame)
		var r := _rects[name_i]
		var s := lerpf(_s0[i], _s1[i], t)
		var c := _col[i]
		var keep := 1.0 - t if _fade[i] < 0.5 else clampf((1.0 - t) * 3.0, 0.0, 1.0)
		c.a *= keep
		draw_set_transform(_pos[i], _rot[i], Vector2(s, s))
		draw_texture_rect_region(tex, Rect2(-r.size * 0.5, r.size), r, c)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
