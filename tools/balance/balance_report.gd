extends SceneTree
## Balance report (headless, read-only: changes no numbers). Measures the
## design's combat contract and the economy at each skull level:
##   1. Focused time-to-wreck: a parked rig with the skull's whole Clear
##      roster (rigs + a full horde) spawned around it at once. DESIGN §
##      Combat Contract: 15 / 13 / 11 / 9 / 7.5 / 6 s at skulls 1-6.
##   2. Offense: seconds of perfect aim to strip that roster (sustained DPS
##      against total toughness), per build.
##   3. Economy: pay per job, kill scrap, and what builds and research cost.
##   4. Night (PR #69): every time-to-wreck cell again at night, the
##      NIGHT_WRECK_TIME_FLOOR check, and day vs night per district.
##
## Run:  godot --headless --fixed-fps 60 --path . -s res://tools/balance/balance_report.gd

const Mission := preload("res://scripts/mission.gd")
const Missions := preload("res://scripts/missions.gd")
const Loadout := preload("res://scripts/loadout.gd")
const Parts := preload("res://scripts/parts.gd")
const T := preload("res://scripts/tuning.gd")
const Layouts := preload("res://scripts/layouts.gd")

const TARGET := [15.0, 13.0, 11.0, 9.0, 7.5, 6.0]
const LIMIT := 120.0   # stop a run after this many seconds alive

const REPEATS := 15    # runs per cell (different seeds); the report shows the mean
# Builds that fit their power and weight budgets at their Research level.
const BUILDS := {
	"starter": {},
	"mid": {"chassis": "scrap_frame", "engine": "patched_v8", "drive": "street_wheels",
		"armor_front": "riot_plating", "armor_sides": "scrap_plating", "armor_rear": "scrap_plating",
		"weapons": ["burst_turret"], "utility": [], "internal": ["junk_emitter", "targeting_computer"]},
	"late": {"chassis": "bulwark_frame", "engine": "diesel_block", "drive": "half_track",
		"armor_front": "composite_plating", "armor_sides": "riot_plating", "armor_rear": "scrap_plating",
		"weapons": ["heavy_mg_turret"], "utility": [], "internal": ["capacitor_bank", "targeting_computer"]},
}
const LEVELS := {"starter": 1, "mid": 4, "late": 8}

var runs: Array = []   # [build, skulls, repeat, night]
var results := {}      # "build:skull[:night]" -> seconds
var main: Mission
var t := 0.0
var frame := 0
var cur: Array = []


func _initialize() -> void:
	var profile: Node = root.get_node("Profile")
	profile.set("persist", false)
	profile.call("new_game")
	for b: String in BUILDS:
		for s in range(1, 7):
			for r in REPEATS:
				runs.append([b, s, r, false])
				runs.append([b, s, r, true])
	_report_builds()


func _loadout(b: String) -> Dictionary:
	return Parts.STARTER_LOADOUT if (BUILDS[b] as Dictionary).is_empty() else BUILDS[b]


## Every part in build `b` at its Research level.
func _levels(b: String) -> Dictionary:
	var out := {}
	var l := _loadout(b)
	for slot: String in ["chassis", "engine", "drive", "armor_front", "armor_sides", "armor_rear"]:
		out[str(l.get(slot, ""))] = int(LEVELS[b])
	for list: String in ["weapons", "utility", "internal"]:
		for id: Variant in l.get(list, []):
			out[str(id)] = int(LEVELS[b])
	return out


func _stats(b: String) -> Dictionary:
	return Loadout.build(_loadout(b), _levels(b))


func _report_builds() -> void:
	print("\n== BUILDS (Research level 1)")
	for b: String in BUILDS:
		var s := _stats(b)
		var cost := 0
		for slot: String in ["chassis", "engine", "drive", "armor_front", "armor_sides", "armor_rear"]:
			cost += int(Parts.get_part(str(_loadout(b).get(slot, ""))).get("cost", 0))
		for list: String in ["weapons", "utility", "internal"]:
			for id: Variant in _loadout(b).get(list, []):
				cost += int(Parts.get_part(str(id)).get("cost", 0))
		print("  %-8s (level %d) toughness %4d + shield %3d   sustained DPS %5.1f   mobility %.2f   speed %d   build cost %d scrap" % [
			b, int(LEVELS[b]), int(Loadout.toughness(s)), int(s.shield), Loadout.total_dps(s), Loadout.mobility(s), int(s.max_speed), cost])


func _process(delta: float) -> bool:
	frame += 1
	if main == null:
		if runs.is_empty():
			_report()
			quit(0)
			return true
		cur = runs.pop_front()
		seed(1000 * int(cur[1]) + 77 * int(cur[2]) + 1)
		_start(str(cur[0]), int(cur[1]), bool(cur[3]))
		return false
	if frame == 3:
		_spawn_roster(int(cur[1]))
		t = 0.0
		return false
	if frame > 3:
		t += delta
		if main.vehicle.is_wrecked or t >= LIMIT:
			var key := "%s:%d%s" % [cur[0], cur[1], ":night" if bool(cur[3]) else ""]
			var list: Array = results.get(key, [])
			list.append(t if main.vehicle.is_wrecked else LIMIT)
			results[key] = list
			main.free()
			main = null
	return false


func _start(b: String, skulls: int, night := false) -> void:
	main = (load("res://scenes/mission.tscn") as PackedScene).instantiate() as Mission
	var spec := Missions.make("clear", skulls, 4242)
	spec["night"] = night
	main.mission_override = spec
	main.auto_spawn_specials = false
	root.add_child(main)
	main.apply_rig(_stats(b))
	frame = 0


## The skull's Clear roster, all at once, around the parked rig.
func _spawn_roster(skulls: int) -> void:
	main.zombies.spawn_budget = 0
	main.zombies.clear_all()
	for barrel in main.barrels:
		barrel.deactivate()
	var rig := main.vehicle
	rig.velocity = Vector2.ZERO
	main.hud.left_stick.output = Vector2.ZERO
	main.hud.right_stick.output = Vector2.ZERO
	var at := rig.global_position
	var spec := main.spec
	var n := 0
	for kind: String in ["bulwarks", "gunners", "outriders", "scrappers"]:
		for i in int(Missions.stat(spec, kind)):
			var p := main._open_spot(380.0 + 30.0 * n)
			match kind:
				"bulwarks":
					main.spawn_bulwark(p)
				"gunners":
					main.spawn_gunner(p)
				"outriders":
					main.spawn_outrider(p)
				"scrappers":
					main.spawn_scrapper(p)
			n += 1
	var cap := main.zombies.cap   # the job's horde, smaller at 1-2 skulls
	for i in cap:
		var kind := "shambler"
		var roll := randf()
		var acc := 0.0
		for k: String in T.ZOMBIE_MIX:
			acc += float(T.ZOMBIE_MIX[k][skulls - 1])
			if roll < acc:
				kind = k
				break
		main.zombies.spawn_at(main._open_spot(240.0 + 8.0 * i), kind)
	for i in int(Missions.stat(spec, "hunters")):
		main.spawn_hunter(main._open_spot(300.0))


func _report() -> void:
	print("\n== FOCUSED TIME-TO-WRECK, mean of %d runs (parked, whole Clear roster at once; target 15/13/11/9/7.5/6 s)" % REPEATS)
	var line := "  skulls     "
	for s in range(1, 7):
		line += "%8d" % s
	print(line)
	line = "  target     "
	for s in range(1, 7):
		line += "%8.1f" % TARGET[s - 1]
	print(line)
	for b: String in BUILDS:
		line = "  %-10s " % b
		for s in range(1, 7):
			var list: Array = results.get("%s:%d" % [b, s], [])
			var sum := 0.0
			for v: float in list:
				sum += v
			line += "%8.1f" % (sum / maxf(list.size(), 1))
		print(line)

	print("\n== OFFENSE (seconds of perfect aim to strip the whole Clear roster, sustained DPS)")
	print(line.substr(0, 0) + "  skulls       1       2       3       4       5       6")
	for b: String in BUILDS:
		var dps := Loadout.total_dps(_stats(b))
		line = "  %-10s " % b
		for s in range(1, 7):
			line += "%8.0f" % (_roster_toughness(s) / maxf(dps, 0.1))
		print(line)
	line = "  roster hp  "
	for s in range(1, 7):
		line += "%8d" % int(_roster_toughness(s))
	print(line)

	print("\n== ECONOMY")
	line = "  avg job pay      "
	var pays: Array[float] = []
	for s in range(1, 7):
		var sum := 0.0
		for type: String in T.MISSIONS:
			sum += float((T.MISSIONS[type].reward as Array)[s - 1])
		pays.append(sum / T.MISSIONS.size())
		line += "%8d" % int(pays[s - 1])
	print(line)
	line = "  clear kill scrap "
	for s in range(1, 7):
		line += "%8d" % int(_kill_scrap(s))
	print(line)
	print("  research one level: Common %d, Uncommon %d, Rare %d (x the level)" % [T.RESEARCH_COST_BASE.Common, T.RESEARCH_COST_BASE.Uncommon, T.RESEARCH_COST_BASE.Rare])
	print("  district needs: %s" % str(T.DISTRICTS.map(func(d: Dictionary) -> String: return "%s %d" % [d.name, int(d.need)])))
	_report_night(pays)


## Share of a district's board that's night (after 3 clears): every job
## type alike, skulls weighted by SKULL_WEIGHTS, 1 skull never night, using
## Missions.night_chance (the district, Courier, Escort and Survive/Hunt rules).
func _night_share(i: int) -> float:
	var dist: Dictionary = T.DISTRICTS[i]
	var lo := int(dist.skulls[0])
	var hi := int(dist.skulls[1])
	var sum := 0.0
	var wsum := 0.0
	for type: String in Missions.TYPES:
		var layout := ""
		for id: String in Layouts.LAYOUTS:
			if str(Layouts.LAYOUTS[id].get("district", "")) == str(dist.id) and (Layouts.LAYOUTS[id].jobs as Array).has(type):
				layout = id
				break
		if layout == "":
			continue
		for s in range(lo, hi + 1):
			var w := float(T.SKULL_WEIGHTS[mini(s - lo, T.SKULL_WEIGHTS.size() - 1)])
			var job := Missions.make(type, s, 1)
			job["layout"] = layout
			wsum += w
			sum += w * (Missions.night_chance(job) if s >= T.NIGHT_MIN_SKULLS else 0.0)
	return sum / maxf(wsum, 1.0)


func _mean(key: String) -> float:
	var list: Array = results.get(key, [])
	var sum := 0.0
	for v: float in list:
		sum += v
	return sum / maxf(list.size(), 1)


func _report_night(pays: Array[float]) -> void:
	print("\n== NIGHT TIME-TO-WRECK, mean of %d runs (same roster at night; floor %.0f%% of day)" % [REPEATS, T.NIGHT_WRECK_TIME_FLOOR * 100.0])
	var fails: Array[String] = []
	for b: String in BUILDS:
		var line := "  %-10s " % (b + " n")
		var ratio := "  %-10s " % (b + " n/d")
		for s in range(1, 7):
			var d := _mean("%s:%d" % [b, s])
			var n := _mean("%s:%d:night" % [b, s])
			line += "%8.1f" % n
			var r := n / maxf(d, 0.01)
			ratio += "%7.0f%%" % (r * 100.0)
			# A cell where both runs hit the time limit can't fail the floor.
			if s >= T.NIGHT_MIN_SKULLS and r < T.NIGHT_WRECK_TIME_FLOOR and d < LIMIT:   # never night at 1 skull
				fails.append("%s %d skulls (%.0f%%)" % [b, s, r * 100.0])
		print(line)
		print(ratio)
	print("  floor check: %s" % ("PASS" if fails.is_empty() else "FAIL " + ", ".join(fails)))

	print("\n== DAY VS NIGHT BY DISTRICT (skulls weighted by SKULL_WEIGHTS inside the band; Clear kill scrap)")
	print("  district           night%   build    ttw day  ttw night  ratio   income day  income night  expected")
	for i in T.DISTRICTS.size():
		var dist: Dictionary = T.DISTRICTS[i]
		var lo := int(dist.skulls[0])
		var hi := int(dist.skulls[1])
		var chance := _night_share(i)
		for b: String in BUILDS:
			var wsum := 0.0
			var dt := 0.0
			var nt := 0.0
			var di := 0.0
			var ni := 0.0
			for s in range(lo, hi + 1):
				var w := float(T.SKULL_WEIGHTS[mini(s - lo, T.SKULL_WEIGHTS.size() - 1)])
				wsum += w
				dt += w * _mean("%s:%d" % [b, s])
				nt += w * _mean("%s:%d:night" % [b, s])
				di += w * (pays[s - 1] + _kill_scrap(s))
				ni += w * (roundi(pays[s - 1] * T.NIGHT_PAYOUT_MULT) + _kill_scrap(s, true))
			dt /= wsum
			nt /= wsum
			di /= wsum
			ni /= wsum
			print("  %-18s %5.0f%%   %-8s %7.1f  %9.1f  %4.0f%%  %11.0f  %12.0f  %8.0f" % [
				str(dist.name), chance * 100.0, b, dt, nt, nt / maxf(dt, 0.01) * 100.0, di, ni, di + chance * (ni - di)])


func _sheet(kind: String) -> Dictionary:
	match kind:
		"outriders":
			return T.OUTRIDER
		"bulwarks":
			return T.BULWARK
		"gunners":
			return T.GUNNER
		"scrappers":
			return T.SCRAPPER
	return {}


func _roster_toughness(skulls: int) -> float:
	var spec := Missions.make("clear", skulls, 4242)
	var total := 0.0
	for kind: String in ["bulwarks", "gunners", "outriders", "scrappers"]:
		var s := _sheet(kind)
		var shield := float(s.get("shield", 0.0)) if skulls >= int(s.get("shield_skulls", 0)) else 0.0
		total += int(Missions.stat(spec, kind)) * (Loadout.toughness(s) + shield)
	var cap := int(Missions.stat(spec, "cap"))
	var zhp := 0.0
	for k: String in T.ZOMBIE_KINDS:
		var share := float(T.ZOMBIE_MIX.get(k, [0, 0, 0, 0, 0, 0])[skulls - 1]) if k != "shambler" and k != "tank" else 0.0
		zhp += share * float(T.ZOMBIE_KINDS[k].hp)
	var others := 0.0
	for k: String in T.ZOMBIE_MIX:
		others += float(T.ZOMBIE_MIX[k][skulls - 1])
	zhp += (1.0 - others) * float(T.ZOMBIE_KINDS.shambler.hp)
	return total + cap * zhp


func _kill_scrap(skulls: int, night := false) -> float:
	var spec := Missions.make("clear", skulls, 4242)
	var s := float(Missions.stat(spec, "shamblers")) * Missions.night_kill_scrap(T.SCRAP_PER_KILL, night)
	s += int(Missions.stat(spec, "hunters")) * Missions.night_kill_scrap(T.HUNTER_SCRAP, night)
	s += int(Missions.stat(spec, "outriders")) * T.OUTRIDER_SCRAP + int(Missions.stat(spec, "bulwarks")) * T.BULWARK_SCRAP
	s += int(Missions.stat(spec, "gunners")) * T.GUNNER_SCRAP + int(Missions.stat(spec, "scrappers")) * T.SCRAPPER_SCRAP
	return s
