extends RefCounted
## Crew (DESIGN §6): who rides the rig. Numbers were approved by the owner in
## the "Helriders: Crew Draft" doc; don't change them without asking.
##
## A crew member is a plain dictionary (it goes in the save file):
##   id       unique number in this save
##   name     "Mae Voss"
##   role     "driver" | "gunner"   (the Mechanic comes later)
##   rarity   "Common" .. "Mythic"; sets the level cap, the base passive and
##            the triggered ability
##   xp       total XP earned (a job's skulls, split among the crew on it)
##   rest     days left resting at the Inn after an injury (0 = fit)
##   seated   riding the rig (one seat per role, if the frame has that seat)
##
## Passives scale with level; triggered abilities scale with rarity. An
## injured crew member loses both for the rest of the run and debuffs the rig
## (vehicle.gd), then rests at the Inn.

const T := preload("res://scripts/tuning.gd")
const Parts := preload("res://scripts/parts.gd")

const RARITIES := ["Common", "Uncommon", "Rare", "Epic", "Legendary", "Mythic"]
const MAX_LEVEL := [5, 8, 11, 14, 17, 20]
const MYTHIC_COLOR := Color(1.0, 0.36, 0.42)

const ROLES := ["driver", "gunner"]
const SEAT_ORDER := ["driver", "gunner", "mechanic"]
const ROLE_NAMES := {"driver": "Driver", "gunner": "Gunner", "mechanic": "Mechanic"}

# Lists are indexed by rarity (Common first). Passives are at level 1; every
# level after adds the *_per_level amount.
const DRIVER := {
	"turn": [0.04, 0.06, 0.08, 0.10, 0.12, 0.14],      # turn rate bonus
	"grip": [0.3, 0.5, 0.7, 0.9, 1.1, 1.3],            # added grip
	"turn_per_level": 0.01,
	"grip_per_level": 0.1,
	# Hard Line (triggered): sharper steering and grip, Epic+ adds top speed.
	"hl_turn": [0.30, 0.30, 0.35, 0.35, 0.40, 0.40],
	"hl_grip": [3.0, 3.0, 3.5, 3.5, 4.0, 4.0],
	"hl_speed": [0.0, 0.0, 0.0, 0.15, 0.20, 0.25],
	"hl_time": [3.0, 3.5, 4.0, 4.5, 5.0, 5.5],
	"hl_cooldown": [22.0, 20.0, 18.0, 16.0, 15.0, 14.0],
}
const GUNNER := {
	"spread": [0.10, 0.15, 0.20, 0.25, 0.30, 0.35],    # less spread, every weapon
	"aim": [0.05, 0.08, 0.10, 0.12, 0.15, 0.18],       # faster turret aim
	"lock": [0.0, 0.0, 0.0, 0.10, 0.15, 0.20],         # Epic+: longer lock range
	"spread_per_level": 0.01,
	"aim_per_level": 0.01,
	# Overcharge (triggered): fire rate and damage.
	"oc_fire": [0.40, 0.45, 0.50, 0.55, 0.60, 0.70],
	"oc_damage": [0.20, 0.25, 0.30, 0.35, 0.40, 0.45],
	"oc_time": [5.0, 5.0, 6.0, 6.0, 7.0, 7.0],
	"oc_cooldown": [25.0, 23.0, 20.0, 19.0, 18.0, 16.0],
}

const FIRST_NAMES := ["Mae", "Jo", "Rook", "Tess", "Cal", "Dez", "Wren", "Hank", "Ivy", "Bo",
	"Nash", "Rae", "Cole", "Lux", "Pike", "Sol", "Vera", "Gus", "Juno", "Kit", "Moss", "Dell"]
const LAST_NAMES := ["Voss", "Kade", "Rusk", "Hale", "Crane", "Mott", "Pryor", "Stack", "Vance", "Dunn",
	"Grit", "Holt", "Marsh", "Quill", "Reyes", "Slade", "Thorn", "Wick", "Yates", "Zell", "Barrow", "Coil"]


## A new level-1 crew member (no id yet; the Profile assigns one).
static func make(role: String, rarity: String, rng: RandomNumberGenerator) -> Dictionary:
	var first: String = FIRST_NAMES[rng.randi_range(0, FIRST_NAMES.size() - 1)]
	var last: String = LAST_NAMES[rng.randi_range(0, LAST_NAMES.size() - 1)]
	return {"id": 0, "name": "%s %s" % [first, last], "role": role, "rarity": rarity,
		"xp": 0.0, "rest": 0, "seated": false}


static func rarity_index(member: Dictionary) -> int:
	return maxi(RARITIES.find(str(member.get("rarity", "Common"))), 0)


static func max_level(member: Dictionary) -> int:
	return int(MAX_LEVEL[rarity_index(member)])


## XP it takes to go from `level` to the next: 4, 6, 8... up to 14.
static func xp_step(level: int) -> int:
	return mini(2 + 2 * level, 14)


## Total XP needed to reach `level`.
static func xp_for_level(level: int) -> int:
	var total := 0
	for k in range(1, level):
		total += xp_step(k)
	return total


static func level(member: Dictionary) -> int:
	var xp := float(member.get("xp", 0.0))
	var cap := max_level(member)
	var lv := 1
	while lv < cap and xp >= xp_for_level(lv + 1):
		lv += 1
	return lv


## 0..1 progress toward the next level (1 at the cap).
static func level_progress(member: Dictionary) -> float:
	var lv := level(member)
	if lv >= max_level(member):
		return 1.0
	var into := float(member.xp) - xp_for_level(lv)
	return clampf(into / xp_step(lv), 0.0, 1.0)


static func role_name(member: Dictionary) -> String:
	return str(ROLE_NAMES.get(str(member.get("role", "")), "Crew"))


static func color_of(member: Dictionary) -> Color:
	var rarity := str(member.get("rarity", "Common"))
	if rarity == "Mythic":
		return MYTHIC_COLOR
	return Parts.RARITY_COLORS.get(rarity, Color.WHITE)


static func describe(member: Dictionary) -> String:
	return "%s  %s %s  L%d" % [member.name, member.rarity, role_name(member), level(member)]


## Passive modifiers at the member's level:
##   turn, grip (Driver)   spread, aim, lock (Gunner)
static func passive(member: Dictionary) -> Dictionary:
	var r := rarity_index(member)
	var steps := level(member) - 1
	match str(member.role):
		"driver":
			return {
				"turn": float(DRIVER.turn[r]) + float(DRIVER.turn_per_level) * steps,
				"grip": float(DRIVER.grip[r]) + float(DRIVER.grip_per_level) * steps,
			}
		"gunner":
			return {
				"spread": float(GUNNER.spread[r]) + float(GUNNER.spread_per_level) * steps,
				"aim": float(GUNNER.aim[r]) + float(GUNNER.aim_per_level) * steps,
				"lock": float(GUNNER.lock[r]),
			}
	return {}


## The triggered ability: kind, duration, cooldown and its numbers.
static func ability(member: Dictionary) -> Dictionary:
	var r := rarity_index(member)
	match str(member.role):
		"driver":
			return {"kind": "hard_line", "time": float(DRIVER.hl_time[r]), "cooldown": float(DRIVER.hl_cooldown[r]),
				"turn": float(DRIVER.hl_turn[r]), "grip": float(DRIVER.hl_grip[r]), "speed": float(DRIVER.hl_speed[r])}
		"gunner":
			return {"kind": "overcharge", "time": float(GUNNER.oc_time[r]), "cooldown": float(GUNNER.oc_cooldown[r]),
				"fire": float(GUNNER.oc_fire[r]), "damage": float(GUNNER.oc_damage[r])}
	return {}


## One line on what the member does, for cards.
static func summary(member: Dictionary) -> String:
	var p := passive(member)
	var a := ability(member)
	match str(member.role):
		"driver":
			var spike := "    SPEED SPIKE +%d%%" % roundi(float(a.speed) * 100.0) if float(a.speed) > 0.0 else ""
			return "TURN +%d%%  GRIP +%.1f    HARD LINE %s s, every %d s%s" % [roundi(float(p.turn) * 100.0), float(p.grip), _secs(float(a.time)), roundi(float(a.cooldown)), spike]
		"gunner":
			var lock := "  LOCK +%d%%" % roundi(float(p.lock) * 100.0) if float(p.lock) > 0.0 else ""
			return "SPREAD -%d%%  AIM +%d%%%s    OVERCHARGE %s s, every %d s" % [roundi(float(p.spread) * 100.0), roundi(float(p.aim) * 100.0), lock, _secs(float(a.time)), roundi(float(a.cooldown))]
	return ""


static func _secs(v: float) -> String:
	return str(int(v)) if is_equal_approx(v, roundf(v)) else "%.1f" % v


## Seats a frame offers, in seat order (parts.gd "seats").
static func seats_for(loadout: Dictionary) -> Array[String]:
	var out: Array[String] = []
	var chassis := Parts.get_part(str(loadout.get("chassis", "")))
	for seat: String in chassis.get("seats", []):
		out.append(seat)
	return out


## Rig stats with the crew's passives folded in (Garage stat sheet). The
## mission applies the same numbers live in vehicle.gd.
static func apply_passives(stats: Dictionary, members: Array) -> Dictionary:
	var out := stats.duplicate(true)
	for m: Dictionary in members:
		var p := passive(m)
		match str(m.role):
			"driver":
				out.turn_rate = float(out.turn_rate) * (1.0 + float(p.turn))
				out.grip = float(out.grip) + float(p.grip)
			"gunner":
				var spread_mult := 1.0 - float(p.spread)
				var aim_mult := 1.0 + float(p.aim)
				for w: Dictionary in out.get("weapons", []):
					w.spread_deg = float(w.spread_deg) * spread_mult
					w.turret_turn_rate = float(w.turret_turn_rate) * aim_mult
				out.spread_deg = float(out.spread_deg) * spread_mult
				out.turret_turn_rate = float(out.turret_turn_rate) * aim_mult
				out.lock_range = float(out.lock_range) * (1.0 + float(p.lock))
	return out
