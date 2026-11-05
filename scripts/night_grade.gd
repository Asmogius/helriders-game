extends RefCounted
## World night grade (Ebbtide plan phase 2, Cameron 2026-11-04): one
## orange-brown tint (#512b11) on the world only; HUD, FX glow and emissive
## lights are never tinted. Art applies it to rigs, zombies and FX here; Maps
## applies the same grade to map chunks and props; UI keeps the HUD out of it.
##
## The tint is the night *average* Ebbtide hits (#512b11, screenshot 01). As a
## multiply it is that colour over Ebbtide's day average (#60594f, screenshot
## 02), so a normal daytime scene averages out at #512b11 at night.
const T := preload("res://scripts/tuning.gd")
const DAY_AVG := Color8(0x60, 0x59, 0x4f)
const FALLBACK_NIGHT := Color8(0x51, 0x2b, 0x11)   # until UI's COL_NIGHT_WORLD (#71) lands


static func night_colour() -> Color:
	var c: Variant = (T as Script).get_script_constant_map().get("COL_NIGHT_WORLD", FALLBACK_NIGHT)
	return c if c is Color else FALLBACK_NIGHT


## The multiply to put on world sprites at night.
static func world_grade() -> Color:
	var n := night_colour()
	return Color(minf(n.r / DAY_AVG.r, 1.0), minf(n.g / DAY_AVG.g, 1.0), minf(n.b / DAY_AVG.b, 1.0))


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
