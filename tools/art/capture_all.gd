extends SceneTree
## Every-screen capture set for art review (VISUAL_PLAN P0). Needs a display:
##   xvfb-run -s "-screen 0 1280x720x24" godot --rendering-driver opengl3 --path . -s res://tools/art/capture_all.gd -- out_dir
## Writes into out_dir (default user://captures):
##   garage_<tab>.png for GARAGE, RESEARCH, SALOON, INN, COMMS
##   rarity_tiers.png  (all six rarity frames side by side)
##   fight.png         (the mission scene after a few seconds)
##   map_outer_blocks_before.png / _after.png (P4 style sample corner)
## Optional second arg: only shots whose name starts with it, e.g. "map_".
## Uses a throwaway profile (persist = false), so no save is touched.
## Packages add their shots as new steps in `_steps()`.

const UI := preload("res://scripts/ui_theme.gd")
const T := preload("res://scripts/tuning.gd")

const TABS := ["GARAGE", "RESEARCH", "SALOON", "INN", "COMMS"]
const SETTLE := 12   # frames to wait before each shot

var _dir := "user://captures"
var _steps: Array[Callable] = []
var _names: Array[String] = []
var _step := -1
var _wait := 0
var _garage: Node
var _strip: Control


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_dir = args[0]
	DirAccess.make_dir_recursive_absolute(_dir)
	var profile: Node = root.get_node("Profile")
	profile.persist = false
	profile.new_game()
	for t: String in TABS:
		_add("garage_" + t.to_lower(), _show_tab.bind(t))
	_add("rarity_tiers", _show_rarity)
	# --- P4 map corner (VISUAL_PLAN V5.5 style sample) ---
	_add("map_outer_blocks_before", _show_map_corner.bind(false))
	_add("map_outer_blocks_after", _show_map_corner.bind(true))
	_add("fight", _show_fight)
	if args.size() > 1:
		var keep_names: Array[String] = []
		var keep_steps: Array[Callable] = []
		for i in _names.size():
			if _names[i].begins_with(args[1]):
				keep_names.append(_names[i])
				keep_steps.append(_steps[i])
		_names = keep_names
		_steps = keep_steps


func _add(shot: String, setup: Callable) -> void:
	_names.append(shot)
	_steps.append(setup)


func _show_tab(t: String) -> void:
	if _garage == null:
		_garage = (load("res://scenes/garage.tscn") as PackedScene).instantiate()
		root.add_child(_garage)
	_garage.show_tab(t)


func _show_rarity() -> void:
	_garage.queue_free()
	_garage = null
	_strip = Control.new()
	_strip.theme = UI.make()
	_strip.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(_strip)
	var bg := ColorRect.new()
	bg.color = UI.PANEL
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_strip.add_child(bg)
	for i in T.RARITY_ORDER.size():
		var r: String = T.RARITY_ORDER[i]
		var card := Panel.new()
		card.position = Vector2(40 + i * 205, 260)
		card.size = Vector2(185, 200)
		_strip.add_child(card)
		var l := UI.label(r, 24, UI.rarity_color(r))
		l.position = Vector2(14, 40)
		card.add_child(l)
		UI.rarity_frame(card, r)


var _map: Node2D


func _show_map_corner(sample: bool) -> void:
	for n: Node in [_garage, _strip, _map]:
		if n != null and is_instance_valid(n):
			n.queue_free()
	_garage = null
	_strip = null
	var Arena := load("res://scripts/arena.gd")
	Arena.style_sample = sample
	_map = Node2D.new()
	root.add_child(_map)
	var arena: Node2D = Arena.new()
	_map.add_child(arena)
	var cam := Camera2D.new()
	cam.position = Vector2(750, 440)
	cam.zoom = Vector2(0.84, 0.84)
	_map.add_child(cam)
	cam.make_current()


func _show_fight() -> void:
	for n: Node in [_strip, _map]:
		if n != null and is_instance_valid(n):
			n.queue_free()
	load("res://scripts/arena.gd").style_sample = false
	change_scene_to_file("res://scenes/mission.tscn")


func _process(_delta: float) -> bool:
	if _wait > 0:
		_wait -= 1
		return false
	if _step >= 0:
		var path := "%s/%s.png" % [_dir, _names[_step]]
		root.get_texture().get_image().save_png(path)
		print("saved ", path)
	_step += 1
	if _step >= _steps.size():
		quit()
		return true
	_steps[_step].call()
	_wait = 150 if _names[_step] == "fight" else SETTLE
	return false
