extends Node
## The player's persistent state (autoload "Profile"): scrap, owned schematics,
## built parts in storage, the rig in the garage, presets, garage upgrades.
## Saved as JSON in user:// after every change.
##
## Economy rules (decided with the owner):
## - Scrap is the only currency.
## - Owning a schematic means you can build that part any time, for scrap.
##   Common parts are free to build, so a basic rig is always within reach.
## - A rig is paid for once, when its parts are built. Parts you swap out go
##   to storage, so putting them back later is free.
## - A wreck destroys the rig and every part on it, and costs a scrap penalty
##   scaled to the lost build's value (DESIGN §4). Schematics and storage
##   survive. Scrap and schematics picked up during that run are lost.
## - You never get a schematic you already own: drops skip known ones.
##
## Research rules (decided with the owner):
## - A level belongs to the schematic, so every copy you build has it and a
##   wreck never takes it away. Build cost and the wreck penalty ignore it.
## - A level costs T.RESEARCH_COST_BASE[rarity] x the level you're buying,
##   less the Bench Discount. It's instant, but only T.RESEARCH_DAILY_CAP
##   levels a day (Second Shift adds one per step).
## - Max level by rarity is T.RESEARCH_MAX_LEVEL; upgrades never raise it.
##
## Crew rules (decided with the owner, "Helriders: Crew Draft" doc):
## - Seats depend on the frame: Driver and Gunner seats, plus open seats any
##   other class can take, one of each class aboard. A Driver is required to
##   deploy; a turret needs a seated Gunner or a targeting computer to aim.
## - Every 3rd level a crew member offers 3 random perks from their class
##   pool; you pick 1.
## - A job's XP (its skulls) is split evenly among the crew on the rig.
## - Big hits mid-fight can injure crew; injured crew rest at the Inn after
##   the run and can't be seated until healed.
## - A wreck kills everyone seated. Crew at the Inn are safe. Quitting
##   mid-run costs only the day.
## - The Saloon always has a free Common Driver and Gunner, so you can never
##   get stuck; its daily paid offers roll rarity by T.SALOON_ODDS.
##
## Expedition rules (decided with the owner):
## - The Inn's expedition board opens after T.EXPEDITION_UNLOCK_CLEARS
##   successful missions. It shows T.EXPEDITION_BOARD_SIZE named trips a day,
##   each with skulls (1-6), a length (1-3 days) and maybe a bonus find.
## - Send 1 to T.EXPEDITION_MAX_TEAM benched crew (not seated, not resting).
##   Their total level against the trip's recommended level sets the odds,
##   which you see before sending. Away crew can't be seated, dismissed or
##   recalled; they don't get Drill Yard XP.
## - Success pays scrap and XP (skulls x days, split) and rolls the bonus
##   find (a new schematic or a recruit). Failure brings back part of it, and
##   each member may come home injured. Nobody is ever lost.
## - Last Rites (Inn upgrade, once Industrial Spine is open): on a wreck each
##   seated crew member may survive, injured.

signal changed

const T := preload("res://scripts/tuning.gd")
const Parts := preload("res://scripts/parts.gd")
const Loadout := preload("res://scripts/loadout.gd")
const Missions := preload("res://scripts/missions.gd")
const Crew := preload("res://scripts/crew.gd")
const Layouts := preload("res://scripts/layouts.gd")
const LOST_DAYS := T.LOST_RETURN_DAYS

const SAVE_VERSION := 1
const SINGLE_SLOTS := ["chassis", "engine", "drive", "armor_front", "armor_sides", "armor_rear"]
const LIST_SLOTS := ["weapons", "utility", "internal"]
const REQUIRED_SLOTS := ["chassis", "engine", "drive"]

var persist := true                 # tests switch this off: no disk writes
var save_path := "user://helriders_save.json"
var scrap := 0
var schematics: Array[String] = []
var storage := {}                   # part id -> number of built spares
var rig := {}                       # the loadout in the garage (may be incomplete)
var plan := {}                      # the last complete rig, for one-tap rebuild
var presets: Array = []             # loadout dictionaries or null
var preset_names: Array = []        # the player's name for each preset ("" = P1, P2...)
var upgrades := _no_upgrades()
var levels := {}                    # schematic id -> Research level (absent = 1)
var research_today := 0             # levels bought today (daily cap)
var record := {"runs": 0, "clears": 0, "wrecks": 0}
var day := 1
var board: Array = []               # today's missions on the Comms board
var active_mission := {}            # the one you took; DEPLOY runs it
var run_active := false             # a mission is under way (saved, so a quit counts)
var notice := ""                    # one-time message for the garage to show
var crew: Array = []                # the roster (crew.gd dictionaries)
var next_crew_id := 1
var saloon: Array = []              # today's paid offers: crew dictionaries + "price", "hired"
var saloon_day := 0
var exp_board: Array = []           # today's expedition offers
var exp_board_day := 0
var expeditions: Array = []         # trips under way: offer + "team" ids + "days_left" + "odds"
var expedition_reports: Array = []  # lines about the trips that came back last
var last_wreck_survivors: Array[String] = []  # names Last Rites saved on the last wreck
var wreck_day := 0                # the day of the last wreck (Extract or Push skips the day after)
var discovered := {}                # Database: category -> ids the player has met
var settings := {}                  # quality, shake, music, effects (own file; survives new games)
var settings_path := "user://helriders_settings.cfg"
var tutorial_active := false        # the next mission is the Training Run (not saved)
var tour_active := false            # the garage tour after it runs on a sandbox copy
var _tour_snapshot := {}
var _tour_persist := true
var lost: Array = []                # crew lost in wrecks, on their way back: member + "back_in" days
var rehire_pool: Array = []         # lost crew who turned up again (level 1, perks reset)
var rehire_day := 0                 # the day today's rehire card was drawn
var rehire_pick := -1               # id of today's rehire card (-1 = none)
var rehire_taken := false           # hired today
var roll_override := -1.0           # tests: 0..1 replaces every expedition/Last Rites roll
var luck := RandomNumberGenerator.new()  # expedition and Last Rites rolls
var _ready_state := false           # set once a game is loaded or started


func _ready() -> void:
	# Tests may have started a game before the autoload is ready; keep it.
	if not _ready_state and not load_game():
		new_game()
	load_settings()
	# The app was closed during a mission: the garage sends you straight back
	# into the same job, the fight reset (resume_job()). Nothing is lost.


func new_game() -> void:
	_ready_state = true
	remove_meta(&"crew_seen_level")   # V6.5: crew_card.gd SEEN_META; no level-up flash carried over
	scrap = T.START_SCRAP
	schematics.clear()
	for id: String in Parts.STARTER_SCHEMATICS:
		schematics.append(id)
	storage = {}
	rig = Parts.STARTER_LOADOUT.duplicate(true)
	plan = rig.duplicate(true)
	presets = []
	presets.resize(T.PRESET_COUNT)
	preset_names = []
	preset_names.resize(T.PRESET_COUNT)
	preset_names.fill("")
	upgrades = _no_upgrades()
	levels = {}
	research_today = 0
	record = {"runs": 0, "clears": 0, "wrecks": 0}
	notice = ""
	day = 1
	active_mission = {}
	run_active = false
	board = Missions.make_board(day, board_size(), 0, board_district())
	_starter_crew()
	saloon_day = 0
	ensure_saloon()
	exp_board = []
	exp_board_day = 0
	expeditions = []
	expedition_reports = []
	last_wreck_survivors = []
	wreck_day = 0
	discovered = {}
	lost = []
	rehire_pool = []
	rehire_day = 0
	rehire_pick = -1
	rehire_taken = false
	save_game()


static func _no_upgrades() -> Dictionary:
	var out := {}
	for key: String in T.UPGRADES:
		out[key] = 0
	return out


## DESIGN §11: a new game starts with a free Common Driver and Gunner, seated.
func _starter_crew() -> void:
	crew = []
	next_crew_id = 1
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("helriders-starter-crew")
	for pair: Array in [["driver", "wheelman"], ["gunner", "gunslinger"]]:
		var m := _add_crew(Crew.make(pair[0], "Common", rng, pair[1]))
		m.seated = true


# --- Loadouts -------------------------------------------------------------------

static func empty_loadout() -> Dictionary:
	return {"chassis": "", "engine": "", "drive": "", "armor_front": "", "armor_sides": "", "armor_rear": "",
		"weapons": [], "utility": [], "internal": []}


## Every part id in a loadout, one entry per installed part.
static func parts_in(loadout: Dictionary) -> Array[String]:
	var out: Array[String] = []
	for key in SINGLE_SLOTS:
		var id: String = loadout.get(key, "")
		if id != "":
			out.append(id)
	for key in LIST_SLOTS:
		for id: String in loadout.get(key, []):
			if id != "":
				out.append(id)
	return out


static func is_complete(loadout: Dictionary) -> bool:
	for key in REQUIRED_SLOTS:
		if str(loadout.get(key, "")) == "":
			return false
	return true


func has_rig() -> bool:
	return is_complete(rig)


## How many slots of a list type the loadout's chassis offers.
static func slot_count(loadout: Dictionary, key: String) -> int:
	var chassis := Parts.get_part(loadout.get("chassis", ""))
	match key:
		"weapons":
			return int(chassis.get("hardpoints", 0))
		"utility":
			return int(chassis.get("utility_slots", 0))
		"internal":
			return int(chassis.get("internal_slots", 0))
	return 1


## A copy of `loadout` with one slot changed. id "" empties the slot.
## List slots beyond the (possibly new) chassis's capacity are dropped.
static func with_part(loadout: Dictionary, key: String, index: int, id: String) -> Dictionary:
	var out := empty_loadout()
	for k in SINGLE_SLOTS:
		out[k] = loadout.get(k, "")
	for k in LIST_SLOTS:
		out[k] = (loadout.get(k, []) as Array).duplicate()
	if key in SINGLE_SLOTS:
		out[key] = id
	else:
		var list: Array = out[key]
		if index < list.size():
			if id == "":
				list.remove_at(index)
			else:
				list[index] = id
		elif id != "":
			list.append(id)
	for k in LIST_SLOTS:
		var list: Array = out[k]
		var cap := slot_count(out, k)
		while list.size() > cap:
			list.pop_back()
	return out


# --- Costs ------------------------------------------------------------------------

func fab_cost(id: String) -> int:
	var part := Parts.get_part(id)
	if part.get("rarity", "") == "Common":
		return 0
	return roundi(float(part.get("cost", 0)) * fab_mult())


## What a build is worth: every part at its listed cost, Commons included.
## The wreck penalty is a share of this.
static func build_value(loadout: Dictionary) -> int:
	var value := 0
	for id in parts_in(loadout):
		value += int(Parts.get_part(id).get("cost", 0))
	return value


func wreck_penalty(loadout: Dictionary) -> int:
	return mini(scrap, roundi(build_value(loadout) * T.WRECK_PENALTY))


## Schematics from `pool` you don't own yet (and aren't in `pending`).
func unknown_schematics(pool: Array, pending: Array = []) -> Array[String]:
	var out: Array[String] = []
	for id: String in pool:
		if not schematics.has(id) and not pending.has(id):
			out.append(id)
	return out


func fab_mult() -> float:
	return 1.0 - float(T.UPGRADES.fabrication.per_level) * int(upgrades.fabrication)


func salvage_mult() -> float:
	return 1.0 + float(T.UPGRADES.salvage.per_level) * int(upgrades.salvage)


func schematic_chance() -> float:
	return minf(T.SCHEMATIC_DROP_CHANCE + float(T.UPGRADES.loot.per_level) * int(upgrades.loot), 0.95)


## Parts you'd have on hand for a rebuild: what's on the rig plus storage.
func _on_hand() -> Dictionary:
	var have: Dictionary = storage.duplicate()
	for id in parts_in(rig):
		have[id] = int(have.get(id, 0)) + 1
	return have


## Scrap needed to turn the current rig into `target`. Parts already on the
## rig or in storage are free; everything else gets built.
func build_cost(target: Dictionary) -> int:
	var have := _on_hand()
	var cost := 0
	for id in parts_in(target):
		if int(have.get(id, 0)) > 0:
			have[id] = int(have[id]) - 1
		else:
			cost += fab_cost(id)
	return cost


func knows_all(target: Dictionary) -> bool:
	for id in parts_in(target):
		if not schematics.has(id):
			return false
	return true


## Make `target` the rig: build what's missing, store what comes off.
## Returns false (and changes nothing) if it costs more scrap than you have.
func apply_loadout(target: Dictionary) -> bool:
	if not knows_all(target):
		return false
	var cost := build_cost(target)
	if cost > scrap:
		return false
	var have := _on_hand()
	for id in parts_in(target):
		if int(have.get(id, 0)) > 0:
			have[id] = int(have[id]) - 1
	var leftover := {}
	for id: String in have:
		if int(have[id]) > 0:
			leftover[id] = int(have[id])
	scrap -= cost
	storage = leftover
	rig = target.duplicate(true)
	if is_complete(rig):
		plan = rig.duplicate(true)
	_fit_seats()
	save_game()
	changed.emit()
	return true


# --- Runs ---------------------------------------------------------------------------

func start_run() -> void:
	if not run_active:   # a restart or a relaunch mid-job is the same run
		record.runs = int(record.runs) + 1
	run_active = true
	if not active_mission.is_empty():
		discover("jobs", str(active_mission.get("type", "")))
	save_game()


## Closed or quit mid-job: on the next launch the garage drops you back into
## it, the fight reset.
func resume_job() -> bool:
	return run_active and has_mission()


# --- Days, the board, districts --------------------------------------------------

func board_size() -> int:
	return T.BOARD_SIZE + int(upgrades.get("choices", 0))


func ensure_board() -> void:
	if board.size() != board_size():
		board = Missions.make_board(day, board_size(), int(upgrades.get("quality", 0)), board_district())


func choose_mission(index: int) -> void:
	ensure_board()
	if index < 0 or index >= board.size():
		return
	active_mission = (board[index] as Dictionary).duplicate(true)
	save_game()
	changed.emit()


func has_mission() -> bool:
	return not active_mission.is_empty()


## A mission ended (cleared, wrecked or abandoned): one day per mission.
func finish_day() -> void:
	run_active = false
	for m: Dictionary in crew:
		m.rest = maxi(int(m.rest) - 1, 0)
	day += 1
	research_today = 0
	active_mission = {}
	board = Missions.make_board(day, board_size(), int(upgrades.get("quality", 0)), board_district())
	_advance_lost()
	ensure_saloon()
	_advance_expeditions()
	save_game()
	changed.emit()


## DESIGN §7: extracted parts only (starter schematics don't count),
## rarity points x Research level.
func district_score() -> int:
	var starter: Array = Parts.STARTER_SCHEMATICS
	var score := 0
	for id in schematics:
		if starter.has(id):
			continue
		score += int(T.RARITY_POINTS.get(str(Parts.get_part(id).get("rarity", "")), 0)) * part_level(id)
	return score


# --- Research -------------------------------------------------------------------

## A schematic's Research level (1 until researched).
func part_level(id: String) -> int:
	return int(levels.get(id, 1))


## The part as you'd build it: its stats at your Research level.
func part(id: String) -> Dictionary:
	return Parts.at_level(Parts.get_part(id), part_level(id))


## Rig stats for `loadout` with your Research levels applied.
func build_stats(loadout: Dictionary) -> Dictionary:
	return Loadout.build(loadout, levels)


func research_cap() -> int:
	return T.RESEARCH_DAILY_CAP + int(T.UPGRADES.research_speed.per_level) * upgrade_level("research_speed")


func research_left() -> int:
	return maxi(research_cap() - research_today, 0)


## Scrap for the next level of `id`, or -1 if it can't go higher.
func research_cost(id: String) -> int:
	var p := Parts.get_part(id)
	var next := part_level(id) + 1
	if not Parts.can_level(p) or next > Parts.max_level(p):
		return -1
	var base := float(T.RESEARCH_COST_BASE.get(str(p.rarity), 0))
	var discount := float(T.UPGRADES.research_discount.per_level) * upgrade_level("research_discount")
	return roundi(base * next * (1.0 - discount))


## Why `id` can't be levelled right now, or "".
func research_block(id: String) -> String:
	if not schematics.has(id):
		return "NOT OWNED"
	var p := Parts.get_part(id)
	if not Parts.can_level(p):
		return "NOTHING TO IMPROVE"
	if part_level(id) >= Parts.max_level(p):
		return "MAX LEVEL"
	if research_left() <= 0:
		return "DONE FOR TODAY"
	if research_cost(id) > scrap:
		return "NEED %d SCRAP" % research_cost(id)
	return ""


## Level `id` up by one. Returns success.
func research(id: String) -> bool:
	if research_block(id) != "":
		return false
	scrap -= research_cost(id)
	levels[id] = part_level(id) + 1
	research_today += 1
	save_game()
	changed.emit()
	return true


## The furthest district open: the board rolls its skull band and may use
## layouts from it and every district before it.
func board_district() -> String:
	var id := str(T.DISTRICTS[0].id)
	for i in T.DISTRICTS.size():
		if is_district_open(i):
			id = str(T.DISTRICTS[i].id)
	return id


func is_district_open(index: int) -> bool:
	return district_score() >= int(T.DISTRICTS[index].need)


## Extracted: bank the run's scrap and schematics. Returns a report for the
## results card. Drops never repeat a known schematic, so all are new.
func bank_run(run_scrap: int, salvaged: Array[String], cleared := true) -> Dictionary:
	var unlocked: Array[String] = []
	for id in salvaged:
		if not schematics.has(id):
			schematics.append(id)
			unlocked.append(id)
	scrap += run_scrap
	if cleared:   # a failed job (the truck lost) banks its haul but isn't a clear
		record.clears = int(record.clears) + 1
	save_game()
	changed.emit()
	return {"scrap": run_scrap, "unlocked": unlocked}


## Wrecked: the rig and every part on it are gone and everyone seated dies.
## The scrap penalty (T.WRECK_PENALTY x build value) is 0 now. Returns the
## penalty paid.
func record_wreck() -> int:
	record.wrecks = int(record.wrecks) + 1
	wreck_day = day
	var penalty := wreck_penalty(rig)
	scrap -= penalty
	if is_complete(rig):
		plan = rig.duplicate(true)
	rig = empty_loadout()
	last_wreck_survivors = []
	var chance := float(T.UPGRADES.last_rites.per_level) * upgrade_level("last_rites")
	for m: Dictionary in crew:
		if bool(m.seated) and chance > 0.0 and _roll() < chance:
			m.seated = false
			m.rest = T.LAST_RITES_REST
			last_wreck_survivors.append(str(m.name))
	for m: Dictionary in crew:
		if bool(m.seated) and LOST_DAYS.has(str(m.rarity)):
			var gone := (m as Dictionary).duplicate(true)
			gone["back_in"] = int(LOST_DAYS[str(m.rarity)])
			lost.append(gone)
	crew = crew.filter(func(m: Dictionary) -> bool: return not bool(m.seated))
	save_game()
	changed.emit()
	return penalty


# --- Crew ---------------------------------------------------------------------------

func _add_crew(member: Dictionary) -> Dictionary:
	discover("crew", Crew.specialty(member))
	var m := member.duplicate(true)
	m.erase("price")
	m.erase("hired")
	m.id = next_crew_id
	next_crew_id += 1
	m.seated = false
	m.rest = 0
	crew.append(m)
	return m


func member(id: int) -> Dictionary:
	for m: Dictionary in crew:
		if int(m.id) == id:
			return m
	return {}


## Seats the rig's frame offers: "driver", "gunner", "open".
func seats(loadout: Dictionary = {}) -> Array[String]:
	return Crew.seats_for(rig if loadout.is_empty() else loadout)


## Who rides as `role` (any class), or {}.
func seated_in(role: String) -> Dictionary:
	for m: Dictionary in crew:
		if bool(m.seated) and str(m.role) == role:
			return m
	return {}


## Crew riding the rig, in seat order: Driver, Gunner, then the open seats
## (by class order). With `loadout`, only those that frame has seats for (the
## Garage previews a frame swap with this).
func seated_crew(loadout: Dictionary = {}) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var open := seats(loadout)
	var free := open.count("open")
	for role: String in Crew.CLASSES:
		var m := seated_in(role)
		if m.is_empty():
			continue
		if role in ["driver", "gunner"]:
			if open.has(role):
				out.append(m)
		elif free > 0:
			out.append(m)
			free -= 1
	return out


func open_seats_used() -> int:
	var used := 0
	for m: Dictionary in crew:
		if bool(m.seated) and Crew.OPEN_CLASSES.has(str(m.role)):
			used += 1
	return used


func is_resting(m: Dictionary) -> bool:
	return int(m.get("rest", 0)) > 0


func roster_cap() -> int:
	return T.ROSTER_SIZE + int(T.UPGRADES.bunkhouse.per_level) * upgrade_level("bunkhouse")


func roster_full() -> bool:
	return crew.size() >= roster_cap()


## The free Saloon hire fits up to one past the roster cap.
func can_hire_basic() -> bool:
	return crew.size() < roster_cap() + 1


## Why crew member `m` can't be seated on this frame, or "".
func seat_block(m: Dictionary) -> String:
	if is_away(m):
		return "ON EXPEDITION"
	if is_resting(m):
		return "RESTING"
	var role := str(m.role)
	var open := seats()
	if role in ["driver", "gunner"]:
		return "" if open.has(role) else "NO %s SEAT" % role.to_upper()
	if open.count("open") == 0:
		return "NO OPEN SEAT"
	if seated_in(role).is_empty() and open_seats_used() >= open.count("open"):
		return "OPEN SEATS FULL"
	return ""


## Put crew member `id` on the rig. A Driver or Gunner takes that seat; any
## other class takes an open seat, swapping out a seated crew member of the
## same class (one of each class aboard). Fails if there's no seat for them
## or they're resting.
func seat_member(id: int) -> bool:
	var m := member(id)
	if m.is_empty() or seat_block(m) != "":
		return false
	var current := seated_in(str(m.role))
	if not current.is_empty():
		current.seated = false
	m.seated = true
	save_game()
	changed.emit()
	return true


func unseat_member(id: int) -> void:
	var m := member(id)
	if m.is_empty():
		return
	m.seated = false
	save_game()
	changed.emit()


## Gone for good, no refund.
func dismiss(id: int) -> bool:
	if is_away(member(id)):
		return false
	var before := crew.size()
	crew = crew.filter(func(m: Dictionary) -> bool: return int(m.id) != id)
	if crew.size() == before:
		return false
	save_game()
	changed.emit()
	return true


## Seats the new frame doesn't have send their crew back to the Inn.
func _fit_seats() -> void:
	var open := seats()
	var free := open.count("open")
	for role: String in Crew.CLASSES:
		var m := seated_in(role)
		if m.is_empty():
			continue
		if role in ["driver", "gunner"]:
			if not open.has(role):
				m.seated = false
		elif free > 0:
			free -= 1
		else:
			m.seated = false


## A fresh hire takes an empty seat for their class, if the frame has one.
func _auto_seat(m: Dictionary) -> void:
	if seated_in(str(m.role)).is_empty() and seat_block(m) == "":
		m.seated = true


## Why the rig can't deploy with this crew, or "" if it can.
func deploy_block() -> String:
	if seated_in("driver").is_empty():
		return "No Driver seated. Seat one at the Inn, or hire a free one at the Saloon."
	var stats := build_stats(rig)
	if bool(stats.has_turret) and not bool(stats.manual_aim) and seated_in("gunner").is_empty():
		return "The turret has no one to aim it. Seat a Gunner, or fit a Targeting Computer."
	return ""


# --- Perks ---

## The 3 perks on offer for `m`, rolling them if a pick is due; [] if none.
func perk_offer(m: Dictionary) -> Array[String]:
	var out: Array[String] = []
	if Crew.perks_due(m) <= 0:
		return out
	if (m.get("perk_offer", []) as Array).is_empty():
		m.perk_offer = Crew.roll_perk_offer(m)
		save_game()
	for p: String in m.perk_offer:
		out.append(p)
	return out


## Take perk `perk` from crew member `id`'s current offer.
func choose_perk(id: int, perk: String) -> bool:
	var m := member(id)
	if m.is_empty() or not perk_offer(m).has(perk):
		return false
	(m.perks as Array).append(perk)
	m.perk_offer = []
	save_game()
	changed.emit()
	return true


func perks_waiting() -> int:
	var n := 0
	for m: Dictionary in crew:
		n += Crew.perks_due(m)
	return n


## Today's Saloon offers (seeded by the day, like the job board).
## Today's Saloon offers (seeded by the day, like the job board). Back Room
## bought mid-day adds offers without changing the ones already there.
func ensure_saloon() -> void:
	var count := saloon_offers()
	if saloon_day == day and saloon.size() == count:
		return
	var keep := saloon_day == day and saloon.size() < count
	var dice := RandomNumberGenerator.new()
	dice.seed = hash("helriders-saloon-%d" % day)
	var fresh: Array = []
	for i in count:
		var role: String = Crew.CLASSES[dice.randi_range(0, Crew.CLASSES.size() - 1)]
		var rarity := _roll_rarity(dice, upgrade_level("word_around"))
		var m := Crew.make(role, rarity, dice)
		m["price"] = int(T.CREW_PRICES[rarity])
		m["hired"] = false
		m.xp = hire_start_xp(m)
		fresh.append(m)
	if keep:
		for i in range(saloon.size(), count):
			saloon.append(fresh[i])
	else:
		saloon = fresh
	saloon_day = day


func saloon_offers() -> int:
	return T.SALOON_OFFERS + int(T.UPGRADES.back_room.per_level) * upgrade_level("back_room")


## The Saloon's offer odds (percent by rarity) with Word Gets Around applied.
static func saloon_odds(step: int) -> Dictionary:
	var odds: Dictionary = T.SALOON_ODDS.duplicate()
	for r: String in T.SALOON_ODDS_STEP:
		odds[r] = maxf(float(odds[r]) + float(T.SALOON_ODDS_STEP[r]) * step, 0.0)
	return odds


static func _roll_rarity(dice: RandomNumberGenerator, step := 0) -> String:
	var odds := saloon_odds(step)
	var total := 0.0
	for r: String in odds:
		total += float(odds[r])
	var roll := dice.randf() * total
	for r: String in odds:
		roll -= float(odds[r])
		if roll < 0.0:
			return r
	return "Uncommon"


## XP a new hire starts with: Seasoned Hands sets the level (capped by rarity).
func hire_start_xp(m: Dictionary) -> float:
	var lv := mini(1 + upgrade_level("seasoned_hands"), Crew.max_level(m))
	return float(Crew.xp_for_level(lv))


## What hiring `offer` costs: its price, less 10% while a Scavenger with
## Haggler is on the roster.
func hire_price(offer: Dictionary) -> int:
	var price := float(offer.get("price", 0)) * (1.0 - float(T.UPGRADES.house_credit.per_level) * upgrade_level("house_credit"))
	for m: Dictionary in crew:
		if str(m.role) == "scavenger" and Crew.has_perk(m, "haggler"):
			return roundi(price * 0.9)
	return roundi(price)


## Hire today's offer `index`. Needs the scrap and a free roster slot.
func hire_offer(index: int) -> bool:
	ensure_saloon()
	if index < 0 or index >= saloon.size() or roster_full():
		return false
	var offer: Dictionary = saloon[index]
	var price := hire_price(offer)
	if bool(offer.hired) or price > scrap:
		return false
	scrap -= price
	offer.hired = true
	var m := _add_crew(offer)
	m.xp = maxf(float(m.xp), hire_start_xp(m))
	_auto_seat(m)
	save_game()
	changed.emit()
	return true


## The free Common Driver or Gunner the Saloon always has. Agreed with the
## owner: it can be hired even with a full roster, up to one over the cap
## (so an injured lone Driver never leaves you stuck: days only pass on jobs).
## While over the cap, nothing else joins until someone leaves.
## The free Common `role` hire on offer right now: exactly who hire_basic()
## adds (same seed), so the Saloon card can show their name and specialty.
func basic_offer(role: String) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("helriders-basic-%d-%d" % [day, next_crew_id])
	var m := Crew.make(role, "Common", rng)
	m.xp = hire_start_xp(m)
	m["price"] = 0
	return m


func hire_basic(role: String) -> bool:
	if not can_hire_basic() or not Crew.ROLES.has(role):
		return false
	var m := _add_crew(basic_offer(role))
	_auto_seat(m)
	save_game()
	changed.emit()
	return true


# --- Lost crew and rehires (§14) ---

## A day passes for the lost: whoever's time is up joins the rehire pool at
## level 1 with their specialty and rarity, perks reset.
func _advance_lost() -> void:
	var still: Array = []
	for m: Dictionary in lost:
		m.back_in = int(m.back_in) - 1
		if int(m.back_in) > 0:
			still.append(m)
			continue
		var back := m.duplicate(true)
		back.erase("back_in")
		back.xp = 0.0
		back.perks = []
		back.perk_offer = []
		back.rest = 0
		back.seated = false
		rehire_pool.append(back)
	lost = still


## Today's rehire card (drawn at random from the pool, once a day), or {}.
func rehire_offer() -> Dictionary:
	if rehire_pool.is_empty() or rehire_done_today():
		return {}
	if rehire_day != day or _pool_index(rehire_pick) < 0:
		var dice := RandomNumberGenerator.new()
		dice.seed = hash("helriders-rehire-%d" % day)
		rehire_pick = int(rehire_pool[dice.randi_range(0, rehire_pool.size() - 1)].id)
		rehire_day = day
		rehire_taken = false
	var m: Dictionary = rehire_pool[_pool_index(rehire_pick)].duplicate(true)
	var discount := T.REHIRE_DISCOUNT + float(T.UPGRADES.old_faces.per_level) * upgrade_level("old_faces")
	m["price"] = roundi(float(T.CREW_PRICES[str(m.rarity)]) * (1.0 - discount))
	m["hired"] = false
	m["rehire"] = true
	m.xp = hire_start_xp(m)
	return m


func _pool_index(id: int) -> int:
	for i in rehire_pool.size():
		if int(rehire_pool[i].id) == id:
			return i
	return -1


## Hire today's rehire card. Needs the scrap and a free roster slot.
func rehire() -> bool:
	var offer := rehire_offer()
	if offer.is_empty() or roster_full():
		return false
	var price := hire_price(offer)
	if price > scrap:
		return false
	scrap -= price
	rehire_pool.remove_at(_pool_index(int(offer.id)))
	offer.erase("rehire")
	var m := _add_crew(offer)
	m.xp = hire_start_xp(m)
	_auto_seat(m)
	rehire_pick = -1
	rehire_taken = true
	save_game()
	changed.emit()
	return true


## Send today's rehire away for good (back to the general hire pool).
func dismiss_rehire() -> bool:
	var offer := rehire_offer()
	if offer.is_empty():
		return false
	rehire_pool.remove_at(_pool_index(int(offer.id)))
	rehire_pick = -1
	rehire_taken = true   # no second card today
	save_game()
	changed.emit()
	return true


## The card is spent for today (hired or sent away).
func rehire_done_today() -> bool:
	return rehire_day == day and rehire_taken


## A job was finished: the crew on it split the skulls as XP, and anyone
## injured goes to the Inn to rest (a day less with Tough, or with a Medic's
## Triage on the run). Call after finish_day(), so tonight's rest doesn't
## count. Returns lines for the results card.
func bank_crew(skulls: int, injured_ids: Array, triage := false, half_rest := false) -> Array[String]:
	var lines: Array[String] = []
	var riders := seated_crew()
	if riders.is_empty():
		return lines
	var share := float(skulls) / riders.size()
	for m in riders:
		var before := Crew.level(m)
		m.xp = float(m.xp) + share
		var after := Crew.level(m)
		var line := "%s +%s XP" % [m.name, _num(share)]
		if after > before:
			line += ", level %d" % after
			if Crew.perks_due(m) > 0:
				line += ", PERK READY"
		if injured_ids.has(int(m.id)):
			var days := T.CREW_REST_DAYS_HARD if skulls >= 5 else T.CREW_REST_DAYS
			if Crew.has_perk(m, "tough"):
				days -= 1
			if triage:
				days -= 1
			if half_rest:
				days = ceili(days / 2.0)   # Clean Bandage (Field Medic): half the rest days, rounded up
			m.rest = rest_days(days)
			m.seated = false
			line += ", injured: resting %d day%s" % [int(m.rest), "" if int(m.rest) == 1 else "s"]
		lines.append(line)
	# Drill Yard: crew idle at the Inn learn a share of the job's XP.
	var drill := float(T.UPGRADES.drill_yard.per_level) * upgrade_level("drill_yard") * skulls
	if drill > 0.0:
		var names: Array[String] = []
		for m: Dictionary in crew:
			if bool(m.seated) or is_away(m):
				continue
			m.xp = float(m.xp) + drill
			names.append(str(m.name))
		if not names.is_empty():
			lines.append("Drill Yard: %s +%s XP" % [", ".join(names), _num(drill)])
	save_game()
	changed.emit()
	return lines


## Rest days after an injury, less the Infirmary, never under 1.
func rest_days(days: int) -> int:
	return maxi(days - int(T.UPGRADES.infirmary.per_level) * upgrade_level("infirmary"), 1)


static func _num(v: float) -> String:
	return str(int(v)) if is_equal_approx(v, roundf(v)) else "%.1f" % v


# --- Expeditions -------------------------------------------------------------------

func _roll() -> float:
	return roll_override if roll_override >= 0.0 else luck.randf()


func expeditions_open() -> bool:
	return int(record.clears) >= T.EXPEDITION_UNLOCK_CLEARS


func expeditions_at_once() -> int:
	return T.EXPEDITION_AT_ONCE + int(T.UPGRADES.second_team.per_level) * upgrade_level("second_team")


func is_away(m: Dictionary) -> bool:
	if m.is_empty():
		return false
	for e: Dictionary in expeditions:
		if (e.team as Array).has(int(m.id)):
			return true
	return false


## Benched crew who could go: not seated, not resting, not already away.
func can_send(m: Dictionary) -> bool:
	return not m.is_empty() and not bool(m.seated) and not is_resting(m) and not is_away(m)


## Today's expedition board (seeded by the day). One easy, one middling and
## one hard trip, so there's always something for a small team.
func ensure_exp_board() -> void:
	if exp_board_day == day and exp_board.size() == T.EXPEDITION_BOARD_SIZE:
		return
	exp_board_day = day
	exp_board = []
	var dice := RandomNumberGenerator.new()
	dice.seed = hash("helriders-expeditions-%d" % day)
	var names: Array = T.EXPEDITION_NAMES.duplicate()
	for i in T.EXPEDITION_BOARD_SIZE:
		var band := i % 3
		var skulls := dice.randi_range(band * 2 + 1, band * 2 + 2)
		var trip_name: String = names.pop_at(dice.randi_range(0, names.size() - 1))
		var bonus := ""
		if dice.randf() < T.EXPEDITION_BONUS_SHARE:
			bonus = "schematic" if dice.randf() < 0.5 else "recruit"
		exp_board.append({"name": trip_name, "skulls": skulls, "days": dice.randi_range(1, 3), "bonus": bonus, "taken": false})


static func recommended_level(e: Dictionary) -> int:
	return int(T.EXPEDITION_TEAM_LEVEL[clampi(int(e.skulls), 1, T.MAX_SKULLS) - 1])


func team_level(ids: Array) -> int:
	var total := 0
	for id: Variant in ids:
		var m := member(int(id))
		if not m.is_empty():
			total += Crew.level(m)
	return total


## Success chance for `ids` on trip `e`, Scout Network included.
func expedition_odds(e: Dictionary, ids: Array) -> float:
	if ids.is_empty():
		return 0.0
	var diff := team_level(ids) - recommended_level(e)
	var odds := T.EXPEDITION_ODDS
	odds += diff * (T.EXPEDITION_ODDS_OVER if diff > 0 else T.EXPEDITION_ODDS_UNDER)
	odds += float(T.UPGRADES.scout_network.per_level) * upgrade_level("scout_network")
	return clampf(odds, T.EXPEDITION_ODDS_MIN, T.EXPEDITION_ODDS_MAX)


static func expedition_scrap(e: Dictionary) -> int:
	var base := float(T.EXPEDITION_SCRAP[int(e.skulls) - 1])
	return roundi(base * float(T.EXPEDITION_DAY_MULT[int(e.days) - 1]))


static func expedition_xp(e: Dictionary) -> int:
	return int(e.skulls) * int(e.days)


static func bonus_chance(e: Dictionary) -> float:
	if str(e.get("bonus", "")) == "":
		return 0.0
	return minf(T.EXPEDITION_BONUS_CHANCE * int(e.skulls) * int(e.days), 1.0)


## Why board trip `index` can't go with team `ids`, or "".
func send_block(index: int, ids: Array) -> String:
	if not expeditions_open():
		return "LOCKED"
	ensure_exp_board()
	if index < 0 or index >= exp_board.size():
		return "PICK A TRIP"
	if bool((exp_board[index] as Dictionary).get("taken", false)):
		return "ALREADY SENT"
	if expeditions.size() >= expeditions_at_once():
		return "TEAM ALREADY OUT"
	if ids.is_empty():
		return "PICK A TEAM"
	if ids.size() > T.EXPEDITION_MAX_TEAM:
		return "TEAM TOO BIG"
	for id: Variant in ids:
		if not can_send(member(int(id))):
			return "CREW NOT FREE"
	return ""


func send_expedition(index: int, ids: Array) -> bool:
	if send_block(index, ids) != "":
		return false
	var offer: Dictionary = exp_board[index]
	var team: Array = []
	for id: Variant in ids:
		team.append(int(id))
	var e := {"name": offer.name, "skulls": offer.skulls, "days": offer.days, "bonus": offer.bonus,
		"team": team, "days_left": int(offer.days), "odds": expedition_odds(offer, ids)}
	offer.taken = true
	expeditions.append(e)
	save_game()
	changed.emit()
	return true


## A day passed: count trips down and bring home the ones that are done.
func _advance_expeditions() -> void:
	var still: Array = []
	var lines: Array[String] = []
	for e: Dictionary in expeditions:
		e.days_left = int(e.days_left) - 1
		if int(e.days_left) > 0:
			still.append(e)
		else:
			lines.append_array(_resolve_expedition(e))
	expeditions = still
	if not lines.is_empty():
		expedition_reports = lines
		notice = (notice + "\n" if notice != "" else "") + lines[0] + " Details at the Inn."


## Bring trip `e` home. Returns lines for the Inn's report.
func _resolve_expedition(e: Dictionary) -> Array[String]:
	var team: Array[Dictionary] = []
	for id: Variant in e.team:
		var m := member(int(id))
		if not m.is_empty():
			team.append(m)
	var lines: Array[String] = []
	if team.is_empty():
		return lines
	var success := _roll() < float(e.odds)
	var scrap_won := expedition_scrap(e)
	var xp := float(expedition_xp(e))
	if not success:
		scrap_won = roundi(scrap_won * T.EXPEDITION_FAIL_SCRAP)
		xp *= T.EXPEDITION_FAIL_XP
	scrap += scrap_won
	lines.append("%s: %s, +%d scrap." % [str(e.name), "the team came back with the goods" if success else "it went wrong", scrap_won])
	var share := xp / team.size()
	for m in team:
		var before := Crew.level(m)
		m.xp = float(m.xp) + share
		var line := "%s +%s XP" % [m.name, _num(share)]
		if Crew.level(m) > before:
			line += ", level %d" % Crew.level(m)
			if Crew.perks_due(m) > 0:
				line += ", PERK READY"
		if not success and _roll() < T.EXPEDITION_FAIL_INJURY:
			m.rest = rest_days(T.CREW_REST_DAYS)
			line += ", injured: resting %d day%s" % [int(m.rest), "" if int(m.rest) == 1 else "s"]
		lines.append(line)
	if success and _roll() < bonus_chance(e):
		lines.append(_bonus_find(str(e.bonus)))
	return lines


func _bonus_find(kind: String) -> String:
	if kind == "schematic":
		var pool: Array = []
		for source: String in Parts.DROP_POOLS:
			if source == "elite":
				continue
			for id: String in Parts.DROP_POOLS[source]:
				if not pool.has(id):
					pool.append(id)
		var unknown := unknown_schematics(pool)
		if unknown.is_empty():
			return "They found a schematic you already had."
		var id: String = unknown[luck.randi_range(0, unknown.size() - 1)]
		schematics.append(id)
		return "New schematic: " + Parts.describe(Parts.get_part(id))
	if roster_full():
		return "A drifter wanted to join, but the Inn has no free bunk."
	var role: String = Crew.CLASSES[luck.randi_range(0, Crew.CLASSES.size() - 1)]
	var m := _add_crew(Crew.make(role, _roll_rarity(luck, upgrade_level("word_around")), luck))
	return "New recruit: %s, %s %s, waiting at the Inn." % [m.name, m.rarity, Crew.role_name(m)]


# --- Upgrades ----------------------------------------------------------------------

func upgrade_level(key: String) -> int:
	return int(upgrades.get(key, 0))


## Scrap for the next level, or -1 when the track is maxed.
func upgrade_cost(key: String) -> int:
	var costs: Array = T.UPGRADES[key].costs
	var level := upgrade_level(key)
	return int(costs[level]) if level < costs.size() else -1


## Why `key` can't be bought yet (beyond scrap), or "".
func upgrade_block(key: String) -> String:
	if key == "last_rites" and not is_district_open(T.LAST_RITES_DISTRICT):
		return "OPENS WITH %s" % str(T.DISTRICTS[T.LAST_RITES_DISTRICT].name).to_upper()
	return ""


func buy_upgrade(key: String) -> bool:
	var cost := upgrade_cost(key)
	if cost < 0 or cost > scrap or upgrade_block(key) != "":
		return false
	scrap -= cost
	upgrades[key] = upgrade_level(key) + 1
	if key == "choices" or key == "quality":
		# Same seed, so today's missions stay; more of them, or better paid.
		board = Missions.make_board(day, board_size(), int(upgrades.quality), board_district())
	if key == "back_room":
		ensure_saloon()
	if key == "seasoned_hands":
		for offer: Dictionary in saloon:
			if not bool(offer.hired):
				offer.xp = maxf(float(offer.xp), hire_start_xp(offer))
	save_game()
	changed.emit()
	return true


# --- Presets ------------------------------------------------------------------------

func save_preset(index: int) -> void:
	if not is_complete(rig):
		return
	presets[index] = rig.duplicate(true)
	save_game()
	changed.emit()


func preset(index: int) -> Dictionary:
	var p: Variant = presets[index] if index < presets.size() else null
	return p if p is Dictionary else {}


## The preset's name: the player's, or P1 / P2 / P3.
func preset_name(index: int) -> String:
	var n := str(preset_names[index]) if index < preset_names.size() else ""
	return n if n != "" else "P%d" % (index + 1)


## Name a preset (empty goes back to P1...). Keeps its loadout.
func rename_preset(index: int, name: String) -> void:
	if index < 0 or index >= T.PRESET_COUNT:
		return
	if preset_names.size() < T.PRESET_COUNT:
		preset_names.resize(T.PRESET_COUNT)
	preset_names[index] = clean_preset_name(name)
	save_game()
	changed.emit()


## One line, no edge spaces, at most PRESET_NAME_MAX characters.
static func clean_preset_name(name: String) -> String:
	var n := name.replace("\n", " ").replace("\t", " ").strip_edges()
	return n.left(T.PRESET_NAME_MAX).strip_edges()


func load_preset(index: int) -> bool:
	var p := preset(index)
	return not p.is_empty() and apply_loadout(p)


# --- Save file -----------------------------------------------------------------------

func save_game() -> void:
	if not persist:
		return
	var data := save_data()
	# Write a temp file, then swap it in, keeping the last good save as .bak:
	# the app dying mid-write can't leave a half-written save behind.
	var tmp := save_path + ".tmp"
	var file := FileAccess.open(tmp, FileAccess.WRITE)
	if file == null:
		push_warning("Profile: can't write save (%s)" % FileAccess.get_open_error())
		return
	file.store_string(JSON.stringify(data, "\t"))
	file.close()
	if FileAccess.file_exists(save_path):
		_move(save_path, save_path + ".bak")
	if _move(tmp, save_path) != OK:
		push_warning("Profile: can't swap in the new save")


## Everything the save file holds.
func save_data() -> Dictionary:
	return {
		"version": SAVE_VERSION,
		"scrap": scrap,
		"schematics": schematics,
		"storage": storage,
		"rig": rig,
		"plan": plan,
		"presets": presets,
		"preset_names": preset_names,
		"upgrades": upgrades,
		"levels": levels,
		"research_today": research_today,
		"record": record,
		"notice": notice,
		"day": day,
		"wreck_day": wreck_day,
		"board": board,
		"active_mission": active_mission,
		"run_active": run_active,
		"crew": crew,
		"next_crew_id": next_crew_id,
		"saloon": saloon,
		"saloon_day": saloon_day,
		"exp_board": exp_board,
		"exp_board_day": exp_board_day,
		"expeditions": expeditions,
		"expedition_reports": expedition_reports,
		"discovered": discovered,
		"lost": lost,
		"rehire_pool": rehire_pool,
		"rehire_day": rehire_day,
		"rehire_pick": rehire_pick,
		"rehire_taken": rehire_taken,
	}


func load_game() -> bool:
	if not persist:
		return false
	if not FileAccess.file_exists(save_path) and FileAccess.file_exists(save_path + ".tmp"):
		_move(save_path + ".tmp", save_path)   # died between write and swap
	if not FileAccess.file_exists(save_path) and not FileAccess.file_exists(save_path + ".bak"):
		return false
	var data := read_save(save_path)
	if data.is_empty():
		# Unreadable: fall back to the previous save, and keep the broken file
		# aside (never overwrite it) so nothing is lost for good.
		var backup := read_save(save_path + ".bak")
		if FileAccess.file_exists(save_path):
			_move(save_path, save_path + ".broken")
		if backup.is_empty():
			push_warning("Profile: save file unreadable, starting fresh")
			notice = "Your save couldn't be read, so this is a fresh start. The old file is kept as helriders_save.json.broken."
			return false
		var ok := apply_data(backup)
		notice = "Your last save couldn't be read; loaded the one before it."
		return ok
	return apply_data(data)


static func _move(from: String, to: String) -> Error:
	return DirAccess.rename_absolute(ProjectSettings.globalize_path(from), ProjectSettings.globalize_path(to))


## A save file as a clean dictionary, or {} if it's missing or unreadable.
## Fields of the wrong type are dropped (they load as a new game's).
static func read_save(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not parsed is Dictionary or (parsed as Dictionary).is_empty():
		return {}
	return sanitize_save(parsed)


const _SAVE_TYPES := {
	"version": TYPE_FLOAT, "scrap": TYPE_FLOAT, "schematics": TYPE_ARRAY, "storage": TYPE_DICTIONARY,
	"rig": TYPE_DICTIONARY, "plan": TYPE_DICTIONARY, "presets": TYPE_ARRAY, "preset_names": TYPE_ARRAY, "upgrades": TYPE_DICTIONARY,
	"levels": TYPE_DICTIONARY, "research_today": TYPE_FLOAT, "record": TYPE_DICTIONARY, "notice": TYPE_STRING,
	"day": TYPE_FLOAT, "wreck_day": TYPE_FLOAT, "board": TYPE_ARRAY, "active_mission": TYPE_DICTIONARY,
	"run_active": TYPE_BOOL, "crew": TYPE_ARRAY, "next_crew_id": TYPE_FLOAT, "saloon": TYPE_ARRAY,
	"saloon_day": TYPE_FLOAT, "exp_board": TYPE_ARRAY, "exp_board_day": TYPE_FLOAT, "expeditions": TYPE_ARRAY,
	"expedition_reports": TYPE_ARRAY, "discovered": TYPE_DICTIONARY, "lost": TYPE_ARRAY,
	"rehire_pool": TYPE_ARRAY, "rehire_day": TYPE_FLOAT, "rehire_pick": TYPE_FLOAT, "rehire_taken": TYPE_BOOL,
}


## Drop top-level fields whose type is wrong (a hand-edited or damaged save),
## so apply_data never meets, say, a number where it expects a list.
static func sanitize_save(data: Dictionary) -> Dictionary:
	var out := {}
	for key: Variant in data:
		var want: int = _SAVE_TYPES.get(str(key), -1)
		var v: Variant = data[key]
		var got := typeof(v)
		if want == -1 or got == want or (want == TYPE_FLOAT and got == TYPE_INT) or (want == TYPE_BOOL and got == TYPE_FLOAT):
			out[str(key)] = v
	return out


## Load the game from a save_data() dictionary (the file, or a snapshot).
func apply_data(data: Dictionary) -> bool:
	_ready_state = true
	scrap = int(data.get("scrap", T.START_SCRAP))
	schematics.clear()
	for id: Variant in data.get("schematics", []):
		if Parts.CATALOG.has(str(id)):
			schematics.append(str(id))
	storage = {}
	var saved_storage: Dictionary = data.get("storage", {})
	for id: String in saved_storage:
		if Parts.CATALOG.has(id) and int(saved_storage[id]) > 0:
			storage[id] = int(saved_storage[id])
	rig = _clean_loadout(data.get("rig", {}))
	plan = _clean_loadout(data.get("plan", {}))
	presets = []
	presets.resize(T.PRESET_COUNT)
	var saved_presets: Array = data.get("presets", [])
	for i in mini(saved_presets.size(), T.PRESET_COUNT):
		if saved_presets[i] is Dictionary:
			presets[i] = _clean_loadout(saved_presets[i])
	preset_names = []
	preset_names.resize(T.PRESET_COUNT)
	preset_names.fill("")
	var saved_names: Array = data.get("preset_names", [])
	for i in mini(saved_names.size(), T.PRESET_COUNT):
		preset_names[i] = clean_preset_name(str(saved_names[i]) if saved_names[i] is String else "")
	var saved_upgrades: Dictionary = data.get("upgrades", {})
	upgrades = _no_upgrades()
	for key: String in upgrades:
		upgrades[key] = clampi(int(saved_upgrades.get(key, 0)), 0, (T.UPGRADES[key].costs as Array).size())
	# Saves from before Research load with every schematic at level 1.
	levels = {}
	var saved_levels: Dictionary = data.get("levels", {})
	for id: String in saved_levels:
		if Parts.CATALOG.has(id):
			var lv := clampi(int(saved_levels[id]), 1, Parts.max_level(Parts.get_part(id)))
			if lv > 1:
				levels[id] = lv
	research_today = maxi(int(data.get("research_today", 0)), 0)
	var saved_record: Dictionary = data.get("record", {})
	for key: String in record:
		record[key] = int(saved_record.get(key, 0))
	notice = str(data.get("notice", ""))
	day = maxi(1, int(data.get("day", 1)))
	board = []
	for m: Variant in data.get("board", []):
		var clean := _clean_mission(m)
		if not clean.is_empty():
			board.append(clean)
	active_mission = _clean_mission(data.get("active_mission", {}))
	run_active = bool(data.get("run_active", false))
	discovered = {}
	var saved_found: Dictionary = data.get("discovered", {})
	for cat: String in saved_found:
		if saved_found[cat] is Array:
			var ids: Array = []
			for id: Variant in saved_found[cat]:
				ids.append(str(id))
			discovered[cat] = ids
	ensure_board()
	if data.has("crew"):
		crew = []
		for raw: Variant in data.get("crew", []):
			var m := _clean_member(raw)
			if not m.is_empty():
				crew.append(m)
		next_crew_id = maxi(int(data.get("next_crew_id", 1)), 1)
		for m: Dictionary in crew:
			next_crew_id = maxi(next_crew_id, int(m.id) + 1)
		saloon = []
		for raw: Variant in data.get("saloon", []):
			var offer := _clean_member(raw)
			if not offer.is_empty() and raw is Dictionary:
				offer["price"] = int((raw as Dictionary).get("price", T.CREW_PRICES[offer.rarity]))
				offer["hired"] = bool((raw as Dictionary).get("hired", false))
				offer.xp = float((raw as Dictionary).get("xp", 0.0))
				saloon.append(offer)
		saloon_day = int(data.get("saloon_day", 0))
		lost = []
		for raw: Variant in data.get("lost", []):
			var m := _clean_member(raw)
			if not m.is_empty() and raw is Dictionary:
				m.seated = false
				m["back_in"] = maxi(int((raw as Dictionary).get("back_in", 1)), 1)
				lost.append(m)
		rehire_pool = []
		for raw: Variant in data.get("rehire_pool", []):
			var m := _clean_member(raw)
			if not m.is_empty():
				m.seated = false
				rehire_pool.append(m)
		rehire_day = int(data.get("rehire_day", 0))
		rehire_pick = int(data.get("rehire_pick", -1))
		rehire_taken = bool(data.get("rehire_taken", false))
	else:
		# A save from before crew: the starter pair joins, seated.
		_starter_crew()
		_fit_seats()
	ensure_saloon()
	# Expeditions (saves from before them have none).
	exp_board_day = int(data.get("exp_board_day", 0))
	wreck_day = int(data.get("wreck_day", 0))
	exp_board = []
	for raw: Variant in data.get("exp_board", []):
		var e := _clean_expedition(raw)
		if not e.is_empty():
			e["taken"] = bool((raw as Dictionary).get("taken", false))
			exp_board.append(e)
	expeditions = []
	for raw: Variant in data.get("expeditions", []):
		var e := _clean_expedition(raw)
		if e.is_empty():
			continue
		var d: Dictionary = raw
		var team: Array = []
		for id: Variant in d.get("team", []):
			if not member(int(id)).is_empty():
				team.append(int(id))
		if team.is_empty():
			continue
		e["team"] = team
		e["days_left"] = clampi(int(d.get("days_left", 1)), 1, 3)
		e["odds"] = clampf(float(d.get("odds", T.EXPEDITION_ODDS)), 0.0, 1.0)
		expeditions.append(e)
	expedition_reports = []
	for line: Variant in data.get("expedition_reports", []):
		expedition_reports.append(str(line))
	return true


static func _clean_expedition(raw: Variant) -> Dictionary:
	if not raw is Dictionary:
		return {}
	var d: Dictionary = raw
	var bonus := str(d.get("bonus", ""))
	if not bonus in ["", "schematic", "recruit"]:
		bonus = ""
	return {
		"name": str(d.get("name", "Expedition")),
		"skulls": clampi(int(d.get("skulls", 1)), 1, T.MAX_SKULLS),
		"days": clampi(int(d.get("days", 1)), 1, 3),
		"bonus": bonus,
	}


## JSON gives back floats and loose types; rebuild a crew member, or {}.
static func _clean_member(raw: Variant) -> Dictionary:
	if not raw is Dictionary:
		return {}
	var d: Dictionary = raw
	var role := str(d.get("role", ""))
	var rarity := str(d.get("rarity", ""))
	if not Crew.CLASSES.has(role) or not Crew.RARITIES.has(rarity):
		return {}
	var out := {
		"id": int(d.get("id", 0)),
		"name": str(d.get("name", "Crew")),
		"role": role,
		"specialty": str(d.get("specialty", "")),
		"rarity": rarity,
		"xp": maxf(float(d.get("xp", 0.0)), 0.0),
		"perks": [],
		"perk_offer": [],
		"rest": maxi(int(d.get("rest", 0)), 0),
		"seated": bool(d.get("seated", false)),
	}
	# Crew from before specialties keep their ability: Wheelman, Gunslinger.
	out.specialty = Crew.specialty(out)
	var pool := Crew.perk_known(out)
	for p: Variant in d.get("perks", []):
		if pool.has(str(p)) and not (out.perks as Array).has(str(p)):
			(out.perks as Array).append(str(p))
	for p: Variant in d.get("perk_offer", []):
		if pool.has(str(p)):
			(out.perk_offer as Array).append(str(p))
	return out


## JSON turns ints into floats; put a mission back in shape, or {} if unusable.
static func _clean_mission(raw: Variant) -> Dictionary:
	if not raw is Dictionary:
		return {}
	var d: Dictionary = raw
	var type := str(d.get("type", ""))
	if not T.MISSIONS.has(type):
		return {}
	# Saves from before skulls rated jobs threat 1-3 (1 skull = threat 1,
	# 6 skulls = threat 3).
	var skulls := int(d.get("skulls", 0))
	if skulls <= 0:
		skulls = [1, 3, 6][clampi(int(d.get("threat", 1)), 1, 3) - 1]
	var out := {
		"id": str(d.get("id", "")),
		"type": type,
		"skulls": clampi(skulls, 1, T.MAX_SKULLS),
		"name": str(d.get("name", "")),
		"seed": int(d.get("seed", 1)),
		"reward": int(d.get("reward", 0)),
	}
	if Layouts.LAYOUTS.has(str(d.get("layout", ""))):
		out["layout"] = str(d.layout)
	return out


## JSON gives back untyped data; rebuild a loadout with only known part ids.
static func _clean_loadout(raw: Variant) -> Dictionary:
	var out := empty_loadout()
	if not raw is Dictionary:
		return out
	var d: Dictionary = raw
	# Saves from before the three armor slots (§14): the one plate goes on all
	# three (a front-only ram plate on the front only).
	if d.has("armor") and not d.has("armor_front"):
		var old := str(d.armor)
		d = d.duplicate()
		d["armor_front"] = old
		var front_only := bool(Parts.get_part(old).get("front_only", false))
		d["armor_sides"] = "" if front_only else old
		d["armor_rear"] = "" if front_only else old
	for key in SINGLE_SLOTS:
		var id := str(d.get(key, ""))
		out[key] = id if Parts.CATALOG.has(id) else ""
	for key in ["armor_sides", "armor_rear"]:
		if bool(Parts.get_part(str(out[key])).get("front_only", false)):
			out[key] = ""
	for key in LIST_SLOTS:
		var list: Array = []
		for id: Variant in d.get(key, []):
			if Parts.CATALOG.has(str(id)):
				list.append(str(id))
		out[key] = list
	return out


# --- Database (what the player has met) -------------------------------------------

## Mark `id` in `category` as met. Saves only when it's new.
func discover(category: String, id: String) -> bool:
	if id == "":
		return false
	var list: Array = discovered.get(category, [])
	if list.has(id):
		return false
	list.append(id)
	discovered[category] = list
	save_game()
	return true


## Has the player met it? Owned schematics, crew on the roster and open
## districts always count.
func is_discovered(category: String, id: String) -> bool:
	match category:
		"parts":
			if schematics.has(id):
				return true
		"crew":
			for m: Dictionary in crew:
				if Crew.specialty(m) == id:
					return true
		"places":
			for i in T.DISTRICTS.size():
				if str(T.DISTRICTS[i].id) == id and is_district_open(i):
					return true
	return (discovered.get(category, []) as Array).has(id)


# --- Settings (own file, kept across new games) ------------------------------------

func load_settings() -> void:
	settings = {"quality": auto_quality(), "shake": true, "music": 0.8, "effects": 0.8, "fullscreen": false}
	if persist:
		var cfg := ConfigFile.new()
		if cfg.load(settings_path) == OK:
			var q := str(cfg.get_value("video", "quality", settings.quality))
			if T.QUALITY.has(q):
				settings.quality = q
			settings.shake = bool(cfg.get_value("video", "shake", true))
			settings.music = clampf(float(cfg.get_value("audio", "music", 0.8)), 0.0, 1.0)
			settings.effects = clampf(float(cfg.get_value("audio", "effects", 0.8)), 0.0, 1.0)
			var fs: Variant = cfg.get_value("video", "fullscreen", false)
			settings.fullscreen = fs is bool and bool(fs)
			# Controller mapping (pad.gd): action -> button code, and the stick swap.
			var saved_map: Variant = cfg.get_value("pad", "map", {})
			if saved_map is Dictionary:
				var m := {}
				for a: Variant in saved_map:
					var code: Variant = saved_map[a]
					if (code is int or code is float) and int(code) >= 0 and int(code) < 200:
						m[str(a)] = int(code)
				if not m.is_empty():
					settings.pad_map = m
			var swap: Variant = cfg.get_value("pad", "swap", false)
			settings.pad_swap = swap is bool and bool(swap)
	apply_settings()


func save_settings() -> void:
	apply_settings()
	if not persist:
		return
	var cfg := ConfigFile.new()
	cfg.set_value("video", "quality", settings.quality)
	cfg.set_value("video", "shake", settings.shake)
	cfg.set_value("video", "fullscreen", bool(settings.get("fullscreen", false)))
	cfg.set_value("audio", "music", settings.music)
	cfg.set_value("audio", "effects", settings.effects)
	if settings.has("pad_map"):
		cfg.set_value("pad", "map", settings.pad_map)
	cfg.set_value("pad", "swap", bool(settings.get("pad_swap", false)))
	cfg.save(settings_path)


func set_setting(key: String, value: Variant) -> void:
	if settings.is_empty():
		load_settings()
	settings[key] = value
	save_settings()
	changed.emit()


## Running on a PC (Windows, Linux, macOS) rather than a phone.
static func is_desktop() -> bool:
	return not OS.has_feature("mobile") and not OS.has_feature("web")


## A first guess for this phone: fewer cores, lower preset. Headless runs
## (tests, CI) always get Ultra, which draws everything.
static func auto_quality() -> String:
	if DisplayServer.get_name() == "headless":
		return "Ultra"
	var cores := OS.get_processor_count()
	if cores <= 4:
		return "Low"
	if cores <= 6:
		return "Medium"
	return "High"


func quality() -> Dictionary:
	return T.QUALITY[str(settings.get("quality", "Ultra"))]


## Frame cap now; the mission reads effects, splats and shake when it starts.
## Volumes go to the Music and Effects buses (made here if missing).
func apply_settings() -> void:
	Engine.max_fps = int(quality().fps)
	# PC: windowed or fullscreen (a phone is always full screen).
	if is_desktop() and DisplayServer.get_name() != "headless":
		var want := DisplayServer.WINDOW_MODE_FULLSCREEN if bool(settings.get("fullscreen", false)) else DisplayServer.WINDOW_MODE_WINDOWED
		if DisplayServer.window_get_mode() != want:
			DisplayServer.window_set_mode(want)
	for bus: String in ["Music", "Effects"]:
		var i := AudioServer.get_bus_index(bus)
		if i < 0:
			AudioServer.add_bus()
			i = AudioServer.bus_count - 1
			AudioServer.set_bus_name(i, bus)
			AudioServer.set_bus_send(i, "Master")
		var v := float(settings.get(bus.to_lower(), 0.8))
		AudioServer.set_bus_volume_db(i, linear_to_db(maxf(v, 0.0001)))
		AudioServer.set_bus_mute(i, v <= 0.0)


# --- Tutorial (optional, from MENU; agreed with the owner) --------------------------

## The garage tour after the Training Run: a sandbox copy of the game with
## the salvaged part in storage. Nothing done in it is saved; end_tour()
## puts everything back.
func begin_tour() -> void:
	if tour_active:
		return
	_tour_snapshot = JSON.parse_string(JSON.stringify(save_data()))
	_tour_persist = persist
	persist = false
	tour_active = true
	if not schematics.has(T.TUTORIAL_PART):
		schematics.append(T.TUTORIAL_PART)
	storage[T.TUTORIAL_PART] = int(storage.get(T.TUTORIAL_PART, 0)) + 1
	changed.emit()


func end_tour() -> void:
	if not tour_active:
		return
	tour_active = false
	apply_data(_tour_snapshot)
	_tour_snapshot = {}
	persist = _tour_persist
	save_game()
	changed.emit()


## Extract or Push (§14): never the day after a wreck.
func push_blocked_today() -> bool:
	return wreck_day > 0 and day == wreck_day + 1
