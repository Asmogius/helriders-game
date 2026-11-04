extends RefCounted
## Part mods (DESIGN §14, numbers from content proposal 01, approved
## 2026-11-03). Every mod is pre-attached to its schematic, shows while
## locked, and unlocks at the part's Research level for its tier
## (T.MOD_UNLOCK: Minor 3, Major 7, Signature 11, second Major 14, Unique 18).
## A part can only reach the tiers its rarity's max level allows. Mods belong
## to the schematic, like levels.
##
## Each mod: [tier, id, name, text, keyword, effect]. `effect` keys:
##   "mult": {stat: x}  multiplies the part's stat
##   "add":  {stat: x}  adds to it (missing stats start at 0)
##   "set":  {stat: x}  replaces it
##   "flag": true       a rule the game checks with has(stats.mods, id)
## Stat effects apply in Parts.at_level after Research growth.

const T := preload("res://scripts/tuning.gd")

const MODS := {
	# --- Weapons (proposal §2.1) -----------------------------------------------------
	"rivet_gun": [
		["minor", "countersunk", "Countersunk", "+1 pierce", "", {"add": {"pierce": 1}}],
	],
	"flame_sprayer": [
		["minor", "wide_nozzle", "Wide Nozzle", "+10° cone", "", {"add": {"spread_deg": 5.0}}],
		["major", "napalm_mix", "Napalm Mix", "BURNING on rigs lasts +2 s; ignites oil from 300 px", "BURNING", {"flag": true}],
	],
	"acid_lobber": [
		["minor", "sticky_glob", "Sticky Glob", "Puddles last +2 s", "", {"add": {"puddle_add": 2.0}}],
		["major", "etch", "Etch", "vs CORRODED rigs, +20% to armor", "CORRODED", {"flag": true}],
	],
	"arc_projector": [
		["minor", "long_arc", "Long Arc", "+60 px range", "", {"add": {"lock_range": 60.0}}],
		["major", "overload_coil", "Overload Coil", "During OVERLOAD the chain hits 2 extra targets", "OVERLOAD", {"flag": true}],
		["signature", "thunderhead", "Thunderhead", "Hitting a STUNNED rig vents 40% heat", "STUNNED", {"flag": true}],
	],
	# --- Harpoon / Mortar / Shock Pulse (proposal §3.4) ------------------------------
	"harpoon": [
		["minor", "barbed_tip", "Barbed Tip", "+20% to pierced zombies (36), pierce 4 -> 5", "", {"mult": {"zombie_damage": 1.2}, "set": {"pierce": 5}}],
		["major", "power_winch", "Power Winch", "Reel 100 -> 130 px/s, reels to 150 px", "", {"set": {"reel_speed": 130.0, "reel_to": 150.0}}],
		["signature", "wrecking_ball", "Wrecking Ball", "Tethered rig hitting a wall, rig or barrel above 250 px/s takes 2x collision damage (min 40)", "RAM", {"flag": true}],
	],
	"mortar": [
		["minor", "heavy_charge", "Heavy Charge", "Blast 90 -> 108 px", "", {"mult": {"blast": 1.2}}],
		["major", "cluster_shell", "Cluster Shell", "Splits at the apex into 3 bomblets, 70 px apart, 45 px blast, 40% damage each", "", {"flag": true}],
	],
	"shock_pulse": [
		["minor", "wide_field", "Wide Field", "Radius 180 -> 216 px", "STUNNED", {"mult": {"pulse_radius": 1.2}}],
		["major", "drain_arc", "Drain Arc", "Strips 50% of current shield on enemy rigs inside", "", {"flag": true}],
	],
	# --- Parts (proposal §2.2) ---------------------------------------------------------
	"slag_plating": [
		["minor", "fused_seams", "Fused Seams", "+5% armor", "", {"mult": {"armor": 1.05}}],
		["major", "heat_soak", "Heat Soak", "BURNING on you deals 50% less", "BURNING", {"flag": true}],
		["signature", "molten_skin", "Molten Skin", "RAM on a rig adds 60 fire buildup", "RAM", {"flag": true}],
	],
	"ceramic_heat_sink": [
		["minor", "fins", "Fins", "Idle cool +15%", "", {"set": {"cool_mult": 1.15}}],
		["major", "vent_purge", "Vent Purge", "Overheat lockout -25%", "", {"set": {"lockout_mult": 0.75}}],
	],
	"goop_launcher": [
		["minor", "wide_splash", "Wide Splash", "+30% radius (hits 2 rigs)", "GOOPED", {"mult": {"goop_radius": 1.3}, "set": {"goop_targets": 2}}],
		["major", "bait_shell", "Bait Shell", "GOOPED rigs also take +10% from zombies", "GOOPED", {"flag": true}],
	],
	"nitro_bottle": [
		["minor", "long_burn", "Long Burn", "+0.5 s", "", {"add": {"nitro_time": 0.5}}],
		["major", "drift_fuel", "Drift Fuel", "Ending a DRIFT refunds 3 s of cooldown", "DRIFT", {"flag": true}],
	],
	# --- Frames (proposal §2.3) --------------------------------------------------------
	"raider_frame": [
		["minor", "gun_rack", "Gun Rack", "Fixed weapons +5% fire rate", "", {"set": {"fixed_fire_mult": 1.05}}],
		["major", "hit_and_run", "Hit and Run", "2 s after a DRIFT, +15% damage", "DRIFT", {"flag": true}],
	],
	"hauler_frame": [
		["minor", "ballast", "Ballast", "+8% max HP", "", {"mult": {"hp": 1.08}}],
		["major", "tow_hitch", "Tow Hitch", "RAM on a rig shoves it 50% further", "RAM", {"flag": true}],
		["signature", "mobile_workshop", "Mobile Workshop", "Once per mission restore 15% HP", "", {"flag": true}],
		["major2", "cargo_bay", "Cargo Bay", "Kill scrap +10%", "", {"flag": true}],
	],
}

# Numbers the flag mods use at runtime.
const NAPALM_BURN_ADD := 2.0
const ETCH_ARMOR := 0.2
const DRAIN_ARC_SHARE := 0.5
const BAIT_SHELL_ZOMBIE := 0.1
const HEAT_SOAK := 0.5
const MOLTEN_SKIN_BUILDUP := 60.0
const OVERLOAD_COIL_EXTRA := 2
const THUNDERHEAD_VENT := 0.4
const DRIFT_FUEL_REFUND := 3.0
const HIT_AND_RUN := 0.15
const HIT_AND_RUN_TIME := 2.0
const TOW_HITCH := 1.5
const MOBILE_WORKSHOP := 0.15
const CARGO_BAY := 0.1
const WRECKING_BALL_SPEED := 250.0
const WRECKING_BALL_MIN := 40.0
const CLUSTER_COUNT := 3
const CLUSTER_SPACING := 70.0
const CLUSTER_BLAST := 45.0
const CLUSTER_DAMAGE := 0.4


## Every mod on a part, unlocked or not (for garage cards). [] if none.
static func for_part(id: String) -> Array:
	return MODS.get(id, [])


static func unlock_level(tier: String) -> int:
	return int(T.MOD_UNLOCK.get(tier, 999))


## Mods this part can ever reach with its rarity's max level.
static func reachable(id: String, max_level: int) -> Array:
	return for_part(id).filter(func(m: Array) -> bool: return unlock_level(str(m[0])) <= max_level)


## Mods unlocked at Research `level`.
static func unlocked(id: String, level: int) -> Array:
	return for_part(id).filter(func(m: Array) -> bool: return unlock_level(str(m[0])) <= level)


## `part` (already at its level) with its unlocked mods applied. Adds
## "mods": [ids] for the flag checks.
static func apply(part: Dictionary, level: int) -> Dictionary:
	var ids: Array[String] = []
	for m: Array in unlocked(str(part.get("id", "")), level):
		ids.append(str(m[1]))
		var fx: Dictionary = m[5]
		var mult: Dictionary = fx.get("mult", {})
		for k: String in mult:
			if part.has(k):
				part[k] = float(part[k]) * float(mult[k])
		var add: Dictionary = fx.get("add", {})
		for k: String in add:
			part[k] = (int(part.get(k, 0)) + int(add[k])) if add[k] is int else float(part.get(k, 0.0)) + float(add[k])
		var set_: Dictionary = fx.get("set", {})
		for k: String in set_:
			part[k] = set_[k]
	if not ids.is_empty():
		part["mods"] = ids
	return part


## Card line: every mod, tier and unlock level; locked ones marked.
static func card_lines(id: String, level: int, max_level: int) -> Array[String]:
	var out: Array[String] = []
	for m: Array in reachable(id, max_level):
		var at := unlock_level(str(m[0]))
		var tag := str(m[0]).to_upper().replace("MAJOR2", "MAJOR")
		var kw := ("[%s] " % str(m[4])) if str(m[4]) != "" else ""
		out.append("%s%s %s: %s%s" % [kw, tag, str(m[2]), str(m[3]), "" if level >= at else "  (LV %d)" % at])
	return out
