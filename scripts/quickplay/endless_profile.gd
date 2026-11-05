extends RefCounted
## Quickplay QP5: Endless scrap / unlocks / bests. Own file
## user://helriders_endless.json — never reads or writes the campaign Profile.

const Parts := preload("res://scripts/parts.gd")
const T := preload("res://scripts/tuning.gd")

const SAVE_VERSION := 1
const DEFAULT_PATH := "user://helriders_endless.json"
## Tree-root meta key for an optional shared instance (no static leak).
const TREE_META := &"quickplay_endless_profile"

var persist := true
var save_path := DEFAULT_PATH
var notice := ""

var scrap := 0
var schematics: Array[String] = []
var storage := {}
var rig := {}
var plan := {}
var presets: Array = []
var preset_names: Array = []
var levels := {}
var crew: Array = []
var next_crew_id := 1
var starter_id := ""
var best_wave := 0
var best_score := 0
var runs := 0
var wrecks := 0


## Optional shared instance hung on the scene tree root (arena.gd MAP_META style).
static func from_tree(tree: SceneTree) -> RefCounted:
	var root: Window = tree.root if tree != null else null
	if root != null and root.has_meta(TREE_META):
		return root.get_meta(TREE_META)
	var profile = new()
	if root != null:
		root.set_meta(TREE_META, profile)
	return profile


static func clear_tree(tree: SceneTree) -> void:
	var root: Window = tree.root if tree != null else null
	if root != null and root.has_meta(TREE_META):
		root.remove_meta(TREE_META)


func new_profile() -> void:
	scrap = int(_t("ENDLESS_START_SCRAP", 0))
	schematics.clear()
	storage = {}
	rig = {}
	plan = {}
	presets = []
	presets.resize(int(T.PRESET_COUNT))
	preset_names = []
	preset_names.resize(int(T.PRESET_COUNT))
	preset_names.fill("")
	levels = {}
	crew = []
	next_crew_id = 1
	starter_id = str(_t("ENDLESS_STARTER_RIG_DEFAULT", "balanced"))
	best_wave = 0
	best_score = 0
	runs = 0
	wrecks = 0
	notice = ""
	save_game()


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
		"levels": levels,
		"crew": crew,
		"next_crew_id": next_crew_id,
		"starter_id": starter_id,
		"best_wave": best_wave,
		"best_score": best_score,
		"runs": runs,
		"wrecks": wrecks,
	}


const _SAVE_TYPES := {
	"version": TYPE_FLOAT, "scrap": TYPE_FLOAT, "schematics": TYPE_ARRAY, "storage": TYPE_DICTIONARY,
	"rig": TYPE_DICTIONARY, "plan": TYPE_DICTIONARY, "presets": TYPE_ARRAY, "preset_names": TYPE_ARRAY,
	"levels": TYPE_DICTIONARY, "crew": TYPE_ARRAY, "next_crew_id": TYPE_FLOAT, "starter_id": TYPE_STRING,
	"best_wave": TYPE_FLOAT, "best_score": TYPE_FLOAT, "runs": TYPE_FLOAT, "wrecks": TYPE_FLOAT,
}


static func sanitize(data: Dictionary) -> Dictionary:
	var out := {}
	for key: Variant in data:
		var want: int = _SAVE_TYPES.get(str(key), -1)
		var v: Variant = data[key]
		var got := typeof(v)
		if want == -1 or got == want or (want == TYPE_FLOAT and got == TYPE_INT) or (want == TYPE_BOOL and got == TYPE_FLOAT):
			out[str(key)] = v
	return out


func apply_data(data: Dictionary) -> bool:
	var clean := sanitize(data)
	if clean.is_empty():
		return false
	scrap = maxi(int(clean.get("scrap", 0)), 0)
	schematics.clear()
	for id: Variant in clean.get("schematics", []):
		if Parts.CATALOG.has(str(id)):
			schematics.append(str(id))
	storage = {}
	var saved_storage: Dictionary = clean.get("storage", {})
	for id: String in saved_storage:
		if Parts.CATALOG.has(id) and int(saved_storage[id]) > 0:
			storage[id] = int(saved_storage[id])
	rig = clean.get("rig", {}) if clean.get("rig", {}) is Dictionary else {}
	plan = clean.get("plan", {}) if clean.get("plan", {}) is Dictionary else {}
	presets = []
	presets.resize(int(T.PRESET_COUNT))
	var saved_presets: Array = clean.get("presets", [])
	for i in mini(saved_presets.size(), int(T.PRESET_COUNT)):
		if saved_presets[i] is Dictionary:
			presets[i] = saved_presets[i]
	preset_names = []
	preset_names.resize(int(T.PRESET_COUNT))
	preset_names.fill("")
	var saved_names: Array = clean.get("preset_names", [])
	for i in mini(saved_names.size(), int(T.PRESET_COUNT)):
		preset_names[i] = str(saved_names[i]) if saved_names[i] is String else ""
	levels = {}
	var saved_levels: Dictionary = clean.get("levels", {})
	for id: String in saved_levels:
		if Parts.CATALOG.has(id):
			levels[id] = maxi(int(saved_levels[id]), 1)
	crew = []
	for raw: Variant in clean.get("crew", []):
		if raw is Dictionary:
			crew.append((raw as Dictionary).duplicate(true))
	next_crew_id = maxi(int(clean.get("next_crew_id", 1)), 1)
	starter_id = str(clean.get("starter_id", _t("ENDLESS_STARTER_RIG_DEFAULT", "balanced")))
	best_wave = maxi(int(clean.get("best_wave", 0)), 0)
	best_score = maxi(int(clean.get("best_score", 0)), 0)
	runs = maxi(int(clean.get("runs", 0)), 0)
	wrecks = maxi(int(clean.get("wrecks", 0)), 0)
	return true


func save_game() -> void:
	if not persist:
		return
	var data := save_data()
	var tmp := save_path + ".tmp"
	var file := FileAccess.open(tmp, FileAccess.WRITE)
	if file == null:
		push_warning("EndlessProfile: can't write save (%s)" % FileAccess.get_open_error())
		return
	file.store_string(JSON.stringify(data, "\t"))
	file.close()
	if FileAccess.file_exists(save_path):
		_move(save_path, save_path + ".bak")
	if _move(tmp, save_path) != OK:
		push_warning("EndlessProfile: can't swap in the new save")


func load_game() -> bool:
	if not persist:
		return false
	if not FileAccess.file_exists(save_path) and FileAccess.file_exists(save_path + ".tmp"):
		_move(save_path + ".tmp", save_path)
	if not FileAccess.file_exists(save_path) and not FileAccess.file_exists(save_path + ".bak"):
		return false
	var data := read_save(save_path)
	if data.is_empty():
		var backup := read_save(save_path + ".bak")
		if FileAccess.file_exists(save_path):
			_move(save_path, save_path + ".broken")
		if backup.is_empty():
			push_warning("EndlessProfile: save unreadable, starting fresh")
			notice = "Your Endless save couldn't be read; starting fresh."
			return false
		var ok := apply_data(backup)
		notice = "Your last Endless save couldn't be read; loaded the one before it."
		return ok
	return apply_data(data)


static func read_save(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not parsed is Dictionary or (parsed as Dictionary).is_empty():
		return {}
	return sanitize(parsed)


func bank_scrap(amount: int) -> void:
	if amount == 0:
		return
	scrap = maxi(scrap + amount, 0)
	save_game()


func record_run(wave: int, score: int, wrecked := true) -> void:
	runs += 1
	if wrecked:
		wrecks += 1
	best_wave = maxi(best_wave, maxi(wave, 0))
	best_score = maxi(best_score, maxi(score, 0))
	save_game()


func unlock_schematic(id: String) -> bool:
	if not Parts.CATALOG.has(id) or schematics.has(id):
		return false
	schematics.append(id)
	save_game()
	return true


func knows(id: String) -> bool:
	return schematics.has(id)


func choose_starter(id: String) -> bool:
	var allowed: Array = _t("ENDLESS_STARTER_RIG_IDS", ["fast", "balanced", "tough"]) as Array
	if not allowed.has(id):
		return false
	starter_id = id
	save_game()
	return true


static func _move(from: String, to: String) -> Error:
	return DirAccess.rename_absolute(ProjectSettings.globalize_path(from), ProjectSettings.globalize_path(to))


## Read Content's ENDLESS_* from tuning when present (PR #91); else fallback.
static func _t(name: String, fallback: Variant) -> Variant:
	var script: GDScript = load("res://scripts/tuning.gd") as GDScript
	var map: Dictionary = script.get_script_constant_map()
	if map.has(name):
		return map[name]
	return fallback
