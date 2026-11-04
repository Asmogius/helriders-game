extends RefCounted
## V4.3 (P2): per-weapon tracer looks. VISUAL ONLY: nothing here is read by
## gameplay (no damage, range, speed or fire rate), and bullets fly the same.
##
## Keyed by the weapon id (Parts id for the player, `gun_id` for enemy rigs).
## Fields:
##   glow      streak colour (tints the atlas glow, or the code-drawn line)
##   core      head colour (white-hot core; alpha 0 = no core)
##   length    x the pool's TRAIL (16 px)
##   width     x the base streak width
##   dash      0 = one streak; n = n short dashes along the tail
## Unknown ids fall back to DEFAULT (player) / DEFAULT_ENEMY by team.
## Mortar and Acid Lobber shells are drawn by shell_pool.gd (unchanged); the
## Harpoon is hitscan, so its entry styles the spear flash in vehicle.gd's
## CableLine.

const T := preload("res://scripts/tuning.gd")

# Sample-local colours (proposed for tuning.gd; UI/P0 owns colours):
const FX_HOT := Color8(255, 217, 102)          # also in fx_sheet.py
const FX_WHITE_HOT := Color8(255, 242, 204)    # also in fx_sheet.py
const TRACER_RIVET := Color8(255, 150, 70)     # hot rivet slug (orange, a step hotter)
const NO_CORE := Color(0, 0, 0, 0)

const DEFAULT := {"glow": T.COL_ORANGE, "core": FX_WHITE_HOT, "length": 1.0, "width": 1.0, "dash": 0}
const DEFAULT_ENEMY := {"glow": T.COL_ENEMY, "core": Color(1.0, 0.6, 0.55), "length": 1.0, "width": 1.0, "dash": 0}

const STYLES := {
	# Player turrets
	"pintle_turret": DEFAULT,
	"burst_turret": {"glow": FX_HOT, "core": FX_WHITE_HOT, "length": 0.7, "width": 0.8, "dash": 0},
	"heavy_mg_turret": {"glow": T.COL_ORANGE, "core": FX_HOT, "length": 1.35, "width": 1.3, "dash": 0},
	"scattergun_turret": {"glow": FX_HOT, "core": NO_CORE, "length": 0.35, "width": 0.8, "dash": 0},
	# Player fixed (nose) guns
	"hood_guns": {"glow": T.COL_ORANGE, "core": FX_HOT, "length": 0.9, "width": 0.8, "dash": 2},
	"outrider_twin_guns": {"glow": T.COL_ORANGE, "core": FX_HOT, "length": 0.9, "width": 0.8, "dash": 2},
	"rivet_gun": {"glow": TRACER_RIVET, "core": FX_WHITE_HOT, "length": 0.5, "width": 1.7, "dash": 0},
	"flame_sprayer": {"glow": T.STATUS_COLORS[1], "core": NO_CORE, "length": 0.6, "width": 2.0, "dash": 0},
	"arc_projector": {"glow": T.STATUS_COLORS[0], "core": T.COL_CYAN, "length": 1.1, "width": 0.9, "dash": 3},
	"harpoon": {"glow": Color(0.8, 0.78, 0.6), "core": Color(0.655, 0.66, 0.668), "length": 1.0, "width": 1.2, "dash": 0},
	# Enemy guns (gun_id in tuning.gd); enemy red family only
	"gunner_rig": {"glow": T.COL_ENEMY, "core": FX_WHITE_HOT, "length": 0.7, "width": 0.8, "dash": 0},
	"convoy_nose": {"glow": T.COL_ENEMY, "core": Color(1.0, 0.6, 0.55), "length": 0.9, "width": 0.8, "dash": 2},
	"convoy_turret": {"glow": T.COL_ENEMY, "core": FX_HOT, "length": 1.3, "width": 1.3, "dash": 0},
	"scrapper": {"glow": T.COL_ENEMY, "core": Color(1.0, 0.6, 0.55), "length": 0.6, "width": 0.9, "dash": 0},
}

static var _ids: Array[String] = []


## Byte index stored per bullet: 0 = DEFAULT, 1 = DEFAULT_ENEMY, 2.. = STYLES.
static func index_for(id: String, enemy: bool) -> int:
	if _ids.is_empty():
		for k: String in STYLES:
			_ids.append(k)
	var i := _ids.find(id)
	if i >= 0:
		return i + 2
	return 1 if enemy else 0


static func style_at(index: int) -> Dictionary:
	if index == 1:
		return DEFAULT_ENEMY
	if index >= 2:
		index_for("", false)
		if index - 2 < _ids.size():
			return STYLES[_ids[index - 2]]
	return DEFAULT


static func style_for(id: String, enemy := false) -> Dictionary:
	return style_at(index_for(id, enemy))
