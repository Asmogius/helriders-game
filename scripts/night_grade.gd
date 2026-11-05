extends RefCounted
## World night grade (Ebbtide plan phase 2): one cool, desaturated blue tint
## (#2a3550) on the world only; HUD, FX glow and emissive lights are never
## tinted. Art applies it to rigs, zombies and FX here; Maps applies the same
## grade to map chunks and props; UI keeps the HUD out of it.
##
## The tint is the night average (#2a3550). As a multiply it is that colour
## over Ebbtide's day average (#60594f). Each channel is capped at 1, so the
## blue channel (80/79) stays at the day value.
const T := preload("res://scripts/tuning.gd")
const DAY_AVG := Color8(0x60, 0x59, 0x4f)
const FALLBACK_NIGHT := Color8(0x2a, 0x35, 0x50)   # same hex as T.COL_NIGHT_WORLD


static func night_colour() -> Color:
	var c: Variant = (T as Script).get_script_constant_map().get("COL_NIGHT_WORLD", FALLBACK_NIGHT)
	return c if c is Color else FALLBACK_NIGHT


## The multiply to put on world sprites at night.
static func world_grade() -> Color:
	return grade_for(night_colour())


## Same multiply aimed at an explicit night average (capture before/after).
static func grade_for(night: Color) -> Color:
	return Color(minf(night.r / DAY_AVG.r, 1.0), minf(night.g / DAY_AVG.g, 1.0), minf(night.b / DAY_AVG.b, 1.0))


## Rig: every voxel sprite takes the grade on self_modulate; the hull's Lights
## child and white-hot / glow layers stay untinted. Color.WHITE turns it off.
static func apply_rig(rig: Node, grade: Color) -> void:
	var hot := {}
	var layers: Variant = rig.get("_layer_sprites")
	if layers is Dictionary:
		for id: String in layers:
			if id.contains("hot") or id.contains("glow"):
				hot[layers[id]] = true
	_walk(rig, grade, hot)


static func _walk(n: Node, grade: Color, hot: Dictionary) -> void:
	for c in n.get_children():
		if c is Sprite2D and c.name != "Lights" and not hot.has(c):
			(c as Sprite2D).self_modulate = grade
		if c.name != "Lights":
			_walk(c, grade, hot)


## Zombies draw themselves (one atlas); the whole body takes the grade.
static func apply_zombie(z: CanvasItem, grade: Color) -> void:
	z.self_modulate = grade
