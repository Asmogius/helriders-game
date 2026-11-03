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

signal changed

const T := preload("res://scripts/tuning.gd")
const Parts := preload("res://scripts/parts.gd")
const Loadout := preload("res://scripts/loadout.gd")
const Missions := preload("res://scripts/missions.gd")
const Crew := preload("res://scripts/crew.gd")

const SAVE_VERSION := 1
const SINGLE_SLOTS := ["chassis", "engine", "drive", "armor"]
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
var upgrades := {"fabrication": 0, "loot": 0, "salvage": 0, "choices": 0, "quality": 0}
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
var _ready_state := false           # set once a game is loaded or started


func _ready() -> void:
	# Tests may have started a game before the autoload is ready; keep it.
	if not _ready_state and not load_game():
		new_game()
	# The app was closed during a mission: the crew pulled out. No loot, no
	# penalty, rig intact, but the day is gone.
	if run_active:
		notice = "You pulled out of yesterday's job. No loot, no penalty, and the day passed."
		finish_day()


func new_game() -> void:
	_ready_state = true
	scrap = T.START_SCRAP
	schematics.clear()
	for id: String in Parts.STARTER_SCHEMATICS:
		schematics.append(id)
	storage = {}
	rig = Parts.STARTER_LOADOUT.duplicate(true)
	plan = rig.duplicate(true)
	presets = []
	presets.resize(T.PRESET_COUNT)
	upgrades = {"fabrication": 0, "loot": 0, "salvage": 0, "choices": 0, "quality": 0}
	record = {"runs": 0, "clears": 0, "wrecks": 0}
	notice = ""
	day = 1
	active_mission = {}
	run_active = false
	board = Missions.make_board(day, board_size(), 0)
	_starter_crew()
	saloon_day = 0
	ensure_saloon()
	save_game()


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
	return {"chassis": "", "engine": "", "drive": "", "armor": "", "weapons": [], "utility": [], "internal": []}


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
	record.runs = int(record.runs) + 1
	run_active = true
	save_game()


# --- Days, the board, districts --------------------------------------------------

func board_size() -> int:
	return T.BOARD_SIZE + int(upgrades.get("choices", 0))


func ensure_board() -> void:
	if board.size() != board_size():
		board = Missions.make_board(day, board_size(), int(upgrades.get("quality", 0)))


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
	active_mission = {}
	board = Missions.make_board(day, board_size(), int(upgrades.get("quality", 0)))
	ensure_saloon()
	save_game()
	changed.emit()


## DESIGN §7: extracted parts only (starter schematics don't count),
## rarity points x level. Every schematic is level 1 until Research.
func district_score() -> int:
	var starter: Array = Parts.STARTER_SCHEMATICS
	var score := 0
	for id in schematics:
		if starter.has(id):
			continue
		score += int(T.RARITY_POINTS.get(str(Parts.get_part(id).get("rarity", "")), 0))
	return score


func is_district_open(index: int) -> bool:
	return district_score() >= int(T.DISTRICTS[index].need)


## Extracted: bank the run's scrap and schematics. Returns a report for the
## results card. Drops never repeat a known schematic, so all are new.
func bank_run(run_scrap: int, salvaged: Array[String]) -> Dictionary:
	var unlocked: Array[String] = []
	for id in salvaged:
		if not schematics.has(id):
			schematics.append(id)
			unlocked.append(id)
	scrap += run_scrap
	record.clears = int(record.clears) + 1
	save_game()
	changed.emit()
	return {"scrap": run_scrap, "unlocked": unlocked}


## Wrecked: the rig and every part on it are gone, everyone seated dies, and
## you pay a scrap penalty scaled to what the build was worth. Returns the
## penalty paid.
func record_wreck() -> int:
	record.wrecks = int(record.wrecks) + 1
	var penalty := wreck_penalty(rig)
	scrap -= penalty
	if is_complete(rig):
		plan = rig.duplicate(true)
	rig = empty_loadout()
	crew = crew.filter(func(m: Dictionary) -> bool: return not bool(m.seated))
	save_game()
	changed.emit()
	return penalty


# --- Crew ---------------------------------------------------------------------------

func _add_crew(member: Dictionary) -> Dictionary:
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


func roster_full() -> bool:
	return crew.size() >= T.ROSTER_SIZE


## Why crew member `m` can't be seated on this frame, or "".
func seat_block(m: Dictionary) -> String:
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
	var stats := Loadout.build(rig)
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
func ensure_saloon() -> void:
	if saloon_day == day and saloon.size() == T.SALOON_OFFERS:
		return
	saloon_day = day
	saloon = []
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("helriders-saloon-%d" % day)
	for i in T.SALOON_OFFERS:
		var role: String = Crew.CLASSES[rng.randi_range(0, Crew.CLASSES.size() - 1)]
		var rarity := _roll_rarity(rng)
		var m := Crew.make(role, rarity, rng)
		m["price"] = int(T.CREW_PRICES[rarity])
		m["hired"] = false
		saloon.append(m)


static func _roll_rarity(rng: RandomNumberGenerator) -> String:
	var total := 0.0
	for r: String in T.SALOON_ODDS:
		total += float(T.SALOON_ODDS[r])
	var roll := rng.randf() * total
	for r: String in T.SALOON_ODDS:
		roll -= float(T.SALOON_ODDS[r])
		if roll < 0.0:
			return r
	return "Uncommon"


## What hiring `offer` costs: its price, less 10% while a Scavenger with
## Haggler is on the roster.
func hire_price(offer: Dictionary) -> int:
	var price := int(offer.get("price", 0))
	for m: Dictionary in crew:
		if str(m.role) == "scavenger" and Crew.has_perk(m, "haggler"):
			return roundi(price * 0.9)
	return price


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
	_auto_seat(_add_crew(offer))
	save_game()
	changed.emit()
	return true


## The free Common Driver or Gunner the Saloon always has.
func hire_basic(role: String) -> bool:
	if roster_full() or not Crew.ROLES.has(role):
		return false
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("helriders-basic-%d-%d" % [day, next_crew_id])
	_auto_seat(_add_crew(Crew.make(role, "Common", rng)))
	save_game()
	changed.emit()
	return true


## A job was finished: the crew on it split the skulls as XP, and anyone
## injured goes to the Inn to rest (a day less with Tough, or with a Medic's
## Triage on the run). Call after finish_day(), so tonight's rest doesn't
## count. Returns lines for the results card.
func bank_crew(skulls: int, injured_ids: Array, triage := false) -> Array[String]:
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
			m.rest = maxi(days, 1)
			m.seated = false
			line += ", injured: resting %d day%s" % [int(m.rest), "" if int(m.rest) == 1 else "s"]
		lines.append(line)
	save_game()
	changed.emit()
	return lines


static func _num(v: float) -> String:
	return str(int(v)) if is_equal_approx(v, roundf(v)) else "%.1f" % v


# --- Upgrades ----------------------------------------------------------------------

func upgrade_level(key: String) -> int:
	return int(upgrades.get(key, 0))


## Scrap for the next level, or -1 when the track is maxed.
func upgrade_cost(key: String) -> int:
	var costs: Array = T.UPGRADES[key].costs
	var level := upgrade_level(key)
	return int(costs[level]) if level < costs.size() else -1


func buy_upgrade(key: String) -> bool:
	var cost := upgrade_cost(key)
	if cost < 0 or cost > scrap:
		return false
	scrap -= cost
	upgrades[key] = upgrade_level(key) + 1
	if key == "choices" or key == "quality":
		# Same seed, so today's missions stay; more of them, or better paid.
		board = Missions.make_board(day, board_size(), int(upgrades.quality))
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


func load_preset(index: int) -> bool:
	var p := preset(index)
	return not p.is_empty() and apply_loadout(p)


# --- Save file -----------------------------------------------------------------------

func save_game() -> void:
	if not persist:
		return
	var data := {
		"version": SAVE_VERSION,
		"scrap": scrap,
		"schematics": schematics,
		"storage": storage,
		"rig": rig,
		"plan": plan,
		"presets": presets,
		"upgrades": upgrades,
		"record": record,
		"notice": notice,
		"day": day,
		"board": board,
		"active_mission": active_mission,
		"run_active": run_active,
		"crew": crew,
		"next_crew_id": next_crew_id,
		"saloon": saloon,
		"saloon_day": saloon_day,
	}
	var file := FileAccess.open(save_path, FileAccess.WRITE)
	if file == null:
		push_warning("Profile: can't write save (%s)" % FileAccess.get_open_error())
		return
	file.store_string(JSON.stringify(data, "\t"))


func load_game() -> bool:
	if not persist or not FileAccess.file_exists(save_path):
		return false
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(save_path))
	if not parsed is Dictionary:
		push_warning("Profile: save file unreadable, starting fresh")
		return false
	var data: Dictionary = parsed
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
	var saved_upgrades: Dictionary = data.get("upgrades", {})
	for key: String in upgrades:
		upgrades[key] = clampi(int(saved_upgrades.get(key, 0)), 0, (T.UPGRADES[key].costs as Array).size())
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
				saloon.append(offer)
		saloon_day = int(data.get("saloon_day", 0))
	else:
		# A save from before crew: the starter pair joins, seated.
		_starter_crew()
		_fit_seats()
	ensure_saloon()
	return true


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
	var pool := Crew.perk_pool(out)
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
	return {
		"id": str(d.get("id", "")),
		"type": type,
		"skulls": clampi(skulls, 1, T.MAX_SKULLS),
		"name": str(d.get("name", "")),
		"seed": int(d.get("seed", 1)),
		"reward": int(d.get("reward", 0)),
	}


## JSON gives back untyped data; rebuild a loadout with only known part ids.
static func _clean_loadout(raw: Variant) -> Dictionary:
	var out := empty_loadout()
	if not raw is Dictionary:
		return out
	var d: Dictionary = raw
	for key in SINGLE_SLOTS:
		var id := str(d.get(key, ""))
		out[key] = id if Parts.CATALOG.has(id) else ""
	for key in LIST_SLOTS:
		var list: Array = []
		for id: Variant in d.get(key, []):
			if Parts.CATALOG.has(str(id)):
				list.append(str(id))
		out[key] = list
	return out
