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

signal changed

const T := preload("res://scripts/tuning.gd")
const Parts := preload("res://scripts/parts.gd")
const Loadout := preload("res://scripts/loadout.gd")

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
var upgrades := {"fabrication": 0, "loot": 0, "salvage": 0}
var record := {"runs": 0, "clears": 0, "wrecks": 0}
var notice := ""                    # one-time message for the garage to show
var _ready_state := false           # set once a game is loaded or started


func _ready() -> void:
	# Tests may have started a game before the autoload is ready; keep it.
	if not _ready_state and not load_game():
		new_game()


func new_game() -> void:
	_ready_state = true
	scrap = T.START_SCRAP
	schematics.clear()
	for id in parts_in(Parts.STARTER_LOADOUT):
		if not schematics.has(id):
			schematics.append(id)
	storage = {}
	rig = Parts.STARTER_LOADOUT.duplicate(true)
	plan = rig.duplicate(true)
	presets = []
	presets.resize(T.PRESET_COUNT)
	upgrades = {"fabrication": 0, "loot": 0, "salvage": 0}
	record = {"runs": 0, "clears": 0, "wrecks": 0}
	notice = ""
	save_game()


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
	save_game()
	changed.emit()
	return true


# --- Runs ---------------------------------------------------------------------------

func start_run() -> void:
	record.runs = int(record.runs) + 1
	save_game()


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


## Wrecked: the rig and every part on it are gone, and you pay a scrap
## penalty scaled to what the build was worth. Returns the penalty paid.
func record_wreck() -> int:
	record.wrecks = int(record.wrecks) + 1
	var penalty := wreck_penalty(rig)
	scrap -= penalty
	if is_complete(rig):
		plan = rig.duplicate(true)
	rig = empty_loadout()
	save_game()
	changed.emit()
	return penalty


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
	return true


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
