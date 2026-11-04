extends RefCounted
## STAND-IN for P0's atlas loader (scripts/art_atlas.gd, not on main yet).
## Loads a generated atlas (PNG + JSON with "regions": name -> [x, y, w, h]).
## Returns null when the files are missing, so callers keep the code-drawn look.
## Delete this and switch to art_atlas.gd when P0 lands (the style-sample PR
## will be rebased onto it).

var texture: Texture2D
var regions := {}     # name -> Rect2


static func open(json_path: String) -> RefCounted:
	if not FileAccess.file_exists(json_path):
		return null
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(json_path))
	if not (data is Dictionary):
		return null
	var meta: Dictionary = data
	var tex_path := json_path.get_base_dir().path_join(str(meta.get("texture", "")))
	if not ResourceLoader.exists(tex_path):
		return null
	var a: RefCounted = (load("res://scripts/fx_atlas_local.gd") as GDScript).new()
	a.texture = load(tex_path)
	var regs: Dictionary = meta.get("regions", {})
	for k: String in regs:
		var r: Array = regs[k]
		a.regions[k] = Rect2(float(r[0]), float(r[1]), float(r[2]), float(r[3]))
	return a


func has(region: String) -> bool:
	return regions.has(region)


func rect(region: String) -> Rect2:
	return regions.get(region, Rect2())
