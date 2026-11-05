extends RefCounted
## Quickplay QP5: local Sandbox level IO under user://quickplay/levels/.
## Atomic write (.tmp → swap, previous kept as .bak) matching Profile.save_game.
## No campaign Profile access.

const LevelData := preload("res://scripts/quickplay/level_data.gd")

const DEFAULT_DIR := "user://quickplay/levels"


var root_dir := DEFAULT_DIR
var persist := true


func ensure_dir() -> Error:
	var abs := ProjectSettings.globalize_path(root_dir)
	if DirAccess.dir_exists_absolute(abs):
		return OK
	return DirAccess.make_dir_recursive_absolute(abs)


## [{ "id", "name", "author", "modified", "path" }, ...] newest modified first.
func list_levels() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if ensure_dir() != OK:
		return out
	var abs := ProjectSettings.globalize_path(root_dir)
	var dir := DirAccess.open(abs)
	if dir == null:
		return out
	dir.list_dir_begin()
	var name := dir.get_next()
	while name != "":
		if not dir.current_is_dir() and name.ends_with(".json") and not name.ends_with(".bak") and not name.ends_with(".tmp") and not name.ends_with(".broken"):
			var path := root_dir.path_join(name)
			var level := LevelData.from_json(FileAccess.get_file_as_string(path))
			if not level.is_empty():
				out.append({
					"id": str(level.id),
					"name": str(level.name),
					"author": str(level.get("author", "")),
					"modified": int(level.get("modified", 0)),
					"path": path,
				})
		name = dir.get_next()
	dir.list_dir_end()
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.modified) > int(b.modified))
	return out


func path_for(level_id: String) -> String:
	return root_dir.path_join("%s.json" % _safe_id(level_id))


func load_level(level_id: String) -> Dictionary:
	var path := path_for(level_id)
	if not FileAccess.file_exists(path) and FileAccess.file_exists(path + ".tmp"):
		_move(path + ".tmp", path)
	if not FileAccess.file_exists(path):
		var bak := _read(path + ".bak")
		return bak
	var data := _read(path)
	if data.is_empty():
		var backup := _read(path + ".bak")
		if FileAccess.file_exists(path):
			_move(path, path + ".broken")
		return backup
	return data


## Saves a sanitized level. Updates modified timestamp. Returns false on IO failure.
func save_level(level: Dictionary) -> bool:
	if not persist:
		return false
	var clean := LevelData.sanitize(level)
	if clean.is_empty() or str(clean.get("id", "")) == "":
		return false
	clean["modified"] = int(Time.get_unix_time_from_system())
	if int(clean.get("created", 0)) <= 0:
		clean["created"] = clean.modified
	if ensure_dir() != OK:
		return false
	var path := path_for(str(clean.id))
	var tmp := path + ".tmp"
	var file := FileAccess.open(tmp, FileAccess.WRITE)
	if file == null:
		push_warning("LevelStore: can't write %s (%s)" % [tmp, FileAccess.get_open_error()])
		return false
	file.store_string(JSON.stringify(clean, "\t"))
	file.close()
	if FileAccess.file_exists(path):
		_move(path, path + ".bak")
	if _move(tmp, path) != OK:
		push_warning("LevelStore: can't swap in %s" % path)
		return false
	return true


func delete_level(level_id: String) -> bool:
	if not persist:
		return false
	var path := path_for(level_id)
	var ok := true
	for ext: String in ["", ".bak", ".tmp", ".broken"]:
		var p := path if ext == "" else path + ext
		if FileAccess.file_exists(p):
			var err := DirAccess.remove_absolute(ProjectSettings.globalize_path(p))
			if err != OK:
				ok = false
	return ok


func _read(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	return LevelData.from_json(FileAccess.get_file_as_string(path))


static func _move(from: String, to: String) -> Error:
	return DirAccess.rename_absolute(ProjectSettings.globalize_path(from), ProjectSettings.globalize_path(to))


static func _safe_id(level_id: String) -> String:
	var out := ""
	for i in level_id.length():
		var ch := level_id[i]
		var code := ch.unicode_at(0)
		var ok := (code >= 97 and code <= 122) or (code >= 65 and code <= 90) or (code >= 48 and code <= 57) or ch == "_" or ch == "-"
		out += ch if ok else "_"
	if out == "":
		out = "level"
	return out
