extends SceneTree
## Every-screen capture set for art review (VISUAL_PLAN P0). Needs a display:
##   xvfb-run -s "-screen 0 1280x720x24" godot --rendering-driver opengl3 --path . -s res://tools/art/capture_all.gd -- out_dir
## Writes into out_dir (default user://captures):
##   garage_<tab>.png for GARAGE, RESEARCH, SALOON, INN, COMMS
##   rarity_tiers.png  (all six rarity frames side by side)
##   fight.png         (the mission scene after a few seconds)
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
	_add("garage_part_cards", _show_part_cards)   # V6.3: part card + stat sheet icons
	_add("rarity_tiers", _show_rarity)
	_add("fight", _show_fight)
	_add("fight_status", _show_status)   # V6.3: status icons on the HUD strip


func _add(shot: String, setup: Callable) -> void:
	_names.append(shot)
	_steps.append(setup)


func _show_tab(t: String) -> void:
	if _garage == null:
		_garage = (load("res://scenes/garage.tscn") as PackedScene).instantiate()
		root.add_child(_garage)
	_garage.show_tab(t)


func _show_part_cards() -> void:
	_garage.show_tab("GARAGE")
	_garage.open_slot(7)   # a weapon slot: weapon cards and the gun rows of the stat sheet


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


func _show_fight() -> void:
	_strip.queue_free()
	change_scene_to_file("res://scenes/mission.tscn")


func _show_status() -> void:
	var m: Node = current_scene
	m.set_process(false)   # freeze the fight so the HUD keeps these values for the shot
	m.set_physics_process(false)
	m.hud.set_statuses(PackedFloat32Array([40, 100, 70, 0, 100, 25]), PackedFloat32Array([0, 3, 0, 0, 2, 0]))


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
