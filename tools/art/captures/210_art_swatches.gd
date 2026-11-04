extends "res://tools/art/capture_step.gd"
## Every art-only colour in tuning.gd, named.

const SWATCHES := [
	"COL_OB_GRASS", "COL_OB_PAVE", "COL_OB_SIDING", "COL_OB_ROOF", "COL_OB_GRADE", "COL_OB_MOTE",
	"COL_FX_HOT", "COL_FX_WHITE_HOT", "COL_FX_EMBER", "COL_FX_SCORCH",
	"COL_FX_SCORCH_EDGE", "COL_FX_SMOKE",
	"COL_GARAGE_FLOOR", "COL_GARAGE_FLOOR_LINE", "COL_GARAGE_OIL", "COL_GARAGE_PEGBOARD",
	"COL_GARAGE_WALL", "COL_GARAGE_STREET_NIGHT", "COL_GARAGE_GAS_RED",
	"COL_GARAGE_DUST", "COL_GARAGE_SPARK",
	"COL_ZOMBIE_SHIRT_0", "COL_ZOMBIE_PANTS_0",
	"COL_ZOMBIE_SHIRT_1", "COL_ZOMBIE_PANTS_1",
	"COL_ZOMBIE_SHIRT_2", "COL_ZOMBIE_PANTS_2",
	"COL_ZOMBIE_SHIRT_3", "COL_ZOMBIE_PANTS_3",
	"COL_ZOMBIE_SHIRT_4", "COL_ZOMBIE_PANTS_4",
	"COL_ZOMBIE_SHIRT_5", "COL_ZOMBIE_PANTS_5",
	"COL_ZOMBIE_EYE", "COL_ZOMBIE_FLASH", "COL_TANK_SHIRT", "COL_TANK_PANTS", "COL_TANK_SKIN",
]


func run(cap: SceneTree) -> void:
	var strip: Control = cap.new_strip(T.COL_ROAD)
	var consts: Dictionary = T.new().get_script().get_script_constant_map()
	for i in SWATCHES.size():
		var n: String = SWATCHES[i]
		var pos := Vector2(16 + (i % 9) * 140, 16 + (i / 9) * 140)
		var sw := ColorRect.new()
		sw.color = consts[n]
		sw.position = pos
		sw.size = Vector2(130, 90)
		strip.add_child(sw)
		var l := UI.label(n.trim_prefix("COL_"), 11, Color(0.9, 0.9, 0.88))
		l.position = pos + Vector2(0, 94)
		strip.add_child(l)
