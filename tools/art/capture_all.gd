extends SceneTree
## Every-screen capture set for art review (VISUAL_PLAN P0). Needs a display:
##   xvfb-run -s "-screen 0 1280x720x24" godot --rendering-driver opengl3 --path . -s res://tools/art/capture_all.gd -- out_dir
## Writes `<shot>.png` into out_dir (default user://captures) for every step.
## Uses a throwaway profile (persist = false), so no save is touched.
##
## Shots live one per file in tools/art/captures/<NNN>_<shot>.gd (extending
## tools/art/capture_step.gd) and run in file-name order. To add a shot, add a
## file there; don't edit this script.

const UI := preload("res://scripts/ui_theme.gd")
const T := preload("res://scripts/tuning.gd")
const Step := preload("res://tools/art/capture_step.gd")
const STEP_DIR := "res://tools/art/captures"

var _dir := "user://captures"
var _steps: Array[Step] = []
var _step := -1
var _wait := 0

# Shared state the steps build on.
var profile: Node
var garage: Node
var strip: Control


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_dir = args[0]
	DirAccess.make_dir_recursive_absolute(_dir)
	profile = root.get_node("Profile")
	profile.persist = false
	profile.new_game()
	# P1: own a schematic of each rarity there is, so frames show on cards.
	for id: String in ["courier_frame", "bulwark_frame", "hauler_frame"]:
		if not profile.schematics.has(id):
			profile.schematics.append(id)
	_steps = load_steps()


## Every step file in STEP_DIR, sorted by file name, with its shot name set.
static func load_steps() -> Array[Step]:
	var files: Array[String] = []
	for f: String in DirAccess.get_files_at(STEP_DIR):
		if f.ends_with(".gd"):
			files.append(f)
	files.sort()
	var out: Array[Step] = []
	for f: String in files:
		var script: GDScript = load(STEP_DIR + "/" + f)
		var s: Step = script.new()
		var base := f.get_basename()
		var cut := base.find("_")
		s.shot = base.substr(cut + 1) if cut >= 0 and base.left(cut).is_valid_int() else base
		out.append(s)
	return out


## Shows a garage tab, building the garage on first use.
func show_tab(t: String) -> void:
	if garage == null:
		garage = (load("res://scenes/garage.tscn") as PackedScene).instantiate()
		root.add_child(garage)
	garage.show_tab(t)


## Replaces whatever is on screen (garage or the last strip) with a blank themed
## full-screen Control filled with `bg`.
func new_strip(bg_color: Color) -> Control:
	if garage != null:
		garage.queue_free()
		garage = null
	if strip != null:
		strip.queue_free()
	strip = Control.new()
	strip.theme = UI.make()
	strip.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(strip)
	var bg := ColorRect.new()
	bg.color = bg_color
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	strip.add_child(bg)
	return strip


func _process(_delta: float) -> bool:
	if _wait > 0:
		_wait -= 1
		return false
	if _step >= 0:
		var path := "%s/%s.png" % [_dir, _steps[_step].shot]
		root.get_texture().get_image().save_png(path)
		print("saved ", path)
	_step += 1
	if _step >= _steps.size():
		quit()
		return true
	_steps[_step].run(self)
	_wait = _steps[_step].wait()
	return false
