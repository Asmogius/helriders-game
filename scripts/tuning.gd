extends RefCounted
## Shared constants: collision layers, palette, and balance numbers.
## Tune the game here rather than inside gameplay scripts.

# --- Collision layers (bit values) -------------------------------------------
const LAYER_WORLD := 1
const LAYER_VEHICLE := 2
const LAYER_ZOMBIE := 4

# --- Palette (rust, concrete, practical cyan/orange lights) -------------------
const COL_CONCRETE := Color(0.16, 0.16, 0.17)
const COL_ROAD := Color(0.105, 0.105, 0.115)
const COL_ROAD_LINE := Color(0.62, 0.55, 0.32, 0.45)
const COL_BUILDING := Color(0.21, 0.205, 0.2)
const COL_ROOF := Color(0.27, 0.26, 0.245)
const COL_RUST := Color(0.46, 0.25, 0.13)
const COL_STEEL := Color(0.31, 0.32, 0.335)
const COL_CYAN := Color(0.25, 0.82, 0.88)
const COL_ORANGE := Color(0.93, 0.48, 0.17)
const COL_ZOMBIE := Color(0.45, 0.5, 0.37)
const COL_ZOMBIE_DARK := Color(0.27, 0.3, 0.23)
const COL_BLOOD := Color(0.3, 0.09, 0.07, 0.85)

# --- Arena ---------------------------------------------------------------------
const WORLD_SIZE := Vector2(3200, 2400)
const SPAWN_MIN_DISTANCE := 850.0  # keep spawns off-screen

# --- Mission: Clear --------------------------------------------------------------
const CLEAR_TARGET := 40       # shamblers to kill to clear the block
const ZOMBIE_START := 12       # alive at the start
const ZOMBIE_CAP := 28         # design cap is 25-30 alive at once
const ZOMBIE_RAMP_SECONDS := 4.0  # +1 allowed alive every N seconds
const SCRAP_PER_KILL := 2
const HORDE_SIZE := Vector2i(3, 6)  # zombies spawn in packs of this many

# --- Shambler ------------------------------------------------------------------
const SHAMBLER_HP := 40.0
const SHAMBLER_SPEED := 85.0
const SHAMBLER_RADIUS := 13.0
const SHAMBLER_DPS := 3.0        # chip damage per zombie in contact
const SHAMBLER_SEPARATION := 34.0

# --- Starter vehicle ------------------------------------------------------------
# One flat dictionary of final stats. The parts system will build this from
# chassis + engine + drive + armor + weapons; for now it is hand-tuned.
const STARTER_RIG := {
	"name": "Starter Rig",
	"max_speed": 560.0,        # px/s
	"reverse_speed": 230.0,
	"acceleration": 640.0,
	"brake": 1500.0,
	"coast": 280.0,
	"turn_rate": 3.4,          # rad/s at full steering authority
	"grip": 5.5,               # how fast sideways slide dies (lower = more drift)
	"armor": 150.0,
	"ram_damage": 70.0,        # at full speed
	"fire_rate": 7.0,          # shots/s
	"bullet_damage": 9.0,
	"bullet_speed": 1500.0,
	"spread_deg": 3.0,
	"turret_turn_rate": 9.0,
}
