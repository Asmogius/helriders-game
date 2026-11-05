extends Node
## Prototype HD-2D look (Octopath-style lighting on chunky 1 px/voxel sprites).
## Hand lights only: no normal maps, no shadow casters.
##
## Cost model (Compatibility / Android), see docs/LOOKTEST_HD2D.md:
## - CanvasModulate ambient (no extra pass)
## - up to 4 PointLight2Ds drawn inside the canvas item shader (not deferred)
## - 1 full-screen grade pass, which is also the only backbuffer copy
## - bloom is a few pre-blurred additive sprites (no HDR glow; Compatibility has none)
## Cameron cut the screen-edge blur on 2026-11-05. This stack cannot turn it on.

const POOL_SIZE := 8
const CAP_HIGH := 4
const CAP_LOW := 3
const CULL_DIST := 980.0

# Hardcoded prototype colours. Not tuning.gd (those constants belong to the UI / night-grade work).
# Night ambient is a cool desaturated blue-grey. It is deliberately not brown #512b11
# (that brown is Color(0.318, 0.169, 0.067) / COL_NIGHT_WORLD on the other branch).
const DAY_AMBIENT := Color(0.84, 0.80, 0.72, 1.0)
const NIGHT_AMBIENT := Color(0.40, 0.46, 0.60, 1.0)
const SUN_COLOR := Color(1.0, 0.92, 0.74, 1.0)
const MOON_COLOR := Color(0.62, 0.74, 0.95, 1.0)
const HEAD_COLOR := Color(1.0, 0.84, 0.58, 1.0)
const FIRE_COLOR := Color(1.0, 0.48, 0.14, 1.0)
const MUZZLE_COLOR := Color(1.0, 0.93, 0.78, 1.0)
const DAY_FOG := Color(0.62, 0.58, 0.48, 1.0)
const NIGHT_FOG := Color(0.08, 0.10, 0.16, 1.0)

var mode := "day"             # "day" or "night"
var enabled := true           # false = the stock look (before shots)
var practicals := true        # false = ambient + grade only, no PointLight2Ds
var low_end := false
var fire_at := Vector2.ZERO
var muzzle_at := Vector2.ZERO
var show_fire := true
var show_muzzle := true

var _world: Node2D
var _cam: Camera2D
var _rig: Node2D
var _modulate: CanvasModulate
var _grade_layer: CanvasLayer
var _grade: ColorRect
var _grade_mat: ShaderMaterial
var _day_ramp: Texture2D
var _night_ramp: Texture2D
var _blob: Texture2D
var _oval: Texture2D
var _halo_tex: Texture2D
var _dot_tex: Texture2D
var _add: ShaderMaterial
var _pool: Array[PointLight2D] = []
var _halos: Array[Sprite2D] = []
var _dots: Array[Sprite2D] = []
var _head_standin: Sprite2D
var _key_anchor: Node2D
var _reqs: Array[Dictionary] = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_blob = _soft(128, 128, 3.4)
	_oval = _soft(160, 96, 2.6)
	_halo_tex = _soft(96, 96, 2.4)
	_dot_tex = _dots_tex()
	_day_ramp = _ramp([
		[0.0, Color(0.20, 0.16, 0.12)],
		[0.42, Color(0.78, 0.70, 0.58)],
		[1.0, Color(1.0, 0.97, 0.90)],
	])
	_night_ramp = _ramp([
		[0.0, Color(0.16, 0.20, 0.30)],
		[0.40, Color(0.34, 0.40, 0.52)],
		[0.75, Color(0.62, 0.68, 0.76)],
		[1.0, Color(1.0, 0.95, 0.86)],
	])
	_add = ShaderMaterial.new()
	_add.shader = load("res://scripts/look_emissive.gdshader")
	_build_grade()


func attach(world: Node2D) -> void:
	_world = world
	_cam = world.get("camera") as Camera2D
	_rig = world.get("vehicle") as Node2D
	if _modulate != null:
		return
	_modulate = CanvasModulate.new()
	_modulate.name = "LookAmbient"
	_world.add_child(_modulate)
	if _cam != null:
		_key_anchor = Node2D.new()
		_key_anchor.name = "LookKeyAnchor"
		# Upper-left of the camera, in world pixels: the 45° key falls off toward the lower right.
		_key_anchor.position = Vector2(-280, -190)
		_cam.add_child(_key_anchor)
	for i in POOL_SIZE:
		var light := PointLight2D.new()
		light.name = "LookLight%d" % i
		light.texture = _blob
		light.shadow_enabled = false
		light.range_z_min = -4096
		light.range_z_max = 4096
		light.enabled = false
		light.visible = false
		_world.add_child(light)
		_pool.append(light)
		var halo := Sprite2D.new()
		halo.name = "LookHalo%d" % i
		halo.texture = _halo_tex
		halo.centered = true
		halo.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		halo.material = _add
		halo.light_mask = 0
		halo.z_index = 8
		halo.visible = false
		_world.add_child(halo)
		_halos.append(halo)
	var stand := Sprite2D.new()
	stand.name = "LookHeadStandin"
	stand.texture = _oval
	stand.centered = true
	stand.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	stand.material = _add
	stand.light_mask = 0
	stand.z_index = 7
	stand.visible = false
	_world.add_child(stand)
	_head_standin = stand
	for i in 2:
		var dot := Sprite2D.new()
		dot.name = "LookHeadDot%d" % i
		dot.texture = _dot_tex
		dot.centered = true
		dot.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		dot.light_mask = 0
		dot.z_index = 9
		dot.visible = false
		_world.add_child(dot)
		_dots.append(dot)
	_apply()


func ambient_color() -> Color:
	return NIGHT_AMBIENT if mode == "night" else DAY_AMBIENT


func light_cap() -> int:
	return CAP_LOW if low_end else CAP_HIGH


func active_light_count() -> int:
	var n := 0
	for light: PointLight2D in _pool:
		if light.visible and light.enabled:
			n += 1
	return n


## True when the night ambient is cool (blue above red), not brown #512b11.
func night_is_cool() -> bool:
	var c := NIGHT_AMBIENT
	var brown := Color(0.318, 0.169, 0.067)
	return c.b > c.r + 0.08 and c.b > c.g and c.g > brown.g + 0.1 and c.b > brown.b + 0.2


func set_mode(next: String) -> void:
	mode = next
	_apply()


func set_enabled(on: bool) -> void:
	enabled = on
	_apply()


func set_practicals(on: bool) -> void:
	practicals = on
	_apply()


func set_low_end(on: bool) -> void:
	low_end = on
	_apply()


func _process(_delta: float) -> void:
	if _world == null:
		return
	_apply()


func _apply() -> void:
	var on := enabled and _modulate != null
	if _modulate != null:
		_modulate.visible = on
		_modulate.color = ambient_color()
	if _grade != null:
		_grade.visible = on
	if not on:
		_hide_lights()
		return
	_grade_params()
	_lift()
	_hide_lights()
	if not practicals:
		_place_dots(false)
		return
	_collect()
	_assign()
	_place_dots(true)


func _hide_lights() -> void:
	for light: PointLight2D in _pool:
		light.enabled = false
		light.visible = false
	for halo: Sprite2D in _halos:
		halo.visible = false
	if _head_standin != null:
		_head_standin.visible = false
	for dot: Sprite2D in _dots:
		dot.visible = false


func _collect() -> void:
	_reqs.clear()
	var night := mode == "night"
	var key_at := _key_anchor.global_position if _key_anchor != null else Vector2.ZERO
	if _cam != null and _key_anchor == null:
		key_at = _cam.global_position + Vector2(-280, -190)
	# The key is one local pool, not a full-screen directional. Upper-left, soft.
	_submit(key_at, MOON_COLOR if night else SUN_COLOR, 0.16 if night else 0.32, _blob, 9.0, 0.0, 1, 0.0)
	if not low_end:
		var nose := _nose()
		var fwd := Vector2.RIGHT.rotated(_rig.global_rotation) if _rig != null else Vector2.DOWN
		# Short warm pool in front of the lamps. Oval, not a hard cone.
		_submit(nose + fwd * 22.0, HEAD_COLOR, 0.72 if night else 0.38, _oval, 0.85, _rig.global_rotation if _rig != null else 0.0, 3, 0.55)
	if show_fire:
		_submit(fire_at, FIRE_COLOR, 0.95 if night else 0.55, _blob, 2.7, 0.0, 2, 1.15)
	if show_muzzle:
		_submit(muzzle_at, MUZZLE_COLOR, 1.05 if night else 0.62, _blob, 0.72, 0.0, 4, 0.42)


func _submit(at: Vector2, color: Color, energy: float, tex: Texture2D, scale: float, rot: float, priority: int, halo: float) -> void:
	if _cam != null and at.distance_to(_cam.global_position) > CULL_DIST:
		return
	_reqs.append({
		"at": at, "color": color, "energy": energy, "tex": tex,
		"scale": scale, "rot": rot, "priority": priority, "halo": halo,
	})


func _assign() -> void:
	_reqs.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.priority) > int(b.priority))
	var cap := light_cap()
	var n := mini(cap, mini(_reqs.size(), _pool.size()))
	for i in n:
		var req: Dictionary = _reqs[i]
		var light := _pool[i]
		light.texture = req.tex
		light.texture_scale = float(req.scale)
		light.color = req.color
		light.energy = float(req.energy)
		light.rotation = float(req.rot)
		light.global_position = req.at
		light.enabled = true
		light.visible = true
		var halo_s := float(req.halo)
		var halo := _halos[i]
		if halo_s > 0.05:
			halo.visible = true
			halo.global_position = req.at
			halo.rotation = float(req.rot)
			halo.scale = Vector2(halo_s, halo_s * (0.62 if req.tex == _oval else 1.0))
			var tint: Color = req.color
			tint.a = 0.28
			halo.modulate = tint
		else:
			halo.visible = false
	# Low preset: the headlight pool is an additive sprite, not a PointLight2D.
	if low_end and _rig != null and _head_standin != null:
		var nose := _nose()
		var fwd := Vector2.RIGHT.rotated(_rig.global_rotation)
		_head_standin.visible = true
		_head_standin.global_position = nose + fwd * 34.0
		_head_standin.rotation = _rig.global_rotation
		_head_standin.scale = Vector2(2.4, 1.5)
		_head_standin.modulate = HEAD_COLOR
		_head_standin.modulate.a = 0.85


func _place_dots(on: bool) -> void:
	if _dots.is_empty() or _rig == null:
		return
	if not on or not practicals:
		for dot: Sprite2D in _dots:
			dot.visible = false
		return
	var nose := _nose()
	var fwd := Vector2.RIGHT.rotated(_rig.global_rotation)
	var side := fwd.orthogonal()
	var mid := nose + fwd * 6.0
	_dots[0].visible = true
	_dots[1].visible = true
	_dots[0].global_position = mid + side * 7.0
	_dots[1].global_position = mid - side * 7.0
	# Solid lamp pixels, not the additive bloom. Bright enough to survive a dark ambient
	# if CanvasModulate multiplies them (night ~0.2, so ~5x brings them back to white).
	var amb := ambient_color()
	var boost := Color(1.0 / maxf(amb.r, 0.08), 0.96 / maxf(amb.g, 0.08), 0.82 / maxf(amb.b, 0.08))
	_dots[0].modulate = boost
	_dots[1].modulate = boost


func _nose() -> Vector2:
	if _rig == null:
		return fire_at
	var sc := absf(_rig.global_scale.x)
	var hull: Object = _rig.get("_hull_art")
	if hull != null and hull.has_method("point_offset"):
		var meta: Dictionary = hull.get("meta")
		var points: Dictionary = meta.get("points", {})
		if points.has("nose_mount"):
			return _rig.global_position + hull.call("point_offset", "nose_mount") * sc
	return _rig.global_position + Vector2.RIGHT.rotated(_rig.global_rotation) * 28.0


func _grade_params() -> void:
	if _grade_mat == null:
		return
	var night := mode == "night"
	_grade_mat.set_shader_parameter("grade_ramp", _night_ramp if night else _day_ramp)
	_grade_mat.set_shader_parameter("tint_strength", 0.46 if night else 0.22)
	_grade_mat.set_shader_parameter("contrast", 1.06 if night else 1.04)
	_grade_mat.set_shader_parameter("vignette_amt", 0.46 if night else 0.34)
	_grade_mat.set_shader_parameter("fog_color", NIGHT_FOG if night else DAY_FOG)
	_grade_mat.set_shader_parameter("fog_amount", 0.22 if night else 0.10)
	# Night keeps lamp hues. Day lets the warm grade sit on the highlights a little.
	_grade_mat.set_shader_parameter("protect", 0.92 if night else 0.35)


func _lift() -> void:
	if _add == null:
		return
	# A warm fringe only. Scaling by 1/ambient turned the halos into white discs.
	var lift := Vector3(1.2, 1.05, 0.85) if mode == "night" else Vector3(1.05, 1.0, 0.92)
	_add.set_shader_parameter("lift", lift)


func _build_grade() -> void:
	_grade_layer = CanvasLayer.new()
	_grade_layer.name = "LookGrade"
	_grade_layer.layer = 9   # HUD is layer 10, so the grade stays under it
	add_child(_grade_layer)
	_grade = ColorRect.new()
	_grade.name = "LookGradeRect"
	_grade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_grade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_grade.color = Color.WHITE
	_grade_mat = ShaderMaterial.new()
	_grade_mat.shader = load("res://scripts/look_grade.gdshader")
	_grade.material = _grade_mat
	_grade.visible = false
	_grade_layer.add_child(_grade)
	_grade_params()


func _soft(w: int, h: int, tightness: float) -> Texture2D:
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var cx := (w - 1) * 0.5
	var cy := (h - 1) * 0.5
	for y in h:
		for x in w:
			var dx := (float(x) - cx) / maxf(cx, 1.0)
			var dy := (float(y) - cy) / maxf(cy, 1.0)
			var d := sqrt(dx * dx + dy * dy)
			# Falloff lives in RGB as well as alpha. A white RGB quad is a hard
			# rectangle in the Compatibility light shader, which ignores a soft alpha.
			var a := exp(-d * d * tightness) * (1.0 - smoothstep(0.42, 0.95, d))
			if a < 0.01:
				a = 0.0
			img.set_pixel(x, y, Color(a, a, a, a))
	return ImageTexture.create_from_image(img)


func _dots_tex() -> Texture2D:
	var img := Image.create(3, 2, false, Image.FORMAT_RGBA8)
	img.fill(Color(1, 1, 1, 1))
	var tex := ImageTexture.create_from_image(img)
	return tex


func _ramp(stops: Array) -> Texture2D:
	var img := Image.create(256, 1, false, Image.FORMAT_RGBA8)
	for i in 256:
		var t := float(i) / 255.0
		var c: Color = stops[0][1]
		for k in range(1, stops.size()):
			var t1: float = stops[k][0]
			if t <= t1:
				var t0: float = stops[k - 1][0]
				var u := clampf((t - t0) / maxf(t1 - t0, 0.0001), 0.0, 1.0)
				var a: Color = stops[k - 1][1]
				var b: Color = stops[k][1]
				c = a.lerp(b, u)
				break
			c = stops[k][1]
		img.set_pixel(i, 0, c)
	return ImageTexture.create_from_image(img)
